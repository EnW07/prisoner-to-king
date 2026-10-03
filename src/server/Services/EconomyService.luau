--!strict
-- EconomyService.lua
-- SECURITY: the only place Gold is ever changed. Nothing on the client can call these.
-- The client receives a read-only snapshot via StateUpdate and renders it.

local Net = require(game.ReplicatedStorage.Shared.Net)
local WeaponConfig = require(game.ReplicatedStorage.Shared.Config.WeaponConfig)

local EconomyService = {}
local ctx
local StateUpdate: RemoteEvent

function EconomyService.Init(context)
	ctx = context
	StateUpdate = Net.Event("StateUpdate")
end

function EconomyService.GetGold(player: Player): number
	local profile = ctx.Data.Get(player)
	return profile and profile.Currencies.Gold or 0
end

function EconomyService.AddGold(player: Player, amount: number, reason: string)
	if amount <= 0 then
		return
	end
	local profile = ctx.Data.Get(player)
	if not profile then
		return
	end
	profile.Currencies.Gold += math.floor(amount)
	ctx.Analytics.Log(player, "GoldEarned", amount, { reason = reason })
	EconomyService.PushState(player)
end

-- Returns false if the player cannot afford it. Callers MUST check the return value.
function EconomyService.TrySpendGold(player: Player, amount: number, reason: string): boolean
	local profile = ctx.Data.Get(player)
	if not profile then
		return false
	end
	if profile.Currencies.Gold < amount then
		return false
	end
	profile.Currencies.Gold -= math.floor(amount)
	ctx.Analytics.Log(player, "GoldSpent", amount, { reason = reason })
	EconomyService.PushState(player)
	return true
end

-- Total damage of the equipped weapon including the permanent weapon-upgrade bonus.
-- The flat bonus from weapon upgrades. It applies to whatever weapon is equipped.
function EconomyService.GetDamageBonus(player: Player): number
	local profile = ctx.Data.Get(player)
	if not profile then
		return 0
	end
	return (profile.Castle.WeaponRackLevel or 0)
		* require(game.ReplicatedStorage.Shared.Config.GameConfig).Economy.WeaponUpgradeDamageBonus
end

function EconomyService.GetPlayerDamage(player: Player): number
	local profile = ctx.Data.Get(player)
	if not profile then
		return 5
	end
	local weapon = WeaponConfig.Get(profile.Equipped.WeaponId) or WeaponConfig.Get("fists")
	return (weapon :: any).Damage + EconomyService.GetDamageBonus(player)
end

function EconomyService.PushState(player: Player)
	local profile = ctx.Data.Get(player)
	if not profile then
		return
	end
	local run = ctx.RunState and ctx.RunState.Get(player)
	local weapon = WeaponConfig.Get(profile.Equipped.WeaponId)

	StateUpdate:FireClient(player, {
		Gold = profile.Currencies.Gold,
		Unsecured = run and run.UnsecuredGold or 0,
		HasKey = run and run.HasKey or false,
		Weapon = weapon and weapon.Name or "Fists",
		WeaponId = profile.Equipped.WeaponId, -- for the HUD's 3D weapon icon
		OwnedWeapons = table.clone(profile.Inventory.Weapons), -- the inventory grid (a copy)
		WeaponDamage = EconomyService.GetPlayerDamage(player), -- total: base + bonus
		-- The upgrade bonus on its own, so every screen can show "base +bonus" and agree
		-- (playtest 5: the HUD showed 28 where the inventory showed 18).
		DamageBonus = EconomyService.GetDamageBonus(player),
		Objective = run and run.Objective or "",
		RunState = run and run.State or "Safe",
		WeaponUpgradeLevel = profile.Castle.WeaponRackLevel or 0,
		TotalEscapes = profile.Meta.TotalEscapes or 0,
		-- Trophies (G3). Meta.CaptainKills is written only once the SchemaVersion 2 migration
		-- lands (Section L5); until then this reads 0 and the trophy stays hidden.
		CaptainKills = profile.Meta.CaptainKills or 0,

		-- Per-player prompt state. Prompt.Enabled is replicated (shared), so the client gates
		-- its own prompts from these fields instead. (M1 bugs 1/2/4/5.)
		ChainsBroken = run and run.ChainsBroken or false,
		HasWeapon = profile.Equipped.WeaponId ~= "fists",
		ChestOpened = run and run.ChestOpened or false,
		DoorOpened = run and run.DoorOpened or false,
		UpgradeCost = (ctx.Upgrade and ctx.Upgrade.GetCost(player)) or 0,
	})
end

return EconomyService
