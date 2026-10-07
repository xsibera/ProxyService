--!strict
--[[
	KilluaVFX: Killua's effects. The emitter effects (script.Effects) and sounds (script.Sounds) play
	through the shared EffectPlayer; the lightning itself is drawn with LightningBolt and
	LightningSparks (Quasiduck's Lightning Beams, in Killua.LightningBeams).

	KilluaVFX.Play(name, cframe, options?) / Attach(name, part, offset?, options?) / Sound(name, at, volume?)
		as EffectPlayer.

	KilluaVFX.Bolt(from, to, options?) -> handle
		One bolt between two points: Vector3s, or Attachments (it then follows them). options:
		Thickness, Life (seconds it shows), Arrive (seconds it takes to reach the end), Radius
		(how far it wanders), Parts, Curve (bend), Sparks (sparks fly off it), Color, Halo (a wide,
		see-through deep blue bolt round the core so it glows; on by default for bolts 0.3+ thick).
	KilluaVFX.Strike(from, to, options?)    a bolt with branches forking off it and a flash of light
		(Narukami, the palm); options also: Branches, Flash (brightness, 0 for none)
	KilluaVFX.Crawl(model, seconds, options?) -> handle
		Arcs crawling over a body: short bolts between points on its parts, as long as it lasts, some
		of them leaping off it into the air. handle:Stop() ends it early. options: Rate (arcs a
		second), Thickness, Reach (how far they wander), Leap (share that leap off, 0..1).
	KilluaVFX.Flash(at, brightness?, range?, seconds?)   a cold blue-white light that fades
	KilluaVFX.Ghost(model, cframe?, seconds?)   a pale afterimage of the body, fading
	KilluaVFX.available() -> boolean        false if LightningBeams is missing (bolts are then skipped)

	Only clients use this (LightningBolt fills a cache of bolt parts when it first loads).
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local EffectPlayer = require(script:WaitForChild("EffectPlayer")) :: any
local Effects = EffectPlayer.new(script:WaitForChild("Effects"), script:FindFirstChild("Sounds"), "KilluaVFX")

local KilluaVFX = {}

local WHITE_BLUE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(170, 225, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 190, 255)),
})
local HALO = ColorSequence.new(Color3.fromRGB(60, 150, 255), Color3.fromRGB(120, 200, 255))
local GHOST_COLOR = Color3.fromRGB(150, 215, 255)
local FLASH_COLOR = Color3.fromRGB(185, 225, 255)

function KilluaVFX.Play(name: string, cframe: CFrame, options: any?): BasePart
	return Effects:Play(name, cframe, options)
end

function KilluaVFX.Attach(name: string, part: BasePart, offset: CFrame?, options: any?): any
	return Effects:Attach(name, part, offset, options)
end

function KilluaVFX.Sound(name: string, at: BasePart | Vector3, volume: number?)
	Effects:Sound(name, at, volume)
end

--------------------------------------------------------------------------- Lightning Beams

local LightningBolt: any = nil
local LightningSparks: any = nil
local tried = false

local function beams(): any
	if tried then
		return LightningBolt
	end
	tried = true
	local folder = script.Parent and script.Parent:FindFirstChild("LightningBeams")
	local module = folder and folder:FindFirstChild("LightningBolt")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			LightningBolt = result
			local sparks = module:FindFirstChild("LightningSparks")
			if sparks and sparks:IsA("ModuleScript") then
				local okSparks, sparksModule = pcall(require, sparks)
				LightningSparks = if okSparks then sparksModule else nil
			end
		else
			warn("KilluaVFX: LightningBolt failed to load: " .. tostring(result))
		end
	end
	return LightningBolt
end

function KilluaVFX.available(): boolean
	return beams() ~= nil
end

export type Handle = { Stop: (self: Handle) -> () }

local NO_HANDLE = {
	Stop = function(_self) end,
}

-- an "attachment" LightningBolt can read: a real Attachment, or a fixed point
local function anchor(point: Vector3 | Attachment, axis: Vector3): any
	if typeof(point) == "Instance" then
		return point
	end
	return { WorldPosition = point, WorldAxis = axis }
end

local function positionOf(point: Vector3 | Attachment): Vector3
	return if typeof(point) == "Instance" then point.WorldPosition else point
end

local function newBolt(Bolt: any, from: any, to: any, o: any, length: number, axis: Vector3, halo: boolean): any
	local parts = o.Parts or math.clamp(math.floor(length * 1.6), 6, 36)
	if halo then
		parts = math.max(4, math.floor(parts / 2)) -- a blur round the core: it doesn't need the detail
	end
	local bolt = Bolt.new(anchor(from, axis), anchor(to, axis), parts)
	local life = o.Life or 0.2
	local arrive = math.max(o.Arrive or 0.04, 0.01)
	local thickness = o.Thickness or 0.5
	bolt.PulseSpeed = 1 / arrive
	bolt.PulseLength = math.max(life / arrive - 1, 0.5)
	bolt.FadeLength = o.Fade or 0.25
	bolt.Thickness = if halo then thickness * 2.8 else thickness
	bolt.MinThicknessMultiplier, bolt.MaxThicknessMultiplier = if halo then 0.6 else 0.5, 1
	bolt.MinRadius, bolt.MaxRadius = 0, o.Radius or math.clamp(length * 0.1, 0.35, 3.5)
	bolt.Frequency = o.Frequency or 2.2
	bolt.AnimationSpeed = o.AnimationSpeed or 10
	bolt.CurveSize0, bolt.CurveSize1 = o.Curve or 0, o.Curve or 0
	bolt.Color = if halo then HALO else (o.Color or WHITE_BLUE)
	bolt.ColorOffsetSpeed = 4
	bolt.ContractFrom = 0.5
	if halo then
		bolt.MinTransparency = 0.62 -- a soft glow round the core, never solid
	end
	return bolt
end

function KilluaVFX.Bolt(from: Vector3 | Attachment, to: Vector3 | Attachment, options: any?): Handle
	local Bolt = beams()
	if not Bolt then
		return NO_HANDLE :: any
	end
	local o = options or {}
	local a, b = positionOf(from), positionOf(to)
	local along = b - a
	local axis = if along.Magnitude > 1e-3 then along.Unit else Vector3.yAxis
	local length = along.Magnitude
	local bolt = newBolt(Bolt, from, to, o, length, axis, false)
	local wantHalo = if o.Halo == nil then (o.Thickness or 0.5) >= 0.3 else o.Halo
	local halo = if wantHalo then newBolt(Bolt, from, to, o, length, axis, true) else nil
	local sparks = nil
	if o.Sparks and LightningSparks then
		sparks = LightningSparks.new(bolt, o.Sparks == true and 6 or o.Sparks)
		sparks.MinDistance, sparks.MaxDistance = 1.5, 4.5
	end
	local handle = {}
	function handle.Stop(_self: Handle)
		if sparks then
			sparks.Enabled = false
		end
		for _, b in { bolt, halo } do
			if b and not b._Destroyed then
				b:DestroyDissipate(0.12, 0.4)
			end
		end
	end
	return (handle :: any) :: Handle
end

-- a cold blue-white light at a point that fades out (so a strike lights up what's round it)
function KilluaVFX.Flash(at: Vector3, brightness: number?, range: number?, seconds: number?)
	local holder = Instance.new("Part")
	holder.Name = "KilluaFlash"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(at)
	local light = Instance.new("PointLight")
	light.Color = FLASH_COLOR
	light.Brightness = brightness or 6
	light.Range = range or 20
	light.Shadows = false
	light.Parent = holder
	holder.Parent = workspace
	local life = seconds or 0.25
	TweenService:Create(light, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
	}):Play()
	Debris:AddItem(holder, life + 0.05)
end

-- a bolt with branches forking off it at random points along the way
function KilluaVFX.Strike(from: Vector3, to: Vector3, options: any?): Handle
	local o = options or {}
	local main = KilluaVFX.Bolt(from, to, o)
	if o.Flash ~= 0 then
		KilluaVFX.Flash(to, o.Flash or 7, math.clamp((to - from).Magnitude * 1.5, 14, 45), (o.Life or 0.2) + 0.1)
	end
	if not beams() then
		return main
	end
	local branches = o.Branches or 5
	local length = (to - from).Magnitude
	local rng = Random.new()
	for _ = 1, branches do
		local t = rng:NextNumber(0.2, 0.75)
		local start = from:Lerp(to, t)
		local side = rng:NextUnitVector()
		local finish = start
			+ (to - from).Unit * length * rng:NextNumber(0.1, 0.3)
			+ side * length * rng:NextNumber(0.1, 0.25)
		KilluaVFX.Bolt(start, finish, {
			Thickness = (o.Thickness or 0.5) * 0.5,
			Life = (o.Life or 0.2) * 0.8,
			Arrive = (o.Arrive or 0.04) * 0.8,
			Radius = (o.Radius or 1) * 0.5,
		})
	end
	return main
end

-- a random point on the surface of a part, as an Attachment (so the arc rides the body)
local function pointOn(part: BasePart, rng: Random): Attachment
	local half = part.Size / 2
	local a = Instance.new("Attachment")
	a.Name = "KilluaArc"
	local face = rng:NextInteger(1, 3)
	local p =
		Vector3.new(rng:NextNumber(-half.X, half.X), rng:NextNumber(-half.Y, half.Y), rng:NextNumber(-half.Z, half.Z))
	local sign = if rng:NextNumber() < 0.5 then -1 else 1
	if face == 1 then
		p = Vector3.new(sign * half.X, p.Y, p.Z)
	elseif face == 2 then
		p = Vector3.new(p.X, sign * half.Y, p.Z)
	else
		p = Vector3.new(p.X, p.Y, sign * half.Z)
	end
	a.Position = p
	a.Parent = part
	return a
end

local BODY = { "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "UpperTorso", "LowerTorso" }

function KilluaVFX.Crawl(model: Instance, seconds: number, options: any?): Handle
	if not beams() then
		return NO_HANDLE :: any
	end
	local o = options or {}
	local parts: { BasePart } = {}
	for _, name in BODY do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	if #parts == 0 then
		return NO_HANDLE :: any
	end
	local rng = Random.new()
	local rate = o.Rate or 34
	local leap = o.Leap or 0.3
	local untilTime = os.clock() + seconds
	local carry = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt: number)
		if os.clock() >= untilTime or not model.Parent then
			connection:Disconnect()
			return
		end
		carry += dt * rate
		while carry >= 1 do
			carry -= 1
			local p0 = parts[rng:NextInteger(1, #parts)]
			local a0 = pointOn(p0, rng)
			local life = rng:NextNumber(0.06, 0.15)
			local thickness = o.Thickness or 0.16
			if rng:NextNumber() < leap then
				-- an arc leaping off the body into the air
				local out = a0.WorldPosition + rng:NextUnitVector() * rng:NextNumber(1.5, 3.2)
				KilluaVFX.Bolt(a0, out, {
					Thickness = thickness * 0.8,
					Life = life,
					Arrive = 0.02,
					Radius = 0.7,
					Parts = 8,
					Halo = false,
				})
			else
				local a1 = pointOn(parts[rng:NextInteger(1, #parts)], rng)
				KilluaVFX.Bolt(a0, a1, {
					Thickness = thickness,
					Life = life,
					Arrive = 0.02,
					Radius = o.Reach or 0.7,
					Parts = 8,
					Halo = thickness >= 0.15,
				})
				Debris:AddItem(a1, life + 0.3)
			end
			Debris:AddItem(a0, life + 0.3)
		end
	end)
	local handle = {}
	function handle.Stop(_self: Handle)
		untilTime = 0
	end
	return (handle :: any) :: Handle
end

-- a pale afterimage of a body at `cframe` (default: where it stands now), fading over `seconds`
function KilluaVFX.Ghost(model: Instance, cframe: CFrame?, seconds: number?)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local offset = if cframe then cframe * root.CFrame:Inverse() else CFrame.identity
	local ghost = Instance.new("Model")
	ghost.Name = "KilluaAfterimage"
	local fade = TweenInfo.new(seconds or 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, name in BODY do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local copy = Instance.new("Part")
			copy.Name = name
			copy.Size = part.Size
			copy.CFrame = offset * part.CFrame
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanQuery = false
			copy.CanTouch = false
			copy.CastShadow = false
			copy.Material = Enum.Material.Neon
			copy.Color = GHOST_COLOR
			copy.Transparency = 0.45
			copy.Parent = ghost
			TweenService:Create(copy, fade, { Transparency = 1, Size = part.Size * 1.08 }):Play()
		end
	end
	ghost.Parent = workspace
	Debris:AddItem(ghost, (seconds or 0.35) + 0.1)
end

return KilluaVFX
