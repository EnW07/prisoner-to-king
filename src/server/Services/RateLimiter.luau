--!strict
-- RateLimiter.lua
-- Blueprint §44: "Every remote should have reasonable server-side rate limiting."
-- Invalid requests are IGNORED and counted — never an instant kick on one false positive.

local Players = game:GetService("Players")

local RateLimiter = {}

type Bucket = { Tokens: number, Last: number, Rate: number, Max: number, Violations: number }

local buckets: { [number]: { [string]: Bucket } } = {}

Players.PlayerRemoving:Connect(function(player)
	buckets[player.UserId] = nil
end)

-- Returns true if the action is allowed right now.
function RateLimiter.Check(player: Player, action: string, ratePerSecond: number): boolean
	local perPlayer = buckets[player.UserId]
	if not perPlayer then
		perPlayer = {}
		buckets[player.UserId] = perPlayer
	end

	local bucket = perPlayer[action]
	local now = os.clock()
	if not bucket then
		bucket =
			{ Tokens = ratePerSecond, Last = now, Rate = ratePerSecond, Max = ratePerSecond, Violations = 0 }
		perPlayer[action] = bucket
	end

	bucket.Tokens = math.min(bucket.Max, bucket.Tokens + (now - bucket.Last) * bucket.Rate)
	bucket.Last = now

	if bucket.Tokens >= 1 then
		bucket.Tokens -= 1
		return true
	end

	bucket.Violations += 1
	if bucket.Violations % 25 == 0 then
		-- Log for review. Do NOT auto-punish from this signal alone; lag looks like this too.
		warn(("[RateLimiter] %s exceeded '%s' %d times"):format(player.Name, action, bucket.Violations))
	end
	return false
end

function RateLimiter.GetViolations(player: Player, action: string): number
	local perPlayer = buckets[player.UserId]
	local bucket = perPlayer and perPlayer[action]
	return bucket and bucket.Violations or 0
end

return RateLimiter
