--!nocheck
-- The village training yard's dummies (DummyBrains) with the parry system: the blocker keeps its
-- guard up and turns to face you, the parrier parries what's coming at it, the sparring dummy
-- throws telegraphed punches you can parry. Run from this folder:
--   cd Abilities/Village && luaurun tests/dummies.luau

local H = assert(loadfile("tests/harness.luau"))()
H.withCombatAndLoadout()
local mock, check = H.mock, H.check
local Combat = require(H.CombatModule)

local area = mock.newInstance("Model", "Test Dummies")
area.Parent = workspace
local function dummy(name, x, z, yaw)
	local model, parts, humanoid = H.character(name, x, z, yaw)
	model.Parent = area
	return model, parts, humanoid
end
local blockerModel, blockerParts = dummy("Blocking Dummy", -20, 0, 0)
local parrierModel = dummy("Parrying Dummy", 20, 0, 0)
local sparModel, _, sparHum = dummy("Sparring Dummy", 0, -40, 0)
local plain = dummy("Dummy", 0, 40, 0)

local pModel, pParts, pHum = H.character("P", -20, -10, 0) -- 10 in front of the blocker (it faces -Z)
local p = H.player("P", pModel)

local brains = mock.newInstance("Script", "DummyBrains")
rawget(brains, "__props").__path = "src/DummyBrains.server.luau"
brains.Parent = area
mock.runScript(brains)
mock.advance(0.2)

local function yawOf(parts)
	local look = parts.HumanoidRootPart.CFrame.LookVector
	return math.deg(math.atan2(-look.X, -look.Z))
end

print("== Blocking Dummy")
check(Combat.isBlocking(blockerModel), "guard up")
check(not Combat.isBlocking(plain), "plain dummies just stand there")
pModel:PivotTo(CFrame.new(-10, 3, 0)) -- to its right side
mock.advance(0.1)
local turned = math.abs(yawOf(blockerParts))
check(turned > 20 and turned < 60, "turns toward you, but not at once (" .. math.round(turned) .. " degrees)")
mock.advance(0.3)
check(math.abs(math.abs(yawOf(blockerParts)) - 90) < 2, "and gets there")
Combat.stun(blockerModel, 0.5, "GuardBreak")
check(not Combat.isBlocking(blockerModel), "a guard break drops it")
mock.advance(0.7)
check(Combat.isBlocking(blockerModel), "back up after the stun")

print("== Parrying Dummy")
pModel:PivotTo(CFrame.new(20, 3, -6)) -- in front of it, facing it
pParts.HumanoidRootPart.CFrame = CFrame.lookAt(Vector3.new(20, 3, -6), Vector3.new(20, 3, 0))
local hitAt = Combat.now() + 0.4
Combat.announce(pModel, hitAt, "LightningPalm")
mock.advance(0.2)
check(not Combat.isBlocking(parrierModel), "waits")
mock.advance(0.15)
check(
	Combat.isBlocking(parrierModel) and typeof(parrierModel:GetAttribute("ParryAt")) == "number",
	"presses F just before"
)
mock.advance(hitAt - Combat.now())
check(Combat.resolve(pModel, parrierModel, { Damage = 10 }) == "Parried", "parried")
mock.advance(0.5)
check(not Combat.isBlocking(parrierModel), "lets go after")
mock.advance(1)
Combat.announce(sparModel, Combat.now() + 0.3, "DummyPunch")
mock.advance(0.3)
check(not Combat.isBlocking(parrierModel), "ignores the other dummies' attacks")
pParts.HumanoidRootPart.CFrame = CFrame.lookAt(Vector3.new(20, 3, -6), Vector3.new(20, 3, -20))
Combat.announce(pModel, Combat.now() + 0.3, "LightningPalm")
mock.advance(0.3)
check(not Combat.isBlocking(parrierModel), "ignores attacks aimed elsewhere")
Combat.announce(pModel, Combat.now() + 0.3, "Thunderbolt", Vector3.new(21, 0, 1))
mock.advance(0.25)
check(Combat.isBlocking(parrierModel), "reacts to one landing on it")
mock.advance(1)
local hole = Vector3.new(24, 4, 3) -- a warp hole behind it, to its right
Combat.announce(pModel, Combat.now() + 0.3, "WarpPunch", Vector3.new(20, 3, 0), hole)
mock.advance(0.25)
local parrierRoot = parrierModel:FindFirstChild("HumanoidRootPart")
local toHole = Vector3.new(hole.X - 20, 0, hole.Z).Unit
check(
	Combat.isBlocking(parrierModel) and parrierRoot.CFrame.LookVector:Dot(toHole) > 0.99,
	"a blow out of a warp hole: it turns to the hole, not to whoever threw it"
)
check(Combat.resolve(pModel, parrierModel, { Damage = 10, From = hole }) == "Parried", "and parries it")
mock.advance(1)

print("== Sparring Dummy")
pModel:PivotTo(CFrame.lookAt(Vector3.new(0, 3, -45), Vector3.new(0, 3, -40))) -- 5 in front of it, facing it
pHum.Health = 200
local before = pHum.Health
local telegraphed = false
for _ = 1, 40 do
	mock.advance(0.1)
	if sparModel:FindFirstChild("Telegraph") then
		telegraphed = true
		break
	end
end
check(telegraphed, "telegraphs a punch at someone close")
check(Combat.isBusy(sparModel), "busy while winding up")
mock.advance(0.7)
check(pHum.Health < before, "the punch lands")
check(Combat.isStunned(pModel), "and staggers")
check(sparModel:FindFirstChild("Telegraph") == nil, "telegraph gone")
mock.advance(1)
-- now parry it
telegraphed = false
for _ = 1, 40 do
	mock.advance(0.05)
	if sparModel:FindFirstChild("Telegraph") then
		telegraphed = true
		break
	end
end
local health = pHum.Health
Combat.setBlocking(pModel, true)
mock.advance(0.35)
Combat.openParry(pModel)
mock.advance(0.3)
check(telegraphed and pHum.Health == health, "parried: no damage")
check(sparModel:GetAttribute("StunKind") == "Parried" and Combat.isStunned(sparModel), "the dummy staggers")
Combat.setBlocking(pModel, false)
pModel:PivotTo(CFrame.new(0, 3, 0))
local hits = 0
local resolved = Combat.Resolved.Event:Connect(function(attacker)
	if attacker == sparModel then
		hits += 1
	end
end)
mock.advance(5)
check(hits == 0, "nobody close: it waits")
resolved:Disconnect()
_ = sparHum

print("== Respawned dummies think too")
local fresh = H.character("Blocking Dummy", -20, 20, 0)
fresh.Parent = area
area.ChildAdded:Fire(fresh)
mock.advance(0.2)
check(Combat.isBlocking(fresh), "a new Blocking Dummy blocks")
_ = p

H.finish("Training dummies")
