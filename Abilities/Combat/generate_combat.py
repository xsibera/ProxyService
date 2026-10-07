"""Builds the Combat package (ReplicatedStorage.Combat) for the ability place:

  python3 generate_combat.py path/to/nen.rbxmx

  build/Combat.rbxmx        Combat (rules), CombatVFX (+ EffectPlayer, Effects, Sounds), Animations, Remote
  tests/effects_tree.luau   the effect tree as data, for the tests
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SHARED = os.path.join(HERE, "..", "Shared")
sys.path.insert(0, SHARED)
sys.path.insert(0, HERE)
import rbxbuild as B  # noqa: E402

SRC = os.path.join(HERE, "src")
anims = B.load("combat_anims", os.path.join(HERE, "anims.py"))
effects = B.load("combat_effects", os.path.join(HERE, "effects.py"))
SOUNDS = {  # new name: (the game's sound, playback speed, volume)
    "Parry": ("Slash", 1.7, 1.4),
    "Block": ("GroundHit", 1.9, 0.5),
    "GuardBreak": ("RockHit", 0.85, 1.0),
}


def combat_folder(nen_rbxmx):
    effect_folder, summary = effects.build_effects(nen_rbxmx)
    game = B.sequences(anims.bake_all())
    vfx = B.module("CombatVFX", os.path.join(SRC, "CombatVFX.luau"), [
        B.module("EffectPlayer", os.path.join(SHARED, "EffectPlayer.luau")),
        effect_folder,
        B.sounds_folder(nen_rbxmx, SOUNDS),
    ])
    out = B.folder("Combat", [
        B.module("Combat", os.path.join(SRC, "Combat.luau")),
        vfx,
        B.animations_folder(anims.NAMES, game),
        B.item("RemoteEvent", "Remote"),
    ])
    return out, summary, game


def build(nen_rbxmx):
    folder, summary, _ = combat_folder(nen_rbxmx)
    B.write([folder], os.path.join(HERE, "build", "Combat.rbxmx"))
    open(os.path.join(HERE, "tests", "effects_tree.luau"), "w").write(B.lua_effects(summary, "generate_combat.py"))
    return folder


if __name__ == "__main__":
    build(sys.argv[1])
