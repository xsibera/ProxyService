--!nocheck
-- Headless test of MovementServer: rolls are checked (cooldown, stun, mid-attack) and make the roller
-- untouchable and busy. Run from this folder:  cd Abilities/Movement && luaurun tests/server.luau

local H = assert(loadfile("tests/harness.luau"))()
local mock, check, near = H.mock, H.check, H.near
local Config = require(H.Config)
local Combat = require(H.CombatModule)
local ROLL = Config.Roll

local aModel, _, aHum = H.character("A", 0, 0, 0)
local a = H.player("A", aModel)
local bModel = H.character("B", 0, -4, 180)

local SSS = game:GetService("ServerScriptService")
local serverScript = mock.newInstance("Script", "MovementServer")
rawget(serverScript, "__props").__path = "src/MovementServer.server.luau"
serverScript.Parent = SSS
mock.runScript(serverScript)
mock.advance(0)

local function roll(dir)
	H.remote.OnServerEvent:Fire(a, "Roll", dir)
end
local function sent(kind)
	return H.sent(kind, "server", H.remote)
end
local function rest()
	mock.advance(2)
	Combat.setBlocking(aModel, false)
	table.clear(H.remoteLog)
end

print("== A roll")
roll(Vector3.new(1, 0, 0))
local r = sent("Roll")[1]
check(r and r.to == "all" and r.args[2] == a and r.args[3] == Vector3.new(1, 0, 0), "Roll broadcast (who, which way)")
check(near(aModel:GetAttribute("IntangibleUntil") - Combat.now(), ROLL.Intangible, 1e-3), "untouchable for Intangible")
check(
	near(aModel:GetAttribute("BusyUntil") - Combat.now(), ROLL.Busy, 1e-3),
	"busy for Busy (no attacking or blocking)"
)
check(Combat.resolve(bModel, aModel, { Damage = 10 }) == "Evaded", "a hit mid-roll passes through")
check(aHum.Health == 200, "no damage")
mock.advance(ROLL.Intangible + 0.02)
check(Combat.resolve(bModel, aModel, { Damage = 10, Stun = 0.1 }) == "Hit", "after the untouchable part: hit")
rest()

print("== Cooldown")
roll(Vector3.new(0, 0, -1))
mock.advance(0.3)
roll(Vector3.new(0, 0, -1))
check(#sent("Roll") == 1, "again too soon: no roll")
local d = H.sent("Denied", "server", H.remote)[1]
check(d and d.to == a and near(d.args[2], ROLL.Cooldown - 0.3, 0.02), "Denied with the time left")
mock.advance(ROLL.Cooldown - 0.3)
roll(Vector3.new(0, 0, -1))
check(#sent("Roll") == 2, "after the cooldown: fine")
rest()

print("== Not now")
Combat.stun(aModel, 0.5)
roll(Vector3.new(1, 0, 0))
check(#sent("Roll") == 0, "stunned: no")
mock.advance(0.6)
Combat.setBusy(aModel, 0.5) -- mid-attack
roll(Vector3.new(1, 0, 0))
check(#sent("Roll") == 0, "mid-attack: no")
mock.advance(0.6)
Combat.setBlocking(aModel, true)
roll(Vector3.new(1, 0, 0))
check(#sent("Roll") == 1, "blocking: rolls out of it")
check(aModel:GetAttribute("Blocking") == false, "and lets go of the block")
rest()

print("== Bad input")
roll(nil)
roll("left")
roll(Vector3.new(0, 1, 0))
roll(Vector3.new(0 / 0, 0, 1))
roll(Vector3.new(math.huge, 0, 0))
H.remote.OnServerEvent:Fire(a, "Fly")
check(#H.remoteLog == 0, "ignored")
aHum.Health = 0
roll(Vector3.new(1, 0, 0))
check(#sent("Roll") == 0, "dead: no")

H.finish("Movement server")
