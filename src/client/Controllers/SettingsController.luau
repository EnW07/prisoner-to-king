--!strict
-- SettingsController.lua
-- The settings panel (J2, §40): music and SFX volume, reduced screen shake, camera
-- sensitivity, a graphics preset. A gear in the top-right opens it. Values live in
-- ClientSettings for this session; everything that shakes, plays or glows reads them.
--
-- Sliders are built from frames (no images): drag anywhere on the track. Toggles are
-- buttons that say ON or OFF in words, never by colour alone.
--
-- Rule 8: the graphics preset first changes OUR effects (light shafts, torch flicker
-- rate), which always works, and then tries the engine quality level inside a pcall.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Palette = require(Config:WaitForChild("Palette"))
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local UIController = require(script.Parent:WaitForChild("UIController"))
local ClientSettings = require(script.Parent:WaitForChild("ClientSettings"))
local FeedbackController = require(script.Parent:WaitForChild("FeedbackController"))

local UI = GameConfig.UI
local player = Players.LocalPlayer
local SettingsController = {}

local gui: ScreenGui
local dim: TextButton
local panel: CanvasGroup
local panelScale: UIScale
local isOpen = false

local function tween(inst: Instance, time: number, props, style: Enum.EasingStyle?)
	TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad), props):Play()
end

local function row(parent: Instance, order: number, title: string): Frame
	local r = Instance.new("Frame")
	r.Name = title
	r.Size = UDim2.fromScale(1, 0.14)
	r.BackgroundTransparency = 1
	r.LayoutOrder = order
	r.Parent = parent
	local label = UIStyle.Text("Title", r, title, UDim2.fromScale(0.45, 1), nil, 26)
	label.TextXAlignment = Enum.TextXAlignment.Left
	return r
end

-- A slider from 0..1 (mapped by the caller). Drag anywhere on the track.
local function slider(parent: Frame, value: number, onChange: (number) -> ())
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.fromScale(1, 0.5)
	track.Size = UDim2.fromScale(0.5, 0.5)
	track.BackgroundColor3 = Palette.pitch
	track.BorderSizePixel = 0
	track.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = track
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.stone
	stroke.Thickness = UIStyle.STROKE_PX
	stroke.Parent = track
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(value, 1)
	fill.BackgroundColor3 = UIStyle.TEXT
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = track
	fillCorner:Clone().Parent = fill
	local readout = UIStyle.Text("Value", track, ("%d%%"):format(value * 100), UDim2.fromScale(1, 1), nil, 20)
	readout.ZIndex = 2

	local dragging = false
	local function setFromX(x: number)
		local v = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		fill.Size = UDim2.fromScale(v, 1)
		readout.Text = ("%d%%"):format(v * 100)
		onChange(v)
	end
	track.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)
end

-- A toggle that says its state in words.
local function toggle(parent: Frame, labels: { string }, value: boolean, onChange: (boolean) -> ())
	local button, content = UIStyle.Panel(
		"Frame",
		"Toggle",
		parent,
		UDim2.fromScale(0.5, 0.8),
		UDim2.fromScale(1, 0.5),
		Vector2.new(1, 0.5)
	)
	local text =
		UIStyle.Text("Label", content, if value then labels[1] else labels[2], UDim2.fromScale(1, 1), nil, 24)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local hit = Instance.new("TextButton")
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 4
	hit.Parent = button
	hit.Activated:Connect(function()
		value = not value
		text.Text = if value then labels[1] else labels[2]
		scale.Scale = UI.PressScale
		tween(scale, UI.PopTime, { Scale = 1 }, Enum.EasingStyle.Back)
		FeedbackController.PlaySound("uiClick", 0.5)
		onChange(value)
	end)
end

local function applyGraphics(low: boolean)
	ClientSettings.Set("GraphicsLow", low)
	-- Our effects first (always works): WorldFXController listens to ClientSettings.
	-- Then the engine's quality level, which may or may not be ours to set.
	pcall(function()
		local settings = UserSettings():GetService("UserGameSettings")
		settings.SavedQualityLevel = if low
			then Enum.SavedQualitySetting.QualityLevel2
			else Enum.SavedQualitySetting.Automatic
	end)
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "PTK_Settings"
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
		SettingsController.Close()
	end)

	local content
	panel, content = UIStyle.Panel(
		"CanvasGroup",
		"Settings",
		gui,
		UDim2.fromScale(0.5, 0.62),
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5)
	)
	UIStyle.Aspect(panel, 1.3)
	panelScale = Instance.new("UIScale")
	panelScale.Parent = panel
	UIStyle.List(content, Enum.FillDirection.Vertical, UDim.new(0.02, 0))

	local title = UIStyle.Text("Title", content, "SETTINGS", UDim2.fromScale(1, 0.14), nil, 40)
	title.LayoutOrder = 0

	slider(row(content, 1, "MUSIC"), ClientSettings.Get("MusicVolume"), function(v)
		ClientSettings.Set("MusicVolume", v)
	end)
	slider(row(content, 2, "SOUND"), ClientSettings.Get("SfxVolume"), function(v)
		ClientSettings.Set("SfxVolume", v)
	end)
	toggle(
		row(content, 3, "SCREEN SHAKE"),
		{ "FULL", "REDUCED" },
		not ClientSettings.Get("ReducedShake"),
		function(full)
			ClientSettings.Set("ReducedShake", not full)
		end
	)
	-- Sensitivity 0.3x .. 2x, shown as a slider over that range.
	local sens = ClientSettings.Get("CameraSensitivity") or 1
	slider(row(content, 4, "CAMERA"), (sens - 0.3) / 1.7, function(v)
		local s = 0.3 + v * 1.7
		ClientSettings.Set("CameraSensitivity", s)
		pcall(function()
			UserInputService.MouseDeltaSensitivity = s
		end)
	end)
	toggle(
		row(content, 5, "GRAPHICS"),
		{ "HIGH", "LOW" },
		not ClientSettings.Get("GraphicsLow"),
		function(high)
			applyGraphics(not high)
		end
	)

	-- Close: a full touch target at the bottom.
	local closeBtn, closeContent =
		UIStyle.Panel("Frame", "Close", content, UDim2.fromScale(0.4, 0.12), UDim2.new())
	closeBtn.LayoutOrder = 9
	UIStyle.Text("Label", closeContent, "DONE", UDim2.fromScale(1, 1), nil, 28)
	local closeHit = Instance.new("TextButton")
	closeHit.Size = UDim2.fromScale(1, 1)
	closeHit.BackgroundTransparency = 1
	closeHit.Text = ""
	closeHit.ZIndex = 4
	closeHit.Parent = closeBtn
	closeHit.Activated:Connect(function()
		SettingsController.Close()
	end)

	-- The gear: top-right of the HUD, a small square, part of the WANTED cluster.
	local hud = UIController.GetGui()
	local root = hud:FindFirstChild("Root") :: Frame
	local gear, gearContent = UIStyle.Panel(
		"Frame",
		"SettingsGear",
		root,
		UDim2.fromScale(UI.GearSize, UI.GearSize),
		UDim2.fromScale(1, 0),
		Vector2.new(1, 0)
	)
	UIStyle.Aspect(gear, 1)
	local floor = Instance.new("UISizeConstraint")
	floor.MinSize = Vector2.new(UIStyle.MIN_TOUCH_PX * 0.5, UIStyle.MIN_TOUCH_PX * 0.5)
	floor.Parent = gear
	UIStyle.Text("Label", gearContent, "MENU", UDim2.fromScale(1, 1), nil, 22)
	local gearHit = Instance.new("TextButton")
	gearHit.Size = UDim2.fromScale(1, 1)
	gearHit.BackgroundTransparency = 1
	gearHit.Text = ""
	gearHit.ZIndex = 4
	gearHit.Parent = gear
	gearHit.Activated:Connect(function()
		FeedbackController.PlaySound("uiClick", 0.5)
		if isOpen then
			SettingsController.Close()
		else
			SettingsController.Open()
		end
	end)
end

function SettingsController.Open()
	if isOpen then
		return
	end
	isOpen = true
	gui.Enabled = true
	dim.BackgroundTransparency = 1
	panel.GroupTransparency = 1
	panelScale.Scale = 0.9
	tween(dim, UI.OverlayInTime, { BackgroundTransparency = UI.OverlayDim })
	tween(panel, UI.OverlayInTime, { GroupTransparency = 0 })
	tween(panelScale, UI.OverlayInTime, { Scale = 1 }, Enum.EasingStyle.Back)
end

function SettingsController.Close()
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

function SettingsController.Init()
	build()
end

return SettingsController
