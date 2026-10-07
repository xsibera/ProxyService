--!nocheck
-- The test engine every ability kit's tests share: Place1's mock engine plus what the kits need on
-- top of it (spherecasts, radius queries, server time, animation tracks, bindable events, remotes
-- that record every argument and which remote sent it, attribute-changed signals, Random, models
-- that pivot with their parts), an effect-tree builder and an R6 character factory. Run from a
-- kit's folder (Abilities/<Kit>): each kit's tests/harness.luau loads this and adds its own folders.

local mock = assert(loadfile("../../Place1/tests/mock.luau"))()

local H = { mock = mock, failures = 0, passes = 0 }

function H.check(cond, msg)
	if cond then
		H.passes += 1
	else
		H.failures += 1
		print("  FAIL: " .. msg)
	end
end

function H.near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end

function H.finish(name)
	for _, w in ipairs(mock.warnings) do
		print("  WARNING: " .. w)
	end
	H.check(#mock.warnings == 0, "no warnings")
	print(("\n%d passed, %d failed"):format(H.passes, H.failures))
	if H.failures > 0 then
		error(name .. " failed", 0)
	end
end

-- sequences with real keypoints
NumberSequenceKeypoint = {
	new = function(t, v, e)
		return { __type = "NumberSequenceKeypoint", Time = t, Value = v, Envelope = e or 0 }
	end,
}
NumberSequence = {
	new = function(a, b)
		if type(a) == "number" then
			a = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) }
		end
		return { __type = "NumberSequence", Keypoints = a }
	end,
}
ColorSequenceKeypoint = {
	new = function(t, c)
		return { __type = "ColorSequenceKeypoint", Time = t, Value = c }
	end,
}
ColorSequence = {
	new = function(a, b)
		if a.R ~= nil then
			a = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) }
		end
		return { __type = "ColorSequence", Keypoints = a }
	end,
}
NumberRange = {
	new = function(a, b)
		return { __type = "NumberRange", Min = a, Max = b or a }
	end,
}

--------------------------------------------------------------------------- engine additions

H.remoteLog = {} -- { from = "server" | "client", to = "all" | player | nil, args = {...} }
H.played = {} -- animation tracks played: { name, fade, model }
H.registered = 0 -- KeyframeSequenceProvider registrations
H.stateEnabled = {} -- Humanoid:SetStateEnabled calls
H.floorY = 0

local function aabbHit(part, point, pad)
	local half = part.Size / 2
	local lp = part.CFrame:Inverse() * point
	return math.abs(lp.X) <= half.X + pad and math.abs(lp.Y) <= half.Y + pad and math.abs(lp.Z) <= half.Z + pad
end

local function excluded(params, part)
	for _, item in ipairs(params and params.FilterDescendantsInstances or {}) do
		if part == item or part:IsDescendantOf(item) then
			return true
		end
	end
	return false
end

local function queryParts()
	local out = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and d.CanQuery ~= false and d.Size then
			table.insert(out, d)
		end
	end
	return out
end

local function spherecast(_, origin, radius, direction, params)
	local length = direction.Magnitude
	local steps = math.max(1, math.ceil(length / 0.25))
	for i = 0, steps do
		local p = origin + direction * (i / steps)
		for _, part in ipairs(queryParts()) do
			if part.Name ~= "Floor" and not excluded(params, part) and aabbHit(part, p, radius) then
				return { Position = p, Instance = part, Normal = -direction.Unit, Distance = length * i / steps }
			end
		end
	end
	return nil
end

local function inRadius(_, at, radius, params)
	local out = {}
	for _, part in ipairs(queryParts()) do
		if not excluded(params, part) and (part.Position - at).Magnitude <= radius + part.Size.Magnitude / 2 then
			table.insert(out, part)
		end
	end
	return out
end

local floorPart = mock.newPart("Floor", Vector3.new(400, 2, 400), CFrame.new(0, -1, 0))
floorPart.Color = Color3.new(0.3, 0.3, 0.35)
floorPart.Parent = workspace
H.floor = floorPart

local function raycast(_, origin, direction)
	local endY = origin.Y + direction.Y
	if origin.Y >= H.floorY and endY <= H.floorY and direction.Y ~= 0 then
		local t = (origin.Y - H.floorY) / -direction.Y
		return { Position = origin + direction * t, Normal = Vector3.yAxis, Instance = floorPart, Material = nil }
	end
	return nil
end

-- events the mock doesn't know about but the kits' scripts connect to
local EXTRA_EVENTS = {
	Activated = true,
	MouseButton2Click = true,
	StateChanged = true,
	Landed = true,
	DescendantAdded = true,
	AncestryChanged = true,
}

local instanceMT = getmetatable(workspace)
local baseIndex = instanceMT.__index
instanceMT.__index = function(self, key)
	if self == workspace then
		if key == "Spherecast" then
			return spherecast
		elseif key == "GetPartBoundsInRadius" then
			return inRadius
		elseif key == "GetServerTimeNow" then
			return function()
				return mock.now() + (H.clockSkew or 0)
			end
		elseif key == "Raycast" then
			return raycast
		end
	end
	local class = rawget(self, "__props").ClassName
	if EXTRA_EVENTS[key] and rawget(self, "__props")[key] == nil then
		local signals = rawget(self, "__signals")
		signals[key] = signals[key] or mock.Signal.new()
		return signals[key]
	end
	if class == "Attachment" and (key == "WorldPosition" or key == "WorldAxis") then
		local world = self.WorldCFrame
		return if key == "WorldPosition" then world.Position else world.RightVector
	end
	if self == game and key == "IsLoaded" then
		return function()
			return true
		end
	elseif self == game and key == "Loaded" then
		return mock.Signal.new()
	end
	if key == "FireAllClients" then
		return function(remote, ...)
			table.insert(H.remoteLog, { from = "server", to = "all", remote = remote, args = { ... } })
		end
	elseif key == "FireClient" then
		return function(remote, player, ...)
			table.insert(H.remoteLog, { from = "server", to = player, remote = remote, args = { ... } })
		end
	elseif key == "FireServer" then
		return function(remote, ...)
			table.insert(H.remoteLog, { from = "client", remote = remote, args = { ... } })
		end
	elseif key == "SetAttribute" then
		return function(item, name, value)
			local attrs = rawget(item, "__attrs")
			local old = attrs[name]
			attrs[name] = value
			if old ~= value then
				local signals = rawget(item, "__attrSignals")
				local s = signals and signals[name]
				if s then
					s:Fire()
				end
			end
		end
	elseif key == "GetAttributeChangedSignal" then
		return function(item, name)
			local signals = rawget(item, "__attrSignals")
			if not signals then
				signals = {}
				rawset(item, "__attrSignals", signals)
			end
			signals[name] = signals[name] or mock.Signal.new()
			return signals[name]
		end
	elseif class == "Model" and key == "PivotTo" then
		return function(model, cframe)
			local pivot = model:GetPivot()
			local delta = cframe * pivot:Inverse()
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CFrame = delta * d.CFrame
				end
			end
		end
	elseif class == "Model" and key == "GetPivot" then
		return function(model)
			local primary = model.PrimaryPart
			return if primary then primary.CFrame else CFrame.identity
		end
	elseif key == "Emit" then
		return function() end
	elseif key == "RegisterKeyframeSequence" then
		return function(_, sequence)
			H.registered += 1
			return "rbxassetid://temp-" .. sequence.Name
		end
	elseif key == "LoadAnimation" then
		return function(animator, animation)
			local track = mock.newInstance("AnimationTrack", animation.Name)
			local props = rawget(track, "__props")
			local humanoid = animator.Parent
			props.__model = humanoid and humanoid.Parent
			props.Animation = animation
			props.Length = 0.4
			props.Speed = 1
			props.IsPlaying = false
			props.Stopped = mock.Signal.new()
			props.__kfs = animation.AnimationId
			return track
		end
	elseif key == "SetStateEnabled" then
		return function(_, state, enabled)
			table.insert(H.stateEnabled, { state = state.Name, enabled = enabled })
		end
	elseif class == "AnimationTrack" and (key == "Play" or key == "Stop") then
		return function(track, fade)
			local props = rawget(track, "__props")
			if key == "Play" then
				props.IsPlaying = true
				table.insert(H.played, { name = props.__kfs, fade = fade, model = props.__model })
			elseif props.IsPlaying then
				props.IsPlaying = false
				props.Stopped:Fire()
			end
		end
	elseif class == "BindableEvent" and (key == "Event" or key == "Fire") then
		local props = rawget(self, "__props")
		props.__event = props.__event or mock.Signal.new()
		if key == "Event" then
			return props.__event
		end
		return function(_, ...)
			props.__event:Fire(...)
		end
	end
	return baseIndex(self, key)
end

-- remote messages sent so far with a given first argument (kind), optionally only from one side
-- ("server" / "client") or through one remote
function H.sent(kind, from, remote)
	local out = {}
	for _, entry in ipairs(H.remoteLog) do
		if
			entry.args[1] == kind
			and (from == nil or entry.from == from)
			and (remote == nil or entry.remote == remote)
		then
			table.insert(out, entry)
		end
	end
	return out
end

function H.emitter(parent, name, attrs)
	local e = mock.newInstance("ParticleEmitter", name)
	e.Enabled = false
	e.Lifetime = NumberRange.new(0.2, 0.6)
	e.TimeScale = 1
	e.Rate = 20
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 2) })
	e.Speed = NumberRange.new(1, 2)
	e.Acceleration = Vector3.zero
	e.Color = ColorSequence.new(Color3.new(1, 0.6, 0.2))
	for k, v in pairs(attrs) do
		e:SetAttribute(k, v)
	end
	e.Parent = parent
	return e
end

-- Random, as far as the kits use it
Random = {
	new = function()
		local r = {}
		function r.NextNumber(_, a, b)
			a, b = a or 0, b or 1
			return a + (b - a) * math.random()
		end
		function r.NextInteger(_, a, b)
			return math.random(a, b)
		end
		function r.NextUnitVector(_)
			return Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
		end
		return r
	end,
}
workspace.Gravity = 196.2

-- the deprecated lowercase aliases and overloads Roblox still accepts (Lightning Beams uses them)
CFrame.inverse = CFrame.Inverse
CFrame.lerp = CFrame.Lerp
local newCFrame = CFrame.new
CFrame.new = function(...)
	local a, b = ...
	if select("#", ...) == 2 and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
		return CFrame.lookAt(a, b)
	end
	return newCFrame(...)
end
debug.profilebegin = debug.profilebegin or function() end
debug.profileend = debug.profileend or function() end
local newColor3 = Color3.new
Color3.new = function(...)
	local c = newColor3(...)
	c.lerp = c.Lerp
	c.__type = "Color3"
	return c
end
function Color3.toHSV(c)
	local max, min = math.max(c.R, c.G, c.B), math.min(c.R, c.G, c.B)
	local d = max - min
	local h = 0
	if d > 0 then
		if max == c.R then
			h = ((c.G - c.B) / d) % 6
		elseif max == c.G then
			h = (c.B - c.R) / d + 2
		else
			h = (c.R - c.G) / d + 4
		end
		h /= 6
	end
	return h, if max > 0 then d / max else 0, max
end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local rgb = ({ { v, t, p }, { q, v, p }, { p, v, t }, { p, q, v }, { t, p, v }, { v, p, q } })[i % 6 + 1]
	return Color3.new(rgb[1], rgb[2], rgb[3])
end

-- build an effect tree (data from a generator's tests/effects_tree.luau) under `effects`
function H.buildEffects(effects, tree)
	for effectName, rows in pairs(tree) do
		local root = Instance.new("Attachment")
		root.Name = effectName
		root.Parent = effects
		local subs = {}
		for _, row in ipairs(rows) do
			local parent = root
			if row.sub ~= "" then
				parent = subs[row.sub]
				if not parent then
					parent = Instance.new("Attachment")
					parent.Name = row.sub
					parent.CFrame = CFrame.new(0, -3, 0)
					parent.Parent = root
					subs[row.sub] = parent
				end
			end
			if row.class == "PointLight" then
				local light = mock.newInstance("PointLight", row.name)
				light.Brightness = 3
				light.Range = 10
				for k, v in pairs(row.attrs) do
					light:SetAttribute(k, v)
				end
				light.Parent = parent
			else
				H.emitter(parent, row.name, row.attrs)
			end
		end
	end
end

function H.sounds(parent, names)
	local sounds = mock.newInstance("Folder", "Sounds")
	sounds.Parent = parent
	for _, name in ipairs(names) do
		local sound = mock.newInstance("Sound", name)
		sound.Volume = 0.5
		sound.Parent = sounds
	end
	return sounds
end

-- an Animations folder of Animation objects (unpublished: a KeyframeSequence inside each)
function H.animations(parent, names, prefix)
	local animations = mock.newInstance("Folder", "Animations")
	animations.Parent = parent
	for _, name in ipairs(names) do
		local anim = mock.newInstance("Animation", name)
		anim.AnimationId = ""
		mock.newInstance("KeyframeSequence", (prefix or "") .. name).Parent = anim
		anim.Parent = animations
	end
	return animations
end

--------------------------------------------------------------------------- characters

local ROOT_R = { -1, 0, 0, 0, 0, 1, 0, 1, 0 }
local RIGHT_R = { 0, 0, 1, 0, 1, 0, -1, 0, 0 }
local LEFT_R = { 0, 0, -1, 0, 1, 0, 1, 0, 0 }
local function cfr(x, y, z, r)
	return CFrame.new(x, y, z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
end

-- an R6 character standing on the floor at `position` (x, z) facing `yaw` degrees (0 = -Z)
function H.character(name, x, z, yaw)
	local model = mock.newInstance("Model", name)
	local base = CFrame.new(x, 3, z) * CFrame.fromEulerAnglesYXZ(0, math.rad(yaw or 0), 0)
	local parts = {}
	local function p(partName, size, offset)
		local part = mock.newPart(partName, size, base * offset)
		part.Parent = model
		parts[partName] = part
		return part
	end
	local root = p("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.identity)
	local torso = p("Torso", Vector3.new(2, 2, 1), CFrame.identity)
	p("Head", Vector3.new(2, 1, 1), CFrame.new(0, 1.5, 0))
	p("Right Arm", Vector3.new(1, 2, 1), CFrame.new(1.5, 0, 0))
	p("Left Arm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 0, 0))
	p("Right Leg", Vector3.new(1, 2, 1), CFrame.new(0.5, -2, 0))
	p("Left Leg", Vector3.new(1, 2, 1), CFrame.new(-0.5, -2, 0))
	for motorName, spec in pairs({
		["Right Shoulder"] = { "Right Arm", cfr(1, 0.5, 0, RIGHT_R), cfr(-0.5, 0.5, 0, RIGHT_R) },
		["Left Shoulder"] = { "Left Arm", cfr(-1, 0.5, 0, LEFT_R), cfr(0.5, 0.5, 0, LEFT_R) },
	}) do
		local motor = mock.newInstance("Motor6D", motorName)
		motor.Part0, motor.Part1, motor.C0, motor.C1 = torso, parts[spec[1]], spec[2], spec[3]
		motor.Parent = torso
	end
	local humanoid = mock.newInstance("Humanoid", "Humanoid")
	humanoid.Health = 200
	humanoid.MaxHealth = 200
	humanoid.WalkSpeed = 16
	humanoid.Parent = model
	root.AssemblyMass = 7
	root.AssemblyLinearVelocity = Vector3.zero
	mock.newInstance("Animator", "Animator").Parent = humanoid
	model.PrimaryPart = root
	model.Parent = workspace
	return model, parts, humanoid
end

function H.player(name, character)
	local player = mock.newInstance("Player", name)
	player.Character = character
	player.Neutral = true
	table.insert(mock.players, player)
	return player
end

return H
