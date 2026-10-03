--!strict
-- LootRevealController.lua
-- RIGS_AND_VISUAL_UI_BRIEF step 5 and blueprint §81: when a weapon drops, you SEE it
-- before you own it. The weapon turns in 3D on a card for a beat, then the card flies into
-- the HUD weapon slot as it enters the inventory. A toast is information; this is a feeling.
--
-- Scales with value (§81): a Common is a short beat; Rare and up hold longer. Tapping the
-- card ends it early. EQUIP sends the same validated EquipRequest as the inventory grid.
--
-- PERFORMANCE: one ViewportFrame, alive only while the card is up. Two icons spin at
-- most: this one and the HUD slot.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local WeaponConfig = require(Config:WaitForChild("WeaponConfig"))
local WeaponModel = require(Shared:WaitForChild("WeaponModel"))
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local ViewportIcon = require(script.Parent:WaitForChild("ViewportIcon"))
local UIController = require(script.Parent:WaitForChild("UIController"))

local UI = GameConfig.UI
local LootRevealController = {}

local EquipRequest: RemoteEvent
local current: CanvasGroup? = nil
local bonus = 0 -- latest weapon-upgrade bonus, so the card agrees with the HUD and inventory
local token = 0

-- Fly the card into the weapon slot and remove it: the weapon "goes into the inventory".
local function stow(card: CanvasGroup, myToken: number)
	if token ~= myToken or not card.Parent then
		return
	end
	token += 1
	current = nil
	local gui = UIController.GetGui()
	local slot = UIController.GetWeaponSlot()
	local target = slot.AbsolutePosition + slot.AbsoluteSize / 2 - gui.AbsolutePosition
	local info = TweenInfo.new(UI.RevealFlyTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	-- Switch to pixel positioning for the flight, from wherever the card is now.
	local from = card.AbsolutePosition + card.AbsoluteSize / 2 - gui.AbsolutePosition
	card.Position = UDim2.fromOffset(from.X, from.Y)
	local scale = card:FindFirstChildOfClass("UIScale")
	if scale then
		TweenService:Create(scale, info, { Scale = UI.RevealFlyScale }):Play()
	end
	local fly = TweenService:Create(card, info, {
		Position = UDim2.fromOffset(target.X, target.Y),
		GroupTransparency = 1,
	})
	fly.Completed:Connect(function()
		card:Destroy()
	end)
	fly:Play()
end

local function tapLayer(parent: GuiObject, zIndex: number, onTap: () -> ())
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = zIndex
	hit.Parent = parent
	hit.Activated:Connect(onTap)
end

local function reveal(data)
	local weapon = WeaponConfig.Get(data.WeaponId) :: any
	if not weapon then
		return
	end
	if current then
		current:Destroy() -- a newer drop replaces an older card at once
	end
	token += 1
	local myToken = token

	local rarityColor = WeaponConfig.RarityColors[weapon.Rarity] or UIStyle.TEXT
	local card, content = UIStyle.Panel(
		"CanvasGroup",
		"LootReveal",
		UIController.GetGui(),
		UDim2.fromScale(0.3, 0.5),
		UDim2.fromScale(0.5, 0.45),
		Vector2.new(0.5, 0.5)
	)
	current = card
	UIStyle.Aspect(card, 0.8)
	-- Rarity as confirmation: the outline takes the rarity colour.
	local background = card:FindFirstChild("Background")
	local stroke = background and background:FindFirstChild("Outline") :: UIStroke?
	if stroke then
		stroke.Color = rarityColor
	end
	local scale = Instance.new("UIScale")
	scale.Parent = card
	UIStyle.List(content, Enum.FillDirection.Vertical, UDim.new(0.02, 0))

	local icon = ViewportIcon.Create(content, UDim2.fromScale(1, 0.56))
	icon.LayoutOrder = 1
	ViewportIcon.SetModel(icon, WeaponModel.Build(data.WeaponId))
	ViewportIcon.SetSpinning(icon, true)

	local name =
		UIStyle.Text("Name", content, weapon.Name:upper(), UDim2.fromScale(1, 0.13), nil, 34, rarityColor)
	name.LayoutOrder = 2
	local stats = UIStyle.Text(
		"Stats",
		content,
		("%s · %s"):format(UIStyle.Damage(weapon.Damage, bonus), weapon.Rarity:upper()),
		UDim2.fromScale(1, 0.1),
		nil,
		24
	)
	stats.Font = UIStyle.BODY_FONT
	stats.LayoutOrder = 3

	-- Tap anywhere on the card: done, stow it now.
	tapLayer(card, 3, function()
		stow(card, myToken)
	end)

	if data.Equipped then
		local tag = UIStyle.Text("Tag", content, "EQUIPPED", UDim2.fromScale(1, 0.12), nil, 26)
		tag.LayoutOrder = 4
	else
		-- EQUIP, above the card's own tap layer.
		local button, buttonContent =
			UIStyle.Panel("Frame", "Equip", content, UDim2.fromScale(0.7, 0.14), UDim2.new())
		button.LayoutOrder = 4
		UIStyle.Text("Label", buttonContent, "EQUIP", UDim2.fromScale(1, 1), nil, 28)
		tapLayer(button, 5, function()
			EquipRequest:FireServer(data.WeaponId)
			stow(card, myToken)
		end)
	end

	card.GroupTransparency = 1
	scale.Scale = 0.6
	TweenService:Create(card, TweenInfo.new(UI.RevealInTime), { GroupTransparency = 0 }):Play()
	TweenService:Create(scale, TweenInfo.new(UI.RevealInTime, Enum.EasingStyle.Back), { Scale = 1 }):Play()

	local hold = UI.RevealHold[weapon.Rarity] or UI.RevealHold.Common
	task.delay(UI.RevealInTime + hold, function()
		stow(card, myToken)
	end)
end

function LootRevealController.Init()
	EquipRequest = Net.Event("EquipRequest")
	Net.Event("StateUpdate").OnClientEvent:Connect(function(state)
		bonus = state.DamageBonus or 0
	end)
	Net.Event("Notify").OnClientEvent:Connect(function(data)
		if data.Kind == "weapon" and data.WeaponId then
			reveal(data)
		end
	end)
end

return LootRevealController
