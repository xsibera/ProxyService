"""Builds Gon Freecss's Jajanken (Hunter x Hunter) as a drop-in Roblox ability.

  python3 generate_jajanken.py path/to/ANIMSFORCLAUDE.rbxmx path/to/nen.rbxmx

ANIMSFORCLAUDE gives the R6 rig, and nen.rbxmx (VFXFORCLAUDE + the nen auras) gives the emitters the
effects are built from. Writes into build/:
  Jajanken.rbxmx       the ReplicatedStorage folder (Config, JajankenVFX + effects + sounds, Animations, Remote)
  JajankenRig.rbxmx    the animation rig, which the ability place's village (../Village) stands in its
                       training yard
and next to this file:
  Jajanken.rbxmx       the labelled kit: folders named for where each piece goes in your own game
                       (with the parry system and the ability menu from ../Combat/build and
                       ../Loadout/build, when they have been built)
  tests/effects_tree.luau   the effect tree as data, for the tests
Then ./build.sh turns them into Jajanken.rbxl (Rojo, place.project.json) and Jajanken.rbxm.
"""

import copy
import os
import sys
import xml.etree.ElementTree as ET

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import anims  # noqa: E402
import effects  # noqa: E402
from animkit import FPS, build_string, clip_transforms, ref, reference_rig, sequence_xml  # noqa: E402

BUILD = os.path.join(HERE, "build")
SRC = os.path.join(HERE, "src")
ABILITIES = os.path.dirname(HERE)

# the Animation objects the client loads, by name -> the KeyframeSequence inside
ANIMATIONS = {
    "Charge": "Jajanken Charge",
    "Hold": "Jajanken Hold",
    "Rock": "Jajanken Rock",
    "Paper": "Jajanken Paper",
    "Scissors": "Jajanken Scissors",
}


# --------------------------------------------------------------------------- XML helpers
def item(cls, name, children=(), **props):
    """An instance. props: name -> (tag, text) or (tag, {child: text})."""
    el = ET.Element("Item", {"class": cls, "referent": ref()})
    p = ET.SubElement(el, "Properties")
    ET.SubElement(p, "string", {"name": "Name"}).text = name
    for key, (tag, value) in props.items():
        sub = ET.SubElement(p, tag, {"name": key})
        if isinstance(value, dict):
            for k, v in value.items():
                ET.SubElement(sub, k).text = str(v)
        elif value is not None:
            sub.text = str(value)
    for child in children:
        el.append(child)
    return el


def source(path):
    return open(os.path.join(SRC, path)).read()


def module(name, path, children=()):
    return item("ModuleScript", name, children, Source=("ProtectedString", source(path)))


def script(cls, name, path):
    return item(cls, name, Source=("ProtectedString", source(path)), Disabled=("bool", "false"))


def folder(name, children=()):
    return item("Folder", name, children)


def cframe_props(m):
    out = {k: repr(float(v)) for k, v in zip("XYZ", m[:3, 3])}
    for i in range(3):
        for j in range(3):
            out["R%d%d" % (i, j)] = repr(float(m[i, j]))
    return out


def part(name, size, position, color, material, rot=None, cls="Part", **extra):
    m = np.eye(4)
    m[:3, 3] = position
    if rot is not None:
        m[:3, :3] = rot
    props = {
        "CFrame": ("CoordinateFrame", cframe_props(m)),
        "size": ("Vector3", {"X": size[0], "Y": size[1], "Z": size[2]}),
        "Color3uint8": ("Color3uint8", str((color[0] << 16) | (color[1] << 8) | color[2])),
        "Material": ("token", str(material)),
        "Anchored": ("bool", "true"),
        "TopSurface": ("token", "0"),
        "BottomSurface": ("token", "0"),
    }
    props.update(extra)
    return item(cls, name, **props)


# --------------------------------------------------------------------------- animations
def baked_sequences():
    """KeyframeSequences for the five clips, plus a full-cast preview per release (charge, a second
    of hold, then the release) for the Animation Editor. Returns (game sequences, previews, hits)."""
    clips = {}
    for c, baked in anims.bake_all():
        clips[c.name] = (c, clip_transforms(c, baked))
    game = {}
    for name, (c, frames) in clips.items():
        game[name] = sequence_xml(name, frames, c.markers, loop=c.loop)  # legs at Weight 0: the walk drives them
    previews = []
    stance = clips["Jajanken Hold"][1][0]
    for mode in ("Rock", "Paper", "Scissors"):
        chain = [clips["Jajanken Charge"], clips["Jajanken Hold"], clips["Jajanken " + mode]]
        end = clips["Jajanken " + mode][1][-1]
        frames, hits = build_string(chain, {"Jajanken Charge": 0.4, "Jajanken Hold": 1.0}, 0.1, 0.3, stance, end)
        previews.append(sequence_xml("Jajanken %s (full cast preview)" % mode, frames, hits))
    hits = {name: c.hit / FPS for name, (c, _) in clips.items() if c.hit is not None}
    return game, previews, hits


def animations_folder(game):
    out = []
    for name, sequence in ANIMATIONS.items():
        anim = item("Animation", name, [copy.deepcopy(game[sequence])])
        ET.SubElement(anim.find("Properties"), "Content", {"name": "AnimationId"}).append(ET.Element("null"))
        out.append(anim)
    return folder("Animations", out)


# --------------------------------------------------------------------------- sounds
def sounds_folder(nen_rbxmx):
    """The game's own Jajanken sounds (RockHit, PaperHit, ScissorsCast), copied as they are."""
    root = ET.parse(nen_rbxmx).getroot()
    wanted = {"RockHit", "PaperHit", "ScissorsCast"}
    found = []
    for it in root.iter("Item"):
        if it.get("class") == "Sound":
            name = it.find("Properties/string[@name='Name']").text
            if name in wanted and name not in [f.find("Properties/string[@name='Name']").text for f in found]:
                found.append(_reref(copy.deepcopy(it)))
    assert len(found) == 3, "missing Jajanken sounds in " + nen_rbxmx
    return folder("Sounds", found)


def _reref(el):
    """Fresh referents for a copied subtree, with the references inside it (Motor6D parts, welds,
    PrimaryPart) moved over, so several copies of one rig can sit in the same file."""
    mapping = {}
    for it in el.iter("Item"):
        new = ref()
        mapping[it.get("referent")] = new
        it.set("referent", new)
    for prop_el in el.iter("Ref"):
        if prop_el.text in mapping:
            prop_el.text = mapping[prop_el.text]
    return el


# --------------------------------------------------------------------------- the package
def check_hit_delays(hits):
    """The server's HitDelay settings must land on the animations' Hit markers."""
    config = source("Config.luau")
    for mode in ("Rock", "Paper", "Scissors"):
        frame = round(hits["Jajanken " + mode] * FPS)
        assert "HitDelay = %d / 60," % frame in config, "Config.%s.HitDelay must be %d / 60 (the Hit marker)" % (mode, frame)


def jajanken_folder(nen_rbxmx, game):
    effects_folder, summary = effects.build_effects(nen_rbxmx)
    vfx = module("JajankenVFX", "JajankenVFX.luau", [effects_folder, sounds_folder(nen_rbxmx)])
    remote = item("RemoteEvent", "Remote")
    return folder("Jajanken", [module("Config", "Config.luau"), vfx, animations_folder(game), remote]), summary


# --------------------------------------------------------------------------- the test area
def moved(rig, target):
    """Move a rig so its HumanoidRootPart sits at `target` (4x4)."""
    hrp = next(c for c in rig.findall("Item") if c.find("Properties/string[@name='Name']").text == "HumanoidRootPart")
    el = hrp.find("Properties/CoordinateFrame[@name='CFrame']")
    v = {c.tag: float(c.text) for c in el}
    cur = np.eye(4)
    cur[:3, :3] = [[v["R00"], v["R01"], v["R02"]], [v["R10"], v["R11"], v["R12"]], [v["R20"], v["R21"], v["R22"]]]
    cur[:3, 3] = [v["X"], v["Y"], v["Z"]]
    t = target @ np.linalg.inv(cur)
    for it in rig.iter("Item"):
        for cf in it.findall("Properties/CoordinateFrame[@name='CFrame']"):
            if it.get("class") in ("Part", "MeshPart", "WedgePart"):
                v = {c.tag: float(c.text) for c in cf}
                m = np.eye(4)
                m[:3, :3] = [[v["R00"], v["R01"], v["R02"]], [v["R10"], v["R11"], v["R12"]], [v["R20"], v["R21"], v["R22"]]]
                m[:3, 3] = [v["X"], v["Y"], v["Z"]]
                new = cframe_props(t @ m)
                for c in cf:
                    c.text = new[c.tag]
    props = rig.find("Properties")
    for el in list(props):
        if el.get("name") in ("WorldPivotData", "ModelMeshCFrame"):
            props.remove(el)
    return rig


def at(x, y, z, yaw=0.0):
    m = np.eye(4)
    a = np.radians(yaw)
    m[:3, :3] = [[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]]
    m[:3, 3] = [x, y, z]
    return m


def dummy(rig_source, name, position, yaw):
    """A plain R6 dummy from the reference rig: no clothes or accessories, free to be knocked back."""
    rig, saves = reference_rig(rig_source, name)
    rig.remove(saves)
    for child in list(rig.findall("Item")):
        if child.get("class") in ("Accessory", "Shirt", "Pants", "ShirtGraphic"):
            rig.remove(child)
    for hum in rig.iter("Item"):
        if hum.get("class") == "Humanoid":
            for d in list(hum.findall("Item")):
                if d.get("class") == "HumanoidDescription":
                    hum.remove(d)
            p = hum.find("Properties")
            for key, val in (("MaxHealth", "200"), ("Health_XML", "200")):  # files store Health as Health_XML
                el = p.find("float[@name='%s']" % key)
                if el is None:
                    el = ET.SubElement(p, "float", {"name": key})
                el.text = val
    for it in rig.iter("Item"):
        anchored = it.find("Properties/bool[@name='Anchored']")
        if anchored is not None:
            anchored.text = "false"
    return _reref(moved(rig, at(position[0], 3, position[1], yaw)))


def jajanken_rig(rig_source, game, previews):
    """The animation rig (AnimSaves with the five animations and the full-cast previews). The ability
    place's village (../Village) stands it in its training yard."""
    rig, saves = reference_rig(rig_source, "Jajanken Animation Rig")
    for name in ANIMATIONS.values():
        saves.append(copy.deepcopy(game[name]))
    for p in previews:
        saves.append(copy.deepcopy(p))
    return _reref(rig)


def built(path):
    """The top instance of another package's build output (../<path>), or None if it isn't built."""
    full = os.path.join(ABILITIES, path)
    if not os.path.exists(full):
        print("  (not built, skipped: %s)" % path)
        return None
    return copy.deepcopy(ET.parse(full).getroot().find("Item"))


def other_script(cls, name, package, filename):
    return item(cls, name, Source=("ProtectedString", open(os.path.join(ABILITIES, package, "src", filename)).read()),
                Disabled=("bool", "false"))


# --------------------------------------------------------------------------- the labelled kit
README = """--[[
	JAJANKEN (Gon Freecss, Hunter x Hunter): where everything goes

	1. The "Jajanken" folder               -> ReplicatedStorage
	2. JajankenServer (Script)             -> ServerScriptService
	3. JajankenClient (LocalScript)        -> StarterPlayer > StarterPlayerScripts
	4. Optional (Workspace):
	     Jajanken Animation Rig  - open it in the Animation Editor to publish the five animations,
	                               then paste their ids into Jajanken.Config.Animations
	     Test Dummy              - something to hit

	5. Optional, for a parry-style fight: the Combat folder -> ReplicatedStorage, CombatServer ->
	   ServerScriptService, CombatClient -> StarterPlayerScripts. Every hit then goes through it: F
	   to block, tap F just before a hit to parry (the attacker staggers), guards that wear down and
	   break (a fully charged Rock breaks one outright), and a stun cuts a charge short.
	6. Optional: the Loadout folder + LoadoutServer + LoadoutClient, for the ability menu (M) and the
	   hotbar when the game has more than one kit (Gon's Jajanken, Killua's lightning...). The keys
	   are then the hotbar's slots.

	Play: hold Z (Rock), X (Paper) or C (Scissors), let go to cast. Tap for a quick cast, hold up to
	3 seconds for full power (it casts itself at full). Everything is tuned in Jajanken > Config.

	The game must use R6 avatars (Game Settings > Avatar > R6).
	Unpublished animations only play in Studio. Publish them before a live game.
]]
return nil
"""


def labelled_kit(jajanken, rig_source, game, previews):
    rig, saves = reference_rig(rig_source, "Jajanken Animation Rig")
    for name in ANIMATIONS.values():
        saves.append(copy.deepcopy(game[name]))
    for p in previews:
        saves.append(copy.deepcopy(p))
    kit = folder("Jajanken (Gon's Hatsu)", [
        item("ModuleScript", "READ ME", Source=("ProtectedString", README)),
        folder("1. Put the Jajanken folder in ReplicatedStorage", [copy.deepcopy(jajanken)]),
        folder("2. Put JajankenServer in ServerScriptService", [script("Script", "JajankenServer", "JajankenServer.server.luau")]),
        folder("3. Put JajankenClient in StarterPlayer - StarterPlayerScripts", [
            script("LocalScript", "JajankenClient", "JajankenClient.client.luau")]),
        folder("4. Optional - Workspace (animation rig to publish the animations, a test dummy)", [
            rig, dummy(rig_source, "Test Dummy", (0, -10), 180)]),
    ])
    combat, loadout = built(os.path.join("Combat", "build", "Combat.rbxmx")), built(
        os.path.join("Loadout", "build", "Loadout.rbxmx"))
    if combat is not None:
        kit.append(folder("5. Optional - the parry system (Combat): folder to ReplicatedStorage, scripts as named", [
            combat,
            other_script("Script", "CombatServer", "Combat", "CombatServer.server.luau"),
            other_script("LocalScript", "CombatClient", "Combat", "CombatClient.client.luau"),
        ]))
    if loadout is not None:
        kit.append(folder("6. Optional - the ability menu (Loadout): folder to ReplicatedStorage, scripts as named", [
            loadout,
            other_script("Script", "LoadoutServer", "Loadout", "LoadoutServer.server.luau"),
            other_script("LocalScript", "LoadoutClient", "Loadout", "LoadoutClient.client.luau"),
        ]))
    return _reref(kit)


# --------------------------------------------------------------------------- effects as data for the tests
def lua_effects(summary):
    def val(v):
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, (int, float)):
            return repr(float(v))
        return '"%s"' % v

    lines = ["-- generated by generate_jajanken.py: every effect's layers and their attributes", "return {"]
    for name, rows in summary.items():
        lines.append("\t%s = {" % name)
        for sub, layer, cls, attrs in rows:
            a = ", ".join("%s = %s" % (k, val(v)) for k, v in attrs.items())
            lines.append('\t\t{ sub = "%s", name = "%s", class = "%s", attrs = { %s } },' % (sub, layer, cls, a))
        lines.append("\t},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def write(items, path):
    root = ET.Element("roblox", {"version": "4"})
    for it in items:
        root.append(it)
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=False)
    print("wrote", os.path.relpath(path, HERE))


def build(rig_source, nen_rbxmx):
    os.makedirs(BUILD, exist_ok=True)
    game, previews, hits = baked_sequences()
    check_hit_delays(hits)
    jajanken, summary = jajanken_folder(nen_rbxmx, game)
    write([jajanken], os.path.join(BUILD, "Jajanken.rbxmx"))
    write([jajanken_rig(rig_source, game, previews)], os.path.join(BUILD, "JajankenRig.rbxmx"))
    write([labelled_kit(jajanken, rig_source, game, previews)], os.path.join(HERE, "Jajanken.rbxmx"))
    open(os.path.join(HERE, "tests", "effects_tree.luau"), "w").write(lua_effects(summary))
    for name, rows in summary.items():
        print("  %-15s %2d layers" % (name, len(rows)))
    print("hit markers:", {k: round(v, 4) for k, v in hits.items()})


def build_rig_only(rig_source, out):
    game, previews, hits = baked_sequences()
    rig, saves = reference_rig(rig_source, "Jajanken Animation Rig")
    for s in list(game.values()) + previews:
        saves.append(copy.deepcopy(s))
    write([rig], out)
    return hits


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--rig":
        print(build_rig_only(sys.argv[2], sys.argv[3]))
    else:
        build(sys.argv[1], sys.argv[2])
