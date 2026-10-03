--!strict
-- WorldParts.lua
-- Not a service: the primitive vocabulary the castle is built from. WorldBuilder lays out
-- rooms with these; WorldDressing fills them. Primitives, WedgeParts and cylinders only,
-- palette tokens only (art §3), nothing imported.
--
-- Conventions: +X is deeper into the castle. floor(...) puts a slab's TOP at `top`.
-- wall(...) stands on floorY. Anything decorative goes through decor() so it never blocks
-- movement, a raycast (sight, projectiles, loot landing) or a swing.

local CollectionService = game:GetService("CollectionService")

local Palette = require(game.ReplicatedStorage.Shared.Config.Palette)

local WorldParts = {}

WorldParts.WOOD = Color3.fromRGB(110, 75, 45) -- M1 value, kept: no palette token for wood
WorldParts.CHEST_WOOD = Color3.fromRGB(120, 85, 50) -- M1 value, kept
WorldParts.STRAW = Color3.fromRGB(170, 145, 80)
WorldParts.CLOTH = Color3.fromRGB(120, 110, 95)

local WOOD = WorldParts.WOOD

function WorldParts.part(
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

function WorldParts.box(
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
	return WorldParts.part(name, CFrame.new(x, y, z), Vector3.new(sx, sy, sz), color, parent, material)
end

function WorldParts.wedge(
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
function WorldParts.decor(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- Floor slab whose TOP surface is at `top`.
function WorldParts.floor(
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	top: number,
	parent: Instance,
	material: Enum.Material?,
	color: Color3?
): Part
	local depth = 2
	return WorldParts.box(
		name,
		(x0 + x1) / 2,
		top - depth / 2,
		(z0 + z1) / 2,
		x1 - x0,
		depth,
		z1 - z0,
		color or Palette.pitch,
		parent,
		material or Enum.Material.Cobblestone
	)
end

-- A ceiling slab whose BOTTOM surface is at `bottom`. Rooms with a ceiling are lit by
-- their torches and windows only: darkness is a design tool (K2).
function WorldParts.ceiling(
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	bottom: number,
	parent: Instance
): Part
	return WorldParts.box(
		name,
		(x0 + x1) / 2,
		bottom + 0.5,
		(z0 + z1) / 2,
		x1 - x0,
		1,
		z1 - z0,
		Palette.pitch,
		parent,
		Enum.Material.Slate
	)
end

-- A ramp rising along +X from `bottom` at x0 to `top` at x1 (or falling, if top < bottom).
function WorldParts.rampX(
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
	WorldParts.wedge(name, cf, Vector3.new(width, h, run), Palette.pitch, parent, Enum.Material.Cobblestone)
end

-- A ramp along Z between z0 and z1 (x0..x1 wide): `high` at the larger z, `low` at the
-- smaller z. (The slope rises toward local +Z, so no yaw is needed.)
function WorldParts.rampZ(
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
	local cf = CFrame.new((x0 + x1) / 2, low + h / 2, (z0 + z1) / 2)
	WorldParts.wedge(
		name,
		cf,
		Vector3.new(x1 - x0, h, z1 - z0),
		Palette.pitch,
		parent,
		Enum.Material.Cobblestone
	)
end

-- A ramp along Z with the HIGH end at the smaller z (falls toward +Z).
function WorldParts.rampZDown(
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
	local cf = CFrame.new((x0 + x1) / 2, low + h / 2, (z0 + z1) / 2) * CFrame.Angles(0, math.pi, 0)
	WorldParts.wedge(
		name,
		cf,
		Vector3.new(x1 - x0, h, z1 - z0),
		Palette.pitch,
		parent,
		Enum.Material.Cobblestone
	)
end

-- A straight wall with an arched opening. The wall runs along local Z of `frame` (frame is
-- at floor level, centred on the wall); thickness is along local X.
--   alongX = true  → the wall runs along world X (turned 90° about Y); openOffset is +X.
--   alongX = false → the wall runs along world Z; openOffset is +Z.
-- The arch is two corner wedges inside the opening: a pointed, castle-like doorway.
function WorldParts.archWall(
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
		WorldParts.part(
			name .. "L",
			frame * CFrame.new(0, height / 2, (left0 + left1) / 2),
			Vector3.new(thick, height, left1 - left0),
			Palette.stone,
			parent,
			mat
		)
	end
	if right1 - right0 > 0.05 then
		WorldParts.part(
			name .. "R",
			frame * CFrame.new(0, height / 2, (right0 + right1) / 2),
			Vector3.new(thick, height, right1 - right0),
			Palette.stone,
			parent,
			mat
		)
	end
	if height - openHeight > 0.05 then
		WorldParts.part(
			name .. "Lintel",
			frame * CFrame.new(0, (openHeight + height) / 2, oc),
			Vector3.new(thick, height - openHeight, openWidth),
			Palette.stone,
			parent,
			mat
		)
	end
	-- Corner wedges. Default WedgePart has its right angle at bottom/+Z; rotating 180° about
	-- X puts it at top/-Z (the left corner), 180° about Z puts it at top/+Z (the right corner).
	local a = archSize
	if a > 0 then
		WorldParts.wedge(
			name .. "ArchL",
			frame
				* CFrame.new(0, openHeight - a / 2, oc - openWidth / 2 + a / 2)
				* CFrame.Angles(math.pi, 0, 0),
			Vector3.new(thick, a, a),
			Palette.stone,
			parent,
			mat
		)
		WorldParts.wedge(
			name .. "ArchR",
			frame
				* CFrame.new(0, openHeight - a / 2, oc + openWidth / 2 - a / 2)
				* CFrame.Angles(0, 0, math.pi),
			Vector3.new(thick, a, a),
			Palette.stone,
			parent,
			mat
		)
	end
end

-- A solid wall along world X or Z, bottom at floorY.
function WorldParts.wall(
	name: string,
	x: number,
	floorY: number,
	z: number,
	sx: number,
	height: number,
	sz: number,
	parent: Instance
): Part
	return WorldParts.box(
		name,
		x,
		floorY + height / 2,
		z,
		sx,
		height,
		sz,
		Palette.stone,
		parent,
		Enum.Material.Brick
	)
end

-- Round pillar with a square base and capital. Collidable: something to fight around.
function WorldParts.pillar(
	x: number,
	floorY: number,
	z: number,
	height: number,
	parent: Instance,
	radius: number?
)
	local r = radius or 1.2
	WorldParts.box(
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
	WorldParts.part(
		"Pillar",
		CFrame.new(x, floorY + height / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(height, r * 2, r * 2),
		Palette.stone,
		parent,
		Enum.Material.Cobblestone
	).Shape =
		Enum.PartType.Cylinder
	WorldParts.box(
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
function WorldParts.bars(
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
			WorldParts.part(
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
		WorldParts.box(name .. "Rail", cx, y, cz, sx, 0.4, sz, Palette.pitch, parent, Enum.Material.Metal)
	end
end

-- Wall torch on an iron sconce. `out` points from the wall into the room. Torches cluster
-- on the critical path (H2: light tells you where to go).
function WorldParts.torch(x: number, y: number, z: number, parent: Instance, out: Vector3?, range: number?)
	local o = out or Vector3.zero
	if o.Magnitude > 0 then
		-- The bracket: an iron plate on the wall and an arm reaching out to the torch.
		local plate = Vector3.new(x, y, z) - o * 0.55
		WorldParts.decor(
			WorldParts.box(
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
		WorldParts.decor(
			WorldParts.box(
				"SconceArm",
				arm.X,
				arm.Y,
				arm.Z,
				0.5,
				0.25,
				0.5,
				Palette.pitch,
				parent,
				Enum.Material.Metal
			)
		)
	end
	local handle = WorldParts.box(
		"Torch",
		x,
		y,
		z,
		0.4,
		1.2,
		0.4,
		Color3.fromRGB(90, 60, 40),
		parent,
		Enum.Material.Wood
	)
	WorldParts.decor(handle)
	-- A visible flame, so the light has a source. Clients flicker it (WorldFXController).
	local flame =
		WorldParts.box("Flame", x, y + 0.9, z, 0.5, 0.7, 0.5, Palette.ember, parent, Enum.Material.Neon)
	WorldParts.decor(flame)
	flame.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = Palette.ember
	light.Brightness = 2.4
	light.Range = range or 26
	light.Shadows = false -- shadow-casting lights are too costly on low-end phones (§41)
	light.Parent = flame
	CollectionService:AddTag(flame, "PTKTorch")
	return flame
end

-- A small candle: a stub, a flame, a short light. For chapels and bedside tables.
function WorldParts.candle(x: number, y: number, z: number, parent: Instance)
	WorldParts.decor(
		WorldParts.box(
			"Candle",
			x,
			y + 0.3,
			z,
			0.25,
			0.6,
			0.25,
			Color3.fromRGB(235, 225, 200),
			parent,
			Enum.Material.SmoothPlastic
		)
	)
	local flame =
		WorldParts.box("Flame", x, y + 0.75, z, 0.2, 0.3, 0.2, Palette.ember, parent, Enum.Material.Neon)
	WorldParts.decor(flame)
	flame.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = Palette.ember
	light.Brightness = 1.2
	light.Range = 9
	light.Shadows = false
	light.Parent = flame
	CollectionService:AddTag(flame, "PTKTorch")
	return flame
end

-- A window slit high in a wall, with a shaft of dusk light falling into the room.
-- `out` points from the wall into the room; the shaft slants down along it.
function WorldParts.windowSlit(
	x: number,
	y: number,
	z: number,
	out: Vector3,
	parent: Instance,
	length: number?
)
	local across = Vector3.new(-out.Z, 0, out.X) -- along the wall
	local slitCF = CFrame.fromMatrix(Vector3.new(x, y, z), across, Vector3.yAxis, -out)
	local slit = WorldParts.decor(
		WorldParts.part(
			"WindowSlit",
			slitCF,
			Vector3.new(0.9, 3.2, 0.3),
			Palette.ember,
			parent,
			Enum.Material.Neon
		)
	)
	slit.CastShadow = false

	-- The shaft: a long, faint slab tilted ~50° down into the room.
	local len = length or 16
	local tilt = math.rad(50)
	local dir = (out * math.cos(tilt) - Vector3.yAxis * math.sin(tilt)).Unit
	local centre = Vector3.new(x, y, z) + dir * (len / 2)
	local shaftCF = CFrame.lookAt(centre, centre + dir)
	local shaft = WorldParts.decor(
		WorldParts.part(
			"LightShaft",
			shaftCF,
			Vector3.new(1.2, 3, len),
			Palette.ember,
			parent,
			Enum.Material.Neon
		)
	)
	shaft.Transparency = 0.93
	shaft.CastShadow = false
	CollectionService:AddTag(shaft, "PTKLightShaft")

	local light = Instance.new("SpotLight")
	light.Color = Palette.ember
	light.Brightness = 3
	light.Range = math.max(22, len + 6)
	light.Angle = 35
	light.Face = Enum.NormalId.Front
	light.Parent = slit
end

-- A hanging cloth banner on a wall. `bleed` marks danger (Bronn's hall); ember is heraldry.
function WorldParts.banner(x: number, y: number, z: number, out: Vector3, parent: Instance, color: Color3?)
	local cloth = color or Palette.bleed
	local across = Vector3.new(-out.Z, 0, out.X)
	local cf = CFrame.fromMatrix(Vector3.new(x, y, z) + out * 0.8, across, Vector3.yAxis, -out)
	WorldParts.decor(
		WorldParts.part("Banner", cf, Vector3.new(3, 7, 0.2), cloth, parent, Enum.Material.Fabric)
	)
	WorldParts.decor(
		WorldParts.part(
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
		WorldParts.decor(
			WorldParts.wedge(
				"BannerTail",
				cf * CFrame.new(side * 0.75, -4.25, 0) * CFrame.Angles(0, math.rad(90), math.pi),
				Vector3.new(0.2, 1.5, 1.5),
				cloth,
				parent,
				Enum.Material.Fabric
			)
		)
	end
end

-- A wooden table (collidable: cover and clutter).
function WorldParts.table_(
	x: number,
	floorY: number,
	z: number,
	sx: number,
	sz: number,
	parent: Instance,
	yaw: number?
)
	local cf = CFrame.new(x, floorY + 2.4, z) * CFrame.Angles(0, yaw or 0, 0)
	WorldParts.part("TableTop", cf, Vector3.new(sx, 0.4, sz), WOOD, parent, Enum.Material.WoodPlanks)
	for _, dx in { -1, 1 } do
		for _, dz in { -1, 1 } do
			WorldParts.decor(
				WorldParts.part(
					"TableLeg",
					cf * CFrame.new(dx * (sx / 2 - 0.4), -1.2, dz * (sz / 2 - 0.4)),
					Vector3.new(0.4, 2.2, 0.4),
					WOOD,
					parent,
					Enum.Material.Wood
				)
			)
		end
	end
	return cf
end

-- A crate. `breakable` tags it for EnvironmentService (a swing breaks it, loot inside).
function WorldParts.crate(
	x: number,
	floorY: number,
	z: number,
	size: number,
	parent: Instance,
	breakable: boolean?
)
	local c = WorldParts.box(
		"Crate",
		x,
		floorY + size / 2,
		z,
		size,
		size,
		size,
		WOOD,
		parent,
		Enum.Material.WoodPlanks
	)
	c.Orientation = Vector3.new(0, math.random(-12, 12), 0)
	if breakable then
		c:SetAttribute("Breakable", "crate")
		CollectionService:AddTag(c, "PTKBreakable")
	end
	return c
end

-- A barrel (a wooden cylinder on end).
function WorldParts.barrel(x: number, floorY: number, z: number, parent: Instance, breakable: boolean?)
	local b = WorldParts.part(
		"Barrel",
		CFrame.new(x, floorY + 1.3, z) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(2.6, 2, 2),
		WOOD,
		parent,
		Enum.Material.WoodPlanks
	)
	b.Shape = Enum.PartType.Cylinder
	for _, dy in { -0.8, 0.8 } do
		WorldParts.decor(
			WorldParts.part(
				"BarrelHoop",
				CFrame.new(x, floorY + 1.3 + dy, z) * CFrame.Angles(0, 0, math.rad(90)),
				Vector3.new(0.2, 2.1, 2.1),
				Palette.pitch,
				parent,
				Enum.Material.Metal
			)
		).Shape =
			Enum.PartType.Cylinder
	end
	if breakable then
		b:SetAttribute("Breakable", "barrel")
		CollectionService:AddTag(b, "PTKBreakable")
	end
	return b
end

-- Murky water over a sewer floor: walk-through, translucent, dark. (No blue token: stone
-- glass over pitch reads as standing water.)
function WorldParts.water(
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	surface: number,
	parent: Instance
)
	local w = WorldParts.box(
		name,
		(x0 + x1) / 2,
		surface - 0.3,
		(z0 + z1) / 2,
		x1 - x0,
		0.6,
		z1 - z0,
		Palette.stone,
		parent,
		Enum.Material.Glass
	)
	WorldParts.decor(w)
	w.Transparency = 0.45
	w.CastShadow = false
	CollectionService:AddTag(w, "PTKWater")
	return w
end

return WorldParts
