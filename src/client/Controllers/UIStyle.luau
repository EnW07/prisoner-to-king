--!strict
-- UIStyle.lua
-- Not a controller: the ONE place the HUD's look is defined. Every panel, label and button
-- is built through these functions so the style can't drift between screens.
-- (docs/VISUAL_OVERHAUL_PLAN.md §3 Phase 1, docs/ART_AND_UI_DIRECTION.md §3, §5, §6.)
--
-- THE STYLE LINE. Reused verbatim; if you change the look, change this sentence first.
--
--   PTK panel: pitch fill under a stone-to-pitch top-lit gradient, corner radius 25% of the
--   short side, 3px stone outline, 10% inner padding, GothamBlack light text with a 2px
--   pitch text stroke; bleed is the only saturated accent and means danger or unsecured
--   loot, nothing else.
--
-- Functional exceptions from art §3, never decoration: `gold` for banked currency,
-- `escape` for the ESCAPED moment, and rarity colours for a weapon's own name.
--
-- Sizing rule: Scale for anything that grows with the screen. Offset only for fixed physical
-- things — stroke widths and the touch-target floor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Palette"))

local UIStyle = {}

UIStyle.LINE = "PTK panel: pitch fill under a stone-to-pitch top-lit gradient, corner radius 25% of the short "
	.. "side, 3px stone outline, 10% inner padding, GothamBlack light text with a 2px pitch text stroke; "
	.. "bleed is the only saturated accent and means danger or unsecured loot, nothing else."

-- Light neutral for text. Palette §3 has no light-neutral token; plain white is the neutral.
UIStyle.TEXT = Color3.new(1, 1, 1)
-- Art §5: Gotham for HUD/body, GothamBlack for numerals. The display serif (Grenze) is not
-- used until its Enum.Font name is verified in Studio (CLAUDE.md rule 8).
UIStyle.FONT = Enum.Font.GothamBlack
UIStyle.BODY_FONT = Enum.Font.GothamBold
UIStyle.CORNER = UDim.new(0.25, 0)
UIStyle.STROKE_PX = 3
UIStyle.TEXT_STROKE_PX = 2
UIStyle.PADDING = UDim.new(0.1, 0)
UIStyle.MIN_TEXT_PX = 18 -- art §5 mobile floor
UIStyle.MIN_TOUCH_PX = 88 -- comfortably over the 44px §6 minimum

-- Builds a styled panel and returns (panel, content). Put children in `content`.
-- className is "Frame" or "CanvasGroup". Use CanvasGroup for anything that fades as a
-- whole: GroupTransparency fades its children too.
--
-- Layering: the panel is transparent, a Background child carries the corner, outline and
-- gradient, and a Content child carries the padding. That keeps the gradient off the text
-- (on a CanvasGroup a UIGradient would tint everything in it) and keeps any UIListLayout
-- from treating the background as a list item.
function UIStyle.Panel(
	className: string,
	name: string,
	parent: Instance,
	size: UDim2,
	position: UDim2,
	anchor: Vector2?
): (any, Frame) -- any: a Frame or a CanvasGroup, depending on className
	local panel = Instance.new(className) :: GuiObject
	panel.Name = name
	panel.Size = size
	panel.Position = position
	panel.AnchorPoint = anchor or Vector2.zero
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.new(1, 1, 1) -- white, so the gradient IS the colour
	background.BorderSizePixel = 0
	background.ZIndex = 0
	background.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UIStyle.CORNER
	corner.Parent = background

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Outline"
	stroke.Color = Palette.stone
	stroke.Thickness = UIStyle.STROKE_PX
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = background

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Palette.stone, Palette.pitch)
	gradient.Rotation = 90 -- top-lit: stone at the top edge, pitch at the bottom
	gradient.Parent = background

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.ZIndex = 1
	content.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UIStyle.PADDING
	padding.PaddingBottom = UIStyle.PADDING
	padding.PaddingLeft = UIStyle.PADDING
	padding.PaddingRight = UIStyle.PADDING
	padding.Parent = content

	panel.Parent = parent
	return panel, content
end

-- Builds a styled text label that scales with its box but never drops below the mobile floor.
function UIStyle.Text(
	name: string,
	parent: Instance,
	text: string,
	size: UDim2,
	position: UDim2?,
	maxTextPx: number?,
	color: Color3?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position or UDim2.new()
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = UIStyle.FONT
	label.TextColor3 = color or UIStyle.TEXT
	label.TextScaled = true
	label.TextWrapped = true

	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = UIStyle.MIN_TEXT_PX
	limit.MaxTextSize = maxTextPx or 48
	limit.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.pitch
	stroke.Thickness = UIStyle.TEXT_STROKE_PX
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label

	label.Parent = parent
	return label
end

-- Stacks children automatically.
function UIStyle.List(parent: Instance, direction: Enum.FillDirection, gap: UDim): UIListLayout
	local list = Instance.new("UIListLayout")
	list.FillDirection = direction
	list.Padding = gap
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = parent
	return list
end

-- Locks a shape (e.g. a round button) so it can't stretch on a wide screen.
function UIStyle.Aspect(parent: Instance, ratio: number): UIAspectRatioConstraint
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = ratio
	aspect.Parent = parent
	return aspect
end

-- The one sanctioned use of the accent on a panel: its outline turns `bleed` in danger.
function UIStyle.SetDanger(panel: GuiObject, danger: boolean)
	local background = panel:FindFirstChild("Background")
	local stroke = background and background:FindFirstChild("Outline") :: UIStroke?
	if stroke then
		stroke.Color = if danger then Palette.bleed else Palette.stone
	end
end

-- Thousands separators: 1240 -> "1,240". Numbers must punch (art §5) and be readable fast.
function UIStyle.Number(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

return UIStyle
