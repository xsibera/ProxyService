--!strict
--[[
	LeorioVFX: Leorio's effects. The emitter effects (script.Effects) and sounds (script.Sounds) play
	through the shared EffectPlayer; the warp holes and the fists that come out of them are parts
	built here, round those emitters.

	LeorioVFX.Play(name, cframe, options?) / Attach(name, part, offset?, options?) / Sound(name, at, volume?)
		as EffectPlayer.

	LeorioVFX.Portal(cframe, radius, options?) -> Portal
		A warp hole at `cframe`, its LookVector the way a fist comes out of it. It opens over
		options.Open seconds (default 0.14), overshooting a touch, and turns until closed:
		  portal:Burst()           the PortalBurst effect (a fist coming through)
		  portal:Close(seconds?)   shrinks it away (default 0.16) and cleans it up
		The hole is a dark disc with a glowing rim (a ring of bright segments turning round it, over a
		softer glow) and a shimmer across it, with the Portal effect's swirl and ripple on top.
	LeorioVFX.Fist(cframe, options?) -> Fist
		His fist and forearm punching out of a hole at `cframe` along its LookVector, in his suit
		sleeve and shirt cuff, glowing faintly with his aura. options: Scale (1 = an R6 arm), Reach
		(studs the fist ends up out of the hole), Out (seconds to get there), Hold, Back (seconds to
		pull back in), Skin / Sleeve / Cuff (Color3s). fist:Retract() pulls it back early.
	LeorioVFX.Trace(from, to, seconds)   the aura's trail along the floor from his fist to the target

	Only clients use this.
]]

local RunService = game:GetService("RunService")

local EffectPlayer = require(script:WaitForChild("EffectPlayer")) :: any
local Effects = EffectPlayer.new(script:WaitForChild("Effects"), script:FindFirstChild("Sounds"), "LeorioVFX")

local LeorioVFX = {}

local AURA = Color3.fromRGB(133, 255, 231)
local CORE = Color3.fromRGB(230, 255, 249)
local VOID = Color3.fromRGB(4, 12, 11)
local RIM_SEGMENTS = 18
local DISC = CFrame.Angles(0, math.rad(90), 0) -- a Cylinder's axis (X) along the hole's LookVector

function LeorioVFX.Play(name: string, cframe: CFrame, options: any?): BasePart
	return Effects:Play(name, cframe, options)
end

function LeorioVFX.Attach(name: string, part: BasePart, offset: CFrame?, options: any?): any
	return Effects:Attach(name, part, offset, options)
end

function LeorioVFX.Sound(name: string, at: BasePart | Vector3, volume: number?)
	Effects:Sound(name, at, volume)
end

local function folder(): Instance
	local found = workspace:FindFirstChild("LeorioWarps")
	if found then
		return found
	end
	local made = Instance.new("Folder")
	made.Name = "LeorioWarps"
	made.Parent = workspace
	return made
end

local function newPart(name: string, parent: Instance, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		part.Shape = shape
	end
	part.Parent = parent
	return part
end

--------------------------------------------------------------------------- warp holes

export type Portal = {
	CFrame: CFrame,
	Model: Model,
	Burst: (self: Portal) -> (),
	Close: (self: Portal, seconds: number?) -> (),
}

-- 0 -> 1 with a small overshoot (a back-out ease)
local function backOut(u: number): number
	local c = 1.4
	local v = u - 1
	return 1 + (c + 1) * v * v * v + c * v * v
end

function LeorioVFX.Portal(cframe: CFrame, radius: number, options: any?): Portal
	local o = options or {}
	local openTime = o.Open or 0.14
	local model = Instance.new("Model")
	model.Name = "WarpHole"
	local holder = newPart("Holder", model)
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = cframe
	local glow = newPart("Glow", model, Enum.PartType.Cylinder)
	glow.Material = Enum.Material.Neon
	glow.Color = AURA
	glow.Transparency = 0.45
	local void = newPart("Void", model, Enum.PartType.Cylinder)
	void.Color = VOID
	void.Transparency = 0.04
	local shimmer = newPart("Shimmer", model, Enum.PartType.Cylinder)
	shimmer.Material = Enum.Material.ForceField
	shimmer.Color = AURA
	shimmer.Transparency = 0.2
	local rim: { Part } = {}
	for i = 1, RIM_SEGMENTS do
		local segment = newPart("Rim", model)
		segment.Material = Enum.Material.Neon
		segment.Color = if i % 3 == 0 then AURA else CORE
		segment.Transparency = 0.1
		rim[i] = segment
	end
	model.Parent = o.Parent or folder()
	local swirl = Effects:Attach("Portal", holder, CFrame.identity, { Charge = 0 })

	local function draw(scale: number, spin: number)
		local d = radius * 2 * math.max(scale, 0.02)
		void.Size = Vector3.new(0.06, d * 0.9, d * 0.9)
		void.CFrame = cframe * DISC
		glow.Size = Vector3.new(0.05, d * 1.08, d * 1.08)
		glow.CFrame = cframe * CFrame.new(0, 0, 0.04) * DISC
		shimmer.Size = Vector3.new(0.05, d * 0.86, d * 0.86)
		shimmer.CFrame = cframe * CFrame.new(0, 0, -0.04) * DISC
		local r = radius * math.max(scale, 0.02)
		local length = 2 * math.pi * r / RIM_SEGMENTS * 0.8
		local thick = math.clamp(radius * 0.09, 0.12, 0.3) * math.sqrt(math.max(scale, 0.02))
		for i, segment in rim do
			local a = spin + (i - 1) * 2 * math.pi / RIM_SEGMENTS
			local wobble = 1 + 0.035 * math.sin(spin * 3 + i * 1.7)
			segment.Size = Vector3.new(length, thick, thick)
			segment.CFrame = cframe * CFrame.Angles(0, 0, a) * CFrame.new(0, r * wobble, -0.02)
		end
	end

	local born = os.clock()
	local closing: { from: number, at: number, seconds: number }? = nil
	local current = 0
	draw(0.02, 0)
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - born
		local scale
		if closing then
			local u = math.clamp((os.clock() - closing.at) / closing.seconds, 0, 1)
			scale = closing.from * (1 - u * u)
			if u >= 1 then
				connection:Disconnect()
				model:Destroy()
				return
			end
		else
			local u = math.clamp(t / openTime, 0, 1)
			scale = backOut(u) * (1 + 0.025 * math.sin(t * 9))
			swirl:SetCharge(u)
		end
		current = scale
		draw(scale, t * 2.6)
	end)

	local portal = { CFrame = cframe, Model = model }
	function portal.Burst(_self: Portal)
		Effects:Play("PortalBurst", cframe)
	end
	function portal.Close(_self: Portal, seconds: number?)
		if closing or not model.Parent then
			return
		end
		closing = { from = math.max(current, 0.05), at = os.clock(), seconds = seconds or 0.16 }
		swirl:Stop()
	end
	return (portal :: any) :: Portal
end

--------------------------------------------------------------------------- the fists

export type Fist = { Model: Model, Retract: (self: Fist) -> () }

function LeorioVFX.Fist(cframe: CFrame, options: any?): Fist
	local o = options or {}
	local s = o.Scale or 1.5
	local reach = o.Reach or 3.5 * s
	local outTime = o.Out or 0.07
	local holdTime = o.Hold or 0.12
	local backTime = o.Back or 0.16
	local model = Instance.new("Model")
	model.Name = "WarpFist"
	local sleeve = newPart("Sleeve", model)
	sleeve.Color = o.Sleeve or Color3.fromRGB(28, 32, 46)
	local cuff = newPart("Cuff", model)
	cuff.Color = o.Cuff or Color3.fromRGB(235, 236, 240)
	local fist = newPart("Fist", model)
	fist.Color = o.Skin or Color3.fromRGB(234, 184, 146)
	local aura = Instance.new("Highlight")
	aura.Name = "Aura"
	aura.FillColor = AURA
	aura.OutlineColor = CORE
	aura.FillTransparency = 0.82
	aura.OutlineTransparency = 0.15
	aura.DepthMode = Enum.HighlightDepthMode.Occluded
	aura.Adornee = model
	aura.Parent = model
	model.Parent = o.Parent or folder()

	local look = cframe.LookVector
	local fistLength = 1.0 * s
	local cuffLength = 0.3 * s
	local function draw(e: number)
		-- the arm only ever exists in front of the hole: its back end stays in the hole's plane
		local front = math.max(e, 0.05)
		local fistBack = math.max(front - fistLength, 0)
		local fistCenter = cframe.Position + look * (front + fistBack) / 2
		fist.Size = Vector3.new(1.05 * s, 1.05 * s, math.max(front - fistBack, 0.05))
		fist.CFrame = CFrame.lookAt(fistCenter, fistCenter + look, cframe.UpVector)
		local cuffBack = math.max(fistBack - cuffLength, 0)
		local cuffCenter = cframe.Position + look * (fistBack + cuffBack) / 2
		cuff.Size = Vector3.new(1.12 * s, 1.12 * s, math.max(fistBack - cuffBack, 0.02))
		cuff.CFrame = CFrame.lookAt(cuffCenter, cuffCenter + look, cframe.UpVector)
		cuff.Transparency = if fistBack - cuffBack < 0.03 then 1 else 0
		local sleeveCenter = cframe.Position + look * cuffBack / 2
		sleeve.Size = Vector3.new(1.0 * s, 1.0 * s, math.max(cuffBack, 0.02))
		sleeve.CFrame = CFrame.lookAt(sleeveCenter, sleeveCenter + look, cframe.UpVector)
		sleeve.Transparency = if cuffBack < 0.03 then 1 else 0
	end
	draw(0)

	local born = os.clock()
	local retractAt: number? = nil
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - born
		local e
		if retractAt == nil and t >= outTime + holdTime then
			retractAt = born + outTime + holdTime
		end
		if retractAt then
			local u = math.clamp((os.clock() - retractAt) / backTime, 0, 1)
			e = reach * (1 - u * u)
			if u >= 1 then
				connection:Disconnect()
				model:Destroy()
				return
			end
		else
			local u = math.clamp(t / outTime, 0, 1)
			e = reach * (1 - (1 - u) ^ 4) -- out fast and hard
		end
		draw(e)
	end)

	local handle = { Model = model }
	function handle.Retract(_self: Fist)
		if retractAt == nil then
			retractAt = os.clock()
		end
	end
	return (handle :: any) :: Fist
end

--------------------------------------------------------------------------- the trace

function LeorioVFX.Trace(from: Vector3, to: Vector3, seconds: number)
	local along = to - from
	local distance = along.Magnitude
	if distance < 0.5 then
		return
	end
	local trail = Effects:Projectile(
		"Trace",
		from,
		along,
		distance / math.max(seconds, 0.05),
		distance,
		workspace:GetServerTimeNow()
	)
	task.delay(seconds + 0.05, function()
		trail:Stop()
	end)
end

return LeorioVFX
