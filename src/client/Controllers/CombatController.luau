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

local player = Players.LocalPlayer
local CombatController = {}

local AttackRequest: RemoteEvent
local localCooldownUntil = 0
local currentCooldown = 0.65

-- ── Procedural swing (VISUAL_OVERHAUL_PLAN Phase 2, item 7) ──
-- Four phases tweened on the shoulder joint: wind-up, strike, follow-through, recover. No
-- imported animation. R15 swings the whole arm through RightShoulder.C0, which composes with
-- whatever the Animator is playing. Other rigs (R6) get a wrist snap on the weapon's Grip
-- weld instead. Local and cosmetic: other players don't see it, and the server never reads it.
--
-- Rotations relative to the rest pose. Positive X raises the arm forward and up.
local ARM = {
	WindUp = CFrame.Angles(math.rad(150), 0, math.rad(-25)), -- up and back over the shoulder
	Strike = CFrame.Angles(math.rad(25), 0, math.rad(20)), -- down and across in front
	FollowThrough = CFrame.Angles(math.rad(-25), 0, math.rad(30)), -- carried on past
}
local WRIST = {
	WindUp = CFrame.Angles(math.rad(70), 0, 0),
	Strike = CFrame.Angles(math.rad(-80), 0, 0),
	FollowThrough = CFrame.Angles(math.rad(-110), 0, 0),
}
local restC0: { [Instance]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local swingToken = 0

-- Plays a list of C0 targets one after another. A newer swing (new token) or a cancelled
-- tween stops the chain; hit-stop pauses it (HitStop.Track) and it resumes in place.
local function chain(joint: Instance, steps: { { any } }, token: number)
	local i = 0
	local function nextStep()
		i += 1
		if token ~= swingToken or i > #steps or not joint.Parent then
			return
		end
		local step = steps[i]
		local t = TweenService:Create(joint, TweenInfo.new(step[2], step[3], step[4]), { C0 = step[1] })
		HitStop.Track(t)
		t.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				nextStep()
			end
		end)
		t:Play()
	end
	nextStep()
end

local function swingJoint(joint: Instance, poses, token: number)
	local rest = restC0[joint] or (joint :: any).C0
	restC0[joint] = rest
	local feel = GameConfig.Feel
	local Quad = Enum.EasingStyle.Quad
	chain(joint, {
		{ rest * poses.WindUp, feel.SwingWindUp, Quad, Enum.EasingDirection.Out },
		{ rest * poses.Strike, feel.SwingStrike, Quad, Enum.EasingDirection.In },
		{ rest * poses.FollowThrough, feel.SwingFollowThrough, Quad, Enum.EasingDirection.Out },
		{ rest, feel.SwingRecover, Quad, Enum.EasingDirection.InOut },
	}, token)
end

local function playSwing()
	local character = player.Character
	if not character then
		return
	end
	swingToken += 1
	local token = swingToken

	local upperArm = character:FindFirstChild("RightUpperArm")
	local shoulder = upperArm and upperArm:FindFirstChild("RightShoulder")
	if shoulder and shoulder:IsA("Motor6D") then
		swingJoint(shoulder, ARM, token)
		return
	end

	local weapon = character:FindFirstChild("EquippedWeapon")
	local grip = weapon and weapon:FindFirstChild("Grip")
	if grip and grip:IsA("Weld") then
		swingJoint(grip, WRIST, token)
	end
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
