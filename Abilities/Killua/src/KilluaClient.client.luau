--!strict
--[[
	KilluaClient (StarterPlayer > StarterPlayerScripts): the keys, the animations, the movement and
	every lightning effect this player sees.

	With a Loadout in the place its keys are whichever slots the abilities sit in; without one they
	are Config.Keys (Z X C V). Your own casts show at once (animation, effects, the lunge, the leap,
	the dashes); everyone else's arrive from the server, which owns the timing, cooldowns and hits.
]]

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Killua = ReplicatedStorage:WaitForChild("Killua")
local Config = require(Killua:WaitForChild("Config")) :: any
local VFX = require(Killua:WaitForChild("KilluaVFX")) :: any
local Remote = Killua:WaitForChild("Remote") :: RemoteEvent
local AnimationFolder = Killua:WaitForChild("Animations")

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

local HAND = CFrame.new(0, -1.05, 0) -- the hand, in an R6 arm
local ABILITIES = Config.Abilities :: { string }

local function serverNow(): number
	return workspace:GetServerTimeNow()
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
				warn("Killua: publish the animations and put their ids in Killua.Config.Animations")
			end
		end
	end
	if result then
		animations[name] = result
	end
	return result
end

local tracks: { [string]: AnimationTrack } = {}

local function loadTracks(character: Model)
	table.clear(tracks)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:WaitForChild("Animator", 10)
	if not (animator and animator:IsA("Animator")) then
		return
	end
	for name in Config.Animations do
		local source = animation(name)
		if source then
			local ok, track = pcall(function()
				return animator:LoadAnimation(source)
			end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action
				tracks[name] = track
			end
		end
	end
end

local function play(name: string, fade: number?)
	for other, track in tracks do
		if other ~= name and track.IsPlaying and other ~= "Land" then
			track:Stop(0.06)
		end
	end
	local track = tracks[name]
	if track then
		track:Play(fade or 0.05)
	end
end

local function stopAll(fade: number?)
	for _, track in tracks do
		if track.IsPlaying then
			track:Stop(fade or 0.15)
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

local function limb(character: Model, name: string): BasePart?
	local part = character:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

local function handPosition(character: Model, side: string): Vector3?
	local arm = limb(character, side .. " Arm")
	return if arm then (arm.CFrame * HAND).Position else nil
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zero
end

local function cameraLook(): Vector3?
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.LookVector else nil
end

local function charactersExcept(...: Instance?): { Instance }
	local list: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	for _, item in { ... } do
		if item then
			table.insert(list, item)
		end
	end
	return list
end

-- the floor under a point (looking through characters), or nil
local function groundBelow(point: Vector3, exclude: { Instance }): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip = table.clone(exclude)
	for _ = 1, 6 do
		params.FilterDescendantsInstances = skip
		local result = workspace:Raycast(point, Vector3.new(0, -24, 0), params)
		if not result then
			return nil
		end
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			table.insert(skip, model)
		else
			return result.Position
		end
	end
	return nil
end

-- a velocity held on the root for `seconds` (the palm's lunge)
local function drive(root: BasePart, velocity: Vector3, seconds: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = "KilluaDrive"
	attachment.Parent = root
	local force = Instance.new("LinearVelocity")
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.MaxForce = 1e6
	force.VectorVelocity = velocity
	force.Parent = attachment
	Debris:AddItem(attachment, seconds)
end

--------------------------------------------------------------------------- cooldowns and the hotbar

local busyUntil = 0
local ready: { [string]: number } = { All = 0 }

local fallbackSlots: { [string]: Frame } = {}
if not Loadout then
	-- no Loadout menu in the place: a small bar of its own
	local gui = Instance.new("ScreenGui")
	gui.Name = "KilluaUI"
	gui.ResetOnSpawn = false
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -14)
	bar.Size = UDim2.fromOffset(#ABILITIES * 104 - 8, 52)
	bar.BackgroundTransparency = 1
	bar.Parent = gui
	for i, ability in ABILITIES do
		local slot = Instance.new("Frame")
		slot.Name = ability
		slot.Position = UDim2.fromOffset((i - 1) * 104, 0)
		slot.Size = UDim2.fromOffset(96, 52)
		slot.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
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
		label.TextSize = 13
		label.TextWrapped = true
		label.TextColor3 = Color3.fromRGB(205, 235, 255)
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
		TweenService:Create(slot, TweenInfo.new(0.35), { BackgroundColor3 = Color3.fromRGB(18, 22, 30) }):Play()
	end
end

-- may this player start an ability now (as far as this client knows; the server has the last word)
local function canStart(ability: string): boolean
	local character, root, humanoid = parts(player)
	if not (character and root and humanoid and humanoid.Health > 0) then
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

--------------------------------------------------------------------------- effects, per caster

type Fx = { Stop: (any) -> () }
local running: { [Player]: { [string]: Fx } } = {}

local function keep(who: Player, key: string, fx: Fx?)
	local list = running[who] or {}
	running[who] = list
	if list[key] then
		list[key]:Stop()
	end
	list[key] = fx
end

local function drop(who: Player, key: string?)
	local list = running[who]
	if not list then
		return
	end
	for k, fx in list do
		if key == nil or k == key then
			fx:Stop()
			list[k] = nil
		end
	end
end

-- Lightning Palm: the lightning gathering in the palm, then going off out of it
local function palmEffects(caster: Player, hitAt: number)
	local character, root = parts(caster)
	local arm = character and limb(character, "Right Arm")
	if not (character and root and arm) then
		return
	end
	local charge = VFX.Attach("HandCharge", arm, HAND, { Charge = 0 })
	keep(caster, "charge", charge)
	keep(caster, "arcs", VFX.Crawl(character, math.max(hitAt - serverNow(), 0.05), { Rate = 14, Thickness = 0.08 }))
	VFX.Sound("Crackle", arm, 0.8)
	local started = serverNow()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = serverNow()
		if t >= hitAt or not arm.Parent then
			connection:Disconnect()
			return
		end
		charge:SetCharge((t - started) / math.max(hitAt - started, 0.05))
	end)
	task.delay(math.max(hitAt - serverNow(), 0), function()
		drop(caster, "charge")
		if not (arm.Parent and root.Parent) then
			return
		end
		local palm = (arm.CFrame * HAND).Position
		local look = flat(root.CFrame.LookVector)
		VFX.Play("PalmBurst", CFrame.lookAt(palm, palm + look), { Ignore = { character } })
		VFX.Strike(palm, palm + look * 8 + Vector3.new(0, 0.5, 0), { Thickness = 0.45, Life = 0.18, Branches = 2 })
		VFX.Sound("PalmHit", palm, 1)
	end)
end

-- Thunderbolt: the warning ring, the lightning between the hands at the top, then the bolt
local function thunderboltEffects(caster: Player, target: Vector3, strikeAt: number)
	local character, root = parts(caster)
	if not (character and root) then
		return
	end
	local holder = Instance.new("Part")
	holder.Name = "ThunderboltMarker"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(target + Vector3.new(0, 0.1, 0))
	holder.Parent = workspace
	local marker = VFX.Attach("StrikeMarker", holder, CFrame.identity, { Charge = 0 })
	Debris:AddItem(holder, math.max(strikeAt - serverNow(), 0) + 2)
	local started = serverNow()
	local hangFrom = started + Config.Thunderbolt.HangFrom - 0.05
	local lastArc = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = serverNow()
		if t >= strikeAt or not character.Parent then
			connection:Disconnect()
			return
		end
		marker:SetCharge((t - started) / math.max(strikeAt - started, 0.05))
		-- lightning gathering between the hands at the top of the leap
		if t >= hangFrom and t - lastArc > 0.07 then
			lastArc = t
			local left, right = handPosition(character, "Left"), handPosition(character, "Right")
			if left and right then
				VFX.Bolt(left, right, { Thickness = 0.25, Life = 0.09, Radius = 0.7, Arrive = 0.02 })
			end
		end
	end)
	VFX.Sound("Crackle", root, 1)
	task.delay(math.max(strikeAt - serverNow(), 0), function()
		marker:Stop()
		local left, right = handPosition(character, "Left"), handPosition(character, "Right")
		local hands = if left and right then (left + right) / 2 else root.Position
		VFX.Strike(
			hands,
			target,
			{ Thickness = 1.1, Life = 0.35, Arrive = 0.05, Branches = 4, Radius = 2.2, Sparks = 8 }
		)
		VFX.Bolt(target + Vector3.new(0, 70, 0), target, { Thickness = 0.6, Life = 0.25, Arrive = 0.06, Radius = 5 })
		VFX.Play("ThunderStrike", CFrame.new(target + Vector3.new(0, 0.3, 0)), { Ignore = { character } })
		VFX.Sound("Thunder", target, 1)
	end)
end

-- Whirlwind's stance: static over the body while the window is open
local function stanceEffects(caster: Player, untilTime: number)
	local character, root = parts(caster)
	if not (character and root) then
		return
	end
	local seconds = math.max(untilTime - serverNow(), 0.05)
	keep(caster, "crackle", VFX.Attach("Crackle", root, CFrame.identity, { Charge = 1 }))
	keep(caster, "arcs", VFX.Crawl(character, seconds, { Rate = 12, Thickness = 0.08 }))
	VFX.Sound("Crackle", root, 0.7)
	task.delay(seconds, function()
		drop(caster, "crackle")
	end)
end

-- a dash: an afterimage where he was, a bolt along the way, bursts at both ends
local function dashEffects(caster: Player, from: Vector3, to: Vector3)
	local character = caster.Character
	local dir = flat(to - from)
	if dir == Vector3.zero then
		dir = Vector3.new(0, 0, -1)
	end
	if character then
		VFX.Ghost(character, CFrame.lookAt(from, from + dir), 0.35)
	end
	local ignore = if character then { character } else {}
	VFX.Play("DashBurst", CFrame.lookAt(from, from + dir), { Ignore = ignore })
	VFX.Play("DashBurst", CFrame.lookAt(to, to + dir), { Ignore = ignore })
	VFX.Bolt(from, to, { Thickness = 0.5, Life = 0.16, Arrive = 0.03, Radius = 1.2, Sparks = 4 })
	VFX.Sound("Dash", to, 1)
end

local function hitEffects(
	caster: Player,
	victim: Instance,
	ability: string,
	position: Vector3,
	outcome: string,
	kind: string
)
	if outcome ~= "Hit" and outcome ~= "Blocked" then
		return
	end
	local from = parts(caster)
	local character = caster.Character
	local origin = if from then from:GetPivot().Position else position
	local dir = flat(position - origin)
	VFX.Play("ShockHit", CFrame.lookAt(position, position + (if dir ~= Vector3.zero then dir else Vector3.zAxis)), {
		Ignore = { victim },
	})
	VFX.Sound("Zap", position, if outcome == "Hit" then 1 else 0.5)
	if ability == "Whirlwind" and character then
		local hand = handPosition(character, "Right")
		if hand then
			VFX.Bolt(hand, position, { Thickness = 0.3, Life = 0.12, Arrive = 0.02 })
		end
	end
	if outcome == "Hit" and kind == "Shock" and victim:IsA("Model") then
		local untilTime = victim:GetAttribute("StunnedUntil")
		local seconds = if typeof(untilTime) == "number" then untilTime - serverNow() else 0.8
		VFX.Crawl(victim, math.clamp(seconds, 0.3, 2), { Rate = 26, Thickness = 0.12, Reach = 0.8 })
	end
end

--------------------------------------------------------------------------- casting (this player)

local leap: { hang: VectorForce?, landing: boolean } = { hang = nil, landing = false }

local function castPalm()
	local ability = "LightningPalm"
	if not canStart(ability) then
		return
	end
	local settings = Config.LightningPalm
	local _, root = parts(player)
	if not root then
		return
	end
	busyUntil = os.clock() + settings.Recovery
	startCooldown(ability)
	play("Palm")
	Remote:FireServer("Cast", ability, cameraLook())
	palmEffects(player, serverNow() + settings.HitDelay)
	task.delay(settings.LungeAt, function()
		if root.Parent and os.clock() < busyUntil then
			drive(root, flat(root.CFrame.LookVector) * (settings.Lunge / settings.LungeTime), settings.LungeTime)
		end
	end)
end

local function endHang()
	if leap.hang then
		local attachment = leap.hang.Attachment0
		leap.hang:Destroy()
		if attachment then
			attachment:Destroy()
		end
		leap.hang = nil
	end
end

local function castThunderbolt()
	local ability = "Thunderbolt"
	if not canStart(ability) then
		return
	end
	local settings = Config.Thunderbolt
	local _, root, humanoid = parts(player)
	if not (root and humanoid) then
		return
	end
	busyUntil = os.clock() + settings.Recovery
	startCooldown(ability)
	play("Thunderbolt")
	Remote:FireServer("Cast", ability, cameraLook())
	task.delay(settings.LeapAt, function()
		if not root.Parent or os.clock() > busyUntil then
			return
		end
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X * 0.3, settings.LeapSpeed, v.Z * 0.3)
		leap.landing = true
	end)
	task.delay(settings.HangFrom, function()
		if not root.Parent or not leap.landing then
			return
		end
		endHang()
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X * 0.5, 0, v.Z * 0.5)
		local attachment = Instance.new("Attachment")
		attachment.Name = "KilluaHang"
		attachment.Parent = root
		local float = Instance.new("VectorForce")
		float.Attachment0 = attachment
		float.RelativeTo = Enum.ActuatorRelativeTo.World
		float.ApplyAtCenterOfMass = true
		float.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity, 0)
		float.Parent = attachment
		leap.hang = float
	end)
	task.delay(settings.HangUntil, endHang)
end

local function castWhirlwind()
	local ability = "Whirlwind"
	if not canStart(ability) then
		return
	end
	local settings = Config.Whirlwind
	busyUntil = os.clock() + settings.Window + settings.WhiffRecovery
	startCooldown(ability)
	play("Stance", 0.03)
	Remote:FireServer("Cast", ability, cameraLook())
	stanceEffects(player, serverNow() + settings.Window)
end

-- Lightning Dash: where to go
local chain: { count: number, lastAt: number, windowUntil: number, target: Model? } =
	{ count = 0, lastAt = -math.huge, windowUntil = 0, target = nil }

local function livingRoot(model: Model?): BasePart?
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if model and model.Parent and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- who to dash at: the chain's target while it's in reach, else whoever is nearest the camera's look
local function dashVictim(from: Vector3, look: Vector3, character: Model, index: number): Model?
	local settings = Config.LightningDash
	local reach = settings.Distance + 3
	local kept = if index > 1 then livingRoot(chain.target) else nil
	if kept and (kept.Position - from).Magnitude <= reach then
		return chain.target
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local best, bestAngle = nil, math.rad(settings.TargetAngle)
	for _, part in workspace:GetPartBoundsInRadius(from, reach, params) do
		local model = part:FindFirstAncestorOfClass("Model")
		local theirRoot = livingRoot(model)
		if model and theirRoot and model ~= character then
			local angle = math.acos(math.clamp(flat(theirRoot.Position - from):Dot(look), -1, 1))
			if angle < bestAngle then
				best, bestAngle = model, angle
			end
		end
	end
	return best
end

-- where dash number `index` goes, and which way he faces when he lands there
local function dashTarget(root: BasePart, character: Model, index: number): (Vector3?, Vector3)
	local settings = Config.LightningDash
	local look = flat(cameraLook() or root.CFrame.LookVector)
	if look == Vector3.zero then
		look = flat(root.CFrame.LookVector)
	end
	local from = root.Position
	local destination = from + look * settings.Distance
	local victim = if settings.AutoTarget then dashVictim(from, look, character, index) else nil
	local victimRoot = livingRoot(victim)
	chain.target = if victimRoot then victim else nil
	if victimRoot then
		local at = victimRoot.Position
		local to = flat(at - from)
		if to == Vector3.zero then
			to = look
		end
		-- the first dash stops just short of them (unless he's already close); the next go through to
		-- the other side, so the chain zigzags: in front, behind, in front
		local through = index > 1 or Vector3.new(at.X - from.X, 0, at.Z - from.Z).Magnitude < 5
		destination = if through then at + to * 2.6 else at - to * 2.2
		destination = Vector3.new(destination.X, from.Y, destination.Z)
	end
	-- not through walls
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = charactersExcept(character)
	local wall = workspace:Raycast(from + Vector3.new(0, 0.5, 0), destination - from, params)
	if wall then
		destination = from + (wall.Position - from) - flat(destination - from) * 1.5
	end
	-- land on the floor, at the same height above it as now
	local exclude = charactersExcept(character)
	local here = groundBelow(from + Vector3.new(0, 1, 0), exclude)
	local height = if here then from.Y - here.Y else 3
	for _ = 1, 4 do
		local there = groundBelow(destination + Vector3.new(0, 6, 0), exclude)
		if there then
			local landed = Vector3.new(destination.X, there.Y + height, destination.Z)
			-- facing them when there is someone (every dash strikes straight ahead), else along the dash
			local facing = flat(if victimRoot then victimRoot.Position - landed else landed - from)
			return landed, if facing ~= Vector3.zero then facing else look
		end
		destination = from + (destination - from) * 0.6
	end
	return nil, look
end

local function castDash()
	local ability = "LightningDash"
	local settings = Config.LightningDash
	local character, root, humanoid = parts(player)
	if not (character and root and humanoid and humanoid.Health > 0) then
		return
	end
	local now = os.clock()
	local index
	if chain.count > 0 and chain.count < settings.Dashes and now <= chain.windowUntil then
		if now - chain.lastAt < settings.MinGap then
			return
		end
		if Combat and (Combat.isStunned(character) or Combat.isBlocking(character)) then
			return
		end
		index = chain.count + 1
	else
		if not canStart(ability) then
			return
		end
		index = 1
	end
	local destination, facing = dashTarget(root, character, index)
	if not destination then
		denyFlash(ability)
		return
	end
	local from = root.Position
	dashEffects(player, from, destination)
	root.CFrame = CFrame.lookAt(destination, destination + facing)
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(0, math.min(v.Y, 0), 0)
	play("Dash" .. index, 0.02)
	chain.count = index
	chain.lastAt = now
	chain.windowUntil = now + settings.ChainWindow
	busyUntil = now + settings.Recovery
	Remote:FireServer("Dash", index, destination)
	if index >= settings.Dashes then
		chain.count = 0
		startCooldown(ability)
	else
		task.delay(settings.ChainWindow + 0.05, function()
			if chain.count == index and chain.lastAt == now then
				chain.count = 0
				startCooldown(ability)
			end
		end)
	end
end

local CASTS = {
	LightningPalm = castPalm,
	Thunderbolt = castThunderbolt,
	Whirlwind = castWhirlwind,
	LightningDash = castDash,
}

--------------------------------------------------------------------------- input

for _, ability in ABILITIES do
	local cast = CASTS[ability]
	local function handler(state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			cast()
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
		local action = "Killua" .. ability
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

Remote.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any, e: any, f: any)
	if kind == "Palm" then -- a: caster, b: hitAt
		if a ~= player then
			palmEffects(a, b)
		end
	elseif kind == "Thunderbolt" then -- a: caster, b: target, c: strikeAt
		thunderboltEffects(a, b, c)
	elseif kind == "Stance" then -- a: caster, b: untilTime
		if a ~= player then
			stanceEffects(a, b)
		end
	elseif kind == "StanceEnd" then -- a: caster, b: evaded
		drop(a, "crackle")
		drop(a, "arcs")
	elseif kind == "Counter" then -- a: caster, b: attacker, c: from (CFrame), d: to (CFrame), e: startAt
		drop(a, "crackle")
		drop(a, "arcs")
		local character = a.Character
		if character then
			VFX.Ghost(character, c, 0.4)
			VFX.Play("Blink", d, { Ignore = { character } })
		end
		VFX.Bolt(c.Position, d.Position, { Thickness = 0.35, Life = 0.14, Arrive = 0.02, Radius = 1.5 })
		VFX.Sound("Dash", d.Position, 1)
		if a == player then
			local _, root = parts(player)
			if root then
				root.CFrame = d
				root.AssemblyLinearVelocity = Vector3.zero
			end
			busyUntil = os.clock() + Config.Whirlwind.Length
			play("Counter", 0.02)
		end
	elseif kind == "Dash" then -- a: caster, b: index, c: from, d: to, e: at
		if a ~= player then
			dashEffects(a, c, d)
		end
	elseif kind == "Hit" then -- a: caster, b: victim, c: ability, d: position, e: outcome, f: stun kind
		hitEffects(a, b, c, d, e, f)
	elseif kind == "Stop" then -- a: caster
		drop(a)
		if a == player then
			busyUntil = 0
			endHang()
			leap.landing = false
			if chain.count > 0 then -- a chain cut short still costs its cooldown (as on the server)
				chain.count = 0
				startCooldown("LightningDash")
			end
			stopAll(0.1)
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
	elseif kind == "DashDenied" then -- a: index, b: back to
		local _, root = parts(player)
		if root and typeof(b) == "Vector3" then
			root.CFrame = CFrame.new(b) * root.CFrame.Rotation
		end
		chain.count = 0
		startCooldown("LightningDash")
	end
end)

Players.PlayerRemoving:Connect(function(who: Player)
	drop(who)
	running[who] = nil
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
	chain.count = 0
	leap.landing = false
	endHang()
	drop(player)
	loadTracks(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.StateChanged:Connect(function(_, new: Enum.HumanoidStateType)
			if new == Enum.HumanoidStateType.Landed and leap.landing then
				leap.landing = false
				endHang()
				play("Land", 0.05)
			end
		end)
	end
end

if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)
