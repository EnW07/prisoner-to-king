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
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local WeaponConfig = require(Shared:WaitForChild("Config"):WaitForChild("WeaponConfig"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local PlayerAnimController = require(script.Parent:WaitForChild("PlayerAnimController"))
local ControlButton = require(script.Parent:WaitForChild("ControlButton"))

local player = Players.LocalPlayer
local CombatController = {}

local AttackRequest: RemoteEvent
local localCooldownUntil = 0
local currentCooldown = 0.65
local comboStage = 0
local lastSwingAt = 0
local swingButton: ControlButton.Button? = nil

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

-- Bottom right, above Roblox's own jump button, with its cooldown as a radial fill.
-- Labelled SWING: art §7 lists "Attack" under "never", and RAID means raiding a castle.
local function buildSwingButton()
	local ui = GameConfig.UI
	local b = ControlButton.Create(
		"Swing",
		"SWING",
		ui.SwingButtonSize,
		UDim2.fromScale(0.97, 0.72),
		Vector2.new(1, 1)
	)
	b.Pressed:Connect(function()
		onAttack("PTK_Attack", Enum.UserInputState.Begin)
	end)
	swingButton = b

	local shown = -1
	RunService.RenderStepped:Connect(function()
		local remaining = math.max(0, localCooldownUntil - os.clock())
		if math.abs(remaining - shown) > 0.01 or (remaining == 0 and shown ~= 0) then
			shown = remaining
			b.SetCooldown(remaining, currentCooldown * 0.9)
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
