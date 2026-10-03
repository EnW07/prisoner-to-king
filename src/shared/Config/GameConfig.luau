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
		-- How long a blow holds at impact before recovery: the "impact pause". The floor
		-- marker flashes solid for the same time. (Was StrikeFlashTime: same value.)
		ImpactPause = 0.15,
	},

	-- ── HUD / UI (client) ───────────────────────────────────────
	-- Timings are seconds. Everything tweens; nothing snaps (VISUAL_OVERHAUL_PLAN Phase 1).
	UI = {
		-- Unsecured bar (art §6, the signature element).
		UnsecuredBarFullAt = 300, -- unsecured gold that fills the bar; it stays full beyond
		BarFillTime = 0.3,
		PulseSlowPeriod = 1.4, -- pulse period with a nearly empty bar...
		PulseFastPeriod = 0.3, -- ...and with a full one. The pulse IS the tension.
		PulseDepth = 0.5, -- how far the fill fades at the bottom of each pulse
		SecureSweepTime = 0.45, -- on ESCAPE: fill sweeps across and turns gold
		SecureFlyTime = 0.4, -- then the amount flies into the Gold counter
		GoldRollTime = 0.7, -- the Gold counter rolls up rather than snapping
		-- Objective banner, toasts, full-screen moments, prompts.
		ObjectiveSwapTime = 0.3,
		ToastInTime = 0.25,
		ToastHoldTime = 1.6,
		ToastOutTime = 0.3,
		OverlayInTime = 0.3,
		OverlayHoldTime = 2.4, -- auto-dismiss; a tap dismisses sooner (§81: never trap the player)
		OverlayOutTime = 0.35,
		OverlayDim = 0.35, -- background transparency behind the card
		PromptFadeTime = 0.15,
		-- Prompt cards are sized in studs (BillboardGui scale), so they grow as you approach.
		PromptWidthStuds = 7,
		PromptHeightStuds = 2.2,
		PromptLiftStuds = 3,
		-- SWING touch button, as a fraction of the screen. Min size is UIStyle.MIN_TOUCH_PX.
		SwingButtonSize = 0.16,
		PopTime = 0.18, -- small "something changed" scale bounce
		PopScale = 1.12,
		PressScale = 0.9, -- touch button squash on press
	},

	-- ── Feel (client): procedural animation, all TweenService ───
	Feel = {
		-- Player weapon swing, in phases. Total stays under the fastest weapon cooldown (0.6s).
		SwingWindUp = 0.1,
		SwingStrike = 0.07,
		SwingFollowThrough = 0.1,
		SwingRecover = 0.2,
		-- Hit-stop: everything local freezes for a beat when a blow lands.
		HitStopTime = 0.06, -- your hit lands
		HeavyHitStopTime = 0.14, -- a kill, or taking a heavy blow
		HeavyHitDamage = 25, -- damage taken at or above this counts as heavy
		-- Camera kick strength, in degrees of shake (§40: a reduced-shake option comes later).
		KickHit = 0.7,
		KickKill = 1.4,
		KickTaken = 1.4,
		KickHeavyTaken = 3,
		-- Torches.
		TorchFlickerAmount = 0.3, -- +/- fraction of base brightness
		TorchFlickerSpeed = 7,
		TorchUpdateRate = 30, -- updates per second (not every frame: §46)
		-- Chest lid.
		ChestLidOpenAngle = 110, -- degrees
		ChestLidOpenTime = 0.45,
		-- Loot on the floor: bob and spin so it's visible.
		LootBobHeight = 0.45,
		LootBobPeriod = 1.6,
		LootSpinSpeed = 90, -- degrees per second
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
