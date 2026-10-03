--!strict
-- EnemyBarController.lua
-- Small health bars above enemies (J2): fade in on the first hit this player lands, show
-- the name and the number, fade out when disengaged. Never permanently on screen. Bosses
-- have their own bar (BossBarController) and are skipped here. The stock Humanoid health
-- display is off (EnemyService), so this is the only bar an enemy ever has.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Palette = require(Config:WaitForChild("Palette"))
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))

local UI = GameConfig.UI
local player = Players.LocalPlayer
local EnemyBarController = {}

type Bar = { Gui: BillboardGui, Group: CanvasGroup, Fill: Frame, Text: TextLabel, Token: number }
local bars: { [Model]: Bar } = {}

local function fadeOut(model: Model, bar: Bar)
	local out = TweenService:Create(bar.Group, TweenInfo.new(UI.EnemyBarFade), { GroupTransparency = 1 })
	out.Completed:Connect(function()
		if bars[model] == bar and bar.Group.GroupTransparency >= 1 then
			bar.Gui:Destroy()
			bars[model] = nil
		end
	end)
	out:Play()
end

local function build(model: Model, humanoid: Humanoid, head: BasePart): Bar
	local gui = Instance.new("BillboardGui")
	gui.Name = "PTK_EnemyBar"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(UI.EnemyBarPx, UI.EnemyBarPx * 0.3)
	gui.StudsOffset = Vector3.new(0, head.Size.Y + 1.2, 0)
	gui.MaxDistance = UI.EnemyBarMaxDistance
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local group = Instance.new("CanvasGroup")
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1
	group.Parent = gui

	local name = Instance.new("TextLabel")
	name.Size = UDim2.fromScale(1, 0.5)
	name.BackgroundTransparency = 1
	name.Text = humanoid.DisplayName ~= "" and humanoid.DisplayName or model.Name
	name.Font = UIStyle.FONT
	name.TextScaled = true
	name.TextColor3 = UIStyle.TEXT
	name.TextStrokeColor3 = Palette.pitch
	name.TextStrokeTransparency = 0
	name.Parent = group

	local track = Instance.new("Frame")
	track.Position = UDim2.fromScale(0, 0.55)
	track.Size = UDim2.fromScale(1, 0.4)
	track.BackgroundColor3 = Palette.pitch
	track.BorderSizePixel = 0
	track.Parent = group
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = track
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.stone
	stroke.Thickness = 2
	stroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Palette.bleed
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = UIStyle.FONT
	text.TextScaled = true
	text.TextColor3 = UIStyle.TEXT
	text.TextStrokeColor3 = Palette.pitch
	text.TextStrokeTransparency = 0
	text.ZIndex = 2
	text.Parent = track

	local bar: Bar = { Gui = gui, Group = group, Fill = fill, Text = text, Token = 0 }
	local function refresh()
		local frac = if humanoid.MaxHealth > 0
			then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
			else 0
		TweenService:Create(fill, TweenInfo.new(UI.BarFillTime), { Size = UDim2.fromScale(frac, 1) }):Play()
		text.Text = ("%d"):format(math.ceil(humanoid.Health))
	end
	refresh()
	humanoid.HealthChanged:Connect(refresh)
	humanoid.Died:Connect(function()
		fadeOut(model, bar)
	end)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			gui:Destroy()
			bars[model] = nil
		end
	end)
	return bar
end

-- Show (or keep showing) the bar for this enemy, and schedule its fade.
local function engage(model: Model)
	if model:GetAttribute("Boss") then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local head = model:FindFirstChild("Head")
	if not humanoid or humanoid.Health <= 0 or not head or not head:IsA("BasePart") then
		return
	end
	local bar = bars[model]
	if not bar then
		bar = build(model, humanoid, head)
		bars[model] = bar
	end
	bar.Token += 1
	local token = bar.Token
	TweenService:Create(bar.Group, TweenInfo.new(UI.EnemyBarFade), { GroupTransparency = 0 }):Play()
	task.delay(UI.EnemyBarHold, function()
		if bars[model] == bar and bar.Token == token then
			fadeOut(model, bar)
		end
	end)
end

function EnemyBarController.Init()
	Net.Event("HitConfirm").OnClientEvent:Connect(function(data)
		if (data.Kind == "dealt" or data.Kind == "blocked") and data.Attacker == player.UserId then
			local target = data.Target
			if typeof(target) == "Instance" and target:IsA("Model") then
				engage(target)
			end
		end
	end)
end

return EnemyBarController
