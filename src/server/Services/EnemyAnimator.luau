--!strict
-- EnemyAnimator.lua
-- Plays animations on enemy rigs. One responsibility: animation playback for NPCs.
-- (docs/RIGS_AND_VISUAL_UI_BRIEF.md §1 step 2.)
--
-- WHY THIS IS NEEDED even with real R15 rigs: Roblox's default walk/run/idle comes from the
-- Animate LocalScript, which only player characters get, and a LocalScript can't run in an
-- NPC. So the server drives it here:
--   • locomotion: idle / walk / run / jump / fall, chosen from the rig's actual movement
--     on a throttled tick
--   • actions: an attack clip from AnimationConfig, or a procedural arm swing when no clip
--     is configured
-- Animations loaded through a server-side Animator replicate to every client.
--
-- Ids come from AnimationConfig. "default" resolves to Roblox's own ids, which RigFactory
-- reads from the engine. A slot that can't resolve yet (no rig or player has supplied the
-- defaults) is retried on the next tick, so guards start walking the moment ids exist.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local AnimationConfig = require(game.ReplicatedStorage.Shared.Config.AnimationConfig)
local RigFactory = require(script.Parent.RigFactory)
local ArmPose = require(game.ReplicatedStorage.Shared.ArmPose)
local Palette = require(game.ReplicatedStorage.Shared.Config.Palette)

-- Parts that make up an enemy's weapon (RigFactory names), glowed during a windup.
local WEAPON_PARTS = { Blade = true, Spear = true, Spearhead = true }

local ANIM = GameConfig.Animation
local EnemyAnimator = {}

type State = {
	Humanoid: Humanoid,
	Root: BasePart,
	Animator: Animator,
	Set: { [string]: string? },
	Tracks: { [string]: AnimationTrack | false }, -- false = tried and failed; don't retry
	Current: string?,
	Arm: ArmPose.Joint?, -- the right shoulder, Motor6D or AnimationConstraint form
	-- The weapon parts, and their normal look, for the windup glow.
	Weapon: { { Part: BasePart, Color: Color3, Material: Enum.Material } },
	UsingClip: boolean, -- this attack is playing an AnimationConfig clip, not poses
}

local states: { [any]: State } = {}
local accumulator = 0

local LOOPS = { Idle = true, Walk = true, Run = true, Fall = true }

local function priorityFor(key: string): Enum.AnimationPriority
	if key == "Idle" then
		return Enum.AnimationPriority.Idle
	elseif LOOPS[key] or key == "Jump" then
		return Enum.AnimationPriority.Movement
	end
	return Enum.AnimationPriority.Action
end

local function resolve(set, key: string): string?
	local value = set[key]
	if value == nil then
		return nil
	end
	if value == AnimationConfig.DEFAULT then
		local ids = RigFactory.DefaultAnimationIds()
		local name = AnimationConfig.DefaultNames[key]
		return ids and name and ids[name] or nil
	end
	return value
end

local function track(state: State, key: string): AnimationTrack?
	local cached = state.Tracks[key]
	if cached then
		return cached
	elseif cached == false then
		return nil
	end
	local id = resolve(state.Set, key)
	if not id then
		return nil -- not cached: a "default" id may become available later
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, result = pcall(function()
		return state.Animator:LoadAnimation(animation)
	end)
	if not ok or not result then
		warn(("[EnemyAnimator] Could not load %s (%s): %s"):format(key, id, tostring(result)))
		state.Tracks[key] = false
		return nil
	end
	local t: AnimationTrack = result
	t.Priority = priorityFor(key)
	t.Looped = LOOPS[key] == true
	state.Tracks[key] = t
	return t
end

-- Crossfade to a looping locomotion clip.
local function playLoop(state: State, key: string, speed: number)
	local t = track(state, key)
	if not t then
		return
	end
	if state.Current == key then
		t:AdjustSpeed(speed)
		return
	end
	if state.Current then
		local old = state.Tracks[state.Current]
		if old then
			old:Stop(ANIM.FadeTime)
		end
	end
	state.Current = key
	t:Play(ANIM.FadeTime, 1, speed)
end

local function locomote(state: State)
	local humanoid = state.Humanoid
	if humanoid.Health <= 0 then
		return
	end
	local humanoidState = humanoid:GetState()
	if humanoidState == Enum.HumanoidStateType.Freefall then
		playLoop(state, "Fall", 1)
		return
	elseif humanoidState == Enum.HumanoidStateType.Jumping then
		playLoop(state, "Jump", 1)
		return
	end
	local v = state.Root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	if speed < ANIM.MoveThreshold then
		playLoop(state, "Idle", 1)
	elseif speed < ANIM.RunThreshold then
		playLoop(state, "Walk", speed / ANIM.WalkReferenceSpeed)
	else
		playLoop(state, "Run", speed / ANIM.WalkReferenceSpeed)
	end
end

function EnemyAnimator.Init()
	-- Player characters always carry Animate: a second, guaranteed source for the default ids.
	local function learn(player: Player)
		player.CharacterAdded:Connect(function(character)
			RigFactory.LearnDefaultAnimations(character)
		end)
		if player.Character then
			RigFactory.LearnDefaultAnimations(player.Character)
		end
	end
	for _, player in Players:GetPlayers() do
		learn(player)
	end
	Players.PlayerAdded:Connect(learn)

	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < ANIM.UpdateInterval then
			return
		end
		accumulator = 0
		for record, state in states do
			if record.Model.Parent and record.State ~= "Dead" then
				locomote(state)
			end
		end
	end)
end

-- Start animating an enemy. Called by EnemyService once the rig is in the world.
function EnemyAnimator.Attach(record)
	local setName = AnimationConfig.Enemies[record.EnemyId]
	local set = setName and AnimationConfig.Sets[setName]
	local humanoid: Humanoid = record.Humanoid
	local root = record.Model.PrimaryPart :: BasePart?
	if not set or not root then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local a = Instance.new("Animator")
		a.Parent = humanoid
		animator = a
	end
	local arm = ArmPose.Find(record.Model)
	if not arm then
		warn(
			("[EnemyAnimator] %s has no right shoulder joint; its attacks won't move the arm"):format(
				record.EnemyId
			)
		)
	end
	local weapon = {}
	for _, p in record.Model:GetChildren() do
		if p:IsA("BasePart") and WEAPON_PARTS[p.Name] then
			table.insert(weapon, { Part = p, Color = p.Color, Material = p.Material })
		end
	end
	local state: State = {
		Humanoid = humanoid,
		Root = root,
		Animator = animator :: Animator,
		Set = set,
		Tracks = {},
		Current = nil,
		Arm = arm,
		Weapon = weapon,
		UsingClip = false,
	}
	states[record] = state
	locomote(state)
end

function EnemyAnimator.Detach(record)
	local state = states[record]
	if not state then
		return
	end
	states[record] = nil
	for _, t in state.Tracks do
		if t then
			t:Stop(0)
		end
	end
end

-- Play a configured action clip (e.g. "Attack", or a Bronn move id). Returns the track, or
-- nil when no clip is configured, in which case the caller uses its procedural fallback.
function EnemyAnimator.PlayAction(record, key: string): AnimationTrack?
	local state = states[record]
	if not state then
		return nil
	end
	local t = track(state, key)
	if t then
		t:Play(ANIM.FadeTime)
	end
	return t
end

-- The weapon glows `bleed` through the windup: the no-sound telegraph (art §2).
local function glow(state: State, on: boolean)
	for _, w in state.Weapon do
		if w.Part.Parent then
			w.Part.Color = if on then Palette.bleed else w.Color
			w.Part.Material = if on then Enum.Material.Neon else w.Material
		end
	end
end

local function poseTo(
	state: State,
	pose: ArmPose.Pose,
	time: number,
	style: Enum.EasingStyle,
	dir: Enum.EasingDirection
)
	local arm = state.Arm
	if not arm or not arm.Target.Parent then
		return
	end
	ArmPose.TweenTo(arm, ArmPose.Rotation(arm.Rig, pose), TweenInfo.new(math.max(time, 0.01), style, dir))
end

-- One phase of an attack cycle (EnemyService.BeginAttack), driven through the real right
-- shoulder (playtest 5, item 2: the arm swings, not just the weapon):
--   Windup  snap into a draw-back, then keep drawing back until the release (anticipation)
--   Strike  a fast arc down and across
--   Recover a slow return to rest: the punish window, visibly
-- An "Attack" clip in AnimationConfig replaces all three. It starts at Windup and should
-- land its hit at the enemy's WindupTime. That's the AnimationConfig contract: imported
-- clip in, no code change.
function EnemyAnimator.AttackPhase(record, phase: string, duration: number)
	local state = states[record]
	if not state then
		return
	end
	local Q = Enum.EasingStyle.Quad
	if phase == "Windup" then
		glow(state, true)
		local clip = track(state, "Attack")
		state.UsingClip = clip ~= nil
		if clip then
			clip:Play(ANIM.FadeTime)
			return
		end
		local draw = math.min(ANIM.EnemyDrawTime, duration * 0.5)
		poseTo(state, ArmPose.Chop.WindUp, draw, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		task.delay(draw, function()
			if states[record] == state and record.State == "Windup" then
				poseTo(
					state,
					ArmPose.Chop.WindUpDeep,
					duration - draw,
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut
				)
			end
		end)
	elseif phase == "Strike" then
		glow(state, false)
		if not state.UsingClip then
			poseTo(state, ArmPose.Chop.Strike, ANIM.EnemyStrikeTime, Q, Enum.EasingDirection.In)
		end
	elseif phase == "Recover" then
		if not state.UsingClip then
			poseTo(state, ArmPose.Chop.Rest, duration * ANIM.EnemyRecoverShare, Q, Enum.EasingDirection.InOut)
		end
	end
end

return EnemyAnimator
