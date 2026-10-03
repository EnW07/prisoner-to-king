--!strict
-- EnemyConfig.lua  (blueprint §111)

local Palette = require(script.Parent.Palette)

-- A boss move. Pure data: CaptainService reads it, and nothing here is logic.
-- Damage is a MULTIPLIER on the enemy's base Damage, so one number rescales the whole moveset.
--   Shape "Box":    hits a Width x Length rectangle in front of the boss.
--   Shape "Circle": hits a Radius circle centred Offset studs in front of the boss.
--   Shape "Charge": the boss dashes Length studs forward, hitting anyone within Width / 2.
export type Attack = {
	Name: string, -- shown above the boss during the wind-up and on the CAPTURED screen
	Shape: string,
	DamageMultiplier: number,
	WindUp: number, -- seconds of telegraph before the hit lands
	Recovery: number, -- seconds the boss stands still afterwards: the punish window
	Width: number?,
	Length: number?,
	Radius: number?,
	Offset: number?,
	-- The wind-up, strike and recovery poses come from AnimationConfig.Sets.Captain, keyed
	-- by this attack's id (a clip or a procedural move). Nothing visual lives here.
}

export type Enemy = {
	DisplayName: string,
	MaxHealth: number,
	Damage: number,
	MoveSpeed: number,
	AggroRange: number,
	AttackRange: number,
	-- Minimum time from the START of one attack to the start of the next.
	AttackCooldown: number,
	-- The attack cycle (playtest 5): Chase → hold at StandoffDistance → committed Windup (no
	-- turning, so it can be dodged) → one Strike at the end of the windup → Recovery, the
	-- punish window. StandoffDistance must be under AttackRange so the strike connects.
	-- Bosses with a moveset use their own per-attack timings; they only need the stand-off.
	StandoffDistance: number?,
	WindupTime: number?,
	RecoveryTime: number?,
	AttackName: string?, -- shown on the CAPTURED screen when this attack kills you
	-- Poise (E7): damage drains it; at zero the enemy staggers for StaggerDuration (its
	-- attack is cut, it can't act, it's open), then poise refills. It regenerates
	-- PoiseRegen per second after GameConfig.Poise.RegenDelay without a hit. Bosses have a
	-- lot but it MUST be reachable, or heavy attacks have no purpose against them.
	Poise: number,
	PoiseRegen: number,
	StaggerDuration: number,
	GoldMin: number,
	GoldMax: number,
	LootTable: string,
	BodyColor: Color3,
	BodySize: Vector3,
	Boss: boolean?,
	-- Presentation only: which body shape EnemyService dresses the rig in, so enemy types
	-- read apart as silhouettes (VISUAL_OVERHAUL_PLAN Phase 3). nil = plain rig.
	Silhouette: string?,
	-- Boss-only. Rotation is the fixed melee order; the attack named by RangedAttack is used
	-- instead when the target is out of melee reach. Fixed, not random: a player who dies
	-- should be able to learn the pattern (§12, §116), and run 1 stays deterministic (§115).
	Attacks: { [string]: Attack }?,
	Rotation: { string }?,
	RangedAttack: string?,
}

local EnemyConfig: { [string]: Enemy } = {
	-- The tutorial guard. Deliberately weak: 3-5 hits with the Bent Spoon. (§8, §116)
	sleepy_guard = {
		DisplayName = "Sleepy Guard",
		MaxHealth = 30,
		Damage = 4,
		MoveSpeed = 9,
		AggroRange = 30,
		AttackRange = 6,
		AttackCooldown = 1.6,
		-- Deliberately slow and readable: he's the tutorial's first fight (§116).
		StandoffDistance = 4.5,
		WindupTime = 1.0,
		RecoveryTime = 1.2,
		AttackName = "SWORD CHOP",
		Poise = 20, -- two Rusty Sword hits
		PoiseRegen = 8,
		StaggerDuration = 1.3,
		GoldMin = 8,
		GoldMax = 15,
		LootTable = "sleepy_guard",
		BodyColor = Color3.fromRGB(105, 110, 125),
		BodySize = Vector3.new(2, 4, 1),
		Silhouette = "Slouch", -- hunched, capped, sword drooping: harmless at a glance
	},

	-- Spawned by the alarm after the chest is opened. Applies pressure during the run out.
	alarm_guard = {
		DisplayName = "Guard",
		MaxHealth = 45,
		Damage = 7,
		MoveSpeed = 12,
		AggroRange = 55,
		AttackRange = 6,
		AttackCooldown = 1.3,
		-- Quicker than the sleepy guard, still generous: the alarm is pressure, not a wall.
		StandoffDistance = 4.5,
		WindupTime = 0.8,
		RecoveryTime = 0.9,
		AttackName = "SPEAR STRIKE",
		Poise = 30,
		PoiseRegen = 10,
		StaggerDuration = 1.1,
		GoldMin = 10,
		GoldMax = 18,
		LootTable = "alarm_guard",
		BodyColor = Color3.fromRGB(80, 70, 70),
		BodySize = Vector3.new(2, 4, 1),
		Silhouette = "Armored", -- helmed, upright, tall spear, `bleed` tabard: the alarm's threat
	},

	-- M2 miniboss (blueprint §12 "Captain", §18 template, §111 stats). Waits in his hall off
	-- the vault: visible from the cellblock door on run 1, but he only fights players who
	-- step into his hall. Losing to him on run 1 is intended. Tuned so a Rusty Sword player
	-- very likely loses, and Guard Sword + one weapon upgrade is a fair fight.
	captain_bronn = {
		DisplayName = "Captain Bronn",
		MaxHealth = 300,
		Damage = 18,
		MoveSpeed = 11,
		AggroRange = 60,
		AttackRange = 7,
		AttackCooldown = 0.5, -- gap between one attack's recovery and the next wind-up
		StandoffDistance = 5.5, -- he holds here instead of walking into you
		Poise = 110, -- about six Guard Sword hits inside the regen delay; a finisher helps
		PoiseRegen = 25,
		StaggerDuration = 1.6,
		GoldMin = 40,
		GoldMax = 60,
		LootTable = "captain_bronn",
		BodyColor = Palette.pitch,
		BodySize = Vector3.new(4, 7, 2.4),
		Boss = true,
		Attacks = {
			Cleave = {
				Name = "CLEAVE",
				Shape = "Box",
				DamageMultiplier = 1, -- 18
				WindUp = 0.7,
				Recovery = 0.9,
				Width = 10,
				Length = 9,
			},
			-- The heavy swing with the long wind-up (brief item 1). Dodge this or lose.
			CrushingBlow = {
				Name = "CRUSHING BLOW",
				Shape = "Circle",
				DamageMultiplier = 2.5, -- 45
				WindUp = 1.5,
				Recovery = 1.3,
				Radius = 8,
				Offset = 6,
			},
			-- Punishes hit-and-run kiting: the hall is not a safe place to stand at range.
			Charge = {
				Name = "CHARGE",
				Shape = "Charge",
				DamageMultiplier = 1.4, -- 25
				WindUp = 0.9,
				Recovery = 1.0,
				Width = 6,
				Length = 26,
			},
		},
		Rotation = { "Cleave", "Cleave", "CrushingBlow" },
		RangedAttack = "Charge",
	},
}

function EnemyConfig.Get(id: string): Enemy?
	local entry = rawget(EnemyConfig, id)
	if typeof(entry) == "table" and entry.MaxHealth then
		return entry :: Enemy
	end
	return nil
end

return EnemyConfig
