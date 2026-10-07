--!nocheck
-- Headless test of LeorioServer in the ability place's setup (with Combat and Loadout), against
-- Place1's mock engine: where the warp holes open, when the blows land, that they come from the
-- holes (blocks and parries face the hole, not him), the barrage chasing its target round, the
-- burst's launch, interrupts, cooldowns and the loadout. Run from this folder:
--   cd Abilities/Leorio && luaurun tests/server.luau

local H = assert(loadfile("tests/harness.luau"))()
H.withCombatAndLoadout()
local mock, check, near = H.mock, H.check, H.near
local Config = require(H.Config)
local Combat = require(H.CombatModule)
local Loadout = require(H.LoadoutModule)

-- Leorio at the origin facing -Z; D (an NPC) 15 studs in front, facing him; B off to the side, far
local lModel, lParts, lHum = H.character("Leorio", 0, 0, 0)
local l = H.player("Leorio", lModel)
l:SetAttribute("Loadout", table.concat(Loadout.Presets.Leorio, ","))
local dModel, dParts, dHum = H.character("D", 0, -15, 180)
local bModel, _, bHum = H.character("B", 60, 0, 0)

local SSS = game:GetService("ServerScriptService")
local serverScript = mock.newInstance("Script", "LeorioServer")
rawget(serverScript, "__props").__path = "src/LeorioServer.server.luau"
serverScript.Parent = SSS
mock.runScript(serverScript)
mock.advance(0)

local onHit = {}
serverScript:FindFirstChild("OnHit").Event:Connect(function(attacker, victim, ability, damage, outcome)
	table.insert(onHit, { attacker = attacker, victim = victim, ability = ability, damage = damage, outcome = outcome })
end)
local announced = {}
Combat.Announced.Event:Connect(function(attacker, hitAt, ability, position, from)
	table.insert(announced, { attacker = attacker, hitAt = hitAt, ability = ability, position = position, from = from })
end)

local AHEAD = Vector3.new(0, 0, -1)
local function send(...)
	H.remote.OnServerEvent:Fire(l, ...)
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
	for _, model in ipairs({ lModel, dModel, bModel }) do
		Combat.setBlocking(model, false)
		model:SetAttribute("Guard", nil)
		model:SetAttribute("StunnedUntil", nil)
	end
	face(lModel, 0, 0, 0)
	face(dModel, 0, -15, 180)
	face(bModel, 60, 0, 0)
	lHum.Health, dHum.Health, bHum.Health = 200, 200, 200
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
		if entry.args[1] == "Denied" and entry.to == l then
			table.insert(out, entry)
		end
	end
	return out
end
local function flatAngle(a, b) -- degrees between two horizontal directions
	local fa, fb = Vector3.new(a.X, 0, a.Z).Unit, Vector3.new(b.X, 0, b.Z).Unit
	return math.deg(math.acos(math.clamp(fa:Dot(fb), -1, 1)))
end

local dRoot = dParts.HumanoidRootPart

print("== Warp Punch: the hole beside the target")
local W = Config.WarpPunch
local t0 = mock.now()
send("Cast", "WarpPunch", AHEAD)
local wp = sent("WarpPunch")[1]
check(wp and wp.to == "all" and wp.args[2] == l, "WarpPunch broadcast")
local hole = wp and wp.args[3]
check(typeof(hole) == "CFrame", "with the hole's CFrame")
check(near(wp.args[4], t0 + W.PunchAt, 1e-6) and near(wp.args[5], t0 + W.HitDelay, 1e-6), "punchAt, hitAt")
local off = hole.Position - dRoot.Position
check(near(Vector3.new(off.X, 0, off.Z).Magnitude, W.Distance, 1e-3), "Distance from D")
check(near(off.Y, W.Height, 1e-3), "at head height")
check(
	near(flatAngle(off, lParts.HumanoidRootPart.Position - dRoot.Position), W.Side, 0.5),
	"Side degrees round from the line to him"
)
check(off.X > 0, "on his right (the punching hand's side)")
check(hole.LookVector:Dot((dRoot.Position - hole.Position).Unit) > 0.95, "facing D")
local a = announced[1]
check(a and a.ability == "WarpPunch" and near(a.hitAt, t0 + W.HitDelay, 1e-6), "announced for hitAt")
check(a and a.position == dRoot.Position and a.from == hole.Position, "with where it lands and where it comes from")
check(Combat.isBusy(lModel) and not Combat.canAct(lModel), "busy while it plays out")
mock.advance(W.HitDelay - 0.03)
check(dHum.Health == 200, "nothing before the Warp marker")
mock.advance(0.05)
check(near(dHum.Health, 200 - W.Damage), "the blow lands out of the hole")
check(
	Combat.isStunned(dModel) and near(dModel:GetAttribute("StunnedUntil") - Combat.now(), W.Stun, 0.05),
	"D is stunned"
)
local h = hitsOn(dModel)[1]
check(h and h.args[4] == "WarpPunch" and h.args[6] == "Hit", "Hit broadcast")
check(h and h.args[7]:Dot(hole.LookVector) > 0.5, "knocked away from the hole")
check(#onHit == 1 and onHit[1].damage == W.Damage, "OnHit fired")
check(bHum.Health == 200, "B untouched")
send("Cast", "WarpPunch", AHEAD)
check(#sent("WarpPunch") == 1 and #denied() == 1, "again at once: denied")
settle()

print("== Warp Punch: block and parry face the hole")
Combat.setBlocking(dModel, true) -- facing him: the hole is 60 deg round, inside the block's arc
send("Cast", "WarpPunch", AHEAD)
mock.advance(W.HitDelay + 0.02)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Blocked", "facing him (and so the hole): blocked")
check(near(Combat.guard(dModel), Combat.Settings.GuardMax - W.GuardDamage), "GuardDamage off the guard")
settle()
face(dModel, 0, -15, 0) -- turned away from him (and the hole)
Combat.setBlocking(dModel, true)
send("Cast", "WarpPunch", AHEAD)
mock.advance(W.HitDelay + 0.02)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Hit", "blocking the wrong way: it lands")
settle()
Combat.setBlocking(dModel, true)
send("Cast", "WarpPunch", AHEAD)
mock.advance(W.HitDelay - 0.15)
Combat.openParry(dModel)
mock.advance(0.17)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Parried", "a timed F parries the fist")
check(Combat.isStunned(lModel) and lModel:GetAttribute("StunKind") == "Parried", "Leorio staggers")
check(#sent("Stop") == 1 and sent("Stop")[1].args[2] == l, "Stop broadcast (his holes close)")
settle()

print("== Warp Punch: dodged, or nobody there")
send("Cast", "WarpPunch", AHEAD)
mock.advance(W.PunchAt)
face(dModel, -12, -15, 180) -- steps out of it while the fist travels
mock.advance(W.HitDelay - W.PunchAt + 0.02)
check(dHum.Health == 200 and #hitsOn(dModel) == 0, "the hole stays put: moving out of it dodges")
settle()
send("Cast", "WarpPunch", Vector3.new(1, 0, 0)) -- nobody to the right
local free = sent("WarpPunch")[1]
local point = Vector3.new(Config.Targeting.Fallback, 3, 0)
local fo = free and free.args[3].Position - point
check(
	fo and near(Vector3.new(fo.X, 0, fo.Z).Magnitude, W.Distance, 1e-3),
	"the hole opens beside a spot Fallback out along the look"
)
settle()
send("Cast", "WarpPunch", Vector3.new(0.6, -0.2, -0.8)) -- 37 deg off D: outside Targeting.Angle
local wide = sent("WarpPunch")[1]
check(wide and (wide.args[3].Position - dRoot.Position).Magnitude > 6, "aiming well off him: not locked on")
settle()

print("== Warp Punch: interrupted")
send("Cast", "WarpPunch", AHEAD)
mock.advance(W.PunchAt)
Combat.stun(lModel, 0.5, "Hit")
check(#sent("Stop") == 1, "stunned with the fist travelling: Stop")
mock.advance(W.HitDelay)
check(dHum.Health == 200, "the blow never lands")
settle()

print("== Remote Jab: from behind")
local J = Config.RemoteJab
t0 = mock.now()
send("Cast", "RemoteJab", AHEAD)
local jab = sent("Jab")[1]
local jhole = jab and jab.args[3]
check(jab and near(jab.args[4], t0 + J.JabAt, 1e-6) and near(jab.args[5], t0 + J.HitDelay, 1e-6), "jabAt, hitAt")
check(
	jhole and jhole.Position.Z < dRoot.Position.Z - J.Distance + 0.01,
	"the hole opens behind D (the far side from him)"
)
check(jhole and jhole.LookVector.Z > 0.9, "punching toward him")
Combat.setBlocking(dModel, true) -- facing Leorio: the jab comes from behind
mock.advance(J.HitDelay + 0.02)
local jh = hitsOn(dModel)[1]
check(jh and jh.args[6] == "Hit", "a block facing him doesn't stop it")
check(near(dHum.Health, 200 - J.Damage), "Damage")
check(jh and jh.args[7].Z > 0.9, "pulled toward him")
check(Combat.isStunned(dModel) and near(dModel:GetAttribute("StunnedUntil") - Combat.now(), J.Stun, 0.05), "Stun")
settle()
face(dModel, 0, -15, 0) -- turned round to face the hole
Combat.setBlocking(dModel, true)
send("Cast", "RemoteJab", AHEAD)
mock.advance(J.HitDelay + 0.02)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Blocked", "turned round to face it: blocked")
settle()

print("== Remote Jab into Warp Punch: a combo")
send("Cast", "RemoteJab", AHEAD)
mock.advance(J.HitDelay + 0.02)
check(Combat.isStunned(dModel), "the jab stuns")
mock.advance(J.Recovery - J.HitDelay)
mock.advance(Config.SharedCooldown)
send("Cast", "WarpPunch", AHEAD)
check(#sent("WarpPunch") == 1, "Warp Punch straight after (Recovery + SharedCooldown)")
mock.advance(W.HitDelay + 0.02)
check(hitsOn(dModel)[2] and hitsOn(dModel)[2].args[6] == "Hit", "and it lands")
settle()

print("== Warp Barrage")
local BR = Config.WarpBarrage
t0 = mock.now()
send("Cast", "WarpBarrage", AHEAD)
check(#sent("Barrage") == 0, "nothing until the first fist hits the floor")
local free_frames = 0
local stepped = false
for _ = 1, 120 do
	mock.advance(1 / 60)
	local n = #sent("Barrage")
	if n >= 2 and n < #BR.Hits and not Combat.isStunned(dModel) then
		free_frames += 1
	end
	if #hitsOn(dModel) == 3 and not stepped then
		stepped = true
		face(dModel, 4, -16, 180) -- knocked about a bit: the next holes follow
	end
end
mock.advance(0.5)
local b = sent("Barrage")
check(#b == #BR.Hits, "one hole per punch (" .. #b .. ")")
local onTime = true
for i, entry in ipairs(b) do
	onTime = onTime and entry.args[3] == i and near(entry.args[5], t0 + BR.Hits[i].At, 0.02)
	onTime = onTime and near(entry.args[6] - entry.args[5], BR.Travel, 1e-6)
end
check(onTime, "each sent as its fist goes into the floor (the Hit markers), landing Travel later")
local sides = {}
for i = 1, #BR.Hits - 1 do
	local o = b[i].args[4].Position
	sides[i] = math.floor(math.deg(math.atan2(o.X - (if i > 3 then 4 else 0), o.Z - (if i > 3 then -16 else -15))))
end
check(sides[1] ~= sides[2] and sides[2] ~= sides[3] and sides[3] ~= sides[4], "from a different side each time")
local o4 = b[4].args[4].Position
check(near(Vector3.new(o4.X - 4, 0, o4.Z + 16).Magnitude, BR.Distance, 1e-3), "the holes follow the target")
local last = b[#b].args[4]
check(last.Position.Y > dRoot.Position.Y + 5 and last.LookVector.Y < -0.99, "the last from a hole overhead, down")
local barrageHits = hitsOn(dModel)
check(#barrageHits == #BR.Hits, "every punch lands (" .. #barrageHits .. ")")
local total = 0
for _, step in ipairs(BR.Hits) do
	total += step.Damage
end
check(near(dHum.Health, 200 - total, 1e-6), "for the sum of their Damage")
check(free_frames == 0, "D never gets out of the stun in between (" .. free_frames .. " frames free)")
settle()
Combat.setBlocking(dModel, true)
face(dModel, 0, -15, 0) -- turned away: only the hammer from overhead can be blocked
send("Cast", "WarpBarrage", AHEAD)
mock.advance(BR.Hits[1].At + BR.Travel + 0.02)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Hit", "the first one from a side he isn't facing lands")
settle()

print("== Portal Burst")
local P = Config.PortalBurst
face(dModel, 0, -5, 180)
face(bModel, 0, 12, 0) -- out of reach
t0 = mock.now()
send("Cast", "PortalBurst")
local burst = sent("Burst")[1]
check(
	burst and near(burst.args[4], t0 + P.HitDelay, 1e-6) and near(burst.args[5], t0 + P.HitDelay + P.Erupt, 1e-6),
	"burstAt, eruptAt"
)
local holes = burst and burst.args[6]
local ring = holes and #holes == P.Holes
for _, c in ipairs(holes or {}) do
	local o = c.Position - Vector3.new(0, 0, 0)
	ring = ring and near(Vector3.new(o.X, 0, o.Z).Magnitude, P.RingRadius, 1e-3) and c.LookVector.Y > 0.99
end
check(ring, "Holes holes in a ring round him on the floor, facing up")
mock.advance(P.HitDelay + P.Erupt - 0.03)
check(dHum.Health == 200, "nothing before the fists come up")
mock.advance(0.05)
local ph = hitsOn(dModel)[1]
check(ph and ph.args[6] == "Hit" and near(dHum.Health, 200 - P.Damage), "D is hit")
check(dModel:GetAttribute("StunKind") == "Launch", "launched")
check(ph and ph.args[7].Y > 0.7 and ph.args[7].Z < -0.1, "up and away from him")
check(bHum.Health == 200, "B (12 studs off) untouched")
settle()
face(dModel, 0, -5, 0) -- turned away, blocking, tapping F
Combat.setBlocking(dModel, true)
send("Cast", "PortalBurst")
mock.advance(P.HitDelay + P.Erupt - 0.1)
Combat.openParry(dModel)
mock.advance(0.12)
check(hitsOn(dModel)[1] and hitsOn(dModel)[1].args[6] == "Blocked", "blockable facing any way, never parried")
settle()

print("== The rules")
l:SetAttribute("Loadout", "WarpPunch,,,")
send("Cast", "RemoteJab", AHEAD)
check(#sent("Jab") == 0, "not equipped: nothing")
l:SetAttribute("Loadout", table.concat(Loadout.Presets.Leorio, ","))
Combat.stun(lModel, 0.5)
send("Cast", "RemoteJab", AHEAD)
check(#sent("Jab") == 0 and #denied() == 1, "stunned: denied")
mock.advance(0.6)
send("Cast", "RemoteJab", Vector3.new(0 / 0, 0, 0))
check(#sent("Jab") == 1, "a NaN aim falls back to his facing")
mock.advance(J.Recovery + Config.SharedCooldown)
local before = #H.remoteLog
send("Cast", "Fly")
send("Cast", nil)
send("Explode")
send("Cast", 42, AHEAD)
check(#H.remoteLog == before, "bad input ignored")
settle()
lHum.Health = 0
send("Cast", "WarpPunch", AHEAD)
check(#sent("WarpPunch") == 0, "dead: nothing")

H.finish("Leorio server")
