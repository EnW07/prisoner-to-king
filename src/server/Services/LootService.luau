--!strict
-- LootService.lua
-- Blueprint §47. Every drop gets a server-generated ID and is claimed ATOMICALLY.
--
-- SECURITY: the client never tells the server what it picked up or how much it is worth.
-- Pickup is driven server-side, by a proximity sweep plus Touched, with a distance
-- re-validation. The claim flag is flipped before any reward is granted, so two triggers
-- cannot both pay out.

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LootConfig = require(game.ReplicatedStorage.Shared.Config.LootConfig)
local WeaponConfig = require(game.ReplicatedStorage.Shared.Config.WeaponConfig)
local Net = require(game.ReplicatedStorage.Shared.Net)

local LootService = {}
local ctx
local Notify: RemoteEvent

local nextId = 0
local drops: { [string]: any } = {}
local container: Folder

function LootService.Init(context)
	ctx = context
	Notify = Net.Event("Notify")
	container = Instance.new("Folder")
	container.Name = "LootDrops"
	container.Parent = workspace

	-- Server-side proximity sweep. This is the primary pickup path now that drops are
	-- anchored: Touched on an anchored, non-collidable part depends on which character
	-- part grazes it (an accessory's parent isn't the character), so it can miss. Touched
	-- stays connected for instant pickup; this sweep guarantees it. TryPickup re-validates
	-- everything either way.
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < LootConfig.Pickups.SweepInterval then
			return
		end
		accumulator = 0
		LootService.Sweep()
	end)
end

local function newId(): string
	nextId += 1
	return ("loot_%d_%d"):format(os.time(), nextId)
end

-- Where a drop comes to rest. P0 fix (playtest 3): loot used to be an unanchored,
-- CanCollide = false part flung with a velocity, so nothing stopped it falling through
-- the floor. Now the landing point is raycast against the level geometry and the part
-- stays anchored. It can't fall, roll away, or be knocked into a wall.
local function landingPoint(origin: Vector3, size: Vector3): Vector3
	local cfg = LootConfig.Pickups
	local world = ctx.World and ctx.World.Folder
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = if world
		then { world:FindFirstChild("Zones"), world:FindFirstChild("Interactables") }
		else {}

	-- Scatter sideways, but stop short of any wall or door between the drop and the target.
	local angle = math.random() * 2 * math.pi
	local scatter = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (math.random() * cfg.ScatterRadius)
	local wall = workspace:Raycast(origin, scatter, params)
	if wall then
		scatter = scatter.Unit * math.max(0, wall.Distance - size.Magnitude)
	end

	local probe = Vector3.new(0, -cfg.FloorProbeDepth, 0)
	local floor = workspace:Raycast(origin + scatter, probe, params)
		or workspace:Raycast(origin, probe, params)
	if not floor then
		warn(("[Loot] No floor under drop at %s; resting at the drop point."):format(tostring(origin)))
	end
	local base = if floor then floor.Position else origin
	return base + Vector3.new(0, size.Y / 2 + cfg.Hover, 0)
end

-- kind: "Gold" | "Key" | "Weapon"
function LootService.Spawn(kind: string, position: Vector3, payload: any, ownerUserId: number?)
	local visual = LootConfig.Pickups[kind]
	if not visual then
		return
	end

	local id = newId()

	local p = Instance.new("Part")
	p.Name = "Loot_" .. kind
	p.Size = visual.Size
	p.Color = visual.Color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CFrame = CFrame.new(position)
	p.Parent = container

	-- Loot still bursts out visibly (§8), as a tweened hop onto the floor rather than physics.
	local cfg = LootConfig.Pickups
	local landing = landingPoint(position, visual.Size)
	local apex = position:Lerp(landing, 0.5) + Vector3.new(0, cfg.HopHeight, 0)
	local rise = TweenService:Create(
		p,
		TweenInfo.new(cfg.HopTime / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(apex) }
	)
	rise.Completed:Connect(function()
		if p.Parent then
			local fall = TweenService:Create(
				p,
				TweenInfo.new(cfg.HopTime / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = CFrame.new(landing) }
			)
			fall.Completed:Connect(function()
				-- Clients bob and spin it from here on, locally (WorldFXController).
				-- The server never moves it again, so the two never fight.
				p:SetAttribute("Landed", true)
			end)
			fall:Play()
		end
	end)
	rise:Play()

	local label = Instance.new("BillboardGui")
	label.Size = UDim2.fromOffset(140, 34)
	label.StudsOffset = Vector3.new(0, 1.6, 0)
	label.AlwaysOnTop = true
	label.Parent = p
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = visual.Color
	text.TextStrokeTransparency = 0.2
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.Text = if kind == "Gold" then ("+%d Gold"):format(payload) else visual.Label
	text.Parent = label

	-- A beam up from the drop (I3, K1): visible across a room, sized and coloured by what
	-- it is. Weapons by rarity tier; gold a thin gold line; the key a thin pale one.
	local VFX = require(game.ReplicatedStorage.Shared.Config.GameConfig).VFX
	local beamColor = visual.Color
	local tier = 1
	if kind == "Weapon" then
		local weapon = WeaponConfig.Get(payload)
		if weapon then
			beamColor = WeaponConfig.RarityColors[weapon.Rarity] or beamColor
			local tiers = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 }
			tier = tiers[weapon.Rarity] or 1
		end
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "BeamBase"
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Name = "BeamTop"
	a1.Position = Vector3.new(0, VFX.BeamHeight, 0)
	a1.Parent = p
	local beam = Instance.new("Beam")
	beam.Name = "RarityBeam"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(beamColor)
	beam.Width0 = VFX.BeamWidth[tier] or 0.5
	beam.Width1 = 0.05
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Parent = p

	local record = {
		Id = id,
		Kind = kind,
		Payload = payload,
		Instance = p,
		Claimed = false,
		OwnerUserId = ownerUserId, -- nil = public
		SpawnTime = os.clock(),
		SafePosition = landing, -- where the sweep puts it back if it ever ends up below the map
	}
	drops[id] = record

	p.Touched:Connect(function(hit)
		local character = hit.Parent
		if not character then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if player then
			LootService.TryPickup(player, id)
		end
	end)

	task.delay(LootConfig.Pickups.Lifetime, function()
		if drops[id] and not drops[id].Claimed then
			drops[id] = nil
			p:Destroy()
		end
	end)

	return id
end

-- Proximity pickup plus a below-the-map safety net. Runs every Pickups.SweepInterval.
function LootService.Sweep()
	local cfg = LootConfig.Pickups
	-- Snapshot first: a pickup can yield (equipping a weapon waits for the hand), and new
	-- drops may be added meanwhile. Never mutate a table while iterating it across a yield.
	local snapshot = {}
	for id, record in drops do
		table.insert(snapshot, { id, record })
	end
	for _, entry in snapshot do
		local id, record = entry[1], entry[2]
		if not drops[id] then
			continue
		end
		local part = record.Instance
		if part.Position.Y < cfg.MinSafeY then
			warn(("[Loot] %s fell below the map; restoring it."):format(id))
			part.CFrame = CFrame.new(record.SafePosition)
		end
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - part.Position).Magnitude <= cfg.PickupRadius then
				LootService.TryPickup(player, id)
				if not drops[id] then
					break
				end
			end
		end
	end
end

function LootService.TryPickup(player: Player, id: string)
	local record = drops[id]
	if not record then
		return
	end

	-- ATOMIC CLAIM. Flip the flag before granting anything. Luau is single-threaded per
	-- script, and there is no yield between the check and the write, so two Touched
	-- callbacks cannot both pass this gate.
	if record.Claimed then
		return
	end

	if record.OwnerUserId and record.OwnerUserId ~= player.UserId then
		return
	end

	-- Distance re-validation: never trust that a Touched event means the player is actually there.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if (root.Position - record.Instance.Position).Magnitude > LootConfig.Pickups.PickupRadius then
		return
	end

	record.Claimed = true
	drops[id] = nil

	if record.Kind == "Gold" then
		ctx.RunState.AddUnsecuredGold(player, record.Payload)
		Notify:FireClient(player, { Text = ("+%d Gold"):format(record.Payload), Kind = "gold" })
	elseif record.Kind == "Key" then
		ctx.RunState.GiveKey(player)
	elseif record.Kind == "Weapon" then
		ctx.Combat.GiveWeapon(player, record.Payload)
	end

	ctx.Analytics.Log(player, "FirstLootPicked", 1, { kind = record.Kind })
	ctx.Analytics.Log(player, "LootPicked", 1, { kind = record.Kind })

	record.Instance:Destroy()
end

-- Weighted roll. Randomisation lives HERE, on the server, never in a config or on a client.
function LootService.RollTable(tableName: string): { any }
	local def = LootConfig.Tables[tableName]
	if not def then
		return {}
	end

	local results = {}
	for _ = 1, def.Rolls do
		local total = 0
		for _, entry in def.Entries do
			total += entry.Weight
		end
		local roll = math.random() * total
		local acc = 0
		for _, entry in def.Entries do
			acc += entry.Weight
			if roll <= acc then
				if entry.Kind ~= "None" then
					table.insert(results, entry)
				end
				break
			end
		end
	end
	return results
end

-- Roll a loot table and drop the results at `position`, owned by `owner` if given, so a
-- bystander can't take someone else's reward. Used by the repeat-run chest.
function LootService.DropTable(tableName: string, position: Vector3, owner: Player?)
	local ownerId = owner and owner.UserId or nil
	for _, entry in LootService.RollTable(tableName) do
		if entry.Kind == "Gold" then
			LootService.Spawn("Gold", position, math.random(entry.Min or 1, entry.Max or 1), ownerId)
		elseif entry.Kind == "Weapon" and entry.Id then
			LootService.Spawn("Weapon", position, entry.Id, ownerId)
		end
	end
end

-- Drop everything an enemy owes, at its death position.
function LootService.DropForEnemy(enemyId: string, position: Vector3, killer: Player?)
	local EnemyConfig = require(game.ReplicatedStorage.Shared.Config.EnemyConfig)
	local cfg = EnemyConfig.Get(enemyId)
	if not cfg then
		return
	end

	-- Guaranteed base gold so a kill is never a total blank (§13 / §67 fail-soft).
	local gold = math.random(cfg.GoldMin, cfg.GoldMax)
	LootService.Spawn("Gold", position, gold)

	-- Guaranteed drops (e.g. Captain Bronn's Guard Sword). Weapons belong to the killer, so a
	-- bystander can't walk off with the reward for someone else's fight.
	local tableDef = LootConfig.Tables[cfg.LootTable]
	if tableDef and tableDef.Guaranteed then
		for _, entry in tableDef.Guaranteed do
			LootService.Spawn(entry.Kind, position, entry.Id, killer and killer.UserId or nil)
		end
	end

	for _, entry in LootService.RollTable(cfg.LootTable) do
		if entry.Kind == "Gold" then
			LootService.Spawn("Gold", position, math.random(entry.Min or 1, entry.Max or 1))
		elseif entry.Kind == "Weapon" and entry.Id then
			LootService.Spawn("Weapon", position, entry.Id)
		end
	end

	-- §115 first-run guarantee: the first guard a player kills ALWAYS drops the key.
	if killer and LootConfig.Guarantees.FirstGuardDropsKey then
		local run = ctx.RunState.Get(killer)
		if run and not run.HasKey and not run.FirstGuardKilled then
			run.FirstGuardKilled = true
			LootService.Spawn("Key", position + Vector3.new(0, 0, 1.5), true, killer.UserId)
		end
	end
end

function LootService.WeaponDisplayName(id: string): string
	local w = WeaponConfig.Get(id)
	return w and w.Name or id
end

return LootService
