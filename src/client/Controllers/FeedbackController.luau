--!strict
-- FeedbackController.lua
-- Blueprint §11 ("combat cannot feel like two Roblox mannequins touching each other")
-- and §92, the no-sound test: every important state must be readable with audio off.
--
-- MANUAL SETUP: fill in SOUND_IDS with your own audio asset IDs. Empty strings are skipped,
-- so the game runs silently but correctly until you do. No placeholder IDs are invented here.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local FeedbackController = {}

local SOUND_IDS = {
	hit = "", -- e.g. "rbxassetid://0000000000"
	takeDamage = "",
	kill = "",
	loot = "",
	rarity = "",
	escape = "",
	alarm = "",
}

local function playSound(name: string, volume: number?)
	local id = SOUND_IDS[name]
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.6
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 5)
end

-- Floating damage number at a world position.
local function damageNumber(position: Vector3, amount: number, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = CFrame.new(position + Vector3.new(math.random(-15, 15) / 10, 2.5, 0))
	anchor.Parent = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 44)
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = tostring(math.floor(amount))
	text.TextColor3 = color
	text.TextStrokeTransparency = 0.2
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.Parent = billboard

	TweenService:Create(anchor, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = anchor.CFrame * CFrame.new(0, 4, 0),
	}):Play()
	TweenService:Create(text, TweenInfo.new(0.7), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

	Debris:AddItem(anchor, 0.8)
end

-- Very short camera nudge. Kept small: §40 asks for a reduced-shake option later.
local function cameraKick(strength: number)
	local start = os.clock()
	local duration = 0.12
	local conn
	conn = game:GetService("RunService").RenderStepped:Connect(function()
		local alpha = (os.clock() - start) / duration
		if alpha >= 1 then
			conn:Disconnect()
			return
		end
		local decay = (1 - alpha) * strength
		camera.CFrame = camera.CFrame
			* CFrame.Angles(
				math.rad((math.random() - 0.5) * decay),
				math.rad((math.random() - 0.5) * decay),
				0
			)
	end)
end

function FeedbackController.Init()
	Net.Event("HitConfirm").OnClientEvent:Connect(function(data)
		if data.Kind == "dealt" then
			-- Only show numbers for hits this player caused, to keep the screen readable.
			if data.Attacker == player.UserId then
				damageNumber(data.Position, data.Damage, Color3.fromRGB(255, 240, 190))
				cameraKick(0.7)
				playSound(if data.Killed then "kill" else "hit")
			end
		elseif data.Kind == "taken" then
			damageNumber(data.Position, data.Damage, Color3.fromRGB(255, 110, 110))
			cameraKick(1.4)
			playSound("takeDamage")
		end
	end)

	Net.Event("Notify").OnClientEvent:Connect(function(data)
		if data.Kind == "gold" or data.Kind == "loot" then
			playSound("loot")
		elseif data.Kind == "weapon" then
			playSound("rarity", 0.8)
		elseif data.Kind == "alarm" then
			playSound("alarm", 0.8)
		end
	end)

	Net.Event("ScreenEvent").OnClientEvent:Connect(function(data)
		if data.Kind == "escaped" then
			playSound("escape", 0.9)
		end
	end)
end

return FeedbackController
