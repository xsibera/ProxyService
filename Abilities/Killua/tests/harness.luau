--!nocheck
-- Setup for the Killua tests: the kits' test engine plus ReplicatedStorage.Killua built from src/
-- (Config, KilluaVFX with the real effect tree, Animations, Remote; no LightningBeams, so bolts are
-- skipped unless a test mounts it). H.withCombatAndLoadout() adds ReplicatedStorage.Combat and
-- ReplicatedStorage.Loadout, as in the ability place (call it before running the scripts).

local H = assert(loadfile("../Shared/tests/engine.luau"))()
local mock = H.mock
local tree = assert(loadfile("tests/effects_tree.luau"))()

local RS = game:GetService("ReplicatedStorage")
local killua = mock.newInstance("Folder", "Killua")
killua.Parent = RS
H.folder = killua
H.Config = mock.module(killua, "Config", "src/Config.luau")
local vfx = mock.module(killua, "KilluaVFX", "src/KilluaVFX.luau")
mock.module(vfx, "EffectPlayer", "../Shared/EffectPlayer.luau")
local effects = mock.newInstance("Folder", "Effects")
effects.Parent = vfx
H.buildEffects(effects, tree)
H.sounds(vfx, { "Crackle", "PalmHit", "Thunder", "Dash", "Zap" })
H.remote = mock.newInstance("RemoteEvent", "Remote")
H.remote.Parent = killua
H.animations(killua, { "Palm", "Thunderbolt", "Land", "Stance", "Counter", "Dash1", "Dash2", "Dash3" }, "Killua ")
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
