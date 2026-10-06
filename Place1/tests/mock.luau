--!nocheck
-- A small fake Roblox engine, just big enough to run the combat modules headlessly:
-- Vector3/CFrame math, Instances with properties/children/attributes/signals, a virtual clock
-- with task.delay/spawn/wait, RemoteEvents that log what they send, and spatial queries.

local M = {}

M.warnings = {}
warn = function(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	table.insert(M.warnings, table.concat(parts, " "))
end

----------------------------------------------------------------------------------------------
-- Virtual time + scheduler

local now = 0
local queue = {}
local seqCounter = 0

local function schedule(at, fn, args)
	seqCounter += 1
	table.insert(queue, { at = at, fn = fn, args = args, seq = seqCounter })
end

os.clock = function()
	return now
end

local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		error(debug.traceback(co, tostring(err)), 0)
	end
end

local function runFn(fn, args)
	if type(fn) == "thread" then
		resume(fn, table.unpack(args or {}))
	else
		local co = coroutine.create(fn)
		resume(co, table.unpack(args or {}))
	end
end

task = {
	spawn = function(fn, ...)
		runFn(fn, { ... })
	end,
	defer = function(fn, ...)
		schedule(now, fn, { ... })
	end,
	delay = function(t, fn, ...)
		schedule(now + (t or 0), fn, { ... })
	end,
	wait = function(t)
		local co = coroutine.running()
		schedule(now + (t or 0), co, {})
		return coroutine.yield()
	end,
}

function M.now()
	return now
end

local signals = {}

-- advance the clock in frames, firing scheduled tasks and frame events
function M.advance(seconds, fps)
	fps = fps or 60
	local dt = 1 / fps
	local target = now + seconds
	while now < target - 1e-9 do
		local stepTo = math.min(target, now + dt)
		while true do
			table.sort(queue, function(a, b)
				if a.at == b.at then
					return a.seq < b.seq
				end
				return a.at < b.at
			end)
			local first = queue[1]
			if not first or first.at > stepTo then
				break
			end
			table.remove(queue, 1)
			now = math.max(now, first.at)
			runFn(first.fn, first.args)
		end
		local frameDt = stepTo - now
		now = stepTo
		if frameDt > 0 then
			M.fireFrame(frameDt)
		end
	end
end

----------------------------------------------------------------------------------------------
-- Signals

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local entry = { fn = fn, Connected = true }
	table.insert(self.handlers, entry)
	function entry.Disconnect()
		entry.Connected = false
	end
	return setmetatable(entry, {
		__index = function(_, k)
			if k == "Disconnect" then
				return function()
					entry.Connected = false
				end
			end
		end,
	})
end

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn.Connected = false
		fn(...)
	end)
	return conn
end

function Signal:Fire(...)
	for _, h in ipairs(self.handlers) do
		if h.Connected then
			h.fn(...)
		end
	end
end

function Signal:Wait()
	local co = coroutine.running()
	self:Once(function(...)
		task.spawn(co, ...)
	end)
	return coroutine.yield()
end

M.Signal = Signal

----------------------------------------------------------------------------------------------
-- Vector3 / Vector2

local Vector3 = {}
local V3 = {}

local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __type = "Vector3" }, V3)
end

V3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then
			return v3(0 / 0, 0 / 0, 0 / 0)
		end
		return v3(v.X / m, v.Y / m, v.Z / m)
	end
	return Vector3[k]
end
V3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(v)
	return string.format("(%.3f, %.3f, %.3f)", v.X, v.Y, v.Z)
end

function Vector3.new(x, y, z)
	return v3(x, y, z)
end
function Vector3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function Vector3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function Vector3.Lerp(a, b, t)
	return a + (b - a) * t
end
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)
_G.Vector3 = Vector3
M.Vector3 = Vector3

local Vector2 = {}
local V2 = {}
local function v2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2)
end
V2.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	end
	return Vector2[k]
end
V2.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2.__mul = function(a, b)
	if type(a) == "number" then
		return v2(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b)
	if type(b) == "number" then
		return v2(a.X / b, a.Y / b)
	end
	return v2(a.X / b.X, a.Y / b.Y)
end
function Vector2.new(x, y)
	return v2(x, y)
end
Vector2.zero = v2(0, 0)
_G.Vector2 = Vector2

----------------------------------------------------------------------------------------------
-- CFrame (rotation matrix rows + position)

local CFrame = {}
local CF = {}

local function cf(px, py, pz, r)
	return setmetatable({ p = v3(px, py, pz), r = r, __type = "CFrame" }, CF)
end

local I3 = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local function mmul(a, b)
	local o = {}
	for i = 0, 2 do
		for j = 0, 2 do
			o[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return o
end

local function mvec(r, v)
	return v3(r[1] * v.X + r[2] * v.Y + r[3] * v.Z, r[4] * v.X + r[5] * v.Y + r[6] * v.Z, r[7] * v.X + r[8] * v.Y + r[9] * v.Z)
end

local function transpose(r)
	return { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
end

local function rx(a)
	local c, s = math.cos(a), math.sin(a)
	return { 1, 0, 0, 0, c, -s, 0, s, c }
end
local function ry(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, 0, s, 0, 1, 0, -s, 0, c }
end
local function rz(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end

CF.__index = function(c, k)
	if k == "Position" then
		return c.p
	elseif k == "X" then
		return c.p.X
	elseif k == "Y" then
		return c.p.Y
	elseif k == "Z" then
		return c.p.Z
	elseif k == "Rotation" then
		return cf(0, 0, 0, c.r)
	elseif k == "LookVector" then
		return v3(-c.r[3], -c.r[6], -c.r[9])
	elseif k == "RightVector" then
		return v3(c.r[1], c.r[4], c.r[7])
	elseif k == "UpVector" then
		return v3(c.r[2], c.r[5], c.r[8])
	end
	return CFrame[k]
end
CF.__mul = function(a, b)
	if getmetatable(b) == CF then
		local r = mmul(a.r, b.r)
		local p = mvec(a.r, b.p) + a.p
		return cf(p.X, p.Y, p.Z, r)
	end
	return mvec(a.r, b) + a.p
end
CF.__add = function(a, v)
	return cf(a.p.X + v.X, a.p.Y + v.Y, a.p.Z + v.Z, a.r)
end
CF.__sub = function(a, v)
	return cf(a.p.X - v.X, a.p.Y - v.Y, a.p.Z - v.Z, a.r)
end
CF.__eq = function(a, b)
	if a.p ~= b.p then
		return false
	end
	for i = 1, 9 do
		if a.r[i] ~= b.r[i] then
			return false
		end
	end
	return true
end

function CFrame.new(...)
	local n = select("#", ...)
	local a = { ... }
	if n == 0 then
		return cf(0, 0, 0, I3)
	elseif n == 1 then
		return cf(a[1].X, a[1].Y, a[1].Z, I3)
	elseif n == 3 then
		return cf(a[1], a[2], a[3], I3)
	elseif n == 12 then
		return cf(a[1], a[2], a[3], { a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12] })
	end
	error("CFrame.new: unsupported arguments")
end
function CFrame.fromEulerAnglesYXZ(x, y, z)
	return cf(0, 0, 0, mmul(mmul(ry(y), rx(x)), rz(z)))
end
function CFrame.Angles(x, y, z)
	return cf(0, 0, 0, mmul(mmul(rx(x), ry(y)), rz(z)))
end
function CFrame.fromMatrix(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy).Unit
	return cf(pos.X, pos.Y, pos.Z, { vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z })
end
function CFrame.lookAt(at, target, up)
	up = up or Vector3.yAxis
	local look = (target - at).Unit
	local right = look:Cross(up).Unit
	local up2 = right:Cross(look).Unit
	return CFrame.fromMatrix(at, right, up2, -look)
end
function CFrame.Inverse(c)
	local rt = transpose(c.r)
	local p = mvec(rt, -c.p)
	return cf(p.X, p.Y, p.Z, rt)
end
function CFrame.Lerp(a, b, t)
	local r = {}
	for i = 1, 9 do
		r[i] = a.r[i] + (b.r[i] - a.r[i]) * t
	end
	local p = a.p:Lerp(b.p, t)
	return cf(p.X, p.Y, p.Z, r)
end
function CFrame.VectorToObjectSpace(c, v)
	return mvec(transpose(c.r), v)
end
function CFrame.VectorToWorldSpace(c, v)
	return mvec(c.r, v)
end
function CFrame.PointToObjectSpace(c, v)
	return mvec(transpose(c.r), v - c.p)
end
function CFrame.ToEulerAnglesYXZ(c)
	local r = c.r
	local x = math.asin(-math.clamp(r[6], -1, 1))
	local y = math.atan2(r[3], r[9])
	local z = math.atan2(r[4], r[5])
	return x, y, z
end
function CFrame.GetComponents(c)
	local r = c.r
	return c.p.X, c.p.Y, c.p.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
end
CFrame.identity = cf(0, 0, 0, I3)
_G.CFrame = CFrame
M.CFrame = CFrame

----------------------------------------------------------------------------------------------
-- Small datatypes

local function plain(name)
	return function(...)
		return { __type = name, ... }
	end
end

Color3 = {
	new = function(r, g, b)
		local c = { R = r or 0, G = g or 0, B = b or 0 }
		c.Lerp = function(self, o, t)
			return Color3.new(self.R + (o.R - self.R) * t, self.G + (o.G - self.G) * t, self.B + (o.B - self.B) * t)
		end
		return c
	end,
}
Color3.fromRGB = function(r, g, b)
	return Color3.new(r / 255, g / 255, b / 255)
end
ColorSequence = { new = plain("ColorSequence") }
NumberSequence = { new = plain("NumberSequence") }
NumberSequenceKeypoint = { new = plain("NumberSequenceKeypoint") }
NumberRange = { new = plain("NumberRange") }
UDim = { new = plain("UDim") }
UDim2 = { new = plain("UDim2"), fromScale = plain("UDim2"), fromOffset = plain("UDim2") }
TweenInfo = { new = plain("TweenInfo") }

local enumCache = {}
Enum = setmetatable({}, {
	__index = function(_, enumName)
		local items = enumCache[enumName]
		if not items then
			items = setmetatable({}, {
				__index = function(t, itemName)
					local item = { Name = itemName, EnumType = enumName, Value = 0 }
					rawset(t, itemName, item)
					return item
				end,
			})
			enumCache[enumName] = items
		end
		return items
	end,
})

local function newParams()
	return { FilterDescendantsInstances = {}, FilterType = nil }
end
RaycastParams = { new = newParams }
OverlapParams = { new = newParams }

typeof = function(v)
	if type(v) == "table" then
		if v.__type then
			return v.__type
		end
		if rawget(v, "__props") then
			return "Instance"
		end
	end
	return type(v)
end

----------------------------------------------------------------------------------------------
-- Instances

local ISA = {
	Part = { "BasePart", "PVInstance" },
	WedgePart = { "BasePart", "PVInstance" },
	SpawnLocation = { "Part", "BasePart", "PVInstance" },
	Model = { "PVInstance" },
	Motor6D = { "JointInstance" },
	ModuleScript = { "LuaSourceContainer" },
	Script = { "BaseScript", "LuaSourceContainer" },
	LocalScript = { "Script", "BaseScript", "LuaSourceContainer" },
}

local InstanceMT = {}
local Methods = {}
local debugIds = 0

local function newInstance(className, name)
	debugIds += 1
	local self = setmetatable({
		__props = { ClassName = className, Name = name or className },
		__children = {},
		__attrs = {},
		__signals = {},
		__id = debugIds,
	}, InstanceMT)
	return self
end
M.newInstance = newInstance

local function getSignal(self, name)
	local s = rawget(self, "__signals")[name]
	if not s then
		s = Signal.new()
		rawget(self, "__signals")[name] = s
	end
	return s
end

local EVENTS = {
	Died = true,
	Destroying = true,
	AncestryChanged = true,
	ChildAdded = true,
	OnServerEvent = true,
	OnClientEvent = true,
	Ended = true,
	CharacterAdded = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	Heartbeat = true,
	PreSimulation = true,
	RenderStepped = true,
	Stepped = true,
	InputBegan = true,
	InputEnded = true,
	JumpRequest = true,
}

InstanceMT.__index = function(self, key)
	local m = Methods[key]
	if m then
		return m
	end
	local props = rawget(self, "__props")
	local v = props[key]
	if v ~= nil then
		return v
	end
	if key == "Parent" then
		return nil
	end
	for _, c in ipairs(rawget(self, "__children")) do
		if c.Name == key then
			return c
		end
	end
	if EVENTS[key] then
		return getSignal(self, key)
	end
	return nil
end

InstanceMT.__newindex = function(self, key, value)
	local props = rawget(self, "__props")
	if key == "Parent" then
		local old = props.Parent
		if old == value then
			return
		end
		if old then
			local list = rawget(old, "__children")
			for i, c in ipairs(list) do
				if c == self then
					table.remove(list, i)
					break
				end
			end
		end
		props.Parent = value
		if value then
			table.insert(rawget(value, "__children"), self)
			getSignal(value, "ChildAdded"):Fire(self)
		end
		getSignal(self, "AncestryChanged"):Fire(self, value)
		return
	end
	props[key] = value
	if key == "Health" and props.ClassName == "Humanoid" and value <= 0 and not props.__dead then
		props.__dead = true
		getSignal(self, "Died"):Fire()
	end
end

InstanceMT.__tostring = function(self)
	return self.Name
end

function Methods.FindFirstChild(self, name, recursive)
	for _, c in ipairs(rawget(self, "__children")) do
		if c.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(rawget(self, "__children")) do
			local f = c:FindFirstChild(name, true)
			if f then
				return f
			end
		end
	end
	return nil
end

function Methods.WaitForChild(self, name)
	local c = self:FindFirstChild(name)
	if not c then
		error("WaitForChild would hang: " .. self.Name .. "." .. name)
	end
	return c
end

function Methods.GetChildren(self)
	return table.clone(rawget(self, "__children"))
end

function Methods.GetDescendants(self)
	local out = {}
	local function walk(n)
		for _, c in ipairs(rawget(n, "__children")) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end

function Methods.IsA(self, className)
	local own = self.ClassName
	if own == className or className == "Instance" then
		return true
	end
	for _, c in ipairs(ISA[own] or {}) do
		if c == className then
			return true
		end
	end
	return false
end

function Methods.FindFirstChildOfClass(self, className)
	for _, c in ipairs(rawget(self, "__children")) do
		if c.ClassName == className then
			return c
		end
	end
	return nil
end
Methods.FindFirstChildWhichIsA = function(self, className)
	for _, c in ipairs(rawget(self, "__children")) do
		if c:IsA(className) then
			return c
		end
	end
	return nil
end

function Methods.FindFirstAncestorOfClass(self, className)
	local p = self.Parent
	while p do
		if p.ClassName == className then
			return p
		end
		p = p.Parent
	end
	return nil
end

function Methods.IsDescendantOf(self, other)
	local p = self.Parent
	while p do
		if p == other then
			return true
		end
		p = p.Parent
	end
	return false
end

function Methods.Destroy(self)
	getSignal(self, "Destroying"):Fire()
	for _, c in ipairs(self:GetChildren()) do
		c:Destroy()
	end
	self.Parent = nil
end

function Methods.Clone(self)
	local copy = newInstance(self.ClassName, self.Name)
	for k, v in pairs(rawget(self, "__props")) do
		if k ~= "Parent" then
			rawget(copy, "__props")[k] = v
		end
	end
	for k, v in pairs(rawget(self, "__attrs")) do
		rawget(copy, "__attrs")[k] = v
	end
	for _, c in ipairs(rawget(self, "__children")) do
		c:Clone().Parent = copy
	end
	return copy
end

function Methods.GetAttribute(self, name)
	return rawget(self, "__attrs")[name]
end
function Methods.SetAttribute(self, name, value)
	rawget(self, "__attrs")[name] = value
end
function Methods.GetDebugId(self)
	return tostring(rawget(self, "__id"))
end
function Methods.GetFullName(self)
	return self.Name
end
function Methods.SetNetworkOwner() end
function Methods.GetPivot(self)
	return self.CFrame or (self.PrimaryPart and self.PrimaryPart.CFrame) or CFrame.identity
end
function Methods.PivotTo(self, c)
	self.CFrame = c
end
function Methods.Connect(self)
	error("Connect called on an Instance: " .. self.Name)
end

-- Humanoid
function Methods.TakeDamage(self, amount)
	self.Health = math.max(0, (self.Health or 100) - amount)
end
function Methods.Move(self, dir)
	rawget(self, "__props").MoveVector = dir
end
function Methods.GetState()
	return Enum.HumanoidStateType.Running
end
function Methods.ChangeState() end

-- RemoteEvent
M.fxLog = {}
function Methods.FireAllClients(self, kind, data)
	table.insert(M.fxLog, { remote = self.Name, kind = kind, data = data, t = now })
end
function Methods.FireClient(self, player, kind, data)
	table.insert(M.fxLog, { remote = self.Name, kind = kind, data = data, t = now, player = player })
end
function Methods.FireServer(self, ...)
	table.insert(M.fxLog, { remote = self.Name, kind = "client->server", data = { ... }, t = now })
end

-- Sound / emitters (no-ops)
function Methods.Play() end
function Methods.Stop() end
function Methods.Emit() end
function Methods.Once(self, fn)
	return Signal.new():Once(fn)
end

function Methods.GetPartBoundsInBox(self, boxCF, size)
	local out = {}
	local inv = boxCF:Inverse()
	local half = size / 2
	for _, part in ipairs(self:GetDescendants()) do
		if part:IsA("BasePart") and part.CanQuery ~= false then
			local lp = inv * part.Position
			if math.abs(lp.X) <= half.X + 0.5 and math.abs(lp.Y) <= half.Y + 1 and math.abs(lp.Z) <= half.Z + 0.5 then
				table.insert(out, part)
			end
		end
	end
	return out
end

-- Flat ground at y = 0
function Methods.Raycast(_, origin, direction)
	local endY = origin.Y + direction.Y
	if origin.Y >= 0 and endY <= 0 and direction.Y ~= 0 then
		local t = origin.Y / -direction.Y
		return { Position = origin + direction * t, Normal = Vector3.yAxis, Instance = nil, Distance = direction.Magnitude * t }
	end
	return nil
end

-- Parts keep Position in sync with CFrame
local PartProps = {}
function M.newPart(name, size, cframe)
	local p = newInstance("Part", name)
	p.Size = size
	p.CFrame = cframe
	p.AssemblyLinearVelocity = Vector3.zero
	return p
end
-- Position is derived from CFrame
local baseIndex = InstanceMT.__index
InstanceMT.__index = function(self, key)
	if key == "Position" then
		local props = rawget(self, "__props")
		if props.Position ~= nil then
			return props.Position
		end
		if props.CFrame then
			return props.CFrame.Position
		end
	elseif key == "WorldCFrame" then
		local parent = rawget(self, "__props").Parent
		return (parent and parent.CFrame or CFrame.identity) * (rawget(self, "__props").CFrame or CFrame.identity)
	end
	return baseIndex(self, key)
end
PartProps = nil

Instance = {
	new = function(className, parent)
		local inst = newInstance(className)
		if className == "Humanoid" then
			inst.Health = 100
			inst.MaxHealth = 100
		elseif className == "Attachment" then
			inst.CFrame = CFrame.identity
		elseif className == "Frame" or className == "ScreenGui" then
			inst.AbsoluteSize = Vector2.new(1920, 1080)
		end
		if parent then
			inst.Parent = parent
		end
		return inst
	end,
}

----------------------------------------------------------------------------------------------
-- Services

local services = {}
game = newInstance("DataModel", "game")
workspace = newInstance("Workspace", "Workspace")
workspace.Parent = game
services.Workspace = workspace

local function service(name)
	local s = services[name]
	if not s then
		s = newInstance(name, name)
		s.Parent = game
		services[name] = s
	end
	return s
end

function Methods.GetService(_, name)
	return service(name)
end

local RunService = service("RunService")
function Methods.IsClient()
	return M.isClient == true
end
function Methods.IsServer()
	return M.isClient ~= true
end
local renderSteps = {}
function Methods.BindToRenderStep(_, name, priority, fn)
	table.insert(renderSteps, { name = name, priority = priority, fn = fn })
	table.sort(renderSteps, function(a, b)
		return a.priority < b.priority
	end)
end
M.renderSteps = renderSteps

function M.fireFrame(dt)
	for _, step in ipairs(renderSteps) do
		step.fn(dt)
	end
	getSignal(RunService, "PreSimulation"):Fire(dt)
	getSignal(RunService, "Heartbeat"):Fire(dt)
	getSignal(RunService, "RenderStepped"):Fire(dt)
end

local TweenService = service("TweenService")
local easing = {
	Linear = function(t)
		return t
	end,
	Quad = function(t)
		return t * t
	end,
	Cubic = function(t)
		return t * t * t
	end,
	Quart = function(t)
		return t ^ 4
	end,
	Sine = function(t)
		return 1 - math.cos(t * math.pi / 2)
	end,
}
function Methods.GetValue(_, alpha, style, dir)
	local f = easing[style.Name]
	assert(f, "mock TweenService: unsupported easing style " .. tostring(style.Name))
	if dir.Name == "In" then
		return f(alpha)
	elseif dir.Name == "Out" then
		return 1 - f(1 - alpha)
	end
	if alpha < 0.5 then
		return f(alpha * 2) / 2
	end
	return 1 - f((1 - alpha) * 2) / 2
end
function Methods.Create()
	return { Play = function() end, Cancel = function() end, Completed = Signal.new() }
end

local Debris = service("Debris")
function Methods.AddItem(_, inst, t)
	task.delay(t, function()
		if inst.Parent then
			inst:Destroy()
		end
	end)
end

local CollectionService = service("CollectionService")
local tags = {}
function Methods.AddTag(_, inst, tag)
	tags[tag] = tags[tag] or {}
	tags[tag][inst] = true
end
function Methods.HasTag(_, inst, tag)
	return tags[tag] ~= nil and tags[tag][inst] == true
end
function Methods.GetTagged(_, tag)
	local out = {}
	for inst in pairs(tags[tag] or {}) do
		table.insert(out, inst)
	end
	return out
end
local tagAdded = {}
function Methods.GetInstanceAddedSignal(_, tag)
	tagAdded[tag] = tagAdded[tag] or Signal.new()
	return tagAdded[tag]
end
function Methods.GetInstanceRemovedSignal()
	return Signal.new()
end

local Players = service("Players")
M.players = {}
function Methods.GetPlayers()
	return table.clone(M.players)
end
function Methods.GetPlayerFromCharacter(_, model)
	for _, p in ipairs(M.players) do
		if p.Character == model then
			return p
		end
	end
	return nil
end

M.actions = {}
function Methods.BindAction(_, name, fn, touch, ...)
	M.actions[name] = { fn = fn, touch = touch, inputs = { ... } }
end
function Methods.SetTitle() end
function Methods.SetPosition() end
function Methods.SetCoreGuiEnabled() end
function Methods.PreloadAsync() end

service("ContentProvider")
service("ServerStorage")
service("ReplicatedStorage")
service("ServerScriptService")
service("StarterPlayer")
service("StarterGui")
service("UserInputService")
service("ContextActionService")
service("Lighting")

----------------------------------------------------------------------------------------------
-- Module loading: mirror a folder of .luau files as ModuleScripts

local moduleCache = {}

function M.mount(parent, dir, name, className)
	-- name.luau -> ModuleScript, name/init.luau (or init.server/client) -> script with children
	local inst = newInstance(className or "Folder", name)
	inst.Parent = parent
	return inst
end

function M.module(parent, name, path)
	local inst = newInstance("ModuleScript", name)
	rawget(inst, "__props").__path = path
	inst.Parent = parent
	return inst
end

require = function(target)
	if type(target) ~= "table" then
		error("require expects a ModuleScript")
	end
	local path = rawget(target, "__props").__path
	if not path then
		error("require: " .. tostring(target.Name) .. " has no source")
	end
	if moduleCache[target] ~= nil then
		return moduleCache[target]
	end
	local fn, err = loadfile(path)
	if not fn then
		error(err, 0)
	end
	local env = setmetatable({ script = target }, { __index = _G })
	setfenv(fn, env)
	local result = fn()
	moduleCache[target] = result
	return result
end

function M.runScript(scriptInst)
	local path = rawget(scriptInst, "__props").__path
	local fn, err = loadfile(path)
	if not fn then
		error(err, 0)
	end
	setfenv(fn, setmetatable({ script = scriptInst }, { __index = _G }))
	task.spawn(fn)
end

M.service = service
return M
