--!strict
-- PromptController.lua
-- Per-player ProximityPrompt visibility.
--
-- WHY THIS EXISTS: ProximityPrompt.Enabled (and ObjectText) are REPLICATED — a value the
-- server sets is global to every player. The game's objectives are per-player, so the server
-- must not toggle those properties (doing so caused M1 bugs 1, 2, 4 and 5). Instead every
-- gated prompt carries a `PTKGate` attribute, and this controller drives Enabled/ObjectText
-- locally from the authoritative StateUpdate snapshot.
--
-- SECURITY: hiding a prompt locally changes nothing on the server. Every Triggered handler
-- still re-validates distance and run state, so a client that force-enables a prompt gains
-- nothing. (§103 "server decides, client asks".)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))

local PromptController = {}

local interactables: Instance

-- Re-gathered per update: there are only a handful of prompts, and this is robust to parts
-- streaming in after the first StateUpdate.
local function gatherPrompts(): { ProximityPrompt }
	local out = {}
	if not interactables then
		return out
	end
	for _, inst in interactables:GetDescendants() do
		if inst:IsA("ProximityPrompt") and inst:GetAttribute("PTKGate") ~= nil then
			table.insert(out, inst)
		end
	end
	return out
end

function PromptController.OnState(state)
	local safe = (state.RunState or "Safe") == "Safe"
	local maxed = (state.WeaponUpgradeLevel or 0) >= GameConfig.Economy.WeaponUpgradeMaxLevel

	for _, prompt in gatherPrompts() do
		local gate = prompt:GetAttribute("PTKGate")

		if gate == "chains" then
			prompt.Enabled = not state.ChainsBroken
		elseif gate == "weapon" then
			prompt.Enabled = state.ChainsBroken == true and not state.HasWeapon
		elseif gate == "door" then
			-- The prompt shows only while you hold the key and haven't opened it yet this run.
			prompt.Enabled = state.HasKey == true and not state.DoorOpened
			-- The door part is shared/replicated, so its physical state is driven per-player
			-- HERE, locally: CanCollide set on the client only affects this client's own
			-- character physics (network ownership), so the door is solid for a player who
			-- hasn't unlocked it this run and passable for one who has. The server never
			-- touches these, so the local values hold.
			local door = prompt.Parent
			if door and door:IsA("BasePart") then
				door.CanCollide = not state.DoorOpened
				door.Transparency = if state.DoorOpened then 0.75 else 0
			end
		elseif gate == "chest" then
			prompt.Enabled = not state.ChestOpened
		elseif gate == "barrackschest" then
			prompt.Enabled = not state.BarracksChestOpened
		elseif gate == "posternkey" then
			prompt.Enabled = not state.HasPosternKey
			local key = prompt.Parent
			if key and key:IsA("BasePart") then
				key.Transparency = if state.HasPosternKey then 1 else 0 -- taken: gone, for you
			end
		elseif gate == "postern" then
			-- Same per-player trick as the cellblock door: the gate is shared, its state is yours.
			prompt.Enabled = state.HasPosternKey == true and not state.PosternOpened
			local gatePart = prompt.Parent
			if gatePart and gatePart:IsA("BasePart") then
				gatePart.CanCollide = not state.PosternOpened
				gatePart.Transparency = if state.PosternOpened then 0.75 else 0
			end
		elseif gate == "bar" then
			prompt.Enabled = not safe
		elseif gate == "always" then
			prompt.Enabled = true
		elseif gate == "extract" then
			prompt.Enabled = not safe
		elseif gate == "reenter" then
			prompt.Enabled = safe
		elseif gate == "upgrade" then
			-- The one prompt whose LABEL is also per-player: it shows the live next-level cost.
			if maxed then
				prompt.ObjectText = "WEAPONS FULLY UPGRADED"
				prompt.Enabled = false
			else
				prompt.ObjectText = ("UPGRADE YOUR WEAPONS — %d Gold"):format(state.UpgradeCost or 0)
				prompt.Enabled = safe
			end
		end
	end
end

function PromptController.Init()
	local world = workspace:WaitForChild("World")
	interactables = world:WaitForChild("Interactables")
	Net.Event("StateUpdate").OnClientEvent:Connect(PromptController.OnState)
end

return PromptController
