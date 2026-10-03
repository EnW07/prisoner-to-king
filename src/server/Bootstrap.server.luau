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
ctx.LootService = require(Services.LootService)
ctx.EnemyService = require(Services.EnemyService)
ctx.Captain = require(Services.CaptainService)
ctx.Combat = require(Services.CombatService)
ctx.Inventory = require(Services.InventoryService)
ctx.Extraction = require(Services.ExtractionService)
ctx.Upgrade = require(Services.UpgradeService)
ctx.Interaction = require(Services.InteractionService)

local WorldBuilder = require(Services.WorldBuilder)

-- ── 1. World first: other services need references to its parts. ──
local world = WorldBuilder.Build()
ctx.World = world

-- ── 2. Core services, dependency order. ──
ctx.Analytics.Init(ctx)
ctx.Data.Init(ctx)
ctx.Economy.Init(ctx)
ctx.RunState.Init(ctx)
ctx.LootService.Init(ctx)
ctx.EnemyService.Init(ctx)
ctx.Captain.Init(ctx, world)
ctx.Combat.Init(ctx)
ctx.Inventory.Init(ctx)
ctx.Extraction.Init(ctx, world)
ctx.Upgrade.Init(ctx, world)
ctx.Interaction.Init(ctx, world)

-- ── 3. Populate the dungeon. ──
ctx.EnemyService.Spawn("sleepy_guard", world.PatrolGuardSpawn, {
	PatrolA = world.PatrolPointA,
	PatrolB = world.PatrolPointB,
	Respawn = true,
	SpawnCFrame = world.PatrolGuardSpawn,
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
