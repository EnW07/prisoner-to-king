--!strict
-- WantedService.lua
-- The castle reacts to you (blueprint §15; MASTER_BUILD_SPEC L1). Levels 0 to 3, per
-- player, per run. One responsibility: heat, level, and the reinforcements it sends.
--
--   HEAT rises on kills, on opening a chest, on being seen (rate-limited), on breaking
--   things, and, voluntarily, on ringing the alarm bell in the long hall. It decays once
--   nobody has seen you for a while. Thresholds turn heat into a level.
--   LEVELS mean: a gold multiplier on everything you loot (danger is voluntary and paid
--   for), and reinforcements arriving at intervals FROM ENTRANCES (doors, stairs, the
--   sewer ramp), never where someone died. At level 3, hounds.
--
-- GUARDS YOU KILL STAY DEAD FOR THE RUN. This service replaced the old RespawnDelay:
-- clearing a room is permanent; the alarm is the threat.
--
-- Server-authoritative throughout. The client only receives the level (StateUpdate) and
-- the toasts. Analytics: WantedLevelReached per level.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(game.ReplicatedStorage.Shared.Net)

local WantedService = {}
local ctx
local world
local Notify: RemoteEvent
local WANTED = GameConfig.Wanted

type Heat = {
	Heat: number,
	Level: number,
	LastSeenAt: number,
	LastSeenHeatAt: number,
	LastSpawnAt: number,
	PackCounter: number,
}
local heats: { [number]: Heat } = {}
local reinforcements: { any } = {} -- records spawned by this service, alive or not yet pruned
local accumulator = 0
local ROMAN = { "I", "II", "III", "IV", "V" }

local function get(player: Player): Heat
	local h = heats[player.UserId]
	if not h then
		h = {
			Heat = 0,
			Level = 0,
			LastSeenAt = -math.huge,
			LastSeenHeatAt = -math.huge,
			LastSpawnAt = 0,
			PackCounter = 0,
		}
		heats[player.UserId] = h
	end
	return h
end

local function levelFor(heat: number): number
	local level = 0
	for i, threshold in WANTED.Thresholds do
		if heat >= threshold then
			level = i
		end
	end
	return math.min(level, WANTED.MaxLevel)
end

local function setLevel(player: Player, h: Heat, level: number)
	if level == h.Level then
		return
	end
	local rose = level > h.Level
	h.Level = level
	if rose then
		ctx.Analytics.Log(player, "WantedLevelReached", level, { level = tostring(level) })
		Notify:FireClient(player, {
			Text = ("WANTED %s"):format(ROMAN[level]),
			Sub = if level >= WANTED.MaxLevel then "THE HOUNDS ARE LOOSE" else "MORE GUARDS, MORE GOLD",
			Kind = "alarm",
		})
	end
	ctx.Economy.PushState(player)
end

-- The run is on: heat only accrues and decays while the player is in the castle.
local function inRun(player: Player): boolean
	local run = ctx.RunState.Get(player)
	return run ~= nil and run.State ~= "Safe" and run.State ~= "Dead"
end

-- ── Public ──────────────────────────────────────────────────────
function WantedService.Level(player: Player): number
	local h = heats[player.UserId]
	return if h then h.Level else 0
end

-- The gold multiplier for loot this player causes to drop (LootService, the chests).
function WantedService.GoldMultiplier(player: Player): number
	local level = WantedService.Level(player)
	return WANTED.GoldMultiplier[level + 1] or 1
end

function WantedService.AddHeat(player: Player, amount: number, reason: string)
	if not inRun(player) or amount <= 0 then
		return
	end
	local h = get(player)
	h.Heat = math.min(h.Heat + amount, WANTED.Thresholds[#WANTED.Thresholds] * WANTED.HeatCapFactor)
	h.LastSeenAt = os.clock() -- doing anything loud counts as being noticed
	setLevel(player, h, levelFor(h.Heat))
	local _ = reason
end

-- An enemy has just noticed this player. Heat from being seen is rate-limited so a room
-- of guards turning at once doesn't jump three levels.
function WantedService.Seen(player: Player)
	local h = get(player)
	local now = os.clock()
	h.LastSeenAt = now
	if now - h.LastSeenHeatAt >= WANTED.SeenHeatInterval then
		h.LastSeenHeatAt = now
		WantedService.AddHeat(player, WANTED.HeatSeen, "seen")
	end
end

-- A fresh run, or a death: nothing carries over.
function WantedService.Reset(player: Player)
	local h = get(player)
	h.Heat = 0
	h.LastSeenAt = -math.huge
	h.LastSpawnAt = 0
	setLevel(player, h, 0)
end

-- ── Reinforcements ──────────────────────────────────────────────
local function prune()
	for i = #reinforcements, 1, -1 do
		local record = reinforcements[i]
		if record.State == "Dead" or not record.Model.Parent then
			table.remove(reinforcements, i)
		end
	end
end

-- An entrance to arrive from: the nearest to the player that is still at least
-- MinSpawnDistance away, so nobody materialises in your face.
local function pickEntrance(position: Vector3): CFrame?
	local best: CFrame? = nil
	local bestDistance = math.huge
	for _, cf in world.WantedSpawns do
		local d = (cf.Position - position).Magnitude
		if d >= WANTED.MinSpawnDistance and d < bestDistance then
			best, bestDistance = cf, d
		end
	end
	return best
end

local function reinforce(player: Player, h: Heat)
	prune()
	if #reinforcements >= WANTED.MaxReinforcements then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local entrance = pickEntrance(root.Position)
	if not entrance then
		return
	end
	h.LastSpawnAt = os.clock()
	local pool = WANTED.SpawnEnemies[h.Level + 1]
	if not pool or #pool == 0 then
		return
	end
	-- At the top level every other arrival is a hound pack: the escape run gets frightening.
	if h.Level >= WANTED.HoundPackAt then
		h.PackCounter += 1
		if h.PackCounter % 2 == 0 then
			for _, record in
				ctx.EnemyService.SpawnPack(
					"hound",
					entrance,
					WANTED.HoundPackSize,
					{ SpawnCFrame = entrance }
				)
			do
				table.insert(reinforcements, record)
			end
			Notify:FireClient(player, { Text = "HOUNDS", Kind = "alarm" })
			return
		end
	end
	local enemyId = pool[math.random(1, #pool)]
	local record = ctx.EnemyService.Spawn(enemyId, entrance, { SpawnCFrame = entrance })
	if record then
		table.insert(reinforcements, record)
	end
end

local function tick()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local h = heats[player.UserId]
		if not h or not inRun(player) then
			continue
		end
		-- Decay once unseen for a while.
		if h.Heat > 0 and now - h.LastSeenAt >= WANTED.DecayDelay then
			h.Heat = math.max(0, h.Heat - WANTED.DecayPerSecond * WANTED.TickInterval)
			setLevel(player, h, levelFor(h.Heat))
		end
		-- Reinforcements by level.
		if h.Level > 0 then
			local interval = WANTED.SpawnInterval[h.Level + 1] or 0
			if interval > 0 and now - h.LastSpawnAt >= interval then
				reinforce(player, h)
			end
		end
	end
end

function WantedService.Init(context, builtWorld)
	ctx = context
	world = builtWorld
	Notify = Net.Event("Notify")

	Players.PlayerRemoving:Connect(function(player)
		heats[player.UserId] = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < WANTED.TickInterval then
			return
		end
		accumulator = 0
		tick()
	end)
end

return WantedService
