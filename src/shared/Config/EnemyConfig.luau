--!strict
-- EnemyConfig.lua  (blueprint §111)

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
}

function EnemyConfig.Get(id: string): Enemy?
	local entry = rawget(EnemyConfig, id)
	if typeof(entry) == "table" and entry.MaxHealth then
		return entry :: Enemy
	end
	return nil
end

return EnemyConfig
