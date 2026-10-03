--!strict
-- GameConfig.lua
-- Central balance + tuning. Per blueprint §114: no magic numbers scattered across services.
-- Change values here, not inside gameplay code.

export type Config = { [string]: any }

local GameConfig = {
	-- ── Persistence ─────────────────────────────────────────────
	Data = {
		StoreName = "PTK_PlayerProfile", -- bump only for a hard reset
		-- 2 (2026-10-03): Meta.CaptainKills (the hideout trophy) and Meta.LuckCharge (the
		-- pity meter). See PlayerDataService.migrate.
		SchemaVersion = 2,
		AutosaveInterval = 120, -- seconds
		SaveRetries = 4,
		SaveRetryBackoff = 2, -- seconds, multiplied each retry
	},

	-- ── Player ──────────────────────────────────────────────────
	Player = {
		MaxHealth = 100,
		WalkSpeed = 18,
		JumpPower = 50,
	},

	-- ── Death (Section D; §66 tension, lesson, quick retry) ─────
	Death = {
		-- The killing blow's freeze on the client, and the hold before the server ragdolls
		-- the body: the same length, so the body goes limp as the freeze ends.
		HitStop = 0.15,
		-- Colour drains over this long (ColorCorrectionEffect), to this saturation.
		DesaturateTime = 0.4,
		Saturation = -0.85,
		Contrast = 0.08,
		-- The camera detaches and drifts back and up from where it is. Never a cut.
		CameraDriftTime = 2.6,
		CameraBack = 13, -- studs behind the body, along the camera's own view
		CameraUp = 8,
		-- CAPTURED fades in after this beat, over CardInTime.
		CardDelay = 1.1,
		CardInTime = 0.45,
		-- TRY AGAIN respawns at once; doing nothing respawns after this.
		AutoRespawnDelay = 8,
		MaxRespawnRate = 1, -- RespawnRequest per second before rate limiting
		ProfileWaitTimeout = 15, -- the first spawn waits this long for the profile at most
		RestoreTime = 0.35, -- colour back on respawn
		-- Enemies: the pose holds this long at the frame of death before the ragdoll, and
		-- the body fades out over CorpseFadeTime after Enemy.CorpseDespawn.
		EnemyHold = 0.15,
		CorpseFadeTime = 0.7,
	},

	-- ── Combat ──────────────────────────────────────────────────
	Combat = {
		-- Server-side hit detection volume, projected in front of the attacker. Depth is the
		-- weapon's Reach (WeaponConfig); these are the cross-section.
		Width = 6,
		Height = 6,
		MaxTargetsPerSwing = 3,
		-- Part cap for the swing's overlap query (enemy parts only). R15 rigs are ~15-20
		-- parts each with costume, so this covers MaxTargetsPerSwing enemies with room to spare.
		OverlapMaxParts = 120,
		-- Grace subtracted from cooldown checks to account for ping. Keep small.
		CooldownGrace = 0.08,
		-- Attack requests per second a client may send before being rate limited.
		MaxAttackRate = 5,
		-- The light combo (E3): damage per stage (the weapon's Combo list indexes this), and
		-- the last stage is the finisher: biggest arc, most hit-stop, and it shoves the enemy
		-- back by this impulse (studs/s, per unit mass) on top of the weapon's own. (E8)
		ComboDamage = { 1, 1.1, 1.35 },
		FinisherKnockback = 28,
		-- The heavy attack (E2): hold the attack input this long and release. Slower, more
		-- damage, breaks guard, knocks back, hits poise harder. The cooldown is per weapon.
		HeavyHoldTime = 0.35,
		HeavyKnockback = 24,
		HeavyPoiseMultiplier = 1.6,
		HeavyReachBonus = 1, -- studs added to the weapon's reach on a heavy
		HeavyAfterLightFraction = 0.5, -- a heavy can't land sooner than this share of the light cooldown
		-- Forward magnetism (§11 "no precision aim required for melee", K3 soft target
		-- assist): if nothing is in the swing box but an enemy is within reach and inside
		-- this half-angle of the facing, the box is tested toward it instead. Server-side,
		-- so phones and mice get the same help.
		AssistAngle = 50, -- degrees either side of the facing
		AssistReachFactor = 1.1,
		-- A light hit that doesn't break poise still rocks an enemy that isn't mid-attack by
		-- this much (E8 "a real flinch on light hits").
		FlinchKnockback = 6,
	},

	-- ── Dash (E1): the highest-value addition in the project ────
	-- Without a dodge an enemy telegraph is just a delay. With one, every windup is a
	-- decision. The client bursts at once for responsiveness; the server validates the
	-- cooldown and owns the invincibility window, which is the part that matters.
	Dash = {
		Distance = 14, -- studs covered
		Duration = 0.18, -- seconds of burst (Distance / Duration is the speed)
		IFrameWindow = 0.32, -- seconds of invincibility from the server's grant
		Cooldown = 1.1,
		MaxRate = 3, -- DashRequest per second before rate limiting
		-- Feedback. Afterimages are limb snapshots that fade; the FOV punches out and back.
		AfterimageCount = 3,
		AfterimageLife = 0.35,
		FovPunch = 9, -- degrees added at the start of the dash
		FovTime = 0.35, -- seconds to settle back
	},

	-- ── Wanted (L1; §15) ────────────────────────────────────────
	Wanted = {
		MaxLevel = 3,
		Thresholds = { 20, 50, 90 }, -- heat at which levels I, II, III begin
		HeatCapFactor = 1.3, -- heat can't exceed the top threshold times this
		HeatKill = 12,
		HeatChest = 30,
		HeatSeen = 6,
		SeenHeatInterval = 5, -- seconds between "seen" heat ticks
		HeatBreak = 2,
		HeatBell = 45, -- the alarm bell: the voluntary way up
		DecayDelay = 8, -- seconds unseen before heat starts to fall
		DecayPerSecond = 1.5,
		TickInterval = 1,
		-- By level (index = level + 1): the gold multiplier on everything you loot, and the
		-- seconds between reinforcements (0 = none) drawn from the pool for that level.
		GoldMultiplier = { 1, 1.15, 1.35, 1.6 },
		SpawnInterval = { 0, 25, 14, 9 },
		SpawnEnemies = {
			{},
			{ "alarm_guard" },
			{ "alarm_guard", "archer" },
			{ "alarm_guard", "shield_guard", "archer" },
		},
		MaxReinforcements = 6, -- alive at once from this system, server-wide
		MinSpawnDistance = 30, -- never from an entrance closer than this
		HoundPackAt = 3, -- at this level every other arrival is a hound pack
		HoundPackSize = 2,
	},

	-- ── Co-play (L3): the minimum that produces the signal, always additive ──
	CoPlay = {
		Window = 20, -- seconds: two extractions within it pay both players the bonus
		Bonus = 60, -- flat gold, on top of everything; never a penalty for solo play
		DownedEligibleRange = 45, -- a killing blow downs you instead if a friend is this close
		DownedTime = 8, -- seconds to be revived before the death happens anyway
		DownedHealth = 1,
		ReviveRange = 8,
		ReviveHold = 2.5,
		RevivedHealthFraction = 0.4,
	},

	-- ── Poise (E7) ──────────────────────────────────────────────
	Poise = {
		RegenDelay = 1.5, -- seconds after the last hit before poise starts refilling
		-- A stagger's pose: the hit share of StaggerDuration, the rest is the sway back up.
		StaggerHitShare = 0.12,
	},

	-- ── Rooms (RoomService) ─────────────────────────────────────
	Rooms = {
		CheckInterval = 0.4, -- seconds between room checks (not every frame, §46)
		-- Per-room lighting notes (K2): the client tweens Lighting.Ambient and OutdoorAmbient
		-- to these on entry. Neutrals only shift; functional colours never (art §3).
		AmbienceTime = 1.2,
		Ambience = {
			["THE CELLS"] = { Ambient = Color3.fromRGB(34, 36, 46), Outdoor = Color3.fromRGB(70, 74, 90) },
			["THE GUARD ROOM"] = {
				Ambient = Color3.fromRGB(52, 42, 38),
				Outdoor = Color3.fromRGB(110, 90, 80),
			},
			["THE LONG HALL"] = {
				Ambient = Color3.fromRGB(46, 44, 50),
				Outdoor = Color3.fromRGB(120, 105, 90),
			},
			["THE KITCHENS"] = { Ambient = Color3.fromRGB(56, 44, 34), Outdoor = Color3.fromRGB(120, 95, 70) },
			["THE BARRACKS"] = { Ambient = Color3.fromRGB(28, 28, 34), Outdoor = Color3.fromRGB(60, 60, 70) },
			["THE VAULT"] = { Ambient = Color3.fromRGB(52, 48, 40), Outdoor = Color3.fromRGB(130, 115, 85) },
			["THE CHAPEL"] = { Ambient = Color3.fromRGB(50, 42, 36), Outdoor = Color3.fromRGB(110, 95, 85) },
			["THE POSTERN"] = {
				Ambient = Color3.fromRGB(44, 46, 52),
				Outdoor = Color3.fromRGB(100, 104, 120),
			},
			["BRONN'S HALL"] = { Ambient = Color3.fromRGB(56, 40, 40), Outdoor = Color3.fromRGB(120, 85, 80) },
			["THE SEWERS"] = { Ambient = Color3.fromRGB(26, 30, 32), Outdoor = Color3.fromRGB(55, 65, 65) },
		},
	},

	-- ── VFX (K1; all ParticleEmitter, Beam, Trail, Highlight: no imported assets) ──
	VFX = {
		-- Weapon trails during swings, coloured by rarity.
		TrailTime = 0.45, -- seconds the trail stays enabled after a swing starts
		TrailLifetime = 0.16,
		TrailWidth = 1,
		-- Hit puffs (stylised dust, no gore, §74) emitted with the sparks.
		PuffCount = 4,
		-- Dust motes in light shafts; torch embers and smoke; the extraction shimmer.
		MoteRate = 2.5,
		EmberRate = 3,
		SmokeRate = 1.2,
		ShimmerRate = 6,
		ShimmerRateAlarm = 18,
		-- Chest-opening burst and Bronn's phase burst.
		ChestBurst = 40,
		PhaseBurst = 60,
		-- Loot beams on the floor: height and width by rarity tier (Common..Mythic).
		BeamHeight = 14,
		BeamWidth = { 0.5, 0.6, 0.9, 1.1, 1.4, 1.8 },
		-- Boss impacts shake nearby players: full strength inside this range, fading to zero
		-- at ImpactFarRange, through the reduced-shake setting.
		ImpactNearRange = 14,
		ImpactFarRange = 50,
		-- Footsteps (K4): seconds per stride at walking speed, and the hook's volume.
		StrideInterval = 0.38,
		FootstepVolume = 0.35,
	},

	-- ── Environmental interaction (EnvironmentService; H4) ──────
	Environment = {
		PromptRange = 12,
		-- Breakables: crates and barrels. Chunks fly; a little loot; they come back later.
		BreakChunks = 5,
		ChunkLife = 1.2,
		BreakableRespawn = 90,
		LootTables = { crate = "crate", barrel = "barrel" },
		-- Chandeliers: cut the chain, it falls ChandelierDrop studs, everything under it hurts.
		ChandelierDrop = 13,
		ChandelierFallTime = 0.45,
		ChandelierRadius = 7,
		ChandelierDamage = 70,
		ChandelierKnockback = 30,
		ChandelierReset = 60,
		ChandelierRaiseTime = 4,
		-- The barrable door: enemies can't pass for this long, then they break it.
		BarDuration = 20,
	},

	-- ── Secrets and side rooms (H3, H5) ─────────────────────────
	Secrets = {
		LooseBrickGold = { 25, 40 }, -- unsecured gold in the live loose brick
		SewerStashGold = { 40, 70 },
		ChapelRelicGold = 120, -- the relic: a lot, in one piece, deep in the castle
	},

	-- ── Player settings (client; J2 builds the panel) ───────────
	Settings = {
		ReducedShake = false, -- §40: halves hit-stop kicks and skips boss shake
		ReducedShakeFactor = 0.35,
		CameraSensitivity = 1,
		MusicVolume = 0.8,
		SfxVolume = 1,
	},

	-- ── Inventory (M2 item 4) ──────────────────────────────────
	Inventory = {
		MaxEquipRate = 3, -- equip requests per second before rate limiting
		MaxWeaponIdLength = 64, -- reject anything longer before even looking it up
	},

	-- ── Run / extraction ────────────────────────────────────────
	Run = {
		ExtractionChannelTime = 3, -- hold duration on the extraction pad
		-- Fraction of UNSECURED gold lost on death; the rest is banked. Equipped gear is
		-- never lost. (§14; L4: §94 lists full loss as a way to kill the game with young
		-- players.)
		DeathUnsecuredLossPercent = 0.5,
		AlarmGuardCount = 2,
		-- Hounds reach the sewer this long after the alarm (F4: what makes carrying 500
		-- unsecured gold to the exit frightening).
		AlarmHoundDelay = 7,
		AlarmHoundCount = 2,
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
		MaxUpgradeRate = 2, -- UpgradeRequest per second before rate limiting
	},

	-- ── Pity / bad-luck protection (§13, I5) ───────────────────
	-- Boss kills add Luck Charge; at FullCharge the next boss chest guarantees Rare or
	-- better. Shown in the HUD as a bar with a number. The charge is persisted by the
	-- SchemaVersion 2 migration (L5); until then it reads 0.
	Pity = {
		FullCharge = 100,
		PerBossKill = 34, -- three Captain kills fill it
	},

	-- ── Enemies ─────────────────────────────────────────────────
	Enemy = {
		ThinkInterval = 0.2, -- AI tick, NOT per-frame (§46)
		-- (There is no RespawnDelay: guards you kill stay dead for the run. New guards arrive
		-- through the wanted system, from entrances. L1.)
		CorpseDespawn = 4, -- seconds a dead enemy lies there before it fades (Death.CorpseFadeTime)
		LeashDistance = 90,
		-- The attack cycle's strike area: a box in front of the enemy, along the facing it
		-- committed to at the start of its windup. Reach is the enemy's AttackRange.
		StrikeWidth = 5,
		StrikeBackReach = 1.5, -- a player overlapping the enemy's own position still counts
		StrikeHeight = 5, -- vertical slack, for ramps and stairs
		-- Hysteresis around StandoffDistance: closer than (stand-off - slack) and the enemy
		-- steps back to it, so it never presses into you.
		StandoffSlack = 1,
		-- R15 rigs (RigFactory): a body this size gets scale 1. It's the M1 guard's BodySize,
		-- so EnemyConfig.BodySize keeps meaning exactly what it did.
		RigReferenceSize = Vector3.new(2, 4, 1),
		-- Spawns: rigs are stood on the floor found by a short ray down from the spawn point.
		SpawnProbeLift = 2,
		SpawnProbeDepth = 30,
		PackSpread = 3, -- studs between members of a pack (SpawnPack)
		-- Awareness (F8): the notice beat before an enemy engages, a shorter one when it's
		-- hit, and how long after losing you it will be surprised again.
		AlertTime = 0.6,
		AlertTimeHit = 0.25,
		AlertCooldown = 6,
		AlertMarkPx = 64, -- the "!" over the head
		AlertHearFactor = 1.5, -- players within AggroRange x this hear the alert hook
		-- A target is kept while within AggroRange x this, sight or not.
		ChaseRangeFactor = 1.5,
		-- Variety (F7): attack timing varies ± this fraction per attack.
		TimingJitter = 0.15,
		-- Sleepers (barracks): notice range while asleep, and how long waking takes.
		SleepNoticeRange = 7,
		WakeTime = 1.1,
		StrafeSpeed = 3, -- radians/s of a strafing enemy's weave
	},

	-- ── Enemy projectiles (ProjectileService; F2, F5) ───────────
	Projectile = {
		MaxLive = 24, -- shots in flight at once, server-wide
		Lifetime = 6, -- seconds before a shot is removed whatever happened
		StickTime = 1.2, -- a shot that hit the world stays there this long
		DefaultSize = Vector3.new(0.25, 0.25, 2.6),
	},

	-- ── Captain Bronn (M2) ──────────────────────────────────────
	-- His stats and moveset are in EnemyConfig.captain_bronn. These values tune the encounter.
	Captain = {
		RespawnDelay = 60, -- after being killed
		-- With no player left in his hall for this long, he walks home and heals to full.
		-- Stops step-in / hit / step-out cheese.
		ResetDelay = 4,
		-- The phase transition (G1) happens at EnemyConfig.captain_bronn.PhaseTwo.AtHealth.
		-- He roars for this long, invulnerable, while a reinforcement arrives.
		ReinforcementEnemy = "alarm_guard",
		PhaseRoarTime = 1.7,
		-- Boss death (G3): the frame of the final blow holds this long before the body goes
		-- and the reward drops. The client stretches its hit-stop to match.
		DeathHold = 1.4,
		-- Client: the phase transition's screen flash and camera push, and how hard each
		-- landed blow shakes nearby players (times the attack's DamageMultiplier).
		PhaseFlashTime = 0.45,
		PhaseKick = 4,
		ImpactKick = 1.6,
		ChargeSpeed = 48, -- studs/s during the dash
		-- He only charges a target at least this far away, so it punishes kiting rather than
		-- every step back from a Cleave.
		ChargeMinRange = 14,
		HitHeightTolerance = 6, -- vertical slack on hit shapes
		-- When idle, he turns to watch the nearest player within this range (vault included).
		WatchRange = 90,
		HomeTolerance = 2, -- studs from his spawn point that count as "home"
		NameplateMaxDistance = 220, -- readable from the cellblock door, ~70 studs away
		-- How often to check Bronn is present (outside his respawn window).
		WatchdogInterval = 5,
		-- His boss bar (client, BossBarController): face, name, health, attack callout.
		PortraitPx = 56, -- the bar is pixel-sized so it stays legible at distance
		PortraitFov = 35,
		PortraitMargin = 1.05,
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
		-- Touch combat buttons (ControlButton), as fractions of the screen; the floor is
		-- UIStyle.MIN_TOUCH_PX. SWING is largest; DASH sits left of it with a gap.
		SwingButtonSize = 0.16,
		DashButtonSize = 0.13,
		HeavyButtonSize = 0.13,
		ControlGap = 0.02,
		-- 3D item icons (ViewportIcon). Close camera so icons read at phone size.
		ViewportFov = 30,
		ViewportMargin = 1.08, -- 1 = the model's largest extent exactly fills the view
		ViewportTiltDegrees = 45, -- weapons shown on the diagonal
		ViewportSpinSpeed = 45, -- degrees per second, spinning icons only
		-- Inventory grid: cell size as a fraction of the grid (3 across), and how far the
		-- rarity colour is darkened into `pitch` at the top of a slot's background gradient.
		InventoryCellWidth = 0.3,
		InventoryCellHeight = 0.46,
		RarityGradientDarken = 0.55,
		-- Loot reveal (§81: presentation scales with value). Seconds on screen per rarity.
		-- A tap ends it early, so the player is never trapped in it.
		RevealHold = {
			Common = 1.3,
			Uncommon = 1.8,
			Rare = 2.8,
			Epic = 3.2,
			Legendary = 3.6,
			Mythic = 4,
		},
		RevealInTime = 0.35,
		RevealFlyTime = 0.4, -- into the weapon slot
		RevealFlyScale = 0.25,
		PopTime = 0.18, -- small "something changed" scale bounce
		PopScale = 1.12,
		PressScale = 0.9, -- touch button squash on press
		-- Health bar (J2): bottom, right of the weapon slot. Fractions of the screen.
		HealthX = 0.165,
		HealthWidth = 0.24,
		HealthHeight = 0.05,
		HealthLowFraction = 0.3, -- at or below: `bleed`, the pulse and the vignette
		HealthFlashTime = 0.25,
		HealthGhostDelay = 0.2, -- the lost-health ghost waits this long, then catches up
		HealthGhostTime = 0.45,
		HealthPulsePeriod = 0.9,
		VignetteDepth = 0.18, -- how far the edge glow reaches into the screen
		VignetteMin = 0.55, -- transparency at the pulse's strongest...
		VignetteMax = 0.9, -- ...and weakest
		-- Objective arrow (J2): under the objective banner.
		ArrowSize = 0.07,
		ArrowY = 0.1,
		ArrowHideDistance = 6, -- studs: this close, you are there
		-- Enemy health bars (J2): pixel-sized, fading in on the first hit, out when disengaged.
		EnemyBarPx = 150,
		EnemyBarMaxDistance = 80,
		EnemyBarHold = 4, -- seconds after the last hit before it fades
		EnemyBarFade = 0.2,
		-- WANTED (J2): pulses at the top level.
		WantedPulsePeriod = 0.6,
		-- The settings gear, top-right.
		GearSize = 0.05,
	},

	-- ── Animation playback (EnemyAnimator; ids live in AnimationConfig) ──
	Animation = {
		FadeTime = 0.15, -- crossfade between locomotion clips
		MoveThreshold = 0.5, -- studs/s: below this an enemy idles
		RunThreshold = 13, -- studs/s: at or above this it runs instead of walks
		WalkReferenceSpeed = 16, -- clip playback speed = actual speed / this
		UpdateInterval = 0.15, -- seconds between locomotion updates (not every frame: §46)
		-- Idle variation: each enemy's idle clip runs at 1 ± this speed, from a random
		-- start, so a room of guards doesn't breathe in unison (C4).
		IdleSpeedJitter = 0.12,
		-- Procedural breathing for a rig with no idle clip (a static idle reads as frozen).
		BreathDegrees = 1.5,
		BreathPeriod = 3.2,
		-- Procedural enemy attacks (PoseAnimator moves, used while AnimationConfig has no
		-- Attack clip). The wind-up fills EnemyConfig.WindupTime minus StrikeLead; the strike
		-- arc starts StrikeLead before the server's hit test so the blade ARRIVES as damage
		-- applies, then holds ImpactHold; recovery fills RecoverShare of RecoveryTime.
		StrikeLead = 0.1,
		ImpactHold = 0.12,
		RecoverShare = 0.85,
		-- How long a cancelled or interrupted pose takes to ease back to rest.
		RelaxTime = 0.25,
		-- Player light combo: a swing within this many seconds of the last continues the
		-- chain (stage 1 → 2 → 3); any longer and it restarts at 1. Client-visual for now; the
		-- server mirrors it when combo damage lands (E3).
		ComboWindow = 1.1,
	},

	-- ── Feel (client): procedural animation, all TweenService ───
	Feel = {
		-- Hit-stop: everything local freezes for a beat when a blow lands. Scaled by the
		-- hit's damage relative to HeavyHitDamage, between the two multipliers (E8).
		HitStopTime = 0.06, -- your hit lands
		HeavyHitStopTime = 0.14, -- a kill, or taking a heavy blow
		HeavyHitDamage = 25, -- damage at or above this counts as heavy
		HitScaleMin = 0.6,
		HitScaleMax = 1.8,
		FinisherHitStopBonus = 1.5, -- the combo finisher's hit-stop multiplier
		-- Camera kick strength, in degrees of shake, scaled like hit-stop. Honours the
		-- reduced-shake setting (Settings.ReducedShakeFactor).
		KickHit = 0.7,
		KickKill = 1.4,
		KickTaken = 1.4,
		KickHeavyTaken = 3,
		-- Damage numbers grow with significance: 1 at nothing, up to this at HeavyHitDamage
		-- and above; a kill adds KillNumberBonus on top.
		NumberScaleMax = 1.9,
		KillNumberBonus = 0.4,
		-- Impact sparks at the contact point, and the killing blow's flash.
		SparkCount = 10,
		SparkCountHeavy = 22,
		SparkCountKill = 36,
		KillFlashTime = 0.22,
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
