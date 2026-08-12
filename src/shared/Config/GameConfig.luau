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
	},

	-- ── Economy (§25 placeholders) ──────────────────────────────
	Economy = {
		FirstEscapeBonus = 100,
		ChestGold = 50,
		WeaponRackCost = 120,
		WeaponRackDamageBonus = 5,
		WeaponRackMaxLevel = 3,
	},

	-- ── Enemies ─────────────────────────────────────────────────
	Enemy = {
		ThinkInterval = 0.2, -- AI tick, NOT per-frame (§46)
		RespawnDelay = 25,
		CorpseDespawn = 3,
		LeashDistance = 90,
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
