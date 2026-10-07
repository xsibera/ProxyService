--!strict
--[[
	MovementClient (StarterPlayer > StarterPlayerScripts): sprinting and rolling for this player,
	and the dust everyone kicks up.

	Sprinting raises this player's walk speed from Config.WalkSpeed to Config.SprintSpeed, and only
	from exactly that: whatever else sets the walk speed (swinging, charging, blocking, a stun) wins
	while it lasts, and the sprint comes back when it ends if the key is still held. Rolls move the
	character here (the client owns its physics) and ask the server for the untouchable part.
]]

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Movement = ReplicatedStorage:WaitForChild("Movement")
local Config = require(Movement:WaitForChild("Config")) :: any
local Remote = Movement:WaitForChild("Remote") :: RemoteEvent
local AnimationFolder = Movement:WaitForChild("Animations")
local Sounds = Movement:FindFirstChild("Sounds")
local VFX = require(ReplicatedStorage:WaitForChild("CombatVFX")) :: any
local Combat = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("Combat")) :: any

local ROLL = Config.Roll

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

local function onFloor(humanoid: Humanoid): boolean
	return humanoid.FloorMaterial ~= Enum.Material.Air
end

--------------------------------------------------------------------------- animations

local warned = false
local function animation(name: string): Animation?
	local id = Config.Animations[name]
	if typeof(id) == "string" and id ~= "" then
		local a = Instance.new("Animation")
		a.AnimationId = id
		return a
	end
	local source = AnimationFolder:FindFirstChild(name)
	if not (source and source:IsA("Animation")) then
		return nil
	end
	if source.AnimationId ~= "" then
		return source
	end
	-- unpublished: register the KeyframeSequence for a temporary id (works in Studio only)
	local ok, temporary = pcall(function()
		return KeyframeSequenceProvider:RegisterKeyframeSequence(
			source:FindFirstChildOfClass("KeyframeSequence") :: any
		)
	end)
	if ok and typeof(temporary) == "string" then
		local a = Instance.new("Animation")
		a.AnimationId = temporary
		return a
	elseif not warned then
		warned = true
		warn("Movement: publish the Sprint and Roll animations and put their ids in Movement.Config.Animations")
	end
	return nil
end

local sprintTrack: AnimationTrack? = nil
local rollTrack: AnimationTrack? = nil

local function loadTracks(character: Model)
	sprintTrack, rollTrack = nil, nil
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:WaitForChild("Animator", 10)
	if not (animator and animator:IsA("Animator")) then
		return
	end
	local function load(name: string, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
		local source = animation(name)
		if not source then
			return nil
		end
		local ok, track = pcall(function()
			return animator:LoadAnimation(source)
		end)
		if ok and track then
			track.Priority = priority
			track.Looped = looped
			return track
		end
		return nil
	end
	sprintTrack = load("Sprint", Enum.AnimationPriority.Movement, true)
	rollTrack = load("Roll", Enum.AnimationPriority.Action3, false)
end

local function sound(name: string, at: Vector3)
	local template = Sounds and Sounds:FindFirstChild(name)
	if not (template and template:IsA("Sound")) then
		return
	end
	local holder = Instance.new("Attachment")
	holder.Name = "MovementSound"
	holder.CFrame = CFrame.new(at) -- Terrain sits at the origin
	holder.Parent = workspace.Terrain
	local s = template:Clone()
	s.Parent = holder
	s:Play()
	Debris:AddItem(holder, 3)
end

--------------------------------------------------------------------------- sprinting

local sprintKeyHeld = false -- Left Ctrl is held
local sprintW = false -- W was double-tapped and is still held
local sprintToggled = false -- gamepad / touch toggle
local lastW = -math.huge
local rollingUntil = 0

local function setFOV(fov: number)
	local camera = workspace.CurrentCamera
	if camera and camera.FieldOfView ~= fov then
		TweenService:Create(camera, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { FieldOfView = fov }):Play()
	end
end

local sprinting = false
local function updateSprint()
	local character, _, humanoid = parts(player)
	if not (character and humanoid) then
		return
	end
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local want = (sprintKeyHeld or sprintW or sprintToggled)
		and moving
		and humanoid.Health > 0
		and os.clock() >= rollingUntil
	-- only ever between the two: anything else that set the walk speed is left alone
	if want and humanoid.WalkSpeed == Config.WalkSpeed then
		humanoid.WalkSpeed = Config.SprintSpeed
	elseif not want and humanoid.WalkSpeed == Config.SprintSpeed then
		humanoid.WalkSpeed = Config.WalkSpeed
	end
	local now = humanoid.WalkSpeed == Config.SprintSpeed and moving and onFloor(humanoid)
	if now ~= sprinting then
		sprinting = now
		if sprintTrack then
			if now then
				sprintTrack:Play(0.2)
			else
				sprintTrack:Stop(0.2)
			end
		end
		setFOV(if now then Config.SprintFOV else 70)
	end
end

--------------------------------------------------------------------------- rolling

local readyAt = 0

local function rollDirection(root: BasePart, humanoid: Humanoid): Vector3
	local dir = flat(humanoid.MoveDirection)
	if dir == Vector3.zero then
		dir = flat(root.CFrame.LookVector)
	end
	return if dir ~= Vector3.zero then dir else Vector3.new(0, 0, -1)
end

-- the burst, the trail and the dust of a roll, on anyone's root (others' come from the server)
local function rollEffects(character: Model, root: BasePart, dir: Vector3)
	VFX.Play("DashBurst", CFrame.lookAt(root.Position, root.Position + dir), { Ignore = { character } })
	local trail = VFX.Start("DashTrail", root, { Ignore = { character } })
	sound("Roll", root.Position)
	task.delay(ROLL.Time, function()
		trail:Stop()
		if root.Parent then
			VFX.Play("Land", CFrame.new(root.Position - Vector3.new(0, 3, 0)), { Ignore = { character }, Scale = 0.8 })
		end
	end)
end

local function tryRoll()
	local character, root, humanoid = parts(player)
	if not (character and root and humanoid and humanoid.Health > 0) then
		return
	end
	local now = os.clock()
	if now < readyAt or now < rollingUntil or Combat.isStunned(character) or Combat.isBusy(character) then
		return
	end
	readyAt = now + ROLL.Cooldown
	rollingUntil = now + ROLL.Time
	local dir = rollDirection(root, humanoid)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	if rollTrack then
		rollTrack:Play(0.05)
	end
	-- the push: fast at first, easing off; only along the floor, so gravity still has its way
	local attachment = Instance.new("Attachment")
	attachment.Name = "MovementRoll"
	attachment.Parent = root
	local push = Instance.new("LinearVelocity")
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	push.PrimaryTangentAxis = Vector3.xAxis
	push.SecondaryTangentAxis = Vector3.zAxis
	push.MaxForce = 6e4
	push.PlaneVelocity = Vector2.new(dir.X, dir.Z) * ROLL.Speed
	push.Parent = attachment
	local started = now
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local t = (os.clock() - started) / ROLL.Time
		if t >= 1 or not attachment.Parent then
			connection:Disconnect()
			attachment:Destroy()
			return
		end
		local speed = ROLL.Speed * (1 - t) ^ 0.6
		push.PlaneVelocity = Vector2.new(dir.X, dir.Z) * speed
	end)
	rollEffects(character, root, dir)
	Remote:FireServer("Roll", dir)
end

--------------------------------------------------------------------------- input

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.KeyCode == Config.SprintKey then
		sprintKeyHeld = true
	elseif input.KeyCode == Enum.KeyCode.W and Config.DoubleTapW then
		local now = os.clock()
		if now - lastW <= Config.DoubleTapTime then
			sprintW = true
		end
		lastW = now
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Config.SprintKey then
		sprintKeyHeld = false
	elseif input.KeyCode == Enum.KeyCode.W then
		sprintW = false
	end
end)

ContextActionService:BindAction("MovementRoll", function(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		tryRoll()
	end
	return Enum.ContextActionResult.Sink
end, Config.MobileButtons, ROLL.Key, ROLL.Button)
ContextActionService:BindAction("MovementSprint", function(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		sprintToggled = not sprintToggled
	end
	return Enum.ContextActionResult.Sink
end, Config.MobileButtons, Config.SprintButton)
if Config.MobileButtons then
	ContextActionService:SetTitle("MovementRoll", "Roll")
	ContextActionService:SetTitle("MovementSprint", "Sprint")
end

--------------------------------------------------------------------------- server events

Remote.OnClientEvent:Connect(function(kind: string, a: any, b: any)
	if kind == "Roll" then -- a: the roller, b: direction
		if a ~= player then
			local character, root = parts(a)
			if character and root and typeof(b) == "Vector3" then
				rollEffects(character, root, b)
			end
		end
	elseif kind == "Denied" then -- a: seconds left on the cooldown
		if typeof(a) == "number" and a > 0 then
			readyAt = math.max(readyAt, os.clock() + a)
		end
	end
end)

--------------------------------------------------------------------------- every frame

-- dust off anyone running fast along the floor (sprinting players, someone knocked back...)
local dust: { [Model]: any } = {}
RunService.Heartbeat:Connect(function()
	updateSprint()
	for _, other in Players:GetPlayers() do
		local character, root, humanoid = parts(other)
		if character and root and humanoid then
			local v = root.AssemblyLinearVelocity
			local fast = Vector3.new(v.X, 0, v.Z).Magnitude > Config.DustSpeed and onFloor(humanoid)
			if fast and not dust[character] then
				dust[character] = VFX.Start("RunDust", root, { Ignore = { character } })
			elseif not fast and dust[character] then
				dust[character]:Stop()
				dust[character] = nil
			end
		end
	end
	for character, handle in dust do
		if not character.Parent then
			handle:Stop()
			dust[character] = nil
		end
	end
end)

--------------------------------------------------------------------------- the character

local function onCharacter(character: Model)
	sprinting = false
	rollingUntil = 0
	loadTracks(character)
end
if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)
