--!strict
-- PromptUIController.lua
-- Draws every ProximityPrompt as a UIStyle card instead of Roblox's default bubble, so
-- prompts match the HUD and fade rather than pop. (VISUAL_OVERHAUL_PLAN Phase 1.)
--
-- Division of labour:
--   • PromptController decides WHETHER a prompt is enabled for this player (PTKGate) and
--     what its per-player label says.
--   • This controller only decides how a shown prompt LOOKS.
--   • The server still validates every Triggered. Drawing a prompt changes no authority.
--
-- Style is set to Custom locally, on this client only. Input still works: Roblox keeps
-- handling the keyboard and gamepad keys for a Custom prompt. Touch has no default bubble
-- to tap, so each card is its own large touch target, wired to InputHoldBegin/End.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))

local UI = GameConfig.UI
local player = Players.LocalPlayer
local PromptUIController = {}

type Card = { Gui: BillboardGui, Panel: CanvasGroup, Connections: { RBXScriptConnection } }
local cards: { [ProximityPrompt]: Card } = {}

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return (prompt.GamepadKeyCode.Name:gsub("^Button", ""))
	end
	return prompt.KeyboardKeyCode.Name
end

local function destroyCard(prompt: ProximityPrompt)
	local card = cards[prompt]
	if not card then
		return
	end
	cards[prompt] = nil
	for _, c in card.Connections do
		c:Disconnect()
	end
	card.Gui:Destroy()
end

local function hide(prompt: ProximityPrompt)
	local card = cards[prompt]
	if not card then
		return
	end
	local fade = TweenService:Create(card.Panel, TweenInfo.new(UI.PromptFadeTime), { GroupTransparency = 1 })
	fade.Completed:Connect(function()
		if cards[prompt] == card then
			destroyCard(prompt)
		end
	end)
	fade:Play()
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	destroyCard(prompt)
	local adornee = prompt.Parent
	if not adornee or not (adornee:IsA("BasePart") or adornee:IsA("Attachment")) then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "PTK_Prompt"
	gui.Adornee = adornee
	gui.AlwaysOnTop = true
	gui.Active = true -- receives taps
	-- Scale on a BillboardGui is studs: the card is a fixed size in the world, so it reads
	-- larger as you approach — exactly when you can use it.
	gui.Size = UDim2.fromScale(UI.PromptWidthStuds, UI.PromptHeightStuds)
	gui.StudsOffset = Vector3.new(0, UI.PromptLiftStuds, 0)
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel, content = UIStyle.Panel("CanvasGroup", "Card", gui, UDim2.fromScale(1, 1), UDim2.new())
	panel.GroupTransparency = 1
	UIStyle.List(content, Enum.FillDirection.Horizontal, UDim.new(0.04, 0))

	-- Key badge: a smaller panel built the same way, so it shares the style line.
	local badge, badgeContent = UIStyle.Panel("Frame", "Key", content, UDim2.fromScale(0.24, 1), UDim2.new())
	UIStyle.Aspect(badge, 1)
	badge.LayoutOrder = 1
	UIStyle.Text("Label", badgeContent, keyText(prompt, inputType), UDim2.fromScale(1, 1), nil, 32)

	local column = Instance.new("Frame")
	column.Name = "Text"
	column.Size = UDim2.fromScale(0.72, 1)
	column.BackgroundTransparency = 1
	column.LayoutOrder = 2
	column.Parent = content
	UIStyle.List(column, Enum.FillDirection.Vertical, UDim.new(0, 0))
	local objectLabel = UIStyle.Text("Object", column, prompt.ObjectText, UDim2.fromScale(1, 0.58), nil, 30)
	objectLabel.TextXAlignment = Enum.TextXAlignment.Left
	objectLabel.LayoutOrder = 1
	local actionLabel =
		UIStyle.Text("Action", column, prompt.ActionText:upper(), UDim2.fromScale(1, 0.42), nil, 24)
	actionLabel.Font = UIStyle.BODY_FONT
	actionLabel.TextXAlignment = Enum.TextXAlignment.Left
	actionLabel.LayoutOrder = 2

	-- Hold progress, along the bottom edge. Light neutral: holding isn't danger.
	local holdFill = Instance.new("Frame")
	holdFill.Name = "Hold"
	holdFill.AnchorPoint = Vector2.new(0, 1)
	holdFill.Position = UDim2.fromScale(0.08, 0.94)
	holdFill.Size = UDim2.fromScale(0, 0.07)
	holdFill.BackgroundColor3 = UIStyle.TEXT
	holdFill.BorderSizePixel = 0
	holdFill.ZIndex = 3
	holdFill.Parent = panel
	local holdCorner = Instance.new("UICorner")
	holdCorner.CornerRadius = UDim.new(0.5, 0)
	holdCorner.Parent = holdFill
	local holdTween: Tween? = nil

	-- The whole card is the touch target.
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 4
	hit.Parent = panel

	local scale = Instance.new("UIScale")
	scale.Parent = panel

	local card: Card = { Gui = gui, Panel = panel, Connections = {} }
	cards[prompt] = card
	local conns = card.Connections

	table.insert(
		conns,
		hit.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				prompt:InputHoldBegin()
			end
		end)
	)
	table.insert(
		conns,
		hit.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				prompt:InputHoldEnd()
			end
		end)
	)
	table.insert(
		conns,
		prompt.PromptButtonHoldBegan:Connect(function()
			holdFill.Size = UDim2.fromScale(0, 0.07)
			holdTween = TweenService:Create(
				holdFill,
				TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear),
				{ Size = UDim2.fromScale(0.84, 0.07) }
			);
			(holdTween :: Tween):Play()
		end)
	)
	table.insert(
		conns,
		prompt.PromptButtonHoldEnded:Connect(function()
			if holdTween then
				holdTween:Cancel()
			end
			TweenService
				:Create(holdFill, TweenInfo.new(UI.PromptFadeTime), { Size = UDim2.fromScale(0, 0.07) })
				:Play()
		end)
	)
	table.insert(
		conns,
		prompt.Triggered:Connect(function()
			scale.Scale = UI.PopScale
			TweenService:Create(scale, TweenInfo.new(UI.PopTime, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end)
	)
	-- PromptController rewrites ObjectText per player (e.g. the live upgrade price).
	table.insert(
		conns,
		prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
			objectLabel.Text = prompt.ObjectText
		end)
	)
	table.insert(
		conns,
		prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
			actionLabel.Text = prompt.ActionText:upper()
		end)
	)
	table.insert(
		conns,
		prompt.PromptHidden:Connect(function()
			hide(prompt)
		end)
	)
	table.insert(
		conns,
		prompt.Destroying:Connect(function()
			destroyCard(prompt)
		end)
	)

	TweenService:Create(panel, TweenInfo.new(UI.PromptFadeTime), { GroupTransparency = 0 }):Play()
end

local function adopt(inst: Instance)
	if inst:IsA("ProximityPrompt") then
		inst.Style = Enum.ProximityPromptStyle.Custom
	end
end

function PromptUIController.Init()
	for _, inst in workspace:GetDescendants() do
		adopt(inst)
	end
	workspace.DescendantAdded:Connect(adopt)
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			show(prompt, inputType)
		end
	end)
end

return PromptUIController
