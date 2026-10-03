--!strict
-- CombatService.lua
-- Blueprint §44/§45. The client sends an INTENT ("I attacked"), never a result.
--
-- The server independently decides:
--   • is this player alive and not rate-limited?
--   • has their weapon cooldown actually elapsed?
--   • which enemies are inside the swing volume, measured from the SERVER's copy of the
--     character position?
--   • how much damage is dealt, from config + saved upgrades?
--
-- A client that says "I dealt 999999 damage" is not even given a field to say it in.
--
-- WEAPON IDENTITY (E6) is data: reach, combo chain, guard break, knockback, stagger bonus
-- and the heavy multiplier come from WeaponConfig. Nothing here checks a weapon id.
-- Three intents: AttackRequest (the light combo), HeavyRequest (hold and release),
-- DashRequest (the i-frames). All zero arguments, all rate limited.

local Players = game:GetService("Players")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local WeaponConfig = require(game.ReplicatedStorage.Shared.Config.WeaponConfig)
local Net = require(game.ReplicatedStorage.Shared.Net)
local WeaponModel = require(game.ReplicatedStorage.Shared.WeaponModel)
local RateLimiter = require(script.Parent.RateLimiter)

local CombatService = {}
local ctx
local AttackRequest: RemoteEvent
local DashRequest: RemoteEvent
local HeavyRequest: RemoteEvent
local Notify: RemoteEvent
local CombatVisual: RemoteEvent

local lastAttack: { [number]: number } = {}
local lastHeavy: { [number]: number } = {}
-- Light combo stage per player, from the same rule the client predicts with
-- (GameConfig.Animation.ComboWindow). The server's count is the one that matters (E3).
local comboStage: { [number]: number } = {}
-- Dash (E1): the server's own cooldown clock and the invincibility window it grants.
local lastDash: { [number]: number } = {}
local invulnerableUntil: { [number]: number } = {}

function CombatService.Init(context)
	ctx = context
	AttackRequest = Net.Event("AttackRequest")
	Notify = Net.Event("Notify")
	CombatVisual = Net.Event("CombatVisual")

	AttackRequest.OnServerEvent:Connect(function(player)
		CombatService.HandleAttack(player)
	end)
	DashRequest = Net.Event("DashRequest")
	DashRequest.OnServerEvent:Connect(function(player)
		CombatService.HandleDash(player)
	end)
	HeavyRequest = Net.Event("HeavyRequest")
	HeavyRequest.OnServerEvent:Connect(function(player)
		CombatService.HandleHeavy(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastAttack[player.UserId] = nil
		comboStage[player.UserId] = nil
		lastDash[player.UserId] = nil
		lastHeavy[player.UserId] = nil
		invulnerableUntil[player.UserId] = nil
	end)
end

-- The alive, equipped attacker: character root, profile and weapon, or nils.
local function attacker(player: Player): (BasePart?, any?, any?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	local profile = ctx.Data.Get(player)
	if not profile then
		return nil, nil, nil
	end
	local weapon = WeaponConfig.Get(profile.Equipped.WeaponId) or WeaponConfig.Get("fists")
	return root, profile, weapon
end

-- Tell every other client to play this move on the attacker's character. A client's joint
-- changes never replicate, so without this other players would see a frozen attacker.
-- The attacker already played its own on input.
local function broadcast(player: Player, key: string, weapon)
	local visual = { UserId = player.UserId, Key = key, Weight = (weapon :: any).Weight }
	for _, other in Players:GetPlayers() do
		if other ~= player then
			CombatVisual:FireClient(other, visual)
		end
	end
end

-- Everything inside the swing volume (the weapon's reach deep, the configured cross-section,
-- in front of the server's copy of the character): breakables break, enemies take `damage`
-- with `info`. Returns the number of enemies hit.
local function strike(player: Player, root: BasePart, reach: number, damage: number, info): number
	local swingCF = root.CFrame * CFrame.new(0, 0, -reach / 2)
	local swingSize = Vector3.new(GameConfig.Combat.Width, GameConfig.Combat.Height, reach)

	-- Only enemy parts and breakables can be hit, so the query is limited to those folders.
	-- That also excludes the attacker. An R15 enemy is ~15+ parts plus costume, so the cap
	-- is sized for several full rigs. MaxTargetsPerSwing counts distinct enemies (models).
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ctx.EnemyService.GetContainer(), ctx.Environment.GetBreakables() }
	params.MaxParts = GameConfig.Combat.OverlapMaxParts
	local parts = workspace:GetPartBoundsInBox(swingCF, swingSize, params)

	local hitModels: { [Model]: boolean } = {}
	local hits = 0
	for _, hitPart in parts do
		if hits >= GameConfig.Combat.MaxTargetsPerSwing then
			break
		end
		-- Crates and barrels in the arc break (H4). They don't count against the target cap.
		if hitPart:GetAttribute("Breakable") then
			ctx.Environment.Break(hitPart, player)
			continue
		end
		local model = hitPart:FindFirstAncestorOfClass("Model")
		if model and not hitModels[model] and model:GetAttribute("EnemyId") then
			hitModels[model] = true
			-- The contact point is the overlapped part itself (a limb, a torso), not the
			-- enemy's centre, so sparks and numbers land where the blade did (E8).
			local perHit = table.clone(info)
			perHit.Contact = hitPart.Position
			if ctx.EnemyService.ApplyDamage(model, damage, player, perHit) then
				hits += 1
			end
		end
	end
	return hits
end

-- The light attack (E3): the combo chain is the weapon's; the last stage is the finisher.
function CombatService.HandleAttack(player: Player)
	-- 1. Rate limit before doing any work.
	if not RateLimiter.Check(player, "Attack", GameConfig.Combat.MaxAttackRate) then
		return
	end

	-- 2. Alive, with a profile and a weapon.
	local root, _profile, weapon = attacker(player)
	if not root or not weapon then
		return
	end

	-- 3. Cooldown, enforced from the equipped weapon's config — not from anything sent.
	local cooldown = weapon.AttackCooldown
	local now = os.clock()
	local last = lastAttack[player.UserId] or 0
	if now - last < (cooldown - GameConfig.Combat.CooldownGrace) then
		return
	end
	lastAttack[player.UserId] = now

	-- The combo stage, from the weapon's own chain length and the same window the client
	-- predicts with. Pausing longer than the window starts the chain over.
	local chain: { string } = weapon.Combo
	local stage = if now - last <= GameConfig.Animation.ComboWindow
		then (comboStage[player.UserId] or 0) % #chain + 1
		else 1
	comboStage[player.UserId] = stage
	local finisher = #chain >= 2 and stage == #chain
	broadcast(player, chain[stage], weapon)

	-- 4. Server-side hit detection, with the weapon's identity as data (E6).
	local stageDamage = GameConfig.Combat.ComboDamage[stage] or 1
	local damage = math.floor(ctx.Economy.GetPlayerDamage(player) * stageDamage + 0.5)
	local info = {
		Knockback = weapon.KnockbackForce + (if finisher then GameConfig.Combat.FinisherKnockback else 0),
		Finisher = finisher,
		GuardBreak = weapon.GuardBreak,
		StaggerBonus = weapon.StaggerBonus,
	}
	local hits = strike(player, root, weapon.Reach, damage, info)

	-- Tell the attacker their swing resolved even on a whiff, so feedback never feels dead.
	Notify:FireClient(player, { Text = "", Kind = if hits > 0 then "hit" else "swing" })
end

-- The heavy attack (E2): the client held the input and released. Slower, more damage,
-- breaks guard, knocks back, hits poise harder, and resets the combo. Its own per-weapon
-- cooldown, and it can't land right on top of a light swing. It is the specific answer to
-- the shield guard (F3).
function CombatService.HandleHeavy(player: Player)
	if not RateLimiter.Check(player, "Attack", GameConfig.Combat.MaxAttackRate) then
		return
	end
	local root, _profile, weapon = attacker(player)
	if not root or not weapon then
		return
	end
	local now = os.clock()
	local C = GameConfig.Combat
	if now - (lastHeavy[player.UserId] or 0) < weapon.HeavyCooldown - C.CooldownGrace then
		return
	end
	if now - (lastAttack[player.UserId] or 0) < weapon.AttackCooldown * C.HeavyAfterLightFraction then
		return
	end
	lastHeavy[player.UserId] = now
	lastAttack[player.UserId] = now
	comboStage[player.UserId] = 0
	broadcast(player, "Heavy", weapon)
	ctx.Analytics.Log(player, "HeavyUsed", 1, { weapon = weapon.Name })

	local damage = math.floor(ctx.Economy.GetPlayerDamage(player) * weapon.HeavyDamageMultiplier + 0.5)
	local info = {
		Knockback = weapon.KnockbackForce + C.HeavyKnockback,
		Finisher = true,
		Heavy = true,
		GuardBreak = true,
		PoiseDamage = damage * C.HeavyPoiseMultiplier,
		StaggerBonus = weapon.StaggerBonus,
	}
	local hits = strike(player, root, weapon.Reach + C.HeavyReachBonus, damage, info)
	Notify:FireClient(player, { Text = "", Kind = if hits > 0 then "hit" else "swing" })
end

-- ── Dash (E1) ───────────────────────────────────────────────────
-- The client already burst; this decides whether it COUNTS: a cooldown from the server's
-- clock, then an invincibility window enemy hits are tested against (EnemyService
-- .DamagePlayer). Nothing is read from the client but the fact of the request.
function CombatService.HandleDash(player: Player)
	if not RateLimiter.Check(player, "Dash", GameConfig.Dash.MaxRate) then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	local last = lastDash[player.UserId] or 0
	if now - last < GameConfig.Dash.Cooldown - GameConfig.Combat.CooldownGrace then
		return
	end
	lastDash[player.UserId] = now
	-- The window is the dash's, plus the weapon's (a dagger slips through anything, E6).
	local profile = ctx.Data.Get(player)
	local weapon = (profile and WeaponConfig.Get(profile.Equipped.WeaponId)) or WeaponConfig.Get("fists")
	invulnerableUntil[player.UserId] = now
		+ GameConfig.Dash.IFrameWindow
		+ ((weapon :: any).DashIFrameBonus or 0)
	ctx.Analytics.Log(player, "DashUsed", 1)
	broadcast(player, "Dash", weapon)
end

-- True while the player's last granted dash still protects them.
function CombatService.IsInvulnerable(player: Player): boolean
	return os.clock() < (invulnerableUntil[player.UserId] or 0)
end

-- ── Weapons ─────────────────────────────────────────────────────
-- autoEquip: put it straight into the player's hand. Reserved for the §115 first-run
-- guarantees; every other weapon is collected and equipped by choice.
function CombatService.GiveWeapon(player: Player, weaponId: string, autoEquip: boolean?)
	local weapon = WeaponConfig.Get(weaponId)
	if not weapon then
		return
	end

	local profile = ctx.Data.Get(player)
	if not profile then
		return
	end

	if not table.find(profile.Inventory.Weapons, weaponId) then
		table.insert(profile.Inventory.Weapons, weaponId)
	end

	-- M2 item 4: weapons are collected, not auto-equipped. You choose what to carry in the
	-- inventory, or from the loot reveal's EQUIP button. Two exceptions keep run 1
	-- deterministic (§115):
	--   • with nothing but fists, your first weapon goes straight into your hand (the §8
	--     tutorial beat, "GRAB A WEAPON");
	--   • the caller asks for it (autoEquip): the first chest's guaranteed Rusty Sword.
	if profile.Equipped.WeaponId == "fists" or autoEquip then
		profile.Equipped.WeaponId = weaponId
		CombatService.EquipVisual(player)
	end

	ctx.Analytics.Log(player, "FirstWeaponPicked", 1, { weapon = weaponId })
	ctx.Analytics.Log(player, "WeaponAcquired", 1, { weapon = weaponId })
	if weapon.Rarity ~= "Common" and weapon.Rarity ~= "Uncommon" then
		ctx.Analytics.Log(player, "RareObtained", 1, { weapon = weaponId, rarity = weapon.Rarity })
	end

	Notify:FireClient(player, {
		Text = ("%s  ·  %s"):format(weapon.Name:upper(), weapon.Rarity:upper()),
		Sub = ("+%d DAMAGE"):format(weapon.Damage),
		Kind = "weapon",
		Rarity = weapon.Rarity,
		WeaponId = weaponId, -- for the 3D loot reveal
		Equipped = profile.Equipped.WeaponId == weaponId,
	})

	ctx.Economy.PushState(player)
end

-- Welds a graybox weapon part to the character's hand. Handles both R6 and R15.
function CombatService.EquipVisual(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local profile = ctx.Data.Get(player)
	if not profile then
		return
	end

	local existing = character:FindFirstChild("EquippedWeapon")
	if existing then
		existing:Destroy()
	end

	local weapon = WeaponConfig.Get(profile.Equipped.WeaponId)
	if not weapon or profile.Equipped.WeaponId == "fists" then
		return
	end

	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand then
		-- Character parts can lag a frame behind CharacterAdded. Retry once, briefly.
		hand = character:WaitForChild("RightHand", 3) or character:WaitForChild("Right Arm", 1)
	end
	if not hand or not hand:IsA("BasePart") then
		return
	end

	-- The same model the HUD icon shows (WeaponModel), so the hand and the UI always match.
	local model = WeaponModel.Build(profile.Equipped.WeaponId)
	if not model or not model.PrimaryPart then
		return
	end
	model.Name = "EquippedWeapon"
	local blade = model.PrimaryPart :: BasePart
	local gripOffset = CFrame.new(0, -blade.Size.Y / 2, 0)
	model:PivotTo(hand.CFrame * gripOffset)
	model.Parent = character

	-- A Weld named "Grip" holds the weapon in the hand. The swing moves the ARM
	-- (PlayerAnimController through the pose system); the grip itself never animates.
	local grip = Instance.new("Weld")
	grip.Name = "Grip"
	grip.Part0 = hand
	grip.Part1 = blade
	grip.C0 = gripOffset
	grip.Parent = blade
end

return CombatService
