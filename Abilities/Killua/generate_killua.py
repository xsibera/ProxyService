"""Builds Killua Zoldyck's lightning (Hunter x Hunter) as a drop-in Roblox ability kit.

  python3 generate_killua.py path/to/ANIMSFORCLAUDE.rbxmx path/to/nen.rbxmx

ANIMSFORCLAUDE gives the R6 rig (for the animation rig), nen.rbxmx the emitters and sounds the
effects are built from. Writes:
  build/Killua.rbxmx        the ReplicatedStorage folder: Config, KilluaVFX (+ EffectPlayer, Effects,
                            Sounds), LightningBeams, Animations, Remote
  build/KilluaRig.rbxmx     the animation rig (AnimSaves with every clip), for the place
  Killua.rbxmx              the labelled kit: folders named for where each piece goes
  tests/effects_tree.luau   the effect tree as data, for the tests
It also checks that the server's timings (Config) land on the animations' Hit markers.
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
anims = B.load("killua_anims", os.path.join(HERE, "anims.py"))
effects = B.load("killua_effects", os.path.join(HERE, "effects.py"))
BEAMS = os.path.join(HERE, "LightningBeams")

ANIMATIONS = {  # the Animation the client loads -> the KeyframeSequence inside it
    "Palm": "Killua Palm",
    "Thunderbolt": "Killua Thunderbolt",
    "Land": "Killua Land",
    "Stance": "Killua Stance",
    "Counter": "Killua Counter",
    "Dash1": "Killua Dash 1",
    "Dash2": "Killua Dash 2",
    "Dash3": "Killua Dash 3",
}
SOUNDS = {  # new name: (the game's sound, playback speed, volume) - swap in real electric sounds any time
    "Crackle": ("ScissorsCast", 1.9, 0.35),
    "PalmHit": ("RockHit", 1.35, 0.9),
    "Thunder": ("GroundHit", 0.75, 1.0),
    "Dash": ("Slash", 1.6, 0.8),
    "Zap": ("PaperHit", 1.7, 0.6),
}


# --------------------------------------------------------------------------- the package
def lightning_beams():
    """Quasiduck's Lightning Beams, laid out as the module expects: LightningBolt (with LightningSparks
    inside it) beside a PartCache folder."""
    license_text = open(os.path.join(BEAMS, "LICENSE")).read()
    note = "--[[\n\tLightning Beams by Quasiduck: https://github.com/SamyBlue/Lightning-Beams (v1.1, 406c3b9)\n" \
           "\tLightningSparks is the pre-v1.1 sub-module, patched to work with v1.1 (see the [Killua kit patch]\n" \
           "\tcomments). PartCache is EtiTheSpirit's (MIT). The license:\n\n" + license_text + "]]\nreturn nil\n"
    return B.folder("LightningBeams", [
        B.module("LightningBolt", os.path.join(BEAMS, "LightningBolt.luau"), [
            B.module("LightningSparks", os.path.join(BEAMS, "LightningSparks.luau")),
        ]),
        B.folder("PartCache", [
            B.module("PartCache", os.path.join(BEAMS, "PartCache", "PartCache.luau")),
            B.module("Table", os.path.join(BEAMS, "PartCache", "Table.luau")),
        ]),
        B.source_module("LICENSE", note),
    ])


def killua_folder(nen_rbxmx, game):
    effect_folder, summary = effects.build_effects(nen_rbxmx)
    vfx = B.module("KilluaVFX", os.path.join(SRC, "KilluaVFX.luau"), [
        B.module("EffectPlayer", os.path.join(SHARED, "EffectPlayer.luau")),
        effect_folder,
        B.sounds_folder(nen_rbxmx, SOUNDS),
    ])
    out = B.folder("Killua", [
        B.module("Config", os.path.join(SRC, "Config.luau")),
        vfx,
        lightning_beams(),
        B.animations_folder(ANIMATIONS, game),
        B.item("RemoteEvent", "Remote"),
    ])
    return out, summary


def animation_rig(rig_source, game):
    rig, saves = reference_rig(rig_source, "Killua Animation Rig")
    for name in ANIMATIONS.values():
        saves.append(copy.deepcopy(game[name]))
    return B.reref(rig)


# --------------------------------------------------------------------------- the server's timings
def check_timings(baked):
    """Every delay the server waits before a hit must land on that animation's Hit marker."""
    config = open(os.path.join(SRC, "Config.luau")).read()
    hits = {c.name: sorted(f for f, m in c.markers.items() if "Hit" in m) for c, _ in baked}
    lengths = {c.name: c.frames for c, _ in baked}

    def has(text, what):
        assert text in config, "Config.luau: expected `%s` (%s)" % (text, what)

    has("HitDelay = %d / 60," % hits["Killua Palm"][0], "Lightning Palm's HitDelay = the Hit marker in Killua Palm")
    has("HitDelay = %d / 60," % hits["Killua Thunderbolt"][0], "Thunderbolt's HitDelay = the Hit marker")
    has("LeapAt = %d / 60," % anims.TAKE_OFF, "Thunderbolt's LeapAt = the take-off frame")
    for f in hits["Killua Counter"]:
        has("At = %d / 60," % f, "a Whirlwind hit on a Hit marker in Killua Counter")
    has("Length = %d / 60," % lengths["Killua Counter"], "Whirlwind's Length = Killua Counter's length")
    for n in (1, 2, 3):
        has("Delay = %d / 60," % hits["Killua Dash %d" % n][0], "Lightning Dash %d's Delay = its Hit marker" % n)
    order = re.findall(r"\bDelay = (\d+) / 60", config)
    assert [int(x) for x in order] == [hits["Killua Dash %d" % n][0] for n in (1, 2, 3)], order
    return hits


# --------------------------------------------------------------------------- the labelled kit
README = """--[[
	KILLUA (Killua Zoldyck, Hunter x Hunter): where everything goes

	1. The "Killua" folder                  -> ReplicatedStorage
	2. KilluaServer (Script)               -> ServerScriptService
	3. KilluaClient (LocalScript)          -> StarterPlayer > StarterPlayerScripts
	4. Optional, for a parry-style fight (recommended): the Combat folder -> ReplicatedStorage,
	   CombatServer -> ServerScriptService, CombatClient -> StarterPlayerScripts. Every hit then
	   goes through it: F to block, tap F to parry, guard breaks, stuns, and Whirlwind's counter.
	   Without it the abilities still work (plain damage and knockback) but Whirlwind can't counter.
	5. Optional: the Loadout folder + LoadoutServer + LoadoutClient, for the ability menu (M) and hotbar
	   when you have more than one kit (Jajanken, Killua...).
	6. Optional (Workspace): Killua Animation Rig - open it in the Animation Editor to publish the
	   animations, then paste their ids into Killua.Config.Animations.

	Play: Z Lightning Palm, X Thunderbolt, C Whirlwind, V Lightning Dash (press up to 3 times).
	Everything is tuned in Killua > Config. The game must use R6 avatars.
	Unpublished animations only play in Studio. Publish them before a live game.
]]
return nil
"""


def labelled_kit(killua, rig, extras):
    combat, combat_scripts, loadout, loadout_scripts = extras
    kit = B.folder("Killua (Godspeed lightning)", [
        B.source_module("READ ME", README),
        B.folder("1. Put the Killua folder in ReplicatedStorage", [copy.deepcopy(killua)]),
        B.folder("2. Put KilluaServer in ServerScriptService", [
            B.script("Script", "KilluaServer", os.path.join(SRC, "KilluaServer.server.luau"))]),
        B.folder("3. Put KilluaClient in StarterPlayer - StarterPlayerScripts", [
            B.script("LocalScript", "KilluaClient", os.path.join(SRC, "KilluaClient.client.luau"))]),
        B.folder("4. Optional - the parry system (Combat): folder to ReplicatedStorage, scripts as named",
                 [copy.deepcopy(combat)] + combat_scripts),
        B.folder("5. Optional - the ability menu (Loadout): folder to ReplicatedStorage, scripts as named",
                 [copy.deepcopy(loadout)] + loadout_scripts),
        B.folder("6. Optional - Workspace (animation rig to publish the animations)", [copy.deepcopy(rig)]),
    ])
    return B.reref(kit)


def build(rig_source, nen_rbxmx, extras=None):
    baked = anims.bake_all()
    hits = check_timings(baked)
    game = B.sequences(baked)
    killua, summary = killua_folder(nen_rbxmx, game)
    rig = animation_rig(rig_source, game)
    os.makedirs(os.path.join(HERE, "build"), exist_ok=True)
    B.write([killua], os.path.join(HERE, "build", "Killua.rbxmx"))
    B.write([rig], os.path.join(HERE, "build", "KilluaRig.rbxmx"))
    open(os.path.join(HERE, "tests", "effects_tree.luau"), "w").write(B.lua_effects(summary, "generate_killua.py"))
    if extras:
        B.write([labelled_kit(killua, rig, extras)], os.path.join(HERE, "Killua.rbxmx"))
    for name, rows in summary.items():
        print("  %-14s %2d layers" % (name, len(rows)))
    print("hit markers:", {k: [round(f / FPS, 4) for f in v] for k, v in hits.items() if v})
    return killua, rig


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
