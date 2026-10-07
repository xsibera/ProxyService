--!nocheck
-- KilluaClient in a place without Loadout or Combat: its own keys (Config.Keys, with gamepad and
-- touch) and its own little cooldown bar. With Killua.LightningBeams mounted, so the bolts, the
-- branches, the sparks and the arcs crawling over a body are really drawn by Lightning Beams.
-- Run from this folder:  cd Abilities/Killua && luaurun tests/client_standalone.luau

local H = assert(loadfile("tests/harness.luau"))()
local mock, check = H.mock, H.check
mock.isClient = true
local Config = require(H.Config)
local Players = game:GetService("Players")

-- Lightning Beams, laid out as in the package
local beams = mock.newInstance("Folder", "LightningBeams")
beams.Parent = H.folder
local bolt = mock.module(beams, "LightningBolt", "LightningBeams/LightningBolt.luau")
mock.module(bolt, "LightningSparks", "LightningBeams/LightningSparks.luau")
local cache = mock.newInstance("Folder", "PartCache")
cache.Parent = beams
mock.module(cache, "PartCache", "LightningBeams/PartCache/PartCache.luau")
mock.module(cache, "Table", "LightningBeams/PartCache/Table.luau")
if workspace:FindFirstChild("Terrain") == nil then
	local terrain = mock.newInstance("Terrain", "Terrain")
	terrain.Parent = workspace
	rawset(workspace, "Terrain", terrain)
end

local camera = mock.newInstance("Camera", "Camera")
camera.CFrame = CFrame.new(0, 6, 12)
camera.Parent = workspace
workspace.CurrentCamera = camera

local kModel, kParts = H.character("Killua", 0, 0, 0)
local k = H.player("Killua", kModel)
mock.newInstance("PlayerGui", "PlayerGui").Parent = k
Players.LocalPlayer = k
local dModel = H.character("D", 0, -10, 180)

local client = mock.newInstance("LocalScript", "KilluaClient")
rawget(client, "__props").__path = "src/KilluaClient.client.luau"
client.Parent = k
mock.runScript(client)
mock.advance(0.05)

local VFX = require(H.folder.KilluaVFX)

print("== Its own keys and bar")
for _, ability in ipairs(Config.Abilities) do
	local action = mock.actions["Killua" .. ability]
	check(action ~= nil, ability .. " bound")
	check(action and action.inputs[1] == Config.Keys[ability], ability .. " on " .. Config.Keys[ability].Name)
	check(action and action.inputs[2] == Config.GamepadButtons[ability], ability .. " on the gamepad")
	check(action and action.touch == Config.MobileButtons, ability .. " touch button")
end
local gui = k.PlayerGui:FindFirstChild("KilluaUI")
check(gui ~= nil, "the bar")
local function slot(ability)
	for _, d in ipairs(gui:GetDescendants()) do
		if d.Name == ability and d.ClassName == "Frame" then
			return d
		end
	end
end
local function shade(ability)
	return slot(ability):FindFirstChild("Cooldown").Size
end
for _, ability in ipairs(Config.Abilities) do
	check(slot(ability) ~= nil, ability .. " slot")
end

print("== Casting from the keys")
mock.actions.KilluaLightningPalm.fn("KilluaLightningPalm", Enum.UserInputState.Begin)
check(#H.sent("Cast", "client", H.remote) == 1, "Z: Lightning Palm")
mock.advance(0.1)
check(shade("LightningPalm")[2] > 0.9, "its slot shades over (cooldown)")
check(shade("Thunderbolt")[2] > 0 and shade("Thunderbolt")[2] < 0.2, "the others: the shared cooldown")
mock.actions.KilluaLightningPalm.fn("KilluaLightningPalm", Enum.UserInputState.Begin)
check(#H.sent("Cast", "client", H.remote) == 1, "again: denied")
mock.actions.KilluaLightningPalm.fn("KilluaLightningPalm", Enum.UserInputState.End)
check(#H.sent("Cast", "client", H.remote) == 1, "releases do nothing")
mock.advance(Config.LightningPalm.Cooldown)
check(shade("LightningPalm")[2] == 0, "ready again")

print("== Lightning Beams")
check(VFX.available(), "LightningBolt loads")
-- bolts are drawn with parts from a cache kept far away; the ones in use are brought to the bolt
local function boltPartsNear(point, radius)
	local n = 0
	for _, part in ipairs(workspace.Terrain:GetChildren()) do
		if part:IsA("BasePart") and (part.Position - point).Magnitude < radius and part.Transparency < 1 then
			n += 1
		end
	end
	return n
end
check(boltPartsNear(Vector3.new(0, 3, -4), 12) == 0, "no bolt yet")
mock.actions.KilluaLightningDash.fn("KilluaLightningDash", Enum.UserInputState.Begin)
mock.advance(2 / 60)
check(boltPartsNear(Vector3.new(0, 3, -4), 12) > 3, "the dash draws a bolt along its path")
mock.advance(0.5)
check(boltPartsNear(Vector3.new(0, 3, -4), 12) == 0, "and it's gone after its Life")
mock.actions.KilluaWhirlwind.fn("KilluaWhirlwind", Enum.UserInputState.Begin)
mock.advance(0.5)
local arcs = 0
for _, d in ipairs(kModel:GetDescendants()) do
	if d.Name == "KilluaArc" then
		arcs += 1
	end
end
check(arcs > 0, "arcs crawl over him in the stance")
H.remote.OnClientEvent:Fire("Thunderbolt", k, Vector3.new(0, 0, -10), workspace:GetServerTimeNow() + 0.3)
mock.advance(0.4)
H.remote.OnClientEvent:Fire("Hit", k, dModel, "LightningDash", Vector3.new(0, 3, -10), "Hit", "Shock")
dModel:SetAttribute("StunnedUntil", workspace:GetServerTimeNow() + 0.8)
mock.advance(1.5)
local sparks = VFX.Strike(Vector3.new(0, 3, 0), Vector3.new(0, 3, -20), { Sparks = 6, Branches = 3 })
mock.advance(0.1)
sparks:Stop()
mock.advance(1)
check(true, "strikes, sparks and the Narukami bolt ran without errors")
_ = kParts

H.finish("Killua client (standalone)")
