--!nocheck
-- Headless tests for the combat system. Run from the Place1 folder:
--   luaurun tests/run.luau
-- (luaurun = a plain Luau VM with loadfile; see tests/README.md)

local mockFn = assert(loadfile("tests/mock.luau"))
local mock = mockFn()

local failures, passes = 0, 0
local function check(cond, msg)
	if cond then
		passes += 1
	else
		failures += 1
		print("  FAIL: " .. msg)
	end
end
local function section(name)
	print("== " .. name)
end
local function finite(n)
	return n == n and n ~= math.huge and n ~= -math.huge
end

----------------------------------------------------------------------------------------------
-- Build the DataModel the scripts expect

local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local combatFolder = mock.newInstance("Folder", "Combat")
combatFolder.Parent = RS
for _, name in ipairs({ "Config", "Util", "AnimationData", "ProceduralAnimator", "VFX", "SFX", "SoundIds" }) do
	mock.module(combatFolder, name, "src/ReplicatedStorage/Combat/" .. name .. ".luau")
end
local remotes = mock.newInstance("Folder", "Remotes")
remotes.Parent = combatFolder
mock.newInstance("RemoteEvent", "Action").Parent = remotes
mock.newInstance("RemoteEvent", "FX").Parent = remotes

local serverScript = mock.newInstance("Script", "CombatServer")
serverScript.Parent = SSS
for _, name in ipairs({ "CombatService", "DummyAI", "CharacterSetup" }) do
	mock.module(serverScript, name, "src/ServerScriptService/CombatServer/" .. name .. ".luau")
end

local Config = require(combatFolder.Config)

----------------------------------------------------------------------------------------------
-- Compile every source file

section("compile")
local files = {
	"src/ReplicatedStorage/Combat/Config.luau",
	"src/ReplicatedStorage/Combat/Util.luau",
	"src/ReplicatedStorage/Combat/AnimationData.luau",
	"src/ReplicatedStorage/Combat/ProceduralAnimator.luau",
	"src/ReplicatedStorage/Combat/VFX.luau",
	"src/ReplicatedStorage/Combat/SFX.luau",
	"src/ReplicatedStorage/Combat/SoundIds.luau",
	"src/ServerScriptService/CombatServer/init.server.luau",
	"src/ServerScriptService/CombatServer/CombatService.luau",
	"src/ServerScriptService/CombatServer/DummyAI.luau",
	"src/ServerScriptService/CombatServer/CharacterSetup.luau",
	"src/StarterPlayer/StarterPlayerScripts/CombatClient/init.client.luau",
	"src/StarterPlayer/StarterPlayerScripts/CombatClient/CameraFX.luau",
	"src/StarterPlayer/StarterPlayerScripts/CombatClient/CombatController.luau",
	"src/StarterPlayer/StarterPlayerScripts/CombatClient/FXHandler.luau",
	"src/StarterPlayer/StarterPlayerScripts/CombatClient/HUD.luau",
	"src/StarterPlayer/StarterPlayerScripts/CombatClient/MovementController.luau",
	"src/StarterPlayer/StarterCharacterScripts/Animate.client.luau",
}
for _, f in ipairs(files) do
	local fn, err = loadfile(f)
	check(fn ~= nil, "compile " .. f .. ": " .. tostring(err))
end

----------------------------------------------------------------------------------------------
-- R6 rig factory

local ROOT_R = { -1, 0, 0, 0, 0, 1, 0, 1, 0 }
local RIGHT_R = { 0, 0, 1, 0, 1, 0, -1, 0, 0 }
local LEFT_R = { 0, 0, -1, 0, 1, 0, 1, 0, 0 }
local function cfr(x, y, z, r)
	return CFrame.new(x, y, z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
end

local function makeR6(name, position, yawDeg)
	local model = mock.newInstance("Model", name)
	local base = CFrame.new(position.X, position.Y, position.Z) * CFrame.fromEulerAnglesYXZ(0, math.rad(yawDeg or 0), 0)
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
	humanoid.FloorMaterial = Enum.Material.Plastic
	humanoid.Parent = model
	model.Parent = workspace
	return model
end

----------------------------------------------------------------------------------------------
-- Animator

section("animator: clips")
mock.isClient = true
local Players = game:GetService("Players")
local localPlayer = mock.newInstance("Player", "Tester")
Players.LocalPlayer = localPlayer

local Animator = require(combatFolder.ProceduralAnimator)
local clipCount = 0
for name, clip in pairs(Animator.Clips) do
	clipCount += 1
	check(clip.Keys[#clip.Keys].t == clip.Length, name .. ": last keyframe == Length")
	for _, m in ipairs(clip.Markers) do
		check(m.t >= 0 and m.t <= clip.Length, name .. ": marker inside clip")
	end
end
check(clipCount >= 24, "expected the full clip set, got " .. clipCount)

-- hit timing lines up with the server windups
local impact = {}
for name, clip in pairs(Animator.Clips) do
	for _, m in ipairs(clip.Markers) do
		if m.name == "Impact" then
			impact[name] = m.t
		end
	end
end
for i, hit in ipairs(Config.M1.Hits) do
	check(impact[hit.Anim] ~= nil and math.abs(impact[hit.Anim] - hit.Windup) < 1e-6, ("M1 %d (%s) impact marker %s == windup %s"):format(i, hit.Anim, tostring(impact[hit.Anim]), hit.Windup))
end
check(math.abs((impact.Heavy or -1) - Config.Heavy.Windup) < 1e-6, "Heavy impact marker == windup")

section("animator: playback")
local dummy = makeR6("AnimDummy", Vector3.new(0, 3, 0), 0)
dummy:SetAttribute("AlwaysCombat", true)
local rig = Animator.Get(dummy)
check(rig ~= nil, "rig created for an R6 model")
local markers = {}
Animator.OnMarker(function(_, track, marker)
	table.insert(markers, track.Name .. ":" .. marker.name)
end)

local function stepRig(seconds)
	local frames = math.floor(seconds * 60)
	for _ = 1, frames do
		mock.advance(1 / 60)
		rig:Step(1 / 60, os.clock())
	end
end

local function transformsFinite()
	for _, motor in ipairs(rig.Motors) do
		local comps = { motor.Transform:GetComponents() }
		for _, c in ipairs(comps) do
			if not finite(c) then
				return false
			end
		end
	end
	return true
end

for name in pairs(Animator.Clips) do
	rig:Play(name)
	stepRig(0.1)
	check(transformsFinite(), name .. ": transforms finite")
end
stepRig(2.5)
local remaining = {}
for _, track in ipairs(rig.Tracks) do
	if not track.Looped then
		table.insert(remaining, track.Name)
	end
end
check(#remaining == 0, "one-shot clips clean themselves up (left: " .. table.concat(remaining, ",") .. ")")
rig:StopAll(0.05, 0)
stepRig(0.3)
check(#rig.Tracks == 0, "StopAll clears looped clips")

table.clear(markers)
rig:Play("Jab")
stepRig(0.5)
check(table.concat(markers, ",") == "Jab:Swing,Jab:Impact,Jab:SwingEnd", "Jab markers in order: " .. table.concat(markers, ","))

table.clear(markers)
rig:Play("Heavy")
stepRig(0.2)
rig:Freeze(0.5)
stepRig(0.45)
local frozenNames = table.concat(markers, ",")
check(frozenNames == "Heavy:Charge", "hitstop freezes clip time (markers so far: " .. frozenNames .. ")")
stepRig(1.2)
check(table.concat(markers, ",") == "Heavy:Charge,Heavy:Swing,Heavy:Impact,Heavy:SwingEnd", "Heavy markers after unfreeze")

section("animator: locomotion")
local steps = 0
Animator.OnStep(function()
	steps += 1
end)
local root = dummy.HumanoidRootPart
root.AssemblyLinearVelocity = Vector3.new(0, 0, -16)
stepRig(1)
check(rig.Phase > 0, "walk phase advances")
check(steps >= 4 and steps <= 8, "footsteps while walking at 16 studs/s for 1s: " .. steps)
check(transformsFinite(), "walking transforms finite")
root.AssemblyLinearVelocity = Vector3.new(0, 0, -26)
steps = 0
stepRig(1)
check(rig.RunBlend > 0.8, "run blend at sprint speed: " .. rig.RunBlend)
root.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
stepRig(0.6)
check(rig.LegYaw < -40, "strafing right turns the legs toward travel: " .. rig.LegYaw)
root.AssemblyLinearVelocity = Vector3.new(0, 0, 14)
local before = rig.Phase
stepRig(0.1)
check(rig.Backwards > 0.5, "backpedalling detected")
root.AssemblyLinearVelocity = Vector3.zero
stepRig(0.5)

section("animator: foot planting")
rig:Play("Slide", { FadeIn = 0 })
stepRig(0.6)
local lowest = rig:_lowestFootY(rig.Pose)
check(lowest >= rig.RestFootY - 0.2, ("slide keeps feet above the floor (lowest %.2f, rest %.2f)"):format(lowest, rig.RestFootY))
rig:Stop("Slide", 0)
rig:Play("Land", { FadeIn = 0 })
stepRig(0.08)
lowest = rig:_lowestFootY(rig.Pose)
check(lowest >= rig.RestFootY - 0.25, ("landing dip keeps feet above the floor (lowest %.2f)"):format(lowest))

-- Python previewer and Luau animator agree on the rig math (Guard pose)
section("animator: matches previewer FK")
rig:StopAll(0, 0)
local guard = Animator.Clips.CombatIdle.Keys[1].pose
for i = 1, #guard do
	rig.Pose[i] = guard[i]
end
local motors = rig.Motors
local torsoCF = motors[1].C0 * (rig.RotInv[1] * CFrame.new(guard[4], guard[5], guard[6]) * CFrame.fromEulerAnglesYXZ(math.rad(guard[1]), math.rad(guard[2]), math.rad(guard[3])) * rig.Rot[1]) * motors[1].C1:Inverse()
local o = 2 * 6
local rArmT = rig.RotInv[3] * CFrame.new(guard[o + 4], guard[o + 5], guard[o + 6]) * CFrame.fromEulerAnglesYXZ(math.rad(guard[o + 1]), math.rad(guard[o + 2]), math.rad(guard[o + 3])) * rig.Rot[3]
local rArm = torsoCF * motors[3].C0 * rArmT * motors[3].C1:Inverse()
local fist = rArm * Vector3.new(0, -0.9, 0)
print(("  GUARD_RIGHT_FIST %.4f %.4f %.4f"):format(fist.X, fist.Y, fist.Z))

----------------------------------------------------------------------------------------------
-- Server combat

section("server: setup")
mock.isClient = false
Players.LocalPlayer = nil
local CombatService = require(serverScript.CombatService)
CombatService.Start()

local arenaX = 0
local function fresh(nameA, nameB, distance)
	arenaX += 200 -- every pair fights far away from the previous ones
	local a = makeR6(nameA, Vector3.new(arenaX, 3, 0), 0) -- faces -Z
	local b = makeR6(nameB, Vector3.new(arenaX, 3, -(distance or 4)), 180) -- faces +Z, toward A
	local fa = CombatService.Register(a, {})
	local fb = CombatService.Register(b, {})
	return fa, fb
end

local function clearFX()
	table.clear(mock.fxLog)
end
local function events(kind)
	local out = {}
	for _, e in ipairs(mock.fxLog) do
		if e.kind == kind then
			table.insert(out, e)
		end
	end
	return out
end

section("server: M1 combo")
local A, B = fresh("A1", "B1")
clearFX()
CombatService.TryM1(A, 1)
check(#events("Attack") == 1 and events("Attack")[1].data.Index == 1, "first M1 is hit 1")
mock.advance(Config.M1.Hits[1].Windup + 0.01)
check(#events("Hit") == 1, "hit 1 lands after its windup")
check(B.Humanoid.Health == 100 - Config.M1.Hits[1].Damage, "hit 1 damage applied: " .. B.Humanoid.Health)
check(B.Model:GetAttribute("CombatState") == "Stunned" or os.clock() < B.StunUntil, "victim stunned")
-- chain the rest with presses just before each punch ends (exercise the server queue)
for i = 2, 4 do
	mock.advance(A.ActionEnd - os.clock() - 0.1)
	CombatService.TryM1(A, i)
	mock.advance(0.1 + Config.M1.Hits[i].Windup + 0.01)
end
local hits = events("Hit")
check(#hits == 4, "4-hit chain lands 4 hits, got " .. #hits)
check(hits[4] and hits[4].data.Finisher == true, "4th hit is the finisher")
check(hits[4] and hits[4].data.Knockback.Magnitude > 30, "finisher knocks back")
local expected = 100
for i = 1, 4 do
	expected -= Config.M1.Hits[i].Damage
end
check(math.abs(B.Humanoid.Health - expected) < 1e-6, "chain damage total " .. B.Humanoid.Health .. " == " .. expected)
CombatService.TryM1(A, 5)
check(#events("Attack") == 4, "can't start a 5th punch during the end-of-combo cooldown")
mock.advance(3)

section("server: block")
A, B = fresh("A2", "B2")
clearFX()
CombatService.TryBlockStart(B)
mock.advance(Config.Parry.Window + 0.2) -- well past the parry window
CombatService.TryM1(A, 1)
mock.advance(0.2)
check(#events("Blocked") == 1, "late block = plain block")
check(B.Humanoid.Health == 100, "blocked hit does no damage")
check(math.abs(B.Posture - (Config.Block.MaxPosture - Config.M1.Hits[1].PostureDamage)) < 1e-6, "blocked hit drains posture")
mock.advance(2)

section("server: parry")
A, B = fresh("A3", "B3")
clearFX()
CombatService.TryM1(A, 1)
mock.advance(0.02)
CombatService.TryBlockStart(B) -- hit lands ~0.09s later: inside the window
mock.advance(0.2)
local parries = events("Parry")
check(#parries == 1, "block pressed just before the hit = parry")
check(#events("Hit") == 0, "parried hit does no damage")
check(A.StunKind == "Parried" and os.clock() < A.StunUntil, "attacker is stunned after being parried")
CombatService.TryM1(A, 2)
check(#events("Attack") == 1, "parried attacker can't attack while stunned")
-- the parrier can punish right away
CombatService.TryBlockEnd(B)
CombatService.TryM1(B, 1)
mock.advance(0.2)
check(#events("Hit") == 1 and events("Hit")[1].data.Attacker == B.Model, "parrier punishes the stunned attacker")
mock.advance(3)

section("server: parry anti-mash")
A, B = fresh("A4", "B4")
clearFX()
CombatService.TryBlockStart(B)
mock.advance(0.3)
CombatService.TryBlockEnd(B)
mock.advance(0.1)
CombatService.TryM1(A, 1)
mock.advance(0.03)
CombatService.TryBlockStart(B) -- re-press within the parry cooldown
mock.advance(0.2)
check(#events("Parry") == 0 and #events("Blocked") == 1, "mashing block gives a plain block, not a parry")
mock.advance(3)

section("server: heavy guard break")
A, B = fresh("A5", "B5")
clearFX()
CombatService.TryBlockStart(B)
mock.advance(0.5)
CombatService.TryHeavy(A, 1)
mock.advance(Config.Heavy.Windup + 0.02)
check(#events("GuardBreak") == 1, "heavy into a held block = guard break")
check(B.StunKind == "GuardBroken", "guard broken victim is stunned")
check(not B.Blocking and not B.WantsBlock, "guard break drops the block until re-pressed")
mock.advance(Config.GuardBreak.Stun + 0.1)
check(B.Posture == Config.Block.MaxPosture * Config.GuardBreak.PostureAfter, "posture restored after guard break stun")
mock.advance(Config.Heavy.Cooldown)

section("server: heavy can be parried")
A, B = fresh("A6", "B6")
clearFX()
CombatService.TryHeavy(A, 1)
mock.advance(Config.Heavy.Windup - 0.1)
CombatService.TryBlockStart(B)
mock.advance(0.2)
check(#events("Parry") == 1, "well-timed block parries a heavy")
mock.advance(Config.Heavy.Cooldown)

section("server: posture break")
A, B = fresh("A7", "B7")
clearFX()
CombatService.TryBlockStart(B)
mock.advance(0.5)
local guardBroken = false
for _ = 1, 20 do
	CombatService.TryM1(A, nil)
	mock.advance(A.ActionEnd - os.clock() + 0.01)
	if #events("GuardBreak") > 0 then
		guardBroken = true
		break
	end
	if os.clock() < A.ComboCooldownUntil then
		mock.advance(A.ComboCooldownUntil - os.clock() + 0.01)
	end
end
check(guardBroken, "enough blocked punches break the guard")
mock.advance(3)

section("server: dodge i-frames")
A, B = fresh("A8", "B8")
clearFX()
CombatService.TryM1(A, 1)
mock.advance(0.03)
CombatService.TryDodge(B, "Back", 1)
check(#events("Dodge") == 1, "dodge accepted")
mock.advance(0.2)
check(#events("Dodged") == 1 and #events("Hit") == 0, "hit during i-frames is dodged")
CombatService.TryDodge(B, "Back", 2)
check(#events("Dodge") == 1, "dodge cooldown enforced")
CombatService.TryDodge(B, "Sideways", 3)
mock.advance(3)

section("server: facing")
arenaX += 200
local a9 = makeR6("A9", Vector3.new(arenaX, 3, 0), 0)
local b9 = makeR6("B9", Vector3.new(arenaX, 3, -4), 0) -- faces away from A
A, B = CombatService.Register(a9, {}), CombatService.Register(b9, {})
clearFX()
CombatService.TryBlockStart(B)
mock.advance(0.5)
CombatService.TryM1(A, 1)
mock.advance(0.2)
check(#events("Hit") == 1, "blocking doesn't protect your back")
mock.advance(3)

section("server: out of range")
A, B = fresh("A10", "B10", 14)
clearFX()
CombatService.TryM1(A, 1)
mock.advance(0.3)
check(#events("Hit") == 0, "no hit beyond hitbox range")

section("server: slide + reject")
A, B = fresh("A11", "B11")
local player = mock.newInstance("Player", "P")
A.Player = player
clearFX()
CombatService.TrySlide(A, true)
check(#events("Slide") == 1 and A.Sliding, "slide accepted")
CombatService.TryM1(A, 7)
check(not A.Sliding, "attacking ends the slide")
mock.advance(Config.M1.Hits[1].Duration + 0.05)
B.StunUntil = os.clock() + 1
B.Player = player
CombatService.TryM1(B, 9)
local rejects = events("Reject")
check(#rejects == 1 and rejects[1].data.Seq == 9, "stunned player's request is rejected with its seq")

----------------------------------------------------------------------------------------------

print(("\n%d passed, %d failed"):format(passes, failures))
if failures > 0 then
	error("tests failed", 0)
end
