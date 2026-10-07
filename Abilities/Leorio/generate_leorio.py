"""Builds Leorio Paladiknight's warp punches (Hunter x Hunter) as a drop-in Roblox ability kit.

  python3 generate_leorio.py path/to/ANIMSFORCLAUDE.rbxmx path/to/nen.rbxmx

ANIMSFORCLAUDE gives the R6 rig (for the animation rig), nen.rbxmx the emitters and sounds the
effects are built from. Writes:
  build/Leorio.rbxmx        the ReplicatedStorage folder: Config, LeorioVFX (+ EffectPlayer, Effects,
                            Sounds), Animations, Remote
  build/LeorioRig.rbxmx     the animation rig (AnimSaves with every clip), for the place
  Leorio.rbxmx              the labelled kit: folders named for where each piece goes
  tests/effects_tree.luau   the effect tree as data, for the tests
It also checks that the server's timings (Config) land on the animations' Hit and Warp markers.
"""

import copy
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SHARED = os.path.join(HERE, "..", "Shared")
sys.path.insert(0, SHARED)
sys.path.insert(0, HERE)
import rbxbuild as B  # noqa: E402
from animkit import FPS, reference_rig  # noqa: E402

SRC = os.path.join(HERE, "src")
anims = B.load("leorio_anims", os.path.join(HERE, "anims.py"))
effects = B.load("leorio_effects", os.path.join(HERE, "effects.py"))

ANIMATIONS = {  # the Animation the client loads -> the KeyframeSequence inside it
    "WarpPunch": "Leorio Warp Punch",
    "RemoteJab": "Leorio Remote Jab",
    "Barrage": "Leorio Barrage",
    "Burst": "Leorio Burst",
}
SOUNDS = {  # new name: (the game's sound, playback speed, volume) - swap in your own any time
    "Charge": ("ScissorsCast", 0.8, 0.4),
    "Warp": ("Slash", 0.7, 0.6),
    "Slam": ("GroundHit", 1.05, 0.9),
    "Punch": ("RockHit", 0.85, 1.0),
    "Hit": ("RockHit", 1.2, 0.9),
}


# --------------------------------------------------------------------------- the package
def leorio_folder(nen_rbxmx, game):
    effect_folder, summary = effects.build_effects(nen_rbxmx)
    vfx = B.module("LeorioVFX", os.path.join(SRC, "LeorioVFX.luau"), [
        B.module("EffectPlayer", os.path.join(SHARED, "EffectPlayer.luau")),
        effect_folder,
        B.sounds_folder(nen_rbxmx, SOUNDS),
    ])
    out = B.folder("Leorio", [
        B.module("Config", os.path.join(SRC, "Config.luau")),
        vfx,
        B.animations_folder(ANIMATIONS, game),
        B.item("RemoteEvent", "Remote"),
    ])
    return out, summary


def animation_rig(rig_source, game):
    rig, saves = reference_rig(rig_source, "Leorio Animation Rig")
    for name in ANIMATIONS.values():
        saves.append(copy.deepcopy(game[name]))
    return B.reref(rig)


# --------------------------------------------------------------------------- the server's timings
def check_timings(baked):
    """Every delay the server waits must land on that animation's marker: the fist going into the
    floor (Hit) and the blow coming out of the hole (Warp)."""
    config = open(os.path.join(SRC, "Config.luau")).read()
    marks = {}
    for c, _ in baked:
        for f, names in c.markers.items():
            for name in names:
                marks.setdefault((c.name, name), []).append(f)
    marks = {k: sorted(v) for k, v in marks.items()}
    lengths = {c.name: c.frames for c, _ in baked}

    def has(text, what):
        assert text in config, "Config.luau: expected `%s` (%s)" % (text, what)

    has("PunchAt = %d / 60," % marks[("Leorio Warp Punch", "Hit")][0], "Warp Punch's PunchAt = the Hit marker")
    has("HitDelay = %d / 60," % marks[("Leorio Warp Punch", "Warp")][0], "Warp Punch's HitDelay = the Warp marker")
    has("JabAt = %d / 60," % marks[("Leorio Remote Jab", "Hit")][0], "Remote Jab's JabAt = the Hit marker")
    has("HitDelay = %d / 60," % marks[("Leorio Remote Jab", "Warp")][0], "Remote Jab's HitDelay = the Warp marker")
    barrage = marks[("Leorio Barrage", "Hit")]
    order = [int(x) for x in re.findall(r"\{ At = (\d+) / 60,", config)]
    assert order == barrage, "Config.WarpBarrage.Hits' At = the Hit markers in Leorio Barrage: %s vs %s" % (
        order, barrage)
    has("Length = %d / 60," % lengths["Leorio Barrage"], "Warp Barrage's Length = Leorio Barrage's length")
    has("HitDelay = %d / 60," % marks[("Leorio Burst", "Hit")][0], "Portal Burst's HitDelay = the Hit marker")
    return marks


# --------------------------------------------------------------------------- the labelled kit
README = """--[[
	LEORIO (Leorio Paladiknight, Hunter x Hunter): where everything goes

	1. The "Leorio" folder                  -> ReplicatedStorage
	2. LeorioServer (Script)               -> ServerScriptService
	3. LeorioClient (LocalScript)          -> StarterPlayer > StarterPlayerScripts
	4. Optional, for a parry-style fight (recommended): the Combat folder -> ReplicatedStorage,
		CombatServer -> ServerScriptService, CombatClient -> StarterPlayerScripts. Every hit then
		goes through it: F to block, tap F to parry, guard breaks and stuns. A blow out of a warp
		hole comes from the hole: face the hole to block or parry it.
		Without it the abilities still work (plain damage and knockback).
	5. Optional: the Loadout folder + LoadoutServer + LoadoutClient, for the ability menu (M) and hotbar
		when you have more than one kit (Jajanken, Killua, Leorio...).
	6. Optional (Workspace): Leorio Animation Rig - open it in the Animation Editor to publish the
		animations, then paste their ids into Leorio.Config.Animations.

	Play: Z Warp Punch, X Remote Jab, C Warp Barrage, V Portal Burst. Aim with the camera.
	Everything is tuned in Leorio > Config. The game must use R6 avatars.
	Unpublished animations only play in Studio. Publish them before a live game.
]]
return nil
"""


def labelled_kit(leorio, rig, extras):
    combat, combat_scripts, loadout, loadout_scripts = extras
    kit = B.folder("Leorio (warp punches)", [
        B.source_module("READ ME", README),
        B.folder("1. Put the Leorio folder in ReplicatedStorage", [copy.deepcopy(leorio)]),
        B.folder("2. Put LeorioServer in ServerScriptService", [
            B.script("Script", "LeorioServer", os.path.join(SRC, "LeorioServer.server.luau"))]),
        B.folder("3. Put LeorioClient in StarterPlayer - StarterPlayerScripts", [
            B.script("LocalScript", "LeorioClient", os.path.join(SRC, "LeorioClient.client.luau"))]),
        B.folder("4. Optional - the parry system (Combat): folder to ReplicatedStorage, scripts as named",
                 [copy.deepcopy(combat)] + combat_scripts),
        B.folder("5. Optional - the ability menu (Loadout): folder to ReplicatedStorage, scripts as named",
                 [copy.deepcopy(loadout)] + loadout_scripts),
        B.folder("6. Optional - Workspace (animation rig to publish the animations)", [copy.deepcopy(rig)]),
    ])
    return B.reref(kit)


def build(rig_source, nen_rbxmx, extras=None):
    baked = anims.bake_all()
    marks = check_timings(baked)
    game = B.sequences(baked)
    leorio, summary = leorio_folder(nen_rbxmx, game)
    rig = animation_rig(rig_source, game)
    os.makedirs(os.path.join(HERE, "build"), exist_ok=True)
    B.write([leorio], os.path.join(HERE, "build", "Leorio.rbxmx"))
    B.write([rig], os.path.join(HERE, "build", "LeorioRig.rbxmx"))
    open(os.path.join(HERE, "tests", "effects_tree.luau"), "w").write(B.lua_effects(summary, "generate_leorio.py"))
    if extras:
        B.write([labelled_kit(leorio, rig, extras)], os.path.join(HERE, "Leorio.rbxmx"))
    for name, rows in summary.items():
        print("  %-12s %2d layers" % (name, len(rows)))
    print("markers:", {"%s %s" % k: [round(f / FPS, 4) for f in v] for k, v in marks.items()})
    return leorio, rig


if __name__ == "__main__":
    sys.path.insert(0, os.path.join(HERE, "..", "Combat"))
    sys.path.insert(0, os.path.join(HERE, "..", "Loadout"))
    import generate_combat  # noqa: E402
    import generate_loadout  # noqa: E402

    combat = generate_combat.build(sys.argv[2])
    loadout = generate_loadout.build()
    cs = os.path.join(HERE, "..", "Combat", "src")
    ls = os.path.join(HERE, "..", "Loadout", "src")
    extras = (
        combat,
        [B.script("Script", "CombatServer", os.path.join(cs, "CombatServer.server.luau")),
         B.script("LocalScript", "CombatClient", os.path.join(cs, "CombatClient.client.luau"))],
        loadout,
        [B.script("Script", "LoadoutServer", os.path.join(ls, "LoadoutServer.server.luau")),
         B.script("LocalScript", "LoadoutClient", os.path.join(ls, "LoadoutClient.client.luau"))],
    )
    build(sys.argv[1], sys.argv[2], extras)
