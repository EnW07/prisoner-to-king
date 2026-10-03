--!strict
-- ArmPose.lua
-- Procedural animation through a rig's REAL joints, for any rig. Used by the player's
-- swing (client), enemy attacks and posture (server), and Bronn's moveset.
-- (Playtest 5, item 2: "the weapon rotates in place; the arm never swings".)
--
-- JOINT FORMS: a joint is posed by rotating its rest offset. Two forms exist:
--   • Motor6D             → its C0
--   • AnimationConstraint → its Attachment0.CFrame (the attachment on the parent part)
-- The second is what Roblox's avatar joint upgrade puts in characters in place of Motor6Ds.
-- Code that assumed Motor6D found nothing there: guards' swings did nothing, the player's
-- swing fell back to a wrist snap, and Bronn's dress asserted and failed. FindJoint handles
-- both, and logs which form it found (once per form), so Output shows the truth.
--
-- POSES are semantic, in degrees, so one pose table works on every rig:
--   Pitch  raise the arm FORWARD and up (0 = hanging, 90 = pointing ahead, 180 = overhead)
--   Roll   raise the arm OUT to the side (positive = away from the body)
-- Rotation() maps them onto the rig's own shoulder axes:
--   R15  joint axes match the torso (+X right, -Z forward): pitch about X, roll about Z
--   R6   "Right Shoulder" C0 is turned 90 degrees about Y: pitch about joint Z, roll about -X
-- Rotations multiply onto the joint's REST offset, so the rig's offsets and scale are kept,
-- and Animator-driven clips (walk, idle) still play underneath.

local TweenService = game:GetService("TweenService")

local ArmPose = {}

export type Pose = { Pitch: number, Roll: number }
export type Joint = { Target: Instance, Property: string, Rest: CFrame, Rig: string, Form: string }

-- Logged once per joint name and form, not per rig, so respawns don't spam Output.
local reported: { [string]: boolean } = {}

local function report(model: Model, name: string, form: string)
	local key = name .. "/" .. form
	if reported[key] then
		return
	end
	reported[key] = true
	print(("[ArmPose] %s: joint %s is a %s"):format(model.Name, name, form))
end

-- A named joint of either form, with its current offset captured as the rest pose.
-- Call once per rig and keep the result: later calls would capture a mid-swing pose.
function ArmPose.FindJoint(model: Model, name: string, rig: string): Joint?
	for _, inst in model:GetDescendants() do
		if inst.Name == name then
			if inst:IsA("Motor6D") then
				report(model, name, "Motor6D")
				return { Target = inst, Property = "C0", Rest = inst.C0, Rig = rig, Form = "Motor6D" }
			elseif inst:IsA("AnimationConstraint") then
				local a0 = inst.Attachment0
				if a0 then
					report(model, name, "AnimationConstraint")
					return {
						Target = a0,
						Property = "CFrame",
						Rest = a0.CFrame,
						Rig = rig,
						Form = "AnimationConstraint",
					}
				end
			end
		end
	end
	return nil
end

-- The right shoulder, R15 or R6.
function ArmPose.Find(model: Model): Joint?
	if model:FindFirstChild("RightUpperArm") then
		return ArmPose.FindJoint(model, "RightShoulder", "R15")
	end
	if model:FindFirstChild("Torso") then
		return ArmPose.FindJoint(model, "Right Shoulder", "R6")
	end
	return nil
end

-- Joint-space rotation for a semantic pose on the given rig.
function ArmPose.Rotation(rig: string, pose: Pose): CFrame
	local pitch, roll = math.rad(pose.Pitch), math.rad(pose.Roll)
	if rig == "R6" then
		return CFrame.Angles(-roll, 0, pitch)
	end
	return CFrame.Angles(pitch, 0, roll)
end

-- The joint's offset for a raw joint-space rotation (Bronn's moveset is authored this way).
function ArmPose.Offset(joint: Joint, rotation: CFrame): CFrame
	return joint.Rest * rotation
end

-- Tween a joint to rest * rotation. Returns the Tween (already playing).
function ArmPose.TweenTo(joint: Joint, rotation: CFrame, info: TweenInfo): Tween
	local t = TweenService:Create(joint.Target, info, { [joint.Property] = joint.Rest * rotation })
	t:Play()
	return t
end

-- Set a joint instantly (posture, initial pose).
function ArmPose.Set(joint: Joint, rotation: CFrame)
	(joint.Target :: any)[joint.Property] = joint.Rest * rotation
end

-- The shared melee arc: a chop from over the shoulder, down and across the body.
-- Used by the player's swing and guards' attacks. (Bronn has his own moveset.)
ArmPose.Chop = {
	Rest = { Pitch = 0, Roll = 0 },
	WindUp = { Pitch = 150, Roll = 25 }, -- cocked up and back over the shoulder
	WindUpDeep = { Pitch = 165, Roll = 32 }, -- anticipation: keeps drawing back until release
	Strike = { Pitch = 25, Roll = -10 }, -- down and across in front
	FollowThrough = { Pitch = -20, Roll = -18 }, -- carried on past
}

return ArmPose
