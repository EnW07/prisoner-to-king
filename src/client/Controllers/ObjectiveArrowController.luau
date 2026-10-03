--!strict
-- ObjectiveArrowController.lua
-- A directional pointer toward the current objective (J2): cheaper and more readable on a
-- phone than a minimap. The server sends the objective's world position with every
-- StateUpdate (RunStateService.ObjectiveTarget); this turns a 3D arrow in a ViewportFrame
-- to point at it relative to the camera, and writes the distance under it. Hidden when
-- there is nothing to point at or you are already there.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Palette = require(Config:WaitForChild("Palette"))
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local UIController = require(script.Parent:WaitForChild("UIController"))

local UI = GameConfig.UI
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local ObjectiveArrowController = {}

local panel: GuiObject
local viewport: ViewportFrame
local arrow: Model
local distanceLabel: TextLabel
local target: Vector3? = nil

local function buildArrow(): Model
	local model = Instance.new("Model")
	-- A wedge pointing along -Z (forward), seen from above: an arrowhead.
	local head = Instance.new("WedgePart")
	head.Anchored = true
	head.Size = Vector3.new(2.2, 0.4, 2.4)
	head.Color = UIStyle.TEXT
	head.Material = Enum.Material.Neon
	head.CFrame = CFrame.new(0, 0, -0.6)
		* CFrame.Angles(0, 0, math.rad(-90))
		* CFrame.Angles(math.rad(90), 0, 0)
	head.Parent = model
	local shaft = Instance.new("Part")
	shaft.Anchored = true
	shaft.Size = Vector3.new(0.7, 0.4, 1.8)
	shaft.Color = UIStyle.TEXT
	shaft.Material = Enum.Material.Neon
	shaft.CFrame = CFrame.new(0, 0, 1.2)
	shaft.Parent = model
	model.PrimaryPart = shaft
	return model
end

local function build()
	local gui = UIController.GetGui()
	local root = gui:FindFirstChild("Root") :: Frame
	local content
	panel, content = UIStyle.Panel(
		"Frame",
		"ObjectiveArrow",
		root,
		UDim2.fromScale(UI.ArrowSize, UI.ArrowSize * 1.3),
		UDim2.fromScale(0.5, UI.ArrowY),
		Vector2.new(0.5, 0)
	)
	UIStyle.Aspect(panel, 1 / 1.3)
	panel.Visible = false
	UIStyle.List(content, Enum.FillDirection.Vertical, UDim.new(0.02, 0))

	viewport = Instance.new("ViewportFrame")
	viewport.Name = "Arrow"
	viewport.Size = UDim2.fromScale(1, 0.7)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = UIStyle.TEXT
	viewport.LightColor = UIStyle.TEXT
	viewport.LayoutOrder = 1
	viewport.Parent = content
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 12, 0), Vector3.zero, Vector3.new(0, 0, -1))
	cam.Parent = viewport
	viewport.CurrentCamera = cam
	arrow = buildArrow()
	arrow.Parent = viewport

	distanceLabel = UIStyle.Text("Distance", content, "", UDim2.fromScale(1, 0.28), nil, 20)
	distanceLabel.Font = UIStyle.BODY_FONT
	distanceLabel.LayoutOrder = 2
end

local function update()
	local t = target
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not t or not root or not root:IsA("BasePart") then
		panel.Visible = false
		return
	end
	local to = t - root.Position
	local flat = Vector3.new(to.X, 0, to.Z)
	local distance = flat.Magnitude
	if distance < UI.ArrowHideDistance then
		panel.Visible = false
		return
	end
	panel.Visible = true
	-- Yaw of the target relative to where the camera looks, so "up" on the arrow is ahead.
	local look = camera.CFrame.LookVector
	local camYaw = math.atan2(-look.X, -look.Z)
	local targetYaw = math.atan2(-flat.X, -flat.Z)
	local relative = targetYaw - camYaw
	arrow:PivotTo(CFrame.Angles(0, relative, 0))
	distanceLabel.Text = ("%d"):format(math.floor(distance + 0.5))
	-- Danger-coloured while the alarm is up is UIController's call; the arrow stays neutral.
end

function ObjectiveArrowController.Init()
	build()
	Net.Event("StateUpdate").OnClientEvent:Connect(function(state)
		local v = state.ObjectiveTarget
		target = if typeof(v) == "Vector3" then v else nil
	end)
	-- Cheap: one atan2 per frame.
	RunService.RenderStepped:Connect(update)
	-- Keep the arrow's colour meaning in step with the money panel's danger outline.
	UIController.DangerChanged.Event:Connect(function(danger: boolean)
		for _, p in arrow:GetDescendants() do
			if p:IsA("BasePart") then
				p.Color = if danger then Palette.bleed else UIStyle.TEXT
			end
		end
	end)
end

return ObjectiveArrowController
