--!nocheck
-- Headless test of CombatVFX.luau against Place1's mock engine. Run from this folder's parent:
--   cd VFX/CombatVFX && luaurun tests/smoke.luau
-- (luaurun: see Place1/README.md)

local mock = assert(loadfile("../../Place1/tests/mock.luau"))()

local failures, passes = 0, 0
local function check(cond, msg)
	if cond then
		passes += 1
	else
		failures += 1
		print("  FAIL: " .. msg)
	end
end
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end

-- the mock's sequences are opaque; give them real keypoints
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

local emitted = {} -- emit log

-- a floor part under y = 0 (or none)
local floorPart = mock.newPart("Floor", Vector3.new(100, 1, 100), CFrame.new(0, -0.5, 0))
floorPart.Color = Color3.new(0.2, 0.6, 0.1)
local floorOn = true
local function raycast(_, origin, direction)
	if not floorOn then
		return nil
	end
	local endY = origin.Y + direction.Y
	if origin.Y >= 0 and endY <= 0 then
		local t = origin.Y / -direction.Y
		return { Position = origin + direction * t, Normal = Vector3.yAxis, Instance = floorPart, Material = nil }
	end
	return nil
end
-- the mock's own Raycast returns hits with no Instance, which Roblox never does; route workspace to ours
local instanceMT = getmetatable(workspace)
local baseIndex = instanceMT.__index
local function logEmit(self, n)
	table.insert(emitted, { name = self.Name, n = n })
end
instanceMT.__index = function(self, key)
	if key == "Raycast" and self == workspace then
		return raycast
	elseif key == "Emit" then -- the mock's Emit is a no-op; log instead
		return logEmit
	end
	return baseIndex(self, key)
end

local function emitter(parent, name, attrs, props)
	local e = mock.newInstance("ParticleEmitter", name)
	e.Enabled = false
	e.Lifetime = NumberRange.new(0.2, 0.5)
	e.TimeScale = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 4, 1) })
	e.Speed = NumberRange.new(10, 20)
	e.Acceleration = Vector3.new(0, -10, 0)
	e.Color = ColorSequence.new(Color3.new(1, 1, 1))
	for k, v in pairs(attrs or {}) do
		e:SetAttribute(k, v)
	end
	for k, v in pairs(props or {}) do
		e[k] = v
	end
	e.Parent = parent
	return e
end
local function attachment(parent, name, cframe)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cframe or CFrame.identity
	a.Parent = parent
	return a
end

-- module + a small effects folder shaped like the real one
local holderFolder = mock.newInstance("Folder", "ReplicatedStorage")
local module = mock.module(holderFolder, "CombatVFX", "CombatVFX.luau")
local effects = mock.newInstance("Folder", "Effects")
effects.Parent = module

local hit = attachment(effects, "TestHit")
hit:SetAttribute("LightBrightness", 5)
hit:SetAttribute("LightRange", 10)
hit:SetAttribute("LightTime", 0.1)
emitter(hit, "Now", { EmitCount = 3, EmitDelay = 0 })
emitter(hit, "Later", { EmitCount = 2, EmitDelay = 0.1 })
emitter(hit, "Accent", { EmitCount = 1, EmitDelay = 0, Accent = true })
emitter(hit, "Window", { EmitCount = 1.4, EmitDelay = 0, EmitDuration = 0.05 })
local hitGround = attachment(hit, "Ground", CFrame.new(0, -3, 0))
emitter(hitGround, "Dust", { EmitCount = 4, EmitDelay = 0, GroundOnly = true, UseGroundColor = true })

local trail = attachment(effects, "TestTrail")
emitter(trail, "Streaks", { Continuous = true })
local trailGround = attachment(trail, "Ground", CFrame.new(0, -3, 0))
emitter(trailGround, "Dust", { Continuous = true, GroundOnly = true, UseGroundColor = true })

local VFX = require(module)

local function find(root, name)
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
end
local function count(name)
	local n = 0
	for _, e in ipairs(emitted) do
		if e.name == name then
			n += e.n
		end
	end
	return n
end

print("== Play over a floor")
local accent = Color3.new(1, 0, 0)
local holder = VFX.Play("TestHit", CFrame.new(0, 3, 0), { Color = accent })
check(holder.Parent == workspace, "holder parented to workspace")
check(count("Now") == 3, "immediate burst emitted 3 (got " .. count("Now") .. ")")
check(count("Later") == 0, "delayed burst waits for EmitDelay")
check(count("Dust") == 4, "ground dust emitted over a floor")
check(count("Window") == 1, "fractional EmitCount rounds (1.4 -> 1)")
local window = find(holder, "Window")
check(window.Enabled == true, "EmitDuration switches the emitter on")
local placed = rawget(find(holder, "Ground"), "__props").WorldCFrame
check(placed ~= nil and near(placed.Position.Y, 0.05, 1e-3), "Ground attachment dropped onto the floor")
local dustColor = find(holder, "Dust").Color.Keypoints[1].Value
check(
	near(dustColor.R, 1 + (0.2 - 1) * 0.6, 1e-6) and near(dustColor.G, 1 + (0.6 - 1) * 0.6, 1e-6),
	"UseGroundColor tints toward the floor"
)
local accentColor = find(holder, "Accent").Color.Keypoints[1].Value
check(accentColor.R == 1 and accentColor.G == 0, "Accent emitter takes the move colour")
check(find(holder, "Now").Color.Keypoints[1].Value.G == 1, "non-accent emitters keep their colour")
check(find(holder, "PointLight") ~= nil, "light flash added")
mock.advance(0.06)
check(window.Enabled == false, "EmitDuration window closes")
mock.advance(0.1)
check(count("Later") == 2, "delayed burst fired after EmitDelay")
mock.advance(1.5)
check(holder.Parent == nil, "holder cleaned up after the particles die")

print("== Play with no floor")
emitted = {}
floorOn = false
local holder2 = VFX.Play("TestHit", CFrame.new(0, 3, 0))
check(count("Dust") == 0, "GroundOnly emitters skipped without floor")
check(count("Now") == 3, "body layers still fire without floor")
check(find(holder2, "Accent").Color.Keypoints[1].Value.G == 1, "no Color option leaves accents alone")
floorOn = true
mock.advance(2)

print("== Scale")
emitted = {}
local holder3 = VFX.Play("TestHit", CFrame.new(0, 3, 0), { Scale = 2 })
local now = find(holder3, "Now")
check(now.Size.Keypoints[2].Value == 8 and now.Size.Keypoints[2].Envelope == 2, "Scale doubles sizes and envelopes")
check(now.Speed.Min == 20 and now.Speed.Max == 40, "Scale doubles speeds")
check(near(now.Acceleration.Y, -20), "Scale doubles acceleration")
check(find(effects, "Now").Size.Keypoints[2].Value == 4, "template left untouched")
mock.advance(2)

print("== Start / Stop")
local root = mock.newPart("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0))
local character = mock.newInstance("Model", "Character")
character.Parent = workspace
root.Parent = character
local handle = VFX.Start("TestTrail", root)
local streaks, dust = find(root, "Streaks"), find(root, "Dust")
check(streaks.Enabled == true, "continuous body layer switched on")
check(dust.Enabled == false, "ground layer waits for the first floor check")
mock.fireFrame(1 / 60)
check(dust.Enabled == true, "ground layer on over a floor")
check(near(dust.Color.Keypoints[1].Value.G, 1 + (0.6 - 1) * 0.6), "ground layer tinted by the floor")
floorOn = false
mock.fireFrame(1 / 60)
check(dust.Enabled == false, "ground layer off in the air")
floorOn = true
mock.fireFrame(1 / 60)
check(near(dust.Color.Keypoints[1].Value.G, 1 + (0.6 - 1) * 0.6), "tint does not compound frame to frame")
handle:Stop()
check(streaks.Enabled == false and dust.Enabled == false, "Stop switches everything off")
handle:Stop()
check(true, "Stop twice is harmless")
mock.advance(1)
check(find(root, "TestTrail") == nil, "continuous effect removed after its particles die")

print("== Unknown effect")
local ok = pcall(VFX.Play, "Nope", CFrame.identity)
check(not ok, "unknown effect name errors")

for _, w in ipairs(mock.warnings) do
	print("  WARNING: " .. w)
end
check(#mock.warnings == 0, "no warnings")
print(("\n%d passed, %d failed"):format(passes, failures))
if failures > 0 then
	error("CombatVFX smoke test failed", 0)
end
