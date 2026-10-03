--!strict
-- EnemyService.lua
-- Blueprint §46: AI runs on a throttled tick, NOT every frame, and only for relevant NPCs.
-- Bodies are real R15 rigs built by RigFactory. (MASTER_BUILD_SPEC Section F.)
--
-- ONE BRAIN, MANY IDENTITIES. Every non-boss enemy runs Think. What makes an archer an
-- archer is EnemyConfig, read here as data (§12 rule: one readable identity each):
--   • melee (default)       chase to a stand-off ring, committed windup, one box strike
--   • PreferredRange        ranged: hold distance, retreat when closed on, fire a projectile
--   • Static                never moves; fires on its cooldown (FixedAim: along its spawn
--                           facing, whoever is there)
--   • Leap                  the strike is a leap at the target; damage at landing
--   • Telegraph             the strike is an area slam painted on the floor
--   • Shield                frontal hits are blocked unless they break guard
--   • Strafe                weaves while chasing
-- Adding an enemy is config plus, at most, a silhouette in RigFactory. Combat logic never
-- special-cases an enemy id.
--
-- AWARENESS (F8): a guard that sees you STOPS, snaps its head up, shows "!", then engages
-- after AlertTime. Sight needs line of sight to the world geometry (a locked door hides
-- you). Being hit skips most of that: a short alert, then the fight.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local EnemyConfig = require(game.ReplicatedStorage.Shared.Config.EnemyConfig)
local Palette = require(game.ReplicatedStorage.Shared.Config.Palette)
local Net = require(game.ReplicatedStorage.Shared.Net)
local RigFactory = require(script.Parent.RigFactory)
local EnemyAnimator = require(script.Parent.EnemyAnimator)
local CollisionGroups = require(script.Parent.CollisionGroups)
local ProjectileService = require(script.Parent.ProjectileService)
local Ragdoll = require(game.ReplicatedStorage.Shared.Anim.Ragdoll)

local EnemyService = {}
local ctx
local HitConfirm: RemoteEvent
local Notify: RemoteEvent

local ENEMY = GameConfig.Enemy
local container: Folder
local telegraphs: Folder
local active: { [Model]: any } = {}
local accumulator = 0

function EnemyService.Init(context)
	ctx = context
	HitConfirm = Net.Event("HitConfirm")
	Notify = Net.Event("Notify")

	container = Instance.new("Folder")
	container.Name = "Enemies"
	container.Parent = workspace
	telegraphs = Instance.new("Folder")
	telegraphs.Name = "EnemyTelegraphs"
	telegraphs.Parent = workspace

	CollisionGroups.Init()
	RigFactory.Prewarm(EnemyConfig)
	EnemyAnimator.Init()
	ProjectileService.Init(ctx, { container, telegraphs })

	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < ENEMY.ThinkInterval then
			return
		end
		local step = accumulator
		accumulator = 0
		local now = os.clock()
		for model, record in active do
			if model.Parent and record.State ~= "Dead" then
				-- Poise refills after a quiet spell (E7).
				local cfg = record.Config
				if
					cfg.Poise
					and record.Poise < cfg.Poise
					and now - record.LastHitAt >= GameConfig.Poise.RegenDelay
				then
					record.Poise = math.min(cfg.Poise, record.Poise + (cfg.PoiseRegen or 0) * step)
				end
				-- A staggered enemy does nothing: that's the vulnerable window.
				if now < record.StaggeredUntil then
					continue
				end
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
	RigFactory.Vary(model, cfg) -- F7: no two guards quite alike
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.MaxHealth = cfg.MaxHealth
	humanoid.Health = cfg.MaxHealth
	humanoid.WalkSpeed = if cfg.Static then 0 else cfg.MoveSpeed
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayName = cfg.DisplayName
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	RigFactory.PlaceOnFloor(model, cframe)
	return model, humanoid
end

-- The "!" over the head during an alert (F8). Server-made so every client sees the same
-- moment; it is one TextLabel, toggled, never rebuilt.
local function buildAlertMark(model: Model): BillboardGui?
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "AlertMark"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(ENEMY.AlertMarkPx, ENEMY.AlertMarkPx)
	gui.StudsOffset = Vector3.new(0, head.Size.Y + 1.6, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "!"
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Palette.bleed
	label.TextStrokeColor3 = Palette.pitch
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = model
	return gui
end

-- ── Spawning ────────────────────────────────────────────────────
export type SpawnOptions = {
	PatrolA: Vector3?,
	PatrolB: Vector3?,
	Respawn: boolean?,
	SpawnCFrame: CFrame?,
	IdlePose: string?, -- an AnimationConfig pose held while idle (leaning, warming hands)
	-- Boss hooks. Brain replaces Think; the others are notifications after the fact.
	Brain: ((record: any, dt: number) -> ())?,
	OnDamaged: ((record: any, attacker: Player) -> ())?,
	OnKilled: ((record: any, killer: Player?) -> ())?,
	OnKilledPlayer: ((record: any, player: Player, attackName: string) -> ())?,
	OnStaggered: ((record: any) -> ())?,
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
		LostTargetAt = -math.huge,
		-- Awareness (F8).
		AlertUntil = 0,
		AlertMark = nil :: BillboardGui?,
		-- Attack cycle (BeginAttack). Attacking pauses Think; AttackToken cancels a cycle
		-- whose enemy died, staggered or was removed mid-swing.
		Attacking = false,
		AttackToken = 0,
		NextAttackAt = 0,
		-- Poise (E7): drained by hits, refilled by time; at zero, a stagger.
		Poise = cfg.Poise or 0,
		LastHitAt = 0,
		StaggeredUntil = 0,
		PatrolA = opts.PatrolA,
		PatrolB = opts.PatrolB,
		PatrolTarget = opts.PatrolA,
		IdlePose = opts.IdlePose,
		IdlePosed = false,
		SpawnCFrame = opts.SpawnCFrame or cframe,
		Seed = math.random() * 100, -- per-enemy phase for strafing
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
		record.AlertMark = buildAlertMark(model)
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

-- A pack: `count` of the same enemy around a point (hounds, F4). Returns the records.
function EnemyService.SpawnPack(enemyId: string, cframe: CFrame, count: number, options: SpawnOptions?)
	local records = {}
	local spread = ENEMY.PackSpread
	for i = 1, count do
		local angle = (i - 1) / count * 2 * math.pi
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * spread
		local record = EnemyService.Spawn(enemyId, cframe + offset, options)
		if record then
			table.insert(records, record)
		end
	end
	return records
end

-- ── Helpers ─────────────────────────────────────────────────────
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

-- Can the enemy see this point? Only world geometry blocks sight, so a closed door hides
-- you and another guard does not.
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Include
local function canSee(record, point: Vector3): boolean
	local world = ctx.World and ctx.World.Folder
	if not world then
		return true
	end
	local head = record.Model:FindFirstChild("Head") or record.Model.PrimaryPart
	if not head or not head:IsA("BasePart") then
		return true
	end
	sightParams.FilterDescendantsInstances = { world }
	local from = head.Position
	local to = point + Vector3.new(0, 1, 0)
	local hit = workspace:Raycast(from, to - from, sightParams)
	return hit == nil
end

local function setAlertMark(record, on: boolean)
	local mark = record.AlertMark
	if mark and mark.Parent then
		mark.Enabled = on
	end
end

-- The alert moment (F8): plant, face, head snap and "!", then engage after `time`.
local function startAlert(record, targetRoot: BasePart, time: number)
	local root = record.Model.PrimaryPart :: BasePart
	local now = os.clock()
	record.State = "Alert"
	record.AlertUntil = now + time
	if not record.Config.Static then
		record.Humanoid:MoveTo(root.Position)
	end
	if not record.Config.FixedAim then
		face(root, targetRoot.Position)
	end
	EnemyAnimator.PlayAction(record, "Alert")
	setAlertMark(record, true)
	-- The sound hook, for anyone close enough to hear it.
	for _, player in Players:GetPlayers() do
		local pRoot = livingRoot(player)
		if
			pRoot
			and (pRoot.Position - root.Position).Magnitude
				<= record.Config.AggroRange * ENEMY.AlertHearFactor
		then
			Notify:FireClient(player, { Text = "", Kind = "enemyAlert" })
		end
	end
	task.delay(time, function()
		setAlertMark(record, false)
	end)
end

-- Hold or release an idle posture (F7: some guards lean, some warm their hands).
local function setIdlePose(record, on: boolean)
	if not record.IdlePose or record.IdlePosed == on then
		return
	end
	record.IdlePosed = on
	EnemyAnimator.SetPose(record, if on then record.IdlePose else nil)
end

-- ── AI tick ─────────────────────────────────────────────────────
-- Playtest 5, item 1. The old Attack branch kept walking INTO the player while a timer
-- subtracted health: a damage-over-time field with legs. Now a fight has a rhythm:
--   Alert   notice: stop, face, "!" (F8)
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
	local now = os.clock()

	-- Target: keep the current one while it stays in chase range; otherwise the closest
	-- living player in aggro range that can be seen.
	local target: Player? = record.Target
	local targetRoot: BasePart? = nil
	local dist = math.huge
	if target then
		targetRoot = livingRoot(target)
		if targetRoot then
			dist = flat(targetRoot.Position - root.Position).Magnitude
			if dist > cfg.AggroRange * ENEMY.ChaseRangeFactor then
				targetRoot = nil
			end
		end
		if not targetRoot then
			target = nil
			record.Target = nil
			record.LostTargetAt = now
		end
	end
	if not target then
		local best = math.huge
		for _, player in Players:GetPlayers() do
			local pRoot = livingRoot(player)
			if pRoot then
				local d = flat(pRoot.Position - root.Position).Magnitude
				if d <= cfg.AggroRange and d < best and canSee(record, pRoot.Position) then
					target, targetRoot, best = player, pRoot, d
				end
			end
		end
		dist = best
		if target then
			record.Target = target
			setIdlePose(record, false)
			-- Notice first. A guard re-finding you soon after losing you skips the surprise.
			if now - record.LostTargetAt > ENEMY.AlertCooldown then
				startAlert(record, targetRoot :: BasePart, ENEMY.AlertTime)
				return
			end
		end
	end

	local leashed = flat(root.Position - record.SpawnCFrame.Position).Magnitude > ENEMY.LeashDistance

	if target and targetRoot and not leashed then
		if now < record.AlertUntil then
			if not cfg.FixedAim then
				face(root, targetRoot.Position)
			end
			return
		end
		local ready = now >= record.NextAttackAt
		local away = flat(root.Position - targetRoot.Position)
		local awayDir = if away.Magnitude > 0.05 then away.Unit else -root.CFrame.LookVector

		-- STATIC (F5): a fixed emplacement. Fires on its interval at whoever is in range.
		if cfg.Static then
			record.State = "Hold"
			if not cfg.FixedAim then
				face(root, targetRoot.Position)
			end
			if ready and dist <= cfg.AttackRange then
				EnemyService.BeginAttack(record, targetRoot)
			end
			return
		end

		-- RANGED (F2): hold the preferred distance, back off when closed on, and shoot.
		if cfg.PreferredRange then
			if dist < cfg.RetreatRange then
				record.State = "Retreat"
				humanoid:MoveTo(root.Position + awayDir * cfg.RetreatStep)
			elseif dist > cfg.PreferredRange then
				record.State = "Chase"
				humanoid:MoveTo(targetRoot.Position + awayDir * cfg.PreferredRange)
			else
				record.State = "Hold"
				humanoid:MoveTo(root.Position)
				face(root, targetRoot.Position)
			end
			if ready and dist <= cfg.AttackRange and record.State ~= "Retreat" then
				EnemyService.BeginAttack(record, targetRoot)
			end
			return
		end

		-- MELEE, with the optional leap (F4) and strafe.
		local standoff = cfg.StandoffDistance or cfg.AttackRange
		local leap = cfg.Leap
		if ready and leap and dist <= leap.Range and dist >= leap.MinRange then
			EnemyService.BeginAttack(record, targetRoot)
		elseif ready and dist <= cfg.AttackRange then
			EnemyService.BeginAttack(record, targetRoot)
		elseif dist > standoff then
			-- Chase to the stand-off ring, not to the player's position. A strafing enemy
			-- weaves across the line of approach: erratic, hard to time (F4).
			record.State = "Chase"
			local goal = targetRoot.Position + awayDir * standoff
			if cfg.Strafe then
				local side = Vector3.new(-awayDir.Z, 0, awayDir.X)
				goal += side * math.sin(now * ENEMY.StrafeSpeed + record.Seed) * cfg.Strafe
			end
			humanoid:MoveTo(goal)
		else
			record.State = "Hold"
			if dist < standoff - ENEMY.StandoffSlack then
				humanoid:MoveTo(targetRoot.Position + awayDir * standoff) -- crowded: step back
			else
				humanoid:MoveTo(root.Position) -- stop
				face(root, targetRoot.Position)
			end
		end
		return
	end

	-- No target: patrol, idle in a posture, or walk home.
	if cfg.Static then
		record.State = "Idle"
		return
	end
	if leashed then
		record.State = "Return"
		humanoid:MoveTo(record.SpawnCFrame.Position)
	elseif record.PatrolA and record.PatrolB then
		record.State = "Patrol"
		local patrolTarget = record.PatrolTarget or record.PatrolA
		if (root.Position - patrolTarget).Magnitude < 6 then
			record.PatrolTarget = if patrolTarget == record.PatrolA then record.PatrolB else record.PatrolA
			patrolTarget = record.PatrolTarget
		end
		humanoid:MoveTo(patrolTarget)
	else
		record.State = "Idle"
		humanoid:MoveTo(root.Position)
		setIdlePose(record, true)
	end
end

-- Is `pos` inside this enemy's strike area, measured from the facing it committed to?
local function inStrike(origin: CFrame, cfg, pos: Vector3): boolean
	local p = origin:PointToObjectSpace(pos)
	return math.abs(p.X) <= ENEMY.StrikeWidth / 2
		and p.Z <= ENEMY.StrikeBackReach
		and p.Z >= -cfg.AttackRange
		and math.abs(p.Y) <= ENEMY.StrikeHeight
end

-- An area attack's floor marker (F6): the exact circle the server will test, painted at
-- the enemy's feet and filling in over the windup. Same idea as Bronn's telegraphs.
local function makeAreaMarker(record, origin: CFrame, radius: number, windup: number): BasePart
	local root = record.Model.PrimaryPart :: BasePart
	local drop = (record.Humanoid :: Humanoid).HipHeight + root.Size.Y / 2
	local p = Instance.new("Part")
	p.Name = "Telegraph"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.Neon
	p.Color = Palette.bleed
	p.Transparency = 0.85
	p.Size = Vector3.new(0.1, radius * 2, radius * 2)
	p.CFrame = origin * CFrame.new(0, -drop + 0.08, 0) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent = telegraphs
	TweenService:Create(p, TweenInfo.new(windup, Enum.EasingStyle.Linear), {
		Transparency = GameConfig.Captain.TelegraphTransparency,
	}):Play()
	return p
end

-- One full attack: committed windup → strike → recovery. All damage is decided here, on
-- the server; clients only see the replicated pose (EnemyAnimator). What the strike IS
-- comes from config: a box in front, a projectile, a leap, or an area slam.
function EnemyService.BeginAttack(record, targetRoot: BasePart)
	local cfg = record.Config
	local humanoid: Humanoid = record.Humanoid
	local root = record.Model.PrimaryPart :: BasePart
	-- Timing varies a little per attack (F7), so the player reads the animation rather than
	-- memorising a stopwatch.
	local jitter = 1 + (math.random() * 2 - 1) * ENEMY.TimingJitter
	local windup = (cfg.WindupTime or 0) * jitter
	local recovery = cfg.RecoveryTime or 0

	record.Attacking = true
	record.State = "Windup"
	record.AttackToken += 1
	local token = record.AttackToken
	record.NextAttackAt = os.clock() + cfg.AttackCooldown * jitter

	-- Commit: plant, face the player ONCE, and stop turning until recovery is over.
	-- A fixed-aim emplacement keeps its spawn facing instead.
	if not cfg.Static then
		humanoid:MoveTo(root.Position)
	end
	humanoid.AutoRotate = false
	if not cfg.FixedAim then
		face(root, targetRoot.Position)
	end
	local origin = root.CFrame
	local marker: BasePart? = nil
	if cfg.Telegraph then
		marker = makeAreaMarker(record, origin, cfg.Telegraph.Radius, windup)
	end
	EnemyAnimator.AttackPhase(record, "Windup", windup)

	local function stillOn(): boolean
		return record.AttackToken == token and record.State ~= "Dead" and record.Model.Parent ~= nil
	end
	local function finish()
		if marker then
			marker:Destroy()
			marker = nil
		end
	end
	local attackName = cfg.AttackName or "ATTACK"

	task.delay(windup, function()
		if not stillOn() then
			finish()
			return
		end
		record.State = "Strike"
		EnemyAnimator.AttackPhase(record, "Strike", 0)

		if cfg.Projectile then
			-- A visible, dodgeable shot along the committed facing (F2, F5).
			ProjectileService.Fire(record, origin, cfg.Projectile, cfg.Damage, attackName)
		elseif cfg.Leap then
			-- Off the ground toward the target; the bite lands where the leap does (F4).
			local leap = cfg.Leap
			local aim = flat(targetRoot.Position - root.Position)
			local dir = if aim.Magnitude > 0.05 then aim.Unit else origin.LookVector
			root.AssemblyLinearVelocity = dir * leap.Speed + Vector3.new(0, leap.Lift, 0)
			task.delay(leap.AirTime, function()
				if not stillOn() then
					return
				end
				for _, player in Players:GetPlayers() do
					local pRoot = livingRoot(player)
					if pRoot and flat(pRoot.Position - root.Position).Magnitude <= cfg.AttackRange then
						EnemyService.DamagePlayer(record, player, cfg.Damage, attackName)
					end
				end
			end)
		elseif cfg.Telegraph then
			-- The painted circle, exactly (F6).
			if marker then
				marker.Transparency = 0
			end
			local radius = cfg.Telegraph.Radius
			for _, player in Players:GetPlayers() do
				local pRoot = livingRoot(player)
				if pRoot and flat(pRoot.Position - origin.Position).Magnitude <= radius then
					EnemyService.DamagePlayer(record, player, cfg.Damage, attackName)
				end
			end
			task.delay(GameConfig.Captain.ImpactPause, finish)
		else
			-- Strike: one test, now, against the committed facing. Step out during the
			-- windup and it misses.
			for _, player in Players:GetPlayers() do
				local pRoot = livingRoot(player)
				if pRoot and inStrike(origin, cfg, pRoot.Position) then
					EnemyService.DamagePlayer(record, player, cfg.Damage, attackName)
				end
			end
		end

		-- Recover: stand still and take it.
		record.State = "Recover"
		EnemyAnimator.AttackPhase(record, "Recover", recovery)
		task.delay(recovery, function()
			if not stillOn() then
				return
			end
			humanoid.AutoRotate = not cfg.Static
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
	-- Inside a dash's invincibility window (server-granted, E1): no damage, and the client
	-- is told, because reading the windup and dodging through it deserves a reward.
	if ctx.Combat.IsInvulnerable(player) then
		HitConfirm:FireClient(player, {
			Kind = "dodged",
			Position = (record.Model.PrimaryPart :: BasePart).Position,
			Source = attackName,
		})
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

-- Shove an enemy away from `from`. The server owns enemy physics, so an impulse on the
-- root is authoritative; the humanoid damps it quickly, which is the point: a shove, not
-- a launch. Enemies never collide with players, so this can't push anyone around.
local function knockback(record, from: Vector3, impulse: number)
	local root = record.Model.PrimaryPart :: BasePart?
	if not root or impulse <= 0 or record.Config.Static then
		return
	end
	local away = flat(root.Position - from)
	local dir = if away.Magnitude > 0.05 then away.Unit else root.CFrame.LookVector * -1
	root:ApplyImpulse((dir + Vector3.new(0, 0.25, 0)) * impulse * root.AssemblyMass)
end

-- Poise broken (E7): the current attack is cut, the enemy can't act for StaggerDuration,
-- and poise refills so a stagger can't chain into another. Visible: the Stagger move.
function EnemyService.Stagger(record, attacker: Player?)
	local cfg = record.Config
	local humanoid: Humanoid = record.Humanoid
	local root = record.Model.PrimaryPart :: BasePart?
	if record.State == "Dead" or humanoid.Health <= 0 or not root then
		return
	end
	local duration = cfg.StaggerDuration or 1
	local now = os.clock()
	record.StaggeredUntil = now + duration
	record.Poise = cfg.Poise or 0
	-- Cut whatever attack was in flight: its delayed strike checks the token.
	record.AttackToken += 1
	record.Attacking = false
	record.State = "Stagger"
	humanoid.AutoRotate = not cfg.Static
	if not cfg.Static then
		humanoid:MoveTo(root.Position)
	end

	EnemyAnimator.Interrupt(record) -- glow off, attack pose released
	local hitShare = GameConfig.Poise.StaggerHitShare
	EnemyAnimator.PlayAction(record, "Stagger", {
		Strike = duration * hitShare,
		Recover = duration * (1 - hitShare),
	})
	if record.Options.OnStaggered then
		record.Options.OnStaggered(record)
	end
	if attacker then
		ctx.Analytics.Log(attacker, "EnemyStaggered", 1, { enemy = record.EnemyId })
	end
	task.delay(duration, function()
		if active[record.Model] == record and record.State == "Stagger" then
			record.State = "Hold"
		end
	end)
end

export type HitInfo = {
	Contact: Vector3?, -- where the blow landed, for sparks and numbers (E8)
	Knockback: number?, -- impulse per unit mass; finishers and hammers
	Finisher: boolean?,
	Heavy: boolean?, -- a heavy attack (E2): the only thing that moves a brute's poise
	GuardBreak: boolean?, -- breaks a shield guard's block (heavy attacks, axes)
	PoiseDamage: number?, -- defaults to the damage dealt
}

-- Is the attacker in front of the enemy, inside its shield arc?
local function frontal(record, from: Vector3, arc: number): boolean
	local root = record.Model.PrimaryPart :: BasePart
	local toAttacker = flat(from - root.Position)
	if toAttacker.Magnitude < 0.05 then
		return true
	end
	return root.CFrame.LookVector:Dot(toAttacker.Unit) >= math.cos(math.rad(arc / 2))
end

-- Called ONLY by CombatService after full server-side validation.
function EnemyService.ApplyDamage(model: Model, amount: number, attacker: Player, info: HitInfo?)
	local record = active[model]
	if not record or record.State == "Dead" then
		return false
	end

	local humanoid = record.Humanoid
	if humanoid.Health <= 0 then
		return false
	end
	local hit: HitInfo = info or {}
	local cfg = record.Config
	local root = record.Model.PrimaryPart :: BasePart
	local attackerRoot = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
	local from = if attackerRoot and attackerRoot:IsA("BasePart")
		then attackerRoot.Position
		else root.Position
	local now = os.clock()

	-- A boss mid-transition (G1) takes nothing: sparks, no number, no reaction.
	if record.Invulnerable then
		HitConfirm:FireAllClients({
			Kind = "blocked",
			Immune = true,
			Position = hit.Contact or root.Position,
			Attacker = attacker.UserId,
			Target = model,
		})
		return true
	end

	-- Being hit is being found (F8): a short alert, then the fight, whatever the sightline.
	if
		not record.Options.Brain
		and record.Target ~= attacker
		and attackerRoot
		and attackerRoot:IsA("BasePart")
	then
		record.Target = attacker
		setIdlePose(record, false)
		if not record.Attacking and now >= record.StaggeredUntil then
			startAlert(record, attackerRoot, ENEMY.AlertTimeHit)
		end
	end

	-- A shield (F3): frontal hits that don't break guard do nothing to the enemy, loudly.
	-- Heavy attacks and guard-breaking weapons break it open; so does attacking from behind.
	if cfg.Shield and now >= record.StaggeredUntil and frontal(record, from, cfg.Shield.Arc) then
		if hit.GuardBreak then
			EnemyService.Stagger(record, attacker) -- guard broken: open
		else
			record.LastHitAt = now
			if not record.Attacking then
				EnemyAnimator.PlayAction(record, "Block")
			end
			HitConfirm:FireAllClients({
				Kind = "blocked",
				Position = hit.Contact or root.Position,
				Attacker = attacker.UserId,
				Target = model,
			})
			return true -- the swing connected, with the shield
		end
	end

	humanoid.Health = math.max(0, humanoid.Health - amount)
	local killed = humanoid.Health <= 0
	record.LastHitAt = now

	-- Poise, then the reaction: a stagger if it broke, else a flinch if the enemy isn't
	-- committed to an attack (a flinch mid-windup would lie about the strike still coming).
	-- A brute's poise only moves for heavy and guard-breaking hits (F6).
	local staggered = record.State == "Stagger" and record.StaggeredUntil > now
	if not killed and cfg.Poise and cfg.Poise > 0 and not staggered then
		local poiseDamage = hit.PoiseDamage or amount
		if cfg.LightPoiseImmune and not (hit.Heavy or hit.GuardBreak) then
			poiseDamage = 0
		end
		record.Poise -= poiseDamage
		if record.Poise <= 0 and now >= record.StaggeredUntil then
			EnemyService.Stagger(record, attacker)
			staggered = true
		end
	end
	if not killed and not staggered and not record.Attacking and now >= record.StaggeredUntil then
		if not cfg.LightPoiseImmune or hit.Heavy then
			EnemyAnimator.PlayAction(record, "Flinch")
			knockback(record, from, GameConfig.Combat.FlinchKnockback)
		end
	end
	if not killed and hit.Knockback and hit.Knockback > 0 and not cfg.LightPoiseImmune then
		knockback(record, from, hit.Knockback)
	end

	HitConfirm:FireAllClients({
		Kind = "dealt",
		Damage = amount,
		Position = hit.Contact or root.Position,
		Killed = killed,
		Attacker = attacker.UserId,
		Target = model,
		Finisher = hit.Finisher == true,
		Staggered = staggered,
	})

	ctx.Analytics.Log(attacker, "FirstGuardHit", 1, { enemy = record.EnemyId })

	if record.Options.OnDamaged then
		record.Options.OnDamaged(record, attacker)
	end

	if killed then
		EnemyService.Kill(record, attacker)
	end
	return true
end

-- A dead enemy fades out and goes. Anchored first, so a ragdoll can't keep sliding while
-- it fades; collisions off, so nobody stands on an invisible corpse.
local function fadeOut(model: Model)
	if not model.Parent then
		return
	end
	local time = GameConfig.Death.CorpseFadeTime
	local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Anchored = true
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		elseif d:IsA("Decal") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		elseif d:IsA("BillboardGui") or d:IsA("Highlight") then
			d.Enabled = false
		end
	end
	task.delay(time, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

-- An enemy's death (D4): the pose holds at the frame of death while the loot bursts out,
-- the body becomes a clean ragdoll after Death.EnemyHold, lies there for CorpseDespawn,
-- then fades. No clip keeps playing, no humanoid keeps pathing, no corpse keeps sliding.
function EnemyService.Kill(record, killer: Player?)
	if record.State == "Dead" then
		return
	end
	record.State = "Dead"
	-- Freeze first (hold the exact pose, stop every clip), then detach from the animator.
	EnemyAnimator.Freeze(record)
	EnemyAnimator.Detach(record)
	setAlertMark(record, false)

	local model = record.Model
	local humanoid: Humanoid = record.Humanoid
	local root = model.PrimaryPart :: BasePart
	local position = root.Position
	active[model] = nil
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- no bar on a corpse
	humanoid.WalkSpeed = 0

	-- A boss's final blow holds its frame for a beat before the body goes and the reward
	-- drops (G3). Everyone else: the loot bursts out at once.
	local hold = if cfg.Boss then GameConfig.Captain.DeathHold else GameConfig.Death.EnemyHold
	if killer then
		ctx.Analytics.Log(killer, "FirstGuardKilled", 1, { enemy = record.EnemyId })
		ctx.Analytics.Log(killer, "EnemyKilled", 1, { enemy = record.EnemyId })
		ctx.RunState.RecordKill(killer)
	end
	task.delay(if cfg.Boss then hold else 0, function()
		ctx.LootService.DropForEnemy(record.EnemyId, position, killer)
	end)

	if record.Options.OnKilled then
		record.Options.OnKilled(record, killer)
	end

	task.delay(hold, function()
		if not model.Parent then
			return
		end
		local ok, result = pcall(Ragdoll.Apply, model)
		if not ok or not result then
			-- Fallback: the old graybox fall. Never a T-pose standing up.
			warn(
				("[Enemy] Ragdoll failed for %s; falling rigid: %s"):format(record.EnemyId, tostring(result))
			)
			humanoid.PlatformStand = true
			root.CanCollide = false
			root.AssemblyLinearVelocity = Vector3.new(0, 6, 0)
		end
	end)

	task.delay(GameConfig.Enemy.CorpseDespawn + (if cfg.Boss then hold else 0), function()
		fadeOut(model)
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
