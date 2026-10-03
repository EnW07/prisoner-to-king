--!strict
-- WeaponConfig.lua
-- Blueprint §110: weapons are DATA. Adding a weapon must never require touching CombatService.
-- Blueprint §64 (MASTER_BUILD_SPEC E6): each CLASS has one mechanical identity, and it is
-- expressed in the fields below, never in code that checks a weapon id:
--   SWORD    balanced: the baseline, the fastest three-hit combo
--   DAGGER   very fast, low damage, the longest dash i-frames
--   AXE      slow, heavy, breaks guard on LIGHT attacks (the shield guard's other key)
--   SPEAR    reach: strikes from outside a guard's stand-off distance
--   GREATSWORD (Bronn's) heavy, every hit shoves
--   (HAMMER  slowest, massive knockback, stuns: reserved for the Warden's drop, G2)

export type Weapon = {
	Name: string,
	Rarity: string,
	Damage: number,
	AttackCooldown: number,
	WeaponClass: string,
	-- Animation weight class (AnimationConfig.Weights): how slowly it winds up and recovers
	-- and how much the body joins the swing. A hammer and a dagger must not share timing.
	Weight: string,
	-- Identity (E6). CombatService reads these; it never special-cases an id.
	Reach: number, -- studs: the swing box's depth in front of the player
	Combo: { string }, -- the light chain's moves (AnimationConfig.Player slots); the last is the finisher
	GuardBreak: boolean, -- light attacks break a shield guard's block
	KnockbackForce: number, -- impulse per unit mass on every hit (finishers add more)
	StaggerBonus: number, -- seconds added to an enemy's stagger when this weapon breaks poise
	DashIFrameBonus: number, -- seconds added to the dash's invincibility window
	-- Heavy attack (E2): hold, then release.
	HeavyDamageMultiplier: number,
	HeavyCooldown: number,
	SellValue: number,
	Special: string?,
	-- Graybox visual: box welded to the hand until real art exists.
	Model: { Size: Vector3, Color: Color3, Material: Enum.Material },
}

local THREE = { "Light1", "Light2", "Light3" }

local WeaponConfig: { [string]: Weapon } = {
	fists = {
		Name = "Fists",
		Rarity = "Common",
		Damage = 5,
		AttackCooldown = 0.65,
		WeaponClass = "Unarmed",
		Weight = "Light",
		Reach = 5,
		Combo = { "Light1", "Light2" },
		GuardBreak = false,
		KnockbackForce = 0,
		StaggerBonus = 0,
		DashIFrameBonus = 0,
		HeavyDamageMultiplier = 1.5,
		HeavyCooldown = 1.4,
		SellValue = 0,
		Special = nil,
		Model = {
			Size = Vector3.new(0.1, 0.1, 0.1),
			Color = Color3.fromRGB(200, 170, 140),
			Material = Enum.Material.SmoothPlastic,
		},
	},

	bent_spoon = {
		Name = "Bent Spoon",
		Rarity = "Common",
		Damage = 7,
		AttackCooldown = 0.60,
		WeaponClass = "Dagger",
		Weight = "Light",
		Reach = 6.5,
		Combo = THREE,
		GuardBreak = false,
		KnockbackForce = 0,
		StaggerBonus = 0,
		DashIFrameBonus = 0.15, -- the dagger's identity: slip through anything
		HeavyDamageMultiplier = 1.6,
		HeavyCooldown = 1.3,
		SellValue = 5,
		Special = nil,
		Model = {
			Size = Vector3.new(0.25, 1.6, 0.25),
			Color = Color3.fromRGB(160, 160, 165),
			Material = Enum.Material.Metal,
		},
	},

	rusty_sword = {
		Name = "Rusty Sword",
		Rarity = "Common",
		Damage = 12,
		AttackCooldown = 0.70,
		WeaponClass = "Sword",
		Weight = "Medium",
		Reach = 8,
		Combo = THREE,
		GuardBreak = false,
		KnockbackForce = 0,
		StaggerBonus = 0,
		DashIFrameBonus = 0,
		HeavyDamageMultiplier = 1.8,
		HeavyCooldown = 1.6,
		SellValue = 30,
		Special = nil,
		Model = {
			Size = Vector3.new(0.3, 3.2, 0.3),
			Color = Color3.fromRGB(140, 90, 60),
			Material = Enum.Material.CorrodedMetal,
		},
	},

	-- Captain Bronn's guaranteed drop (M2 brief item 1). §11 baseline: 18 dmg, 0.72s.
	-- Longer and heavier than the Rusty Sword so the upgrade reads by silhouette (art §4).
	guard_sword = {
		Name = "Guard Sword",
		Rarity = "Uncommon",
		Damage = 18,
		AttackCooldown = 0.72,
		WeaponClass = "Sword",
		Weight = "Medium",
		Reach = 8.5,
		Combo = THREE,
		GuardBreak = false,
		KnockbackForce = 0,
		StaggerBonus = 0,
		DashIFrameBonus = 0,
		HeavyDamageMultiplier = 1.8,
		HeavyCooldown = 1.6,
		SellValue = 80, -- placeholder: selling doesn't exist yet
		Special = nil,
		Model = {
			Size = Vector3.new(0.4, 4.2, 0.4),
			Color = Color3.fromRGB(170, 170, 180), -- the guards' own blade colour
			Material = Enum.Material.Metal,
		},
	},

	-- The guards' spear, a low-weight drop from spearmen (E6, §59 P0 list). Reach: it
	-- strikes from outside a guard's stand-off ring, so the guard has to come to you.
	guard_spear = {
		Name = "Guard Spear",
		Rarity = "Uncommon",
		Damage = 14,
		AttackCooldown = 0.8,
		WeaponClass = "Spear",
		Weight = "Medium",
		Reach = 11.5,
		Combo = { "Thrust1", "Thrust2" },
		GuardBreak = false,
		KnockbackForce = 6,
		StaggerBonus = 0,
		DashIFrameBonus = 0,
		HeavyDamageMultiplier = 1.8,
		HeavyCooldown = 1.7,
		SellValue = 70,
		Special = nil,
		Model = {
			Size = Vector3.new(0.25, 7, 0.25),
			Color = Color3.fromRGB(110, 75, 45),
			Material = Enum.Material.Wood,
		},
	},

	-- From the kitchens and the barracks chest (E6, §59 P0 list). Slow and heavy; its light
	-- attacks break a shield guard's block, so it is the second key to that lock.
	woodcutter_axe = {
		Name = "Woodcutter's Axe",
		Rarity = "Uncommon",
		Damage = 16,
		AttackCooldown = 0.95,
		WeaponClass = "Axe",
		Weight = "Heavy",
		Reach = 7.5,
		Combo = { "Light1", "Light3" },
		GuardBreak = true,
		KnockbackForce = 14,
		StaggerBonus = 0.2,
		DashIFrameBonus = 0,
		HeavyDamageMultiplier = 2.2,
		HeavyCooldown = 2,
		SellValue = 75,
		Special = nil,
		Model = {
			Size = Vector3.new(0.3, 3.6, 0.3),
			Color = Color3.fromRGB(110, 75, 45),
			Material = Enum.Material.Wood,
		},
	},

	-- Bronn's own sword, a weighted chance from his chest (M2 brief item 2; §11: 32 dmg,
	-- 0.95s, cone knockback). One signature mechanic, understood at once: every hit shoves.
	captain_greatsword = {
		Name = "Captain's Greatsword",
		Rarity = "Rare",
		Damage = 32,
		AttackCooldown = 0.95,
		WeaponClass = "Greatsword",
		Weight = "Heavy",
		Reach = 9.5,
		Combo = { "Light1", "Light3" },
		GuardBreak = false,
		KnockbackForce = 22,
		StaggerBonus = 0.3,
		DashIFrameBonus = 0,
		HeavyDamageMultiplier = 2,
		HeavyCooldown = 2.2,
		SellValue = 250,
		Special = "Every hit shoves",
		Model = {
			Size = Vector3.new(0.8, 7, 0.35),
			Color = Color3.fromRGB(90, 90, 100),
			Material = Enum.Material.Metal,
		},
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
