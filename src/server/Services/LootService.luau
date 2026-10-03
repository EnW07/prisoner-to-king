--!strict
-- LootService.lua
-- Blueprint §47. Every drop gets a server-generated ID and is claimed ATOMICALLY.
--
-- SECURITY: the client never tells the server what it picked up or how much it is worth.
-- Pickup is driven by a server-side Touched check plus a distance re-validation, and the
-- claim flag is flipped before any reward is granted, so two touches cannot both pay out.

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

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
end

local function newId(): string
	nextId += 1
	return ("loot_%d_%d"):format(os.time(), nextId)
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
	p.CanCollide = false
	p.CFrame = CFrame.new(position + Vector3.new(0, 2, 0))
	p.Parent = container

	-- Loot physically bursts out and is visible (§8).
	p.AssemblyLinearVelocity = Vector3.new(
		(math.random() - 0.5) * LootConfig.Pickups.BurstForce,
		LootConfig.Pickups.BurstForce * 0.7,
		(math.random() - 0.5) * LootConfig.Pickups.BurstForce
	)

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

	local record = {
		Id = id,
		Kind = kind,
		Payload = payload,
		Instance = p,
		Claimed = false,
		OwnerUserId = ownerUserId, -- nil = public
		SpawnTime = os.clock(),
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
