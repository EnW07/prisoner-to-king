--!strict
-- ExtractionService.lua
-- Blueprint §14 + §48. This is the moment the whole game is built around:
-- loot is NOT yours until you get out.
--
-- SECURITY: banking happens here and nowhere else. The amount comes from the server's run
-- record, and the player's position is re-validated against the pad before the transfer.

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(game.ReplicatedStorage.Shared.Net)

local ExtractionService = {}
local ctx
local world
local prompt: ProximityPrompt
local ScreenEvent: RemoteEvent
local Notify: RemoteEvent

function ExtractionService.Init(context, builtWorld)
	ctx = context
	world = builtWorld
	ScreenEvent = Net.Event("ScreenEvent")
	Notify = Net.Event("Notify")

	prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Escape"
	prompt.ObjectText = "ESCAPE WITH YOUR LOOT"
	prompt.HoldDuration = GameConfig.Run.ExtractionChannelTime
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = world.ExtractionPad

	prompt.PromptButtonHoldBegan:Connect(function(player)
		ctx.Analytics.Log(player, "FirstEscapeStarted", 1)
		ctx.RunState.SetState(player, "Extracting")
	end)

	prompt.PromptButtonHoldEnded:Connect(function(player)
		local run = ctx.RunState.Get(player)
		if run and run.State == "Extracting" then
			ctx.RunState.SetState(player, "InDanger")
		end
	end)

	prompt.Triggered:Connect(function(player)
		ExtractionService.Complete(player)
	end)
end

-- Called when the alarm goes off, to make the exit obvious. (§8: "Exit marker activates.")
function ExtractionService.Reveal()
	world.ExtractionPad.Material = Enum.Material.Neon
	world.ExtractionPad.Color = Color3.fromRGB(90, 255, 140)
end

function ExtractionService.Complete(player: Player)
	local run = ctx.RunState.Get(player)
	local profile = ctx.Data.Get(player)
	if not run or not profile then return end
	if run.State == "Extracted" then return end

	-- Re-validate position. Never bank on the word of a prompt alone.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	if (root.Position - world.ExtractionPad.Position).Magnitude > 16 then
		warn(("[Extraction] %s triggered the pad from out of range — ignored."):format(player.Name))
		return
	end

	local banked = run.UnsecuredGold
	run.UnsecuredGold = 0
	run.State = "Extracted"

	local isFirstEscape = (profile.Meta.TotalEscapes or 0) == 0
	local bonus = 0
	if isFirstEscape then
		bonus = GameConfig.Economy.FirstEscapeBonus
		profile.Meta.TutorialComplete = true
	end

	profile.Meta.TotalEscapes = (profile.Meta.TotalEscapes or 0) + 1
	ctx.Economy.AddGold(player, banked + bonus, "extraction")

	ctx.Analytics.Log(player, "FirstEscapeCompleted", 1)
	ctx.Analytics.Log(player, "ExtractionSuccess", banked, {
		run = tostring(run.RunIndex),
		duration = tostring(math.floor(os.clock() - run.StartedAt)),
	})
	ctx.Analytics.Log(player, "RunEnded", run.RunIndex, { result = "extracted" })

	local lines = { ("Loot secured: +%d Gold"):format(banked) }
	if bonus > 0 then
		table.insert(lines, ("First Escape Bonus: +%d Gold"):format(bonus))
	end

	ScreenEvent:FireClient(player, { Kind = "escaped", Title = "ESCAPED!", Lines = lines })

	-- Move to the hideout.
	task.wait(0.6)
	if root and root.Parent then
		root.CFrame = world.HideoutSpawnCFrame
	end

	ctx.RunState.SetState(player, "Safe")
	ctx.RunState.SetObjective(player, "UPGRADE YOUR ARMORY")
	ctx.Data.Save(player, false)
	ctx.Economy.PushState(player)
end

return ExtractionService
