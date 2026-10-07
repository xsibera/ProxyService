"""Builds the Melee kit: a basic stun fighting system, the five-hit fist M1 string.

  python3 generate_melee.py path/to/ANIMSFORCLAUDE.rbxmx path/to/nen.rbxmx

The animations are the fist combo's five hits (Animations/FistCombo), the effects are the combat
effects pack (VFX/CombatVFX) and the sounds are the game's own (from nen.rbxmx). Writes:
  build/Melee.rbxmx       the ReplicatedStorage folder: Config, CombatVFX (+ Effects), Animations,
                          Sounds, Remote
  build/MeleeRig.rbxmx    the animation rig (AnimSaves with the five hits), for publishing
  Melee.rbxmx             the labelled kit: folders named for where each piece goes, with the stun
                          system (Combat) it needs
It also checks that Config's HitDelays land on the animations' Hit markers.
"""

import copy
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ABILITIES = os.path.dirname(HERE)
ROOT = os.path.dirname(ABILITIES)
sys.path.insert(0, os.path.join(ABILITIES, "Shared"))
import rbxbuild as B  # noqa: E402
from animkit import FPS, reference_rig  # noqa: E402

SRC = os.path.join(HERE, "src")
combo = B.load("fist_combo", os.path.join(ROOT, "Animations", "FistCombo", "generate_combo.py"))
VFX_DIR = os.path.join(ROOT, "VFX", "CombatVFX")

# the string, in order: (the fist combo's clip, its name here, the Animation the client loads)
HITS = [
    (combo.m1_1, "Fist M1 1", "M1_1"),  # lead jab
    (combo.m1_2, "Fist M1 2", "M1_2"),  # rear overhand
    (combo.m1_3, "Fist M1 3", "M1_3"),  # lead hook
    (combo.m1_4, "Fist M1 4", "M1_4"),  # uppercut
    (combo.m1_5, "Fist M1 5", "M1_5"),  # spinning backfist (the finisher)
]
SOUNDS = {  # new name: (the game's sound, playback speed, volume) - swap in your own any time
    "Swing": ("Slash", 1.5, 0.35),
    "Hit": ("RockHit", 1.55, 0.6),
    "Finisher": ("RockHit", 1.1, 0.9),
}


def bake():
    """[(clip, baked)] for the five hits, renamed for the kit."""
    out = []
    for make, name, _ in HITS:
        c = make()
        c.name = name
        out.append((c, c.bake()))
    return out


def check_timings(baked):
    """Each hit's HitDelay in Config must be its animation's Hit marker."""
    config = open(os.path.join(SRC, "Config.luau")).read()
    delays = [int(x) for x in re.findall(r"HitDelay = (\d+) / 60", config)]
    hits = [sorted(f for f, m in c.markers.items() if "Hit" in m)[0] for c, _ in baked]
    assert delays == hits, "Config.Hits HitDelays %s must be the Hit markers %s (in 60ths)" % (delays, hits)
    return hits


def combat_vfx():
    """The combat effects pack: the CombatVFX module with its Effects, as VFX/CombatVFX built it,
    carrying the current CombatVFX.luau."""
    module = copy.deepcopy(ET.parse(os.path.join(VFX_DIR, "CombatVFX.rbxmx")).getroot().find("Item"))
    source = module.find("Properties/ProtectedString[@name='Source']")
    source.text = open(os.path.join(VFX_DIR, "CombatVFX.luau")).read()
    return B.reref(module)


def melee_folder(nen_rbxmx, game):
    return B.folder("Melee", [
        B.module("Config", os.path.join(SRC, "Config.luau")),
        combat_vfx(),
        B.animations_folder({short: name for _, name, short in HITS}, game),
        B.sounds_folder(nen_rbxmx, SOUNDS),
        B.item("RemoteEvent", "Remote"),
    ])


def animation_rig(rig_source, game):
    rig, saves = reference_rig(rig_source, "Melee Animation Rig")
    for _, name, _ in HITS:
        saves.append(copy.deepcopy(game[name]))
    return B.reref(rig)


README = """--[[
	MELEE: a basic stun fighting system (the five-hit fist M1 string). Where everything goes:

	1. The "Melee" folder                  -> ReplicatedStorage
	2. MeleeServer (Script)                -> ServerScriptService
	3. MeleeClient (LocalScript)           -> StarterPlayer > StarterPlayerScripts
	4. The stun system, which it needs: the Combat folder -> ReplicatedStorage, CombatServer ->
	   ServerScriptService, CombatClient -> StarterPlayerScripts. It does the stun (and the hit
	   reactions, blocking with F and parrying).
	5. Optional (Workspace): Melee Animation Rig - open it in the Animation Editor to publish the five
	   hits, then paste their ids into Melee.Config.Animations.

	Play: left click (hold to keep going): jab, overhand, hook, uppercut, spinning backfist. Every hit
	stuns long enough for the next to land; the fifth knocks them away. Tune it in Melee > Config.
	The game must use R6 avatars. Unpublished animations only play in Studio.
]]
return nil
"""


def labelled_kit(melee, rig, combat):
    cs = os.path.join(ABILITIES, "Combat", "src")
    kit = B.folder("Melee (M1 stun combat)", [
        B.source_module("READ ME", README),
        B.folder("1. Put the Melee folder in ReplicatedStorage", [copy.deepcopy(melee)]),
        B.folder("2. Put MeleeServer in ServerScriptService", [
            B.script("Script", "MeleeServer", os.path.join(SRC, "MeleeServer.server.luau"))]),
        B.folder("3. Put MeleeClient in StarterPlayer - StarterPlayerScripts", [
            B.script("LocalScript", "MeleeClient", os.path.join(SRC, "MeleeClient.client.luau"))]),
        B.folder("4. Needed - the stun system (Combat): folder to ReplicatedStorage, scripts as named", [
            copy.deepcopy(combat),
            B.script("Script", "CombatServer", os.path.join(cs, "CombatServer.server.luau")),
            B.script("LocalScript", "CombatClient", os.path.join(cs, "CombatClient.client.luau")),
        ]),
        B.folder("5. Optional - Workspace (animation rig to publish the animations)", [copy.deepcopy(rig)]),
    ])
    return B.reref(kit)


def build(rig_source, nen_rbxmx, combat=None):
    baked = bake()
    hits = check_timings(baked)
    game = B.sequences(baked)
    melee = melee_folder(nen_rbxmx, game)
    rig = animation_rig(rig_source, game)
    os.makedirs(os.path.join(HERE, "build"), exist_ok=True)
    B.write([melee], os.path.join(HERE, "build", "Melee.rbxmx"))
    B.write([rig], os.path.join(HERE, "build", "MeleeRig.rbxmx"))
    if combat is not None:
        B.write([labelled_kit(melee, rig, combat)], os.path.join(HERE, "Melee.rbxmx"))
    print("hit markers:", [round(f / FPS, 4) for f in hits])
    return melee


if __name__ == "__main__":
    generate_combat = B.load("melee_generate_combat", os.path.join(ABILITIES, "Combat", "generate_combat.py"))
    build(sys.argv[1], sys.argv[2], generate_combat.build(sys.argv[2]))
