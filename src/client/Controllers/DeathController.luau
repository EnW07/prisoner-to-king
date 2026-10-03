--!strict
-- DeathController.lua
-- The player's death, as this client sees it. (MASTER_BUILD_SPEC Section D; blueprint §66.)
-- The sequence, in order, each beat separate so none of it reads as a bug:
--   1. IMPACT      the killing blow gets the heaviest hit-stop in the game; the pose holds
--   2. the body     the server ragdolls it after the same hold (DeathService); nothing here
--                   animates after Freeze, so no running clip plays on a falling corpse
--   3. CAMERA       detaches and drifts back and up from where it is. Never cuts.
--   4. COLOUR       the screen desaturates over DesaturateTime (a ColorCorrectionEffect)
--   5. the bar      the unsecured bar drains in one hard frame (UIController, on the
--                   CAPTURED event, which arrives at once)
--   6. CAPTURED     the card fades in after a beat: what killed you, what you lost, what
--                   you kept, how far you got, and TRY AGAIN, focused and large
-- TRY AGAIN sends RespawnRequest (no arguments; the server decides). A new character
-- restores the camera, the colour and the HUD, and this controller forgets everything.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Palette = require(Config:WaitForChild("Palette"))
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local HitStop = require(script.Parent:WaitForChild("HitStop"))
local PlayerAnimController = require(script.Parent:WaitForChild("PlayerAnimController"))

local DEATH = GameConfig.Death
local UI = GameConfig.UI
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local DeathController = {}

local RespawnRequest: RemoteEvent

local gui: ScreenGui
local dim: Frame
local card: CanvasGroup
local cardScale: UIScale
local killedByLabel: TextLabel
local goldLostLabel: TextLabel
local gearKeptLabel: TextLabel
local progressLabel: TextLabel
local tryAgain: GuiObject
local tryAgainHit: TextButton
local tryAgainLabel: TextLabel
local tryAgainScale: UIScale
local waitLabel: TextLabel

local color: ColorCorrectionEffect
local cameraTween: Tween? = nil
local token = 0 -- bumps on death and on respawn; stale delays check it
local diedAt = 0
local payload: any = nil -- the CAPTURED data, whenever it arrives
local cardShown = false
local requested = false

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

-- ── Build ───────────────────────────────────────────────────────
local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "PTK_Death"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20 -- above every other PTK gui
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Palette.pitch
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Parent = gui

	local content
	card, content = UIStyle.Panel(
		"CanvasGroup",
		"Captured",
		gui,
		UDim2.fromScale(0.52, 0.62),
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5)
	)
	UIStyle.Aspect(card, 1.25)
	UIStyle.SetDanger(card, true)
	cardScale = Instance.new("UIScale")
	cardScale.Parent = card
	UIStyle.List(content, Enum.FillDirection.Vertical, UDim.new(0.025, 0))

	local title =
		UIStyle.Text("Title", content, "CAPTURED!", UDim2.fromScale(1, 0.22), nil, 72, Palette.bleed)
	title.LayoutOrder = 1

	local function line(name: string, order: number, color3: Color3?): TextLabel
		local l = UIStyle.Text(name, content, "", UDim2.fromScale(1, 0.09), nil, 30, color3)
		l.Font = UIStyle.BODY_FONT
		l.LayoutOrder = order
		return l
	end
	killedByLabel = line("KilledBy", 2)
	goldLostLabel = line("GoldLost", 3, Palette.bleed)
	gearKeptLabel = line("GearKept", 4, Palette.gold) -- reassurance: your gear is safe
	progressLabel = line("Progress", 5)

	-- TRY AGAIN: the one action, large, the default focus. Neutral panel: it is not danger.
	local buttonContent
	tryAgain, buttonContent =
		UIStyle.Panel("Frame", "TryAgain", content, UDim2.fromScale(0.72, 0.17), UDim2.new())
	tryAgain.LayoutOrder = 6
	local floor = Instance.new("UISizeConstraint")
	floor.MinSize = Vector2.new(UIStyle.MIN_TOUCH_PX * 2.5, UIStyle.MIN_TOUCH_PX)
	floor.Parent = tryAgain
	tryAgainScale = Instance.new("UIScale")
	tryAgainScale.Parent = tryAgain
	tryAgainLabel = UIStyle.Text("Label", buttonContent, "TRY AGAIN", UDim2.fromScale(1, 1), nil, 44)
	tryAgainHit = Instance.new("TextButton")
	tryAgainHit.Name = "Hit"
	tryAgainHit.Size = UDim2.fromScale(1, 1)
	tryAgainHit.BackgroundTransparency = 1
	tryAgainHit.Text = ""
	tryAgainHit.ZIndex = 4
	tryAgainHit.Selectable = true
	tryAgainHit.Parent = tryAgain

	waitLabel = line("Wait", 7)
	waitLabel.Size = UDim2.fromScale(1, 0.07)
	waitLabel.TextTransparency = 0.3
end

-- ── The beats ───────────────────────────────────────────────────
local function fillCard()
	local data = payload
	if not data then
		killedByLabel.Text = ""
		goldLostLabel.Text = ""
		gearKeptLabel.Text = ""
		progressLabel.Text = ""
		return
	end
	local killer = data.KilledBy
	killedByLabel.Text = if killer
		then ("Killed by: %s — %s"):format(tostring(killer.Enemy), tostring(killer.Attack))
		else "Killed"
	local kept = data.GoldKept or 0
	goldLostLabel.Text = if kept > 0
		then ("Gold lost: %s  ·  kept: %s"):format(UIStyle.Number(data.GoldLost or 0), UIStyle.Number(kept))
		else ("Gold lost: %s"):format(UIStyle.Number(data.GoldLost or 0))
	gearKeptLabel.Text = ("Gear kept: %s"):format(tostring(data.GearKept or "None"))
	progressLabel.Text = ("Progress this run: %s"):format(tostring(data.Progress or ""))
end

local function showCard(myToken: number)
	if token ~= myToken or cardShown then
		return
	end
	cardShown = true
	fillCard()
	requested = false
	tryAgainLabel.Text = "TRY AGAIN"
	gui.Enabled = true
	dim.BackgroundTransparency = 1
	card.GroupTransparency = 1
	cardScale.Scale = 0.9
	tween(dim, DEATH.CardInTime, { BackgroundTransparency = UI.OverlayDim })
	tween(card, DEATH.CardInTime, { GroupTransparency = 0 })
	tween(cardScale, DEATH.CardInTime, { Scale = 1 }, Enum.EasingStyle.Back)
	-- Focused by default on a gamepad (the selection box only means something there); a
	-- thumb or a click works regardless.
	if UserInputService.GamepadEnabled then
		pcall(function()
			GuiService.SelectedObject = tryAgainHit
		end)
	end

	-- "or wait Ns": the automatic retry, so nobody is ever stuck on this screen.
	task.spawn(function()
		while token == myToken and gui.Enabled do
			local left = math.ceil(DEATH.AutoRespawnDelay - (os.clock() - diedAt))
			if left <= 0 or requested then
				waitLabel.Text = if requested then "" else "BREAKING OUT..."
				break
			end
			waitLabel.Text = ("or wait %ds"):format(left)
			task.wait(0.25)
		end
	end)
end

local function hideCard()
	if not gui.Enabled then
		return
	end
	cardShown = false
	pcall(function()
		if GuiService.SelectedObject == tryAgainHit then
			GuiService.SelectedObject = nil
		end
	end)
	tween(dim, UI.OverlayOutTime, { BackgroundTransparency = 1 })
	local out = tween(card, UI.OverlayOutTime, { GroupTransparency = 1 })
	out.Completed:Connect(function()
		if not cardShown then
			gui.Enabled = false
		end
	end)
end

local function driftCamera(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if not root or not root:IsA("BasePart") then
		return
	end
	local focus = root.Position
	-- From exactly where the camera is now (never a cut), back along its own view and up.
	local start = camera.CFrame
	local flat = Vector3.new(start.LookVector.X, 0, start.LookVector.Z)
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit
	local position = focus - flat * DEATH.CameraBack + Vector3.new(0, DEATH.CameraUp, 0)
	local target = CFrame.lookAt(position, focus)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = start
	if cameraTween then
		cameraTween:Cancel()
	end
	cameraTween = tween(
		camera,
		DEATH.CameraDriftTime,
		{ CFrame = target },
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.Out
	)
end

local function onDied(character: Model)
	token += 1
	local myToken = token
	diedAt = os.clock()
	cardShown = false

	-- 1. Impact: the heaviest freeze in the game, and the pose holds exactly.
	HitStop.Freeze(DEATH.HitStop)
	PlayerAnimController.Freeze()
	-- 3. Camera.
	driftCamera(character)
	-- 4. Colour.
	color.Enabled = true
	tween(color, DEATH.DesaturateTime, { Saturation = DEATH.Saturation, Contrast = DEATH.Contrast })
	-- 6. The card, after a beat. Let the loss land first.
	task.delay(DEATH.CardDelay, function()
		showCard(myToken)
	end)
end

local function onCharacter(character: Model)
	token += 1
	-- Restore: camera back to the new character, colour back, card away. A fresh character
	-- is the state reset; nothing from the last life is referenced after this.
	if cameraTween then
		cameraTween:Cancel()
		cameraTween = nil
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	camera.CameraType = Enum.CameraType.Custom
	if humanoid and humanoid:IsA("Humanoid") then
		camera.CameraSubject = humanoid
	end
	if color.Enabled then
		local back = tween(color, DEATH.RestoreTime, { Saturation = 0, Contrast = 0 })
		back.Completed:Connect(function()
			if camera.CameraType ~= Enum.CameraType.Scriptable then
				color.Enabled = false
			end
		end)
	end
	hideCard()
	payload = nil
	requested = false

	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			onDied(character)
		end)
	end
end

local function onTryAgain()
	if requested then
		return
	end
	requested = true
	tryAgainScale.Scale = UI.PressScale
	tween(tryAgainScale, UI.PopTime, { Scale = 1 }, Enum.EasingStyle.Back)
	tryAgainLabel.Text = "BREAKING OUT..."
	RespawnRequest:FireServer()
end

function DeathController.Init()
	RespawnRequest = Net.Event("RespawnRequest")
	build()

	color = Instance.new("ColorCorrectionEffect")
	color.Name = "PTK_DeathColor"
	color.Enabled = false
	color.Parent = Lighting

	tryAgainHit.Activated:Connect(onTryAgain)

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	-- The CAPTURED payload arrives at death; the card shows it after the beat.
	Net.Event("ScreenEvent").OnClientEvent:Connect(function(data)
		if data.Kind ~= "captured" then
			return
		end
		payload = data
		if cardShown then
			fillCard()
		end
	end)
end

return DeathController
