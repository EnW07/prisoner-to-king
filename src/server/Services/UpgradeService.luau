--!strict
-- UpgradeService.lua
-- The first gold sink, and the button that closes the loop.
-- §16: an upgrade must VISIBLY change the 3D space, not just a number in a menu.

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(game.ReplicatedStorage.Shared.Net)

local UpgradeService = {}
local ctx
local world
local Notify: RemoteEvent

local upgradePrompt: ProximityPrompt
local reenterPrompt: ProximityPrompt

local function makePrompt(parent: BasePart, action: string, object: string, hold: number): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.Parent = parent
	return p
end

function UpgradeService.Init(context, builtWorld)
	ctx = context
	world = builtWorld
	Notify = Net.Event("Notify")

	-- Price-free label. ProximityPrompt.ObjectText is replicated, so it can never show a
	-- per-player price from here; PromptController writes the live cost locally per client.
	upgradePrompt = makePrompt(world.UpgradePad, "Upgrade", "UPGRADE ARMORY", 0.4)
	upgradePrompt:SetAttribute("PTKGate", "upgrade")

	reenterPrompt = makePrompt(world.ReenterPad, "Enter", "BREAK INTO THE CASTLE AGAIN", 0.4)
	reenterPrompt:SetAttribute("PTKGate", "reenter")

	upgradePrompt.Triggered:Connect(function(player)
		UpgradeService.BuyWeaponRack(player)
	end)

	reenterPrompt.Triggered:Connect(function(player)
		UpgradeService.ReenterDungeon(player)
	end)
end

-- Per-player cost of the NEXT armory level. Sent in StateUpdate so the client can render an
-- accurate price without the (replicated, shared) prompt label ever going stale. (Bug 4.)
function UpgradeService.GetCost(player: Player): number
	local profile = ctx and ctx.Data.Get(player)
	local level = profile and profile.Castle.WeaponRackLevel or 0
	return GameConfig.Economy.WeaponRackCost * (level + 1)
end

function UpgradeService.BuyWeaponRack(player: Player)
	local profile = ctx.Data.Get(player)
	if not profile then
		return
	end

	local level = profile.Castle.WeaponRackLevel or 0
	if level >= GameConfig.Economy.WeaponRackMaxLevel then
		Notify:FireClient(player, { Text = "ARMORY FULLY UPGRADED", Kind = "warn" })
		return
	end

	local cost = GameConfig.Economy.WeaponRackCost * (level + 1)

	-- SECURITY: TrySpendGold is the only path that can reduce gold, and it returns false
	-- rather than going negative. The grant happens only if it returned true.
	if not ctx.Economy.TrySpendGold(player, cost, "weapon_rack") then
		Notify:FireClient(player, {
			Text = ("NEED %d MORE GOLD"):format(cost - ctx.Economy.GetGold(player)),
			Kind = "warn",
		})
		return
	end

	profile.Castle.WeaponRackLevel = level + 1

	ctx.Analytics.Log(player, "FirstUpgradePurchased", 1, { upgrade = "weapon_rack" })
	ctx.Analytics.Log(player, "UpgradeBought", cost, { upgrade = "weapon_rack", level = tostring(level + 1) })

	-- Visible change in the world, per §16.
	local rack = world.WeaponRack
	rack.Size = Vector3.new(6 + (level + 1) * 1.5, 4 + (level + 1), 1)
	rack.Position = Vector3.new(-8, rack.Size.Y / 2, 388)
	rack.Color = Color3.fromRGB(140 + level * 30, 100 + level * 30, 55)

	Notify:FireClient(player, {
		Text = ("ARMORY LEVEL %d"):format(level + 1),
		Sub = ("+%d DAMAGE"):format(GameConfig.Economy.WeaponRackDamageBonus),
		Kind = "milestone",
	})

	-- §82: the hook into the next goal. Restored now that Captain Bronn exists (M1 Bug 3 note).
	ctx.RunState.SetObjective(player, "THE CAPTAIN HAS BETTER GEAR")
	ctx.Data.Save(player, false)
	ctx.Economy.PushState(player)
end

function UpgradeService.ReenterDungeon(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	root.CFrame = world.CellSpawnCFrame
	ctx.RunState.StartRun(player)
	ctx.Combat.EquipVisual(player)
	Notify:FireClient(player, { Text = "BACK INSIDE", Kind = "milestone" })
end

return UpgradeService
