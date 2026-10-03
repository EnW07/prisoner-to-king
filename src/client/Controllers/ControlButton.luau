--!strict
-- ControlButton.lua
-- Not a controller: builds the touch combat buttons (SWING, DASH, later HEAVY) in one
-- style, with a radial cooldown fill. (Blueprint §38: bottom cluster for thumbs; art §6:
-- touch targets at least 44px; J2: cooldowns as radial fills on the mobile buttons.)
--
-- RADIAL FILL with no images: two half-frames clip two full circles; each circle has a
-- hard-edged UIGradient (one half opaque, one transparent) whose Rotation sweeps, so the
-- visible wedge grows clockwise from 12 o'clock. Progress 0 = nothing covered (ready),
-- 1 = fully covered. We draw the REMAINING cooldown as a dim cover that sweeps away.
--
-- All buttons share one ScreenGui, PTK_Controls, in the CoreUI-safe area.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Palette = require(Config:WaitForChild("Palette"))
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))

local UI = GameConfig.UI
local player = Players.LocalPlayer
local ControlButton = {}

export type Button = {
	Panel: GuiObject,
	Pressed: RBXScriptSignal, -- fires on touch/click down
	SetCooldown: (remaining: number, total: number) -> (), -- 0 remaining = ready
	SetLabel: (text: string) -> (),
}

local gui: ScreenGui? = nil

function ControlButton.Gui(): ScreenGui
	if gui then
		return gui
	end
	local g = Instance.new("ScreenGui")
	g.Name = "PTK_Controls"
	g.ResetOnSpawn = false
	g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	return g
end

local HARD_EDGE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.501, 1),
	NumberSequenceKeypoint.new(1, 1),
})

-- A full-circle cover in a half-width clip. `left` selects which half it lives in.
local function half(parent: GuiObject, left: boolean): UIGradient
	local clip = Instance.new("Frame")
	clip.Name = if left then "Left" else "Right"
	clip.Size = UDim2.fromScale(0.5, 1)
	clip.Position = UDim2.fromScale(if left then 0 else 0.5, 0)
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.ZIndex = 3
	clip.Parent = parent

	local circle = Instance.new("Frame")
	circle.Name = "Cover"
	circle.Size = UDim2.fromScale(2, 1)
	circle.Position = UDim2.fromScale(if left then 0 else -1, 0)
	circle.BackgroundColor3 = Palette.pitch
	circle.BackgroundTransparency = 0.35
	circle.BorderSizePixel = 0
	circle.ZIndex = 3
	circle.Parent = clip
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UIStyle.CORNER
	corner.Parent = circle
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = HARD_EDGE
	gradient.Parent = circle
	return gradient
end

-- Build a button. `size` is a fraction of the screen (square; floor is the touch minimum),
-- `position`/`anchor` place it.
function ControlButton.Create(
	name: string,
	label: string,
	size: number,
	position: UDim2,
	anchor: Vector2
): Button
	local g = ControlButton.Gui()
	local panel, content = UIStyle.Panel("Frame", name, g, UDim2.fromScale(size, size), position, anchor)
	UIStyle.Aspect(panel, 1)
	local floor = Instance.new("UISizeConstraint")
	floor.MinSize = Vector2.new(UIStyle.MIN_TOUCH_PX, UIStyle.MIN_TOUCH_PX)
	floor.Parent = panel
	local text = UIStyle.Text("Label", content, label, UDim2.fromScale(1, 1), nil, 30)
	text.ZIndex = 2

	local scale = Instance.new("UIScale")
	scale.Parent = panel

	-- The radial cooldown cover, over the label, under the hit layer.
	local rightGradient = half(panel, false)
	local leftGradient = half(panel, true)
	local covered = false

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 5
	hit.Parent = panel

	local pressed = Instance.new("BindableEvent")
	local press = TweenInfo.new(UI.PopTime / 2)
	hit.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			TweenService:Create(scale, press, { Scale = UI.PressScale }):Play()
			pressed:Fire()
		end
	end)
	hit.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			TweenService:Create(scale, TweenInfo.new(UI.PopTime, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end)

	local function setCooldown(remaining: number, total: number)
		local p = if total > 0 then math.clamp(remaining / total, 0, 1) else 0
		-- Right half fills over the first half of p, left half over the second.
		rightGradient.Rotation = math.clamp(p * 2, 0, 1) * 180
		leftGradient.Rotation = 180 + math.clamp((p - 0.5) * 2, 0, 1) * 180
		local nowCovered = p > 0
		if nowCovered ~= covered then
			covered = nowCovered
			if not covered then
				-- Ready again: a small pop says so without a sound.
				scale.Scale = UI.PopScale
				TweenService:Create(scale, TweenInfo.new(UI.PopTime, Enum.EasingStyle.Back), { Scale = 1 })
					:Play()
			end
		end
		rightGradient.Parent.Visible = covered
		leftGradient.Parent.Visible = covered
	end
	setCooldown(0, 1)

	return {
		Panel = panel,
		Pressed = pressed.Event,
		SetCooldown = setCooldown,
		SetLabel = function(t: string)
			text.Text = t
		end,
	}
end

return ControlButton
