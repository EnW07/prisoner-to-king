--!strict
-- DeathService.lua
-- The player's death and respawn, server side. One responsibility: what happens to the
-- BODY when a player dies, and when a new one arrives. (MASTER_BUILD_SPEC Section D;
-- blueprint §66: tension, a lesson, a quick retry.)
--
-- RunStateService still owns what death MEANS (gold lost, analytics, the CAPTURED
-- payload). This service owns:
--   • joints that don't scatter: BreakJointsOnDeath is off for every character; after the
--     impact hold the body becomes a clean ragdoll (shared Ragdoll module, which the
--     client's own physics simulates since it owns the character)
--   • respawning: Roblox's automatic respawn is off. The client's TRY AGAIN sends
--     RespawnRequest (zero arguments, rate limited) and the server loads a fresh character
--     at once; if the player does nothing, it happens anyway after AutoRespawnDelay.
--   • the first spawn waits for the profile, so a character can never arrive before the
--     run that goes with it (that race left a character with no run and no chains).
-- A fresh character is a full state reset by construction: every per-character thing
-- lives on the old model (constraints, welds, poses) and dies with it.

local Players = game:GetService("Players")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(game.ReplicatedStorage.Shared.Net)
local Ragdoll = require(game.ReplicatedStorage.Shared.Anim.Ragdoll)
local RateLimiter = require(script.Parent.RateLimiter)

local DeathService = {}
local ctx
local DEATH = GameConfig.Death

local RespawnRequest: RemoteEvent
-- A token per player for the automatic respawn timer; bumping it cancels the timer.
local respawnTokens: { [number]: number } = {}
local loading: { [number]: boolean } = {}

local function bump(player: Player): number
	local token = (respawnTokens[player.UserId] or 0) + 1
	respawnTokens[player.UserId] = token
	return token
end

local function loadCharacter(player: Player)
	if loading[player.UserId] or not player.Parent then
		return
	end
	loading[player.UserId] = true
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	loading[player.UserId] = nil
	if not ok then
		warn(("[Death] Could not load a character for %s: %s"):format(player.Name, tostring(err)))
	end
end

-- Respawn now, if the player is actually dead. Alive players are ignored: the remote is
-- not a teleport-home button.
function DeathService.Respawn(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return
	end
	bump(player)
	loadCharacter(player)
end

local function onDied(player: Player, character: Model)
	-- The impact hold: the client freezes for the same DEATH.HitStop, then the body goes.
	task.delay(DEATH.HitStop, function()
		if not character.Parent then
			return
		end
		local ok, result = pcall(Ragdoll.Apply, character)
		if not ok or not result then
			warn(
				("[Death] Ragdoll failed for %s; leaving the body rigid: %s"):format(
					player.Name,
					tostring(result)
				)
			)
		end
	end)

	local token = bump(player)
	task.delay(DEATH.AutoRespawnDelay, function()
		if respawnTokens[player.UserId] == token and player.Parent then
			DeathService.Respawn(player)
		end
	end)
end

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	-- Roblox's default scatters the limbs on death. Never.
	humanoid.BreakJointsOnDeath = false
	humanoid.Died:Connect(function()
		onDied(player, character)
	end)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
	-- First spawn, after the profile. CharacterAutoLoads is off, so this is the only way
	-- a first character appears.
	task.spawn(function()
		ctx.Data.WaitForProfile(player, DEATH.ProfileWaitTimeout)
		if player.Parent and not player.Character then
			loadCharacter(player)
		end
	end)
end

function DeathService.Init(context)
	ctx = context
	Players.CharacterAutoLoads = false
	RespawnRequest = Net.Event("RespawnRequest")

	RespawnRequest.OnServerEvent:Connect(function(player)
		if not RateLimiter.Check(player, "Respawn", DEATH.MaxRespawnRate) then
			return
		end
		DeathService.Respawn(player)
	end)

	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		respawnTokens[player.UserId] = nil
		loading[player.UserId] = nil
	end)
end

return DeathService
