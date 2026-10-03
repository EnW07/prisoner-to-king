--!strict
-- EnemyService.lua
-- Blueprint §46: AI runs on a throttled tick, NOT every frame, and only for relevant NPCs.
-- Rigs are built from Parts so the loop is playable before any custom art exists.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local EnemyConfig = require(game.ReplicatedStorage.Shared.Config.EnemyConfig)
local Palette = require(game.ReplicatedStorage.Shared.Config.Palette)
local Net = require(game.ReplicatedStorage.Shared.Net)

local EnemyService = {}
local ctx
local HitConfirm: RemoteEvent

local container: Folder
local active: { [Model]: any } = {}
local accumulator = 0

function EnemyService.Init(context)
	ctx = context
	HitConfirm = Net.Event("HitConfirm")

	container = Instance.new("Folder")
	container.Name = "Enemies"
	container.Parent = workspace

	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < GameConfig.Enemy.ThinkInterval then
			return
		end
		local step = accumulator
		accumulator = 0
		for model, record in active do
			if model.Parent and record.State ~= "Dead" then
				-- Bosses bring their own brain (e.g. CaptainService); everyone else uses Think.
				local brain = record.Options.Brain
				if brain then
					brain(record, step)
				else
					EnemyService.Think(record, step)
				end
			end
		end
	end)
end

-- ── Rig construction ────────────────────────────────────────────
-- A welded, massless, non-colliding piece of costume. Swings still hit it (it's in the
-- enemy model), which only makes a silhouette easier to hit, never harder.
local function costume(
	model: Model,
	root: BasePart,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material
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
	p.Parent = model
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
	return p
end

-- Silhouettes (VISUAL_OVERHAUL_PLAN Phase 3, art §4/§8: enemy readability first). Each
-- enemy type must be recognisable as a black shape. Captain Bronn is dressed separately
-- by CaptainService. Shapes are rig geometry; colours are palette tokens.
-- Move a part that is already welded to root, then weld it again at its new offset, so the
-- result never depends on when a WeldConstraint captures its offset.
local function moveWelded(root: BasePart, p: BasePart, cf: CFrame)
	for _, w in root:GetChildren() do
		if w:IsA("WeldConstraint") and w.Part1 == p then
			w:Destroy()
		end
	end
	p.CFrame = cf
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = root
end

local function dressSilhouette(
	model: Model,
	root: BasePart,
	head: BasePart,
	blade: BasePart,
	cfg,
	cframe: CFrame
)
	local body: Vector3 = cfg.BodySize
	if cfg.Silhouette == "Slouch" then
		-- Hunched: head dropped forward, a floppy cap, a paunch, the sword hanging limp.
		moveWelded(root, head, cframe * CFrame.new(0, body.Y / 2 + 0.5, -0.5))
		costume(
			model,
			root,
			"Cap",
			Vector3.new(1.7, 0.45, 1.7),
			head.CFrame * CFrame.new(0, 0.8, 0.2) * CFrame.Angles(math.rad(-15), 0, math.rad(10)),
			Palette.stone,
			Enum.Material.Fabric
		)
		costume(
			model,
			root,
			"Paunch",
			Vector3.new(1.7, 1.4, 0.6),
			cframe * CFrame.new(0, -0.3, -0.7),
			cfg.BodyColor,
			Enum.Material.SmoothPlastic
		)
		moveWelded(root, blade, cframe * CFrame.new(1.3, -0.9, -0.2) * CFrame.Angles(0, 0, math.rad(25)))
	elseif cfg.Silhouette == "Armored" then
		-- Upright and armoured: a helm with a nasal guard, pauldrons, a `bleed` tabard
		-- (danger, art §3) and a spear that stands well above the head.
		costume(
			model,
			root,
			"Helm",
			head.Size + Vector3.new(0.4, 0.3, 0.4),
			head.CFrame * CFrame.new(0, 0.2, 0),
			Palette.stone,
			Enum.Material.Metal
		)
		costume(
			model,
			root,
			"Nasal",
			Vector3.new(0.25, 0.9, 0.2),
			head.CFrame * CFrame.new(0, -0.1, -0.85),
			Palette.stone,
			Enum.Material.Metal
		)
		for _, side in { -1, 1 } do
			costume(
				model,
				root,
				"Pauldron",
				Vector3.new(0.9, 0.6, 1.4),
				cframe * CFrame.new(side * (body.X / 2 + 0.3), body.Y / 2 - 0.3, 0),
				Palette.stone,
				Enum.Material.Metal
			)
		end
		costume(
			model,
			root,
			"Tabard",
			Vector3.new(body.X - 0.4, body.Y - 0.8, 0.15),
			cframe * CFrame.new(0, -0.2, -body.Z / 2 - 0.08),
			Palette.bleed,
			Enum.Material.Fabric
		)
		blade.Size = Vector3.new(0.25, 7.5, 0.25) -- the shaft: blade becomes a spear
		blade.Color = Palette.pitch
		moveWelded(root, blade, cframe * CFrame.new(1.4, 1.2, -0.4))
		costume(
			model,
			root,
			"Spearhead",
			Vector3.new(0.5, 1.2, 0.2),
			blade.CFrame * CFrame.new(0, 4.3, 0),
			Palette.stone,
			Enum.Material.Metal
		)
	end
end

-- A minimal Humanoid rig: HumanoidRootPart + Head is enough for Humanoid:MoveTo.
-- Replace this whole function with a real rig later; nothing else depends on its internals.
local function buildRig(cfg, cframe: CFrame): (Model, Humanoid)
	local model = Instance.new("Model")
	model.Name = cfg.DisplayName

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = cfg.BodySize
	root.Color = cfg.BodyColor
	root.Material = Enum.Material.SmoothPlastic
	root.CFrame = cframe
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.4, 1.4, 1.4)
	head.Color = Color3.fromRGB(215, 190, 160)
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = false
	head.CFrame = cframe * CFrame.new(0, cfg.BodySize.Y / 2 + 0.8, 0)
	head.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = root

	-- A stubby weapon so the silhouette reads as "armed guard" (§36 strong silhouettes).
	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(0.3, 2.6, 0.3)
	blade.Color = Color3.fromRGB(170, 170, 180)
	blade.Material = Enum.Material.Metal
	blade.CanCollide = false
	blade.CFrame = cframe * CFrame.new(1.4, 0, -0.4)
	blade.Parent = model
	local bweld = Instance.new("WeldConstraint")
	bweld.Part0 = root
	bweld.Part1 = blade
	bweld.Parent = root

	dressSilhouette(model, root, head, blade, cfg, cframe)

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = cfg.MaxHealth
	humanoid.Health = cfg.MaxHealth
	humanoid.WalkSpeed = cfg.MoveSpeed
	humanoid.HipHeight = 0
	humanoid.BreakJointsOnDeath = false
	-- CRITICAL for part-built rigs: a Humanoid with no Neck Motor6D will kill itself
	-- within a few seconds unless RequiresNeck is disabled.
	humanoid.RequiresNeck = false
	humanoid.DisplayName = cfg.DisplayName
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.Parent = model

	model.PrimaryPart = root
	return model, humanoid
end

-- ── Spawning ────────────────────────────────────────────────────
export type SpawnOptions = {
	PatrolA: Vector3?,
	PatrolB: Vector3?,
	Respawn: boolean?,
	SpawnCFrame: CFrame?,
	-- Boss hooks. Brain replaces Think; the others are notifications after the fact.
	Brain: ((record: any, dt: number) -> ())?,
	OnDamaged: ((record: any, attacker: Player) -> ())?,
	OnKilled: ((record: any, killer: Player?) -> ())?,
	OnKilledPlayer: ((record: any, player: Player, attackName: string) -> ())?,
}

function EnemyService.Spawn(enemyId: string, cframe: CFrame, options: SpawnOptions?)
	local cfg = EnemyConfig.Get(enemyId)
	if not cfg then
		warn("[Enemy] Unknown enemy id: " .. enemyId)
		return
	end
	local opts = options or {}

	local model, humanoid = buildRig(cfg, cframe)
	model:SetAttribute("EnemyId", enemyId)
	model.Parent = container

	local record = {
		Model = model,
		Humanoid = humanoid,
		Config = cfg,
		EnemyId = enemyId,
		State = "Patrol",
		Target = nil :: Player?,
		LastAttack = 0,
		PatrolA = opts.PatrolA,
		PatrolB = opts.PatrolB,
		PatrolTarget = opts.PatrolA,
		SpawnCFrame = opts.SpawnCFrame or cframe,
		Respawn = opts.Respawn == true,
		Options = opts,
	}
	active[model] = record
	return record
end

-- ── AI tick ─────────────────────────────────────────────────────
function EnemyService.Think(record, _dt: number)
	local model, humanoid, cfg = record.Model, record.Humanoid, record.Config
	local root = model.PrimaryPart
	if not root or humanoid.Health <= 0 then
		return
	end

	-- Find the closest living player inside aggro range.
	local best, bestDist = nil, math.huge
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local pRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local pHum = char and char:FindFirstChildOfClass("Humanoid")
		if pRoot and pHum and pHum.Health > 0 then
			local d = (pRoot.Position - root.Position).Magnitude
			if d < bestDist then
				best, bestDist = player, d
			end
		end
	end

	local leashed = (root.Position - record.SpawnCFrame.Position).Magnitude > GameConfig.Enemy.LeashDistance

	if best and bestDist <= cfg.AggroRange and not leashed then
		record.Target = best
		if bestDist <= cfg.AttackRange then
			record.State = "Attack"
			local now = os.clock()
			if now - record.LastAttack >= cfg.AttackCooldown then
				record.LastAttack = now
				EnemyService.AttackPlayer(record, best)
			end
			-- Face the target while attacking.
			local pRoot = best.Character and best.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if pRoot then
				humanoid:MoveTo(pRoot.Position)
			end
		else
			record.State = "Chase"
			local pRoot = best.Character and best.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if pRoot then
				humanoid:MoveTo(pRoot.Position)
			end
		end
		return
	end

	-- No target: patrol, or walk home.
	record.Target = nil
	if leashed then
		record.State = "Return"
		humanoid:MoveTo(record.SpawnCFrame.Position)
	elseif record.PatrolA and record.PatrolB then
		record.State = "Patrol"
		local target = record.PatrolTarget or record.PatrolA
		if (root.Position - target).Magnitude < 6 then
			record.PatrolTarget = if target == record.PatrolA then record.PatrolB else record.PatrolA
			target = record.PatrolTarget
		end
		humanoid:MoveTo(target)
	else
		record.State = "Idle"
	end
end

function EnemyService.AttackPlayer(record, player: Player)
	EnemyService.DamagePlayer(record, player, record.Config.Damage, "ATTACK")
end

-- The one path by which an enemy hurts a player. Records which attack landed so the
-- CAPTURED screen can say exactly what killed you (§12: telegraphs must be learnable).
function EnemyService.DamagePlayer(record, player: Player, amount: number, attackName: string)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	-- Recorded BEFORE the health change: Humanoid.Died reads it synchronously.
	ctx.RunState.RecordHit(player, record.Config.DisplayName, attackName)
	hum.Health = math.max(0, hum.Health - amount)
	HitConfirm:FireClient(player, {
		Kind = "taken",
		Damage = amount,
		Position = (record.Model.PrimaryPart :: BasePart).Position,
		Source = attackName,
	})
	if hum.Health <= 0 and record.Options.OnKilledPlayer then
		record.Options.OnKilledPlayer(record, player, attackName)
	end
end

-- ── Damage & death ──────────────────────────────────────────────
function EnemyService.GetRecord(model: Model)
	return active[model]
end

-- Called ONLY by CombatService after full server-side validation.
function EnemyService.ApplyDamage(model: Model, amount: number, attacker: Player)
	local record = active[model]
	if not record or record.State == "Dead" then
		return false
	end

	local humanoid = record.Humanoid
	if humanoid.Health <= 0 then
		return false
	end

	humanoid.Health = math.max(0, humanoid.Health - amount)

	local root = record.Model.PrimaryPart :: BasePart
	HitConfirm:FireAllClients({
		Kind = "dealt",
		Damage = amount,
		Position = root.Position,
		Killed = humanoid.Health <= 0,
		Attacker = attacker.UserId,
	})

	ctx.Analytics.Log(attacker, "FirstGuardHit", 1, { enemy = record.EnemyId })

	if record.Options.OnDamaged then
		record.Options.OnDamaged(record, attacker)
	end

	if humanoid.Health <= 0 then
		EnemyService.Kill(record, attacker)
	end
	return true
end

function EnemyService.Kill(record, killer: Player?)
	if record.State == "Dead" then
		return
	end
	record.State = "Dead"

	local root = record.Model.PrimaryPart :: BasePart
	local position = root.Position

	if killer then
		ctx.Analytics.Log(killer, "FirstGuardKilled", 1, { enemy = record.EnemyId })
		ctx.Analytics.Log(killer, "EnemyKilled", 1, { enemy = record.EnemyId })
		ctx.LootService.DropForEnemy(record.EnemyId, position, killer)

		local run = ctx.RunState.Get(killer)
		if run and run.Objective == "STEAL THE KEY" and not run.HasKey then
			-- Objective advances once the key actually drops; LootService handles the pickup.
		end
	else
		ctx.LootService.DropForEnemy(record.EnemyId, position, nil)
	end

	-- Simple graybox death: fall over, then despawn.
	record.Humanoid.PlatformStand = true
	root.CanCollide = false
	root.AssemblyLinearVelocity = Vector3.new(0, 12, 0)

	local model = record.Model
	active[model] = nil

	if record.Options.OnKilled then
		record.Options.OnKilled(record, killer)
	end

	task.delay(GameConfig.Enemy.CorpseDespawn, function()
		if model.Parent then
			model:Destroy()
		end
	end)

	if record.Respawn then
		task.delay(GameConfig.Enemy.RespawnDelay, function()
			EnemyService.Spawn(record.EnemyId, record.SpawnCFrame, record.Options)
		end)
	end
end

-- Remove a living enemy without a kill: no loot, no analytics, no respawn. For enemies
-- whose reason to exist has gone (e.g. Bronn's reinforcement after he resets).
function EnemyService.Despawn(record)
	local model = record.Model
	if active[model] then
		active[model] = nil
		record.State = "Dead"
		model:Destroy()
	end
end

function EnemyService.ClearAll()
	for model in active do
		active[model] = nil
		model:Destroy()
	end
end

-- All living enemies, used by CombatService hit detection.
function EnemyService.GetActive()
	return active
end

return EnemyService
