--!strict
-- AnimationConfig.lua  (MASTER_BUILD_SPEC Section C; RIGS_AND_VISUAL_UI_BRIEF §1, §3)
-- Everything about how characters move, as DATA. Three layers:
--
--   1. SETS and SLOTS — which clip plays for what. Each slot is one of:
--        "default"              Roblox's own R15 animation for that state. The id is read
--                               at runtime from the engine's Animate script (RigFactory),
--                               never typed in, so it can't be wrong.
--        "rbxassetid://123..."  Your animation. Must be owned by the experience owner (or
--                               Roblox). Loading is pcall-wrapped: a bad id warns and falls
--                               back as if it were nil.
--        nil                    Nothing: the slot falls back to the PROCEDURAL move named
--                               in the set's Procedural map, played by PoseAnimator.
--      THIS IS THE IMPORT CONTRACT (C6). Dropping an animation pack in means editing a slot
--      here, nothing else. Every procedural move below is replaceable by a clip this way.
--
--   2. POSES — a set of joint angles, in degrees, in Rig's semantic frame:
--        x pitch (positive = forward / lean forward), y yaw (positive = across the body on
--        limbs, toward the left on the torso), z roll (positive = out to the side), and an
--        optional P = { x, y, z } translation in studs (scaled to the rig).
--      Joints not named in a pose return to rest. Rest is {} by definition.
--
--   3. MOVES — ordered poses with per-step TweenInfo and per-joint delays, in up to three
--      phases: Wind, Strike, Recover. The step list is the character of the motion:
--        Wind    eases OUT, slowly: the anticipation the player reacts to. Big attacks have
--                a big, slow wind-up (Back/Out snaps into it; Sine/InOut keeps creeping
--                deeper until the release).
--        Strike  eases IN, fast and hard (Quint/In accelerates into the target), then a
--                follow-through step with Back/Out so the limb carries past and settles.
--        Recover eases InOut, slow and heavy. The punish window, visibly.
--      Delay = { Joint = seconds } offsets a joint's start inside a step: the torso leads,
--      the arm follows, the wrist (and the weapon welded to the hand) lags last. Hold keeps
--      the pose after the tween. Times are authored for a Medium weapon; Weights rescale
--      them per class, and a caller may instead supply exact phase durations (an enemy's
--      WindupTime), which rescale a phase's steps in proportion.
--
-- Locomotion playback tuning (speed thresholds, fades) lives in GameConfig.Animation.

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

-- ── 1. Sets and slots ───────────────────────────────────────────
AnimationConfig.Sets = {
	Guard = {
		Idle = DEFAULT,
		Walk = DEFAULT,
		Run = DEFAULT,
		Jump = DEFAULT,
		Fall = DEFAULT,
		-- nil: procedural. A clip starts at the windup and should land its hit at the
		-- enemy's WindupTime.
		Attack = nil,
		Alert = nil,
		Stagger = nil,
		Block = nil,
		Procedural = { Attack = "GuardChop", Alert = "Alert", Stagger = "Stagger", Block = "ShieldBlock" },
	},
	Spearman = {
		Idle = DEFAULT,
		Walk = DEFAULT,
		Run = DEFAULT,
		Jump = DEFAULT,
		Fall = DEFAULT,
		Attack = nil,
		Alert = nil,
		Stagger = nil,
		Block = nil,
		Procedural = { Attack = "SpearThrust", Alert = "Alert", Stagger = "Stagger", Block = "ShieldBlock" },
	},
	Captain = {
		Idle = DEFAULT,
		Walk = DEFAULT,
		Run = DEFAULT,
		Jump = DEFAULT,
		Fall = DEFAULT,
		-- Moveset. Keys are EnemyConfig.captain_bronn.Attacks ids. A clip should land its
		-- hit at the attack's WindUp seconds.
		Cleave = nil,
		CrushingBlow = nil,
		Charge = nil,
		Roar = nil,
		Stagger = nil,
		Procedural = {
			Cleave = "BronnCleave",
			CrushingBlow = "BronnCrush",
			Charge = "BronnCharge",
			Roar = "BronnRoar",
			Stagger = "Stagger",
		},
		-- A resting posture baked into the rig at spawn; every move is relative to it.
		Posture = "BronnStance",
	},
}

-- Which set each enemy uses. An enemy not listed here isn't animated.
AnimationConfig.Enemies = {
	sleepy_guard = "Guard",
	alarm_guard = "Spearman",
	captain_bronn = "Captain",
}

-- The local player's own actions. Locomotion (idle with breathing, walk, run, jump, fall)
-- is Roblox's Animate script, which player characters always get. Each slot: a clip id, or
-- nil for the procedural move in Procedural.
AnimationConfig.Player = {
	Light1 = nil,
	Light2 = nil,
	Light3 = nil,
	Heavy = nil,
	Dash = nil,
	Block = nil,
	HitReact = nil,
	Land = nil,
	Interact = nil,
	Celebrate = nil,
	Death = nil,
	Procedural = {
		Light1 = "Light1",
		Light2 = "Light2",
		Light3 = "Light3",
		Heavy = "Heavy",
		Dash = "Dash",
		Block = "Block",
		HitReact = "HitReact",
		Land = "Land",
		Interact = "Interact",
		Celebrate = "Celebrate",
		Death = "Collapse",
	},
}

-- ── Weight classes (C2 "weight") ────────────────────────────────
-- Phase time multipliers and how much the body joins in (Body scales torso, head, root and
-- leg angles). A hammer and a dagger must not share timing values. WeaponConfig.Weight
-- names one of these.
AnimationConfig.Weights = {
	Light = { Wind = 0.7, Strike = 0.85, Recover = 0.7, Body = 0.55 },
	Medium = { Wind = 1, Strike = 1, Recover = 1, Body = 1 },
	Heavy = { Wind = 1.5, Strike = 1.05, Recover = 1.6, Body = 1.35 },
}

-- ── 2. Poses ────────────────────────────────────────────────────
-- Angles in degrees. See the header for the frame. Rest = {}.
AnimationConfig.Poses = {
	Rest = {},

	-- Player light combo, stage 1: a diagonal chop from over the right shoulder, down and
	-- across the body. The torso coils right then unwinds left; the head counter-turns to
	-- stay on the target; the left arm counter-balances.
	L1Wind = {
		RightShoulder = { x = 165, y = 10, z = 25 },
		RightElbow = { x = 55 },
		RightWrist = { x = -15 },
		LeftShoulder = { x = 30, z = 15 },
		LeftElbow = { x = 20 },
		Waist = { x = -8, y = -25 },
		Neck = { x = -5, y = 22 },
		Root = { x = -3 },
		RightHip = { x = -5 },
		LeftHip = { x = 5 },
	},
	L1Hit = {
		RightShoulder = { x = 25, y = -5, z = -20 },
		RightElbow = { x = 10 },
		RightWrist = { x = -25 },
		LeftShoulder = { x = -25, z = 20 },
		Waist = { x = 12, y = 28 },
		Neck = { x = 8, y = -22 },
		Root = { x = 4 },
		RightHip = { x = 6 },
		LeftHip = { x = -4 },
	},
	L1Through = {
		RightShoulder = { x = -5, y = -15, z = -35 },
		RightElbow = { x = 5 },
		RightWrist = { x = -10 },
		LeftShoulder = { x = -30, z = 25 },
		Waist = { x = 14, y = 34 },
		Neck = { x = 8, y = -24 },
		Root = { x = 5 },
		RightHip = { x = 6 },
		LeftHip = { x = -4 },
	},

	-- Stage 2: a backhand, swept horizontally from across the body out to the right.
	L2Wind = {
		RightShoulder = { x = 85, y = 50, z = -10 },
		RightElbow = { x = 60 },
		RightWrist = { y = 20 },
		LeftShoulder = { x = 40, y = -20, z = -10 },
		Waist = { x = -4, y = 30 },
		Neck = { y = -20 },
		Root = { y = 4 },
	},
	L2Hit = {
		RightShoulder = { x = 80, y = -45, z = 55 },
		RightElbow = { x = 10 },
		RightWrist = { y = -20 },
		LeftShoulder = { x = -10, z = 25 },
		Waist = { x = 8, y = -30 },
		Neck = { y = 25 },
		Root = { y = -5 },
	},
	L2Through = {
		RightShoulder = { x = 60, y = -65, z = 70 },
		RightElbow = { x = 5 },
		LeftShoulder = { x = -15, z = 28 },
		Waist = { x = 8, y = -36 },
		Neck = { y = 28 },
		Root = { y = -6 },
	},

	-- Stage 3, the finisher: a two-handed overhead slam, the biggest arc, dropping the
	-- whole body into it. Passes through L3Mid so the path is an arc, not a line.
	L3Wind = {
		RightShoulder = { x = 185, y = -5, z = 10 },
		RightElbow = { x = 70 },
		RightWrist = { x = -20 },
		LeftShoulder = { x = 175, y = -10, z = 10 },
		LeftElbow = { x = 60 },
		Waist = { x = -20 },
		Neck = { x = -15 },
		Root = { x = -6, P = { 0, 0.15, 0 } },
		RightHip = { x = -8 },
		LeftHip = { x = -8 },
	},
	L3Mid = {
		RightShoulder = { x = 110, z = 5 },
		RightElbow = { x = 20 },
		LeftShoulder = { x = 105, z = 5 },
		LeftElbow = { x = 15 },
		Waist = { x = 10 },
		Neck = { x = 5 },
		Root = { x = 2 },
	},
	L3Hit = {
		RightShoulder = { x = 40, z = -5 },
		RightElbow = { x = 5 },
		RightWrist = { x = -30 },
		LeftShoulder = { x = 35, z = -5 },
		Waist = { x = 35 },
		Neck = { x = 20 },
		Root = { x = 10, P = { 0, -0.45, 0 } },
		RightHip = { x = 30 },
		LeftHip = { x = 30 },
		RightKnee = { x = -55 },
		LeftKnee = { x = -55 },
	},
	L3Through = {
		RightShoulder = { x = 15, z = -10 },
		LeftShoulder = { x = 10, z = -8 },
		Waist = { x = 38 },
		Neck = { x = 22 },
		Root = { x = 11, P = { 0, -0.4, 0 } },
		RightHip = { x = 28 },
		LeftHip = { x = 28 },
		RightKnee = { x = -50 },
		LeftKnee = { x = -50 },
	},

	-- Heavy attack: a one-handed overhead from a sideways coil. Distinct from the finisher
	-- (torso twists, not just bends) and paced by the Heavy weight class.
	HeavyWind = {
		RightShoulder = { x = 175, y = -20, z = 40 },
		RightElbow = { x = 80 },
		RightWrist = { x = -20 },
		LeftShoulder = { x = 60, z = 20 },
		LeftElbow = { x = 30 },
		Waist = { x = -15, y = -35 },
		Neck = { x = -10, y = 30 },
		Root = { x = -5, y = -8, P = { 0, 0.1, 0 } },
	},
	HeavyWindDeep = {
		RightShoulder = { x = 190, y = -25, z = 45 },
		RightElbow = { x = 90 },
		RightWrist = { x = -25 },
		LeftShoulder = { x = 65, z = 22 },
		LeftElbow = { x = 32 },
		Waist = { x = -20, y = -42 },
		Neck = { x = -12, y = 36 },
		Root = { x = -7, y = -10, P = { 0, 0.15, 0.1 } },
	},
	HeavyMid = {
		RightShoulder = { x = 110, y = -5, z = 15 },
		RightElbow = { x = 20 },
		LeftShoulder = { x = 20, z = 15 },
		Waist = { x = 10, y = -5 },
		Neck = { x = 5 },
		Root = { x = 3 },
	},
	HeavyHit = {
		RightShoulder = { x = 35, y = 15, z = -15 },
		RightElbow = { x = 5 },
		RightWrist = { x = -30 },
		LeftShoulder = { x = -25, z = 25 },
		Waist = { x = 30, y = 25 },
		Neck = { x = 15, y = -20 },
		Root = { x = 10, y = 10, P = { 0, -0.4, -0.1 } },
		RightHip = { x = 30 },
		LeftHip = { x = 30 },
		RightKnee = { x = -55 },
		LeftKnee = { x = -55 },
	},
	HeavyThrough = {
		RightShoulder = { x = 10, y = 20, z = -25 },
		LeftShoulder = { x = -30, z = 28 },
		Waist = { x = 34, y = 30 },
		Neck = { x = 18, y = -24 },
		Root = { x = 12, y = 12, P = { 0, -0.38, -0.1 } },
		RightHip = { x = 28 },
		LeftHip = { x = 28 },
		RightKnee = { x = -50 },
		LeftKnee = { x = -50 },
	},

	-- Dash: a hard forward lean, arms trailing.
	DashLean = {
		Waist = { x = 22 },
		Neck = { x = -12 },
		Root = { x = 8 },
		RightShoulder = { x = -35, z = 10 },
		LeftShoulder = { x = -35, z = 10 },
		RightElbow = { x = 30 },
		LeftElbow = { x = 30 },
		RightHip = { x = 20 },
		LeftHip = { x = -10 },
	},

	-- Block: weapon raised across the face, weight down.
	BlockGuard = {
		RightShoulder = { x = 75, y = 35, z = -20 },
		RightElbow = { x = 70 },
		RightWrist = { x = 20, y = 30 },
		LeftShoulder = { x = 65, y = 20, z = 10 },
		LeftElbow = { x = 60 },
		Waist = { x = 8 },
		Neck = { x = 5 },
		Root = { x = 3, P = { 0, -0.15, 0 } },
		RightHip = { x = 12 },
		LeftHip = { x = 12 },
		RightKnee = { x = -20 },
		LeftKnee = { x = -20 },
	},

	-- Taking a hit: a flinch back and to the side.
	HitFlinch = {
		Waist = { x = -14, y = 12 },
		Neck = { x = -18, y = -10 },
		Root = { x = -5, P = { 0, 0, 0.15 } },
		RightShoulder = { x = 25, z = 25 },
		LeftShoulder = { x = 20, z = 25 },
		RightElbow = { x = 30 },
		LeftElbow = { x = 30 },
	},

	-- Landing: a squash, then Back/Out stretches it back up.
	LandSquash = {
		Waist = { x = 18 },
		Neck = { x = -10 },
		Root = { x = 4, P = { 0, -0.35, 0 } },
		RightHip = { x = 30 },
		LeftHip = { x = 30 },
		RightKnee = { x = -50 },
		LeftKnee = { x = -50 },
		RightShoulder = { x = 20, z = 15 },
		LeftShoulder = { x = 20, z = 15 },
	},

	-- Interact: reach forward with the right hand.
	Reach = {
		RightShoulder = { x = 75, y = 10 },
		RightElbow = { x = 15 },
		Waist = { x = 12, y = -6 },
		Neck = { x = 15 },
		LeftShoulder = { x = 10, z = 5 },
	},

	-- Extract celebration: both arms up, a bounce.
	CheerUp = {
		RightShoulder = { x = 170, z = 25 },
		LeftShoulder = { x = 170, z = 25 },
		RightElbow = { x = 20 },
		LeftElbow = { x = 20 },
		Waist = { x = -8 },
		Neck = { x = -18 },
		Root = { P = { 0, 0.15, 0 } },
	},
	CheerDown = {
		RightShoulder = { x = 150, z = 35 },
		LeftShoulder = { x = 150, z = 35 },
		RightElbow = { x = 30 },
		LeftElbow = { x = 30 },
		Waist = { x = -4 },
		Neck = { x = -10 },
		Root = { P = { 0, -0.1, 0 } },
	},

	-- Death fallback when a ragdoll isn't possible: knees go, torso folds, arms drop.
	Collapse = {
		Waist = { x = 40, z = 10 },
		Neck = { x = 35 },
		Root = { x = 15, P = { 0, -0.9, 0 } },
		RightHip = { x = 50 },
		LeftHip = { x = 50 },
		RightKnee = { x = -100 },
		LeftKnee = { x = -100 },
		RightShoulder = { x = 30, z = 10 },
		LeftShoulder = { x = 30, z = 10 },
	},

	-- Guard chop (enemies): the same family as Light1, with a long, readable wind-up that
	-- keeps drawing back until the release, and a rise onto the toes as it coils.
	ChopWind = {
		RightShoulder = { x = 160, y = 10, z = 25 },
		RightElbow = { x = 55 },
		RightWrist = { x = -15 },
		LeftShoulder = { x = 30, z = 15 },
		LeftElbow = { x = 20 },
		Waist = { x = -8, y = -25 },
		Neck = { x = -5, y = 22 },
		Root = { x = -3 },
	},
	ChopWindDeep = {
		RightShoulder = { x = 185, y = 15, z = 30 },
		RightElbow = { x = 70 },
		RightWrist = { x = -20 },
		LeftShoulder = { x = 35, z = 18 },
		LeftElbow = { x = 25 },
		Waist = { x = -12, y = -32 },
		Neck = { x = -8, y = 28 },
		Root = { x = -5, P = { 0, 0.1, 0 } },
	},
	ChopHit = {
		RightShoulder = { x = 25, y = -5, z = -20 },
		RightElbow = { x = 10 },
		RightWrist = { x = -25 },
		LeftShoulder = { x = -25, z = 20 },
		Waist = { x = 14, y = 28 },
		Neck = { x = 8, y = -22 },
		Root = { x = 5, P = { 0, -0.1, -0.1 } },
	},
	ChopThrough = {
		RightShoulder = { x = -5, y = -15, z = -35 },
		RightElbow = { x = 5 },
		RightWrist = { x = -10 },
		LeftShoulder = { x = -30, z = 25 },
		Waist = { x = 16, y = 34 },
		Neck = { x = 8, y = -24 },
		Root = { x = 6, P = { 0, -0.12, -0.12 } },
	},

	-- Spear thrust (spearmen): drawn back at the hip, a rock back, then a lunge.
	ThrustWind = {
		RightShoulder = { x = 55, y = -15, z = 15 },
		RightElbow = { x = 80 },
		RightWrist = { x = 10 },
		LeftShoulder = { x = 70, y = 25, z = -10 },
		LeftElbow = { x = 20 },
		Waist = { x = -6, y = -35 },
		Neck = { y = 32 },
		Root = { y = -8 },
		RightHip = { x = -10 },
		LeftHip = { x = 12 },
	},
	ThrustWindDeep = {
		RightShoulder = { x = 45, y = -20, z = 20 },
		RightElbow = { x = 95 },
		RightWrist = { x = 12 },
		LeftShoulder = { x = 72, y = 28, z = -10 },
		LeftElbow = { x = 22 },
		Waist = { x = -10, y = -42 },
		Neck = { y = 38 },
		Root = { y = -10, P = { 0, 0, 0.25 } },
		RightHip = { x = -12 },
		LeftHip = { x = 14 },
	},
	ThrustHit = {
		RightShoulder = { x = 95, y = 5, z = -5 },
		RightElbow = { x = 0 },
		RightWrist = { x = -5 },
		LeftShoulder = { x = 20, y = -10, z = 10 },
		Waist = { x = 15, y = 20 },
		Neck = { x = 5, y = -15 },
		Root = { x = 6, y = 6, P = { 0, -0.1, -0.5 } },
		RightHip = { x = 25 },
		LeftHip = { x = -25 },
	},
	ThrustThrough = {
		RightShoulder = { x = 100, y = 8, z = -8 },
		RightElbow = { x = 0 },
		LeftShoulder = { x = 15, y = -10, z = 12 },
		Waist = { x = 18, y = 24 },
		Neck = { x = 5, y = -17 },
		Root = { x = 7, y = 7, P = { 0, -0.12, -0.55 } },
		RightHip = { x = 27 },
		LeftHip = { x = -27 },
	},

	-- Alert (enemies noticing you): the head snaps up, the shoulders rise, the weapon
	-- comes up, then settles into a ready stance. The body turn is the Humanoid's.
	AlertSnap = {
		RightShoulder = { x = 45, z = 20 },
		RightElbow = { x = 40 },
		LeftShoulder = { x = 25, z = 25 },
		LeftElbow = { x = 30 },
		Waist = { x = -8 },
		Neck = { x = -15 },
		Root = { P = { 0, 0.12, 0 } },
	},
	AlertReady = {
		RightShoulder = { x = 35, z = 10 },
		RightElbow = { x = 30 },
		LeftShoulder = { x = 15, z = 15 },
		LeftElbow = { x = 20 },
		Waist = { x = 4 },
		Neck = { x = -5 },
	},

	-- Stagger (poise broken): thrown back and off balance, then a sway, then upright.
	StaggerBack = {
		Waist = { x = -22, y = 10, z = -6 },
		Neck = { x = -25 },
		Root = { x = -10, P = { 0, -0.1, 0.3 } },
		RightShoulder = { x = 40, z = 35 },
		LeftShoulder = { x = 35, z = 35 },
		RightElbow = { x = 40 },
		LeftElbow = { x = 40 },
		RightHip = { x = -15 },
		LeftHip = { x = 15 },
		RightKnee = { x = -20 },
		LeftKnee = { x = -20 },
	},
	StaggerSway = {
		Waist = { x = -10, y = -8 },
		Neck = { x = -12, y = 8 },
		Root = { x = -4, P = { 0, -0.05, 0.2 } },
		RightShoulder = { x = 20, z = 20 },
		LeftShoulder = { x = 15, z = 20 },
		RightElbow = { x = 20 },
		LeftElbow = { x = 20 },
	},

	-- Shield block (shield guards): the shield arm comes up; a recoil when it takes a hit.
	ShieldUp = {
		LeftShoulder = { x = 70, y = 30, z = -5 },
		LeftElbow = { x = 80 },
		Waist = { x = 6, y = -10 },
		Neck = { x = 3 },
		Root = { x = 2, P = { 0, -0.1, 0 } },
	},
	ShieldRecoil = {
		LeftShoulder = { x = 60, y = 40, z = 5 },
		LeftElbow = { x = 85 },
		Waist = { x = -8, y = -18 },
		Neck = { x = -6 },
		Root = { x = -4, P = { 0, 0, 0.2 } },
	},

	-- Captain Bronn. His resting stance, then three attacks each with a wind-up pose so
	-- distinct it reads from the first frame with the sound off (G1).
	BronnStance = {
		RightShoulder = { x = 15, z = 8 },
		LeftShoulder = { z = 6 },
		Waist = { x = 4 },
		Neck = { x = -3 },
	},
	-- CLEAVE: the greatsword drawn far out to his right, torso coiled, head on you.
	BronnCleaveWind = {
		RightShoulder = { x = 20, y = -40, z = 95 },
		RightElbow = { x = 25 },
		RightWrist = { y = 10 },
		LeftShoulder = { x = 45, y = 10, z = 20 },
		LeftElbow = { x = 30 },
		Waist = { x = -6, y = -45 },
		Neck = { y = 38 },
		Root = { x = -3, y = -10 },
		RightHip = { x = -12, z = 5 },
		LeftHip = { x = 10 },
	},
	BronnCleaveWindDeep = {
		RightShoulder = { x = 25, y = -55, z = 100 },
		RightElbow = { x = 30 },
		RightWrist = { y = 12 },
		LeftShoulder = { x = 48, y = 12, z = 22 },
		LeftElbow = { x = 32 },
		Waist = { x = -10, y = -55 },
		Neck = { y = 45 },
		Root = { x = -4, y = -14, P = { 0, 0.08, 0.15 } },
		RightHip = { x = -14, z = 5 },
		LeftHip = { x = 12 },
	},
	BronnCleaveHit = {
		RightShoulder = { x = 5, y = 100, z = 90 },
		RightElbow = { x = 5 },
		RightWrist = { y = -15 },
		LeftShoulder = { x = -15, z = 30 },
		Waist = { x = 12, y = 50 },
		Neck = { x = 5, y = -40 },
		Root = { x = 4, y = 14, P = { 0, -0.15, -0.2 } },
		RightHip = { x = 15 },
		LeftHip = { x = -12 },
	},
	BronnCleaveThrough = {
		RightShoulder = { y = 125, z = 85 },
		RightElbow = { x = 5 },
		LeftShoulder = { x = -20, z = 32 },
		Waist = { x = 14, y = 60 },
		Neck = { x = 6, y = -45 },
		Root = { x = 5, y = 18, P = { 0, -0.18, -0.25 } },
		RightHip = { x = 16 },
		LeftHip = { x = -13 },
	},
	-- CRUSHING BLOW: both arms straight up, leaning back, the whole body then drops into it.
	BronnCrushWind = {
		RightShoulder = { x = 180, y = -5, z = 15 },
		RightElbow = { x = 60 },
		RightWrist = { x = -20 },
		LeftShoulder = { x = 165, y = -10, z = 15 },
		LeftElbow = { x = 50 },
		Waist = { x = -22, y = -5 },
		Neck = { x = -20 },
		Root = { x = -8, P = { 0, 0.2, 0.1 } },
		RightHip = { x = -10 },
		LeftHip = { x = -10 },
	},
	BronnCrushWindDeep = {
		RightShoulder = { x = 195, y = -8, z = 20 },
		RightElbow = { x = 70 },
		RightWrist = { x = -25 },
		LeftShoulder = { x = 180, y = -12, z = 18 },
		LeftElbow = { x = 60 },
		Waist = { x = -30, y = -8 },
		Neck = { x = -25 },
		Root = { x = -12, P = { 0, 0.3, 0.2 } },
		RightHip = { x = -12 },
		LeftHip = { x = -12 },
	},
	BronnCrushMid = {
		RightShoulder = { x = 110, z = 10 },
		RightElbow = { x = 15 },
		LeftShoulder = { x = 100, z = 10 },
		LeftElbow = { x = 10 },
		Waist = { x = 15 },
		Neck = { x = 10 },
		Root = { x = 4, P = { 0, 0, -0.1 } },
	},
	BronnCrushHit = {
		RightShoulder = { x = 35 },
		RightElbow = { x = 5 },
		RightWrist = { x = -30 },
		LeftShoulder = { x = 30 },
		Waist = { x = 42 },
		Neck = { x = 25 },
		Root = { x = 14, P = { 0, -0.7, -0.3 } },
		RightHip = { x = 35 },
		LeftHip = { x = 35 },
		RightKnee = { x = -65 },
		LeftKnee = { x = -65 },
	},
	BronnCrushThrough = {
		RightShoulder = { x = 25, z = -5 },
		RightElbow = { x = 5 },
		LeftShoulder = { x = 20, z = -5 },
		Waist = { x = 45 },
		Neck = { x = 28 },
		Root = { x = 15, P = { 0, -0.65, -0.3 } },
		RightHip = { x = 34 },
		LeftHip = { x = 34 },
		RightKnee = { x = -62 },
		LeftKnee = { x = -62 },
	},
	-- CHARGE: the sword levelled like a lance, weight rocked back, then the run, then
	-- stuck and open at the end.
	BronnChargeWind = {
		RightShoulder = { x = 70, y = -10, z = 10 },
		RightElbow = { x = 30 },
		LeftShoulder = { x = -30, z = 15 },
		Waist = { x = -12, y = -20 },
		Neck = { x = -8, y = 15 },
		Root = { x = -6, P = { 0, 0, 0.35 } },
		RightHip = { x = -20 },
		LeftHip = { x = 25 },
		LeftKnee = { x = -30 },
	},
	BronnChargeWindDeep = {
		RightShoulder = { x = 65, y = -15, z = 12 },
		RightElbow = { x = 35 },
		LeftShoulder = { x = -35, z = 16 },
		Waist = { x = -18, y = -26 },
		Neck = { x = -10, y = 20 },
		Root = { x = -9, P = { 0, -0.1, 0.5 } },
		RightHip = { x = -24 },
		LeftHip = { x = 28 },
		LeftKnee = { x = -34 },
	},
	BronnChargeRun = {
		RightShoulder = { x = 95, y = 5, z = -5 },
		RightElbow = { x = 5 },
		LeftShoulder = { x = -45, z = 15 },
		Waist = { x = 25, y = 10 },
		Neck = { x = -15, y = -10 },
		Root = { x = 12, P = { 0, -0.15, -0.3 } },
	},
	BronnChargeStuck = {
		RightShoulder = { x = 100, z = -10 },
		RightElbow = { x = 0 },
		LeftShoulder = { x = 10, z = 20 },
		Waist = { x = 35, y = 5 },
		Neck = { x = -5 },
		Root = { x = 15, P = { 0, -0.3, -0.4 } },
		RightHip = { x = 20 },
		LeftHip = { x = -20 },
	},
	-- ROAR (phase transition): arms thrown wide and up, chest out, head back.
	RoarUp = {
		RightShoulder = { x = 160, z = 45 },
		LeftShoulder = { x = 160, z = 45 },
		RightElbow = { x = 40 },
		LeftElbow = { x = 40 },
		Waist = { x = -25 },
		Neck = { x = -35 },
		Root = { x = -10, P = { 0, 0.25, 0 } },
	},
	RoarHold = {
		RightShoulder = { x = 150, z = 60 },
		LeftShoulder = { x = 150, z = 60 },
		RightElbow = { x = 30 },
		LeftElbow = { x = 30 },
		Waist = { x = -28 },
		Neck = { x = -40 },
		Root = { x = -12, P = { 0, 0.3, 0 } },
	},
}

-- ── 3. Moves ────────────────────────────────────────────────────
-- Times are seconds for a Medium weapon (see Weights), or shares when the caller fills a
-- phase with its own duration (enemy WindupTime / RecoveryTime, Bronn's WindUp / Recovery).
local ARM_LAG = { RightShoulder = 0.03, RightElbow = 0.03, RightWrist = 0.05 } -- torso leads
local WRIST_LAG = { RightWrist = 0.03 } -- the hand, and the weapon in it, whips last
local ARM_LAST = { RightShoulder = 0.05, RightElbow = 0.05, RightWrist = 0.05 } -- torso settles first

AnimationConfig.Moves = {
	-- Player light combo (E3). Each stage bigger than the last; the third is the finisher.
	Light1 = {
		Wind = { { Pose = "L1Wind", Time = 0.16, Style = "Sine", Dir = "Out", Delay = ARM_LAG } },
		Strike = {
			{ Pose = "L1Hit", Time = 0.1, Style = "Quint", Dir = "In", Delay = WRIST_LAG },
			{ Pose = "L1Through", Time = 0.12, Style = "Back", Dir = "Out", Delay = WRIST_LAG },
		},
		Recover = { { Pose = "Rest", Time = 0.28, Style = "Sine", Dir = "InOut", Delay = ARM_LAST } },
	},
	Light2 = {
		Wind = { { Pose = "L2Wind", Time = 0.15, Style = "Sine", Dir = "Out", Delay = ARM_LAG } },
		Strike = {
			{ Pose = "L2Hit", Time = 0.1, Style = "Quint", Dir = "In", Delay = WRIST_LAG },
			{ Pose = "L2Through", Time = 0.12, Style = "Back", Dir = "Out", Delay = WRIST_LAG },
		},
		Recover = { { Pose = "Rest", Time = 0.3, Style = "Sine", Dir = "InOut", Delay = ARM_LAST } },
	},
	Light3 = {
		Wind = { { Pose = "L3Wind", Time = 0.22, Style = "Sine", Dir = "Out", Delay = ARM_LAG, Hold = 0.04 } },
		Strike = {
			{ Pose = "L3Mid", Time = 0.05, Style = "Quad", Dir = "In" },
			{ Pose = "L3Hit", Time = 0.07, Style = "Quint", Dir = "In", Delay = WRIST_LAG },
			{ Pose = "L3Through", Time = 0.14, Style = "Back", Dir = "Out", Delay = WRIST_LAG, Hold = 0.06 },
		},
		Recover = { { Pose = "Rest", Time = 0.38, Style = "Sine", Dir = "InOut", Delay = ARM_LAST } },
	},
	-- Heavy attack (E2): slow coil, hard drop, long heavy recovery.
	Heavy = {
		Wind = {
			{ Pose = "HeavyWind", Time = 0.3, Style = "Back", Dir = "Out", Delay = ARM_LAG },
			{ Pose = "HeavyWindDeep", Time = 0.2, Style = "Sine", Dir = "InOut" },
		},
		Strike = {
			{ Pose = "HeavyMid", Time = 0.06, Style = "Quad", Dir = "In" },
			{ Pose = "HeavyHit", Time = 0.08, Style = "Quint", Dir = "In", Delay = WRIST_LAG },
			{
				Pose = "HeavyThrough",
				Time = 0.14,
				Style = "Back",
				Dir = "Out",
				Delay = WRIST_LAG,
				Hold = 0.1,
			},
		},
		Recover = { { Pose = "Rest", Time = 0.45, Style = "Sine", Dir = "InOut", Delay = ARM_LAST } },
	},
	Dash = {
		Strike = { { Pose = "DashLean", Time = 0.08, Style = "Quad", Dir = "Out" } },
		Recover = { { Pose = "Rest", Time = 0.25, Style = "Sine", Dir = "Out" } },
	},
	-- Block has no Recover: the owner holds it and calls Relax on release.
	Block = {
		Strike = { { Pose = "BlockGuard", Time = 0.12, Style = "Back", Dir = "Out" } },
	},
	HitReact = {
		Strike = { { Pose = "HitFlinch", Time = 0.07, Style = "Back", Dir = "Out", Hold = 0.05 } },
		Recover = { { Pose = "Rest", Time = 0.3, Style = "Sine", Dir = "Out" } },
	},
	Land = {
		Strike = { { Pose = "LandSquash", Time = 0.08, Style = "Quad", Dir = "Out" } },
		Recover = { { Pose = "Rest", Time = 0.28, Style = "Back", Dir = "Out" } },
	},
	Interact = {
		Strike = { { Pose = "Reach", Time = 0.15, Style = "Sine", Dir = "Out", Hold = 0.25 } },
		Recover = { { Pose = "Rest", Time = 0.3, Style = "Sine", Dir = "InOut" } },
	},
	Celebrate = {
		Strike = {
			{ Pose = "CheerUp", Time = 0.25, Style = "Back", Dir = "Out", Hold = 0.2 },
			{ Pose = "CheerDown", Time = 0.3, Style = "Sine", Dir = "InOut" },
			{ Pose = "CheerUp", Time = 0.3, Style = "Sine", Dir = "InOut", Hold = 0.3 },
		},
		Recover = { { Pose = "Rest", Time = 0.4, Style = "Sine", Dir = "InOut" } },
	},
	Collapse = {
		Strike = { { Pose = "Collapse", Time = 0.35, Style = "Quad", Dir = "In" } },
	},

	-- Enemy attacks. Phases are filled with WindupTime / strike window / RecoveryTime by
	-- EnemyAnimator, so these times are proportions. Wind: a snap into the draw-back
	-- (30%), then a slow creep deeper (70%) until the release. Strike: a Quint/In arc
	-- timed to arrive as the server's hit test fires, then a Back/Out follow-through that
	-- holds. Recover: a slow InOut return, torso first, arm last.
	GuardChop = {
		Wind = {
			{ Pose = "ChopWind", Time = 0.3, Style = "Back", Dir = "Out", Delay = ARM_LAG },
			{ Pose = "ChopWindDeep", Time = 0.7, Style = "Sine", Dir = "InOut" },
		},
		Strike = {
			{ Pose = "ChopHit", Time = 0.1, Style = "Quint", Dir = "In", Delay = WRIST_LAG },
			{ Pose = "ChopThrough", Time = 0.1, Style = "Back", Dir = "Out", Delay = WRIST_LAG, Hold = 0.12 },
		},
		Recover = { { Pose = "Rest", Time = 1, Style = "Sine", Dir = "InOut", Delay = ARM_LAST } },
	},
	SpearThrust = {
		Wind = {
			{ Pose = "ThrustWind", Time = 0.3, Style = "Back", Dir = "Out", Delay = ARM_LAG },
			{ Pose = "ThrustWindDeep", Time = 0.7, Style = "Sine", Dir = "InOut" },
		},
		Strike = {
			{ Pose = "ThrustHit", Time = 0.08, Style = "Quint", Dir = "In", Delay = WRIST_LAG },
			{ Pose = "ThrustThrough", Time = 0.1, Style = "Back", Dir = "Out", Hold = 0.14 },
		},
		Recover = { { Pose = "Rest", Time = 1, Style = "Sine", Dir = "InOut", Delay = ARM_LAST } },
	},
	Alert = {
		Strike = { { Pose = "AlertSnap", Time = 0.12, Style = "Back", Dir = "Out", Hold = 0.25 } },
		Recover = { { Pose = "AlertReady", Time = 0.3, Style = "Sine", Dir = "Out" } },
	},
	-- Filled with the enemy's StaggerDuration (E7).
	Stagger = {
		Strike = { { Pose = "StaggerBack", Time = 0.1, Style = "Back", Dir = "Out" } },
		Recover = {
			{ Pose = "StaggerSway", Time = 0.4, Style = "Sine", Dir = "InOut" },
			{ Pose = "Rest", Time = 0.35, Style = "Sine", Dir = "InOut" },
		},
	},
	ShieldBlock = {
		Strike = { { Pose = "ShieldRecoil", Time = 0.06, Style = "Quad", Dir = "Out", Hold = 0.08 } },
		Recover = { { Pose = "ShieldUp", Time = 0.25, Style = "Back", Dir = "Out" } },
	},

	-- Captain Bronn. Phases filled with each attack's WindUp / impact pause / Recovery.
	BronnCleave = {
		Wind = {
			{ Pose = "BronnCleaveWind", Time = 0.3, Style = "Back", Dir = "Out", Delay = ARM_LAG },
			{ Pose = "BronnCleaveWindDeep", Time = 0.7, Style = "Sine", Dir = "InOut" },
		},
		Strike = {
			{ Pose = "BronnCleaveHit", Time = 0.1, Style = "Quint", Dir = "In", Delay = WRIST_LAG },
			{
				Pose = "BronnCleaveThrough",
				Time = 0.1,
				Style = "Back",
				Dir = "Out",
				Delay = WRIST_LAG,
				Hold = 0.15,
			},
		},
		Recover = { { Pose = "Rest", Time = 1, Style = "Sine", Dir = "InOut", Delay = ARM_LAST } },
	},
	BronnCrush = {
		Wind = {
			{ Pose = "BronnCrushWind", Time = 0.3, Style = "Back", Dir = "Out", Delay = ARM_LAG },
			{ Pose = "BronnCrushWindDeep", Time = 0.7, Style = "Sine", Dir = "InOut" },
		},
		Strike = {
			{ Pose = "BronnCrushMid", Time = 0.05, Style = "Quad", Dir = "In" },
			{ Pose = "BronnCrushHit", Time = 0.07, Style = "Quint", Dir = "In", Delay = WRIST_LAG },
			{ Pose = "BronnCrushThrough", Time = 0.12, Style = "Back", Dir = "Out", Hold = 0.2 },
		},
		Recover = { { Pose = "Rest", Time = 1, Style = "Sine", Dir = "InOut", Delay = ARM_LAST } },
	},
	-- Strike here is the run itself (filled with the charge's travel time).
	BronnCharge = {
		Wind = {
			{ Pose = "BronnChargeWind", Time = 0.3, Style = "Back", Dir = "Out", Delay = ARM_LAG },
			{ Pose = "BronnChargeWindDeep", Time = 0.7, Style = "Sine", Dir = "InOut" },
		},
		Strike = { { Pose = "BronnChargeRun", Time = 0.1, Style = "Quint", Dir = "In", Hold = 0.9 } },
		Recover = {
			{ Pose = "BronnChargeStuck", Time = 0.15, Style = "Back", Dir = "Out", Hold = 0.55 },
			{ Pose = "Rest", Time = 0.3, Style = "Sine", Dir = "InOut" },
		},
	},
	BronnRoar = {
		Strike = {
			{ Pose = "RoarUp", Time = 0.25, Style = "Back", Dir = "Out", Hold = 0.1 },
			{ Pose = "RoarHold", Time = 0.5, Style = "Sine", Dir = "InOut", Hold = 0.4 },
		},
		Recover = { { Pose = "Rest", Time = 0.45, Style = "Sine", Dir = "InOut" } },
	},
}

return AnimationConfig
