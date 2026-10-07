--!strict
--[[
	KilluaServer (ServerScriptService): runs Killua's lightning for every player.

	The server owns timing, cooldowns, targets and hits; clients only ask and draw. Every hit goes
	through ReplicatedStorage.Combat (block, parry, guard, stun, counters) when the place has it, and
	is plain damage and knockback when it doesn't. With a Loadout in the place, only equipped
	abilities can be used.

	Client -> server (Killua.Remote:FireServer):
		"Cast", ability, aim         LightningPalm | Thunderbolt | Whirlwind (aim: the camera's look)
		"Dash", index, destination   Lightning Dash number index (1..3), to where the client went
	Server -> clients (FireAllClients):
		"Palm", caster, hitAt                                   the palm is coming (hits at server time hitAt)
		"Thunderbolt", caster, target, strikeAt                 the leap; the bolt lands on target at strikeAt
		"Stance", caster, untilTime / "StanceEnd", caster, evaded
		"Counter", caster, attacker, from, to, startAt          the counter: from -> to (CFrames), flurry from startAt
		"Dash", caster, index, from, to, at                     a dash (Vector3s)
		"Hit", caster, victim, ability, position, outcome, stunKind
		"Stop", caster                                          cut short (stunned, died)
	Server -> one client: "Denied", ability, secondsLeft / "DashDenied", index, backTo

	Other server scripts can listen for hits:
		ServerScriptService.KilluaServer.OnHit.Event:Connect(function(attacker, victim, ability, damage, outcome) end)
]]

if not script:IsDescendantOf(game:GetService("ServerScriptService")) then
	return -- still in the package's folders: it only runs from ServerScriptService
end

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Killua = ReplicatedStorage:WaitForChild("Killua")
local Config = require(Killua:WaitForChild("Config")) :: any
local Remote = Killua:WaitForChild("Remote") :: RemoteEvent

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

type Chain = { count: number, lastAt: number, windowUntil: number }
type State = {
	token: number, -- bumped to cancel whatever is in flight
	busyUntil: number,
	ready: { [string]: number },
	chain: Chain?,
	stance: { untilTime: number, token: number }?,
}
local states: { [Player]: State } = {}

local function stateOf(player: Player): State
	local s = states[player]
	if not s then
		s = { token = 0, busyUntil = 0, ready = {}, chain = nil, stance = nil }
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

-- cancel anything in flight (a stun, a death); tell everyone. A dash chain cut short still costs its cooldown.
local function interrupt(player: Player)
	local s = states[player]
	if not s then
		return
	end
	s.token += 1
	if s.chain then
		s.chain = nil
		startCooldown(s, "LightningDash")
	end
	if s.stance then
		s.stance = nil
		local character = player.Character
		if character and Combat then
			Combat.setCounter(character, 0)
		end
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
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else model:GetPivot().Position
end

local function push(model: Model, velocity: Vector3)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or velocity.Magnitude < 1 then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "KilluaKnockback"
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
	Remote:FireAllClients("Hit", player, victim, ability, rootPosition(victim), outcome, info.StunKind or "Hit")
	if outcome == "Hit" or outcome == "Blocked" then
		OnHit:Fire(player, victim, ability, info.Damage, outcome)
	end
	return outcome
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

-- can `player` start `ability` now? (cooldowns, busy, stun, block, loadout)
local function ready(player: Player, s: State, ability: string): boolean
	local character = parts(player)
	if not character then
		return false
	end
	if Loadout and not Loadout.has(player, ability) then
		return false
	end
	local t = now()
	if Combat and not Combat.canAct(character) then
		deny(player, ability, 0)
		return false
	end
	if t < s.busyUntil then
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

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zero
end

-- the horizontal direction to act along: the camera's look when it's within maxAngle of the facing
local function aimDirection(root: BasePart, aim: any, maxAngle: number): Vector3
	local facing = flat(root.CFrame.LookVector)
	if facing == Vector3.zero then
		facing = Vector3.new(0, 0, -1)
	end
	if typeof(aim) ~= "Vector3" or not (aim.Magnitude >= 0.5 and aim.Magnitude < math.huge) then
		return facing
	end
	local d = flat(aim)
	if d == Vector3.zero or d:Dot(facing) < math.cos(math.rad(maxAngle)) then
		return facing
	end
	return d
end

local function lightningPalm(player: Player, s: State)
	local settings = Config.LightningPalm
	local character, _, root = parts(player)
	if not (character and root) then
		return
	end
	busy(s, character, settings.Recovery)
	startCooldown(s, "LightningPalm")
	local hitAt = now() + settings.HitDelay
	local token = s.token
	if Combat then
		Combat.announce(character, hitAt, "LightningPalm")
	end
	Remote:FireAllClients("Palm", player, hitAt)
	task.delay(settings.HitDelay, function()
		if s.token ~= token or not parts(player) then
			return
		end
		local frame = root.CFrame
		local size: Vector3 = settings.Hitbox
		local box = frame * CFrame.new(0, 0, -size.Z / 2)
		local found = workspace:GetPartBoundsInBox(box, size, overlap(character))
		for _, victim in victimsAmong(player, found) do
			hit(player, victim, "LightningPalm", {
				Damage = settings.Damage,
				Ability = "LightningPalm",
				Knockback = flat(frame.LookVector) * settings.Knockback + Vector3.new(0, 8, 0),
				Stun = settings.Paralyze,
				StunKind = "Shock",
				GuardDamage = settings.GuardDamage,
				From = frame.Position,
			})
		end
	end)
end

-- the floor under a point, looking through anyone standing on it
local function groundBelow(point: Vector3, exclude: { Instance }): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip = table.clone(exclude)
	for _ = 1, 6 do
		params.FilterDescendantsInstances = skip
		local result = workspace:Raycast(point, Vector3.new(0, -40, 0), params)
		if not result then
			return nil
		end
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			table.insert(skip, model)
		else
			return result.Position
		end
	end
	return nil
end

-- where Narukami lands: on someone near the aim line, or Range x 0.75 out along it; dropped onto the floor
local function strikePoint(player: Player, character: Model, root: BasePart, aim: any): Vector3
	local settings = Config.Thunderbolt
	local dir = aimDirection(root, aim, if settings.AimWithCamera then settings.MaxAimAngle else 0)
	local from = root.Position
	local target = from + dir * settings.Range * 0.75
	if settings.LockOn then
		local best, bestAngle = nil, math.rad(25)
		local found = workspace:GetPartBoundsInRadius(from, settings.Range + settings.Radius, overlap(character))
		for _, model in victimsAmong(player, found) do
			local to = rootPosition(model) - from
			local horizontal = flat(to)
			local distance = Vector3.new(to.X, 0, to.Z).Magnitude
			if distance <= settings.Range and distance >= settings.MinRange * 0.5 then
				local angle = math.acos(math.clamp(horizontal:Dot(dir), -1, 1))
				if angle < bestAngle then
					best, bestAngle = rootPosition(model), angle
				end
			end
		end
		if best then
			target = best
		end
	end
	local offset = target - from
	local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
	if distance < settings.MinRange then
		target = from + dir * settings.MinRange
	end
	local ground = groundBelow(target + Vector3.new(0, 12, 0), { character })
	return ground or Vector3.new(target.X, from.Y - 3, target.Z)
end

local function thunderbolt(player: Player, s: State, aim: any)
	local settings = Config.Thunderbolt
	local character, _, root = parts(player)
	if not (character and root) then
		return
	end
	busy(s, character, settings.Recovery)
	startCooldown(s, "Thunderbolt")
	local target = strikePoint(player, character, root, aim)
	local strikeAt = now() + settings.HitDelay
	local token = s.token
	if Combat then
		Combat.announce(character, strikeAt, "Thunderbolt", target)
	end
	Remote:FireAllClients("Thunderbolt", player, target, strikeAt)
	task.delay(settings.HitDelay, function()
		if s.token ~= token or not parts(player) then
			return
		end
		local found = workspace:GetPartBoundsInRadius(target, settings.Radius + 2, overlap(character))
		for _, victim in victimsAmong(player, found) do
			local away = rootPosition(victim) - target
			local horizontal = Vector3.new(away.X, 0, away.Z)
			if horizontal.Magnitude <= settings.Radius then
				local out = if horizontal.Magnitude > 0.1 then horizontal.Unit else flat(root.CFrame.LookVector)
				hit(player, victim, "Thunderbolt", {
					Damage = settings.Damage,
					Ability = "Thunderbolt",
					Knockback = out * settings.Knockback + Vector3.new(0, settings.Lift, 0),
					Stun = settings.Paralyze,
					StunKind = "Shock",
					GuardDamage = settings.GuardDamage,
					Parryable = false,
					FromAbove = true,
					From = target + Vector3.new(0, 20, 0),
				})
			end
		end
	end)
end

local function whirlwind(player: Player, s: State)
	local settings = Config.Whirlwind
	local character = parts(player)
	if not character then
		return
	end
	busy(s, character, settings.Window + settings.WhiffRecovery)
	startCooldown(s, "Whirlwind")
	local untilTime = now() + settings.Window
	s.token += 1
	local token = s.token
	s.stance = { untilTime = untilTime, token = token }
	if Combat then
		Combat.setCounter(character, settings.Window)
	end
	Remote:FireAllClients("Stance", player, untilTime)
	task.delay(settings.Window, function()
		local stance = s.stance
		if stance and stance.token == token then
			s.stance = nil
			if Combat then
				Combat.setCounter(character, 0)
			end
			Remote:FireAllClients("StanceEnd", player, false)
		end
	end)
end

-- the stance caught a hit: vanish, reappear behind the attacker and answer
local function counter(player: Player, s: State, attacker: Instance)
	local settings = Config.Whirlwind
	local character, _, root = parts(player)
	if not (character and root) then
		return
	end
	s.stance = nil
	s.token += 1
	local token = s.token
	local attackerRoot = attacker:FindFirstChild("HumanoidRootPart")
	local close = attackerRoot
		and attackerRoot:IsA("BasePart")
		and (attackerRoot.Position - root.Position).Magnitude <= settings.CounterRange
	if not (close and attackerRoot and attackerRoot:IsA("BasePart") and attacker:IsA("Model")) then
		busy(s, character, 0.2) -- too far to reach (a projectile): only evaded
		Remote:FireAllClients("StanceEnd", player, true)
		return
	end
	local behind = attackerRoot.CFrame * CFrame.new(0, 0, settings.Behind)
	local to =
		CFrame.lookAt(behind.Position, attackerRoot.Position * Vector3.new(1, 0, 1) + Vector3.new(0, behind.Y, 0))
	local from = root.CFrame
	busy(s, character, settings.Length + 0.05)
	if Combat then
		Combat.setIntangible(character, settings.Length)
		Combat.stun(attacker, settings.Length, "Countered")
	end
	character:PivotTo(to)
	local startAt = now()
	Remote:FireAllClients("Counter", player, attacker, from, to, startAt)
	for _, step in settings.Hits do
		task.delay(step.At, function()
			if s.token ~= token or not parts(player) then
				return
			end
			local aimFrom = rootPosition(character)
			hit(player, attacker, "Whirlwind", {
				Damage = step.Damage,
				Ability = "Whirlwind",
				Stun = step.Stun,
				StunKind = step.StunKind or "Hit",
				Knockback = if step.Knockback then flat(rootPosition(attacker) - aimFrom) * step.Knockback else nil,
				Parryable = false,
				Blockable = false,
				Counterable = false,
				From = aimFrom,
			})
		end)
	end
end

if Combat then
	Combat.Countered.Event:Connect(function(victim: Instance, attacker: Instance)
		local player = playerOfModel(victim)
		local s = player and states[player]
		if player and s and s.stance and now() <= s.stance.untilTime + 0.05 then
			counter(player, s, attacker)
		end
	end)
end

--------------------------------------------------------------------------- Lightning Dash

local function endChain(s: State, chain: Chain)
	if s.chain == chain then
		s.chain = nil
		startCooldown(s, "LightningDash")
	end
end

local function pathClear(character: Model, from: Vector3, to: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { character }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	local lift = Vector3.new(0, 0.5, 0)
	return workspace:Raycast(from + lift, (to - from), params) == nil
end

local function distanceToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local t = if ab.Magnitude > 1e-6 then math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1) else 0
	return (a + ab * t - p).Magnitude
end

local function dash(player: Player, s: State, index: any, destination: any)
	local settings = Config.LightningDash
	local character, _, root = parts(player)
	if not (character and root) then
		return
	end
	if typeof(index) ~= "number" or index ~= math.floor(index) or typeof(destination) ~= "Vector3" then
		return
	end
	local t = now()
	local chain = s.chain
	if index == 1 then
		if not ready(player, s, "LightningDash") then
			return
		end
		chain = { count = 0, lastAt = -math.huge, windowUntil = math.huge }
		s.chain = chain
	elseif
		not chain
		or chain.count ~= index - 1
		or t > chain.windowUntil
		or t - chain.lastAt < settings.MinGap - 0.05
		or (Combat and (Combat.isStunned(character) or Combat.isBlocking(character)))
	then
		return
	end
	local current = chain :: Chain
	local from = root.Position
	local offset = destination - from
	local reach = settings.Distance + settings.Slack
	local valid = destination.Magnitude < math.huge
		and Vector3.new(offset.X, 0, offset.Z).Magnitude <= reach
		and math.abs(offset.Y) <= 10
		and pathClear(character, from, destination)
	if not valid then
		Remote:FireClient(player, "DashDenied", index, from)
		endChain(s, current)
		return
	end
	current.count = index
	current.lastAt = t
	current.windowUntil = t + settings.ChainWindow
	busy(s, character, settings.Recovery)
	if Combat then
		Combat.setIntangible(character, settings.Intangible)
	end
	Remote:FireAllClients("Dash", player, index, from, destination, t)
	if index >= settings.Dashes then
		endChain(s, current)
	else
		task.delay(settings.ChainWindow + 0.05, function()
			if s.chain == current and current.count == index then
				endChain(s, current)
			end
		end)
	end
	local strike = settings.Strikes[index]
	local token = s.token
	if Combat then
		Combat.announce(character, t + strike.Delay, "LightningDash", destination)
	end
	task.delay(strike.Delay, function()
		if s.token ~= token or not parts(player) then
			return
		end
		local mid = (from + destination) / 2
		local radius = (destination - from).Magnitude / 2 + settings.Width + settings.ArriveRadius
		local found = workspace:GetPartBoundsInRadius(mid, radius, overlap(character))
		local dir = flat(destination - from)
		for _, victim in victimsAmong(player, found) do
			local p = rootPosition(victim)
			local onPath = distanceToSegment(p, from, destination) <= settings.Width
			if onPath or (p - destination).Magnitude <= settings.ArriveRadius then
				local outcome = hit(player, victim, "LightningDash", {
					Damage = strike.Damage,
					Ability = "LightningDash",
					Stun = strike.Stun,
					StunKind = strike.StunKind or "Hit",
					Knockback = if strike.Knockback then dir * strike.Knockback + Vector3.new(0, 10, 0) else nil,
					GuardDamage = settings.GuardDamage,
					-- passing through: it comes from where he started (face that to block or parry it);
					-- only landing beside someone hits from where he arrives
					From = if onPath then from else destination,
				})
				if outcome == "Parried" and s.chain == current then
					endChain(s, current) -- a parry ends the chain
				end
			end
		end
	end)
end

--------------------------------------------------------------------------- input

local CASTS = {
	LightningPalm = lightningPalm,
	Thunderbolt = thunderbolt,
	Whirlwind = whirlwind,
}

Remote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
	local s = stateOf(player)
	if action == "Cast" then
		local cast = if typeof(a) == "string" then (CASTS :: any)[a] else nil
		if cast and ready(player, s, a) then
			s.token += 1
			cast(player, s, b)
		end
	elseif action == "Dash" then
		dash(player, s, a, b)
	end
end)

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
		s.token += 1
		s.busyUntil = 0
		s.chain = nil
		s.stance = nil
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
