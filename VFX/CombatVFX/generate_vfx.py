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
    # wind and air
    "wind_burst": ("15574235597", "WIND3"),  # 4x4 wind blast flipbook
    "wind_swirl": ("98612397494241", "goodwindflip"),  # 4x4 swirling wind
    "wind_swirl2": ("107694353577834", "winddflip34"),
    "wind_crescent": ("15011468690", "Windy Crescent"),  # 4x4 wind crescent
    "wind_fb": ("119303887930651", "GroundImpact/wind"),  # 4x4 ground wind, spun
    "wind_spin": ("108159585520170", "GroundImpact/wind"),
    "wind_spin2": ("127670412975280", "GroundImpact/wind"),
    "wind_big": ("139946503438976", "GroundImpact/wind"),
    "wind_arc": ("10859315454", ""),  # grey wind arcs
    "air_shock": ("95143770508905", "GroundImpact/shock"),  # faint air-pressure ring
    "air_shock_fb": ("89531304475987", "SweepKick/shock"),
    "air_ring": ("134323380005873", "GroundImpact/shockwave"),  # grey shockwave, run soft
    "streak": ("14505952260", "GroundTPEmit/12"),  # thin air streaks
    # smoke and dust
    "billow": ("15415212938", "Billowing"),
    "smoke_fb": ("127900103415485", "GroundImpact/Smoke"),
    "smoke_burst": ("126248619163267", "GroundImpact/Smoke"),
    "smoke_fast": ("140112533856157", "GroundImpact/Smoke"),
    "smoke_linger": ("109202189790588", "smokeBack"),
    "cloud": ("90422254305404", "irregularcloud1"),
    "dust": ("8527116276", "ImpactFeet/duhhst"),
    "dust_big": ("1084987899", "ImpactFeet/duhhst"),
    # ground
    "rock": ("626588936", "JajankenImpact/rock"),
    "dirt": ("120481559306849", "Dirt"),
    "clumps": ("16177865281", "JajankenImpact/3"),
    "crack_fb": ("17137667240", "crack1"),
    "crack": ("108864559214218", "crack1"),
    "scorch": ("13781849388", "Realistic"),
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
        root = ET.parse(path).getroot()
        self.emitters = index_emitters(root)
        self.trail = next(item for item in root.iter("Item") if item.get("class") == "Trail")

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


class Trail:
    """A swing trail: a copy of the reference Trail with no texture (a soft sheet that fades out).

    transp, width: keys over the trail's length (0 = at the blade / fist, 1 = the oldest end)
    attrs: where it sits, read by CombatVFX.Swing (blades: From / To along SwingBase -> SwingTip;
    fists: Width across the knuckles), plus Accent.
    """

    def __init__(self, name, life, transp, width, face_camera=False, color="ffffff", attrs=None):
        self.name, self.life, self.transp, self.width = name, life, transp, width
        self.face_camera, self.color, self.attrs = face_camera, color, attrs or {}

    def build(self, lib):
        t = copy.deepcopy(lib.trail)
        t.set("referent", ref())
        props = t.find("Properties")
        for el in list(props):
            if el.get("name") in ("TextureContent", "Texture"):
                props.remove(el)
        _set_text(t, "string", "Name", self.name)
        _set_text(t, "Ref", "Attachment0", "null")
        _set_text(t, "Ref", "Attachment1", "null")
        set_bool(t, "Enabled", False)
        set_bool(t, "FaceCamera", self.face_camera)
        set_float(t, "Lifetime", self.life)
        set_float(t, "Brightness", 1)
        set_float(t, "LightEmission", 0)
        set_float(t, "LightInfluence", 0)
        set_float(t, "MinLength", 0)
        set_float(t, "MaxLength", 0)
        set_float(t, "TextureLength", 1)
        set_token(t, "TextureMode", 0)
        set_color(t, self.color)
        set_nseq(t, "Transparency", self.transp)
        set_nseq(t, "WidthScale", self.width)
        set_attributes(t, self.attrs)
        return t


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
DUST_FADE = [[0, 0.55, 0], [0.4, 0.7, 0], [1, 1, 0]]
GREY, LIGHT, DARK, WHITE = "9f9d9b", "d6d6d6", "4d4d4d", "ffffff"


# --------------------------------------------------------------------------- the effects
# Realistic wind: every effect is moving air, smoke and dust. No flashes, stars, glows or lights. The
# air layers are faint like the reference's (peak opacity 25-55%, grey) and stack up into the shape;
# Accent layers (the wind) take a move's colour when one is passed in.
# Placement: Play(name, cframe) puts the effect's root at cframe with its Front (-Z, LookVector)
# along the hit / travel direction; the "Ground" attachment is dropped onto the floor below it.
AIR = [[0, 0.5, 0], [0.5, 0.7, 0], [1, 1, 0]]  # faint wind
AIR_SOFT = [[0, 0.65, 0], [0.5, 0.8, 0], [1, 1, 0]]
STREAK = [[0, 0.45, 0], [1, 1, 0]]
WIND_GREY, WIND_LIGHT = "9a9a9a", "c4c4c4"


def m1_hit():
    """Light M1 contact: a puff of air blasted through the target (a wind burst, a swirl, a
    pressure ring and a couple of wind arcs), a few air streaks and a little dust. About 0.4s."""
    hit = [
        Layer("wind_burst", "AirBurst", spread=(0, 0), count=1, life=(0.3, 0.4), size=6, dir=FRONT, ori=VEL_PERP,
              speed=(0.1, 0.1), color=WHITE, transp=AIR, flags=ACCENT),
        Layer("wind_swirl", "AirSwirl", count=2, life=(0.3, 0.5), size=5, dir=FRONT, ori=VEL_PERP, spread=(15, 15),
              speed=(0.05, 0.05), rotspeed=(60, 140), color=WIND_LIGHT, transp=AIR, le=0.3, br=1, flags=ACCENT),
        Layer("air_shock", "PressureRing", count=1, life=(0.18, 0.24), size=6.5, dir=FRONT, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR),
        Layer("wind_arc", "WindArcs", count=2, life=(0.2, 0.35), size=5, dir=FRONT, ori=VEL_PERP, speed=(0.5, 2),
              rotspeed=(200, 400), color=WIND_GREY, transp=AIR, le=0.4, br=1),
        Layer("streak", "AirStreaks", count=4, life=(0.08, 0.18), size=1.2, dir=FRONT, spread=(28, 28),
              speed=(35, 60), drag=12, color=WIND_LIGHT, transp=STREAK, z=1),
        Layer("dust", "DustPuff", count=3, life=(0.35, 0.6), size=2.2, dir=FRONT, spread=(50, 50), speed=(5, 14),
              drag=7, accel=(0, 1.5, 0), color=LIGHT, transp=DUST_FADE),
    ]
    return {"name": "M1Hit", "layers": {"": hit}}


def m1_final():
    """Last hit of the string: a bigger blast of air through the target (two wind bursts, swirls,
    rings, wind arcs and streaks), a smoke puff blown out the far side and a dust ring on the floor."""
    hit = [
        Layer("wind_burst", "AirBurst", spread=(0, 0), count=2, life=(0.35, 0.5), size=9, dir=FRONT, ori=VEL_PERP,
              speed=(0.1, 0.1), color=WHITE, transp=AIR, flags=ACCENT),
        Layer("wind_swirl", "AirSwirl", count=3, life=(0.35, 0.6), size=7, dir=FRONT, ori=VEL_PERP, spread=(20, 20),
              speed=(0.05, 0.05), rotspeed=(60, 160), color=WIND_LIGHT, transp=AIR, le=0.3, br=1, flags=ACCENT),
        Layer("wind_swirl2", "AirSwirl2", spread=(8, 8), count=1, life=(0.4, 0.7), size=8, dir=FRONT, ori=VEL_PERP,
              speed=(0.05, 0.05), color=WIND_GREY, transp=AIR, flags=ACCENT),
        Layer("air_shock", "PressureRing", count=2, life=(0.18, 0.28), size=10, dir=FRONT, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR),
        Layer("air_ring", "AirRing", count=1, life=(0.15, 0.25), size=11, dir=FRONT, ori=VEL_PERP, speed=(5, 5),
              drag=10, le=0.3, br=1, color=WIND_LIGHT, transp=AIR_SOFT, delay=0.03),
        Layer("wind_arc", "WindArcs", count=4, life=(0.25, 0.4), size=8, dir=FRONT, ori=VEL_PERP, spread=(15, 15),
              speed=(0.5, 3), rotspeed=(200, 450), color=WIND_GREY, transp=AIR, le=0.4, br=1),
        Layer("streak", "AirStreaks", count=7, life=(0.1, 0.25), size=1.8, dir=FRONT, spread=(26, 26),
              speed=(50, 80), drag=12, color=WIND_LIGHT, transp=STREAK, z=1),
        Layer("billow", "SmokePuff", count=3, life=(0.5, 1.0), size=4.5, dir=FRONT, spread=(40, 40), speed=(14, 28),
              drag=7, accel=(0, 1, 0)),
        Layer("smoke_burst", "DustBurst", count=3, life=(0.3, 0.6), size=4, dir=FRONT, spread=(40, 40),
              speed=(40, 60), drag=10, accel=(0, 2, 0), color=GREY),
    ]
    ground = [
        Layer("wind_fb", "GroundWind", count=1, life=(0.3, 0.6), size=10, dir=TOP, ori=VEL_PERP, speed=(3, 3),
              rotspeed=(-300, -130), drag=6, flags={"GroundOnly": True}),
        Layer("air_shock", "GroundRing", count=1, life=(0.2, 0.3), size=10, dir=TOP, ori=VEL_PERP, speed=(0.15, 0.15),
              drag=3.8, color=WHITE, transp=AIR, flags={"GroundOnly": True}),
        Layer("dust", "DustKick", count=6, life=(0.4, 0.9), size=2.8, dir=FRONT, spread=(5, 70), speed=(14, 32),
              drag=7.4, accel=(0, 1.6, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
    ]
    return {"name": "M1Final", "layers": {"": hit, "Ground": ground}}


def heavy_hit():
    """Heavy / charged hit: a cone of wind blasted through the target in three waves, big spinning
    wind and pressure rings, a cone of smoke that hangs in the air, and wind and dust across the floor."""
    hit = [
        Layer("wind_burst", "AirBurst", spread=(0, 0), count=1, life=(0.4, 0.6), size=14, dir=FRONT, ori=VEL_PERP,
              speed=(0.1, 0.1), color=WHITE, transp=AIR, flags=ACCENT),
        Layer("wind_burst", "AirBurst2", spread=(0, 0), count=1, life=(0.4, 0.6), size=12, dir=FRONT, ori=VEL_PERP,
              speed=(0.1, 0.1), color=WHITE, transp=AIR, delay=0.03, flags=ACCENT),
        Layer("wind_burst", "AirBurst3", spread=(0, 0), count=1, life=(0.4, 0.6), size=10, dir=FRONT, ori=VEL_PERP,
              speed=(0.1, 0.1), color=WHITE, transp=AIR, delay=0.06, flags=ACCENT),
        Layer("wind_big", "WindSpin", count=2, life=(0.15, 0.4), size=16, dir=FRONT, ori=VEL_PERP, speed=(3, 3),
              rotspeed=(500, 1500), drag=6, transp=AIR, flags=ACCENT),
        Layer("wind_swirl", "AirSwirl", count=4, life=(0.4, 0.7), size=10, dir=FRONT, ori=VEL_PERP, spread=(20, 20),
              speed=(0.05, 0.05), rotspeed=(60, 160), color=WIND_LIGHT, transp=AIR, le=0.3, br=1, flags=ACCENT),
        Layer("wind_crescent", "WindCrescents", spread=(8, 8), count=2, life=(0.4, 0.8), size=10, dir=FRONT, ori=VEL_PERP,
              speed=(0.05, 0.05), color=WIND_GREY, transp=AIR),
        Layer("air_shock", "PressureRing", count=2, life=(0.2, 0.3), size=14, dir=FRONT, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR),
        Layer("air_shock_fb", "PressureWave", count=1, life=(0.4, 0.6), size=16, dir=FRONT, ori=VEL_PERP,
              speed=(0.5, 0.5), transp=AIR),
        Layer("air_ring", "AirRing", count=2, life=(0.18, 0.32), size=18, dir=FRONT, ori=VEL_PERP, speed=(6, 6),
              drag=10, le=0.3, br=1, color=WIND_LIGHT, transp=AIR_SOFT, delay=0.03),
        Layer("wind_arc", "WindArcs", count=6, life=(0.3, 0.5), size=12, dir=FRONT, ori=VEL_PERP, spread=(20, 20),
              speed=(1, 5), rotspeed=(200, 500), color=WIND_GREY, transp=AIR, le=0.4, br=1),
        Layer("streak", "AirStreaks", count=10, life=(0.12, 0.3), size=2.4, dir=FRONT, spread=(28, 28),
              speed=(60, 100), drag=12, color=WIND_LIGHT, transp=STREAK, z=1),
        Layer("smoke_burst", "SmokeCone", count=6, life=(0.4, 0.9), size=6.5, dir=FRONT, spread=(45, 45),
              speed=(70, 110), drag=10, accel=(0, 2, 0), color=GREY),
        Layer("billow", "SmokeBillow", count=4, life=(0.6, 1.4), size=6, dir=FRONT, spread=(50, 50), speed=(15, 35),
              drag=7, accel=(0, 1, 0)),
        Layer("smoke_linger", "Haze", count=4, life=(0.8, 1.6), size=6, dir=FRONT, spread=(60, 60), speed=(4, 25),
              drag=3, color=DARK, delay=0.04),
    ]
    ground = [
        Layer("wind_spin2", "GroundWind", count=2, life=(0.2, 0.6), size=16, dir=TOP, ori=VEL_PERP, speed=(4, 4),
              drag=6, rotspeed=(108, 266), flags={"GroundOnly": True}),
        Layer("wind_spin", "GroundWind2", count=2, life=(0.15, 0.5), size=14, dir=TOP, ori=VEL_PERP, speed=(7, 20),
              rotspeed=(130, 900), drag=6, flags={"GroundOnly": True}),
        Layer("air_shock", "GroundRing", count=1, life=(0.2, 0.35), size=16, dir=TOP, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR, flags={"GroundOnly": True}),
        Layer("dust", "DustKick", count=8, life=(0.5, 1.1), size=3.4, dir=FRONT, spread=(8, 80), speed=(18, 40),
              drag=7.4, accel=(0, 1.6, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("rock", "Pebbles", count=8, life=(0.4, 0.9), size=0.3, dir=TOP, spread=(40, 40), speed=(18, 40),
              drag=3, accel=(0, -60, 0), flags=GROUND),
    ]
    return {"name": "HeavyHit", "layers": {"": hit, "Ground": ground}}


def ground_slam():
    """Ground slam: the air blasts out flat across the floor (spinning wind, wind bursts and soft
    pressure rings racing outward), a radial wall of smoke and dust, billows rolling up, dirt and
    rocks thrown up and raining down, cracks and a scorch, and dust that hangs for a few seconds."""
    ground = [
        Layer("wind_burst", "AirBlast", spread=(0, 0), count=2, life=(0.4, 0.6), size=24, dir=TOP, ori=VEL_PERP, speed=(0.1, 0.1),
              color=WHITE, transp=AIR, flags=ACCENT),
        Layer("wind_fb", "Wind1", count=4, life=(0.15, 0.6), size=26, dir=TOP, ori=VEL_PERP, speed=(6.8, 6.8),
              rotspeed=(-444, -130), drag=6, flags=ACCENT),
        Layer("wind_spin", "Wind2", count=3, life=(0.15, 0.58), size=23, dir=TOP, ori=VEL_PERP, speed=(7, 30),
              rotspeed=(130, 1350), drag=6),
        Layer("wind_spin2", "Wind3", count=2, life=(0.2, 0.8), size=25, dir=TOP, ori=VEL_PERP, speed=(6.8, 6.8),
              rotspeed=(108, 266), drag=6),
        Layer("wind_big", "WindBig", count=2, life=(0.15, 0.4), size=22, dir=TOP, ori=VEL_PERP, speed=(3, 3),
              rotspeed=(500, 1500), drag=6, transp=AIR),
        Layer("wind_swirl", "WindSwirl", count=3, life=(0.4, 1.3), size=12, dir=TOP, ori=VEL_PERP, spread=(360, 360),
              speed=(0.05, 0.05), drag=5, transp=AIR_SOFT),
        Layer("air_shock", "PressureRing", count=2, life=(0.2, 0.35), size=22, dir=TOP, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR),
        Layer("air_ring", "AirRing1", count=1, life=(0.1, 0.25), size=27, dir=TOP, ori=VEL_PERP, speed=(6, 6), drag=10,
              le=0.3, br=1, color=WIND_LIGHT, transp=AIR_SOFT),
        Layer("air_ring", "AirRing2", count=1, life=(0.15, 0.3), size=25, dir=TOP, ori=VEL_PERP, speed=(6, 6),
              drag=10, le=0.3, br=1, color=WIND_LIGHT, transp=AIR_SOFT, delay=0.05),
        Layer("smoke_burst", "SmokeWall", count=10, life=(0.4, 0.9), size=6.4, dir=FRONT, spread=(0, 360),
              speed=(84, 110), drag=10, accel=(0, -4, 0), color=GREY, flags=GROUND),
        Layer("smoke_fast", "SmokeWallFast", count=6, life=(0.2, 0.35), size=5, dir=FRONT, spread=(0, 360),
              speed=(70, 130), drag=10, color=GREY, flags=GROUND),
        Layer("billow", "Billow", count=5, life=(0.5, 1.6), size=4.5, dir=TOP, spread=(60, 60), speed=(15, 37),
              drag=7, accel=(0, -6.7, 0), flags=GROUND),
        Layer("cloud", "DustCloud", count=3, life=(0.4, 1.4), size=5.5, dir=FRONT, spread=(0, 360), speed=(9, 38),
              drag=7, accel=(0, -4, 0), flags=GROUND),
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
        Layer("scorch", "Scorch", count=1, life=(1.4, 1.4), size=6, dir=TOP, ori=VEL_PERP, br=1, le=0,
              flags={"GroundOnly": True}),
    ]
    return {"name": "GroundSlam", "layers": {"Ground": ground}, "ground_offset": 0}


def dash_burst():
    """Start of a dash, aimed along the dash: a gust of wind tears off behind the body (a wind burst,
    swirls, wind arcs and air streaks) and the ground under the feet kicks up a ring of wind and dust."""
    body = [
        Layer("wind_burst", "Gust", spread=(0, 0), count=1, life=(0.3, 0.45), size=7, dir=BACK, ori=VEL_PERP, speed=(0.1, 0.1),
              color=WHITE, transp=AIR, flags=ACCENT),
        Layer("wind_swirl", "GustSwirl", count=2, life=(0.3, 0.5), size=6, dir=BACK, ori=VEL_PERP, spread=(15, 15),
              speed=(0.05, 0.05), rotspeed=(60, 140), color=WIND_LIGHT, transp=AIR, le=0.3, br=1, flags=ACCENT),
        Layer("wind_arc", "WindArcs", count=3, life=(0.2, 0.35), size=6, dir=BACK, ori=VEL_PERP, speed=(1, 4),
              rotspeed=(-400, -200), color=WIND_GREY, transp=AIR, le=0.4, br=1),
        Layer("streak", "AirStreaks", count=5, life=(0.1, 0.22), size=2, dir=BACK, spread=(10, 10), speed=(30, 70),
              drag=10, color=WIND_LIGHT, transp=STREAK),
    ]
    ground = [
        Layer("air_shock", "Ring", count=1, life=(0.18, 0.26), size=9, dir=TOP, ori=VEL_PERP, speed=(0.15, 0.15),
              drag=3.8, color=WHITE, transp=AIR, flags={"GroundOnly": True}),
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
    """While dashing (Start/Stop): wind arcs and faint air streaks pour off the body, dust trails off
    the feet."""
    body = [
        Layer("streak", "AirStreaks", continuous=True, rate=25, life=(0.1, 0.22), size=1.8, dir=BACK, spread=(8, 8),
              speed=(25, 45), drag=8, color=WIND_LIGHT, transp=STREAK, z=1),
        Layer("wind_arc", "WindArcs", continuous=True, rate=8, life=(0.15, 0.3), size=6, dir=BACK, ori=VEL_PERP,
              speed=(1, 4), rotspeed=(-240, -24), color=WIND_GREY, transp=AIR, flags=ACCENT),
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
    """Landing from a fall: a ring of air and a swirl of wind across the floor, dust blown out to
    both sides and grit (scale it with the fall using the Scale option)."""
    ground = [
        Layer("air_shock", "Ring", count=1, life=(0.18, 0.28), size=9, dir=TOP, ori=VEL_PERP, speed=(0.15, 0.15),
              drag=3.8, color=WHITE, transp=AIR, flags={"GroundOnly": True}),
        Layer("wind_swirl", "Swirl", count=1, life=(0.3, 0.6), size=8, dir=TOP, ori=VEL_PERP, speed=(0.05, 0.05),
              rotspeed=(60, 140), color=WIND_LIGHT, transp=AIR, flags={"GroundOnly": True}),
        Layer("dust", "DustLeft", count=6, life=(0.5, 0.9), size=3.2, dir=LEFT, spread=(0, 100), speed=(25, 40),
              drag=7.4, accel=(0, 1.6, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("dust", "DustRight", count=6, life=(0.5, 0.9), size=3.2, dir=RIGHT, spread=(0, 100), speed=(25, 40),
              drag=7.4, accel=(0, 1.6, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("dust_big", "DustUp", count=4, life=(0.4, 0.8), size=5, dir=TOP, spread=(80, 80), speed=(8, 30), drag=7.4,
              accel=(0, 0.8, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("rock", "Grit", count=6, life=(0.3, 0.9), size=0.14, dir=TOP, spread=(33, 33), speed=(8, 25), drag=3,
              accel=(0, -17.5, 0), flags=GROUND),
    ]
    return {"name": "Land", "layers": {"Ground": ground}, "ground_offset": 0}


def jump():
    """Take-off: a ring of air and a swirl pushed out under the feet, and a puff of dust."""
    ground = [
        Layer("air_shock", "Ring", count=1, life=(0.15, 0.25), size=7, dir=TOP, ori=VEL_PERP, speed=(0.15, 0.15),
              drag=3.8, color=WHITE, transp=AIR, flags={"GroundOnly": True}),
        Layer("wind_spin2", "Swirl", count=1, life=(0.2, 0.4), size=7, dir=TOP, ori=VEL_PERP, speed=(4, 4), drag=6,
              rotspeed=(108, 266), flags={"GroundOnly": True}),
        Layer("dust", "Puff", count=5, life=(0.3, 0.6), size=2.4, dir=FRONT, spread=(5, 360), speed=(10, 20), drag=7,
              accel=(0, 1, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
    ]
    return {"name": "Jump", "layers": {"Ground": ground}, "ground_offset": 0}


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


# --------------------------------------------------------------------------- swings
# Swing visualisation (CombatVFX.Swing): trails that follow the blade / fist while it moves fast, a wake
# of air pulled along behind it, and a burst of air at the fastest point. The swing templates hold the
# trails and a "Wake" attachment of continuous emitters (aimed along the travel every frame, so BACK
# trails behind); their attributes are the speeds (studs/s, measured relative to the body) that switch
# the trails on and off, picked from the M1 animations: sword slashes peak at 230-280 and their wind-ups
# stay under 100; the stab peaks at 70 along the blade; punches peak at 75-125, the guard hand under 85.
SHEET_FADE = [[0, 0.82, 0], [0.5, 0.9, 0], [1, 1, 0]]
EDGE_FADE = [[0, 0.62, 0], [0.35, 0.8, 0], [1, 1, 0]]
POINT_FADE = [[0, 0.5, 0], [0.3, 0.72, 0], [1, 1, 0]]


def sword_swing():
    """Sword M1s: a faint sheet over the blade's path, a stronger band along the edge and a line off the
    point (the only part a stab leaves), with wisps and streaks of air pulled along behind the blade."""
    trails = [
        Trail("Sheet", 0.12, SHEET_FADE, [[0, 1, 0], [1, 0.6, 0]], attrs={"From": 0.05, "To": 1.0, "Accent": True}),
        Trail("Edge", 0.17, EDGE_FADE, [[0, 1, 0], [1, 0.3, 0]], attrs={"From": 0.62, "To": 1.0, "Accent": True}),
        Trail("Point", 0.22, POINT_FADE, [[0, 1, 0], [1, 0.15, 0]], face_camera=True,
              attrs={"From": 0.9, "To": 1.0, "Accent": True}),
    ]
    wake = [
        Layer("wind_swirl", "AirWisps", continuous=True, rate=70, life=(0.2, 0.35), size=1.6, dir=BACK, ori=CAM,
              spread=(25, 25), speed=(2, 6), drag=6, rotspeed=(60, 160), color=WIND_LIGHT, transp=AIR_SOFT,
              flags=ACCENT),
        Layer("streak", "AirStreaks", continuous=True, rate=40, life=(0.08, 0.16), size=0.9, dir=BACK, spread=(10, 10),
              speed=(15, 30), drag=10, color=WIND_LIGHT, transp=STREAK, z=1),
    ]
    attrs = {"Kind": "Blade", "OnSpeed": 120.0, "OffSpeed": 80.0, "ThrustSpeed": 45.0, "ThrustOffSpeed": 30.0,
             "ThrustAlign": 0.85, "Burst": "SwordCut", "ThrustBurst": "SwordThrust", "BurstAlong": 0.8,
             "BurstAhead": 0.0}
    return {"name": "SwordSwing", "attrs": attrs, "trails": trails, "layers": {"Wake": wake},
            "wake_attrs": {"Along": 0.85}}


def fist_swing():
    """Fist M1s: a soft streak behind the punching fist (only that one: the guard hand is left alone)
    with wisps and streaks of air pulled along behind it."""
    trails = [
        Trail("Streak", 0.14, [[0, 0.72, 0], [0.4, 0.86, 0], [1, 1, 0]], [[0, 1, 0], [1, 0.35, 0]], face_camera=True,
              attrs={"Width": 0.9, "Accent": True}),
        Trail("Core", 0.1, [[0, 0.55, 0], [1, 1, 0]], [[0, 1, 0], [1, 0.2, 0]], face_camera=True,
              attrs={"Width": 0.35, "Accent": True}),
    ]
    wake = [
        Layer("wind_swirl", "AirWisps", continuous=True, rate=60, life=(0.18, 0.3), size=1.1, dir=BACK, ori=CAM,
              spread=(25, 25), speed=(1, 4), drag=6, rotspeed=(60, 160), color=WIND_LIGHT, transp=AIR_SOFT,
              flags=ACCENT),
        Layer("streak", "AirStreaks", continuous=True, rate=35, life=(0.07, 0.14), size=0.7, dir=BACK, spread=(10, 10),
              speed=(12, 24), drag=10, color=WIND_LIGHT, transp=STREAK, z=1),
    ]
    attrs = {"Kind": "Fist", "OnSpeed": 50.0, "OffSpeed": 35.0, "Burst": "FistPush", "BurstAlong": 0.0,
             "BurstAhead": 0.6}
    return {"name": "FistSwing", "attrs": attrs, "trails": trails, "layers": {"Wake": wake}}


def kick_swing():
    """Kicks: the fist swing's streak, wider, behind the kicking foot (only that one: the standing leg is
    left alone), with air pulled along behind it. At the fastest point it fires KickPush."""
    trails = [
        Trail("Streak", 0.16, [[0, 0.7, 0], [0.4, 0.85, 0], [1, 1, 0]], [[0, 1, 0], [1, 0.35, 0]], face_camera=True,
              attrs={"Width": 1.2, "Accent": True}),
        Trail("Core", 0.11, [[0, 0.55, 0], [1, 1, 0]], [[0, 1, 0], [1, 0.2, 0]], face_camera=True,
              attrs={"Width": 0.45, "Accent": True}),
    ]
    wake = [
        Layer("wind_swirl", "AirWisps", continuous=True, rate=70, life=(0.2, 0.32), size=1.4, dir=BACK, ori=CAM,
              spread=(25, 25), speed=(1, 4), drag=6, rotspeed=(60, 160), color=WIND_LIGHT, transp=AIR_SOFT,
              flags=ACCENT),
        Layer("streak", "AirStreaks", continuous=True, rate=40, life=(0.07, 0.15), size=0.9, dir=BACK, spread=(10, 10),
              speed=(14, 26), drag=10, color=WIND_LIGHT, transp=STREAK, z=1),
    ]
    attrs = {"Kind": "Kick", "OnSpeed": 36.0, "OffSpeed": 24.0, "Burst": "KickPush", "BurstAlong": 0.0,
             "BurstAhead": 0.8}
    return {"name": "KickSwing", "attrs": attrs, "trails": trails, "layers": {"Wake": wake}}


def sword_cut():
    """Fired by SwordSwing at the fastest point of a slash, at the blade's last fifth. LookVector = the
    blade's travel, UpVector = off the swing plane, so TOP + VelocityPerpendicular lies in the plane:
    wind arcs and a swirl of air in the plane of the cut, and air streaks thrown on along it."""
    cut = [
        Layer("wind_arc", "WindArcs", count=2, life=(0.18, 0.3), size=5, dir=TOP, ori=VEL_PERP, spread=(0, 0),
              speed=(0.1, 0.1), rotspeed=(150, 300), color=WIND_GREY, transp=AIR, le=0.4, br=1, flags=ACCENT),
        Layer("wind_swirl2", "AirSwirl", count=1, life=(0.3, 0.45), size=4.5, dir=TOP, ori=VEL_PERP, spread=(0, 0),
              speed=(0.05, 0.05), color=WIND_GREY, transp=AIR_SOFT, flags=ACCENT),
        Layer("streak", "AirStreaks", count=4, life=(0.08, 0.18), size=1.4, dir=FRONT, spread=(12, 12),
              speed=(40, 70), drag=12, color=WIND_LIGHT, transp=STREAK, z=1),
    ]
    return {"name": "SwordCut", "layers": {"": cut}}


def sword_thrust():
    """Fired by SwordSwing at the fastest point of a stab, at the point, looking along the thrust: a
    ring of air pushed off the point, a small blast and swirl ahead of it, and air streaks."""
    pierce = [
        Layer("air_shock", "PressureRing", count=1, life=(0.15, 0.22), size=3.5, dir=FRONT, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR),
        Layer("wind_burst", "AirPierce", spread=(0, 0), count=1, life=(0.25, 0.35), size=4.5, dir=FRONT,
              ori=VEL_PERP, speed=(0.1, 0.1), color=WHITE, transp=AIR, flags=ACCENT),
        Layer("wind_swirl", "AirSwirl", count=1, life=(0.25, 0.35), size=3, dir=FRONT, ori=VEL_PERP, spread=(10, 10),
              speed=(0.05, 0.05), rotspeed=(80, 160), color=WIND_LIGHT, transp=AIR, flags=ACCENT),
        Layer("streak", "AirStreaks", count=5, life=(0.1, 0.2), size=1.6, dir=FRONT, spread=(8, 8), speed=(50, 80),
              drag=12, color=WIND_LIGHT, transp=STREAK, z=1),
    ]
    return {"name": "SwordThrust", "layers": {"": pierce}}


def fist_push():
    """Fired by FistSwing at the fastest point of a punch, just ahead of the knuckles, looking along the
    punch: a small push of air, a pressure ring, a swirl and a few streaks. Smaller than M1Hit, which
    is the contact."""
    push = [
        Layer("wind_burst", "AirPush", spread=(0, 0), count=1, life=(0.2, 0.3), size=3.2, dir=FRONT, ori=VEL_PERP,
              speed=(0.1, 0.1), color=WHITE, transp=AIR, flags=ACCENT),
        Layer("air_shock", "PressureRing", count=1, life=(0.12, 0.18), size=2.6, dir=FRONT, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR),
        Layer("wind_swirl", "AirSwirl", count=1, life=(0.2, 0.3), size=2.2, dir=FRONT, ori=VEL_PERP, spread=(10, 10),
              speed=(0.05, 0.05), rotspeed=(80, 160), color=WIND_LIGHT, transp=AIR_SOFT, flags=ACCENT),
        Layer("streak", "AirStreaks", count=3, life=(0.07, 0.14), size=0.9, dir=FRONT, spread=(15, 15),
              speed=(30, 50), drag=12, color=WIND_LIGHT, transp=STREAK, z=1),
    ]
    return {"name": "FistPush", "layers": {"": push}}


def kick_push():
    """Fired by KickSwing at the fastest point of a kick, just ahead of the foot, looking along it: the
    fist's push of air, bigger - a wind burst, a pressure ring, a swirl and streaks."""
    push = [
        Layer("wind_burst", "AirPush", spread=(0, 0), count=1, life=(0.22, 0.32), size=4.5, dir=FRONT, ori=VEL_PERP,
              speed=(0.1, 0.1), color=WHITE, transp=AIR, flags=ACCENT),
        Layer("air_shock", "PressureRing", count=1, life=(0.14, 0.2), size=3.6, dir=FRONT, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR),
        Layer("wind_swirl", "AirSwirl", count=1, life=(0.22, 0.32), size=3, dir=FRONT, ori=VEL_PERP, spread=(10, 10),
              speed=(0.05, 0.05), rotspeed=(80, 160), color=WIND_LIGHT, transp=AIR_SOFT, flags=ACCENT),
        Layer("wind_arc", "WindArcs", count=1, life=(0.18, 0.28), size=3.5, dir=FRONT, ori=VEL_PERP, speed=(0.5, 2),
              rotspeed=(200, 400), color=WIND_GREY, transp=AIR, le=0.4, br=1),
        Layer("streak", "AirStreaks", count=4, life=(0.07, 0.15), size=1.1, dir=FRONT, spread=(15, 15),
              speed=(35, 55), drag=12, color=WIND_LIGHT, transp=STREAK, z=1),
    ]
    return {"name": "KickPush", "layers": {"": push}}


def body_slam():
    """A body slammed into the floor (a suplex, a chokeslam): a smaller ground slam - air blasted out flat,
    a low ring of smoke and dust rolling outward, grit and pebbles thrown up, a few cracks, and dust that
    hangs a moment. Place it at the floor point under the body."""
    ground = [
        Layer("wind_burst", "AirBlast", spread=(0, 0), count=1, life=(0.35, 0.5), size=14, dir=TOP, ori=VEL_PERP,
              speed=(0.1, 0.1), color=WHITE, transp=AIR, flags=ACCENT),
        Layer("wind_fb", "Wind", count=2, life=(0.15, 0.5), size=15, dir=TOP, ori=VEL_PERP, speed=(6, 6),
              rotspeed=(-444, -130), drag=6, flags=ACCENT),
        Layer("wind_spin2", "Wind2", count=1, life=(0.2, 0.6), size=14, dir=TOP, ori=VEL_PERP, speed=(6, 6),
              rotspeed=(108, 266), drag=6),
        Layer("air_shock", "PressureRing", count=1, life=(0.2, 0.3), size=13, dir=TOP, ori=VEL_PERP,
              speed=(0.15, 0.15), drag=3.8, color=WHITE, transp=AIR),
        Layer("air_ring", "AirRing", count=1, life=(0.12, 0.25), size=16, dir=TOP, ori=VEL_PERP, speed=(6, 6),
              drag=10, le=0.3, br=1, color=WIND_LIGHT, transp=AIR_SOFT),
        Layer("smoke_burst", "SmokeWall", count=7, life=(0.35, 0.8), size=4.8, dir=FRONT, spread=(0, 360),
              speed=(60, 85), drag=10, accel=(0, -4, 0), color=GREY, flags=GROUND),
        Layer("dust", "Dust", count=8, life=(0.5, 1.0), size=3, dir=FRONT, spread=(8, 360), speed=(14, 32),
              drag=7.4, accel=(0, 1.6, 0), color=GREY, transp=DUST_FADE, flags=GROUND),
        Layer("billow", "Billow", count=3, life=(0.5, 1.2), size=3.8, dir=TOP, spread=(60, 60), speed=(10, 25),
              drag=7, accel=(0, -6, 0), flags=GROUND),
        Layer("rock", "Pebbles", count=10, life=(0.4, 1.0), size=0.3, dir=TOP, spread=(55, 55), speed=(18, 45),
              drag=5.6, accel=(0, -68, 0), flags=GROUND),
        Layer("crack", "Cracks", count=1, life=(1.4, 1.4), size=9, dir=TOP, ori=VEL_PERP, flags={"GroundOnly": True}),
        Layer("smoke_linger", "DustHang", count=4, life=(1.2, 2.4), size=7, dir=FRONT, spread=(0, 360),
              speed=(4, 25), drag=3, color=DARK, delay=0.05, flags=GROUND),
    ]
    return {"name": "BodySlam", "layers": {"Ground": ground}, "ground_offset": 0}


EFFECTS = [m1_hit, m1_final, heavy_hit, ground_slam, dash_burst, dash_trail, footstep, land, jump, slide_dust,
           run_dust, sword_swing, fist_swing, sword_cut, sword_thrust, fist_push, kick_swing, kick_push, body_slam]


# --------------------------------------------------------------------------- export
def build_effect(lib, spec):
    root_attrs = {"Continuous": bool(spec.get("continuous"))}
    if spec.get("light"):
        root_attrs["LightBrightness"], root_attrs["LightRange"], root_attrs["LightTime"] = spec["light"]
    root_attrs.update(spec.get("attrs", {}))
    root = attachment(spec["name"], attrs=root_attrs)
    for trail in spec.get("trails", []):
        root.append(trail.build(lib))
    for sub, layers in spec["layers"].items():
        if sub == "":
            parent = root
        elif sub == "Air":
            parent = attachment("Air", pos=(0, spec.get("air_height", 1.5), 0))
            root.append(parent)
        elif sub == "Wake":  # swing templates: Swing moves it onto the blade / fist
            parent = attachment("Wake", attrs=spec.get("wake_attrs"))
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
        counts[spec["name"]] = sum(len(v) for v in spec["layers"].values()) + len(spec.get("trails", []))
    root = ET.Element("roblox", {"version": "4"})
    root.append(module)
    out = os.path.join(out_dir, "CombatVFX.rbxmx")
    ET.ElementTree(root).write(out, encoding="utf-8", xml_declaration=False)
    for k, v in counts.items():
        print("%-12s %2d layers" % (k, v))
    print("wrote", out)
    return out


if __name__ == "__main__":
    build(sys.argv[1])
