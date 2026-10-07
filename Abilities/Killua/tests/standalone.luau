--!nocheck
-- KilluaServer on its own: a place without Combat or Loadout (plain damage and knockback, no
-- counters). Run from this folder:  cd Abilities/Killua && luaurun tests/standalone.luau

local H = assert(loadfile("tests/harness.luau"))()
local mock, check, near = H.mock, H.check, H.near
local Config = require(H.Config)

local kModel = H.character("Killua", 0, 0, 0)
local k = H.player("Killua", kModel)
local dModel, dParts, dHum = H.character("D", 0, -5, 180)

local SSS = game:GetService("ServerScriptService")
local serverScript = mock.newInstance("Script", "KilluaServer")
rawget(serverScript, "__props").__path = "src/KilluaServer.server.luau"
serverScript.Parent = SSS
mock.runScript(serverScript)
mock.advance(0)

local function send(...)
	H.remote.OnServerEvent:Fire(k, ...)
end
local function sent(kind)
	return H.sent(kind, "server", H.remote)
end
local function knockback()
	local a = dParts.HumanoidRootPart:FindFirstChild("KilluaKnockback")
	return a and a:FindFirstChildOfClass("LinearVelocity")
end

print("== Without Combat or Loadout")
send("Cast", "LightningPalm")
check(#sent("Palm") == 1, "every ability is usable (no Loadout)")
mock.advance(Config.LightningPalm.HitDelay + 0.02)
check(near(dHum.Health, 200 - Config.LightningPalm.Damage), "plain damage")
local push = knockback()
check(push and push.VectorVelocity.Z < -Config.LightningPalm.Knockback + 1, "pushed away from Killua")
check(sent("Hit")[1] and sent("Hit")[1].args[6] == "Hit", "outcome Hit")
mock.advance(Config.KnockbackTime + 0.05)
check(knockback() == nil, "the push ends")
send("Cast", "LightningPalm")
check(#sent("Palm") == 1, "cooldowns still apply")

mock.advance(Config.LightningPalm.Recovery)
send("Cast", "Whirlwind")
check(#sent("Stance") == 1, "Whirlwind's stance goes up")
mock.advance(Config.Whirlwind.Window + 0.02)
check(
	sent("StanceEnd")[1] and sent("StanceEnd")[1].args[3] == false,
	"and ends (nothing can trigger it without Combat)"
)

mock.advance(Config.Whirlwind.WhiffRecovery + 0.05)
dHum.Health = 200
send("Dash", 1, Vector3.new(0, 3, -10))
kModel:PivotTo(CFrame.new(0, 3, -10))
mock.advance(Config.LightningDash.Strikes[1].Delay + 0.02)
check(#sent("Dash") == 1 and near(dHum.Health, 200 - Config.LightningDash.Strikes[1].Damage), "the dash strikes")

H.finish("Killua standalone")
