--!strict
-- ViewportIcon.lua
-- Not a controller: a small client utility that shows a 3D model inside the UI with a
-- ViewportFrame. No image assets: it renders the same model the game already uses.
-- (docs/RIGS_AND_VISUAL_UI_BRIEF.md §2.)
--
-- PERFORMANCE: a ViewportFrame re-renders when its contents move. Only icons explicitly set
-- spinning are animated, all from ONE RenderStepped connection, and a static icon costs
-- one render. Keep spinning icons to one or two at a time (the HUD slot, the loot reveal).
--
-- Camera: close and tight on the model's bounds, so an icon still reads at phone size.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local Palette =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Palette"))

local UI = GameConfig.UI
local ViewportIcon = {}

type Icon = { Frame: ViewportFrame, Camera: Camera, Model: Model?, Spin: boolean, Angle: number }
local icons: { [ViewportFrame]: Icon } = {}

local TILT = CFrame.Angles(0, 0, math.rad(UI.ViewportTiltDegrees)) -- shown diagonally

local function pose(icon: Icon)
	local model = icon.Model
	if model then
		model:PivotTo(CFrame.Angles(0, icon.Angle, 0) * TILT)
	end
end

local function frame(icon: Icon)
	local model = icon.Model
	if not model then
		return
	end
	pose(icon)
	local _, size = model:GetBoundingBox()
	-- Fit the largest extent (a spinning model sweeps its full size) inside the view cone.
	local extent = math.max(size.X, size.Y, size.Z)
	local fov = math.rad(icon.Camera.FieldOfView)
	local distance = (extent / 2) / math.tan(fov / 2) * UI.ViewportMargin
	icon.Camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, distance), Vector3.zero)
end

-- Creates an empty icon in `parent`, sized by Scale like everything else in the HUD.
function ViewportIcon.Create(parent: Instance, size: UDim2, position: UDim2?): ViewportFrame
	local vf = Instance.new("ViewportFrame")
	vf.Name = "Icon"
	vf.Size = size
	vf.Position = position or UDim2.new()
	vf.BackgroundTransparency = 1
	vf.Ambient = Palette.stone
	vf.LightColor = Palette.ember
	vf.LightDirection = Vector3.new(-1, -1, -1)
	local camera = Instance.new("Camera")
	camera.FieldOfView = UI.ViewportFov
	camera.Parent = vf
	vf.CurrentCamera = camera
	vf.Parent = parent
	icons[vf] = { Frame = vf, Camera = camera, Model = nil, Spin = false, Angle = 0 }
	vf.Destroying:Connect(function()
		icons[vf] = nil
	end)
	return vf
end

-- Shows `model` (a fresh clone the icon now owns) or clears the icon when nil.
function ViewportIcon.SetModel(vf: ViewportFrame, model: Model?)
	local icon = icons[vf]
	if not icon then
		return
	end
	if icon.Model then
		icon.Model:Destroy()
	end
	icon.Model = model
	if model then
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true -- nothing simulates in a viewport; anchoring keeps PivotTo exact
			end
		end
		model.Parent = vf
		frame(icon)
	end
end

function ViewportIcon.SetSpinning(vf: ViewportFrame, spinning: boolean)
	local icon = icons[vf]
	if icon then
		icon.Spin = spinning
	end
end

RunService.RenderStepped:Connect(function(dt)
	local step = math.rad(UI.ViewportSpinSpeed) * dt
	for _, icon in icons do
		if icon.Spin and icon.Model and icon.Frame.Visible then
			icon.Angle = (icon.Angle + step) % (2 * math.pi)
			pose(icon)
		end
	end
end)

return ViewportIcon
