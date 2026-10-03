--!strict
-- LootConfig.lua  (blueprint §112 + §115 first-run guarantees)
-- All rolling happens SERVER-side in LootService. This file is data only.

export type Entry = { Kind: string, Id: string?, Weight: number, Min: number?, Max: number? }
-- Always dropped, before any weighted roll. Weapons here are owned by the killer.
export type Guaranteed = { Kind: string, Id: string }

local LootConfig = {}

LootConfig.Tables = {
	sleepy_guard = {
		Rolls = 1,
		Entries = {
			{ Kind = "None", Weight = 70 },
			{ Kind = "Gold", Weight = 30, Min = 5, Max = 12 },
		} :: { Entry },
	},

	alarm_guard = {
		Rolls = 1,
		Entries = {
			{ Kind = "None", Weight = 55 },
			{ Kind = "Gold", Weight = 45, Min = 8, Max = 20 },
		} :: { Entry },
	},

	-- M2 brief item 1: the Guard Sword is guaranteed. The weighted Captain's Greatsword
	-- chance is added with the rare-drops work (m2/rare-drops).
	captain_bronn = {
		Rolls = 1,
		Guaranteed = {
			{ Kind = "Weapon", Id = "guard_sword" },
		} :: { Guaranteed },
		Entries = {
			{ Kind = "None", Weight = 40 },
			{ Kind = "Gold", Weight = 60, Min = 20, Max = 40 },
		} :: { Entry },
	},
}

-- §115: randomness must never be able to break onboarding.
-- These are unconditional in Milestone 1 and stay unconditional on every player's FIRST run.
LootConfig.Guarantees = {
	-- The first guard a player kills always drops the cellblock key.
	FirstGuardDropsKey = true,
	-- The first chest a player opens always contains the Rusty Sword.
	FirstChestWeapon = "rusty_sword",
}

LootConfig.Pickups = {
	Gold = { Color = Color3.fromRGB(255, 200, 60), Size = Vector3.new(1, 1, 1), Label = "Gold" },
	Key = {
		Color = Color3.fromRGB(230, 230, 120),
		Size = Vector3.new(0.6, 1.4, 0.3),
		Label = "Cellblock Key",
	},
	Weapon = { Color = Color3.fromRGB(200, 200, 200), Size = Vector3.new(0.6, 2.4, 0.6), Label = "Weapon" },
	-- Loot bursts out physically and is visible on the floor (§8).
	BurstForce = 22,
	Lifetime = 120,
	PickupRadius = 7,
}

return LootConfig
