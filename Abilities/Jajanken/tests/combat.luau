--!nocheck
-- JajankenServer in the ability place's setup: every hit through Combat (blocks, parries, a full
-- Rock breaking a guard), stuns cutting a charge short, no charging while blocking or stunned, and
-- only the modes in the Loadout. Run from this folder:  cd Abilities/Jajanken && luaurun tests/combat.luau

local H = assert(loadfile("tests/harness.luau"))()
H.withCombatAndLoadout()
local mock, check, near = H.mock, H.check, H.near
local Config = require(H.Config)
local Combat = require(H.CombatModule)
local Loadout = require(H.LoadoutModule)

local gonModel, _, gonHum = H.character("Gon", 0, 0, 0)
local gon = H.player("Gon", gonModel)
gon:SetAttribute("Loadout", table.concat(Loadout.Presets.Gon, ","))
local dModel, _, dHum = H.character("D", 0, -3.5, 180)

local SSS = game:GetService("ServerScriptService")
local serverScript = mock.newInstance("Script", "JajankenServer")
rawget(serverScript, "__props").__path = "src/JajankenServer.server.luau"
serverScript.Parent = SSS
mock.runScript(serverScript)
mock.advance(0)

local announced = {}
Combat.Announced.Event:Connect(function(attacker, hitAt, ability)
	table.insert(announced, { attacker = attacker, hitAt = hitAt, ability = ability })
end)
local function send(...)
	H.remote.OnServerEvent:Fire(gon, ...)
end
local function settle()
	mock.advance(6)
	Combat.setBlocking(dModel, false)
	Combat.setBlocking(gonModel, false)
	dModel:SetAttribute("Guard", nil)
	gonHum.Health, dHum.Health = 200, 200
	table.clear(H.remoteLog)
	table.clear(announced)
end
local R = Config.Rock

print("== Announced, and busy while it plays out")
send("Charge", "Rock")
check(Combat.isBusy(gonModel), "charging: busy (no blocking, no other ability)")
send("Release")
check(
	announced[1] and announced[1].ability == "Rock" and near(announced[1].hitAt, mock.now() + R.HitDelay, 1e-3),
	"the hit announced"
)
mock.advance(R.HitDelay + 0.02)
check(near(dHum.Health, 200 - R.Damage[1], 0.01), "a clean hit")
check(Combat.isStunned(dModel), "stuns")
mock.advance(1)
check(not Combat.isBusy(gonModel), "not busy once it's over")
settle()

print("== Blocked")
mock.advance(0.1)
Combat.setBlocking(dModel, true)
mock.advance(Combat.Settings.ParryWindow)
send("Charge", "Rock")
send("Release")
mock.advance(R.HitDelay + 0.02)
check(near(dHum.Health, 200 - R.Damage[1] * Combat.Settings.ChipDamage, 0.01), "chip damage")
check(near(Combat.guard(dModel), Combat.Settings.GuardMax - R.Damage[1] * 2, 0.01), "guard worn")
check(#H.sent("Hit", "server", H.remote) == 1, "the hit still shows (blocked)")
settle()

print("== Parried")
Combat.setBlocking(dModel, true)
send("Charge", "Rock")
send("Release")
mock.advance(R.HitDelay - 0.1)
Combat.openParry(dModel)
mock.advance(0.12)
check(dHum.Health == 200, "parried: no damage")
check(Combat.isStunned(gonModel) and gonModel:GetAttribute("StunKind") == "Parried", "Gon staggers")
check(#H.sent("Hit", "server", H.remote) == 0, "no hit effect (Combat draws the parry)")
settle()

print("== A full Rock breaks a guard")
mock.advance(0.1)
Combat.setBlocking(dModel, true)
send("Charge", "Rock")
mock.advance(Config.MaxCharge + R.HitDelay + 0.05) -- it goes off by itself at full power
check(Combat.isStunned(dModel) and dModel:GetAttribute("StunKind") == "GuardBreak", "guard broken")
check(dModel:GetAttribute("Blocking") == false, "no longer blocking")
settle()

print("== A stun cuts the charge short")
send("Charge", "Paper")
mock.advance(1)
Combat.resolve(dModel, gonModel, { Damage = 5, Stun = 0.4 })
check(#H.sent("Stop", "server", H.remote) == 1, "Stop broadcast")
check(gonHum.WalkSpeed == Combat.Settings.StunWalkSpeed, "the stun's walk speed, not the charge's")
mock.advance(Config.MaxCharge)
check(#H.sent("Cast", "server", H.remote) == 0, "it never goes off")
mock.advance(0.5)
check(gonHum.WalkSpeed == 16, "walk speed back after the stun")
settle()

print("== Not while blocking or stunned")
Combat.setBlocking(gonModel, true)
send("Charge", "Rock")
local denied = H.sent("Denied", "server", H.remote)[1]
check(denied and denied.to == gon and denied.args[3] == 0, "blocking: denied")
Combat.setBlocking(gonModel, false)
Combat.stun(gonModel, 1)
send("Charge", "Rock")
check(#H.sent("Charge", "server", H.remote) == 0, "stunned: no charge")
settle()

print("== Only what's equipped")
gon:SetAttribute("Loadout", table.concat(Loadout.Presets.Killua, ","))
send("Charge", "Rock")
check(
	#H.sent("Charge", "server", H.remote) == 0 and #H.sent("Denied", "server", H.remote) == 0,
	"not equipped: ignored"
)
gon:SetAttribute("Loadout", "LightningPalm,Scissors,,")
send("Charge", "Scissors")
check(#H.sent("Charge", "server", H.remote) == 1, "equipped on any slot: works")

H.finish("Jajanken with Combat")
