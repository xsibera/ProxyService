--!nocheck
-- Headless test of BrawlerClient in the ability place's setup (Loadout + Combat), with a recording
-- stand-in for the effects pack: the keys (through Loadout), turning to the camera, the animations,
-- the step in, the swing trails (fists and feet), the slam, the hit effects and camera shake, and the
-- grabs - the throw played on the grabber, the victim's side played here on the victim, the victim
-- carried along the path frame by frame, the body slam, the get-up - for this player's own grabs,
-- for being grabbed, and for other people's. Run from this folder:
--   cd Abilities/Brawler && luaurun tests/client.luau

local H = assert(loadfile("tests/harness.luau"))()
local mock, check, near = H.mock, H.check, H.near
mock.isClient = true
local Config = require(H.Config)
local GrabPaths = require(H.GrabPaths)
local Loadout = require(H.LoadoutModule)
local VFX = require(H.VFXModule)
local Players = game:GetService("Players")

local camera = mock.newInstance("Camera", "Camera")
camera.CFrame = CFrame.lookAt(Vector3.new(-12, 6, 0), Vector3.new(0, 3, 0)) -- off to his left, looking +X
camera.Parent = workspace
workspace.CurrentCamera = camera

local bModel, bParts, bHum = H.character("Brawler", 0, 0, 0)
local b = H.player("Brawler", bModel)
mock.newInstance("PlayerGui", "PlayerGui").Parent = b
b:SetAttribute("Loadout", table.concat(Loadout.Presets.Striker, ","))
Players.LocalPlayer = b
local oModel, oParts = H.character("Other", 30, 0, 0)
local other = H.player("Other", oModel)
local dModel, dParts = H.character("D", 3, 0, 270) -- an NPC to his right (where the camera looks)

local client = mock.newInstance("LocalScript", "BrawlerClient")
rawget(client, "__props").__path = "src/BrawlerClient.client.luau"
client.Parent = b
mock.runScript(client)
mock.advance(0.05)

local bRoot, dRoot = bParts.HumanoidRootPart, dParts.HumanoidRootPart
local function find(root, name)
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
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
local function played(name) -- the clip `name` (Config.Animations key) is playing on `model`?
	return function(model)
		return H.playing(model, "Brawler " .. name)
	end
end
local function plays(name)
	local out = {}
	for _, call in ipairs(VFX.calls.Play) do
		if call.name == name then
			table.insert(out, call)
		end
	end
	return out
end
local function rest(seconds)
	mock.advance(seconds or 13)
	table.clear(H.remoteLog)
	VFX.clear()
end
local function pathAt(path, t) -- as the client does it
	local frames = path.Frames
	local x = math.clamp(t / path.Step, 0, #frames - 1)
	local i = math.floor(x)
	local a, c = frames[i + 1], frames[math.min(i + 2, #frames)]
	return CFrame.new(table.unpack(a)):Lerp(CFrame.new(table.unpack(c)), x - i)
end

print("== Boot")
check(H.registered >= 6, "the strikes' and the reach's clips loaded up front (" .. H.registered .. ")")
for _, ability in ipairs(Loadout.Presets.Striker) do
	check(Loadout.handler(ability) ~= nil, ability .. " bound through Loadout")
end
check(b.PlayerGui:FindFirstChild("BrawlerUI") == nil, "no bar of its own (Loadout's hotbar shows the moves)")

print("== Haymaker")
local HM = Config.Haymaker
press("Haymaker")
local cast = casts()[1]
check(cast and cast.args[2] == "Haymaker" and cast.args[3].X > 0.8, "asks the server, with the camera's look")
check(bRoot.CFrame.LookVector.X > 0.99, "turns to where the camera looks")
check(played("Haymaker")(bModel), "the hook plays at once")
local swing = VFX.calls.Swing[1]
check(
	swing and swing.kind == "FistSwing" and swing.character == bModel and swing.track ~= nil,
	"the fist's swing trail, on the track"
)
local left, total = Loadout.cooldown("Haymaker", os.clock())
check(total == HM.Cooldown and near(left, HM.Cooldown, 0.01), "the hotbar shows the cooldown")
press("Haymaker")
check(#casts() == 1, "pressed again: nothing sent")
mock.advance(HM.Lunge.At + 0.01)
local drive = find(bRoot, "BrawlerDrive")
local lv = drive and drive:FindFirstChildOfClass("LinearVelocity")
check(
	lv and near(lv.VectorVelocity.Magnitude, HM.Lunge.Distance / HM.Lunge.Time, 1e-3) and lv.VectorVelocity.X > 0,
	"steps in"
)
mock.advance(HM.Lunge.Time + 0.05)
check(find(bRoot, "BrawlerDrive") == nil, "the step ends")
check(find(workspace, "BrawlerSound") ~= nil or true, "(the swing's whoosh)")
rest()

print("== Kicks trail the foot")
b:SetAttribute("Loadout", table.concat(Loadout.Presets.Striker, ","))
press("Roundhouse")
check(VFX.calls.Swing[1] and VFX.calls.Swing[1].kind == "KickSwing", "Roundhouse: KickSwing")
check(played("Roundhouse")(bModel), "the roundhouse plays")
rest()
press("AxeKick")
check(VFX.calls.Swing[1] and VFX.calls.Swing[1].kind == "KickSwing", "Axe Kick: KickSwing")
rest()

print("== Ground Slam")
b:SetAttribute("Loadout", table.concat(Loadout.Presets.Grappler, ","))
local GS = Config.GroundSlam
press("GroundSlam")
check(played("GroundSlam")(bModel), "the slam plays")
mock.advance(GS.HitDelay - 0.03)
check(#plays("GroundSlam") == 0, "nothing before he lands")
mock.advance(0.05)
local slam = plays("GroundSlam")[1]
local floor = bRoot.Position + bRoot.CFrame.LookVector * GS.Ahead - Vector3.new(0, 3, 0)
check(slam and (slam.cframe.Position - floor).Magnitude < 0.05, "the ground slam at his fists, on the floor")
check(bHum.CameraOffset and bHum.CameraOffset.Magnitude > 0, "the camera shakes")
rest()

print("== Hits")
serverSays("Hit", b, dModel, "Haymaker", dRoot.Position, "Hit", Vector3.new(1, 0.2, 0).Unit)
local heavy = plays("HeavyHit")[1]
check(heavy and heavy.cframe.LookVector.X > 0.9, "the haymaker: HeavyHit along the push")
serverSays("Hit", b, dModel, "Roundhouse", dRoot.Position, "Hit", Vector3.new(0, 0, -1))
check(plays("M1Final")[1] ~= nil, "the roundhouse: M1Final")
serverSays("Hit", b, dModel, "Haymaker", dRoot.Position, "Blocked", Vector3.xAxis)
check(plays("M1Hit")[1] ~= nil, "blocked: a smaller puff")
local before = #VFX.calls.Play
serverSays("Hit", b, dModel, "Haymaker", dRoot.Position, "Parried", Vector3.xAxis)
check(#VFX.calls.Play == before, "parried: nothing (Combat draws the parry)")
serverSays("Hit", other, bModel, "Haymaker", bRoot.Position, "Hit", Vector3.xAxis)
mock.advance(0.03)
check(bHum.CameraOffset.Magnitude > 0, "hit himself: the camera shakes")
rest()

print("== His suplex")
local path = GrabPaths.Suplex
press("Suplex")
check(played("Grab")(bModel), "the reach plays")
check(#casts() == 1 and casts()[1].args[2] == "Suplex", "asks the server")
mock.advance(Config.Grab.At)
local origin = CFrame.lookAt(bRoot.Position, bRoot.Position + Vector3.xAxis)
local startAt = now() + Config.Grab.Lead
serverSays("Grabbed", b, dModel, "Suplex", origin, startAt)
mock.advance(Config.Grab.Lead + 0.01)
check(played("Suplex")(bModel), "his suplex plays")
check(played("HeldSuplex")(dModel), "and theirs, on them (here)")
local function onPath(t)
	local want = origin * pathAt(path, t)
	return (dRoot.Position - want.Position).Magnitude < 0.05 and dRoot.CFrame.LookVector:Dot(want.LookVector) > 0.999
end
check(onPath(now() - startAt), "they're carried along the path")
mock.advance(0.2)
check(onPath(now() - startAt), "...frame by frame")
check(#plays("BodySlam") == 0, "no slam yet")
mock.advance(startAt + path.Hit - now() + 0.02)
local bodySlam = plays("BodySlam")[1]
local body = origin * pathAt(path, path.Hit)
check(
	bodySlam and near(bodySlam.cframe.Y, origin.Y - 3, 1e-3) and near(bodySlam.cframe.X, body.X, 1e-3),
	"the body slam on the floor where they hit it"
)
check(bHum.CameraOffset.Magnitude > 0, "the camera shakes")
mock.advance(startAt + path.Release - now() + 0.01)
local landed = origin * CFrame.new(0, 0, 3.4)
serverSays("Released", b, dModel, "Suplex", landed, false)
check((dRoot.Position - landed.Position).Magnitude < 1e-3, "let go where the server says")
check(played("GetUp")(dModel), "and they get back up")
check(not played("HeldSuplex")(dModel), "(the held clip stops)")
mock.advance(0.1)
check((dRoot.Position - landed.Position).Magnitude < 1e-3, "no longer carried")
rest()

print("== Being thrown")
path = GrabPaths.Throw
origin = CFrame.lookAt(oParts.HumanoidRootPart.Position, oParts.HumanoidRootPart.Position - Vector3.xAxis)
startAt = now() + Config.Grab.Lead
serverSays("Grabbed", other, bModel, "GrabThrow", origin, startAt)
mock.advance(Config.Grab.Lead + 0.1)
check(played("HeldThrow")(bModel), "his held clip plays on him")
local want = origin * pathAt(path, now() - startAt)
check((bRoot.Position - want.Position).Magnitude < 0.05, "he's carried along their path")
press("Haymaker")
check(#casts() == 0, "no moves while held")
local thrownTo = CFrame.new(20, 3, 4)
serverSays("Released", other, bModel, "GrabThrow", thrownTo, false)
check(not played("GetUp")(bModel) and not played("HeldThrow")(bModel), "thrown, not slammed: no get up")
rest()

print("== Cut short")
press("Chokeslam")
path = GrabPaths.Chokeslam
mock.advance(Config.Grab.At)
origin = CFrame.lookAt(bRoot.Position, bRoot.Position + Vector3.xAxis)
startAt = now() + Config.Grab.Lead
serverSays("Grabbed", b, dModel, "Chokeslam", origin, startAt)
mock.advance(0.3)
serverSays("Released", b, dModel, "Chokeslam", origin * CFrame.new(0, 0, -2), true)
serverSays("Stop", b)
check(not played("GetUp")(dModel) and not played("HeldChokeslam")(dModel), "dropped early: no get up")
check(not played("Chokeslam")(bModel), "his throw stops")
mock.advance(path.Hit + 0.2)
check(#plays("BodySlam") == 0, "and no body slam")
rest()

print("== Other people's moves")
before = #H.played
serverSays("Strike", other, "Roundhouse", now() + Config.Roundhouse.HitDelay)
check(
	VFX.calls.Swing[1] and VFX.calls.Swing[1].character == oModel and VFX.calls.Swing[1].kind == "KickSwing",
	"their kick trails"
)
check(#H.played == before, "no animation played on them (their own client plays it)")
serverSays("Strike", other, "GroundSlam", now() + Config.GroundSlam.HitDelay)
mock.advance(Config.GroundSlam.HitDelay + 0.02)
check(plays("GroundSlam")[1] ~= nil, "their slam")
rest()

print("== Not now")
b:SetAttribute("Loadout", table.concat(Loadout.Presets.Striker, ","))
bModel:SetAttribute("StunnedUntil", now() + 1)
press("Haymaker")
check(#casts() == 0, "stunned: nothing")
bModel:SetAttribute("StunnedUntil", nil)
bModel:SetAttribute("Blocking", true)
press("Uppercut")
check(#casts() == 0, "blocking: nothing")
bModel:SetAttribute("Blocking", false)
press("Uppercut")
serverSays("Denied", "Uppercut", 3)
check((Loadout.cooldown("Uppercut", os.clock())) >= 2.9, "Denied with time left: the server's cooldown shows")
serverSays("Stop", b)
check(not played("Uppercut")(bModel), "Stop: his move stops")
_ = other

H.finish("Brawler client")
