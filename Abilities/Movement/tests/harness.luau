--!nocheck
-- Setup for the Movement tests: the kits' test engine, ReplicatedStorage.Movement built from src/,
-- a recording stand-in for the effects pack (ReplicatedStorage.CombatVFX) and ReplicatedStorage.Combat
-- (the roll's dodge goes through it).

local H = assert(loadfile("../Shared/tests/engine.luau"))()
local mock = H.mock

local RS = game:GetService("ReplicatedStorage")
local movement = mock.newInstance("Folder", "Movement")
movement.Parent = RS
H.folder = movement
H.Config = mock.module(movement, "Config", "src/Config.luau")
H.sounds(movement, { "Roll" })
H.remote = mock.newInstance("RemoteEvent", "Remote")
H.remote.Parent = movement
H.animations(movement, { "Sprint", "Roll" })
H.VFXModule = mock.module(RS, "CombatVFX", "../Shared/tests/FakeCombatVFX.luau")

local combat = mock.newInstance("Folder", "Combat")
combat.Parent = RS
mock.newInstance("RemoteEvent", "Remote").Parent = combat
H.CombatModule = mock.module(combat, "Combat", "../Combat/src/Combat.luau")

if workspace:FindFirstChild("Terrain") == nil then
	local terrain = mock.newInstance("Terrain", "Terrain")
	terrain.Parent = workspace
	rawset(workspace, "Terrain", terrain)
end

return H
