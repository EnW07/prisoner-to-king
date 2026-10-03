--!strict
-- RigFactory.lua
-- Builds enemy bodies. One responsibility: turn an EnemyConfig entry into a real R15 rig.
-- (docs/RIGS_AND_VISUAL_UI_BRIEF.md §1, playtest 4.)
--
-- WHY: M1 enemies were a HumanoidRootPart, a Head and a welded Blade. With no limbs there
-- was nothing to animate, so guards slid. These are full R15 rigs (head, torso, arms,
-- legs, Motor6D joints), so any R15 animation can play on them.
--
-- TEMPLATES: one per enemy id, kept in ServerStorage/PTK_RigTemplates/<enemyId> and cloned
-- per spawn. ServerStorage isn't synced by Rojo and place files are never committed, so a
-- missing template is generated at runtime from a HumanoidDescription. A template you build
-- by hand (Studio → Avatar → Rig Builder) and save under that name is used instead.
--
-- SCALE: EnemyConfig stays unchanged. BodySize is read relative to the M1 guard's size
-- (GameConfig.Enemy.RigReferenceSize), and becomes the Humanoid's height, width, depth and
-- head scales. So Bronn (4 x 7 x 2.4) is genuinely taller, broader and bulkier than a guard.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local Palette = require(game.ReplicatedStorage.Shared.Config.Palette)
local Rig = require(game.ReplicatedStorage.Shared.Anim.Rig)

local RigFactory = {}

local SKIN = Color3.fromRGB(215, 190, 160) -- M1 head colour, kept
local GUARD_STEEL = Color3.fromRGB(170, 170, 180) -- M1 guard blade colour, kept

local templates: Folder? = nil
-- Roblox's default R15 animation ids, read from the Animate script the engine puts in a
-- generated rig. Read, never typed in, so they can't be wrong. nil until a rig is built.
local defaultAnimationIds: { [string]: string }? = nil

local function templateFolder(): Folder
	if templates then
		return templates
	end
	local existing = ServerStorage:FindFirstChild("PTK_RigTemplates")
	local f: Folder
	if existing and existing:IsA("Folder") then
		f = existing
	else
		f = Instance.new("Folder")
		f.Name = "PTK_RigTemplates"
		f.Parent = ServerStorage
	end
	templates = f
	return f
end

-- Weld (not WeldConstraint) with an explicit C0, so the offset never depends on timing.
local function weld(part0: BasePart, part1: BasePart, c0: CFrame): Weld
	local w = Instance.new("Weld")
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = c0
	w.Parent = part1
	return w
end

-- A costume piece fixed to a named body part, at `offset` in that part's space.
-- Massless and non-colliding. It's inside the enemy model, so swings that touch it still
-- hit the enemy: costume only makes a silhouette easier to hit, never harder.
function RigFactory.Attach(
	model: Model,
	partName: string,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material
): Part?
	local base = model:FindFirstChild(partName, true)
	if not base or not base:IsA("BasePart") then
		warn(("[RigFactory] %s has no %s to attach %s to"):format(model.Name, partName, name))
		return nil
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = base.CFrame * offset
	weld(base, p, offset)
	p.Parent = model
	return p
end

-- Rotate a joint's rest pose and bake it: posture (a slouch is a bent waist, not a prop).
-- Applied to the template, so every clone starts with it as its rest.
local function bend(model: Model, jointName: string, rotation: CFrame)
	local rig = Rig.Open(model) -- Motor6D or AnimationConstraint form
	local joint = rig and rig.Joints[jointName]
	if joint then
		Rig.Set(joint, rotation)
		Rig.Bake(joint)
	end
end

-- Silhouettes (art §4 and §8: enemy readability comes first). Each type must read as a black
-- shape. Bronn (Boss) is dressed by CaptainService; his weapon there is part of the fight.
local function dress(model: Model, cfg)
	if cfg.Boss then
		return
	end

	-- Everyone else carries the guards' sword in the right hand: hilt in the palm, blade
	-- running down the arm's line and angled forward.
	local blade = RigFactory.Attach(
		model,
		"RightHand",
		"Blade",
		Vector3.new(0.3, 2.6, 0.3),
		CFrame.Angles(math.rad(30), 0, 0) * CFrame.new(0, -1.1, 0),
		GUARD_STEEL,
		Enum.Material.Metal
	)

	if cfg.Silhouette == "Slouch" then
		-- Hunched at the waist, head hanging, a floppy cap and a paunch: harmless at a glance.
		bend(model, "Waist", CFrame.Angles(math.rad(-18), 0, 0))
		bend(model, "Neck", CFrame.Angles(math.rad(-15), 0, 0))
		RigFactory.Attach(
			model,
			"Head",
			"Cap",
			Vector3.new(1.5, 0.4, 1.5),
			CFrame.new(0, 0.65, 0.15) * CFrame.Angles(math.rad(-15), 0, math.rad(10)),
			Palette.stone,
			Enum.Material.Fabric
		)
		RigFactory.Attach(
			model,
			"LowerTorso",
			"Paunch",
			Vector3.new(1.6, 1.0, 0.6),
			CFrame.new(0, 0.3, -0.55),
			cfg.BodyColor,
			Enum.Material.SmoothPlastic
		)
	elseif cfg.Silhouette == "Armored" then
		-- Upright and armoured: helm with a nasal guard, pauldrons, a `bleed` tabard (danger,
		-- art §3) and a spear that stands well above the head. The spear replaces the sword.
		if blade then
			blade:Destroy()
		end
		RigFactory.Attach(
			model,
			"Head",
			"Helm",
			Vector3.new(1.45, 0.9, 1.45),
			CFrame.new(0, 0.3, 0),
			Palette.stone,
			Enum.Material.Metal
		)
		RigFactory.Attach(
			model,
			"Head",
			"Nasal",
			Vector3.new(0.22, 0.8, 0.2),
			CFrame.new(0, -0.05, -0.68),
			Palette.stone,
			Enum.Material.Metal
		)
		for _, side in { "Left", "Right" } do
			RigFactory.Attach(
				model,
				side .. "UpperArm",
				"Pauldron",
				Vector3.new(1.3, 0.55, 1.3),
				CFrame.new(0, 0.55, 0),
				Palette.stone,
				Enum.Material.Metal
			)
		end
		RigFactory.Attach(
			model,
			"UpperTorso",
			"Tabard",
			Vector3.new(1.4, 1.9, 0.12),
			CFrame.new(0, -0.35, -0.55),
			Palette.bleed,
			Enum.Material.Fabric
		)
		RigFactory.Attach(
			model,
			"RightHand",
			"Spear",
			Vector3.new(0.25, 7.5, 0.25),
			CFrame.new(0, 2.5, -0.2),
			Palette.pitch,
			Enum.Material.Wood
		)
		RigFactory.Attach(
			model,
			"RightHand",
			"Spearhead",
			Vector3.new(0.5, 1.2, 0.2),
			CFrame.new(0, 6.8, -0.2),
			Palette.stone,
			Enum.Material.Metal
		)
	elseif cfg.Silhouette == "Archer" then
		-- Lean and hooded, a tall bow in the LEFT hand (the right draws), a quiver on the
		-- back. No sword: up close it has nothing.
		if blade then
			blade:Destroy()
		end
		RigFactory.Attach(
			model,
			"Head",
			"Hood",
			Vector3.new(1.5, 1.3, 1.5),
			CFrame.new(0, 0.25, 0.1),
			Color3.fromRGB(45, 55, 45),
			Enum.Material.Fabric
		)
		RigFactory.Attach(
			model,
			"LeftHand",
			"Bow",
			Vector3.new(0.25, 5.2, 0.35),
			CFrame.new(0, 0, -0.1),
			Color3.fromRGB(90, 60, 40),
			Enum.Material.Wood
		)
		RigFactory.Attach(
			model,
			"LeftHand",
			"Bowstring",
			Vector3.new(0.08, 5, 0.08),
			CFrame.new(0, 0, 0.3),
			Palette.stone,
			Enum.Material.Fabric
		)
		RigFactory.Attach(
			model,
			"UpperTorso",
			"Quiver",
			Vector3.new(0.6, 2.2, 0.6),
			CFrame.new(0.45, 0.3, 0.75) * CFrame.Angles(0, 0, math.rad(-15)),
			Color3.fromRGB(90, 60, 40),
			Enum.Material.Wood
		)
	elseif cfg.Silhouette == "Shield" then
		-- Broad and helmed, a round shield the size of his torso on the LEFT forearm. The
		-- shield reads from any angle: that is the lock.
		RigFactory.Attach(
			model,
			"Head",
			"Helm",
			Vector3.new(1.5, 0.95, 1.5),
			CFrame.new(0, 0.3, 0),
			Palette.stone,
			Enum.Material.Metal
		)
		local shield = RigFactory.Attach(
			model,
			"LeftLowerArm",
			"Shield",
			Vector3.new(0.35, 3.4, 3.4),
			CFrame.new(-0.55, 0, 0),
			Palette.stone,
			Enum.Material.Metal
		)
		if shield then
			shield.Shape = Enum.PartType.Cylinder
		end
		RigFactory.Attach(
			model,
			"LeftLowerArm",
			"ShieldBoss",
			Vector3.new(0.3, 1, 1),
			CFrame.new(-0.85, 0, 0),
			Palette.bleed,
			Enum.Material.Metal
		)
	elseif cfg.Silhouette == "Hound" then
		-- Low and long, hunched toward all fours by its posture (AnimationConfig
		-- HoundStance): a snout, ears and a tail, dark. No weapon; it is the weapon.
		if blade then
			blade:Destroy()
		end
		RigFactory.Attach(
			model,
			"Head",
			"Snout",
			Vector3.new(0.7, 0.6, 0.9),
			CFrame.new(0, -0.15, -0.8),
			cfg.BodyColor,
			Enum.Material.SmoothPlastic
		)
		for _, side in { -1, 1 } do
			RigFactory.Attach(
				model,
				"Head",
				"Ear",
				Vector3.new(0.3, 0.7, 0.2),
				CFrame.new(side * 0.5, 0.75, 0) * CFrame.Angles(0, 0, math.rad(side * -20)),
				cfg.BodyColor,
				Enum.Material.SmoothPlastic
			)
		end
		RigFactory.Attach(
			model,
			"LowerTorso",
			"Tail",
			Vector3.new(0.25, 0.25, 1.6),
			CFrame.new(0, 0.2, 1.1) * CFrame.Angles(math.rad(25), 0, 0),
			cfg.BodyColor,
			Enum.Material.SmoothPlastic
		)
	elseif cfg.Silhouette == "Sentry" then
		-- Kneeling (AnimationConfig SentryStance) behind a heavy crossbow held level in both
		-- hands, a helm. The crossbow is long enough to point down the corridor.
		if blade then
			blade:Destroy()
		end
		RigFactory.Attach(
			model,
			"Head",
			"Helm",
			Vector3.new(1.45, 0.9, 1.45),
			CFrame.new(0, 0.3, 0),
			Palette.stone,
			Enum.Material.Metal
		)
		RigFactory.Attach(
			model,
			"RightHand",
			"Crossbow",
			Vector3.new(0.35, 0.4, 3.6),
			CFrame.new(-0.4, 0.1, -1.1),
			Color3.fromRGB(90, 60, 40),
			Enum.Material.Wood
		)
		RigFactory.Attach(
			model,
			"RightHand",
			"CrossbowLimb",
			Vector3.new(3, 0.2, 0.25),
			CFrame.new(-0.4, 0.15, -2.6),
			Palette.stone,
			Enum.Material.Metal
		)
	elseif cfg.Silhouette == "Brute" then
		-- A wall of a man: huge pauldrons, a bare head, a belt, and a club the size of a
		-- door in the right hand. Reads as "the room is about this" from the far side of it.
		if blade then
			blade:Destroy()
		end
		for _, side in { "Left", "Right" } do
			RigFactory.Attach(
				model,
				side .. "UpperArm",
				"Pauldron",
				Vector3.new(2.2, 0.9, 2.2),
				CFrame.new(0, 1, 0),
				Palette.stone,
				Enum.Material.Metal
			)
		end
		RigFactory.Attach(
			model,
			"LowerTorso",
			"Belt",
			Vector3.new(4, 0.6, 2.4),
			CFrame.new(0, -0.6, 0),
			Palette.pitch,
			Enum.Material.Metal
		)
		RigFactory.Attach(
			model,
			"RightHand",
			"Club",
			Vector3.new(0.9, 6.5, 0.9),
			CFrame.Angles(math.rad(30), 0, 0) * CFrame.new(0, -2.6, 0),
			Color3.fromRGB(90, 60, 40),
			Enum.Material.Wood
		)
		RigFactory.Attach(
			model,
			"RightHand",
			"ClubHead",
			Vector3.new(1.9, 2.2, 1.9),
			CFrame.Angles(math.rad(30), 0, 0) * CFrame.new(0, -5.6, 0),
			Palette.stone,
			Enum.Material.Slate
		)
	end
end

-- Variety within a type (F7): a small random scale and body tint per spawn, inside
-- config-defined ranges. Stats never vary; only the look, so a line of guards reads as
-- people rather than copies. Rule 8: Model:ScaleTo is the 2023 Model API; wrapped.
function RigFactory.Vary(model: Model, cfg)
	local v = cfg.Variation
	if not v then
		return
	end
	local range = v.Scale
	if range and range[1] and range[2] then
		local s = range[1] + math.random() * (range[2] - range[1])
		pcall(function()
			model:ScaleTo(model:GetScale() * s)
		end)
	end
	local tint = v.Tint or 0
	if tint > 0 then
		local k = (math.random() * 2 - 1) * tint
		local toward = if k < 0 then Palette.pitch else Color3.new(1, 1, 1)
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and p.Color == cfg.BodyColor then
				p.Color = cfg.BodyColor:Lerp(toward, math.abs(k))
			end
		end
	end
end

-- Read Roblox's default animation ids out of the Animate script in a generated rig, then
-- remove the script: a LocalScript can't run in an NPC. EnemyAnimator plays them instead.
local function harvestAnimate(model: Model)
	local animate = model:FindFirstChild("Animate")
	if not animate then
		return
	end
	if not defaultAnimationIds then
		local found: { [string]: string } = {}
		for _, value in animate:GetChildren() do
			if value:IsA("StringValue") then
				local anim = value:FindFirstChildOfClass("Animation")
				if anim and anim.AnimationId ~= "" then
					found[value.Name] = anim.AnimationId
				end
			end
		end
		if next(found) then
			defaultAnimationIds = found
		end
	end
	animate:Destroy()
end

-- Roblox's default R15 animation ids, keyed by Animate's names (idle, walk, run, jump, fall,
-- climb, ...). nil if no generated rig carried an Animate script.
function RigFactory.DefaultAnimationIds(): { [string]: string }?
	return defaultAnimationIds
end

-- Also accepts ids read from a player's character, which always carries Animate.
function RigFactory.LearnDefaultAnimations(character: Model)
	if defaultAnimationIds then
		return
	end
	local animate = character:FindFirstChild("Animate")
	if not animate then
		return
	end
	local found: { [string]: string } = {}
	for _, value in animate:GetChildren() do
		if value:IsA("StringValue") then
			local anim = value:FindFirstChildOfClass("Animation")
			if anim and anim.AnimationId ~= "" then
				found[value.Name] = anim.AnimationId
			end
		end
	end
	if next(found) then
		defaultAnimationIds = found
	end
end

local function makeTemplate(enemyId: string, cfg): Model
	local ref: Vector3 = GameConfig.Enemy.RigReferenceSize
	local body: Vector3 = cfg.BodySize
	local height = body.Y / ref.Y

	local desc = Instance.new("HumanoidDescription")
	desc.HeightScale = height
	desc.WidthScale = body.X / ref.X
	desc.DepthScale = body.Z / ref.Z
	desc.HeadScale = height
	desc.HeadColor = SKIN
	desc.TorsoColor = cfg.BodyColor
	desc.LeftArmColor = cfg.BodyColor
	desc.RightArmColor = cfg.BodyColor
	desc.LeftLegColor = cfg.BodyColor
	desc.RightLegColor = cfg.BodyColor

	-- Server-only, may yield. Wrapped so a failure names the enemy instead of a bare error.
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not result then
		error(("[RigFactory] Could not build an R15 rig for %s: %s"):format(enemyId, tostring(result)))
	end
	local rig: Model = result
	harvestAnimate(rig)

	-- If the engine clamped the requested height, make up the rest uniformly so the
	-- silhouette still matches config. (Rule 8: ScaleTo is a Model API since 2023.)
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local applied = humanoid and humanoid:FindFirstChild("BodyHeightScale")
	if
		applied
		and applied:IsA("NumberValue")
		and applied.Value > 0
		and math.abs(applied.Value - height) > 0.01
	then
		warn(
			("[RigFactory] %s height scale clamped to %.2f; scaling the model to compensate"):format(
				enemyId,
				applied.Value
			)
		)
		rig:ScaleTo(height / applied.Value)
	end

	rig.PrimaryPart = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	dress(rig, cfg)
	rig.Name = enemyId
	rig.Parent = templateFolder()
	return rig
end

-- Build every enemy's template once at server start. Generating a rig can yield, and the
-- first alarm of a session shouldn't be the moment it happens.
function RigFactory.Prewarm(enemyConfig)
	for id in enemyConfig do
		local cfg = enemyConfig.Get(id)
		if cfg and not templateFolder():FindFirstChild(id) then
			makeTemplate(id, cfg)
		end
	end
end

-- A fresh R15 enemy body, not yet parented. Callers set Humanoid stats and place it.
function RigFactory.Build(enemyId: string, cfg): Model
	local template = templateFolder():FindFirstChild(enemyId)
	if not template or not template:IsA("Model") then
		template = makeTemplate(enemyId, cfg)
	end
	local model = (template :: Model):Clone()
	model.Name = cfg.DisplayName
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	return model
end

-- Stand a rig on the floor beneath `cframe`, facing the same way. Spawn points only need to
-- be roughly above the right floor: the feet are placed exactly, whatever the rig's scale.
function RigFactory.PlaceOnFloor(model: Model, cframe: CFrame)
	local root = model.PrimaryPart
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		model:PivotTo(cframe)
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace:FindFirstChild("World") :: Instance }
	local start = cframe.Position + Vector3.new(0, GameConfig.Enemy.SpawnProbeLift, 0)
	local hit = workspace:Raycast(start, Vector3.new(0, -GameConfig.Enemy.SpawnProbeDepth, 0), params)
	local y = if hit then hit.Position.Y + humanoid.HipHeight + root.Size.Y / 2 else cframe.Position.Y
	model:PivotTo(CFrame.new(cframe.Position.X, y, cframe.Position.Z) * cframe.Rotation)
end

return RigFactory
