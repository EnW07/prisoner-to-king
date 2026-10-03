--!strict
-- EnemyAnimator.lua
-- Plays animations on enemy rigs. One responsibility: animation playback for NPCs.
-- (docs/RIGS_AND_VISUAL_UI_BRIEF.md §1 step 2; MASTER_BUILD_SPEC Section C.)
--
-- WHY THIS IS NEEDED even with real R15 rigs: Roblox's default walk/run/idle comes from the
-- Animate LocalScript, which only player characters get, and a LocalScript can't run in an
-- NPC. So the server drives it here:
--   • locomotion: idle / walk / run / jump / fall, chosen from the rig's actual movement on
--     a throttled tick, with per-enemy idle variation so a room of guards isn't in unison
--   • actions: a clip from AnimationConfig when one is configured, otherwise the
--     procedural move named in the set's Procedural map, played through PoseAnimator on
--     the rig's real joints (torso, head, both arms, legs: not just one shoulder)
-- Animations loaded through a server-side Animator replicate to every client, and so do
-- joint offsets set on the server, so every client sees the same motion.
--
-- Ids come from AnimationConfig. "default" resolves to Roblox's own ids, which RigFactory
-- reads from the engine. A slot that can't resolve yet (no rig or player has supplied the
-- defaults) is retried on the next tick, so guards start walking the moment ids exist.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local AnimationConfig = require(game.ReplicatedStorage.Shared.Config.AnimationConfig)
local RigFactory = require(script.Parent.RigFactory)
local Rig = require(game.ReplicatedStorage.Shared.Anim.Rig)
local PoseAnimator = require(game.ReplicatedStorage.Shared.Anim.PoseAnimator)
local Palette = require(game.ReplicatedStorage.Shared.Config.Palette)

-- Parts that make up an enemy's weapon (RigFactory names), glowed during a windup. Bronn's
-- Greatsword is lit by CaptainService together with his outline and callout.
local WEAPON_PARTS = { Blade = true, Spear = true, Spearhead = true }

local ANIM = GameConfig.Animation
local EnemyAnimator = {}

-- What PlayAction hands back: a clip, a procedural move, or neither. Cancel works on all.
export type Action = { Clip: AnimationTrack?, Move: PoseAnimator.Handle?, Cancel: () -> () }

type State = {
	Humanoid: Humanoid,
	Root: BasePart,
	Animator: Animator,
	Set: { [string]: any },
	Tracks: { [string]: AnimationTrack | false }, -- false = tried and failed; don't retry
	Current: string?,
	Rig: Rig.Rig?, -- every joint, Motor6D or AnimationConstraint form
	IdleSpeed: number, -- this enemy's own idle tempo
	Breathing: boolean, -- procedural breath running (no idle clip available)
	Action: Action?, -- the action playing now, if any
	-- The weapon parts, and their normal look, for the windup glow.
	Weapon: { { Part: BasePart, Color: Color3, Material: Enum.Material } },
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

local function stopBreathing(state: State)
	if state.Breathing then
		state.Breathing = false
		if state.Rig then
			PoseAnimator.Relax(state.Rig, ANIM.RelaxTime)
		end
	end
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
	if key == "Idle" and t.Length > 0 then
		-- A random start point, so two guards spawned together don't breathe in step.
		t.TimePosition = math.random() * t.Length
	end
end

local function locomote(state: State)
	local humanoid = state.Humanoid
	if humanoid.Health <= 0 then
		return
	end
	local humanoidState = humanoid:GetState()
	if humanoidState == Enum.HumanoidStateType.Freefall then
		stopBreathing(state)
		playLoop(state, "Fall", 1)
		return
	elseif humanoidState == Enum.HumanoidStateType.Jumping then
		stopBreathing(state)
		playLoop(state, "Jump", 1)
		return
	end
	local v = state.Root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	if speed < ANIM.MoveThreshold then
		playLoop(state, "Idle", state.IdleSpeed)
		-- No idle clip (defaults not learned yet, or none configured): breathe procedurally
		-- rather than stand frozen. Only while no action owns the joints.
		local rig = state.Rig
		if rig and not state.Tracks.Idle and not state.Breathing and not PoseAnimator.IsBusy(rig) then
			state.Breathing = true
			PoseAnimator.Breathe(rig, ANIM.BreathDegrees, ANIM.BreathPeriod)
		elseif state.Breathing and state.Tracks.Idle then
			stopBreathing(state) -- the clip arrived; it breathes better than we do
		end
	else
		stopBreathing(state)
		if speed < ANIM.RunThreshold then
			playLoop(state, "Walk", speed / ANIM.WalkReferenceSpeed)
		else
			playLoop(state, "Run", speed / ANIM.WalkReferenceSpeed)
		end
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
	local rig = Rig.Open(record.Model)
	if not rig then
		warn(
			("[EnemyAnimator] %s has no poseable joints; its actions won't move its body"):format(
				record.EnemyId
			)
		)
	elseif set.Posture then
		PoseAnimator.Bake(rig, set.Posture)
	end
	local weapon = {}
	for _, p in record.Model:GetChildren() do
		if p:IsA("BasePart") and WEAPON_PARTS[p.Name] then
			table.insert(weapon, { Part = p, Color = p.Color, Material = p.Material })
		end
	end
	local jitter = ANIM.IdleSpeedJitter
	local state: State = {
		Humanoid = humanoid,
		Root = root,
		Animator = animator :: Animator,
		Set = set,
		Tracks = {},
		Current = nil,
		Rig = rig,
		IdleSpeed = 1 + (math.random() * 2 - 1) * jitter,
		Breathing = false,
		Action = nil,
		Weapon = weapon,
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
	if state.Action then
		state.Action.Cancel()
	end
	for _, t in state.Tracks do
		if t then
			t:Stop(0)
		end
	end
	Rig.Close(record.Model)
end

-- Play an action by slot key ("Attack", "Alert", "Stagger", a Bronn move id...): the
-- configured clip if there is one, otherwise the set's procedural move with the given
-- phase durations. Returns an Action (Cancel always works), or nil when the enemy isn't
-- animated or the key resolves to nothing. That's the AnimationConfig contract: imported
-- clip in, no code change.
function EnemyAnimator.PlayAction(record, key: string, durations: PoseAnimator.Durations?): Action?
	local state = states[record]
	if not state then
		return nil
	end
	if state.Action then
		state.Action.Cancel()
		state.Action = nil
	end
	state.Breathing = false

	local clip = track(state, key)
	if clip then
		clip:Play(ANIM.FadeTime)
		local action: Action = {
			Clip = clip,
			Move = nil,
			Cancel = function()
				clip:Stop(ANIM.FadeTime)
			end,
		}
		state.Action = action
		return action
	end

	local procedural = state.Set.Procedural
	local moveName = procedural and procedural[key]
	local rig = state.Rig
	if not moveName or not rig then
		return nil
	end
	local handle = PoseAnimator.Play(rig, moveName, { Durations = durations })
	local action: Action = {
		Clip = nil,
		Move = handle,
		Cancel = function()
			handle.Cancel()
			if rig.Model.Parent then
				PoseAnimator.Relax(rig, ANIM.RelaxTime)
			end
		end,
	}
	state.Action = action
	return action
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

-- The attack cycle (EnemyService.BeginAttack), as one move that fills the cycle's real
-- durations:
--   Wind     the draw-back, over WindupTime minus StrikeLead
--   Strike   the arc, started StrikeLead BEFORE the server's hit test so the blade arrives
--            as damage applies, then the follow-through holds for ImpactHold
--   Recover  the slow return, over RecoverShare of RecoveryTime: the punish window, visibly
-- The whole move starts at Windup; the later phase calls only drive the glow. An "Attack"
-- clip in AnimationConfig replaces the move: it should land its hit at WindupTime.
function EnemyAnimator.AttackPhase(record, phase: string, duration: number)
	local state = states[record]
	if not state then
		return
	end
	if phase == "Windup" then
		glow(state, true)
		local lead = math.min(ANIM.StrikeLead, duration * 0.4)
		EnemyAnimator.PlayAction(record, "Attack", {
			Wind = math.max(duration - lead, 0.05),
			Strike = lead + ANIM.ImpactHold,
			Recover = math.max((record.Config.RecoveryTime or 0) * ANIM.RecoverShare, 0.1),
		})
	elseif phase == "Strike" then
		glow(state, false)
	end
end

-- Stop whatever action is playing and ease back to rest (a stagger cutting a windup, an
-- attack cancelled by a reset). The glow goes out with it.
function EnemyAnimator.Interrupt(record)
	local state = states[record]
	if not state then
		return
	end
	glow(state, false)
	if state.Action then
		state.Action.Cancel()
		state.Action = nil
	elseif state.Rig then
		PoseAnimator.Relax(state.Rig, ANIM.RelaxTime)
	end
end

-- Hold the body exactly where it is and stop every clip: the frame of death, before the
-- ragdoll takes over (D4). Nothing animates after this.
function EnemyAnimator.Freeze(record)
	local state = states[record]
	if not state then
		return
	end
	glow(state, false)
	if state.Action then
		if state.Action.Clip then
			state.Action.Clip:Stop(0)
		end
		if state.Action.Move then
			state.Action.Move.Cancel()
		end
		state.Action = nil
	end
	for _, t in state.Tracks do
		if t then
			t:Stop(0)
		end
	end
	state.Current = nil
	if state.Rig then
		PoseAnimator.Freeze(state.Rig)
	end
end

return EnemyAnimator
