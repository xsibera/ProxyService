--!nocheck
-- Setup for the Combat tests: the kits' test engine plus ReplicatedStorage.Combat built from src/
-- (Combat, CombatVFX with the real effect tree, the reaction Animations, the Remote).

local H = assert(loadfile("../Shared/tests/engine.luau"))()
local mock = H.mock
local tree = assert(loadfile("tests/effects_tree.luau"))()

local RS = game:GetService("ReplicatedStorage")
local folder = mock.newInstance("Folder", "Combat")
folder.Parent = RS
H.folder = folder
H.remote = mock.newInstance("RemoteEvent", "Remote")
H.remote.Parent = folder
H.CombatModule = mock.module(folder, "Combat", "src/Combat.luau")
local vfx = mock.module(folder, "CombatVFX", "src/CombatVFX.luau")
mock.module(vfx, "EffectPlayer", "../Shared/EffectPlayer.luau")
local effects = mock.newInstance("Folder", "Effects")
effects.Parent = vfx
H.buildEffects(effects, tree)
H.sounds(vfx, { "Parry", "Block", "GuardBreak" })
H.animations(folder, { "Block", "Parry", "Hit", "Shocked", "GuardBreak", "Parried" }, "Combat ")

return H
