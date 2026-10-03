--!strict
-- HitStop.lua
-- Not a controller: a tiny shared utility. Hit-stop is the brief freeze when a blow lands,
-- the cheapest way to make a hit feel heavy. (VISUAL_OVERHAUL_PLAN Phase 2, item 12.)
--
-- Client-only and purely visual: it pauses this client's tracked tweens (the weapon swing)
-- and this character's animation tracks. Physics, the server and other players are never
-- touched, so it can't affect fairness.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local HitStop = {}

local tracked: { [Tween]: boolean } = {}
local frozenUntil = 0

-- Register a tween that should freeze during hit-stop. Untracks itself when finished.
function HitStop.Track(t: Tween)
	tracked[t] = true
	t.Completed:Connect(function()
		tracked[t] = nil
	end)
end

function HitStop.Freeze(duration: number)
	local now = os.clock()
	local wasFrozen = now < frozenUntil
	frozenUntil = math.max(frozenUntil, now + duration)
	if wasFrozen then
		return -- already frozen: the deadline is extended, and the pending thaw re-checks it
	end

	local paused: { Tween } = {}
	for t in tracked do
		if t.PlaybackState == Enum.PlaybackState.Playing then
			t:Pause()
			table.insert(paused, t)
		end
	end

	local tracks: { { any } } = {}
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			table.insert(tracks, { track, track.Speed })
			track:AdjustSpeed(0)
		end
	end

	local function thaw()
		local remaining = frozenUntil - os.clock()
		if remaining > 0 then
			task.delay(remaining, thaw)
			return
		end
		for _, t in paused do
			t:Play() -- resumes a paused tween from where it stopped
		end
		for _, entry in tracks do
			entry[1]:AdjustSpeed(entry[2])
		end
	end
	task.delay(duration, thaw)
end

return HitStop
