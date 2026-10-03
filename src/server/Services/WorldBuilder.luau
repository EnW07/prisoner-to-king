--!strict
-- WorldBuilder.lua
-- Builds the whole playable castle from code at runtime: no manual Studio building, no
-- imported meshes, no marketplace assets. Primitives only (WorldParts); props and clutter
-- are WorldDressing's. (MASTER_BUILD_SPEC Section H.)
--
-- WHY: so the loop is testable with zero manual Studio work. When real art exists, replace
-- this module with a streamed static map and keep the same reference names; nothing else in
-- the codebase needs to change. Every name in the returned table is load-bearing.
--
-- LAYOUT (top-down, +X is deeper into the castle; floor heights in brackets):
--
--   CELL ─bars─ CELLBLOCK ─ramp↑─ GUARD ROOM [+3] ─ramp↓─ CORRIDOR ─[LOCKED DOOR x76]─▶
--  (-44..-28)   (-28..0)          (8..48)              (56..76)
--
--                        KITCHEN / STORES (96..136, z 15..45)
--                              │ door x106            └─ vestibule ─▶ vault NW corner
--   ▶ THE LONG HALL (76..136, z ±15, 24 high, balconies at +8) ─ passage, BARRABLE DOOR x141 ─▶
--                              │ steps↓ x96
--                        BARRACKS [-2] (86..126, z -47..-21): sleepers, a brute, the POSTERN KEY
--
--   ▶ VAULT (146..196, z ±20) ═great arch═ stairs↑ BRONN'S HALL [+3] (202..246)
--        │ false wall x162..168 north → CHAPEL [+1] (150..170, z 21..41): relic, ghost knight
--        │ POSTERN GATE x186..190 north → short stair↑ → POSTERN PAD (the locked shortcut)
--        │ sewer arch x170..176 south
--        ▼ ramp↓ SEWERS [-6]: south to z=-90, west to the ESCAPE PAD at x=124; a dark branch east
--
--   HIDEOUT sits far away at z = 400 (separate safe area, same place file — §77).
--
-- READABILITY (H2): torches cluster on the critical path; side rooms are darker. Each room
-- has one colour note (cells: cold slate; guard room: a hearth; hall: light shafts and
-- ember heraldry; kitchen: wood; barracks: near-dark; vault: gold; chapel: candles;
-- Bronn: `bleed` banners; sewer: black water). Sightlines: the door, the hall's arch, the
-- vault and Bronn's dais are on z = 0. Vertical: balconies, steps down, a dais, a stair up.
--
-- Colour: palette tokens only (art §3). Wood keeps its M1 value; variety is Materials.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local Palette = require(game.ReplicatedStorage.Shared.Config.Palette)
local P = require(script.Parent.WorldParts)
local WorldDressing = require(script.Parent.WorldDressing)

local WorldBuilder = {}

local box, wall, floor, ceiling, archWall, pillar, bars, torch, windowSlit, banner, decor =
	P.box, P.wall, P.floor, P.ceiling, P.archWall, P.pillar, P.bars, P.torch, P.windowSlit, P.banner, P.decor
local rampX, rampZ, rampZDown = P.rampX, P.rampZ, P.rampZDown
local WOOD, CHEST_WOOD = P.WOOD, P.CHEST_WOOD

-- ── Build ───────────────────────────────────────────────────────
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

	-- ── Lighting: dungeon dusk, torch-lit, with depth haze for sightlines ──
	Lighting.ClockTime = 17.2
	Lighting.Brightness = 1.4
	Lighting.Ambient = Palette.pitch
	Lighting.OutdoorAmbient = Palette.stone
	Lighting.FogEnd = 600
	Lighting.FogColor = Palette.pitch
	local oldAtmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if oldAtmosphere then
		oldAtmosphere:Destroy()
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Haze = 1
	atmosphere.Color = Palette.stone
	atmosphere.Decay = Palette.pitch
	atmosphere.Parent = Lighting

	-- ══ YOUR CELL ══════════════════════════════════════════════
	floor("CellFloor", -44, -28, -8, 8, 0, zones, Enum.Material.Slate)
	wall("CellWallW", -44.7, 0, 0, 1.4, 12, 17.4, zones)
	wall("CellWallN", -36, 0, 8.7, 17.4, 12, 1.4, zones)
	wall("CellWallS", -36, 0, -8.7, 17.4, 12, 1.4, zones)
	-- Cell bars across the east side; the cell gate stands open where the chain used to hold you.
	bars("CellBars", -28, -8, 8, false, 0, 10, zones, -2.2, 2.2)
	local gate = Instance.new("Folder")
	gate.Name = "CellGate"
	gate.Parent = props
	bars("GateBar", -28, -2, 2, false, 0, 10, gate)
	-- Swing the whole gate about its hinge post so it stands open into the hall.
	local hinge = CFrame.new(-28, 0, 2.2)
	local swing = hinge * CFrame.Angles(0, math.rad(-100), 0) * hinge:Inverse()
	for _, p in gate:GetChildren() do
		if p:IsA("BasePart") then
			p.CFrame = swing * p.CFrame
			decor(p)
		end
	end
	torch(-43.6, 7, 4, props, Vector3.new(1, 0, 0), 18) -- one dim torch: the cells are cold
	windowSlit(-36, 9, 7.9, Vector3.new(0, 0, -1), props)

	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "CellSpawn"
	spawnPad.Anchored = true
	spawnPad.Size = Vector3.new(6, 1, 6)
	spawnPad.CFrame = CFrame.new(-40, 0.5, 0)
	spawnPad.Color = Palette.pitch
	spawnPad.Material = Enum.Material.Slate
	spawnPad.Neutral = true
	spawnPad.Duration = 0
	spawnPad.Transparency = 1
	spawnPad.CanCollide = false
	spawnPad.Parent = zones

	-- The chain the player breaks. (§8, 0:05–0:20)
	local chain = box("Chain", -43, 2.5, 0, 0.5, 5, 0.5, Palette.pitch, interact, Enum.Material.Metal)
	chain.CanCollide = false

	-- First weapon, on a plank by the north wall.
	local plank = box("WeaponPlank", -36, 1, 6.9, 3, 0.4, 1, WOOD, interact, Enum.Material.Wood)
	local spoon = box("SpoonProp", -36, 1.4, 6.9, 0.25, 1.4, 0.25, Palette.stone, props, Enum.Material.Metal)
	spoon.CanCollide = false
	spoon.Orientation = Vector3.new(0, 0, 90)

	-- Distant castle silhouette, visible above the walls. Pure motivation prop. (§8, 0:00–0:05)
	for i = 1, 5 do
		local t = box(
			"DistantTower",
			-280 - i * 22,
			40 + (i % 3) * 14,
			-40 + i * 30,
			26,
			90 + (i % 3) * 30,
			26,
			Palette.pitch,
			props,
			Enum.Material.Concrete
		)
		decor(t)
	end

	-- ══ CELLBLOCK HALL ═════════════════════════════════════════
	floor("HallFloor", -28, 0, -8, 8, 0, zones)
	wall("CellblockWallS", -14, 0, -8.7, 28, 14, 1.4, zones)
	-- North side: two more cells behind bars, between short wall piers.
	wall("CellblockPierW", -26.5, 0, 8.7, 3, 14, 1.4, zones)
	wall("CellblockPierM", -15, 0, 8.7, 2, 14, 1.4, zones)
	wall("CellblockPierE", -2, 0, 8.7, 4, 14, 1.4, zones)
	bars("NeighbourBarsW", 8.7, -25, -16, true, 0, 10, zones)
	bars("NeighbourBarsE", 8.7, -14, -4, true, 0, 10, zones)
	floor("NeighbourCellsFloor", -25, -4, 8, 16, 0, zones, Enum.Material.Slate)
	wall("NeighbourCellsBack", -14.5, 0, 16.7, 23, 12, 1.4, zones)
	wall("NeighbourCellsSideW", -25.7, 0, 12.4, 1.4, 12, 8, zones)
	wall("NeighbourCellsSideE", -3.3, 0, 12.4, 1.4, 12, 8, zones)
	wall("NeighbourCellsSplit", -15, 0, 12.4, 1.4, 12, 8, zones)
	windowSlit(-20, 9, 16, Vector3.new(0, 0, -1), props)
	windowSlit(-9, 9, 16, Vector3.new(0, 0, -1), props)
	torch(-20, 7, -7.6, props, Vector3.new(0, 0, 1))
	torch(-6, 7, -7.6, props, Vector3.new(0, 0, 1))
	-- Exit: an arched doorway into the ramp up.
	archWall("CellblockExit", 0, 0, 0, false, 17.4, 14, 10, 10, 2.5, zones)

	-- ══ RAMP UP → GUARD ROOM (+3) ══════════════════════════════
	rampX("RampUp", 0, 8, -5, 5, 0, 3, zones)
	wall("RampWallN", 4, 0, 5.7, 8, 14, 1.4, zones)
	wall("RampWallS", 4, 0, -5.7, 8, 14, 1.4, zones)

	-- ══ GUARD ROOM (+3): the first real fight, by a hearth ═════
	local g = 3
	floor("GuardFloor", 8, 48, -14, 14, g, zones)
	-- Fill under the raised floor so there's no gap to see through.
	box("GuardFloorFill", 28, 0.5, 0, 40, 1, 28, Palette.pitch, zones, Enum.Material.Cobblestone)
	archWall("GuardWallW", 8, g, 0, false, 29.4, 14, 10, 10, 2.5, zones)
	archWall("GuardWallE", 48, g, 0, false, 29.4, 14, 10, 10, 2.5, zones)
	wall("GuardWallN", 28, g, 14.7, 41.4, 14, 1.4, zones)
	wall("GuardWallS", 28, g, -14.7, 41.4, 14, 1.4, zones)
	-- Wall the step down from the archways to the lower ramps' sides.
	wall("GuardStepW", 8, 0, 0, 1.4, g, 29.4, zones)
	wall("GuardStepE", 48, 0, 0, 1.4, g, 29.4, zones)
	for _, px in { 18, 38 } do
		pillar(px, g, 8, 14, zones)
		pillar(px, g, -8, 14, zones)
	end
	windowSlit(18, g + 9, 13.9, Vector3.new(0, 0, -1), props)
	torch(28, g + 7, -13.6, props, Vector3.new(0, 0, 1))
	torch(9.2, g + 7, 9, props, Vector3.new(1, 0, 0))
	torch(46.8, g + 7, -9, props, Vector3.new(-1, 0, 0))

	-- ══ RAMP DOWN → CORRIDOR ═══════════════════════════════════
	rampX("RampDown", 48, 56, -5, 5, g, 0, zones)
	wall("RampDownWallN", 52, 0, 5.7, 8, 14, 1.4, zones)
	wall("RampDownWallS", 52, 0, -5.7, 8, 14, 1.4, zones)
	floor("CorridorFloor", 56, 76, -6, 6, 0, zones)
	wall("CorridorWallN", 66, 0, 6.7, 20, 14, 1.4, zones)
	wall("CorridorWallS", 66, 0, -6.7, 20, 14, 1.4, zones)
	torch(62, 7, 5.6, props, Vector3.new(0, 0, -1))
	torch(70, 7, -5.6, props, Vector3.new(0, 0, 1))

	-- ══ THE LONG HALL (76..136, z ±15, 24 high) ════════════════
	-- The room that makes the castle feel big: pillars, balconies at +8 along both sides,
	-- banners, light shafts from high windows, a ceiling so the shafts read.
	local hallTop = 24
	floor("LongHallFloor", 76, 136, -15, 15, 0, zones)
	ceiling("LongHallCeiling", 76, 136, -15, 15, hallTop, zones)
	-- West wall carries the LOCKED CELLBLOCK DOOR (thinner than the wall, so the arch frames it).
	archWall("LongHallWallW", 76, 0, 0, false, 31.4, hallTop, 6, 10, 2, zones)
	local door = box("LockedDoor", 76, 5, 0, 0.6, 10, 6, WOOD, interact, Enum.Material.WoodPlanks)
	-- East wall: the great arch toward the vault passage.
	archWall("LongHallWallE", 136, 0, 0, false, 31.4, hallTop, 10, 13, 3, zones)
	-- North wall: the kitchen door at x = 106. South wall: the barracks steps at x = 96.
	archWall("LongHallWallN", 106, 0, 15, true, 61.4, hallTop, 8, 10, 2, zones, 0)
	archWall("LongHallWallS", 106, 0, -15, true, 61.4, hallTop, 8, 10, 2, zones, -10)
	for _, px in { 88, 106, 124 } do
		pillar(px, 0, 9, hallTop, zones, 1.4)
		pillar(px, 0, -9, hallTop, zones, 1.4)
	end
	-- Balconies: walkways at +8 along both long walls, reached by stairs at the east end.
	local balcony = 8
	for _, side in { 1, -1 } do
		local z0, z1 = if side == 1 then 11 else -15, if side == 1 then 15 else -11
		local slab = box(
			"HallBalcony",
			102,
			balcony - 0.5,
			(z0 + z1) / 2,
			44,
			1,
			z1 - z0,
			Palette.stone,
			zones,
			Enum.Material.Slate
		)
		slab.Name = if side == 1 then "HallBalconyN" else "HallBalconyS"
		bars("BalconyRail", if side == 1 then 11.2 else -11.2, 80, 124, true, balcony, 3, zones)
		rampX("BalconyStair", 124, 136, z0, z1, balcony, 0, zones)
	end
	for _, px in { 90, 106, 122 } do
		windowSlit(px, 18, 14.9, Vector3.new(0, 0, -1), props, 22)
		windowSlit(px, 18, -14.9, Vector3.new(0, 0, 1), props, 22)
	end
	banner(135.6, 11, -8, Vector3.new(-1, 0, 0), props, Palette.ember)
	banner(135.6, 11, 8, Vector3.new(-1, 0, 0), props, Palette.ember)
	banner(76.4, 11, -9, Vector3.new(1, 0, 0), props, Palette.ember)
	banner(76.4, 11, 9, Vector3.new(1, 0, 0), props, Palette.ember)
	-- Torches run the length of the critical path (both sides); the side doors are dimmer.
	for _, px in { 82, 96, 116, 130 } do
		torch(px, 7, 14.6, props, Vector3.new(0, 0, -1))
		torch(px, 7, -14.6, props, Vector3.new(0, 0, 1))
	end
	-- The alarm bell (L1): hanging from a post at the hall's midpoint. Ring it on purpose.
	box("BellPost", 106, 4, -13.2, 0.6, 8, 0.6, Palette.pitch, zones, Enum.Material.Metal)
	decor(box("BellArm", 106, 7.8, -12.2, 0.4, 0.4, 2.4, Palette.pitch, props, Enum.Material.Metal))
	local alarmBell = P.part(
		"AlarmBell",
		CFrame.new(106, 6.4, -11.4),
		Vector3.new(1.6, 1.8, 1.6),
		Palette.gold,
		interact,
		Enum.Material.Metal
	)
	alarmBell.Shape = Enum.PartType.Cylinder
	alarmBell.CFrame = CFrame.new(106, 6.4, -11.4) * CFrame.Angles(0, 0, math.rad(90))
	alarmBell.CanCollide = false

	-- Chandelier winches (H4): a cleat on the south wall under each chandelier.
	local winchW =
		box("ChandelierWinchW", 92, 1.2, -14.2, 1.2, 2.4, 1, Palette.pitch, interact, Enum.Material.Metal)
	local winchE =
		box("ChandelierWinchE", 120, 1.2, -14.2, 1.2, 2.4, 1, Palette.pitch, interact, Enum.Material.Metal)

	-- ══ PASSAGE → VAULT, with the BARRABLE DOOR at x = 141 ═════
	floor("PassageFloor", 136, 146, -5, 5, 0, zones)
	ceiling("PassageCeiling", 136, 146, -5, 5, 13, zones)
	wall("PassageWallS", 141, 0, -5.7, 10, 16, 1.4, zones)
	-- The block between the main passage and the kitchen vestibule.
	box("PassageBlock", 141, 8, 9.5, 10, 16, 8, Palette.stone, zones, Enum.Material.Brick)
	local barDoor = box("BarDoor", 141, 5, 0, 0.6, 10, 10, WOOD, interact, Enum.Material.WoodPlanks)
	barDoor.CanCollide = false -- open until barred (EnvironmentService)
	barDoor.CanQuery = false
	barDoor.Transparency = 0.75
	-- The bar itself, shown only while the door is barred.
	local doorBar = decor(box("DoorBar", 141.6, 5, 0, 0.4, 0.6, 8, Palette.pitch, props, Enum.Material.Metal))
	doorBar.Transparency = 1
	-- The winch the player uses, on the vault side of the door.
	local barWinch =
		box("BarWinch", 143.5, 1.2, -4.4, 1.2, 2.4, 1, Palette.pitch, interact, Enum.Material.Metal)
	torch(140, 7, 4.6, props, Vector3.new(0, 0, -1))

	-- Kitchen vestibule: the kitchen's east door drops into the vault's north-west corner.
	floor("VestibuleFloor", 136, 146, 13.5, 24, 0, zones)
	ceiling("VestibuleCeiling", 136, 146, 13.5, 24, 12, zones)
	wall("VestibuleWallN", 141, 0, 24.7, 10, 14, 1.4, zones)
	torch(141, 6, 24, props, Vector3.new(0, 0, -1), 18)

	-- ══ KITCHEN / STORES (96..136, z 15..45): clutter, crates, a hearth ═
	floor("KitchenFloor", 96, 136, 15, 45, 0, zones, Enum.Material.WoodPlanks, Color3.fromRGB(80, 62, 45))
	ceiling("KitchenCeiling", 96, 136, 15, 45, 14, zones)
	wall("KitchenWallW", 96, 0, 30, 1.4, 14, 30, zones)
	wall("KitchenWallN", 116, 0, 45.7, 41.4, 14, 1.4, zones)
	-- East wall with the door to the vestibule (z 18..24).
	archWall("KitchenWallE", 136, 0, 30, false, 30, 14, 6, 9, 1.5, zones, -9)
	windowSlit(126, 10, 45.2, Vector3.new(0, 0, -1), props, 14)
	torch(97, 6, 22, props, Vector3.new(1, 0, 0), 20)
	torch(135, 6, 40, props, Vector3.new(-1, 0, 0), 20)

	-- ══ BARRACKS (-2) (86..126, z -47..-21): sleepers, a brute, the key ═
	local b = -2
	rampZDown("BarracksSteps", -21, -15, 92, 100, 0, b, zones)
	wall("BarracksStepWallW", 91.3, b, -18, 1.4, 14, 6, zones)
	wall("BarracksStepWallE", 100.7, b, -18, 1.4, 14, 6, zones)
	floor("BarracksFloor", 86, 126, -47, -21, b, zones, Enum.Material.Slate)
	ceiling("BarracksCeiling", 86, 126, -47, -21, b + 12, zones)
	wall("BarracksWallW", 86, b, -34, 1.4, 14, 26, zones)
	wall("BarracksWallE", 126, b, -34, 1.4, 14, 26, zones)
	wall("BarracksWallS", 106, b, -47.7, 41.4, 14, 1.4, zones)
	-- North wall, with the steps' opening at x 92..100.
	wall("BarracksWallNW", 88.5, b, -21, 5, 14, 1.4, zones)
	wall("BarracksWallNE", 113, b, -21, 26, 14, 1.4, zones)
	-- Near dark: one torch by the steps, candles by the bunks (WorldDressing). Risk reads as dark.
	torch(101.4, b + 6, -24, props, Vector3.new(1, 0, 0), 16)
	-- Better loot, risk attached: a second chest, and the postern key on a table.
	local barracksChest =
		box("BarracksChest", 122, b + 1.1, -44, 3.6, 2.2, 2.6, CHEST_WOOD, interact, Enum.Material.WoodPlanks)
	local keyTable = P.table_(90, b, -42, 4, 2.4, props)
	local posternKey =
		box("PosternKey", 90, b + 3, -42, 0.5, 0.2, 1.4, Palette.gold, interact, Enum.Material.Metal)
	posternKey.CanCollide = false
	posternKey.CFrame = keyTable * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, math.rad(25), 0)

	-- ══ VAULT (146..196, z ±20) ═════════════════════════════════
	floor("VaultFloor", 146, 196, -20, 20, 0, zones)
	-- West wall: the passage arch at z = 0 and the vestibule arch at z 14..20.
	archWall("VaultWallWMain", 146, 0, -5, false, 30, 16, 10, 13, 3, zones, 5)
	archWall("VaultWallWVest", 146, 0, 15, false, 10, 16, 6, 9, 1.5, zones, 2)
	-- North wall: solid pieces, the FALSE WALL (x 162..168), and the POSTERN GATE (x 186..190).
	wall("VaultWallN1", 154, 0, 20.7, 16, 16, 1.4, zones)
	local falseWall = box("FalseWall", 165, 8, 20.7, 6, 16, 1.4, Palette.stone, zones, Enum.Material.Slate)
	falseWall.CanCollide = false
	falseWall.CanQuery = false -- sight passes too: a guard behind it would not be hidden, there are none
	wall("VaultWallN2", 177, 0, 20.7, 18, 16, 1.4, zones)
	wall("VaultWallN3", 193, 0, 20.7, 6, 16, 1.4, zones)
	box("PosternLintel", 188, 12, 20.7, 4, 8, 1.4, Palette.stone, zones, Enum.Material.Brick)
	local posternGate =
		box("PosternGate", 188, 4, 20.7, 4, 8, 0.6, Palette.pitch, interact, Enum.Material.Metal)
	-- South wall: the sewer arch at x = 170..176.
	archWall("VaultWallS", 171, 0, -20.7, true, 51.4, 16, 6, 9, 2, zones, 2)
	-- East wall: the great arch into Bronn's hall, on the door's sightline.
	archWall("VaultWallE", 196, 0, 0, false, 41.4, 16, 14, 13, 3, zones)
	-- Pillars flank the room, clear of the treasure dais (x 167..183) and the z = 0 sightline.
	for _, px in { 156, 188 } do
		pillar(px, 0, 12, 16, zones)
		pillar(px, 0, -12, 16, zones)
	end
	-- The treasure dais, lit by the vault's two window shafts: the valuable thing is
	-- literally in the light (art §2 screenshot test).
	box("TreasureDais", 175, 0.75, 16, 16, 1.5, 7, Palette.stone, zones, Enum.Material.Slate)
	rampZ("TreasureStep", 11.5, 12.5, 167, 183, 1.5, 0, zones)
	windowSlit(169, 11, 19.9, Vector3.new(0, 0, -1), props)
	windowSlit(181, 11, 19.9, Vector3.new(0, 0, -1), props)
	torch(147.2, 8, 9, props, Vector3.new(1, 0, 0))
	torch(147.2, 8, -9, props, Vector3.new(1, 0, 0))
	torch(194.8, 8, 12, props, Vector3.new(-1, 0, 0))
	torch(194.8, 8, -12, props, Vector3.new(-1, 0, 0))
	torch(172, 8, -19.6, props, Vector3.new(0, 0, 1)) -- the sewer arch is the lit way out

	-- Base + separate lid, so the lid can hinge open. The lid is per-player visual state
	-- (each run's chest is its own), so clients open it locally (WorldFXController); the
	-- server never moves it. Gold bands: it's the valuable thing (art §3 `gold`).
	local chestY = 1.5
	local chest =
		box("Chest", 175, chestY + 1.1, 16, 4, 2.2, 3, CHEST_WOOD, interact, Enum.Material.WoodPlanks)
	for _, bx in { -1.3, 1.3 } do
		decor(
			box(
				"ChestBand",
				175 + bx,
				chestY + 1.1,
				16,
				0.3,
				2.3,
				3.1,
				Palette.gold,
				props,
				Enum.Material.Metal
			)
		)
	end
	local chestLid =
		box("ChestLid", 175, chestY + 2.6, 16, 4.2, 0.8, 3.2, CHEST_WOOD, props, Enum.Material.WoodPlanks)
	chestLid.CanCollide = false
	CollectionService:AddTag(chestLid, "PTKChestLid")

	-- ══ CHAPEL (+1) (150..170, z 21..41): behind the false wall ═══
	local c = 1
	rampZ("ChapelStep", 21.4, 23, 162, 168, c, 0, zones)
	floor("ChapelFloor", 150, 170, 21.4, 41, c, zones, Enum.Material.Slate)
	ceiling("ChapelCeiling", 150, 170, 21.4, 41, c + 13, zones)
	wall("ChapelWallW", 150, c, 31, 1.4, 14, 20, zones)
	wall("ChapelWallE", 170, c, 31, 1.4, 14, 20, zones)
	wall("ChapelWallN", 160, c, 41.7, 21.4, 14, 1.4, zones)
	-- The chapel's south wall is the vault's north wall; close the sides of the false wall.
	wall("ChapelWallSW", 155.5, c, 21.4, 11, 14, 1.4, zones)
	wall("ChapelWallSE", 174.5, c, 21.4, 11, 14, 1.4, zones)
	windowSlit(160, c + 10, 41.2, Vector3.new(0, 0, -1), props, 12)
	local altar = box("Altar", 160, c + 1, 38, 5, 2, 2, Palette.stone, zones, Enum.Material.Slate)
	local relic =
		box("ChapelRelic", 160, c + 2.6, 38, 1.2, 1.2, 1.2, Palette.gold, interact, Enum.Material.Neon)
	relic.CanCollide = false
	relic.Orientation = Vector3.new(45, 0, 45)

	-- ══ POSTERN (the locked shortcut, H3) ═════════════════════
	-- Through the gate: a short stair up to a pad in the open air. Shorter and safer than
	-- the sewer, if you took the key from the barracks.
	floor("PosternFloor", 185, 191, 21.4, 28, 0, zones)
	rampZ("PosternStair", 28, 36, 185, 191, 3, 0, zones)
	floor("PosternLanding", 185, 191, 36, 42, 3, zones)
	wall("PosternWallW", 185, 0, 31.7, 1.4, 12, 20.6, zones)
	wall("PosternWallE", 191, 0, 31.7, 1.4, 12, 20.6, zones)
	wall("PosternWallN", 188, 3, 42.7, 7.4, 9, 1.4, zones)
	wall("PosternWallSE", 193, 0, 21.4, 4, 12, 1.4, zones)
	torch(185.6, 6, 26, props, Vector3.new(1, 0, 0), 16)
	local posternPad =
		box("PosternPad", 188, 3.3, 39, 5, 0.6, 5, Palette.escape, interact, Enum.Material.SmoothPlastic)

	-- ══ BRONN'S HALL (+3) (196..246) ══════════════════════════
	local h = 3
	rampX("HallStairs", 196, 202, -7, 7, 0, h, zones)
	wall("HallStairsWallN", 199, 0, 7.7, 6, 16, 1.4, zones)
	wall("HallStairsWallS", 199, 0, -7.7, 6, 16, 1.4, zones)
	floor("BronnHallFloor", 202, 246, -18, 18, h, zones, Enum.Material.Slate)
	box("BronnHallFloorFill", 224, 0.5, 0, 44, 1, 36, Palette.pitch, zones)
	wall("BronnWallW1", 202, 0, 12.85, 1.4, h + 18, 10.3, zones)
	wall("BronnWallW2", 202, 0, -12.85, 1.4, h + 18, 10.3, zones)
	wall("BronnWallN", 224, 0, 18.7, 45.4, h + 18, 1.4, zones)
	wall("BronnWallS", 224, 0, -18.7, 45.4, h + 18, 1.4, zones)
	wall("BronnWallE", 246.7, 0, 0, 1.4, h + 18, 38.8, zones)
	-- The line you cross to start the fight, at the top of the stairs. Colour is backed by
	-- the stairs, the arch and the banner on entry, never the only signal (art §3).
	decor(box("HallThreshold", 202.6, h + 0.03, 0, 1, 0.06, 14, Palette.bleed, props, Enum.Material.Neon))
	-- Pillars block the charge (G1); side ledges change the elevation. A flat box is a worse fight.
	for _, px in { 212, 224, 236 } do
		pillar(px, h, 12, 18, zones)
		pillar(px, h, -12, 18, zones)
	end
	for _, side in { 1, -1 } do
		box("BronnLedge", 220, h + 0.75, side * 16, 28, 1.5, 4, Palette.stone, zones, Enum.Material.Slate)
		rampX("BronnLedgeRamp", 202.5, 206, side * 14, side * 18, h, h + 1.5, zones)
	end
	-- His dais at the far end: he stands above you, and it reads as his room.
	box("HallDais", 238, h + 0.5, 0, 14, 1, 18, Palette.stone, zones, Enum.Material.Slate)
	banner(246, h + 10, -6, Vector3.new(-1, 0, 0), props)
	banner(246, h + 10, 6, Vector3.new(-1, 0, 0), props)
	banner(218, h + 11, 18, Vector3.new(0, 0, -1), props)
	banner(230, h + 11, -18, Vector3.new(0, 0, 1), props)
	torch(245.6, h + 8, 11, props, Vector3.new(-1, 0, 0))
	torch(245.6, h + 8, -11, props, Vector3.new(-1, 0, 0))
	torch(212, h + 8, 17.6, props, Vector3.new(0, 0, -1))
	torch(212, h + 8, -17.6, props, Vector3.new(0, 0, 1))

	-- ══ SEWERS (-6): south from the vault, west to the pad ═════
	-- Narrow, flooded, claustrophobic. The tension corridor: it must feel unlike anywhere.
	local s = -6
	rampZ("SewerRamp", -34, -20.7, 170, 176, 0, s, zones)
	wall("SewerRampWallW", 169.3, s, -27, 1.4, 16, 14, zones)
	wall("SewerRampWallE", 176.7, s, -27, 1.4, 16, 14, zones)
	floor("SewerFloorS", 170, 176, -90, -34, s, zones, Enum.Material.Concrete)
	ceiling("SewerCeilingS", 170, 176, -90, -34, s + 10, zones)
	wall("SewerWallSW", 169.3, s, -62, 1.4, 10, 56, zones)
	wall("SewerWallSE", 176.7, s, -62, 1.4, 10, 56, zones)
	-- The turn west, and the pad at the far end.
	floor("SewerFloorW", 118, 176, -96, -90, s, zones, Enum.Material.Concrete)
	ceiling("SewerCeilingW", 118, 190, -96, -90, s + 10, zones)
	wall("SewerWallWN", 144, s, -89.3, 52, 10, 1.4, zones)
	wall("SewerWallWS", 154, s, -96.7, 72, 10, 1.4, zones)
	wall("SewerWallEnd", 117.3, s, -93, 1.4, 10, 7.4, zones)
	-- The dark branch east: no torch, a rusted stash at the end (a secret, H5).
	floor("SewerBranchFloor", 176, 190, -96, -90, s, zones, Enum.Material.Concrete)
	wall("SewerBranchWallN", 183.5, s, -89.3, 13, 10, 1.4, zones)
	wall("SewerBranchEnd", 190.7, s, -93, 1.4, 10, 7.4, zones)
	local sewerStash =
		box("SewerStash", 188, s + 0.9, -93, 2.4, 1.8, 2, CHEST_WOOD, interact, Enum.Material.CorrodedMetal)
	-- Water in the channel, both legs.
	P.water("SewerWater", 170.5, 175.5, -90, -34, s + 0.6, props)
	P.water("SewerWaterW", 118, 190, -95.5, -90.5, s + 0.6, props)
	-- A drain line down the middle: the floor reads as a sewer, not another corridor.
	decor(box("SewerChannel", 173, s + 0.05, -62, 1.6, 0.1, 56, Palette.pitch, props, Enum.Material.Glass))
	torch(170.2, s + 5, -44, props, Vector3.new(1, 0, 0), 20)
	torch(175.8, s + 5, -66, props, Vector3.new(-1, 0, 0), 20)
	torch(175.8, s + 5, -86, props, Vector3.new(-1, 0, 0), 20)
	torch(150, s + 5, -89.9, props, Vector3.new(0, 0, -1), 20)
	torch(130, s + 5, -96.1, props, Vector3.new(0, 0, 1), 20)

	-- The escape pad: `escape` green (art §3), dim until the alarm reveals it.
	local extraction = box(
		"ExtractionPad",
		124,
		s + 0.3,
		-93,
		6,
		0.6,
		5,
		Palette.escape,
		interact,
		Enum.Material.SmoothPlastic
	)

	-- ══ HIDEOUT (safe zone) ════════════════════════════════════
	box("HideoutFloor", 0, -0.5, 400, 40, 1, 40, Color3.fromRGB(95, 80, 65), zones, Enum.Material.WoodPlanks)
	box("HideoutWallN", 0, 4, 420.5, 41, 8, 1, WOOD, zones, Enum.Material.WoodPlanks)
	box("HideoutWallS", 0, 4, 379.5, 41, 8, 1, WOOD, zones, Enum.Material.WoodPlanks)
	box("HideoutWallW", -20.5, 4, 400, 1, 8, 40, WOOD, zones, Enum.Material.WoodPlanks)
	box("HideoutWallE", 20.5, 4, 400, 1, 8, 40, WOOD, zones, Enum.Material.WoodPlanks)
	torch(-19, 5, 390, props, Vector3.new(1, 0, 0))
	torch(19, 5, 410, props, Vector3.new(-1, 0, 0))

	local upgradePad = box("UpgradePad", -8, 0.3, 392, 6, 0.6, 6, Palette.gold, interact, Enum.Material.Neon)
	local reenterPad = box("ReenterPad", 8, 0.3, 392, 6, 0.6, 6, Palette.bleed, interact, Enum.Material.Neon)

	-- The weapon rack visibly grows with each weapon upgrade (§16: upgrades change the 3D space).
	local rack = box("WeaponRack", -8, 2, 388, 6, 4, 1, WOOD, props, Enum.Material.WoodPlanks)
	rack.CanCollide = false

	-- Trophy plinth (G3): Bronn's crested helm appears here for players who have killed him.
	-- The plinth is always there; the helm is per-player visible (WorldFXController), since
	-- the hideout is shared and the kill is yours.
	box("TrophyPlinth", 0, 1, 418, 3, 2, 3, Palette.stone, props, Enum.Material.Slate)
	local trophyHelm =
		box("TrophyHelm", 0, 2.75, 418, 1.7, 1.3, 1.7, Palette.stone, props, Enum.Material.Metal)
	decor(trophyHelm)
	trophyHelm.Transparency = 1
	trophyHelm:SetAttribute("Trophy", "captain")
	CollectionService:AddTag(trophyHelm, "PTKTrophy")
	local trophyCrest =
		box("TrophyCrest", 0, 3.9, 418, 0.4, 1.1, 2.1, Palette.bleed, props, Enum.Material.SmoothPlastic)
	decor(trophyCrest)
	trophyCrest.Transparency = 1
	trophyCrest:SetAttribute("Trophy", "captain")
	CollectionService:AddTag(trophyCrest, "PTKTrophy")

	local hideoutSpawn = box("HideoutSpawnMarker", 0, 0.1, 405, 4, 0.2, 4, Color3.fromRGB(95, 80, 65), zones)
	hideoutSpawn.Transparency = 1
	hideoutSpawn.CanCollide = false

	-- ── Secrets that rotate per server (H5): one of these loose bricks is real ──
	local brickSpots = {
		CFrame.new(-15, 2.2, 8), -- the cellblock's middle pier
		CFrame.new(66, 2.2, -6), -- the corridor's south wall
	}
	local liveBrick = brickSpots[math.random(1, #brickSpots)]
	local looseBrick = P.part(
		"LooseBrick",
		liveBrick,
		Vector3.new(1.6, 0.8, 1.6),
		Palette.stone,
		interact,
		Enum.Material.Brick
	)
	looseBrick.CanCollide = false

	local refs = {
		Folder = world,
		Zones = zones,
		Interactables = interact,
		Props = props,
		CellSpawn = spawnPad,
		Chain = chain,
		WeaponPlank = plank,
		SpoonProp = spoon,
		LockedDoor = door,
		BarDoor = barDoor,
		DoorBar = doorBar,
		BarWinch = barWinch,
		ChandelierWinchW = winchW,
		ChandelierWinchE = winchE,
		AlarmBell = alarmBell,
		Chest = chest,
		BarracksChest = barracksChest,
		PosternKey = posternKey,
		PosternGate = posternGate,
		PosternPad = posternPad,
		ChapelRelic = relic,
		Altar = altar,
		SewerStash = sewerStash,
		LooseBrick = looseBrick,
		ExtractionPad = extraction,
		UpgradePad = upgradePad,
		ReenterPad = reenterPad,
		WeaponRack = rack,
		HideoutSpawn = hideoutSpawn,

		-- Named positions other services need
		CellSpawnCFrame = CFrame.new(-40, 4, 0),
		HideoutSpawnCFrame = CFrame.new(0, 4, 405),
		-- Guard room: the patroller (the tutorial fight) and a second guard at the hearth who
		-- only notices you up close.
		PatrolGuardSpawn = CFrame.new(28, g + 3, 0),
		PatrolPointA = Vector3.new(12, g, 0),
		PatrolPointB = Vector3.new(44, g, 0),
		HearthGuardSpawn = CFrame.lookAt(Vector3.new(42, g + 3, 10), Vector3.new(42, g + 3, 14)),
		-- The long hall: two spearmen walking opposite lengths, a sentry on the north balcony
		-- firing across the hall at the kitchen door's line.
		HallPatrolSpawns = {
			{ Spawn = CFrame.new(84, 3, 6), A = Vector3.new(84, 0, 6), B = Vector3.new(128, 0, 6) },
			{ Spawn = CFrame.new(128, 3, -6), A = Vector3.new(128, 0, -6), B = Vector3.new(84, 0, -6) },
		},
		HallSentrySpawn = CFrame.lookAt(
			Vector3.new(106, balcony + 3, 13),
			Vector3.new(106, balcony + 3, -13)
		),
		-- Kitchen: a cook at the hearth, back to the door.
		KitchenGuardSpawn = CFrame.lookAt(Vector3.new(124, 3, 41), Vector3.new(124, 3, 45)),
		-- Barracks: three sleepers on the bunks, a brute between you and the key.
		BarracksSleeperSpawns = {
			CFrame.lookAt(Vector3.new(96, b + 3, -44), Vector3.new(96, b + 3, -40)),
			CFrame.lookAt(Vector3.new(106, b + 3, -44), Vector3.new(106, b + 3, -40)),
			CFrame.lookAt(Vector3.new(116, b + 3, -44), Vector3.new(116, b + 3, -40)),
		},
		BarracksBruteSpawn = CFrame.lookAt(Vector3.new(106, b + 3, -32), Vector3.new(106, b + 3, -21)),
		-- Vault: the archer on the dais, the shield guard between the door and the sewer arch.
		AlarmGuardSpawns = { CFrame.new(152, 3, -15), CFrame.new(190, 3, 15) },
		VaultArcherSpawn = CFrame.lookAt(Vector3.new(181, 4, 17), Vector3.new(160, 4, 0)),
		VaultShieldSpawn = CFrame.new(166, 3, -11),
		VaultShieldPatrolA = Vector3.new(154, 0, -12),
		VaultShieldPatrolB = Vector3.new(186, 0, -12),
		SewerHoundSpawn = CFrame.new(173, s + 3, -60),
		-- Where the wanted system's reinforcements arrive from (L1): doors and stairs,
		-- never where someone died.
		WantedSpawns = {
			CFrame.lookAt(Vector3.new(3, 3, 0), Vector3.new(20, 3, 0)), -- the cellblock arch
			CFrame.lookAt(Vector3.new(52, 3, 0), Vector3.new(66, 3, 0)), -- the corridor ramp
			CFrame.lookAt(Vector3.new(106, 3, 17), Vector3.new(106, 3, 0)), -- the kitchen door
			CFrame.lookAt(Vector3.new(96, 1, -17), Vector3.new(96, 1, 0)), -- the barracks steps
			CFrame.lookAt(Vector3.new(141, 3, 0), Vector3.new(160, 3, 0)), -- the vault passage
			CFrame.lookAt(Vector3.new(141, 3, 19), Vector3.new(150, 3, 15)), -- the vestibule
			CFrame.lookAt(Vector3.new(199, 4, 0), Vector3.new(180, 4, 0)), -- the hall stairs
			CFrame.lookAt(Vector3.new(173, -3, -30), Vector3.new(173, -3, -60)), -- the sewer ramp
		},

		-- Captain Bronn: on his dais, facing west down the sightline to the cellblock door.
		CaptainSpawn = CFrame.lookAt(Vector3.new(238, h + 1 + 3.6, 0), Vector3.new(76, h + 1 + 3.6, 0)),
		CaptainReinforcementSpawn = CFrame.new(242, h + 3, 14),
		-- Fight zone: the hall floor east of the threshold, full room height.
		CaptainArena = { Min = Vector3.new(202, 0, -18), Max = Vector3.new(246, h + 22, 18) },

		-- Rooms (RoomService): entered-room tracking for progress, analytics and ambience.
		-- Boxes are generous so stairs count.
		Rooms = {
			{ Name = "THE CELLS", Min = Vector3.new(-46, -2, -10), Max = Vector3.new(0, 14, 18) },
			{ Name = "THE GUARD ROOM", Min = Vector3.new(8, 0, -15), Max = Vector3.new(48, 18, 15) },
			{ Name = "THE LONG HALL", Min = Vector3.new(76, -2, -15), Max = Vector3.new(136, 26, 15) },
			{ Name = "THE KITCHENS", Min = Vector3.new(96, -2, 15), Max = Vector3.new(146, 16, 46) },
			{ Name = "THE BARRACKS", Min = Vector3.new(86, -5, -48), Max = Vector3.new(126, 12, -15) },
			{ Name = "THE VAULT", Min = Vector3.new(146, -2, -20), Max = Vector3.new(196, 18, 20) },
			{
				Name = "THE CHAPEL",
				Min = Vector3.new(150, -1, 21),
				Max = Vector3.new(170, 16, 41),
				Secret = true,
			},
			{ Name = "THE POSTERN", Min = Vector3.new(185, -1, 21), Max = Vector3.new(191, 14, 42) },
			{ Name = "BRONN'S HALL", Min = Vector3.new(196, 0, -18), Max = Vector3.new(246, 26, 18) },
			{ Name = "THE SEWERS", Min = Vector3.new(117, -9, -97), Max = Vector3.new(191, 5, -20) },
		},
	}

	-- Props, clutter, prisoners, rats, treasure, chandeliers, bunks, candles, the ghost.
	WorldDressing.Dress(
		refs,
		{ Guard = g, Barracks = b, Chapel = c, Bronn = h, Sewer = s, Balcony = balcony }
	)

	return refs
end

return WorldBuilder
