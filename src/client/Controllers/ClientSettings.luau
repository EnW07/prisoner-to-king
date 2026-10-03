--!strict
-- ClientSettings.lua
-- Not a controller: this client's player settings (§40 accessibility). Defaults come from
-- GameConfig.Settings; the settings panel (J2) writes them; feedback code reads them.
-- Local to this client and this session: nothing here touches the server or the profile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))

local ClientSettings = {}

local values: { [string]: any } = table.clone(GameConfig.Settings)
local changed = Instance.new("BindableEvent")

-- Fires (key, value) whenever a setting changes.
ClientSettings.Changed = changed.Event

function ClientSettings.Get(key: string): any
	return values[key]
end

function ClientSettings.Set(key: string, value: any)
	if values[key] == value then
		return
	end
	values[key] = value
	changed:Fire(key, value)
end

-- The multiplier for every camera kick and shake: 1 normally, a fraction with the
-- reduced-shake setting on. Everything that moves the camera for feedback goes through it.
function ClientSettings.ShakeFactor(): number
	return if values.ReducedShake then GameConfig.Settings.ReducedShakeFactor else 1
end

return ClientSettings
