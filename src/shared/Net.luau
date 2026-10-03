--!strict
-- Net.lua
-- Single source of truth for remotes. The SERVER creates them; the client only waits.
-- Keeping the list here means no manual RemoteEvent objects need to exist in Studio.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IS_SERVER = RunService:IsServer()

local EVENTS = {
	-- Client → Server (intents only; the server never trusts a value from these)
	"AttackRequest",
	"EquipRequest", -- a weapon id; the server equips it only if the profile owns it
	"RespawnRequest", -- TRY AGAIN, zero arguments; the server respawns only a dead player

	-- Server → Client
	"StateUpdate", -- gold, unsecured, weapon, objective, run state
	"Notify", -- toast / banner messages
	"HitConfirm", -- feedback: position, damage, killed
	"ScreenEvent", -- ESCAPED / CAPTURED full-screen moments
	"CombatVisual", -- another player's validated swing, so every client can play it
}

local Net = {}

local folder: Folder
if IS_SERVER then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local ev = Instance.new("RemoteEvent")
			ev.Name = name
			ev.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes", 30) :: Folder
end

function Net.Event(name: string): RemoteEvent
	assert(folder, "Remotes folder missing — is the server Bootstrap running?")
	local ev = folder:WaitForChild(name, 20)
	assert(ev and ev:IsA("RemoteEvent"), "Unknown remote: " .. name)
	return ev :: RemoteEvent
end

return Net
