-- Server-authoritative combat: every fighter (player or dummy) runs through the same state
-- machine. Clients only *ask* to act; the server decides what happens and tells everyone.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Config = require(Combat.Config)
local Util = require(Combat.Util)
local Remotes = Combat:WaitForChild("Remotes")
local ActionRemote = Remotes:WaitForChild("Action")
local FXRemote = Remotes:WaitForChild("FX")

local create = Util.create
local flat = Util.flat

local CombatService = {}

local fighters = {} -- [Model] = fighter
CombatService.Fighters = fighters

local QUEUE_WINDOW = 0.3 -- requests this early are queued instead of rejected
local MAX_POSTURE = Config.Block.MaxPosture
local HITS = Config.M1.Hits

local attackListeners, resultListeners = {}, {}

-- fn(fighter, kind, spec, index) whenever an attack starts (dummies use this to react)
function CombatService.OnAttackStarted(fn)
	table.insert(attackListeners, fn)
end

-- fn(result, attacker, victim) after every resolved attack: "Hit" | "Blocked" | "Parry" | ...
function CombatService.OnResult(fn)
	table.insert(resultListeners, fn)
end

local function broadcast(kind, data)
	FXRemote:FireAllClients(kind, data)
end

local function emit(list, ...)
	for _, fn in ipairs(list) do
		task.spawn(fn, ...)
	end
end

----------------------------------------------------------------------------------------------
-- Registration

local function fighterFromPart(part)
	local node = part.Parent
	while node and node ~= Workspace do
		local f = fighters[node]
		if f then
			return f
		end
		node = node.Parent
	end
	return nil
end

function CombatService.Get(model)
	return fighters[model]
end

function CombatService.Register(model, opts)
	opts = opts or {}
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) then
		return nil
	end
	local f = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Player = opts.Player,
		IsDummy = opts.IsDummy == true,
		Dead = false,
		State = "Idle",

		Action = nil, -- "M1" | "Heavy"
		ActionToken = 0,
		ActionEnd = 0,
		HitTime = 0,
		Queued = nil,

		Combo = 0,
		LastM1End = -math.huge,
		ComboCooldownUntil = 0,
		HeavyCooldownUntil = 0,

		Blocking = false,
		WantsBlock = false,
		BlockPressTime = -math.huge,
		BlockStart = 0,
		ParryEligible = false,
		LastParryAttempt = -math.huge,

		StunUntil = 0,
		StunKind = nil, -- "Stunned" | "Parried" | "GuardBroken"
		RestorePosture = false, -- refill posture once the current stun ends (after a guard break)
		StunParryUntil = 0, -- a block pressed during hitstun parries until this time

		Posture = MAX_POSTURE,
		PostureSent = MAX_POSTURE,
		LastPostureDamage = -math.huge,

		DodgeCooldownUntil = 0,
		DodgingUntil = 0,
		IFramesUntil = 0,

		Sliding = false,
		SlideUntil = 0,

		LastHitTime = -math.huge,
	}
	fighters[model] = f

	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	model:SetAttribute("CombatState", "Idle")
	model:SetAttribute("Posture", MAX_POSTURE)
	model:SetAttribute("MaxPosture", MAX_POSTURE)
	model:SetAttribute("AttackKind", nil)
	CollectionService:AddTag(model, "Combatant")

	humanoid.Died:Connect(function()
		f.Dead = true
		f.Blocking = false
		f.Action = nil
		model:SetAttribute("CombatState", "Dead")
	end)
	model.Destroying:Connect(function()
		fighters[model] = nil
	end)
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			fighters[model] = nil
		end
	end)
	return f
end

----------------------------------------------------------------------------------------------
-- Helpers

local function now()
	return os.clock()
end

local function isStunned(f, t)
	return t < f.StunUntil
end

-- Free to start a new action right now?
local function canAct(f, t)
	return not f.Dead and not isStunned(f, t) and t >= f.ActionEnd
end

local function reject(f, action, seq)
	if f.Player then
		FXRemote:FireClient(f.Player, "Reject", { Action = action, Seq = seq })
	end
end

local function cancelAction(f)
	if f.Action then
		f.ActionToken += 1
		f.Action = nil
		f.ActionEnd = 0
		broadcast("Cancel", { Model = f.Model })
	end
	f.Queued = nil
end

local function endBlock(f)
	if f.Blocking then
		f.Blocking = false
		broadcast("BlockEnd", { Model = f.Model })
	end
end

local function endSlide(f)
	if f.Sliding then
		f.Sliding = false
		broadcast("Slide", { Model = f.Model, Active = false })
	end
end

-- Pushes a server-owned body (dummies). Player characters are pushed by their own client,
-- which receives the knockback vector in the FX event.
local function physicsPush(f, velocity, duration)
	if f.Player or not f.Root.Parent then
		return
	end
	local attachment = f.Root:FindFirstChild("RootAttachment")
		or create("Attachment", { Name = "RootAttachment", Parent = f.Root })
	local old = f.Root:FindFirstChild("KnockbackVelocity")
	if old then
		old:Destroy()
	end
	local lv = create("LinearVelocity", {
		Name = "KnockbackVelocity",
		Attachment0 = attachment,
		VelocityConstraintMode = Enum.VelocityConstraintMode.Vector,
		VectorVelocity = velocity,
		MaxForce = 1e6,
		RelativeTo = Enum.ActuatorRelativeTo.World,
		Parent = f.Root,
	})
	Debris:AddItem(lv, duration)
end
CombatService.Push = physicsPush

local function isFacing(victim, attacker)
	local toAttacker = flat(attacker.Root.Position - victim.Root.Position)
	if toAttacker.Magnitude < 0.05 then
		return true
	end
	local look = flat(victim.Root.CFrame.LookVector)
	if look.Magnitude < 0.05 then
		return true
	end
	return look.Unit:Dot(toAttacker.Unit) >= Config.Block.FacingDot
end

local function stun(f, duration, kind)
	local t = now()
	local untilTime = t + duration
	if untilTime >= f.StunUntil or not f.StunKind then
		f.StunUntil = untilTime
		f.StunKind = kind
	end
end

----------------------------------------------------------------------------------------------
-- Resolution

local function applyGuardBreak(attacker, victim, spec, dir, contact, t)
	cancelAction(victim)
	endSlide(victim)
	endBlock(victim)
	victim.WantsBlock = false
	victim.Posture = 0
	victim.LastPostureDamage = t
	victim.RestorePosture = true
	victim.StunParryUntil = 0
	stun(victim, Config.GuardBreak.Stun, "GuardBroken")
	local damage = if spec.GuardBreak then spec.Damage * 0.35 else 0
	if damage > 0 then
		victim.Humanoid:TakeDamage(damage)
	end
	physicsPush(victim, dir * 18, 0.12)
	broadcast("GuardBreak", {
		Attacker = attacker.Model,
		Victim = victim.Model,
		Position = contact,
		Direction = dir,
		Damage = damage,
		Stun = Config.GuardBreak.Stun,
		Knockback = dir * 18,
	})
	emit(resultListeners, "GuardBreak", attacker, victim)
end

local function resolve(attacker, victim, kind, index, spec)
	local t = now()
	local delta = flat(victim.Root.Position - attacker.Root.Position)
	local dir = if delta.Magnitude > 0.05 then delta.Unit else flat(attacker.Root.CFrame.LookVector).Unit
	local contact = victim.Root.Position - dir * 0.9 + Vector3.new(0, 0.7, 0)

	-- Dodge i-frames
	if t < victim.IFramesUntil then
		broadcast("Dodged", { Attacker = attacker.Model, Victim = victim.Model, Position = contact })
		emit(resultListeners, "Dodged", attacker, victim)
		return "Dodged"
	end

	local facing = isFacing(victim, attacker)
	-- Parry: the first moments of a fresh block, or a block pressed during hitstun
	local blockParry = victim.Blocking and victim.ParryEligible and (t - victim.BlockStart) <= Config.Parry.Window
	local stunParry = t <= victim.StunParryUntil and victim.StunKind == "Stunned"
	if facing and (blockParry or stunParry) then
		cancelAction(attacker)
		endSlide(attacker)
		attacker.Combo = 0
		attacker.StunParryUntil = 0
		stun(attacker, Config.Parry.AttackerStun, "Parried")
		physicsPush(attacker, -dir * Config.Parry.AttackerPushback, 0.12)
		if stunParry then
			-- parrying out of a combo frees you from the hitstun
			victim.StunUntil = t
			victim.StunKind = nil
			victim.StunParryUntil = 0
		end
		victim.Posture = math.min(MAX_POSTURE, victim.Posture + Config.Parry.PostureRestore)
		victim.LastParryAttempt = -math.huge -- a successful parry never locks you out
		victim.BlockStart = t -- and keeps the window open for a follow-up hit
		broadcast("Parry", {
			Attacker = attacker.Model,
			Victim = victim.Model,
			Position = contact,
			Direction = dir,
			Stun = Config.Parry.AttackerStun,
			Knockback = -dir * Config.Parry.AttackerPushback,
			FromStun = stunParry,
		})
		emit(resultListeners, "Parry", attacker, victim)
		return "Parry"
	end

	if victim.Blocking and facing then
		if spec.GuardBreak then
			applyGuardBreak(attacker, victim, spec, dir, contact, t)
			return "GuardBreak"
		end

		victim.Posture -= spec.PostureDamage
		victim.LastPostureDamage = t
		if victim.Posture <= 0 then
			applyGuardBreak(attacker, victim, spec, dir, contact, t)
			return "GuardBreak"
		end
		local chip = spec.Damage * Config.Block.DamageMultiplier
		if chip > 0 then
			victim.Humanoid:TakeDamage(chip)
		end
		local push = dir * Config.Block.BlockedPushback
		physicsPush(victim, push, 0.1)
		broadcast("Blocked", {
			Attacker = attacker.Model,
			Victim = victim.Model,
			Position = contact,
			Direction = dir,
			Posture = victim.Posture / MAX_POSTURE,
			Damage = chip,
			Knockback = push,
		})
		emit(resultListeners, "Blocked", attacker, victim)
		return "Blocked"
	end

	-- Clean hit
	cancelAction(victim)
	endBlock(victim)
	endSlide(victim)
	victim.Combo = 0
	victim.LastHitTime = t
	victim.Humanoid:TakeDamage(spec.Damage)
	stun(victim, spec.Stun, "Stunned")
	local knock = dir * spec.Knockback + Vector3.new(0, spec.KnockUp or 0, 0)
	local knockTime = if spec.KnockUp then 0.22 else 0.12
	physicsPush(victim, knock, knockTime)
	broadcast("Hit", {
		Attacker = attacker.Model,
		Victim = victim.Model,
		Kind = kind,
		Index = index,
		Damage = spec.Damage,
		Position = contact,
		Direction = dir,
		Finisher = spec.Finisher == true,
		Knockback = knock,
		KnockTime = knockTime,
		Stun = spec.Stun,
	})
	emit(resultListeners, "Hit", attacker, victim)
	return "Hit"
end

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function showHitbox(cf, size)
	local box = create("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 0.7,
		Color = Color3.fromRGB(255, 60, 60),
		Material = Enum.Material.ForceField,
		CFrame = cf,
		Size = size,
		Parent = Workspace,
	})
	Debris:AddItem(box, 0.25)
end

local function performHit(f, kind, index, spec)
	if f.Dead or not f.Root.Parent then
		return
	end
	local hitbox = if kind == "Heavy" then Config.Heavy.Hitbox else Config.M1.Hitbox
	local cf = f.Root.CFrame * hitbox.Offset
	overlapParams.FilterDescendantsInstances = { f.Model }
	local parts = Workspace:GetPartBoundsInBox(cf, hitbox.Size, overlapParams)
	if Config.Debug.ShowHitboxes then
		showHitbox(cf, hitbox.Size)
	end
	local seen = {}
	for _, part in ipairs(parts) do
		local target = fighterFromPart(part)
		if target and target ~= f and not seen[target] and not target.Dead then
			seen[target] = true
			resolve(f, target, kind, index, spec)
		end
	end
end

----------------------------------------------------------------------------------------------
-- Actions

local function pickAnim(spec, requested)
	if spec.Anims then
		for _, name in ipairs(spec.Anims) do
			if name == requested then
				return name
			end
		end
		return spec.Anims[math.random(1, #spec.Anims)]
	end
	return spec.Anim
end
CombatService.PickAnim = pickAnim

local function startAttack(f, kind, index, spec, seq, requestedAnim)
	local t = now()
	f.ActionToken += 1
	local token = f.ActionToken
	f.Action = kind
	f.ActionEnd = t + spec.Duration
	f.HitTime = t + spec.Windup
	endSlide(f)
	f.Model:SetAttribute("AttackKind", kind)
	broadcast(
		"Attack",
		{ Model = f.Model, Kind = kind, Index = index, Anim = pickAnim(spec, requestedAnim), Seq = seq }
	)
	emit(attackListeners, f, kind, spec, index)

	if f.IsDummy and spec.Lunge then
		local look = flat(f.Root.CFrame.LookVector)
		if look.Magnitude > 0.01 then
			task.delay(spec.Windup * 0.3, function()
				if f.ActionToken == token then
					physicsPush(f, look.Unit * spec.Lunge, spec.Windup * 0.7)
				end
			end)
		end
	end

	task.delay(spec.Windup, function()
		if f.ActionToken == token and not f.Dead and not isStunned(f, now()) then
			performHit(f, kind, index, spec)
		end
	end)
	task.delay(spec.Duration, function()
		if f.ActionToken == token then
			f.Action = nil
		end
	end)
end

local tryM1, tryHeavy

local function queue(f, kind, seq, at, anim)
	if f.Queued then
		return reject(f, kind, seq)
	end
	local entry = { Kind = kind, Seq = seq }
	f.Queued = entry
	task.delay(math.max(0, at - now()) + 0.001, function()
		if f.Queued == entry then
			f.Queued = nil
			if kind == "M1" then
				tryM1(f, seq, anim)
			else
				tryHeavy(f, seq)
			end
		end
	end)
end

function tryM1(f, seq, anim)
	local t = now()
	if f.Dead or isStunned(f, t) or f.Blocking or t < f.DodgingUntil then
		return reject(f, "M1", seq)
	end
	local readyAt = math.max(f.ActionEnd, f.ComboCooldownUntil)
	if t < readyAt then
		if readyAt - t <= QUEUE_WINDOW then
			return queue(f, "M1", seq, readyAt, anim)
		end
		return reject(f, "M1", seq)
	end
	if t - f.LastM1End > Config.M1.ComboResetTime then
		f.Combo = 0
	end
	f.Combo = f.Combo % #HITS + 1
	local index = f.Combo
	local spec = HITS[index]
	startAttack(f, "M1", index, spec, seq, anim)
	f.LastM1End = t + spec.Duration
	if index == #HITS then
		f.Combo = 0
		f.ComboCooldownUntil = t + spec.Duration + Config.M1.ComboEndCooldown
	end
end

function tryHeavy(f, seq)
	local t = now()
	if f.Dead or isStunned(f, t) or f.Blocking or t < f.HeavyCooldownUntil or t < f.DodgingUntil then
		return reject(f, "Heavy", seq)
	end
	if t < f.ActionEnd then
		if f.ActionEnd - t <= QUEUE_WINDOW then
			return queue(f, "Heavy", seq, f.ActionEnd)
		end
		return reject(f, "Heavy", seq)
	end
	f.Combo = 0
	f.HeavyCooldownUntil = t + Config.Heavy.Cooldown
	startAttack(f, "Heavy", 1, Config.Heavy, seq)
end

local function startBlock(f, t)
	f.Blocking = true
	f.BlockStart = t
	local fresh = (t - f.BlockPressTime) <= 0.25 and not f.BlockNoParry
	f.ParryEligible = fresh and (t - f.LastParryAttempt) >= Config.Parry.Cooldown
	if f.ParryEligible then
		f.LastParryAttempt = t
	end
	endSlide(f)
	broadcast("BlockStart", { Model = f.Model, Parry = f.ParryEligible })
end

-- noParry: raise a plain block with no parry window (used by dummies that only block)
local function tryBlockStart(f, noParry)
	local t = now()
	f.WantsBlock = true
	f.BlockPressTime = t
	f.BlockNoParry = noParry == true
	-- Pressing block while being comboed can still parry the next hit
	if Config.Parry.DuringHitstun and f.StunKind == "Stunned" and isStunned(f, t) and not noParry then
		if (t - f.LastParryAttempt) >= Config.Parry.Cooldown then
			f.LastParryAttempt = t
			f.StunParryUntil = t + Config.Parry.Window
		end
	end
	if not f.Blocking and canAct(f, t) and t >= f.DodgingUntil then
		startBlock(f, t)
	end
end

local function tryBlockEnd(f)
	f.WantsBlock = false
	endBlock(f)
end

local DODGE_DIRS = { Forward = true, Back = true, Left = true, Right = true }

local function tryDodge(f, dir, seq)
	local t = now()
	if not DODGE_DIRS[dir] then
		return reject(f, "Dodge", seq)
	end
	if f.Dead or isStunned(f, t) or t < f.DodgeCooldownUntil then
		return reject(f, "Dodge", seq)
	end
	if f.Action then
		-- you can dodge out of a punch's recovery, never out of its windup
		if not Config.Dodge.CanCancelRecovery or t < f.HitTime then
			return reject(f, "Dodge", seq)
		end
		cancelAction(f)
	end
	endBlock(f) -- a held block comes back up once the dodge ends
	endSlide(f)
	f.DodgeCooldownUntil = t + Config.Dodge.Cooldown
	f.DodgingUntil = t + Config.Dodge.Duration
	f.IFramesUntil = t + Config.Dodge.IFrames + 0.06 -- small allowance for latency
	broadcast("Dodge", { Model = f.Model, Dir = dir, Seq = seq })
	return true
end

local function trySlide(f, active)
	local t = now()
	if active then
		if f.Dead or isStunned(f, t) or f.Action or f.Blocking then
			return reject(f, "Slide", nil)
		end
		f.Sliding = true
		f.SlideUntil = t + Config.Slide.MaxDuration + 0.3
		broadcast("Slide", { Model = f.Model, Active = true })
	else
		endSlide(f)
	end
end

CombatService.TryM1 = tryM1
CombatService.TryHeavy = tryHeavy
CombatService.TryBlockStart = tryBlockStart
CombatService.TryBlockEnd = tryBlockEnd
CombatService.TryDodge = tryDodge
CombatService.TrySlide = trySlide

----------------------------------------------------------------------------------------------
-- Networking

local rate = {} -- [Player] = { window = time, count = n }

local function allowRequest(player)
	local t = now()
	local r = rate[player]
	if not r or t - r.window > 1 then
		r = { window = t, count = 0 }
		rate[player] = r
	end
	r.count += 1
	return r.count <= 40
end

local function onAction(player, action, payload)
	if type(action) ~= "string" or not allowRequest(player) then
		return
	end
	local character = player.Character
	local f = character and fighters[character]
	if not f then
		return
	end
	payload = if type(payload) == "table" then payload else {}
	local seq = if type(payload.Seq) == "number" then payload.Seq else nil
	if action == "M1" then
		tryM1(f, seq, if type(payload.Anim) == "string" then payload.Anim else nil)
	elseif action == "Heavy" then
		tryHeavy(f, seq)
	elseif action == "BlockStart" then
		tryBlockStart(f)
	elseif action == "BlockEnd" then
		tryBlockEnd(f)
	elseif action == "Dodge" then
		tryDodge(f, if type(payload.Dir) == "string" then payload.Dir else "", seq)
	elseif action == "Slide" then
		trySlide(f, payload.Active == true)
	end
end

----------------------------------------------------------------------------------------------
-- Per-frame upkeep

local function computeState(f, t)
	if f.Dead then
		return "Dead"
	end
	if t < f.StunUntil then
		return f.StunKind or "Stunned"
	end
	if f.Action and t < f.ActionEnd then
		return "Attacking"
	end
	if t < f.DodgingUntil then
		return "Dodging"
	end
	if f.Blocking then
		return "Blocking"
	end
	if f.Sliding then
		return "Sliding"
	end
	return "Idle"
end

local function dummySpeed(f, state)
	local m = Config.Movement
	if state == "Stunned" or state == "Parried" or state == "GuardBroken" then
		return 0
	elseif state == "Attacking" then
		return if f.Action == "Heavy" then m.HeavyWalkSpeed else m.AttackWalkSpeed
	elseif state == "Blocking" then
		return m.BlockWalkSpeed
	end
	return f.DesiredWalkSpeed or m.WalkSpeed
end

local function heartbeat(dt)
	local t = now()
	for model, f in pairs(fighters) do
		if f.Dead or not model.Parent then
			continue
		end
		if f.Action and t >= f.ActionEnd then
			f.Action = nil
		end
		if f.StunKind and t >= f.StunUntil then
			f.StunKind = nil
		end
		if f.RestorePosture and t >= f.StunUntil then
			f.RestorePosture = false
			f.Posture = MAX_POSTURE * Config.GuardBreak.PostureAfter
		end
		if f.Sliding and t >= f.SlideUntil then
			endSlide(f)
		end
		if f.WantsBlock and not f.Blocking and canAct(f, t) and t >= f.DodgingUntil then
			startBlock(f, t)
		end
		if
			f.Posture < MAX_POSTURE
			and not f.RestorePosture
			and not isStunned(f, t)
			and t - f.LastPostureDamage > Config.Block.PostureRegenDelay
		then
			f.Posture = math.min(MAX_POSTURE, f.Posture + Config.Block.PostureRegenRate * dt)
		end

		local state = computeState(f, t)
		if state ~= f.State then
			f.State = state
			model:SetAttribute("CombatState", state)
			if state ~= "Attacking" then
				model:SetAttribute("AttackKind", nil)
			end
		end
		if math.abs(f.Posture - f.PostureSent) >= 1 or (f.Posture >= MAX_POSTURE and f.PostureSent < MAX_POSTURE) then
			f.PostureSent = f.Posture
			model:SetAttribute("Posture", math.floor(f.Posture + 0.5))
		end
		if f.IsDummy then
			local speed = dummySpeed(f, state)
			if f.Humanoid.WalkSpeed ~= speed then
				f.Humanoid.WalkSpeed = speed
			end
		end
	end
end

function CombatService.Start()
	ActionRemote.OnServerEvent:Connect(onAction)
	RunService.Heartbeat:Connect(heartbeat)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		rate[player] = nil
	end)
end

return CombatService
