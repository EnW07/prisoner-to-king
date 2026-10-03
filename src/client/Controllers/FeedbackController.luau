--!strict
-- FeedbackController.lua
-- Blueprint §11 ("combat cannot feel like two Roblox mannequins touching each other")
-- and §92, the no-sound test: every important state must be readable with audio off.
-- (MASTER_BUILD_SPEC E8: the hit feedback stack, all of it scaled to significance.)
--
-- On every hit the player lands: hit-stop scaled to damage, a camera kick scaled to
-- damage (honouring the reduced-shake setting), a damage number sized by significance,
-- sparks at the CONTACT POINT the server reports (not the enemy's centre), and on a
-- killing blow a flash on the enemy and the biggest of everything. Taking a hit: a number
-- in `bleed`, a kick, hit-stop on heavy blows. Dodging through an attack: DODGED.
--
-- MANUAL SETUP: fill in SOUND_IDS with your own audio asset IDs. Empty strings are skipped,
-- so the game runs silently but correctly until you do. No placeholder IDs are invented
-- here, and every sound the game can make is in this one table (K4).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Palette = require(Shared:WaitForChild("Config"):WaitForChild("Palette"))
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local HitStop = require(script.Parent:WaitForChild("HitStop"))
local ClientSettings = require(script.Parent:WaitForChild("ClientSettings"))
local PlayerAnimController = require(script.Parent:WaitForChild("PlayerAnimController"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))

local FEEL = GameConfig.Feel
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local FeedbackController = {}

-- Every sound hook in the game. Fill these in; leave what you don't have as "".
local SOUND_IDS = {
	-- combat
	hitLight = "", -- e.g. "rbxassetid://0000000000"
	hitHeavy = "",
	takeDamage = "",
	kill = "",
	enemyWindup = "",
	enemyAlert = "",
	block = "",
	blocked = "", -- your hit clangs off a shield
	dodge = "",
	dash = "",
	stagger = "",
	-- loot
	lootPickup = "",
	rarityCommon = "",
	rarityUncommon = "",
	rarityRare = "",
	rarityEpic = "",
	rarityLegendary = "",
	rarityMythic = "", -- §37: must be instantly recognisable
	chestOpen = "",
	-- world
	door = "",
	alarm = "",
	footstepStone = "",
	footstepWood = "",
	footstepWater = "",
	torchCrackle = "",
	ambientDrone = "",
	-- moments
	extraction = "",
	death = "",
	bossRoar = "",
	phaseTransition = "",
	bossMusic = "", -- looped while a boss fight is on (G3)
	rankUp = "",
	-- ui
	uiClick = "",
	purchase = "",
}

local function playSound(name: string, volume: number?)
	local id = SOUND_IDS[name]
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = (volume or 0.6) * (ClientSettings.Get("SfxVolume") or 1)
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 5)
end

-- Other controllers play hooks through this, so the ID table stays in one place.
function FeedbackController.PlaySound(name: string, volume: number?)
	playSound(name, volume)
end

-- One looping music track at a time. A blank id, or nil, means silence.
local music: Sound? = nil
local musicName: string? = nil
function FeedbackController.SetMusic(name: string?)
	if name == musicName then
		return
	end
	musicName = name
	if music then
		music:Stop()
		music:Destroy()
		music = nil
	end
	local id = name and SOUND_IDS[name]
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "PTK_Music"
	s.SoundId = id
	s.Looped = true
	s.Volume = 0.5 * (ClientSettings.Get("MusicVolume") or 1)
	s.Parent = SoundService
	s:Play()
	music = s
end

-- A full-screen flash (the boss phase transition). Starts white-hot, fades out.
local flashGui: ScreenGui? = nil
local function screenFlash(color: Color3, time: number)
	if not flashGui then
		local g = Instance.new("ScreenGui")
		g.Name = "PTK_Flash"
		g.ResetOnSpawn = false
		g.IgnoreGuiInset = true
		g.DisplayOrder = 15
		g.Parent = player:WaitForChild("PlayerGui")
		local f = Instance.new("Frame")
		f.Name = "Flash"
		f.Size = UDim2.fromScale(1, 1)
		f.BorderSizePixel = 0
		f.BackgroundTransparency = 1
		f.Parent = g
		flashGui = g
	end
	local frame = (flashGui :: ScreenGui):FindFirstChild("Flash") :: Frame
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 0.15
	TweenService:Create(frame, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end

-- 0 at nothing, 1 at HeavyHitDamage and above.
local function significance(damage: number): number
	return math.clamp(damage / FEEL.HeavyHitDamage, 0, 1)
end

-- Floating text at a world position. `scale` sizes it by significance.
local function floatingText(position: Vector3, text: string, color: Color3, scale: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = CFrame.new(position + Vector3.new(math.random(-15, 15) / 10, 2.5, 0))
	anchor.Parent = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(140 * scale, 50 * scale)
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeColor3 = Palette.pitch
	label.TextStrokeTransparency = 0
	label.Font = UIStyle.FONT
	label.TextScaled = true
	label.Parent = billboard

	-- Numbers punch (art §5): land big, settle.
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 1.6
	uiScale.Parent = label
	TweenService:Create(uiScale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()

	TweenService:Create(anchor, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = anchor.CFrame * CFrame.new(0, 4, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.7), { TextTransparency = 1, TextStrokeTransparency = 1 })
		:Play()

	Debris:AddItem(anchor, 0.8)
end

local function damageNumber(position: Vector3, amount: number, color: Color3, scale: number)
	floatingText(position, tostring(math.floor(amount)), color, scale)
end

-- ── Sparks at the contact point (pooled: no create/destroy per hit, §41) ──
local SPARK_POOL = 8
local sparkPool: { { Part: BasePart, Emitter: ParticleEmitter } } = {}
local sparkIndex = 0

local function makeSpark()
	local part = Instance.new("Part")
	part.Name = "PTK_Spark"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Parent = workspace
	local emitter = Instance.new("ParticleEmitter")
	-- Default particle texture (a built-in asset), rate 0: emitted in bursts only.
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.18, 0.4)
	emitter.Speed = NumberRange.new(12, 26)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.LightEmission = 1
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Drag = 4
	emitter.Parent = part
	return { Part = part, Emitter = emitter }
end

local function sparks(position: Vector3, count: number, color: Color3)
	if #sparkPool < SPARK_POOL then
		table.insert(sparkPool, makeSpark())
	end
	sparkIndex = sparkIndex % #sparkPool + 1
	local spark = sparkPool[sparkIndex]
	spark.Part.CFrame = CFrame.new(position)
	spark.Emitter.Color = ColorSequence.new(color)
	spark.Emitter:Emit(count)
end

-- The killing blow: the enemy flashes white and fades. Unmistakable with the sound off.
local function killFlash(target: Instance?)
	if not target or not target:IsA("Model") then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Adornee = target
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.OutlineColor = Palette.bleed
	highlight.FillTransparency = 0.1
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = target
	TweenService:Create(highlight, TweenInfo.new(FEEL.KillFlashTime, Enum.EasingStyle.Quad), {
		FillTransparency = 1,
		OutlineTransparency = 1,
	}):Play()
	Debris:AddItem(highlight, FEEL.KillFlashTime + 0.05)
end

-- Very short camera nudge, scaled by the reduced-shake setting (§40).
local function cameraKick(strength: number)
	if camera.CameraType == Enum.CameraType.Scriptable then
		return -- the death camera is drifting; a kick would fight its tween
	end
	strength *= ClientSettings.ShakeFactor()
	if strength <= 0 then
		return
	end
	local start = os.clock()
	local duration = 0.12
	local conn
	conn = RunService.RenderStepped:Connect(function()
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

-- Public, so boss attacks and other moments can shake through the same setting.
function FeedbackController.Kick(strength: number)
	cameraKick(strength)
end

local function onDealt(data)
	-- Sparks and the kill flash show for everyone's hits; numbers, hit-stop and kicks
	-- only for this player's own, to keep the screen readable.
	local s = significance(data.Damage)
	local heavy = s >= 1
	local mine = data.Attacker == player.UserId
	sparks(
		data.Position,
		if data.Killed
			then FEEL.SparkCountKill
			elseif heavy or data.Finisher then FEEL.SparkCountHeavy
			else FEEL.SparkCount,
		if data.Killed then Palette.bleed else Palette.ember
	)
	if data.Killed then
		killFlash(data.Target)
	end
	if not mine then
		return
	end

	local scale = FEEL.HitScaleMin + (FEEL.HitScaleMax - FEEL.HitScaleMin) * s
	if data.Finisher or data.Heavy then
		scale *= FEEL.FinisherHitStopBonus
	end
	local numberScale = 1 + (FEEL.NumberScaleMax - 1) * s + (if data.Killed then FEEL.KillNumberBonus else 0)
	damageNumber(data.Position, data.Damage, UIStyle.TEXT, numberScale)
	if data.Killed then
		-- A boss's final blow (G3): the longest freeze in the game, then the held beat the
		-- server keeps before the body falls.
		local boss = data.Target and data.Target:GetAttribute("Boss") == true
		HitStop.Freeze(
			if boss then GameConfig.Captain.DeathHold * 0.35 else FEEL.HeavyHitStopTime * math.max(scale, 1)
		)
		cameraKick(if boss then GameConfig.Captain.PhaseKick else FEEL.KickKill)
		playSound("kill")
	else
		HitStop.Freeze(FEEL.HitStopTime * scale)
		cameraKick(FEEL.KickHit * scale)
		playSound(if heavy or data.Finisher then "hitHeavy" else "hitLight")
	end
	if data.Staggered then
		playSound("stagger", 0.7)
	end
end

local function onTaken(data)
	damageNumber(
		data.Position,
		data.Damage,
		Palette.bleed,
		1 + (FEEL.NumberScaleMax - 1) * significance(data.Damage)
	)
	local heavy = data.Damage >= FEEL.HeavyHitDamage
	if heavy then
		HitStop.Freeze(FEEL.HeavyHitStopTime) -- e.g. Bronn's CRUSHING BLOW
	end
	cameraKick(if heavy then FEEL.KickHeavyTaken else FEEL.KickTaken)
	playSound("takeDamage")
end

function FeedbackController.Init()
	Net.Event("HitConfirm").OnClientEvent:Connect(function(data)
		if data.Kind == "dealt" then
			onDealt(data)
		elseif data.Kind == "taken" then
			onTaken(data)
		elseif data.Kind == "dodged" then
			-- Through the attack with the i-frames: the reward for reading the windup.
			floatingText(data.Position, "DODGED", Palette.escape, 1.2)
			playSound("dodge", 0.7)
		elseif data.Kind == "blocked" then
			-- A shield took it (F3): a clang, stone sparks, and the attacker recoils. The
			-- normal attack simply does not work here; that must be unmistakable. An immune
			-- boss (mid-roar) only sparks.
			sparks(data.Position, FEEL.SparkCountHeavy, Palette.stone)
			if data.Attacker == player.UserId and not data.Immune then
				floatingText(data.Position, "BLOCKED", UIStyle.TEXT, 1.1)
				cameraKick(FEEL.KickTaken)
				HitStop.Freeze(FEEL.HitStopTime)
				PlayerAnimController.Play("HitReact")
				playSound("blocked", 0.8)
			end
		end
	end)

	Net.Event("Notify").OnClientEvent:Connect(function(data)
		if data.Kind == "gold" or data.Kind == "loot" then
			playSound("lootPickup")
		elseif data.Kind == "weapon" then
			playSound("rarity" .. tostring(data.Rarity or "Common"), 0.8)
		elseif data.Kind == "alarm" then
			playSound("alarm", 0.8)
		elseif data.Kind == "enemyAlert" then
			playSound("enemyAlert", 0.6)
		elseif data.Kind == "bossIntro" then
			FeedbackController.SetMusic("bossMusic")
			playSound("bossRoar", 0.8)
		elseif data.Kind == "bossPhase" then
			-- The moment (G1): a flash, a hard camera push, the sting.
			screenFlash(Palette.ember, GameConfig.Captain.PhaseFlashTime)
			cameraKick(GameConfig.Captain.PhaseKick)
			HitStop.Freeze(FEEL.HeavyHitStopTime)
			playSound("phaseTransition", 1)
			playSound("bossRoar", 0.9)
		elseif data.Kind == "bossDefeated" or data.Kind == "bossReset" then
			FeedbackController.SetMusic(nil)
		end
	end)

	Net.Event("ScreenEvent").OnClientEvent:Connect(function(data)
		if data.Kind == "escaped" then
			playSound("extraction", 0.9)
		elseif data.Kind == "captured" then
			playSound("death", 0.9)
		end
	end)
end

return FeedbackController
