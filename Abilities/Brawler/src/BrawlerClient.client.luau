--!strict
--[[
	BrawlerClient (StarterPlayer > StarterPlayerScripts): the keys, the animations, the lunges, the
	effects, and the grabs as this player sees them.

	With a Loadout in the place its keys are whichever slots the moves sit in; without one they are
	Config.Keys. Your own moves start at once (you turn to where the camera looks, the animation, the
	step in, the swing trail); the server decides what they hit, and whether a grab connects.

	A grab that connects is played the same on every client: the grabber's throw (his own client
	plays it, and it replicates), the victim's side of it played here on the victim, and the victim
	carried along the throw's path (Brawler.GrabPaths) from the grabber's spot until they're let go.
	Being slammed down, they get back up (Brawler Get Up).

	Effects come from the combat effects pack (ReplicatedStorage.CombatVFX): the swing trails (fists
	and feet), the hits, the ground slam and the body slams.
]]

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Brawler = ReplicatedStorage:WaitForChild("Brawler")
local Config = require(Brawler:WaitForChild("Config")) :: any
local GrabPaths = require(Brawler:WaitForChild("GrabPaths")) :: any
local Remote = Brawler:WaitForChild("Remote") :: RemoteEvent
local AnimationFolder = Brawler:WaitForChild("Animations")
local VFX = require(ReplicatedStorage:WaitForChild("CombatVFX")) :: any

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local function optional(folderName: string, moduleName: string): any
	local folder = ReplicatedStorage:FindFirstChild(folderName)
	local module = folder and folder:FindFirstChild(moduleName)
	return if module and module:IsA("ModuleScript") then require(module) :: any else nil
end
local Loadout = optional("Loadout", "Loadout")
local Combat = optional("Combat", "Combat")

local ABILITIES = Config.Abilities :: { string }
local GRABS = { GrabThrow = true, Suplex = true, Chokeslam = true }
local Sounds = Brawler:FindFirstChild("Sounds")

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- run fn at server time `t` (at once if that's past)
local function at(t: number, fn: () -> ())
	task.delay(math.max(t - serverNow(), 0), fn)
end

--------------------------------------------------------------------------- animations

local animations: { [string]: Animation } = {}
local warnedStudioOnly = false

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
			elseif not warnedStudioOnly then
				warnedStudioOnly = true
				warn("Brawler: publish the animations and put their ids in Brawler.Config.Animations")
			end
		end
	end
	if result then
		animations[name] = result
	end
	return result
end

-- tracks per model: this player's own, and the ones played here on others (held victims)
local trackCache: { [Model]: { [string]: AnimationTrack } } = {}

local function track(model: Model, name: string): AnimationTrack?
	local cache = trackCache[model]
	if not cache then
		cache = {}
		trackCache[model] = cache
		model.AncestryChanged:Connect(function()
			if not model.Parent then
				trackCache[model] = nil
			end
		end)
	end
	if cache[name] then
		return cache[name]
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local source = animation(name)
	if not (animator and source) then
		return nil
	end
	local ok, loaded = pcall(function()
		return (animator :: Animator):LoadAnimation(source :: Animation)
	end)
	if not (ok and loaded) then
		return nil
	end
	loaded.Priority = Enum.AnimationPriority.Action
	cache[name] = loaded
	return loaded
end

local function play(model: Model, name: string, fade: number?): AnimationTrack?
	local cache = trackCache[model]
	if cache then
		for other, t in cache do
			if other ~= name and t.IsPlaying then
				t:Stop(0.06)
			end
		end
	end
	local t = track(model, name)
	if t then
		t:Play(fade or 0.05)
	end
	return t
end

local function stopAll(model: Model, fade: number?)
	for _, t in trackCache[model] or {} do
		if t.IsPlaying then
			t:Stop(fade or 0.15)
		end
	end
end

--------------------------------------------------------------------------- helpers

local function parts(who: Player): (Model?, BasePart?, Humanoid?)
	local character = who.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and root and root:IsA("BasePart") then
		return character, root, humanoid
	end
	return nil, nil, nil
end

local function rootOf(model: Instance): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zero
end

local function cameraLook(): Vector3?
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.LookVector else nil
end

-- a velocity held on the root for `seconds` (the step in)
local function drive(root: BasePart, velocity: Vector3, seconds: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = "BrawlerDrive"
	attachment.Parent = root
	local force = Instance.new("LinearVelocity")
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.MaxForce = 1e6
	force.VectorVelocity = velocity
	force.Parent = attachment
	Debris:AddItem(attachment, seconds)
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
		if t > 0.2 or not humanoid.Parent then
			humanoid.CameraOffset = Vector3.zero
			connection:Disconnect()
			return
		end
		local k = strength * (1 - t / 0.2)
		humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * k
	end)
end

local function options(ignore: { Instance }): any
	return { Ignore = ignore, Color = Config.Color }
end

-- a sound from Brawler.Sounds at a point
local function sound(name: string, position: Vector3, volume: number?)
	local source = Sounds and Sounds:FindFirstChild(name)
	if not (source and source:IsA("Sound")) then
		return
	end
	local holder = Instance.new("Part")
	holder.Name = "BrawlerSound"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(position)
	holder.Parent = workspace
	local s = source:Clone()
	s.Volume *= volume or 1
	s.Parent = holder
	s:Play()
	Debris:AddItem(holder, 4)
end

--------------------------------------------------------------------------- cooldowns and the hotbar

type Carry = { victim: Model, path: any, origin: CFrame, startAt: number, stopped: boolean }
local carries: { [Model]: Carry } = {} -- who is being carried along a throw, here

local busyUntil = 0
local ready: { [string]: number } = { All = 0 }

local fallbackSlots: { [string]: Frame } = {}
if not Loadout then
	-- no Loadout menu in the place: a small bar of its own
	local gui = Instance.new("ScreenGui")
	gui.Name = "BrawlerUI"
	gui.ResetOnSpawn = false
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -14)
	bar.Size = UDim2.fromOffset(#ABILITIES * 84 - 6, 50)
	bar.BackgroundTransparency = 1
	bar.Parent = gui
	for i, ability in ABILITIES do
		local slot = Instance.new("Frame")
		slot.Name = ability
		slot.Position = UDim2.fromOffset((i - 1) * 84, 0)
		slot.Size = UDim2.fromOffset(78, 50)
		slot.BackgroundColor3 = Color3.fromRGB(28, 22, 20)
		slot.BackgroundTransparency = 0.15
		slot.ClipsDescendants = true
		slot.Parent = bar
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = slot
		local shade = Instance.new("Frame")
		shade.Name = "Cooldown"
		shade.AnchorPoint = Vector2.new(0, 1)
		shade.Position = UDim2.fromScale(0, 1)
		shade.Size = UDim2.fromScale(1, 0)
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BackgroundTransparency = 0.4
		shade.BorderSizePixel = 0
		shade.Parent = slot
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 12
		label.TextWrapped = true
		label.TextColor3 = Color3.fromRGB(255, 225, 200)
		local key = Config.Keys[ability]
		label.Text = (if key then key.Name .. "\n" else "") .. Config.DisplayNames[ability]
		label.ZIndex = 2
		label.Parent = slot
		fallbackSlots[ability] = slot
	end
	gui.Parent = player:WaitForChild("PlayerGui")
end

local function startCooldown(ability: string)
	local now = os.clock()
	ready[ability] = now + Config[ability].Cooldown
	ready.All = now + Config.SharedCooldown
	if Loadout then
		Loadout.setCooldown(ability, ready[ability], Config[ability].Cooldown)
	end
end

local function denyFlash(ability: string)
	if Loadout then
		Loadout.deny(ability)
		return
	end
	local slot = fallbackSlots[ability]
	if slot then
		slot.BackgroundColor3 = Color3.fromRGB(140, 30, 30)
		TweenService:Create(slot, TweenInfo.new(0.35), { BackgroundColor3 = Color3.fromRGB(28, 22, 20) }):Play()
	end
end

-- may this player start a move now (as far as this client knows; the server has the last word)
local function canStart(ability: string): boolean
	local character, root, humanoid = parts(player)
	if not (character and root and humanoid and humanoid.Health > 0) or root.Anchored or carries[character] then
		return false
	end
	local now = os.clock()
	if now < busyUntil or now < (ready[ability] or 0) or now < ready.All then
		denyFlash(ability)
		return false
	end
	if Combat and (Combat.isStunned(character) or Combat.isBlocking(character)) then
		denyFlash(ability)
		return false
	end
	return true
end

--------------------------------------------------------------------------- the grabs

local function pathAt(path: any, t: number): CFrame
	local frames = path.Frames
	local x = math.clamp(t / path.Step, 0, #frames - 1)
	local i = math.floor(x)
	local a, b = frames[i + 1], frames[math.min(i + 2, #frames)]
	return CFrame.new(table.unpack(a)):Lerp(CFrame.new(table.unpack(b)), x - i)
end

RunService.RenderStepped:Connect(function()
	local t = serverNow()
	for victim, carry in carries do
		local root = rootOf(victim)
		if not root or not victim.Parent then
			carries[victim] = nil
		elseif t >= carry.startAt then
			root.CFrame = carry.origin * pathAt(carry.path, t - carry.startAt)
		end
	end
end)

local function grabbed(caster: Player, victim: Model, ability: string, origin: CFrame, startAt: number)
	local settings = Config[ability]
	local path = GrabPaths[settings.Throw]
	if not (path and victim:IsA("Model")) then
		return
	end
	carries[victim] = { victim = victim, path = path, origin = origin, startAt = startAt, stopped = false }
	local victimRoot = rootOf(victim)
	sound("Grab", if victimRoot then victimRoot.Position else origin.Position, 0.8)
	at(startAt, function()
		if carries[victim] and carries[victim].origin == origin then
			play(victim, path.Victim, 0.05)
		end
	end)
	if caster == player then
		busyUntil = os.clock() + (startAt - serverNow()) + path.Length
		local character = player.Character
		if character then
			at(startAt, function()
				play(character, path.Attacker, 0.05)
			end)
		end
	end
	-- the body hitting the floor
	if settings.Effect then
		at(startAt + path.Hit, function()
			local carry = carries[victim]
			if not carry or carry.origin ~= origin then
				return
			end
			local body = origin * pathAt(path, path.Hit)
			local floor = Vector3.new(body.X, origin.Y - 3, body.Z)
			VFX.Play(settings.Effect, CFrame.new(floor), options({ victim, caster.Character :: Instance }))
			VFX.Play("HeavyHit", CFrame.lookAt(body.Position, body.Position - Vector3.yAxis), options({ victim }))
			sound("Slam", floor, 1)
			if victim == player.Character or caster == player then
				shake(if victim == player.Character then 0.6 else 0.35)
			end
		end)
	end
end

local function released(_caster: Player, victim: Model, ability: string, cframe: CFrame, early: boolean)
	carries[victim] = nil
	local root = rootOf(victim)
	if root and typeof(cframe) == "CFrame" then
		victim:PivotTo(cframe)
	end
	local path = GrabPaths[Config[ability].Throw]
	if path and path.GetUp and not early then
		play(victim, "GetUp", 0.08)
	else
		stopAll(victim, 0.15)
	end
end

--------------------------------------------------------------------------- casting (this player)

local function cast(ability: string)
	if not canStart(ability) then
		return
	end
	local settings = Config[ability]
	local character, root = parts(player)
	if not (character and root) then
		return
	end
	if Config.TurnToCamera then
		local look = flat(cameraLook() or root.CFrame.LookVector)
		if look ~= Vector3.zero then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
		end
	end
	local grab = GRABS[ability] == true
	busyUntil = os.clock() + (if grab then Config.Grab.WhiffRecovery else settings.Recovery)
	startCooldown(ability)
	local t = play(character, if grab then "Grab" else settings.Animation)
	Remote:FireServer("Cast", ability, cameraLook())
	task.delay(math.max((if grab then Config.Grab.At else settings.HitDelay) - 0.12, 0), function()
		if root.Parent then
			sound("Swing", root.Position, 0.8)
		end
	end)
	if settings.Swing and t then
		VFX.Swing(settings.Swing, character, t, options({ character }))
	end
	local lunge = if grab then Config.Grab.Lunge else settings.Lunge
	if lunge then
		local look = flat(root.CFrame.LookVector)
		task.delay(lunge.At, function()
			if root.Parent and not root.Anchored and os.clock() < busyUntil then
				drive(root, look * (lunge.Distance / lunge.Time), lunge.Time)
			end
		end)
	end
	if ability == "GroundSlam" then
		local look = flat(root.CFrame.LookVector)
		task.delay(settings.HitDelay, function()
			if root.Parent and os.clock() < busyUntil + 0.1 then
				local floor = root.Position + look * settings.Ahead - Vector3.new(0, 3, 0)
				VFX.Play("GroundSlam", CFrame.new(floor), options({ character }))
				sound("Slam", floor, 1)
				shake(0.45)
			end
		end)
	end
end

--------------------------------------------------------------------------- input

for _, ability in ABILITIES do
	local function handler(state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			cast(ability)
		end
	end
	if Loadout then
		Loadout.bind(ability, handler)
	else
		local inputs = {}
		if Config.Keys[ability] then
			table.insert(inputs, Config.Keys[ability])
		end
		if Config.GamepadButtons[ability] then
			table.insert(inputs, Config.GamepadButtons[ability])
		end
		local action = "Brawler" .. ability
		ContextActionService:BindAction(action, function(_, state: Enum.UserInputState)
			handler(state)
			return Enum.ContextActionResult.Sink
		end, Config.MobileButtons, table.unpack(inputs))
		if Config.MobileButtons then
			ContextActionService:SetTitle(action, Config.DisplayNames[ability])
		end
	end
end

--------------------------------------------------------------------------- server events

-- someone else's strike: the swing trail on them, and the slam on the floor
local function otherStrike(caster: Player, ability: string, hitAt: number)
	local settings = Config[ability]
	local character, root = parts(caster)
	if not (character and root and settings) then
		return
	end
	if settings.Swing then
		VFX.Swing(settings.Swing, character, nil, options({ character }) :: any)
	end
	at(hitAt - 0.12, function()
		if root.Parent then
			sound("Swing", root.Position, 0.6)
		end
	end)
	if ability == "GroundSlam" then
		local look = flat(root.CFrame.LookVector)
		at(hitAt, function()
			if root.Parent then
				local floor = root.Position + look * settings.Ahead - Vector3.new(0, 3, 0)
				VFX.Play("GroundSlam", CFrame.new(floor), options({ character }))
				sound("Slam", floor, 1)
			end
		end)
	end
end

local function hitEffects(
	caster: Player,
	victim: Instance,
	ability: string,
	position: Vector3,
	outcome: string,
	push: any
)
	if outcome ~= "Hit" and outcome ~= "Blocked" then
		return
	end
	local settings = Config[ability]
	local effect = settings and settings.Effect
	if GRABS[ability] or not effect or effect == "BodySlam" then
		effect = if ability == "GrabThrow" and outcome == "Hit" then "M1Final" else nil
	end
	if effect == nil then
		return
	end
	if outcome == "Blocked" then
		effect = "M1Hit"
	end
	local dir = if typeof(push) == "Vector3" and push.Magnitude > 1e-3 then push else Vector3.zAxis
	VFX.Play(effect, CFrame.lookAt(position, position + dir), options({ victim, caster.Character :: Instance }))
	sound(if effect == "HeavyHit" then "Heavy" else "Punch", position, if outcome == "Hit" then 1 else 0.5)
	if victim == player.Character then
		shake(if effect == "HeavyHit" then 0.5 else 0.25)
	elseif caster == player then
		shake(if effect == "HeavyHit" then 0.3 else 0.14)
	end
end

Remote.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any, e: any, f: any)
	if kind == "Strike" then -- a: caster, b: ability, c: hitAt
		if a ~= player then
			otherStrike(a, b, c)
		end
	elseif kind == "Grabbed" then -- a: caster, b: victim, c: ability, d: origin, e: startAt
		grabbed(a, b, c, d, e)
	elseif kind == "Released" then -- a: caster, b: victim, c: ability, d: cframe, e: early
		released(a, b, c, d, e)
	elseif kind == "Hit" then -- a: caster, b: victim, c: ability, d: position, e: outcome, f: push
		hitEffects(a, b, c, d, e, f)
	elseif kind == "Stop" then -- a: caster
		if a == player then
			busyUntil = 0
			local character = player.Character
			if character then
				stopAll(character, 0.1)
			end
		end
	elseif kind == "Denied" then -- a: ability, b: seconds left
		if typeof(b) == "number" and b > 0 then
			ready[a] = math.max(ready[a] or 0, os.clock() + b)
			if Loadout then
				Loadout.setCooldown(a, ready[a], Config[a].Cooldown)
			end
		end
		busyUntil = 0
		denyFlash(a)
	end
end)

--------------------------------------------------------------------------- every frame: the fallback bar

if not Loadout then
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for ability, slot in fallbackSlots do
			local left = math.max((ready[ability] or 0) - now, ready.All - now, 0)
			local shade = slot:FindFirstChild("Cooldown")
			if shade and shade:IsA("Frame") then
				shade.Size = UDim2.fromScale(1, math.clamp(left / math.max(Config[ability].Cooldown, 0.01), 0, 1))
			end
		end
	end)
end

--------------------------------------------------------------------------- the character

local function onCharacter(character: Model)
	busyUntil = 0
	trackCache[character] = nil
	for _, name in { "Haymaker", "Uppercut", "Roundhouse", "AxeKick", "GroundSlam", "Grab" } do
		task.spawn(track, character, name) -- loaded up front, so the first press isn't late
	end
end

if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)
