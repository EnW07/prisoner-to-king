--!strict
-- DashController.lua
-- The dash (E1): a short directional burst with invincibility at the start. The single
-- addition that turns the attack cycle into a fight: with it, every enemy windup is a
-- decision instead of a delay.
--
-- Division of authority (CLAUDE.md rules 1-3): the client bursts IMMEDIATELY on input for
-- responsiveness, like the swing, and sends DashRequest with no arguments. The server
-- validates the cooldown from its own clock and owns the invincibility window, which is
-- the only part that affects outcomes: enemy hits are tested server-side against the
-- server's copy of the character. A client that moved itself without permission gains
-- nothing it couldn't get by walking.
--
-- Direction: the current movement input, else facing. Movement: a LinearVelocity on the
-- root for Dash.Duration, so walls and doors still stop you (a CFrame slide would phase
-- through the locked door). Feedback: afterimages, a FOV punch, the Dash lean, a sound
-- hook, and a radial cooldown on the touch button.

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local PlayerAnimController = require(script.Parent:WaitForChild("PlayerAnimController"))
local FeedbackController = require(script.Parent:WaitForChild("FeedbackController"))
local ControlButton = require(script.Parent:WaitForChild("ControlButton"))

local DASH = GameConfig.Dash
local UI = GameConfig.UI
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local DashController = {}

local DashRequest: RemoteEvent
local lastDashAt = -math.huge
local button: ControlButton.Button? = nil
local baseFov: number? = nil
local fovTween: Tween? = nil

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function living(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return character, humanoid, root
	end
	return nil, nil, nil
end

-- The burst. Rule 8: LinearVelocity (Attachment0, VectorVelocity, MaxForce, RelativeTo)
-- is the current constraint API; wrapped so a surprise degrades to a plain velocity set.
local function burst(root: BasePart, direction: Vector3)
	local speed = DASH.Distance / DASH.Duration
	local ok = pcall(function()
		local attachment = root:FindFirstChild("RootAttachment")
		if not attachment or not attachment:IsA("Attachment") then
			local a = Instance.new("Attachment")
			a.Name = "PTK_DashAttachment"
			a.Parent = root
			attachment = a
		end
		local lv = Instance.new("LinearVelocity")
		lv.Name = "PTK_Dash"
		lv.Attachment0 = attachment :: Attachment
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.MaxForce = math.huge
		lv.VectorVelocity = direction * speed -- Y is 0: the burst is flat (skims stairs briefly)
		lv.Parent = root
		Debris:AddItem(lv, DASH.Duration)
	end)
	if not ok then
		root.AssemblyLinearVelocity = direction * speed
	end
end

-- Afterimages: a few snapshots of the limbs that fade, so the dash leaves a trail.
local function afterimage(character: Model)
	local ghost = Instance.new("Folder")
	ghost.Name = "PTK_Afterimage"
	ghost.Parent = workspace
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 1 then
			local copy = part:Clone()
			for _, child in copy:GetChildren() do
				if not (child:IsA("DataModelMesh") or child:IsA("SpecialMesh")) then
					child:Destroy() -- keep the shape; joints, guis, scripts mean nothing here
				end
			end
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanQuery = false
			copy.CanTouch = false
			copy.Massless = true
			copy.Material = Enum.Material.Neon
			copy.Color = copy.Color:Lerp(Color3.new(1, 1, 1), 0.6)
			copy.Transparency = 0.55
			copy.CastShadow = false
			copy.Parent = ghost
			TweenService
				:Create(copy, TweenInfo.new(DASH.AfterimageLife, Enum.EasingStyle.Quad), { Transparency = 1 })
				:Play()
		end
	end
	Debris:AddItem(ghost, DASH.AfterimageLife + 0.1)
end

-- A quick FOV punch out and settle. Skipped while the death camera owns the camera.
local function fovPunch()
	if camera.CameraType == Enum.CameraType.Scriptable then
		return
	end
	if fovTween then
		fovTween:Cancel()
	end
	if not baseFov then
		baseFov = camera.FieldOfView
	end
	local base = baseFov :: number
	camera.FieldOfView = base + DASH.FovPunch
	fovTween = TweenService:Create(
		camera,
		TweenInfo.new(DASH.FovTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = base }
	)
	fovTween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			fovTween = nil
		end
	end)
	fovTween:Play()
end

function DashController.Dash()
	local character, humanoid, root = living()
	if not character or not humanoid or not root then
		return
	end
	local now = os.clock()
	if now - lastDashAt < DASH.Cooldown then
		return
	end
	lastDashAt = now

	local direction = flat(humanoid.MoveDirection)
	if direction.Magnitude < 0.1 then
		direction = flat(root.CFrame.LookVector)
	end
	if direction.Magnitude < 0.05 then
		direction = Vector3.new(0, 0, -1)
	end
	direction = direction.Unit

	burst(root, direction)
	PlayerAnimController.Play("Dash")
	FeedbackController.PlaySound("dash", 0.7)
	fovPunch()
	for i = 1, DASH.AfterimageCount do
		task.delay((i - 1) * DASH.Duration / DASH.AfterimageCount, function()
			if character.Parent then
				afterimage(character)
			end
		end)
	end
	DashRequest:FireServer()
end

local function onDashInput(_name: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		DashController.Dash()
	end
end

function DashController.Init()
	DashRequest = Net.Event("DashRequest")

	ContextActionService:BindAction(
		"PTK_Dash",
		onDashInput,
		false,
		Enum.KeyCode.Q,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.ButtonB
	)

	if UserInputService.TouchEnabled then
		-- Left of SWING in the bottom-right cluster (§38), with its radial cooldown.
		local b = ControlButton.Create(
			"Dash",
			"DASH",
			UI.DashButtonSize,
			UDim2.fromScale(0.97 - UI.SwingButtonSize - UI.ControlGap, 0.72),
			Vector2.new(1, 1)
		)
		b.Pressed:Connect(DashController.Dash)
		button = b
	end

	-- The cooldown fill. Cheap: one subtraction per frame, and SetCooldown only redraws
	-- when the value changes meaningfully.
	local shown = -1
	RunService.RenderStepped:Connect(function()
		local b = button
		if not b then
			return
		end
		local remaining = math.max(0, DASH.Cooldown - (os.clock() - lastDashAt))
		if math.abs(remaining - shown) > 0.01 or (remaining == 0 and shown ~= 0) then
			shown = remaining
			b.SetCooldown(remaining, DASH.Cooldown)
		end
	end)
end

return DashController
