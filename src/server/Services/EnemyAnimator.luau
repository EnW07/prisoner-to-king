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

local ANIM = GameConfig.Animation
local EnemyAnimator = {}

type State = {
	Humanoid: Humanoid,
	Root: BasePart,
	Animator: Animator,
	Set: { [string]: string? },
	Tracks: { [string]: AnimationTrack | false }, -- false = tried and failed; don't retry
	Current: string?,
	Shoulder: Motor6D?,
	ShoulderRest: CFrame?,
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
	local shoulder = record.Model:FindFirstChild("RightShoulder", true)
	local state: State = {
		Humanoid = humanoid,
		Root = root,
		Animator = animator :: Animator,
		Set = set,
		Tracks = {},
		Current = nil,
		Shoulder = if shoulder and shoulder:IsA("Motor6D") then shoulder else nil,
		ShoulderRest = if shoulder and shoulder:IsA("Motor6D") then shoulder.C0 else nil,
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

-- A guard's swing: the configured "Attack" clip if there is one, otherwise a procedural
-- wind-up / strike / recover on the real right shoulder.
function EnemyAnimator.Swing(record)
	if EnemyAnimator.PlayAction(record, "Attack") then
		return
	end
	local state = states[record]
	if not state or not state.Shoulder or not state.ShoulderRest then
		return
	end
	local shoulder: Motor6D = state.Shoulder
	local rest: CFrame = state.ShoulderRest
	local Quad = Enum.EasingStyle.Quad
	-- Same joint-space convention as CaptainService: +X raises the arm forward and up.
	local windUp = TweenService:Create(
		shoulder,
		TweenInfo.new(ANIM.EnemySwingWindUp, Quad, Enum.EasingDirection.Out),
		{ C0 = rest * CFrame.Angles(math.rad(140), 0, 0) }
	)
	windUp.Completed:Connect(function(playback)
		if playback ~= Enum.PlaybackState.Completed or not shoulder.Parent then
			return
		end
		local strike = TweenService:Create(
			shoulder,
			TweenInfo.new(ANIM.EnemySwingStrike, Quad, Enum.EasingDirection.In),
			{ C0 = rest * CFrame.Angles(math.rad(30), 0, 0) }
		)
		strike.Completed:Connect(function(p)
			if p == Enum.PlaybackState.Completed and shoulder.Parent then
				TweenService:Create(
					shoulder,
					TweenInfo.new(ANIM.EnemySwingRecover, Quad, Enum.EasingDirection.InOut),
					{ C0 = rest }
				):Play()
			end
		end)
		strike:Play()
	end)
	windUp:Play()
end

return EnemyAnimator
