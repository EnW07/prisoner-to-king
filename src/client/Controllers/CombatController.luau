--!strict
-- CombatController.lua
-- Blueprint §45: the client plays its swing IMMEDIATELY for responsiveness, then sends an
-- intent. It never decides whether anything was hit — that comes back from the server.
--
-- ContextActionService with CreateTouchButton gives mobile a real attack button for free.

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local WeaponConfig = require(Shared:WaitForChild("Config"):WaitForChild("WeaponConfig"))

local player = Players.LocalPlayer
local CombatController = {}

local AttackRequest: RemoteEvent
local localCooldownUntil = 0
local currentCooldown = 0.65

local function playSwing()
	local character = player.Character
	if not character then return end
	local weapon = character:FindFirstChild("EquippedWeapon")
	if not weapon or not weapon:IsA("BasePart") then return end

	-- Cheap but readable graybox swing: rotate the weld offset.
	local original = weapon.CFrame
	TweenService:Create(weapon, TweenInfo.new(0.08), { CFrame = original * CFrame.Angles(math.rad(-70), 0, 0) }):Play()
end

local function onAttack(_actionName: string, inputState: Enum.UserInputState)
	if inputState ~= Enum.UserInputState.Begin then return end

	local now = os.clock()
	-- Local predictive cooldown only. The SERVER enforces the real one; this just avoids
	-- spamming the remote and getting rate limited.
	if now < localCooldownUntil then return end
	localCooldownUntil = now + currentCooldown * 0.9

	playSwing()
	AttackRequest:FireServer()
end

function CombatController.Init()
	AttackRequest = Net.Event("AttackRequest")

	ContextActionService:BindAction("PTK_Attack", onAttack, true,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2)

	ContextActionService:SetTitle("PTK_Attack", "ATTACK")
	ContextActionService:SetPosition("PTK_Attack", UDim2.new(1, -160, 1, -180))

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
