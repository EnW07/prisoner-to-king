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
local RigFactory = require(script.Parent.RigFactory)
local EnemyAnimator = require(script.Parent.EnemyAnimator)

local CaptainService = {}
local ctx
local world
local Notify: RemoteEvent
local telegraphs: Folder

local ENEMY_ID = "captain_bronn"
local TUNE = GameConfig.Captain

-- His arm poses live in AnimationConfig (Poses.Bronn*, Moves.BronnCleave/Crush/Charge/
-- Roar) and play through EnemyAnimator, so a clip id in AnimationConfig.Sets.Captain
-- replaces any of them with no change here. Each wind-up pose is a distinct silhouette.
-- The greatsword in his palm: blade along the arm's line, angled 40 degrees forward.
local SWORD_SIZE = Vector3.new(0.8, 7.5, 0.35)
local SWORD_GRIP = CFrame.Angles(math.rad(40), 0, 0) * CFrame.new(0, -(SWORD_SIZE.Y / 2 - 0.8), 0)

-- Presentation pieces are optional. If dressing him fails, the fight still runs (playtest 5:
-- a failed dress used to leave an inert, killable husk with no health bar and no respawn).
type Fight = {
	Record: any,
	Sword: BasePart?,
	Highlight: Highlight?,
	Busy: boolean,
	Interrupt: number, -- bumped by a stagger; a running attack bails when it changes
	InFight: boolean,
	RotationIndex: number,
	NextAttackAt: number,
	LastTargetAt: number,
	Reinforced: boolean,
	Phase: number, -- 1, then 2 after the transition (G1)
	Fire: Fire?, -- the ignited greatsword
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
-- True from his death until the respawn delay fires. The watchdog leaves him alone then.
local respawnPending = false

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

-- ── Presentation ────────────────────────────────────────────────
-- Silhouette: an R15 rig scaled from EnemyConfig (RigFactory), so he is genuinely taller,
-- broader and bulkier than any guard. Dressed with pauldrons, a crested helm and an oversized
-- greatsword held in his hand. Readable as a black shape (art §8 priority 1).
local function dress(record): (BasePart?, Highlight)
	local model: Model = record.Model
	local head = model:FindFirstChild("Head") :: BasePart

	for _, side in { "Left", "Right" } do
		local arm = model:FindFirstChild(side .. "UpperArm") :: BasePart?
		if arm then
			RigFactory.Attach(
				model,
				side .. "UpperArm",
				"Pauldron",
				Vector3.new(arm.Size.X + 1, arm.Size.Y * 0.35, arm.Size.Z + 1),
				CFrame.new(0, arm.Size.Y / 2, 0),
				Palette.stone,
				Enum.Material.Metal
			)
		end
	end
	RigFactory.Attach(
		model,
		"Head",
		"Helm",
		head.Size + Vector3.new(0.5, 0.4, 0.5),
		CFrame.new(0, 0.2, 0),
		Palette.stone,
		Enum.Material.Metal
	)
	RigFactory.Attach(
		model,
		"Head",
		"Crest",
		Vector3.new(0.4, 1.2, head.Size.Z + 0.6),
		CFrame.new(0, head.Size.Y / 2 + 0.7, 0),
		Palette.bleed,
		Enum.Material.SmoothPlastic
	)
	local sword = RigFactory.Attach(
		model,
		"RightHand",
		"Greatsword",
		SWORD_SIZE,
		SWORD_GRIP,
		Palette.stone,
		Enum.Material.Metal
	) :: BasePart

	-- His resting stance (AnimationConfig.Sets.Captain.Posture) is baked by EnemyAnimator
	-- when EnemyService attaches him, before this runs. Nothing about joints lives here.

	local highlight = Instance.new("Highlight")
	highlight.Adornee = model
	highlight.FillColor = Palette.bleed
	highlight.OutlineColor = Palette.bleed
	highlight.FillTransparency = TUNE.TelegraphTransparency
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = model

	return sword, highlight
end

-- The telegraph. The attack name is published as the model's "Callout" attribute and drawn
-- by the client's boss bar (BossBarController), next to his health.
local function setTelegraph(f: Fight, attackName: string?)
	local on = attackName ~= nil
	if f.Highlight then
		f.Highlight.Enabled = on
	end
	if f.Sword then
		-- In phase two the sword stays lit (it burns); the telegraph is the outline.
		local lit = on or f.Phase >= 2
		f.Sword.Material = if lit then Enum.Material.Neon else Enum.Material.Metal
		f.Sword.Color = if lit then Palette.bleed else Palette.stone
	end
	f.Record.Model:SetAttribute("Callout", if attackName then attackName .. "!" else "")
end

-- The attack timings for the current phase.
local function timeScale(f: Fight): number
	local phase = f.Record.Config.PhaseTwo
	return if f.Phase >= 2 and phase then phase.TimeScale else 1
end

local function rotationFor(f: Fight): { string }
	local cfg = f.Record.Config
	local phase = cfg.PhaseTwo
	return if f.Phase >= 2 and phase then phase.Rotation else cfg.Rotation
end

-- Paints the exact hit area on the floor for the whole wind-up. What you see is precisely
-- what the server will test: both use the same `origin` and the same attack data.
local function makeMarker(f: Fight, attack, origin: CFrame, reach: number, windUp: number): BasePart
	-- His feet: root centre minus hip height and half the root. Correct at any rig scale.
	local root = f.Record.Model.PrimaryPart :: BasePart
	local drop = (f.Record.Humanoid :: Humanoid).HipHeight + root.Size.Y / 2
	local floor = origin * CFrame.new(0, -drop + 0.08, 0)

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
	TweenService:Create(p, TweenInfo.new(windUp, Enum.EasingStyle.Linear), {
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
	local myInterrupt = f.Interrupt
	while os.clock() < deadline and alive(f) and f.Interrupt == myInterrupt do
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

-- attackId is the EnemyConfig key (e.g. "CrushingBlow"), used to look up a clip.
local function performAttack(f: Fight, attackId: string, attack, aim: Vector3)
	local record = f.Record
	local cfg = record.Config
	local hum: Humanoid = record.Humanoid
	local root = record.Model.PrimaryPart :: BasePart
	f.Busy = true
	record.Attacking = true -- a hit mid-attack doesn't flinch him out of it (EnemyService)
	local myInterrupt = f.Interrupt
	local function cut(): boolean
		return not alive(f) or f.Interrupt ~= myInterrupt
	end

	-- Plant and lock facing. The strike resolves against THIS origin, so stepping out of the
	-- painted area during the wind-up is always a clean dodge.
	hum.WalkSpeed = 0
	hum:MoveTo(root.Position)
	local origin = facing(root.Position, aim)
	root.CFrame = origin
	-- Phase two runs modestly faster. Every timing below uses these, including the marker.
	local scale = timeScale(f)
	local windUp = attack.WindUp * scale
	local recovery = attack.Recovery * scale

	local reach = attack.Length or 0
	local destination = root.Position
	if attack.Shape == "Charge" then
		destination = clampToArena((origin * CFrame.new(0, 0, -attack.Length)).Position, cfg.BodySize.X)
		reach = flatDistance(root.Position, destination)
	end

	local marker = makeMarker(f, attack, origin, reach, windUp)
	setTelegraph(f, attack.Name)
	-- The whole attack is one move with its phases filled from the attack's own timings:
	--   Wind     the wind-up pose, snapped into then drawn deeper until the release
	--   Strike   the arc, started StrikeLead before the hit test so the sword ARRIVES as
	--            the blow lands, then held through the impact pause (or, for the charge,
	--            the run pose held for the whole dash)
	--   Recover  a slow, heavy return: the punish window, visibly
	-- An AnimationConfig clip for this move replaces all of it with no change here.
	local lead = math.min(GameConfig.Animation.StrikeLead, windUp * 0.4)
	local strikeTime = if attack.Shape == "Charge" then reach / TUNE.ChargeSpeed else TUNE.ImpactPause
	EnemyAnimator.PlayAction(record, attackId, {
		Wind = windUp - lead,
		Strike = lead + strikeTime,
		Recover = recovery,
	})

	task.wait(windUp)

	if cut() then
		removeMarker(f, marker)
		return
	end
	do
		local damage = math.floor(cfg.Damage * attack.DamageMultiplier + 0.5)
		marker.Transparency = 0
		setTelegraph(f, nil)
		-- Impact: the hit test (or the dash), then the blow HOLDS (impact pause). Nearby
		-- players feel it (K3): the heavier the blow, the harder the shake.
		if attack.Shape ~= "Charge" then
			local impactAt = if attack.Shape == "Circle"
				then (origin * CFrame.new(0, 0, -(attack.Offset or 0))).Position
				else (origin * CFrame.new(0, 0, -(attack.Length or 0) / 2)).Position
			notifyEngaged(f, {
				Text = "",
				Kind = "bossImpact",
				Position = impactAt,
				Strength = TUNE.ImpactKick * attack.DamageMultiplier,
			})
		end
		if attack.Shape == "Charge" then
			charge(f, attack, destination, damage)
		else
			strike(f, attack, origin, damage)
		end
		task.wait(TUNE.ImpactPause)
	end
	removeMarker(f, marker)

	if cut() then
		return
	end
	-- Recovery: he stands still while the move's Recover phase plays out. This is the
	-- player's punish window.
	task.wait(recovery)
	if cut() then
		return
	end
	hum.WalkSpeed = cfg.MoveSpeed
	f.NextAttackAt = os.clock() + cfg.AttackCooldown
	f.Busy = false
	record.Attacking = false
end

-- ── Brain ───────────────────────────────────────────────────────
local function engage(f: Fight, player: Player)
	if f.Engaged[player.UserId] then
		return
	end
	f.Engaged[player.UserId] = true
	ctx.RunState.MarkCaptainReached(player)
	ctx.Analytics.Log(player, "CaptainEngaged", 1, { weapon = weaponId(player), run = runIndex(player) })
	-- Spell out the choice the whole game is built on: fight for the reward, or leave with
	-- what you're carrying (art §7 verbs: STEAL, ESCAPE).
	-- The title card (G3): name and title, once per session on the client, skippable.
	Notify:FireClient(player, {
		Text = "CAPTAIN BRONN",
		Sub = "STEAL HIS SWORD — OR ESCAPE WITH YOUR LOOT",
		Kind = "bossIntro",
		Title = "KEEPER OF THE VAULT",
	})
end

-- No one left in the hall long enough: walk home and heal fully. Stops the step-in,
-- hit, step-out pattern from whittling him down for free.
-- Back to phase one: the sword goes out, the rotation resets.
local function leavePhaseTwo(f: Fight)
	f.Phase = 1
	if f.Fire then
		f.Fire.Enabled = false
	end
	setTelegraph(f, nil)
	notifyEngaged(f, { Text = "", Kind = "bossReset" })
end

local function reset(f: Fight)
	dismissReinforcements()
	f.InFight = false
	f.Reinforced = false
	f.RotationIndex = 1
	leavePhaseTwo(f)
	table.clear(f.Engaged)
	local hum: Humanoid = f.Record.Humanoid
	hum.Health = hum.MaxHealth
end

-- THE MOMENT (G1): at half health, once. Whatever he was doing stops; he is invulnerable
-- while he roars; his armour lights, the greatsword ignites, a guard is called; then his
-- attacks come faster and the rotation gains the Flame Sweep. Clients get one event to
-- flash, push the camera and play the sting.
local function enterPhaseTwo(f: Fight)
	local record = f.Record
	f.Phase = 2
	f.Interrupt += 1 -- cuts any attack in flight
	for _, marker in f.Markers do
		marker:Destroy()
	end
	table.clear(f.Markers)
	f.Busy = true
	record.Attacking = true
	record.Invulnerable = true
	local hum: Humanoid = record.Humanoid
	hum.WalkSpeed = 0
	hum:MoveTo((record.Model.PrimaryPart :: BasePart).Position)

	-- The look: outline on, sword lit, and fire on the blade. Fire is an old, stable class.
	if f.Highlight then
		f.Highlight.Enabled = true
	end
	setTelegraph(f, nil)
	if f.Sword and not f.Fire then
		local fire = Instance.new("Fire")
		fire.Color = Palette.ember
		fire.SecondaryColor = Palette.bleed
		fire.Size = 5
		fire.Heat = 12
		fire.Parent = f.Sword
		f.Fire = fire
	elseif f.Fire then
		f.Fire.Enabled = true
	end
	record.Model:SetAttribute("Callout", "")
	record.Model:SetAttribute("Phase", 2)

	EnemyAnimator.PlayAction(record, "Roar")
	notifyEngaged(f, {
		Text = "BRONN ROARS",
		Sub = "HIS BLADE IGNITES",
		Kind = "bossPhase",
		Position = (record.Model.PrimaryPart :: BasePart).Position,
	})
	for userId in f.Engaged do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			ctx.Analytics.Log(
				player,
				"CaptainPhaseTwo",
				1,
				{ weapon = weaponId(player), run = runIndex(player) }
			)
		end
	end

	-- The reinforcement, called during the roar.
	dismissReinforcements()
	local guard = ctx.EnemyService.Spawn(TUNE.ReinforcementEnemy, world.CaptainReinforcementSpawn, {
		SpawnCFrame = world.CaptainReinforcementSpawn,
	})
	if guard then
		table.insert(reinforcements, guard)
	end

	task.delay(TUNE.PhaseRoarTime, function()
		if not alive(f) then
			return
		end
		record.Invulnerable = false
		record.Attacking = false
		f.Busy = false
		f.RotationIndex = 1
		hum.WalkSpeed = record.Config.MoveSpeed
		f.NextAttackAt = os.clock() + record.Config.AttackCooldown
		if f.Highlight then
			f.Highlight.Enabled = false
		end
	end)
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
			local rotation = rotationFor(f)
			local name = rotation[f.RotationIndex]
			f.RotationIndex = f.RotationIndex % #rotation + 1
			task.spawn(performAttack, f, name, cfg.Attacks[name], target.Position)
			return
		end
		local ranged = cfg.RangedAttack and cfg.Attacks[cfg.RangedAttack]
		if ranged and best >= TUNE.ChargeMinRange and best <= ranged.Length then
			task.spawn(performAttack, f, cfg.RangedAttack, ranged, target.Position)
			return
		end
	end
	-- Close to his stand-off ring, never into the player (playtest 5). Inside it he plants
	-- and turns to face you between attacks, and steps back if crowded.
	local root = record.Model.PrimaryPart :: BasePart
	local standoff = cfg.StandoffDistance or cfg.AttackRange
	local away = Vector3.new(root.Position.X - target.Position.X, 0, root.Position.Z - target.Position.Z)
	local awayDir = if away.Magnitude > 0.05 then away.Unit else -root.CFrame.LookVector
	if best > standoff or best < standoff - GameConfig.Enemy.StandoffSlack then
		record.Humanoid:MoveTo(target.Position + awayDir * standoff)
	else
		record.Humanoid:MoveTo(root.Position)
		root.CFrame = facing(root.Position, target.Position)
	end
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
	local phase = record.Config.PhaseTwo
	if phase and not f.Reinforced and hum.Health > 0 and hum.Health <= hum.MaxHealth * phase.AtHealth then
		f.Reinforced = true
		enterPhaseTwo(f)
	end
end

local function onKilled(record, killer: Player?)
	-- The respawn is scheduled whatever state the fight is in. It used to sit behind the
	-- fight check below, so a Bronn whose fight never formed died and never came back.
	if not respawnPending then
		respawnPending = true
		task.delay(TUNE.RespawnDelay, function()
			respawnPending = false
			CaptainService.Spawn()
		end)
	end

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
	record.Model:SetAttribute("Callout", "")
	notifyEngaged(f, { Text = "", Kind = "bossDefeated" })

	if killer then
		ctx.Analytics.Log(killer, "CaptainKilled", 1, { weapon = weaponId(killer), run = runIndex(killer) })
		Notify:FireClient(killer, {
			Text = "CAPTAIN BRONN DEFEATED",
			Sub = "STEAL HIS SWORD",
			Kind = "milestone",
		})
	end
end

-- His poise broke (E7): whatever he was doing stops, telegraph and all, and he is open
-- for his StaggerDuration. Rare, by his poise, but it must be possible or heavy attacks
-- have no purpose against him.
local function onStaggered(record)
	local f = fight
	if not f or f.Record ~= record then
		return
	end
	f.Interrupt += 1
	for _, marker in f.Markers do
		marker:Destroy()
	end
	table.clear(f.Markers)
	setTelegraph(f, nil)
	local hum: Humanoid = record.Humanoid
	hum.WalkSpeed = record.Config.MoveSpeed
	f.Busy = false
	record.Attacking = false
	f.NextAttackAt = os.clock() + (record.Config.StaggerDuration or 1) + record.Config.AttackCooldown
	notifyEngaged(f, { Text = "BRONN STAGGERS!", Sub = "HIT HIM", Kind = "milestone" })
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

	-- Watchdog: Bronn must be present on every run (playtest 5). If he's missing outside
	-- his respawn window, for any reason, he's put back and the reason is logged.
	task.spawn(function()
		while true do
			task.wait(TUNE.WatchdogInterval)
			local f = fight
			if f and not (f.Record.Model.Parent and f.Record.State ~= "Dead") and not respawnPending then
				warn("[Captain] Bronn's model is gone without a death; respawning")
				fight = nil
			end
			if not fight and not respawnPending then
				warn("[Captain] Bronn is missing outside his respawn window; spawning him")
				CaptainService.Spawn()
			end
		end
	end)
end

function CaptainService.Spawn()
	if fight then
		return
	end
	-- A guard from Bronn's previous life must not carry into this one.
	dismissReinforcements()
	local record = ctx.EnemyService.Spawn(ENEMY_ID, world.CaptainSpawn, {
		-- Respawned here, on GameConfig.Captain.RespawnDelay: the one enemy who comes back.
		SpawnCFrame = world.CaptainSpawn,
		Brain = think,
		OnDamaged = onDamaged,
		OnKilled = onKilled,
		OnKilledPlayer = onKilledPlayer,
		OnStaggered = onStaggered,
	})
	if not record then
		warn("[Captain] EnemyService could not spawn Bronn; the watchdog will retry")
		return
	end

	-- What clients need to draw his boss bar (name, health from the Humanoid, callout).
	local model: Model = record.Model
	-- PhaseAt before Boss: the client builds the bar on Boss and reads PhaseAt as it does.
	model:SetAttribute("PhaseAt", record.Config.PhaseTwo and record.Config.PhaseTwo.AtHealth or 0)
	model:SetAttribute("Phase", 1)
	model:SetAttribute("Boss", true)
	model:SetAttribute("BossName", record.Config.DisplayName:upper())
	model:SetAttribute("Callout", "")
	-- The boss bar replaces the stock Humanoid bar.
	record.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	-- Dressing is presentation. If it fails, say exactly why and fight anyway: a Bronn who
	-- can't be dressed must still move, attack and die properly.
	local ok, sword, highlight = xpcall(dress, debug.traceback, record)
	if not ok then
		warn("[Captain] Dressing Bronn failed; fighting without costume:\n" .. tostring(sword))
		sword, highlight = nil, nil
	end
	local f: Fight = {
		Record = record,
		Sword = sword,
		Highlight = highlight,
		Busy = false,
		Interrupt = 0,
		InFight = false,
		RotationIndex = 1,
		NextAttackAt = 0,
		LastTargetAt = 0,
		Reinforced = false,
		Phase = 1,
		Fire = nil,
		Engaged = {},
		Markers = {},
	}
	fight = f
	respawnPending = false
	local root = model.PrimaryPart
	print(
		("[Captain] Bronn ready: %d HP at %s"):format(
			record.Humanoid.MaxHealth,
			if root then tostring(root.Position) else "?"
		)
	)
end

return CaptainService
