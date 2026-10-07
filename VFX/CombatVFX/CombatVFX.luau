--!strict
--[[
	CombatVFX: plays the combat effects in script.Effects.

	CombatVFX.Play(name, cframe, options?) -> Part
		One-shot effect. The effect sits at `cframe`, whose LookVector is the hit / travel direction.
		Its "Ground" attachment is dropped onto the floor under it and turned to the slope.

	CombatVFX.Start(name, part, options?) -> handle
		Continuous effect (DashTrail, SlideDust, RunDust) riding on `part` (usually the
		HumanoidRootPart) until handle:Stop(). Its "Ground" attachment follows the floor under the part.

	CombatVFX.Swing(kind, character, track?, options?) -> handle
		Swing visualisation for an M1, "SwordSwing" or "FistSwing": a trail behind the blade / the
		punching fist, air pulled along behind it, and a burst of air at the fastest point of the
		swing (SwordCut, SwordThrust for stabs, FistPush). Call it when the attack animation starts
		and pass its AnimationTrack: it watches until the track stops (or options.Duration seconds
		without one). The motion drives it: trails only show while the blade / fist moves fast
		relative to the body, so wind-ups, recoveries, walking and turning leave none. The sword
		needs two attachments in the blade, SwingBase and SwingTip (else a part named Blade is used).

	CombatVFX.WatchSwings(animations, characters?) -> handle
		Calls Swing for you: whenever a player's character (or one of `characters`) plays one of
		`animations` ({ [animation id or Animation name] = "SwordSwing" | "FistSwing" }) on this
		client, other players' replicated animations included. Run it once in a LocalScript.

	options (all optional):
		Color: Color3        recolours the Accent emitters and trails (the move's colour)
		Scale: number        scales sizes, speeds and offsets (default 1)
		Ignore: {Instance}   left out of the floor raycast (pass the characters involved)
		Parent: Instance     where one-shot holders go (default workspace)
		Duration: number     Swing without a track: how long to watch (default 1)

	Emitters use the same attributes as the game's existing VFX, so its own emit code can play these
	too: EmitCount, EmitDelay, EmitDuration, GroundOnly (only with floor under it) and
	UseGroundColor (tinted by the floor). Accent and Continuous are added here.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Effects = script:WaitForChild("Effects")

export type Options = {
	Color: Color3?,
	Scale: number?,
	Ignore: { Instance }?,
	Parent: Instance?,
	Duration: number?,
}

export type Handle = {
	Stop: (self: Handle) -> (),
}

local CombatVFX = {}

local FLOOR_PROBE = 14 -- studs below the effect searched for floor
local GROUND_TINT = 0.6 -- how far UseGroundColor emitters move toward the floor colour

local function ignoreList(options: Options?, extra: Instance?): { Instance }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	if options and options.Ignore then
		for _, item in options.Ignore do
			table.insert(list, item)
		end
	end
	if extra then
		table.insert(list, extra)
	end
	return list
end

local function floorUnder(position: Vector3, ignore: { Instance }): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -(FLOOR_PROBE + 2), 0), params)
end

local function floorColor(result: RaycastResult): Color3
	local hit = result.Instance
	if hit:IsA("Terrain") then
		return hit:GetMaterialColor(result.Material)
	elseif hit:IsA("BasePart") then
		return hit.Color
	end
	return Color3.new(0.6, 0.6, 0.6)
end

-- a frame on the floor: up along the surface normal, facing `look` as closely as the slope allows
local function floorFrame(result: RaycastResult, look: Vector3): CFrame
	local up = result.Normal
	local forward = look - up * look:Dot(up)
	if forward.Magnitude < 1e-3 then
		forward = up:Cross(Vector3.xAxis)
	end
	forward = forward.Unit
	return CFrame.fromMatrix(result.Position + up * 0.05, forward:Cross(up), up, -forward)
end

local function scaleSequence(sequence: NumberSequence, k: number): NumberSequence
	local keys = {}
	for _, key in sequence.Keypoints do
		table.insert(keys, NumberSequenceKeypoint.new(key.Time, key.Value * k, key.Envelope * k))
	end
	return NumberSequence.new(keys)
end

local function tint(sequence: ColorSequence, color: Color3, amount: number): ColorSequence
	local keys = {}
	for _, key in sequence.Keypoints do
		table.insert(keys, ColorSequenceKeypoint.new(key.Time, key.Value:Lerp(color, amount)))
	end
	return ColorSequence.new(keys)
end

-- Scale and Accent colour for a freshly cloned effect
local function dress(effect: Instance, options: Options?)
	local scale = options and options.Scale or 1
	local color = options and options.Color
	for _, item in effect:GetDescendants() do
		if item:IsA("ParticleEmitter") then
			if scale ~= 1 then
				item.Size = scaleSequence(item.Size, scale)
				item.Speed = NumberRange.new(item.Speed.Min * scale, item.Speed.Max * scale)
				item.Acceleration *= scale
			end
			if color and item:GetAttribute("Accent") then
				item.Color = ColorSequence.new(color)
			end
		elseif item:IsA("Trail") then
			if color and item:GetAttribute("Accent") then
				item.Color = ColorSequence.new(color)
			end
		elseif item:IsA("Attachment") and scale ~= 1 then
			item.Position *= scale
		end
	end
end

local function number(item: Instance, name: string): number
	local value = item:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

-- fires one burst emitter from its attributes; returns how long its particles can live
local function fire(emitter: ParticleEmitter): number
	local count = number(emitter, "EmitCount")
	if count <= 0 then
		return 0
	end
	local delay, duration = number(emitter, "EmitDelay"), number(emitter, "EmitDuration")
	local function go()
		if not emitter.Parent then
			return
		end
		emitter:Emit(math.max(1, math.round(count)))
		if duration > 0 then
			emitter.Enabled = true
			task.delay(duration, function()
				emitter.Enabled = false
			end)
		end
	end
	if delay > 0 then
		task.delay(delay, go)
	else
		go()
	end
	return delay + duration + emitter.Lifetime.Max / math.max(emitter.TimeScale, 0.05)
end

local function lightFlash(effect: Attachment, color: Color3?)
	local brightness = effect:GetAttribute("LightBrightness")
	if typeof(brightness) ~= "number" then
		return
	end
	local light = Instance.new("PointLight")
	light.Brightness = brightness
	light.Range = number(effect, "LightRange")
	light.Color = color or Color3.new(1, 1, 1)
	light.Shadows = false
	light.Parent = effect
	local time = math.max(number(effect, "LightTime"), 0.05)
	TweenService:Create(light, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
	}):Play()
end

local function template(name: string): Attachment
	local effect = Effects:FindFirstChild(name)
	assert(effect and effect:IsA("Attachment"), "CombatVFX: no effect named " .. name)
	return effect
end

function CombatVFX.Play(name: string, cframe: CFrame, options: Options?): BasePart
	local effect = template(name):Clone()
	dress(effect, options)

	local holder = Instance.new("Part")
	holder.Name = name .. "VFX"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = cframe
	effect.CFrame = CFrame.identity
	effect.Parent = holder

	local floor = floorUnder(cframe.Position, ignoreList(options))
	local ground = effect:FindFirstChild("Ground")
	if floor and ground and ground:IsA("Attachment") then
		ground.WorldCFrame = floorFrame(floor, cframe.LookVector)
	end
	local floorTint = if floor then floorColor(floor) else nil

	holder.Parent = options and options.Parent or workspace
	local longest = 0
	for _, item in effect:GetDescendants() do
		if item:IsA("ParticleEmitter") then
			if item:GetAttribute("GroundOnly") and not floor then
				continue
			end
			if floorTint and item:GetAttribute("UseGroundColor") then
				item.Color = tint(item.Color, floorTint, GROUND_TINT)
			end
			longest = math.max(longest, fire(item))
		end
	end
	lightFlash(effect, options and options.Color)
	Debris:AddItem(holder, longest + 0.5)
	return holder
end

function CombatVFX.Start(name: string, part: BasePart, options: Options?): Handle
	local effect = template(name):Clone()
	dress(effect, options)
	effect.CFrame = CFrame.identity
	effect.Parent = part

	local ground = effect:FindFirstChild("Ground")
	local ignore = ignoreList(options, part.Parent)
	local emitters: { ParticleEmitter } = {}
	local baseColor: { [ParticleEmitter]: ColorSequence } = {}
	for _, item in effect:GetDescendants() do
		if item:IsA("ParticleEmitter") and item:GetAttribute("Continuous") then
			table.insert(emitters, item)
			baseColor[item] = item.Color
			item.Enabled = not item:GetAttribute("GroundOnly")
		end
	end

	local lastTint: Color3? = nil
	local connection = RunService.Heartbeat:Connect(function()
		local floor = floorUnder(part.Position, ignore)
		if floor and ground and ground:IsA("Attachment") then
			ground.WorldCFrame = floorFrame(floor, part.CFrame.LookVector)
		end
		local floorTint = if floor then floorColor(floor) else nil
		for _, emitter in emitters do
			if emitter:GetAttribute("GroundOnly") then
				emitter.Enabled = floor ~= nil
			end
			if floorTint and floorTint ~= lastTint and emitter:GetAttribute("UseGroundColor") then
				emitter.Color = tint(baseColor[emitter], floorTint, GROUND_TINT)
			end
		end
		lastTint = floorTint
	end)

	local stopped = false
	local handle = {}
	function handle.Stop(_self: Handle)
		if stopped then
			return
		end
		stopped = true
		connection:Disconnect()
		local longest = 0
		for _, emitter in emitters do
			emitter.Enabled = false
			longest = math.max(longest, emitter.Lifetime.Max / math.max(emitter.TimeScale, 0.05))
		end
		Debris:AddItem(effect, longest + 0.2)
	end
	return (handle :: any) :: Handle
end

--------------------------------------------------------------------------- swings

local SWING_TIME = 1 -- seconds a Swing without a track watches for
local SWING_TRACK_MAX = 4 -- seconds a track is watched at most while its length isn't known yet
local PAST_PEAK = 0.9 -- the burst fires once the speed drops below this fraction of the swing's peak
local REACH_GATE = 0.2 -- a fist trails only while not pulling in faster than this fraction of its speed
local REACH_WEIGHT = 3 -- how much reaching out counts when picking the punching hand

type SwingPoint = {
	part: BasePart,
	base: Vector3, -- part space: where the blade starts (fists: the fist)
	tip: Vector3, -- part space: the blade's point (fists: the fist)
	shoulder: Motor6D?, -- fists: reach is measured from this joint's socket
	trails: { Trail },
	emitters: { ParticleEmitter },
	wake: Attachment,
	wakeAt: Vector3, -- part space
	prev: Vector3?, -- tip in root space last frame
	prevReach: number,
	velocity: Vector3, -- tip velocity in root space, studs/s
	speed: number,
	reachRate: number, -- studs/s away from the shoulder
	mode: string?, -- nil, "Slash", "Thrust" or "Punch"
	peak: number,
	peakAt: CFrame?, -- where the burst goes: LookVector along the travel, UpVector off the swing plane
	fired: boolean,
}

type Swing = {
	add: (track: AnimationTrack?, options: Options?) -> (),
	handle: Handle,
}

local swings: { [Model]: { [string]: Swing } } = setmetatable({}, { __mode = "k" }) :: any
local warned: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local NO_SWING: Handle = ({ Stop = function() end } :: any) :: Handle

-- the blade's part, and where the blade starts and ends in that part's space
local function findBlade(character: Model): (BasePart?, Vector3, Vector3)
	local base = character:FindFirstChild("SwingBase", true)
	local tip = character:FindFirstChild("SwingTip", true)
	if base and tip and base:IsA("Attachment") and tip:IsA("Attachment") then
		local part, basePart = tip.Parent, base.Parent
		if part and part:IsA("BasePart") and basePart and basePart:IsA("BasePart") then
			return part, part.CFrame:PointToObjectSpace(basePart.CFrame * base.Position), tip.Position
		end
	end
	local blade = character:FindFirstChild("Blade", true)
	if blade and blade:IsA("BasePart") then
		-- along its longest side, pointing away from the hand
		local size = blade.Size
		local half = if size.X >= size.Y and size.X >= size.Z
			then Vector3.new(size.X / 2, 0, 0)
			elseif size.Y >= size.Z then Vector3.new(0, size.Y / 2, 0)
			else Vector3.new(0, 0, size.Z / 2)
		local hand = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
		if hand and hand:IsA("BasePart") then
			if (blade.CFrame * half - hand.Position).Magnitude < (blade.CFrame * -half - hand.Position).Magnitude then
				half = -half
			end
		end
		return blade, -half, half
	end
	return nil, Vector3.zero, Vector3.zero
end

-- the arm (R6: the fist is its lower end) or hand (R15), and its shoulder joint
local function findFist(character: Model, side: string): (BasePart?, Vector3, Motor6D?)
	local arm = character:FindFirstChild(side .. " Arm")
	local joint = character:FindFirstChild(side .. " Shoulder", true)
	if not (arm and arm:IsA("BasePart")) then
		arm = character:FindFirstChild(side .. "Hand")
		joint = character:FindFirstChild(side .. "Shoulder", true)
	end
	if not (arm and arm:IsA("BasePart")) then
		return nil, Vector3.zero, nil
	end
	local fist = if arm.Name == side .. " Arm" then Vector3.new(0, -arm.Size.Y / 2, 0) else Vector3.zero
	return arm, fist, if joint and joint:IsA("Motor6D") then joint else nil
end

local function socket(joint: Motor6D): Vector3?
	local part0 = joint.Part0
	return if part0 then part0.CFrame * joint.C0.Position else nil
end

local function attach(part: BasePart, name: string, position: Vector3, created: { Instance }): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = CFrame.new(position)
	attachment.Parent = part
	table.insert(created, attachment)
	return attachment
end

-- trails and wake emitters for one blade / fist, switched off
local function makePoint(
	effect: Instance,
	part: BasePart,
	base: Vector3,
	tip: Vector3,
	shoulder: Motor6D?,
	isBlade: boolean,
	created: { Instance }
): SwingPoint
	local trails = {}
	for _, item in effect:GetChildren() do
		if item:IsA("Trail") then
			local a0, a1
			if isBlade then -- a stretch of the blade (From / To: 0 = SwingBase, 1 = SwingTip)
				a0 = attach(part, "SwingTrail", base:Lerp(tip, number(item, "From")), created)
				a1 = attach(part, "SwingTrail", base:Lerp(tip, number(item, "To")), created)
			else -- across the knuckles
				local half = Vector3.new(number(item, "Width") / 2, 0, 0)
				a0 = attach(part, "SwingTrail", tip - half, created)
				a1 = attach(part, "SwingTrail", tip + half, created)
			end
			local trail = item:Clone()
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Enabled = false
			trail.Parent = part
			table.insert(created, trail)
			table.insert(trails, trail)
		end
	end
	local wakeTemplate = effect:FindFirstChild("Wake")
	local wakeAt = if isBlade and wakeTemplate then base:Lerp(tip, number(wakeTemplate, "Along")) else tip
	local wake = attach(part, "SwingWake", wakeAt, created)
	local emitters = {}
	if wakeTemplate then
		for _, item in wakeTemplate:GetChildren() do
			if item:IsA("ParticleEmitter") then
				local emitter = item:Clone()
				emitter.Enabled = false
				emitter.Parent = wake
				table.insert(emitters, emitter)
			end
		end
	end
	return {
		part = part,
		base = base,
		tip = tip,
		shoulder = shoulder,
		trails = trails,
		emitters = emitters,
		wake = wake,
		wakeAt = wakeAt,
		prev = nil,
		prevReach = 0,
		velocity = Vector3.zero,
		speed = 0,
		reachRate = 0,
		mode = nil,
		peak = 0,
		peakAt = nil,
		fired = false,
	}
end

-- a frame at `position` looking along `look`, with its top as close to `up` as possible
local function frameAt(position: Vector3, look: Vector3, up: Vector3, fallback: CFrame): CFrame
	if up:Cross(look).Magnitude < 1e-3 then
		up = fallback.UpVector
		if up:Cross(look).Magnitude < 1e-3 then
			up = fallback.LookVector
		end
	end
	return CFrame.lookAt(position, position + look, up)
end

local function newSwing(kind: string, character: Model, options: Options?): Swing?
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local effect = template(kind):Clone()
	dress(effect, options)
	local isBlade = effect:GetAttribute("Kind") == "Blade"
	local onSpeed, offSpeed = number(effect, "OnSpeed"), number(effect, "OffSpeed")
	local thrustSpeed, thrustOff = number(effect, "ThrustSpeed"), number(effect, "ThrustOffSpeed")
	local thrustAlign = number(effect, "ThrustAlign")
	local burstAlong, burstAhead = number(effect, "BurstAlong"), number(effect, "BurstAhead")
	local burst, thrustBurst = effect:GetAttribute("Burst"), effect:GetAttribute("ThrustBurst")

	local created: { Instance } = {}
	local points: { SwingPoint } = {}
	if isBlade then
		local part, base, tip = findBlade(character)
		if not part then
			if not warned[character] then
				warned[character] = true
				warn(
					"CombatVFX: no blade on " .. character.Name .. "; give the sword SwingBase and SwingTip attachments"
				)
			end
			effect:Destroy()
			return nil
		end
		table.insert(points, makePoint(effect, part, base, tip, nil, true, created))
	else
		for _, side in { "Right", "Left" } do
			local arm, fist, shoulder = findFist(character, side)
			if arm then
				table.insert(points, makePoint(effect, arm, fist, fist, shoulder, false, created))
			end
		end
	end
	effect:Destroy()

	local playOptions: Options = {
		Ignore = { character },
		Color = options and options.Color,
		Scale = options and options.Scale,
		Parent = options and options.Parent,
	}

	local function fire(point: SwingPoint)
		point.fired = true
		local name = if point.mode == "Thrust" then thrustBurst else burst
		if typeof(name) == "string" and name ~= "" and point.peakAt then
			CombatVFX.Play(name, point.peakAt, playOptions)
		end
	end
	local function setOn(point: SwingPoint, on: boolean)
		for _, trail in point.trails do
			trail.Enabled = on
		end
		for _, emitter in point.emitters do
			emitter.Enabled = on
		end
	end
	local function start(point: SwingPoint, mode: string)
		point.mode, point.peak, point.peakAt, point.fired = mode, 0, nil, false
		setOn(point, true)
	end
	local function stop(point: SwingPoint)
		if not point.fired then
			fire(point)
		end
		point.mode = nil
		setOn(point, false)
	end

	local function step(dt: number)
		local rootCF = root.CFrame
		-- measure: speeds relative to the body, so running, dashing and turning don't count
		for _, point in points do
			local world = point.part.CFrame * point.tip
			local rel = rootCF:PointToObjectSpace(world)
			local at = if point.shoulder then socket(point.shoulder) else nil
			local reach = if at then (world - at).Magnitude else 0
			if point.prev and dt > 0 then
				point.velocity = (rel - point.prev) / dt
				point.speed = point.velocity.Magnitude
				point.reachRate = (reach - point.prevReach) / dt
			else
				point.velocity, point.speed, point.reachRate = Vector3.zero, 0, 0
			end
			point.prev, point.prevReach = rel, reach
		end

		-- decide what is swinging
		if isBlade then
			local point = points[1]
			local axis = rootCF:VectorToObjectSpace(point.part.CFrame:VectorToWorldSpace(point.tip - point.base)).Unit
			local along = if point.speed > 0 then point.velocity:Dot(axis) / point.speed else 0
			if not point.mode then
				if point.speed > onSpeed then
					start(point, "Slash")
				elseif point.speed > thrustSpeed and along > thrustAlign then
					start(point, "Thrust")
				end
			elseif point.speed < (if point.mode == "Thrust" then thrustOff else offSpeed) then
				stop(point)
			end
		else
			-- one fist at a time: the one moving fastest while reaching out (the guard hand gets
			-- carried along by the body's turn, but it pulls in)
			local active: SwingPoint? = nil
			for _, point in points do
				if point.mode then
					active = point
				end
			end
			if active and active.speed < offSpeed then
				stop(active)
				active = nil
			end
			if not active then
				local best: SwingPoint?, bestScore = nil, -math.huge
				for _, point in points do
					if point.speed > onSpeed and point.reachRate > -REACH_GATE * point.speed then
						local score = point.speed + REACH_WEIGHT * point.reachRate
						if score > bestScore then
							best, bestScore = point, score
						end
					end
				end
				if best then
					start(best, "Punch")
				end
			end
		end

		-- follow the swing: aim the wake behind it, find the fastest point and burst just after it
		for _, point in points do
			if point.mode and point.speed > 0 then
				local travel = rootCF:VectorToWorldSpace(point.velocity / point.speed)
				local partCF = point.part.CFrame
				local back = partCF:VectorToObjectSpace(travel)
				local up = if math.abs(back.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis
				point.wake.CFrame = CFrame.lookAt(point.wakeAt, point.wakeAt + back, up)
				if point.speed > point.peak then
					point.peak = point.speed
					local at = partCF * point.base:Lerp(point.tip, burstAlong) + travel * burstAhead
					local normal = if isBlade
						then travel:Cross(partCF:VectorToWorldSpace(point.tip - point.base))
						else rootCF.UpVector
					point.peakAt = frameAt(at, travel, normal, rootCF)
				elseif not point.fired and point.speed < PAST_PEAK * point.peak then
					fire(point)
				end
			end
		end
	end

	local reasons: { [any]: number } = {} -- what keeps it watching (tracks, timers) -> when it expires
	local lastEnd = 0
	local done = false
	local swing: Swing
	local connection: RBXScriptConnection

	local function finish()
		if done then
			return
		end
		done = true
		connection:Disconnect()
		local linger = 0
		for _, point in points do
			if point.mode then
				stop(point)
			end
			for _, trail in point.trails do
				linger = math.max(linger, trail.Lifetime)
			end
			for _, emitter in point.emitters do
				linger = math.max(linger, emitter.Lifetime.Max / math.max(emitter.TimeScale, 0.05))
			end
		end
		for _, item in created do
			Debris:AddItem(item, linger + 0.1)
		end
		local perCharacter = swings[character]
		if perCharacter and perCharacter[kind] == swing then
			perCharacter[kind] = nil
		end
	end

	connection = RunService.Heartbeat:Connect(function(dt: number)
		if not root.Parent or not character.Parent then
			finish()
			return
		end
		local now = os.clock()
		for key, expiry in reasons do
			if now > expiry then
				reasons[key] = nil
			end
		end
		local busy = false
		for _, point in points do
			busy = busy or point.mode ~= nil
		end
		if (next(reasons) == nil and not busy) or now > lastEnd + 1 then
			finish()
			return
		end
		step(dt)
	end)

	local function add(track: AnimationTrack?, addOptions: Options?)
		local now = os.clock()
		local expiry
		if track then
			local length = track.Length
			expiry = now + (if length > 0 then length / math.max(track.Speed, 0.05) + 0.25 else SWING_TRACK_MAX)
			reasons[track] = expiry
			track.Stopped:Once(function()
				reasons[track] = nil
			end)
		else
			expiry = now + (addOptions and addOptions.Duration or SWING_TIME)
			reasons[{}] = expiry
		end
		lastEnd = math.max(lastEnd, expiry)
	end

	local handle = {}
	function handle.Stop(_self: Handle)
		finish()
	end
	swing = { add = add, handle = (handle :: any) :: Handle }
	return swing
end

function CombatVFX.Swing(kind: string, character: Model, track: AnimationTrack?, options: Options?): Handle
	local perCharacter = swings[character]
	if not perCharacter then
		perCharacter = {}
		swings[character] = perCharacter
	end
	local swing = perCharacter[kind]
	if not swing then
		swing = newSwing(kind, character, options)
		if not swing then
			return NO_SWING
		end
		perCharacter[kind] = swing
	end
	swing.add(track, options)
	return swing.handle
end

-- "rbxassetid://123", ".../asset/?id=123" and 123 all key as "123"; anything else is an Animation name
local function animationKey(text: string): string
	return string.match(text, "^rbxassetid://(%d+)$") or string.match(text, "[?&]id=(%d+)") or text
end

function CombatVFX.WatchSwings(animations: { [any]: string }, characters: { Model }?): Handle
	local kinds: { [string]: string } = {}
	for key, kind in animations do
		kinds[animationKey(tostring(key))] = kind
	end
	local connections: { RBXScriptConnection } = {}
	local stopped = false

	local function watch(character: Model)
		task.spawn(function()
			local humanoid = character:WaitForChild("Humanoid", 10)
			local animator = humanoid and humanoid:WaitForChild("Animator", 10)
			if stopped or not (animator and animator:IsA("Animator")) then
				return
			end
			table.insert(
				connections,
				animator.AnimationPlayed:Connect(function(track: AnimationTrack)
					local animation = track.Animation
					if not animation then
						return
					end
					local kind = kinds[animationKey(animation.AnimationId)] or kinds[animation.Name]
					if kind then
						CombatVFX.Swing(kind, character, track)
					end
				end)
			)
		end)
	end
	local function watchPlayer(player: Player)
		if player.Character then
			watch(player.Character)
		end
		table.insert(connections, player.CharacterAdded:Connect(watch))
	end

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
	for _, model in characters or {} do
		watch(model)
	end

	local handle = {}
	function handle.Stop(_self: Handle)
		stopped = true
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	return (handle :: any) :: Handle
end

return CombatVFX
