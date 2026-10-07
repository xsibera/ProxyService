--!strict
--[[
	The village's bandits (every Model named "Bandit" beside this script, in the camp past the gate).

	They wait round their campfire, wandering a little. Come within AGGRO studs and they come for you:
	they run you down and throw M1 strings at you through the same stun system the players use
	(ServerScriptService.MeleeServer.NpcM1), so you're stunned through their strings as they are
	through yours, and you can block (F) or parry them (tap F as a hit comes). They sometimes block or
	parry your hits too. Lead them more than LEASH studs from their camp and they give up, go back and
	patch themselves up. A bandit that's knocked out stands back up at the camp RESPAWN seconds later.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local combatFolder = ReplicatedStorage:WaitForChild("Combat", 10)
local combatModule = combatFolder and combatFolder:FindFirstChild("Combat")
local meleeServer = ServerScriptService:WaitForChild("MeleeServer", 10)
local npcM1 = meleeServer and meleeServer:WaitForChild("NpcM1", 10)
if not (combatModule and combatModule:IsA("ModuleScript") and npcM1 and npcM1:IsA("BindableFunction")) then
	warn("BanditBrains: the bandits need ReplicatedStorage.Combat and ServerScriptService.MeleeServer")
	return
end
local Combat = require(combatModule) :: any

local AGGRO = 45 -- studs: a player this close (and inside the leash) is attacked
local LEASH = 90 -- studs from home: further than this, they give up and go back
local REACH = 4.5 -- studs: close enough to swing
local STRING_PAUSE = 1.0 -- seconds they back off after a full string
local THINK = 0.1 -- seconds between decisions
local BLOCK_CHANCE = 0.25 -- of guarding against a hit they see coming
local PARRY_CHANCE = 0.12 -- of parrying it instead
local REGEN = 12 -- health a second, back home with no one to fight
local RESPAWN = 10

type Brain = { model: Model, home: Vector3, pauseUntil: number, wanderAt: number, guardToken: number }
local brains: { [Model]: Brain } = {}

local function now(): number
	return Combat.now()
end

local function parts(model: Model): (Humanoid?, BasePart?)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zero
end

local function face(root: BasePart, point: Vector3)
	local dir = flat(point - root.Position)
	if dir ~= Vector3.zero then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	end
end

-- the nearest living player within AGGRO of the bandit and inside the leash
local function target(brain: Brain, root: BasePart): (Model?, BasePart?)
	local best, bestRoot, bestDistance = nil, nil, AGGRO
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			local humanoid, theirs = parts(character)
			if humanoid and theirs then
				local distance = (theirs.Position - root.Position).Magnitude
				if distance <= bestDistance and (theirs.Position - brain.home).Magnitude <= LEASH then
					best, bestRoot, bestDistance = character, theirs, distance
				end
			end
		end
	end
	return best, bestRoot
end

local function think(brain: Brain)
	local model = brain.model
	local humanoid, root = parts(model)
	if not (humanoid and root) or Combat.isStunned(model) then
		return
	end
	local t = now()
	local enemy, enemyRoot = target(brain, root)
	if not (enemy and enemyRoot) then
		-- nobody to fight: home, a slow wander round the fire, and patched up
		local away = (root.Position - brain.home)
		if Vector3.new(away.X, 0, away.Z).Magnitude > 6 then
			humanoid:MoveTo(brain.home)
		elseif t >= brain.wanderAt then
			brain.wanderAt = t + 4 + math.random() * 4
			local a = math.random() * math.pi * 2
			humanoid:MoveTo(brain.home + Vector3.new(math.cos(a), 0, math.sin(a)) * (2 + math.random() * 4))
		end
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + REGEN * THINK)
		return
	end
	local to = enemyRoot.Position - root.Position
	local distance = Vector3.new(to.X, 0, to.Z).Magnitude
	if distance > REACH then
		-- run them down (to just short of them)
		humanoid:MoveTo(enemyRoot.Position - flat(to) * (REACH - 1.5))
		return
	end
	humanoid:MoveTo(root.Position) -- stand and fight
	if Combat.isBlocking(model) or t < brain.pauseUntil then
		return
	end
	face(root, enemyRoot.Position)
	local thrown = npcM1:Invoke(model)
	if thrown == 5 then
		brain.pauseUntil = t + STRING_PAUSE -- a beat after the finisher
	end
end

-- a player's attack on its way at a bandit: sometimes it guards, or parries
Combat.Announced.Event:Connect(function(attacker: Instance, hitAt: number)
	if not (attacker:IsA("Model") and Players:GetPlayerFromCharacter(attacker)) then
		return
	end
	local from = attacker:FindFirstChild("HumanoidRootPart")
	if not (from and from:IsA("BasePart")) then
		return
	end
	for model, brain in brains do
		local _, root = parts(model)
		if
			root
			and (root.Position - from.Position).Magnitude < 9
			and not Combat.isStunned(model)
			and not Combat.isBusy(model)
		then
			local roll = math.random()
			local parry = roll < PARRY_CHANCE
			if parry or roll < PARRY_CHANCE + BLOCK_CHANCE then
				brain.guardToken += 1
				local token = brain.guardToken
				local lead = if parry then hitAt - now() - 0.1 else 0
				task.delay(math.max(lead, 0), function()
					if brain.guardToken ~= token or Combat.isStunned(model) or not parts(model) then
						return
					end
					face(root, from.Position)
					Combat.setBlocking(model, true)
					if parry then
						Combat.openParry(model)
					end
					task.delay(hitAt - now() + 0.35, function()
						if brain.guardToken == token and model.Parent then
							Combat.setBlocking(model, false)
						end
					end)
				end)
			end
		end
	end
end)

--------------------------------------------------------------------------- hooking them up

local container = script.Parent

local function start(model: Model, original: Model)
	local _, root = parts(model)
	if not root then
		return
	end
	local brain: Brain = { model = model, home = root.Position, pauseUntil = 0, wanderAt = 0, guardToken = 0 }
	brains[model] = brain
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		brains[model] = nil
		task.delay(RESPAWN, function()
			local fresh = original:Clone()
			model:Destroy()
			fresh.Parent = container
			start(fresh, original)
		end)
	end)
	task.spawn(function()
		while brains[model] == brain and model.Parent do
			think(brain)
			task.wait(THINK)
		end
	end)
end

for _, child in container:GetChildren() do
	if child:IsA("Model") and child.Name == "Bandit" then
		start(child, child:Clone())
	end
end
