--!strict
-- Bootstrap.server.lua
-- The ONLY Script in ServerScriptService. Everything else is a ModuleScript.
-- Blueprint §42: "Do not make one 5,000-line MainScript."
--
-- Services receive a shared `ctx` table instead of requiring each other directly, which
-- keeps the dependency graph flat and avoids require cycles.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- script.Parent rather than the service directly, so the tree can be re-nested later
-- without touching this file.
local Services = script.Parent:WaitForChild("Services")

local Net = require(game.ReplicatedStorage.Shared.Net) -- creates the Remotes folder

local ctx = {}

ctx.Analytics = require(Services.AnalyticsService)
ctx.Data = require(Services.PlayerDataService)
ctx.Economy = require(Services.EconomyService)
ctx.RunState = require(Services.RunStateService)
ctx.Death = require(Services.DeathService)
ctx.LootService = require(Services.LootService)
ctx.EnemyService = require(Services.EnemyService)
ctx.Captain = require(Services.CaptainService)
ctx.Combat = require(Services.CombatService)
ctx.Inventory = require(Services.InventoryService)
ctx.Extraction = require(Services.ExtractionService)
ctx.Upgrade = require(Services.UpgradeService)
ctx.Interaction = require(Services.InteractionService)
ctx.Rooms = require(Services.RoomService)
ctx.Environment = require(Services.EnvironmentService)
ctx.Wanted = require(Services.WantedService)
ctx.Revive = require(Services.ReviveService)

local WorldBuilder = require(Services.WorldBuilder)

-- ── 1. World first: other services need references to its parts. ──
local world = WorldBuilder.Build()
ctx.World = world

-- ── 2. Core services, dependency order. ──
ctx.Analytics.Init(ctx)
ctx.Data.Init(ctx)
ctx.Economy.Init(ctx)
ctx.RunState.Init(ctx)
ctx.Death.Init(ctx) -- turns off CharacterAutoLoads; spawns after the profile loads
ctx.LootService.Init(ctx)
ctx.EnemyService.Init(ctx)
ctx.Captain.Init(ctx, world)
ctx.Combat.Init(ctx)
ctx.Inventory.Init(ctx)
ctx.Extraction.Init(ctx, world)
ctx.Upgrade.Init(ctx, world)
ctx.Environment.Init(ctx, world) -- before Interaction: the swing's breakables folder
ctx.Wanted.Init(ctx, world) -- before Interaction: the chest and the bell add heat
ctx.Revive.Init(ctx)
ctx.Interaction.Init(ctx, world)
ctx.Rooms.Init(ctx, world)

-- ── 3. Populate the dungeon. ──
ctx.EnemyService.Spawn("sleepy_guard", world.PatrolGuardSpawn, {
	PatrolA = world.PatrolPointA,
	PatrolB = world.PatrolPointB,
	SpawnCFrame = world.PatrolGuardSpawn,
})
-- The garrison (Sections F and H): each room a different problem.
-- Guard room: a second guard warms his hands at the hearth and only notices you up close,
-- so the first fight stays one guard at a time (§116).
ctx.EnemyService.Spawn("sleepy_guard", world.HearthGuardSpawn, {
	SpawnCFrame = world.HearthGuardSpawn,
	IdlePose = "WarmHands",
	AggroRange = 12,
})
-- The long hall: two spearmen on opposite lengths, a sentry on the north balcony firing
-- across the hall on the kitchen door's line.
for _, p in world.HallPatrolSpawns do
	ctx.EnemyService.Spawn("alarm_guard", p.Spawn, { PatrolA = p.A, PatrolB = p.B, SpawnCFrame = p.Spawn })
end
ctx.EnemyService.Spawn("crossbow_sentry", world.HallSentrySpawn, { SpawnCFrame = world.HallSentrySpawn })
-- Kitchen: a cook with his back to the door.
ctx.EnemyService.Spawn("sleepy_guard", world.KitchenGuardSpawn, {
	SpawnCFrame = world.KitchenGuardSpawn,
	IdlePose = "WarmHands",
	AggroRange = 14,
})
-- Barracks: three sleepers who wake if disturbed, and a brute between you and the key.
for _, cf in world.BarracksSleeperSpawns do
	ctx.EnemyService.Spawn("alarm_guard", cf, { SpawnCFrame = cf, Asleep = true })
end
ctx.EnemyService.Spawn(
	"brute",
	world.BarracksBruteSpawn,
	{ SpawnCFrame = world.BarracksBruteSpawn, AggroRange = 20 }
)
-- Vault: the archer covers it from the dais; the shield guard walks the line between the
-- door and the sewer arch.
ctx.EnemyService.Spawn("archer", world.VaultArcherSpawn, { SpawnCFrame = world.VaultArcherSpawn })
ctx.EnemyService.Spawn("shield_guard", world.VaultShieldSpawn, {
	PatrolA = world.VaultShieldPatrolA,
	PatrolB = world.VaultShieldPatrolB,
	SpawnCFrame = world.VaultShieldSpawn,
})
-- M2: Captain Bronn waits in his hall off the vault. (M2 brief item 1)
ctx.Captain.Spawn()

-- ── 4. Players always start in the cell. ──
Players.PlayerAdded:Connect(function(player)
	player.RespawnLocation = world.CellSpawn
	player.CharacterAdded:Connect(function(character)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root then
			task.wait(0.1)
			-- Milestone 1: every death restarts the run from the cell.
			local spawnRoot = root :: BasePart
			spawnRoot.CFrame = world.CellSpawnCFrame
		end
	end)
end)

print("[PRISONER TO KING] Milestone 1 server ready.")
