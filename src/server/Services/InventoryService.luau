--!strict
-- InventoryService.lua
-- M2 item 4: equip a weapon you own. One responsibility: validated equip requests.
--
-- SECURITY (CLAUDE.md rules 1–3): the client sends only WHICH weapon it wants, an intent
-- the server can't compute. The server checks, in order: rate limit, the argument is a
-- short string, the weapon exists, and the profile owns it. Any failure is ignored
-- silently. Nothing about damage or stats is ever taken from the client.

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local WeaponConfig = require(game.ReplicatedStorage.Shared.Config.WeaponConfig)
local Net = require(game.ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.RateLimiter)

local InventoryService = {}
local ctx

function InventoryService.Init(context)
	ctx = context
	Net.Event("EquipRequest").OnServerEvent:Connect(function(player, weaponId)
		InventoryService.Equip(player, weaponId)
	end)
end

function InventoryService.Equip(player: Player, weaponId: any)
	if not RateLimiter.Check(player, "Equip", GameConfig.Inventory.MaxEquipRate) then
		return
	end
	if typeof(weaponId) ~= "string" or #weaponId > GameConfig.Inventory.MaxWeaponIdLength then
		return
	end
	if not WeaponConfig.Get(weaponId) then
		return
	end
	local profile = ctx.Data.Get(player)
	if not profile or not table.find(profile.Inventory.Weapons, weaponId) then
		return -- not owned: never equip on the client's word
	end
	if profile.Equipped.WeaponId == weaponId then
		return
	end

	profile.Equipped.WeaponId = weaponId
	ctx.Combat.EquipVisual(player)
	ctx.Analytics.Log(player, "WeaponEquipped", 1, { weapon = weaponId })
	ctx.Economy.PushState(player)
end

return InventoryService
