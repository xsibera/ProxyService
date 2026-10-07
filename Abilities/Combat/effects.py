"""The combat effects (parry, block, guard break), built from the game's own emitters like the ability
effects: sparks and shards struck off the contact, a soft glow, and the air punched out, in the
realistic style (no star bursts, flash frames or black frames).

  ParrySpark   Play between the two fighters, LookVector = toward the attacker
  BlockSpark   Play at the blocker
  GuardBreak   Play at the blocker whose guard broke
"""

import importlib.util
import os
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


JE = _load("jajanken_effects_for_combat", os.path.join(HERE, "..", "Jajanken", "effects.py"))
G = JE.G
Layer, Light, ref = G.Layer, JE.Light, G.ref
G.TEX.update(
    {
        "spark_fast": ("14005903992", "GroundImpact/ember"),
        "shards": ("17164994986", "Attachment/shards"),
        "glow_soft": ("17844277603", "GroundImpact/glow"),
    }
)

STEEL, WARM = ("ffffff", "ffe6b0"), "ffd27a"


def parry_spark():
    """A clean deflection: a hot spray of sparks and shards off the contact, a soft bright glow and
    a sharp ring of air."""
    body = [
        Layer("spark_fast", "Sparks", count=30, life=(0.1, 0.3), size=0.8, dir=G.FRONT, spread=(70, 70),
              speed=(40, 110), drag=6, accel=(0, -50, 0), color=STEEL, le=1, br=4, lock=False),
        Layer("shards", "Shards", count=12, life=(0.05, 0.12), size=2.6, dir=G.FRONT, spread=(60, 60),
              speed=(150, 260), drag=10, color="ffffff", le=1, br=3, lock=False),
        Layer("glow_soft", "Glow", count=1, life=(0.12, 0.16), size=7, color=WARM, le=1, br=2,
              transp=[[0, 0.15, 0], [1, 1, 0]], lock=False),
        Layer("air_shock", "Ring", count=1, life=(0.16, 0.22), size=7, dir=G.FRONT, ori=G.VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=G.WHITE, transp=G.AIR),
        Light(WARM, 14, 4, attrs={"FadeTime": 0.25}),
    ]
    return {"name": "ParrySpark", "layers": {"": body}}


def block_spark():
    """A hit taken on the guard: a few sparks, a dull puff of air and a little dust."""
    body = [
        Layer("spark_fast", "Sparks", count=8, life=(0.08, 0.2), size=0.6, dir=G.FRONT, spread=(60, 60),
              speed=(20, 50), drag=6, accel=(0, -40, 0), color=STEEL, le=1, br=3, lock=False),
        Layer("wind_burst", "AirPuff", spread=(0, 0), count=1, life=(0.25, 0.35), size=5, dir=G.FRONT,
              ori=G.VEL_PERP, speed=(0.1, 0.1), color=G.WHITE, transp=G.AIR),
        Layer("dust", "Dust", count=3, life=(0.35, 0.6), size=2, dir=G.FRONT, spread=(50, 50), speed=(5, 12),
              drag=7, accel=(0, 1.5, 0), color=G.LIGHT, transp=G.DUST_FADE),
    ]
    return {"name": "BlockSpark", "layers": {"": body}}


def guard_break():
    """The guard giving way: a burst of sparks and shards all round, a heavy ring of air and dust
    kicked off the floor."""
    body = [
        Layer("spark_fast", "Sparks", count=34, life=(0.1, 0.35), size=0.9, dir=G.FRONT, spread=(180, 180),
              speed=(30, 90), drag=6, accel=(0, -50, 0), color=STEEL, le=1, br=4, lock=False),
        Layer("shards", "Shards", count=14, life=(0.06, 0.14), size=3, dir=G.FRONT, spread=(180, 180),
              speed=(140, 240), drag=10, color="ffffff", le=1, br=3, lock=False),
        Layer("air_shock", "Ring", count=2, life=(0.2, 0.3), size=11, dir=G.FRONT, ori=G.VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=G.WHITE, transp=G.AIR),
        Layer("wind_burst", "AirBurst", spread=(0, 0), count=2, life=(0.3, 0.45), size=10, dir=G.FRONT,
              ori=G.VEL_PERP, speed=(0.1, 0.1), color=G.WHITE, transp=G.AIR),
        Light(WARM, 16, 3, attrs={"FadeTime": 0.3}),
    ]
    ground = [
        Layer("dust", "Dust", count=8, life=(0.5, 1.0), size=2.8, dir=G.FRONT, spread=(5, 360), speed=(14, 30),
              drag=7, accel=(0, 1.2, 0), color=G.GREY, transp=G.DUST_FADE, flags=JE.GROUND),
    ]
    return {"name": "GuardBreak", "layers": {"": body, "Ground": ground}}


EFFECTS = [parry_spark, block_spark, guard_break]


def build_effects(nen_rbxmx):
    lib = G.Library(nen_rbxmx)
    folder = ET.Element("Item", {"class": "Folder", "referent": ref()})
    ET.SubElement(ET.SubElement(folder, "Properties"), "string", {"name": "Name"}).text = "Effects"
    summary = {}
    for make in EFFECTS:
        spec = make()
        folder.append(JE.build_effect(lib, spec))
        rows = []
        for sub, layers in spec["layers"].items():
            for layer in layers:
                if isinstance(layer, Layer):
                    attrs = {"EmitCount": float(layer.kw.get("count", 1))}
                    attrs.update(layer.kw.get("flags", {}))
                    rows.append((sub, layer.name, "ParticleEmitter", attrs))
                else:
                    rows.append((sub, "Glow", "PointLight", layer.attrs))
        summary[spec["name"]] = rows
    return folder, summary
