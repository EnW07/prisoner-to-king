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

-- Total damage of the equipped weapon including permanent Training/Armory upgrades.
function EconomyService.GetPlayerDamage(player: Player): number
	local profile = ctx.Data.Get(player)
	if not profile then
		return 5
	end
	local weapon = WeaponConfig.Get(profile.Equipped.WeaponId) or WeaponConfig.Get("fists")
	local bonus = (profile.Castle.WeaponRackLevel or 0)
		* require(game.ReplicatedStorage.Shared.Config.GameConfig).Economy.WeaponRackDamageBonus
	return (weapon :: any).Damage + bonus
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
		WeaponDamage = EconomyService.GetPlayerDamage(player),
		Objective = run and run.Objective or "",
		RunState = run and run.State or "Safe",
		WeaponRackLevel = profile.Castle.WeaponRackLevel or 0,
		WeaponRackCost = require(game.ReplicatedStorage.Shared.Config.GameConfig).Economy.WeaponRackCost,
		TotalEscapes = profile.Meta.TotalEscapes or 0,
	})
end

return EconomyService
