--!nocheck
-- Setup for the village's tests: the kits' test engine with ReplicatedStorage.Combat, Loadout and
-- Melee (the bandits fight with the M1 string), as in the ability place.

local H = assert(loadfile("../Shared/tests/engine.luau"))()
local mock = H.mock

local RS = game:GetService("ReplicatedStorage")
function H.withCombatAndLoadout()
	local combat = mock.newInstance("Folder", "Combat")
	combat.Parent = RS
	mock.newInstance("RemoteEvent", "Remote").Parent = combat
	H.CombatModule = mock.module(combat, "Combat", "../Combat/src/Combat.luau")
	local loadout = mock.newInstance("Folder", "Loadout")
	loadout.Parent = RS
	mock.newInstance("RemoteEvent", "Remote").Parent = loadout
	H.LoadoutModule = mock.module(loadout, "Loadout", "../Loadout/src/Loadout.luau")
end

-- ReplicatedStorage.Melee, and MeleeServer running (call after withCombatAndLoadout)
function H.withMelee()
	local melee = mock.newInstance("Folder", "Melee")
	melee.Parent = RS
	H.MeleeConfig = mock.module(melee, "Config", "../Melee/src/Config.luau")
	H.meleeRemote = mock.newInstance("RemoteEvent", "Remote")
	H.meleeRemote.Parent = melee
	H.animations(melee, { "M1_1", "M1_2", "M1_3", "M1_4", "M1_5" }, "Fist ")
	local server = mock.newInstance("Script", "MeleeServer")
	rawget(server, "__props").__path = "../Melee/src/MeleeServer.server.luau"
	server.Parent = game:GetService("ServerScriptService")
	mock.runScript(server)
	mock.advance(0)
	H.meleeServer = server
end

return H
