--!strict
--[[
	Test area only: training dummies for the parry system (ReplicatedStorage.Combat), by name.

	  Blocking Dummy   holds its guard up and turns to face you (not instantly: get behind it).
	                   Wear the guard down, or break it with a full Rock.
	  Parrying Dummy   parries every attack it sees coming (it presses F just before the hit).
	                   Beat it with what can't be parried (Thunderbolt), from behind, or with a
	                   Lightning Dash mixup.
	  Sparring Dummy   throws a punch at anyone close every few seconds, telegraphed (it glows red
	                   and pulls its arm back). Practise parrying it (F just before it lands), or
	                   counter it with Whirlwind.

	Dummies keep their brain when DummyRespawn puts them back.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local folder = ReplicatedStorage:WaitForChild("Combat", 10)
local module = folder and folder:FindFirstChild("Combat")
if not (module and module:IsA("ModuleScript")) then
	return -- no parry system in the place: plain dummies
end
local Combat = require(module) :: any

local TURN_SPEED = math.rad(400) -- degrees a second the blocker turns to face you
local PARRY_LEAD = 0.1 -- the parrier presses F this long before a hit lands
local PUNCH = {
	Range = 7, -- studs: it swings at anyone this close
	Every = 2.4, -- seconds between swings
	WindUp = 0.55, -- seconds from the telegraph to the hit
	Damage = 8,
	Stun = 0.45,
	Knockback = 22,
}

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zero
end

-- the nearest living player character within `range`
local function nearestPlayer(model: Model, range: number): Model?
	local root = rootOf(model)
	if not root then
		return nil
	end
	local best, bestDistance = nil, range
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local theirs = character and rootOf(character)
		if character and theirs and Combat.alive(character) then
			local distance = (theirs.Position - root.Position).Magnitude
			if distance <= bestDistance then
				best, bestDistance = character, distance
			end
		end
	end
	return best
end

-- turn toward a point, at most `maxAngle` radians (math.huge: all the way)
local function turnToward(model: Model, point: Vector3, maxAngle: number)
	local root = rootOf(model)
	if not root then
		return
	end
	local want = flat(point - root.Position)
	local look = flat(root.CFrame.LookVector)
	if want == Vector3.zero or look == Vector3.zero then
		return
	end
	local angle = math.acos(math.clamp(look:Dot(want), -1, 1))
	local turn = math.min(angle, maxAngle)
	local side = if look:Cross(want).Y >= 0 then 1 else -1
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, math.atan2(-look.X, -look.Z) + side * turn, 0)
end

--------------------------------------------------------------------------- the brains

local function blocker(model: Model)
	local step = 0.1
	while model.Parent and Combat.alive(model) do
		local target = nearestPlayer(model, 40)
		if target and not Combat.isStunned(model) then
			local theirs = rootOf(target)
			if theirs then
				turnToward(model, theirs.Position, TURN_SPEED * step)
			end
		end
		if not Combat.isStunned(model) and not Combat.isBlocking(model) then
			Combat.setBlocking(model, true)
		end
		task.wait(step)
	end
end

local parriers: { [Model]: number } = {} -- each parrier's latest press (so an old release can't drop a newer guard)

local function parrier(model: Model)
	parriers[model] = 0
	while model.Parent and Combat.alive(model) do
		task.wait(0.5)
	end
	parriers[model] = nil
end

-- is `model` what the attack is aimed at: where it lands (when it says), else in front of the attacker
local function aimedAt(model: Model, from: BasePart, position: Vector3?): boolean
	local root = rootOf(model)
	if not root then
		return false
	end
	if position then
		return (position - root.Position).Magnitude <= 14
	end
	local offset = root.Position - from.Position
	return offset.Magnitude <= 16 and flat(offset):Dot(flat(from.CFrame.LookVector)) > 0.3
end

-- source: where the blow comes from, when that isn't the attacker (a warp hole's)
local function onAnnounced(attacker: Instance, hitAt: number, _ability: string, position: Vector3?, source: Vector3?)
	local from = attacker:IsA("Model") and rootOf(attacker)
	if not from or not Players:GetPlayerFromCharacter(attacker) then
		return -- players' attacks only
	end
	for model in parriers do
		if model ~= attacker and aimedAt(model, from, position) then
			task.delay(math.max(hitAt - Combat.now() - PARRY_LEAD, 0), function()
				if not (model.Parent and Combat.alive(model)) or Combat.isStunned(model) then
					return
				end
				turnToward(model, source or from.Position, math.huge)
				Combat.setBlocking(model, true)
				Combat.openParry(model)
				local press = (parriers[model] or 0) + 1
				parriers[model] = press
				task.delay(Combat.Settings.ParryWindow + 0.15, function()
					if parriers[model] == press and model.Parent then
						Combat.setBlocking(model, false)
					end
				end)
			end)
		end
	end
end
Combat.Announced.Event:Connect(onAnnounced)

-- the telegraph: it glows red and pulls its right arm back, then throws it forward
local function windUp(model: Model, seconds: number): (boolean) -> ()
	local glow = Instance.new("Highlight")
	glow.Name = "Telegraph"
	glow.FillColor = Color3.fromRGB(255, 70, 50)
	glow.OutlineColor = Color3.fromRGB(255, 200, 160)
	glow.FillTransparency = 1
	glow.OutlineTransparency = 0.2
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Parent = model
	TweenService:Create(glow, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		FillTransparency = 0.35,
	}):Play()
	local torso = model:FindFirstChild("Torso")
	local shoulder = torso and torso:FindFirstChild("Right Shoulder")
	local rest = if shoulder and shoulder:IsA("Motor6D") then shoulder.C0 else nil
	if shoulder and shoulder:IsA("Motor6D") and rest then
		TweenService:Create(shoulder, TweenInfo.new(seconds * 0.8, Enum.EasingStyle.Sine), {
			C0 = rest * CFrame.Angles(0, 0, -0.9),
		}):Play()
	end
	return function(thrown: boolean)
		glow:Destroy()
		if shoulder and shoulder:IsA("Motor6D") and rest then
			if thrown then
				TweenService:Create(shoulder, TweenInfo.new(0.06), { C0 = rest * CFrame.Angles(0, 0, 1.5) }):Play()
			end
			task.delay(if thrown then 0.3 else 0, function()
				TweenService:Create(shoulder, TweenInfo.new(0.25), { C0 = rest }):Play()
			end)
		end
	end
end

local function sparring(model: Model)
	while model.Parent and Combat.alive(model) do
		task.wait(PUNCH.Every)
		local target = nearestPlayer(model, PUNCH.Range)
		local root = rootOf(model)
		if target and root and Combat.canAct(model) then
			local theirs = rootOf(target)
			if theirs then
				turnToward(model, theirs.Position, math.huge)
			end
			Combat.setBusy(model, PUNCH.WindUp + 0.3)
			Combat.announce(model, Combat.now() + PUNCH.WindUp, "DummyPunch")
			local release = windUp(model, PUNCH.WindUp)
			task.wait(PUNCH.WindUp)
			local interrupted = Combat.isStunned(model) or not Combat.alive(model)
			release(not interrupted)
			-- it commits to where it aimed: step out of the way and it whiffs
			local look = flat(root.CFrame.LookVector)
			theirs = rootOf(target)
			local offset = if theirs then theirs.Position - root.Position else Vector3.zero
			local inFront = offset.Magnitude <= PUNCH.Range + 1 and flat(offset):Dot(look) > 0.4
			if theirs and inFront and not interrupted and Combat.alive(target) then
				Combat.resolve(model, target, {
					Damage = PUNCH.Damage,
					Ability = "DummyPunch",
					Stun = PUNCH.Stun,
					Knockback = look * PUNCH.Knockback + Vector3.new(0, 6, 0),
					From = root.Position,
				})
			end
		end
	end
end

--------------------------------------------------------------------------- hooking them up

local BRAINS: { [string]: (Model) -> () } = {
	["Blocking Dummy"] = blocker,
	["Parrying Dummy"] = parrier,
	["Sparring Dummy"] = sparring,
}
local running: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function think(child: Instance)
	local brain = BRAINS[child.Name]
	if brain and child:IsA("Model") and not running[child] then
		running[child] = true
		task.spawn(brain, child)
	end
end

local container = script.Parent
container.ChildAdded:Connect(think)
for _, child in container:GetChildren() do
	think(child)
end
