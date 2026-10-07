--!strict
--[[
	MeleeClient (StarterPlayer > StarterPlayerScripts): left click for the M1 string, the animations
	and every M1 effect this player sees.

	Your own swings start at once (the animation, the swing trail, the step in); the server decides
	which hit it is, whether it lands and the stun. Hold the button to keep the string going; a click
	a little early is remembered and thrown as soon as it can be. Everyone else's swings and hits
	arrive from the server.
]]

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Melee = ReplicatedStorage:WaitForChild("Melee")
local Config = require(Melee:WaitForChild("Config")) :: any
local VFX = require(Melee:WaitForChild("CombatVFX")) :: any
local Remote = Melee:WaitForChild("Remote") :: RemoteEvent
local AnimationFolder = Melee:WaitForChild("Animations")
local Sounds = Melee:FindFirstChild("Sounds")
local Combat = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("Combat")) :: any

local HITS = Config.Hits :: { any }
local BUFFER = 0.35 -- a click this long before the next hit opens is kept and thrown when it does

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zero
end

local function parts(who: Player): (Model?, BasePart?, Humanoid?)
	local character = who.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and root and root:IsA("BasePart") and humanoid then
		return character, root, humanoid
	end
	return nil, nil, nil
end

--------------------------------------------------------------------------- animations

local animations: { [string]: Animation } = {}
local warned = false

local function animation(name: string): Animation?
	if animations[name] then
		return animations[name]
	end
	local id = Config.Animations[name]
	local source = AnimationFolder:FindFirstChild(name)
	local result: Animation? = nil
	if typeof(id) == "string" and id ~= "" then
		result = Instance.new("Animation")
		result.AnimationId = id
	elseif source and source:IsA("Animation") then
		if source.AnimationId ~= "" then
			result = source
		else
			-- unpublished: register the KeyframeSequence for a temporary id (works in Studio only)
			local sequence = source:FindFirstChildOfClass("KeyframeSequence")
			local ok, temporary = pcall(function()
				return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence :: KeyframeSequence)
			end)
			if ok and typeof(temporary) == "string" then
				result = Instance.new("Animation")
				result.AnimationId = temporary
			elseif not warned then
				warned = true
				warn("Melee: publish the M1 animations and put their ids in Melee.Config.Animations")
			end
		end
	end
	if result then
		animations[name] = result
	end
	return result
end

local tracks: { AnimationTrack } = {}

local function loadTracks(character: Model)
	table.clear(tracks)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:WaitForChild("Animator", 10)
	if not (animator and animator:IsA("Animator")) then
		return
	end
	for i, hit in HITS do
		local source = animation(hit.Animation)
		if source then
			local ok, track = pcall(function()
				return animator:LoadAnimation(source)
			end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action
				tracks[i] = track
			end
		end
	end
end

local function stopAll(fade: number?)
	for _, track in tracks do
		if track.IsPlaying then
			track:Stop(fade or 0.15)
		end
	end
end

--------------------------------------------------------------------------- sounds

local function sound(name: string, at: Vector3, volume: number?)
	local template = Sounds and Sounds:FindFirstChild(name)
	if not (template and template:IsA("Sound")) then
		return
	end
	local holder = Instance.new("Attachment")
	holder.Name = "MeleeSound"
	holder.CFrame = CFrame.new(at) -- Terrain sits at the origin
	holder.Parent = workspace.Terrain
	local s = template:Clone()
	s.Volume = template.Volume * (volume or 1)
	s.Parent = holder
	s:Play()
	Debris:AddItem(holder, 3)
end

--------------------------------------------------------------------------- the string (this player)

local count = 0 -- hits thrown in the current string
local lastAt = -math.huge -- os.clock() of the last one
local holding = false -- the button is held: keep the string going
local queued = false -- a click came a little early: throw it when the next hit opens

-- the hit that can be thrown now (1..5), or nil and how long until one can be (as the server sees it)
local function nextHit(t: number): (number?, number)
	if count >= #HITS then
		local ready = lastAt + Config.FinisherCooldown
		return if t < ready then nil else 1, math.max(ready - t, 0)
	end
	if count == 0 then
		return 1, 0
	end
	local opens = lastAt + HITS[count].Next
	if t > opens + Config.ComboWindow then
		return 1, 0
	end
	if t < opens then
		return nil, opens - t
	end
	return count + 1, 0
end

-- can this character swing at all (not stunned, blocking, or busy with something else)?
local function free(character: Model): boolean
	if Combat.isStunned(character) or Combat.isBlocking(character) then
		return false
	end
	local busy = character:GetAttribute("BusyUntil")
	if typeof(busy) == "number" and busy > serverNow() + 0.05 then
		-- busy with this string is fine (its next hit is timed here); with anything else it isn't
		local mine = character:GetAttribute("MeleeUntil")
		return typeof(mine) == "number" and (mine == busy or math.abs(busy - mine) < 1e-3)
	end
	return true
end

local function lunge(root: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Name = "MeleeLunge"
	attachment.Parent = root
	local force = Instance.new("LinearVelocity")
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.MaxForce = 4e4
	force.VectorVelocity = flat(root.CFrame.LookVector) * Config.Lunge
	force.Parent = attachment
	Debris:AddItem(attachment, Config.LungeTime)
end

local function swing(index: number)
	local character, root = parts(player)
	if not (character and root) then
		return
	end
	local hit = HITS[index]
	if Config.TurnToCamera then
		local camera = workspace.CurrentCamera
		local look = camera and flat(camera.CFrame.LookVector) or Vector3.zero
		if look ~= Vector3.zero then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
		end
	end
	count = index
	lastAt = os.clock()
	queued = false
	for i, track in tracks do
		if i ~= index and track.IsPlaying then
			track:Stop(0.15)
		end
	end
	local track = tracks[index]
	if track then
		track:Play(0.1)
	end
	VFX.Swing(Config.SwingEffect, character, track, { Color = Config.Color, Duration = hit.HitDelay + 0.3 })
	sound("Swing", root.Position, if index == #HITS then 1.3 else 1)
	Remote:FireServer("M1")
	local started = lastAt
	task.delay(math.max(hit.HitDelay - 0.08, 0), function()
		if lastAt == started and root.Parent and count == index then
			lunge(root)
		end
	end)
end

local function tryM1()
	local character, _, humanoid = parts(player)
	if not (character and humanoid and humanoid.Health > 0) or not free(character) then
		return
	end
	local index, wait = nextHit(os.clock())
	if index then
		swing(index)
	elseif wait <= BUFFER then
		queued = true
	end
end

-- thrown as soon as it opens: a buffered click, or the button still held
RunService.Heartbeat:Connect(function()
	if not (queued or holding) then
		return
	end
	if nextHit(os.clock()) then
		tryM1()
	end
end)

--------------------------------------------------------------------------- input

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	holding = true
	tryM1()
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = false
	end
end)

ContextActionService:BindAction("MeleeM1", function(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		holding = true
		tryM1()
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		holding = false
	end
	return Enum.ContextActionResult.Sink
end, Config.MobileButton, Config.GamepadButton)
if Config.MobileButton then
	ContextActionService:SetTitle("MeleeM1", "Punch")
end

--------------------------------------------------------------------------- server events

-- where a hit goes: from the attacker to the victim
local function hitFrame(attacker: Player, position: Vector3): CFrame
	local _, root = parts(attacker)
	local dir = if root then flat(position - root.Position) else Vector3.zero
	if dir == Vector3.zero and root then
		dir = flat(root.CFrame.LookVector)
	end
	return CFrame.lookAt(position, position + (if dir ~= Vector3.zero then dir else Vector3.zAxis))
end

-- a short shake of the camera (this player threw or took a hit)
local function shake(strength: number)
	local _, _, humanoid = parts(player)
	if not humanoid then
		return
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if t > 0.18 or not humanoid.Parent then
			humanoid.CameraOffset = Vector3.zero
			connection:Disconnect()
			return
		end
		local k = strength * (1 - t / 0.18)
		humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * k
	end)
end

Remote.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any, e: any)
	if kind == "M1" then -- a: attacker, b: index, c: at
		if a == player then
			if b ~= count then
				count = b -- the server's count rules (a lost click, say)
			end
		else
			local character, root = parts(a)
			local hit = HITS[b]
			if character and root and hit then
				VFX.Swing(Config.SwingEffect, character, nil, { Color = Config.Color, Duration = hit.HitDelay + 0.3 })
				sound("Swing", root.Position, if b == #HITS then 1.3 else 1)
			end
		end
	elseif kind == "Hit" then -- a: attacker, b: victim, c: index, d: position, e: outcome
		if e ~= "Hit" then
			return -- blocked and parried hits: ReplicatedStorage.Combat draws those
		end
		local finisher = c == #HITS
		local ignore = { b }
		if a.Character then
			table.insert(ignore, a.Character)
		end
		VFX.Play(
			if finisher then Config.FinisherEffect else Config.HitEffect,
			hitFrame(a, d),
			{ Ignore = ignore, Color = Config.Color }
		)
		sound(if finisher then "Finisher" else "Hit", d, 1)
		if a == player or b == player.Character then
			shake(if finisher then 0.5 else 0.18)
		end
	elseif kind == "Stop" then -- a: attacker
		if a == player then
			count = 0
			queued = false
			stopAll(0.1)
		end
	elseif kind == "Denied" then -- a: the server's count
		if typeof(a) == "number" then
			count = a
		end
		queued = false
		stopAll(0.1) -- the swing never happened
	end
end)

--------------------------------------------------------------------------- the character

local function onCharacter(character: Model)
	count = 0
	queued = false
	loadTracks(character)
end

if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)
