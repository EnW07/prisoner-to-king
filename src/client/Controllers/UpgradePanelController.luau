--!strict
-- UpgradePanelController.lua
-- The hideout's upgrade panel (J3): what the upgrade does, what it costs, what comes next,
-- one UPGRADE button. Opens when the server says so (the upgrade pad's prompt) and sends
-- UpgradeRequest with no arguments; the server validates and pays or refuses, and the
-- panel re-reads everything from StateUpdate. Failure states give direction, not mood:
-- NEED 46 MORE GOLD, never "insufficient funds" (art §7).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Palette = require(Config:WaitForChild("Palette"))
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local FeedbackController = require(script.Parent:WaitForChild("FeedbackController"))

local UI = GameConfig.UI
local ECON = GameConfig.Economy
local player = Players.LocalPlayer
local UpgradePanelController = {}

local UpgradeRequest: RemoteEvent
local gui: ScreenGui
local dim: TextButton
local panel: CanvasGroup
local panelScale: UIScale
local levelLabel: TextLabel
local effectLabel: TextLabel
local nextLabel: TextLabel
local costLabel: TextLabel
local buttonLabel: TextLabel
local buttonPanel: GuiObject
local isOpen = false

local gold = 0
local level = 0
local cost = 0

local function tween(inst: Instance, time: number, props, style: Enum.EasingStyle?)
	TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad), props):Play()
end

local function refresh()
	local maxed = level >= ECON.WeaponUpgradeMaxLevel
	levelLabel.Text = ("LEVEL %d / %d"):format(level, ECON.WeaponUpgradeMaxLevel)
	effectLabel.Text = ("EVERY WEAPON YOU HOLD: +%d DAMAGE PER LEVEL  (NOW +%d)"):format(
		ECON.WeaponUpgradeDamageBonus,
		level * ECON.WeaponUpgradeDamageBonus
	)
	if maxed then
		nextLabel.Text = "WEAPONS FULLY UPGRADED"
		costLabel.Text = ""
		buttonLabel.Text = "DONE"
		UIStyle.SetDanger(buttonPanel, false)
		return
	end
	nextLabel.Text = ("NEXT: LEVEL %d  ·  +%d DAMAGE ON EVERY WEAPON"):format(
		level + 1,
		(level + 1) * ECON.WeaponUpgradeDamageBonus
	)
	if gold >= cost then
		costLabel.Text = ("%s GOLD"):format(UIStyle.Number(cost))
		costLabel.TextColor3 = Palette.gold
		buttonLabel.Text = "UPGRADE"
		UIStyle.SetDanger(buttonPanel, false)
	else
		costLabel.Text = ("NEED %s MORE GOLD"):format(UIStyle.Number(cost - gold))
		costLabel.TextColor3 = Palette.bleed
		buttonLabel.Text = ("UPGRADE  ·  %s GOLD"):format(UIStyle.Number(cost))
		UIStyle.SetDanger(buttonPanel, true)
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "PTK_Upgrade"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	dim = Instance.new("TextButton")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Palette.pitch
	dim.BackgroundTransparency = 1
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.Parent = gui
	dim.Activated:Connect(function()
		UpgradePanelController.Close()
	end)

	local content
	panel, content = UIStyle.Panel(
		"CanvasGroup",
		"Upgrade",
		gui,
		UDim2.fromScale(0.52, 0.56),
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5)
	)
	UIStyle.Aspect(panel, 1.4)
	panelScale = Instance.new("UIScale")
	panelScale.Parent = panel
	UIStyle.List(content, Enum.FillDirection.Vertical, UDim.new(0.03, 0))

	local title = UIStyle.Text(
		"Title",
		content,
		"UPGRADE YOUR WEAPONS",
		UDim2.fromScale(1, 0.16),
		nil,
		40,
		Palette.gold
	)
	title.LayoutOrder = 1
	levelLabel = UIStyle.Text("Level", content, "", UDim2.fromScale(1, 0.1), nil, 28)
	levelLabel.LayoutOrder = 2
	effectLabel = UIStyle.Text("Effect", content, "", UDim2.fromScale(1, 0.12), nil, 24)
	effectLabel.Font = UIStyle.BODY_FONT
	effectLabel.LayoutOrder = 3
	nextLabel = UIStyle.Text("Next", content, "", UDim2.fromScale(1, 0.12), nil, 24)
	nextLabel.Font = UIStyle.BODY_FONT
	nextLabel.LayoutOrder = 4
	costLabel = UIStyle.Text("Cost", content, "", UDim2.fromScale(1, 0.1), nil, 28, Palette.gold)
	costLabel.LayoutOrder = 5

	local buttonContent
	buttonPanel, buttonContent =
		UIStyle.Panel("Frame", "Buy", content, UDim2.fromScale(0.7, 0.18), UDim2.new())
	buttonPanel.LayoutOrder = 6
	local floor = Instance.new("UISizeConstraint")
	floor.MinSize = Vector2.new(UIStyle.MIN_TOUCH_PX * 2, UIStyle.MIN_TOUCH_PX * 0.8)
	floor.Parent = buttonPanel
	local scale = Instance.new("UIScale")
	scale.Parent = buttonPanel
	buttonLabel = UIStyle.Text("Label", buttonContent, "UPGRADE", UDim2.fromScale(1, 1), nil, 34)
	local hit = Instance.new("TextButton")
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 4
	hit.Parent = buttonPanel
	hit.Activated:Connect(function()
		scale.Scale = UI.PressScale
		tween(scale, UI.PopTime, { Scale = 1 }, Enum.EasingStyle.Back)
		FeedbackController.PlaySound("uiClick", 0.5)
		if level >= ECON.WeaponUpgradeMaxLevel then
			UpgradePanelController.Close()
			return
		end
		UpgradeRequest:FireServer()
	end)

	local closeLabel =
		UIStyle.Text("Hint", content, "TAP OUTSIDE TO CLOSE", UDim2.fromScale(1, 0.07), nil, 18)
	closeLabel.Font = UIStyle.BODY_FONT
	closeLabel.TextTransparency = 0.35
	closeLabel.LayoutOrder = 7
end

function UpgradePanelController.Open()
	if isOpen then
		return
	end
	isOpen = true
	refresh()
	gui.Enabled = true
	dim.BackgroundTransparency = 1
	panel.GroupTransparency = 1
	panelScale.Scale = 0.9
	tween(dim, UI.OverlayInTime, { BackgroundTransparency = UI.OverlayDim })
	tween(panel, UI.OverlayInTime, { GroupTransparency = 0 })
	tween(panelScale, UI.OverlayInTime, { Scale = 1 }, Enum.EasingStyle.Back)
end

function UpgradePanelController.Close()
	if not isOpen then
		return
	end
	isOpen = false
	tween(dim, UI.OverlayOutTime, { BackgroundTransparency = 1 })
	local out = TweenService:Create(panel, TweenInfo.new(UI.OverlayOutTime), { GroupTransparency = 1 })
	out.Completed:Connect(function()
		if not isOpen then
			gui.Enabled = false
		end
	end)
	out:Play()
end

function UpgradePanelController.Init()
	UpgradeRequest = Net.Event("UpgradeRequest")
	build()
	Net.Event("StateUpdate").OnClientEvent:Connect(function(state)
		gold = state.Gold or 0
		level = state.WeaponUpgradeLevel or 0
		cost = state.UpgradeCost or 0
		if isOpen then
			refresh()
		end
		-- Leaving the hideout closes it.
		if isOpen and (state.RunState or "Safe") ~= "Safe" then
			UpgradePanelController.Close()
		end
	end)
	Net.Event("Notify").OnClientEvent:Connect(function(data)
		if data.Kind == "upgradePanel" then
			UpgradePanelController.Open()
		elseif data.Kind == "milestone" and data.Text == "WEAPONS UPGRADED" then
			FeedbackController.PlaySound("purchase", 0.8)
		end
	end)
end

return UpgradePanelController
