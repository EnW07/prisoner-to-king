--!strict
-- Rig.lua
-- A character's joints, found once and posed many times. Shared: the client poses the local
-- character (and other players' characters), the server poses enemies and Bronn.
-- (MASTER_BUILD_SPEC C3: "joint handling must support BOTH Motor6D and AnimationConstraint".)
--
-- JOINT FORMS. A joint is posed by rotating its rest offset:
--   • Motor6D             → its C0
--   • AnimationConstraint → its Attachment0.CFrame (the attachment on the parent part)
-- Roblox's avatar joint upgrade puts AnimationConstraints in some characters in place of
-- Motor6Ds; code that assumed Motor6D silently found nothing there. Both forms share one
-- formula: Part1 = Part0 * C0 * Transform * C1:Inverse() (Motor6D) and Attachment1.World =
-- Attachment0.World * Transform (AnimationConstraint). Rotating C0 / Attachment0.CFrame
-- rotates the child about the joint, and Animator-driven clips (walk, idle) still play on
-- top through Transform. Which form a rig has is logged once per model name, so Output
-- shows the truth.
--
-- SEMANTIC ANGLES. Poses are authored in degrees per joint, the same for every rig:
--   x  pitch: positive swings the limb FORWARD (an arm: 90 points ahead, 160 is raised
--      overhead; negative swings it back). On the torso and head, positive leans forward.
--   y  yaw: positive turns toward the LEFT seen from above; on arms and legs it is
--      mirrored, so positive always means "across the body".
--   z  roll: positive raises an arm or leg OUT to its own side (mirrored for the left side);
--      on the torso and head, positive tilts toward the left shoulder.
--   P  an optional translation in studs { x, y, z }, scaled to the rig (Root P.y = -0.5 is
--      a crouch). Rarely needed outside Root.
-- Rotations are CFrame.Angles(x, y, z) = Rx * Ry * Rz: the roll is applied first, then the
-- yaw, then the pitch. Multiplied onto the REST offset, so a rig's own proportions, scale
-- and any baked posture (a guard's slouch) are kept.
--
-- ONE TWEEN PER JOINT. A joint remembers the tween driving it; starting another cancels
-- the first. Two tweens can never fight over a joint, which was the known cause of poses
-- that never rendered. A cancelled tween leaves the joint where it was, so the next tween
-- starts from the CURRENT pose: that is what makes every transition a blend (C5).

local TweenService = game:GetService("TweenService")

local Rig = {}

export type Joint = {
	Name: string, -- the R15 name, whatever the rig
	Target: Instance, -- Motor6D, or the AnimationConstraint's Attachment0
	Property: string, -- "C0" or "CFrame"
	Rest: CFrame,
	Form: string, -- "Motor6D" | "AnimationConstraint"
	Side: number, -- -1 for a left-side joint (mirrored), else 1
	Kind: string, -- "Root" | "Torso" | "Head" | "Arm" | "Hand" | "Leg"
	Tween: Tween?, -- the ONE tween allowed to drive this joint right now
}

export type Rig = {
	Model: Model,
	Type: string, -- "R15" | "R6"
	Joints: { [string]: Joint },
	Scale: number, -- 1 for a standard-height rig; translations are multiplied by it
	Form: string, -- the form most joints have, for logs
}

export type Angles = { x: number?, y: number?, z: number?, P: { number }? }

-- R15 names are canonical. R6 rigs expose a subset under these names.
local R15_NAMES = {
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
}
local R6_ALIASES = {
	Root = "RootJoint",
	Neck = "Neck",
	LeftShoulder = "Left Shoulder",
	RightShoulder = "Right Shoulder",
	LeftHip = "Left Hip",
	RightHip = "Right Hip",
}
-- R6 shoulders and hips have a 90-degree yaw baked into C0 and the Neck/RootJoint are
-- turned 180, so only the arms are mapped there (Offset below). Torso, head and legs on an
-- R6 rig are found but left at rest: posing them with the R15 formula would read wrong.
local R6_POSEABLE = { RightShoulder = true, LeftShoulder = true }

local function kindOf(name: string): string
	if name == "Root" then
		return "Root"
	elseif name == "Waist" then
		return "Torso"
	elseif name == "Neck" then
		return "Head"
	elseif name:find("Wrist") then
		return "Hand"
	elseif name:find("Shoulder") or name:find("Elbow") then
		return "Arm"
	end
	return "Leg"
end

-- Body-involvement scaling (weight classes) applies to these, never to the striking arm.
Rig.BODY_KINDS = { Root = true, Torso = true, Head = true, Leg = true }

local rigs: { [Model]: Rig } = setmetatable({}, { __mode = "k" }) :: any
local reported: { [string]: boolean } = {}

local function report(model: Model, rigType: string, form: string, count: number)
	local key = model.Name .. "/" .. rigType .. "/" .. form
	if reported[key] then
		return
	end
	reported[key] = true
	print(("[Rig] %s: %s rig, %d joints, form %s"):format(model.Name, rigType, count, form))
end

-- Find every joint by name, in either form. Called once per model; the result is cached
-- (weakly) so later calls never re-capture a mid-pose offset as the rest pose.
function Rig.Open(model: Model): Rig?
	local cached = rigs[model]
	if cached then
		return cached
	end

	local rigType: string? = nil
	if model:FindFirstChild("UpperTorso") then
		rigType = "R15"
	elseif model:FindFirstChild("Torso") then
		rigType = "R6"
	end
	if not rigType then
		return nil
	end

	local byName: { [string]: Instance } = {}
	for _, inst in model:GetDescendants() do
		if inst:IsA("Motor6D") or inst:IsA("AnimationConstraint") then
			if byName[inst.Name] == nil then
				byName[inst.Name] = inst
			end
		end
	end

	local joints: { [string]: Joint } = {}
	local forms: { [string]: number } = {}
	for _, name in R15_NAMES do
		local lookup = if rigType == "R6" then R6_ALIASES[name] else name
		local inst = lookup and byName[lookup]
		if inst then
			local joint: Joint? = nil
			if inst:IsA("Motor6D") then
				joint = {
					Name = name,
					Target = inst,
					Property = "C0",
					Rest = inst.C0,
					Form = "Motor6D",
					Side = if name:sub(1, 4) == "Left" then -1 else 1,
					Kind = kindOf(name),
					Tween = nil,
				}
			elseif inst:IsA("AnimationConstraint") then
				local a0 = inst.Attachment0
				if a0 then
					joint = {
						Name = name,
						Target = a0,
						Property = "CFrame",
						Rest = a0.CFrame,
						Form = "AnimationConstraint",
						Side = if name:sub(1, 4) == "Left" then -1 else 1,
						Kind = kindOf(name),
						Tween = nil,
					}
				end
			end
			if joint then
				joints[name] = joint
				forms[joint.Form] = (forms[joint.Form] or 0) + 1
			end
		end
	end

	local count, form = 0, "none"
	for f, n in forms do
		count += n
		if n > (forms[form] or 0) then
			form = f
		end
	end
	if count == 0 then
		return nil
	end

	-- A standard R15 HumanoidRootPart is 2 studs tall; HumanoidDescription scaling and
	-- Model:ScaleTo both grow it, so this is the rig's size relative to a standard one.
	local root = model:FindFirstChild("HumanoidRootPart")
	local scale = if root and root:IsA("BasePart") then math.max(root.Size.Y / 2, 0.1) else 1

	local rig: Rig = { Model = model, Type = rigType, Joints = joints, Scale = scale, Form = form }
	rigs[model] = rig
	report(model, rigType, form, count)
	return rig
end

-- The joint-space rotation (and translation) for semantic angles on this joint.
function Rig.Offset(rig: Rig, joint: Joint, a: Angles, bodyScale: number?): CFrame
	local k = if Rig.BODY_KINDS[joint.Kind] then (bodyScale or 1) else 1
	local x = math.rad((a.x or 0) * k)
	local y = math.rad((a.y or 0) * k)
	local z = math.rad((a.z or 0) * k)
	local s = joint.Side

	local rotation: CFrame
	if rig.Type == "R6" then
		if not R6_POSEABLE[joint.Name] then
			rotation = CFrame.identity
		else
			-- R6 shoulder C0s are yawed 90 degrees toward the body, so pitch is about the
			-- joint's Z and "out" is about its -X. The left shoulder pitches about -Z.
			rotation = CFrame.Angles(-z, y * s, x * s)
		end
	else
		rotation = CFrame.Angles(x, y * s, z * s)
	end

	local p = a.P
	local translation = if p
		then CFrame.new((p[1] or 0) * rig.Scale, (p[2] or 0) * rig.Scale, (p[3] or 0) * rig.Scale)
		else CFrame.identity
	return translation * rotation
end

-- Cancel whatever is driving the joint. The joint stays exactly where it is.
function Rig.Release(joint: Joint)
	local t = joint.Tween
	if t then
		joint.Tween = nil
		t:Cancel()
	end
end

-- Tween the joint to rest * offset. Any previous tween on this joint is cancelled first,
-- so exactly one tween drives a joint at a time. Returns the (playing) tween, or nil if the
-- joint's instance is gone.
function Rig.TweenTo(joint: Joint, offset: CFrame, info: TweenInfo): Tween?
	Rig.Release(joint)
	if not joint.Target.Parent then
		return nil
	end
	local t = TweenService:Create(joint.Target, info, { [joint.Property] = joint.Rest * offset })
	joint.Tween = t
	t.Completed:Connect(function()
		if joint.Tween == t then
			joint.Tween = nil
		end
	end)
	t:Play()
	return t
end

-- Set the joint instantly (postures, hard resets).
function Rig.Set(joint: Joint, offset: CFrame)
	Rig.Release(joint)
	if joint.Target.Parent then
		(joint.Target :: any)[joint.Property] = joint.Rest * offset
	end
end

-- Make the joint's CURRENT offset its new rest. Used to bake a posture (a slouch, Bronn's
-- stance) so every later pose is relative to it.
function Rig.Bake(joint: Joint)
	Rig.Release(joint)
	if joint.Target.Parent then
		joint.Rest = (joint.Target :: any)[joint.Property]
	end
end

-- Cancel every tween on the rig and leave the joints exactly where they are (hit-stop at
-- the moment of death, or handing the body to a ragdoll).
function Rig.Freeze(rig: Rig)
	for _, joint in rig.Joints do
		Rig.Release(joint)
	end
end

-- Cancel everything and snap every joint to rest. For a fresh character, never mid-game.
function Rig.Reset(rig: Rig)
	for _, joint in rig.Joints do
		Rig.Set(joint, CFrame.identity)
	end
end

-- Forget a model (its rig is gone). The cache is weak anyway; this is for explicit cleanup.
function Rig.Close(model: Model)
	local rig = rigs[model]
	if rig then
		Rig.Freeze(rig)
		rigs[model] = nil
	end
end

return Rig
