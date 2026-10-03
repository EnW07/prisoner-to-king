--!strict
-- EnemyService.lua
-- Blueprint §46: AI runs on a throttled tick, NOT every frame, and only for relevant NPCs.
-- Bodies are real R15 rigs built by RigFactory.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local EnemyConfig = require(game.ReplicatedStorage.Shared.Config.EnemyConfig)
local Net = require(game.ReplicatedStorage.Shared.Net)
local RigFactory = require(script.Parent.RigFactory)
local EnemyAnimator = require(script.Parent.EnemyAnimator)
local CollisionGroups = require(script.Parent.CollisionGroups)

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

	CollisionGroups.Init()
	RigFactory.Prewarm(EnemyConfig)
	EnemyAnimator.Init()

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
-- Real R15 rigs from RigFactory (playtest 4: the old part-built rigs had no limbs, so
-- nothing could animate and guards slid). The body is an implementation detail: every
-- stat still comes from EnemyConfig, unchanged.
local function buildRig(enemyId: string, cfg, cframe: CFrame): (Model, Humanoid)
	local model = RigFactory.Build(enemyId, cfg)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.MaxHealth = cfg.MaxHealth
	humanoid.Health = cfg.MaxHealth
	humanoid.WalkSpeed = cfg.MoveSpeed
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayName = cfg.DisplayName
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	RigFactory.PlaceOnFloor(model, cframe)
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

	-- Build and set up first; register as active LAST. A spawn that fails part-way must not
	-- leave a hittable, killable body with no AI behind it (playtest 5, Bronn).
	local model: Model
	local humanoid: Humanoid
	local ok, err = pcall(function()
		model, humanoid = buildRig(enemyId, cfg, cframe)
		model:SetAttribute("EnemyId", enemyId)
		CollisionGroups.TagEnemy(model) -- never pushes, or is pushed by, a player
		model.Parent = container
	end)
	if not ok then
		warn(("[Enemy] Could not build %s: %s"):format(enemyId, tostring(err)))
		return nil
	end

	local record = {
		Model = model,
		Humanoid = humanoid,
		Config = cfg,
		EnemyId = enemyId,
		State = "Patrol",
		Target = nil :: Player?,
		-- Attack cycle (BeginAttack). Attacking pauses Think; AttackToken cancels a cycle
		-- whose enemy died or was removed mid-swing.
		Attacking = false,
		AttackToken = 0,
		NextAttackAt = 0,
		PatrolA = opts.PatrolA,
		PatrolB = opts.PatrolB,
		PatrolTarget = opts.PatrolA,
		SpawnCFrame = opts.SpawnCFrame or cframe,
		Respawn = opts.Respawn == true,
		Options = opts,
	}

	local setupOk, setupErr = pcall(function()
		-- Server owns enemy physics. Otherwise Roblox may hand a nearby player network
		-- ownership, and that client could then move the enemy. It also keeps the
		-- locomotion velocity EnemyAnimator reads authoritative.
		local root = model.PrimaryPart
		if root then
			root:SetNetworkOwner(nil)
		end
		EnemyAnimator.Attach(record)
	end)
	if not setupOk then
		warn(("[Enemy] Could not set up %s; removing it: %s"):format(enemyId, tostring(setupErr)))
		EnemyAnimator.Detach(record)
		model:Destroy()
		return nil
	end

	active[model] = record
	return record
end

-- ── AI tick ─────────────────────────────────────────────────────
-- Flattened (XZ) vector from a to b.
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function livingRoot(player: Player): BasePart?
	local char = player.Character
	local pRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pHum = char and char:FindFirstChildOfClass("Humanoid")
	if pRoot and pHum and pHum.Health > 0 then
		return pRoot
	end
	return nil
end

-- Turn to face a point, level, without moving. Used only OUTSIDE an attack: once a windup
-- starts the enemy is committed and doesn't track.
local function face(root: BasePart, point: Vector3)
	local d = flat(point - root.Position)
	if d.Magnitude > 0.05 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + d)
	end
end

-- ── AI tick ─────────────────────────────────────────────────────
-- Playtest 5, item 1. The old Attack branch kept walking INTO the player while a timer
-- subtracted health: a damage-over-time field with legs. Now a fight has a rhythm:
--   Chase   close to the stand-off ring around the player, never into them
--   Hold    stop at StandoffDistance and face the player, stepping back if crowded
--   Windup  committed: no moving, no turning (that's what makes dodging possible)
--   Strike  one hit test, at one moment, against the committed facing
--   Recover a still, vulnerable pause: the player's punish window
-- Windup, strike and recover run on their own timers (BeginAttack), not on this tick.
function EnemyService.Think(record, _dt: number)
	local model, humanoid, cfg = record.Model, record.Humanoid, record.Config
	local root = model.PrimaryPart
	if not root or humanoid.Health <= 0 or record.Attacking then
		return
	end

	-- Closest living player.
	local best: Player? = nil
	local bestRoot: BasePart? = nil
	local bestDist = math.huge
	for _, player in Players:GetPlayers() do
		local pRoot = livingRoot(player)
		if pRoot then
			local d = flat(pRoot.Position - root.Position).Magnitude
			if d < bestDist then
				best, bestRoot, bestDist = player, pRoot, d
			end
		end
	end

	local leashed = (root.Position - record.SpawnCFrame.Position).Magnitude > GameConfig.Enemy.LeashDistance

	if best and bestRoot and bestDist <= cfg.AggroRange and not leashed then
		record.Target = best
		local standoff = cfg.StandoffDistance or cfg.AttackRange
		local away = flat(root.Position - bestRoot.Position)
		local awayDir = if away.Magnitude > 0.05 then away.Unit else -root.CFrame.LookVector

		if bestDist <= cfg.AttackRange and os.clock() >= record.NextAttackAt then
			EnemyService.BeginAttack(record, bestRoot)
		elseif bestDist > standoff then
			-- Chase to the stand-off ring, not to the player's position.
			record.State = "Chase"
			humanoid:MoveTo(bestRoot.Position + awayDir * standoff)
		else
			record.State = "Hold"
			if bestDist < standoff - GameConfig.Enemy.StandoffSlack then
				humanoid:MoveTo(bestRoot.Position + awayDir * standoff) -- crowded: step back
			else
				humanoid:MoveTo(root.Position) -- stop
				face(root, bestRoot.Position)
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

-- Is `pos` inside this enemy's strike area, measured from the facing it committed to?
local function inStrike(origin: CFrame, cfg, pos: Vector3): boolean
	local p = origin:PointToObjectSpace(pos)
	local E = GameConfig.Enemy
	return math.abs(p.X) <= E.StrikeWidth / 2
		and p.Z <= E.StrikeBackReach
		and p.Z >= -cfg.AttackRange
		and math.abs(p.Y) <= E.StrikeHeight
end

-- One full attack: committed windup → strike → recovery. All damage is decided here, on
-- the server; clients only see the replicated pose (EnemyAnimator).
function EnemyService.BeginAttack(record, targetRoot: BasePart)
	local cfg = record.Config
	local humanoid: Humanoid = record.Humanoid
	local root = record.Model.PrimaryPart :: BasePart
	local windup = cfg.WindupTime or 0
	local recovery = cfg.RecoveryTime or 0

	record.Attacking = true
	record.State = "Windup"
	record.AttackToken += 1
	local token = record.AttackToken
	record.NextAttackAt = os.clock() + cfg.AttackCooldown

	-- Commit: plant, face the player ONCE, and stop turning until recovery is over.
	humanoid:MoveTo(root.Position)
	humanoid.AutoRotate = false
	face(root, targetRoot.Position)
	local origin = root.CFrame
	EnemyAnimator.AttackPhase(record, "Windup", windup)

	local function stillOn(): boolean
		return record.AttackToken == token and record.State ~= "Dead" and record.Model.Parent ~= nil
	end

	task.delay(windup, function()
		if not stillOn() then
			return
		end
		-- Strike: one test, now, against the committed facing. Step out during the windup
		-- and it misses.
		record.State = "Strike"
		EnemyAnimator.AttackPhase(record, "Strike", 0)
		for _, player in Players:GetPlayers() do
			local pRoot = livingRoot(player)
			if pRoot and inStrike(origin, cfg, pRoot.Position) then
				EnemyService.DamagePlayer(record, player, cfg.Damage, cfg.AttackName or "ATTACK")
			end
		end

		-- Recover: stand still and take it.
		record.State = "Recover"
		EnemyAnimator.AttackPhase(record, "Recover", recovery)
		task.delay(recovery, function()
			if not stillOn() then
				return
			end
			humanoid.AutoRotate = true
			record.Attacking = false
			record.State = "Hold"
		end)
	end)
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
	EnemyAnimator.Detach(record)

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
		EnemyAnimator.Detach(record)
		model:Destroy()
	end
end

function EnemyService.ClearAll()
	for model in active do
		active[model] = nil
		model:Destroy()
	end
end

-- The folder every enemy model lives in. CombatService limits its swing query to it.
function EnemyService.GetContainer(): Folder
	return container
end

-- All living enemies, used by CombatService hit detection.
function EnemyService.GetActive()
	return active
end

return EnemyService
