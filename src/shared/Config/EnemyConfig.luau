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
	-- Identity flags (Section F). EnemyService reads these as data; nothing special-cases
	-- an enemy id. Each enemy sets at most one or two.
	PreferredRange: number?, -- ranged: hold this distance...
	RetreatRange: number?, -- ...and back off when the player is closer than this
	RetreatStep: number?, -- how far each retreat step goes
	Projectile: { Speed: number, Range: number, Height: number, Size: Vector3?, Color: Color3? }?,
	Static: boolean?, -- never moves
	FixedAim: boolean?, -- fires along its spawn facing, not at the player
	Leap: { Range: number, MinRange: number, Speed: number, Lift: number, AirTime: number }?,
	Strafe: number?, -- studs of sideways weave while chasing
	Telegraph: { Radius: number }?, -- an area slam painted on the floor
	Shield: { Arc: number }?, -- blocks frontal hits inside this arc (degrees)
	LightPoiseImmune: boolean?, -- only heavy / guard-breaking hits move its poise
	-- Variety (F7): per-spawn scale range and body tint jitter.
	Variation: { Scale: { number }?, Tint: number? }?,
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
	-- Boss-only (G1): at AtHealth of MaxHealth he transitions once: roars, calls his
	-- reinforcement, his attacks run at TimeScale of their timings, and the rotation
	-- changes (usually gaining a move).
	PhaseTwo: { AtHealth: number, Rotation: { string }, TimeScale: number }?,
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
		Variation = { Scale = { 0.96, 1.06 }, Tint = 0.08 },
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
		Variation = { Scale = { 0.97, 1.08 }, Tint = 0.06 },
	},

	-- ARCHER (F2). Identity: punishes standing still, weak up close. Holds twenty studs,
	-- backs off when you close, and every shot has a long, visible draw. Two hits kill it.
	-- The first real positioning problem: fight the guard while being shot, or break off
	-- and kill the archer first.
	archer = {
		DisplayName = "Archer",
		MaxHealth = 16,
		Damage = 9,
		MoveSpeed = 13,
		AggroRange = 42,
		AttackRange = 28,
		AttackCooldown = 2.2,
		PreferredRange = 20,
		RetreatRange = 11,
		RetreatStep = 8,
		WindupTime = 0.9,
		RecoveryTime = 0.7,
		AttackName = "ARROW",
		Projectile = { Speed = 55, Range = 50, Height = 1.8 },
		Poise = 10,
		PoiseRegen = 8,
		StaggerDuration = 1,
		GoldMin = 8,
		GoldMax = 14,
		LootTable = "archer",
		BodyColor = Color3.fromRGB(70, 85, 70),
		BodySize = Vector3.new(1.7, 4, 0.9),
		Silhouette = "Archer", -- hooded, lean, a bow in the left hand, a quiver
		Variation = { Scale = { 0.95, 1.04 }, Tint = 0.08 },
	},

	-- SHIELD GUARD (F3). Identity: a lock with a specific key. Frontal light attacks do
	-- nothing but ring the shield. A heavy attack breaks the guard; so does getting behind
	-- him. Slow, tough, weak hitter.
	shield_guard = {
		DisplayName = "Shield Guard",
		MaxHealth = 70,
		Damage = 6,
		MoveSpeed = 8,
		AggroRange = 30,
		AttackRange = 6,
		AttackCooldown = 1.8,
		StandoffDistance = 4.5,
		WindupTime = 1.1,
		RecoveryTime = 1.2,
		AttackName = "SHIELD BASH",
		Shield = { Arc = 150 },
		Poise = 40,
		PoiseRegen = 10,
		StaggerDuration = 1.6,
		GoldMin = 12,
		GoldMax = 20,
		LootTable = "shield_guard",
		BodyColor = Color3.fromRGB(95, 90, 100),
		BodySize = Vector3.new(2.4, 4.2, 1.2),
		Silhouette = "Shield", -- a round shield on the left arm, helmed, broad
		Variation = { Scale = { 0.98, 1.05 }, Tint = 0.05 },
	},

	-- HOUND (F4). Identity: pressure. Fast, erratic, almost no health, leaps at you, comes
	-- in packs. Appears with the alarm in the sewer and at high wanted levels.
	hound = {
		DisplayName = "Hound",
		MaxHealth = 14,
		Damage = 6,
		MoveSpeed = 22,
		AggroRange = 60,
		AttackRange = 5, -- the bite radius at landing
		AttackCooldown = 1.5,
		StandoffDistance = 3.5,
		WindupTime = 0.45,
		RecoveryTime = 0.7,
		AttackName = "BITE",
		Leap = { Range = 16, MinRange = 6, Speed = 34, Lift = 14, AirTime = 0.4 },
		Strafe = 4,
		Poise = 8,
		PoiseRegen = 6,
		StaggerDuration = 0.8,
		GoldMin = 3,
		GoldMax = 7,
		LootTable = "hound",
		BodyColor = Color3.fromRGB(55, 45, 40),
		BodySize = Vector3.new(1.7, 2.3, 1.6),
		Silhouette = "Hound", -- low, long, snout and ears, hunched onto all fours
		Variation = { Scale = { 0.92, 1.08 }, Tint = 0.12 },
	},

	-- CROSSBOW SENTRY (F5). Identity: area denial. Never moves. Fires along one line on a
	-- fixed interval, whether or not you're in it. A corridor becomes a timing problem.
	crossbow_sentry = {
		DisplayName = "Sentry",
		MaxHealth = 40,
		Damage = 12,
		MoveSpeed = 0,
		AggroRange = 48,
		AttackRange = 48,
		AttackCooldown = 2.4, -- the interval
		WindupTime = 0.5, -- the crossbow comes up: the click before the shot
		RecoveryTime = 0.4,
		AttackName = "CROSSBOW BOLT",
		Static = true,
		FixedAim = true,
		Projectile = { Speed = 70, Range = 48, Height = 1.6, Size = Vector3.new(0.2, 0.2, 2) },
		Poise = 30,
		PoiseRegen = 10,
		StaggerDuration = 1.2,
		GoldMin = 6,
		GoldMax = 12,
		LootTable = "sentry",
		BodyColor = Color3.fromRGB(80, 75, 80),
		BodySize = Vector3.new(2, 4, 1),
		Silhouette = "Sentry", -- kneeling behind a heavy crossbow
	},

	-- BRUTE (F6). Identity: an unmissable threat that changes the room. Huge, slow,
	-- enormous damage, a telegraphed ground slam painted on the floor. Light attacks can't
	-- stagger it. When one is in a room, the room is about the brute.
	brute = {
		DisplayName = "Brute",
		MaxHealth = 160,
		Damage = 30,
		MoveSpeed = 7,
		AggroRange = 36,
		AttackRange = 9,
		AttackCooldown = 2.6,
		StandoffDistance = 6,
		WindupTime = 1.6,
		RecoveryTime = 1.8,
		AttackName = "GROUND SLAM",
		Telegraph = { Radius = 9 },
		LightPoiseImmune = true,
		Poise = 60,
		PoiseRegen = 15,
		StaggerDuration = 2,
		GoldMin = 25,
		GoldMax = 40,
		LootTable = "brute",
		BodyColor = Color3.fromRGB(110, 85, 75),
		BodySize = Vector3.new(3.4, 6.4, 2.1),
		Silhouette = "Brute", -- a wall of a man with a club the size of a door
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
			-- Phase two only: a full circle around him. The answer is distance, not a side
			-- step. (The sword is lit by then; the spin sells it.)
			FlameSweep = {
				Name = "FLAME SWEEP",
				Shape = "Circle",
				DamageMultiplier = 1.3, -- 23
				WindUp = 1.1,
				Recovery = 1.1,
				Radius = 9,
				Offset = 0,
			},
		},
		Rotation = { "Cleave", "Cleave", "CrushingBlow" },
		RangedAttack = "Charge",
		PhaseTwo = {
			AtHealth = 0.5,
			Rotation = { "Cleave", "CrushingBlow", "FlameSweep", "Cleave" },
			TimeScale = 0.82, -- modestly faster: readable, not a different fight
		},
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
