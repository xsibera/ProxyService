--!strict
--[[
	BrawlerServer (ServerScriptService): runs the Brawler's moves for every player.

	The server owns timing, cooldowns, hit boxes, the grabs and the hits; clients only ask and draw.
	Every hit goes through ReplicatedStorage.Combat (block, parry, guard, stun) when the place has it,
	and is plain damage and knockback when it doesn't. With a Loadout in the place, only equipped
	moves can be used.

	A grab that connects anchors both of them: the grabber where he stands, the victim at the start of
	the throw's path (Brawler.GrabPaths, in the grabber's space). Every client then carries the victim
	along it; the server only lets them go again at the end (or at once if the grabber is cut short).

	Client -> server (Brawler.Remote:FireServer):
		"Cast", ability, aim            any of Config.Abilities (aim: the camera's look)
	Server -> clients (FireAllClients):
		"Strike", caster, ability, hitAt             a strike (or the slam, or a grab's reach) is coming
		"Grabbed", caster, victim, ability, origin, startAt   the grab connected: the throw starts at startAt
		                                             (server time); origin is his HumanoidRootPart, where
		                                             the path is measured from
		"Whiff", caster, ability                     the grab closed on nothing
		"Released", caster, victim, ability, cframe, early   the victim let go at `cframe` (early: cut short)
		"Hit", caster, victim, ability, position, outcome, push
		"Stop", caster                               cut short (stunned, died)
	Server -> one client: "Denied", ability, secondsLeft

	Other server scripts can listen for hits:
		ServerScriptService.BrawlerServer.OnHit.Event:Connect(function(attacker, victim, ability, damage, outcome) end)
]]

if not script:IsDescendantOf(game:GetService("ServerScriptService")) then
	return -- still in the package's folders: it only runs from ServerScriptService
end

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Brawler = ReplicatedStorage:WaitForChild("Brawler")
local Config = require(Brawler:WaitForChild("Config")) :: any
local GrabPaths = require(Brawler:WaitForChild("GrabPaths")) :: any
local Remote = Brawler:WaitForChild("Remote") :: RemoteEvent

local function optional(folderName: string, moduleName: string): any
	local folder = ReplicatedStorage:FindFirstChild(folderName)
	local module = folder and folder:FindFirstChild(moduleName)
	return if module and module:IsA("ModuleScript") then require(module) :: any else nil
end
local Combat = optional("Combat", "Combat")
local Loadout = optional("Loadout", "Loadout")

local OnHit = Instance.new("BindableEvent")
OnHit.Name = "OnHit"
OnHit.Parent = script

local function now(): number
	return workspace:GetServerTimeNow()
end

--------------------------------------------------------------------------- state

type Hold = {
	attacker: Player,
	victim: Model,
	ability: string,
	path: any,
	origin: CFrame,
	startAt: number,
	token: number,
	done: boolean,
}
type State = {
	token: number, -- bumped to cancel whatever is in flight
	busyUntil: number,
	ready: { [string]: number },
	walkSpeed: number?, -- his walk speed before a move slowed him
	hold: Hold?,
}
local states: { [Player]: State } = {}
local held: { [Model]: Hold } = {} -- who is being held, by whom

local function stateOf(player: Player): State
	local s = states[player]
	if not s then
		s = { token = 0, busyUntil = 0, ready = {}, walkSpeed = nil, hold = nil }
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

local function rootOf(model: Instance): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function playerOfModel(model: Instance): Player?
	for player in states do
		if player.Character == model then
			return player
		end
	end
	return if model:IsA("Model") then Players:GetPlayerFromCharacter(model) else nil
end

local function startCooldown(s: State, ability: string)
	local t = now()
	s.ready[ability] = t + Config[ability].Cooldown
	s.ready.All = t + Config.SharedCooldown
end

-- slowed while a strike plays out, back to his own speed after (unless something else changed it)
local function slow(s: State, humanoid: Humanoid, seconds: number, token: number)
	if s.walkSpeed == nil then
		s.walkSpeed = humanoid.WalkSpeed
	end
	humanoid.WalkSpeed = math.min(s.walkSpeed :: number, Config.MoveWalkSpeed)
	task.delay(seconds, function()
		if s.token == token and s.walkSpeed ~= nil then
			if humanoid.WalkSpeed == math.min(s.walkSpeed :: number, Config.MoveWalkSpeed) then
				humanoid.WalkSpeed = s.walkSpeed :: number
			end
			s.walkSpeed = nil
		end
	end)
end

local function restoreSpeed(s: State, humanoid: Humanoid?)
	if s.walkSpeed ~= nil and humanoid then
		humanoid.WalkSpeed = s.walkSpeed :: number
	end
	s.walkSpeed = nil
end

--------------------------------------------------------------------------- grab paths

-- the victim's HumanoidRootPart t seconds into a throw, in the grabber's space
local function pathAt(path: any, t: number): CFrame
	local frames = path.Frames
	local x = math.clamp(t / path.Step, 0, #frames - 1)
	local i = math.floor(x)
	local a, b = frames[i + 1], frames[math.min(i + 2, #frames)]
	local ca, cb = CFrame.new(table.unpack(a)), CFrame.new(table.unpack(b))
	return ca:Lerp(cb, x - i)
end

-- stood upright where a CFrame is, facing the flat of its look
local function upright(cframe: CFrame, floorY: number): CFrame
	local look = cframe.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.1 then
		local up = cframe.UpVector
		flatLook = Vector3.new(-up.X, 0, -up.Z)
	end
	if flatLook.Magnitude < 0.1 then
		flatLook = Vector3.new(0, 0, -1)
	end
	local position = Vector3.new(cframe.X, math.max(cframe.Y, floorY), cframe.Z)
	return CFrame.lookAt(position, position + flatLook.Unit)
end

-- let the victim go: placed upright where the path has them, unanchored (and the grabber freed, if
-- he was cut short)
local function release(hold: Hold, early: boolean)
	if hold.done then
		return
	end
	hold.done = true
	if held[hold.victim] == hold then
		held[hold.victim] = nil
	end
	local s = states[hold.attacker]
	if s and s.hold == hold then
		s.hold = nil
	end
	local victimRoot = rootOf(hold.victim)
	local where = hold.origin
	if victimRoot then
		local t = math.min(now() - hold.startAt, hold.path.Release)
		where = upright(hold.origin * pathAt(hold.path, t), hold.origin.Y)
		victimRoot.Anchored = false
		victimRoot.AssemblyLinearVelocity = Vector3.zero
		hold.victim:PivotTo(where)
	end
	local character = hold.attacker.Character
	local root = character and rootOf(character)
	if root and early then
		root.Anchored = false -- (let go on time, he stays put until his clip ends: runThrow frees him)
	end
	if early and Combat and hold.victim:GetAttribute("StunKind") == "Grabbed" then
		Combat.stun(hold.victim, 0.3, "Hit") -- dropped: a moment to find their feet
	end
	Remote:FireAllClients("Released", hold.attacker, hold.victim, hold.ability, where, early)
end

--------------------------------------------------------------------------- interrupts

-- cancel anything in flight (a stun, a death); tell everyone. A held victim is dropped.
local function interrupt(player: Player)
	local s = states[player]
	if not s then
		return
	end
	s.token += 1
	s.busyUntil = 0
	local _, humanoid = parts(player)
	restoreSpeed(s, humanoid)
	if s.hold then
		release(s.hold, true)
	end
	Remote:FireAllClients("Stop", player)
end

if Combat then
	Combat.Interrupted.Event:Connect(function(model: Instance)
		local player = playerOfModel(model)
		if player and states[player] then
			interrupt(player)
		end
	end)
end

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

-- the living Humanoid models (other than the caster) among `found`
local function victimsAmong(attacker: Player, found: { BasePart }): { Model }
	local out: { Model } = {}
	local seen: { [Model]: boolean } = {}
	for _, part in found do
		local model = part:FindFirstAncestorOfClass("Model")
		while model and not model:FindFirstChildOfClass("Humanoid") do
			model = model:FindFirstAncestorOfClass("Model")
		end
		if model and not seen[model] and model ~= attacker.Character then
			seen[model] = true
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and canHit(attacker, model) then
				table.insert(out, model)
			end
		end
	end
	return out
end

local function overlap(character: Model): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	return params
end

local function rootPosition(model: Model): Vector3
	local root = rootOf(model)
	return if root then root.Position else model:GetPivot().Position
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zero
end

local function push(model: Model, velocity: Vector3)
	local root = rootOf(model)
	if not root or velocity.Magnitude < 1 then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "BrawlerKnockback"
	attachment.Parent = root
	local force = Instance.new("LinearVelocity")
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.MaxForce = 1e6
	force.VectorVelocity = velocity
	force.Parent = attachment
	Debris:AddItem(attachment, Config.KnockbackTime)
end

-- one hit on one victim: through Combat when the place has it
local function hit(player: Player, victim: Model, ability: string, info: any): string
	local character = player.Character :: Model
	local outcome = "Hit"
	if Combat then
		outcome = Combat.resolve(character, victim, info)
	else
		local humanoid = victim:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:TakeDamage(info.Damage)
		end
		if info.Knockback then
			push(victim, info.Knockback)
		end
	end
	local pushed = if info.Knockback and info.Knockback.Magnitude > 1e-3 then info.Knockback.Unit else Vector3.zero
	Remote:FireAllClients("Hit", player, victim, ability, rootPosition(victim), outcome, pushed)
	if (outcome == "Hit" or outcome == "Blocked") and info.Damage > 0 then
		OnHit:Fire(player, victim, ability, info.Damage, outcome)
	end
	return outcome
end

-- everyone in the box in front of him: Box (width, height, depth), its near face Ahead studs out
local function inFront(player: Player, character: Model, frame: CFrame, box: Vector3, ahead: number): { Model }
	local center = frame * CFrame.new(0, 0, -(ahead + box.Z / 2))
	return victimsAmong(player, workspace:GetPartBoundsInBox(center, box, overlap(character)))
end

--------------------------------------------------------------------------- casting

local function busy(s: State, character: Model, seconds: number)
	s.busyUntil = now() + seconds
	if Combat then
		Combat.setBusy(character, seconds)
	end
end

local function deny(player: Player, ability: string, left: number)
	Remote:FireClient(player, "Denied", ability, left)
end

-- can `player` start `ability` now? (cooldowns, busy, stun, block, loadout, holding someone)
local function ready(player: Player, s: State, ability: string): boolean
	local character = parts(player)
	if not character then
		return false
	end
	if Loadout and not Loadout.has(player, ability) then
		return false
	end
	local t = now()
	if s.hold or held[character] or (Combat and not Combat.canAct(character)) or t < s.busyUntil then
		deny(player, ability, 0)
		return false
	end
	local wait = math.max(s.ready[ability] or 0, s.ready.All or 0) - t
	if wait > 0 then
		deny(player, ability, wait)
		return false
	end
	return true
end

-- the way he faces for a move: the camera's look (flattened) when he turns to it, else his facing
local function facing(root: BasePart, aim: any): CFrame
	local look = flat(root.CFrame.LookVector)
	if
		Config.TurnToCamera
		and typeof(aim) == "Vector3"
		and aim.Magnitude >= 0.5
		and aim.Magnitude < math.huge
		and flat(aim) ~= Vector3.zero
	then
		look = flat(aim)
	end
	if look == Vector3.zero then
		look = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(root.Position, root.Position + look)
end

local function strike(player: Player, s: State, ability: string, aim: any)
	local settings = Config[ability]
	local character, humanoid, root = parts(player)
	if not (character and humanoid and root) then
		return
	end
	busy(s, character, settings.Recovery)
	startCooldown(s, ability)
	local token = s.token
	slow(s, humanoid, settings.Recovery, token)
	local hitAt = now() + settings.HitDelay
	local frame = facing(root, aim)
	if Combat then
		Combat.announce(character, hitAt, ability)
	end
	Remote:FireAllClients("Strike", player, ability, hitAt)
	task.delay(settings.HitDelay, function()
		if s.token ~= token or not parts(player) then
			return
		end
		-- measured from where he is now (the lunge carried him), the way he faced when he threw it
		frame = CFrame.lookAt(root.Position, root.Position + frame.LookVector)
		local victims: { Model }
		if settings.Radius then
			local center = root.Position + frame.LookVector * (settings.Ahead or 0)
			victims = {}
			local found = workspace:GetPartBoundsInRadius(center, settings.Radius + 2, overlap(character))
			for _, victim in victimsAmong(player, found) do
				local offset = rootPosition(victim) - center
				if Vector3.new(offset.X, 0, offset.Z).Magnitude <= settings.Radius and math.abs(offset.Y) <= 7 then
					table.insert(victims, victim)
				end
			end
		else
			victims = inFront(player, character, frame, settings.Box, settings.Ahead or 0)
		end
		for _, victim in victims do
			local away = flat(rootPosition(victim) - root.Position)
			if away == Vector3.zero then
				away = frame.LookVector
			end
			local direction = if settings.Sideways then -frame.RightVector else away
			hit(player, victim, ability, {
				Damage = settings.Damage,
				Ability = ability,
				Knockback = direction * settings.Knockback + Vector3.new(0, settings.Lift or 0, 0),
				Stun = settings.Stun,
				StunKind = settings.StunKind or "Hit",
				GuardDamage = settings.GuardDamage,
				GuardBreak = settings.GuardBreak,
				FromAbove = settings.FromAbove,
				Parryable = if settings.FromAbove then false else nil,
				From = root.Position,
			})
		end
	end)
end

-- a held victim's throw: the slam (or the hurl) and the release, on the path's clock
local function runThrow(hold: Hold, s: State)
	local settings = Config[hold.ability]
	local path = hold.path
	local token = hold.token
	local function alive(): boolean
		return not hold.done and s.token == token and parts(hold.attacker) ~= nil
	end
	local slamAt = hold.startAt + path.Hit
	local releaseAt = hold.startAt + path.Release
	local thrown = settings.Knockback ~= nil -- a throw lets go first, then the hurl is the hit
	task.delay(math.max(slamAt - now(), 0), function()
		if not alive() or thrown then
			return
		end
		local stunFor = (path.Release - path.Hit) + Config.Grab.GetUp
		hit(hold.attacker, hold.victim, hold.ability, {
			Damage = settings.Damage,
			Ability = hold.ability,
			Stun = stunFor,
			StunKind = "Knockdown",
			Blockable = false,
			Parryable = false,
			Counterable = false,
			From = hold.origin.Position,
		})
	end)
	task.delay(math.max(releaseAt - now(), 0), function()
		if not alive() then
			return
		end
		release(hold, false)
		if thrown then
			local away = flat(hold.origin:VectorToWorldSpace(path.Toss or Vector3.new(-1, 0, -0.4)))
			hit(hold.attacker, hold.victim, hold.ability, {
				Damage = settings.Damage,
				Ability = hold.ability,
				Knockback = away * settings.Knockback + Vector3.new(0, settings.Lift, 0),
				Stun = settings.Stun,
				StunKind = settings.StunKind,
				Blockable = false,
				Parryable = false,
				Counterable = false,
				From = hold.origin.Position,
			})
		end
	end)
	task.delay(math.max(hold.startAt + path.Length - now(), 0), function()
		local character = hold.attacker.Character
		local root = character and rootOf(character)
		if root and s.hold == nil and s.token == token then
			root.Anchored = false
		end
	end)
end

local function grab(player: Player, s: State, ability: string, aim: any)
	local settings = Config.Grab
	local character, humanoid, root = parts(player)
	if not (character and humanoid and root) then
		return
	end
	busy(s, character, settings.WhiffRecovery)
	startCooldown(s, ability)
	local token = s.token
	slow(s, humanoid, settings.WhiffRecovery, token)
	local frame = facing(root, aim)
	local grabAt = now() + settings.At
	if Combat then
		Combat.announce(character, grabAt, ability)
	end
	Remote:FireAllClients("Strike", player, ability, grabAt)
	task.delay(settings.At, function()
		if s.token ~= token or not parts(player) then
			return
		end
		frame = CFrame.lookAt(root.Position, root.Position + frame.LookVector)
		local best, bestDistance = nil, math.huge
		for _, model in inFront(player, character, frame, settings.Box, settings.Ahead) do
			local theirRoot = rootOf(model)
			local distance = (rootPosition(model) - root.Position).Magnitude
			if theirRoot and not theirRoot.Anchored and not held[model] and distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
		local path = GrabPaths[Config[ability].Throw]
		local outcome = "Whiff"
		if best and path then
			outcome = hit(player, best, ability, {
				Damage = 0,
				Ability = ability,
				Stun = path.Length + settings.Lead + 0.2,
				StunKind = "Grabbed",
				Blockable = false,
				Parryable = false,
				From = root.Position,
			})
		end
		if outcome ~= "Hit" or not best or not path then
			Remote:FireAllClients("Whiff", player, ability)
			return
		end
		-- connected: both anchored, the victim placed at the start of the throw's path
		local victim = best :: Model
		local origin = CFrame.lookAt(root.Position, root.Position + frame.LookVector)
		local victimRoot = rootOf(victim) :: BasePart
		root.Anchored = true
		root.CFrame = origin
		victimRoot.Anchored = true
		victim:PivotTo(origin * pathAt(path, 0))
		local hold: Hold = {
			attacker = player,
			victim = victim,
			ability = ability,
			path = path,
			origin = origin,
			startAt = now() + settings.Lead,
			token = s.token,
			done = false,
		}
		s.hold = hold
		held[victim] = hold
		busy(s, character, settings.Lead + path.Length)
		restoreSpeed(s, humanoid)
		Remote:FireAllClients("Grabbed", player, victim, ability, origin, hold.startAt)
		runThrow(hold, s)
	end)
end

--------------------------------------------------------------------------- input

local GRABS = { GrabThrow = true, Suplex = true, Chokeslam = true }

Remote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
	local s = stateOf(player)
	if action ~= "Cast" or typeof(a) ~= "string" or Config[a] == nil or not table.find(Config.Abilities, a) then
		return
	end
	if ready(player, s, a) then
		s.token += 1
		if GRABS[a] then
			grab(player, s, a, b)
		else
			strike(player, s, a, b)
		end
	end
end)

-- a held victim who dies (or is removed) is let go
local function watchVictims()
	for victim, hold in held do
		local humanoid = victim:FindFirstChildOfClass("Humanoid")
		if not victim.Parent or not humanoid or humanoid.Health <= 0 then
			release(hold, true)
		end
	end
end
game:GetService("RunService").Heartbeat:Connect(watchVictims)

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			interrupt(player)
		end)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		local s = stateOf(player)
		if s.hold then
			release(s.hold, true)
		end
		s.token += 1
		s.busyUntil = 0
		s.walkSpeed = nil
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
	local s = states[player]
	if s and s.hold then
		release(s.hold, true)
	end
	for victim, hold in held do
		if victim == player.Character then
			release(hold, true)
		end
	end
	states[player] = nil
end)
