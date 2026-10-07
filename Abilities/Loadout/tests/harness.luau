--!nocheck
-- Setup for the Loadout tests: the kits' test engine plus ReplicatedStorage.Loadout (the module and
-- its Remote) and ReplicatedStorage.Combat (so "no changes mid-attack" can be tested).

local H = assert(loadfile("../Shared/tests/engine.luau"))()
local mock = H.mock

local RS = game:GetService("ReplicatedStorage")
local folder = mock.newInstance("Folder", "Loadout")
folder.Parent = RS
H.remote = mock.newInstance("RemoteEvent", "Remote")
H.remote.Parent = folder
H.LoadoutModule = mock.module(folder, "Loadout", "src/Loadout.luau")

local combat = mock.newInstance("Folder", "Combat")
combat.Parent = RS
mock.newInstance("RemoteEvent", "Remote").Parent = combat
H.CombatModule = mock.module(combat, "Combat", "../Combat/src/Combat.luau")

return H
