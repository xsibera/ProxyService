-- Training dummies. Each model in Workspace.Dummies has a "DummyType" attribute:
--   Bag       stands still and takes hits
--   Blocker   always holds block (break it with a heavy or by draining its posture)
--   Parrier   reads your windups and parries most attacks (practise getting parried / baiting)
--   Attacker  chases you and throws combos and heavies (practise blocking and parrying)
--   Sparring  a full sparring partner: blocks, parries, dodges and counter-attacks
-- Dummies respawn after dying and heal back up when left alone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Config = require(Combat.Config)
local Util = require(Combat.Util)

local CombatService = require(script.Parent.CombatService)

local create = Util.create
local flat = Util.flat

local DummyAI = {}

local DUMMY_CONFIG = Config.Dummy
local brains = {} -- [fighter] = brain

local templates
local function templateFolder()
	if not templates then
		templates = create("Folder", { Name = "DummyTemplates", Parent = ServerStorage })
	end
	return templates
end

local function nearestPlayerFighter(position, range)
	local best, bestDist = nil, range
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local f = character and CombatService.Get(character)
		if f and not f.Dead and f.Root.Parent then
			local d = (f.Root.Position - position).Magnitude
			if d < bestDist then
				best, bestDist = f, d
			end
		end
	end
	return best, bestDist
end

local function face(brain, position)
	local delta = flat(position - brain.Fighter.Root.Position)
	if delta.Magnitude > 0.1 then
		brain.Align.CFrame = CFrame.lookAt(Vector3.zero, delta.Unit)
	end
end

local function canAct(f)
	local t = os.clock()
	return not f.Dead and t >= f.StunUntil and t >= f.ActionEnd and t >= f.DodgingUntil
end

local function pressBlock(f, holdFor)
	CombatService.TryBlockStart(f)
	local token = {}
	f.BlockToken = token
	task.delay(holdFor, function()
		if f.BlockToken == token and f.Model:GetAttribute("DummyType") ~= "Blocker" then
			CombatService.TryBlockEnd(f)
		end
	end)
end

local function dodge(f, dirName)
	local root = f.Root
	local cf = root.CFrame
	local vectors = {
		Back = -cf.LookVector,
		Left = -cf.RightVector,
		Right = cf.RightVector,
		Forward = cf.LookVector,
	}
	local before = f.DodgeCooldownUntil
	CombatService.TryDodge(f, dirName, nil)
	if f.DodgeCooldownUntil ~= before then
		CombatService.Push(f, flat(vectors[dirName]).Unit * Config.Dodge.Speed * 0.8, Config.Dodge.Duration * 0.8)
		return true
	end
	return false
end

-- Throws an n-hit chain, pressing each punch as the previous one ends.
local function throwChain(brain, hits)
	local f = brain.Fighter
	brain.Busy = true
	task.spawn(function()
		for i = 1, hits do
			if f.Dead or os.clock() < f.StunUntil or brain.Dead then
				break
			end
			if brain.Target then
				face(brain, brain.Target.Root.Position)
			end
			CombatService.TryM1(f, nil)
			-- press the next punch just before this one ends (the server queues it)
			task.wait(math.max(0.05, f.ActionEnd - os.clock() - (if i == hits then 0 else 0.05)))
		end
		brain.Busy = false
		brain.NextAttack = os.clock() + 0.7 + math.random() * 0.8
	end)
end

local function throwHeavy(brain)
	local f = brain.Fighter
	if os.clock() < f.HeavyCooldownUntil then
		return false
	end
	brain.Busy = true
	CombatService.TryHeavy(f, nil)
	task.delay(Config.Heavy.Duration, function()
		brain.Busy = false
		brain.NextAttack = os.clock() + 0.9 + math.random() * 0.6
	end)
	return true
end

----------------------------------------------------------------------------------------------
-- Reactions to incoming attacks

local function attackAimedAt(attacker, f, spec)
	local delta = flat(f.Root.Position - attacker.Root.Position)
	local dist = delta.Magnitude
	if dist > 11 or dist < 0.05 then
		return false
	end
	local look = flat(attacker.Root.CFrame.LookVector)
	return look.Magnitude > 0 and look.Unit:Dot(delta.Unit) > 0.35 and spec ~= nil
end

local function schedulePerfectParry(f, spec, jitter)
	-- press so the hit lands in the middle of the parry window
	local pressIn = math.max(0, spec.Windup - Config.Parry.Window * 0.5 + (jitter or 0))
	task.delay(pressIn, function()
		if not f.Dead and os.clock() >= f.StunUntil and os.clock() >= f.ActionEnd then
			pressBlock(f, Config.Parry.Window + 0.25)
		end
	end)
end

local function onAttackStarted(attacker, _kind, spec)
	for f, brain in pairs(brains) do
		if f == attacker or f.Dead or brain.Dead or not attackAimedAt(attacker, f, spec) then
			continue
		end
		face(brain, attacker.Root.Position)
		local kindName = brain.Kind
		if kindName == "Parrier" then
			if canAct(f) and math.random() < 0.85 then
				schedulePerfectParry(f, spec, (math.random() - 0.5) * 0.04)
			end
		elseif kindName == "Sparring" then
			if canAct(f) and not brain.Busy then
				local roll = math.random()
				if roll < 0.35 then
					schedulePerfectParry(f, spec, (math.random() - 0.5) * 0.12)
				elseif roll < 0.62 then
					task.delay(0.08 + math.random() * 0.06, function()
						if canAct(f) then
							pressBlock(f, 0.9)
						end
					end)
				elseif roll < 0.78 then
					task.delay(math.max(0, spec.Windup - 0.12), function()
						if canAct(f) then
							local dirs = { "Back", "Left", "Right" }
							dodge(f, dirs[math.random(1, #dirs)])
						end
					end)
				end
			end
		end
	end
end

local function onResult(result, attacker, victim)
	-- Sparring partners punish openings: after parrying/blocking, or when you get parried.
	local brain = brains[victim]
	if brain and brain.Kind == "Sparring" and (result == "Parry" or result == "Blocked") then
		brain.CounterAt = os.clock() + (if result == "Parry" then 0.12 else 0.35)
	end
	local attackerBrain = brains[attacker]
	if attackerBrain and result == "Parry" then
		attackerBrain.NextAttack = os.clock() + Config.Parry.AttackerStun + 0.4
	end
end

----------------------------------------------------------------------------------------------
-- Brain loop

local function think(brain, dt)
	local f = brain.Fighter
	local root = f.Root
	local humanoid = f.Humanoid
	if f.Dead or not root.Parent then
		return
	end
	local t = os.clock()
	local kind = brain.Kind
	local aggressive = kind == "Attacker" or kind == "Sparring"
	local target, dist = nearestPlayerFighter(root.Position, if aggressive then DUMMY_CONFIG.AggroRange else 40)
	brain.Target = target
	local fromHome = flat(root.Position - brain.Home.Position).Magnitude

	if kind == "Blocker" and not f.WantsBlock and t >= f.StunUntil then
		CombatService.TryBlockStart(f)
	end

	if target then
		face(brain, target.Root.Position)
	else
		brain.Align.CFrame = brain.Home.Rotation
	end

	-- Movement
	local move = Vector3.zero
	if aggressive and target and fromHome < DUMMY_CONFIG.LeashRange and t >= f.StunUntil then
		local delta = flat(target.Root.Position - root.Position)
		if dist > DUMMY_CONFIG.AttackRange - 0.8 then
			move = delta.Unit
		elseif not brain.Busy then
			-- circle a little while waiting to attack
			brain.StrafeSign = brain.StrafeSign or 1
			if math.random() < dt * 0.6 then
				brain.StrafeSign = -brain.StrafeSign
			end
			move = root.CFrame.RightVector * brain.StrafeSign * 0.5
		end
		f.DesiredWalkSpeed = if dist > 12 then 18 else 13
	elseif fromHome > 1.5 then
		move = flat(brain.Home.Position - root.Position).Unit
		f.DesiredWalkSpeed = 14
	end
	humanoid:Move(move, false)

	-- Attacking
	if aggressive and target and dist <= DUMMY_CONFIG.AttackRange and canAct(f) and not brain.Busy then
		local counter = brain.CounterAt and t >= brain.CounterAt
		if counter then
			brain.CounterAt = nil
			if f.Blocking then
				CombatService.TryBlockEnd(f)
			end
			throwChain(brain, 4)
		elseif t >= (brain.NextAttack or 0) and not f.Blocking then
			local targetBlockingLong = target.Blocking and (t - target.BlockStart) > 0.9
			if (targetBlockingLong or math.random() < 0.2) and throwHeavy(brain) then
				return
			end
			throwChain(brain, if kind == "Attacker" then 4 else math.random(2, 4))
		end
	end

	-- Heal up when left alone
	if t - f.LastHitTime > DUMMY_CONFIG.RegenDelay and humanoid.Health < humanoid.MaxHealth then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * 0.6 * dt)
	end
end

----------------------------------------------------------------------------------------------
-- Spawning

local function setup(model, template, folder)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) then
		warn("[DummyAI] " .. model:GetFullName() .. " is missing a Humanoid or HumanoidRootPart")
		return
	end
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	humanoid.MaxHealth = DUMMY_CONFIG.MaxHealth
	humanoid.Health = DUMMY_CONFIG.MaxHealth
	humanoid.AutoRotate = false
	humanoid.BreakJointsOnDeath = true
	model:SetAttribute("AlwaysCombat", true)

	local f = CombatService.Register(model, { IsDummy = true })
	if not f then
		return
	end
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local attachment = root:FindFirstChild("RootAttachment")
		or create("Attachment", { Name = "RootAttachment", Parent = root })
	local align = create("AlignOrientation", {
		Name = "FaceTarget",
		Mode = Enum.OrientationAlignmentMode.OneAttachment,
		Attachment0 = attachment,
		Responsiveness = 28,
		MaxTorque = 1e6,
		CFrame = root.CFrame.Rotation,
		Parent = root,
	})

	local brain = {
		Fighter = f,
		Kind = model:GetAttribute("DummyType") or "Bag",
		Home = root.CFrame,
		Align = align,
		Busy = false,
		NextAttack = os.clock() + 1.5,
	}
	brains[f] = brain

	humanoid.Died:Connect(function()
		brain.Dead = true
		brains[f] = nil
		task.delay(DUMMY_CONFIG.RespawnTime, function()
			model:Destroy()
			local fresh = template:Clone()
			fresh.Parent = folder
			setup(fresh, template, folder)
		end)
	end)
end

function DummyAI.Start()
	local folder = Workspace:FindFirstChild("Dummies")
	if not folder then
		warn("[DummyAI] Workspace.Dummies not found, no dummies will spawn")
		return
	end
	CombatService.OnAttackStarted(onAttackStarted)
	CombatService.OnResult(onResult)

	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") then
			local template = model:Clone()
			template.Parent = templateFolder()
			setup(model, template, folder)
		end
	end

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.05 then
			return
		end
		local step = accumulator
		accumulator = 0
		for _, brain in pairs(brains) do
			local ok, err = pcall(think, brain, step)
			if not ok then
				warn("[DummyAI]", err)
			end
		end
	end)
end

return DummyAI
