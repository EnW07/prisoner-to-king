--!strict
-- RoomService.lua
-- Which room each player is in. One responsibility: room entry. (MASTER_BUILD_SPEC H2, L6.)
--
-- Rooms are boxes WorldBuilder returns (world.Rooms). On a slow tick the server checks
-- every living player against them; entering a new room logs RoomEntered, marks it on
-- the run (so CAPTURED can say "4 rooms entered"), and tells the client, which shows the
-- name briefly and may tint its ambience. A room marked Secret also counts as a secret
-- found. Nothing here is authoritative over anything but bookkeeping.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(game.ReplicatedStorage.Shared.Net)

local RoomService = {}
local ctx
local world
local Notify: RemoteEvent

local current: { [number]: string } = {}
local accumulator = 0

local function roomAt(position: Vector3): any?
	for _, room in world.Rooms do
		local lo, hi = room.Min, room.Max
		if
			position.X >= lo.X
			and position.X <= hi.X
			and position.Y >= lo.Y
			and position.Y <= hi.Y
			and position.Z >= lo.Z
			and position.Z <= hi.Z
		then
			return room
		end
	end
	return nil
end

local function tick()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local room = roomAt(root.Position)
			local name = room and room.Name or nil
			if name ~= current[player.UserId] then
				current[player.UserId] = name
				if room then
					local first = ctx.RunState.MarkRoom(player, room.Name)
					if first then
						ctx.Analytics.Log(player, "RoomEntered", 1, { room = room.Name })
						if room.Secret then
							ctx.Analytics.Log(player, "SecretFound", 1, { secret = room.Name })
						end
					end
					Notify:FireClient(player, { Text = room.Name, Kind = "room", First = first })
				end
			end
		end
	end
end

function RoomService.Init(context, builtWorld)
	ctx = context
	world = builtWorld
	Notify = Net.Event("Notify")

	Players.PlayerRemoving:Connect(function(player)
		current[player.UserId] = nil
	end)
	-- A new character starts outside every room, so the first room announces itself.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			current[player.UserId] = nil
		end)
	end)

	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < GameConfig.Rooms.CheckInterval then
			return
		end
		accumulator = 0
		tick()
	end)
end

-- The room a player is standing in right now, by name (nil outside every room).
function RoomService.Current(player: Player): string?
	return current[player.UserId]
end

return RoomService
