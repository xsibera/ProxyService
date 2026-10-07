--!nocheck
-- Headless test of the Combat rules (Combat.resolve and friends) and CombatServer's F key, against
-- Place1's mock engine. Run from this folder:  cd Abilities/Combat && luaurun tests/server.luau

local H = assert(loadfile("tests/harness.luau"))()
local mock, check, near = H.mock, H.check, H.near
local Combat = require(H.CombatModule)
local S = Combat.Settings

local SSS = game:GetService("ServerScriptService")
local serverScript = mock.newInstance("Script", "CombatServer")
rawget(serverScript, "__props").__path = "src/CombatServer.server.luau"
serverScript.Parent = SSS
mock.runScript(serverScript)
mock.advance(0)

local function send(player, ...)
	H.remote.OnServerEvent:Fire(player, ...)
end

-- A at the origin facing -Z, V 4 studs in front facing back at A
local aModel, aParts, aHum = H.character("A", 0, 0, 0)
local a = H.player("A", aModel)
local vModel, vParts, vHum = H.character("V", 0, -4, 180)
local v = H.player("V", vModel)

local interrupted, countered, resolved = {}, {}, {}
Combat.Interrupted.Event:Connect(function(model)
	table.insert(interrupted, model)
end)
Combat.Countered.Event:Connect(function(victim, attacker)
	table.insert(countered, { victim = victim, attacker = attacker })
end)
Combat.Resolved.Event:Connect(function(attacker, victim, outcome)
	table.insert(resolved, outcome)
end)

local function heal()
	aHum.Health, vHum.Health = 200, 200
end
local function settle()
	mock.advance(2.5) -- every stun, window and cooldown over, guard regenerated
	send(v, "Block", false)
	send(a, "Block", false)
	mock.advance(0.1)
	heal()
	table.clear(H.remoteLog)
	table.clear(interrupted)
	table.clear(countered)
end
local function pushOn(parts)
	for _, d in ipairs(parts.HumanoidRootPart:GetDescendants()) do
		if d.ClassName == "LinearVelocity" then
			return d.VectorVelocity
		end
	end
	return nil
end
local HIT = { Damage = 10, Stun = 0.5, Knockback = Vector3.new(0, 5, -30) }

print("== A clean hit")
check(Combat.resolve(aModel, vModel, HIT) == "Hit", "hit")
check(near(vHum.Health, 190), "full damage")
check(Combat.isStunned(vModel) and vModel:GetAttribute("StunKind") == "Hit", "stunned")
check(not Combat.canAct(vModel), "can't act while stunned")
check(vHum.WalkSpeed == S.StunWalkSpeed, "slowed while stunned")
check(pushOn(vParts) ~= nil, "knocked back")
check(#interrupted == 1 and interrupted[1] == vModel, "Interrupted fired for the victim")
mock.advance(0.6)
check(not Combat.isStunned(vModel) and vHum.WalkSpeed == 16, "stun over: walk speed back")
check(Combat.canAct(vModel), "can act again")
settle()

print("== Blocking")
send(v, "Block", true)
check(vModel:GetAttribute("Blocking") == true, "F held: blocking")
check(vHum.WalkSpeed == S.BlockWalkSpeed, "slowed while blocking")
check(typeof(vModel:GetAttribute("ParryAt")) == "number", "the press opened a parry window")
check(not Combat.canAct(vModel), "can't cast while blocking")
mock.advance(S.ParryWindow + 0.05)
check(Combat.resolve(aModel, vModel, HIT) == "Blocked", "after the window: blocked")
check(near(vHum.Health, 200 - 10 * S.ChipDamage, 1e-3), "chip damage only")
check(near(Combat.guard(vModel), S.GuardMax - 20, 1e-3), "guard worn down by 2 x damage")
check(not Combat.isStunned(vModel), "no stun through a block")
check(#H.sent("Blocked", "server", H.remote) == 1, "Blocked broadcast")
send(v, "Block", false)
check(vModel:GetAttribute("Blocking") == false and vHum.WalkSpeed == 16, "let go: walk speed back")
settle()

print("== Guard break")
send(v, "Block", true)
mock.advance(S.ParryWindow + 0.05)
local outcome
for _ = 1, 10 do
	outcome = Combat.resolve(aModel, vModel, { Damage = 12 })
	if outcome == "GuardBroken" then
		break
	end
end
check(outcome == "GuardBroken", "the guard runs out and breaks")
check(Combat.isStunned(vModel) and vModel:GetAttribute("StunKind") == "GuardBreak", "guard break stun")
check(vModel:GetAttribute("Blocking") == false, "no longer blocking")
check(Combat.guard(vModel) == S.GuardMax, "guard reset")
check(#H.sent("GuardBroken", "server", H.remote) == 1, "GuardBroken broadcast")
settle()
send(v, "Block", true)
mock.advance(S.ParryWindow + 0.05)
check(
	Combat.resolve(aModel, vModel, { Damage = 1, GuardBreak = true }) == "GuardBroken",
	"a GuardBreak hit breaks it outright"
)
settle()

print("== Parry")
send(v, "Block", true)
mock.advance(0.1)
check(Combat.resolve(aModel, vModel, HIT) == "Parried", "inside the window: parried")
check(vHum.Health == 200, "the parrier takes nothing")
check(Combat.isStunned(aModel) and aModel:GetAttribute("StunKind") == "Parried", "the attacker staggers")
check(near(aModel:GetAttribute("StunnedUntil") - Combat.now(), S.ParriedStun, 0.02), "for ParriedStun")
local parried = H.sent("Parried", "server", H.remote)[1]
check(parried and parried.args[2] == vModel and parried.args[3] == aModel, "Parried broadcast (parrier, attacker)")
check(Combat.resolve(aModel, vModel, HIT) == "Parried", "a second hit straight after is parried too")
settle()

print("== Parries only cover the front")
vParts.HumanoidRootPart.CFrame = CFrame.new(0, 3, -4) -- facing -Z: away from A
send(v, "Block", true)
mock.advance(0.05)
check(Combat.resolve(aModel, vModel, HIT) == "Hit", "parry window open but facing away: hit")
vParts.HumanoidRootPart.CFrame = CFrame.new(0, 3, -4) * CFrame.fromEulerAnglesYXZ(0, math.pi, 0)
settle()

print("== No parry spamming")
send(v, "Block", true)
mock.advance(0.05)
send(v, "Block", false)
mock.advance(0.1)
send(v, "Block", true) -- again, inside ParryCooldown of a parry that caught nothing
check(vModel:GetAttribute("ParryAt") == nil, "the re-press only blocks")
check(Combat.resolve(aModel, vModel, HIT) == "Blocked", "so the hit is blocked, not parried")
send(v, "Block", false)
mock.advance(S.ParryCooldown)
send(v, "Block", true)
check(Combat.resolve(aModel, vModel, HIT) == "Parried", "after ParryCooldown the press parries again")
send(v, "Block", false)
mock.advance(0.05)
send(v, "Block", true)
check(typeof(vModel:GetAttribute("ParryAt")) == "number", "after a parry that landed, re-pressing parries at once")
settle()

print("== From above, parryable, blockable")
send(v, "Block", true)
mock.advance(0.05)
check(
	Combat.resolve(aModel, vModel, { Damage = 10, FromAbove = true }) == "Blocked",
	"from above: never parried, still blocked"
)
vParts.HumanoidRootPart.CFrame = CFrame.new(0, 3, -4)
check(
	Combat.resolve(aModel, vModel, { Damage = 10, FromAbove = true, Parryable = false }) == "Blocked",
	"from above: blocked even facing away"
)
vParts.HumanoidRootPart.CFrame = CFrame.new(0, 3, -4) * CFrame.fromEulerAnglesYXZ(0, math.pi, 0)
settle()
send(v, "Block", true)
mock.advance(0.05)
check(
	Combat.resolve(aModel, vModel, { Damage = 10, Parryable = false }) == "Blocked",
	"Parryable = false: blocked instead"
)
check(
	Combat.resolve(aModel, vModel, { Damage = 10, Blockable = false, Parryable = false }) == "Hit",
	"Blockable = false: through the guard"
)
settle()

print("== Counter stance and intangible")
Combat.setCounter(vModel, 0.5)
check(Combat.resolve(aModel, vModel, HIT) == "Countered", "a counter stance catches the hit")
check(vHum.Health == 200, "no damage")
check(
	#countered == 1 and countered[1].victim == vModel and countered[1].attacker == aModel,
	"Countered(victim, attacker)"
)
check(vModel:GetAttribute("CounterUntil") == nil, "the stance is used up")
check(Combat.resolve(aModel, vModel, HIT) == "Hit", "the next hit lands")
settle()
Combat.setCounter(vModel, 0.5)
check(Combat.resolve(aModel, vModel, { Damage = 5, Counterable = false }) == "Hit", "Counterable = false goes through")
settle()
Combat.setIntangible(vModel, 0.2)
check(Combat.resolve(aModel, vModel, HIT) == "Evaded", "intangible: evaded")
mock.advance(0.25)
check(Combat.resolve(aModel, vModel, HIT) == "Hit", "and then not")
settle()

print("== Busy")
Combat.setBusy(vModel)
send(v, "Block", true)
check(vModel:GetAttribute("Blocking") ~= true, "can't block mid-attack")
check(not Combat.canAct(vModel), "busy: can't act")
Combat.clearBusy(vModel)
check(Combat.canAct(vModel), "free again")
Combat.setBusy(vModel, 0.3)
Combat.stun(vModel, 0.2)
check(not Combat.isBusy(vModel), "a stun clears busy (the cast was cut short)")
settle()

print("== Stun while blocking, walk speed")
send(v, "Block", true)
mock.advance(S.ParryWindow + 0.05)
Combat.stun(vModel, 0.4, "Shock")
check(vModel:GetAttribute("Blocking") == false, "a stun drops the guard")
check(vHum.WalkSpeed == S.StunWalkSpeed, "stun speed")
mock.advance(0.5)
check(vHum.WalkSpeed == 16, "walk speed back to the original, not the block speed")
settle()

print("== Guard regeneration")
send(v, "Block", true)
mock.advance(S.ParryWindow + 0.05)
Combat.resolve(aModel, vModel, { Damage = 20 })
local worn = Combat.guard(vModel)
mock.advance(S.GuardRegenDelay * 0.5)
check(near(Combat.guard(vModel), worn, 1e-3), "no regen before GuardRegenDelay")
mock.advance(S.GuardRegenDelay)
check(Combat.guard(vModel) > worn, "regenerates after it")
mock.advance(5)
check(Combat.guard(vModel) == S.GuardMax, "back to full")
settle()

print("== The dead")
vHum.Health = 0
check(Combat.resolve(aModel, vModel, HIT) == "Immune", "a dead victim is immune")
heal()

print("== Resolved signal")
check(#resolved > 10, "Resolved fired for every hit")

H.finish("Combat server")
