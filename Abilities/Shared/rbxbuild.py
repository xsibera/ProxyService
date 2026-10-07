"""Small helpers for writing Roblox XML (.rbxmx) by hand: instances, scripts from source files,
animations from baked clips, sounds copied out of a reference file. Shared by the ability kits'
generators (Killua, Combat, Loadout; Jajanken has its own copy of the same ideas)."""

import copy
import importlib.util
import os
import sys
import xml.etree.ElementTree as ET

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "Animations"))
from animkit import clip_transforms, ref, sequence_xml  # noqa: E402


def load(name, path):
    """A Python file loaded as a module under its own name (each kit has an anims.py / effects.py)."""
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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


def folder(name, children=()):
    return item("Folder", name, children)


def module(name, path, children=()):
    return item("ModuleScript", name, children, Source=("ProtectedString", open(path).read()))


def script(cls, name, path):
    return item(cls, name, Source=("ProtectedString", open(path).read()), Disabled=("bool", "false"))


def source_module(name, text, children=()):
    return item("ModuleScript", name, children, Source=("ProtectedString", text))


def reref(el):
    """Fresh referents for a copied subtree, with the Ref properties inside it moved over."""
    mapping = {}
    for it in el.iter("Item"):
        new = ref()
        mapping[it.get("referent")] = new
        it.set("referent", new)
    for prop_el in el.iter("Ref"):
        if prop_el.text in mapping:
            prop_el.text = mapping[prop_el.text]
    return el


def sequences(baked_clips):
    """{clip name: KeyframeSequence} for [(clip, baked)], legs at Weight 0 where the clip doesn't key
    them."""
    out = {}
    for c, baked in baked_clips:
        frames = clip_transforms(c, baked)
        free = tuple(j for j in ("RLeg", "LLeg") if j not in c.joints)
        out[c.name] = sequence_xml(c.name, frames, c.markers, loop=c.loop, zero_weight=free)
    return out


def animations_folder(names, game):
    """Folder "Animations": an Animation per short name, holding the KeyframeSequence it plays."""
    out = []
    for short, clip_name in names.items():
        anim = item("Animation", short, [copy.deepcopy(game[clip_name])])
        ET.SubElement(anim.find("Properties"), "Content", {"name": "AnimationId"}).append(ET.Element("null"))
        out.append(anim)
    return folder("Animations", out)


def sounds_folder(reference_rbxmx, wanted):
    """Folder "Sounds" from sounds in a reference file: wanted = {new name: (source name, speed, volume)}."""
    root = ET.parse(reference_rbxmx).getroot()
    by_name = {}
    for it in root.iter("Item"):
        if it.get("class") == "Sound":
            name = it.find("Properties/string[@name='Name']").text
            by_name.setdefault(name, it)
    out = []
    for new, (source_name, speed, volume) in wanted.items():
        assert source_name in by_name, "no sound %s in %s" % (source_name, reference_rbxmx)
        sound = reref(copy.deepcopy(by_name[source_name]))
        props = sound.find("Properties")
        props.find("string[@name='Name']").text = new
        for key, value in (("PlaybackSpeed", speed), ("Volume", volume)):
            el = props.find("float[@name='%s']" % key)
            if el is None:
                el = ET.SubElement(props, "float", {"name": key})
            el.text = repr(float(value))
        out.append(sound)
    return folder("Sounds", out)


def combat_vfx():
    """The combat effects pack (VFX/CombatVFX): the CombatVFX module with its Effects, as its generator
    built it, carrying the current CombatVFX.luau. It goes in ReplicatedStorage."""
    vfx = os.path.join(HERE, "..", "..", "VFX", "CombatVFX")
    module = copy.deepcopy(ET.parse(os.path.join(vfx, "CombatVFX.rbxmx")).getroot().find("Item"))
    source = module.find("Properties/ProtectedString[@name='Source']")
    source.text = open(os.path.join(vfx, "CombatVFX.luau")).read()
    return reref(module)


def reference_animation(rig_source, rig_name, animation_name, new_name):
    """A KeyframeSequence from the reference file (one rig's AnimSaves), copied and renamed."""
    root = ET.parse(rig_source).getroot()
    for rig in root.findall("Item"):
        name = rig.find("Properties/string[@name='Name']")
        if name is None or name.text != rig_name:
            continue
        for kfs in rig.iter("Item"):
            n = kfs.find("Properties/string[@name='Name']")
            if kfs.get("class") == "KeyframeSequence" and n is not None and n.text == animation_name:
                out = copy.deepcopy(kfs)
                out.find("Properties/string[@name='Name']").text = new_name
                for props in out.iter("Properties"):
                    for el in list(props):
                        if el.tag == "SharedString":
                            props.remove(el)
                return reref(out)
    raise AssertionError("no %s > %s in %s" % (rig_name, animation_name, rig_source))


def write(items, path):
    root = ET.Element("roblox", {"version": "4"})
    for it in items:
        root.append(it)
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=False)
    print("wrote", path)


def lua_effects(summary, generator):
    """The effect tree as Lua data, for the headless tests."""

    def val(v):
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, (int, float)):
            return repr(float(v))
        return '"%s"' % v

    lines = ["-- generated by %s: every effect's layers and their attributes" % generator, "return {"]
    for name, rows in summary.items():
        lines.append("\t%s = {" % name)
        for sub, layer, cls, attrs in rows:
            a = ", ".join("%s = %s" % (k, val(v)) for k, v in attrs.items())
            lines.append('\t\t{ sub = "%s", name = "%s", class = "%s", attrs = { %s } },' % (sub, layer, cls, a))
        lines.append("\t},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def cframe_props(m):
    out = {k: repr(float(v)) for k, v in zip("XYZ", m[:3, 3], strict=True)}
    for i in range(3):
        for j in range(3):
            out["R%d%d" % (i, j)] = repr(float(m[i, j]))
    return out


_ = np
