--!nocheck
-- Headless test of the Loadout module and LoadoutServer against Place1's mock engine.
-- Run from this folder:  cd Abilities/Loadout && luaurun tests/server.luau

local H = assert(loadfile("tests/harness.luau"))()
local mock, check = H.mock, H.check
local Loadout = require(H.LoadoutModule)
local Combat = require(H.CombatModule)

print("== The module")
local p = Loadout.parse("Rock,Thunderbolt,,LightningDash")
check(p[1] == "Rock" and p[2] == "Thunderbolt" and p[3] == "" and p[4] == "LightningDash", "parse")
check(Loadout.parse("Nonsense,Rock")[1] == "" and Loadout.parse("Nonsense,Rock")[2] == "Rock", "unknown names dropped")
check(#Loadout.parse(nil) == 4 and Loadout.parse(nil)[1] == "", "nothing: four empty slots")
check(Loadout.format(p) == "Rock,Thunderbolt,,LightningDash", "format round-trips")
local placed = Loadout.place({ "Rock", "Paper", "Scissors", "" }, 4, "Rock")
check(placed[4] == "Rock" and placed[1] == "" and placed[2] == "Paper", "moving an ability empties its old slot")
local swapped = Loadout.place({ "Rock", "Paper", "Scissors", "Whirlwind" }, 1, "Whirlwind")
check(swapped[1] == "Whirlwind" and swapped[4] == "Rock", "onto a full slot: they swap")
for name, slots in pairs(Loadout.Presets) do
	for _, ability in ipairs(slots) do
		check(ability == "" or Loadout.Abilities[ability] ~= nil, name .. " preset: " .. ability .. " exists")
	end
end
for _, ability in ipairs(Loadout.Order) do
	check(Loadout.Abilities[ability] ~= nil, ability .. " listed in the menu exists")
end

print("== The server")
local character = H.character("Gon", 0, 0, 0)
local gon = H.player("Gon", character)
local SSS = game:GetService("ServerScriptService")
local serverScript = mock.newInstance("Script", "LoadoutServer")
rawget(serverScript, "__props").__path = "src/LoadoutServer.server.luau"
serverScript.Parent = SSS
mock.runScript(serverScript)
mock.advance(0)
check(gon:GetAttribute("Loadout") == table.concat(Loadout.Presets[Loadout.Default], ","), "joined: the default preset")
check(Loadout.has(gon, "LightningPalm") and not Loadout.has(gon, "Rock"), "has()")
check(Loadout.slotOf(gon, "Thunderbolt") == 2, "slotOf()")

local function send(...)
	H.remote.OnServerEvent:Fire(gon, ...)
end
send("Set", 1, "Rock")
check(Loadout.get(gon)[1] == "Rock" and not Loadout.has(gon, "LightningPalm"), "Set: Rock on Z replaces the palm")
send("Set", 2, "Rock")
check(Loadout.get(gon)[2] == "Rock" and Loadout.get(gon)[1] == "Thunderbolt", "Set onto another slot: swapped")
send("Set", 3, "")
check(Loadout.get(gon)[3] == "", "Set to empty")
local before = gon:GetAttribute("Loadout")
send("Set", 9, "Paper")
send("Set", 0, "Paper")
send("Set", 1.5, "Paper")
send("Set", 1, "NotAnAbility")
send("Set", "1", "Paper")
send("Set", 1, 42)
send("Preset", "Nobody")
send("Explode")
check(gon:GetAttribute("Loadout") == before, "bad requests change nothing")
send("Preset", "Gon")
check(gon:GetAttribute("Loadout") == "Rock,Paper,Scissors,", "Preset Gon")

print("== Not mid-attack")
Combat.setBusy(character, 1)
send("Preset", "Killua")
check(gon:GetAttribute("Loadout") == "Rock,Paper,Scissors,", "busy: refused")
Combat.clearBusy(character)
Combat.stun(character, 0.5)
send("Preset", "Killua")
check(gon:GetAttribute("Loadout") == "Rock,Paper,Scissors,", "stunned: refused")
mock.advance(0.6)
send("Preset", "Killua")
check(Loadout.has(gon, "Whirlwind"), "free again: changed")

H.finish("Loadout server")
