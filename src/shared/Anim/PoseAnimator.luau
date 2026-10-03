--!strict
-- PoseAnimator.lua
-- Plays MOVES (data in AnimationConfig) on a Rig. Shared by client and server.
-- (MASTER_BUILD_SPEC C2/C3: a pose is a set of joint offsets; a move is a sequence of poses
-- with per-step easing and per-joint start delays; moves are data.)
--
-- WHY THE OLD ANIMATION LOOKED WRONG (C1 diagnosis, from reading ArmPose/EnemyAnimator/
-- CombatController before this rewrite):
--   • one joint: only the right shoulder moved, so the body read as a mannequin with a
--     single hinge;
--   • Quad easing everywhere, so nothing accelerated into a strike or settled out of one;
--   • no overshoot: the arm stopped dead at the end of the arc;
--   • the player's wind-up was 0.1s, too short to read as anticipation at all;
--   • one timing for every weapon and every enemy;
--   • no lead or lag between joints, so what did move moved in lockstep.
-- This module fixes the mechanics (multi-joint poses, any easing per step, per-joint delays,
-- weight classes, clean cancellation, blending from the current pose). The craft is in the
-- data: AnimationConfig.Poses and .Moves.
--
-- A MOVE has up to three PHASES in fixed order, Wind → Strike → Recover (any may be
-- absent). Each phase is a list of STEPS:
--   { Pose = "name", Time = s, Style = "Quint", Dir = "In", Delay = { Waist = 0.03 },
--     Hold = s, Snap = false }
-- Step.Time values are the authored durations. When the caller supplies a phase duration
-- (an enemy's WindupTime, Bronn's WindUp), the phase's steps are rescaled to fill it in
-- proportion. Without one, the weight class's phase multiplier applies (a hammer winds up
-- slower than a dagger with the same pose data).
--
-- SEQUENCING runs on a pacer tween (a NumberValue), not task.delay, so a client's hit-stop
-- pauses the whole chain together with the joints and it resumes in step. One move per rig:
-- starting a move cancels the previous one's remaining steps; joints blend from wherever
-- they are into the new move's first pose.
--
-- CLIPS. Callers resolve AnimationConfig slots first (a clip id replaces the procedural
-- move with no code change); this module only ever sees procedural moves.

local TweenService = game:GetService("TweenService")

local Rig = require(script.Parent.Rig)
local AnimationConfig = require(script.Parent.Parent.Config.AnimationConfig)

local PoseAnimator = {}

export type Durations = { Wind: number?, Strike: number?, Recover: number? }
export type Options = {
	Durations: Durations?, -- per-phase durations to fill; otherwise authored x weight
	Weight: string?, -- AnimationConfig.Weights key; default "Medium"
	OnPhase: ((phase: string) -> ())?, -- called as each phase begins
	OnDone: (() -> ())?, -- called when the last step completes (not on cancel)
}
export type Handle = { Cancel: () -> (), Done: boolean }

local PHASES = { "Wind", "Strike", "Recover" }

-- Hook for the client's hit-stop: every tween this module starts is passed here.
PoseAnimator.OnTween = nil :: ((Tween) -> ())?

type Active = { Token: number, Pacer: NumberValue, Handle: Handle }
local active: { [Rig.Rig]: Active } = setmetatable({}, { __mode = "k" }) :: any
local tokens: { [Rig.Rig]: number } = setmetatable({}, { __mode = "k" }) :: any

local function track(t: Tween?)
	local hook = PoseAnimator.OnTween
	if t and hook then
		hook(t)
	end
end

local function easing(name: string?): Enum.EasingStyle
	local style = name and (Enum.EasingStyle :: any)[name]
	return style or Enum.EasingStyle.Sine
end

local function direction(name: string?): Enum.EasingDirection
	local dir = name and (Enum.EasingDirection :: any)[name]
	return dir or Enum.EasingDirection.Out
end

local function weightOf(name: string?)
	return AnimationConfig.Weights[name or "Medium"] or AnimationConfig.Weights.Medium
end

-- Every joint the pose mentions moves to it; every joint it doesn't mention moves to rest.
-- Returning to rest implicitly is what keeps a move self-contained: the next move never
-- inherits a stray elbow from the last.
local function applyPose(
	rig: Rig.Rig,
	poseName: string,
	time: number,
	style: Enum.EasingStyle,
	dir: Enum.EasingDirection,
	delays: { [string]: number }?,
	bodyScale: number,
	token: number
)
	local pose = AnimationConfig.Poses[poseName]
	if not pose then
		warn(("[PoseAnimator] Unknown pose %q"):format(poseName))
		pose = {}
	end
	for name, joint in rig.Joints do
		local angles = pose[name]
		local offset = if angles then Rig.Offset(rig, joint, angles, bodyScale) else CFrame.identity
		local delay = delays and delays[name] or 0
		local info = TweenInfo.new(math.max(time, 0.01), style, dir)
		if delay > 0 then
			-- Delayed joints keep their current tween until they start (not released), so a
			-- lagging wrist finishes its previous arc rather than freezing mid-air.
			task.delay(delay, function()
				if tokens[rig] == token then
					track(Rig.TweenTo(joint, offset, info))
				end
			end)
		else
			track(Rig.TweenTo(joint, offset, info))
		end
	end
end

-- Build the flat step list for a move with concrete times.
local function plan(move, options: Options): { any }
	local weight = weightOf(options.Weight)
	local durations = options.Durations or {}
	local steps = {}
	for _, phase in PHASES do
		local list = move[phase]
		if list then
			-- A step spans its slowest joint (time + its delay) plus any hold. The phase's
			-- authored span is the sum; delays scale with the rest so a phase filled with a
			-- caller's duration lasts exactly that long (the strike arc must land on time).
			local total = 0
			local longest = {}
			for i, step in list do
				local maxDelay = 0
				if step.Delay then
					for _, d in step.Delay do
						maxDelay = math.max(maxDelay, d)
					end
				end
				longest[i] = maxDelay
				total += (step.Time or 0) + maxDelay + (step.Hold or 0)
			end
			local given = (durations :: any)[phase]
			local scale: number
			if given and total > 0 then
				scale = given / total
			else
				scale = (weight :: any)[phase] or 1
			end
			for i, step in list do
				local delay: { [string]: number }? = nil
				if step.Delay then
					delay = {}
					for joint, d in step.Delay do
						(delay :: any)[joint] = d * scale
					end
				end
				table.insert(steps, {
					Phase = phase,
					First = i == 1,
					Pose = step.Pose,
					Time = (step.Time or 0) * scale,
					Hold = (step.Hold or 0) * scale,
					Span = ((step.Time or 0) + longest[i] + (step.Hold or 0)) * scale,
					Style = easing(step.Style),
					Dir = direction(step.Dir),
					Delay = delay,
					Snap = step.Snap == true,
				})
			end
		end
	end
	return steps
end

local function cancelActive(rig: Rig.Rig)
	local current = active[rig]
	if current then
		active[rig] = nil
		current.Pacer:Destroy() -- destroys the pacer tween with it
	end
end

-- Stop the current move. Joints stay where they are (the caller blends them elsewhere).
function PoseAnimator.Cancel(rig: Rig.Rig)
	tokens[rig] = (tokens[rig] or 0) + 1
	cancelActive(rig)
end

-- Play a move by name. Returns a handle; Cancel() stops the remaining steps.
function PoseAnimator.Play(rig: Rig.Rig, moveName: string, options: Options?): Handle
	local opts: Options = options or {}
	local handle: Handle = { Done = false, Cancel = function() end }
	local move = AnimationConfig.Moves[moveName]
	if not move then
		warn(("[PoseAnimator] Unknown move %q"):format(moveName))
		handle.Done = true
		return handle
	end

	PoseAnimator.Cancel(rig)
	local token = tokens[rig]
	local steps = plan(move, opts)
	local bodyScale = (weightOf(opts.Weight) :: any).Body or 1

	local pacer = Instance.new("NumberValue")
	pacer.Name = "PosePacer"
	local record: Active = { Token = token, Pacer = pacer, Handle = handle }
	active[rig] = record
	handle.Cancel = function()
		if tokens[rig] == token then
			PoseAnimator.Cancel(rig)
		end
	end

	local i = 0
	local function nextStep()
		if tokens[rig] ~= token then
			return
		end
		i += 1
		local step = steps[i]
		if not step then
			handle.Done = true
			cancelActive(rig)
			if opts.OnDone then
				opts.OnDone()
			end
			return
		end
		if step.First and opts.OnPhase then
			opts.OnPhase(step.Phase)
		end

		if step.Snap then
			-- An instant pose (a freeze frame, a ragdoll hand-off). No tweens.
			local pose = AnimationConfig.Poses[step.Pose] or {}
			for name, joint in rig.Joints do
				local angles = pose[name]
				Rig.Set(joint, if angles then Rig.Offset(rig, joint, angles, bodyScale) else CFrame.identity)
			end
		else
			applyPose(rig, step.Pose, step.Time, step.Style, step.Dir, step.Delay, bodyScale, token)
		end

		-- The pacer runs for the step's full span (slowest joint + hold) and drives the next
		-- step from its Completed, so a paused pacer pauses the chain.
		local span = math.max(step.Span, 0.01)
		pacer.Value = 0
		local pace = TweenService:Create(pacer, TweenInfo.new(span, Enum.EasingStyle.Linear), { Value = 1 })
		track(pace)
		pace.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				nextStep()
			end
		end)
		pace:Play()
	end
	nextStep()
	return handle
end

-- Ease every joint back to rest over `time`, cancelling any move. The soft stop.
function PoseAnimator.Relax(rig: Rig.Rig, time: number?)
	PoseAnimator.Cancel(rig)
	local info =
		TweenInfo.new(math.max(time or 0.25, 0.01), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	for _, joint in rig.Joints do
		track(Rig.TweenTo(joint, CFrame.identity, info))
	end
end

-- Hold the current pose exactly: cancel the move and every joint tween. The hard stop
-- (hit-stop at death, handing over to a ragdoll).
function PoseAnimator.Freeze(rig: Rig.Rig)
	PoseAnimator.Cancel(rig)
	Rig.Freeze(rig)
end

-- Snap to a pose with no tween (postures at spawn).
function PoseAnimator.Set(rig: Rig.Rig, poseName: string)
	PoseAnimator.Cancel(rig)
	local pose = AnimationConfig.Poses[poseName]
	if not pose then
		return
	end
	for name, joint in rig.Joints do
		local angles = pose[name]
		Rig.Set(joint, if angles then Rig.Offset(rig, joint, angles, 1) else CFrame.identity)
	end
end

-- Apply a pose and make it the rig's new rest: a resting posture every later move is
-- relative to (a guard's slouch, Bronn's stance).
function PoseAnimator.Bake(rig: Rig.Rig, poseName: string)
	PoseAnimator.Set(rig, poseName)
	for _, joint in rig.Joints do
		Rig.Bake(joint)
	end
end

-- A gentle looping breath on the torso and head, for rigs with no idle clip (a static
-- idle reads as a frozen game, C4). Runs as reversing tweens, so it costs no per-frame
-- work; any move cancels it by taking the joints, and the owner restarts it when idle.
function PoseAnimator.Breathe(rig: Rig.Rig, amplitudeDegrees: number, period: number)
	PoseAnimator.Cancel(rig)
	local info = TweenInfo.new(period / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local waist = rig.Joints.Waist
	local neck = rig.Joints.Neck
	if waist then
		track(Rig.TweenTo(waist, Rig.Offset(rig, waist, { x = amplitudeDegrees }), info))
	end
	if neck then
		track(Rig.TweenTo(neck, Rig.Offset(rig, neck, { x = -amplitudeDegrees * 0.6 }), info))
	end
end

-- True while a move is playing on this rig.
function PoseAnimator.IsBusy(rig: Rig.Rig): boolean
	return active[rig] ~= nil
end

return PoseAnimator
