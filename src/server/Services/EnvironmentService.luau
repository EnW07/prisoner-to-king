--!strict
-- EnvironmentService.lua
-- Things in the castle the player can USE against it. One responsibility: environmental
-- interaction. (MASTER_BUILD_SPEC H4; blueprint §90: systems that make sentences.)
--
--   • BREAKABLES  crates and barrels (tag PTKBreakable). A validated swing that overlaps
--                 one breaks it: chunks fly, a little loot drops, it comes back later.
--   • CHANDELIERS a winch prompt drops the chandelier above it; enemies underneath take
--                 heavy damage ("I dropped a chandelier on three guards"). It is hauled
--                 back up after a while.
--   • THE BAR     a winch on the vault side of the passage door bars it. Enemies cannot
--                 pass for BarDuration; then the guards break it open.
--
-- All of it is SHARED world state (the castle is one place for everyone on the server),
-- and all of it is decided here on the server: the client only sees parts move. The
-- swing's overlap query is CombatService's; it hands any breakable parts it touched to
-- Break. ProximityPrompts fire on the server with the real player, re-validated by
-- distance like every other prompt.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local Palette = require(game.ReplicatedStorage.Shared.Config.Palette)
local Net = require(game.ReplicatedStorage.Shared.Net)

local EnvironmentService = {}
local ctx
local world
local Notify: RemoteEvent
local ENV = GameConfig.Environment

local breakables: Folder
local chandeliers: { [BasePart]: { Winch: BasePart, RestY: number, Dropped: boolean } } = {}
local barred = false
local barToken = 0

local function makePrompt(parent: BasePart, action: string, object: string, hold: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = parent
	return prompt
end

local function near(player: Player, target: BasePart, range: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return root ~= nil
		and root:IsA("BasePart")
		and humanoid ~= nil
		and humanoid.Health > 0
		and (root.Position - target.Position).Magnitude <= range
end

-- ── Breakables ──────────────────────────────────────────────────
-- Chunks of the broken thing fly out and vanish; the loot is real (LootService).
local function burst(part: BasePart)
	local n = ENV.BreakChunks
	for _ = 1, n do
		local chunk = Instance.new("Part")
		chunk.Size = part.Size / 3
		chunk.Color = part.Color
		chunk.Material = part.Material
		chunk.CFrame = part.CFrame
			* CFrame.new((math.random() - 0.5) * part.Size.X, 0, (math.random() - 0.5) * part.Size.Z)
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.Parent = workspace
		chunk.AssemblyLinearVelocity =
			Vector3.new((math.random() - 0.5) * 16, 10 + math.random() * 8, (math.random() - 0.5) * 16)
		chunk.AssemblyAngularVelocity = Vector3.new(math.random() * 6, math.random() * 6, math.random() * 6)
		TweenService
			:Create(chunk, TweenInfo.new(ENV.ChunkLife, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1,
			})
			:Play()
		Debris:AddItem(chunk, ENV.ChunkLife)
	end
end

-- Break a tagged part. Returns true if it broke now (false if already broken).
function EnvironmentService.Break(part: BasePart, player: Player?): boolean
	if not CollectionService:HasTag(part, "PTKBreakable") or part:GetAttribute("Broken") then
		return false
	end
	part:SetAttribute("Broken", true)
	burst(part)
	-- Small loot, sometimes. Barrels pay a little more than crates.
	local kind = tostring(part:GetAttribute("Breakable") or "crate")
	local lootTable = ENV.LootTables[kind]
	if lootTable and player then
		ctx.LootService.DropTable(lootTable, part.Position + Vector3.new(0, 1, 0), nil)
		ctx.Analytics.Log(player, "BreakableBroken", 1, { kind = kind })
	end
	-- Hide it and bring it back later: a shared castle restocks its clutter.
	local children = {}
	for _, d in part:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(children, { d, d.Transparency })
			d.Transparency = 1
			d.CanCollide = false
		end
	end
	local wasCollide = part.CanCollide
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	task.delay(ENV.BreakableRespawn, function()
		if not part.Parent then
			return
		end
		part.Transparency = 0
		part.CanCollide = wasCollide
		part.CanQuery = true
		for _, entry in children do
			entry[1].Transparency = entry[2]
			entry[1].CanCollide = false
		end
		part:SetAttribute("Broken", nil)
	end)
	return true
end

-- The parts a swing may break: the folder CombatService adds to its overlap query.
function EnvironmentService.GetBreakables(): Folder
	return breakables
end

-- ── Chandeliers ─────────────────────────────────────────────────
local function dropChandelier(hub: BasePart, record, player: Player)
	if record.Dropped then
		return
	end
	record.Dropped = true
	local floorY = hub.Position.Y - ENV.ChandelierDrop
	local fall = TweenService:Create(
		hub,
		TweenInfo.new(ENV.ChandelierFallTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = CFrame.new(hub.Position.X, floorY + 0.5, hub.Position.Z) }
	)
	fall.Completed:Connect(function()
		-- Everyone under it, enemy or player. Enemies take a lot: this is the story.
		local centre = hub.Position
		local radius = ENV.ChandelierRadius
		local hitAny = false
		for model, enemy in ctx.EnemyService.GetActive() do
			local root = model.PrimaryPart
			if
				root
				and (
						Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(centre.X, 0, centre.Z)
					).Magnitude
					<= radius
			then
				hitAny = true
				ctx.EnemyService.ApplyDamage(model, ENV.ChandelierDamage, player, {
					Contact = root.Position,
					Knockback = ENV.ChandelierKnockback,
					Heavy = true,
					GuardBreak = true,
				})
			end
			local _ = enemy
		end
		ctx.Analytics.Log(player, "ChandelierDropped", 1, { hit = if hitAny then "yes" else "no" })
		Notify:FireAllClients({ Text = "", Kind = "chandelier", Position = centre })
		-- Hauled back up later, for the next player (or the next run).
		task.delay(ENV.ChandelierReset, function()
			if hub.Parent then
				TweenService:Create(hub, TweenInfo.new(ENV.ChandelierRaiseTime, Enum.EasingStyle.Sine), {
					CFrame = CFrame.new(hub.Position.X, record.RestY, hub.Position.Z),
				}):Play()
				task.delay(ENV.ChandelierRaiseTime, function()
					record.Dropped = false
				end)
			end
		end)
	end)
	fall:Play()
end

local function setupChandelier(hub: Instance)
	if not hub:IsA("BasePart") then
		return
	end
	local winchName = tostring(hub:GetAttribute("Winch") or "")
	local winch = world.Interactables:FindFirstChild(winchName)
	if not winch or not winch:IsA("BasePart") then
		warn(("[Environment] Chandelier %s has no winch %q"):format(hub.Name, winchName))
		return
	end
	local record =
		{ Winch = winch, RestY = tonumber(hub:GetAttribute("RestY")) or hub.Position.Y, Dropped = false }
	chandeliers[hub] = record
	local prompt = makePrompt(winch, "Cut", "CHANDELIER CHAIN", 0.4)
	prompt:SetAttribute("PTKGate", "always")
	prompt.Triggered:Connect(function(player)
		if near(player, winch, ENV.PromptRange) then
			dropChandelier(hub, record, player)
		end
	end)
end

-- ── The barrable door ───────────────────────────────────────────
local function setBarred(on: boolean)
	barred = on
	local door: BasePart = world.BarDoor
	local bar: BasePart = world.DoorBar
	-- The door is solid for ENEMIES while barred (they path straight into it); players
	-- pass through either way, so nobody is ever locked out of the vault. Enemies and
	-- players are in different collision groups: the door joins the enemies' side.
	door.CanCollide = on
	door.CanQuery = on -- an open door blocks neither sight nor arrows; a barred one blocks both
	door.Transparency = if on then 0 else 0.75
	bar.Transparency = if on then 0 else 1
	door:SetAttribute("Barred", on)
end

local function setupBar()
	local winch: BasePart = world.BarWinch
	local prompt = makePrompt(winch, "Bar", "BAR THE DOOR BEHIND YOU", 0.6)
	prompt:SetAttribute("PTKGate", "bar")
	prompt.Triggered:Connect(function(player)
		if barred or not near(player, winch, ENV.PromptRange) then
			return
		end
		setBarred(true)
		barToken += 1
		local token = barToken
		ctx.Analytics.Log(player, "DoorBarred", 1)
		Notify:FireClient(player, { Text = "DOOR BARRED", Sub = "THEY WILL BREAK IT", Kind = "milestone" })
		task.delay(ENV.BarDuration, function()
			if barToken == token and barred then
				setBarred(false)
				Notify:FireAllClients({ Text = "THE DOOR GIVES WAY", Kind = "alarm" })
			end
		end)
	end)
end

function EnvironmentService.Init(context, builtWorld)
	ctx = context
	world = builtWorld
	Notify = Net.Event("Notify")

	-- Breakables live where WorldDressing put them (Props); the swing query needs one
	-- folder, so they are gathered under it by tag.
	breakables = Instance.new("Folder")
	breakables.Name = "Breakables"
	breakables.Parent = workspace
	for _, part in CollectionService:GetTagged("PTKBreakable") do
		if part:IsA("BasePart") then
			part.Parent = breakables
		end
	end
	CollectionService:GetInstanceAddedSignal("PTKBreakable"):Connect(function(part)
		if part:IsA("BasePart") and part.Parent ~= breakables then
			part.Parent = breakables
		end
	end)

	for _, hub in CollectionService:GetTagged("PTKChandelier") do
		setupChandelier(hub)
	end
	if world.BarDoor and world.BarWinch and world.DoorBar then
		setupBar()
		-- The door's collision group: enemies collide with it when barred, players never do.
		pcall(function()
			(world.BarDoor :: BasePart).CollisionGroup = "PTKBarrier"
		end)
	end
end

return EnvironmentService
