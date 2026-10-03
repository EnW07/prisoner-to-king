--!strict
-- WorldBuilder.lua
-- Builds the whole playable world from code at runtime: no manual Studio building, no
-- imported meshes, no marketplace assets. Primitives, WedgeParts and cylinders only.
--
-- WHY: so the loop is testable with zero manual Studio work. When real art exists, replace
-- this module with a streamed static map and keep the same reference names; nothing else in
-- the codebase needs to change. Every name in the returned table is load-bearing.
--
-- Layout (top-down, +X is deeper into the castle). Floor heights in brackets.
--
--   YOUR CELL ─bars─ CELLBLOCK HALL ─ramp↑─ GUARD ROOM [+3] ─ramp↓─ CORRIDOR ─[LOCKED DOOR]─▶
--   (-44..-28)       (-28..0)                (8..48)                (56..76)
--
--   ▶ VAULT (76..126) ═arch═ stairs↑ CAPTAIN'S HALL [+3] (126..176)
--        │ sewer arch, south wall
--        ▼ ramp↓ SEWER [-6] ── ESCAPE PAD
--
--   HIDEOUT sits far away at z = 400 (separate safe area, same place file — §77).
--
-- Sightlines (VISUAL_OVERHAUL_PLAN Phase 3): the cellblock door, the vault, the hall arch
-- and Bronn's dais are all on z = 0. Bronn stands raised at the far end, so he is in view
-- the moment the door opens on run 1. The treasure dais sits in the vault's light shafts,
-- and the sewer arch is the only south opening, so the way out reads at a glance.
-- Bronn never leaves his hall, so he can't block the chest or the escape (§115).
--
-- Colour: palette tokens only (art §3). `stone` walls, `pitch` floors and iron, `ember`
-- light, `bleed` only for danger (the hall threshold, Bronn's banners). Wood keeps its
-- original M1 value; the palette has no wood token. Variety comes from Materials, not hues.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local Palette = require(game.ReplicatedStorage.Shared.Config.Palette)

local WorldBuilder = {}

local WOOD = Color3.fromRGB(110, 75, 45) -- M1 value, kept: no palette token for wood
local CHEST_WOOD = Color3.fromRGB(120, 85, 50) -- M1 value, kept

-- ── Primitive helpers ───────────────────────────────────────────
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

local function wedge(
	name: string,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	parent: Instance,
	material: Enum.Material?
): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = material or Enum.Material.Slate
	w.Parent = parent
	return w
end

-- Decorative: never blocks movement, a raycast, a swing, or a loot drop.
local function decor(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- Floor slab whose TOP surface is at `top`.
local function floor(
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	top: number,
	parent: Instance,
	material: Enum.Material?
): Part
	local depth = 2
	return box(
		name,
		(x0 + x1) / 2,
		top - depth / 2,
		(z0 + z1) / 2,
		x1 - x0,
		depth,
		z1 - z0,
		Palette.pitch,
		parent,
		material or Enum.Material.Cobblestone
	)
end

-- A ramp rising along +X from `bottom` at x0 to `top` at x1 (or falling, if top < bottom).
local function rampX(
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	bottom: number,
	top: number,
	parent: Instance
)
	local rise = top - bottom
	local run = x1 - x0
	local width = z1 - z0
	-- WedgePart: the slope rises toward local +Z. Turn local +Z to world +X (or -X if falling).
	local yaw = if rise >= 0 then math.rad(90) else math.rad(-90)
	local h = math.abs(rise)
	local low = math.min(bottom, top)
	local cf = CFrame.new((x0 + x1) / 2, low + h / 2, (z0 + z1) / 2) * CFrame.Angles(0, yaw, 0)
	wedge(name, cf, Vector3.new(width, h, run), Palette.pitch, parent, Enum.Material.Cobblestone)
end

-- Same as rampX but along -Z (used for the sewer descent).
local function rampZ(
	name: string,
	z0: number,
	z1: number,
	x0: number,
	x1: number,
	high: number,
	low: number,
	parent: Instance
)
	local h = high - low
	-- Slope rises toward local +Z; no yaw needed since the high end is at the larger z.
	local cf = CFrame.new((x0 + x1) / 2, low + h / 2, (z0 + z1) / 2)
	wedge(name, cf, Vector3.new(x1 - x0, h, z1 - z0), Palette.pitch, parent, Enum.Material.Cobblestone)
end

-- A straight wall with an arched opening. The wall runs along local Z of `frame` (frame is
-- at floor level, centred on the wall); thickness is along local X.
--   alongX = true  → the wall runs along world X (turned 90° about Y).
-- The arch is two corner wedges inside the opening: a pointed, castle-like doorway.
local function archWall(
	name: string,
	cx: number,
	floorY: number,
	cz: number,
	alongX: boolean,
	length: number,
	height: number,
	openWidth: number,
	openHeight: number,
	archSize: number,
	parent: Instance,
	openOffset: number?
)
	local frame = CFrame.new(cx, floorY, cz)
		* (if alongX then CFrame.Angles(0, math.rad(90), 0) else CFrame.new())
	local thick = 1.4
	local oc = openOffset or 0
	local left0, left1 = -length / 2, oc - openWidth / 2
	local right0, right1 = oc + openWidth / 2, length / 2
	local mat = Enum.Material.Brick

	if left1 - left0 > 0.05 then
		part(
			name .. "L",
			frame * CFrame.new(0, height / 2, (left0 + left1) / 2),
			Vector3.new(thick, height, left1 - left0),
			Palette.stone,
			parent,
			mat
		)
	end
	if right1 - right0 > 0.05 then
		part(
			name .. "R",
			frame * CFrame.new(0, height / 2, (right0 + right1) / 2),
			Vector3.new(thick, height, right1 - right0),
			Palette.stone,
			parent,
			mat
		)
	end
	part(
		name .. "Lintel",
		frame * CFrame.new(0, (openHeight + height) / 2, oc),
		Vector3.new(thick, height - openHeight, openWidth),
		Palette.stone,
		parent,
		mat
	)
	-- Corner wedges. Default WedgePart has its right angle at bottom/+Z; rotating 180° about
	-- X puts it at top/-Z (the left corner), 180° about Z puts it at top/+Z (the right corner).
	local a = archSize
	wedge(
		name .. "ArchL",
		frame * CFrame.new(0, openHeight - a / 2, oc - openWidth / 2 + a / 2) * CFrame.Angles(math.pi, 0, 0),
		Vector3.new(thick, a, a),
		Palette.stone,
		parent,
		mat
	)
	wedge(
		name .. "ArchR",
		frame * CFrame.new(0, openHeight - a / 2, oc + openWidth / 2 - a / 2) * CFrame.Angles(0, 0, math.pi),
		Vector3.new(thick, a, a),
		Palette.stone,
		parent,
		mat
	)
end

-- A solid wall along world X or Z, bottom at floorY.
local function wall(
	name: string,
	x: number,
	floorY: number,
	z: number,
	sx: number,
	height: number,
	sz: number,
	parent: Instance
): Part
	return box(name, x, floorY + height / 2, z, sx, height, sz, Palette.stone, parent, Enum.Material.Brick)
end

-- Round pillar with a square base and capital. Collidable: something to fight around.
local function pillar(x: number, floorY: number, z: number, height: number, parent: Instance)
	local r = 1.2
	box(
		"PillarBase",
		x,
		floorY + 0.4,
		z,
		r * 2 + 0.8,
		0.8,
		r * 2 + 0.8,
		Palette.stone,
		parent,
		Enum.Material.Slate
	)
	part(
		"Pillar",
		CFrame.new(x, floorY + height / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(height, r * 2, r * 2),
		Palette.stone,
		parent,
		Enum.Material.Cobblestone
	).Shape =
		Enum.PartType.Cylinder
	box(
		"PillarCapital",
		x,
		floorY + height - 0.4,
		z,
		r * 2 + 0.8,
		0.8,
		r * 2 + 0.8,
		Palette.stone,
		parent,
		Enum.Material.Slate
	)
end

-- Iron bars along world X (alongX) or Z, from a to b, skipping any [gap0, gap1] span.
local function bars(
	name: string,
	fixed: number,
	a: number,
	b: number,
	alongX: boolean,
	floorY: number,
	height: number,
	parent: Instance,
	gap0: number?,
	gap1: number?
)
	local spacing = 1.1
	local n = math.floor((b - a) / spacing)
	for i = 0, n do
		local t = a + i * spacing
		if not (gap0 and gap1 and t > gap0 and t < gap1) then
			local x = if alongX then t else fixed
			local z = if alongX then fixed else t
			part(
				name,
				CFrame.new(x, floorY + height / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
				Vector3.new(height, 0.35, 0.35),
				Palette.pitch,
				parent,
				Enum.Material.Metal
			).Shape =
				Enum.PartType.Cylinder
		end
	end
	-- Top and bottom rails. No bottom rail across a doorway gap: nothing to trip on.
	local railYs = if gap0 then { floorY + height - 0.3 } else { floorY + 0.3, floorY + height - 0.3 }
	for _, y in railYs do
		local cx = if alongX then (a + b) / 2 else fixed
		local cz = if alongX then fixed else (a + b) / 2
		local sx = if alongX then b - a else 0.4
		local sz = if alongX then 0.4 else b - a
		box(name .. "Rail", cx, y, cz, sx, 0.4, sz, Palette.pitch, parent, Enum.Material.Metal)
	end
end

-- Wall torch on an iron sconce. `out` points from the wall into the room.
local function torch(x: number, y: number, z: number, parent: Instance, out: Vector3?)
	local o = out or Vector3.zero
	if o.Magnitude > 0 then
		-- The bracket: an iron plate on the wall and an arm reaching out to the torch.
		local plate = Vector3.new(x, y, z) - o * 0.55
		decor(
			box(
				"SconcePlate",
				plate.X,
				plate.Y,
				plate.Z,
				0.8,
				1.2,
				0.8,
				Palette.pitch,
				parent,
				Enum.Material.Metal
			)
		)
		local arm = Vector3.new(x, y - 0.5, z) - o * 0.3
		decor(
			box("SconceArm", arm.X, arm.Y, arm.Z, 0.5, 0.25, 0.5, Palette.pitch, parent, Enum.Material.Metal)
		)
	end
	local handle =
		box("Torch", x, y, z, 0.4, 1.2, 0.4, Color3.fromRGB(90, 60, 40), parent, Enum.Material.Wood)
	decor(handle)
	-- A visible flame, so the light has a source. Clients flicker it (WorldFXController).
	local flame = box("Flame", x, y + 0.9, z, 0.5, 0.7, 0.5, Palette.ember, parent, Enum.Material.Neon)
	decor(flame)
	flame.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = Palette.ember
	light.Brightness = 2.4
	light.Range = 26
	light.Shadows = false -- shadow-casting lights are too costly on low-end phones (§41)
	light.Parent = flame
	CollectionService:AddTag(flame, "PTKTorch")
end

-- A window slit high in a wall, with a shaft of dusk light falling into the room.
-- `out` points from the wall into the room; the shaft slants down along it.
local function windowSlit(x: number, y: number, z: number, out: Vector3, parent: Instance)
	local across = Vector3.new(-out.Z, 0, out.X) -- along the wall
	local slitCF = CFrame.fromMatrix(Vector3.new(x, y, z), across, Vector3.yAxis, -out)
	local slit = decor(
		part("WindowSlit", slitCF, Vector3.new(0.9, 3.2, 0.3), Palette.ember, parent, Enum.Material.Neon)
	)
	slit.CastShadow = false

	-- The shaft: a long, faint slab tilted ~50° down into the room.
	local length = 16
	local tilt = math.rad(50)
	local dir = (out * math.cos(tilt) - Vector3.yAxis * math.sin(tilt)).Unit
	local centre = Vector3.new(x, y, z) + dir * (length / 2)
	local shaftCF = CFrame.lookAt(centre, centre + dir)
	local shaft = decor(
		part("LightShaft", shaftCF, Vector3.new(1.2, 3, length), Palette.ember, parent, Enum.Material.Neon)
	)
	shaft.Transparency = 0.93
	shaft.CastShadow = false

	local light = Instance.new("SpotLight")
	light.Color = Palette.ember
	light.Brightness = 3
	light.Range = 22
	light.Angle = 35
	light.Face = Enum.NormalId.Front
	light.Parent = slit
end

-- A hanging cloth banner on a wall. Bronn's hall only: `bleed` marks danger.
local function banner(x: number, y: number, z: number, out: Vector3, parent: Instance)
	local across = Vector3.new(-out.Z, 0, out.X)
	local cf = CFrame.fromMatrix(Vector3.new(x, y, z) + out * 0.8, across, Vector3.yAxis, -out)
	decor(part("Banner", cf, Vector3.new(3, 7, 0.2), Palette.bleed, parent, Enum.Material.Fabric))
	decor(
		part(
			"BannerRod",
			cf * CFrame.new(0, 3.6, 0),
			Vector3.new(3.8, 0.3, 0.3),
			Palette.pitch,
			parent,
			Enum.Material.Metal
		)
	)
	-- Swallowtail: two wedges hanging off the bottom edge.
	for _, side in { -1, 1 } do
		decor(
			wedge(
				"BannerTail",
				cf * CFrame.new(side * 0.75, -4.25, 0) * CFrame.Angles(0, math.rad(90), math.pi),
				Vector3.new(0.2, 1.5, 1.5),
				Palette.bleed,
				parent,
				Enum.Material.Fabric
			)
		)
	end
end

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
	torch(-43.6, 7, 4, props, Vector3.new(1, 0, 0))
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

	-- ══ GUARD ROOM (+3) ════════════════════════════════════════
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
	for _, px in { 18, 28, 38 } do
		pillar(px, g, 8, 14, zones)
		pillar(px, g, -8, 14, zones)
	end
	windowSlit(18, g + 9, 13.9, Vector3.new(0, 0, -1), props)
	windowSlit(38, g + 9, 13.9, Vector3.new(0, 0, -1), props)
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

	-- ══ LOCKED CELLBLOCK DOOR (arched) ═════════════════════════
	-- Thinner than the arch wall, so the arch's corner wedges frame its top.
	archWall("DoorWall", 76, 0, 0, false, 14.8, 14, 6, 10, 2, zones)
	local door = box("LockedDoor", 76, 5, 0, 0.6, 10, 6, WOOD, interact, Enum.Material.WoodPlanks)

	-- ══ VAULT ══════════════════════════════════════════════════
	floor("VaultFloor", 76, 126, -20, 20, 0, zones)
	wall("VaultWallWN", 76, 0, 13.6, 1.4, 16, 12.8, zones)
	wall("VaultWallWS", 76, 0, -13.6, 1.4, 16, 12.8, zones)
	wall("VaultWallN", 101, 0, 20.7, 51.4, 16, 1.4, zones)
	-- South wall: the sewer arch at x = 100..106.
	archWall("VaultWallS", 101, 0, -20.7, true, 51.4, 16, 6, 9, 2, zones, 2)
	-- East wall: the great arch into Bronn's hall, on the door's sightline.
	archWall("VaultWallE", 126, 0, 0, false, 41.4, 16, 14, 13, 3, zones)
	-- Pillars flank the room, clear of the treasure dais (x 97..113) and the z = 0 sightline.
	for _, px in { 86, 118 } do
		pillar(px, 0, 12, 16, zones)
		pillar(px, 0, -12, 16, zones)
	end
	-- The treasure dais, lit by the vault's two window shafts: the valuable thing is
	-- literally in the light (art §2 screenshot test).
	box("TreasureDais", 105, 0.75, 16, 16, 1.5, 7, Palette.stone, zones, Enum.Material.Slate)
	rampZ("TreasureStep", 11.5, 12.5, 97, 113, 1.5, 0, zones)
	windowSlit(99, 11, 19.9, Vector3.new(0, 0, -1), props)
	windowSlit(111, 11, 19.9, Vector3.new(0, 0, -1), props)
	torch(77.2, 8, 9, props, Vector3.new(1, 0, 0))
	torch(77.2, 8, -9, props, Vector3.new(1, 0, 0))
	torch(124.8, 8, 12, props, Vector3.new(-1, 0, 0))
	torch(124.8, 8, -12, props, Vector3.new(-1, 0, 0))

	-- Base + separate lid, so the lid can hinge open. The lid is per-player visual state
	-- (each run's chest is its own), so clients open it locally (WorldFXController); the
	-- server never moves it. Gold bands: it's the valuable thing (art §3 `gold`).
	local chestY = 1.5
	local chest =
		box("Chest", 105, chestY + 1.1, 16, 4, 2.2, 3, CHEST_WOOD, interact, Enum.Material.WoodPlanks)
	for _, bx in { -1.3, 1.3 } do
		decor(
			box(
				"ChestBand",
				105 + bx,
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
		box("ChestLid", 105, chestY + 2.6, 16, 4.2, 0.8, 3.2, CHEST_WOOD, props, Enum.Material.WoodPlanks)
	chestLid.CanCollide = false
	CollectionService:AddTag(chestLid, "PTKChestLid")

	-- ══ CAPTAIN'S HALL (+3) ════════════════════════════════════
	local h = 3
	rampX("HallStairs", 126, 132, -7, 7, 0, h, zones)
	wall("HallStairsWallN", 129, 0, 7.7, 6, 16, 1.4, zones)
	wall("HallStairsWallS", 129, 0, -7.7, 6, 16, 1.4, zones)
	floor("HallFloor", 132, 176, -18, 18, h, zones, Enum.Material.Slate)
	box("HallFloorFill", 154, 0.5, 0, 44, 1, 36, Palette.pitch, zones)
	wall("HallWallW1", 132, 0, 12.85, 1.4, h + 18, 10.3, zones)
	wall("HallWallW2", 132, 0, -12.85, 1.4, h + 18, 10.3, zones)
	wall("HallWallN", 154, 0, 18.7, 45.4, h + 18, 1.4, zones)
	wall("HallWallS", 154, 0, -18.7, 45.4, h + 18, 1.4, zones)
	wall("HallWallE", 176.7, 0, 0, 1.4, h + 18, 38.8, zones)
	-- The line you cross to start the fight, at the top of the stairs. Colour is backed by
	-- the stairs, the arch and the banner on entry, never the only signal (art §3).
	decor(box("HallThreshold", 132.6, h + 0.03, 0, 1, 0.06, 14, Palette.bleed, props, Enum.Material.Neon))
	for _, px in { 142, 154, 166 } do
		pillar(px, h, 12, 18, zones)
		pillar(px, h, -12, 18, zones)
	end
	-- His dais at the far end: he stands above you, and it reads as his room.
	box("HallDais", 168, h + 0.5, 0, 14, 1, 18, Palette.stone, zones, Enum.Material.Slate)
	banner(176, h + 10, -6, Vector3.new(-1, 0, 0), props)
	banner(176, h + 10, 6, Vector3.new(-1, 0, 0), props)
	banner(148, h + 11, 18, Vector3.new(0, 0, -1), props)
	banner(160, h + 11, -18, Vector3.new(0, 0, 1), props)
	torch(175.6, h + 8, 11, props, Vector3.new(-1, 0, 0))
	torch(175.6, h + 8, -11, props, Vector3.new(-1, 0, 0))
	torch(142, h + 8, 17.6, props, Vector3.new(0, 0, -1))
	torch(142, h + 8, -17.6, props, Vector3.new(0, 0, 1))

	-- ══ SEWER (-6) → ESCAPE PAD ════════════════════════════════
	local s = -6
	rampZ("SewerRamp", -34, -20, 100, 106, 0, s, zones)
	floor("SewerFloor", 100, 106, -76, -34, s, zones, Enum.Material.Concrete)
	for _, sx in { 99.3, 106.7 } do
		box("SewerWall", sx, s + 5, -48, 1.4, 10, 56, Palette.stone, zones, Enum.Material.Concrete)
	end
	box("SewerWallEnd", 103, s + 5, -76.7, 8.8, 10, 1.4, Palette.stone, zones, Enum.Material.Concrete)
	-- A drain channel down the middle: the floor reads as a sewer, not another corridor.
	decor(box("SewerChannel", 103, s + 0.05, -55, 1.6, 0.1, 40, Palette.pitch, props, Enum.Material.Glass))
	torch(100.2, s + 5, -40, props, Vector3.new(1, 0, 0))
	torch(105.8, s + 5, -58, props, Vector3.new(-1, 0, 0))

	-- The escape pad: `escape` green (art §3), dim until the alarm reveals it.
	local extraction = box(
		"ExtractionPad",
		103,
		s + 0.3,
		-70,
		6,
		0.6,
		6,
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
		CellSpawnCFrame = CFrame.new(-40, 4, 0),
		HideoutSpawnCFrame = CFrame.new(0, 4, 405),
		PatrolGuardSpawn = CFrame.new(28, g + 3, 0),
		PatrolPointA = Vector3.new(12, g, 0),
		PatrolPointB = Vector3.new(44, g, 0),
		AlarmGuardSpawns = { CFrame.new(82, 3, -15), CFrame.new(120, 3, 15) },
		-- The roster (Section F). An archer on the treasure dais covering the vault; a shield
		-- guard patrolling the south side, between you and the sewer arch; a sentry in the
		-- corridor firing across it; hounds loosed into the sewer on the alarm.
		VaultArcherSpawn = CFrame.lookAt(Vector3.new(111, 4, 17), Vector3.new(90, 4, 0)),
		VaultShieldSpawn = CFrame.new(96, 3, -11),
		VaultShieldPatrolA = Vector3.new(84, 0, -12),
		VaultShieldPatrolB = Vector3.new(116, 0, -12),
		CorridorSentrySpawn = CFrame.lookAt(Vector3.new(66, 3, 5), Vector3.new(66, 3, -5)),
		SewerHoundSpawn = CFrame.new(103, -3, -42),

		-- Captain Bronn: on his dais, facing west down the sightline to the cellblock door.
		CaptainSpawn = CFrame.lookAt(Vector3.new(168, h + 1 + 3.6, 0), Vector3.new(76, h + 1 + 3.6, 0)),
		CaptainReinforcementSpawn = CFrame.new(172, h + 3, 14),
		-- Fight zone: the hall floor east of the threshold, full room height.
		CaptainArena = { Min = Vector3.new(132, 0, -18), Max = Vector3.new(176, h + 22, 18) },
	}
end

return WorldBuilder
