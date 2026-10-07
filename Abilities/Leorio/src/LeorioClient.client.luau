--!strict
--[[
	LeorioClient (StarterPlayer > StarterPlayerScripts): the keys, the animations and every warp
	hole and fist this player sees.

	With a Loadout in the place its keys are whichever slots the abilities sit in; without one they
	are Config.Keys (Z X C V). Your own cast starts at once (you turn to where the camera looks, the
	animation, the aura gathering in the fist); where the holes open is the server's call, so they
	arrive from it, for everyone alike, timed to its clock.
]]

local ContextActionService = game:GetService("ContextActionService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Leorio = ReplicatedStorage:WaitForChild("Leorio")
local Config = require(Leorio:WaitForChild("Config")) :: any
local VFX = require(Leorio:WaitForChild("LeorioVFX")) :: any
local Remote = Leorio:WaitForChild("Remote") :: RemoteEvent
local AnimationFolder = Leorio:WaitForChild("Animations")

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

local HAND = CFrame.new(0, -1.05, 0) -- the fist, in an R6 arm
local ABILITIES = Config.Abilities :: { string }
local ANIMATION_OF = { -- ability -> Config.Animations key
	WarpPunch = "WarpPunch",
	RemoteJab = "RemoteJab",
	WarpBarrage = "Barrage",
	PortalBurst = "Burst",
}

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
				warn("Leorio: publish the animations and put their ids in Leorio.Config.Animations")
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
		if other ~= name and track.IsPlaying then
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

local function fistPosition(character: Model, side: string): Vector3?
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

-- the floor under a point (looking through characters), or the point 3 below it
local function floorUnder(point: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(skip, other.Character)
		end
	end
	params.FilterDescendantsInstances = skip
	local result = workspace:Raycast(point + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), params)
	return if result then result.Position else point - Vector3.new(0, 3, 0)
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

-- the colours of the fists that come out of the holes: his own skin, his suit
local function fistLook(caster: Player, scale: number): { [string]: any }
	local fist = Config.Fist
	local skin = fist.SkinColor
	local character = caster.Character
	local arm = character and limb(character, "Right Arm")
	if fist.SkinFromCaster and arm then
		skin = arm.Color
	end
	return { Scale = scale, Skin = skin, Sleeve = fist.SleeveColor, Cuff = fist.CuffColor }
end

--------------------------------------------------------------------------- cooldowns and the hotbar

local busyUntil = 0
local ready: { [string]: number } = { All = 0 }

local fallbackSlots: { [string]: Frame } = {}
if not Loadout then
	-- no Loadout menu in the place: a small bar of its own
	local gui = Instance.new("ScreenGui")
	gui.Name = "LeorioUI"
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
		slot.BackgroundColor3 = Color3.fromRGB(16, 26, 26)
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
		label.TextColor3 = Color3.fromRGB(200, 255, 240)
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
		TweenService:Create(slot, TweenInfo.new(0.35), { BackgroundColor3 = Color3.fromRGB(16, 26, 26) }):Play()
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
local running: { [Player]: { [Fx]: boolean } } = {}

-- remember an effect of `caster`'s, so a Stop can close it; returns it
local function keep(caster: Player, fx: Fx): Fx
	local list = running[caster] or {}
	running[caster] = list
	list[fx] = true
	return fx
end

local function release(caster: Player, fx: Fx)
	local list = running[caster]
	if list and list[fx] then
		list[fx] = nil
		fx:Stop()
	end
end

local function dropAll(caster: Player)
	local list = running[caster]
	if not list then
		return
	end
	running[caster] = nil
	for fx in list do
		fx:Stop()
	end
end

local function portal(caster: Player, cframe: CFrame, radius: number, closeAt: number): Fx
	local hole = VFX.Portal(cframe, radius)
	local fx = keep(caster, {
		Stop = function()
			hole:Close()
		end,
	})
	at(closeAt, function()
		release(caster, fx)
	end)
	return fx
end

-- the aura gathering in a fist until `untilTime`
local function charge(caster: Player, side: string, untilTime: number)
	local character = caster.Character
	local arm = character and limb(character, side .. " Arm")
	if not arm then
		return
	end
	local attached = VFX.Attach("FistCharge", arm, HAND, { Charge = 0 })
	local fx = keep(caster, attached)
	local started = serverNow()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local t = serverNow()
		if t >= untilTime or not arm.Parent then
			connection:Disconnect()
			release(caster, fx)
			return
		end
		attached:SetCharge((t - started) / math.max(untilTime - started, 0.05))
	end)
end

-- a fist going into the floor (into a little hole under it): the hole, the ripple and dust, the trace
local function intoTheFloor(caster: Player, side: string, closeAt: number, traceTo: Vector3?, travel: number)
	local character = caster.Character
	local fist = character and fistPosition(character, side)
	if not (character and fist) then
		return
	end
	local floor = floorUnder(fist)
	local spot = CFrame.lookAt(floor + Vector3.new(0, 0.06, 0), floor + Vector3.new(0, 1.06, 0))
	portal(caster, spot, 1.1, closeAt)
	VFX.Play("GroundPunch", CFrame.new(floor + Vector3.new(0, 0.3, 0)), { Ignore = { character } })
	VFX.Sound("Slam", floor, 0.8)
	if traceTo then
		VFX.Trace(floor + Vector3.new(0, 0.2, 0), floorUnder(traceTo) + Vector3.new(0, 0.2, 0), travel)
	end
end

-- a fist punching out of `hole` at hitAt, and the hole closing after
local function punchOut(caster: Player, hole: CFrame, radius: number, hitAt: number, scale: number, reach: number)
	local fx = portal(caster, hole, radius, hitAt + 0.38)
	at(hitAt, function()
		local list = running[caster]
		if not (list and list[fx]) then
			return -- cut short
		end
		VFX.Play("PortalBurst", hole)
		local options = fistLook(caster, scale)
		options.Reach = reach
		local fist = VFX.Fist(hole, options)
		keep(caster, {
			Stop = function()
				fist:Retract()
			end,
		})
		VFX.Sound("Punch", hole.Position, 1)
	end)
end

local function warpPunchEffects(caster: Player, hole: CFrame, punchAt: number, hitAt: number)
	local settings = Config.WarpPunch
	charge(caster, "Right", punchAt)
	VFX.Sound("Charge", hole.Position, 0.5)
	at(punchAt, function()
		local target = hole.Position + hole.LookVector * settings.Distance
		intoTheFloor(caster, "Right", hitAt + 0.3, target, hitAt - punchAt)
		punchOut(caster, hole, settings.Radius, hitAt, Config.Fist.Scale, settings.Distance + 1.4)
		if caster == player then
			shake(0.25)
		end
	end)
end

local function jabEffects(caster: Player, hole: CFrame, jabAt: number, hitAt: number)
	local settings = Config.RemoteJab
	punchOut(caster, hole, settings.Radius, hitAt, Config.Fist.Scale * 0.8, settings.Distance + 1.2)
	at(jabAt, function()
		local character, root = parts(caster)
		local fist = character and fistPosition(character, "Left")
		if not (root and fist) then
			return
		end
		local look = flat(root.CFrame.LookVector)
		local spot = CFrame.lookAt(fist + look * 0.4, fist + look * 1.4)
		portal(caster, spot, 1.0, hitAt + 0.1)
		VFX.Play("PortalBurst", spot, { Scale = 0.6 })
		VFX.Sound("Warp", fist, 0.7)
	end)
end

local function barrageEffects(caster: Player, index: number, hole: CFrame, punchAt: number, hitAt: number)
	local settings = Config.WarpBarrage
	local step = settings.Hits[index]
	if not step then
		return
	end
	local last = step.Above == true
	local side = if last or index % 2 == 1 then "Right" else "Left"
	at(punchAt, function()
		intoTheFloor(caster, side, hitAt + 0.25, hole.Position + hole.LookVector * 2, hitAt - punchAt)
		if last and caster == player then
			shake(0.3)
		end
	end)
	if last then
		punchOut(caster, hole, step.Radius or 2.8, hitAt, Config.Fist.Scale * 1.25, 7)
	else
		punchOut(caster, hole, settings.Radius, hitAt, Config.Fist.Scale * 0.85, settings.Distance + 1.2)
	end
end

local function burstEffects(caster: Player, center: Vector3, burstAt: number, eruptAt: number, holes: { CFrame })
	local settings = Config.PortalBurst
	local _, root = parts(caster)
	if root then
		local aura = VFX.Attach("Aura", root, CFrame.identity, { Charge = 1 })
		local fx = keep(caster, aura)
		at(eruptAt + 0.2, function()
			release(caster, fx)
		end)
	end
	charge(caster, "Right", burstAt)
	charge(caster, "Left", burstAt)
	at(burstAt, function()
		VFX.Play("BurstRing", CFrame.new(center + Vector3.new(0, 0.3, 0)), { Ignore = { caster.Character } })
		VFX.Sound("Slam", center, 1)
		if caster == player then
			shake(0.35)
		end
	end)
	for _, hole in holes do
		if typeof(hole) == "CFrame" then
			portal(caster, hole, settings.HoleRadius, eruptAt + 0.4)
			at(eruptAt, function()
				local list = running[caster]
				if not list then
					return
				end
				VFX.Play("PortalBurst", hole)
				local options = fistLook(caster, Config.Fist.Scale * 0.95)
				options.Reach = 4.5
				options.Hold = 0.18
				local fist = VFX.Fist(hole, options)
				keep(caster, {
					Stop = function()
						fist:Retract()
					end,
				})
			end)
		end
	end
	at(eruptAt, function()
		VFX.Sound("Punch", center, 1)
	end)
end

local HEAVY = { WarpPunch = true, PortalBurst = true }

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
	local dir = if typeof(push) == "Vector3" and push.Magnitude > 1e-3 then push else Vector3.zAxis
	local heavy = HEAVY[ability] == true or (ability == "WarpBarrage" and dir.Y < -0.5)
	VFX.Play(if heavy then "WarpHeavy" else "WarpHit", CFrame.lookAt(position, position + dir), { Ignore = { victim } })
	VFX.Sound("Hit", position, if outcome == "Hit" then 1 else 0.5)
	local character = player.Character
	if victim == character then
		shake(if heavy then 0.5 else 0.22)
	elseif caster == player then
		shake(if heavy then 0.3 else 0.12)
	end
end

--------------------------------------------------------------------------- casting (this player)

local function cast(ability: string)
	if not canStart(ability) then
		return
	end
	local settings = Config[ability]
	local _, root = parts(player)
	if not root then
		return
	end
	-- turn to where the camera looks: that's where he's aiming
	local look = flat(cameraLook() or root.CFrame.LookVector)
	if look ~= Vector3.zero then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
	end
	busyUntil = os.clock() + settings.Recovery
	startCooldown(ability)
	play(ANIMATION_OF[ability])
	Remote:FireServer("Cast", ability, cameraLook())
	if ability == "RemoteJab" then
		charge(player, "Left", serverNow() + settings.JabAt)
	elseif ability == "WarpBarrage" then
		local _, myRoot = parts(player)
		if myRoot then
			local aura = VFX.Attach("Aura", myRoot, CFrame.identity, { Charge = 1 })
			local fx = keep(player, aura)
			task.delay(settings.Length, function()
				release(player, fx)
			end)
		end
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
		local action = "Leorio" .. ability
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
	if kind == "WarpPunch" then -- a: caster, b: hole, c: punchAt, d: hitAt
		warpPunchEffects(a, b, c, d)
	elseif kind == "Jab" then -- a: caster, b: hole, c: jabAt, d: hitAt
		jabEffects(a, b, c, d)
	elseif kind == "Barrage" then -- a: caster, b: index, c: hole, d: punchAt, e: hitAt
		barrageEffects(a, b, c, d, e)
	elseif kind == "Burst" then -- a: caster, b: center, c: burstAt, d: eruptAt, e: holes
		burstEffects(a, b, c, d, e)
	elseif kind == "Hit" then -- a: caster, b: victim, c: ability, d: position, e: outcome, f: push
		hitEffects(a, b, c, d, e, f)
	elseif kind == "Stop" then -- a: caster
		dropAll(a)
		if a == player then
			busyUntil = 0
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
	end
end)

Players.PlayerRemoving:Connect(function(who: Player)
	dropAll(who)
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
	dropAll(player)
	loadTracks(character)
end

if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)
