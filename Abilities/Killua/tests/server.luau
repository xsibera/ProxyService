--!nocheck
-- Headless test of KilluaServer in the ability place's setup (with Combat and Loadout), against
-- Place1's mock engine. Run from this folder:  cd Abilities/Killua && luaurun tests/server.luau

local H = assert(loadfile("tests/harness.luau"))()
H.withCombatAndLoadout()
local mock, check, near = H.mock, H.check, H.near
local Config = require(H.Config)
local Combat = require(H.CombatModule)
local Loadout = require(H.LoadoutModule)

-- Killua at the origin facing -Z; D (an NPC) 5 studs in front facing him; B behind him
local kModel, kParts, kHum = H.character("Killua", 0, 0, 0)
local k = H.player("Killua", kModel)
k:SetAttribute("Loadout", table.concat(Loadout.Presets.Killua, ","))
local dModel, dParts, dHum = H.character("D", 0, -5, 180)
local bModel, _, bHum = H.character("B", 0, 6, 0)

local SSS = game:GetService("ServerScriptService")
local serverScript = mock.newInstance("Script", "KilluaServer")
rawget(serverScript, "__props").__path = "src/KilluaServer.server.luau"
serverScript.Parent = SSS
mock.runScript(serverScript)
mock.advance(0)

local onHit = {}
serverScript:FindFirstChild("OnHit").Event:Connect(function(attacker, victim, ability, damage, outcome)
	table.insert(onHit, { attacker = attacker, victim = victim, ability = ability, damage = damage, outcome = outcome })
end)
local announced = {}
Combat.Announced.Event:Connect(function(attacker, hitAt, ability, position)
	table.insert(announced, { attacker = attacker, hitAt = hitAt, ability = ability, position = position })
end)

local function send(...)
	H.remote.OnServerEvent:Fire(k, ...)
end
local function sent(kind)
	return H.sent(kind, "server", H.remote)
end
local function home()
	kParts.HumanoidRootPart.CFrame = CFrame.new(0, 3, 0)
	dParts.HumanoidRootPart.CFrame = CFrame.new(0, 3, -5) * CFrame.fromEulerAnglesYXZ(0, math.pi, 0)
end
-- every cooldown, stun and window over; everyone healed and back in place
local function settle()
	mock.advance(11)
	for _, model in ipairs({ kModel, dModel, bModel }) do
		Combat.setBlocking(model, false)
		model:SetAttribute("Guard", nil)
	end
	kModel:PivotTo(CFrame.new(0, 3, 0))
	dModel:PivotTo(CFrame.new(0, 3, -5) * CFrame.fromEulerAnglesYXZ(0, math.pi, 0))
	kHum.Health, dHum.Health, bHum.Health = 200, 200, 200
	table.clear(H.remoteLog)
	table.clear(onHit)
	table.clear(announced)
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
		if entry.args[1] == "Denied" and entry.to == k then
			table.insert(out, entry)
		end
	end
	return out
end

print("== Lightning Palm")
local P = Config.LightningPalm
local t0 = mock.now()
send("Cast", "LightningPalm", Vector3.new(0, 0, -1))
local palm = sent("Palm")[1]
check(palm and palm.to == "all" and palm.args[2] == k, "Palm broadcast")
check(palm and near(palm.args[3], t0 + P.HitDelay, 1e-6), "hitAt = now + HitDelay")
check(
	announced[1] and announced[1].attacker == kModel and announced[1].ability == "LightningPalm",
	"announced to Combat"
)
check(Combat.isBusy(kModel) and not Combat.canAct(kModel), "busy while it plays out")
mock.advance(P.HitDelay - 0.05)
check(dHum.Health == 200, "nothing before the Hit marker")
mock.advance(0.07)
check(near(dHum.Health, 200 - P.Damage), "D takes the palm")
check(Combat.isStunned(dModel) and dModel:GetAttribute("StunKind") == "Shock", "D is paralysed (Shock)")
check(near(dModel:GetAttribute("StunnedUntil") - Combat.now(), P.Paralyze, 0.05), "for Paralyze seconds")
check(bHum.Health == 200, "B (behind) is untouched")
local h = hitsOn(dModel)[1]
check(h and h.args[4] == "LightningPalm" and h.args[6] == "Hit" and h.args[7] == "Shock", "Hit broadcast")
check(#onHit == 1 and onHit[1].victim == dModel and onHit[1].damage == P.Damage, "OnHit fired")
send("Cast", "LightningPalm")
check(#denied() == 1 and denied()[1].args[3] == 0, "pressed again while busy: denied")
mock.advance(P.Recovery)
send("Cast", "LightningPalm")
local d = denied()[2]
check(d and near(d.args[3], P.Cooldown - (mock.now() - t0), 0.02), "after Recovery: denied with the cooldown left")
check(#sent("Palm") == 1, "no second palm")
send("Cast", "Thunderbolt")
check(#sent("Thunderbolt") == 1, "a different ability right after Recovery: fine")
settle()

print("== Lightning Palm into a block")
mock.advance(0.1)
Combat.setBlocking(dModel, true)
send("Cast", "LightningPalm")
mock.advance(P.HitDelay + 0.02)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Blocked", "Blocked")
check(near(Combat.guard(dModel), Combat.Settings.GuardMax - P.GuardDamage), "guard down by GuardDamage")
check(near(dHum.Health, 200 - P.Damage * Combat.Settings.ChipDamage, 1e-3), "chip damage only")
check(not Combat.isStunned(dModel), "no stun")
check(#onHit == 1 and onHit[1].outcome == "Blocked", "OnHit reports blocked hits too")
settle()

print("== Lightning Palm parried")
Combat.setBlocking(dModel, true)
send("Cast", "LightningPalm")
mock.advance(P.HitDelay - 0.15)
check(Combat.resolve(kModel, dModel, { Damage = 1 }) == "Blocked", "(F held, no fresh press yet: a block)")
dHum.Health = 200
Combat.openParry(dModel) -- F pressed 0.15 s before the palm
mock.advance(0.17)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Parried", "Parried")
check(dHum.Health == 200, "D takes nothing")
check(Combat.isStunned(kModel) and kModel:GetAttribute("StunKind") == "Parried", "Killua staggers")
check(#sent("Stop") == 1 and sent("Stop")[1].args[2] == k, "Stop broadcast (his cast is cut)")
check(#onHit == 0, "OnHit not fired for a parried hit")
settle()

print("== Interrupted mid-cast")
send("Cast", "LightningPalm")
mock.advance(0.1)
Combat.stun(kModel, 0.5, "Hit")
check(#sent("Stop") == 1, "stunned in the wind-up: Stop")
mock.advance(P.HitDelay)
check(dHum.Health == 200 and #hitsOn(dModel) == 0, "the palm never lands")
settle()

print("== Thunderbolt: lock-on")
local T = Config.Thunderbolt
t0 = mock.now()
send("Cast", "Thunderbolt", Vector3.new(0.2, -0.3, -1))
local tb = sent("Thunderbolt")[1]
local target = tb and tb.args[3]
check(target and near(target.X, 0, 1e-3) and near(target.Z, -5, 1e-3), "locked on to D")
check(target and near(target.Y, 0, 1e-3), "dropped onto the floor")
check(tb and near(tb.args[4], t0 + T.HitDelay, 1e-6), "strikeAt = now + HitDelay")
check(
	announced[1] and announced[1].ability == "Thunderbolt" and announced[1].position == target,
	"announced with where"
)
mock.advance(T.HitDelay - 0.05)
check(dHum.Health == 200, "nothing before the strike")
mock.advance(0.07)
check(near(dHum.Health, 200 - T.Damage), "D is struck")
check(dModel:GetAttribute("StunKind") == "Shock", "paralysed")
check(bHum.Health == 200, "B (6 behind Killua, 11 from the strike) is outside the radius")
settle()

print("== Thunderbolt: aim, range and the ring")
dModel:PivotTo(CFrame.new(40, 3, 0)) -- out of the way
send("Cast", "Thunderbolt", Vector3.new(1, 0, -1)) -- 45 degrees right of his facing: within MaxAimAngle
target = sent("Thunderbolt")[1].args[3]
local reach = T.Range * 0.75 / math.sqrt(2)
check(near(target.X, reach, 1e-3) and near(target.Z, -reach, 1e-3), "no one to lock on to: Range x 0.75 along the aim")
settle()
dModel:PivotTo(CFrame.new(40, 3, 0))
send("Cast", "Thunderbolt", Vector3.new(1, 0, 0)) -- 90 degrees off: beyond MaxAimAngle
target = sent("Thunderbolt")[1].args[3]
check(near(target.X, 0, 1e-3) and near(target.Z, -T.Range * 0.75, 1e-3), "aim too far off: straight ahead")
settle()
dModel:PivotTo(CFrame.new(0, 3, -5) * CFrame.fromEulerAnglesYXZ(0, math.pi, 0))
send("Cast", "Thunderbolt", Vector3.new(0, 0, -1))
mock.advance(T.HitDelay + 0.02)
check(near(kHum.Health, 200), "it never strikes Killua himself")
settle()

print("== Thunderbolt can't be parried, only blocked (from any side)")
dModel:PivotTo(CFrame.new(0, 3, -5)) -- facing away from Killua
Combat.setBlocking(dModel, true)
Combat.openParry(dModel)
send("Cast", "Thunderbolt", Vector3.new(0, 0, -1))
mock.advance(T.HitDelay + 0.02)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Blocked", "parry window open, facing away: still Blocked")
check(near(Combat.guard(dModel), Combat.Settings.GuardMax - T.GuardDamage), "a big bite out of the guard")
check(not Combat.isStunned(kModel), "Killua isn't staggered")
mock.advance(Combat.Settings.ParryWindow)
settle()
mock.advance(0.1)
Combat.setBlocking(dModel, true)
dModel:SetAttribute("Guard", 50)
send("Cast", "Thunderbolt", Vector3.new(0, 0, -1))
mock.advance(T.HitDelay + 0.02)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "GuardBroken", "a worn guard breaks")
settle()

print("== Whirlwind: the counter")
local W = Config.Whirlwind
send("Cast", "Whirlwind")
local stance = sent("Stance")[1]
check(stance and near(stance.args[3], mock.now() + W.Window, 1e-6), "Stance broadcast with when it ends")
check(kModel:GetAttribute("CounterUntil") ~= nil, "counter window open")
mock.advance(0.2)
local outcome = Combat.resolve(dModel, kModel, { Damage = 10, Stun = 0.5 })
check(outcome == "Countered", "D's hit is countered")
check(kHum.Health == 200, "Killua takes nothing")
local kRoot = kParts.HumanoidRootPart
check(near(kRoot.Position.Z, -5 - W.Behind, 1e-3) and near(kRoot.Position.X, 0, 1e-3), "Killua is behind D")
check(kRoot.CFrame.LookVector.Z > 0.99, "facing D's back")
local counterMsg = sent("Counter")[1]
check(counterMsg and counterMsg.args[3] == dModel, "Counter broadcast")
check(Combat.isStunned(dModel) and dModel:GetAttribute("StunKind") == "Countered", "D is caught")
check(Combat.resolve(dModel, kModel, { Damage = 10 }) == "Evaded", "Killua is untouchable during the flurry")
mock.advance(W.Length + 0.05)
local total = 0
for _, step in ipairs(W.Hits) do
	total += step.Damage
end
check(near(dHum.Health, 200 - total), "three hits land")
local flurry = hitsOn(dModel)
check(#flurry == 3 and flurry[3].args[7] == "Shock", "the last one shocks")
check(#sent("StanceEnd") == 0, "no StanceEnd (it was used)")
settle()

print("== Whirlwind: the flurry ignores blocks and parries")
send("Cast", "Whirlwind")
mock.advance(0.1)
Combat.resolve(dModel, kModel, { Damage = 10 })
-- D gets out of the Countered stun just in time to put up a guard and press F
dModel:SetAttribute("StunnedUntil", nil)
Combat.setBlocking(dModel, true)
Combat.openParry(dModel)
mock.advance(W.Length + 0.05)
check(near(dHum.Health, 200 - total), "every hit lands anyway")
check(not Combat.isStunned(kModel) or kModel:GetAttribute("StunKind") ~= "Parried", "Killua isn't parried")
settle()

print("== Whirlwind: a whiff leaves him open")
send("Cast", "Whirlwind")
mock.advance(W.Window + 0.02)
local whiff = sent("StanceEnd")[1]
check(whiff and whiff.args[3] == false, "StanceEnd (nothing caught)")
check(kModel:GetAttribute("CounterUntil") == nil, "window closed")
check(not Combat.canAct(kModel), "still open for WhiffRecovery")
check(Combat.resolve(dModel, kModel, { Damage = 10, Stun = 0.3 }) == "Hit", "and hittable")
settle()

print("== Whirlwind: far attackers (projectiles) are only evaded")
dModel:PivotTo(CFrame.new(0, 3, -(W.CounterRange + 10)) * CFrame.fromEulerAnglesYXZ(0, math.pi, 0))
send("Cast", "Whirlwind")
mock.advance(0.1)
check(Combat.resolve(dModel, kModel, { Damage = 10 }) == "Countered", "caught")
local ended = sent("StanceEnd")[1]
check(ended and ended.args[3] == true, "StanceEnd, evaded")
check(near(kRoot.Position.Z, 0, 1e-3), "Killua stays where he is")
mock.advance(W.Length)
check(dHum.Health == 200, "no flurry")
settle()

print("== Whirlwind: unblockable hits go through the stance")
send("Cast", "Whirlwind")
mock.advance(0.1)
check(Combat.resolve(dModel, kModel, { Damage = 10, Counterable = false }) == "Hit", "a Counterable = false hit lands")
check(#sent("Stop") == 1, "and cuts the stance")
check(kModel:GetAttribute("CounterUntil") == nil, "counter window gone")
mock.advance(W.Window)
check(#sent("StanceEnd") == 0, "no StanceEnd after a Stop")
settle()

print("== Lightning Dash: the triple dash")
local L = Config.LightningDash
local function dashTo(index, x, z)
	send("Dash", index, Vector3.new(x, 3, z))
	-- the client moved him there
	kModel:PivotTo(CFrame.new(x, 3, z))
end
local dashTotal = 0
for _, strike in ipairs(L.Strikes) do
	dashTotal += strike.Damage
end
dashTo(1, 0, -10)
check(#sent("Dash") == 1 and sent("Dash")[1].args[3] == 1, "dash 1")
check(
	announced[1]
		and announced[1].ability == "LightningDash"
		and near(announced[1].hitAt, mock.now() + L.Strikes[1].Delay),
	"its strike announced to Combat"
)
local dash1 = sent("Dash")[1]
check(dash1.args[4] == Vector3.new(0, 3, 0) and dash1.args[5] == Vector3.new(0, 3, -10), "from, to")
check(Combat.resolve(dModel, kModel, { Damage = 5 }) == "Evaded", "untouchable in the dash")
mock.advance(L.Strikes[1].Delay + 0.02)
check(near(dHum.Health, 200 - L.Strikes[1].Damage), "struck D on the way through")
mock.advance(L.MinGap)
dashTo(2, 0, 0)
mock.advance(L.Strikes[2].Delay + 0.02)
check(near(dHum.Health, 200 - L.Strikes[1].Damage - L.Strikes[2].Damage), "and back")
mock.advance(L.MinGap)
dashTo(3, 0, -10)
mock.advance(L.Strikes[3].Delay + 0.02)
check(near(dHum.Health, 200 - dashTotal), "and through again: the finisher")
check(dModel:GetAttribute("StunKind") == "Shock", "the finisher shocks")
check(#sent("Dash") == 3, "three dashes")
check(#onHit == 3, "OnHit for each")
mock.advance(L.MinGap)
dashTo(4, 0, 0)
check(#sent("Dash") == 3, "no fourth")
dashTo(1, 0, -10)
check(#sent("Dash") == 3 and denied()[1] and denied()[1].args[3] > L.Cooldown - 1, "a new chain waits for the cooldown")
settle()

print("== Lightning Dash: the chain's rules")
dModel:PivotTo(CFrame.new(40, 3, 0))
dashTo(1, 0, -10)
dashTo(2, 0, 0)
check(#sent("Dash") == 1, "too soon after the last (MinGap): ignored")
mock.advance(L.MinGap)
dashTo(3, 0, 0)
check(#sent("Dash") == 1, "skipping one: ignored")
mock.advance(L.ChainWindow + 0.1)
dashTo(2, 0, 0)
check(#sent("Dash") == 1, "after ChainWindow: the chain is over")
mock.advance(Config.SharedCooldown)
dashTo(1, 0, -10)
check(#sent("Dash") == 1 and denied()[1], "and on cooldown")
settle()

print("== Lightning Dash: checks on where the client went")
dModel:PivotTo(CFrame.new(40, 3, 0))
send("Dash", 1, Vector3.new(0, 3, -(L.Distance + L.Slack + 5)))
local no = H.sent("DashDenied", "server", H.remote)[1]
check(
	no and no.to == k and no.args[2] == 1 and no.args[3] == Vector3.new(0, 3, 0),
	"too far: DashDenied, back to the start"
)
check(#sent("Dash") == 0, "no dash broadcast")
settle()
dModel:PivotTo(CFrame.new(40, 3, 0))
send("Dash", 1, Vector3.new(0, 30, -5))
check(#H.sent("DashDenied", "server", H.remote) == 1, "too high: denied")
settle()
dModel:PivotTo(CFrame.new(40, 3, 0))
send("Dash", 1, Vector3.new(0 / 0, 3, -5))
send("Dash", 1, Vector3.new(math.huge, 3, -5))
check(#sent("Dash") == 0, "NaN / inf: denied")
settle()

print("== Lightning Dash: a parry ends it")
Combat.setBlocking(dModel, true)
Combat.openParry(dModel)
dashTo(1, 0, -10) -- through D, from in front of him
mock.advance(L.Strikes[1].Delay + 0.02)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Parried", "parried")
check(Combat.isStunned(kModel), "Killua staggers")
mock.advance(Combat.Settings.ParriedStun + 0.05)
dashTo(2, 0, 0)
check(#sent("Dash") == 1, "the chain is over")
dashTo(1, 0, 0)
check(#sent("Dash") == 1 and denied()[1], "and on cooldown")
settle()

print("== Lightning Dash: front, back - a mixup for a blocker")
mock.advance(0.1)
Combat.setBlocking(dModel, true)
mock.advance(Combat.Settings.ParryWindow)
dashTo(1, 0, -10) -- through D from the front
mock.advance(L.Strikes[1].Delay + 0.02)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Blocked", "coming from in front: blocked")
mock.advance(L.MinGap)
dashTo(2, 0, 0) -- and back through him from behind
mock.advance(L.Strikes[2].Delay + 0.02)
check(hitsOn(dModel)[2] and hitsOn(dModel)[2].args[6] == "Hit", "coming from behind: the block doesn't cover it")
settle()
-- D guards towards where Killua starts, 4 studs to the side of where he lands
dModel:PivotTo(CFrame.new(-10, 3, -4) * CFrame.fromEulerAnglesYXZ(0, -math.pi / 2, 0))
mock.advance(0.1)
Combat.setBlocking(dModel, true)
mock.advance(Combat.Settings.ParryWindow)
dashTo(1, -10, 0) -- lands beside him (not through him): the strike comes from where he lands
mock.advance(L.Strikes[1].Delay + 0.02)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Hit", "landing at someone's side: from the side")
settle()

print("== Gating")
k:SetAttribute("Loadout", table.concat(Loadout.Presets.Gon, ","))
send("Cast", "LightningPalm")
send("Dash", 1, Vector3.new(0, 3, -10))
check(#sent("Palm") == 0 and #sent("Dash") == 0 and #denied() == 0, "not equipped: nothing happens")
k:SetAttribute("Loadout", "Rock,LightningPalm,,")
send("Cast", "LightningPalm")
check(#sent("Palm") == 1, "equipped on any slot: works")
settle()
k:SetAttribute("Loadout", table.concat(Loadout.Presets.Killua, ","))
Combat.setBlocking(kModel, true)
send("Cast", "LightningPalm")
check(#sent("Palm") == 0 and denied()[1] and denied()[1].args[3] == 0, "blocking: denied")
Combat.setBlocking(kModel, false)
Combat.stun(kModel, 1, "Hit")
send("Cast", "Whirlwind")
check(#sent("Stance") == 0 and #denied() == 2, "stunned: denied")
settle()
send("Cast", "Explode")
send("Cast", 42)
send("Cast")
send("Dash", "1", Vector3.new(0, 3, -5))
send("Dash", 1.5, Vector3.new(0, 3, -5))
send("Dash", 1, "there")
send("Nonsense", 1, 2)
check(#H.remoteLog == 0, "bad requests: ignored")
kHum.Health = 0
send("Cast", "LightningPalm")
check(#sent("Palm") == 0, "dead: nothing")
settle()

print("== Players and teams")
local pModel, _, pHum = H.character("P", 0, -5, 180)
local p = H.player("P", pModel)
dModel:PivotTo(CFrame.new(40, 3, 0))
send("Cast", "LightningPalm")
mock.advance(P.HitDelay + 0.02)
check(near(pHum.Health, 200 - P.Damage), "another player is hit")
settle()
local team = mock.newInstance("Team", "Red")
k.Neutral, p.Neutral = false, false
k.Team, p.Team = team, team
pHum.Health = 200
send("Cast", "LightningPalm")
mock.advance(P.HitDelay + 0.02)
check(pHum.Health == 200, "a teammate isn't")
k.Neutral, p.Neutral = true, true
pModel.Parent = nil
settle()

print("== Death")
send("Cast", "Whirlwind")
mock.advance(0.1)
kHum.Health = 0
kHum.Died:Fire()
check(#sent("Stop") == 1, "dying: Stop")
check(kModel:GetAttribute("CounterUntil") == nil, "the stance is gone")

H.finish("Killua server")
