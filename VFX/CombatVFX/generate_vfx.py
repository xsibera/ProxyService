"""Combat VFX pack, built from the emitters in VFXFORCLAUDE.rbxm / nen.rbxm.

Every layer of every effect starts as a copy of one of the reference emitters (picked by its texture), so
each texture keeps the flipbook layout, light emission and squash it was authored with. The layer is
then re-sized, re-timed, re-aimed and re-coloured for its new job. Effects follow the reference
conventions:
  * Burst emitters are disabled and carry EmitCount / EmitDelay (and EmitDuration) attributes, so the
    game's own emit code can play them. CombatVFX.luau plays them the same way.
  * Ground layers (dust, rocks, cracks, rings) sit in a "Ground" attachment that the player drops onto
    the floor. Emitters marked GroundOnly only fire when there is floor there; UseGroundColor emitters
    are tinted by the floor's colour.
  * Emitters marked Accent take the move's colour when one is passed in.

Usage:  python3 generate_vfx.py path/to/nen.rbxmx
"""

import base64
import copy
import math
import os
import struct
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))

# EmissionDirection (NormalId) and Orientation tokens
RIGHT, TOP, BACK, LEFT, BOTTOM, FRONT = range(6)
CAM, CAM_UP, VEL_PAR, VEL_PERP = range(4)

# --------------------------------------------------------------------------- reference emitters
TEX = {  # role -> (texture id, path hint picking which reference emitter to copy)
    "flash_big": ("13853120945", "GroundImpact/flash"),
    "flash_short": ("108142928341917", "GroundImpact/3"),
    "flash_burst": ("7162072137", "Burst/3"),
    "flash_flat": ("16697955702", "FLASH"),
    "flash_star": ("14080556170", "GroundImpact/Impact"),
    "black_flat": ("16559053748", "GroundImpact/Impact"),
    "impact_fb": ("110231729477276", "JajankenImpact/Impact"),
    "impact_fb_flat": ("115669629549824", "JajankenImpact/Impact"),
    "impact_flicker": ("18397658030", "JajankenImpact/impact"),
    "ring_grey": ("134323380005873", "GroundImpact/shockwave"),
    "ring_white": ("96004355425020", "Extra/shockwave"),
    "ring_shock": ("95143770508905", "GroundImpact/shock"),
    "ring_fast": ("9641756324", "Shockwave2"),
    "ring_linger": ("15056677063", "Shockwaves1"),
    "ring_spin": ("10149702982", "impactshock"),
    "ring_3": ("11707580805", "Shockwave3"),
    "cresc_spin": ("140234193278455", "cresc"),
    "cresc_out": ("105372547148688", "cresc"),
    "wind_fb": ("119303887930651", "GroundImpact/wind"),
    "wind_spin": ("108159585520170", "GroundImpact/wind"),
    "wind_spin2": ("127670412975280", "GroundImpact/wind"),
    "wind_flip": ("98612397494241", "goodwindflip"),
    "wind_arc": ("10859315454", ""),
    "shards": ("17164994986", "shards"),
    "streak": ("14505952260", "GroundTPEmit/12"),
    "streak_fast": ("9660685442", "GroundTPEmit/2"),
    "streak_big": ("14680194852", "GroundTPEmit/1"),
    "stretch_flash": ("12262387727", "GroundTPEmit"),
    "streak_5": ("14730297032", "GroundTPEmit/5"),
    "specs": ("98820846953467", "BangImpact/ParticleEmitter"),
    "ember": ("14005903992", "ember"),
    "dust": ("8527116276", "ImpactFeet/duhhst"),
    "dust_big": ("1084987899", "ImpactFeet/duhhst"),
    "smoke_burst": ("126248619163267", "GroundImpact/Smoke"),
    "smoke_burst2": ("82804901664521", "GroundImpact/Smoke"),
    "smoke_fast": ("140112533856157", "GroundImpact/Smoke"),
    "smoke_fb": ("127900103415485", "GroundImpact/Smoke"),
    "smoke_linger": ("109202189790588", "smokeBack"),
    "smoke_linger2": ("93675353995344", "smokeBack"),
    "billow": ("15415212938", "Billowing"),
    "rock": ("626588936", "JajankenImpact/rock"),
    "dirt": ("120481559306849", "Dirt"),
    "clumps": ("16177865281", "JajankenImpact/3"),
    "crack_fb": ("17137667240", "crack1"),
    "crack": ("108864559214218", "crack1"),
    "crack2": ("17013333656", "crack"),
    "scorch": ("13781849388", "Realistic"),
    "glow": ("17844277603", "glow"),
    "land_lines": ("2360242557", "ImpactFeet/16"),
}


def name_of(item):
    el = item.find("Properties/string[@name='Name']")
    return el.text if el is not None else ""


def index_emitters(root):
    out = []

    def walk(item, path):
        for c in item.findall("Item"):
            p = path + "/" + name_of(c)
            if c.get("class") == "ParticleEmitter":
                tex = c.find("Properties/Content[@name='TextureContent']")
                uri = tex.find("uri") if tex is not None else None
                out.append((p, (uri.text if uri is not None else "") or "", c))
            walk(c, p)

    walk(root, "")
    return out


class Library:
    def __init__(self, path):
        self.emitters = index_emitters(ET.parse(path).getroot())

    def template(self, role):
        tex, hint = TEX[role]
        hits = [e for p, t, e in self.emitters if t.endswith(tex) and hint in p]
        if not hits:
            hits = [e for p, t, e in self.emitters if t.endswith(tex)]
        assert hits, "no reference emitter for %s (%s)" % (role, tex)
        return hits[0]


# --------------------------------------------------------------------------- XML editing
_ref = [0]


def ref():
    _ref[0] += 1
    return "RBXVFX%06d" % _ref[0]


def _prop(item, tag, name):
    return item.find("Properties/%s[@name='%s']" % (tag, name))


def _set_text(item, tag, name, text):
    el = _prop(item, tag, name)
    if el is None:
        el = ET.SubElement(item.find("Properties"), tag, {"name": name})
    el.text = text


def _num(v):
    return repr(round(float(v), 6))


def nseq(item, name):
    vals = [float(x) for x in (_prop(item, "NumberSequence", name).text or "").split()]
    return [vals[i:i + 3] for i in range(0, len(vals), 3)]


def set_nseq(item, name, keys):
    keys = [list(k) + [0.0] * (3 - len(k)) for k in keys]
    _set_text(item, "NumberSequence", name, " ".join(_num(v) for k in keys for v in k) + " ")


def set_range(item, name, lo, hi=None):
    _set_text(item, "NumberRange", name, "%s %s " % (_num(lo), _num(lo if hi is None else hi)))


def get_range(item, name):
    return [float(x) for x in (_prop(item, "NumberRange", name).text or "0 0").split()]


def set_color(item, *hexes):
    cols = [tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)) for h in hexes]
    if len(cols) == 1:
        cols = cols * 2
    keys = []
    for i, c in enumerate(cols):
        keys += [i / (len(cols) - 1), c[0], c[1], c[2], 0]
    _set_text(item, "ColorSequence", "Color", " ".join(_num(v) for v in keys) + " ")


def set_vec(item, tag, name, vals):
    el = _prop(item, tag, name)
    for c, v in zip(el, vals):
        c.text = _num(v)


def set_float(item, name, v):
    _set_text(item, "float", name, _num(v))


def set_token(item, name, v):
    _set_text(item, "token", name, str(int(v)))


def set_bool(item, name, v):
    _set_text(item, "bool", name, "true" if v else "false")


def encode_attributes(attrs):
    out = struct.pack("<I", len(attrs))
    for k, v in attrs.items():
        kb = k.encode()
        out += struct.pack("<I", len(kb)) + kb
        if isinstance(v, bool):
            out += b"\x03" + struct.pack("<B", int(v))
        elif isinstance(v, (int, float)):
            out += b"\x06" + struct.pack("<d", float(v))
        else:
            sb = str(v).encode()
            out += b"\x02" + struct.pack("<I", len(sb)) + sb
    return base64.b64encode(out).decode()


def set_attributes(item, attrs):
    _set_text(item, "BinaryString", "AttributesSerialize", encode_attributes(attrs))


# --------------------------------------------------------------------------- layers
class Layer:
    """One emitter of an effect: a copy of a reference emitter with overrides.

    size: number (scale the reference curve so it peaks at this many studs) or explicit keys
    life, speed: (lo, hi);  count, delay, duration: emit attributes;  color: hex or (hex, hex)
    Anything else maps straight onto the emitter: dir, ori, spread, accel, drag, le (LightEmission),
    br (Brightness), z (ZOffset), rot, rotspeed, ts (TimeScale), transp, squash, lock, rate.
    flags: extra attributes (GroundOnly, UseGroundColor, Accent).
    """

    def __init__(self, role, name=None, **kw):
        self.role, self.name, self.kw = role, name or role, kw

    def build(self, lib):
        e = copy.deepcopy(lib.template(self.role))
        e.set("referent", ref())
        kw = self.kw
        _set_text(e, "string", "Name", self.name)
        if "size" in kw:
            size = kw["size"]
            if isinstance(size, (int, float)):
                keys = nseq(e, "Size")
                peak = max(abs(k[1]) for k in keys) or 1.0
                f = size / peak
                keys = [[k[0], k[1] * f, k[2] * f] for k in keys]
            else:
                keys = size
            set_nseq(e, "Size", keys)
        if "life" in kw:
            set_range(e, "Lifetime", *kw["life"])
        if "speed" in kw:
            set_range(e, "Speed", *kw["speed"])
        if "rot" in kw:
            set_range(e, "Rotation", *kw["rot"])
        if "rotspeed" in kw:
            set_range(e, "RotSpeed", *kw["rotspeed"])
        if "transp" in kw:
            set_nseq(e, "Transparency", kw["transp"])
        if "squash" in kw:
            set_nseq(e, "Squash", kw["squash"])
        if "color" in kw:
            c = kw["color"]
            set_color(e, *(c if isinstance(c, tuple) else (c,)))
        if "dir" in kw:
            set_token(e, "EmissionDirection", kw["dir"])
        if "ori" in kw:
            set_token(e, "Orientation", kw["ori"])
        if "spread" in kw:
            set_vec(e, "Vector2", "SpreadAngle", kw["spread"])
        if "accel" in kw:
            set_vec(e, "Vector3", "Acceleration", kw["accel"])
        for key, prop in (("drag", "Drag"), ("le", "LightEmission"), ("br", "Brightness"), ("z", "ZOffset"),
                          ("ts", "TimeScale"), ("rate", "Rate"), ("inherit", "VelocityInheritance")):
            if key in kw:
                set_float(e, prop, kw[key])
        if "lock" in kw:
            set_bool(e, "LockedToPart", kw["lock"])
        continuous = kw.get("continuous", False)
        set_bool(e, "Enabled", False)  # bursts fire from attributes; continuous ones are switched on by Start()
        attrs = {}
        if not continuous:
            attrs["EmitCount"] = float(kw.get("count", 1))
            attrs["EmitDelay"] = float(kw.get("delay", 0))
            if kw.get("duration"):
                attrs["EmitDuration"] = float(kw["duration"])
        else:
            attrs["Continuous"] = True
        attrs.update(kw.get("flags", {}))
        set_attributes(e, attrs)
        return e


def attachment(name, pos=(0, 0, 0), up=None, attrs=None):
    """Attachment item; `up` tilts it so its Top face points that way (default: Y up, Front = -Z)."""
    item = ET.Element("Item", {"class": "Attachment", "referent": ref()})
    props = ET.SubElement(item, "Properties")
    ET.SubElement(props, "string", {"name": "Name"}).text = name
    cfe = ET.SubElement(props, "CoordinateFrame", {"name": "CFrame"})
    rot = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    if up is not None:  # Top face along `up`, keeping -Z as close to forward as possible
        y = [v / math.sqrt(sum(c * c for c in up)) for v in up]
        z = [0, 0, 1]
        x = [y[1] * z[2] - y[2] * z[1], y[2] * z[0] - y[0] * z[2], y[0] * z[1] - y[1] * z[0]]
        n = math.sqrt(sum(c * c for c in x))
        x = [c / n for c in x]
        z = [x[1] * y[2] - x[2] * y[1], x[2] * y[0] - x[0] * y[2], x[0] * y[1] - x[1] * y[0]]
        rot = [[x[0], y[0], z[0]], [x[1], y[1], z[1]], [x[2], y[2], z[2]]]
    for k, v in zip("XYZ", pos):
        ET.SubElement(cfe, k).text = _num(v)
    for i in range(3):
        for j in range(3):
            ET.SubElement(cfe, "R%d%d" % (i, j)).text = _num(rot[i][j])
    if attrs:
        ET.SubElement(props, "BinaryString", {"name": "AttributesSerialize"}).text = encode_attributes(attrs)
    return item


GROUND = {"GroundOnly": True, "UseGroundColor": True}
ACCENT = {"Accent": True}
FADE = [[0, 0, 0], [1, 1, 0]]  # opaque -> gone
FADE_SOFT = [[0, 0.6, 0], [1, 1, 0]]
DUST_FADE = [[0, 0.55, 0], [0.4, 0.7, 0], [1, 1, 0]]
GREY, LIGHT, DARK, WHITE, BLACK = "9f9d9b", "d6d6d6", "4d4d4d", "ffffff", "000000"


# --------------------------------------------------------------------------- the effects
# Placement: Play(name, cframe) puts the effect's root at cframe with its Front (-Z, LookVector)
# along the hit / travel direction; the "Ground" attachment is dropped onto the floor below it.
def m1_hit():
    """Light M1 contact: a hot white pop, a ring punched along the hit, crescents and streaks
    sprayed through the target and a little dust. About 0.4s, sized for a 5-stud character."""
    hit = [
        Layer("flash_burst", "Flash", count=1, life=(0.06, 0.08), size=6.5, br=6, le=1, z=3, color=WHITE, flags=ACCENT),
        Layer("impact_fb", "Pop", count=1, life=(0.14, 0.14), size=4.5, speed=(6, 6), dir=FRONT, drag=15, br=3, z=2,
              color=WHITE, flags=ACCENT),
        Layer("ring_white", "Ring", count=1, life=(0.12, 0.16), size=6, dir=FRONT, ori=VEL_PERP, speed=(0.01, 0.01),
              le=1, br=1.5, transp=FADE_SOFT),
        Layer("ring_fast", "RingSnap", count=1, life=(0.08, 0.1), size=7.5, dir=FRONT, ori=VEL_PERP, speed=(0.01, 0.01),
              le=1, br=1.2),
        Layer("cresc_spin", "Crescents", count=3, life=(0.1, 0.18), size=4.5, dir=FRONT, ori=VEL_PERP, speed=(0.02, 0.02),
              rotspeed=(-800, -550), le=1),
        Layer("streak", "Streaks", count=6, life=(0.08, 0.2), size=1.6, dir=FRONT, spread=(32, 32), speed=(45, 75),
              drag=15, color=WHITE, z=1.5),
        Layer("specs", "Specks", count=5, life=(0.25, 0.45), size=1.6, dir=FRONT, spread=(45, 45), speed=(14, 30),
              drag=5, color=LIGHT, le=0.6, br=1.5),
        Layer("dust", "Puff", count=3, life=(0.35, 0.6), size=2.4, dir=FRONT, spread=(60, 60), speed=(6, 16),
              drag=7, accel=(0, 1.5, 0), color=LIGHT, transp=DUST_FADE),
    ]
    return {"name": "M1Hit", "layers": {"": hit}, "light": (4, 8, 0.12)}


def m1_final():
    """Last hit of the string: the M1 pop with a black/white contrast frame, a double ring, a fan
    of streaks and shards blown through the target, a smoke burst, and a dust ring on the floor."""
    hit = [
        Layer("flash_big", "Flash", count=1, life=(0.1, 0.1), size=12, br=12, z=6, color=WHITE, flags=ACCENT),
        Layer("black_flat", "BlackFrame", count=1, life=(0.07, 0.12), size=9, dir=FRONT, ori=VEL_PERP, speed=(0.01, 0.01),
              color=BLACK, le=0.55),
        Layer("flash_star", "Star", count=2, life=(0.05, 0.1), size=10, dir=FRONT, ori=VEL_PERP, speed=(0.1, 0.1),
              br=4, le=0.4, z=2.7, color=WHITE, flags=ACCENT),
        Layer("impact_fb", "Pop", count=1, life=(0.15, 0.15), size=6.5, speed=(10, 10), dir=FRONT, drag=15, br=3, z=2,
              color=WHITE, flags=ACCENT),
        Layer("ring_grey", "Ring", count=1, life=(0.12, 0.2), size=12, dir=FRONT, ori=VEL_PERP, speed=(6, 6), drag=10,
              le=1),
        Layer("ring_fast", "RingSnap", count=2, life=(0.1, 0.12), size=13, dir=FRONT, ori=VEL_PERP, speed=(0.01, 0.01),
              le=1),
        Layer("cresc_spin", "Crescents", count=6, life=(0.12, 0.2), size=7, dir=FRONT, ori=VEL_PERP, speed=(0.03, 0.03),
              rotspeed=(-800, -550), le=1),
        Layer("cresc_out", "CrescentsOut", count=5, life=(0.16, 0.3), size=6, dir=FRONT, ori=VEL_PERP, spread=(25, 25),
              speed=(0, 40)),
        Layer("shards", "Shards", count=3, life=(0.04, 0.12), size=4, dir=FRONT, spread=(30, 30), speed=(270, 700),
              drag=44, color=WHITE, flags=ACCENT),
        Layer("streak", "Streaks", count=10, life=(0.1, 0.3), size=2.2, dir=FRONT, spread=(28, 28), speed=(60, 95),
              drag=14, color=WHITE, z=1.5),
        Layer("specs", "Specks", count=7, life=(0.3, 0.6), size=2, dir=FRONT, spread=(40, 40), speed=(18, 40),
              drag=4.8, color=LIGHT, le=0.6, br=1.5),
        Layer("smoke_burst", "SmokeBurst", count=4, life=(0.3, 0.6), size=4.5, dir=FRONT, spread=(50, 50),
              speed=(40, 70), drag=10, accel=(0, 2, 0), color=GREY),
    ]
    ground = [
        Layer("ring_grey", "DustRing", count=1, life=(0.15, 0.3), size=11, dir=TOP, ori=VEL_PERP, speed=(4, 4), drag=10,
              le=0.6, color="b8b6b4", flags={"GroundOnly": True}),
        Layer("dust", "DustKick", count=6, life=(0.4, 0.9), size=2.8, dir=FRONT, spread=(5, 70), speed=(14, 32),
              drag=7.4, accel=(0, 1.6, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
    ]
    return {"name": "M1Final", "layers": {"": hit, "Ground": ground}, "light": (7, 12, 0.18)}


def heavy_hit():
    """Heavy / charged hit: a big contrast flash, black and white eruptions blown out along the hit,
    stacked rings, spinning crescents, shards, a cone of smoke that hangs, embers and a ground ring."""
    hit = [
        Layer("flash_big", "Flash", count=1, life=(0.15, 0.15), size=18, br=20, z=8, color=WHITE, flags=ACCENT),
        Layer("flash_short", "FlashCore", count=1, life=(0.08, 0.08), size=12, br=25, z=6, color=WHITE),
        Layer("black_flat", "BlackFrame", count=2, life=(0.1, 0.22), size=16, dir=FRONT, ori=VEL_PERP,
              speed=(1.2, 1.2), color=BLACK, le=0.55),
        Layer("flash_star", "Star", count=3, life=(0.05, 0.12), size=16, dir=FRONT, ori=VEL_PERP, speed=(0.1, 0.1),
              br=4, le=0.4, z=2.7, color=WHITE, flags=ACCENT),
        Layer("impact_fb_flat", "Burst", count=1, life=(0.1, 0.1), size=9, dir=FRONT, ori=VEL_PERP, speed=(0.01, 0.01),
              br=12, le=1, z=2, color=WHITE, flags=ACCENT),
        Layer("ring_grey", "Ring", count=2, life=(0.15, 0.3), size=18, dir=FRONT, ori=VEL_PERP, speed=(6, 6), drag=10,
              le=1),
        Layer("ring_fast", "RingSnap", count=2, life=(0.1, 0.14), size=18, dir=FRONT, ori=VEL_PERP, speed=(0.01, 0.01),
              le=1),
        Layer("ring_3", "RingWide", count=2, life=(0.2, 0.3), size=14, dir=FRONT, ori=VEL_PERP, speed=(0.3, 0.3), le=1,
              br=0.6, delay=0.03),
        Layer("ring_spin", "RingSpin", count=1, life=(0.4, 0.5), size=12, dir=FRONT, ori=VEL_PERP, speed=(0.2, 0.2),
              color=("cfcfcf", "434343")),
        Layer("cresc_spin", "Crescents", count=10, life=(0.12, 0.22), size=9, dir=FRONT, ori=VEL_PERP,
              speed=(0.03, 0.03), rotspeed=(-800, -550), le=1),
        Layer("cresc_out", "CrescentsOut", count=8, life=(0.16, 0.32), size=8, dir=FRONT, ori=VEL_PERP, spread=(25, 25),
              speed=(0, 70)),
        Layer("stretch_flash", "Eruption", count=2, life=(0.06, 0.14), size=14, dir=FRONT, spread=(10, 10),
              speed=(40, 140), drag=13, color=WHITE),
        Layer("shards", "Shards", count=5, life=(0.04, 0.14), size=5, dir=FRONT, spread=(35, 35), speed=(300, 1000),
              drag=44, color=WHITE, flags=ACCENT),
        Layer("streak", "Streaks", count=14, life=(0.1, 0.35), size=2.8, dir=FRONT, spread=(30, 30), speed=(70, 110),
              drag=14, color=WHITE, z=1.5),
        Layer("ember", "Embers", count=6, life=(0.05, 0.25), size=6, dir=FRONT, spread=(40, 40), speed=(80, 300),
              drag=25, color=WHITE, br=6, flags=ACCENT),
        Layer("smoke_burst", "SmokeBurst", count=6, life=(0.4, 0.9), size=6.5, dir=FRONT, spread=(45, 45),
              speed=(70, 110), drag=10, accel=(0, 2, 0), color=GREY),
        Layer("smoke_linger", "SmokeHang", count=4, life=(0.8, 1.6), size=6, dir=FRONT, spread=(60, 60), speed=(4, 25),
              drag=3, color=DARK, delay=0.04),
    ]
    ground = [
        Layer("ring_grey", "DustRing", count=1, life=(0.2, 0.35), size=18, dir=TOP, ori=VEL_PERP, speed=(6, 6), drag=10,
              le=0.6, color="b8b6b4", flags={"GroundOnly": True}),
        Layer("wind_spin2", "GroundWind", count=2, life=(0.2, 0.6), size=16, dir=TOP, ori=VEL_PERP, speed=(4, 4),
              drag=6, rotspeed=(108, 266), flags={"GroundOnly": True}),
        Layer("dust", "DustKick", count=8, life=(0.5, 1.1), size=3.4, dir=FRONT, spread=(8, 80), speed=(18, 40),
              drag=7.4, accel=(0, 1.6, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("rock", "Pebbles", count=8, life=(0.4, 0.9), size=0.3, dir=TOP, spread=(40, 40), speed=(18, 40),
              drag=3, accel=(0, -60, 0), flags=GROUND),
    ]
    return {"name": "HeavyHit", "layers": {"": hit, "Ground": ground}, "light": (10, 18, 0.25)}


def ground_slam():
    """Ground slam: a flash and black contrast frame on contact, shockwave rings racing out across
    the floor, wind swirling flat over the ground, a radial wall of smoke, dirt and rocks thrown up
    and raining down, cracks and a scorch left behind, and dust that hangs for a few seconds."""
    air = [
        Layer("flash_big", "Flash", count=1, life=(0.15, 0.15), size=24, br=25, z=11, color=WHITE, flags=ACCENT),
        Layer("flash_short", "FlashCore", count=1, life=(0.083, 0.083), size=18, br=30, z=3, color=WHITE),
        Layer("glow", "Glow", count=1, life=(0.6, 0.6), size=(([0, 16, 0], [1, 20, 0])), le=1, br=2, z=4,
              color=LIGHT, flags=ACCENT),
        Layer("stretch_flash", "Eruption", count=3, life=(0.08, 0.16), size=16, dir=TOP, spread=(15, 15),
              speed=(40, 141), drag=13, color=WHITE),
        Layer("streak_fast", "Spikes", count=4, life=(0.1, 0.2), size=5, dir=TOP, spread=(20, 20), speed=(140, 300),
              drag=7, color=WHITE),
        Layer("shards", "Shards", count=6, life=(0.04, 0.14), size=5, dir=TOP, spread=(70, 70), speed=(300, 900),
              drag=44, color=WHITE, flags=ACCENT),
        Layer("ember", "Embers", count=8, life=(0.05, 0.28), size=7, dir=TOP, spread=(70, 70), speed=(75, 300),
              drag=25, color=WHITE, br=6, flags=ACCENT),
    ]
    ground = [
        Layer("black_flat", "BlackFrame", count=2, life=(0.13, 0.3), size=24, dir=TOP, ori=VEL_PERP, speed=(1.2, 1.2),
              color=BLACK, le=0.55),
        Layer("flash_flat", "FlatFlash", count=3, life=(0.1, 0.13), size=19, dir=TOP, ori=VEL_PERP, br=30, z=3,
              color=WHITE, flags=ACCENT),
        Layer("ring_fast", "RingSnap", count=2, life=(0.12, 0.12), size=24, dir=TOP, ori=VEL_PERP, le=1),
        Layer("ring_grey", "Ring1", count=1, life=(0.1, 0.25), size=27, dir=TOP, ori=VEL_PERP, speed=(6, 6), drag=10,
              le=1),
        Layer("ring_grey", "Ring2", count=1, life=(0.15, 0.3), size=25, dir=TOP, ori=VEL_PERP, speed=(6, 6), drag=10,
              le=1, delay=0.05),
        Layer("ring_grey", "Ring3", count=1, life=(0.35, 0.35), size=23, dir=TOP, ori=VEL_PERP, speed=(8, 8), drag=10,
              le=1, delay=0.1),
        Layer("ring_linger", "RingLinger", count=1, life=(0.75, 1.1), size=14, ori=CAM, le=1, br=0.1),
        Layer("ring_spin", "RingSpin", count=1, life=(0.57, 0.57), size=17, dir=TOP, ori=VEL_PERP, speed=(0.2, 0.2),
              color=("b3b3b3", "434343")),
        Layer("wind_fb", "Wind1", count=4, life=(0.15, 0.6), size=26, dir=TOP, ori=VEL_PERP, speed=(6.8, 6.8),
              rotspeed=(-444, -130), drag=6),
        Layer("wind_spin", "Wind2", count=3, life=(0.15, 0.58), size=23, dir=TOP, ori=VEL_PERP, speed=(7, 30),
              rotspeed=(130, 1350), drag=6),
        Layer("wind_spin2", "Wind3", count=2, life=(0.2, 0.8), size=25, dir=TOP, ori=VEL_PERP, speed=(6.8, 6.8),
              rotspeed=(108, 266), drag=6),
        Layer("wind_flip", "WindFlip", count=3, life=(0.4, 1.3), size=11, dir=TOP, ori=VEL_PERP, spread=(360, 360),
              speed=(0.05, 0.05), drag=5),
        Layer("smoke_burst", "SmokeWall", count=10, life=(0.4, 0.9), size=6.4, dir=FRONT, spread=(0, 360),
              speed=(84, 110), drag=10, accel=(0, -4, 0), color=GREY, flags=GROUND),
        Layer("smoke_fast", "SmokeWallFast", count=6, life=(0.2, 0.35), size=5, dir=FRONT, spread=(0, 360),
              speed=(70, 130), drag=10, color=GREY, flags=GROUND),
        Layer("billow", "Billow", count=5, life=(0.5, 1.6), size=4.5, dir=TOP, spread=(60, 60), speed=(15, 37),
              drag=7, accel=(0, -6.7, 0), flags=GROUND),
        Layer("smoke_linger", "DustHang", count=10, life=(1.8, 4), size=10, dir=FRONT, spread=(0, 360),
              speed=(4, 40), drag=3, color=DARK, delay=0.05, flags=GROUND),
        Layer("dirt", "Dirt", count=9, life=(0.4, 1.2), size=5, dir=TOP, spread=(60, 60), speed=(40, 85), drag=10,
              accel=(0, -74, 0), flags=GROUND),
        Layer("clumps", "Clumps", count=4, life=(0.5, 2), size=4.5, dir=TOP, spread=(70, 70), speed=(10, 25), drag=5,
              accel=(0, -12, 0), flags=GROUND),
        Layer("rock", "Rocks", count=16, life=(0.4, 1.2), size=0.4, dir=TOP, spread=(55, 55), speed=(25, 70),
              drag=5.6, accel=(0, -68, 0), flags=GROUND),
        Layer("crack_fb", "Cracks", count=1, life=(2, 2), size=13, dir=TOP, ori=VEL_PERP, flags={"GroundOnly": True}),
        Layer("crack", "CracksOuter", count=1, life=(1.5, 1.5), size=(([0, 6, 0], [1, 14, 0])), dir=TOP, ori=VEL_PERP,
              flags={"GroundOnly": True}),
        Layer("scorch", "Scorch", count=1, life=(1.4, 1.4), size=6, dir=TOP, ori=VEL_PERP, flags={"GroundOnly": True}),
    ]
    return {"name": "GroundSlam", "layers": {"Air": air, "Ground": ground}, "air_height": 1.5, "ground_offset": 0,
            "light": (12, 26, 0.3)}


def dash_burst():
    """Start of a dash, aimed along the dash: the air snaps behind the body in stretched flashes and
    speed streaks, and the ground under the feet kicks up a ring, a swirl and a spray of dust."""
    body = [
        Layer("stretch_flash", "Snap", count=2, life=(0.05, 0.15), size=10, dir=BACK, spread=(20, 20),
              speed=(1, 120), drag=13, color=LIGHT),
        Layer("streak_5", "Streaks", count=5, life=(0.04, 0.25), size=3, dir=BACK, spread=(10, 10), speed=(20, 120),
              drag=13, color=LIGHT),
        Layer("streak_fast", "LongStreaks", count=2, life=(0.1, 0.18), size=4, dir=BACK, spread=(4, 4),
              speed=(140, 380), drag=7, color=WHITE),
        Layer("streak_big", "Whoosh", count=1, life=(0.1, 0.1), size=7, dir=BACK, speed=(220, 220), drag=9,
              color=LIGHT),
        Layer("cresc_spin", "Crescents", count=2, life=(0.1, 0.16), size=5, dir=BACK, ori=VEL_PERP, speed=(0.02, 0.02),
              rotspeed=(-800, -550), le=1),
    ]
    ground = [
        Layer("ring_grey", "Ring", count=1, life=(0.12, 0.22), size=10, dir=TOP, ori=VEL_PERP, speed=(4, 4), drag=10,
              le=0.6, color="b8b6b4", flags={"GroundOnly": True}),
        Layer("wind_spin2", "Swirl", count=1, life=(0.2, 0.45), size=9, dir=TOP, ori=VEL_PERP, speed=(4, 4), drag=6,
              rotspeed=(108, 266), flags={"GroundOnly": True}),
        Layer("dust", "DustKick", count=7, life=(0.35, 0.9), size=3.2, dir=BACK, spread=(15, 40), speed=(17, 40), drag=5,
              accel=(0, -8, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("dust_big", "DustCloud", count=3, life=(0.25, 0.6), size=6, dir=BACK, spread=(10, 50), speed=(25, 45),
              drag=5.5, accel=(0, 0.8, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("rock", "Pebbles", count=6, life=(0.3, 0.8), size=0.22, dir=BACK, spread=(30, 30), speed=(10, 30),
              drag=2, accel=(0, -40, 0), flags=GROUND),
    ]
    return {"name": "DashBurst", "layers": {"": body, "Ground": ground}}


def dash_trail():
    """While dashing (Start/Stop): wind streaks pour off the body and dust trails off the feet."""
    body = [
        Layer("streak", "Streaks", continuous=True, rate=40, life=(0.1, 0.22), size=2, dir=BACK, spread=(8, 8),
              speed=(25, 45), drag=8, color=LIGHT, z=1),
        Layer("wind_arc", "WindArcs", continuous=True, rate=8, life=(0.15, 0.3), size=6, dir=BACK, ori=VEL_PERP,
              speed=(1, 4), rotspeed=(-240, -24), transp=[[0, 0.6, 0], [1, 1, 0]]),
    ]
    feet = [
        Layer("dust", "Dust", continuous=True, rate=22, life=(0.3, 0.7), size=2.2, dir=BACK, spread=(20, 30),
              speed=(6, 16), drag=5, accel=(0, 1, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
    ]
    return {"name": "DashTrail", "layers": {"": body, "Ground": feet}, "continuous": True}


def footstep():
    """One footfall while sprinting: a small puff and a couple of grains, tinted by the floor."""
    ground = [
        Layer("dust", "Puff", count=3, life=(0.3, 0.6), size=1.8, dir=TOP, spread=(70, 70), speed=(3, 8), drag=6,
              accel=(0, 0.8, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("dust", "Kick", count=2, life=(0.25, 0.45), size=1.4, dir=BACK, spread=(20, 25), speed=(6, 12), drag=6,
              color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("rock", "Grains", count=2, life=(0.25, 0.5), size=0.12, dir=TOP, spread=(45, 45), speed=(5, 12), drag=2,
              accel=(0, -30, 0), flags=GROUND),
    ]
    return {"name": "Footstep", "layers": {"Ground": ground}, "ground_offset": 0}


def land():
    """Landing from a fall: dust blown out to both sides, a ring, grit and downward speed lines,
    copied from the reference ImpactFeet (scale with the fall using the Scale option)."""
    ground = [
        Layer("ring_grey", "Ring", count=1, life=(0.12, 0.25), size=9, dir=TOP, ori=VEL_PERP, speed=(4, 4), drag=10,
              le=0.6, color="b8b6b4", flags={"GroundOnly": True}),
        Layer("dust", "DustLeft", count=6, life=(0.5, 0.9), size=3.2, dir=LEFT, spread=(0, 100), speed=(25, 40),
              drag=7.4, accel=(0, 1.6, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("dust", "DustRight", count=6, life=(0.5, 0.9), size=3.2, dir=RIGHT, spread=(0, 100), speed=(25, 40),
              drag=7.4, accel=(0, 1.6, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("dust_big", "DustUp", count=4, life=(0.4, 0.8), size=5, dir=TOP, spread=(80, 80), speed=(8, 30), drag=7.4,
              accel=(0, 0.8, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("rock", "Grit", count=6, life=(0.3, 0.9), size=0.14, dir=TOP, spread=(33, 33), speed=(8, 25), drag=3,
              accel=(0, -17.5, 0), flags=GROUND),
        Layer("land_lines", "Lines", count=8, life=(0.1, 0.3), size=2.4, dir=TOP, spread=(10, 180), speed=(50, 70),
              drag=8.9, flags={"GroundOnly": True}),
    ]
    return {"name": "Land", "layers": {"Ground": ground}, "ground_offset": 0}


def jump():
    """Take-off: a ring and a puff pushed down and out from the feet, and a short upward whoosh."""
    ground = [
        Layer("ring_grey", "Ring", count=1, life=(0.1, 0.2), size=7, dir=TOP, ori=VEL_PERP, speed=(4, 4), drag=10,
              le=0.6, color="b8b6b4", flags={"GroundOnly": True}),
        Layer("dust", "Puff", count=5, life=(0.3, 0.6), size=2.4, dir=FRONT, spread=(5, 360), speed=(10, 20), drag=7,
              accel=(0, 1, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
    ]
    body = [
        Layer("streak_5", "Whoosh", count=3, life=(0.05, 0.15), size=2.2, dir=BOTTOM, spread=(12, 12), speed=(30, 80),
              drag=13, color=LIGHT),
    ]
    return {"name": "Jump", "layers": {"": body, "Ground": ground}, "ground_offset": 0}


def slide_dust():
    """While sliding (Start/Stop): a spray of dust and grit off the feet, tinted by the floor."""
    feet = [
        Layer("dust", "Spray", continuous=True, rate=26, life=(0.3, 0.8), size=2.6, dir=BACK, spread=(20, 35),
              speed=(10, 24), drag=5, accel=(0, -4, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("dust_big", "Cloud", continuous=True, rate=6, life=(0.5, 1.0), size=4.5, dir=BACK, spread=(15, 40),
              speed=(6, 14), drag=5.5, accel=(0, 0.8, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("rock", "Grit", continuous=True, rate=10, life=(0.25, 0.6), size=0.14, dir=BACK, spread=(25, 25),
              speed=(8, 20), drag=2, accel=(0, -30, 0), flags=GROUND),
    ]
    return {"name": "SlideDust", "layers": {"Ground": feet}, "continuous": True}


def run_dust():
    """While sprinting (Start/Stop): a light trail of dust off the feet."""
    feet = [
        Layer("dust", "Trail", continuous=True, rate=9, life=(0.3, 0.6), size=1.8, dir=BACK, spread=(25, 35),
              speed=(3, 8), drag=6, accel=(0, 1, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
    ]
    return {"name": "RunDust", "layers": {"Ground": feet}, "continuous": True}


EFFECTS = [m1_hit, m1_final, heavy_hit, ground_slam, dash_burst, dash_trail, footstep, land, jump, slide_dust,
           run_dust]


# --------------------------------------------------------------------------- export
def build_effect(lib, spec):
    root_attrs = {"Continuous": bool(spec.get("continuous"))}
    if spec.get("light"):
        root_attrs["LightBrightness"], root_attrs["LightRange"], root_attrs["LightTime"] = spec["light"]
    root = attachment(spec["name"], attrs=root_attrs)
    for sub, layers in spec["layers"].items():
        if sub == "":
            parent = root
        elif sub == "Air":
            parent = attachment("Air", pos=(0, spec.get("air_height", 1.5), 0))
            root.append(parent)
        else:  # "Ground": the player drops it onto the floor (until then it sits ground_offset below)
            parent = attachment(sub, pos=(0, spec.get("ground_offset", -3), 0))
            root.append(parent)
        for layer in layers:
            parent.append(layer.build(lib))
    return root


def module_script(name, source):
    item = ET.Element("Item", {"class": "ModuleScript", "referent": ref()})
    props = ET.SubElement(item, "Properties")
    ET.SubElement(props, "string", {"name": "Name"}).text = name
    ET.SubElement(props, "ProtectedString", {"name": "Source"}).text = source
    return item


def build(ref_path, out_dir=HERE):
    lib = Library(ref_path)
    module = module_script("CombatVFX", open(os.path.join(out_dir, "CombatVFX.luau")).read())
    effects = ET.SubElement(module, "Item", {"class": "Folder", "referent": ref()})
    ET.SubElement(ET.SubElement(effects, "Properties"), "string", {"name": "Name"}).text = "Effects"
    counts = {}
    for make in EFFECTS:
        spec = make()
        effects.append(build_effect(lib, spec))
        counts[spec["name"]] = sum(len(v) for v in spec["layers"].values())
    root = ET.Element("roblox", {"version": "4"})
    root.append(module)
    out = os.path.join(out_dir, "CombatVFX.rbxmx")
    ET.ElementTree(root).write(out, encoding="utf-8", xml_declaration=False)
    for k, v in counts.items():
        print("%-11s %2d layers" % (k, v))
    print("wrote", out)
    return out


if __name__ == "__main__":
    build(sys.argv[1])
