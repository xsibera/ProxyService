--!nocheck
-- Headless test of MeleeClient: the click (and holding it), the string's timing and buffering, the
-- animations, the swing trail, the step in, the hit effects and sounds, and the server's word.
-- Run from this folder:  cd Abilities/Melee && luaurun tests/client.luau

local H = assert(loadfile("tests/harness.luau"))()
local mock, check, near = H.mock, H.check, H.near
mock.isClient = true
local Config = require(H.Config)
local VFX = require(H.VFXModule)
local HITS = Config.Hits
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local camera = mock.newInstance("Camera", "Camera")
camera.CFrame = CFrame.lookAt(Vector3.new(8, 6, 8), Vector3.new(0, 3, 0)) -- looking at him from his front-right
camera.Parent = workspace
workspace.CurrentCamera = camera

local aModel, aParts = H.character("A", 0, 0, 0)
local a = H.player("A", aModel)
mock.newInstance("PlayerGui", "PlayerGui").Parent = a
Players.LocalPlayer = a
local oModel = H.character("Other", 20, 0, 0)
local other = H.player("Other", oModel)
local dModel = H.character("D", 0, -4, 180)

local client = mock.newInstance("LocalScript", "MeleeClient")
rawget(client, "__props").__path = "src/MeleeClient.client.luau"
client.Parent = a
mock.runScript(client)
mock.advance(0.05)

local root = aParts.HumanoidRootPart
local function click(processed)
	UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1 }, processed == true)
end
local function release()
	UIS.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 }, false)
end
local function m1s()
	return H.sent("M1", "client", H.remote)
end
local function lastPlayed()
	local p = H.played[#H.played]
	return p and p.name or ""
end
local function find(rootInstance, name)
	for _, d in ipairs(rootInstance:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
end
local function serverSays(...)
	H.remote.OnClientEvent:Fire(...)
end
local function rest()
	release()
	mock.advance(3)
	table.clear(H.remoteLog)
	table.clear(VFX.calls.Play)
	table.clear(VFX.calls.Swing)
	serverSays("Stop", aModel)
	table.clear(H.played)
	root.CFrame = CFrame.new(0, 3, 0)
end

print("== Boot")
check(H.registered == 5, "the five KeyframeSequences registered for Studio play (" .. H.registered .. ")")
local action = mock.actions.MeleeM1
check(
	action ~= nil and action.touch == true and action.inputs[1] == Config.GamepadButton,
	"gamepad R2 and a touch button"
)

print("== A click")
click()
check(#m1s() == 1, "asks the server")
check(lastPlayed() == "rbxassetid://temp-Fist M1_1", "the jab plays at once")
local swing = VFX.calls.Swing[1]
check(
	swing and swing.kind == "FistSwing" and swing.character == aModel and swing.track ~= nil,
	"the fist swing trail, on the track"
)
check(find(workspace.Terrain, "MeleeSound") ~= nil, "a swing sound")
check(root.CFrame.LookVector.X < -0.6 and root.CFrame.LookVector.Z < -0.6, "turned to face where the camera looks")
mock.advance(HITS[1].HitDelay - 0.07)
local lunge = find(root, "MeleeLunge")
local lv = lunge and lunge:FindFirstChildOfClass("LinearVelocity")
check(lv and near(lv.VectorVelocity.Magnitude, Config.Lunge, 1e-3), "steps in on the hit")
mock.advance(Config.LungeTime + 0.05)
check(find(root, "MeleeLunge") == nil, "the step ends")
rest()

print("== Clicking early is remembered")
click()
release()
mock.advance(HITS[1].Next - 0.2)
click()
release()
check(#m1s() == 1, "a click before the next hit opens: not sent yet")
mock.advance(0.25)
check(#m1s() == 2 and lastPlayed() == "rbxassetid://temp-Fist M1_2", "thrown as soon as it opens")
mock.advance(0.1)
click()
release()
check(#m1s() == 2, "way too early (more than the buffer): dropped")
mock.advance(1)
check(#m1s() == 2, "(and not thrown later)")
rest()

print("== Holding the button")
click()
local times = { os.clock() }
for _ = 1, 400 do
	mock.advance(1 / 60)
	if #m1s() > #times then
		table.insert(times, os.clock())
	end
	if #m1s() >= #HITS then
		break
	end
end
check(#m1s() == #HITS, "holding throws the whole string")
for i = 2, #HITS do
	check(near(times[i] - times[i - 1], HITS[i - 1].Next, 0.03), "hit " .. i .. " right as it opens")
end
check(lastPlayed() == "rbxassetid://temp-Fist M1_5", "the finisher")
mock.advance(Config.FinisherCooldown - 0.1)
check(#m1s() == #HITS, "the finisher's cooldown")
mock.advance(0.15)
check(#m1s() == #HITS + 1 and lastPlayed() == "rbxassetid://temp-Fist M1_1", "still holding: a new string")
release()
mock.advance(1)
check(#m1s() == #HITS + 1, "let go: it stops")
rest()

print("== Hits")
-- the hit sounds (Audio/HitSounds), with ids filled in: they play the hits instead of Melee.Sounds
local HitSounds =
	require(H.mock.module(game:GetService("ReplicatedStorage"), "HitSounds", "../../Audio/HitSounds/HitSounds.luau"))
HitSounds.Ids.FistHit = { 101, 102, 103 }
HitSounds.Ids.FistHeavy = { 201, 202 }
local function soundsIn(name)
	local out = {}
	for _, d in ipairs(workspace.Terrain:GetChildren()) do
		local s = d.Name == name and d:FindFirstChildOfClass("Sound")
		if s then
			table.insert(out, s)
		end
	end
	return out
end
local meleeBefore = #soundsIn("MeleeSound")
serverSays("Hit", aModel, dModel, 1, Vector3.new(0, 3, -4), "Hit")
local play = VFX.calls.Play[1]
check(play and play.name == "M1Hit", "M1Hit on a hit")
check(
	play and near(play.cframe.Position.Z, -4, 1e-3) and play.cframe.LookVector.Z < -0.99,
	"at the victim, along the hit"
)
check(play and table.find(play.options.Ignore, dModel) ~= nil, "the floor probe ignores the victim")
serverSays("Hit", aModel, dModel, 5, Vector3.new(0, 3, -4), "Hit")
check(VFX.calls.Play[2] and VFX.calls.Play[2].name == "M1Final", "M1Final on the finisher")
local hits = soundsIn("HitSound")
check(
	#hits == 2
		and string.match(hits[1].SoundId, "^rbxassetid://10%d$")
		and string.match(hits[2].SoundId, "^rbxassetid://20%d$"),
	"the hit sounds play the hit and the finisher (FistHit, FistHeavy)"
)
check(#soundsIn("MeleeSound") == meleeBefore, "instead of Melee.Sounds' own")
serverSays("Hit", aModel, dModel, 2, Vector3.new(0, 3, -4), "Blocked")
serverSays("Hit", aModel, dModel, 2, Vector3.new(0, 3, -4), "Parried")
check(#VFX.calls.Play == 2, "blocked and parried hits: none (Combat draws those)")
mock.advance(1 / 60)
local offset = aModel.Humanoid.CameraOffset
check(offset ~= nil and offset.Magnitude > 0, "your hit landing shakes the camera a little")
mock.advance(0.3)
check(aModel.Humanoid.CameraOffset == Vector3.zero, "and settles")
rest()

print("== Other players")
serverSays("M1", oModel, 3, workspace:GetServerTimeNow())
local theirs = VFX.calls.Swing[1]
check(
	theirs and theirs.character == oModel and theirs.track == nil and theirs.options.Duration > HITS[3].HitDelay,
	"their swing trail (watched for a while)"
)
check(#H.played == 0, "no animation played on them here (their own client does)")
rest()

print("== NPCs (bandits)")
local bandit = H.character("Bandit", -20, 0, 0)
serverSays("M1", bandit, 2, workspace:GetServerTimeNow())
check(H.playing(bandit, "Fist M1_2"), "an NPC's swing is animated here (no client of its own)")
local npcSwing = VFX.calls.Swing[#VFX.calls.Swing]
check(npcSwing and npcSwing.character == bandit and npcSwing.track ~= nil, "with its swing trail on the track")
serverSays("M1", bandit, 3, workspace:GetServerTimeNow())
check(H.playing(bandit, "Fist M1_3") and not H.playing(bandit, "Fist M1_2"), "the next hit takes over")
serverSays("Hit", bandit, aModel, 3, aParts.HumanoidRootPart.Position, "Hit")
mock.advance(1 / 60)
check(aModel.Humanoid.CameraOffset.Magnitude > 0, "being hit shakes the camera")
serverSays("Stop", bandit)
check(not H.playing(bandit, "Fist M1_3"), "a Stop ends its swing")
rest()

print("== The server's word")
click()
serverSays("Denied", 0)
local track = nil
for _, d in ipairs(aModel:GetDescendants()) do
	if d.ClassName == "AnimationTrack" and d.IsPlaying then
		track = d
	end
end
check(track == nil, "denied: the swing stops")
mock.advance(0.1)
click()
check(lastPlayed() == "rbxassetid://temp-Fist M1_1", "and the string starts from the server's count")
rest()
click()
mock.advance(0.2)
serverSays("Stop", aModel)
mock.advance(HITS[1].Next)
click()
check(lastPlayed() == "rbxassetid://temp-Fist M1_1", "stopped (stunned): the string starts over")
rest()

print("== Not now")
click(true)
check(#m1s() == 0, "a click on the UI: nothing")
aModel:SetAttribute("StunnedUntil", workspace:GetServerTimeNow() + 1)
click()
check(#m1s() == 0, "stunned: nothing")
aModel:SetAttribute("StunnedUntil", nil)
aModel:SetAttribute("Blocking", true)
click()
check(#m1s() == 0, "blocking: nothing")
aModel:SetAttribute("Blocking", false)
aModel:SetAttribute("BusyUntil", math.huge)
click()
check(#m1s() == 0, "busy with something else (charging Jajanken, say): nothing")
aModel:SetAttribute("MeleeUntil", math.huge)
click()
check(#m1s() == 1, "busy with the string itself: fine")
aModel:SetAttribute("BusyUntil", nil)
rest()

print("== Gamepad and touch")
action.fn("MeleeM1", Enum.UserInputState.Begin)
check(#m1s() == 1, "R2 / the Punch button")
action.fn("MeleeM1", Enum.UserInputState.End)
_ = other

H.finish("Melee client")
