--!strict
--[[
	MeleeServer (ServerScriptService): runs the M1 string for every player, and for NPCs.

	The server owns the string: which hit is next, when it may be thrown, the hitbox, the damage and
	the stun (through ReplicatedStorage.Combat). Clients only ask and draw.

	Client -> server (Melee.Remote:FireServer):  "M1"
	Server -> clients (FireAllClients), attacker = the attacking character (a player's or an NPC's):
		"M1", attacker, index, at                    hit number index (1..5) thrown at server time at
		"Hit", attacker, victim, index, position, outcome
		"Stop", attacker                             cut short (stunned, died)
	Server -> one client: "Denied", count            not now; count = the hits the server has in the string

	NPCs (the village's bandits) fight with it too, from the server:
		ServerScriptService.MeleeServer.NpcM1:Invoke(model) -> the hit thrown (1..5), or nil (not now)
	An NPC's hits only land on players, and deal Config.NpcDamage of a player's damage.

	Other server scripts can listen for hits:
		ServerScriptService.MeleeServer.OnHit.Event:Connect(function(attacker, victim, index, damage, outcome) end)
]]

if not script:IsDescendantOf(game:GetService("ServerScriptService")) then
	return -- still in the package's folders: it only runs from ServerScriptService
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Melee = ReplicatedStorage:WaitForChild("Melee")
local Config = require(Melee:WaitForChild("Config")) :: any
local Remote = Melee:WaitForChild("Remote") :: RemoteEvent
local Combat = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("Combat")) :: any

local OnHit = Instance.new("BindableEvent")
OnHit.Name = "OnHit"
OnHit.Parent = script
local NpcM1 = Instance.new("BindableFunction")
NpcM1.Name = "NpcM1"
NpcM1.Parent = script

local SLACK = 0.12 -- seconds of lag allowed either way on the string's timing

local function now(): number
	return workspace:GetServerTimeNow()
end

--------------------------------------------------------------------------- state, per attacking character

type State = {
	count: number, -- hits thrown in the current string (0: none)
	lastAt: number, -- server time the last one was thrown
	token: number, -- bumped to cancel a hit in flight
	walkSpeed: number?, -- the walk speed to put back when the swinging stops
}
local states: { [Model]: State } = setmetatable({}, { __mode = "k" }) :: any

local function stateOf(model: Model): State
	local s = states[model]
	if not s then
		s = { count = 0, lastAt = -math.huge, token = 0, walkSpeed = nil }
		states[model] = s
	end
	return s
end

local function alive(model: Model?): (Humanoid?, BasePart?)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

local function restoreWalk(model: Model, s: State)
	local humanoid = alive(model)
	if s.walkSpeed and humanoid then
		humanoid.WalkSpeed = s.walkSpeed
	end
	s.walkSpeed = nil
end

-- stunned (hit, parried, guard broken) or died: the swing in flight never lands and the string ends
local function interrupt(model: Model)
	local s = states[model]
	if not s then
		return
	end
	s.token += 1
	s.count = 0
	restoreWalk(model, s)
	Remote:FireAllClients("Stop", model)
end

Combat.Interrupted.Event:Connect(function(model: Instance)
	if model:IsA("Model") and states[model] then
		interrupt(model) -- before Combat slows them for the stun, so the right walk speed is kept
	end
end)

--------------------------------------------------------------------------- hitting

local function canHit(attacker: Model, model: Model): boolean
	local victim = Players:GetPlayerFromCharacter(model)
	local player = Players:GetPlayerFromCharacter(attacker)
	if not player then
		return victim ~= nil -- NPCs fight players, not each other
	end
	if victim then
		if not Config.HitPlayers or victim == player then
			return false
		end
		if Config.TeamCheck and not player.Neutral and not victim.Neutral and player.Team == victim.Team then
			return false
		end
	end
	return true
end

local function victimsIn(attacker: Model, box: CFrame, size: Vector3): { Model }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attacker }
	local out: { Model } = {}
	local seen: { [Model]: boolean } = {}
	for _, part in workspace:GetPartBoundsInBox(box, size, params) do
		local model = part:FindFirstAncestorOfClass("Model")
		while model and not model:FindFirstChildOfClass("Humanoid") do
			model = model:FindFirstAncestorOfClass("Model")
		end
		if model and not seen[model] and model ~= attacker then
			seen[model] = true
			if alive(model) and canHit(attacker, model) then
				table.insert(out, model)
			end
		end
	end
	return out
end

local function rootPosition(model: Model): Vector3
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else model:GetPivot().Position
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zero
end

local function land(attacker: Model, index: number)
	local _, root = alive(attacker)
	if not root then
		return
	end
	local hit = Config.Hits[index]
	local damage = hit.Damage * (if Players:GetPlayerFromCharacter(attacker) then 1 else Config.NpcDamage)
	local frame = root.CFrame
	local size: Vector3 = Config.Hitbox
	local look = flat(frame.LookVector)
	for _, victim in victimsIn(attacker, frame * CFrame.new(0, 0, -size.Z / 2), size) do
		local push = if hit.Knockback
			then look * hit.Knockback + Vector3.new(0, hit.Lift or 0, 0)
			else look * Config.Push
		local outcome = Combat.resolve(attacker, victim, {
			Damage = damage,
			Ability = "M1",
			Knockback = push,
			Stun = hit.Stun,
			StunKind = "Hit",
			From = frame.Position,
		})
		Remote:FireAllClients("Hit", attacker, victim, index, rootPosition(victim), outcome)
		if outcome == "Hit" or outcome == "Blocked" then
			OnHit:Fire(attacker, victim, index, damage, outcome)
		end
	end
end

--------------------------------------------------------------------------- the string

-- busy with something that isn't this string (charging Jajanken, mid-Killua-ability, rolling)
local function busyElsewhere(model: Model): boolean
	local busy = model:GetAttribute("BusyUntil")
	return typeof(busy) == "number" and busy > now() + 0.02 and busy ~= model:GetAttribute("MeleeUntil")
end

-- the hit to throw now (1..5), or nil and the time left before one can be
local function nextHit(s: State, t: number): (number?, number)
	local hits = Config.Hits
	if s.count >= #hits then
		local ready = s.lastAt + Config.FinisherCooldown
		if t < ready - SLACK then
			return nil, ready - t
		end
		return 1, 0
	end
	if s.count == 0 then
		return 1, 0
	end
	local opens = s.lastAt + hits[s.count].Next
	if t > opens + Config.ComboWindow + SLACK then
		return 1, 0 -- too late: the string starts over
	end
	if t < opens - SLACK then
		return nil, opens - t
	end
	return s.count + 1, 0
end

-- throw the next hit of `model`'s string, if it can be thrown now; returns which hit, or nil
local function m1(model: Model): number?
	local humanoid = alive(model)
	if not humanoid then
		return nil
	end
	local s = stateOf(model)
	if Combat.isStunned(model) or Combat.isBlocking(model) or busyElsewhere(model) then
		return nil
	end
	local t = now()
	local index = nextHit(s, t)
	if not index then
		return nil
	end
	local hit = Config.Hits[index]
	s.count = index
	s.lastAt = t
	s.token += 1
	local token = s.token
	-- committed until the next hit can be thrown: no blocking, no abilities mid-swing
	local busyFor = hit.Next or Config.FinisherRecovery
	Combat.setBusy(model, busyFor)
	model:SetAttribute("MeleeUntil", model:GetAttribute("BusyUntil"))
	if s.walkSpeed == nil then
		s.walkSpeed = humanoid.WalkSpeed
	end
	humanoid.WalkSpeed = math.min(s.walkSpeed :: number, Config.AttackWalkSpeed)
	Combat.announce(model, t + hit.HitDelay, "M1")
	Remote:FireAllClients("M1", model, index, t)
	task.delay(hit.HitDelay, function()
		if s.token == token then
			land(model, index)
		end
	end)
	task.delay(busyFor + 0.2, function()
		if s.token == token then
			restoreWalk(model, s) -- they stopped swinging
		end
	end)
	return index
end

Remote.OnServerEvent:Connect(function(player: Player, action: any)
	if action == "M1" then
		local character = player.Character
		if not (character and m1(character)) then
			Remote:FireClient(player, "Denied", if character and states[character] then states[character].count else 0)
		end
	end
end)

NpcM1.OnInvoke = function(model: any): number?
	if typeof(model) == "Instance" and model:IsA("Model") and not Players:GetPlayerFromCharacter(model) then
		return m1(model)
	end
	return nil
end

--------------------------------------------------------------------------- players

local function onCharacter(character: Model)
	local s = stateOf(character)
	s.count = 0
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			interrupt(character)
		end)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
