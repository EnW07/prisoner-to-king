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

	archer = {
		Rolls = 1,
		Entries = {
			{ Kind = "None", Weight = 60 },
			{ Kind = "Gold", Weight = 40, Min = 5, Max = 12 },
		} :: { Entry },
	},

	shield_guard = {
		Rolls = 1,
		Entries = {
			{ Kind = "None", Weight = 45 },
			{ Kind = "Gold", Weight = 55, Min = 10, Max = 22 },
		} :: { Entry },
	},

	hound = {
		Rolls = 1,
		Entries = {
			{ Kind = "None", Weight = 85 },
			{ Kind = "Gold", Weight = 15, Min = 2, Max = 6 },
		} :: { Entry },
	},

	sentry = {
		Rolls = 1,
		Entries = {
			{ Kind = "None", Weight = 60 },
			{ Kind = "Gold", Weight = 40, Min = 5, Max = 10 },
		} :: { Entry },
	},

	brute = {
		Rolls = 1,
		Entries = {
			{ Kind = "None", Weight = 30 },
			{ Kind = "Gold", Weight = 70, Min = 20, Max = 45 },
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

-- The chest on every run after the first (playtest 5). Run 1 is the §115 guarantee below;
-- after that the chest pays out like any other loot: usually gold, sometimes a better blade,
-- sometimes nothing. The chest's fixed Economy.ChestGold is paid on top, every run.
LootConfig.ChestTable = "chest"
LootConfig.Tables.chest = {
	Rolls = 1,
	Entries = {
		{ Kind = "None", Weight = 30 },
		{ Kind = "Gold", Weight = 62, Min = 15, Max = 35 },
		{ Kind = "Weapon", Id = "guard_sword", Weight = 8 },
	} :: { Entry },
}

-- §115: randomness must never be able to break onboarding.
-- These are unconditional in Milestone 1 and stay unconditional on every player's FIRST run.
LootConfig.Guarantees = {
	-- The first guard a player kills always drops the cellblock key.
	FirstGuardDropsKey = true,
	-- The chest on a player's FIRST run always contains the Rusty Sword (and on any later run
	-- until they own it). Every other run it rolls LootConfig.ChestTable.
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
	-- Loot hops out and comes to rest, anchored, on the floor (§8). No physics: an unanchored
	-- drop fell through the floor (playtest 3, P0).
	ScatterRadius = 6, -- max sideways distance from the drop point
	HopHeight = 4,
	HopTime = 0.45, -- seconds, whole arc
	Hover = 0.4, -- resting gap above the floor so it never z-fights or sinks
	FloorProbeDepth = 40, -- how far down to search for a floor
	-- Safety net: a drop below this Y is moved back to its landing point. The dungeon floor
	-- is at Y = 0, so this only fires if something is badly wrong.
	MinSafeY = -20,
	SweepInterval = 0.15, -- seconds between server-side proximity pickup checks
	Lifetime = 120,
	PickupRadius = 7,
}

return LootConfig
