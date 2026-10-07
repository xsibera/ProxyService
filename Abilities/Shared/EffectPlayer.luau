--!strict
--[[
	EffectPlayer: plays effects built from emitters, the same way in every ability kit (it is the
	player JajankenVFX uses, made reusable). Each kit's VFX module makes one for its own folders:

		local Effects = EffectPlayer.new(script.Effects, script.Sounds, "KilluaVFX")

	Effects:Play(name, cframe, options?) -> Part
		One-shot burst. The effect sits at `cframe`, whose LookVector is the strike direction. Its
		"Ground" attachment is dropped onto the floor under it.

	Effects:Attach(name, part, offset?, options?) -> Attached
		Continuous effect riding on a part. attached:SetCharge(0..1) grows it; attached:Stop() stops
		it emitting, and it cleans itself up once the last particles die.

	Effects:Projectile(name, from, direction, speed, range, launchAt, options?) -> Attached
		A continuous effect flying from `from` along `direction` from server time `launchAt`, so every
		client draws it where the server has it. :Stop() when it lands.

	Effects:Sound(name, at, volume?)
		Plays a sound from the sounds folder at a part or a position.

	options (all optional):
		Charge: number      0..1. Layers marked MinCharge only show above it; Grow layers swell with it
		Scale: number       scales sizes, speeds and offsets
		Ignore: {Instance}  left out of the floor raycast
		Parent: Instance    where one-shot holders go (default workspace)

	Emitter attributes: EmitCount, EmitDelay, EmitDuration (bursts), Continuous, GroundOnly,
	UseGroundColor, MinCharge, Grow, RateGrow. A PointLight with a MaxBrightness attribute brightens
	with the charge; one with a FadeTime fades out over it in a burst.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

export type Options = {
	Charge: number?,
	Scale: number?,
	Ignore: { Instance }?,
	Parent: Instance?,
}

export type Attached = {
	SetCharge: (self: Attached, charge: number) -> (),
	Stop: (self: Attached) -> (),
}

local FLOOR_PROBE = 14 -- studs below an effect searched for floor
local GROUND_TINT = 0.6 -- how far UseGroundColor emitters move toward the floor's colour

local EffectPlayer = {}
EffectPlayer.__index = EffectPlayer

export type EffectPlayer = typeof(setmetatable(
	{} :: { Effects: Instance, Sounds: Instance?, Label: string },
	EffectPlayer
))

function EffectPlayer.new(effects: Instance, sounds: Instance?, label: string?): EffectPlayer
	return setmetatable({ Effects = effects, Sounds = sounds, Label = label or "EffectPlayer" }, EffectPlayer)
end

function EffectPlayer.Template(self: EffectPlayer, name: string): Attachment
	local effect = self.Effects:FindFirstChild(name)
	assert(effect and effect:IsA("Attachment"), self.Label .. ": no effect named " .. name)
	return effect
end

local function number(item: Instance, name: string): number
	local value = item:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function ignoreList(options: Options?): { Instance }
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

-- Scale for a freshly cloned effect
local function dress(effect: Instance, options: Options?)
	local scale = options and options.Scale or 1
	if scale == 1 then
		return
	end
	for _, item in effect:GetDescendants() do
		if item:IsA("ParticleEmitter") then
			item.Size = scaleSequence(item.Size, scale)
			item.Speed = NumberRange.new(item.Speed.Min * scale, item.Speed.Max * scale)
			item.Acceleration *= scale
		elseif item:IsA("Attachment") then
			item.Position *= scale
		elseif item:IsA("PointLight") then
			item.Range *= scale
		end
	end
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

local function holderPart(name: string, cframe: CFrame): Part
	local holder = Instance.new("Part")
	holder.Name = name
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = cframe
	return holder
end

function EffectPlayer.Play(self: EffectPlayer, name: string, cframe: CFrame, options: Options?): BasePart
	local effect = self:Template(name):Clone()
	dress(effect, options)
	local charge = options and options.Charge or 1

	local holder = holderPart(name .. "VFX", cframe)
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
			if (item:GetAttribute("GroundOnly") and not floor) or number(item, "MinCharge") > charge then
				continue
			end
			if floorTint and item:GetAttribute("UseGroundColor") then
				item.Color = tint(item.Color, floorTint, GROUND_TINT)
			end
			longest = math.max(longest, fire(item))
		elseif item:IsA("PointLight") then -- a glow that fades out over its FadeTime
			local fade = TweenInfo.new(math.max(number(item, "FadeTime"), 0.1), Enum.EasingStyle.Quad)
			TweenService:Create(item, fade, { Brightness = 0 }):Play()
		end
	end
	Debris:AddItem(holder, longest + 0.5)
	return holder
end

-- the continuous side: emitters that switch on, swell with the charge and switch off again
local function attachEffect(effect: Attachment, floor: RaycastResult?, options: Options?): Attached
	type Layer = { emitter: ParticleEmitter, rate: number, size: NumberSequence }
	local layers: { Layer } = {}
	local lights: { PointLight } = {}
	local floorTint = if floor then floorColor(floor) else nil
	for _, item in effect:GetDescendants() do
		if item:IsA("ParticleEmitter") and item:GetAttribute("Continuous") then
			if floorTint and item:GetAttribute("UseGroundColor") then
				item.Color = tint(item.Color, floorTint, GROUND_TINT)
			end
			item.Enabled = false
			table.insert(layers, { emitter = item, rate = item.Rate, size = item.Size })
		elseif item:IsA("PointLight") then
			item.Brightness = 0
			table.insert(lights, item)
		end
	end

	local stopped = false
	local lastCharge = -1
	local attached = {}
	function attached.SetCharge(_self: Attached, value: number)
		if stopped then
			return
		end
		local charge = math.clamp(value, 0, 1)
		local resize = math.abs(charge - lastCharge) > 0.02
		for _, layer in layers do
			local emitter = layer.emitter
			emitter.Enabled = charge >= number(emitter, "MinCharge")
				and not (emitter:GetAttribute("GroundOnly") and floor == nil)
			local rateGrow = number(emitter, "RateGrow")
			emitter.Rate = layer.rate * (1 - rateGrow + rateGrow * charge)
			local grow = number(emitter, "Grow")
			if grow ~= 0 and resize then
				emitter.Size = scaleSequence(layer.size, 1 + grow * charge)
			end
		end
		if resize then
			lastCharge = charge
		end
		for _, light in lights do
			light.Brightness = number(light, "MaxBrightness") * (0.25 + 0.75 * charge)
		end
	end
	function attached.Stop(_self: Attached)
		if stopped then
			return
		end
		stopped = true
		local longest = 0
		for _, layer in layers do
			layer.emitter.Enabled = false
			longest = math.max(longest, layer.emitter.Lifetime.Max / math.max(layer.emitter.TimeScale, 0.05))
		end
		for _, light in lights do
			TweenService:Create(light, TweenInfo.new(0.25), { Brightness = 0 }):Play()
		end
		Debris:AddItem(effect, longest + 0.3)
	end
	attached.SetCharge(attached :: any, options and options.Charge or 0)
	return (attached :: any) :: Attached
end

function EffectPlayer.Attach(
	self: EffectPlayer,
	name: string,
	part: BasePart,
	offset: CFrame?,
	options: Options?
): Attached
	local effect = self:Template(name):Clone()
	dress(effect, options)
	effect.CFrame = offset or CFrame.identity
	effect.Parent = part
	local ignore = ignoreList(options)
	local model = part:FindFirstAncestorOfClass("Model")
	if model then
		table.insert(ignore, model)
	end
	return attachEffect(effect, floorUnder(part.Position, ignore), options)
end

function EffectPlayer.Projectile(
	self: EffectPlayer,
	name: string,
	from: Vector3,
	direction: Vector3,
	speed: number,
	range: number,
	launchAt: number,
	options: Options?
): Attached
	local look = if direction.Magnitude > 1e-3 then direction.Unit else Vector3.new(0, 0, -1)
	local holder = holderPart(name .. "Projectile", CFrame.lookAt(from, from + look))
	local effect = self:Template(name):Clone()
	dress(effect, options)
	effect.CFrame = CFrame.identity
	effect.Parent = holder
	holder.Parent = options and options.Parent or workspace
	local inner = attachEffect(effect, nil, { Charge = 1 })
	inner:SetCharge(0)
	for _, item in effect:GetDescendants() do
		if item:IsA("ParticleEmitter") then
			item.Enabled = false -- until it leaves the hand
		end
	end

	local launched = false
	local connection: RBXScriptConnection
	local projectile = {}
	function projectile.SetCharge(_self: Attached, _charge: number) end
	function projectile.Stop(_self: Attached)
		if connection.Connected then
			connection:Disconnect()
		end
		inner:Stop()
		Debris:AddItem(holder, 1.5)
	end
	connection = RunService.Heartbeat:Connect(function()
		local t = workspace:GetServerTimeNow() - launchAt
		if t < 0 then
			return
		end
		if not launched then
			launched = true
			inner:SetCharge(1)
		end
		local travelled = math.min(t * speed, range)
		local at = from + look * travelled
		holder.CFrame = CFrame.lookAt(at, at + look)
		if t * speed > range + speed * 1.5 then -- the burst never arrived: don't leave it hanging
			projectile.Stop(projectile :: any)
		end
	end)
	return (projectile :: any) :: Attached
end

function EffectPlayer.Sound(self: EffectPlayer, name: string, at: BasePart | Vector3, volume: number?)
	local source = self.Sounds and self.Sounds:FindFirstChild(name)
	if not (source and source:IsA("Sound")) then
		return
	end
	local sound = source:Clone()
	sound.Volume *= volume or 1
	local holder: BasePart
	if typeof(at) == "Vector3" then
		holder = holderPart(name .. "Sound", CFrame.new(at))
		holder.Parent = workspace
		Debris:AddItem(holder, 6)
	else
		holder = at
	end
	sound.Parent = holder
	sound:Play()
	Debris:AddItem(sound, 6)
end

return EffectPlayer
