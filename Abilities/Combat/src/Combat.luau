--!strict
--[[
	Combat (ReplicatedStorage.Combat): the rules every ability's hits go through, for a parry-style
	fight. The ability kits (Jajanken, Killua) call Combat.resolve for each target instead of dealing
	damage themselves, so blocking, parrying, guard breaks and counters work the same against all of
	them. Put your own game's combat behind these few functions to plug the kits into it.

	Block       hold F: a hit from the front deals ChipDamage of its damage and wears the guard
	            down (GuardMax, refilling after a pause). When it runs out, or a GuardBreak hit lands on
	            it, the guard breaks: the blocker is stunned for GuardBreakStun.
	Parry       press F: the first ParryWindow seconds of a block are a parry. A parryable hit that
	            lands in the window does nothing and staggers the attacker for ParriedStun. Pressing F
	            again within ParryCooldown of a parry that caught nothing only blocks.
	Stun        a clean hit stuns for its Stun seconds: no abilities, no blocking, slowed to
	            StunWalkSpeed. Stuns don't stack; the longer one wins.
	Counter     a counter stance (Killua's Whirlwind) catches the next counterable hit instead.
	Intangible  a dash passes through hits.

	The state lives in attributes on the character Model, so clients and NPC code can read it:
	  Blocking (bool), ParryAt (server time the parry window opened), Guard (number),
	  StunnedUntil (server time), StunKind (string), CounterUntil, IntangibleUntil, BusyUntil
	  (server times; BusyUntil = mid-attack: no blocking, no other ability)

	Server API:
	  Combat.resolve(attacker, victim, hit) -> Outcome    "Hit" | "Blocked" | "GuardBroken" |
	                                                      "Parried" | "Countered" | "Evaded" | "Immune"
	  Combat.stun(model, seconds, kind?)
	  Combat.canAct(model) -> boolean           alive, not stunned, blocking or busy (check before a cast)
	  Combat.setBusy(model, seconds?) / Combat.clearBusy(model)   mid-attack (nil seconds: until cleared)
	  Combat.announce(attacker, hitAt, ability, position?, from?)   an attack is on its way (NPC parries,
	                                            AI); from: where it comes from when that isn't the
	                                            attacker (a warp hole)
	  Combat.setCounter(model, seconds) / Combat.setIntangible(model, seconds)
	  Combat.setBlocking(model, on)             what the F key does (CombatServer calls it)
	  Combat.knockback(model, velocity)
	Server signals (Combat.Resolved etc. are BindableEvents; connect to .Event):
	  Resolved(attacker, victim, outcome, hit)   every resolved hit
	  Countered(victim, attacker, hit)           a counter stance caught a hit (the kit acts on it)
	  Interrupted(model)                         a stun cut the model's action short: cancel its cast
	  Announced(attacker, hitAt, ability, position, from)
	Clients get Combat.Remote: "Parried", "Blocked", "GuardBroken", "Countered", "Evaded" (for effects).
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local Combat = {}

Combat.Settings = {
	ParryWindow = 0.25, -- seconds after pressing F that a hit is parried
	ParryCooldown = 0.6, -- a missed parry can't be retried for this long (holding F still blocks)
	ParriedStun = 0.9, -- the attacker's stagger when parried
	ChipDamage = 0.15, -- share of a blocked hit's damage that still goes through
	BlockPush = 0.25, -- share of a blocked hit's knockback
	GuardMax = 100,
	GuardRegen = 20, -- per second, once GuardRegenDelay has passed since the guard was last hit
	GuardRegenDelay = 1.5,
	GuardBreakStun = 1.4,
	BlockAngle = 150, -- degrees: the front arc a block or parry covers
	BlockWalkSpeed = 9,
	StunWalkSpeed = 3,
	DefaultStun = 0.35,
	KnockbackTime = 0.18,
}

export type Hit = {
	Damage: number,
	Ability: string?, -- which attack, for signals and effects
	Knockback: Vector3?, -- push on a clean hit (studs/s)
	Stun: number?, -- seconds stunned on a clean hit (default Settings.DefaultStun)
	StunKind: string?, -- "Hit" (default), "Shock" (paralysed), "Launch", ...
	Parryable: boolean?, -- default true
	Blockable: boolean?, -- default true
	Counterable: boolean?, -- default true
	GuardDamage: number?, -- default 2 x Damage
	GuardBreak: boolean?, -- breaks a block outright
	From: Vector3?, -- where it comes from: blocks and parries only work facing it (default the attacker)
	FromAbove: boolean?, -- strikes down from above: blocks work facing any way, parries never do
}
export type Outcome = "Hit" | "Blocked" | "GuardBroken" | "Parried" | "Countered" | "Evaded" | "Immune"

local function event(name: string): BindableEvent
	local e = Instance.new("BindableEvent")
	e.Name = name
	return e
end
Combat.Resolved = event("Resolved")
Combat.Countered = event("Countered")
Combat.Interrupted = event("Interrupted")
Combat.Announced = event("Announced")

local remote: RemoteEvent? = nil
local function broadcast(...: any)
	if not remote then
		local found = script.Parent and script.Parent:FindFirstChild("Remote")
		remote = if found and found:IsA("RemoteEvent") then found else nil
	end
	if remote then
		remote:FireAllClients(...)
	end
end

function Combat.now(): number
	return workspace:GetServerTimeNow()
end

local function humanoidOf(model: Instance?): Humanoid?
	return if model then model:FindFirstChildOfClass("Humanoid") else nil
end

local function rootOf(model: Instance?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function number(model: Instance, name: string): number
	local v = model:GetAttribute(name)
	return if typeof(v) == "number" then v else 0
end

function Combat.isStunned(model: Instance): boolean
	return number(model, "StunnedUntil") > Combat.now()
end

function Combat.isBlocking(model: Instance): boolean
	return model:GetAttribute("Blocking") == true
end

function Combat.alive(model: Instance?): boolean
	local humanoid = humanoidOf(model)
	return humanoid ~= nil and humanoid.Health > 0
end

function Combat.isBusy(model: Instance): boolean
	return number(model, "BusyUntil") > Combat.now()
end

function Combat.canAct(model: Instance?): boolean
	return model ~= nil
		and Combat.alive(model)
		and not Combat.isStunned(model)
		and not Combat.isBlocking(model)
		and not Combat.isBusy(model)
end

function Combat.setBusy(model: Instance, seconds: number?)
	model:SetAttribute("BusyUntil", if seconds then Combat.now() + seconds else math.huge)
end

function Combat.clearBusy(model: Instance)
	model:SetAttribute("BusyUntil", nil)
end

function Combat.guard(model: Instance): number
	local v = model:GetAttribute("Guard")
	return if typeof(v) == "number" then v else Combat.Settings.GuardMax
end

-- models whose guard is below full (they regenerate in Combat.step)
local worn: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- the walk speed a model goes back to once nothing (block, stun) is holding it down
local held: { [Instance]: { speed: number, by: { [string]: boolean } } } = setmetatable({}, { __mode = "k" }) :: any

local function hold(model: Instance, reason: string, speed: number)
	local humanoid = humanoidOf(model)
	if not humanoid then
		return
	end
	local entry = held[model]
	if not entry then
		entry = { speed = humanoid.WalkSpeed, by = {} }
		held[model] = entry
	end
	entry.by[reason] = true
	local slowest = speed
	if entry.by.Stun then
		slowest = math.min(slowest, Combat.Settings.StunWalkSpeed)
	end
	if entry.by.Block then
		slowest = math.min(slowest, Combat.Settings.BlockWalkSpeed)
	end
	humanoid.WalkSpeed = math.min(entry.speed, slowest)
end

local function release(model: Instance, reason: string)
	local entry = held[model]
	if not entry then
		return
	end
	entry.by[reason] = nil
	local humanoid = humanoidOf(model)
	if next(entry.by) == nil then
		held[model] = nil
		if humanoid then
			humanoid.WalkSpeed = entry.speed
		end
	elseif humanoid then
		humanoid.WalkSpeed = math.min(
			entry.speed,
			if entry.by.Stun then Combat.Settings.StunWalkSpeed else Combat.Settings.BlockWalkSpeed
		)
	end
end

function Combat.setBlocking(model: Instance, on: boolean)
	if on then
		if not (Combat.alive(model) and not Combat.isStunned(model) and not Combat.isBusy(model)) then
			return
		end
		model:SetAttribute("Blocking", true)
		hold(model, "Block", Combat.Settings.BlockWalkSpeed)
	else
		if model:GetAttribute("Blocking") then
			model:SetAttribute("Blocking", false)
		end
		model:SetAttribute("ParryAt", nil)
		release(model, "Block")
	end
end

-- opens the parry window now (CombatServer calls it on the key press, within ParryCooldown rules)
function Combat.openParry(model: Instance)
	model:SetAttribute("ParryAt", Combat.now())
end

function Combat.stun(model: Instance, seconds: number, kind: string?)
	if seconds <= 0 or not Combat.alive(model) then
		return
	end
	local untilTime = math.max(number(model, "StunnedUntil"), Combat.now() + seconds)
	Combat.Interrupted:Fire(model) -- abilities cancel their cast (and put their walk speed back) first
	Combat.clearBusy(model)
	Combat.setBlocking(model, false)
	model:SetAttribute("CounterUntil", nil)
	model:SetAttribute("StunnedUntil", untilTime)
	model:SetAttribute("StunKind", kind or "Hit")
	hold(model, "Stun", Combat.Settings.StunWalkSpeed)
	task.delay(untilTime - Combat.now() + 0.01, function()
		if number(model, "StunnedUntil") <= Combat.now() then
			release(model, "Stun")
		end
	end)
end

function Combat.setCounter(model: Instance, seconds: number)
	model:SetAttribute("CounterUntil", if seconds > 0 then Combat.now() + seconds else nil)
end

function Combat.setIntangible(model: Instance, seconds: number)
	model:SetAttribute("IntangibleUntil", Combat.now() + seconds)
end

function Combat.announce(attacker: Instance, hitAt: number, ability: string, position: Vector3?, from: Vector3?)
	Combat.Announced:Fire(attacker, hitAt, ability, position, from)
end

function Combat.knockback(model: Instance, velocity: Vector3)
	local root = rootOf(model)
	if not root or velocity.Magnitude < 1 then
		return
	end
	-- a short-lived constraint: it replicates to whoever owns the victim's physics, so it pushes
	-- players as well as NPCs
	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatKnockback"
	attachment.Parent = root
	local push = Instance.new("LinearVelocity")
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.MaxForce = 1e6
	push.VectorVelocity = velocity
	push.Parent = attachment
	Debris:AddItem(attachment, Combat.Settings.KnockbackTime)
end

-- is `from` inside the victim's front arc?
local function facing(victim: Instance, from: Vector3): boolean
	local root = rootOf(victim)
	if not root then
		return false
	end
	local to = from - root.Position
	to = Vector3.new(to.X, 0, to.Z)
	if to.Magnitude < 0.05 then
		return true
	end
	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 1e-3 then
		return true
	end
	return look.Unit:Dot(to.Unit) >= math.cos(math.rad(Combat.Settings.BlockAngle / 2))
end

local function positionOf(model: Instance): Vector3
	local root = rootOf(model)
	return if root then root.Position elseif model:IsA("Model") then model:GetPivot().Position else Vector3.zero
end

local function finish(attacker: Instance, victim: Instance, outcome: Outcome, hit: Hit): Outcome
	Combat.Resolved:Fire(attacker, victim, outcome, hit)
	return outcome
end

function Combat.resolve(attacker: Instance, victim: Instance, hit: Hit): Outcome
	local humanoid = humanoidOf(victim)
	if not humanoid or humanoid.Health <= 0 then
		return "Immune"
	end
	local S = Combat.Settings
	local now = Combat.now()
	local at = positionOf(victim)
	local from = hit.From or positionOf(attacker)

	if number(victim, "IntangibleUntil") > now then
		broadcast("Evaded", victim, at)
		return finish(attacker, victim, "Evaded", hit)
	end

	if number(victim, "CounterUntil") > now and hit.Counterable ~= false then
		victim:SetAttribute("CounterUntil", nil)
		broadcast("Countered", victim, attacker, at)
		Combat.Countered:Fire(victim, attacker, hit)
		return finish(attacker, victim, "Countered", hit)
	end

	local stunned = Combat.isStunned(victim)
	local parryAt = victim:GetAttribute("ParryAt")
	if
		hit.Parryable ~= false
		and not hit.FromAbove
		and not stunned
		and typeof(parryAt) == "number"
		and now - parryAt <= S.ParryWindow
		and facing(victim, from)
	then
		victim:SetAttribute("ParryAt", now) -- a parry that lands keeps the window open for the next hit
		victim:SetAttribute("ParrySucceeded", true)
		local mid = at:Lerp(positionOf(attacker), 0.35)
		broadcast("Parried", victim, attacker, mid)
		if attacker ~= victim and Combat.alive(attacker) then
			Combat.stun(attacker, S.ParriedStun, "Parried")
		end
		return finish(attacker, victim, "Parried", hit)
	end

	if
		Combat.isBlocking(victim)
		and hit.Blockable ~= false
		and not stunned
		and (hit.FromAbove or facing(victim, from))
	then
		local guard = Combat.guard(victim) - (hit.GuardDamage or hit.Damage * 2)
		victim:SetAttribute("GuardHitAt", now)
		if hit.GuardBreak or guard <= 0 then
			victim:SetAttribute("Guard", S.GuardMax)
			broadcast("GuardBroken", victim, at)
			Combat.stun(victim, S.GuardBreakStun, "GuardBreak")
			return finish(attacker, victim, "GuardBroken", hit)
		end
		victim:SetAttribute("Guard", guard)
		worn[victim] = true
		humanoid:TakeDamage(hit.Damage * S.ChipDamage)
		if hit.Knockback then
			local push = hit.Knockback * S.BlockPush
			Combat.knockback(victim, Vector3.new(push.X, 0, push.Z))
		end
		broadcast("Blocked", victim, at)
		return finish(attacker, victim, "Blocked", hit)
	end

	humanoid:TakeDamage(hit.Damage)
	if hit.Knockback then
		Combat.knockback(victim, hit.Knockback)
	end
	Combat.stun(victim, hit.Stun or S.DefaultStun, hit.StunKind)
	return finish(attacker, victim, "Hit", hit)
end

-- guard regeneration: CombatServer calls this every frame
function Combat.step(dt: number)
	local S = Combat.Settings
	local now = Combat.now()
	for model in worn do
		local guard = Combat.guard(model)
		if guard >= S.GuardMax or not model.Parent then
			worn[model] = nil
		elseif now - number(model, "GuardHitAt") >= S.GuardRegenDelay then
			model:SetAttribute("Guard", math.min(S.GuardMax, guard + S.GuardRegen * dt))
		end
	end
end

-- the player controlling a model, if any
function Combat.playerOf(model: Instance?): Player?
	return if model and model:IsA("Model") then Players:GetPlayerFromCharacter(model) else nil
end

return Combat
