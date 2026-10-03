--!strict
-- GameConfig.lua
-- Central balance + tuning. Per blueprint §114: no magic numbers scattered across services.
-- Change values here, not inside gameplay code.

export type Config = { [string]: any }

local GameConfig = {
	-- ── Persistence ─────────────────────────────────────────────
	Data = {
		StoreName = "PTK_PlayerProfile", -- bump only for a hard reset
		SchemaVersion = 1,
		AutosaveInterval = 120, -- seconds
		SaveRetries = 4,
		SaveRetryBackoff = 2, -- seconds, multiplied each retry
	},

	-- ── Player ──────────────────────────────────────────────────
	Player = {
		MaxHealth = 100,
		WalkSpeed = 18,
		JumpPower = 50,
		RespawnDelay = 2,
	},

	-- ── Combat ──────────────────────────────────────────────────
	Combat = {
		-- Server-side hit detection volume, projected in front of the attacker.
		Range = 8,
		Width = 6,
		Height = 6,
		MaxTargetsPerSwing = 3,
		-- Grace subtracted from cooldown checks to account for ping. Keep small.
		CooldownGrace = 0.08,
		-- Attack requests per second a client may send before being rate limited.
		MaxAttackRate = 5,
	},

	-- ── Run / extraction ────────────────────────────────────────
	Run = {
		ExtractionChannelTime = 3, -- hold duration on the extraction pad
		-- Fraction of UNSECURED gold lost on death. Equipped gear is never lost. (§14)
		DeathUnsecuredLossPercent = 1.0,
		AlarmGuardCount = 2,
		-- The CAPTURED screen names the attack that killed you if it landed this recently.
		DeathAttributionWindow = 10, -- seconds
	},

	-- ── Economy (§25 placeholders) ──────────────────────────────
	Economy = {
		FirstEscapeBonus = 100,
		ChestGold = 50,
		-- "UPGRADE YOUR WEAPONS": a permanent flat damage bonus on every weapon you hold.
		-- (Was WeaponRack*. "Armory" read as armour/defence in playtest 3.)
		WeaponUpgradeCost = 120,
		WeaponUpgradeDamageBonus = 5,
		WeaponUpgradeMaxLevel = 3,
	},

	-- ── Enemies ─────────────────────────────────────────────────
	Enemy = {
		ThinkInterval = 0.2, -- AI tick, NOT per-frame (§46)
		RespawnDelay = 25,
		CorpseDespawn = 3,
		LeashDistance = 90,
	},

	-- ── Captain Bronn (M2) ──────────────────────────────────────
	-- His stats and moveset are in EnemyConfig.captain_bronn. These values tune the encounter.
	Captain = {
		RespawnDelay = 60, -- after being killed
		-- With no player left in his hall for this long, he walks home and heals to full.
		-- Stops step-in / hit / step-out cheese.
		ResetDelay = 4,
		ReinforcementAtHealth = 0.5, -- fraction of MaxHealth; one call per fight
		ReinforcementEnemy = "alarm_guard",
		ChargeSpeed = 48, -- studs/s during the dash
		-- He only charges a target at least this far away, so it punishes kiting rather than
		-- every step back from a Cleave.
		ChargeMinRange = 14,
		HitHeightTolerance = 6, -- vertical slack on hit shapes
		-- When idle, he turns to watch the nearest player within this range (vault included).
		WatchRange = 90,
		HomeTolerance = 2, -- studs from his spawn point that count as "home"
		NameplateMaxDistance = 220, -- readable from the cellblock door, ~70 studs away
		TelegraphTransparency = 0.45,
		StrikeFlashTime = 0.15,
	},

	-- ── Analytics ───────────────────────────────────────────────
	Analytics = {
		Enabled = true,
		-- Custom events only report in a PUBLISHED experience. Studio logs to output.
		LogToOutputInStudio = true,
	},

	Debug = {
		Verbose = true,
	},
}

return GameConfig
