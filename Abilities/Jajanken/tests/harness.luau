--!nocheck
-- Shared setup for the Jajanken tests: Place1's mock engine plus what Jajanken needs on top of it
-- (spherecasts, radius queries, server time, animation tracks, bindable events, a remote that
-- records every argument), the ReplicatedStorage.Jajanken folder built from src/ and the real
-- effect tree (tests/effects_tree.luau), and an R6 character factory.

local mock = assert(loadfile("../../Place1/tests/mock.luau"))()
local tree = assert(loadfile("tests/effects_tree.luau"))()

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
H.played = {} -- animation tracks played: { name, fade }
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
	if key == "FireAllClients" then
		return function(_, ...)
			table.insert(H.remoteLog, { from = "server", to = "all", args = { ... } })
		end
	elseif key == "FireClient" then
		return function(_, player, ...)
			table.insert(H.remoteLog, { from = "server", to = player, args = { ... } })
		end
	elseif key == "FireServer" then
		return function(_, ...)
			table.insert(H.remoteLog, { from = "client", args = { ... } })
		end
	elseif key == "Emit" then
		return function() end
	elseif key == "RegisterKeyframeSequence" then
		return function(_, sequence)
			H.registered += 1
			return "rbxassetid://temp-" .. sequence.Name
		end
	elseif key == "LoadAnimation" then
		return function(_, animation)
			local track = mock.newInstance("AnimationTrack", animation.Name)
			local props = rawget(track, "__props")
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
				table.insert(H.played, { name = props.__kfs, fade = fade })
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

-- remote messages sent so far with a given first argument (kind)
function H.sent(kind, from)
	local out = {}
	for _, entry in ipairs(H.remoteLog) do
		if entry.args[1] == kind and (from == nil or entry.from == from) then
			table.insert(out, entry)
		end
	end
	return out
end

--------------------------------------------------------------------------- the Jajanken folder

local RS = game:GetService("ReplicatedStorage")
local jajanken = mock.newInstance("Folder", "Jajanken")
jajanken.Parent = RS
H.folder = jajanken
H.Config = mock.module(jajanken, "Config", "src/Config.luau")
local vfxModule = mock.module(jajanken, "JajankenVFX", "src/JajankenVFX.luau")
local effects = mock.newInstance("Folder", "Effects")
effects.Parent = vfxModule
local sounds = mock.newInstance("Folder", "Sounds")
sounds.Parent = vfxModule
for _, name in ipairs({ "RockHit", "PaperHit", "ScissorsCast" }) do
	local sound = mock.newInstance("Sound", name)
	sound.Volume = 0.5
	sound.Parent = sounds
end
H.remote = mock.newInstance("RemoteEvent", "Remote")
H.remote.Parent = jajanken
local animations = mock.newInstance("Folder", "Animations")
animations.Parent = jajanken
for _, name in ipairs({ "Charge", "Hold", "Rock", "Paper", "Scissors" }) do
	local anim = mock.newInstance("Animation", name)
	anim.AnimationId = ""
	mock.newInstance("KeyframeSequence", "Jajanken " .. name).Parent = anim
	anim.Parent = animations
end

local function emitter(parent, name, attrs)
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

-- the real effect tree: every layer with the attributes generate_jajanken.py gave it
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
			emitter(parent, row.name, row.attrs)
		end
	end
end
H.tree = tree

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
