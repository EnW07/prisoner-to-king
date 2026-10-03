--!strict
-- WorldBuilder.lua
-- Builds the entire Milestone 1 graybox from code at runtime.
--
-- WHY: so the whole loop is testable with zero manual Studio building. Drop the scripts in,
-- press Play. When real art exists, replace this module with a streamed static map and keep
-- the same reference names — nothing else in the codebase needs to change.
--
-- Layout (top-down, +X is "deeper into the castle"):
--
--   CELL (-20..0)  ──corridor(0..60)──  [LOCKED DOOR]  VAULT ROOM (60..100) ═arch═ CAPTAIN'S HALL (101..141)
--                                                            │
--                                                       sewer tunnel
--                                                            │
--                                                     EXTRACTION PAD
--
--   The hall sits on the same z = 0 sightline as the cellblock door, so Captain Bronn is in
--   view the moment the door opens on run 1. He never leaves his hall, so he can't block
--   the chest or the escape route (§115): fighting him is always a choice.
--
--   HIDEOUT sits far away at z=400 (separate safe area, same place file — §77).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local Palette = require(game.ReplicatedStorage.Shared.Config.Palette)

local WorldBuilder = {}

local function part(
	name: string,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	parent: Instance,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Slate
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function box(
	name: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	color: Color3,
	parent: Instance,
	material: Enum.Material?
): Part
	return part(name, CFrame.new(x, y, z), Vector3.new(sx, sy, sz), color, parent, material)
end

local function torch(x: number, y: number, z: number, parent: Instance)
	local p = box("Torch", x, y, z, 0.4, 1.2, 0.4, Color3.fromRGB(90, 60, 40), parent, Enum.Material.Wood)
	p.CanCollide = false
	-- A visible flame, so the light has a source. Clients flicker it (WorldFXController).
	local flame = box("Flame", x, y + 0.9, z, 0.5, 0.7, 0.5, Palette.ember, parent, Enum.Material.Neon)
	flame.CanCollide = false
	flame.CanQuery = false
	flame.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = Palette.ember
	light.Brightness = 2.4
	light.Range = 26
	light.Parent = flame
	CollectionService:AddTag(flame, "PTKTorch")
end

local STONE = Color3.fromRGB(105, 105, 110)
local DARK = Color3.fromRGB(70, 70, 76)
local WOOD = Color3.fromRGB(110, 75, 45)

function WorldBuilder.Build()
	-- Clear anything Studio put there by default.
	for _, inst in workspace:GetChildren() do
		if inst.Name == "Baseplate" or inst:IsA("SpawnLocation") then
			inst:Destroy()
		end
	end

	local existing = workspace:FindFirstChild("World")
	if existing then
		existing:Destroy()
	end

	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = workspace

	local zones = Instance.new("Folder")
	zones.Name = "Zones"
	zones.Parent = world
	local interact = Instance.new("Folder")
	interact.Name = "Interactables"
	interact.Parent = world
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = world

	-- ── Lighting: dungeon dusk, torch-lit ──────────────────────
	Lighting.ClockTime = 17.2
	Lighting.Brightness = 1.4
	Lighting.Ambient = Color3.fromRGB(60, 58, 66)
	Lighting.OutdoorAmbient = Color3.fromRGB(80, 80, 95)
	Lighting.FogEnd = 600
	Lighting.FogColor = Color3.fromRGB(60, 62, 75)

	-- ══ CELL ═══════════════════════════════════════════════════
	box("CellFloor", -10, -0.5, 0, 20, 1, 16, DARK, zones)
	box("CellWallW", -20.5, 6, 0, 1, 12, 18, STONE, zones)
	box("CellWallN", -10, 6, 8.5, 22, 12, 1, STONE, zones)
	box("CellWallS", -10, 6, -8.5, 22, 12, 1, STONE, zones)
	-- East wall split to leave a 6-stud doorway at z = -3..3
	box("CellWallE1", 0.5, 6, 5.75, 1, 12, 5.5, STONE, zones)
	box("CellWallE2", 0.5, 6, -5.75, 1, 12, 5.5, STONE, zones)
	torch(-19.5, 7, 5, props)
	torch(-19.5, 7, -5, props)

	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "CellSpawn"
	spawnPad.Anchored = true
	spawnPad.Size = Vector3.new(6, 1, 6)
	spawnPad.CFrame = CFrame.new(-16, 0.5, 0)
	spawnPad.Color = DARK
	spawnPad.Material = Enum.Material.Slate
	spawnPad.Neutral = true
	spawnPad.Duration = 0
	spawnPad.Transparency = 1
	spawnPad.Parent = zones

	-- The chain the player breaks. (§8, 0:05–0:20)
	local chain =
		box("Chain", -19, 2.5, 0, 0.5, 5, 0.5, Color3.fromRGB(85, 85, 90), interact, Enum.Material.Metal)
	chain.CanCollide = false

	-- First weapon, on a plank near the wall.
	local plank = box("WeaponPlank", -10, 1, 6.6, 3, 0.4, 1, WOOD, interact, Enum.Material.Wood)
	local spoon = box(
		"SpoonProp",
		-10,
		1.4,
		6.6,
		0.25,
		1.4,
		0.25,
		Color3.fromRGB(170, 170, 175),
		props,
		Enum.Material.Metal
	)
	spoon.CanCollide = false
	spoon.Orientation = Vector3.new(0, 0, 90)

	-- Distant castle silhouette, visible past the cell. Pure motivation prop. (§8, 0:00–0:05)
	for i = 1, 5 do
		local t = box(
			"DistantTower",
			-260 - i * 22,
			40 + (i % 3) * 14,
			-40 + i * 30,
			26,
			90 + (i % 3) * 30,
			26,
			Color3.fromRGB(48, 50, 62),
			props,
			Enum.Material.Concrete
		)
		t.CanCollide = false
	end

	-- ══ CORRIDOR ═══════════════════════════════════════════════
	box("CorridorFloor", 30, -0.5, 0, 60, 1, 14, DARK, zones)
	box("CorridorWallN", 30, 6, 7.5, 60, 12, 1, STONE, zones)
	box("CorridorWallS", 30, 6, -7.5, 60, 12, 1, STONE, zones)
	torch(10, 7, 6.8, props)
	torch(30, 7, -6.8, props)
	torch(50, 7, 6.8, props)

	-- ══ LOCKED CELLBLOCK DOOR ══════════════════════════════════
	box("DoorWallN", 60.5, 6, 5.75, 1, 12, 5.5, STONE, zones)
	box("DoorWallS", 60.5, 6, -5.75, 1, 12, 5.5, STONE, zones)
	local door = box("LockedDoor", 60.5, 5.5, 0, 1, 11, 6, WOOD, interact, Enum.Material.WoodPlanks)

	-- ══ VAULT ROOM ═════════════════════════════════════════════
	box("VaultFloor", 80.5, -0.5, 0, 40, 1, 30, DARK, zones)
	box("VaultWallN", 80.5, 6, 15.5, 41, 12, 1, STONE, zones)
	-- East wall split around a 12-wide, 10-tall archway into the Captain's hall.
	box("VaultWallE1", 101, 6, 11, 1, 12, 10, STONE, zones)
	box("VaultWallE2", 101, 6, -11, 1, 12, 10, STONE, zones)
	box("VaultArchLintel", 101, 11, 0, 1, 2, 12, STONE, zones)
	box("VaultWallW1", 60.5, 6, 11.75, 1, 12, 7.5, STONE, zones)
	box("VaultWallW2", 60.5, 6, -11.75, 1, 12, 7.5, STONE, zones)
	-- South wall with a 6-stud sewer opening at x = 90..96
	box("VaultWallS1", 75, 6, -15.5, 30, 12, 1, STONE, zones)
	box("VaultWallS2", 98.5, 6, -15.5, 5, 12, 1, STONE, zones)
	torch(99.5, 7, 8, props)
	torch(99.5, 7, -8, props)

	-- Base + separate lid, so the lid can hinge open. The lid is per-player visual state
	-- (each run's chest is its own), so clients open it locally (WorldFXController); the
	-- server never moves it.
	local chest =
		box("Chest", 80.5, 1.1, 8, 4, 2.2, 3, Color3.fromRGB(120, 85, 50), interact, Enum.Material.WoodPlanks)
	local chestLid = box(
		"ChestLid",
		80.5,
		2.6,
		8,
		4.2,
		0.8,
		3.2,
		Color3.fromRGB(120, 85, 50),
		props,
		Enum.Material.WoodPlanks
	)
	chestLid.CanCollide = false
	CollectionService:AddTag(chestLid, "PTKChestLid")

	-- ══ CAPTAIN'S HALL (M2) ════════════════════════════════════
	box("HallFloor", 121.5, -0.5, 0, 41, 1, 30, Palette.pitch, zones)
	box("HallWallN", 121.5, 7, 15.5, 41, 14, 1, Palette.stone, zones)
	box("HallWallS", 121.5, 7, -15.5, 41, 14, 1, Palette.stone, zones)
	box("HallWallE", 142.5, 7, 0, 1, 14, 32, Palette.stone, zones)
	-- The line you cross to start the fight. Colour is backed by the archway itself and the
	-- banner on entry, so this is never the only signal (art §3).
	local threshold =
		box("HallThreshold", 102.5, 0.03, 0, 1, 0.06, 12, Palette.bleed, props, Enum.Material.Neon)
	threshold.CanCollide = false
	-- His dais at the far end, so he reads as "the thing in this room" from the vault.
	box("HallDais", 134, 0.25, 0, 10, 0.5, 14, Palette.stone, zones)
	torch(141.5, 8, 9, props)
	torch(141.5, 8, -9, props)
	torch(118, 8, 14.8, props)
	torch(118, 8, -14.8, props)

	-- ══ SEWER TUNNEL → EXTRACTION ══════════════════════════════
	box("SewerFloor", 93, -0.5, -33, 6, 1, 37, Color3.fromRGB(60, 62, 55), zones, Enum.Material.Concrete)
	box("SewerWallW", 89.5, 4, -33, 1, 8, 37, Color3.fromRGB(70, 72, 65), zones, Enum.Material.Concrete)
	box("SewerWallE", 96.5, 4, -33, 1, 8, 37, Color3.fromRGB(70, 72, 65), zones, Enum.Material.Concrete)
	torch(90.2, 5, -25, props)
	torch(90.2, 5, -40, props)

	local extraction = box(
		"ExtractionPad",
		93,
		0.3,
		-47,
		6,
		0.6,
		6,
		Color3.fromRGB(70, 200, 110),
		interact,
		Enum.Material.Neon
	)

	-- ══ HIDEOUT (safe zone) ════════════════════════════════════
	box("HideoutFloor", 0, -0.5, 400, 40, 1, 40, Color3.fromRGB(95, 80, 65), zones, Enum.Material.WoodPlanks)
	box("HideoutWallN", 0, 4, 420.5, 41, 8, 1, WOOD, zones, Enum.Material.WoodPlanks)
	box("HideoutWallS", 0, 4, 379.5, 41, 8, 1, WOOD, zones, Enum.Material.WoodPlanks)
	box("HideoutWallW", -20.5, 4, 400, 1, 8, 40, WOOD, zones, Enum.Material.WoodPlanks)
	box("HideoutWallE", 20.5, 4, 400, 1, 8, 40, WOOD, zones, Enum.Material.WoodPlanks)
	torch(-19, 5, 390, props)
	torch(19, 5, 410, props)

	local upgradePad =
		box("UpgradePad", -8, 0.3, 392, 6, 0.6, 6, Color3.fromRGB(255, 190, 70), interact, Enum.Material.Neon)
	local reenterPad =
		box("ReenterPad", 8, 0.3, 392, 6, 0.6, 6, Color3.fromRGB(220, 80, 80), interact, Enum.Material.Neon)

	-- The weapon rack visibly grows with each weapon upgrade (§16: upgrades change the 3D space).
	local rack = box("WeaponRack", -8, 2, 388, 6, 4, 1, WOOD, props, Enum.Material.WoodPlanks)
	rack.CanCollide = false

	local hideoutSpawn = box("HideoutSpawnMarker", 0, 0.1, 405, 4, 0.2, 4, Color3.fromRGB(95, 80, 65), zones)
	hideoutSpawn.Transparency = 1
	hideoutSpawn.CanCollide = false

	return {
		Folder = world,
		Interactables = interact,
		Props = props,
		CellSpawn = spawnPad,
		Chain = chain,
		WeaponPlank = plank,
		SpoonProp = spoon,
		LockedDoor = door,
		Chest = chest,
		ExtractionPad = extraction,
		UpgradePad = upgradePad,
		ReenterPad = reenterPad,
		WeaponRack = rack,
		HideoutSpawn = hideoutSpawn,

		-- Named positions other services need
		CellSpawnCFrame = CFrame.new(-16, 4, 0),
		HideoutSpawnCFrame = CFrame.new(0, 4, 405),
		PatrolGuardSpawn = CFrame.new(25, 3, 0),
		PatrolPointA = Vector3.new(12, 0, 0),
		PatrolPointB = Vector3.new(50, 0, 0),
		AlarmGuardSpawns = { CFrame.new(66, 3, -10), CFrame.new(96, 3, 10) },

		-- Captain Bronn: faces west, down the sightline to the cellblock door.
		CaptainSpawn = CFrame.lookAt(Vector3.new(130, 4.5, 0), Vector3.new(60, 4.5, 0)),
		CaptainReinforcementSpawn = CFrame.new(138, 3, 11),
		-- Fight zone: the hall floor east of the threshold, full room height.
		CaptainArena = { Min = Vector3.new(102, -2, -15), Max = Vector3.new(142, 20, 15) },
	}
end

return WorldBuilder
