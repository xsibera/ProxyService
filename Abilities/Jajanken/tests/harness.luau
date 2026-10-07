--!nocheck
-- Shared setup for the Jajanken tests: the kits' test engine (../Shared/tests/engine.luau: Place1's
-- mock engine plus what the abilities need), the ReplicatedStorage.Jajanken folder built from src/
-- and the real effect tree (tests/effects_tree.luau).

local H = assert(loadfile("../Shared/tests/engine.luau"))()
local mock = H.mock
local tree = assert(loadfile("tests/effects_tree.luau"))()

--------------------------------------------------------------------------- the Jajanken folder

local RS = game:GetService("ReplicatedStorage")
local jajanken = mock.newInstance("Folder", "Jajanken")
jajanken.Parent = RS
H.folder = jajanken
H.Config = mock.module(jajanken, "Config", "src/Config.luau")
local vfxModule = mock.module(jajanken, "JajankenVFX", "src/JajankenVFX.luau")
local effects = mock.newInstance("Folder", "Effects")
effects.Parent = vfxModule
local sounds = mock.newInstance("Folder", "Sounds")
sounds.Parent = vfxModule
for _, name in ipairs({ "RockHit", "PaperHit", "ScissorsCast" }) do
	local sound = mock.newInstance("Sound", name)
	sound.Volume = 0.5
	sound.Parent = sounds
end
H.remote = mock.newInstance("RemoteEvent", "Remote")
H.remote.Parent = jajanken
local animations = mock.newInstance("Folder", "Animations")
animations.Parent = jajanken
for _, name in ipairs({ "Charge", "Hold", "Rock", "Paper", "Scissors" }) do
	local anim = mock.newInstance("Animation", name)
	anim.AnimationId = ""
	mock.newInstance("KeyframeSequence", "Jajanken " .. name).Parent = anim
	anim.Parent = animations
end

-- the real effect tree: every layer with the attributes generate_jajanken.py gave it
H.buildEffects(effects, tree)
H.tree = tree

-- ReplicatedStorage.Combat and .Loadout, as in the ability place (call before running the scripts)
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

return H
