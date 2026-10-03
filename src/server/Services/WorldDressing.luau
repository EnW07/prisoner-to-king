--!strict
-- WorldDressing.lua
-- Not a service: fills the rooms WorldBuilder lays out. Props, clutter, prisoners, rats,
-- treasure, bunks, candles, chandeliers, the ghost knight. Everything here is set
-- dressing or a tagged interactable; nothing here has logic. (MASTER_BUILD_SPEC H1, H4, H5.)
--
-- Tags other code reads:
--   PTKBreakable   crates and barrels a swing breaks (EnvironmentService); attribute
--                  Breakable = "crate" | "barrel"
--   PTKChandelier  a chandelier EnvironmentService can drop; attribute Winch names its winch
--   PTKTorch       flames the client flickers (WorldParts)
--   PTKWater       the client ripples it
--   PTKGhost       the client fades it in and out
--   PTKRat         the client scurries it between two points (attributes A, B)
--   PTKDrip        the client drips water from it

local CollectionService = game:GetService("CollectionService")

local Palette = require(game.ReplicatedStorage.Shared.Config.Palette)
local RigFactory = require(script.Parent.RigFactory)
local EnemyConfig = require(game.ReplicatedStorage.Shared.Config.EnemyConfig)
local P = require(script.Parent.WorldParts)

local WorldDressing = {}

local box, decor, torch, candle = P.box, P.decor, P.torch, P.candle
local WOOD, STRAW, CLOTH = P.WOOD, P.STRAW, P.CLOTH

-- A static prisoner: a rig from the sleepy guard template, recoloured, posed sitting
-- against a wall, anchored, no AI. A prop with a silhouette, not an enemy.
local function prisoner(parent: Instance, cf: CFrame)
	local cfg = EnemyConfig.Get("sleepy_guard")
	if not cfg then
		return
	end
	local ok, model = pcall(RigFactory.Build, "sleepy_guard", cfg)
	if not ok or not model then
		return
	end
	model.Name = "Prisoner"
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			if d.Color == cfg.BodyColor then
				d.Color = CLOTH
			end
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		elseif d:IsA("BillboardGui") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local blade = model:FindFirstChild("Blade")
	if blade then
		blade:Destroy()
	end
	-- Slumped: the whole rig tilted back against the wall and lowered as if seated.
	model:PivotTo(cf * CFrame.new(0, -1.1, 0) * CFrame.Angles(math.rad(-20), 0, 0))
	model.Parent = parent
end

local function rat(parent: Instance, a: Vector3, b: Vector3)
	local r =
		box("Rat", a.X, a.Y + 0.25, a.Z, 0.8, 0.4, 0.5, Palette.pitch, parent, Enum.Material.SmoothPlastic)
	decor(r)
	r:SetAttribute("A", a)
	r:SetAttribute("B", b)
	CollectionService:AddTag(r, "PTKRat")
	local tail = box(
		"RatTail",
		a.X,
		a.Y + 0.2,
		a.Z + 0.6,
		0.12,
		0.12,
		0.8,
		Palette.pitch,
		parent,
		Enum.Material.SmoothPlastic
	)
	decor(tail)
	tail.Parent = r -- moves with the rat
end

local function drip(parent: Instance, x: number, y: number, z: number)
	local d = box("Drip", x, y, z, 0.15, 0.15, 0.15, Palette.stone, parent, Enum.Material.Glass)
	decor(d)
	d.Transparency = 0.3
	d:SetAttribute("Top", y)
	CollectionService:AddTag(d, "PTKDrip")
end

local function hayPile(parent: Instance, x: number, floorY: number, z: number)
	decor(box("Hay", x, floorY + 0.35, z, 3.2, 0.7, 2.6, STRAW, parent, Enum.Material.Grass))
end

local function hearth(parent: Instance, x: number, floorY: number, z: number, facing: Vector3)
	-- A stone surround on the wall, embers, a bigger light: the guard room's colour note.
	local back = Vector3.new(x, floorY, z) - facing * 0.4
	box("HearthSurround", back.X, floorY + 2.5, back.Z, 6, 5, 1.2, Palette.stone, parent, Enum.Material.Slate)
	decor(
		box(
			"HearthMantel",
			back.X,
			floorY + 5.2,
			back.Z,
			7,
			0.5,
			2,
			Palette.stone,
			parent,
			Enum.Material.Slate
		)
	)
	local embers = box("Embers", x, floorY + 0.4, z, 3.6, 0.6, 1.6, Palette.ember, parent, Enum.Material.Neon)
	decor(embers)
	local light = Instance.new("PointLight")
	light.Color = Palette.ember
	light.Brightness = 3.5
	light.Range = 30
	light.Shadows = false
	light.Parent = embers
	CollectionService:AddTag(embers, "PTKTorch")
	local fire = Instance.new("Fire")
	fire.Color = Palette.ember
	fire.SecondaryColor = Palette.bleed
	fire.Size = 6
	fire.Heat = 9
	fire.Parent = embers
end

local function weaponRack(parent: Instance, x: number, floorY: number, z: number, facing: Vector3)
	local back = Vector3.new(x, floorY, z) - facing * 0.3
	box("Rack", back.X, floorY + 2.6, back.Z, 5, 4.4, 0.5, WOOD, parent, Enum.Material.WoodPlanks)
	for i = -1, 1 do
		local p = Vector3.new(x, floorY, z) + Vector3.new(-facing.Z, 0, facing.X) * (i * 1.4)
		decor(
			box("RackSpear", p.X, floorY + 2.6, p.Z, 0.25, 5, 0.25, Palette.pitch, parent, Enum.Material.Wood)
		)
		decor(
			box(
				"RackSpearhead",
				p.X,
				floorY + 5.3,
				p.Z,
				0.5,
				0.9,
				0.2,
				Palette.stone,
				parent,
				Enum.Material.Metal
			)
		)
	end
end

local function bunk(parent: Instance, x: number, floorY: number, z: number)
	box("BunkFrame", x, floorY + 0.5, z, 3, 1, 7, WOOD, parent, Enum.Material.WoodPlanks)
	decor(box("BunkStraw", x, floorY + 1.15, z, 2.8, 0.3, 6.6, STRAW, parent, Enum.Material.Grass))
	decor(box("BunkBlanket", x, floorY + 1.35, z + 0.8, 2.6, 0.15, 4.4, CLOTH, parent, Enum.Material.Fabric))
end

local function treasurePile(parent: Instance, x: number, floorY: number, z: number, size: number)
	local pile = box(
		"TreasurePile",
		x,
		floorY + size * 0.3,
		z,
		size,
		size * 0.6,
		size * 0.9,
		Palette.gold,
		parent,
		Enum.Material.Metal
	)
	decor(pile)
	pile.Orientation = Vector3.new(0, math.random(0, 90), 0)
	decor(
		box(
			"TreasureGlint",
			x,
			floorY + size * 0.62,
			z,
			size * 0.35,
			0.2,
			size * 0.35,
			Palette.gold,
			parent,
			Enum.Material.Neon
		)
	)
end

local function chandelier(parent: Instance, name: string, x: number, y: number, z: number, winch: BasePart)
	local hub = box(name, x, y, z, 5, 0.5, 5, Palette.pitch, parent, Enum.Material.Metal)
	hub.CanCollide = false
	for i = 1, 6 do
		local a = i / 6 * 2 * math.pi
		local cx, cz = x + math.cos(a) * 2.1, z + math.sin(a) * 2.1
		local c = box(
			"ChandelierCandle",
			cx,
			y + 0.6,
			cz,
			0.3,
			0.7,
			0.3,
			Color3.fromRGB(235, 225, 200),
			parent,
			Enum.Material.SmoothPlastic
		)
		decor(c)
		c.Parent = hub
		local flame =
			box("Flame", cx, y + 1.1, cz, 0.25, 0.35, 0.25, Palette.ember, parent, Enum.Material.Neon)
		decor(flame)
		flame.CastShadow = false
		flame.Parent = hub
		CollectionService:AddTag(flame, "PTKTorch")
	end
	local light = Instance.new("PointLight")
	light.Color = Palette.ember
	light.Brightness = 2
	light.Range = 24
	light.Shadows = false
	light.Parent = hub
	local chainPart =
		box(name .. "Chain", x, y + 5, z, 0.3, 10, 0.3, Palette.pitch, parent, Enum.Material.Metal)
	decor(chainPart)
	chainPart.Parent = hub
	hub:SetAttribute("Winch", winch.Name)
	hub:SetAttribute("RestY", y)
	CollectionService:AddTag(hub, "PTKChandelier")
	return hub
end

-- A translucent knight in a dark corner, standing watch. Fades in and out (client).
local function ghostKnight(parent: Instance, cf: CFrame)
	local cfg = EnemyConfig.Get("alarm_guard")
	if not cfg then
		return
	end
	local ok, model = pcall(RigFactory.Build, "alarm_guard", cfg)
	if not ok or not model then
		return
	end
	model.Name = "GhostKnight"
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Color = Palette.stone
			d.Material = Enum.Material.ForceField
			d.Transparency = 0.6
			d.CastShadow = false
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		elseif d:IsA("BillboardGui") or d:IsA("Decal") then
			d:Destroy()
		end
	end
	model:PivotTo(cf)
	model.Parent = parent
	CollectionService:AddTag(model, "PTKGhost")
end

-- `levels` are the floor heights WorldBuilder used.
function WorldDressing.Dress(refs, levels)
	local props: Folder = refs.Props
	local interact: Folder = refs.Interactables
	local g, b, c, h, s = levels.Guard, levels.Barracks, levels.Chapel, levels.Bronn, levels.Sewer

	-- ══ THE CELLS: cramped, oppressive. Other prisoners, dripping water, rats ══
	prisoner(props, CFrame.lookAt(Vector3.new(-20, 3.6, 14), Vector3.new(-20, 3.6, 0)))
	prisoner(props, CFrame.lookAt(Vector3.new(-9, 3.6, 14), Vector3.new(-9, 3.6, 0)))
	hayPile(props, -22, 0, 11)
	hayPile(props, -7, 0, 12)
	hayPile(props, -41, 0, -5)
	for _, pos in { Vector3.new(-33, 11.4, -6), Vector3.new(-12, 13.4, 5) } do
		drip(props, pos.X, pos.Y, pos.Z)
	end
	rat(props, Vector3.new(-30, 0, -6), Vector3.new(-16, 0, -6))
	rat(props, Vector3.new(-6, 0, 6), Vector3.new(-2, 0, -4))
	-- A bucket and chains: props that say "cell" at a glance.
	decor(box("Bucket", -41, 0.5, 6, 1, 1, 1, Palette.pitch, props, Enum.Material.Metal))
	decor(box("WallChain", -44, 5, -4, 0.3, 4, 0.3, Palette.pitch, props, Enum.Material.Metal))

	-- ══ THE GUARD ROOM: tables, weapon racks, a hearth; sightlines to plan ══
	hearth(props, 42, g, 14, Vector3.new(0, 0, -1))
	P.table_(22, g, 4, 6, 3, props)
	P.table_(34, g, -6, 6, 3, props, math.rad(15))
	weaponRack(props, 14, g, -14, Vector3.new(0, 0, 1))
	weaponRack(props, 28, g, 14, Vector3.new(0, 0, -1))
	for i = 1, 3 do
		decor(
			box(
				"Tankard",
				20 + i * 1.3,
				g + 2.9,
				4 + (i % 2) * 0.6,
				0.5,
				0.6,
				0.5,
				Palette.pitch,
				props,
				Enum.Material.Metal
			)
		)
	end
	P.crate(44, g, -10, 2.2, props, true)
	P.barrel(12, g, 10, props, true)

	-- ══ THE LONG HALL: chandeliers to drop (H4), crates for cover ══
	chandelier(props, "ChandelierW", 92, 14, 0, refs.ChandelierWinchW)
	chandelier(props, "ChandelierE", 120, 14, 0, refs.ChandelierWinchE)
	P.crate(98, 0, -12, 2.6, props, true)
	P.crate(100, 0, -12, 2.2, props, true)
	P.barrel(114, 0, 12, props, true)
	P.barrel(116, 0, 12, props, true)
	P.crate(116, 0, 10, 2.4, props, false)

	-- ══ KITCHEN / STORES: clutter, barrels and crates with loot inside ══
	hearth(props, 124, 0, 45, Vector3.new(0, 0, -1))
	P.table_(106, 0, 30, 10, 3.5, props)
	P.table_(120, 0, 24, 5, 3, props, math.rad(-20))
	for i, pos in { { 99, 42 }, { 102, 42 }, { 99, 38 }, { 132, 20 }, { 132, 24 }, { 128, 42 } } do
		if i % 2 == 0 then
			P.barrel(pos[1], 0, pos[2], props, true)
		else
			P.crate(pos[1], 0, pos[2], 2.4, props, true)
		end
	end
	P.crate(110, 0, 42, 3, props, true)
	P.crate(110, 3, 42, 2, props, true) -- stacked
	for i = 1, 4 do
		decor(box("Loaf", 102 + i * 1.6, 2.9, 30, 1, 0.5, 0.6, STRAW, props, Enum.Material.Sand))
	end
	decor(box("Cauldron", 124, 1.2, 42.5, 2.2, 1.8, 2.2, Palette.pitch, props, Enum.Material.Metal))
	rat(props, Vector3.new(98, 0, 18), Vector3.new(130, 0, 18))

	-- ══ THE BARRACKS: bunks, candles, a weapon chest; the sleepers lie here ══
	for _, x in { 96, 106, 116 } do
		bunk(props, x, b, -43.5)
		candle(x + 2.2, b + 2.6, -40, props)
		decor(box("Nightstand", x + 2.2, b + 1.2, -40, 1.4, 2.4, 1.4, WOOD, props, Enum.Material.Wood))
	end
	weaponRack(props, 110, b, -47, Vector3.new(0, 0, 1))
	P.table_(118, b, -30, 5, 3, props, math.rad(30))
	P.crate(88, b, -24, 2.2, props, true)

	-- ══ THE VAULT: treasure piles around the dais ══
	for _, pile in
		{
			{ 166, 18, 3 },
			{ 184, 18, 3.4 },
			{ 170, 13, 2.2 },
			{ 180, 13, 2.4 },
			{ 150, 16, 2.6 },
			{ 192, -16, 2.8 },
		}
	do
		treasurePile(
			props,
			pile[1],
			if pile[2] > 12 and pile[1] > 166 and pile[1] < 184 then 1.5 else 0,
			pile[2],
			pile[3]
		)
	end
	P.crate(150, 0, -17, 2.4, props, true)
	P.barrel(192, 0, -14, props, true)

	-- ══ THE CHAPEL: candles, pews, a ghost in the dark corner ══
	for _, pos in { { 157, 37 }, { 163, 37 }, { 153, 30 }, { 167, 30 }, { 155, 25 }, { 165, 25 } } do
		candle(pos[1], c, pos[2], props)
	end
	for _, z in { 27, 31 } do
		box("Pew", 156, c + 0.6, z, 5, 1.2, 1, WOOD, props, Enum.Material.WoodPlanks)
		box("Pew", 164, c + 0.6, z, 5, 1.2, 1, WOOD, props, Enum.Material.WoodPlanks)
	end
	ghostKnight(props, CFrame.lookAt(Vector3.new(152.5, c + 3.6, 39), Vector3.new(160, c + 3.6, 30)))

	-- ══ BRONN'S HALL: nothing extra. The pillars and ledges are the fight. ══

	-- ══ THE SEWERS: a grate, drips, rats; the branch stays dark ══
	P.bars("SewerGrate", -75, 170.5, 175.5, true, s, 4, props)
	for _, z in { -50, -70, -84 } do
		drip(props, 173 + (z % 3) - 1, s + 9.4, z)
	end
	drip(props, 140, s + 9.4, -93)
	rat(props, Vector3.new(171, s, -40), Vector3.new(171, s, -80))
	rat(props, Vector3.new(182, s, -92), Vector3.new(188, s, -92))

	-- ══ SIGNPOSTS: light tells you where to go. Dead ends stay dark. ══
	-- (Nothing to add here: torches are placed with the rooms. This note is the rule.)
	return refs
end

return WorldDressing
