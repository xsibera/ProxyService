--!nocheck
-- Headless test of BrawlerServer in the ability place's setup (with Combat and Loadout), against
-- Place1's mock engine: every strike's timing, hit box, damage, stun and knockback, the rules (the
-- axe kick and slam from above, grabs beating blocks), and the grabs - connecting, holding both still,
-- the slam on the path's clock, letting go where the path ends, whiffs, being cut short, and the victim
-- dying mid-throw. Run from this folder:  cd Abilities/Brawler && luaurun tests/server.luau

local H = assert(loadfile("tests/harness.luau"))()
local mock, check, near = H.mock, H.check, H.near
local Config = require(H.Config)
local GrabPaths = require(H.GrabPaths)
local Combat = require(H.CombatModule)
local Loadout = require(H.LoadoutModule)

-- the Brawler at the origin facing -Z; D (an NPC) 3 studs in front, facing him; E off to his left; F far
local bModel, bParts, bHum = H.character("Brawler", 0, 0, 0)
local b = H.player("Brawler", bModel)
local dModel, dParts, dHum = H.character("D", 0, -3, 180)
local eModel, _, eHum = H.character("E", -7, -2, 90)
local fModel, _, fHum = H.character("F", 0, -40, 180)

local SSS = game:GetService("ServerScriptService")
local serverScript = mock.newInstance("Script", "BrawlerServer")
rawget(serverScript, "__props").__path = "src/BrawlerServer.server.luau"
serverScript.Parent = SSS
mock.runScript(serverScript)
mock.advance(0)

local onHit = {}
serverScript:FindFirstChild("OnHit").Event:Connect(function(attacker, victim, ability, damage, outcome)
	table.insert(onHit, { attacker = attacker, victim = victim, ability = ability, damage = damage, outcome = outcome })
end)

local AHEAD = Vector3.new(0, 0, -1)
local bRoot, dRoot = bParts.HumanoidRootPart, dParts.HumanoidRootPart
local function preset(name)
	b:SetAttribute("Loadout", table.concat(Loadout.Presets[name], ","))
end
local function send(...)
	H.remote.OnServerEvent:Fire(b, ...)
end
local function sent(kind)
	return H.sent(kind, "server", H.remote)
end
local function face(model, x, z, yaw)
	model:PivotTo(CFrame.new(x, 3, z) * CFrame.fromEulerAnglesYXZ(0, math.rad(yaw), 0))
end
-- every cooldown, stun and window over; everyone healed and back in place
local function settle()
	mock.advance(13)
	for _, model in ipairs({ bModel, dModel, eModel, fModel }) do
		Combat.setBlocking(model, false)
		model:SetAttribute("Guard", nil)
		model:SetAttribute("StunnedUntil", nil)
		model:SetAttribute("StunKind", nil)
		model.HumanoidRootPart.Anchored = false
	end
	face(bModel, 0, 0, 0)
	face(dModel, 0, -3, 180)
	face(eModel, -7, -2, 90)
	face(fModel, 0, -40, 180)
	bHum.Health, dHum.Health, eHum.Health, fHum.Health = 200, 200, 200, 200
	bHum.WalkSpeed = 16
	table.clear(H.remoteLog)
	table.clear(onHit)
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
local function knockOf(victim) -- the velocity of the push on a victim, if one is running
	local a = victim.HumanoidRootPart:FindFirstChild("CombatKnockback")
	local lv = a and a:FindFirstChildOfClass("LinearVelocity")
	return lv and lv.VectorVelocity
end

preset("Striker")

print("== Haymaker")
local HM = Config.Haymaker
local t0 = mock.now()
send("Cast", "Haymaker", AHEAD)
local s1 = sent("Strike")[1]
check(
	s1 and s1.args[2] == b and s1.args[3] == "Haymaker" and near(s1.args[4], t0 + HM.HitDelay, 1e-6),
	"Strike broadcast"
)
check(Combat.isBusy(bModel), "busy")
check(bHum.WalkSpeed == Config.MoveWalkSpeed, "slowed while it plays out")
mock.advance(HM.HitDelay - 0.03)
check(dHum.Health == 200, "nothing before the Hit marker")
mock.advance(0.05)
check(near(dHum.Health, 200 - HM.Damage), "D takes the hook")
check(Combat.isStunned(dModel) and near(dModel:GetAttribute("StunnedUntil") - Combat.now(), HM.Stun, 0.05), "stunned")
local k = knockOf(dModel)
check(k and k.Z < -HM.Knockback * 0.9 and k.Y > 0, "knocked away from him")
check(eHum.Health == 200 and fHum.Health == 200, "nobody else")
check(#onHit == 1 and onHit[1].damage == HM.Damage, "OnHit")
send("Cast", "Uppercut", AHEAD)
check(#sent("Strike") == 1, "another move while busy: denied")
mock.advance(HM.Recovery)
check(bHum.WalkSpeed == 16, "walk speed back after Recovery")
settle()

print("== Haymaker: blocked and parried")
Combat.setBlocking(dModel, true)
send("Cast", "Haymaker", AHEAD)
mock.advance(HM.HitDelay + 0.02)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Blocked", "blocked facing him")
check(near(Combat.guard(dModel), Combat.Settings.GuardMax - HM.GuardDamage), "GuardDamage")
settle()
Combat.setBlocking(dModel, true)
send("Cast", "Haymaker", AHEAD)
mock.advance(HM.HitDelay - 0.15)
Combat.openParry(dModel)
mock.advance(0.17)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Parried", "parried")
check(Combat.isStunned(bModel) and #sent("Stop") == 1, "he staggers: Stop")
check(bHum.WalkSpeed == Combat.Settings.StunWalkSpeed, "stun-slowed")
mock.advance(Combat.Settings.ParriedStun + 0.05)
check(bHum.WalkSpeed == 16, "then his own walk speed back (not the move's)")
settle()

print("== Uppercut")
local UC = Config.Uppercut
send("Cast", "Uppercut", AHEAD)
mock.advance(UC.HitDelay + 0.02)
k = knockOf(dModel)
check(near(dHum.Health, 200 - UC.Damage) and dModel:GetAttribute("StunKind") == "Launch", "a launch")
check(k and k.Y >= UC.Lift - 1e-3 and k.Y > math.abs(k.Z), "straight up")
settle()

print("== Roundhouse")
local RH = Config.Roundhouse
face(dModel, 2.5, -3, 180) -- a little off to his right: the wide box still has him
send("Cast", "Roundhouse", AHEAD)
mock.advance(RH.HitDelay + 0.02)
k = knockOf(dModel)
check(near(dHum.Health, 200 - RH.Damage), "the kick lands wide")
check(k and k.X < -RH.Knockback * 0.9, "swept off to his left (the way the leg goes)")
settle()

print("== Axe Kick: from above")
local AX = Config.AxeKick
face(dModel, 0, -3, 0) -- facing away, blocking
Combat.setBlocking(dModel, true)
send("Cast", "AxeKick", AHEAD)
mock.advance(AX.HitDelay - 0.12)
Combat.openParry(dModel)
mock.advance(0.14)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Blocked", "blocked facing away, and never parried")
check(near(Combat.guard(dModel), Combat.Settings.GuardMax - AX.GuardDamage), "it takes most of a guard")
settle()
send("Cast", "AxeKick", AHEAD)
mock.advance(AX.HitDelay + 0.02)
check(near(dHum.Health, 200 - AX.Damage), "clean: Damage")
settle()

print("== Ground Slam")
preset("Grappler")
local GS = Config.GroundSlam
send("Cast", "GroundSlam", AHEAD)
mock.advance(GS.HitDelay - 0.03)
check(dHum.Health == 200 and eHum.Health == 200, "nothing before he lands")
mock.advance(0.05)
check(near(dHum.Health, 200 - GS.Damage) and near(eHum.Health, 200 - GS.Damage), "everyone round him")
check(fHum.Health == 200, "not F, far off")
check(dModel:GetAttribute("StunKind") == "Launch" and eModel:GetAttribute("StunKind") == "Launch", "launched")
local ke = knockOf(eModel)
check(ke and ke.X < 0 and ke.Y > 0, "out from him (E to his left goes left)")
settle()

print("== Suplex: grabs beat blocks")
local SP, path = Config.Suplex, GrabPaths.Suplex
Combat.setBlocking(dModel, true)
t0 = mock.now()
send("Cast", "Suplex", AHEAD)
check(sent("Strike")[1] and sent("Strike")[1].args[3] == "Suplex", "the reach")
mock.advance(Config.Grab.At + 0.01)
local g = sent("Grabbed")[1]
check(g and g.args[2] == b and g.args[3] == dModel and g.args[4] == "Suplex", "Grabbed broadcast, blocking or not")
local origin = g and g.args[5]
local startAt = g and g.args[6]
check(startAt and near(startAt, t0 + Config.Grab.At + Config.Grab.Lead, 0.02), "the throw starts Lead later")
check(dModel:GetAttribute("StunKind") == "Grabbed" and Combat.isStunned(dModel), "D is held (stunned: Grabbed)")
check(bRoot.Anchored and dRoot.Anchored, "both held still (anchored)")
local start = origin * CFrame.new(table.unpack(path.Frames[1]))
check((dRoot.Position - start.Position).Magnitude < 1e-3, "D placed at the start of the path")
check(dRoot.CFrame.LookVector:Dot(-origin.LookVector) > 0.99, "facing him")
check(dHum.Health == 200, "no damage from the grab itself")
check(#onHit == 0, "and no OnHit for it")
mock.advance(startAt + path.Hit - mock.now() - 0.03)
check(dHum.Health == 200, "nothing before the slam")
mock.advance(0.05)
check(near(dHum.Health, 200 - SP.Damage), "the slam: Damage")
check(dModel:GetAttribute("StunKind") == "Knockdown", "knocked down")
check(
	near(dModel:GetAttribute("StunnedUntil"), startAt + path.Release + Config.Grab.GetUp, 0.05),
	"down until they're back up (Release + GetUp)"
)
check(dRoot.Anchored, "still held until Release")
mock.advance(startAt + path.Release - mock.now() + 0.02)
local rel = sent("Released")[1]
check(rel and rel.args[3] == dModel and rel.args[6] == false, "Released broadcast")
check(not dRoot.Anchored, "let go")
local landed = rel and rel.args[5]
local expect = origin * CFrame.new(table.unpack(path.Frames[#path.Frames]))
check(landed and (Vector3.new(landed.X - expect.X, 0, landed.Z - expect.Z)).Magnitude < 0.05, "where the path ends")
check(landed and landed.Position.Z > origin.Position.Z + 2, "behind him")
check(
	landed and landed.UpVector.Y > 0.999 and landed.Y >= origin.Y - 1e-3,
	"standing upright (the get up lies them down)"
)
check(bRoot.Anchored, "he's still finishing")
mock.advance(startAt + path.Length - mock.now() + 0.02)
check(not bRoot.Anchored, "and is let go at the end of his clip")
settle()

print("== Chokeslam")
local CS = Config.Chokeslam
path = GrabPaths.Chokeslam
send("Cast", "Chokeslam", AHEAD)
mock.advance(Config.Grab.At + 0.01)
g = sent("Grabbed")[1]
startAt = g.args[6]
mock.advance(startAt + path.Release - mock.now() + 0.02)
check(near(dHum.Health, 200 - CS.Damage), "Damage")
rel = sent("Released")[1]
check(rel and rel.args[5].Position.Z < -2, "slammed down in front of him")
settle()

print("== Grab & Throw")
local GT = Config.GrabThrow
path = GrabPaths.Throw
send("Cast", "GrabThrow", AHEAD)
mock.advance(Config.Grab.At + 0.01)
g = sent("Grabbed")[1]
startAt = g.args[6]
mock.advance(startAt + path.Release - mock.now() - 0.03)
check(dRoot.Anchored and dHum.Health == 200, "held until he lets go")
mock.advance(0.05)
check(not dRoot.Anchored, "let go...")
check(near(dHum.Health, 200 - GT.Damage) and dModel:GetAttribute("StunKind") == "Launch", "...and hurled")
k = knockOf(dModel)
local toss = g.args[5]:VectorToWorldSpace(path.Toss)
check(k and Vector3.new(k.X, 0, k.Z).Unit:Dot(toss) > 0.99 and k.Y > 0, "the way the swing carries them")
settle()

print("== Whiffs")
face(dModel, 0, -12, 180)
send("Cast", "Suplex", AHEAD)
mock.advance(Config.Grab.At + 0.01)
check(#sent("Whiff") == 1 and #sent("Grabbed") == 0, "nobody in reach: Whiff")
check(not bRoot.Anchored and Combat.isBusy(bModel), "open for the whiff recovery")
settle()
Combat.setIntangible(dModel, 1) -- rolling through it
send("Cast", "Suplex", AHEAD)
mock.advance(Config.Grab.At + 0.01)
check(#sent("Whiff") == 1 and not dRoot.Anchored, "a roll goes through a grab")
settle()

print("== Cut short")
send("Cast", "Suplex", AHEAD)
mock.advance(Config.Grab.At + 0.01)
g = sent("Grabbed")[1]
mock.advance(0.3)
Combat.stun(bModel, 0.5, "Hit") -- someone hits him mid-throw
rel = sent("Released")[1]
check(rel and rel.args[6] == true, "dropped at once (early)")
check(not dRoot.Anchored and not bRoot.Anchored, "both free")
check(dModel:GetAttribute("StunKind") == "Hit", "D gets a moment to find their feet")
check(dHum.Health == 200, "no slam")
mock.advance(2)
check(dHum.Health == 200, "not later either")
check(
	rel and rel.args[5].UpVector.Y > 0.999 and rel.args[5].Y >= g.args[5].Y - 1e-3,
	"dropped upright, not under the floor"
)
settle()
send("Cast", "Suplex", AHEAD)
mock.advance(Config.Grab.At + 0.01)
mock.advance(0.2)
dHum.Health = 0 -- killed by someone else while held
mock.advance(0.05)
check(sent("Released")[1] ~= nil and not bRoot.Anchored, "a victim who dies is let go")
settle()

print("== One at a time")
local cModel = H.character("C", 0, -6, 0) -- another grabber, behind D
local c = H.player("C", cModel)
c:SetAttribute("Loadout", table.concat(Loadout.Presets.Grappler, ","))
send("Cast", "Suplex", AHEAD)
mock.advance(Config.Grab.At + 0.01)
H.remote.OnServerEvent:Fire(c, "Cast", "Suplex", Vector3.new(0, 0, 1))
mock.advance(Config.Grab.At + 0.01)
check(#sent("Grabbed") == 1, "someone already held can't be grabbed again")
send("Cast", "Chokeslam", AHEAD)
check(#sent("Strike") == 2, "and he can't start another move while holding someone")
settle()
cModel:Destroy()

print("== The rules")
b:SetAttribute("Loadout", "Haymaker,,,")
send("Cast", "Suplex", AHEAD)
check(#sent("Strike") == 0, "not equipped: nothing")
send("Cast", "Fly")
send("Cast", nil)
send("Cast", "Config")
send("Kick")
check(#H.remoteLog == 0, "bad input ignored")
bHum.Health = 0
send("Cast", "Haymaker", AHEAD)
check(#sent("Strike") == 0, "dead: nothing")

H.finish("Brawler server")
