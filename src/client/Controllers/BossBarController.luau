--!strict
-- BossBarController.lua
-- Draws a boss's nameplate on THIS client: face, name, health bar and attack callout.
-- (Playtest 5: Bronn had no health bar.)
--
-- WHY CLIENT-SIDE: the bar used to be a server-built BillboardGui inside Bronn's model,
-- with a server-built ViewportFrame portrait. That put anchored BaseParts (the copied head)
-- under Workspace inside his own rig, and made his whole presentation part of a spawn path
-- that could fail and leave him inert. Now the server only publishes state, and this
-- controller renders it. The GUI lives in PlayerGui, adorned to his head:
--   • model attribute  Boss      = true     → this enemy gets a bar
--   • model attribute  BossName  = string
--   • model attribute  Callout   = string   → the attack name during a wind-up, else ""
--   • Humanoid.Health / MaxHealth           → replicated anyway
--
-- Pixel-sized on purpose (the bar must stay legible at distance, art §5), occluded by walls
-- (no wallhack). The portrait is a static ViewportFrame of a client-side copy of his helmed
-- head: it renders once.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Palette = require(Config:WaitForChild("Palette"))
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))

local TUNE = GameConfig.Captain
local player = Players.LocalPlayer
local BossBarController = {}

local bars: { [Model]: BillboardGui } = {}

local function label(
	parent: Instance,
	text: string,
	size: UDim2,
	pos: UDim2,
	px: number,
	color: Color3
): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = UIStyle.FONT
	l.TextSize = px
	l.TextColor3 = color
	l.TextStrokeColor3 = Palette.pitch
	l.TextStrokeTransparency = 0
	l.Parent = parent
	return l
end

-- A face-on copy of his helmed head in a ViewportFrame. Built from replicated parts, cloned
-- locally, so nothing lands in Workspace.
local function portrait(model: Model, head: BasePart, parent: Instance, sizePx: number)
	local frame = Instance.new("ViewportFrame")
	frame.Name = "Portrait"
	frame.Size = UDim2.fromOffset(sizePx, sizePx)
	frame.BackgroundColor3 = Palette.pitch
	frame.BorderSizePixel = 0
	frame.Ambient = Palette.stone
	frame.LightColor = Palette.ember
	frame.LightDirection = Vector3.new(-1, -1, 1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UIStyle.CORNER
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.bleed -- he is danger (art §3)
	stroke.Thickness = UIStyle.STROKE_PX
	stroke.Parent = frame
	frame.Parent = parent

	local bust = Instance.new("Model")
	local origin = head.CFrame
	for _, name in { "Head", "Helm", "Crest" } do
		local source = model:FindFirstChild(name)
		if source and source:IsA("BasePart") then
			local copy = source:Clone()
			for _, child in copy:GetChildren() do
				if not (child:IsA("DataModelMesh") or child:IsA("Decal")) then
					child:Destroy() -- keep the mesh and face; joints and GUIs mean nothing here
				end
			end
			copy.Anchored = true
			copy.CFrame = origin:ToObjectSpace(source.CFrame)
			copy.Parent = bust
		end
	end
	bust.Parent = frame

	-- R15 heads face -Z: the camera sits on -Z looking back at the face.
	local camera = Instance.new("Camera")
	camera.FieldOfView = TUNE.PortraitFov
	local centre, size = bust:GetBoundingBox()
	local extent = math.max(size.X, size.Y, size.Z)
	local distance = (extent / 2) / math.tan(math.rad(camera.FieldOfView) / 2) * TUNE.PortraitMargin
	camera.CFrame = CFrame.lookAt(centre.Position + Vector3.new(0, 0, -distance), centre.Position)
	camera.Parent = frame
	frame.CurrentCamera = camera
end

local function build(model: Model)
	if bars[model] then
		return
	end
	local head = model:WaitForChild("Head", 10) :: BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid", 10)
	if not head or not humanoid or not humanoid:IsA("Humanoid") or not model.Parent or bars[model] then
		return
	end

	local px = TUNE.PortraitPx
	local textX = px + 6
	local gui = Instance.new("BillboardGui")
	gui.Name = "PTK_BossBar"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(textX + 300, 96)
	gui.StudsOffset = Vector3.new(0, head.Size.Y + 2.4, 0)
	gui.MaxDistance = TUNE.NameplateMaxDistance
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	bars[model] = gui

	local name = label(
		gui,
		tostring(model:GetAttribute("BossName") or humanoid.DisplayName),
		UDim2.new(1, -textX, 0, 30),
		UDim2.fromOffset(textX, 0),
		26,
		UIStyle.TEXT
	)
	name.TextXAlignment = Enum.TextXAlignment.Left

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, -textX, 0, 22)
	bar.Position = UDim2.fromOffset(textX, 32)
	bar.BackgroundColor3 = Palette.pitch
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Palette.bleed
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = bar
	local healthText = label(bar, "", UDim2.fromScale(1, 1), UDim2.new(), 18, UIStyle.TEXT)
	healthText.ZIndex = 2

	local callout = label(gui, "", UDim2.new(1, 0, 0, 38), UDim2.fromOffset(0, 58), 32, Palette.bleed)
	callout.Visible = false

	local function refreshHealth()
		local frac = if humanoid.MaxHealth > 0
			then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
			else 0
		fill.Size = UDim2.fromScale(frac, 1)
		healthText.Text = ("%d / %d"):format(math.ceil(humanoid.Health), humanoid.MaxHealth)
	end
	local function refreshCallout()
		local text = model:GetAttribute("Callout")
		callout.Text = if typeof(text) == "string" then text else ""
		callout.Visible = callout.Text ~= ""
	end
	refreshHealth()
	refreshCallout()
	-- A corpse has no health bar: the ragdoll lies there for a few seconds before fading.
	humanoid.Died:Connect(function()
		gui.Enabled = false
	end)
	humanoid.HealthChanged:Connect(refreshHealth)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refreshHealth)
	model:GetAttributeChangedSignal("Callout"):Connect(refreshCallout)
	model:GetAttributeChangedSignal("BossName"):Connect(function()
		name.Text = tostring(model:GetAttribute("BossName") or humanoid.DisplayName)
	end)

	-- The costume is added just after spawn; give it a moment so the face wears the helm.
	task.spawn(function()
		model:WaitForChild("Helm", 3)
		model:WaitForChild("Crest", 1)
		if gui.Parent then
			portrait(model, head, gui, px)
		end
	end)

	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			gui:Destroy()
			bars[model] = nil
		end
	end)
end

local function watch(model: Instance)
	if not model:IsA("Model") then
		return
	end
	if model:GetAttribute("Boss") then
		task.spawn(build, model)
	end
	-- The attribute may replicate a moment after the model itself.
	model:GetAttributeChangedSignal("Boss"):Connect(function()
		if model:GetAttribute("Boss") then
			task.spawn(build, model)
		end
	end)
end

function BossBarController.Init()
	task.spawn(function()
		local enemies = workspace:WaitForChild("Enemies")
		for _, model in enemies:GetChildren() do
			watch(model)
		end
		enemies.ChildAdded:Connect(watch)
	end)
end

return BossBarController
