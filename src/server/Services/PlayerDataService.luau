--!strict
-- PlayerDataService.lua
-- Blueprint §43 / §76. Profiles are server-owned. The client is only ever SENT a view of them.
--
-- Studio note: DataStores require "Studio Access to API Services" (Game Settings → Security).
-- If it's off, this falls back to an in-memory profile so the loop is still testable.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)

local PlayerDataService = {}
local ctx

local store: DataStore? = nil
local profiles: { [number]: any } = {}
local dataStoreAvailable = true

local function newProfile()
	return {
		Version = GameConfig.Data.SchemaVersion,

		Currencies = { Gold = 0, Crowns = 0 },

		Progression = { Rank = 1, XP = 0, CurrentKingdom = "Dungeon" },

		Inventory = { Weapons = { "fists" } },
		Equipped = { WeaponId = "fists" },

		Castle = { WeaponRackLevel = 0 },

		Meta = {
			FirstJoinUnix = os.time(),
			LastJoinUnix = os.time(),
			TutorialComplete = false,
			TotalEscapes = 0,
			TotalDeaths = 0,
			TotalRuns = 0,
		},
	}
end

-- §43: never assume the first schema is forever. Migrations run oldest → newest.
local function migrate(profile)
	if type(profile) ~= "table" or type(profile.Version) ~= "number" then
		return newProfile()
	end
	-- while profile.Version == 1 do ... profile.Version = 2 end   ← add future steps here
	if profile.Version > GameConfig.Data.SchemaVersion then
		warn("[PlayerData] Profile from a NEWER schema; refusing to downgrade. Using read-only copy.")
	end
	-- Defensive fill for fields added without a version bump during development.
	local base = newProfile()
	for k, v in base do
		if profile[k] == nil then
			profile[k] = v
		end
	end
	return profile
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

function PlayerDataService.Init(context)
	ctx = context

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.Data.StoreName)
	end)
	if ok then
		store = result
	else
		dataStoreAvailable = false
		warn("[PlayerData] DataStore unavailable — running in-memory only. " .. tostring(result))
	end

	Players.PlayerAdded:Connect(function(player)
		PlayerDataService.Load(player)
	end)
	-- Players already present when the server script starts (Studio) get loaded too.
	for _, player in Players:GetPlayers() do
		if not profiles[player.UserId] then
			task.spawn(PlayerDataService.Load, player)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		PlayerDataService.Save(player, true)
		profiles[player.UserId] = nil
	end)

	-- Autosave loop
	task.spawn(function()
		while true do
			task.wait(GameConfig.Data.AutosaveInterval)
			for _, player in Players:GetPlayers() do
				PlayerDataService.Save(player, false)
			end
		end
	end)

	-- Best-effort flush on server shutdown.
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			PlayerDataService.Save(player, true)
		end
		if RunService:IsStudio() then
			task.wait(1)
		else
			task.wait(3)
		end
	end)
end

function PlayerDataService.Load(player: Player)
	local profile
	if store and dataStoreAvailable then
		local ok, data = pcall(function()
			return (store :: DataStore):GetAsync(key(player))
		end)
		if ok then
			profile = data and migrate(data) or newProfile()
		else
			warn(
				"[PlayerData] Load failed for "
					.. player.Name
					.. " — using a temporary profile. Saves are disabled for this session."
			)
			profile = newProfile()
			profile.__noSave = true -- never overwrite real data with a fallback profile
		end
	else
		profile = newProfile()
		profile.__noSave = true
	end

	profile.Meta.LastJoinUnix = os.time()
	profiles[player.UserId] = profile
	return profile
end

function PlayerDataService.Get(player: Player)
	return profiles[player.UserId]
end

-- Yields until the player's profile is loaded, they leave, or `timeout` seconds pass.
-- Returns the profile or nil. DeathService waits on this before the first spawn.
function PlayerDataService.WaitForProfile(player: Player, timeout: number)
	local deadline = os.clock() + timeout
	while not profiles[player.UserId] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	return profiles[player.UserId]
end

-- Mutate through this so every write is centralised and easy to log later.
function PlayerDataService.Update(player: Player, fn: (any) -> ())
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	fn(profile)
	if ctx.Economy then
		ctx.Economy.PushState(player)
	end
end

function PlayerDataService.Save(player: Player, immediate: boolean)
	local profile = profiles[player.UserId]
	if not profile or profile.__noSave or not store then
		return
	end

	local attempt = 0
	local delayFor = GameConfig.Data.SaveRetryBackoff

	local function attemptSave()
		while attempt < GameConfig.Data.SaveRetries do
			attempt += 1
			local ok, err = pcall(function()
				(store :: DataStore):UpdateAsync(key(player), function(old)
					-- Last-write-wins is acceptable for a single-session profile,
					-- but never regress a profile that is somehow newer.
					if
						type(old) == "table"
						and type(old.Meta) == "table"
						and (old.Meta.LastJoinUnix or 0) > (profile.Meta.LastJoinUnix or 0)
					then
						return nil -- abort write
					end
					return profile
				end)
			end)
			if ok then
				return true
			end
			warn(
				("[PlayerData] Save attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(err))
			)
			task.wait(delayFor)
			delayFor *= 2
		end
		warn("[PlayerData] SAVE FAILED after retries for " .. player.Name)
		return false
	end

	if immediate then
		attemptSave()
	else
		task.spawn(attemptSave)
	end
end

return PlayerDataService
