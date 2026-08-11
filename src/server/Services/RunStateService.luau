--!strict
-- RunStateService.lua
-- Blueprint §48 + §113. Run loot is kept STRICTLY separate from the saved profile.
-- Nothing here is banked until ExtractionService says so.
--
-- States: Safe → InDanger → Extracting → Extracted | Dead

local Players = game:GetService("Players")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(game.ReplicatedStorage.Shared.Net)

local RunStateService = {}
local ctx
local Notify: RemoteEvent
local ScreenEvent: RemoteEvent

type Run = {
	State: string,
	UnsecuredGold: number,
	HasKey: boolean,
	ChestOpened: boolean,
	ChainsBroken: boolean,
	Objective: string,
	RunIndex: number,
	StartedAt: number,
	FirstGuardKilled: boolean,
}

local runs: { [number]: Run } = {}

local function blank(index: number): Run
	return {
		State = "InDanger",
		UnsecuredGold = 0,
		HasKey = false,
		ChestOpened = false,
		ChainsBroken = false,
		Objective = "BREAK YOUR CHAINS",
		RunIndex = index,
		StartedAt = os.clock(),
		FirstGuardKilled = false,
	}
end

function RunStateService.Init(context)
	ctx = context
	Notify = Net.Event("Notify")
	ScreenEvent = Net.Event("ScreenEvent")

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			RunStateService.OnCharacterAdded(player, character)
		end)
		if player.Character then
			RunStateService.OnCharacterAdded(player, player.Character)
		end
	end

	-- Cover players who joined before this service finished initialising.
	for _, player in Players:GetPlayers() do hook(player) end
	Players.PlayerAdded:Connect(hook)

	Players.PlayerRemoving:Connect(function(player)
		runs[player.UserId] = nil
	end)
end

function RunStateService.Get(player: Player): Run?
	return runs[player.UserId]
end

function RunStateService.GetRunCount(player: Player): number
	local profile = ctx.Data.Get(player)
	return profile and profile.Meta.TotalRuns or 0
end

-- Start a fresh run. Called on first spawn and every time the player re-enters the dungeon.
function RunStateService.StartRun(player: Player)
	local profile = ctx.Data.Get(player)
	if not profile then return end

	profile.Meta.TotalRuns = (profile.Meta.TotalRuns or 0) + 1
	local index = profile.Meta.TotalRuns

	runs[player.UserId] = blank(index)

	if index == 1 then
		ctx.Analytics.Log(player, "FirstSpawn", 1)
	elseif index == 2 then
		-- §51 funnel event 11: the single best early signal that the loop works.
		ctx.Analytics.Log(player, "SecondRunStarted", 1)
	end
	ctx.Analytics.Log(player, "RunStarted", index)

	-- Returning players skip the chain tutorial framing but keep the same objective chain.
	if profile.Meta.TutorialComplete then
		RunStateService.SetObjective(player, "STEAL THE KEY")
		local run = runs[player.UserId]
		if run then run.ChainsBroken = true end
		if player.Character then
			ctx.Interaction.ReleaseChains(player)
		end
	end

	ctx.Economy.PushState(player)
end

function RunStateService.SetObjective(player: Player, text: string)
	local run = runs[player.UserId]
	if not run then return end
	run.Objective = text
	ctx.Economy.PushState(player)
end

function RunStateService.SetState(player: Player, state: string)
	local run = runs[player.UserId]
	if not run then return end
	run.State = state
	ctx.Economy.PushState(player)
end

function RunStateService.AddUnsecuredGold(player: Player, amount: number)
	local run = runs[player.UserId]
	if not run or amount <= 0 then return end
	run.UnsecuredGold += math.floor(amount)
	ctx.Economy.PushState(player)
end

function RunStateService.GiveKey(player: Player)
	local run = runs[player.UserId]
	if not run then return end
	run.HasKey = true
	RunStateService.SetObjective(player, "UNLOCK THE CELLBLOCK")
	Notify:FireClient(player, { Text = "CELLBLOCK KEY", Kind = "loot" })
	ctx.Economy.PushState(player)
end

function RunStateService.OnCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.MaxHealth = GameConfig.Player.MaxHealth
	humanoid.Health = GameConfig.Player.MaxHealth
	humanoid.WalkSpeed = GameConfig.Player.WalkSpeed
	humanoid.JumpPower = GameConfig.Player.JumpPower

	humanoid.Died:Connect(function()
		RunStateService.OnDeath(player)
	end)

	-- A fresh character always means a fresh run in Milestone 1.
	task.defer(function()
		RunStateService.StartRun(player)
		ctx.Interaction.ApplyChains(player)
		ctx.Combat.EquipVisual(player)
	end)
end

function RunStateService.OnDeath(player: Player)
	local run = runs[player.UserId]
	local profile = ctx.Data.Get(player)
	if not run or not profile then return end

	local lost = math.floor(run.UnsecuredGold * GameConfig.Run.DeathUnsecuredLossPercent)
	local bestKept = "None"
	local weapon = require(game.ReplicatedStorage.Shared.Config.WeaponConfig).Get(profile.Equipped.WeaponId)
	if weapon then bestKept = weapon.Name end

	profile.Meta.TotalDeaths = (profile.Meta.TotalDeaths or 0) + 1
	run.State = "Dead"

	ctx.Analytics.Log(player, "Death", 1, {
		run = tostring(run.RunIndex),
		unsecured = tostring(run.UnsecuredGold),
		objective = run.Objective,
	})
	ctx.Analytics.Log(player, "RunEnded", run.RunIndex, { result = "death" })

	-- §66: CAPTURED, not "you lost everything". Equipped gear is always kept.
	ScreenEvent:FireClient(player, {
		Kind = "captured",
		Title = "CAPTURED!",
		Lines = {
			("Unsecured Gold lost: %d"):format(lost),
			("Gear kept: %s"):format(bestKept),
		},
	})

	ctx.Data.Save(player, false)
end

return RunStateService
