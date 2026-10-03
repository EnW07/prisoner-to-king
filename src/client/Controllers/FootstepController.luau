--!strict
-- FootstepController.lua
-- Footstep sound hooks that vary by surface (K4, §37). While the local character moves,
-- every stride plays footstepStone, footstepWood or footstepWater depending on what is
-- underfoot (a short ray down; the sewer water is tagged). The ids are blank until you
-- fill them in FeedbackController.SOUND_IDS, so this costs one raycast per stride and
-- makes no sound until then.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local FeedbackController = require(script.Parent:WaitForChild("FeedbackController"))

local VFX = GameConfig.VFX
local player = Players.LocalPlayer
local FootstepController = {}

local WOOD = { [Enum.Material.Wood] = true, [Enum.Material.WoodPlanks] = true }
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local strideClock = 0

local function surfaceUnder(root: BasePart): string
	params.FilterDescendantsInstances = { player.Character :: Instance }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -6, 0), params)
	if not hit then
		return "footstepStone"
	end
	-- Water is walk-through and CanQuery off, so test for it by position against tagged slabs.
	for _, water in CollectionService:GetTagged("PTKWater") do
		if water:IsA("BasePart") then
			local p = water.CFrame:PointToObjectSpace(root.Position)
			if
				math.abs(p.X) <= water.Size.X / 2
				and math.abs(p.Z) <= water.Size.Z / 2
				and root.Position.Y - water.Position.Y < 4
			then
				return "footstepWater"
			end
		end
	end
	if WOOD[hit.Material] then
		return "footstepWood"
	end
	return "footstepStone"
end

function FootstepController.Init()
	RunService.Heartbeat:Connect(function(dt)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
			strideClock = 0
			return
		end
		local v = root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		if speed < 2 or humanoid.FloorMaterial == Enum.Material.Air then
			strideClock = 0
			return
		end
		-- Faster movement, quicker strides.
		strideClock += dt * math.clamp(speed / GameConfig.Player.WalkSpeed, 0.5, 2)
		if strideClock >= VFX.StrideInterval then
			strideClock = 0
			FeedbackController.PlaySound(surfaceUnder(root), VFX.FootstepVolume)
		end
	end)
end

return FootstepController
