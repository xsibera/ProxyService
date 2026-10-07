--!strict
--[[
	LeorioServer (ServerScriptService): runs Leorio's warp punches for every player.

	The server owns timing, cooldowns, targets, where the warp holes open and the hits; clients only
	ask and draw. Every hit goes through ReplicatedStorage.Combat (block, parry, guard, stun) when the
	place has it, and is plain damage and knockback when it doesn't. A blow that comes out of a hole
	comes FROM the hole: blocks and parries only work facing it. With a Loadout in the place, only
	equipped abilities can be used.

	Client -> server (Leorio.Remote:FireServer):
		"Cast", ability, aim          WarpPunch | RemoteJab | WarpBarrage | PortalBurst (aim: the camera's look)
	Server -> clients (FireAllClients):
		"WarpPunch", caster, hole, punchAt, hitAt     the fist goes into the floor at punchAt (server
		                                              time) and comes out of `hole` (a CFrame, its
		                                              LookVector the punch) at hitAt
		"Jab", caster, hole, jabAt, hitAt             the same for the jab (the hole opens at once)
		"Barrage", caster, index, hole, punchAt, hitAt   one barrage punch (sent as it goes into the floor)
		"Burst", caster, center, burstAt, eruptAt, holes  the fists into the floor at burstAt; `holes`
		                                              (CFrames) open round him and the fists come up at eruptAt
		"Hit", caster, victim, ability, position, outcome, push   push: the direction it was knocked
		"Stop", caster                                cut short (stunned, died): close his holes
	Server -> one client: "Denied", ability, secondsLeft

	Other server scripts can listen for hits:
		ServerScriptService.LeorioServer.OnHit.Event:Connect(function(attacker, victim, ability, damage, outcome) end)
]]

if not script:IsDescendantOf(game:GetService("ServerScriptService")) then
	return -- still in the package's folders: it only runs from ServerScriptService
end

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Leorio = ReplicatedStorage:WaitForChild("Leorio")
local Config = require(Leorio:WaitForChild("Config")) :: any
local Remote = Leorio:WaitForChild("Remote") :: RemoteEvent

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

type State = {
	token: number, -- bumped to cancel whatever is in flight
	busyUntil: number,
	ready: { [string]: number },
}
local states: { [Player]: State } = {}

local function stateOf(player: Player): State
	local s = states[player]
	if not s then
		s = { token = 0, busyUntil = 0, ready = {} }
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

-- cancel anything in flight (a stun, a death); tell everyone, so his holes close
local function interrupt(player: Player)
	local s = states[player]
	if not s then
		return
	end
	s.token += 1
	s.busyUntil = 0
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

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zero
end

local function push(model: Model, velocity: Vector3)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or velocity.Magnitude < 1 then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "LeorioKnockback"
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

-- the horizontal direction he aims along: the camera's look (any way: the fist goes through a hole)
local function aimDirection(root: BasePart, aim: any): Vector3
	local facing = flat(root.CFrame.LookVector)
	if facing == Vector3.zero then
		facing = Vector3.new(0, 0, -1)
	end
	if
		not Config.Targeting.AimWithCamera
		or typeof(aim) ~= "Vector3"
		or not (aim.Magnitude >= 0.5 and aim.Magnitude < math.huge)
	then
		return facing
	end
	local d = flat(aim)
	return if d == Vector3.zero then facing else d
end

-- who he's punching at: the living target nearest the aim line, within range and Targeting.Angle
local function findTarget(player: Player, character: Model, root: BasePart, dir: Vector3, range: number): Model?
	local best, bestAngle, bestDistance = nil, math.rad(Config.Targeting.Angle), math.huge
	local found = workspace:GetPartBoundsInRadius(root.Position, range, overlap(character))
	for _, model in victimsAmong(player, found) do
		local to = rootPosition(model) - root.Position
		local distance = Vector3.new(to.X, 0, to.Z).Magnitude
		if distance <= range and distance > 0.5 then
			local angle = math.acos(math.clamp(flat(to):Dot(dir), -1, 1))
			if angle < bestAngle - 1e-3 or (math.abs(angle - bestAngle) <= 1e-3 and distance < bestDistance) then
				best, bestAngle, bestDistance = model, angle, distance
			end
		end
	end
	return best
end

-- a hole `distance` studs from `at`, `angle` degrees round from the line to him (+ = his right),
-- `height` up, facing `at` (raised a little: the fist goes for the head and shoulders)
local function holeBeside(at: Vector3, from: Vector3, angle: number, distance: number, height: number): CFrame
	local toHim = flat(from - at)
	if toHim == Vector3.zero then
		toHim = Vector3.new(0, 0, 1)
	end
	local right = Vector3.new(toHim.Z, 0, -toHim.X) -- his right, seen from him facing `at`
	local a = math.rad(angle)
	local dir = toHim * math.cos(a) + right * math.sin(a)
	local position = at + dir * distance + Vector3.new(0, height, 0)
	return CFrame.lookAt(position, at + Vector3.new(0, height * 0.6, 0))
end

-- a hole straight over `at`, looking down
local function holeAbove(at: Vector3, from: Vector3, height: number): CFrame
	local position = at + Vector3.new(0, height, 0)
	local toHim = flat(from - at)
	return CFrame.lookAt(position, at, if toHim ~= Vector3.zero then toHim else Vector3.zAxis)
end

-- where to aim when there's nobody: Fallback studs out along the aim, at his height
local function fallbackPoint(root: BasePart, dir: Vector3): Vector3
	return root.Position + dir * Config.Targeting.Fallback
end

-- everyone in the box in front of a hole (its LookVector), `reach` long and `width` across
local function inFrontOf(player: Player, character: Model, hole: CFrame, reach: number, width: number): { Model }
	local box = hole * CFrame.new(0, 0, -reach / 2)
	local found = workspace:GetPartBoundsInBox(box, Vector3.new(width, width, reach), overlap(character))
	return victimsAmong(player, found)
end

local function livingRoot(model: Model?): BasePart?
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if model and model.Parent and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function warpPunch(player: Player, s: State, aim: any)
	local settings = Config.WarpPunch
	local character, _, root = parts(player)
	if not (character and root) then
		return
	end
	busy(s, character, settings.Recovery)
	startCooldown(s, "WarpPunch")
	local dir = aimDirection(root, aim)
	local target = findTarget(player, character, root, dir, settings.Range)
	local at = if target then rootPosition(target) else fallbackPoint(root, dir)
	local hole = holeBeside(at, root.Position, settings.Side, settings.Distance, settings.Height)
	local t = now()
	local punchAt, hitAt = t + settings.PunchAt, t + settings.HitDelay
	local token = s.token
	if Combat then
		Combat.announce(character, hitAt, "WarpPunch", at, hole.Position)
	end
	Remote:FireAllClients("WarpPunch", player, hole, punchAt, hitAt)
	task.delay(settings.HitDelay, function()
		if s.token ~= token or not parts(player) then
			return
		end
		local out = flat(hole.LookVector)
		for _, victim in inFrontOf(player, character, hole, settings.Reach, settings.Width) do
			hit(player, victim, "WarpPunch", {
				Damage = settings.Damage,
				Ability = "WarpPunch",
				Knockback = out * settings.Knockback + Vector3.new(0, settings.Lift, 0),
				Stun = settings.Stun,
				StunKind = "Hit",
				GuardDamage = settings.GuardDamage,
				From = hole.Position,
			})
		end
	end)
end

local function remoteJab(player: Player, s: State, aim: any)
	local settings = Config.RemoteJab
	local character, _, root = parts(player)
	if not (character and root) then
		return
	end
	busy(s, character, settings.Recovery)
	startCooldown(s, "RemoteJab")
	local dir = aimDirection(root, aim)
	local target = findTarget(player, character, root, dir, settings.Range)
	local at = if target then rootPosition(target) else fallbackPoint(root, dir)
	local hole = holeBeside(at, root.Position, 180, settings.Distance, settings.Height) -- behind them
	local t = now()
	local jabAt, hitAt = t + settings.JabAt, t + settings.HitDelay
	local token = s.token
	if Combat then
		Combat.announce(character, hitAt, "RemoteJab", at, hole.Position)
	end
	Remote:FireAllClients("Jab", player, hole, jabAt, hitAt)
	task.delay(settings.HitDelay, function()
		if s.token ~= token or not parts(player) then
			return
		end
		local toward = flat(hole.LookVector)
		for _, victim in inFrontOf(player, character, hole, settings.Reach, settings.Width) do
			hit(player, victim, "RemoteJab", {
				Damage = settings.Damage,
				Ability = "RemoteJab",
				Knockback = toward * settings.Pull,
				Stun = settings.Stun,
				StunKind = "Hit",
				GuardDamage = settings.GuardDamage,
				From = hole.Position,
			})
		end
	end)
end

local function warpBarrage(player: Player, s: State, aim: any)
	local settings = Config.WarpBarrage
	local character, _, root = parts(player)
	if not (character and root) then
		return
	end
	busy(s, character, settings.Recovery)
	startCooldown(s, "WarpBarrage")
	local dir = aimDirection(root, aim)
	local target = findTarget(player, character, root, dir, settings.Range)
	local lastAt = if target then rootPosition(target) else fallbackPoint(root, dir)
	local token = s.token
	for index, step in settings.Hits do
		task.delay(step.At, function()
			if s.token ~= token or not parts(player) then
				return
			end
			-- each hole opens round wherever the target is now (a stunned target is chased down)
			local targetRoot = livingRoot(target)
			if targetRoot and (targetRoot.Position - root.Position).Magnitude <= settings.Range * 1.25 then
				lastAt = targetRoot.Position
			end
			local hole = if step.Above
				then holeAbove(lastAt, root.Position, 7)
				else holeBeside(lastAt, root.Position, step.Angle, settings.Distance, settings.Height)
			local punchAt = now()
			local hitAt = punchAt + settings.Travel
			if Combat then
				Combat.announce(character, hitAt, "WarpBarrage", lastAt, hole.Position)
			end
			Remote:FireAllClients("Barrage", player, index, hole, punchAt, hitAt)
			task.delay(settings.Travel, function()
				if s.token ~= token or not parts(player) then
					return
				end
				local reach = if step.Above then 9 else settings.Reach
				local width = if step.Above then (step.Radius or 2.8) * 2 else settings.Width
				local away = flat(lastAt - root.Position)
				for _, victim in inFrontOf(player, character, hole, reach, width) do
					hit(player, victim, "WarpBarrage", {
						Damage = step.Damage,
						Ability = "WarpBarrage",
						Knockback = if step.Knockback then away * step.Knockback else flat(hole.LookVector) * 4,
						Stun = step.Stun,
						StunKind = "Hit",
						GuardDamage = settings.GuardDamage,
						FromAbove = step.Above or nil,
						Parryable = if step.Above then false else nil,
						From = hole.Position,
					})
				end
			end)
		end)
	end
end

local function portalBurst(player: Player, s: State)
	local settings = Config.PortalBurst
	local character, _, root = parts(player)
	if not (character and root) then
		return
	end
	busy(s, character, settings.Recovery)
	startCooldown(s, "PortalBurst")
	local t = now()
	local burstAt = t + settings.HitDelay
	local eruptAt = burstAt + settings.Erupt
	local center = root.Position - Vector3.new(0, 3, 0) -- the floor under him (R6: the root is 3 up)
	local facing = flat(root.CFrame.LookVector)
	if facing == Vector3.zero then
		facing = Vector3.new(0, 0, -1)
	end
	local holes = {}
	for i = 1, settings.Holes do
		local a = (i - 1) / settings.Holes * 2 * math.pi
		local out = facing * math.cos(a) + Vector3.new(facing.Z, 0, -facing.X) * math.sin(a)
		local spot = center + out * settings.RingRadius + Vector3.new(0, 0.05, 0)
		table.insert(holes, CFrame.lookAt(spot, spot + Vector3.yAxis, out))
	end
	local token = s.token
	if Combat then
		Combat.announce(character, eruptAt, "PortalBurst", root.Position)
	end
	Remote:FireAllClients("Burst", player, center, burstAt, eruptAt, holes)
	task.delay(settings.HitDelay + settings.Erupt, function()
		if s.token ~= token or not parts(player) then
			return
		end
		local from = root.Position
		local found = workspace:GetPartBoundsInRadius(from, settings.Radius + 2, overlap(character))
		for _, victim in victimsAmong(player, found) do
			local away = rootPosition(victim) - from
			local horizontal = Vector3.new(away.X, 0, away.Z)
			if horizontal.Magnitude <= settings.Radius and math.abs(away.Y) <= 6 then
				local out = if horizontal.Magnitude > 0.1 then horizontal.Unit else facing
				hit(player, victim, "PortalBurst", {
					Damage = settings.Damage,
					Ability = "PortalBurst",
					Knockback = out * settings.Knockback + Vector3.new(0, settings.Lift, 0),
					Stun = settings.Stun,
					StunKind = "Launch",
					GuardDamage = settings.GuardDamage,
					Parryable = false,
					FromAbove = true, -- (from below: blocks work facing any way, parries never do)
					From = from,
				})
			end
		end
	end)
end

--------------------------------------------------------------------------- input

local CASTS = {
	WarpPunch = warpPunch,
	RemoteJab = remoteJab,
	WarpBarrage = warpBarrage,
	PortalBurst = portalBurst,
}

Remote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
	local s = stateOf(player)
	if action == "Cast" then
		local cast = if typeof(a) == "string" then (CASTS :: any)[a] else nil
		if cast and ready(player, s, a) then
			s.token += 1
			cast(player, s, b)
		end
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
