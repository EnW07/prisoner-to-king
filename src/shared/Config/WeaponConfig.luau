--!strict
-- WeaponConfig.lua
-- Blueprint §110: weapons are DATA. Adding a weapon must never require touching CombatService.

export type Weapon = {
	Name: string,
	Rarity: string,
	Damage: number,
	AttackCooldown: number,
	WeaponClass: string,
	SellValue: number,
	Special: string?,
	-- Graybox visual: box welded to the hand until real art exists.
	Model: { Size: Vector3, Color: Color3, Material: Enum.Material },
}

local WeaponConfig: { [string]: Weapon } = {
	fists = {
		Name = "Fists",
		Rarity = "Common",
		Damage = 5,
		AttackCooldown = 0.65,
		WeaponClass = "Unarmed",
		SellValue = 0,
		Special = nil,
		Model = { Size = Vector3.new(0.1, 0.1, 0.1), Color = Color3.fromRGB(200, 170, 140), Material = Enum.Material.SmoothPlastic },
	},

	bent_spoon = {
		Name = "Bent Spoon",
		Rarity = "Common",
		Damage = 7,
		AttackCooldown = 0.60,
		WeaponClass = "Dagger",
		SellValue = 5,
		Special = nil,
		Model = { Size = Vector3.new(0.25, 1.6, 0.25), Color = Color3.fromRGB(160, 160, 165), Material = Enum.Material.Metal },
	},

	rusty_sword = {
		Name = "Rusty Sword",
		Rarity = "Common",
		Damage = 12,
		AttackCooldown = 0.70,
		WeaponClass = "Sword",
		SellValue = 30,
		Special = nil,
		Model = { Size = Vector3.new(0.3, 3.2, 0.3), Color = Color3.fromRGB(140, 90, 60), Material = Enum.Material.CorrodedMetal },
	},
}

-- Rarity → colour, used by loot beams and UI. (§13: don't rely on UI colour alone,
-- but colour is still the cheapest first signal in a graybox.)
WeaponConfig.RarityColors = {
	Common = Color3.fromRGB(200, 200, 200),
	Uncommon = Color3.fromRGB(90, 210, 110),
	Rare = Color3.fromRGB(80, 150, 255),
	Epic = Color3.fromRGB(180, 100, 255),
	Legendary = Color3.fromRGB(255, 180, 60),
	Mythic = Color3.fromRGB(255, 70, 70),
}

function WeaponConfig.Get(id: string): Weapon?
	local entry = rawget(WeaponConfig, id)
	if typeof(entry) == "table" and entry.Damage then
		return entry :: Weapon
	end
	return nil
end

return WeaponConfig
