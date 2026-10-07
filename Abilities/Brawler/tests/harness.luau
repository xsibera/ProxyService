--!nocheck
-- Setup for the Brawler tests: the kits' test engine, ReplicatedStorage.Brawler built from src/ (the
-- grab paths from tests/grab_paths.luau, which generate_brawler.py writes alongside the real ones),
-- a recording stand-in for the effects pack (ReplicatedStorage.CombatVFX), and Combat and Loadout as
-- in the ability place.

local H = assert(loadfile("../Shared/tests/engine.luau"))()
local mock = H.mock

local RS = game:GetService("ReplicatedStorage")
local brawler = mock.newInstance("Folder", "Brawler")
brawler.Parent = RS
H.folder = brawler
H.Config = mock.module(brawler, "Config", "src/Config.luau")
H.GrabPaths = mock.module(brawler, "GrabPaths", "tests/grab_paths.luau")
H.VFXModule = mock.module(RS, "CombatVFX", "../Shared/tests/FakeCombatVFX.luau")
H.sounds(brawler, { "Swing", "Punch", "Heavy", "Slam", "Grab" })
H.remote = mock.newInstance("RemoteEvent", "Remote")
H.remote.Parent = brawler
H.animations(brawler, {
	"Haymaker",
	"Uppercut",
	"Roundhouse",
	"AxeKick",
	"GroundSlam",
	"Grab",
	"Suplex",
	"Chokeslam",
	"Throw",
	"HeldSuplex",
	"HeldChokeslam",
	"HeldThrow",
	"GetUp",
}, "Brawler ")

local combat = mock.newInstance("Folder", "Combat")
combat.Parent = RS
H.combatRemote = mock.newInstance("RemoteEvent", "Remote")
H.combatRemote.Parent = combat
H.CombatModule = mock.module(combat, "Combat", "../Combat/src/Combat.luau")
local loadout = mock.newInstance("Folder", "Loadout")
loadout.Parent = RS
mock.newInstance("RemoteEvent", "Remote").Parent = loadout
H.LoadoutModule = mock.module(loadout, "Loadout", "../Loadout/src/Loadout.luau")

return H
