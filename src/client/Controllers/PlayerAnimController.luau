--!strict
-- PlayerAnimController.lua
-- Plays the player's own actions on their character, and other players' replicated swings
-- on theirs. (MASTER_BUILD_SPEC C4 player coverage, C5 blending, L3 swing replication.)
--
-- LOCOMOTION is Roblox's own Animate script, which every player character gets: idle with
-- breathing, walk, run, jump, fall. This controller adds the ACTIONS on top, through the
-- rig's real joints (PoseAnimator), or through a clip when AnimationConfig.Player names one:
--   Light1/2/3   the combo stages (CombatController asks for them)
--   Heavy, Dash, Block                       (Section E wires the inputs)
--   HitReact     on taking damage, when not mid-swing
--   Land         on landing from a fall
--   Interact     on triggering a prompt
--   Celebrate    on ESCAPED
--   Death        handed to the death sequence (Section D)
--
-- Joint offsets set here are LOCAL: a client's joint changes never replicate. Other
-- players see this player's swing because the server rebroadcasts each validated attack
-- (CombatVisual) and every other client plays the same move on that character here.
--
-- Hit-stop: every pose tween on this client is registered with HitStop, so a landed hit
-- freezes the swing mid-arc and it resumes in step.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local AnimationConfig = require(Config:WaitForChild("AnimationConfig"))
local WeaponConfig = require(Config:WaitForChild("WeaponConfig"))
local Anim = Shared:WaitForChild("Anim")
local Rig = require(Anim:WaitForChild("Rig"))
local PoseAnimator = require(Anim:WaitForChild("PoseAnimator"))
local HitStop = require(script.Parent:WaitForChild("HitStop"))

local ANIM = GameConfig.Animation
local player = Players.LocalPlayer
local PlayerAnimController = {}

-- The local weapon's weight class, from StateUpdate.
local weight = "Medium"
-- Characters we failed to open, so the warning prints once per character.
local unposeable: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
-- Loaded clip tracks per Animator and slot. Weak: a dead character's Animator is collected.
local clips: { [Instance]: { [string]: AnimationTrack | false } } = setmetatable({}, { __mode = "k" }) :: any

-- A character's limbs arrive over a few frames after CharacterAdded (and stream in for
-- other players). Opening the rig early would cache a partial joint set for its whole
-- life, so wait for the last limb parts before opening.
local function ready(character: Model): boolean
	if character:FindFirstChild("UpperTorso") then
		return character:FindFirstChild("RightFoot") ~= nil and character:FindFirstChild("LeftFoot") ~= nil
	end
	return character:FindFirstChild("Right Leg") ~= nil and character:FindFirstChild("Left Leg") ~= nil
end

local function rigFor(character: Model): Rig.Rig?
	if not ready(character) then
		return nil
	end
	local rig = Rig.Open(character)
	if not rig and not unposeable[character] then
		unposeable[character] = true
		warn(("[PlayerAnim] %s has no poseable joints; actions won't move its body"):format(character.Name))
	end
	return rig
end

-- A configured clip for a slot, loaded once per Animator. nil when the slot has no clip
-- or it failed to load (then the procedural move is used instead).
local function clipFor(character: Model, key: string): AnimationTrack?
	local id = (AnimationConfig.Player :: any)[key]
	if type(id) ~= "string" then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local perAnimator = clips[animator]
	if not perAnimator then
		perAnimator = {}
		clips[animator] = perAnimator
	end
	local cached = perAnimator[key]
	if cached == nil then
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, result = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if ok and result then
			result.Priority = Enum.AnimationPriority.Action
			cached = result
		else
			warn(
				("[PlayerAnim] Clip for %s failed to load; using the procedural move: %s"):format(
					key,
					tostring(result)
				)
			)
			cached = false
		end
		perAnimator[key] = cached
	end
	return cached or nil
end

-- Play a slot on any character: the clip if configured, else the procedural move.
function PlayerAnimController.PlayOn(character: Model, key: string, weightName: string?): PoseAnimator.Handle?
	local clip = clipFor(character, key)
	if clip then
		-- No HitStop.Track: HitStop already freezes every playing track on the local
		-- Animator, and other players' clips are theirs to time.
		clip:Play(ANIM.FadeTime)
		return nil
	end
	local moveName = AnimationConfig.Player.Procedural[key]
	local rig = rigFor(character)
	if not moveName or not rig then
		return nil
	end
	return PoseAnimator.Play(rig, moveName, { Weight = weightName or "Medium" })
end

-- Play a slot on the local character with the equipped weapon's weight.
function PlayerAnimController.Play(key: string): PoseAnimator.Handle?
	local character = player.Character
	if not character then
		return nil
	end
	return PlayerAnimController.PlayOn(character, key, weight)
end

-- True while a move is playing on the local character (so a flinch doesn't cut a swing).
function PlayerAnimController.IsBusy(): boolean
	local character = player.Character
	local rig = character and Rig.Open(character)
	return rig ~= nil and PoseAnimator.IsBusy(rig)
end

-- Ease the local character back to rest (releasing a block, cancelling an action).
function PlayerAnimController.Relax()
	local character = player.Character
	local rig = character and Rig.Open(character)
	if rig then
		PoseAnimator.Relax(rig, ANIM.RelaxTime)
	end
end

-- Hold the local character exactly as it is and stop every clip: the frame of death.
function PlayerAnimController.Freeze()
	local character = player.Character
	if not character then
		return
	end
	local rig = Rig.Open(character)
	if rig then
		PoseAnimator.Freeze(rig)
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, t in animator:GetPlayingAnimationTracks() do
			t:Stop(0)
		end
	end
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	-- Landing from a fall squashes and recovers. Jump → Landed also fires, which is fine:
	-- a small squash on every landing reads as weight.
	humanoid.StateChanged:Connect(function(_old, new)
		if new == Enum.HumanoidStateType.Landed and humanoid.Health > 0 then
			if not PlayerAnimController.IsBusy() then
				PlayerAnimController.PlayOn(character, "Land", weight)
			end
		end
	end)
	-- Nothing from this life may leak into the next: the rig entry dies with the model.
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			Rig.Close(character)
		end
	end)
end

function PlayerAnimController.Init()
	PoseAnimator.OnTween = HitStop.Track

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	Net.Event("StateUpdate").OnClientEvent:Connect(function(state)
		local w = state.WeaponId and WeaponConfig.Get(state.WeaponId)
		weight = (w and w.Weight) or "Medium"
	end)

	-- Taking a hit flinches, unless a swing is in flight: cancelling the player's own
	-- attack to flinch would make every trade feel like losing control.
	Net.Event("HitConfirm").OnClientEvent:Connect(function(data)
		if data.Kind == "taken" and not PlayerAnimController.IsBusy() then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				PlayerAnimController.Play("HitReact")
			end
		end
	end)

	Net.Event("ScreenEvent").OnClientEvent:Connect(function(data)
		if data.Kind == "escaped" then
			PlayerAnimController.Play("Celebrate")
		end
	end)

	-- Fires on this client when the local player triggers a prompt.
	ProximityPromptService.PromptTriggered:Connect(function(_prompt, who)
		if who == player and not PlayerAnimController.IsBusy() then
			PlayerAnimController.Play("Interact")
		end
	end)

	-- Other players' validated swings (CombatService rebroadcasts them). The server never
	-- sends the local player's own: that one already played on input.
	Net.Event("CombatVisual").OnClientEvent:Connect(function(data)
		if type(data) ~= "table" or data.UserId == player.UserId then
			return
		end
		local other = Players:GetPlayerByUserId(data.UserId)
		local character = other and other.Character
		if character and type(data.Key) == "string" then
			PlayerAnimController.PlayOn(character, data.Key, data.Weight)
		end
	end)
end

return PlayerAnimController
