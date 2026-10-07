--!nocheck
-- Headless test of MeleeServer (the M1 string) with the stun system (Combat), against Place1's mock
-- engine. Run from this folder:  cd Abilities/Melee && luaurun tests/server.luau

local H = assert(loadfile("tests/harness.luau"))()
local mock, check, near = H.mock, H.check, H.near
local Config = require(H.Config)
local Combat = require(H.CombatModule)
local HITS = Config.Hits

-- A at the origin facing -Z; D (an NPC) 4 studs in front, facing A
local aModel, aParts, aHum = H.character("A", 0, 0, 0)
local a = H.player("A", aModel)
local dModel, dParts, dHum = H.character("D", 0, -4, 180)

local SSS = game:GetService("ServerScriptService")
local serverScript = mock.newInstance("Script", "MeleeServer")
rawget(serverScript, "__props").__path = "src/MeleeServer.server.luau"
serverScript.Parent = SSS
mock.runScript(serverScript)
mock.advance(0)

local onHit = {}
serverScript:FindFirstChild("OnHit").Event:Connect(function(attacker, victim, index, damage, outcome)
	table.insert(onHit, { attacker = attacker, victim = victim, index = index, damage = damage, outcome = outcome })
end)
local announced = {}
Combat.Announced.Event:Connect(function(attacker, hitAt, ability)
	table.insert(announced, { attacker = attacker, hitAt = hitAt, ability = ability })
end)

local function m1()
	H.remote.OnServerEvent:Fire(a, "M1")
end
local function sent(kind)
	return H.sent(kind, "server", H.remote)
end
local function lastM1()
	local list = sent("M1")
	return list[#list]
end
local function hitsOn(victim)
	local out = {}
	for _, entry in ipairs(sent("Hit")) do
		if entry.args[3] == victim then
			table.insert(out, entry)
		end
	end
	return out
end
local function denied()
	local out = {}
	for _, entry in ipairs(H.remoteLog) do
		if entry.args[1] == "Denied" and entry.to == a then
			table.insert(out, entry)
		end
	end
	return out
end
local function pushOn(parts)
	for _, d in ipairs(parts.HumanoidRootPart:GetDescendants()) do
		if d.ClassName == "LinearVelocity" then
			return d.VectorVelocity
		end
	end
	return nil
end
local function settle()
	mock.advance(3)
	for _, model in ipairs({ aModel, dModel }) do
		Combat.setBlocking(model, false)
		model:SetAttribute("Guard", nil)
	end
	aModel:PivotTo(CFrame.new(0, 3, 0))
	dModel:PivotTo(CFrame.new(0, 3, -4) * CFrame.fromEulerAnglesYXZ(0, math.pi, 0))
	aHum.Health, dHum.Health = 200, 200
	table.clear(H.remoteLog)
	table.clear(onHit)
	table.clear(announced)
end
-- throw the whole string, each hit as soon as it opens; returns the server times each hit landed
local function string(upTo)
	local landed = {}
	for i = 1, upTo or #HITS do
		m1()
		local hit = HITS[i]
		mock.advance(hit.HitDelay + 0.01)
		landed[i] = Combat.now()
		if hit.Next then
			mock.advance(hit.Next - hit.HitDelay - 0.01 + 0.02)
		end
	end
	return landed
end

print("== The first hit")
local t0 = Combat.now()
m1()
local first = lastM1()
check(first and first.to == "all" and first.args[2] == a and first.args[3] == 1, "M1 broadcast: hit 1")
check(first and near(first.args[4], t0, 1e-6), "with the server time it was thrown")
check(
	announced[1] and announced[1].ability == "M1" and near(announced[1].hitAt, t0 + HITS[1].HitDelay),
	"announced to Combat"
)
check(
	Combat.isBusy(aModel) and aModel:GetAttribute("MeleeUntil") == aModel:GetAttribute("BusyUntil"),
	"busy with the string"
)
check(aHum.WalkSpeed == Config.AttackWalkSpeed, "slowed while swinging")
mock.advance(HITS[1].HitDelay - 0.05)
check(dHum.Health == 200, "nothing before the Hit marker")
mock.advance(0.07)
check(near(dHum.Health, 200 - HITS[1].Damage), "the jab lands")
check(Combat.isStunned(dModel) and dModel:GetAttribute("StunKind") == "Hit", "D is stunned")
check(near(dModel:GetAttribute("StunnedUntil") - Combat.now(), HITS[1].Stun, 0.05), "for the hit's Stun")
local push = pushOn(dParts)
check(push and near(push.Z, -Config.Push, 0.01), "a small push back")
local h = hitsOn(dModel)[1]
check(h and h.args[4] == 1 and h.args[6] == "Hit", "Hit broadcast (index, outcome)")
check(#onHit == 1 and onHit[1].damage == HITS[1].Damage, "OnHit fired")
m1()
check(#sent("M1") == 1 and denied()[1] and denied()[1].args[2] == 1, "too soon for the next: denied (the server has 1)")
mock.advance(HITS[1].Next - HITS[1].HitDelay - 0.02 + 0.02)
m1()
check(lastM1().args[3] == 2, "at Next: hit 2")
settle()

print("== The whole string is a true combo")
local landed = string()
check(#sent("M1") == #HITS, "five hits thrown")
for i, entry in ipairs(sent("M1")) do
	check(entry.args[3] == i, "hit " .. i .. " in order")
end
local total = 0
for _, hit in ipairs(HITS) do
	total += hit.Damage
end
check(near(dHum.Health, 200 - total), "every hit landed (" .. 200 - dHum.Health .. " damage)")
check(#hitsOn(dModel) == #HITS, "five Hit broadcasts")
-- stunned from the first hit to the last without a gap
settle()
local gaps = 0
m1()
mock.advance(HITS[1].HitDelay + 0.01)
local index = 1
local nextAt = Combat.now() + HITS[1].Next - HITS[1].HitDelay
local finished = false
for _ = 1, 400 do
	if Combat.now() >= nextAt and index < #HITS then
		m1()
		index += 1
		local hit = HITS[index]
		nextAt = Combat.now() + (hit.Next or 99)
		if index == #HITS then
			task.delay(hit.HitDelay + 0.01, function()
				finished = true
			end)
		end
	end
	if finished then
		break
	end
	if not Combat.isStunned(dModel) then
		gaps += 1
	end
	mock.advance(1 / 60)
end
check(finished and gaps == 0, "never out of stun between hits (" .. gaps .. " frames free)")
local last = hitsOn(dModel)[#HITS]
check(last and last.args[4] == #HITS, "the finisher landed")
push = pushOn(dParts)
check(push and push.Z < -HITS[5].Knockback + 1 and push.Y > HITS[5].Lift - 1, "the finisher knocks them away (and up)")
settle()

print("== After the finisher")
string()
m1()
check(#sent("M1") == #HITS, "straight after: denied")
local wait = denied()[1] and denied()[1].args[2]
check(wait == #HITS, "(the server still has the full string)")
mock.advance(Config.FinisherCooldown)
m1()
check(lastM1().args[3] == 1, "after FinisherCooldown: a new string from hit 1")
settle()

print("== Too slow: the string starts over")
m1()
mock.advance(HITS[1].Next + Config.ComboWindow + 0.2)
m1()
check(lastM1().args[3] == 1, "late: hit 1 again")
mock.advance(HITS[1].Next + 0.05)
m1()
check(lastM1().args[3] == 2, "in time: hit 2")
settle()

print("== Blocked and parried")
mock.advance(0.1)
Combat.setBlocking(dModel, true)
mock.advance(Combat.Settings.ParryWindow)
m1()
mock.advance(HITS[1].HitDelay + 0.02)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Blocked", "into a block: Blocked")
check(near(dHum.Health, 200 - HITS[1].Damage * Combat.Settings.ChipDamage, 1e-3), "chip damage only")
check(not Combat.isStunned(dModel), "no stun through a block")
settle()
Combat.setBlocking(dModel, true)
m1()
mock.advance(HITS[1].HitDelay - 0.1)
Combat.openParry(dModel)
mock.advance(0.12)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Parried", "timed F: Parried")
check(Combat.isStunned(aModel) and aModel:GetAttribute("StunKind") == "Parried", "A staggers")
check(#sent("Stop") == 1 and sent("Stop")[1].args[2] == a, "Stop broadcast: the string is cut")
m1()
check(#sent("M1") == 1, "no swinging while staggered")
mock.advance(Combat.Settings.ParriedStun + 0.05)
m1()
check(lastM1().args[3] == 1, "after the stagger: a new string from hit 1")
settle()

print("== Hit mid-swing")
m1()
mock.advance(0.1)
Combat.resolve(dModel, aModel, { Damage = 5, Stun = 0.5 })
check(aHum.WalkSpeed == Combat.Settings.StunWalkSpeed, "stunned: the stun's walk speed")
mock.advance(HITS[1].HitDelay)
check(dHum.Health == 200, "the swing never lands")
mock.advance(0.5)
check(aHum.WalkSpeed == 16, "walk speed back after the stun")
settle()

print("== Busy with something else")
aModel:SetAttribute("BusyUntil", Combat.now() + 5) -- say, charging Jajanken
m1()
check(#sent("M1") == 0 and #denied() == 1, "denied")
aModel:SetAttribute("BusyUntil", nil)
Combat.setBlocking(aModel, true)
m1()
check(#sent("M1") == 0, "blocking: denied")
Combat.setBlocking(aModel, false)
settle()

print("== Walk speed comes back")
m1()
mock.advance(HITS[1].Next + 0.25)
check(aHum.WalkSpeed == 16, "stopped swinging: full walk speed")
settle()
string()
mock.advance(Config.FinisherRecovery + 0.25)
check(aHum.WalkSpeed == 16, "after the finisher too")
settle()

print("== Out of reach, players and teams")
dModel:PivotTo(CFrame.new(0, 3, -12) * CFrame.fromEulerAnglesYXZ(0, math.pi, 0))
m1()
mock.advance(HITS[1].HitDelay + 0.02)
check(dHum.Health == 200 and #sent("Hit") == 0, "too far: a miss")
settle()
dModel:PivotTo(CFrame.new(0, 3, 4)) -- behind A
m1()
mock.advance(HITS[1].HitDelay + 0.02)
check(dHum.Health == 200, "behind: a miss")
settle()
local pModel, _, pHum = H.character("P", 0, -4, 180)
local p = H.player("P", pModel)
dModel:PivotTo(CFrame.new(40, 3, 0))
m1()
mock.advance(HITS[1].HitDelay + 0.02)
check(near(pHum.Health, 200 - HITS[1].Damage), "another player is hit")
settle()
local team = mock.newInstance("Team", "Red")
a.Neutral, p.Neutral = false, false
a.Team, p.Team = team, team
pHum.Health = 200
dModel:PivotTo(CFrame.new(40, 3, 0))
m1()
mock.advance(HITS[1].HitDelay + 0.02)
check(pHum.Health == 200, "a teammate isn't")
a.Neutral, p.Neutral = true, true
pModel.Parent = nil
settle()

print("== Bad input and death")
H.remote.OnServerEvent:Fire(a, "Explode")
H.remote.OnServerEvent:Fire(a, 42)
H.remote.OnServerEvent:Fire(a)
check(#H.remoteLog == 0, "ignored")
m1()
mock.advance(0.1)
aHum.Health = 0 -- (the mock fires Died)
check(#sent("Stop") == 1, "dying mid-swing: Stop")
mock.advance(HITS[1].HitDelay)
check(dHum.Health == 200, "the swing never lands")
_ = aParts

H.finish("Melee server")
