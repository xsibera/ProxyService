"""Builds the Movement kit: sprinting, rolling, jumping and landing.

  python3 generate_movement.py path/to/ANIMSFORCLAUDE.rbxmx path/to/nen.rbxmx

The animations are anims.py's (the run plays as Sprint), the effects are the combat effects pack
(VFX/CombatVFX) and the roll's whoosh is the game's own sound. Writes:
  build/Movement.rbxmx     the ReplicatedStorage folder: Config, Animations, Sounds, Remote
  build/MovementRig.rbxmx  the animation rig (AnimSaves with every animation), for publishing
  Movement.rbxmx           the labelled kit: folders named for where each piece goes
"""

import copy
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ABILITIES = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ABILITIES, "Shared"))
import rbxbuild as B  # noqa: E402
from animkit import reference_rig  # noqa: E402

SRC = os.path.join(HERE, "src")
anims = B.load("movement_anims", os.path.join(HERE, "anims.py"))
SOUNDS = {"Roll": ("Slash", 0.75, 0.45)}  # new name: (the game's sound, playback speed, volume)
# Animation name in the kit (what MovementClient loads): the clip it plays
ANIMATIONS = {"Sprint": "Run", "Roll": "Roll", "Jump": "Jump", "Fall": "Fall", "Land": "Land"}


def sequences(rig_source=None):
    """{clip name: KeyframeSequence} for every clip in anims.py."""
    return B.sequences(anims.bake_all())


def movement_folder(nen_rbxmx, game):
    return B.folder("Movement", [
        B.module("Config", os.path.join(SRC, "Config.luau")),
        B.animations_folder(ANIMATIONS, game),
        B.sounds_folder(nen_rbxmx, SOUNDS),
        B.item("RemoteEvent", "Remote"),
    ])


def animation_rig(rig_source, game):
    rig, saves = reference_rig(rig_source, "Movement Animation Rig")
    for name in ANIMATIONS.values():
        saves.append(copy.deepcopy(game[name]))
    return B.reref(rig)


README = """--[[
	MOVEMENT: sprinting, rolling, jumping and landing. Where everything goes:

	1. The "Movement" folder               -> ReplicatedStorage
	2. MovementServer (Script)             -> ServerScriptService
	3. MovementClient (LocalScript)        -> StarterPlayer > StarterPlayerScripts
	4. CombatVFX (the combat effects pack)   -> ReplicatedStorage (skip it if you already have it)
	5. Needed - the Combat folder -> ReplicatedStorage, CombatServer -> ServerScriptService,
		CombatClient -> StarterPlayerScripts (the roll's dodge goes through it)
	6. Optional (Workspace): Movement Animation Rig - publish Run (as Sprint), Roll, Jump, Fall and
		Land from it, then paste the ids into Movement.Config.Animations.

	Play: hold Left Ctrl (or double-tap W and hold) to sprint; Q to roll; Space to jump.
	The game must use R6 avatars. Unpublished animations only play in Studio.
]]
return nil
"""


def labelled_kit(movement, rig, combat):
    cs = os.path.join(ABILITIES, "Combat", "src")
    kit = B.folder("Movement (sprint, roll, jump)", [
        B.source_module("READ ME", README),
        B.folder("1. Put the Movement folder in ReplicatedStorage", [copy.deepcopy(movement)]),
        B.folder("2. Put MovementServer in ServerScriptService", [
            B.script("Script", "MovementServer", os.path.join(SRC, "MovementServer.server.luau"))]),
        B.folder("3. Put MovementClient in StarterPlayer - StarterPlayerScripts", [
            B.script("LocalScript", "MovementClient", os.path.join(SRC, "MovementClient.client.luau"))]),
        B.folder("4. Put CombatVFX in ReplicatedStorage (the effects pack)", [B.combat_vfx()]),
        B.folder("5. Needed - the Combat folder to ReplicatedStorage, scripts as named", [
            copy.deepcopy(combat),
            B.script("Script", "CombatServer", os.path.join(cs, "CombatServer.server.luau")),
            B.script("LocalScript", "CombatClient", os.path.join(cs, "CombatClient.client.luau")),
        ]),
        B.folder("6. Optional - Workspace (animation rig to publish the animations)", [copy.deepcopy(rig)]),
    ])
    return B.reref(kit)


def build(rig_source, nen_rbxmx, combat=None):
    game = sequences(rig_source)
    movement = movement_folder(nen_rbxmx, game)
    rig = animation_rig(rig_source, game)
    os.makedirs(os.path.join(HERE, "build"), exist_ok=True)
    B.write([movement], os.path.join(HERE, "build", "Movement.rbxmx"))
    B.write([rig], os.path.join(HERE, "build", "MovementRig.rbxmx"))
    if combat is not None:
        B.write([labelled_kit(movement, rig, combat)], os.path.join(HERE, "Movement.rbxmx"))
    return movement


if __name__ == "__main__":
    generate_combat = B.load("movement_generate_combat", os.path.join(ABILITIES, "Combat", "generate_combat.py"))
    build(sys.argv[1], sys.argv[2], generate_combat.build(sys.argv[2]))
