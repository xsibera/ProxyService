--!nocheck
-- Boots the real client scripts against the mock engine, presses buttons and feeds server
-- events, and fails on any error or warning. Run from the Place1 folder:
--   luaurun tests/client_smoke.luau

local mock = assert(loadfile("tests/mock.luau"))()
mock.isClient = true

local failures, passes = 0, 0
local function check(cond, msg)
	if cond then
		passes += 1
	else
		failures += 1
		print("  FAIL: " .. msg)
	end
end

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local combatFolder = mock.newInstance("Folder", "Combat")
combatFolder.Parent = RS
for _, name in ipairs({ "Config", "Util", "AnimationData", "ProceduralAnimator", "VFX", "SFX", "SoundIds" }) do
	mock.module(combatFolder, name, "src/ReplicatedStorage/Combat/" .. name .. ".luau")
end
local remotes = mock.newInstance("Folder", "Remotes")
remotes.Parent = combatFolder
local actionRemote = mock.newInstance("RemoteEvent", "Action")
actionRemote.Parent = remotes
local fxRemote = mock.newInstance("RemoteEvent", "FX")
fxRemote.Parent = remotes

local Config = require(combatFolder.Config)

-- camera
local camera = mock.newInstance("Camera", "Camera")
camera.CFrame = CFrame.new(0, 8, 20)
camera.FieldOfView = 70
camera.Parent = workspace
workspace.CurrentCamera = camera

-- local player + character
local player = mock.newInstance("Player", "Tester")
player.DisplayName = "Tester"
mock.newInstance("PlayerGui", "PlayerGui").Parent = player
Players.LocalPlayer = player
table.insert(mock.players, player)

local ROOT_R = { -1, 0, 0, 0, 0, 1, 0, 1, 0 }
local RIGHT_R = { 0, 0, 1, 0, 1, 0, -1, 0, 0 }
local LEFT_R = { 0, 0, -1, 0, 1, 0, 1, 0, 0 }
local function cfr(x, y, z, r)
	return CFrame.new(x, y, z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
end
local function makeR6(name, position)
	local model = mock.newInstance("Model", name)
	local base = CFrame.new(position.X, position.Y, position.Z)
	local function p(partName, size, offset)
		local part = mock.newPart(partName, size, base * CFrame.new(offset.X, offset.Y, offset.Z))
		part.Parent = model
		return part
	end
	local hrp = p("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.zero)
	local torso = p("Torso", Vector3.new(2, 2, 1), Vector3.zero)
	local head = p("Head", Vector3.new(2, 1, 1), Vector3.new(0, 1.5, 0))
	local ra = p("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0))
	local la = p("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0))
	local rl = p("Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0))
	local ll = p("Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0))
	local function motor(parent, mName, p0, p1, c0, c1)
		local m = mock.newInstance("Motor6D", mName)
		m.Part0, m.Part1, m.C0, m.C1, m.Transform = p0, p1, c0, c1, CFrame.identity
		m.Parent = parent
	end
	motor(hrp, "RootJoint", hrp, torso, cfr(0, 0, 0, ROOT_R), cfr(0, 0, 0, ROOT_R))
	motor(torso, "Neck", torso, head, cfr(0, 1, 0, ROOT_R), cfr(0, -0.5, 0, ROOT_R))
	motor(torso, "Right Shoulder", torso, ra, cfr(1, 0.5, 0, RIGHT_R), cfr(-0.5, 0.5, 0, RIGHT_R))
	motor(torso, "Left Shoulder", torso, la, cfr(-1, 0.5, 0, LEFT_R), cfr(0.5, 0.5, 0, LEFT_R))
	motor(torso, "Right Hip", torso, rl, cfr(1, -1, 0, RIGHT_R), cfr(0.5, 1, 0, RIGHT_R))
	motor(torso, "Left Hip", torso, ll, cfr(-1, -1, 0, LEFT_R), cfr(-0.5, 1, 0, LEFT_R))
	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = 16
	humanoid.JumpHeight = 7.2
	humanoid.MoveDirection = Vector3.zero
	humanoid.FloorMaterial = Enum.Material.Plastic
	humanoid.Parent = model
	model:SetAttribute("CombatState", "Idle")
	model:SetAttribute("Posture", 100)
	model:SetAttribute("MaxPosture", 100)
	model.Parent = workspace
	CollectionService:AddTag(model, "Combatant")
	return model
end

local me = makeR6("Tester", Vector3.new(0, 3, 0))
player.Character = me
local enemy = makeR6("Dummy", Vector3.new(0, 3, -5))
enemy:SetAttribute("AlwaysCombat", true)
enemy:SetAttribute("DisplayName", "Sparring Partner")

-- boot the client
local starterScripts = mock.newInstance("Folder", "StarterPlayerScripts")
local client = mock.newInstance("LocalScript", "CombatClient")
rawget(client, "__props").__path = "src/StarterPlayer/StarterPlayerScripts/CombatClient/init.client.luau"
client.Parent = starterScripts
for _, name in ipairs({ "CameraFX", "HUD", "MovementController", "CombatController", "FXHandler" }) do
	mock.module(client, name, "src/StarterPlayer/StarterPlayerScripts/CombatClient/" .. name .. ".luau")
end
local ok, err = pcall(mock.runScript, client)
check(ok, "client boots: " .. tostring(err))
mock.advance(0.5)

local Animator = require(combatFolder.ProceduralAnimator)
local myRig = Animator.Get(me)
check(myRig ~= nil, "local character has a rig")
check(Animator.Get(enemy) ~= nil, "enemy has a rig")
check(player.PlayerGui:FindFirstChild("CombatHUD") ~= nil, "HUD built")

local function press(action, state, keyCode)
	local a = mock.actions[action]
	assert(a, "action not bound: " .. action)
	a.fn(action, Enum.UserInputState[state or "Begin"], { KeyCode = keyCode or Enum.KeyCode.Unknown, UserInputType = Enum.UserInputType.Keyboard })
end
local function sent(kind)
	local n = 0
	for _, e in ipairs(mock.fxLog) do
		if e.kind == "client->server" and e.data[1] == kind then
			n += 1
		end
	end
	return n
end
local function serverFX(kind, data)
	fxRemote.OnClientEvent:Fire(kind, data)
end

-- every action is bound
for _, name in ipairs({ "CombatAttack", "CombatBlock", "CombatHeavy", "CombatDodge", "CombatSlide", "CombatSprint", "CombatHelp" }) do
	check(mock.actions[name] ~= nil, name .. " bound")
end

-- M1 prediction
press("CombatAttack", "Begin")
press("CombatAttack", "End")
check(sent("M1") == 1, "M1 sent to the server")
check(myRig:IsPlaying("Jab"), "jab plays immediately (prediction)")
serverFX("Attack", { Model = me, Kind = "M1", Index = 1, Anim = "Jab", Seq = 1 })
mock.advance(0.12)
serverFX("Hit", {
	Attacker = me,
	Victim = enemy,
	Kind = "M1",
	Index = 1,
	Damage = 4,
	Position = Vector3.new(0, 3.7, -4),
	Direction = Vector3.new(0, 0, -1),
	Finisher = false,
	Knockback = Vector3.new(0, 0, -9),
	KnockTime = 0.12,
	Stun = 0.55,
})
check(Animator.Get(enemy):IsPlaying("HitA"), "enemy plays its hit reaction")
mock.advance(0.5)

-- a mismatched server index is corrected
press("CombatAttack", "Begin")
press("CombatAttack", "End")
serverFX("Attack", { Model = me, Kind = "M1", Index = 3, Anim = "Hook", Seq = 2 })
check(myRig:IsPlaying("Hook"), "client follows the server's combo index")
mock.advance(1)

-- reject rolls back
press("CombatHeavy")
check(sent("Heavy") == 1, "heavy sent")
serverFX("Reject", { Action = "Heavy", Seq = 3 })
mock.advance(0.3)

-- getting hit, blocked, parried, guard broken (as victim and attacker)
for _, kind in ipairs({ "Hit", "Blocked", "Parry", "GuardBreak" }) do
	serverFX(kind, {
		Attacker = enemy,
		Victim = me,
		Kind = "Heavy",
		Index = 1,
		Damage = 14,
		Position = Vector3.new(0, 3.7, -1),
		Direction = Vector3.new(0, 0, 1),
		Finisher = true,
		Knockback = Vector3.new(0, 20, 40),
		KnockTime = 0.2,
		Stun = 1,
		Posture = 0.5,
	})
	mock.advance(0.4)
	serverFX(kind, {
		Attacker = me,
		Victim = enemy,
		Kind = "M1",
		Index = 2,
		Damage = 4,
		Position = Vector3.new(0, 3.7, -4),
		Direction = Vector3.new(0, 0, -1),
		Finisher = false,
		Knockback = Vector3.new(0, 0, -9),
		KnockTime = 0.12,
		Stun = 0.55,
		Posture = 0.5,
	})
	mock.advance(0.4)
end

-- other fighters' events
serverFX("Attack", { Model = enemy, Kind = "Heavy", Index = 1, Anim = "Heavy" })
mock.advance(0.6)
serverFX("Cancel", { Model = enemy })
serverFX("BlockStart", { Model = enemy, Parry = true })
mock.advance(0.2)
serverFX("BlockEnd", { Model = enemy })
serverFX("Dodge", { Model = enemy, Dir = "Left" })
serverFX("Dodged", { Attacker = me, Victim = enemy, Position = Vector3.new(0, 3, -4) })
serverFX("Slide", { Model = enemy, Active = true })
mock.advance(0.5)
serverFX("Slide", { Model = enemy, Active = false })
mock.advance(1.5)

-- block / parry input
press("CombatBlock", "Begin")
check(sent("BlockStart") == 1, "block sent")
mock.advance(0.3)
press("CombatBlock", "End")
check(sent("BlockEnd") == 1, "block release sent")

-- dodge
mock.advance(2)
me.Humanoid.MoveDirection = Vector3.new(1, 0, 0)
press("CombatDodge")
check(sent("Dodge") == 1, "dodge sent")
mock.advance(0.5)

-- sprint + slide
mock.advance(1)
me.Humanoid.MoveDirection = Vector3.new(0, 0, -1)
press("CombatSprint", "Begin", Config.Keybinds.SprintHold)
mock.advance(1)
check(me.Humanoid.WalkSpeed > Config.Movement.WalkSpeed + 5, "sprinting raises WalkSpeed: " .. me.Humanoid.WalkSpeed)
me.HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, 0, -26)
press("CombatSlide")
check(sent("Slide") == 1, "slide started")
check(me.HumanoidRootPart:FindFirstChild("Mover_Slide") ~= nil, "slide velocity applied")
mock.advance(2)
check(me.HumanoidRootPart:FindFirstChild("Mover_Slide") == nil, "slide ends on its own")
press("CombatSprint", "End", Config.Keybinds.SprintHold)
press("CombatHelp")
mock.advance(1)

for _, w in ipairs(mock.warnings) do
	print("  WARNING: " .. w)
end
check(#mock.warnings == 0, "no warnings or handler errors")

print(("\n%d passed, %d failed"):format(passes, failures))
if failures > 0 then
	error("client smoke test failed", 0)
end
