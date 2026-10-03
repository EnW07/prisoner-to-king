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

local Players = game:GetService("Players")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local WeaponConfig = require(game.ReplicatedStorage.Shared.Config.WeaponConfig)
local Net = require(game.ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.RateLimiter)

local CombatService = {}
local ctx
local AttackRequest: RemoteEvent
local Notify: RemoteEvent

local lastAttack: { [number]: number } = {}

function CombatService.Init(context)
	ctx = context
	AttackRequest = Net.Event("AttackRequest")
	Notify = Net.Event("Notify")

	AttackRequest.OnServerEvent:Connect(function(player)
		CombatService.HandleAttack(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastAttack[player.UserId] = nil
	end)
end

function CombatService.HandleAttack(player: Player)
	-- 1. Rate limit before doing any work.
	if not RateLimiter.Check(player, "Attack", GameConfig.Combat.MaxAttackRate) then
		return
	end

	-- 2. Alive check.
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	local profile = ctx.Data.Get(player)
	if not profile then
		return
	end

	-- 3. Cooldown, enforced from the equipped weapon's config — not from anything sent.
	local weapon = WeaponConfig.Get(profile.Equipped.WeaponId) or WeaponConfig.Get("fists")
	local cooldown = (weapon :: any).AttackCooldown
	local now = os.clock()
	local last = lastAttack[player.UserId] or 0
	if now - last < (cooldown - GameConfig.Combat.CooldownGrace) then
		return
	end
	lastAttack[player.UserId] = now

	-- 4. Server-side hit detection, from the server's position for this character.
	local range = GameConfig.Combat.Range
	local swingCF = root.CFrame * CFrame.new(0, 0, -range / 2)
	local swingSize = Vector3.new(GameConfig.Combat.Width, GameConfig.Combat.Height, range)

	-- Only enemy parts can be hit, so the query is limited to the Enemies folder. That also
	-- excludes the attacker. An R15 enemy is ~15+ parts plus costume, so the old 24-part
	-- cap could fill up on one guard and hide a second. The cap is now sized for several
	-- full rigs. MaxTargetsPerSwing still counts distinct enemies (models), not parts.
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ctx.EnemyService.GetContainer() }
	params.MaxParts = GameConfig.Combat.OverlapMaxParts

	local parts = workspace:GetPartBoundsInBox(swingCF, swingSize, params)

	local damage = ctx.Economy.GetPlayerDamage(player)
	local hitModels: { [Model]: boolean } = {}
	local hits = 0

	for _, hitPart in parts do
		if hits >= GameConfig.Combat.MaxTargetsPerSwing then
			break
		end
		local model = hitPart:FindFirstAncestorOfClass("Model")
		if model and not hitModels[model] and model:GetAttribute("EnemyId") then
			hitModels[model] = true
			if ctx.EnemyService.ApplyDamage(model, damage, player) then
				hits += 1
			end
		end
	end

	-- Tell the attacker their swing resolved even on a whiff, so feedback never feels dead.
	Notify:FireClient(player, { Text = "", Kind = if hits > 0 then "hit" else "swing" })
end

-- ── Weapons ─────────────────────────────────────────────────────
function CombatService.GiveWeapon(player: Player, weaponId: string)
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

	-- Milestone 1 auto-equips anything stronger. Manual equip arrives in Milestone 2.
	local current = WeaponConfig.Get(profile.Equipped.WeaponId)
	if not current or weapon.Damage > current.Damage then
		profile.Equipped.WeaponId = weaponId
		CombatService.EquipVisual(player)
	end

	ctx.Analytics.Log(player, "FirstWeaponPicked", 1, { weapon = weaponId })
	ctx.Analytics.Log(player, "WeaponAcquired", 1, { weapon = weaponId })

	Notify:FireClient(player, {
		Text = ("%s  ·  %s"):format(weapon.Name:upper(), weapon.Rarity:upper()),
		Sub = ("+%d DAMAGE"):format(weapon.Damage),
		Kind = "weapon",
		Rarity = weapon.Rarity,
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

	local p = Instance.new("Part")
	p.Name = "EquippedWeapon"
	p.Size = weapon.Model.Size
	p.Color = weapon.Model.Color
	p.Material = weapon.Model.Material
	p.CanCollide = false
	p.Massless = true
	p.CFrame = hand.CFrame * CFrame.new(0, -weapon.Model.Size.Y / 2, 0)
	p.Parent = character

	-- A Weld (not a WeldConstraint) named "Grip", so the client can tween its C0 for a
	-- wrist snap on rigs where it can't swing the arm (R6). See CombatController.
	local grip = Instance.new("Weld")
	grip.Name = "Grip"
	grip.Part0 = hand
	grip.Part1 = p
	grip.C0 = CFrame.new(0, -weapon.Model.Size.Y / 2, 0)
	grip.Parent = p
end

return CombatService
