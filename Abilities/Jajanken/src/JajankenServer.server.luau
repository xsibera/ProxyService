--!strict
--[[
	JajankenServer (ServerScriptService): runs Jajanken for every player.

	The server owns the timing: the charge is measured from when it hears the key go down to when
	it hears it come up (or MaxCharge, when it casts by itself), it checks cooldowns, and it does the
	hits, damage and knockback. Clients only ask ("Charge" with a mode, then "Release") and draw.

	Server -> clients (Remote:FireAllClients):
		"Charge",  caster, mode, startedAt            started charging (server time)
		"Stop",    caster                             the charge was cancelled (died, left)
		"Cast",    caster, mode, charge, hitAt        released; the hit lands at server time hitAt
		"Launch",  caster, id, from, direction, speed, range, launchAt, charge     Paper ball thrown
		"Explode", caster, id, position, charge       Paper ball burst
		"Hit",     victim, mode, position, direction  someone was hit
	Server -> one client: "Denied", mode, secondsLeft (on cooldown or busy)

	Other server scripts can listen for hits:
		ServerScriptService.JajankenServer.OnHit.Event:Connect(function(attacker, victim, mode, damage, charge) end)
]]

if not script:IsDescendantOf(game:GetService("ServerScriptService")) then
	return -- still in the package's folders: it only runs from ServerScriptService
end

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Jajanken = ReplicatedStorage:WaitForChild("Jajanken")
local Config = require(Jajanken:WaitForChild("Config")) :: any
local Remote = Jajanken:WaitForChild("Remote") :: RemoteEvent

local OnHit = Instance.new("BindableEvent")
OnHit.Name = "OnHit"
OnHit.Parent = script

type State = {
	mode: string,
	started: number,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	walkSpeed: number,
	casting: boolean,
	died: RBXScriptConnection?,
}

local states: { [Player]: State } = {}
local readyAt: { [Player]: { [string]: number } } = {}
local projectileId = 0

local function isMode(mode: any): boolean
	return mode == "Rock" or mode == "Paper" or mode == "Scissors"
end

local function alive(state: State): boolean
	return state.humanoid.Health > 0 and state.root:IsDescendantOf(workspace) and state.character.Parent ~= nil
end

local function finish(player: Player, state: State)
	if states[player] ~= state then
		return
	end
	states[player] = nil
	if state.died then
		state.died:Disconnect()
	end
	if state.humanoid.Parent and state.humanoid.WalkSpeed == Config.ChargeWalkSpeed then
		state.humanoid.WalkSpeed = state.walkSpeed
	end
end

local function cancel(player: Player)
	local state = states[player]
	if state and not state.casting then
		finish(player, state)
		Remote:FireAllClients("Stop", player)
	elseif state then
		finish(player, state)
	end
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

-- the living Humanoids (other than the caster) with a part among `parts`
local function victimsAmong(attacker: Player, parts: { BasePart }): { [Model]: Humanoid }
	local found: { [Model]: Humanoid } = {}
	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		while model and not model:FindFirstChildOfClass("Humanoid") do
			model = model:FindFirstAncestorOfClass("Model")
		end
		if model and not found[model] and model ~= attacker.Character then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and canHit(attacker, model) then
				found[model] = humanoid
			end
		end
	end
	return found
end

local function overlap(character: Model): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	return params
end

local function knockback(model: Model, velocity: Vector3)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or velocity.Magnitude < 1 then
		return
	end
	-- a short-lived constraint: it replicates to whoever owns the victim's physics, so it pushes
	-- players as well as NPCs
	local attachment = Instance.new("Attachment")
	attachment.Name = "JajankenKnockback"
	attachment.Parent = root
	local push = Instance.new("LinearVelocity")
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.MaxForce = 1e6
	push.VectorVelocity = velocity
	push.Parent = attachment
	Debris:AddItem(attachment, Config.KnockbackTime)
end

local function hit(
	attacker: Player,
	model: Model,
	humanoid: Humanoid,
	mode: string,
	damage: number,
	charge: number,
	push: Vector3
)
	humanoid:TakeDamage(damage)
	knockback(model, push)
	local root = model:FindFirstChild("HumanoidRootPart")
	local at = if root and root:IsA("BasePart") then root.Position else model:GetPivot().Position
	Remote:FireAllClients("Hit", model, mode, at, if push.Magnitude > 0 then push.Unit else Vector3.yAxis)
	OnHit:Fire(attacker, model, mode, damage, charge)
end

-- Rock and Scissors: one box in front of the caster at the moment of the hit
local function strike(player: Player, state: State, charge: number)
	local settings = Config[state.mode]
	local size: Vector3 = Config.scaled(settings.Hitbox, charge)
	local root = state.root.CFrame
	local box = root * CFrame.new(0, 0, -size.Z / 2)
	local parts = workspace:GetPartBoundsInBox(box, size, overlap(state.character))
	local damage = Config.scaled(settings.Damage, charge)
	local speed = Config.scaled(settings.Knockback, charge)
	local direction = if state.mode == "Scissors"
		then (root.LookVector * 0.8 - root.RightVector * 0.6).Unit -- the blade sweeps right to left
		else root.LookVector
	for model, humanoid in victimsAmong(player, parts) do
		hit(player, model, humanoid, state.mode, damage, charge, direction * speed + Vector3.new(0, speed * 0.3, 0))
	end
end

-- where the ball goes: the camera's aim if it's within MaxAimAngle of the facing, else straight ahead
local function aimOf(root: BasePart, aim: any): Vector3
	local facing = root.CFrame.LookVector
	if not Config.Paper.AimWithCamera or typeof(aim) ~= "Vector3" then
		return facing
	end
	local length = aim.Magnitude
	if not (length >= 0.5 and length < math.huge) then -- also rejects NaN
		return facing
	end
	local direction = aim.Unit
	if direction:Dot(facing) < math.cos(math.rad(Config.Paper.MaxAimAngle)) then
		return facing
	end
	return direction
end

local function throwPaper(player: Player, state: State, charge: number, aim: any)
	local settings = Config.Paper
	local speed = Config.scaled(settings.Speed, charge)
	local range = Config.scaled(settings.Range, charge)
	local radius = Config.scaled(settings.Radius, charge)
	local direction = aimOf(state.root, aim)
	local from = (state.root.CFrame * CFrame.new(0.9, -0.75, -3.4)).Position -- the palm at the Hit marker
	projectileId += 1
	local id = projectileId
	Remote:FireAllClients("Launch", player, id, from, direction, speed, range, workspace:GetServerTimeNow(), charge)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { state.character }
	local travelled = 0
	local connection: RBXScriptConnection

	local function burst(at: Vector3, struck: Instance?)
		connection:Disconnect()
		Remote:FireAllClients("Explode", player, id, at, charge)
		local blast = Config.scaled(settings.BlastRadius, charge)
		local damage = Config.scaled(settings.Damage, charge)
		local push = Config.scaled(settings.Knockback, charge)
		local parts = workspace:GetPartBoundsInRadius(at, blast, overlap(state.character))
		if struck and struck:IsA("BasePart") then
			table.insert(parts, struck)
		end
		for model, humanoid in victimsAmong(player, parts) do
			local pivot = model:GetPivot().Position
			local away = pivot - at
			local falloff = 1 - 0.5 * math.clamp(away.Magnitude / blast, 0, 1)
			local outward = if away.Magnitude > 0.1 then away.Unit else direction
			local velocity = (outward * 0.7 + direction * 0.5).Unit * push * falloff
			hit(player, model, humanoid, "Paper", damage * falloff, charge, velocity + Vector3.new(0, push * 0.3, 0))
		end
	end

	connection = RunService.Heartbeat:Connect(function(dt: number)
		local step = math.min(speed * dt, range - travelled)
		local origin = from + direction * travelled
		local result = workspace:Spherecast(origin, radius, direction * step, params)
		if result then
			burst(result.Position, result.Instance)
			return
		end
		travelled += step
		if travelled >= range - 1e-6 then
			burst(from + direction * range, nil)
		end
	end)
end

--------------------------------------------------------------------------- charge and cast

local function cast(player: Player, state: State, aim: any)
	if state.casting then
		return
	end
	state.casting = true
	local mode = state.mode
	local settings = Config[mode]
	local now = os.clock()
	local charge = math.clamp((now - state.started) / Config.MaxCharge, 0, 1)
	local ready = readyAt[player]
	ready[mode] = now + Config.Cooldown[mode]
	ready.All = now + Config.SharedCooldown
	Remote:FireAllClients("Cast", player, mode, charge, workspace:GetServerTimeNow() + settings.HitDelay)

	task.delay(settings.HitDelay, function()
		if states[player] ~= state or not alive(state) then
			return
		end
		if mode == "Paper" then
			throwPaper(player, state, charge, aim)
		else
			strike(player, state, charge)
		end
	end)
	task.delay(math.max(settings.Recovery, settings.HitDelay + 0.05), function()
		finish(player, state)
	end)
end

local function startCharge(player: Player, mode: string)
	if states[player] then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		return
	end
	local now = os.clock()
	local ready = readyAt[player] or {}
	readyAt[player] = ready
	local waitFor = math.max(ready[mode] or 0, ready.All or 0) - now
	if waitFor > 0 then
		Remote:FireClient(player, "Denied", mode, waitFor)
		return
	end

	local state: State = {
		mode = mode,
		started = now,
		character = character,
		humanoid = humanoid,
		root = root,
		walkSpeed = humanoid.WalkSpeed,
		casting = false,
		died = nil,
	}
	states[player] = state
	humanoid.WalkSpeed = Config.ChargeWalkSpeed
	state.died = humanoid.Died:Connect(function()
		cancel(player)
	end)
	Remote:FireAllClients("Charge", player, mode, workspace:GetServerTimeNow())

	task.delay(Config.MaxCharge, function()
		if states[player] == state and not state.casting then
			if alive(state) then
				cast(player, state, nil) -- full power: it goes off by itself
			else
				cancel(player)
			end
		end
	end)
end

Remote.OnServerEvent:Connect(function(player: Player, action: any, value: any)
	if action == "Charge" and isMode(value) then
		startCharge(player, value)
	elseif action == "Release" then
		local state = states[player]
		if state and not state.casting then
			if alive(state) then
				cast(player, state, value)
			else
				cancel(player)
			end
		end
	elseif action == "Cancel" then
		cancel(player)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	cancel(player)
	readyAt[player] = nil
end)
