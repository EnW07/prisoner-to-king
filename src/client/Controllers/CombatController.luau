--!strict
-- CombatController.lua
-- Blueprint §45: the client plays its swing IMMEDIATELY for responsiveness, then sends an
-- intent. It never decides whether anything was hit — that comes back from the server.
--
-- Mouse and gamepad go through ContextActionService. Touch gets a large UIStyle SWING
-- button (over half of Roblox play is mobile), not the stock CAS touch button.
--
-- The swing itself is a PoseAnimator move on the character's real joints (or a clip, if
-- AnimationConfig.Player names one), played by PlayerAnimController. Three stages chain
-- when swings come within GameConfig.Animation.ComboWindow of each other: a chop, a
-- backhand, then the two-handed finisher. The stage shown here is predictive; the server
-- keeps its own count from the same rule and decides what each stage does (E3).

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
local PlayerAnimController = require(script.Parent:WaitForChild("PlayerAnimController"))

local player = Players.LocalPlayer
local CombatController = {}

local AttackRequest: RemoteEvent
local localCooldownUntil = 0
local currentCooldown = 0.65
local comboStage = 0
local lastSwingAt = 0

local function onAttack(_actionName: string, inputState: Enum.UserInputState)
	if inputState ~= Enum.UserInputState.Begin then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	-- Local predictive cooldown only. The SERVER enforces the real one; this just avoids
	-- spamming the remote and getting rate limited.
	if now < localCooldownUntil then
		return
	end
	localCooldownUntil = now + currentCooldown * 0.9

	-- Combo stage: continue the chain inside the window, otherwise start over.
	if now - lastSwingAt <= GameConfig.Animation.ComboWindow then
		comboStage = comboStage % 3 + 1
	else
		comboStage = 1
	end
	lastSwingAt = now

	PlayerAnimController.Play("Light" .. comboStage)
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
		local weapon = state.WeaponId and WeaponConfig.Get(state.WeaponId)
		if weapon then
			currentCooldown = weapon.AttackCooldown
		end
	end)
end

return CombatController
