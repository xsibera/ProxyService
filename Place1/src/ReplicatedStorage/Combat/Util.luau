local RunService = game:GetService("RunService")

local Util = {}

-- Instance.new with a property table. Parent is applied last so it replicates/renders once.
function Util.create(className, props, children)
	local inst = Instance.new(className)
	local parent
	if props then
		for key, value in pairs(props) do
			if key == "Parent" then
				parent = value
			else
				inst[key] = value
			end
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- Runs step(alpha, dt) every rendered frame for `duration` seconds, then done().
-- Returns a cancel function.
function Util.animate(duration, step, done)
	local start = os.clock()
	local connection
	local event = if RunService:IsClient() then RunService.RenderStepped else RunService.Heartbeat
	connection = event:Connect(function(dt)
		local alpha = if duration > 0 then math.min(1, (os.clock() - start) / duration) else 1
		local ok, err = pcall(step, alpha, dt)
		if not ok then
			warn("[Util.animate]", err)
			alpha = 1
		end
		if alpha >= 1 then
			connection:Disconnect()
			if done then
				done()
			end
		end
	end)
	return function()
		if connection.Connected then
			connection:Disconnect()
		end
	end
end

function Util.outQuad(t)
	return 1 - (1 - t) * (1 - t)
end

function Util.outCubic(t)
	return 1 - (1 - t) ^ 3
end

function Util.outQuart(t)
	return 1 - (1 - t) ^ 4
end

function Util.inQuad(t)
	return t * t
end

function Util.outBack(t)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

function Util.lerp(a, b, t)
	return a + (b - a) * t
end

function Util.randRange(range)
	if type(range) == "number" then
		return range
	end
	return range[1] + (range[2] - range[1]) * math.random()
end

-- Two perpendicular unit vectors spanning the plane whose normal is `n`.
function Util.basis(n)
	n = if n.Magnitude > 1e-4 then n.Unit else Vector3.zAxis
	local helper = if math.abs(n.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local u = helper:Cross(n).Unit
	local v = n:Cross(u).Unit
	return u, v
end

function Util.flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

function Util.isAlive(model)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and model:FindFirstChild("HumanoidRootPart") ~= nil
end

return Util
