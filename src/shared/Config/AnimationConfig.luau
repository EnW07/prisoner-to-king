--!strict
-- AnimationConfig.lua  (docs/RIGS_AND_VISUAL_UI_BRIEF.md §1 and §3)
-- Which animation plays for what. Data only: EnemyAnimator (server) and CombatController
-- (client) read it. Acquiring an animation pack means editing THIS file, nothing else.
--
-- Each slot is one of:
--   "default"              Roblox's own default R15 animation for that state. The id is read
--                          at runtime from the engine's Animate script (RigFactory), never
--                          typed in, so it can't be wrong.
--   "rbxassetid://123..."  Your animation. It must be owned by the experience owner (or by
--                          Roblox), or it won't load. Loading is pcall-wrapped: a bad id logs
--                          a warning and the slot falls back as if it were nil.
--   nil                    Nothing. Actions fall back to the procedural animation.
--
-- Locomotion and playback tuning (speed thresholds, fades) live in GameConfig.Animation.

local DEFAULT = "default"

local AnimationConfig = {}

AnimationConfig.DEFAULT = DEFAULT

-- Maps our slot names to the StringValue names in Roblox's Animate script.
AnimationConfig.DefaultNames = {
	Idle = "idle",
	Walk = "walk",
	Run = "run",
	Jump = "jump",
	Fall = "fall",
}

AnimationConfig.Sets = {
	Guard = {
		Idle = DEFAULT,
		Walk = DEFAULT,
		Run = DEFAULT,
		Jump = DEFAULT,
		Fall = DEFAULT,
		Attack = nil, -- nil: procedural arm swing (EnemyAnimator)
	},
	Captain = {
		Idle = DEFAULT,
		Walk = DEFAULT,
		Run = DEFAULT,
		Jump = DEFAULT,
		Fall = DEFAULT,
		-- Moveset. Keys are EnemyConfig.captain_bronn.Attacks ids. nil: procedural arm poses
		-- (CaptainService). A clip should land its hit at the attack's WindUp seconds.
		Cleave = nil,
		CrushingBlow = nil,
		Charge = nil,
	},
}

-- Which set each enemy uses. An enemy not listed here isn't animated.
AnimationConfig.Enemies = {
	sleepy_guard = "Guard",
	alarm_guard = "Guard",
	captain_bronn = "Captain",
}

-- The local player's own swing. nil: the procedural four-phase swing (CombatController).
AnimationConfig.Player = {
	Swing = nil,
}

return AnimationConfig
