--!strict
-- WeaponModel.lua
-- Turns a weapon id into a 3D model. Used for the weapon in a player's hand (server) and for
-- every weapon icon: the HUD slot, the inventory, the loot reveal (client). One builder, so
-- what you see in the UI is exactly what you hold.
-- (docs/RIGS_AND_VISUAL_UI_BRIEF.md §2.)
--
-- ASSET HOOK: if ReplicatedStorage.WeaponModels has a Model named after the weapon id, with a
-- PrimaryPart, it's cloned instead of building primitives. Drop an imported mesh there and
-- every surface picks it up with no code change. The PrimaryPart is what the hand grips;
-- its +Y end sits at the hand, the same convention as the primitive blade below.
-- Without one, the weapon is built from primitives: a blade from WeaponConfig.Model, plus a
-- crossguard and hilt for swords, and a bowl for the spoon, so each class has its own
-- silhouette (art §4).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = script.Parent
local WeaponConfig = require(Shared:WaitForChild("Config"):WaitForChild("WeaponConfig"))
local Palette = require(Shared:WaitForChild("Config"):WaitForChild("Palette"))

local WeaponModel = {}

local function piece(
	model: Model,
	blade: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material
)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = blade.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = blade
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	p.Parent = model
end

-- Returns nil for fists (nothing to show) or an unknown id. Parts are unanchored and
-- non-colliding; a viewport ignores physics, and a hand weld holds them in play.
function WeaponModel.Build(weaponId: string): Model?
	local weapon = WeaponConfig.Get(weaponId)
	if not weapon or weapon.WeaponClass == "Unarmed" then
		return nil
	end

	local library = ReplicatedStorage:FindFirstChild("WeaponModels")
	local custom = library and library:FindFirstChild(weaponId)
	if custom and custom:IsA("Model") and custom.PrimaryPart then
		return custom:Clone()
	end

	local model = Instance.new("Model")
	model.Name = weaponId
	local size = weapon.Model.Size
	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = size
	blade.Color = weapon.Model.Color
	blade.Material = weapon.Model.Material
	blade.CanCollide = false
	blade.CanTouch = false
	blade.Massless = true
	blade.TopSurface = Enum.SurfaceType.Smooth
	blade.BottomSurface = Enum.SurfaceType.Smooth
	blade.CFrame = CFrame.new()
	blade.Parent = model
	model.PrimaryPart = blade

	local length, width = size.Y, size.X
	local class = weapon.WeaponClass
	if class == "Sword" or class == "Greatsword" then
		local heavy = class == "Greatsword"
		local guardWidth = math.max(1, width * (if heavy then 4.5 else 3.5))
		local hiltLength = length * (if heavy then 0.3 else 0.24)
		piece(
			model,
			blade,
			"Crossguard",
			Vector3.new(guardWidth, 0.22, math.max(0.3, size.Z * 1.4)),
			CFrame.new(0, length / 2, 0),
			Palette.stone,
			Enum.Material.Metal
		)
		piece(
			model,
			blade,
			"Hilt",
			Vector3.new(width * 0.8, hiltLength, width * 0.8),
			CFrame.new(0, length / 2 + hiltLength / 2, 0),
			Palette.pitch,
			Enum.Material.Fabric
		)
		piece(
			model,
			blade,
			"Pommel",
			Vector3.new(width * 1.3, width * 1.3, width * 1.3),
			CFrame.new(0, length / 2 + hiltLength + width * 0.5, 0),
			Palette.stone,
			Enum.Material.Metal
		)
	elseif class == "Axe" then
		-- A haft with a one-sided head near the business end (-Y is the tip).
		piece(
			model,
			blade,
			"AxeHead",
			Vector3.new(width * 5, length * 0.32, math.max(0.25, size.Z * 0.9)),
			CFrame.new(width * 2.2, -length / 2 + length * 0.2, 0),
			Palette.stone,
			Enum.Material.Metal
		)
		piece(
			model,
			blade,
			"AxeBit",
			Vector3.new(width * 1.2, length * 0.4, math.max(0.2, size.Z * 0.7)),
			CFrame.new(width * 4.6, -length / 2 + length * 0.2, 0),
			Palette.stone,
			Enum.Material.Metal
		)
	elseif class == "Spear" then
		-- A long shaft with a leaf head at the tip and a butt cap at the hand.
		piece(
			model,
			blade,
			"Spearhead",
			Vector3.new(width * 2.2, length * 0.16, math.max(0.2, size.Z * 0.8)),
			CFrame.new(0, -length / 2 - length * 0.07, 0),
			Palette.stone,
			Enum.Material.Metal
		)
		piece(
			model,
			blade,
			"ButtCap",
			Vector3.new(width * 1.4, width * 1.4, width * 1.4),
			CFrame.new(0, length / 2, 0),
			Palette.pitch,
			Enum.Material.Metal
		)
	elseif class == "Dagger" then
		-- It's a spoon: a bowl at the business end.
		piece(
			model,
			blade,
			"Bowl",
			Vector3.new(width * 2.6, length * 0.32, width * 0.7),
			CFrame.new(0, -length / 2 - length * 0.12, 0),
			weapon.Model.Color,
			weapon.Model.Material
		)
	end
	return model
end

return WeaponModel
