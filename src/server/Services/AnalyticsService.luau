--!strict
-- AnalyticsService.lua
-- Blueprint §51: "The game should not be launched without events."
--
-- ⚠ VERIFY BEFORE LAUNCH: AnalyticsService:LogCustomEvent(player, name, value, customFields)
-- and the Enum.AnalyticsCustomFieldKeys names should be re-checked against current Roblox
-- Creator docs (create.roblox.com/docs/production/analytics/custom-events). Every call is
-- pcall-wrapped so a signature change degrades to a log line instead of breaking gameplay.
--
-- Custom events only report from a PUBLISHED experience. In Studio they print to Output.

local RobloxAnalytics = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)

local AnalyticsService = {}
local ctx

-- Funnel events that must fire at most once per player per session (§51 funnel 1-18).
local ONCE_PER_SESSION = {
	FirstSpawn = true,
	ChainsBroken = true,
	FirstWeaponPicked = true,
	FirstGuardHit = true,
	FirstGuardKilled = true,
	FirstLootPicked = true,
	FirstChestOpened = true,
	FirstEscapeStarted = true,
	FirstEscapeCompleted = true,
	FirstUpgradePurchased = true,
	SecondRunStarted = true,
}

local fired: { [number]: { [string]: boolean } } = {}

function AnalyticsService.Init(context)
	ctx = context
	Players.PlayerAdded:Connect(function(player)
		fired[player.UserId] = {}
	end)
	Players.PlayerRemoving:Connect(function(player)
		AnalyticsService.Log(player, "SessionEnd", 1, {
			runs = tostring((ctx.RunState and ctx.RunState.GetRunCount(player)) or 0),
		})
		fired[player.UserId] = nil
	end)
end

-- fields: a small string→string map. NEVER put personal information in here (§51).
function AnalyticsService.Log(
	player: Player,
	eventName: string,
	value: number?,
	fields: { [string]: string }?
)
	if not GameConfig.Analytics.Enabled then
		return
	end

	if ONCE_PER_SESSION[eventName] then
		local seen = fired[player.UserId]
		if not seen then
			seen = {}
			fired[player.UserId] = seen
		end
		if seen[eventName] then
			return
		end
		seen[eventName] = true
	end

	if RunService:IsStudio() and GameConfig.Analytics.LogToOutputInStudio then
		local extra = ""
		if fields then
			for k, v in fields do
				extra ..= (" %s=%s"):format(k, tostring(v))
			end
		end
		print(("[Analytics] %s | %s = %s%s"):format(player.Name, eventName, tostring(value or 1), extra))
	end

	task.spawn(function()
		local customFields = nil
		if fields then
			customFields = {}
			local slot = 1
			for _, v in fields do
				if slot > 3 then
					break
				end -- Roblox currently exposes 3 custom field slots
				local key = (Enum.AnalyticsCustomFieldKeys :: any)["CustomField0" .. slot]
				customFields[key.Name] = tostring(v)
				slot += 1
			end
		end

		local ok, err = pcall(function()
			RobloxAnalytics:LogCustomEvent(player, eventName, value or 1, customFields)
		end)
		if not ok and GameConfig.Debug.Verbose then
			warn("[Analytics] LogCustomEvent failed for " .. eventName .. ": " .. tostring(err))
		end
	end)
end

return AnalyticsService
