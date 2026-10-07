--!nocheck
-- Headless test of KilluaClient + KilluaVFX in the ability place's setup (Loadout + Combat), with
-- the real effect tree: the keys (through Loadout), the animations, the predicted casts (the
-- palm's charge and lunge, the leap and hang, the stance, the dashes and their targeting), and
-- every server event drawn. Run from this folder:  cd Abilities/Killua && luaurun tests/client.luau

local H = assert(loadfile("tests/harness.luau"))()
H.withCombatAndLoadout()
local mock, check, near = H.mock, H.check, H.near
mock.isClient = true
local Config = require(H.Config)
local Loadout = require(H.LoadoutModule)
local Combat = require(H.CombatModule)
local Players = game:GetService("Players")

local camera = mock.newInstance("Camera", "Camera")
camera.CFrame = CFrame.new(0, 6, 12) -- behind him, looking -Z
camera.Parent = workspace
workspace.CurrentCamera = camera

local kModel, kParts, kHum = H.character("Killua", 0, 0, 0)
local k = H.player("Killua", kModel)
mock.newInstance("PlayerGui", "PlayerGui").Parent = k
k:SetAttribute("Loadout", table.concat(Loadout.Presets.Killua, ","))
Players.LocalPlayer = k
local oModel, oParts = H.character("Other", 30, 0, 0)
local other = H.player("Other", oModel)

local client = mock.newInstance("LocalScript", "KilluaClient")
rawget(client, "__props").__path = "src/KilluaClient.client.luau"
client.Parent = k
mock.runScript(client)
mock.advance(0.05)

local kRoot = kParts.HumanoidRootPart
local function find(root, name)
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
end
local function count(root, name)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then
			n += 1
		end
	end
	return n
end
local function lastPlayed()
	local p = H.played[#H.played]
	return p and p.name or ""
end
local function playing(name) -- the last animation played was Killua's `name` (Config.Animations key)
	return lastPlayed() == "rbxassetid://temp-Killua " .. name
end
-- an effect is stopped when none of its emitters emit any more (it's cleaned up once they fade)
local function stopped(effect)
	if effect == nil or effect.Parent == nil then
		return true
	end
	for _, d in ipairs(effect:GetDescendants()) do
		if d.ClassName == "ParticleEmitter" and d.Enabled then
			return false
		end
	end
	return true
end
local function cooldownLeft(ability)
	return (Loadout.cooldown(ability, os.clock()))
end
local function press(ability)
	Loadout.handler(ability)(Enum.UserInputState.Begin)
end
local function serverSays(...)
	H.remote.OnClientEvent:Fire(...)
end
local function casts()
	return H.sent("Cast", "client", H.remote)
end
local function rest(seconds)
	mock.advance(seconds or 11) -- every cooldown over
	table.clear(H.remoteLog)
end

print("== Boot")
check(H.registered == 8, "the eight KeyframeSequences registered for Studio play (" .. H.registered .. ")")
for _, ability in ipairs(Config.Abilities) do
	check(Loadout.handler(ability) ~= nil, ability .. " bound through Loadout")
end
check(k.PlayerGui:FindFirstChild("KilluaUI") == nil, "no bar of its own (Loadout's hotbar shows the abilities)")
check(mock.actions.KilluaLightningPalm == nil, "no keys of its own")

print("== Lightning Palm")
local P = Config.LightningPalm
press("LightningPalm")
local cast = casts()[1]
check(cast and cast.args[2] == "LightningPalm", "asks the server")
check(cast and typeof(cast.args[3]) == "Vector3" and cast.args[3].Z < -0.5, "with the camera's look")
check(playing("Palm"), "Palm plays at once")
local charge = find(kParts["Right Arm"], "HandCharge")
check(charge ~= nil and near(charge.CFrame.Position.Y, -1.05), "lightning gathers in the palm")
local left, total = Loadout.cooldown("LightningPalm", os.clock())
check(total == P.Cooldown and near(left, P.Cooldown, 0.01), "the hotbar shows the cooldown")
press("LightningPalm")
check(#casts() == 1, "pressed again: nothing sent")
check(Loadout.deniedAt("LightningPalm") > 0, "the slot flashes")
mock.advance(P.LungeAt + 0.01)
local drive = find(kRoot, "KilluaDrive")
local lv = drive and drive:FindFirstChildOfClass("LinearVelocity")
check(
	lv and near(lv.VectorVelocity.Magnitude, P.Lunge / P.LungeTime, 1e-3) and lv.VectorVelocity.Z < 0,
	"the lunge, forward"
)
mock.advance(P.LungeTime + 0.05)
check(find(kRoot, "KilluaDrive") == nil, "the lunge ends")
mock.advance(P.HitDelay - P.LungeAt - P.LungeTime)
check(stopped(charge), "the charge goes off at the hit")
check(find(workspace, "PalmBurst") ~= nil, "the burst out of the palm")
rest()

print("== Thunderbolt")
local T = Config.Thunderbolt
press("Thunderbolt")
check(casts()[1] and casts()[1].args[2] == "Thunderbolt", "asks the server")
check(playing("Thunderbolt"), "Thunderbolt plays")
mock.advance(T.LeapAt + 0.01)
check(near(kRoot.AssemblyLinearVelocity.Y, T.LeapSpeed), "the leap")
local target = Vector3.new(0, 0, -12)
serverSays("Thunderbolt", k, target, workspace:GetServerTimeNow() + T.HitDelay - T.LeapAt)
local marker = find(workspace, "ThunderboltMarker")
local ring = marker and find(marker, "StrikeMarker")
check(ring ~= nil and not stopped(ring), "the warning ring where it will land")
mock.advance(T.HangFrom - T.LeapAt)
local hang = find(kRoot, "KilluaHang")
local force = hang and hang:FindFirstChildOfClass("VectorForce")
check(force and near(force.Force.Y, kRoot.AssemblyMass * workspace.Gravity, 1e-3), "hangs at the top")
mock.advance(T.HitDelay - T.HangFrom + 0.02)
check(stopped(ring), "the ring goes when the bolt lands")
check(find(workspace, "ThunderStrike") ~= nil, "the strike")
mock.advance(T.HangUntil - T.HitDelay)
check(find(kRoot, "KilluaHang") == nil, "falls after HangUntil")
kHum.StateChanged:Fire(Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Landed)
check(playing("Land"), "lands into the Land animation")
local played = #H.played
kHum.StateChanged:Fire(Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Landed)
check(#H.played == played, "(only after a leap)")
rest()

print("== Whirlwind")
local W = Config.Whirlwind
press("Whirlwind")
check(casts()[1] and casts()[1].args[2] == "Whirlwind", "asks the server")
check(playing("Stance"), "drops into the stance")
local crackle = find(kRoot, "Crackle")
check(crackle ~= nil and not stopped(crackle), "static over him")
local behind = CFrame.lookAt(Vector3.new(30, 3, 3.2), Vector3.new(30, 3, 0))
serverSays("Counter", k, oModel, kRoot.CFrame, behind, workspace:GetServerTimeNow())
check(stopped(crackle), "the static goes")
check(near((kRoot.Position - behind.Position).Magnitude, 0, 1e-3), "blinks behind the attacker")
check(playing("Counter"), "the counter flurry plays")
check(find(workspace, "KilluaAfterimage") ~= nil, "an afterimage where he was")
check(find(workspace, "Blink") ~= nil, "the blink where he lands")
mock.advance(0.55)
check(find(workspace, "KilluaAfterimage") == nil, "the afterimage fades")
kModel:PivotTo(CFrame.new(0, 3, 0))
rest()
press("Whirlwind")
crackle = find(kRoot, "Crackle")
mock.advance(W.Window - 0.1)
serverSays("StanceEnd", k, false)
check(stopped(crackle), "a whiff: the static goes")
press("LightningPalm")
check(#H.sent("Cast", "client", H.remote) == 1, "still open after a whiff (WhiffRecovery)")
rest()

print("== Lightning Dash: the zigzag")
local L = Config.LightningDash
local dModel, dParts = H.character("D", 0, -10, 180)
local dRoot = dParts.HumanoidRootPart
local function dashes()
	return H.sent("Dash", "client", H.remote)
end
press("LightningDash")
local d1 = dashes()[1]
check(d1 and d1.args[2] == 1, "dash 1 sent")
check(d1 and near(d1.args[3].Z, -10 + 2.2, 1e-3) and near(d1.args[3].X, 0, 1e-3), "stops just in front of D")
check(near(kRoot.Position.Z, -7.8, 1e-3), "he's there at once")
check(kRoot.CFrame.LookVector.Z < -0.99, "facing D")
check(playing("Dash1"), "Dash 1 plays")
check(find(workspace, "KilluaAfterimage") ~= nil and find(workspace, "DashBurst") ~= nil, "afterimage and bursts")
press("LightningDash")
check(#dashes() == 1, "too soon (MinGap): nothing")
mock.advance(L.MinGap + 0.01)
press("LightningDash")
local d2 = dashes()[2]
check(d2 and d2.args[2] == 2 and near(d2.args[3].Z, -12.6, 1e-3), "dash 2: through to behind D")
check(kRoot.CFrame.LookVector.Z > 0.99, "turned to face D again")
check(playing("Dash2"), "Dash 2 plays")
mock.advance(L.MinGap + 0.01)
press("LightningDash")
local d3 = dashes()[3]
check(
	d3 and d3.args[2] == 3 and near(d3.args[3].Z, -7.4, 1e-3),
	"dash 3: back through (the camera still looks away from D)"
)
check(kRoot.CFrame.LookVector.Z < -0.99, "facing D")
check(playing("Dash3"), "the finisher plays")
mock.advance(L.MinGap + 0.01)
press("LightningDash")
check(#dashes() == 3, "three is the chain: a fourth press waits for the cooldown")
check(near(cooldownLeft("LightningDash"), L.Cooldown - L.MinGap - 0.01, 0.05), "cooldown from the end of the chain")
for _, entry in ipairs(dashes()) do
	check(math.abs(entry.args[3].Y - 3) < 1e-3, "dash " .. entry.args[2] .. " keeps his height above the floor")
end
rest()

print("== Lightning Dash: no one there")
kModel:PivotTo(CFrame.new(0, 3, 0))
dModel:PivotTo(CFrame.new(-40, 3, 0))
press("LightningDash")
local free = dashes()[1]
check(free and near(free.args[3].Z, -L.Distance, 1e-3), "Distance straight along the camera's look")
mock.advance(L.ChainWindow + 0.1)
press("LightningDash")
check(#dashes() == 1, "the window passed: the chain is over, on cooldown")
rest()

print("== Lightning Dash: denied")
kModel:PivotTo(CFrame.new(0, 3, 0))
press("LightningDash")
serverSays("DashDenied", 1, Vector3.new(0, 3, 0))
check(near(kRoot.Position.Z, 0, 1e-3), "put back where he started")
mock.advance(L.MinGap + 0.01)
press("LightningDash")
check(#dashes() == 1, "and the chain is over")
rest()

print("== Stopped")
press("LightningDash")
mock.advance(L.MinGap + 0.01)
serverSays("Stop", k)
press("LightningDash")
check(#dashes() == 1, "a Stop ends the chain")
check(cooldownLeft("LightningDash") > L.Cooldown - 1, "and starts its cooldown")
rest()
press("LightningPalm")
charge = find(kParts["Right Arm"], "HandCharge")
serverSays("Stop", k)
check(charge ~= nil and stopped(charge), "the palm's charge is cut")
rest()

print("== Combat: no casting while stunned or blocking")
kModel:SetAttribute("StunnedUntil", workspace:GetServerTimeNow() + 1)
press("LightningPalm")
press("LightningDash")
check(#casts() == 0 and #dashes() == 0, "stunned: nothing")
kModel:SetAttribute("StunnedUntil", nil)
kModel:SetAttribute("Blocking", true)
press("Thunderbolt")
check(#casts() == 0, "blocking: nothing")
kModel:SetAttribute("Blocking", false)
_ = Combat
rest()

print("== The server's word")
press("LightningPalm")
serverSays("Denied", "LightningPalm", 3)
local busyFor = 0.2
mock.advance(Config.LightningPalm.Cooldown - busyFor) -- the client thinks it's nearly ready...
serverSays("Denied", "LightningPalm", 3) -- ...the server says 3 s more
check(cooldownLeft("LightningPalm") >= 2.9, "Denied with time left: the hotbar shows the server's cooldown")
rest()

print("== Other players")
local before = #H.played
serverSays("Palm", other, workspace:GetServerTimeNow() + P.HitDelay)
check(find(oParts["Right Arm"], "HandCharge") ~= nil, "their palm charges")
check(#H.played == before, "no animation on them (their own client plays it)")
serverSays("Stance", other, workspace:GetServerTimeNow() + W.Window)
local theirs = find(oParts.HumanoidRootPart, "Crackle")
check(theirs ~= nil and not stopped(theirs), "their stance")
serverSays("StanceEnd", other, true)
check(stopped(theirs), "ends")
serverSays("Dash", other, 1, Vector3.new(30, 3, 0), Vector3.new(30, 3, -12), workspace:GetServerTimeNow())
check(count(workspace, "DashBurst") >= 2, "their dash: bursts at both ends")
check(find(workspace, "KilluaAfterimage") ~= nil, "and an afterimage")
mock.advance(P.HitDelay + 0.05)
local shocks = count(workspace, "ShockHit")
serverSays("Hit", other, kModel, "LightningPalm", kRoot.Position, "Hit", "Shock")
check(count(workspace, "ShockHit") == shocks + 1, "a hit: the shock where it landed")
serverSays("Hit", other, kModel, "LightningPalm", kRoot.Position, "Parried", "Shock")
check(count(workspace, "ShockHit") == shocks + 1, "a parried hit: no shock (Combat draws the parry)")
serverSays("Stop", other)
Players.PlayerRemoving:Fire(other)

H.finish("Killua client")
