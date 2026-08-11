--!strict
-- UIController.lua
-- Blueprint §38 + §80. The HUD answers four questions and nothing else:
--   1. What should I do?      → objective banner
--   2. What will I get?       → unsecured gold
--   3. Am I in danger?        → run state colour
--   4. What am I close to?    → gold vs next upgrade cost
--
-- Built entirely in code so there is nothing to assemble by hand in StarterGui, and so
-- text is centralised for localisation later (§73).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer
local UIController = {}

local gui: ScreenGui
local objectiveLabel: TextLabel
local goldLabel: TextLabel
local unsecuredLabel: TextLabel
local weaponLabel: TextLabel
local toastLabel: TextLabel
local toastSubLabel: TextLabel
local overlay: Frame
local overlayTitle: TextLabel
local overlayBody: TextLabel

local RARITY_COLORS = {
	Common = Color3.fromRGB(215, 215, 215),
	Uncommon = Color3.fromRGB(90, 210, 110),
	Rare = Color3.fromRGB(80, 150, 255),
	Epic = Color3.fromRGB(180, 100, 255),
	Legendary = Color3.fromRGB(255, 180, 60),
	Mythic = Color3.fromRGB(255, 70, 70),
}

local function label(parent: Instance, name: string, size: UDim2, pos: UDim2, text: string, textSize: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color
	l.TextSize = textSize
	l.Font = Enum.Font.GothamBold
	l.TextStrokeTransparency = 0.35
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.Parent = parent
	return l
end

function UIController.Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "PTK_HUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	-- ── Objective (top centre, biggest thing on screen) ────────
	objectiveLabel = label(gui, "Objective", UDim2.new(1, -40, 0, 44), UDim2.new(0, 20, 0, 44),
		"", 30, Color3.fromRGB(255, 255, 255))
	objectiveLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- ── Currency (top left) ────────────────────────────────────
	goldLabel = label(gui, "Gold", UDim2.new(0, 320, 0, 30), UDim2.new(0, 20, 0, 100),
		"Gold 0", 24, Color3.fromRGB(255, 205, 80))
	goldLabel.TextXAlignment = Enum.TextXAlignment.Left

	unsecuredLabel = label(gui, "Unsecured", UDim2.new(0, 360, 0, 28), UDim2.new(0, 20, 0, 132),
		"", 22, Color3.fromRGB(255, 120, 90))
	unsecuredLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- ── Weapon (bottom left) ───────────────────────────────────
	weaponLabel = label(gui, "Weapon", UDim2.new(0, 400, 0, 28), UDim2.new(0, 20, 1, -56),
		"Fists", 22, Color3.fromRGB(220, 220, 230))
	weaponLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- ── Toast (centre) ─────────────────────────────────────────
	toastLabel = label(gui, "Toast", UDim2.new(1, -60, 0, 44), UDim2.new(0, 30, 0.34, 0),
		"", 34, Color3.fromRGB(255, 255, 255))
	toastLabel.TextTransparency = 1
	toastSubLabel = label(gui, "ToastSub", UDim2.new(1, -60, 0, 30), UDim2.new(0, 30, 0.34, 46),
		"", 24, Color3.fromRGB(200, 255, 200))
	toastSubLabel.TextTransparency = 1

	-- ── Full-screen moment (ESCAPED / CAPTURED) ────────────────
	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.Visible = false
	overlay.ZIndex = 10
	overlay.Parent = gui

	overlayTitle = label(overlay, "Title", UDim2.new(1, 0, 0, 70), UDim2.new(0, 0, 0.32, 0), "", 62, Color3.new(1, 1, 1))
	overlayTitle.ZIndex = 11
	overlayBody = label(overlay, "Body", UDim2.new(1, 0, 0, 100), UDim2.new(0, 0, 0.32, 80), "", 26, Color3.fromRGB(230, 230, 230))
	overlayBody.ZIndex = 11

	Net.Event("StateUpdate").OnClientEvent:Connect(UIController.OnState)
	Net.Event("Notify").OnClientEvent:Connect(UIController.OnNotify)
	Net.Event("ScreenEvent").OnClientEvent:Connect(UIController.OnScreenEvent)
end

function UIController.OnState(state)
	objectiveLabel.Text = state.Objective or ""
	goldLabel.Text = ("Gold %d"):format(state.Gold or 0)
	weaponLabel.Text = ("%s   ·   %d DMG"):format(state.Weapon or "Fists", state.WeaponDamage or 0)

	if (state.Unsecured or 0) > 0 then
		unsecuredLabel.Text = ("UNSECURED: %d"):format(state.Unsecured)
		unsecuredLabel.TextColor3 = Color3.fromRGB(255, 120, 90)
	else
		unsecuredLabel.Text = ""
	end

	-- The objective turns red while carrying loot in danger. (§80: "Am I in danger?")
	if state.RunState == "Safe" then
		objectiveLabel.TextColor3 = Color3.fromRGB(160, 255, 190)
	elseif (state.Unsecured or 0) > 0 then
		objectiveLabel.TextColor3 = Color3.fromRGB(255, 190, 90)
	else
		objectiveLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
end

local toastToken = 0
function UIController.OnNotify(data)
	if not data.Text or data.Text == "" then return end

	toastToken += 1
	local token = toastToken

	toastLabel.Text = data.Text
	toastSubLabel.Text = data.Sub or ""
	toastLabel.TextColor3 = (data.Rarity and RARITY_COLORS[data.Rarity])
		or (data.Kind == "warn" and Color3.fromRGB(255, 120, 120))
		or (data.Kind == "gold" and Color3.fromRGB(255, 205, 80))
		or (data.Kind == "alarm" and Color3.fromRGB(255, 90, 90))
		or Color3.fromRGB(255, 255, 255)

	toastLabel.TextTransparency = 0
	toastSubLabel.TextTransparency = if data.Sub then 0 else 1

	task.delay(1.6, function()
		if token ~= toastToken then return end
		TweenService:Create(toastLabel, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(toastSubLabel, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
	end)
end

function UIController.OnScreenEvent(data)
	overlay.Visible = true
	overlayTitle.Text = data.Title or ""
	overlayTitle.TextColor3 = if data.Kind == "escaped"
		then Color3.fromRGB(120, 255, 160)
		else Color3.fromRGB(255, 110, 110)
	overlayBody.Text = table.concat(data.Lines or {}, "\n")

	overlay.BackgroundTransparency = 1
	TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.35 }):Play()

	-- §81: never trap the player inside a reward animation.
	task.delay(2.4, function()
		local fade = TweenService:Create(overlay, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		overlay.Visible = false
	end)
end

return UIController
