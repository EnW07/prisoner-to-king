--!strict
-- CombatController.lua
-- Blueprint §45: the client plays its swing IMMEDIATELY for responsiveness, then sends an
-- intent. It never decides whether anything was hit — that comes back from the server.
--
-- INPUTS (E5: four in total, with dash and interact elsewhere):
--   tap / click / R2        the light attack, at once (AttackRequest)
--   hold, then release      the HEAVY attack (E2): past HeavyHoldTime the wind-up begins
--                           and is held; release plays the strike and sends HeavyRequest.
--                           The light swing still fires on the press, so tapping never
--                           waits for the hold decision.
--   touch                   a SWING button and a separate HEAVY button (press to wind,
--                           release to strike), each with a radial cooldown.
--
-- The combo (E3) is the weapon's own chain (WeaponConfig.Combo), stages within
-- GameConfig.Animation.ComboWindow of each other. The stage shown is predictive; the
-- server keeps its own count from the same rule and decides what each stage does.

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local WeaponConfig = require(Shared:WaitForChild("Config"):WaitForChild("WeaponConfig"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local AnimationConfig = require(Shared:WaitForChild("Config"):WaitForChild("AnimationConfig"))
local Anim = Shared:WaitForChild("Anim")
local Rig = require(Anim:WaitForChild("Rig"))
local PoseAnimator = require(Anim:WaitForChild("PoseAnimator"))
local PlayerAnimController = require(script.Parent:WaitForChild("PlayerAnimController"))
local ControlButton = require(script.Parent:WaitForChild("ControlButton"))

local COMBAT = GameConfig.Combat
local player = Players.LocalPlayer
local CombatController = {}

local AttackRequest: RemoteEvent
local HeavyRequest: RemoteEvent

local weapon: any = WeaponConfig.Get("fists")
local localCooldownUntil = 0
local comboStage = 0
local lastSwingAt = 0
local lastHeavyAt = -math.huge

-- The hold: when the attack input went down, and whether the heavy wind-up has begun.
local heldSince: number? = nil
local winding = false
local heavyToken = 0

local swingButton: ControlButton.Button? = nil
local heavyButton: ControlButton.Button? = nil

local function alive(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function heavyReady(now: number): boolean
	return now - lastHeavyAt >= weapon.HeavyCooldown
end

-- ── Light ───────────────────────────────────────────────────────
local function lightAttack()
	if not alive() then
		return
	end
	local now = os.clock()
	-- Local predictive cooldown only. The SERVER enforces the real one; this just avoids
	-- spamming the remote and getting rate limited.
	if now < localCooldownUntil then
		return
	end
	localCooldownUntil = now + weapon.AttackCooldown * 0.9

	-- Combo stage: continue the chain inside the window, otherwise start over.
	local chain: { string } = weapon.Combo
	if now - lastSwingAt <= GameConfig.Animation.ComboWindow then
		comboStage = comboStage % #chain + 1
	else
		comboStage = 1
	end
	lastSwingAt = now

	PlayerAnimController.Play(chain[comboStage])
	AttackRequest:FireServer()
end

-- ── Heavy ───────────────────────────────────────────────────────
-- Begin the wind-up and hold it: only the move's Wind phase plays, and the joints stay
-- there until release. (The clip path, if a Heavy clip is configured, plays whole on release.)
local function beginHeavyWind()
	if winding or not alive() or not heavyReady(os.clock()) then
		return
	end
	winding = true
	heavyToken += 1
	local character = player.Character
	local rig = character and Rig.Open(character)
	local clipId = (AnimationConfig.Player :: any).Heavy
	if rig and type(clipId) ~= "string" then
		PoseAnimator.Play(
			rig,
			AnimationConfig.Player.Procedural.Heavy,
			{ Weight = weapon.Weight, Only = { "Wind" } }
		)
	end
end

local function releaseHeavy()
	if not winding then
		return
	end
	winding = false
	local now = os.clock()
	if not alive() or not heavyReady(now) then
		PlayerAnimController.Relax()
		return
	end
	lastHeavyAt = now
	lastSwingAt = -math.huge -- a heavy ends the chain
	comboStage = 0
	localCooldownUntil =
		math.max(localCooldownUntil, now + weapon.AttackCooldown * COMBAT.HeavyAfterLightFraction)

	local character = player.Character
	local rig = character and Rig.Open(character)
	local clipId = (AnimationConfig.Player :: any).Heavy
	if type(clipId) == "string" then
		PlayerAnimController.Play("Heavy")
	elseif rig then
		PoseAnimator.Play(rig, AnimationConfig.Player.Procedural.Heavy, {
			Weight = weapon.Weight,
			Only = { "Strike", "Recover" },
		})
	end
	HeavyRequest:FireServer()
end

-- Keyboard / mouse / gamepad: press = light at once, keep holding = heavy on release.
local function onAttackInput(_name: string, state: Enum.UserInputState)
	local now = os.clock()
	if state == Enum.UserInputState.Begin then
		heldSince = now
		lightAttack()
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		heldSince = nil
		releaseHeavy()
	end
end

-- Touch: SWING taps; HEAVY presses to wind and releases to strike. A HEAVY tap shorter
-- than the hold time still strikes, after the wind-up has had its minimum.
local function buildButtons()
	local ui = GameConfig.UI
	local swing = ControlButton.Create(
		"Swing",
		"SWING",
		ui.SwingButtonSize,
		UDim2.fromScale(0.97, 0.72),
		Vector2.new(1, 1)
	)
	swing.Pressed:Connect(lightAttack)
	swingButton = swing

	local heavy = ControlButton.Create(
		"Heavy",
		"HEAVY",
		ui.HeavyButtonSize,
		UDim2.fromScale(0.97, 0.72 - ui.SwingButtonSize - ui.ControlGap),
		Vector2.new(1, 1)
	)
	local pressedAt = 0
	heavy.Pressed:Connect(function()
		pressedAt = os.clock()
		beginHeavyWind()
	end)
	heavy.Released:Connect(function()
		local remaining = COMBAT.HeavyHoldTime - (os.clock() - pressedAt)
		if remaining > 0 then
			local token = heavyToken
			task.delay(remaining, function()
				if token == heavyToken then
					releaseHeavy()
				end
			end)
		else
			releaseHeavy()
		end
	end)
	heavyButton = heavy
end

function CombatController.Init()
	AttackRequest = Net.Event("AttackRequest")
	HeavyRequest = Net.Event("HeavyRequest")

	-- false: no stock CAS touch button; touch uses the styled buttons instead.
	ContextActionService:BindAction(
		"PTK_Attack",
		onAttackInput,
		false,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2
	)
	if UserInputService.TouchEnabled then
		buildButtons()
	end

	-- Keep the local weapon in sync with the equipped one.
	Net.Event("StateUpdate").OnClientEvent:Connect(function(state)
		local w = state.WeaponId and WeaponConfig.Get(state.WeaponId)
		if w then
			weapon = w
		end
	end)

	-- Per frame: the held input past HeavyHoldTime begins the wind-up; the buttons' radial
	-- cooldowns redraw only when they change meaningfully.
	local shownSwing, shownHeavy = -1, -1
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		if heldSince and not winding and now - heldSince >= COMBAT.HeavyHoldTime then
			beginHeavyWind()
		end
		if swingButton then
			local remaining = math.max(0, localCooldownUntil - now)
			if math.abs(remaining - shownSwing) > 0.01 or (remaining == 0 and shownSwing ~= 0) then
				shownSwing = remaining
				swingButton.SetCooldown(remaining, weapon.AttackCooldown * 0.9)
			end
		end
		if heavyButton then
			local remaining = math.max(0, weapon.HeavyCooldown - (now - lastHeavyAt))
			if math.abs(remaining - shownHeavy) > 0.01 or (remaining == 0 and shownHeavy ~= 0) then
				shownHeavy = remaining
				heavyButton.SetCooldown(remaining, weapon.HeavyCooldown)
			end
		end
	end)
end

return CombatController
