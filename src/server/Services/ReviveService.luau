--!strict
-- ReviveService.lua
-- The co-play hook, part one (MASTER_BUILD_SPEC L3; CLAUDE.md market constraints): a
-- downed player can be revived by another within a few seconds instead of dying. One
-- responsibility: the downed state and the revive.
--
-- WHEN: an enemy blow that would kill a player who has another living player nearby
-- (CoPlay.DownedEligibleRange) downs them instead: health to one, no movement, a REVIVE
-- prompt on them for everyone else, a timer. A revive within the time restores a share of
-- health; the timer expiring, or any further blow, is the death that would have happened.
--
-- SOLO IS UNCHANGED: with nobody near, the blow kills as before. Nothing about playing
-- alone gets slower or worse; this only adds a chance when someone is there (additive,
-- never a penalty). Server-authoritative: eligibility, distance and timing are all the
-- server's; the client only sees prompts and toasts.

local Players = game:GetService("Players")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(game.ReplicatedStorage.Shared.Net)

local ReviveService = {}
local ctx
local Notify: RemoteEvent
local CombatVisual: RemoteEvent
local COPLAY = GameConfig.CoPlay

type Downed = { Token: number, Prompt: ProximityPrompt, Humanoid: Humanoid }
local downed: { [number]: Downed } = {}

local function livingRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and not downed[player.UserId] then
		return root
	end
	return nil
end

function ReviveService.IsDowned(player: Player): boolean
	return downed[player.UserId] ~= nil
end

local function clear(player: Player)
	local d = downed[player.UserId]
	if not d then
		return
	end
	downed[player.UserId] = nil
	if d.Prompt.Parent then
		d.Prompt:Destroy()
	end
end

-- Bring them back up. `reviver` is who did it.
local function revive(player: Player, reviver: Player)
	local d = downed[player.UserId]
	if not d then
		return
	end
	local humanoid = d.Humanoid
	clear(player)
	if humanoid.Health <= 0 or not humanoid.Parent then
		return
	end
	humanoid.Health = math.max(humanoid.Health, humanoid.MaxHealth * COPLAY.RevivedHealthFraction)
	humanoid.WalkSpeed = GameConfig.Player.WalkSpeed
	humanoid.JumpPower = GameConfig.Player.JumpPower
	humanoid.PlatformStand = false
	Notify:FireClient(
		player,
		{ Text = "BACK UP", Sub = ("%s PULLED YOU UP"):format(reviver.DisplayName:upper()), Kind = "revived" }
	)
	Notify:FireClient(reviver, { Text = "REVIVED", Sub = player.DisplayName:upper(), Kind = "milestone" })
	ctx.Analytics.Log(reviver, "PlayerRevived", 1, { role = "reviver" })
	ctx.Analytics.Log(player, "PlayerRevived", 1, { role = "revived" })
	-- Everyone sees them stand (the Collapse pose relaxes).
	for _, other in Players:GetPlayers() do
		CombatVisual:FireClient(other, { UserId = player.UserId, Key = "Relax" })
	end
end

-- Down the player instead of killing them, if someone is near enough to help. Returns
-- true when they were downed (the caller skips the kill), false to let the blow kill.
function ReviveService.TryDown(player: Player, humanoid: Humanoid, attackName: string): boolean
	if downed[player.UserId] then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	-- Anyone else alive and up, close enough that a revive is realistic?
	local helper = false
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherRoot = livingRoot(other)
			if otherRoot and (otherRoot.Position - root.Position).Magnitude <= COPLAY.DownedEligibleRange then
				helper = true
				break
			end
		end
	end
	if not helper then
		return false
	end

	humanoid.Health = COPLAY.DownedHealth
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Revive"
	prompt.ObjectText = ("REVIVE %s"):format(player.DisplayName:upper())
	prompt.HoldDuration = COPLAY.ReviveHold
	prompt.MaxActivationDistance = COPLAY.ReviveRange
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt:SetAttribute("PTKGate", "revive")
	prompt:SetAttribute("DownedUserId", player.UserId)
	prompt.Parent = root

	local token = os.clock()
	downed[player.UserId] = { Token = token, Prompt = prompt, Humanoid = humanoid }
	prompt.Triggered:Connect(function(reviver)
		local d = downed[player.UserId]
		if not d or d.Token ~= token or reviver == player then
			return
		end
		local reviverRoot = livingRoot(reviver)
		if not reviverRoot or (reviverRoot.Position - root.Position).Magnitude > COPLAY.ReviveRange + 2 then
			return
		end
		revive(player, reviver)
	end)

	Notify:FireClient(
		player,
		{ Text = "DOWNED", Sub = "A FRIEND CAN PULL YOU UP", Kind = "downed", Time = COPLAY.DownedTime }
	)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Notify:FireClient(other, {
				Text = ("%s IS DOWN"):format(player.DisplayName:upper()),
				Sub = "REVIVE THEM",
				Kind = "alarm",
			})
		end
		CombatVisual:FireClient(other, { UserId = player.UserId, Key = "Death" })
	end
	ctx.Analytics.Log(player, "PlayerDowned", 1, { attack = attackName })

	task.delay(COPLAY.DownedTime, function()
		local d = downed[player.UserId]
		if d and d.Token == token then
			clear(player)
			if humanoid.Parent and humanoid.Health > 0 then
				humanoid.Health = 0 -- the death that was coming; RunState already knows the attack
			end
		end
	end)
	return true
end

function ReviveService.Init(context)
	ctx = context
	Notify = Net.Event("Notify")
	CombatVisual = Net.Event("CombatVisual")
	Players.PlayerRemoving:Connect(clear)
	-- A new character is never downed.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			clear(player)
		end)
	end)
end

return ReviveService
