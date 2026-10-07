--!nocheck
-- Headless test of LeorioClient + LeorioVFX in the ability place's setup (Loadout + Combat), with
-- the real effect tree: the keys (through Loadout), turning to the camera, the animations, the aura
-- in the fist, and every server event drawn - the holes opening on time and closing, the fists
-- punching out of them along their look and pulling back, the trace, the burst's ring, the hits,
-- and Stop closing everything. Run from this folder:  cd Abilities/Leorio && luaurun tests/client.luau

local H = assert(loadfile("tests/harness.luau"))()
H.withCombatAndLoadout()
local mock, check, near = H.mock, H.check, H.near
mock.isClient = true
local Config = require(H.Config)
local Loadout = require(H.LoadoutModule)
local Players = game:GetService("Players")

local camera = mock.newInstance("Camera", "Camera")
camera.CFrame = CFrame.lookAt(Vector3.new(-12, 6, 0), Vector3.new(0, 3, 0)) -- off to his left, looking +X
camera.Parent = workspace
workspace.CurrentCamera = camera

local lModel, lParts, lHum = H.character("Leorio", 0, 0, 0)
local l = H.player("Leorio", lModel)
mock.newInstance("PlayerGui", "PlayerGui").Parent = l
l:SetAttribute("Loadout", table.concat(Loadout.Presets.Leorio, ","))
Players.LocalPlayer = l
local oModel, oParts = H.character("Other", 30, 0, 0)
local other = H.player("Other", oModel)

local client = mock.newInstance("LocalScript", "LeorioClient")
rawget(client, "__props").__path = "src/LeorioClient.client.luau"
client.Parent = l
mock.runScript(client)
mock.advance(0.05)

local lRoot = lParts.HumanoidRootPart
local function find(root, name)
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
end
local function all(root, name)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then
			table.insert(out, d)
		end
	end
	return out
end
local function count(root, name)
	return #all(root, name)
end
local function warps()
	return workspace:FindFirstChild("LeorioWarps") or mock.newInstance("Folder", "none")
end
local function lastPlayed()
	local p = H.played[#H.played]
	return p and p.name or ""
end
local function playing(name) -- the last animation played was Leorio's `name` (Config.Animations key)
	return lastPlayed() == "rbxassetid://temp-Leorio " .. name
end
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
local function press(ability)
	Loadout.handler(ability)(Enum.UserInputState.Begin)
end
local function serverSays(...)
	H.remote.OnClientEvent:Fire(...)
end
local function casts()
	return H.sent("Cast", "client", H.remote)
end
local function now()
	return workspace:GetServerTimeNow()
end
local function rest(seconds)
	mock.advance(seconds or 13) -- every cooldown over, every hole closed
	table.clear(H.remoteLog)
end
-- a warp hole whose Void disc sits at `position`
local function holeAt(position)
	for _, hole in ipairs(all(warps(), "WarpHole")) do
		local void = hole:FindFirstChild("Void")
		if void and (void.Position - position).Magnitude < 0.05 then
			return hole
		end
	end
end

print("== Boot")
check(H.registered == 4, "the four KeyframeSequences registered for Studio play (" .. H.registered .. ")")
for _, ability in ipairs(Config.Abilities) do
	check(Loadout.handler(ability) ~= nil, ability .. " bound through Loadout")
end
check(l.PlayerGui:FindFirstChild("LeorioUI") == nil, "no bar of its own (Loadout's hotbar shows the abilities)")

print("== Warp Punch: the cast")
local W = Config.WarpPunch
press("WarpPunch")
local cast = casts()[1]
check(cast and cast.args[2] == "WarpPunch", "asks the server")
check(cast and typeof(cast.args[3]) == "Vector3" and cast.args[3].X > 0.8, "with the camera's look")
check(lRoot.CFrame.LookVector.X > 0.99, "turns to where the camera looks")
check(playing("WarpPunch"), "the animation plays at once")
local left, total = Loadout.cooldown("WarpPunch", os.clock())
check(total == W.Cooldown and near(left, W.Cooldown, 0.01), "the hotbar shows the cooldown")
press("WarpPunch")
check(#casts() == 1, "pressed again: nothing sent")

print("== Warp Punch: the holes and the fist")
local hole = CFrame.lookAt(Vector3.new(14, 4.3, 3), Vector3.new(15, 3.8, 0))
local t0 = now()
serverSays("WarpPunch", l, hole, t0 + W.PunchAt, t0 + W.HitDelay)
local charge = find(lParts["Right Arm"], "FistCharge")
check(charge ~= nil and not stopped(charge), "the aura gathers in his right fist")
mock.advance(W.PunchAt - 0.03)
check(count(warps(), "WarpHole") == 0, "no hole before the fist hits the floor")
mock.advance(0.05)
check(stopped(charge), "the charge goes with the punch")
check(find(workspace, "GroundPunch") ~= nil, "the punch into the floor")
check(find(workspace, "TraceProjectile") ~= nil, "the trace runs off along the floor")
local target = holeAt(hole.Position)
check(target ~= nil, "the hole opens by the target as the fist goes in (the telegraph)")
check(count(warps(), "WarpHole") == 2, "and a small one under his fist")
local swirl = target and find(target, "Portal")
check(swirl ~= nil and not stopped(swirl), "the swirl across it")
check(target and #all(target, "Rim") == 18, "its rim")
mock.advance(0.2)
local void = target and target:FindFirstChild("Void")
check(void and near(void.Size.Y, W.Radius * 2 * 0.9, W.Radius * 0.15), "open to its Radius")
check(void and math.abs(void.CFrame.RightVector:Dot(hole.LookVector)) > 0.99, "the disc square to its look")
check(find(warps(), "WarpFist") == nil, "no fist yet")
mock.advance(W.HitDelay - W.PunchAt - 0.2 + 0.02)
check(find(workspace, "PortalBurst") ~= nil, "the burst as the fist comes through")
local fist = find(warps(), "WarpFist")
check(fist ~= nil, "the fist punches out of it")
mock.advance(0.08)
local knuckles = fist and fist:FindFirstChild("Fist")
local reach = W.Distance + 1.4
local s = Config.Fist.Scale
check(
	knuckles and near((knuckles.Position - hole.Position):Dot(hole.LookVector), reach - 0.5 * s, 0.05),
	"all the way out along the hole's look"
)
check(fist and fist:FindFirstChild("Sleeve").Transparency == 0 and fist:FindFirstChild("Cuff") ~= nil, "in his sleeve")
check(fist and fist:FindFirstChildOfClass("Highlight") ~= nil, "glowing with his aura")
mock.advance(0.5)
check(find(warps(), "WarpFist") == nil, "pulled back in")
check(count(warps(), "WarpHole") == 0, "and the holes close")
rest()

print("== Remote Jab")
local J = Config.RemoteJab
press("RemoteJab")
check(casts()[1] and casts()[1].args[2] == "RemoteJab", "asks the server")
check(playing("RemoteJab"), "the jab plays")
check(find(lParts["Left Arm"], "FistCharge") ~= nil, "the aura in the jabbing (left) fist")
local behind = CFrame.lookAt(Vector3.new(20, 4.2, 0), Vector3.new(16, 3.7, 0))
t0 = now()
serverSays("Jab", l, behind, t0 + J.JabAt, t0 + J.HitDelay)
check(holeAt(behind.Position) ~= nil, "the hole behind the target opens at once")
mock.advance(J.JabAt + 0.02)
check(count(warps(), "WarpHole") == 2, "and one at his knuckles as the jab goes in")
mock.advance(J.HitDelay - J.JabAt)
check(find(warps(), "WarpFist") ~= nil, "the fist comes out behind them")
rest()

print("== Warp Barrage")
local BR = Config.WarpBarrage
press("WarpBarrage")
check(playing("Barrage"), "the barrage plays")
local aura = find(lRoot, "Aura")
check(aura ~= nil and not stopped(aura), "his aura flares")
for i, step in ipairs(BR.Hits) do
	t0 = now()
	local at = Vector3.new(16 + i * 0.2, 4, 0)
	local h = if step.Above
		then CFrame.lookAt(Vector3.new(16, 10, 0), Vector3.new(16, 3, 0), Vector3.xAxis)
		else CFrame.lookAt(at, Vector3.new(15, 3.6, 0))
	serverSays("Barrage", l, i, h, t0, t0 + BR.Travel)
	check(holeAt(h.Position) ~= nil, "punch " .. i .. ": its hole opens")
	mock.advance(BR.Travel + 0.02)
	check(find(warps(), "WarpFist") ~= nil, "punch " .. i .. ": a fist comes out")
	mock.advance(0.1)
end
mock.advance(BR.Length)
check(stopped(aura), "the aura dies down after")
rest()

print("== Portal Burst")
local P = Config.PortalBurst
press("PortalBurst")
check(playing("Burst"), "the burst plays")
local holes = {}
for i = 1, P.Holes do
	local a = (i - 1) / P.Holes * 2 * math.pi
	local spot = Vector3.new(math.cos(a), 0, math.sin(a)) * P.RingRadius + Vector3.new(0, 0.05, 0)
	holes[i] = CFrame.lookAt(spot, spot + Vector3.yAxis, Vector3.xAxis)
end
t0 = now()
serverSays("Burst", l, Vector3.zero, t0 + P.HitDelay, t0 + P.HitDelay + P.Erupt, holes)
check(count(warps(), "WarpHole") == P.Holes, "a ring of holes opens round him")
check(find(lParts["Right Arm"], "FistCharge") and find(lParts["Left Arm"], "FistCharge"), "both fists charge")
mock.advance(P.HitDelay + 0.02)
check(find(workspace, "BurstRing") ~= nil, "the ring of dust and air as the fists go in")
mock.advance(P.Erupt)
check(count(warps(), "WarpFist") == P.Holes, "a fist comes up out of each")
local up = all(warps(), "Fist")
check(#up > 0 and up[1].Position.Y > 1, "upward")
rest()

print("== Hits")
local victim = oModel
serverSays("Hit", l, victim, "RemoteJab", oParts.HumanoidRootPart.Position, "Hit", Vector3.new(-1, 0, 0))
check(find(workspace, "WarpHit") ~= nil, "a light one: WarpHit")
serverSays("Hit", l, victim, "WarpPunch", oParts.HumanoidRootPart.Position, "Hit", Vector3.new(0, 0.3, 1).Unit)
check(find(workspace, "WarpHeavy") ~= nil, "a heavy one: WarpHeavy")
local heavies = count(workspace, "WarpHeavy")
serverSays("Hit", l, victim, "WarpPunch", oParts.HumanoidRootPart.Position, "Parried", Vector3.xAxis)
check(count(workspace, "WarpHeavy") == heavies, "a parried one: nothing (Combat draws the parry)")
serverSays("Hit", other, lModel, "WarpPunch", lRoot.Position, "Hit", Vector3.xAxis)
mock.advance(0.03)
check(lHum.CameraOffset and lHum.CameraOffset.Magnitude > 0, "hit himself: the camera shakes")
rest()

print("== Stop")
press("WarpPunch")
t0 = now()
serverSays("WarpPunch", l, hole, t0 + W.PunchAt, t0 + W.HitDelay)
charge = find(lParts["Right Arm"], "FistCharge")
mock.advance(W.PunchAt + 0.05)
check(count(warps(), "WarpHole") == 2, "holes open")
serverSays("Stop", l)
check(stopped(charge), "the charge is cut")
mock.advance(0.25)
check(count(warps(), "WarpHole") == 0, "every hole of his closes")
mock.advance(W.HitDelay)
check(find(warps(), "WarpFist") == nil, "no fist comes out")
rest()

print("== No casting while stunned or blocking")
lModel:SetAttribute("StunnedUntil", now() + 1)
press("WarpPunch")
check(#casts() == 0, "stunned: nothing")
lModel:SetAttribute("StunnedUntil", nil)
lModel:SetAttribute("Blocking", true)
press("RemoteJab")
check(#casts() == 0, "blocking: nothing")
lModel:SetAttribute("Blocking", false)
rest()

print("== The server's word")
press("RemoteJab")
mock.advance(J.Cooldown - 0.2)
serverSays("Denied", "RemoteJab", 3)
check((Loadout.cooldown("RemoteJab", os.clock())) >= 2.9, "Denied with time left: the server's cooldown shows")
rest()

print("== Other players")
local before = #H.played
t0 = now()
serverSays("WarpPunch", other, hole, t0 + W.PunchAt, t0 + W.HitDelay)
check(find(oParts["Right Arm"], "FistCharge") ~= nil, "their fist charges")
check(#H.played == before, "no animation on them (their own client plays it)")
mock.advance(W.HitDelay + 0.02)
check(find(warps(), "WarpFist") ~= nil, "their fist comes out of their hole")
serverSays("Stop", other)
mock.advance(0.3)
check(find(warps(), "WarpFist") == nil and count(warps(), "WarpHole") == 0, "their Stop closes theirs")
Players.PlayerRemoving:Fire(other)

H.finish("Leorio client")
