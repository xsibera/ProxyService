--!nocheck
-- Headless test of JajankenServer against Place1's mock engine: charging, tapping, holding, the
-- auto-cast at full charge, cooldowns, every mode's hits / damage / knockback, the Paper ball's
-- flight, aim and blast, cancelling, bad input and teams. Run from this folder:
--   cd Abilities/Jajanken && luaurun tests/server.luau

local H = assert(loadfile("tests/harness.luau"))()
local mock, check, near = H.mock, H.check, H.near
local Config = require(H.Config)

local SSS = game:GetService("ServerScriptService")
local serverScript = mock.newInstance("Script", "JajankenServer")
rawget(serverScript, "__props").__path = "src/JajankenServer.server.luau"
serverScript.Parent = SSS
mock.runScript(serverScript)
mock.advance(0)

local remote = H.remote
local function send(player, ...)
	remote.OnServerEvent:Fire(player, ...)
end

-- Gon at the origin facing -Z; targets in front
local gonModel, gonParts, gonHumanoid = H.character("Gon", 0, 0, 0)
local gon = H.player("Gon", gonModel)
local hits = {}
serverScript:WaitForChild("OnHit").Event:Connect(function(attacker, victim, mode, damage, charge)
	table.insert(hits, { attacker = attacker, victim = victim, mode = mode, damage = damage, charge = charge })
end)

local function dummy(name, x, z)
	local model, parts, humanoid = H.character(name, x, z, 180)
	return model, humanoid, parts
end

local function reset()
	table.clear(H.remoteLog)
	table.clear(hits)
end

local function pushOn(parts)
	for _, d in ipairs(parts.HumanoidRootPart:GetDescendants()) do
		if d.ClassName == "LinearVelocity" then
			return d.VectorVelocity
		end
	end
	return nil
end

print("== Tap Rock")
local front, frontHum, frontParts = dummy("Front", 0, -3.5)
reset()
send(gon, "Charge", "Rock")
check(#H.sent("Charge") == 1, "charge broadcast")
check(gonHumanoid.WalkSpeed == Config.ChargeWalkSpeed, "slowed while charging")
send(gon, "Release")
local cast = H.sent("Cast")[1]
check(cast ~= nil and cast.args[3] == "Rock" and near(cast.args[4], 0, 1e-3), "tapped: cast with no charge")
check(cast and near(cast.args[5] - mock.now(), Config.Rock.HitDelay, 1e-3), "hitAt = now + HitDelay")
check(frontHum.Health == 200, "no damage before the hit lands")
mock.advance(Config.Rock.HitDelay + 0.02)
check(
	near(200 - frontHum.Health, Config.Rock.Damage[1], 0.01),
	"tap does the minimum damage (" .. 200 - frontHum.Health .. ")"
)
check(#hits == 1 and hits[1].attacker == gon and hits[1].victim == front and hits[1].mode == "Rock", "OnHit fired")
check(#H.sent("Hit") == 1, "hit broadcast")
local push = pushOn(frontParts)
check(push ~= nil and push.Z < -30 and push.Y > 0, "knocked back away from Gon (and up)")
mock.advance(1)
check(gonHumanoid.WalkSpeed == 16, "walk speed restored after the recovery")

print("== Cooldowns")
reset()
send(gon, "Charge", "Rock")
local denied = H.sent("Denied")[1]
check(denied ~= nil and denied.to == gon and denied.args[2] == "Rock", "Rock again: denied to the caster only")
check(denied and denied.args[3] > 2 and denied.args[3] <= Config.Cooldown.Rock, "denied with the time left")
check(#H.sent("Charge") == 0, "no charge started")
send(gon, "Charge", "Scissors")
check(#H.sent("Charge") == 1, "another mode is free after the shared cooldown")
send(gon, "Cancel")
check(#H.sent("Stop") == 1, "cancel stops the charge")
mock.advance(Config.Cooldown.Rock)

print("== Held Rock (1.5s)")
frontHum.Health = 200
reset()
send(gon, "Charge", "Rock")
mock.advance(1.5)
send(gon, "Release")
mock.advance(Config.Rock.HitDelay + 0.02)
local expect = Config.Rock.Damage[1] + (Config.Rock.Damage[2] - Config.Rock.Damage[1]) * 0.5
check(
	near(200 - frontHum.Health, expect, 0.6),
	("half charge: %.1f damage (expected %.1f)"):format(200 - frontHum.Health, expect)
)
check(hits[1] and near(hits[1].charge, 0.5, 0.02), "charge reported 0.5")
mock.advance(Config.Cooldown.Rock)

print("== Full charge casts by itself")
frontHum.Health = 200
reset()
send(gon, "Charge", "Rock")
mock.advance(Config.MaxCharge - 0.05)
check(#H.sent("Cast") == 0, "still charging just before MaxCharge")
mock.advance(0.1)
local auto = H.sent("Cast")[1]
check(auto ~= nil and near(auto.args[4], 1, 1e-6), "cast at MaxCharge with full charge")
send(gon, "Release")
check(#H.sent("Cast") == 1, "the late release is ignored")
mock.advance(Config.Rock.HitDelay + 0.02)
check(near(200 - frontHum.Health, Config.Rock.Damage[2], 0.01), "full charge does the maximum damage")
mock.advance(Config.Cooldown.Rock)
front:Destroy()

print("== Scissors: wide")
local left, leftHum = dummy("Left", -5, -4)
local right, rightHum = dummy("Right", 5, -4)
reset()
send(gon, "Charge", "Scissors")
send(gon, "Release")
mock.advance(Config.Scissors.HitDelay + 0.02)
check(leftHum.Health < 200 and rightHum.Health < 200, "the sweep hits both sides")
check(near(200 - leftHum.Health, Config.Scissors.Damage[1], 0.01), "tapped scissors damage")
mock.advance(Config.Cooldown.Scissors + 0.1)

print("== Rock: narrow")
leftHum.Health, rightHum.Health = 200, 200
reset()
send(gon, "Charge", "Rock")
send(gon, "Release")
mock.advance(Config.Rock.HitDelay + 0.02)
check(leftHum.Health == 200 and rightHum.Health == 200, "the punch doesn't reach 5 studs to the side")
mock.advance(Config.Cooldown.Rock)
left:Destroy()
right:Destroy()

print("== Paper: thrown")
local far, farHum = dummy("Far", 0, -40)
reset()
send(gon, "Charge", "Paper")
mock.advance(1.5)
send(gon, "Release", Vector3.new(0, 0, -1))
mock.advance(Config.Paper.HitDelay + 0.02)
local launch = H.sent("Launch")[1]
check(launch ~= nil, "ball launched")
local id, from, direction, speed, range = launch.args[3], launch.args[4], launch.args[5], launch.args[6], launch.args[7]
check(from and from.Z < -2 and near(direction.Z, -1, 1e-6), "from the palm, straight ahead")
check(near(speed, Config.scaled(Config.Paper.Speed, 0.5), 0.5), "speed scales with charge")
check(farHum.Health == 200, "not there yet")
mock.advance(40 / speed + 0.1)
local boom = H.sent("Explode")[1]
check(boom ~= nil and boom.args[3] == id, "it bursts on the dummy")
check(boom and math.abs(boom.args[4].Z - -40) < 3, "at the dummy (z " .. (boom and boom.args[4].Z or 0) .. ")")
check(farHum.Health < 200 and #hits == 1 and hits[1].mode == "Paper", "the dummy takes the blast")
mock.advance(Config.Cooldown.Paper)

print("== Paper: aim")
reset()
send(gon, "Charge", "Paper")
send(gon, "Release", Vector3.new(1, 0, -1).Unit)
mock.advance(Config.Paper.HitDelay + 0.02)
local aimed = H.sent("Launch")[1].args[5]
check(near(aimed.X, math.sqrt(0.5), 1e-3), "thrown where the camera aims (45 deg right)")
mock.advance(Config.Cooldown.Paper + 2)
reset()
send(gon, "Charge", "Paper")
send(gon, "Release", Vector3.new(0, 0, 1))
mock.advance(Config.Paper.HitDelay + 0.02)
check(near(H.sent("Launch")[1].args[5].Z, -1, 1e-6), "aim behind: thrown straight ahead instead")
mock.advance(Config.Cooldown.Paper + 2)
reset()
send(gon, "Charge", "Paper")
send(gon, "Release", Vector3.new(0 / 0, 0, 0))
mock.advance(Config.Paper.HitDelay + 0.02)
check(near(H.sent("Launch")[1].args[5].Z, -1, 1e-6), "NaN aim: straight ahead")
mock.advance(Config.Cooldown.Paper + 2)
far:Destroy()

print("== Paper: a wall in the way")
local wall = mock.newPart("Wall", Vector3.new(10, 10, 2), CFrame.new(0, 5, -20))
wall.Parent = workspace
local hidden, hiddenHum = dummy("Behind", 0, -40)
reset()
send(gon, "Charge", "Paper")
send(gon, "Release")
mock.advance(Config.Paper.HitDelay + 1)
local wallBoom = H.sent("Explode")[1]
check(wallBoom and math.abs(wallBoom.args[4].Z - -19) < 2, "bursts on the wall")
check(hiddenHum.Health == 200, "the dummy behind it is safe")
wall:Destroy()
hidden:Destroy()
mock.advance(Config.Cooldown.Paper)

print("== Range")
reset()
send(gon, "Charge", "Paper")
send(gon, "Release")
mock.advance(Config.Paper.HitDelay + Config.Paper.Range[1] / Config.Paper.Speed[1] + 0.1)
local fizzle = H.sent("Explode")[1]
check(
	fizzle and near((fizzle.args[4] - H.sent("Launch")[1].args[4]).Magnitude, Config.Paper.Range[1], 0.05),
	"bursts at its range"
)
mock.advance(Config.Cooldown.Paper)

print("== Dying while charging")
reset()
send(gon, "Charge", "Rock")
gonHumanoid.Health = 0
check(#H.sent("Stop") == 1, "death stops the charge")
mock.advance(Config.MaxCharge + 0.5)
check(#H.sent("Cast") == 0, "and it never casts")
gonHumanoid.Health = 200
rawget(gonHumanoid, "__props").__dead = nil

print("== Bad input")
reset()
send(gon, "Charge", "Lizard")
send(gon, "Charge", nil)
send(gon, "Release")
send(gon, "Nonsense", 1, 2, 3)
check(#H.remoteLog == 0, "ignored")
send(gon, "Charge", "Rock")
send(gon, "Charge", "Paper")
check(#H.sent("Charge") == 1, "a second charge while charging is ignored")
send(gon, "Cancel")
mock.advance(0.1)

print("== Teams")
local friendModel, friendParts, friendHum = H.character("Friend", 0, -3.5, 180)
local friend = H.player("Friend", friendModel)
local team = mock.newInstance("Team", "Hunters")
gon.Neutral, friend.Neutral = false, false
gon.Team, friend.Team = team, team
reset()
send(gon, "Charge", "Rock")
send(gon, "Release")
mock.advance(Config.Rock.HitDelay + 0.02)
check(friendHum.Health == 200, "a teammate isn't hit")
mock.advance(Config.Cooldown.Rock)
friend.Team = mock.newInstance("Team", "Phantom Troupe")
reset()
send(gon, "Charge", "Rock")
send(gon, "Release")
mock.advance(Config.Rock.HitDelay + 0.02)
check(friendHum.Health < 200, "another team's player is")
local _ = friendParts

print("== Leaving")
reset()
mock.advance(Config.Cooldown.Rock)
send(gon, "Charge", "Rock")
game:GetService("Players").PlayerRemoving:Fire(gon)
check(#H.sent("Stop") == 1, "leaving mid-charge stops it")

H.finish("Jajanken server test")
