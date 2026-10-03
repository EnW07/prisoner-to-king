--!strict
-- HealthController.lua
-- The player's health as a styled bar (J2), replacing Roblox's default. Damage flashes
-- the bar and leaves a trailing ghost of what was lost; low health pulses the bar and
-- brings up a `bleed` vignette at the screen edges (K1). Nothing here is authoritative:
-- it reads the local Humanoid, which the server owns.
--
-- Colour carries meaning only (art §3): health is `ember` (warmth, safety-adjacent) and
-- turns `bleed` when low, which is danger. The number is always written out too.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Palette = require(Config:WaitForChild("Palette"))
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local UIController = require(script.Parent:WaitForChild("UIController"))

local UI = GameConfig.UI
local player = Players.LocalPlayer
local HealthController = {}

local panel: GuiObject
local track: Frame
local fill: Frame
local ghost: Frame
local flash: Frame
local label: TextLabel
local vignette: { Frame } = {}
local vignetteGui: ScreenGui

local humanoid: Humanoid? = nil
local shownFraction = 1
local lowClock = 0

local function tween(
	inst: Instance,
	time: number,
	props,
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
)
	local t = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

local function build()
	local gui = UIController.GetGui()
	local root = gui:FindFirstChild("Root") :: Frame
	local content
	panel, content = UIStyle.Panel(
		"Frame",
		"Health",
		root,
		UDim2.fromScale(UI.HealthWidth, UI.HealthHeight),
		UDim2.fromScale(UI.HealthX, 1),
		Vector2.new(0, 1)
	)

	track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.fromScale(1, 1)
	track.BackgroundColor3 = Palette.pitch
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = content
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UIStyle.CORNER
	corner.Parent = track

	-- The ghost: what you just lost, lagging behind the real fill.
	ghost = Instance.new("Frame")
	ghost.Name = "Ghost"
	ghost.Size = UDim2.fromScale(1, 1)
	ghost.BackgroundColor3 = UIStyle.TEXT
	ghost.BackgroundTransparency = 0.5
	ghost.BorderSizePixel = 0
	ghost.Parent = track
	local ghostCorner = Instance.new("UICorner")
	ghostCorner.CornerRadius = UIStyle.CORNER
	ghostCorner.Parent = ghost

	fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Palette.ember
	fill.BorderSizePixel = 0
	fill.ZIndex = 2
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UIStyle.CORNER
	fillCorner.Parent = fill

	flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = UIStyle.TEXT
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 3
	flash.Parent = track

	label = UIStyle.Text("Label", track, "100 / 100", UDim2.fromScale(0.92, 1), UDim2.fromScale(0.04, 0), 24)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 4

	-- The vignette (K1): four edge frames fading from `bleed` to nothing, pulsed when low.
	vignetteGui = Instance.new("ScreenGui")
	vignetteGui.Name = "PTK_Vignette"
	vignetteGui.ResetOnSpawn = false
	vignetteGui.IgnoreGuiInset = true
	vignetteGui.DisplayOrder = 2
	vignetteGui.Parent = player:WaitForChild("PlayerGui")
	local edges = {
		{ UDim2.fromScale(1, UI.VignetteDepth), UDim2.fromScale(0, 0), 90 }, -- top
		{ UDim2.fromScale(1, UI.VignetteDepth), UDim2.fromScale(0, 1 - UI.VignetteDepth), 270 }, -- bottom
		{ UDim2.fromScale(UI.VignetteDepth, 1), UDim2.fromScale(0, 0), 0 }, -- left
		{ UDim2.fromScale(UI.VignetteDepth, 1), UDim2.fromScale(1 - UI.VignetteDepth, 0), 180 }, -- right
	}
	for _, e in edges do
		local f = Instance.new("Frame")
		f.Size = e[1]
		f.Position = e[2]
		f.BackgroundColor3 = Palette.bleed
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Parent = vignetteGui
		local g = Instance.new("UIGradient")
		g.Rotation = e[3]
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		table.insert(vignette, f)
	end
end

local function setVignette(transparency: number)
	for _, f in vignette do
		f.BackgroundTransparency = transparency
	end
end

local function refresh(animated: boolean)
	local h = humanoid
	if not h then
		return
	end
	local fraction = if h.MaxHealth > 0 then math.clamp(h.Health / h.MaxHealth, 0, 1) else 0
	label.Text = ("%d / %d"):format(math.ceil(h.Health), h.MaxHealth)
	local low = fraction <= UI.HealthLowFraction
	fill.BackgroundColor3 = if low then Palette.bleed else Palette.ember
	UIStyle.SetDanger(panel, low)

	if not animated then
		fill.Size = UDim2.fromScale(fraction, 1)
		ghost.Size = UDim2.fromScale(fraction, 1)
		shownFraction = fraction
		return
	end
	if fraction < shownFraction then
		-- Damage: the fill cuts at once and flashes; the ghost follows after a beat.
		fill.Size = UDim2.fromScale(fraction, 1)
		flash.BackgroundTransparency = 0.2
		tween(flash, UI.HealthFlashTime, { BackgroundTransparency = 1 })
		task.delay(UI.HealthGhostDelay, function()
			tween(ghost, UI.HealthGhostTime, { Size = UDim2.fromScale(fraction, 1) })
		end)
	else
		-- Healing (a respawn): the fill grows, the ghost snaps ahead of it.
		ghost.Size = UDim2.fromScale(fraction, 1)
		tween(fill, UI.HealthGhostTime, { Size = UDim2.fromScale(fraction, 1) })
	end
	shownFraction = fraction
end

local function onCharacter(character: Model)
	local h = character:WaitForChild("Humanoid", 10)
	if not h or not h:IsA("Humanoid") then
		return
	end
	humanoid = h
	refresh(false)
	h.HealthChanged:Connect(function()
		refresh(true)
	end)
	h:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		refresh(false)
	end)
end

function HealthController.Init()
	build()
	-- Roblox's own health bar is replaced, not duplicated. Wrapped: the core gui call
	-- can throw during the first frames of a session; a retry covers it.
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			end)
			if ok then
				break
			end
			task.wait(0.5)
		end
	end)

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	-- The low-health pulse: the fill breathes and the vignette throbs with it.
	RunService.RenderStepped:Connect(function(dt)
		local h = humanoid
		local fraction = if h and h.MaxHealth > 0 then h.Health / h.MaxHealth else 1
		if h and h.Health > 0 and fraction <= UI.HealthLowFraction then
			lowClock += dt
			local wave = (math.sin(lowClock * 2 * math.pi / UI.HealthPulsePeriod) + 1) / 2
			fill.BackgroundTransparency = 0.35 * wave
			setVignette(UI.VignetteMin + (UI.VignetteMax - UI.VignetteMin) * wave)
		else
			lowClock = 0
			fill.BackgroundTransparency = 0
			setVignette(1)
		end
	end)
end

return HealthController
