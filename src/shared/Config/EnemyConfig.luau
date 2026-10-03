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
	Pose: string, -- sword pose during the wind-up, see CaptainService.POSES
}

export type Enemy = {
	DisplayName: string,
	MaxHealth: number,
	Damage: number,
	MoveSpeed: number,
	AggroRange: number,
	AttackRange: number,
	AttackCooldown: number,
	GoldMin: number,
	GoldMax: number,
	LootTable: string,
	BodyColor: Color3,
	BodySize: Vector3,
	Boss: boolean?,
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
		GoldMin = 8,
		GoldMax = 15,
		LootTable = "sleepy_guard",
		BodyColor = Color3.fromRGB(105, 110, 125),
		BodySize = Vector3.new(2, 4, 1),
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
		GoldMin = 10,
		GoldMax = 18,
		LootTable = "alarm_guard",
		BodyColor = Color3.fromRGB(80, 70, 70),
		BodySize = Vector3.new(2, 4, 1),
	},

	-- M2 miniboss (blueprint §12 "Captain", §18 template, §111 stats). Waits in his hall off
	-- the vault: visible from the cellblock door on run 1, but he only fights players who
	-- step into his hall. Losing to him on run 1 is intended. Tuned so a Rusty Sword player
	-- very likely loses, and Guard Sword + one armory level is a fair fight.
	captain_bronn = {
		DisplayName = "Captain Bronn",
		MaxHealth = 300,
		Damage = 18,
		MoveSpeed = 11,
		AggroRange = 60,
		AttackRange = 7,
		AttackCooldown = 0.5, -- gap between one attack's recovery and the next wind-up
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
				Pose = "Cleave",
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
				Pose = "Overhead",
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
				Pose = "Lowered",
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
