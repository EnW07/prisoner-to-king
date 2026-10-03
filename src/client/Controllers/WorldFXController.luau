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

local FEEL = GameConfig.Feel
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
	if torchAccumulator < 1 / FEEL.TorchUpdateRate then
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

	task.spawn(function()
		local drops = workspace:WaitForChild("LootDrops")
		for _, part in drops:GetChildren() do
			watchLoot(part)
		end
		drops.ChildAdded:Connect(watchLoot)
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
	end)
end

return WorldFXController
