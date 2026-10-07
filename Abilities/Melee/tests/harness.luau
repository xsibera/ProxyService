--!nocheck
-- Setup for the Melee tests: the kits' test engine, ReplicatedStorage.Melee built from src/, a
-- recording stand-in for the effects pack (ReplicatedStorage.CombatVFX) and ReplicatedStorage.Combat,
-- which does the stun.

local H = assert(loadfile("../Shared/tests/engine.luau"))()
local mock = H.mock

local RS = game:GetService("ReplicatedStorage")
local melee = mock.newInstance("Folder", "Melee")
melee.Parent = RS
H.folder = melee
H.Config = mock.module(melee, "Config", "src/Config.luau")
H.VFXModule = mock.module(RS, "CombatVFX", "../Shared/tests/FakeCombatVFX.luau")
H.sounds(melee, { "Swing", "Hit", "Finisher" })
H.remote = mock.newInstance("RemoteEvent", "Remote")
H.remote.Parent = melee
H.animations(melee, { "M1_1", "M1_2", "M1_3", "M1_4", "M1_5" }, "Fist ")

local combat = mock.newInstance("Folder", "Combat")
combat.Parent = RS
H.combatRemote = mock.newInstance("RemoteEvent", "Remote")
H.combatRemote.Parent = combat
H.CombatModule = mock.module(combat, "Combat", "../Combat/src/Combat.luau")

if workspace:FindFirstChild("Terrain") == nil then
	local terrain = mock.newInstance("Terrain", "Terrain")
	terrain.Parent = workspace
	rawset(workspace, "Terrain", terrain)
end

return H
