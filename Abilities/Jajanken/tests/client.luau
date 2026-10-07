--!nocheck
-- Headless test of JajankenClient + JajankenVFX against Place1's mock engine, with the real effect
-- tree: the keys, the animations, the predicted charge (aura, hand, bar, chant), the release, the
-- auto-release at full charge, and every server event drawn (other players' charges, casts, the
-- Paper ball's flight and burst, hits, denials). Run from this folder:
--   cd Abilities/Jajanken && luaurun tests/client.luau

local H = assert(loadfile("tests/harness.luau"))()
local mock, check, near = H.mock, H.check, H.near
mock.isClient = true
local Config = require(H.Config)
local Players = game:GetService("Players")

local camera = mock.newInstance("Camera", "Camera")
camera.CFrame = CFrame.new(0, 6, 12)
camera.Parent = workspace
workspace.CurrentCamera = camera

local gonModel, gonParts, gonHumanoid = H.character("Gon", 0, 0, 0)
local gon = H.player("Gon", gonModel)
mock.newInstance("PlayerGui", "PlayerGui").Parent = gon
Players.LocalPlayer = gon

local killuaModel, killuaParts = H.character("Killua", 10, 0, 0)
local killua = H.player("Killua", killuaModel)

local client = mock.newInstance("LocalScript", "JajankenClient")
rawget(client, "__props").__path = "src/JajankenClient.client.luau"
client.Parent = gon
mock.runScript(client)
mock.advance(0.05)

local function count(root, name)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then
			n += 1
		end
	end
	return n
end
local function find(root, name)
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
end
local function lastPlayed()
	local p = H.played[#H.played]
	return p and p.name or ""
end
local function press(mode, state)
	mock.actions["Jajanken" .. mode].fn("Jajanken" .. mode, state)
end
local function serverSays(...)
	H.remote.OnClientEvent:Fire(...)
end

print("== Boot")
check(H.registered == 5, "the five KeyframeSequences registered for Studio play (" .. H.registered .. ")")
for _, mode in ipairs(Config.Modes) do
	local action = mock.actions["Jajanken" .. mode]
	check(action ~= nil and action.touch == true, mode .. " bound, with a touch button")
	check(action and action.inputs[1] == Config.Keys[mode], mode .. " on " .. Config.Keys[mode].Name)
end
local gui = gon.PlayerGui:FindFirstChild("JajankenUI")
check(gui ~= nil, "charge bar UI created")
local bar = find(gui, "Bar")
local chant = find(gui, "Chant")
check(bar.Visible == false, "bar hidden until charging")

print("== Hold Rock")
press("Rock", Enum.UserInputState.Begin)
local sent = H.sent("Charge", "client")
check(#sent == 1 and sent[1].args[2] == "Rock", "asks the server to charge Rock")
check(lastPlayed():find("Charge") ~= nil, "charge animation plays at once")
check(find(gonParts.HumanoidRootPart, "Aura") ~= nil, "aura on the body")
local hand = find(gonParts["Right Arm"], "RockCharge")
check(hand ~= nil and near(hand.CFrame.Position.Y, -1.05), "Rock charge at the fist")
check(#H.stateEnabled > 0 and H.stateEnabled[#H.stateEnabled].enabled == false, "jumping off while charging")
mock.advance(0.5)
check(lastPlayed():find("Hold") ~= nil, "then the hold loop")
check(bar.Visible and chant.Text == "Saisho wa guu...", "bar up, chanting")
local lines = find(gonParts.HumanoidRootPart, "PowerLines")
local flame = find(gonParts.HumanoidRootPart, "Flame")
check(lines.Enabled == false, "power lines wait for 35% charge")
local lowRate = flame.Rate
mock.advance(1.0)
check(lines.Enabled == true, "power lines on at 50%")
check(flame.Rate > lowRate, "the aura thickens as it charges")
check(chant.Text == "Jan...", "Jan...")
check(find(gonParts.HumanoidRootPart, "FullPower").Enabled == false, "full-power layer still waiting")

print("== Let go")
press("Rock", Enum.UserInputState.End)
local release = H.sent("Release", "client")
check(#release == 1 and typeof(release[1].args[2]) == "Vector3", "release sent with the camera aim")
check(lastPlayed():find("Rock") ~= nil, "Rock release animation")
check(chant.Text == "GUU!" and bar.Visible == false, "GUU!")
check(flame.Enabled == false, "aura stops")
check(find(gonParts["Right Arm"], "Fire").Enabled == true, "the fist keeps burning up to the hit")
mock.advance(Config.Rock.HitDelay + 0.05)
check(
	find(gonParts["Right Arm"], "Fire") == nil or find(gonParts["Right Arm"], "Fire").Enabled == false,
	"and goes out after it"
)

print("== Server events for the cast")
local now = workspace:GetServerTimeNow()
serverSays("Cast", gon, "Rock", 0.5, now + Config.Rock.HitDelay)
check(find(workspace, "ReleaseVFX") ~= nil, "release flare at once")
check(find(workspace, "RockBlastVFX") == nil, "blast waits for the hit")
mock.advance(Config.Rock.HitDelay + 0.02)
local blast = find(workspace, "RockBlastVFX")
check(blast ~= nil, "Rock blast at the hit")
check(blast and blast.CFrame.Position.Z < -3.5, "out at the fist")
check(blast and find(blast, "Rocks") ~= nil, "charged enough for rocks")
local ground = blast and find(blast, "Ground")
check(ground and rawget(ground, "__props").WorldCFrame ~= nil, "ground layers dropped onto the floor")
check(count(workspace, "RockHit") == 1, "Rock hit sound")
H.played = {}
press("Rock", Enum.UserInputState.Begin)
check(#H.sent("Charge", "client") == 1 and #H.played == 0, "on cooldown: no new charge")
mock.advance(3)

print("== Full charge releases itself")
mock.advance(Config.Cooldown.Rock)
table.clear(H.remoteLog)
press("Paper", Enum.UserInputState.Begin)
check(find(gonParts["Right Arm"], "PaperCharge") ~= nil, "Paper charge in the palm")
mock.advance(Config.MaxCharge + 0.05)
check(#H.sent("Release", "client") == 1, "released at MaxCharge without letting go")
check(chant.Text == "PAA!", "PAA!")
press("Paper", Enum.UserInputState.End)
check(#H.sent("Release", "client") == 1, "letting go afterwards sends nothing")
serverSays("Cast", gon, "Paper", 1, workspace:GetServerTimeNow() + Config.Paper.HitDelay)
check(lastPlayed():find("Paper") ~= nil, "Paper release animation (once)")

print("== The ball")
local from, direction = Vector3.new(0, 3, -3), Vector3.new(0, 0, -1)
local launchAt = workspace:GetServerTimeNow()
serverSays("Launch", gon, 7, from, direction, 100, 140, launchAt, 1)
local ball = find(workspace, "PaperBallProjectile")
check(ball ~= nil, "ball created")
mock.advance(0.5)
check(
	ball and near(ball.CFrame.Position.Z, -3 - 50, 2),
	"flies along the server's line (z " .. (ball and ball.CFrame.Position.Z or 0) .. ")"
)
check(find(ball, "Orb").Enabled == true, "glowing in flight")
serverSays("Explode", gon, 7, Vector3.new(0, 3, -53), 1)
check(find(ball, "Orb") == nil or find(ball, "Orb").Enabled == false, "stops at the burst")
check(find(workspace, "PaperBlastVFX") ~= nil, "Paper blast")
check(find(find(workspace, "PaperBlastVFX"), "Scorch") ~= nil, "full charge leaves a scorch")
mock.advance(3)
check(find(workspace, "PaperBallProjectile") == nil, "ball cleaned up")

print("== Someone else charging")
serverSays("Charge", killua, "Scissors", workspace:GetServerTimeNow())
check(find(killuaParts.HumanoidRootPart, "Aura") ~= nil, "their aura")
check(find(killuaParts["Right Arm"], "ScissorsCharge") ~= nil, "their scissors blade")
mock.advance(1.5)
local theirLines = find(killuaParts.HumanoidRootPart, "PowerLines")
check(theirLines.Enabled == true, "their aura builds from the server's clock")
serverSays("Cast", killua, "Scissors", 0.5, workspace:GetServerTimeNow() + Config.Scissors.HitDelay)
mock.advance(Config.Scissors.HitDelay + 0.02)
check(find(workspace, "ScissorsSlashVFX") ~= nil, "their slash")
check(
	find(killuaParts.HumanoidRootPart, "Flame") == nil or find(killuaParts.HumanoidRootPart, "Flame").Enabled == false,
	"their aura stops"
)
serverSays("Charge", killua, "Rock", workspace:GetServerTimeNow())
serverSays("Stop", killua)
mock.advance(2)
check(find(killuaParts["Right Arm"], "RockCharge") == nil, "a cancelled charge is cleaned up")

print("== Hits and denials")
serverSays("Hit", killuaModel, "Rock", Vector3.new(10, 3, 0), Vector3.new(0, 0.3, -1).Unit)
check(find(workspace, "NenHitVFX") ~= nil, "hit effect on the victim")
mock.advance(Config.SharedCooldown + 5)
press("Scissors", Enum.UserInputState.Begin)
check(find(gonParts["Right Arm"], "ScissorsCharge") ~= nil, "charging Scissors")
serverSays("Denied", "Scissors", 2)
check(bar.Visible == false and find(gonParts["Right Arm"], "ScissorsCharge") ~= nil, "denied: the charge is dropped")
mock.advance(1)
press("Scissors", Enum.UserInputState.End)
check(#H.sent("Release", "client") == 1, "nothing to release after a denial")
table.clear(H.remoteLog)
press("Scissors", Enum.UserInputState.Begin)
check(#H.sent("Charge", "client") == 0, "and it honours the time the server gave")
mock.advance(1.5)

print("== Dying mid-charge")
table.clear(H.remoteLog)
press("Rock", Enum.UserInputState.Begin)
check(#H.sent("Charge", "client") == 1, "charging")
gonHumanoid.Health = 0
check(#H.sent("Cancel", "client") == 1, "tells the server")
check(bar.Visible == false, "bar gone")

H.finish("Jajanken client test")
