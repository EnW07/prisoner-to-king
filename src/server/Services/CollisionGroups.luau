--!strict
-- CollisionGroups.lua
-- Enemies and players never physically collide. (Playtest 5, item 1: "enemies must stop
-- pushing me around; walking into the player needs to stop being a thing that happens.")
--
-- Two layers, belt and braces: the AI keeps a stand-off distance and never walks into you
-- (EnemyService.Think), and even if something does overlap, physics can't shove you.
-- Hit detection is unaffected: swing queries and raycasts use the Default group, which
-- still collides with both.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local CollisionGroups = {}

local ENEMIES = "PTKEnemies"
local PLAYERS = "PTKPlayers"
-- Parts that stop enemies but never players: the barred door (EnvironmentService).
local BARRIER = "PTKBarrier"

local function register(name: string)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

-- Put every part of `model`, now and later (costume added after spawn), into `group`.
local function assign(model: Instance, group: string)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
	model.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end)
end

function CollisionGroups.Init()
	register(ENEMIES)
	register(PLAYERS)
	register(BARRIER)
	PhysicsService:CollisionGroupSetCollidable(ENEMIES, PLAYERS, false)
	PhysicsService:CollisionGroupSetCollidable(BARRIER, PLAYERS, false)
	PhysicsService:CollisionGroupSetCollidable(BARRIER, ENEMIES, true)

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			assign(character, PLAYERS)
		end)
		if player.Character then
			assign(player.Character, PLAYERS)
		end
	end
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
end

-- Called by EnemyService for every enemy it spawns.
function CollisionGroups.TagEnemy(model: Model)
	assign(model, ENEMIES)
end

return CollisionGroups
