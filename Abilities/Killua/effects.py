"""Killua's effects, built from the game's own emitters (nen.rbxmx: the BigBang / Crazy Slots sparks,
the Ken aura's energy layers and the combat VFX), the same way the Jajanken effects are: every
layer starts as a copy of a reference emitter, picked by texture, then is re-sized, re-timed,
re-aimed and re-coloured. The lightning itself (the bolts, the arcs over the body, Narukami) is drawn
by LightningBolt in KilluaVFX; these are everything around it: sparks thrown off, the glow, the
static on the body, and the physical side done the realistic way (air rings, dust, rocks, cracks,
scorch), with soft glows instead of flash frames.

The look: Killua's lightning is white at the core and pale electric blue round it (CORE / BOLT),
going deeper blue (DEEP) at the edges.

Placement (KilluaVFX.luau):
  Crackle        Attach to the HumanoidRootPart: static on the body (Whirlwind's stance, the dash chain)
  HandCharge     Attach to the Right Arm at the hand: lightning gathering for the palm (grows with charge)
  PalmBurst      Play at the palm on the hit, LookVector = the thrust
  ShockHit       Play at each victim, LookVector = the push
  StrikeMarker   Attach to a holder on the floor where Thunderbolt will land: the warning ring
  ThunderStrike  Play on the floor where the bolt lands (UpVector = up)
  DashBurst      Play where a dash leaves and where it arrives, LookVector = the dash
  Blink          Play where Whirlwind's counter reappears
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


# the Jajanken effect builder (and through it VFX/CombatVFX/generate_vfx.py's layer builder)
JE = _load("jajanken_effects", os.path.join(HERE, "..", "Jajanken", "effects.py"))
G = JE.G
Layer, Light, ref = G.Layer, JE.Light, G.ref
AIR, AIR_SOFT, DUST_FADE, STREAK = G.AIR, G.AIR_SOFT, G.DUST_FADE, G.STREAK
FRONT, BACK, TOP = G.FRONT, G.BACK, G.TOP
VEL_PERP, GREY, WHITE, WIND_LIGHT = G.VEL_PERP, G.GREY, G.WHITE, G.WIND_LIGHT
GROUND, GROUND_ONLY = JE.GROUND, JE.GROUND_ONLY

G.TEX.update(
    {
        # sparks: the BigBang ground impact's fast embers and shards, the BangImpact specs, the Crazy
        # Slots specs
        "spark_fast": ("14005903992", "GroundImpact/ember"),
        "spark_specs": ("11757797090", "BangImpact/specs"),
        "spark_dots": ("11868920572", "CondensedShotSlots"),
        "shards": ("17164994986", "Attachment/shards"),
        # a soft round glow (BigBang ground impact)
        "glow_soft": ("17844277603", "GroundImpact/glow"),
    }
)

CORE, BOLT, DEEP = "f2fbff", "9fdcff", "3aa0ff"
ELECTRIC = (CORE, BOLT)


def static(rate_scale=1.0):
    """Static crawling over the body: tiny sparks, upward lines and a faint energy haze."""
    return [
        Layer("spark_dots", "Sparks", continuous=True, rate=26 * rate_scale, life=(0.08, 0.2), size=0.45,
              dir=TOP, spread=(180, 180), speed=(6, 16), drag=4, color=ELECTRIC, le=1, br=3),
        Layer("aura_lines", "Static", continuous=True, rate=16 * rate_scale, life=(0.12, 0.18), size=3.2,
              color=BOLT, le=1, br=2),
        Layer("aura_burst", "Haze", continuous=True, rate=5 * rate_scale, life=(0.4, 0.7), size=4.2,
              color=(BOLT, DEEP), le=1, br=1.2),
    ]


def crackle():
    """Static on the body (Whirlwind's stance, the dash chain) and a cold light."""
    return {"name": "Crackle", "layers": {"": static() + [Light(BOLT, 10, attrs={"MaxBrightness": 1.1})]}}


def hand_charge():
    """Lightning gathering in the palm: sparks spitting off it, a white-blue glow and energy wrapped
    round the hand, all growing as the wind-up goes on."""
    hand = [
        Layer("spark_fast", "Sparks", continuous=True, rate=40, life=(0.05, 0.14), size=0.6, dir=TOP,
              spread=(180, 180), speed=(10, 26), drag=6, color=ELECTRIC, le=1, br=4,
              flags=JE.charged(RateGrow=0.6, Grow=0.5)),
        Layer("glow_soft", "Glow", continuous=True, size=2.4, color=BOLT, le=1, br=1.5,
              flags=JE.charged(Grow=1.0)),
        Layer("aura_esque", "Energy", continuous=True, size=1.8, color=(CORE, BOLT), le=1, br=2,
              flags=JE.charged(Grow=0.8, RateGrow=0.5)),
        Light(BOLT, 8, attrs={"MaxBrightness": 1.6}),
    ]
    return {"name": "HandCharge", "layers": {"": hand}}


def palm_burst():
    """The palm landing: the lightning discharges forward out of it (a burst of energy, sparks and
    shards thrown on through the target, a soft white-blue glow) and the air is punched out in front."""
    body = [
        Layer("glow_soft", "Glow", count=1, life=(0.14, 0.18), size=8, color=CORE, le=1, br=2,
              transp=[[0, 0.2, 0], [1, 1, 0]], lock=False),
        Layer("aura_disperse", "Discharge", count=1, life=(0.3, 0.35), size=8, color=(CORE, BOLT), le=1, br=2.5),
        Layer("spark_fast", "Sparks", count=26, life=(0.08, 0.25), size=0.9, dir=FRONT, spread=(40, 40),
              speed=(45, 110), drag=8, color=ELECTRIC, le=1, br=4, lock=False),
        Layer("shards", "Shards", count=10, life=(0.05, 0.14), size=2.5, dir=FRONT, spread=(25, 25),
              speed=(140, 260), drag=10, color=CORE, le=1, br=3, lock=False),
        Layer("air_shock", "PressureRing", count=1, life=(0.18, 0.26), size=9, dir=FRONT, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR),
        Layer("streak", "AirStreaks", count=8, life=(0.1, 0.22), size=2, dir=FRONT, spread=(25, 25),
              speed=(60, 100), drag=12, color=WIND_LIGHT, transp=STREAK, z=1),
        Light(BOLT, 16, 4, attrs={"FadeTime": 0.25}),
    ]
    return {"name": "PalmBurst", "layers": {"": body}}


def shock_hit():
    """On each victim: sparks bursting off them, a small discharge and a flicker of light."""
    hit = [
        Layer("spark_fast", "Sparks", count=16, life=(0.08, 0.22), size=0.7, dir=FRONT, spread=(180, 180),
              speed=(20, 55), drag=7, color=ELECTRIC, le=1, br=4, lock=False),
        Layer("aura_esque", "Discharge", count=1, life=(0.22, 0.3), size=4.5, color=(CORE, BOLT), le=1, br=2),
        Layer("glow_soft", "Glow", count=1, life=(0.1, 0.14), size=5, color=CORE, le=1, br=1.5,
              transp=[[0, 0.3, 0], [1, 1, 0]], lock=False),
        Layer("air_shock", "PressureRing", count=1, life=(0.16, 0.22), size=5, dir=FRONT, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR),
        Light(BOLT, 10, 2.5, attrs={"FadeTime": 0.2}),
    ]
    return {"name": "ShockHit", "layers": {"": hit}}


def strike_marker():
    """Where Thunderbolt will land, from the leap until the bolt: a pale ring on the floor the size of
    the strike, sparks skittering over it and a cold light growing."""
    ring = [
        Layer("air_ring", "Ring", continuous=True, rate=5, life=(0.35, 0.45), size=18, dir=TOP, ori=VEL_PERP,
              speed=(0.05, 0.05), color=BOLT, le=1, br=1.5, transp=[[0, 0.55, 0], [0.4, 0.45, 0], [1, 1, 0]]),
        Layer("spark_dots", "Sparks", continuous=True, rate=40, life=(0.1, 0.25), size=0.5, dir=TOP,
              spread=(80, 80), speed=(4, 14), drag=3, color=ELECTRIC, le=1, br=3),
        Layer("aura_lines", "Static", continuous=True, rate=10, life=(0.15, 0.2), size=4, color=BOLT, le=1, br=1.5),
        Light(BOLT, 20, attrs={"MaxBrightness": 2}),
    ]
    return {"name": "StrikeMarker", "layers": {"": ring}}


def thunder_strike():
    """The bolt landing: a white-blue burst and glow where it hits, sparks and shards thrown up and
    out, and on the floor a ring of air, a wall of dust, rocks, cracks and a scorch."""
    body = [
        Layer("glow_soft", "Glow", count=1, life=(0.2, 0.26), size=18, color=CORE, le=1, br=2.5,
              transp=[[0, 0.1, 0], [1, 1, 0]], lock=False),
        Layer("aura_disperse", "Discharge", count=1, life=(0.4, 0.5), size=18, color=(CORE, BOLT), le=1, br=3),
        Layer("aura_burst", "Energy", count=6, life=(0.3, 0.6), size=7, dir=TOP, spread=(60, 60), speed=(8, 20),
              drag=4, color=(BOLT, DEEP), le=1, br=2),
        Layer("spark_fast", "Sparks", count=40, life=(0.12, 0.35), size=1.1, dir=TOP, spread=(75, 75),
              speed=(40, 120), drag=6, accel=(0, -40, 0), color=ELECTRIC, le=1, br=4, lock=False),
        Layer("shards", "Shards", count=18, life=(0.06, 0.16), size=3.5, dir=TOP, spread=(70, 70),
              speed=(160, 300), drag=10, color=CORE, le=1, br=3, lock=False),
        Light(BOLT, 32, 6, attrs={"FadeTime": 0.45}),
    ]
    ground = [
        Layer("air_ring", "AirRing", count=1, life=(0.25, 0.4), size=24, dir=TOP, ori=VEL_PERP, speed=(6, 6),
              drag=10, le=0.4, br=1, color=WIND_LIGHT, transp=AIR_SOFT, flags=GROUND_ONLY),
        Layer("air_shock", "PressureRing", count=2, life=(0.2, 0.3), size=18, dir=TOP, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR, flags=GROUND_ONLY),
        Layer("smoke_burst", "DustWall", count=10, life=(0.4, 0.9), size=6, dir=FRONT, spread=(0, 360),
              speed=(70, 100), drag=10, accel=(0, -4, 0), color=GREY, flags=GROUND),
        Layer("dust", "Dust", count=10, life=(0.5, 1.1), size=3.4, dir=FRONT, spread=(8, 360), speed=(18, 40),
              drag=7.4, accel=(0, 1.6, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("rock", "Rocks", count=14, life=(0.4, 1.1), size=0.35, dir=TOP, spread=(45, 45), speed=(25, 60),
              drag=5, accel=(0, -68, 0), flags=GROUND),
        Layer("crack", "Cracks", count=1, life=(1.6, 1.6), size=12, dir=TOP, ori=VEL_PERP, flags=GROUND_ONLY),
        Layer("scorch", "Scorch", count=1, life=(1.8, 1.8), size=9, dir=TOP, ori=VEL_PERP, br=1, le=0,
              flags=GROUND_ONLY),
    ]
    return {"name": "ThunderStrike", "layers": {"": body, "Ground": ground}}


def dash_burst():
    """Where a dash leaves or arrives: sparks spat back along the dash, a crack of glow, a short
    streak of air and a puff of dust off the floor."""
    body = [
        Layer("spark_fast", "Sparks", count=18, life=(0.08, 0.22), size=0.8, dir=BACK, spread=(55, 55),
              speed=(25, 70), drag=7, color=ELECTRIC, le=1, br=4, lock=False),
        Layer("glow_soft", "Glow", count=1, life=(0.1, 0.14), size=6, color=CORE, le=1, br=1.5,
              transp=[[0, 0.3, 0], [1, 1, 0]], lock=False),
        Layer("aura_esque", "Energy", count=1, life=(0.2, 0.26), size=4.5, color=(CORE, BOLT), le=1, br=2),
        Layer("streak", "AirStreaks", count=6, life=(0.08, 0.18), size=2, dir=BACK, spread=(15, 15),
              speed=(50, 90), drag=12, color=WIND_LIGHT, transp=STREAK, z=1),
        Light(BOLT, 12, 3, attrs={"FadeTime": 0.2}),
    ]
    ground = [
        Layer("dust", "Dust", count=5, life=(0.4, 0.8), size=2.6, dir=FRONT, spread=(10, 120), speed=(10, 24),
              drag=7, accel=(0, 1.2, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
    ]
    return {"name": "DashBurst", "layers": {"": body, "Ground": ground}}


def blink():
    """Whirlwind's counter reappearing: a burst of sparks all round, a glow and a ring of static."""
    body = [
        Layer("spark_fast", "Sparks", count=22, life=(0.08, 0.24), size=0.8, dir=FRONT, spread=(180, 180),
              speed=(25, 60), drag=7, color=ELECTRIC, le=1, br=4, lock=False),
        Layer("glow_soft", "Glow", count=1, life=(0.12, 0.16), size=7, color=CORE, le=1, br=1.5,
              transp=[[0, 0.25, 0], [1, 1, 0]], lock=False),
        Layer("aura_disperse", "Discharge", count=1, life=(0.3, 0.35), size=7, color=(CORE, BOLT), le=1, br=2),
        Layer("aura_lines", "Static", count=6, life=(0.12, 0.18), size=4, color=BOLT, le=1, br=2),
        Light(BOLT, 14, 3, attrs={"FadeTime": 0.25}),
    ]
    return {"name": "Blink", "layers": {"": body}}


EFFECTS = [crackle, hand_charge, palm_burst, shock_hit, strike_marker, thunder_strike, dash_burst, blink]


def build_effects(nen_rbxmx):
    """Folder "Effects" with every effect, and a summary {name: [(sub, layer name, class, attributes)]}."""
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
                    attrs = {"Continuous": True} if layer.kw.get("continuous") else {
                        "EmitCount": float(layer.kw.get("count", 1))}
                    attrs.update(layer.kw.get("flags", {}))
                    rows.append((sub, layer.name, "ParticleEmitter", attrs))
                else:
                    rows.append((sub, "Glow", "PointLight", layer.attrs))
        summary[spec["name"]] = rows
    return folder, summary
