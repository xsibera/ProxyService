"""Leorio's effects, built from the game's own emitters (nen.rbxmx: the Ken and Ren auras, the
Disrupt and BigBang impacts and the combat VFX) the same way the Jajanken and Killua effects are:
every layer starts as a copy of a reference emitter, picked by texture, then is re-sized, re-timed,
re-aimed and re-coloured.

The look: Leorio's aura is the game's own nen teal (the Ken aura's 85ffe7), white at the core, going
deep sea-green at the edges. A warp hole is a dark, still hole (Disrupt's black shockwave, which
darkens what's behind it) with the Ken aura's energy swirl turning round it and its water-surface
ripple over it - the rim and the hole's body are parts LeorioVFX builds round these. The punches
themselves are done the realistic way, like the rest of the game's hits: air blasted out (wind
bursts, pressure rings, streaks), smoke, dust, rocks and cracks.

Placement (LeorioVFX.luau):
  FistCharge   Attach to the striking arm at the fist: the aura gathering in it (grows with charge)
  Aura         Attach to the HumanoidRootPart while he pounds (the barrage, the burst)
  Portal       Attach to the warp hole's holder, LookVector = the way the fist comes out: the swirl
               and ripple across the hole (grows as it opens)
  PortalBurst  Play at the hole as the fist comes through, LookVector = the punch
  Trace        the faint aura trail running along the floor to the target (a projectile)
  GroundPunch  Play at the fist where it goes into the floor (UpVector = up)
  WarpHit      Play at each victim of a warp punch, LookVector = the push
  WarpHeavy    the same for the big ones (Warp Punch, the barrage's last, the burst)
  BurstRing    Play on the floor round him for Portal Burst
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
VEL_PERP, GREY, DARK, WHITE, WIND_LIGHT = G.VEL_PERP, G.GREY, G.DARK, G.WHITE, G.WIND_LIGHT
GROUND, GROUND_ONLY = JE.GROUND, JE.GROUND_ONLY

G.TEX.update(
    {
        # the warp hole: Disrupt's black shockwave (LightEmission -1: it darkens), the Ken aura's
        # water-surface ripple and wisps, and the expanding energy ring
        "void": ("96004355425020", "Disrupt/Extra/shockwaveblack"),
        "ripple": ("126178873329014", "Water Surface Ripple"),
        "wisp": ("117668562426090", "Wispy Water 2"),
        "expand": ("13378750401", "Expanding Energy"),
        "energy_up": ("120154460257489", "Detailed Energy Upward"),
        "spark_dots": ("11868920572", "CondensedShotSlots"),
        "glow_soft": ("17844277603", "GroundImpact/glow"),
    }
)

CORE, AURA, DEEP = "e6fff9", "85ffe7", "1fb79a"
NEN = (CORE, AURA)


def fist_charge():
    """The aura gathering in the fist as he winds up: wisps of it pulled in round the hand, a soft
    teal glow and specks of it spitting off, all swelling with the charge."""
    fist = [
        Layer("aura_esque", "Energy", continuous=True, size=2.2, color=NEN, le=1, br=2,
              flags=JE.charged(Grow=0.8, RateGrow=0.5)),
        Layer("wisp", "Wisps", continuous=True, rate=6, life=(0.4, 0.6), size=2.6, color=AURA, le=1, br=1.5,
              flags=JE.charged(Grow=0.6, RateGrow=0.6)),
        Layer("glow_soft", "Glow", continuous=True, size=2.6, color=AURA, le=1, br=1.2, flags=JE.charged(Grow=1.0)),
        Layer("spark_dots", "Specks", continuous=True, rate=24, life=(0.12, 0.3), size=0.35, dir=TOP,
              spread=(180, 180), speed=(5, 12), drag=4, color=NEN, le=1, br=3, flags=JE.charged(RateGrow=0.7)),
        Light(AURA, 8, attrs={"MaxBrightness": 1.4}),
    ]
    return {"name": "FistCharge", "layers": {"": fist}}


def aura():
    """His aura while he pounds away: teal nen rising off the body, power lines, and dust stirred
    up round his feet."""
    body = [
        Layer("energy_up", "Rising", continuous=True, rate=6, life=(0.6, 0.9), size=5, color=NEN, le=1, br=1.5),
        Layer("aura_burst", "Flame", continuous=True, rate=12, life=(0.5, 0.9), size=3.2, speed=(2, 4),
              color=(CORE, AURA), le=1, br=2),
        Layer("aura_lines", "PowerLines", continuous=True, rate=26, life=(0.3, 0.3), size=4.5, speed=(12, 12),
              color=CORE, le=1, br=1.2),
        Light(AURA, 12, attrs={"MaxBrightness": 1.2}),
    ]
    feet = [
        Layer("dust", "Dust", continuous=True, rate=10, life=(0.6, 1.1), size=2.6, dir=FRONT, spread=(0, 360),
              speed=(6, 14), drag=4, accel=(0, 1, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
    ]
    return {"name": "Aura", "layers": {"": body, "Feet": feet}, "subs": {"Feet": (0, -2.9, 0)}}


def portal():
    """Across the warp hole, in its plane: the dark of the hole itself, the aura's energy swirl
    turning round it, its water-surface ripple spreading over it, wisps curling off the rim and
    specks of aura drawn in; a teal light. It all grows as the hole opens (Charge 0..1)."""
    hole = [
        Layer("void", "Void", continuous=True, rate=14, life=(0.35, 0.45), size=5.2, dir=FRONT, ori=VEL_PERP,
              speed=(0.02, 0.02), rotspeed=(-40, 40), le=-1, transp=[[0, 0.15, 0], [0.6, 0.3, 0], [1, 1, 0]],
              lock=True, flags=JE.charged(Grow=1.0)),
        Layer("aura_swirl", "Swirl", continuous=True, rate=6, life=(0.6, 0.8), size=6.4, dir=FRONT, ori=VEL_PERP,
              speed=(0.03, 0.03), rotspeed=(160, 220), color=NEN, le=1, br=2.2, lock=True,
              flags=JE.charged(Grow=1.0, RateGrow=0.5)),
        Layer("ripple", "Ripple", continuous=True, rate=4, life=(0.7, 0.9), size=5.6, dir=FRONT, ori=VEL_PERP,
              speed=(0.04, 0.04), color=CORE, le=1, br=1.5, lock=True, flags=JE.charged(Grow=1.0)),
        Layer("wisp", "Wisps", continuous=True, rate=8, life=(0.4, 0.7), size=2.4, dir=FRONT, spread=(70, 70),
              speed=(1, 3), drag=2, color=AURA, le=1, br=1.5, flags=JE.charged(Grow=0.8, RateGrow=0.6)),
        Layer("spark_dots", "Specks", continuous=True, rate=30, life=(0.15, 0.35), size=0.4, dir=BACK,
              spread=(80, 80), speed=(4, 10), drag=3, color=NEN, le=1, br=3, flags=JE.charged(RateGrow=0.8)),
        Light(AURA, 14, attrs={"MaxBrightness": 2.2}),
    ]
    return {"name": "Portal", "layers": {"": hole}}


def portal_burst():
    """The fist coming through: a ring of aura expanding off the hole, a burst of energy and specks
    thrown on with the punch, and the air punched out of it - a pressure ring and streaks."""
    body = [
        Layer("expand", "Ring", count=1, life=(0.25, 0.32), size=8, dir=FRONT, ori=VEL_PERP, speed=(0.05, 0.05),
              color=NEN, le=1, br=2.5),
        Layer("aura_disperse", "Burst", count=1, life=(0.3, 0.38), size=6.5, color=(CORE, AURA), le=1, br=2.2),
        Layer("spark_dots", "Specks", count=20, life=(0.15, 0.35), size=0.6, dir=FRONT, spread=(35, 35),
              speed=(25, 60), drag=6, color=NEN, le=1, br=3, lock=False),
        Layer("air_shock", "PressureRing", count=1, life=(0.18, 0.24), size=7, dir=FRONT, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR),
        Layer("streak", "AirStreaks", count=8, life=(0.1, 0.2), size=2, dir=FRONT, spread=(18, 18),
              speed=(60, 100), drag=12, color=WIND_LIGHT, transp=STREAK, z=1),
        Light(AURA, 14, 3, attrs={"FadeTime": 0.25}),
    ]
    return {"name": "PortalBurst", "layers": {"": body}}


def trace():
    """The faint trace of aura that runs along the floor from where he punched to the target (the
    fist travelling through the warp): low teal wisps and specks, and a breath of dust."""
    line = [
        Layer("wisp", "Wisps", continuous=True, rate=40, life=(0.25, 0.45), size=1.8, dir=TOP, spread=(30, 30),
              speed=(1, 3), drag=2, color=AURA, le=1, br=1.5),
        Layer("spark_dots", "Specks", continuous=True, rate=60, life=(0.15, 0.3), size=0.35, dir=TOP,
              spread=(60, 60), speed=(3, 8), drag=3, color=NEN, le=1, br=3),
        Layer("dust", "Dust", continuous=True, rate=16, life=(0.4, 0.7), size=1.6, dir=TOP, spread=(70, 70),
              speed=(2, 5), drag=4, accel=(0, 1, 0), color=GREY, transp=DUST_FADE),
        Light(AURA, 8, attrs={"MaxBrightness": 1.2}),
    ]
    return {"name": "Trace", "layers": {"": line}}


def ground_punch():
    """His fist going into the floor (into the hole under it): the aura rippling out flat across
    the floor from it, a ring of air and dust pushed out, grit kicked up and a few cracks."""
    flat = [
        Layer("ripple", "Ripple", count=1, life=(0.4, 0.5), size=7, dir=TOP, ori=VEL_PERP, speed=(0.05, 0.05),
              color=CORE, le=1, br=1.8),
        Layer("expand", "Ring", count=1, life=(0.3, 0.38), size=8, dir=TOP, ori=VEL_PERP, speed=(0.05, 0.05),
              color=NEN, le=1, br=2),
        Layer("aura_disperse", "Flare", count=1, life=(0.28, 0.35), size=5, color=(CORE, AURA), le=1, br=2),
        Light(AURA, 14, 3, attrs={"FadeTime": 0.3}),
    ]
    ground = [
        Layer("air_shock", "PressureRing", count=1, life=(0.2, 0.28), size=10, dir=TOP, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR, flags=GROUND_ONLY),
        Layer("wind_spin2", "GroundWind", count=1, life=(0.2, 0.45), size=10, dir=TOP, ori=VEL_PERP, speed=(4, 4),
              drag=6, rotspeed=(108, 266), flags=GROUND_ONLY),
        Layer("dust", "Dust", count=8, life=(0.5, 1.0), size=2.8, dir=FRONT, spread=(5, 360), speed=(14, 30),
              drag=7, accel=(0, 1.2, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("rock", "Grit", count=8, life=(0.4, 0.9), size=0.25, dir=TOP, spread=(45, 45), speed=(14, 34),
              drag=5, accel=(0, -68, 0), flags=GROUND),
        Layer("crack", "Cracks", count=1, life=(1.4, 1.4), size=6, dir=TOP, ori=VEL_PERP, flags=GROUND_ONLY),
    ]
    return {"name": "GroundPunch", "layers": {"": flat, "Ground": ground}}


def _impact(big):
    k = 1.5 if big else 1.0
    body = [
        Layer("aura_burst", "NenBurst", count=int(8 * k), life=(0.25, 0.45), speed=(14, 28), drag=6, dir=FRONT,
              spread=(40, 40), size=2.4 * k, color=NEN, le=1, br=2, lock=False),
        Layer("glow_soft", "Glow", count=1, life=(0.1, 0.14), size=5 * k, color=CORE, le=1, br=1.4,
              transp=[[0, 0.35, 0], [1, 1, 0]], lock=False),
        Layer("wind_burst", "AirBurst", spread=(0, 0), count=2 if big else 1, life=(0.3, 0.45), size=7 * k,
              dir=FRONT, ori=VEL_PERP, speed=(0.1, 0.1), color=WHITE, transp=AIR),
        Layer("air_shock", "PressureRing", count=2 if big else 1, life=(0.18, 0.26), size=6.5 * k, dir=FRONT,
              ori=VEL_PERP, speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR),
        Layer("streak", "AirStreaks", count=int(6 * k), life=(0.1, 0.22), size=1.8 * k, dir=FRONT,
              spread=(28, 28), speed=(50, 90), drag=12, color=WIND_LIGHT, transp=STREAK, z=1),
        Layer("dust", "Dust", count=3, life=(0.35, 0.6), size=2.2 * k, dir=FRONT, spread=(50, 50), speed=(5, 14),
              drag=7, accel=(0, 1.5, 0), color=G.LIGHT, transp=DUST_FADE),
        Light(AURA, 12 * k, 2.5, attrs={"FadeTime": 0.22}),
    ]
    if big:
        body += [
            Layer("wind_big", "WindSpin", count=1, life=(0.15, 0.4), size=13, dir=FRONT, ori=VEL_PERP, speed=(3, 3),
                  rotspeed=(500, 1500), drag=6, transp=AIR),
            Layer("smoke_burst", "SmokeCone", count=5, life=(0.4, 0.85), size=5.5, dir=FRONT, spread=(40, 40),
                  speed=(60, 95), drag=10, accel=(0, 2, 0), color=GREY),
            Layer("smoke_linger", "Haze", count=3, life=(0.8, 1.4), size=5.5, dir=FRONT, spread=(55, 55),
                  speed=(4, 20), drag=3, color=DARK, delay=0.04),
        ]
    return body


def warp_hit():
    """On each victim of a warp punch: the aura bursting through them, a puff of air, a pressure
    ring, streaks and a little dust."""
    return {"name": "WarpHit", "layers": {"": _impact(False)}}


def warp_heavy():
    """The big ones (Warp Punch, the barrage's last, the burst): twice the air - wind bursts, a
    spinning gust, pressure rings, streaks - and a cone of smoke blown out the far side."""
    return {"name": "WarpHeavy", "layers": {"": _impact(True)}}


def burst_ring():
    """Portal Burst, on the floor all round him: the aura rippling out, a ring of air and a wall of
    dust blown outward, rocks thrown up and cracks."""
    flat = [
        Layer("expand", "Ring", count=1, life=(0.35, 0.45), size=22, dir=TOP, ori=VEL_PERP, speed=(0.05, 0.05),
              color=NEN, le=1, br=2),
        Layer("ripple", "Ripple", count=2, life=(0.45, 0.6), size=18, dir=TOP, ori=VEL_PERP, speed=(0.05, 0.05),
              color=CORE, le=1, br=1.5),
        Light(AURA, 24, 4, attrs={"FadeTime": 0.4}),
    ]
    ground = [
        Layer("air_ring", "AirRing", count=1, life=(0.25, 0.4), size=24, dir=TOP, ori=VEL_PERP, speed=(6, 6),
              drag=10, le=0.4, br=1, color=WIND_LIGHT, transp=AIR_SOFT, flags=GROUND_ONLY),
        Layer("air_shock", "PressureRing", count=2, life=(0.2, 0.3), size=18, dir=TOP, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR, flags=GROUND_ONLY),
        Layer("smoke_burst", "DustWall", count=12, life=(0.4, 0.9), size=6, dir=FRONT, spread=(0, 360),
              speed=(70, 100), drag=10, accel=(0, -4, 0), color=GREY, flags=GROUND),
        Layer("dust", "Dust", count=10, life=(0.5, 1.1), size=3.4, dir=FRONT, spread=(8, 360), speed=(18, 40),
              drag=7.4, accel=(0, 1.6, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("rock", "Rocks", count=16, life=(0.4, 1.1), size=0.35, dir=TOP, spread=(50, 50), speed=(25, 60),
              drag=5, accel=(0, -68, 0), flags=GROUND),
        Layer("crack", "Cracks", count=1, life=(1.6, 1.6), size=14, dir=TOP, ori=VEL_PERP, flags=GROUND_ONLY),
    ]
    return {"name": "BurstRing", "layers": {"": flat, "Ground": ground}}


EFFECTS = [fist_charge, aura, portal, portal_burst, trace, ground_punch, warp_hit, warp_heavy, burst_ring]


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
