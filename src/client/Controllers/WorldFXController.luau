--!strict
-- WorldFXController.lua
-- Ambient procedural animation, all TweenService or cheap per-frame maths. No imported
-- assets. (VISUAL_OVERHAUL_PLAN Phase 2: torch flicker, chest lid, loot bob and spin.)
--
-- Everything here is LOCAL and cosmetic. The server places each object once and never moves
-- it again, so client-side motion can't fight replication:
--   • torches   — tagged "PTKTorch" by WorldBuilder
--   • chest lid — tagged "PTKChestLid"; open/closed follows THIS player's run state, the
--                 same per-player rule as the cellblock door (M1 bugs 1/2/5)
--   • loot      — starts bobbing once the server marks it Landed after its hop

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local ClientSettings = require(script.Parent:WaitForChild("ClientSettings"))

local FEEL = GameConfig.Feel
-- The graphics preset (J2): LOW hides the light shafts and halves the torch update rate.
local torchRate = FEEL.TorchUpdateRate
local function applyGraphics()
	local low = ClientSettings.Get("GraphicsLow") == true
	torchRate = if low then FEEL.TorchUpdateRate / 2 else FEEL.TorchUpdateRate
	for _, shaft in CollectionService:GetTagged("PTKLightShaft") do
		if shaft:IsA("BasePart") then
			shaft.Transparency = if low then 1 else 0.93
		end
	end
end
local WorldFXController = {}

-- ── Torches ─────────────────────────────────────────────────────
type Torch = { Flame: BasePart, Light: PointLight?, Brightness: number, Size: Vector3, Seed: number }
local torches: { Torch } = {}

local function addTorch(flame: Instance)
	if not flame:IsA("BasePart") then
		return
	end
	local light = flame:FindFirstChildOfClass("PointLight")
	table.insert(torches, {
		Flame = flame,
		Light = light,
		Brightness = light and light.Brightness or 0,
		Size = flame.Size,
		Seed = math.random() * 1000,
	})
end

local torchClock = 0
local torchAccumulator = 0
local function flickerTorches(dt: number)
	torchClock += dt
	torchAccumulator += dt
	if torchAccumulator < 1 / torchRate then
		return
	end
	torchAccumulator = 0
	for _, t in torches do
		if t.Flame.Parent then
			-- math.noise is smooth, so the flame wavers rather than strobing.
			local n = math.noise(torchClock * FEEL.TorchFlickerSpeed, t.Seed) * 2
			local k = 1 + FEEL.TorchFlickerAmount * n
			if t.Light then
				t.Light.Brightness = t.Brightness * k
			end
			t.Flame.Size = Vector3.new(t.Size.X, t.Size.Y * k, t.Size.Z)
		end
	end
end

-- ── Chest lid ───────────────────────────────────────────────────
local lid: BasePart? = nil
local lidClosed: CFrame
local lidOpen: CFrame
local lidIsOpen = false

local function setupLid(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	lid = part
	lidClosed = part.CFrame
	-- Hinge along the back-bottom edge (+Z is the back: the chest sits against the north
	-- wall and the player opens it from the south). Positive rotation about X lifts the front.
	local hinge = lidClosed * CFrame.new(0, -part.Size.Y / 2, part.Size.Z / 2)
	lidOpen = hinge * CFrame.Angles(math.rad(FEEL.ChestLidOpenAngle), 0, 0) * hinge:Inverse() * lidClosed
end

local function setLid(open: boolean)
	if not lid or open == lidIsOpen then
		return
	end
	lidIsOpen = open
	if open then
		TweenService:Create(
			lid,
			TweenInfo.new(FEEL.ChestLidOpenTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ CFrame = lidOpen }
		):Play()
	else
		lid.CFrame = lidClosed -- a fresh run's chest is simply shut
	end
end

-- ── Loot ────────────────────────────────────────────────────────
local bobbing: { [BasePart]: Vector3 } = {}
local lootClock = 0

local function watchLoot(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local function start()
		if part:GetAttribute("Landed") then
			bobbing[part] = part.Position
		end
	end
	start()
	part:GetAttributeChangedSignal("Landed"):Connect(start)
	part.Destroying:Connect(function()
		bobbing[part] = nil
	end)
end

local function bobLoot(dt: number)
	lootClock += dt
	local lift = (math.sin(lootClock * 2 * math.pi / FEEL.LootBobPeriod) + 1) / 2 * FEEL.LootBobHeight
	local spin = CFrame.Angles(0, math.rad(lootClock * FEEL.LootSpinSpeed), 0)
	for part, base in bobbing do
		if part.Parent then
			part.CFrame = CFrame.new(base + Vector3.new(0, lift, 0)) * spin
		else
			bobbing[part] = nil
		end
	end
end

-- ── Set dressing that moves (H1): rats, drips, the ghost knight, water ──
-- All local, all cheap: one RenderStepped pass over a handful of parts.
type Rat = { Part: BasePart, A: Vector3, B: Vector3, T: number, Speed: number, Pause: number }
local rats: { Rat } = {}
type Drip = { Part: BasePart, Top: number, T: number, Period: number }
local drips: { Drip } = {}
local ghosts: { { Parts: { BasePart }, Seed: number } } = {}
local waters: { { Part: BasePart, Base: number } } = {}

local function addRat(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local a, b = part:GetAttribute("A"), part:GetAttribute("B")
	if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		return
	end
	table.insert(
		rats,
		{ Part = part, A = a, B = b, T = math.random(), Speed = 0.18 + math.random() * 0.1, Pause = 0 }
	)
end

local function addDrip(part: Instance)
	if part:IsA("BasePart") then
		table.insert(drips, {
			Part = part,
			Top = tonumber(part:GetAttribute("Top")) or part.Position.Y,
			T = math.random(),
			Period = 1.6 + math.random() * 1.4,
		})
	end
end

local function addGhost(model: Instance)
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	table.insert(ghosts, { Parts = parts, Seed = math.random() * 10 })
end

local function addWater(part: Instance)
	if part:IsA("BasePart") then
		table.insert(waters, { Part = part, Base = part.Position.Y })
	end
end

local dressClock = 0
local function animateDressing(dt: number)
	dressClock += dt
	for _, r in rats do
		if r.Part.Parent then
			if r.Pause > 0 then
				r.Pause -= dt
			else
				r.T += dt * r.Speed
				if r.T >= 1 then
					r.T = 0
					r.A, r.B = r.B, r.A
					r.Pause = 0.8 + math.random() * 2
				end
				local pos = r.A:Lerp(r.B, r.T) + Vector3.new(0, 0.25, 0)
				r.Part.CFrame = CFrame.lookAt(pos, Vector3.new(r.B.X, pos.Y, r.B.Z))
			end
		end
	end
	for _, d in drips do
		if d.Part.Parent then
			d.T = (d.T + dt / d.Period) % 1
			-- Fall from the ceiling, fast toward the end (gravity), reappear at the top.
			local fall = d.T * d.T
			d.Part.Position = Vector3.new(d.Part.Position.X, d.Top - fall * 9, d.Part.Position.Z)
			d.Part.Transparency = if d.T > 0.92 then 1 else 0.3
		end
	end
	for _, g in ghosts do
		local t = (math.sin(dressClock * 0.7 + g.Seed) + 1) / 2 -- 0..1, slow
		local transparency = 0.5 + t * 0.45
		for _, p in g.Parts do
			if p.Parent then
				p.Transparency = transparency
			end
		end
	end
	for _, w in waters do
		if w.Part.Parent then
			w.Part.Position =
				Vector3.new(w.Part.Position.X, w.Base + math.sin(dressClock * 1.3) * 0.06, w.Part.Position.Z)
		end
	end
end

-- ── Trophies (G3) ──────────────────────────────────────────────
-- The hideout is shared; a trophy is yours. Tagged parts carry a Trophy attribute naming
-- the kill; StateUpdate says whether THIS player has it, and the parts show or hide locally.
local trophyCounts: { [string]: number } = {}

local function refreshTrophies()
	for _, part in CollectionService:GetTagged("PTKTrophy") do
		if part:IsA("BasePart") then
			local key = tostring(part:GetAttribute("Trophy") or "")
			local earned = (trophyCounts[key] or 0) > 0
			local target = if earned then 0 else 1
			if part.Transparency ~= target then
				TweenService:Create(part, TweenInfo.new(0.6), { Transparency = target }):Play()
			end
		end
	end
end

-- ── Init ────────────────────────────────────────────────────────
function WorldFXController.Init()
	for _, flame in CollectionService:GetTagged("PTKTorch") do
		addTorch(flame)
	end
	CollectionService:GetInstanceAddedSignal("PTKTorch"):Connect(addTorch)

	for _, part in CollectionService:GetTagged("PTKChestLid") do
		setupLid(part)
	end
	CollectionService:GetInstanceAddedSignal("PTKChestLid"):Connect(setupLid)

	for _, part in CollectionService:GetTagged("PTKRat") do
		addRat(part)
	end
	CollectionService:GetInstanceAddedSignal("PTKRat"):Connect(addRat)
	for _, part in CollectionService:GetTagged("PTKDrip") do
		addDrip(part)
	end
	CollectionService:GetInstanceAddedSignal("PTKDrip"):Connect(addDrip)
	for _, model in CollectionService:GetTagged("PTKGhost") do
		addGhost(model)
	end
	CollectionService:GetInstanceAddedSignal("PTKGhost"):Connect(addGhost)
	for _, part in CollectionService:GetTagged("PTKWater") do
		addWater(part)
	end
	CollectionService:GetInstanceAddedSignal("PTKWater"):Connect(addWater)

	task.spawn(function()
		local drops = workspace:WaitForChild("LootDrops")
		for _, part in drops:GetChildren() do
			watchLoot(part)
		end
		drops.ChildAdded:Connect(watchLoot)
	end)

	applyGraphics()
	ClientSettings.Changed:Connect(function(key)
		if key == "GraphicsLow" then
			applyGraphics()
		end
	end)

	Net.Event("StateUpdate").OnClientEvent:Connect(function(state)
		setLid(state.ChestOpened == true)
		trophyCounts.captain = state.CaptainKills or 0
		refreshTrophies()
	end)
	CollectionService:GetInstanceAddedSignal("PTKTrophy"):Connect(refreshTrophies)

	RunService.RenderStepped:Connect(function(dt)
		flickerTorches(dt)
		bobLoot(dt)
		animateDressing(dt)
	end)
end

return WorldFXController
