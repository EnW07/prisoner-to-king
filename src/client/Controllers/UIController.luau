--!strict
-- UIController.lua
-- Blueprint §38 + §80, art doc §6. The HUD answers four questions and nothing else:
--   1. What should I do?      → objective banner (top centre)
--   2. What will I get?       → Gold + the UNSECURED bar (top left)
--   3. Am I in danger?        → `bleed` outlines and the bar's pulse
--   4. What am I close to?    → reserved: the near-goal arrives with M2 item 6
--
-- Persistent elements: objective, money panel (gold + unsecured bar), weapon, swing button.
-- Two slots are reserved for M2 (WANTED top right, near-goal bottom left), which makes six,
-- the art §6 maximum. Toasts and full-screen moments are transient.
--
-- Every panel is built through UIStyle, so the whole HUD shares one style line.
-- Everything tweens; nothing snaps, except the unsecured bar on death, which is meant to.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Palette = require(Config:WaitForChild("Palette"))
local WeaponConfig = require(Config:WaitForChild("WeaponConfig"))
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local ViewportIcon = require(script.Parent:WaitForChild("ViewportIcon"))
local WeaponModel = require(Shared:WaitForChild("WeaponModel"))

local UI = GameConfig.UI
local player = Players.LocalPlayer
local UIController = {}

-- Fired when the player taps the weapon slot. InventoryController opens the inventory on it.
UIController.WeaponSlotTapped = Instance.new("BindableEvent")

-- ── Instances ───────────────────────────────────────────────────
local gui: ScreenGui
local overlayGui: ScreenGui

local objectivePanel: CanvasGroup
local objectiveLabel: TextLabel
local objectiveScale: UIScale

local moneyPanel: GuiObject
local goldLabel: TextLabel
local goldScale: UIScale
local barTrack: Frame
local barFill: Frame
local barLabel: TextLabel

local weaponPanel: GuiObject
local weaponIcon: ViewportFrame
local weaponName: TextLabel
local weaponDamage: TextLabel
local weaponScale: UIScale

local toastPanel: CanvasGroup
local toastTitle: TextLabel
local toastSub: TextLabel

local dim: TextButton
local card: CanvasGroup
local cardScale: UIScale
local cardTitle: TextLabel
local cardBody: TextLabel

-- ── Displayed state (what the screen shows, which lags the server on purpose) ──
local shownObjective = ""
local shownWeapon = ""
local shownWeaponId: string? = nil
local shownUnsecured = 0
local inRun = false
local sweeping = false
local pendingGold: number? = nil
local goldValue = Instance.new("NumberValue")
local fillTween: Tween? = nil
local pulseClock = 0

-- ── Small helpers ───────────────────────────────────────────────
local function tween(
	inst: Instance,
	time: number,
	props,
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
): Tween
	local t = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

local function pop(scale: UIScale)
	scale.Scale = UI.PopScale
	tween(scale, UI.PopTime, { Scale = 1 }, Enum.EasingStyle.Back)
end

local function barFraction(amount: number): number
	return math.clamp(amount / UI.UnsecuredBarFullAt, 0, 1)
end

-- ── Build ───────────────────────────────────────────────────────
local function buildHud()
	gui = Instance.new("ScreenGui")
	gui.Name = "PTK_HUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Keep clear of Roblox's own top-bar buttons and phone notches.
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Parent = player:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui
	local rootPad = Instance.new("UIPadding")
	rootPad.PaddingTop = UDim.new(0.02, 0)
	rootPad.PaddingBottom = UDim.new(0.03, 0)
	rootPad.PaddingLeft = UDim.new(0.02, 0)
	rootPad.PaddingRight = UDim.new(0.02, 0)
	rootPad.Parent = root

	-- 1. Objective: top centre, the biggest thing on screen.
	local objContent
	objectivePanel, objContent = UIStyle.Panel(
		"CanvasGroup",
		"Objective",
		root,
		UDim2.fromScale(0.46, 0.085),
		UDim2.fromScale(0.5, 0),
		Vector2.new(0.5, 0)
	)
	objectiveScale = Instance.new("UIScale")
	objectiveScale.Parent = objectivePanel
	objectiveLabel = UIStyle.Text("Label", objContent, "", UDim2.fromScale(1, 1), nil, 40)

	-- 2. Money: Gold (calm, `gold`) above the UNSECURED bar (hot, `bleed`).
	local moneyContent
	moneyPanel, moneyContent = UIStyle.Panel(
		"Frame",
		"Money",
		root,
		UDim2.fromScale(0.26, 0.15),
		UDim2.fromScale(0, 0.1),
		Vector2.zero
	)
	UIStyle.List(moneyContent, Enum.FillDirection.Vertical, UDim.new(0.08, 0))

	goldLabel = UIStyle.Text("Gold", moneyContent, "Gold 0", UDim2.fromScale(1, 0.46), nil, 34, Palette.gold)
	goldLabel.TextXAlignment = Enum.TextXAlignment.Left
	goldLabel.LayoutOrder = 1
	goldScale = Instance.new("UIScale")
	goldScale.Parent = goldLabel

	barTrack = Instance.new("Frame")
	barTrack.Name = "UnsecuredBar"
	barTrack.Size = UDim2.fromScale(1, 0.46)
	barTrack.BackgroundColor3 = Palette.pitch
	barTrack.BorderSizePixel = 0
	barTrack.LayoutOrder = 2
	barTrack.ClipsDescendants = true
	barTrack.Parent = moneyContent
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UIStyle.CORNER
	trackCorner.Parent = barTrack
	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = Palette.bleed
	trackStroke.Thickness = UIStyle.STROKE_PX
	trackStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	trackStroke.Parent = barTrack

	barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = Palette.bleed
	barFill.BorderSizePixel = 0
	barFill.Parent = barTrack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UIStyle.CORNER
	fillCorner.Parent = barFill

	barLabel =
		UIStyle.Text("Label", barTrack, "UNSECURED 0", UDim2.fromScale(0.94, 1), UDim2.fromScale(0.04, 0), 26)
	barLabel.TextXAlignment = Enum.TextXAlignment.Left
	barLabel.ZIndex = 2

	-- 3. Weapon slot: bottom left. The equipped weapon as a slowly turning 3D model, with
	-- name and damage beneath (RIGS_AND_VISUAL_UI_BRIEF §2: show items, not text).
	-- The whole slot is a button: tapping it opens the inventory.
	local weaponContent
	weaponPanel, weaponContent = UIStyle.Panel(
		"Frame",
		"Weapon",
		root,
		UDim2.fromScale(0.15, 0.3),
		UDim2.fromScale(0, 1),
		Vector2.new(0, 1)
	)
	UIStyle.Aspect(weaponPanel, 0.8)
	local slotFloor = Instance.new("UISizeConstraint")
	slotFloor.MinSize = Vector2.new(UIStyle.MIN_TOUCH_PX * 1.4, UIStyle.MIN_TOUCH_PX * 1.75)
	slotFloor.Parent = weaponPanel
	weaponScale = Instance.new("UIScale")
	weaponScale.Parent = weaponPanel
	UIStyle.List(weaponContent, Enum.FillDirection.Vertical, UDim.new(0.02, 0))
	weaponIcon = ViewportIcon.Create(weaponContent, UDim2.fromScale(1, 0.62))
	weaponIcon.LayoutOrder = 1
	ViewportIcon.SetSpinning(weaponIcon, true)
	weaponName = UIStyle.Text("Name", weaponContent, "Fists", UDim2.fromScale(1, 0.2), nil, 26)
	weaponName.LayoutOrder = 2
	weaponDamage = UIStyle.Text("Damage", weaponContent, "", UDim2.fromScale(1, 0.14), nil, 22)
	weaponDamage.Font = UIStyle.BODY_FONT
	weaponDamage.LayoutOrder = 3

	local slotHit = Instance.new("TextButton")
	slotHit.Name = "Hit"
	slotHit.Size = UDim2.fromScale(1, 1)
	slotHit.BackgroundTransparency = 1
	slotHit.Text = ""
	slotHit.ZIndex = 4
	slotHit.Parent = weaponPanel
	slotHit.Activated:Connect(function()
		pop(weaponScale)
		UIController.WeaponSlotTapped:Fire()
	end)

	-- Toast: slides in under the objective. Transient, not one of the six.
	local toastContent
	toastPanel, toastContent = UIStyle.Panel(
		"CanvasGroup",
		"Toast",
		root,
		UDim2.fromScale(0.42, 0.11),
		UDim2.fromScale(0.5, 0.06),
		Vector2.new(0.5, 0)
	)
	toastPanel.GroupTransparency = 1
	toastPanel.Visible = false
	UIStyle.List(toastContent, Enum.FillDirection.Vertical, UDim.new(0.04, 0))
	toastTitle = UIStyle.Text("Title", toastContent, "", UDim2.fromScale(1, 0.58), nil, 38)
	toastTitle.LayoutOrder = 1
	toastSub = UIStyle.Text("Sub", toastContent, "", UDim2.fromScale(1, 0.38), nil, 24)
	toastSub.LayoutOrder = 2
end

local function buildOverlay()
	-- Separate full-bleed gui: the dim covers the whole screen, notch included.
	overlayGui = Instance.new("ScreenGui")
	overlayGui.Name = "PTK_Overlay"
	overlayGui.ResetOnSpawn = false
	overlayGui.IgnoreGuiInset = true
	overlayGui.DisplayOrder = 10
	overlayGui.Enabled = false
	overlayGui.Parent = player:WaitForChild("PlayerGui")

	-- The dim is a button: tapping anywhere dismisses the moment early (§81).
	dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Palette.pitch
	dim.BackgroundTransparency = 1
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.Parent = overlayGui

	local cardContent
	card, cardContent = UIStyle.Panel(
		"CanvasGroup",
		"Card",
		overlayGui,
		UDim2.fromScale(0.5, 0.42),
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5)
	)
	UIStyle.Aspect(card, 1.7)
	cardScale = Instance.new("UIScale")
	cardScale.Parent = card
	UIStyle.List(cardContent, Enum.FillDirection.Vertical, UDim.new(0.04, 0))
	cardTitle = UIStyle.Text("Title", cardContent, "", UDim2.fromScale(1, 0.4), nil, 72)
	cardTitle.LayoutOrder = 1
	cardBody = UIStyle.Text("Body", cardContent, "", UDim2.fromScale(1, 0.52), nil, 30)
	cardBody.Font = UIStyle.BODY_FONT
	cardBody.LayoutOrder = 2
end

-- ── Gold counter ────────────────────────────────────────────────
local function rollGold(target: number)
	if goldValue.Value == target then
		return
	end
	tween(goldValue, UI.GoldRollTime, { Value = target })
end

-- ── The unsecured bar (art §6) ──────────────────────────────────
local function setFill(amount: number)
	if fillTween then
		fillTween:Cancel()
	end
	fillTween = tween(barFill, UI.BarFillTime, { Size = UDim2.fromScale(barFraction(amount), 1) })
end

-- Death: drains in one hard frame. No animation, no easing. Gone.
local function drainHard()
	if fillTween then
		fillTween:Cancel()
		fillTween = nil
	end
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundTransparency = 0
	barLabel.Text = "UNSECURED 0"
	shownUnsecured = 0
end

-- ESCAPE: the fill sweeps across and turns gold, the amount flies into the Gold counter,
-- then the counter rolls up. The player watches risk become safety.
local function secureSweep(amount: number)
	sweeping = true
	if fillTween then
		fillTween:Cancel()
	end
	barFill.BackgroundTransparency = 0
	tween(barFill, UI.SecureSweepTime, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Palette.gold })
	barLabel.Text = ("SECURED %s"):format(UIStyle.Number(amount))

	task.delay(UI.SecureSweepTime, function()
		-- The flying number: a transient label in screen pixels, from bar to Gold counter.
		local from = barTrack.AbsolutePosition
		local to = goldLabel.AbsolutePosition
		local flyer = UIStyle.Text(
			"Flyer",
			gui,
			"+" .. UIStyle.Number(amount),
			UDim2.fromOffset(barTrack.AbsoluteSize.X, barTrack.AbsoluteSize.Y),
			UDim2.fromOffset(from.X, from.Y),
			34,
			Palette.gold
		)
		flyer.TextXAlignment = Enum.TextXAlignment.Left
		flyer.ZIndex = 5
		local fly = tween(flyer, UI.SecureFlyTime, {
			Position = UDim2.fromOffset(to.X, to.Y),
			TextTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		fly.Completed:Connect(function()
			flyer:Destroy()
			pop(goldScale) -- the landing: the counter bumps as the amount arrives
			if pendingGold then
				rollGold(pendingGold)
				pendingGold = nil
			end
			-- Reset the bar for the next run.
			barFill.Size = UDim2.fromScale(0, 1)
			barFill.BackgroundColor3 = Palette.bleed
			barLabel.Text = "UNSECURED 0"
			shownUnsecured = 0
			sweeping = false
			barTrack.Visible = inRun
		end)
	end)
end

-- The pulse IS the tension: faster as the total climbs.
local function pulse(dt: number)
	if sweeping or shownUnsecured <= 0 then
		pulseClock = 0
		if not sweeping then
			barFill.BackgroundTransparency = 0
		end
		return
	end
	local f = barFraction(shownUnsecured)
	local period = UI.PulseSlowPeriod + (UI.PulseFastPeriod - UI.PulseSlowPeriod) * f
	pulseClock = (pulseClock + dt / period) % 1
	local wave = (math.sin(pulseClock * 2 * math.pi) + 1) / 2
	barFill.BackgroundTransparency = UI.PulseDepth * wave
end

-- ── Objective ───────────────────────────────────────────────────
local objectiveToken = 0
local function setObjective(text: string)
	if text == shownObjective then
		return
	end
	shownObjective = text
	objectiveToken += 1
	local token = objectiveToken
	local half = UI.ObjectiveSwapTime / 2
	local out =
		tween(objectivePanel, half, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	out.Completed:Connect(function()
		if token ~= objectiveToken then
			return
		end
		objectiveLabel.Text = text
		objectiveScale.Scale = 0.85
		tween(objectivePanel, half, { GroupTransparency = 0 })
		tween(objectiveScale, half, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
end

-- ── Server events ───────────────────────────────────────────────
function UIController.OnState(state)
	setObjective(state.Objective or "")

	local weaponText = ("%s  ·  %d DMG"):format(state.Weapon or "Fists", state.WeaponDamage or 0)
	if weaponText ~= shownWeapon then
		local first = shownWeapon == ""
		shownWeapon = weaponText
		weaponName.Text = state.Weapon or "Fists"
		weaponDamage.Text = ("%d DMG"):format(state.WeaponDamage or 0)
		if state.WeaponId ~= shownWeaponId then
			shownWeaponId = state.WeaponId
			ViewportIcon.SetModel(weaponIcon, state.WeaponId and WeaponModel.Build(state.WeaponId) or nil)
		end
		if not first then
			pop(weaponScale)
		end
	end

	local unsecured = state.Unsecured or 0
	local runState = state.RunState or "Safe"
	inRun = runState ~= "Safe"
	local gold = state.Gold or 0

	if unsecured == 0 and shownUnsecured > 0 and runState == "Extracted" and not sweeping then
		pendingGold = gold
		secureSweep(shownUnsecured)
	elseif sweeping then
		pendingGold = gold -- applied when the sweep lands
	else
		rollGold(gold)
		barTrack.Visible = inRun
		if unsecured ~= shownUnsecured then
			if unsecured < shownUnsecured then
				drainHard() -- any loss of unsecured gold outside an escape is a hard cut
			end
			shownUnsecured = unsecured
			barLabel.Text = ("UNSECURED %s"):format(UIStyle.Number(unsecured))
			setFill(unsecured)
		end
	end

	-- Danger: carrying loot outside safety outlines the objective and money panel in `bleed`.
	local danger = inRun and runState ~= "Extracted" and unsecured > 0
	UIStyle.SetDanger(objectivePanel, danger)
	UIStyle.SetDanger(moneyPanel, danger)
end

local toastToken = 0
function UIController.OnNotify(data)
	if not data.Text or data.Text == "" then
		return
	end
	toastToken += 1
	local token = toastToken

	-- Colour carries meaning only: rarity on a weapon's name, `bleed` for danger and for
	-- unsecured gold; everything else is the light neutral.
	local rarityColor = data.Rarity and WeaponConfig.RarityColors[data.Rarity]
	local danger = data.Kind == "alarm"
	toastTitle.Text = data.Text
	toastTitle.TextColor3 = rarityColor or ((danger or data.Kind == "gold") and Palette.bleed) or UIStyle.TEXT
	toastSub.Text = data.Sub or ""
	toastSub.Visible = data.Sub ~= nil
	UIStyle.SetDanger(toastPanel, danger)

	toastPanel.Visible = true
	toastPanel.Position = UDim2.fromScale(0.5, 0.06)
	toastPanel.GroupTransparency = 1
	tween(
		toastPanel,
		UI.ToastInTime,
		{ Position = UDim2.fromScale(0.5, 0.11), GroupTransparency = 0 },
		Enum.EasingStyle.Back
	)

	task.delay(UI.ToastInTime + UI.ToastHoldTime, function()
		if token ~= toastToken then
			return
		end
		local out = tween(
			toastPanel,
			UI.ToastOutTime,
			{ Position = UDim2.fromScale(0.5, 0.06), GroupTransparency = 1 },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		out.Completed:Connect(function()
			if token == toastToken then
				toastPanel.Visible = false
			end
		end)
	end)
end

local overlayToken = 0
local function hideOverlay(token: number)
	if token ~= overlayToken or not overlayGui.Enabled then
		return
	end
	overlayToken += 1
	tween(dim, UI.OverlayOutTime, { BackgroundTransparency = 1 })
	local out = tween(card, UI.OverlayOutTime, { GroupTransparency = 1 })
	out.Completed:Connect(function()
		overlayGui.Enabled = false
	end)
end

function UIController.OnScreenEvent(data)
	local escaped = data.Kind == "escaped"
	if not escaped then
		drainHard() -- CAPTURED: the bar is already empty before the card lands
	end

	overlayToken += 1
	local token = overlayToken
	cardTitle.Text = data.Title or ""
	cardTitle.TextColor3 = if escaped then Palette.escape else Palette.bleed
	cardBody.Text = table.concat(data.Lines or {}, "\n")
	UIStyle.SetDanger(card, not escaped)

	overlayGui.Enabled = true
	dim.BackgroundTransparency = 1
	card.GroupTransparency = 1
	cardScale.Scale = 0.8
	tween(dim, UI.OverlayInTime, { BackgroundTransparency = UI.OverlayDim })
	tween(card, UI.OverlayInTime, { GroupTransparency = 0 })
	tween(cardScale, UI.OverlayInTime, { Scale = 1 }, Enum.EasingStyle.Back)

	task.delay(UI.OverlayInTime + UI.OverlayHoldTime, function()
		hideOverlay(token)
	end)
end

function UIController.Init()
	buildHud()
	buildOverlay()

	goldValue.Changed:Connect(function(value)
		goldLabel.Text = "Gold " .. UIStyle.Number(value)
	end)
	dim.Activated:Connect(function()
		hideOverlay(overlayToken)
	end)
	RunService.RenderStepped:Connect(pulse)

	Net.Event("StateUpdate").OnClientEvent:Connect(UIController.OnState)
	Net.Event("Notify").OnClientEvent:Connect(UIController.OnNotify)
	Net.Event("ScreenEvent").OnClientEvent:Connect(UIController.OnScreenEvent)
end

return UIController
