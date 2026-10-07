--!nocheck
-- Setup for the Leorio tests: the kits' test engine plus ReplicatedStorage.Leorio built from src/
-- (Config, LeorioVFX with the real effect tree, Animations, Remote). H.withCombatAndLoadout() adds
-- ReplicatedStorage.Combat and ReplicatedStorage.Loadout, as in the ability place (call it before
-- running the scripts).

local H = assert(loadfile("../Shared/tests/engine.luau"))()
local mock = H.mock
local tree = assert(loadfile("tests/effects_tree.luau"))()

local RS = game:GetService("ReplicatedStorage")
local leorio = mock.newInstance("Folder", "Leorio")
leorio.Parent = RS
H.folder = leorio
H.Config = mock.module(leorio, "Config", "src/Config.luau")
local vfx = mock.module(leorio, "LeorioVFX", "src/LeorioVFX.luau")
mock.module(vfx, "EffectPlayer", "../Shared/EffectPlayer.luau")
local effects = mock.newInstance("Folder", "Effects")
effects.Parent = vfx
H.buildEffects(effects, tree)
H.sounds(vfx, { "Charge", "Warp", "Slam", "Punch", "Hit" })
H.remote = mock.newInstance("RemoteEvent", "Remote")
H.remote.Parent = leorio
H.animations(leorio, { "WarpPunch", "RemoteJab", "Barrage", "Burst" }, "Leorio ")
H.tree = tree

function H.withCombatAndLoadout()
	local combat = mock.newInstance("Folder", "Combat")
	combat.Parent = RS
	H.combatRemote = mock.newInstance("RemoteEvent", "Remote")
	H.combatRemote.Parent = combat
	H.CombatModule = mock.module(combat, "Combat", "../Combat/src/Combat.luau")
	local loadout = mock.newInstance("Folder", "Loadout")
	loadout.Parent = RS
	mock.newInstance("RemoteEvent", "Remote").Parent = loadout
	H.LoadoutModule = mock.module(loadout, "Loadout", "../Loadout/src/Loadout.luau")
end

return H
