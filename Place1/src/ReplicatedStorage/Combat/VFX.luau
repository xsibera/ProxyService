-- Client-side visual effects. Everything here is created locally (never replicated), uses
-- only textures that ship with the Roblox client, and is animated per rendered frame.

local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Util = require(script.Parent.Util)

local create = Util.create
local animate = Util.animate
local lerp = Util.lerp

local VFX = {}

local TEX = {
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
}

local WHITE = Color3.new(1, 1, 1)

VFX.Palette = {
	Light = { Accent = Color3.fromRGB(255, 205, 130), Scale = 1 },
	Finisher = { Accent = Color3.fromRGB(255, 150, 70), Scale = 1.45 },
	Heavy = { Accent = Color3.fromRGB(255, 92, 45), Scale = 1.9 },
	Block = { Accent = Color3.fromRGB(125, 195, 255), Scale = 1 },
	Parry = { Accent = Color3.fromRGB(255, 220, 90), Scale = 2 },
	GuardBreak = { Accent = Color3.fromRGB(95, 170, 255), Scale = 1.8 },
	Dodge = { Accent = Color3.fromRGB(150, 210, 255), Scale = 1 },
}

local fxFolder
local function folder()
	if not fxFolder or not fxFolder.Parent then
		fxFolder = create("Folder", { Name = "CombatFX_Local", Parent = Workspace })
	end
	return fxFolder
end
VFX.Folder = folder

local function fxPart(props)
	local p = create("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		Size = Vector3.one,
	})
	for key, value in pairs(props) do
		p[key] = value
	end
	p.Parent = folder()
	return p
end

local function host(cf)
	return fxPart({ CFrame = cf, Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2) })
end

local function seq(...)
	-- seq(t0, v0, t1, v1, ...) -> NumberSequence
	local args = { ... }
	local points = {}
	for i = 1, #args, 2 do
		table.insert(points, NumberSequenceKeypoint.new(args[i], args[i + 1]))
	end
	return NumberSequence.new(points)
end

local function lookCF(pos, dir)
	local u, v = Util.basis(dir)
	-- Z axis = -dir so LookVector = dir
	return CFrame.fromMatrix(pos, -u, v)
end

----------------------------------------------------------------------------------------------
-- Building blocks

-- Expanding glowing sphere.
function VFX.Flash(pos, color, startSize, endSize, duration, material)
	local p = fxPart({
		Shape = Enum.PartType.Ball,
		Color = color,
		Material = material or Enum.Material.Neon,
		Size = Vector3.one * startSize,
		CFrame = CFrame.new(pos),
	})
	animate(duration, function(a)
		local s = lerp(startSize, endSize, Util.outQuart(a))
		p.Size = Vector3.new(s, s, s)
		p.Transparency = a ^ 0.55
	end, function()
		p:Destroy()
	end)
end

-- Expanding ring of glowing segments in the plane perpendicular to `normal`.
function VFX.Ring(pos, normal, color, r0, r1, thickness, duration, segments)
	segments = segments or 26
	local u, v = Util.basis(normal)
	local parts = table.create(segments)
	for i = 1, segments do
		parts[i] = fxPart({ Color = color, Size = Vector3.new(thickness, thickness, 0.2) })
	end
	local n = normal.Unit
	animate(duration, function(a)
		local e = Util.outCubic(a)
		local r = lerp(r0, r1, e)
		local segLen = 2 * math.pi * r / segments * 1.12
		local th = thickness * (1 - 0.65 * a)
		local tr = a ^ 1.4
		for i = 1, segments do
			local ang = (i / segments) * 2 * math.pi
			local radial = u * math.cos(ang) + v * math.sin(ang)
			local p = parts[i]
			p.Size = Vector3.new(th, th, segLen)
			p.CFrame = CFrame.fromMatrix(pos + radial * r, radial, n)
			p.Transparency = tr
		end
	end, function()
		for _, p in ipairs(parts) do
			p:Destroy()
		end
	end)
end

-- Anime-style impact star: thin spikes shooting out radially.
function VFX.Spikes(pos, dir, color, count, length, duration)
	local u, v = Util.basis(dir)
	local d = if dir.Magnitude > 1e-4 then dir.Unit else Vector3.zAxis
	for i = 1, count do
		local ang = (i / count) * 2 * math.pi + (math.random() - 0.5) * 0.5
		local radial = (u * math.cos(ang) + v * math.sin(ang) + d * (math.random() - 0.35) * 0.9).Unit
		local ru, rv = Util.basis(radial)
		local len = length * (0.55 + math.random() * 0.7)
		local width = 0.1 + math.random() * 0.08
		local p = fxPart({ Color = color, Size = Vector3.new(width, width, 0.1) })
		animate(duration * (0.8 + math.random() * 0.4), function(a)
			local grow = Util.outQuart(math.min(1, a * 2.5))
			local shrink = if a > 0.4 then (a - 0.4) / 0.6 else 0
			local l = math.max(0.05, len * grow * (1 - shrink))
			local start = 0.35 + len * 0.6 * Util.outCubic(a)
			local center = pos + radial * (start + l * 0.5)
			local w = width * (1 - shrink * 0.6)
			p.Size = Vector3.new(w, w, l)
			p.CFrame = CFrame.fromMatrix(center, ru, rv)
			p.Transparency = shrink ^ 0.8
		end, function()
			p:Destroy()
		end)
	end
end

-- One-shot burst of streaking sparks.
function VFX.Sparks(pos, dir, color, count, speed, spread, lifetime, size)
	local h = host(lookCF(pos, dir))
	local att = create("Attachment", { Parent = h })
	local emitter = create("ParticleEmitter", {
		Texture = TEX.Spark,
		Color = ColorSequence.new(WHITE, color),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 2,
		Size = seq(0, size, 1, 0),
		Transparency = seq(0, 0, 0.7, 0.15, 1, 1),
		Squash = seq(0, 2.2, 1, 1),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Lifetime = NumberRange.new(lifetime * 0.5, lifetime),
		Speed = NumberRange.new(speed * 0.45, speed),
		SpreadAngle = Vector2.new(spread, spread),
		Acceleration = Vector3.new(0, -40, 0),
		Drag = 5,
		EmissionDirection = Enum.NormalId.Front,
		Rate = 0,
		Enabled = false,
		ZOffset = 1,
		Parent = att,
	})
	emitter:Emit(count)
	Debris:AddItem(h, lifetime + 0.3)
end

-- Soft smoke/dust puff.
function VFX.Dust(pos, dir, count, color, size, speed, spread, lifetime)
	local h = host(lookCF(pos, dir or Vector3.yAxis))
	local att = create("Attachment", { Parent = h })
	local emitter = create("ParticleEmitter", {
		Texture = TEX.Smoke,
		Color = ColorSequence.new(color or Color3.fromRGB(196, 186, 170)),
		LightEmission = 0,
		LightInfluence = 0.7,
		Size = seq(0, size * 0.5, 1, size * 1.6),
		Transparency = seq(0, 0.45, 0.6, 0.7, 1, 1),
		Lifetime = NumberRange.new((lifetime or 0.8) * 0.7, lifetime or 0.8),
		Speed = NumberRange.new(speed * 0.5, speed),
		SpreadAngle = Vector2.new(spread or 70, spread or 70),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		Acceleration = Vector3.new(0, 1.5, 0),
		Drag = 4,
		EmissionDirection = Enum.NormalId.Front,
		Rate = 0,
		Enabled = false,
		Parent = att,
	})
	emitter:Emit(count)
	Debris:AddItem(h, (lifetime or 0.8) + 0.3)
end

function VFX.Light(pos, color, brightness, range, duration)
	local h = host(CFrame.new(pos))
	local light = create("PointLight", {
		Color = color,
		Brightness = brightness,
		Range = range,
		Shadows = false,
		Parent = h,
	})
	animate(duration, function(a)
		light.Brightness = brightness * (1 - a) ^ 2
	end, function()
		h:Destroy()
	end)
end

-- Brief full-body glow on a character.
function VFX.FlashModel(model, color, duration, fill)
	if not model or not model.Parent then
		return
	end
	local startFill = fill or 0.15
	local highlight = create("Highlight", {
		Adornee = model,
		FillColor = color,
		OutlineColor = color,
		FillTransparency = startFill,
		OutlineTransparency = 0.1,
		DepthMode = Enum.HighlightDepthMode.Occluded,
		Parent = folder(),
	})
	animate(duration, function(a)
		highlight.FillTransparency = lerp(startFill, 1, a)
		highlight.OutlineTransparency = lerp(0.1, 1, a)
	end, function()
		highlight:Destroy()
	end)
end

-- Floating, popping world-space text.
function VFX.PopText(pos, text, color, height, duration, rise)
	local h = host(CFrame.new(pos))
	local gui = create("BillboardGui", {
		Size = UDim2.fromScale(height * #text * 0.62 + height, height),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 160,
		Parent = h,
	})
	local label = create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = color,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		Parent = gui,
	})
	local stroke =
		create("UIStroke", { Thickness = 2.5, Color = Color3.new(0, 0, 0), Transparency = 0.1, Parent = label })
	local scale = create("UIScale", { Scale = 0.3, Parent = label })
	local drift = (math.random() - 0.5) * 0.8
	animate(duration, function(a)
		if a < 0.12 then
			scale.Scale = lerp(0.3, 1.3, Util.outQuad(a / 0.12))
		elseif a < 0.26 then
			scale.Scale = lerp(1.3, 1, Util.outQuad((a - 0.12) / 0.14))
		else
			scale.Scale = 1
		end
		gui.StudsOffsetWorldSpace = Vector3.new(drift * a, rise * Util.outQuad(a), 0)
		if a > 0.6 then
			local t = (a - 0.6) / 0.4
			label.TextTransparency = t
			stroke.Transparency = lerp(0.1, 1, t)
		end
	end, function()
		h:Destroy()
	end)
end

function VFX.DamageNumber(pos, amount, kind)
	local colors = {
		Light = Color3.fromRGB(255, 255, 255),
		Finisher = Color3.fromRGB(255, 170, 80),
		Heavy = Color3.fromRGB(255, 85, 60),
		Chip = Color3.fromRGB(160, 200, 255),
	}
	local text = tostring(math.floor(amount * 10 + 0.5) / 10)
	local jitter = Vector3.new((math.random() - 0.5) * 1.6, math.random() * 0.6, (math.random() - 0.5) * 1.6)
	local size = if kind == "Heavy" then 1.5 elseif kind == "Finisher" then 1.3 else 1.05
	VFX.PopText(pos + jitter, text, colors[kind] or colors.Light, size, 0.8, 2.2)
end

----------------------------------------------------------------------------------------------
-- Character attachments: fist trails

local ARMS = { R = "Right Arm", L = "Left Arm" }

function VFX.EnsureTrails(model)
	for _, armName in pairs(ARMS) do
		local arm = model:FindFirstChild(armName)
		if arm and not arm:FindFirstChild("FX_Trail") then
			local top =
				create("Attachment", { Name = "FX_TrailTop", Position = Vector3.new(0, -0.35, 0), Parent = arm })
			local bottom =
				create("Attachment", { Name = "FX_TrailBottom", Position = Vector3.new(0, -1.05, 0), Parent = arm })
			create("Attachment", { Name = "FX_Fist", Position = Vector3.new(0, -1.1, 0), Parent = arm })
			create("Trail", {
				Name = "FX_Trail",
				Attachment0 = top,
				Attachment1 = bottom,
				Lifetime = 0.13,
				MinLength = 0.02,
				FaceCamera = true,
				LightEmission = 1,
				LightInfluence = 0,
				Color = ColorSequence.new(WHITE, Color3.fromRGB(190, 225, 255)),
				Transparency = seq(0, 0.25, 1, 1),
				WidthScale = seq(0, 1, 1, 0.25),
				Enabled = false,
				Parent = arm,
			})
		end
	end
end

function VFX.SetTrail(model, side, enabled, color)
	local arm = model:FindFirstChild(ARMS[side] or "")
	local trail = arm and arm:FindFirstChild("FX_Trail")
	if trail then
		if color then
			trail.Color = ColorSequence.new(WHITE, color)
			trail.Lifetime = 0.2
		else
			trail.Color = ColorSequence.new(WHITE, Color3.fromRGB(190, 225, 255))
			trail.Lifetime = 0.13
		end
		trail.Enabled = enabled
	end
end

----------------------------------------------------------------------------------------------
-- Compound effects

-- dir = direction the blow travelled (attacker -> victim)
function VFX.Hit(pos, dir, kind, victim)
	local pal = VFX.Palette[kind] or VFX.Palette.Light
	local s, accent = pal.Scale, pal.Accent
	VFX.Flash(pos, WHITE, 0.5 * s, 2.6 * s, 0.11)
	VFX.Flash(pos, accent, 0.4 * s, 3.4 * s, 0.2, Enum.Material.ForceField)
	VFX.Ring(pos, dir, accent, 0.5 * s, 3.4 * s, 0.16 * s, 0.22)
	VFX.Spikes(pos, dir, if kind == "Light" then WHITE else accent, if kind == "Light" then 6 else 10, 1.9 * s, 0.2)
	VFX.Sparks(pos, dir, accent, math.floor(12 * s), 42 * s, 50, 0.32, 0.32)
	VFX.Light(pos, accent, 2.5 * s, 9 * s, 0.2)
	if victim then
		VFX.FlashModel(victim, WHITE, 0.14, 0.05)
	end
	if kind ~= "Light" then
		task.delay(0.045, function()
			VFX.Ring(pos, dir, WHITE, 0.4 * s, 2.4 * s, 0.1 * s, 0.2)
		end)
		local feet = if victim and victim:FindFirstChild("HumanoidRootPart")
			then victim.HumanoidRootPart.Position - Vector3.new(0, 2.8, 0)
			else pos - Vector3.new(0, 3, 0)
		VFX.Dust(feet, Vector3.yAxis, math.floor(6 * s), nil, 1.6, 10, 85, 0.7)
	end
	if kind == "Heavy" then
		VFX.Flash(pos, accent, 1, 9, 0.32, Enum.Material.ForceField)
		VFX.Ring(pos, Vector3.yAxis, accent, 1, 9, 0.22, 0.35)
	end
end

function VFX.Block(pos, dir, blocker)
	local pal = VFX.Palette.Block
	local accent = pal.Accent
	VFX.Flash(pos, WHITE, 0.35, 1.6, 0.09)
	VFX.Ring(pos, dir, accent, 0.4, 2.6, 0.12, 0.18, 20)
	VFX.Sparks(pos, -dir, accent, 10, 32, 60, 0.25, 0.25)
	local root = blocker and blocker:FindFirstChild("HumanoidRootPart")
	if root then
		local center = root.Position + root.CFrame.LookVector * 1.4 + Vector3.new(0, 0.6, 0)
		local bubble = fxPart({
			Shape = Enum.PartType.Ball,
			Material = Enum.Material.ForceField,
			Color = accent,
			Size = Vector3.one * 4.5,
			CFrame = CFrame.new(center),
		})
		animate(0.22, function(a)
			local sz = lerp(4.5, 6, Util.outCubic(a))
			bubble.Size = Vector3.new(sz, sz, sz)
			bubble.Transparency = a
		end, function()
			bubble:Destroy()
		end)
	end
end

function VFX.Parry(pos, dir, parrier, parried, stunDuration)
	local gold = VFX.Palette.Parry.Accent
	VFX.Flash(pos, WHITE, 0.8, 4.5, 0.12)
	VFX.Flash(pos, gold, 0.6, 7.5, 0.3, Enum.Material.ForceField)
	VFX.Ring(pos, dir, gold, 0.8, 7.5, 0.26, 0.32, 32)
	task.delay(0.06, function()
		VFX.Ring(pos, dir, WHITE, 0.5, 4.6, 0.16, 0.26, 28)
	end)
	VFX.Spikes(pos, dir, WHITE, 12, 4.2, 0.24)
	VFX.Spikes(pos, -dir, gold, 8, 2.6, 0.2)
	VFX.Sparks(pos, dir, gold, 40, 75, 70, 0.45, 0.45)
	VFX.Sparks(pos, -dir, WHITE, 18, 40, 50, 0.3, 0.3)
	VFX.Light(pos, gold, 8, 18, 0.35)
	if parrier then
		VFX.FlashModel(parrier, gold, 0.3, 0.25)
		local head = parrier:FindFirstChild("Head")
		if head then
			VFX.PopText(head.Position + Vector3.new(0, 1.4, 0), "PARRY", gold, 1.5, 0.95, 2)
		end
	end
	if parried then
		VFX.Dizzy(parried, stunDuration or 1.2)
	end
end

function VFX.GuardBreak(pos, dir, victim, stunDuration)
	local blue = VFX.Palette.GuardBreak.Accent
	VFX.Flash(pos, WHITE, 0.8, 4.5, 0.14)
	VFX.Flash(pos, blue, 0.6, 6, 0.28, Enum.Material.ForceField)
	VFX.Ring(pos, dir, blue, 1, 6, 0.24, 0.3, 30)
	VFX.Shards(pos, blue, 16)
	VFX.Sparks(pos, dir, blue, 26, 55, 70, 0.4, 0.38)
	VFX.Light(pos, blue, 6, 16, 0.3)
	if victim then
		VFX.FlashModel(victim, blue, 0.35, 0.2)
		local head = victim:FindFirstChild("Head")
		if head then
			VFX.PopText(head.Position + Vector3.new(0, 1.4, 0), "GUARD BREAK", blue, 1.3, 1.1, 2)
		end
		VFX.Dizzy(victim, stunDuration or 1.4)
	end
end

function VFX.Shards(pos, color, count)
	local gravity = Vector3.new(0, -70, 0)
	for _ = 1, count do
		local p = fxPart({
			Material = Enum.Material.Glass,
			Color = color,
			Transparency = 0.15,
			Reflectance = 0.2,
			Size = Vector3.new(0.25 + math.random() * 0.5, 0.25 + math.random() * 0.5, 0.06),
			CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28),
		})
		local velocity = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.2, math.random() - 0.5).Unit
			* (14 + math.random() * 16)
		local spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 18
		local life = 0.55 + math.random() * 0.35
		animate(life, function(a, dt)
			velocity += gravity * dt
			p.CFrame = (p.CFrame + velocity * dt) * CFrame.Angles(spin.X * dt, spin.Y * dt, spin.Z * dt)
			p.Transparency = lerp(0.15, 1, a ^ 2)
		end, function()
			p:Destroy()
		end)
	end
end

-- Orbiting stars above a stunned character's head.
function VFX.Dizzy(model, duration)
	local head = model and model:FindFirstChild("Head")
	if not head then
		return
	end
	local old = folder():FindFirstChild("Dizzy_" .. model:GetDebugId())
	if old then
		old:Destroy()
	end
	local gui = create("BillboardGui", {
		Name = "Dizzy_" .. model:GetDebugId(),
		Adornee = head,
		Size = UDim2.fromScale(3.2, 1.4),
		StudsOffset = Vector3.new(0, 1.5, 0),
		LightInfluence = 0,
		MaxDistance = 120,
		Parent = folder(),
	})
	local stars = {}
	for i = 1, 3 do
		local label = create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(0.28, 0.65),
			BackgroundTransparency = 1,
			Text = "★",
			TextColor3 = Color3.fromRGB(255, 226, 92),
			TextScaled = true,
			Font = Enum.Font.GothamBlack,
			Parent = gui,
		})
		create("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(120, 70, 0), Parent = label })
		stars[i] = label
	end
	local angle = math.random() * 6.28
	animate(duration, function(a, dt)
		angle += dt * 6
		local fade = if a > 0.8 then (a - 0.8) / 0.2 else 0
		for i, label in ipairs(stars) do
			local theta = angle + (i - 1) * (2 * math.pi / 3)
			local depth = (math.sin(theta) + 1) * 0.5
			label.Position = UDim2.fromScale(0.5 + 0.4 * math.cos(theta), 0.5 + 0.2 * math.sin(theta))
			label.Size = UDim2.fromScale(0.2 + 0.12 * depth, 0.45 + 0.3 * depth)
			label.ZIndex = if depth > 0.5 then 2 else 1
			label.TextTransparency = lerp(0.35 - depth * 0.35, 1, fade)
		end
	end, function()
		gui:Destroy()
	end)
end

-- Ghostly copies of the body left behind during a dodge.
local BODY_PARTS = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
function VFX.Afterimage(model, color, duration)
	local parts = {}
	for _, name in ipairs(BODY_PARTS) do
		local src = model:FindFirstChild(name)
		if src and src:IsA("BasePart") then
			local p = fxPart({
				Material = Enum.Material.ForceField,
				Color = color,
				Size = src.Size,
				CFrame = src.CFrame,
				Transparency = 0.05,
			})
			if name == "Head" then
				create(
					"SpecialMesh",
					{ MeshType = Enum.MeshType.Head, Scale = Vector3.new(1.25, 1.25, 1.25), Parent = p }
				)
			end
			table.insert(parts, p)
		end
	end
	animate(duration, function(a)
		for _, p in ipairs(parts) do
			p.Transparency = lerp(0.05, 1, a)
		end
	end, function()
		for _, p in ipairs(parts) do
			p:Destroy()
		end
	end)
end

-- Heavy-attack charge: energy converging into the fist. Returns a stop function.
function VFX.Charge(model, side, duration)
	local arm = model:FindFirstChild(ARMS[side or "R"])
	local fist = arm and arm:FindFirstChild("FX_Fist")
	if not fist then
		return function() end
	end
	local accent = VFX.Palette.Heavy.Accent
	local emitter = create("ParticleEmitter", {
		Texture = TEX.Spark,
		Color = ColorSequence.new(WHITE, accent),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 2,
		Size = seq(0, 0.5, 1, 0.05),
		Transparency = seq(0, 0.6, 0.3, 0, 1, 0.2),
		Lifetime = NumberRange.new(0.18, 0.3),
		Speed = NumberRange.new(6, 9),
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Rate = 70,
		Parent = fist,
	})
	local light = create("PointLight", { Color = accent, Brightness = 0, Range = 9, Shadows = false, Parent = fist })
	local orb = fxPart({ Shape = Enum.PartType.Ball, Color = accent, Size = Vector3.one * 0.3 })
	local stopped = false
	local stopAnim = animate(duration, function(a)
		if not fist.Parent then
			return
		end
		local flicker = 0.85 + math.random() * 0.3
		local s = lerp(0.3, 1.3, Util.outQuad(a)) * flicker
		orb.Size = Vector3.new(s, s, s)
		orb.CFrame = fist.WorldCFrame
		orb.Transparency = 0.25
		light.Brightness = lerp(0, 5, a) * flicker
	end)
	local function stop()
		if stopped then
			return
		end
		stopped = true
		stopAnim()
		emitter.Enabled = false
		Debris:AddItem(emitter, 0.4)
		light:Destroy()
		local s = orb.Size.X
		animate(0.12, function(a)
			orb.Size = Vector3.one * lerp(s, s * 2.2, a)
			orb.Transparency = lerp(0.25, 1, a)
		end, function()
			orb:Destroy()
		end)
	end
	task.delay(duration + 0.3, stop)
	return stop
end

-- Ground dust that streams off the feet while sliding. Returns a stop function.
function VFX.SlideTrail(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return function() end
	end
	local att = create("Attachment", { Name = "FX_Slide", Position = Vector3.new(0, -2.75, 0.6), Parent = root })
	local dust = create("ParticleEmitter", {
		Texture = TEX.Smoke,
		Color = ColorSequence.new(Color3.fromRGB(205, 195, 180)),
		LightInfluence = 0.7,
		Size = seq(0, 0.9, 1, 3.4),
		Transparency = seq(0, 0.5, 0.5, 0.75, 1, 1),
		Lifetime = NumberRange.new(0.45, 0.75),
		Speed = NumberRange.new(3, 7),
		SpreadAngle = Vector2.new(35, 35),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-50, 50),
		Acceleration = Vector3.new(0, 2.5, 0),
		Drag = 3,
		EmissionDirection = Enum.NormalId.Back,
		Rate = 45,
		Parent = att,
	})
	local sparks = create("ParticleEmitter", {
		Texture = TEX.Spark,
		Color = ColorSequence.new(WHITE, Color3.fromRGB(255, 190, 110)),
		LightEmission = 1,
		LightInfluence = 0,
		Size = seq(0, 0.18, 1, 0),
		Squash = seq(0, 2, 1, 1),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Lifetime = NumberRange.new(0.12, 0.25),
		Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(0, -30, 0),
		EmissionDirection = Enum.NormalId.Back,
		Rate = 22,
		Parent = att,
	})
	return function()
		dust.Enabled = false
		sparks.Enabled = false
		Debris:AddItem(att, 0.8)
	end
end

function VFX.Land(model, impact)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local feet = root.Position - Vector3.new(0, 2.9, 0)
	VFX.Dust(feet, Vector3.yAxis, math.floor(6 + 10 * impact), nil, 1.4 + impact, 9 + 10 * impact, 88, 0.8)
	if impact > 0.6 then
		VFX.Ring(
			feet + Vector3.new(0, 0.1, 0),
			Vector3.yAxis,
			Color3.fromRGB(235, 230, 220),
			1,
			4 + 3 * impact,
			0.12,
			0.3
		)
	end
end

function VFX.Footstep(model, intensity)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local back = -root.CFrame.LookVector
	VFX.Dust(
		root.Position - Vector3.new(0, 2.85, 0),
		(back + Vector3.new(0, 0.6, 0)).Unit,
		2,
		nil,
		0.8 * intensity + 0.3,
		4,
		30,
		0.5
	)
end

function VFX.DodgeBurst(model, direction)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local accent = VFX.Palette.Dodge.Accent
	VFX.Dust(
		root.Position - Vector3.new(0, 2.8, 0),
		(-direction + Vector3.new(0, 0.4, 0)).Unit,
		8,
		nil,
		1.3,
		12,
		40,
		0.6
	)
	VFX.Ring(root.Position, direction, accent, 1.2, 3.2, 0.1, 0.2, 20)
end

return VFX
