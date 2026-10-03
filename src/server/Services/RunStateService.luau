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
	DoorOpened: boolean,
	ChainsBroken: boolean,
	Objective: string,
	RunIndex: number,
	StartedAt: number,
	FirstGuardKilled: boolean,
	-- The last enemy attack that landed on this player, for the CAPTURED screen.
	LastHit: { Enemy: string, Attack: string, At: number }?,
	-- Progress this run, for the CAPTURED screen (§67 fail-soft: the run was not wasted).
	Kills: number,
	CaptainReached: boolean,
	Rooms: { [string]: boolean }, -- rooms entered this run (RoomService)
	RoomCount: number,
	-- The locked shortcut (H3): the postern key is per run, like the cellblock key.
	HasPosternKey: boolean,
	PosternOpened: boolean,
	-- Secrets taken this run (H5), so a loose brick pays once per run.
	Secrets: { [string]: boolean },
	BarracksChestOpened: boolean,
}

local runs: { [number]: Run } = {}

local function blank(index: number): Run
	return {
		State = "InDanger",
		UnsecuredGold = 0,
		HasKey = false,
		ChestOpened = false,
		DoorOpened = false,
		ChainsBroken = false,
		Objective = "BREAK YOUR CHAINS",
		RunIndex = index,
		StartedAt = os.clock(),
		FirstGuardKilled = false,
		LastHit = nil,
		Kills = 0,
		CaptainReached = false,
		Rooms = {},
		RoomCount = 0,
		HasPosternKey = false,
		PosternOpened = false,
		Secrets = {},
		BarracksChestOpened = false,
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
	for _, player in Players:GetPlayers() do
		hook(player)
	end
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
	if not profile then
		return
	end

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
		if run then
			run.ChainsBroken = true
		end
		if player.Character then
			ctx.Interaction.ReleaseChains(player)
		end
	end

	ctx.Economy.PushState(player)
end

function RunStateService.SetObjective(player: Player, text: string)
	local run = runs[player.UserId]
	if not run then
		return
	end
	run.Objective = text
	ctx.Economy.PushState(player)
end

function RunStateService.SetState(player: Player, state: string)
	local run = runs[player.UserId]
	if not run then
		return
	end
	run.State = state
	ctx.Economy.PushState(player)
end

function RunStateService.AddUnsecuredGold(player: Player, amount: number)
	local run = runs[player.UserId]
	if not run or amount <= 0 then
		return
	end
	run.UnsecuredGold += math.floor(amount)
	ctx.Economy.PushState(player)
end

function RunStateService.GiveKey(player: Player)
	local run = runs[player.UserId]
	if not run then
		return
	end
	run.HasKey = true
	RunStateService.SetObjective(player, "UNLOCK THE CELLBLOCK")
	Notify:FireClient(player, { Text = "CELLBLOCK KEY", Kind = "loot" })
	ctx.Economy.PushState(player)
end

-- Called by EnemyService.DamagePlayer for every enemy hit that lands.
function RunStateService.RecordHit(player: Player, enemyName: string, attackName: string)
	local run = runs[player.UserId]
	if not run then
		return
	end
	run.LastHit = { Enemy = enemyName, Attack = attackName, At = os.clock() }
end

-- Called by EnemyService.Kill for every enemy this player kills.
function RunStateService.RecordKill(player: Player)
	local run = runs[player.UserId]
	if run then
		run.Kills += 1
	end
end

-- Called by CaptainService when the player picks the fight.
function RunStateService.MarkCaptainReached(player: Player)
	local run = runs[player.UserId]
	if run then
		run.CaptainReached = true
	end
end

-- Called by RoomService. Returns true the first time this run enters the room.
function RunStateService.MarkRoom(player: Player, room: string): boolean
	local run = runs[player.UserId]
	if not run or run.Rooms[room] then
		return false
	end
	run.Rooms[room] = true
	run.RoomCount += 1
	return true
end

-- A secret taken this run. Returns false if it was already taken.
function RunStateService.TakeSecret(player: Player, id: string): boolean
	local run = runs[player.UserId]
	if not run or run.Secrets[id] then
		return false
	end
	run.Secrets[id] = true
	return true
end

function RunStateService.GivePosternKey(player: Player)
	local run = runs[player.UserId]
	if not run or run.HasPosternKey then
		return
	end
	run.HasPosternKey = true
	Notify:FireClient(
		player,
		{ Text = "POSTERN KEY", Sub = "A SHORTER WAY OUT, FROM THE VAULT", Kind = "loot" }
	)
	ctx.Economy.PushState(player)
end

-- What this run achieved, in one line. Shown on CAPTURED so a death never reads as a
-- wasted run (§67). Rooms are added when the castle has rooms to count (Section H).
local function progressLine(run: Run): string
	local parts = {}
	if run.RoomCount > 0 then
		table.insert(
			parts,
			("%d room%s entered"):format(run.RoomCount, if run.RoomCount == 1 then "" else "s")
		)
	end
	if run.Kills > 0 then
		table.insert(parts, ("%d guard%s killed"):format(run.Kills, if run.Kills == 1 then "" else "s"))
	end
	if run.HasKey then
		table.insert(parts, "key stolen")
	end
	if run.DoorOpened then
		table.insert(parts, "cellblock opened")
	end
	if run.ChestOpened then
		table.insert(parts, "chest looted")
	end
	if run.CaptainReached then
		table.insert(parts, "Captain reached")
	end
	if #parts == 0 then
		return "the first guard is the lesson"
	end
	return table.concat(parts, ", ")
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
	if not run or not profile then
		return
	end

	local lost = math.floor(run.UnsecuredGold * GameConfig.Run.DeathUnsecuredLossPercent)
	local bestKept = "None"
	local weapon = require(game.ReplicatedStorage.Shared.Config.WeaponConfig).Get(profile.Equipped.WeaponId)
	if weapon then
		bestKept = weapon.Name
	end

	profile.Meta.TotalDeaths = (profile.Meta.TotalDeaths or 0) + 1
	run.State = "Dead"

	ctx.Analytics.Log(player, "Death", 1, {
		run = tostring(run.RunIndex),
		unsecured = tostring(run.UnsecuredGold),
		objective = run.Objective,
	})
	ctx.Analytics.Log(player, "RunEnded", run.RunIndex, { result = "death" })

	-- §66: CAPTURED, not "you lost everything". Equipped gear is always kept. Name the
	-- exact attack that did it, so a death teaches something (§12), and what the run
	-- achieved, so it was not wasted (§67). The client (DeathController) lays this out.
	local hit = run.LastHit
	local killedBy = nil
	if hit and os.clock() - hit.At <= GameConfig.Run.DeathAttributionWindow then
		killedBy = { Enemy = hit.Enemy:upper(), Attack = hit.Attack }
	end
	ScreenEvent:FireClient(player, {
		Kind = "captured",
		Title = "CAPTURED!",
		KilledBy = killedBy,
		GoldLost = lost,
		GearKept = bestKept,
		Progress = progressLine(run),
	})

	ctx.Data.Save(player, false)
end

return RunStateService
