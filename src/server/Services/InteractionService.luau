--!strict
-- InteractionService.lua
-- Every interaction uses a ProximityPrompt, which gives keyboard, gamepad and TOUCH support
-- for free (§38 mobile-first, §103 "usable on keyboard, controller, and touch").
--
-- SECURITY: ProximityPrompt.Triggered fires on the server with the real player. The server
-- still re-checks distance and run state, because a prompt can be fired by an exploiter.

local Players = game:GetService("Players")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local LootConfig = require(game.ReplicatedStorage.Shared.Config.LootConfig)
local Net = require(game.ReplicatedStorage.Shared.Net)

local InteractionService = {}
local ctx
local world
local Notify: RemoteEvent

local MAX_PROMPT_DISTANCE = 14

local function makePrompt(
	parent: BasePart,
	actionText: string,
	objectText: string,
	hold: number?
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = hold or 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = parent
	return prompt
end

-- Shared guard for every prompt handler.
local function validate(player: Player, target: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if (root.Position - target.Position).Magnitude > MAX_PROMPT_DISTANCE then
		return false
	end
	return true
end

function InteractionService.Init(context, builtWorld)
	ctx = context
	world = builtWorld
	Notify = Net.Event("Notify")

	-- ── 1. BREAK YOUR CHAINS ───────────────────────────────────
	-- NOTE: the server never toggles prompt.Enabled — that property is replicated and would
	-- be global to every player. Each prompt is tagged with a PTKGate attribute and the
	-- client's PromptController shows/hides it per-player from StateUpdate. The server still
	-- re-validates every Triggered call, so this loses no authority. (M1 bugs 1/2/5.)
	local chainPrompt = makePrompt(world.Chain, "Break", "BREAK YOUR CHAINS", 0.35)
	chainPrompt:SetAttribute("PTKGate", "chains")
	chainPrompt.Triggered:Connect(function(player)
		if not validate(player, world.Chain) then
			return
		end
		local run = ctx.RunState.Get(player)
		if not run or run.ChainsBroken then
			return
		end

		run.ChainsBroken = true
		ctx.Analytics.Log(player, "ChainsBroken", 1)
		InteractionService.ReleaseChains(player)

		Notify:FireClient(player, { Text = "CHAINS BROKEN", Kind = "milestone" })
		ctx.RunState.SetObjective(player, "GRAB A WEAPON")
	end)

	-- ── 2. GRAB A WEAPON ───────────────────────────────────────
	local weaponPrompt = makePrompt(world.WeaponPlank, "Take", "GRAB A WEAPON")
	weaponPrompt:SetAttribute("PTKGate", "weapon")
	weaponPrompt.Triggered:Connect(function(player)
		if not validate(player, world.WeaponPlank) then
			return
		end
		local run = ctx.RunState.Get(player)
		if not run or not run.ChainsBroken then
			Notify:FireClient(player, { Text = "BREAK YOUR CHAINS FIRST", Kind = "warn" })
			return
		end
		local profile = ctx.Data.Get(player)
		if profile and table.find(profile.Inventory.Weapons, "bent_spoon") then
			-- Already has it; on repeat runs this prompt is just flavour.
			ctx.RunState.SetObjective(player, "STEAL THE KEY")
			return
		end

		ctx.Combat.GiveWeapon(player, "bent_spoon")
		ctx.RunState.SetObjective(player, "STEAL THE KEY")
		if world.SpoonProp then
			world.SpoonProp.Transparency = 1
		end
	end)

	-- ── 3. UNLOCK THE CELLBLOCK ────────────────────────────────
	local doorPrompt = makePrompt(world.LockedDoor, "Unlock", "LOCKED — NEEDS KEY", 0.5)
	doorPrompt:SetAttribute("PTKGate", "door")
	doorPrompt.Triggered:Connect(function(player)
		if not validate(player, world.LockedDoor) then
			return
		end
		local run = ctx.RunState.Get(player)
		if not run then
			return
		end

		if not run.HasKey then
			Notify:FireClient(player, { Text = "YOU NEED THE CELLBLOCK KEY", Kind = "warn" })
			return
		end

		run.DoorOpened = true
		ctx.Analytics.Log(player, "DoorUnlocked", 1)
		Notify:FireClient(player, { Text = "CELLBLOCK OPEN", Kind = "milestone" })
		-- SetObjective pushes state, so the DoorOpened = true above rides along to the client.
		ctx.RunState.SetObjective(player, "TAKE THE SWORD")

		-- The door is a shared, replicated part — the server must NOT change its CanCollide
		-- or Transparency, or it would open for every player at once and stay open across
		-- runs (the M1 regression). Instead the client's "door" gate opens it locally for
		-- this player only, this run only. `run.DoorOpened` is reset by StartRun.
	end)

	-- ── 4. THE CHEST → ALARM ───────────────────────────────────
	local chestPrompt = makePrompt(world.Chest, "Open", "CHEST", 0.6)
	chestPrompt:SetAttribute("PTKGate", "chest")
	chestPrompt.Triggered:Connect(function(player)
		if not validate(player, world.Chest) then
			return
		end
		local run = ctx.RunState.Get(player)
		if not run or run.ChestOpened then
			return
		end
		run.ChestOpened = true

		ctx.Analytics.Log(player, "FirstChestOpened", 1)

		-- §115: the first chest ALWAYS contains the Rusty Sword. No random onboarding.
		ctx.Combat.GiveWeapon(player, LootConfig.Guarantees.FirstChestWeapon)
		ctx.RunState.AddUnsecuredGold(player, GameConfig.Economy.ChestGold)
		Notify:FireClient(player, { Text = ("+%d Gold"):format(GameConfig.Economy.ChestGold), Kind = "gold" })

		InteractionService.TriggerAlarm(player)

		-- The chest gives loot exactly once per run. `run.ChestOpened` stays true for the
		-- life of this run; StartRun mints a fresh run record on re-entry, so the next run
		-- gets its guaranteed chest again. The client's "chest" gate hides the prompt for
		-- this player only. (Bug 2: the old 30s re-arm let a player farm the chest.)
	end)
end

-- ── Alarm ───────────────────────────────────────────────────────
function InteractionService.TriggerAlarm(player: Player)
	ctx.RunState.SetObjective(player, "RUN! ESCAPE WITH YOUR LOOT")
	ctx.RunState.SetState(player, "InDanger")
	ctx.Analytics.Log(player, "AlarmTriggered", 1)

	Notify:FireAllClients({ Text = "ALARM! GUARDS ARE COMING", Kind = "alarm" })
	ctx.Extraction.Reveal()

	for i = 1, math.min(GameConfig.Run.AlarmGuardCount, #world.AlarmGuardSpawns) do
		ctx.EnemyService.Spawn("alarm_guard", world.AlarmGuardSpawns[i], { Respawn = false })
	end
end

-- ── Chain movement restriction ──────────────────────────────────
-- Chains are a real mechanic, not a cutscene: the player is slow until they break them.
function InteractionService.ApplyChains(player: Player)
	local profile = ctx.Data.Get(player)
	if profile and profile.Meta.TutorialComplete then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = 6
	humanoid.JumpPower = 0
end

function InteractionService.ReleaseChains(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = GameConfig.Player.WalkSpeed
	humanoid.JumpPower = GameConfig.Player.JumpPower

	-- Feedback: let the chain physically drop once, instead of a meaningless 3s transparency
	-- blip. It's a shared graybox prop, so we only unanchor it the first time.
	if world and world.Chain and world.Chain.Anchored then
		world.Chain.CanCollide = true
		world.Chain.Anchored = false
	end
end

return InteractionService
