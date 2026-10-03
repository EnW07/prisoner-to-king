--!strict
-- ProjectileService.lua
-- Enemy projectiles: arrows and crossbow bolts. One responsibility: fly a shot along a
-- line, decide on the server what it hit, and show it. (MASTER_BUILD_SPEC F2, F5.)
--
-- SECURITY: the client never decides a projectile hit. The server moves one anchored part
-- per shot and sweeps a ray along each step; a player character in the way takes the
-- damage through EnemyService.DamagePlayer, which also honours dash i-frames. Clients
-- only see the replicated part move.
--
-- READABILITY: shots are slow enough to see and sidestep (the Speed in the enemy's
-- Projectile spec), lit in `bleed` (danger, art §3), and they stick where they land for a
-- moment so a miss is visible as a miss.
--
-- COST: a handful of shots at once, one raycast each per Heartbeat. Expired or landed
-- shots are removed; nothing here lives longer than Lifetime.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local Palette = require(game.ReplicatedStorage.Shared.Config.Palette)

local ProjectileService = {}
local ctx
local PROJ = GameConfig.Projectile

local folder: Folder
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

export type Spec = {
	Speed: number, -- studs per second
	Range: number, -- studs before it drops out of the world
	Height: number, -- launch height above the shooter's root
	Size: Vector3?,
	Color: Color3?,
}

type Shot = {
	Part: BasePart,
	Direction: Vector3,
	Speed: number,
	Remaining: number,
	Damage: number,
	Name: string,
	Record: any,
	Landed: number?, -- when it stuck into the world; removed StickTime later
}

local shots: { Shot } = {}

-- Which player owns this instance, if it's part of a character. The swing weapon is a
-- model inside the character, so the nearest Model ancestor is not enough.
local function playerOf(inst: Instance): Player?
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and inst:IsDescendantOf(character) then
			return player
		end
	end
	return nil
end

function ProjectileService.Init(context, ignore: { Instance })
	ctx = context
	folder = Instance.new("Folder")
	folder.Name = "Projectiles"
	folder.Parent = workspace
	-- Shots pass through enemies, telegraphs, other shots and loot. Only the world and
	-- players stop them.
	local exclude = { folder :: Instance }
	for _, inst in ignore do
		table.insert(exclude, inst)
	end
	local loot = workspace:FindFirstChild("LootDrops")
	if loot then
		table.insert(exclude, loot)
	end
	local bossTelegraphs = workspace:FindFirstChild("Telegraphs")
	if bossTelegraphs then
		table.insert(exclude, bossTelegraphs)
	end
	params.FilterDescendantsInstances = exclude

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for i = #shots, 1, -1 do
			local shot = shots[i]
			local part = shot.Part
			if not part.Parent then
				table.remove(shots, i)
			elseif shot.Landed then
				if now - shot.Landed >= PROJ.StickTime then
					part:Destroy()
					table.remove(shots, i)
				end
			else
				local step = shot.Direction * (shot.Speed * dt)
				local from = part.Position
				local hit = workspace:Raycast(from, step, params)
				if hit then
					local player = playerOf(hit.Instance)
					if player then
						ctx.EnemyService.DamagePlayer(shot.Record, player, shot.Damage, shot.Name)
						part:Destroy()
						table.remove(shots, i)
					else
						-- The world: stick there, visibly, then go.
						part.CFrame =
							CFrame.lookAt(hit.Position - shot.Direction * (part.Size.Z / 2), hit.Position)
						shot.Landed = now
					end
				else
					part.CFrame = CFrame.lookAt(from + step, from + step + shot.Direction)
					shot.Remaining -= step.Magnitude
					if shot.Remaining <= 0 then
						part:Destroy()
						table.remove(shots, i)
					end
				end
			end
		end
	end)
end

-- Fire one shot from `record` along `origin`'s facing (the committed facing of the
-- attack, so a shot can be dodged by stepping out of the line during the windup).
function ProjectileService.Fire(record, origin: CFrame, spec: Spec, damage: number, attackName: string)
	if #shots >= PROJ.MaxLive then
		return -- never let a room of archers become a particle system
	end
	local direction = origin.LookVector
	local size = spec.Size or PROJ.DefaultSize
	local start = origin * CFrame.new(0, spec.Height, -1.5)

	local part = Instance.new("Part")
	part.Name = "Shot"
	part.Size = size
	part.Color = spec.Color or Palette.bleed
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.lookAt(start.Position, start.Position + direction)
	part.Parent = folder

	table.insert(shots, {
		Part = part,
		Direction = direction,
		Speed = spec.Speed,
		Remaining = spec.Range,
		Damage = damage,
		Name = attackName,
		Record = record,
		Landed = nil,
	})
	task.delay(PROJ.Lifetime, function()
		if part.Parent then
			part:Destroy()
		end
	end)
end

return ProjectileService
