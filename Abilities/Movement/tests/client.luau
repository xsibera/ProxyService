--!nocheck
-- Headless test of MovementClient: sprinting (Left Ctrl, double-tap W, the toggle), its animation
-- played at the speed really gone, giving way to whatever else sets the walk speed; rolling (the way
-- you move, the push, the animation, the effects, the cooldown, not while stunned or mid-attack);
-- jumping, falling and landing (from the Humanoid's states, the landing as hard as the fall);
-- everyone's run dust.
-- Run from this folder:  cd Abilities/Movement && luaurun tests/client.luau

local H = assert(loadfile("tests/harness.luau"))()
local mock, check, near = H.mock, H.check, H.near
mock.isClient = true
local Config = require(H.Config)
local VFX = require(H.VFXModule)
local ROLL = Config.Roll
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local camera = mock.newInstance("Camera", "Camera")
camera.CFrame = CFrame.new(0, 6, 12)
camera.FieldOfView = 70
camera.Parent = workspace
workspace.CurrentCamera = camera

local aModel, aParts, hum = H.character("A", 0, 0, 0)
local a = H.player("A", aModel)
mock.newInstance("PlayerGui", "PlayerGui").Parent = a
Players.LocalPlayer = a
hum.WalkSpeed = Config.WalkSpeed
hum.MoveDirection = Vector3.zero
hum.FloorMaterial = Enum.Material.Grass
local oModel, oParts, oHum = H.character("Other", 20, 0, 0)
local other = H.player("Other", oModel)
oHum.FloorMaterial = Enum.Material.Grass

local client = mock.newInstance("LocalScript", "MovementClient")
rawget(client, "__props").__path = "src/MovementClient.client.luau"
client.Parent = a
mock.runScript(client)
mock.advance(0.05)

local root = aParts.HumanoidRootPart
local function key(code, down)
	if down then
		UIS.InputBegan:Fire({ KeyCode = code, UserInputType = Enum.UserInputType.Keyboard }, false)
	else
		UIS.InputEnded:Fire({ KeyCode = code, UserInputType = Enum.UserInputType.Keyboard }, false)
	end
end
local function playing(name)
	return H.playing(aModel, name)
end
local function track(name)
	for _, t in ipairs(H.tracks) do
		local props = rawget(t, "__props")
		if props.__model == aModel and props.__kfs == "rbxassetid://temp-" .. name then
			return props
		end
	end
end
local function lastPlay(name)
	for i = #H.played, 1, -1 do
		local p = H.played[i]
		if p.model == aModel and p.name == "rbxassetid://temp-" .. name then
			return p
		end
	end
end
local function state(new)
	hum.StateChanged:Fire(Enum.HumanoidStateType.Running, new)
end
local function rolls()
	return H.sent("Roll", "client", H.remote)
end
local function find(rootInstance, name)
	for _, d in ipairs(rootInstance:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
end
local function started(name)
	for _, call in ipairs(VFX.calls.Start) do
		if call.name == name then
			return call
		end
	end
end
local function played(name)
	for _, call in ipairs(VFX.calls.Play) do
		if call.name == name then
			return call
		end
	end
end

print("== Boot")
check(H.registered == 5, "Sprint, Roll, Jump, Fall and Land registered for Studio play")
check(mock.actions.MovementRoll and mock.actions.MovementRoll.inputs[1] == ROLL.Key, "Q rolls")
check(mock.actions.MovementSprint and mock.actions.MovementSprint.touch == true, "a Sprint button on touch")

print("== Sprinting with Left Ctrl")
key(Enum.KeyCode.LeftControl, true)
mock.advance(0.05)
check(hum.WalkSpeed == Config.WalkSpeed, "standing still: no sprint")
hum.MoveDirection = Vector3.new(0, 0, -1)
mock.advance(0.05)
check(hum.WalkSpeed == Config.SprintSpeed, "moving: sprinting")
check(playing("Sprint"), "the run plays")
root.AssemblyLinearVelocity = Vector3.new(0, 0, -Config.RunAnimationSpeed)
mock.advance(0.05)
check(near(track("Sprint").Speed, 1, 1e-3), "at full speed: the run at its own speed")
root.AssemblyLinearVelocity = Vector3.new(0, 0, -0.8 * Config.RunAnimationSpeed)
mock.advance(0.05)
check(near(track("Sprint").Speed, 0.8, 1e-3), "slower: the run slows to match (the feet stay planted)")
root.AssemblyLinearVelocity = Vector3.zero
hum.WalkSpeed = 10 -- swinging (the server slows them)
mock.advance(0.05)
check(hum.WalkSpeed == 10, "something else sets the walk speed: it wins")
check(not playing("Sprint"), "and the run stops")
hum.WalkSpeed = Config.WalkSpeed -- the swing ends
mock.advance(0.05)
check(hum.WalkSpeed == Config.SprintSpeed and playing("Sprint"), "still holding Ctrl: sprinting again")
key(Enum.KeyCode.LeftControl, false)
mock.advance(0.05)
check(hum.WalkSpeed == Config.WalkSpeed and not playing("Sprint"), "let go: walking")

print("== Double-tap W")
key(Enum.KeyCode.W, true)
key(Enum.KeyCode.W, false)
mock.advance(0.1)
key(Enum.KeyCode.W, true)
mock.advance(0.05)
check(hum.WalkSpeed == Config.SprintSpeed, "tap-tap and hold: sprinting")
key(Enum.KeyCode.W, false)
mock.advance(0.05)
check(hum.WalkSpeed == Config.WalkSpeed, "let go: walking")
key(Enum.KeyCode.W, true)
key(Enum.KeyCode.W, false)
mock.advance(0.5)
key(Enum.KeyCode.W, true)
mock.advance(0.05)
check(hum.WalkSpeed == Config.WalkSpeed, "two slow taps: walking")
key(Enum.KeyCode.W, false)

print("== The toggle (gamepad, touch)")
mock.actions.MovementSprint.fn("MovementSprint", Enum.UserInputState.Begin)
mock.advance(0.05)
check(hum.WalkSpeed == Config.SprintSpeed, "on")
mock.actions.MovementSprint.fn("MovementSprint", Enum.UserInputState.Begin)
mock.advance(0.05)
check(hum.WalkSpeed == Config.WalkSpeed, "off")

print("== Rolling")
hum.MoveDirection = Vector3.new(1, 0, 0)
VFX.clear()
mock.actions.MovementRoll.fn("MovementRoll", Enum.UserInputState.Begin)
local r = rolls()[1]
check(r and r.args[2] == Vector3.new(1, 0, 0), "asks the server, the way you're moving")
check(root.CFrame.LookVector.X > 0.99, "turned to roll that way")
check(playing("Roll"), "the roll plays")
local push = find(root, "MovementRoll")
local lv = push and push:FindFirstChildOfClass("LinearVelocity")
check(
	lv and lv.VelocityConstraintMode == Enum.VelocityConstraintMode.Plane,
	"pushed along the floor only (gravity still works)"
)
check(lv and near(lv.PlaneVelocity.X, ROLL.Speed, 1e-3), "at Speed")
check(played("DashBurst") ~= nil and started("DashTrail") ~= nil, "a burst and a trail")
mock.advance(ROLL.Time / 2)
check(lv and lv.PlaneVelocity.X < ROLL.Speed * 0.8 and lv.PlaneVelocity.X > 0, "easing off")
mock.advance(ROLL.Time / 2 + 0.05)
check(find(root, "MovementRoll") == nil, "the push ends")
check(started("DashTrail").stopped and played("Land") ~= nil, "the trail stops, dust where you come up")
mock.actions.MovementRoll.fn("MovementRoll", Enum.UserInputState.Begin)
check(#rolls() == 1, "again too soon: no")
mock.advance(ROLL.Cooldown)
hum.MoveDirection = Vector3.zero
mock.actions.MovementRoll.fn("MovementRoll", Enum.UserInputState.Begin)
check(#rolls() == 2 and rolls()[2].args[2].X > 0.99, "standing still: rolls the way you face")
mock.advance(ROLL.Cooldown + 0.1)

print("== Sprinting into a roll")
key(Enum.KeyCode.LeftControl, true)
hum.MoveDirection = Vector3.new(0, 0, -1)
mock.advance(0.05)
mock.actions.MovementRoll.fn("MovementRoll", Enum.UserInputState.Begin)
mock.advance(0.05)
check(hum.WalkSpeed == Config.WalkSpeed, "the sprint pauses for the roll")
mock.advance(ROLL.Time)
check(hum.WalkSpeed == Config.SprintSpeed, "and picks up again after")
key(Enum.KeyCode.LeftControl, false)
mock.advance(ROLL.Cooldown)

print("== Not now")
aModel:SetAttribute("StunnedUntil", workspace:GetServerTimeNow() + 1)
mock.actions.MovementRoll.fn("MovementRoll", Enum.UserInputState.Begin)
aModel:SetAttribute("StunnedUntil", nil)
aModel:SetAttribute("BusyUntil", workspace:GetServerTimeNow() + 1)
mock.actions.MovementRoll.fn("MovementRoll", Enum.UserInputState.Begin)
aModel:SetAttribute("BusyUntil", nil)
check(#rolls() == 3, "stunned or mid-attack: no roll")
H.remote.OnClientEvent:Fire("Denied", 2)
mock.actions.MovementRoll.fn("MovementRoll", Enum.UserInputState.Begin)
check(#rolls() == 3, "the server says wait: waits")
mock.advance(2.1)

print("== Jumping, falling, landing")
local AIR = Config.Air
hum.MoveDirection = Vector3.zero
state(Enum.HumanoidStateType.Jumping)
check(playing("Jump") and not playing("Fall"), "jump: the jump plays")
state(Enum.HumanoidStateType.Freefall)
root.AssemblyLinearVelocity = Vector3.new(0, 40, 0)
mock.advance(0.2)
check(playing("Jump") and not playing("Fall"), "rising: still the jump")
mock.advance(0.3)
check(playing("Fall"), "the jump done, still in the air: the fall pose")
root.AssemblyLinearVelocity = Vector3.new(0, -53, 0)
mock.advance(0.1)
root.AssemblyLinearVelocity = Vector3.zero
VFX.clear()
state(Enum.HumanoidStateType.Landed)
check(not playing("Jump") and not playing("Fall"), "landed: the air poses stop")
local landing = lastPlay("Land")
check(playing("Land") and landing.weight == 1 and landing.speed == 1, "standing still: the full landing")
check(played("Land") == nil, "a normal jump: no dust")
state(Enum.HumanoidStateType.Running)
check(lastPlay("Land") == landing, "running after landing: no second landing")
mock.advance(0.6)

state(Enum.HumanoidStateType.Freefall) -- walked off an edge
mock.advance(AIR.FallDelay / 2)
check(not playing("Fall") and not playing("Jump"), "off an edge: no jump, and no fall pose straight away")
mock.advance(AIR.FallDelay)
check(playing("Fall") and lastPlay("Fall").fade == 0.25, "a moment later: the fall pose eases in")
root.AssemblyLinearVelocity = Vector3.new(0, -12, 0)
mock.advance(0.05)
root.AssemblyLinearVelocity = Vector3.zero
local before = lastPlay("Land")
state(Enum.HumanoidStateType.Landed)
check(lastPlay("Land") == before and not playing("Fall"), "a step down: no landing")

state(Enum.HumanoidStateType.Jumping)
hum.MoveDirection = Vector3.new(0, 0, -1)
root.AssemblyLinearVelocity = Vector3.new(0, -53, -26)
mock.advance(0.1)
state(Enum.HumanoidStateType.Landed)
landing = lastPlay("Land")
check(
	landing ~= before and near(landing.weight, AIR.MovingLandWeight, 1e-3) and landing.speed == AIR.MovingLandSpeed,
	"landing on the move: lighter and quicker"
)
hum.MoveDirection = Vector3.zero
root.AssemblyLinearVelocity = Vector3.zero
mock.advance(0.6)

state(Enum.HumanoidStateType.Freefall)
root.AssemblyLinearVelocity = Vector3.new(0, -95, 0)
mock.advance(0.5)
VFX.clear()
state(Enum.HumanoidStateType.Landed)
check(played("Land") ~= nil and played("Land").options.Ignore[1] == aModel, "a long drop: dust where you land")
root.AssemblyLinearVelocity = Vector3.zero
mock.advance(0.6)

state(Enum.HumanoidStateType.Jumping)
mock.advance(0.5)
state(Enum.HumanoidStateType.Climbing)
check(not playing("Jump") and not playing("Fall"), "grabbing a ladder mid-air: the air poses stop")
before = lastPlay("Land")
state(Enum.HumanoidStateType.Landed)
check(lastPlay("Land") == before, "and no landing after")
mock.advance(0.1)

print("== Everyone")
VFX.clear()
H.remote.OnClientEvent:Fire("Roll", other, Vector3.new(0, 0, 1))
check(played("DashBurst") and played("DashBurst").options.Ignore[1] == oModel, "someone else's roll: its burst")
check(started("DashTrail") and started("DashTrail").part == oParts.HumanoidRootPart, "and trail")
oParts.HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(Config.SprintSpeed, 0, 0)
mock.advance(0.05)
local dust = started("RunDust")
check(dust and dust.part == oParts.HumanoidRootPart, "someone running fast: dust")
oParts.HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
mock.advance(0.05)
check(dust and dust.stopped, "they stop: it stops")
_ = other

H.finish("Movement client")
