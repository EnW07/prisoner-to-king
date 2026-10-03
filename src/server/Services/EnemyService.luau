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
		LastAttack = 0,
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
	EnemyAnimator.Swing(record)
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
