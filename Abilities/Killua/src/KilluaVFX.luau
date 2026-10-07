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
		(how far it wanders), Parts, Curve (bend), Sparks (sparks fly off it), Color.
	KilluaVFX.Strike(from, to, options?)    a bolt with branches forking off it (Narukami, the palm)
	KilluaVFX.Crawl(model, seconds, options?) -> handle
		Arcs crawling over a body: short bolts between points on its parts, as long as it lasts.
		handle:Stop() ends it early. options: Rate (arcs a second), Thickness, Reach.
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
local GHOST_COLOR = Color3.fromRGB(150, 215, 255)

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
	local parts = o.Parts or math.clamp(math.floor(length * 1.6), 6, 40)
	local bolt = Bolt.new(anchor(from, axis), anchor(to, axis), parts)
	local life = o.Life or 0.2
	local arrive = math.max(o.Arrive or 0.04, 0.01)
	bolt.PulseSpeed = 1 / arrive
	bolt.PulseLength = math.max(life / arrive - 1, 0.5)
	bolt.FadeLength = o.Fade or 0.25
	bolt.Thickness = o.Thickness or 0.35
	bolt.MinThicknessMultiplier, bolt.MaxThicknessMultiplier = 0.4, 1
	bolt.MinRadius, bolt.MaxRadius = 0, o.Radius or math.clamp(length * 0.08, 0.3, 3)
	bolt.Frequency = o.Frequency or 1.6
	bolt.AnimationSpeed = o.AnimationSpeed or 8
	bolt.CurveSize0, bolt.CurveSize1 = o.Curve or 0, o.Curve or 0
	bolt.Color = o.Color or WHITE_BLUE
	bolt.ColorOffsetSpeed = 4
	bolt.ContractFrom = 0.5
	local sparks = nil
	if o.Sparks and LightningSparks then
		sparks = LightningSparks.new(bolt, o.Sparks == true and 6 or o.Sparks)
		sparks.MinDistance, sparks.MaxDistance = 1.5, 4
	end
	local handle = {}
	function handle.Stop(_self: Handle)
		if sparks then
			sparks.Enabled = false
		end
		if not bolt._Destroyed then
			bolt:DestroyDissipate(0.12, 0.4)
		end
	end
	return (handle :: any) :: Handle
end

-- a bolt with branches forking off it at random points along the way
function KilluaVFX.Strike(from: Vector3, to: Vector3, options: any?): Handle
	local o = options or {}
	local main = KilluaVFX.Bolt(from, to, o)
	local branches = o.Branches or 3
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
			Thickness = (o.Thickness or 0.35) * 0.45,
			Life = (o.Life or 0.2) * 0.7,
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
	local rate = o.Rate or 22
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
			local p1 = parts[rng:NextInteger(1, #parts)]
			local a0, a1 = pointOn(p0, rng), pointOn(p1, rng)
			local life = rng:NextNumber(0.06, 0.14)
			KilluaVFX.Bolt(a0, a1, {
				Thickness = o.Thickness or 0.12,
				Life = life,
				Arrive = 0.02,
				Radius = o.Reach or 0.6,
				Parts = 8,
			})
			Debris:AddItem(a0, life + 0.3)
			Debris:AddItem(a1, life + 0.3)
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
