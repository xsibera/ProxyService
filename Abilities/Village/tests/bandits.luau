--!nocheck
-- The village's bandits (BanditBrains) fighting with the real M1 string (MeleeServer) and stun
-- system (Combat): they idle at camp, run you down, throw strings that keep you stunned, can be
-- parried, sometimes guard against your hits, give up past their leash, heal at home and stand back
-- up after being knocked out. Run from this folder:  cd Abilities/Village && luaurun tests/bandits.luau

local H = assert(loadfile("tests/harness.luau"))()
H.withCombatAndLoadout()
H.withMelee()
local mock, check = H.mock, H.check
local Combat = require(H.CombatModule)
local MeleeConfig = require(H.MeleeConfig)
math.randomseed(1)

local camp = mock.newInstance("Model", "Bandits")
camp.Parent = workspace
local bModel, bParts, bHum = H.character("Bandit", 0, -200, 0)
bModel.Parent = camp
bHum.Health, bHum.MaxHealth, bHum.WalkSpeed = 140, 140, 14
local home = bParts.HumanoidRootPart.Position

local pModel, pParts, pHum = H.character("P", 0, 0, 180) -- far away: in the village
local p = H.player("P", pModel)
pHum.Health, pHum.MaxHealth = 100, 100

local brains = mock.newInstance("Script", "BanditBrains")
rawget(brains, "__props").__path = "src/BanditBrains.server.luau"
brains.Parent = camp
mock.runScript(brains)
mock.advance(0.2)

local pRoot = pParts.HumanoidRootPart
local function bRoot()
	local bandit = camp:FindFirstChild("Bandit")
	return bandit and bandit:FindFirstChild("HumanoidRootPart")
end
local function swings()
	return H.sent("M1", "server", H.meleeRemote)
end

print("== At camp")
mock.advance(6)
check(#swings() == 0, "nobody near: no fighting")
check((bRoot().Position - home).Magnitude < 7, "it stays round the camp")

print("== Coming for you")
local dealt = {} -- what each of the bandit's hits on you did
local dealing = Combat.Resolved.Event:Connect(function(attacker, victim, outcome, hit)
	if attacker == bModel and victim == pModel and outcome == "Hit" then
		table.insert(dealt, hit.Damage)
	end
end)
pModel:PivotTo(CFrame.new(0, 3, -170)) -- 30 studs off, inside AGGRO
local start = (bRoot().Position - pRoot.Position).Magnitude
mock.advance(1)
local closer = (bRoot().Position - pRoot.Position).Magnitude
check(closer < start - 8, "it runs at you (" .. math.floor(start) .. " -> " .. math.floor(closer) .. " studs)")
mock.advance(2)
check((bRoot().Position - pRoot.Position).Magnitude < 5, "and gets to you")
check(#swings() >= 1 and swings()[1].args[2] == bModel, "and swings (through the M1 string, as itself)")

print("== A string keeps you stunned")
local landed = 0
local free = 0
for _ = 1, 240 do
	mock.advance(1 / 60)
	if #swings() >= 2 and #swings() < 5 then
		if not Combat.isStunned(pModel) then
			free += 1
		end
	end
	if #swings() >= 5 then
		break
	end
end
mock.advance(1)
for _, entry in ipairs(H.sent("Hit", "server", H.meleeRemote)) do
	if entry.args[3] == pModel then
		landed += 1
	end
end
check(#swings() >= 5, "it throws the whole string (" .. #swings() .. ")")
check(landed >= 5, "every hit lands on you (" .. landed .. ")")
check(free == 0, "you're stunned all the way through (" .. free .. " frames free)")
dealing:Disconnect()
local share = #dealt >= 5
for i, hit in ipairs(MeleeConfig.Hits) do
	share = share and math.abs((dealt[i] or 0) - hit.Damage * MeleeConfig.NpcDamage) < 1e-6
end
check(share, "each hit for the NPC share of a player's damage")

print("== Parry it")
pHum.Health = 100
pModel:SetAttribute("StunnedUntil", nil) -- (out of the last string's stun)
pModel:PivotTo(CFrame.lookAt(pRoot.Position, bRoot().Position))
Combat.setBlocking(pModel, true)
local parried = false
local resolved = Combat.Resolved.Event:Connect(function(attacker, victim, outcome)
	if attacker == bModel and outcome == "Parried" then
		parried = true
	end
end)
local announcedAt = nil
local watch = Combat.Announced.Event:Connect(function(attacker, hitAt)
	if attacker == bModel and not announcedAt then
		announcedAt = hitAt
		task.delay(hitAt - Combat.now() - 0.1, function()
			Combat.openParry(pModel) -- F, just before it lands
		end)
	end
end)
mock.advance(3)
watch:Disconnect()
resolved:Disconnect()
check(parried, "a timed F parries the bandit's hit")
Combat.setBlocking(pModel, false)
mock.advance(1)

print("== It guards against you sometimes")
local guards = 0
for _ = 1, 40 do
	pHum.Health = 100 -- (it's hitting you meanwhile)
	mock.advance(0.6)
	bModel:SetAttribute("StunnedUntil", nil)
	bModel:SetAttribute("BusyUntil", nil)
	Combat.setBlocking(bModel, false)
	Combat.announce(pModel, Combat.now() + 0.35, "M1")
	mock.advance(0.3)
	if bModel:GetAttribute("Blocking") then
		guards += 1
	end
end
check(guards >= 4 and guards <= 25, "it guards some of your attacks, not all (" .. guards .. " of 40)")

print("== The leash")
pModel:PivotTo(CFrame.new(0, 3, -60)) -- 140 from camp: well past the leash
mock.advance(12)
check((bRoot().Position - home).Magnitude < 7, "it gives up and goes home")
bHum.Health = 60
mock.advance(6)
check(bHum.Health > 120, "and patches itself up there (" .. math.floor(bHum.Health) .. ")")

print("== Knocked out")
bHum.Health = 0
mock.advance(1)
check(camp:FindFirstChild("Bandit") == bModel, "down for now")
mock.advance(10)
local fresh = camp:FindFirstChild("Bandit")
check(fresh and fresh ~= bModel and fresh.Humanoid.Health == 140, "a fresh bandit stands up at the camp")
pHum.Health = 100
pModel:SetAttribute("StunnedUntil", nil)
pModel:PivotTo(CFrame.new(0, 3, -175))
local swung = #swings()
mock.advance(4)
check(#swings() > swung, "and fights like the first")
_ = p

H.finish("Bandits")
