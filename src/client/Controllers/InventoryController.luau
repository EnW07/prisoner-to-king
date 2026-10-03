--!strict
-- InventoryController.lua
-- M2 item 4 + RIGS_AND_VISUAL_UI_BRIEF step 4: the inventory as a grid of real 3D items.
--
-- Opens when the HUD weapon slot is tapped. One ViewportFrame per owned weapon; tap a slot
-- to EQUIP it. The client only ASKS (EquipRequest with an id). The server checks ownership
-- and answers through StateUpdate, which is what moves the EQUIPPED tag.
--
-- Rarity reads in art §4's order: silhouette first (each class has its own model shape),
-- colour last, as confirmation. Here that's the slot's outline (UIStroke) and a background
-- gradient running from the rarity colour into `pitch`. The rarity is also written out.
--
-- PERFORMANCE: icons render once and stay still, except the equipped weapon's, which turns
-- slowly. The grid exists only while open.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Palette = require(Config:WaitForChild("Palette"))
local WeaponConfig = require(Config:WaitForChild("WeaponConfig"))
local WeaponModel = require(Shared:WaitForChild("WeaponModel"))
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local ViewportIcon = require(script.Parent:WaitForChild("ViewportIcon"))
local UIController = require(script.Parent:WaitForChild("UIController"))

local UI = GameConfig.UI
local player = Players.LocalPlayer
local InventoryController = {}

local EquipRequest: RemoteEvent
local gui: ScreenGui
local dim: TextButton
local panel: CanvasGroup
local panelScale: UIScale
local grid: Frame

local owned: { string } = {}
local equipped: string? = nil
local bonus = 0 -- weapon-upgrade bonus: applies to whichever weapon is equipped
local isOpen = false
local sortButtonLabel: TextLabel

-- Sorting (J3): three orders, cycled by one button.
local SORTS = { "DAMAGE", "RARITY", "CLASS" }
local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 }
local sortIndex = 1

-- Weapons worth showing (fists aren't an item), in the chosen order.
local function sortedOwned(): { string }
	local list = {}
	for _, id in owned do
		local w = WeaponConfig.Get(id)
		if w and w.WeaponClass ~= "Unarmed" then
			table.insert(list, id)
		end
	end
	local mode = SORTS[sortIndex]
	table.sort(list, function(a, b)
		local wa, wb = WeaponConfig.Get(a) :: any, WeaponConfig.Get(b) :: any
		if mode == "RARITY" then
			local ra, rb = RARITY_RANK[wa.Rarity] or 0, RARITY_RANK[wb.Rarity] or 0
			if ra ~= rb then
				return ra > rb
			end
		elseif mode == "CLASS" then
			if wa.WeaponClass ~= wb.WeaponClass then
				return wa.WeaponClass < wb.WeaponClass
			end
		end
		return wa.Damage > wb.Damage
	end)
	return list
end

-- How this weapon compares with the one in your hand, in words and a signed number.
local function comparison(weapon): string
	local current = equipped and WeaponConfig.Get(equipped) :: any
	if not current or current.WeaponClass == "Unarmed" then
		return "TAP TO EQUIP"
	end
	local delta = weapon.Damage - current.Damage
	local parts = {}
	if delta ~= 0 then
		table.insert(parts, ("%+d DMG"):format(delta))
	else
		table.insert(parts, "SAME DMG")
	end
	if weapon.AttackCooldown < current.AttackCooldown - 0.01 then
		table.insert(parts, "FASTER")
	elseif weapon.AttackCooldown > current.AttackCooldown + 0.01 then
		table.insert(parts, "SLOWER")
	end
	if weapon.Reach > current.Reach + 0.5 then
		table.insert(parts, "LONGER")
	end
	return table.concat(parts, " · ")
end

local function rarityTint(slot: GuiObject, rarity: string)
	local color = WeaponConfig.RarityColors[rarity] or Palette.stone
	local background = slot:FindFirstChild("Background")
	if not background then
		return
	end
	local stroke = background:FindFirstChild("Outline") :: UIStroke?
	if stroke then
		stroke.Color = color
	end
	local gradient = background:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(color:Lerp(Palette.pitch, UI.RarityGradientDarken), Palette.pitch)
	end
end

local function buildSlot(id: string, order: number)
	local weapon = WeaponConfig.Get(id) :: any
	local slot, content = UIStyle.Panel("Frame", id, grid, UDim2.new(), UDim2.new())
	slot.LayoutOrder = order
	rarityTint(slot, weapon.Rarity)
	UIStyle.List(content, Enum.FillDirection.Vertical, UDim.new(0.02, 0))

	local icon = ViewportIcon.Create(content, UDim2.fromScale(1, 0.46))
	icon.LayoutOrder = 1
	ViewportIcon.SetModel(icon, WeaponModel.Build(id))
	ViewportIcon.SetSpinning(icon, id == equipped)

	local name = UIStyle.Text("Name", content, weapon.Name, UDim2.fromScale(1, 0.16), nil, 24)
	name.LayoutOrder = 2
	local stats = UIStyle.Text(
		"Stats",
		content,
		-- What this weapon WOULD do if equipped: its own damage plus your upgrade bonus.
		("%s · %s"):format(UIStyle.Damage(weapon.Damage, bonus), weapon.Rarity:upper()),
		UDim2.fromScale(1, 0.12),
		nil,
		20
	)
	stats.Font = UIStyle.BODY_FONT
	stats.LayoutOrder = 3
	-- The class identity in words (J3): what it DOES, not just its number.
	local identity = UIStyle.Text(
		"Identity",
		content,
		(WeaponConfig :: any).ClassIdentity[weapon.WeaponClass] or "",
		UDim2.fromScale(1, 0.1),
		nil,
		18
	)
	identity.Font = UIStyle.BODY_FONT
	identity.LayoutOrder = 4
	local tag = UIStyle.Text(
		"Tag",
		content,
		if id == equipped then "EQUIPPED" else comparison(weapon),
		UDim2.fromScale(1, 0.12),
		nil,
		20,
		if id == equipped then Palette.gold else UIStyle.TEXT
	)
	tag.Font = UIStyle.BODY_FONT
	tag.LayoutOrder = 5

	local scale = Instance.new("UIScale")
	scale.Parent = slot
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 4
	hit.Parent = slot
	hit.Activated:Connect(function()
		scale.Scale = UI.PressScale
		TweenService:Create(scale, TweenInfo.new(UI.PopTime, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		if id ~= equipped then
			EquipRequest:FireServer(id)
		end
	end)
end

local function rebuild()
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy() -- ViewportIcon cleans itself up on Destroying
		end
	end
	for i, id in sortedOwned() do
		buildSlot(id, i)
	end
end

local function close()
	if not isOpen then
		return
	end
	isOpen = false
	TweenService:Create(dim, TweenInfo.new(UI.OverlayOutTime), { BackgroundTransparency = 1 }):Play()
	local out = TweenService:Create(panel, TweenInfo.new(UI.OverlayOutTime), { GroupTransparency = 1 })
	out.Completed:Connect(function()
		if not isOpen then
			gui.Enabled = false
			for _, child in grid:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy() -- don't keep viewports alive while hidden
				end
			end
		end
	end)
	out:Play()
end

local function open()
	if isOpen then
		close()
		return
	end
	isOpen = true
	rebuild()
	gui.Enabled = true
	dim.BackgroundTransparency = 1
	panel.GroupTransparency = 1
	panelScale.Scale = 0.85
	TweenService:Create(dim, TweenInfo.new(UI.OverlayInTime), { BackgroundTransparency = UI.OverlayDim })
		:Play()
	TweenService:Create(panel, TweenInfo.new(UI.OverlayInTime), { GroupTransparency = 0 }):Play()
	TweenService:Create(panelScale, TweenInfo.new(UI.OverlayInTime, Enum.EasingStyle.Back), { Scale = 1 })
		:Play()
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "PTK_Inventory"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Tapping outside the panel closes it.
	dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Palette.pitch
	dim.BackgroundTransparency = 1
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.Parent = gui
	dim.Activated:Connect(close)

	local content
	panel, content = UIStyle.Panel(
		"CanvasGroup",
		"Inventory",
		gui,
		UDim2.fromScale(0.7, 0.7),
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5)
	)
	UIStyle.Aspect(panel, 1.5)
	panelScale = Instance.new("UIScale")
	panelScale.Parent = panel

	local title = UIStyle.Text("Title", content, "YOUR WEAPONS", UDim2.fromScale(0.5, 0.12), nil, 40)
	title.TextXAlignment = Enum.TextXAlignment.Left

	-- SORT: one button that cycles the order (J3).
	local sortBtn, sortContent = UIStyle.Panel(
		"Frame",
		"Sort",
		content,
		UDim2.fromScale(0.3, 0.12),
		UDim2.fromScale(0.84, 0),
		Vector2.new(1, 0)
	)
	sortButtonLabel = UIStyle.Text("Label", sortContent, "SORT: DAMAGE", UDim2.fromScale(1, 1), nil, 22)
	sortButtonLabel.Font = UIStyle.BODY_FONT
	local sortScale = Instance.new("UIScale")
	sortScale.Parent = sortBtn
	local sortHit = Instance.new("TextButton")
	sortHit.Size = UDim2.fromScale(1, 1)
	sortHit.BackgroundTransparency = 1
	sortHit.Text = ""
	sortHit.ZIndex = 4
	sortHit.Parent = sortBtn
	sortHit.Activated:Connect(function()
		sortIndex = sortIndex % #SORTS + 1
		sortButtonLabel.Text = "SORT: " .. SORTS[sortIndex]
		sortScale.Scale = UI.PressScale
		TweenService:Create(sortScale, TweenInfo.new(UI.PopTime, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		rebuild()
	end)

	-- Close button: top right, a full touch target.
	local closeBtn, closeContent = UIStyle.Panel(
		"Frame",
		"Close",
		content,
		UDim2.fromScale(0.12, 0.14),
		UDim2.fromScale(1, 0),
		Vector2.new(1, 0)
	)
	UIStyle.Aspect(closeBtn, 1)
	local floor = Instance.new("UISizeConstraint")
	floor.MinSize = Vector2.new(UIStyle.MIN_TOUCH_PX * 0.6, UIStyle.MIN_TOUCH_PX * 0.6)
	floor.Parent = closeBtn
	UIStyle.Text("X", closeContent, "X", UDim2.fromScale(1, 1), nil, 32)
	local closeHit = Instance.new("TextButton")
	closeHit.Size = UDim2.fromScale(1, 1)
	closeHit.BackgroundTransparency = 1
	closeHit.Text = ""
	closeHit.ZIndex = 4
	closeHit.Parent = closeBtn
	closeHit.Activated:Connect(close)

	grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromScale(0, 0.17)
	grid.Size = UDim2.fromScale(1, 0.83)
	grid.BackgroundTransparency = 1
	grid.Parent = content
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromScale(UI.InventoryCellWidth, UI.InventoryCellHeight)
	layout.CellPadding = UDim2.fromScale(0.03, 0.04)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = grid
end

function InventoryController.Init()
	EquipRequest = Net.Event("EquipRequest")
	build()
	UIController.WeaponSlotTapped.Event:Connect(open)

	Net.Event("StateUpdate").OnClientEvent:Connect(function(state)
		local changed = state.WeaponId ~= equipped
			or #(state.OwnedWeapons or {}) ~= #owned
			or (state.DamageBonus or 0) ~= bonus
		owned = state.OwnedWeapons or owned
		equipped = state.WeaponId
		bonus = state.DamageBonus or 0
		if isOpen and changed then
			rebuild()
		end
	end)
end

return InventoryController
