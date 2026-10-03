--!strict
-- CaptainService.lua
-- Captain Bronn, the Milestone 2 miniboss. (M2 brief item 1; blueprint §12, §18, §116.)
--
-- One responsibility: Bronn's encounter. EnemyService still owns the rig, damage intake and
-- death; this module supplies his brain through EnemyService's boss hooks.
--
-- Design rules this file exists to keep:
--   • He fights only players inside his hall (world.CaptainArena) and never leaves it, so he
--     can never block the chest or the escape route. Fighting him is always a choice (§115).
--   • Every attack is telegraphed hard and without sound (art §2 no-sound test): the sword
--     takes a distinct pose and glows `bleed`, his body is outlined, the attack's name
--     appears over his head, and the exact hit area is painted on the floor.
--   • The melee pattern is a fixed rotation, not random, so a death teaches the pattern.
--   • All numbers live in EnemyConfig.captain_bronn and GameConfig.Captain.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local EnemyConfig = require(game.ReplicatedStorage.Shared.Config.EnemyConfig)
local Palette = require(game.ReplicatedStorage.Shared.Config.Palette)
local Net = require(game.ReplicatedStorage.Shared.Net)

local CaptainService = {}
local ctx
local world
local Notify: RemoteEvent
local telegraphs: Folder

local ENEMY_ID = "captain_bronn"
local TUNE = GameConfig.Captain

-- Sword poses relative to his root. These are rig geometry, like WorldBuilder coordinates,
-- not balance values. Each wind-up pose must be readable as a silhouette on its own.
local POSES = {
	Rest = CFrame.new(2.6, -0.5, -0.8) * CFrame.Angles(math.rad(-25), 0, 0), -- held low
	Cleave = CFrame.new(3.6, 1.5, 1) * CFrame.Angles(0, 0, math.rad(-75)), -- drawn back wide
	Overhead = CFrame.new(0.8, 6.5, 0) * CFrame.Angles(math.rad(10), 0, 0), -- raised straight up
	Lowered = CFrame.new(1.6, -0.5, -3) * CFrame.Angles(math.rad(-80), 0, 0), -- levelled like a lance
}
local POSE_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SWING_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Linear)

type Nameplate = { Fill: Frame, HealthText: TextLabel, Callout: TextLabel }

type Fight = {
	Record: any,
	Grip: Weld,
	Sword: BasePart,
	Highlight: Highlight,
	Nameplate: Nameplate,
	Busy: boolean,
	InFight: boolean,
	RotationIndex: number,
	NextAttackAt: number,
	LastTargetAt: number,
	Reinforced: boolean,
	Engaged: { [number]: boolean },
	Markers: { BasePart },
}

-- TODO(per-player instancing): Bronn is ONE shared, replicated enemy. If any player kills
-- him he is gone for everyone until GameConfig.Captain.RespawnDelay elapses, even for a
-- player whose run has only just started. It's the same replicated-state limitation as
-- the ProximityPrompts and the cellblock door (M1 bugs 1/2/5): world state is global, but
-- objectives are per-player. The eventual fix is per-player (or per-party) dungeon
-- instancing. Accepted for M2 (decision 2026-10-03). Don't build it piecemeal here.
local fight: Fight? = nil

-- Guards Bronn has called. Module-level, not per-Fight, so a guard that outlives the Bronn
-- who called it is still found and removed when the next Bronn spawns.
local reinforcements: { any } = {}

-- Despawn every living reinforcement. Called on reset, before calling a new one, and when
-- a fresh Bronn spawns, so they can never accumulate across engagements. (Playtest 3, P2.)
local function dismissReinforcements()
	for _, guard in reinforcements do
		ctx.EnemyService.Despawn(guard)
	end
	table.clear(reinforcements)
end

-- ── Helpers ─────────────────────────────────────────────────────
local function livingRoot(player: Player): BasePart?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if root and hum and hum.Health > 0 then
		return root
	end
	return nil
end

local function inArena(pos: Vector3): boolean
	local a = world.CaptainArena
	return pos.X >= a.Min.X
		and pos.X <= a.Max.X
		and pos.Y >= a.Min.Y
		and pos.Y <= a.Max.Y
		and pos.Z >= a.Min.Z
		and pos.Z <= a.Max.Z
end

local function clampToArena(pos: Vector3, margin: number): Vector3
	local a = world.CaptainArena
	return Vector3.new(
		math.clamp(pos.X, a.Min.X + margin, a.Max.X - margin),
		pos.Y,
		math.clamp(pos.Z, a.Min.Z + margin, a.Max.Z - margin)
	)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function facing(from: Vector3, toward: Vector3): CFrame
	return CFrame.lookAt(from, Vector3.new(toward.X, from.Y, toward.Z))
end

local function alive(f: Fight): boolean
	return fight == f and f.Record.State ~= "Dead" and f.Record.Humanoid.Health > 0
end

local function weaponId(player: Player): string
	local profile = ctx.Data.Get(player)
	return profile and profile.Equipped.WeaponId or "unknown"
end

local function runIndex(player: Player): string
	local run = ctx.RunState.Get(player)
	return tostring(run and run.RunIndex or 0)
end

local function notifyEngaged(f: Fight, payload)
	for userId in f.Engaged do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			Notify:FireClient(player, payload)
		end
	end
end

local function weld(part0: BasePart, part1: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part0
	w.Part1 = part1
	w.Parent = part1
end

local function armourPart(
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- ── Presentation ────────────────────────────────────────────────
-- Silhouette: wider, taller and differently proportioned than any guard (art §8 priority 1),
-- with a crested helm, pauldrons and an oversized greatsword. Readable as a black shape.
local function dress(record): (Weld, BasePart, Highlight, Nameplate)
	local model: Model = record.Model
	local root = model.PrimaryPart :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart
	local body: Vector3 = record.Config.BodySize

	local stockBlade = model:FindFirstChild("Blade")
	if stockBlade then
		stockBlade:Destroy()
	end

	-- His own nameplate replaces the stock Humanoid one.
	record.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	for _, side in { -1, 1 } do
		local pauldron = armourPart(
			"Pauldron",
			Vector3.new(1.8, 1.1, body.Z + 0.6),
			root.CFrame * CFrame.new(side * (body.X / 2 + 0.5), body.Y / 2 - 0.4, 0),
			Palette.stone,
			Enum.Material.Metal,
			model
		)
		weld(root, pauldron)
	end

	local helm = armourPart(
		"Helm",
		head.Size + Vector3.new(0.5, 0.4, 0.5),
		head.CFrame,
		Palette.stone,
		Enum.Material.Metal,
		model
	)
	weld(root, helm)
	local crest = armourPart(
		"Crest",
		Vector3.new(0.4, 1.2, head.Size.Z + 0.6),
		head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.7, 0),
		Palette.bleed,
		Enum.Material.SmoothPlastic,
		model
	)
	weld(root, crest)

	-- The greatsword. A real Weld (not a constraint) so C0 can be tweened between poses.
	local sword = armourPart(
		"Greatsword",
		Vector3.new(0.8, 7.5, 0.35),
		root.CFrame * POSES.Rest,
		Palette.stone,
		Enum.Material.Metal,
		model
	)
	local grip = Instance.new("Weld")
	grip.Name = "Grip"
	grip.Part0 = root
	grip.Part1 = sword
	grip.C0 = POSES.Rest
	grip.Parent = sword

	local highlight = Instance.new("Highlight")
	highlight.Adornee = model
	highlight.FillColor = Palette.bleed
	highlight.OutlineColor = Palette.bleed
	highlight.FillTransparency = TUNE.TelegraphTransparency
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = model

	-- Name + health bar, readable from the cellblock door (brief: "a thing you fight").
	-- Offset-sized so it stays legible at distance; occluded by walls so it isn't a wallhack.
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate"
	gui.Size = UDim2.fromOffset(300, 96)
	gui.StudsOffset = Vector3.new(0, head.Size.Y + 2.4, 0)
	gui.MaxDistance = TUNE.NameplateMaxDistance
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 30)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = record.Config.DisplayName:upper()
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextSize = 26
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.2
	nameLabel.Parent = gui

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 22)
	bar.Position = UDim2.fromOffset(0, 32)
	bar.BackgroundColor3 = Palette.pitch
	bar.BorderSizePixel = 0
	bar.Parent = gui

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Palette.bleed
	fill.BorderSizePixel = 0
	fill.Parent = bar

	local healthText = Instance.new("TextLabel")
	healthText.Size = UDim2.fromScale(1, 1)
	healthText.BackgroundTransparency = 1
	healthText.Font = Enum.Font.GothamBlack
	healthText.TextSize = 18
	healthText.TextColor3 = Color3.new(1, 1, 1)
	healthText.TextStrokeTransparency = 0.3
	healthText.ZIndex = 2
	healthText.Parent = bar

	-- The attack callout. Big, `bleed`, only visible during a wind-up.
	local callout = Instance.new("TextLabel")
	callout.Size = UDim2.new(1, 0, 0, 38)
	callout.Position = UDim2.fromOffset(0, 58)
	callout.BackgroundTransparency = 1
	callout.Font = Enum.Font.GothamBlack
	callout.TextSize = 32
	callout.TextColor3 = Palette.bleed
	callout.TextStrokeTransparency = 0
	callout.Visible = false
	callout.Parent = gui

	return grip, sword, highlight, { Fill = fill, HealthText = healthText, Callout = callout }
end

local function refreshHealth(f: Fight)
	local hum: Humanoid = f.Record.Humanoid
	local frac = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
	f.Nameplate.Fill.Size = UDim2.fromScale(frac, 1)
	f.Nameplate.HealthText.Text = ("%d / %d"):format(math.ceil(hum.Health), hum.MaxHealth)
end

local function setPose(f: Fight, pose: string, info: TweenInfo)
	TweenService:Create(f.Grip, info, { C0 = POSES[pose] }):Play()
end

local function setTelegraph(f: Fight, attackName: string?)
	local on = attackName ~= nil
	f.Highlight.Enabled = on
	f.Sword.Material = if on then Enum.Material.Neon else Enum.Material.Metal
	f.Sword.Color = if on then Palette.bleed else Palette.stone
	f.Nameplate.Callout.Text = if attackName then attackName .. "!" else ""
	f.Nameplate.Callout.Visible = on
end

-- Paints the exact hit area on the floor for the whole wind-up. What you see is precisely
-- what the server will test: both use the same `origin` and the same attack data.
local function makeMarker(f: Fight, attack, origin: CFrame, reach: number): BasePart
	local body: Vector3 = f.Record.Config.BodySize
	local floor = origin * CFrame.new(0, -body.Y / 2 + 0.08, 0)

	local p = Instance.new("Part")
	p.Name = "Telegraph"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Palette.bleed
	p.Transparency = 0.85

	if attack.Shape == "Circle" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.1, attack.Radius * 2, attack.Radius * 2)
		p.CFrame = floor * CFrame.new(0, 0, -attack.Offset) * CFrame.Angles(0, 0, math.rad(90))
	else
		-- Box and Charge both paint a rectangle starting at his feet.
		p.Size = Vector3.new(attack.Width, 0.1, reach)
		p.CFrame = floor * CFrame.new(0, 0, -reach / 2)
	end
	p.Parent = telegraphs
	table.insert(f.Markers, p)

	-- The area "fills in" as the swing approaches: fainter early, solid just before impact.
	TweenService:Create(p, TweenInfo.new(attack.WindUp, Enum.EasingStyle.Linear), {
		Transparency = TUNE.TelegraphTransparency,
	}):Play()
	return p
end

local function removeMarker(f: Fight, marker: BasePart)
	local i = table.find(f.Markers, marker)
	if i then
		table.remove(f.Markers, i)
	end
	marker:Destroy()
end

-- ── Attacks ─────────────────────────────────────────────────────
local function hits(attack, origin: CFrame, pos: Vector3): boolean
	local p = origin:PointToObjectSpace(pos)
	if math.abs(p.Y) > TUNE.HitHeightTolerance then
		return false
	end
	if attack.Shape == "Box" then
		return math.abs(p.X) <= attack.Width / 2 and p.Z <= 0 and p.Z >= -attack.Length
	elseif attack.Shape == "Circle" then
		local dz = p.Z + attack.Offset
		return p.X * p.X + dz * dz <= attack.Radius * attack.Radius
	end
	return false
end

local function strike(f: Fight, attack, origin: CFrame, damage: number)
	for _, player in Players:GetPlayers() do
		local pRoot = livingRoot(player)
		if pRoot and hits(attack, origin, pRoot.Position) then
			ctx.EnemyService.DamagePlayer(f.Record, player, damage, attack.Name)
		end
	end
end

local function charge(f: Fight, attack, destination: Vector3, damage: number)
	local record = f.Record
	local hum: Humanoid = record.Humanoid
	local root = record.Model.PrimaryPart :: BasePart
	local reach = attack.Width / 2 + record.Config.BodySize.X / 2
	local struck: { [Player]: boolean } = {}

	hum.WalkSpeed = TUNE.ChargeSpeed
	hum:MoveTo(destination)
	local deadline = os.clock() + flatDistance(root.Position, destination) / TUNE.ChargeSpeed

	-- Checked every frame, not on the AI tick: at charge speed he covers ~10 studs a tick.
	while os.clock() < deadline and alive(f) do
		for _, player in Players:GetPlayers() do
			local pRoot = livingRoot(player)
			if pRoot and not struck[player] and flatDistance(pRoot.Position, root.Position) <= reach then
				struck[player] = true
				ctx.EnemyService.DamagePlayer(record, player, damage, attack.Name)
			end
		end
		RunService.Heartbeat:Wait()
	end

	hum.WalkSpeed = 0
	hum:MoveTo(root.Position)
end

local function performAttack(f: Fight, attack, aim: Vector3)
	local record = f.Record
	local cfg = record.Config
	local hum: Humanoid = record.Humanoid
	local root = record.Model.PrimaryPart :: BasePart
	f.Busy = true

	-- Plant and lock facing. The strike resolves against THIS origin, so stepping out of the
	-- painted area during the wind-up is always a clean dodge.
	hum.WalkSpeed = 0
	hum:MoveTo(root.Position)
	local origin = facing(root.Position, aim)
	root.CFrame = origin

	local reach = attack.Length or 0
	local destination = root.Position
	if attack.Shape == "Charge" then
		destination = clampToArena((origin * CFrame.new(0, 0, -attack.Length)).Position, cfg.BodySize.X)
		reach = flatDistance(root.Position, destination)
	end

	local marker = makeMarker(f, attack, origin, reach)
	setTelegraph(f, attack.Name)
	setPose(f, attack.Pose, POSE_TWEEN)

	task.wait(attack.WindUp)

	if alive(f) then
		local damage = math.floor(cfg.Damage * attack.DamageMultiplier + 0.5)
		marker.Transparency = 0
		setTelegraph(f, nil)
		setPose(f, "Rest", SWING_TWEEN)
		if attack.Shape == "Charge" then
			charge(f, attack, destination, damage)
		else
			strike(f, attack, origin, damage)
		end
		task.wait(TUNE.StrikeFlashTime)
	end
	removeMarker(f, marker)

	if not alive(f) then
		return
	end
	-- Recovery: he stands still. This is the player's punish window.
	task.wait(attack.Recovery)
	if not alive(f) then
		return
	end
	hum.WalkSpeed = cfg.MoveSpeed
	f.NextAttackAt = os.clock() + cfg.AttackCooldown
	f.Busy = false
end

-- ── Brain ───────────────────────────────────────────────────────
local function engage(f: Fight, player: Player)
	if f.Engaged[player.UserId] then
		return
	end
	f.Engaged[player.UserId] = true
	ctx.Analytics.Log(player, "CaptainEngaged", 1, { weapon = weaponId(player), run = runIndex(player) })
	-- Spell out the choice the whole game is built on: fight for the reward, or leave with
	-- what you're carrying (art §7 verbs: STEAL, ESCAPE).
	Notify:FireClient(player, {
		Text = "CAPTAIN BRONN",
		Sub = "STEAL HIS SWORD — OR ESCAPE WITH YOUR LOOT",
		Kind = "alarm",
	})
end

-- No one left in the hall long enough: walk home and heal fully. Stops the step-in,
-- hit, step-out pattern from whittling him down for free.
local function reset(f: Fight)
	dismissReinforcements()
	f.InFight = false
	f.Reinforced = false
	f.RotationIndex = 1
	table.clear(f.Engaged)
	local hum: Humanoid = f.Record.Humanoid
	hum.Health = hum.MaxHealth
end

local function idle(f: Fight, now: number)
	local record = f.Record
	local hum: Humanoid = record.Humanoid
	local root = record.Model.PrimaryPart :: BasePart
	local home: Vector3 = world.CaptainSpawn.Position

	if f.InFight and now - f.LastTargetAt >= TUNE.ResetDelay then
		reset(f)
	end

	if flatDistance(root.Position, home) > TUNE.HomeTolerance then
		record.State = "Return"
		hum:MoveTo(home)
		return
	end

	-- At home: watch the nearest player in range, from the vault too. He sees you.
	record.State = "Idle"
	local nearest, best = nil, TUNE.WatchRange
	for _, player in Players:GetPlayers() do
		local pRoot = livingRoot(player)
		if pRoot then
			local d = flatDistance(pRoot.Position, root.Position)
			if d < best then
				nearest, best = pRoot, d
			end
		end
	end
	if nearest then
		root.CFrame = facing(root.Position, nearest.Position)
	end
end

local function think(record, _dt: number)
	local f = fight
	if not f or f.Record ~= record or f.Busy then
		return
	end
	local root = record.Model.PrimaryPart :: BasePart?
	if not root or record.Humanoid.Health <= 0 then
		return
	end

	-- He only ever targets players inside his hall.
	local target: BasePart? = nil
	local best = math.huge
	for _, player in Players:GetPlayers() do
		local pRoot = livingRoot(player)
		if pRoot and inArena(pRoot.Position) then
			engage(f, player)
			local d = flatDistance(pRoot.Position, root.Position)
			if d < best then
				target, best = pRoot, d
			end
		end
	end

	local now = os.clock()
	if not target then
		idle(f, now)
		return
	end
	f.InFight = true
	f.LastTargetAt = now
	record.State = "Chase"

	local cfg = record.Config
	if now >= f.NextAttackAt then
		if best <= cfg.AttackRange then
			local name = cfg.Rotation[f.RotationIndex]
			f.RotationIndex = f.RotationIndex % #cfg.Rotation + 1
			task.spawn(performAttack, f, cfg.Attacks[name], target.Position)
			return
		end
		local ranged = cfg.RangedAttack and cfg.Attacks[cfg.RangedAttack]
		if ranged and best >= TUNE.ChargeMinRange and best <= ranged.Length then
			task.spawn(performAttack, f, ranged, target.Position)
			return
		end
	end
	record.Humanoid:MoveTo(target.Position)
end

-- ── EnemyService hooks ──────────────────────────────────────────
local function onDamaged(record, attacker: Player)
	local f = fight
	if not f or f.Record ~= record then
		return
	end
	-- Hitting him from the archway still counts as picking the fight.
	engage(f, attacker)

	local hum: Humanoid = record.Humanoid
	if not f.Reinforced and hum.Health > 0 and hum.Health <= hum.MaxHealth * TUNE.ReinforcementAtHealth then
		f.Reinforced = true
		dismissReinforcements()
		local guard = ctx.EnemyService.Spawn(
			TUNE.ReinforcementEnemy,
			world.CaptainReinforcementSpawn,
			{ Respawn = false }
		)
		if guard then
			table.insert(reinforcements, guard)
		end
		notifyEngaged(f, { Text = "BRONN CALLS A GUARD!", Kind = "alarm" })
	end
end

local function onKilled(record, killer: Player?)
	local f = fight
	if not f or f.Record ~= record then
		return
	end
	fight = nil
	for _, marker in f.Markers do
		marker:Destroy()
	end
	table.clear(f.Markers)
	setTelegraph(f, nil)

	if killer then
		ctx.Analytics.Log(killer, "CaptainKilled", 1, { weapon = weaponId(killer), run = runIndex(killer) })
		Notify:FireClient(killer, {
			Text = "CAPTAIN BRONN DEFEATED",
			Sub = "STEAL HIS SWORD",
			Kind = "milestone",
		})
	end

	task.delay(TUNE.RespawnDelay, CaptainService.Spawn)
end

local function onKilledPlayer(_record, player: Player, attackName: string)
	ctx.Analytics.Log(player, "CaptainDefeatedPlayer", 1, {
		attack = attackName,
		weapon = weaponId(player),
		run = runIndex(player),
	})
end

-- ── Public ──────────────────────────────────────────────────────
function CaptainService.Init(context, builtWorld)
	ctx = context
	world = builtWorld
	Notify = Net.Event("Notify")

	telegraphs = Instance.new("Folder")
	telegraphs.Name = "Telegraphs"
	telegraphs.Parent = workspace

	assert(EnemyConfig.Get(ENEMY_ID), "EnemyConfig is missing " .. ENEMY_ID)
end

function CaptainService.Spawn()
	if fight then
		return
	end
	-- A guard from Bronn's previous life must not carry into this one.
	dismissReinforcements()
	local record = ctx.EnemyService.Spawn(ENEMY_ID, world.CaptainSpawn, {
		Respawn = false, -- respawned here, on GameConfig.Captain.RespawnDelay
		SpawnCFrame = world.CaptainSpawn,
		Brain = think,
		OnDamaged = onDamaged,
		OnKilled = onKilled,
		OnKilledPlayer = onKilledPlayer,
	})
	if not record then
		return
	end

	local grip, sword, highlight, nameplate = dress(record)
	local f: Fight = {
		Record = record,
		Grip = grip,
		Sword = sword,
		Highlight = highlight,
		Nameplate = nameplate,
		Busy = false,
		InFight = false,
		RotationIndex = 1,
		NextAttackAt = 0,
		LastTargetAt = 0,
		Reinforced = false,
		Engaged = {},
		Markers = {},
	}
	fight = f

	refreshHealth(f)
	record.Humanoid.HealthChanged:Connect(function()
		refreshHealth(f)
	end)
end

return CaptainService
