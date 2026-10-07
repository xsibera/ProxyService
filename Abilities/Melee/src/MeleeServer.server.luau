--!strict
--[[
	MeleeServer (ServerScriptService): runs the M1 string for every player.

	The server owns the string: which hit is next, when it may be thrown, the hitbox, the damage and
	the stun (through ReplicatedStorage.Combat). Clients only ask and draw.

	Client -> server (Melee.Remote:FireServer):  "M1"
	Server -> clients (FireAllClients):
		"M1", attacker, index, at                    hit number index (1..5) thrown at server time at
		"Hit", attacker, victim, index, position, outcome
		"Stop", attacker                             cut short (stunned, died)
	Server -> one client: "Denied", count            not now; count = the hits the server has in the string

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

local SLACK = 0.12 -- seconds of lag allowed either way on the string's timing

local function now(): number
	return workspace:GetServerTimeNow()
end

--------------------------------------------------------------------------- state

type State = {
	count: number, -- hits thrown in the current string (0: none)
	lastAt: number, -- server time the last one was thrown
	token: number, -- bumped to cancel a hit in flight
	walkSpeed: number?, -- the walk speed to put back when the swinging stops
}
local states: { [Player]: State } = {}

local function stateOf(player: Player): State
	local s = states[player]
	if not s then
		s = { count = 0, lastAt = -math.huge, token = 0, walkSpeed = nil }
		states[player] = s
	end
	return s
end

local function parts(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return character, humanoid, root
	end
	return nil, nil, nil
end

local function restoreWalk(player: Player, s: State)
	local _, humanoid = parts(player)
	if s.walkSpeed and humanoid then
		humanoid.WalkSpeed = s.walkSpeed
	end
	s.walkSpeed = nil
end

local function playerOfModel(model: Instance): Player?
	for player in states do
		if player.Character == model then
			return player
		end
	end
	return if model:IsA("Model") then Players:GetPlayerFromCharacter(model) else nil
end

-- stunned (hit, parried, guard broken) or died: the swing in flight never lands and the string ends
local function interrupt(player: Player)
	local s = states[player]
	if not s then
		return
	end
	s.token += 1
	s.count = 0
	restoreWalk(player, s)
	Remote:FireAllClients("Stop", player)
end

Combat.Interrupted.Event:Connect(function(model: Instance)
	local player = playerOfModel(model)
	if player and states[player] then
		interrupt(player) -- before Combat slows them for the stun, so the right walk speed is kept
	end
end)

--------------------------------------------------------------------------- hitting

local function canHit(attacker: Player, model: Model): boolean
	local victim = Players:GetPlayerFromCharacter(model)
	if victim then
		if not Config.HitPlayers or victim == attacker then
			return false
		end
		if Config.TeamCheck and not attacker.Neutral and not victim.Neutral and attacker.Team == victim.Team then
			return false
		end
	end
	return true
end

local function victimsIn(attacker: Player, character: Model, box: CFrame, size: Vector3): { Model }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local out: { Model } = {}
	local seen: { [Model]: boolean } = {}
	for _, part in workspace:GetPartBoundsInBox(box, size, params) do
		local model = part:FindFirstAncestorOfClass("Model")
		while model and not model:FindFirstChildOfClass("Humanoid") do
			model = model:FindFirstAncestorOfClass("Model")
		end
		if model and not seen[model] and model ~= character then
			seen[model] = true
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and canHit(attacker, model) then
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

local function land(player: Player, index: number)
	local character, _, root = parts(player)
	if not (character and root) then
		return
	end
	local hit = Config.Hits[index]
	local frame = root.CFrame
	local size: Vector3 = Config.Hitbox
	local look = flat(frame.LookVector)
	for _, victim in victimsIn(player, character, frame * CFrame.new(0, 0, -size.Z / 2), size) do
		local push = if hit.Knockback
			then look * hit.Knockback + Vector3.new(0, hit.Lift or 0, 0)
			else look * Config.Push
		local outcome = Combat.resolve(character, victim, {
			Damage = hit.Damage,
			Ability = "M1",
			Knockback = push,
			Stun = hit.Stun,
			StunKind = "Hit",
			From = frame.Position,
		})
		Remote:FireAllClients("Hit", player, victim, index, rootPosition(victim), outcome)
		if outcome == "Hit" or outcome == "Blocked" then
			OnHit:Fire(player, victim, index, hit.Damage, outcome)
		end
	end
end

--------------------------------------------------------------------------- the string

-- busy with something that isn't this string (charging Jajanken, mid-Killua-ability)
local function busyElsewhere(character: Model): boolean
	local busy = character:GetAttribute("BusyUntil")
	return typeof(busy) == "number" and busy > now() + 0.02 and busy ~= character:GetAttribute("MeleeUntil")
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

local function m1(player: Player, s: State)
	local character, humanoid = parts(player)
	if not (character and humanoid) then
		return
	end
	if Combat.isStunned(character) or Combat.isBlocking(character) or busyElsewhere(character) then
		Remote:FireClient(player, "Denied", s.count)
		return
	end
	local t = now()
	local index = nextHit(s, t)
	if not index then
		Remote:FireClient(player, "Denied", s.count)
		return
	end
	local hit = Config.Hits[index]
	s.count = index
	s.lastAt = t
	s.token += 1
	local token = s.token
	-- committed until the next hit can be thrown: no blocking, no abilities mid-swing
	local busyFor = hit.Next or Config.FinisherRecovery
	Combat.setBusy(character, busyFor)
	character:SetAttribute("MeleeUntil", character:GetAttribute("BusyUntil"))
	if s.walkSpeed == nil then
		s.walkSpeed = humanoid.WalkSpeed
	end
	humanoid.WalkSpeed = math.min(s.walkSpeed :: number, Config.AttackWalkSpeed)
	Combat.announce(character, t + hit.HitDelay, "M1")
	Remote:FireAllClients("M1", player, index, t)
	task.delay(hit.HitDelay, function()
		if s.token == token then
			land(player, index)
		end
	end)
	task.delay(busyFor + 0.2, function()
		if s.token == token then
			restoreWalk(player, s) -- they stopped swinging
		end
	end)
end

Remote.OnServerEvent:Connect(function(player: Player, action: any)
	if action == "M1" then
		m1(player, stateOf(player))
	end
end)

--------------------------------------------------------------------------- players

local function onCharacter(player: Player, character: Model)
	local s = stateOf(player)
	s.token += 1
	s.count = 0
	s.walkSpeed = nil
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			interrupt(player)
		end)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
Players.PlayerRemoving:Connect(function(player: Player)
	states[player] = nil
end)
