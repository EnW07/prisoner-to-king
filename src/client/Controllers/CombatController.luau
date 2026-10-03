--!strict
-- CombatController.lua
-- Blueprint §45: the client plays its swing IMMEDIATELY for responsiveness, then sends an
-- intent. It never decides whether anything was hit — that comes back from the server.
--
-- Mouse and gamepad go through ContextActionService. Touch gets a large UIStyle SWING
-- button (over half of Roblox play is mobile), not the stock CAS touch button.

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local WeaponConfig = require(Shared:WaitForChild("Config"):WaitForChild("WeaponConfig"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local HitStop = require(script.Parent:WaitForChild("HitStop"))
local AnimationConfig = require(Shared:WaitForChild("Config"):WaitForChild("AnimationConfig"))
local ArmPose = require(Shared:WaitForChild("ArmPose"))

local player = Players.LocalPlayer
local CombatController = {}

local AttackRequest: RemoteEvent
local localCooldownUntil = 0
local currentCooldown = 0.65

-- ── Procedural swing (playtest 5, item 2) ──
-- Four phases through the real right shoulder: wind-up, strike, follow-through, recover.
-- The ARM swings, carrying the weapon in the hand. Nothing rotates the weapon on its own.
-- ArmPose finds the joint on R15 or R6, in Motor6D or AnimationConstraint form. The old
-- version only knew the R15 Motor6D, and otherwise fell back to a wrist snap on the
-- weapon: "the weapon moves and the arm doesn't". Local and cosmetic: the server never
-- reads it.
local arms: { [Instance]: ArmPose.Joint | false } = setmetatable({}, { __mode = "k" }) :: any
local swingToken = 0

-- The character's shoulder, found once per character so its rest pose is the real rest.
local function armFor(character: Model): ArmPose.Joint?
	local cached = arms[character]
	if cached == nil then
		local found = ArmPose.Find(character)
		if not found then
			warn("[CombatController] No right shoulder joint on this character; the swing can't move the arm")
		end
		arms[character] = found or false
		return found
	end
	return cached or nil
end

-- Plays poses one after another. A newer swing (new token) or a cancelled tween stops the
-- chain; hit-stop pauses it (HitStop.Track) and it resumes in place.
local function chain(arm: ArmPose.Joint, steps: { { any } }, token: number)
	local i = 0
	local function nextStep()
		i += 1
		if token ~= swingToken or i > #steps or not arm.Target.Parent then
			return
		end
		local step = steps[i]
		local t =
			ArmPose.TweenTo(arm, ArmPose.Rotation(arm.Rig, step[1]), TweenInfo.new(step[2], step[3], step[4]))
		HitStop.Track(t)
		t.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				nextStep()
			end
		end)
	end
	nextStep()
end

-- A configured swing clip (AnimationConfig.Player.Swing), loaded once per Animator.
-- Weak keys, so a dead character's Animator and track are collected.
local swingTracks: { [Instance]: AnimationTrack | false } = setmetatable({}, { __mode = "k" }) :: any

local function clipSwing(character: Model): boolean
	local id = AnimationConfig.Player.Swing
	if not id then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end
	local cached = swingTracks[animator]
	if cached == nil then
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, result = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if ok and result then
			result.Priority = Enum.AnimationPriority.Action
			cached = result
		else
			warn(
				"[CombatController] Swing clip failed to load; using the procedural swing: "
					.. tostring(result)
			)
			cached = false
		end
		swingTracks[animator] = cached
	end
	if cached then
		-- No HitStop.Track: HitStop already freezes every playing track on this Animator.
		cached:Play(0.05)
		return true
	end
	return false
end

local function playSwing()
	local character = player.Character
	if not character then
		return
	end
	swingToken += 1
	local token = swingToken

	-- An acquired swing animation replaces the procedural one with no other change.
	if clipSwing(character) then
		return
	end

	local arm = armFor(character)
	if not arm then
		return
	end
	local feel = GameConfig.Feel
	local Q = Enum.EasingStyle.Quad
	local Chop = ArmPose.Chop
	chain(arm, {
		{ Chop.WindUp, feel.SwingWindUp, Q, Enum.EasingDirection.Out },
		{ Chop.Strike, feel.SwingStrike, Q, Enum.EasingDirection.In },
		{ Chop.FollowThrough, feel.SwingFollowThrough, Q, Enum.EasingDirection.Out },
		{ Chop.Rest, feel.SwingRecover, Q, Enum.EasingDirection.InOut },
	}, token)
end

local function onAttack(_actionName: string, inputState: Enum.UserInputState)
	if inputState ~= Enum.UserInputState.Begin then
		return
	end

	local now = os.clock()
	-- Local predictive cooldown only. The SERVER enforces the real one; this just avoids
	-- spamming the remote and getting rate limited.
	if now < localCooldownUntil then
		return
	end
	localCooldownUntil = now + currentCooldown * 0.9

	playSwing()
	AttackRequest:FireServer()
end

-- Bottom right, above Roblox's own jump button. Rounded-square per the style line.
-- Labelled SWING: art §7 lists "Attack" under "never", and RAID means raiding a castle.
local function buildSwingButton()
	local ui = GameConfig.UI
	local gui = Instance.new("ScreenGui")
	gui.Name = "PTK_Controls"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel, content = UIStyle.Panel(
		"Frame",
		"Swing",
		gui,
		UDim2.fromScale(ui.SwingButtonSize, ui.SwingButtonSize),
		UDim2.fromScale(0.97, 0.72),
		Vector2.new(1, 1)
	)
	UIStyle.Aspect(panel, 1)
	local floor = Instance.new("UISizeConstraint")
	floor.MinSize = Vector2.new(UIStyle.MIN_TOUCH_PX, UIStyle.MIN_TOUCH_PX)
	floor.Parent = panel
	UIStyle.Text("Label", content, "SWING", UDim2.fromScale(1, 1), nil, 30)

	local scale = Instance.new("UIScale")
	scale.Parent = panel

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 4
	hit.Parent = panel

	local press = TweenInfo.new(ui.PopTime / 2)
	hit.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			TweenService:Create(scale, press, { Scale = ui.PressScale }):Play()
			onAttack("PTK_Attack", Enum.UserInputState.Begin)
		end
	end)
	hit.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			TweenService:Create(scale, TweenInfo.new(ui.PopTime, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end)
end

function CombatController.Init()
	AttackRequest = Net.Event("AttackRequest")

	-- false: no stock CAS touch button; touch uses the styled SWING button instead.
	ContextActionService:BindAction(
		"PTK_Attack",
		onAttack,
		false,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2
	)
	if UserInputService.TouchEnabled then
		buildSwingButton()
	end

	-- Keep the local cooldown in sync with the equipped weapon.
	Net.Event("StateUpdate").OnClientEvent:Connect(function(state)
		for _, weapon in WeaponConfig do
			if type(weapon) == "table" and weapon.Name == state.Weapon then
				currentCooldown = weapon.AttackCooldown
				break
			end
		end
	end)
end

return CombatController
