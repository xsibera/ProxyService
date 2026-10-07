--!strict
--[[
	CombatVFX: plays the combat effects in script.Effects.

	CombatVFX.Play(name, cframe, options?) -> Part
		One-shot effect. The effect sits at `cframe`, whose LookVector is the hit / travel direction.
		Its "Ground" attachment is dropped onto the floor under it and turned to the slope.

	CombatVFX.Start(name, part, options?) -> handle
		Continuous effect (DashTrail, SlideDust, RunDust) riding on `part` (usually the
		HumanoidRootPart) until handle:Stop(). Its "Ground" attachment follows the floor under the part.

	options (all optional):
		Color: Color3        recolours the Accent emitters (the move's colour)
		Scale: number        scales sizes, speeds and offsets (default 1)
		Ignore: {Instance}   left out of the floor raycast (pass the characters involved)
		Parent: Instance     where one-shot holders go (default workspace)

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

return CombatVFX
