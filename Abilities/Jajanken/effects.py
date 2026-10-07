"""The Jajanken effects, built from the game's own emitters (nen.rbxmx: the Jajanken folder, the nen
auras and the combat VFX), the same way VFX/CombatVFX/generate_vfx.py builds its pack: every layer
starts as a copy of a reference emitter, picked by texture, and is then re-sized, re-timed, re-aimed
and re-coloured.

The look: Gon's aura is gold-orange nen (the game's Jajanken orange, ff7701 / ff5100) rising off the
body and gathering in the hand. The hits are the nen going off: fire-like energy plus the physical
side done the realistic way (wind, pressure rings, smoke, dust, rocks and cracks), with no star
bursts, flash frames or black frames.

Placement (JajankenVFX.luau):
  Aura            Attach to the HumanoidRootPart while charging ("Feet" sits on the floor)
  HandCharge      Attach to the Right Arm at the fist while charging (the same for all three modes)
  Release         Play at the caster's HumanoidRootPart on release
  RockBlast       Play at the fist, LookVector = the punch
  PaperBall       the projectile (continuous), LookVector = its travel
  PaperBlast      Play where the ball bursts
  ScissorsSlash   Play in front of the chest, UpVector = up (the cut lies flat across the front)
  NenHit          Play at each victim, LookVector = the push
"""

import os
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "VFX", "CombatVFX"))
import generate_vfx as G  # noqa: E402
from generate_vfx import (  # noqa: E402
    AIR,
    AIR_SOFT,
    BACK,
    BOTTOM,
    CAM,
    DARK,
    DUST_FADE,
    FRONT,
    GREY,
    LIGHT,
    STREAK,
    TOP,
    VEL_PAR,
    VEL_PERP,
    WHITE,
    WIND_GREY,
    WIND_LIGHT,
    Layer,
    encode_attributes,
    ref,
)

G.TEX.update(
    {
        # Jajanken: the game's fist fire and glow (RockRA / PaperProjectile)
        "nen_fire": ("5898511947", "Rock/RockRA/1"),
        "nen_fire2": ("5898549549", "Rock/RockRA/2"),
        "nen_glow": ("9589798202", "Rock/RockRA/1"),
        # the nen auras (Ken / Ren)
        "aura_smoke": ("17510992903", "Ken/Cursed"),
        "aura_swirl": ("91555031263035", "Ken/Energy Swirl"),
        "aura_burst": ("16509892607", "Ken/Attachment/Small"),
        "aura_esque": ("14200879082", "Ken/Attachment/Energy Esque"),
        "aura_disperse": ("70968840196067", "Ken/Bright"),
        "aura_lines": ("434294468", "RenAura/LinesFX"),
        "aura_awaken": ("17612127081", "RenAura/AwakeningL"),
        # Jajanken scissors slash
        "sc_slash4": ("16709589914", "ScissorsSlash/Slash4"),
        "sc_slash5": ("12697203738", "ScissorsSlash/Slash5"),
        "sc_rawr": ("100613109627758", "ScissorsSlash/Rawr"),
        "sc_windarc": ("10859315454", "ScissorsSlash/3"),
    }
)

HOT, NEN, DEEP = "ffe2a6", "ffb547", "ff7701"  # core, aura, the game's Jajanken orange
FIRE = ("ffd08a", "ff6a00")
GROUND = {"GroundOnly": True, "UseGroundColor": True}
GROUND_ONLY = {"GroundOnly": True}


def charged(**extra):
    """Attributes for continuous layers that build with the charge."""
    return dict(extra)


class Light:
    """A PointLight: MaxBrightness for charging effects (brightens with the charge), or a glow that
    fades out over FadeTime in a burst."""

    def __init__(self, color, rng, brightness=0.0, attrs=None):
        self.color, self.rng, self.brightness, self.attrs = color, rng, brightness, attrs or {}

    def build(self, _lib):
        item = ET.Element("Item", {"class": "PointLight", "referent": ref()})
        props = ET.SubElement(item, "Properties")
        ET.SubElement(props, "string", {"name": "Name"}).text = "Glow"
        col = ET.SubElement(props, "Color3", {"name": "Color"})
        for k, i in zip("RGB", (0, 2, 4)):
            ET.SubElement(col, k).text = repr(int(self.color[i:i + 2], 16) / 255)
        ET.SubElement(props, "float", {"name": "Brightness"}).text = repr(float(self.brightness))
        ET.SubElement(props, "float", {"name": "Range"}).text = repr(float(self.rng))
        ET.SubElement(props, "bool", {"name": "Shadows"}).text = "false"
        ET.SubElement(props, "bool", {"name": "Enabled"}).text = "true"
        if self.attrs:
            ET.SubElement(props, "BinaryString", {"name": "AttributesSerialize"}).text = encode_attributes(self.attrs)
        return item


# --------------------------------------------------------------------------- charging
def aura():
    """Round the body while charging: gold-orange nen rising off the body, power lines and a second
    layer that only come in as it charges, a swirl of aura and smoke round the feet, dust blown out
    across the floor and pebbles lifting off it once the charge is high."""
    body = [
        Layer("aura_burst", "Flame", continuous=True, rate=18, life=(0.5, 1.1), size=3.0, speed=(2, 4.5),
              color=(HOT, NEN), le=1, br=2.5, flags=charged(RateGrow=0.7, Grow=0.6)),
        Layer("aura_esque", "Flame2", continuous=True, rate=12, life=(0.45, 0.9), size=3.6, speed=(1.5, 4),
              color=(NEN, DEEP), le=1, br=2, flags=charged(RateGrow=0.7, Grow=0.6)),
        Layer("aura_lines", "PowerLines", continuous=True, rate=40, life=(0.3, 0.3), size=4.5, speed=(12, 12),
              color=HOT, le=1, br=1.5, flags=charged(MinCharge=0.35, RateGrow=0.6)),
        Layer("aura_awaken", "FullPower", continuous=True, rate=9, life=(0.5, 0.5), size=5.5, color=NEN, le=1,
              br=1.5, flags=charged(MinCharge=0.7)),
        Light(NEN, 12, attrs={"MaxBrightness": 1.6}),
    ]
    feet = [
        Layer("aura_swirl", "Swirl", continuous=True, rate=5, size=7, color=NEN, le=1, br=2,
              flags=charged(RateGrow=0.6, Grow=0.4)),
        Layer("aura_smoke", "Smoke", continuous=True, rate=5, size=6, color=DEEP, le=1, br=1.5,
              flags=charged(RateGrow=0.6, Grow=0.3)),
        Layer("dust", "Dust", continuous=True, rate=14, life=(0.6, 1.2), size=2.5, dir=FRONT, spread=(0, 360),
              speed=(6, 14), drag=4, accel=(0, 1, 0), color=GREY, transp=DUST_FADE,
              flags=dict(GROUND, MinCharge=0.15, RateGrow=0.8)),
        Layer("rock", "Pebbles", continuous=True, rate=7, life=(0.8, 1.6), size=0.25, dir=TOP, spread=(60, 60),
              speed=(2, 5), drag=1, accel=(0, 5, 0), flags=dict(GROUND, MinCharge=0.45, RateGrow=0.7)),
    ]
    return {"name": "Aura", "layers": {"": body, "Feet": feet}, "subs": {"Feet": (0, -2.9, 0)}}


def hand_charge():
    """The aura gathering in the fist while charging, the same for all three (as in the anime, the
    opponent can't tell Rock from Paper or Scissors until the release): the game's RockRA fire
    (orange round a white core) and its glow, swelling as it charges."""
    fist = [
        Layer("nen_fire", "Fire", continuous=True, size=1.2, color=("ffd08a", DEEP), flags=charged(Grow=0.9, RateGrow=0.5)),
        Layer("nen_fire2", "Fire2", continuous=True, size=1.15, color=DEEP, flags=charged(Grow=0.9, RateGrow=0.5)),
        Layer("nen_fire", "Core", continuous=True, size=0.6, color=WHITE, le=0.4, flags=charged(Grow=0.6)),
        Layer("nen_glow", "Glow", continuous=True, size=2.2, color="ff6a00", flags=charged(Grow=0.8, MinCharge=0.1)),
        Light(DEEP, 6, attrs={"MaxBrightness": 1.2}),
    ]
    return {"name": "HandCharge", "layers": {"": fist}}


# --------------------------------------------------------------------------- casting
def release():
    """Letting go: the gathered aura flares off the body, and a ring of air and dust is pushed out
    across the floor."""
    body = [
        Layer("aura_disperse", "Flare", count=1, life=(0.45, 0.5), size=9, color=NEN, le=1, br=2),
        Layer("aura_burst", "Burst", count=10, life=(0.3, 0.6), size=3, dir=TOP, spread=(90, 90), speed=(8, 16),
              drag=4, color=(HOT, NEN), le=1, br=2),
    ]
    ground = [
        Layer("air_shock", "Ring", count=1, life=(0.18, 0.28), size=10, dir=TOP, ori=VEL_PERP, speed=(0.15, 0.15),
              drag=3.8, color=WHITE, transp=AIR, flags=GROUND_ONLY),
        Layer("wind_spin2", "Swirl", count=1, life=(0.2, 0.45), size=10, dir=TOP, ori=VEL_PERP, speed=(4, 4), drag=6,
              rotspeed=(108, 266), flags=GROUND_ONLY),
        Layer("dust", "Dust", count=8, life=(0.5, 1.0), size=2.8, dir=FRONT, spread=(5, 360), speed=(14, 30),
              drag=7, accel=(0, 1.2, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
    ]
    return {"name": "Release", "layers": {"": body, "Ground": ground}}


def _nen_burst(cone, count=14, size=4.0, speed=(25, 45)):
    return [
        Layer("nen_fire", "NenBurst", count=count, life=(0.3, 0.6), speed=speed, drag=6, dir=FRONT, spread=cone,
              size=size, color=FIRE, le=1, br=2, lock=False, accel=(0, 4, 0)),
        Layer("nen_fire2", "NenBurst2", count=max(4, count * 2 // 3), life=(0.35, 0.7), speed=(speed[0] * 0.4, speed[1] * 0.6),
              drag=5, dir=FRONT, spread=(min(180, cone[0] * 2), min(180, cone[1] * 2)), size=size * 0.9, color=DEEP,
              lock=False, accel=(0, 4, 0)),
        Layer("nen_glow", "NenCore", count=1, life=(0.2, 0.26), size=size * 2, color="ff8a2a", le=1, br=1,
              transp=[[0, 0.3, 0], [1, 1, 0]], lock=False),
    ]


def rock_blast():
    """Rock going off at the fist: the nen detonates forward (fire-like energy and a short glow), the
    air is blasted out in front (wind bursts, a spinning gust, pressure rings, streaks) with a cone
    of smoke that hangs, and the floor below kicks up wind, a wall of dust, rocks and (charged) cracks."""
    body = _nen_burst((35, 35)) + [
        Layer("wind_burst", "WindBlast", spread=(0, 0), count=2, life=(0.35, 0.5), size=14, dir=FRONT, ori=VEL_PERP,
              speed=(0.1, 0.1), color=WHITE, transp=AIR),
        Layer("wind_big", "WindSpin", count=1, life=(0.15, 0.4), size=15, dir=FRONT, ori=VEL_PERP, speed=(3, 3),
              rotspeed=(500, 1500), drag=6, transp=AIR),
        Layer("air_shock", "PressureRing", count=2, life=(0.2, 0.3), size=13, dir=FRONT, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR),
        Layer("air_ring", "AirRing", count=1, life=(0.18, 0.3), size=16, dir=FRONT, ori=VEL_PERP, speed=(6, 6), drag=10,
              le=0.3, br=1, color=WIND_LIGHT, transp=AIR_SOFT, delay=0.03),
        Layer("streak", "AirStreaks", count=10, life=(0.12, 0.3), size=2.4, dir=FRONT, spread=(28, 28),
              speed=(70, 110), drag=12, color=WIND_LIGHT, transp=STREAK, z=1),
        Layer("smoke_burst", "SmokeCone", count=6, life=(0.4, 0.9), size=6.5, dir=FRONT, spread=(45, 45),
              speed=(70, 110), drag=10, accel=(0, 2, 0), color=GREY),
        Layer("billow", "Billow", count=4, life=(0.6, 1.4), size=6, dir=FRONT, spread=(50, 50), speed=(15, 35),
              drag=7, accel=(0, 1, 0)),
        Layer("smoke_linger", "Haze", count=4, life=(0.8, 1.6), size=6, dir=FRONT, spread=(60, 60), speed=(4, 25),
              drag=3, color=DARK, delay=0.04),
        Light("ff9a3a", 18, 3, attrs={"FadeTime": 0.35}),
    ]
    ground = [
        Layer("wind_spin2", "GroundWind", count=2, life=(0.2, 0.6), size=16, dir=TOP, ori=VEL_PERP, speed=(4, 4),
              drag=6, rotspeed=(108, 266), flags=GROUND_ONLY),
        Layer("smoke_burst", "DustWall", count=8, life=(0.4, 0.9), size=6, dir=FRONT, spread=(0, 360),
              speed=(70, 100), drag=10, accel=(0, -4, 0), color=GREY, flags=GROUND),
        Layer("dust", "Dust", count=8, life=(0.5, 1.1), size=3.4, dir=FRONT, spread=(8, 80), speed=(18, 40),
              drag=7.4, accel=(0, 1.6, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("rock", "Rocks", count=12, life=(0.4, 1.1), size=0.35, dir=TOP, spread=(50, 50), speed=(20, 55), drag=5,
              accel=(0, -68, 0), flags=dict(GROUND, MinCharge=0.3)),
        Layer("crack", "Cracks", count=1, life=(1.5, 1.5), size=10, dir=TOP, ori=VEL_PERP,
              flags=dict(GROUND_ONLY, MinCharge=0.6)),
    ]
    return {"name": "RockBlast", "layers": {"": body, "Ground": ground}}


def paper_ball():
    """The thrown ball (continuous on the projectile): the game's PaperProjectile orb, fire round a
    white core, trailing air streaks and a thin smoke behind it."""
    ball = [
        Layer("nen_glow", "Orb", continuous=True, size=3.2, color="ff7a1a"),
        Layer("nen_fire", "Fire", continuous=True, size=2.2, color=FIRE, lock=True),
        Layer("nen_fire", "Core", continuous=True, size=1.2, color=WHITE, le=0.4, lock=True),
        Layer("streak", "AirTrail", continuous=True, rate=30, life=(0.1, 0.2), size=1.4, dir=BACK, spread=(8, 8),
              speed=(20, 40), drag=6, color=WIND_LIGHT, transp=STREAK),
        Layer("billow", "SmokeTrail", continuous=True, rate=14, life=(0.4, 0.8), size=2.4, dir=BACK, spread=(15, 15),
              speed=(2, 6), drag=3, color=GREY, transp=AIR_SOFT),
        Light("ff9a3a", 10, attrs={"MaxBrightness": 1.5}),
    ]
    return {"name": "PaperBall", "layers": {"": ball}}


def paper_blast():
    """Where the ball bursts: the nen goes off in every direction, with a burst of wind, pressure
    rings, streaks and smoke, and (on the floor) wind, a ring of dust, rocks and a scorch."""
    body = _nen_burst((180, 180), count=16, speed=(18, 34)) + [
        Layer("wind_burst", "WindBurst", spread=(0, 0), count=2, life=(0.35, 0.5), size=13, dir=FRONT, ori=VEL_PERP,
              speed=(0.1, 0.1), color=WHITE, transp=AIR),
        Layer("air_shock", "PressureRing", count=2, life=(0.2, 0.3), size=12, dir=FRONT, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR),
        Layer("air_ring", "AirRing", count=1, life=(0.18, 0.3), size=15, dir=FRONT, ori=VEL_PERP, speed=(6, 6), drag=10,
              le=0.3, br=1, color=WIND_LIGHT, transp=AIR_SOFT, delay=0.03),
        Layer("streak", "AirStreaks", count=12, life=(0.12, 0.28), size=2.2, dir=FRONT, spread=(180, 180),
              speed=(50, 90), drag=12, color=WIND_LIGHT, transp=STREAK, z=1),
        Layer("smoke_burst", "Smoke", count=8, life=(0.4, 0.9), size=5.5, dir=FRONT, spread=(180, 180),
              speed=(40, 80), drag=10, accel=(0, 2, 0), color=GREY),
        Layer("billow", "Billow", count=4, life=(0.6, 1.4), size=5.5, dir=TOP, spread=(70, 70), speed=(10, 25),
              drag=7, accel=(0, 1, 0)),
        Layer("smoke_linger", "Haze", count=4, life=(0.8, 1.6), size=6, dir=FRONT, spread=(180, 180), speed=(4, 20),
              drag=3, color=DARK, delay=0.04),
        Light("ff9a3a", 16, 3, attrs={"FadeTime": 0.35}),
    ]
    ground = [
        Layer("wind_fb", "GroundWind", count=2, life=(0.3, 0.6), size=14, dir=TOP, ori=VEL_PERP, speed=(3, 3),
              rotspeed=(-300, -130), drag=6, flags=GROUND_ONLY),
        Layer("smoke_burst", "DustWall", count=8, life=(0.4, 0.9), size=5.5, dir=FRONT, spread=(0, 360),
              speed=(60, 90), drag=10, accel=(0, -4, 0), color=GREY, flags=GROUND),
        Layer("rock", "Rocks", count=10, life=(0.4, 1.0), size=0.3, dir=TOP, spread=(55, 55), speed=(18, 45), drag=5,
              accel=(0, -68, 0), flags=dict(GROUND, MinCharge=0.3)),
        Layer("scorch", "Scorch", count=1, life=(1.4, 1.4), size=6, dir=TOP, ori=VEL_PERP, br=1, le=0,
              flags=dict(GROUND_ONLY, MinCharge=0.5)),
    ]
    return {"name": "PaperBlast", "layers": {"": body, "Ground": ground}}


def scissors_slash():
    """The scissors cut, lying flat across the front: the game's own ScissorsSlash crescents (the
    orange slash flipbooks and the grey wind arcs, without its black contrast frames), a wind
    crescent in the same plane and air streaks thrown on along the cut."""
    cut = [
        Layer("sc_slash4", "Slash", count=1, br=5),
        Layer("sc_slash5", "Slash2", count=1, br=5),
        Layer("sc_rawr", "Spin", count=1, br=5),
        Layer("sc_windarc", "WindArcs", count=2),
        Layer("wind_crescent", "WindCrescent", spread=(8, 8), count=1, life=(0.3, 0.4), size=10, dir=TOP, ori=VEL_PERP,
              speed=(0.05, 0.05), color=WIND_GREY, transp=AIR),
        Layer("streak", "AirStreaks", count=6, life=(0.1, 0.22), size=2, dir=FRONT, spread=(10, 40), speed=(60, 90),
              drag=12, color=WIND_LIGHT, transp=STREAK, z=1),
    ]
    return {"name": "ScissorsSlash", "layers": {"": cut}}


def nen_hit():
    """On each victim: a small burst of nen through them, a puff of air, a pressure ring, streaks
    and a little dust."""
    hit = [
        Layer("nen_fire", "NenBurst", count=6, life=(0.25, 0.45), speed=(14, 26), drag=6, dir=FRONT, spread=(40, 40),
              size=2.2, color=FIRE, le=1, br=2, lock=False),
        Layer("wind_burst", "AirBurst", spread=(0, 0), count=1, life=(0.3, 0.4), size=6, dir=FRONT, ori=VEL_PERP,
              speed=(0.1, 0.1), color=WHITE, transp=AIR),
        Layer("air_shock", "PressureRing", count=1, life=(0.18, 0.24), size=5.5, dir=FRONT, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR),
        Layer("streak", "AirStreaks", count=5, life=(0.08, 0.18), size=1.4, dir=FRONT, spread=(28, 28),
              speed=(40, 70), drag=12, color=WIND_LIGHT, transp=STREAK, z=1),
        Layer("dust", "Dust", count=3, life=(0.35, 0.6), size=2.2, dir=FRONT, spread=(50, 50), speed=(5, 14), drag=7,
              accel=(0, 1.5, 0), color=LIGHT, transp=DUST_FADE),
    ]
    return {"name": "NenHit", "layers": {"": hit}}


EFFECTS = [aura, hand_charge, release, rock_blast, paper_ball, paper_blast,
           scissors_slash, nen_hit]
_ = CAM  # (camera-facing is the reference default for most of these layers)


def build_effect(lib, spec):
    root = G.attachment(spec["name"], attrs={"Continuous": any(
        getattr(layer, "kw", {}).get("continuous") for layers in spec["layers"].values() for layer in layers)})
    for sub, layers in spec["layers"].items():
        if sub == "":
            parent = root
        else:
            pos = spec.get("subs", {}).get(sub, (0, -3, 0))
            parent = G.attachment(sub, pos=pos)
            root.append(parent)
        for layer in layers:
            parent.append(layer.build(lib))
    return root


def build_effects(nen_rbxmx):
    """Folder "Effects" with every effect, and a summary {name: [(sub, layer name, attributes)]}."""
    lib = G.Library(nen_rbxmx)
    folder = ET.Element("Item", {"class": "Folder", "referent": ref()})
    ET.SubElement(ET.SubElement(folder, "Properties"), "string", {"name": "Name"}).text = "Effects"
    summary = {}
    for make in EFFECTS:
        spec = make()
        folder.append(build_effect(lib, spec))
        rows = []
        for sub, layers in spec["layers"].items():
            for layer in layers:
                if isinstance(layer, Layer):
                    attrs = {}
                    kw = layer.kw
                    if kw.get("continuous"):
                        attrs["Continuous"] = True
                    else:
                        attrs["EmitCount"] = float(kw.get("count", 1))
                    attrs.update(kw.get("flags", {}))
                    rows.append((sub, layer.name, "ParticleEmitter", attrs))
                else:
                    rows.append((sub, "Glow", "PointLight", layer.attrs))
        summary[spec["name"]] = rows
    return folder, summary
