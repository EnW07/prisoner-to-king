--!strict
-- Ragdoll.lua
-- Turns a rigged character into a ragdoll, once, cleanly. Shared: the server applies it to
-- enemies and to player characters on death (constraints replicate; whoever owns the
-- character's physics simulates them). (MASTER_BUILD_SPEC D1 step 2, D4.)
--
-- WHY A RAGDOLL AND NOT A DEATH CLIP: Roblox's default death breaks every joint, so the
-- limbs scatter, while the walk animation keeps playing on whatever is left. That is "when
-- you die everything is a mess". A ragdoll needs no clip, falls differently every time,
-- works at any rig scale, and reads as a body rather than a pile of parts. We commit to
-- it: every animation is stopped and every pose frozen BEFORE this runs (callers do that),
-- and nothing animates after.
--
-- HOW: each joint becomes a BallSocketConstraint with angle and twist limits, and the
-- original joint is disabled (not destroyed, so pose code holding a reference can't throw).
-- Both joint forms are handled: a Motor6D gets attachments made from its C0/C1; an
-- AnimationConstraint already has Attachment0/1. The Root joint is kept rigid so the
-- HumanoidRootPart stays with the torso. Limbs are made collidable and the root is not,
-- so the body drapes over the floor instead of balancing on an invisible box.
--
-- Rule 8 note: Humanoid:SetStateEnabled / ChangeState and JointInstance.Enabled are
-- long-standing APIs. Every call that could plausibly differ per rig is pcall-wrapped and
-- the function returns false rather than erroring; callers keep a fallback.

local Ragdoll = {}

-- Per-joint limits in degrees: how far a socket can swing (Upper) and twist (Twist).
local LIMITS: { [string]: { Upper: number, Twist: number } } = {
	Neck = { Upper = 35, Twist = 45 },
	Waist = { Upper = 25, Twist = 20 },
	Shoulder = { Upper = 95, Twist = 60 },
	Elbow = { Upper = 70, Twist = 15 },
	Wrist = { Upper = 40, Twist = 30 },
	Hip = { Upper = 60, Twist = 25 },
	Knee = { Upper = 70, Twist = 10 },
	Ankle = { Upper = 30, Twist = 15 },
	Default = { Upper = 45, Twist = 30 },
}

-- States the Humanoid must not re-enter once the body is a ragdoll.
local DISABLED_STATES = {
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Running,
	Enum.HumanoidStateType.RunningNoPhysics,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.Landed,
	Enum.HumanoidStateType.Seated,
	Enum.HumanoidStateType.PlatformStanding,
	Enum.HumanoidStateType.StrafingNoPhysics,
	Enum.HumanoidStateType.Freefall,
	Enum.HumanoidStateType.FallingDown,
}

local ROOT_JOINTS = { Root = true, RootJoint = true }

local function limitsFor(name: string)
	for key, limits in LIMITS do
		if key ~= "Default" and name:find(key) then
			return limits
		end
	end
	return LIMITS.Default
end

local function socket(name: string, a0: Attachment, a1: Attachment, parent: Instance)
	local limits = limitsFor(name)
	local s = Instance.new("BallSocketConstraint")
	s.Name = "Ragdoll_" .. name
	s.Attachment0 = a0
	s.Attachment1 = a1
	s.LimitsEnabled = true
	s.UpperAngle = limits.Upper
	s.TwistLimitsEnabled = true
	s.TwistLowerAngle = -limits.Twist
	s.TwistUpperAngle = limits.Twist
	s.Parent = parent
end

-- True when a character has already been ragdolled.
function Ragdoll.IsApplied(character: Model): boolean
	return character:GetAttribute("Ragdolled") == true
end

-- Convert the character. Returns true if at least one joint became a socket.
function Ragdoll.Apply(character: Model): boolean
	if Ragdoll.IsApplied(character) then
		return true
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	character:SetAttribute("Ragdolled", true)

	-- Disable the state machine properly before the body goes limp (D1 step 2).
	humanoid.BreakJointsOnDeath = false
	humanoid.AutoRotate = false
	for _, state in DISABLED_STATES do
		pcall(function()
			humanoid:SetStateEnabled(state, false)
		end)
	end
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)

	local converted = 0
	for _, inst in character:GetDescendants() do
		if inst:IsA("Motor6D") then
			local part0, part1 = inst.Part0, inst.Part1
			if not ROOT_JOINTS[inst.Name] and part0 and part1 and inst.Enabled then
				local a0 = Instance.new("Attachment")
				a0.Name = "Ragdoll0_" .. inst.Name
				a0.CFrame = inst.C0
				a0.Parent = part0
				local a1 = Instance.new("Attachment")
				a1.Name = "Ragdoll1_" .. inst.Name
				a1.CFrame = inst.C1
				a1.Parent = part1
				socket(inst.Name, a0, a1, part0)
				inst.Enabled = false
				converted += 1
			end
		elseif inst:IsA("AnimationConstraint") then
			local a0, a1 = inst.Attachment0, inst.Attachment1
			if not ROOT_JOINTS[inst.Name] and a0 and a1 and inst.Enabled then
				socket(inst.Name, a0, a1, a0.Parent or character)
				inst.Enabled = false
				converted += 1
			end
		end
	end

	-- Limbs collide so the body drapes; the root doesn't, so it can't prop the body up.
	-- Massless parts are costume and weapons: left as they are.
	local root = character:FindFirstChild("HumanoidRootPart")
	for _, p in character:GetDescendants() do
		if p:IsA("BasePart") and not p.Massless then
			p.CanCollide = p ~= root
		end
	end
	return converted > 0
end

return Ragdoll
