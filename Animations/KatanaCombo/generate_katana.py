"""R6 two-handed katana set, in the style of the reference animations (ANIMSFORCLAUDE.rbxm), built on
the same two-handed machinery as the greatsword (../twohanded.py) but cut the way a katana is used:
quicker, tighter cuts from a centre guard, and a draw that is itself a cut.

Clips: idle (chudan-no-kamae, looped), unsheathe (iai: the blade is drawn from the saya at the left
hip and cuts across the front one-handed, nukitsuke, then the left hand joins it in chudan),
m1-1 (kesa-giri: high right to low left), m1-2 (kiri-age: rising, low left to high right), m1-3
(shomen-giri: from overhead straight down the centre, with a lunge), running attack (a dash cut,
right to left at waist height, into a deep lunge), aerial attack (a falling cut from overhead), and
"m1 string (1,2,1,2,3)", which chains the M1s the way the game plays them, to preview the string.

From the references (kareemandbeast two-handed swings, as the greatsword): the left fist is locked
on the grip every frame (here at the end of the long tsuka, LEFT_GRIP below the right), the wind-up
cocks the blade back over a shoulder (or the hip, for the rising cut) with the body wound the wrong
way, and the hands travel an exact circle through the target with the tip whipping behind them.
The cuts are faster and shorter than the greatsword's: Hit ~0.4s into 0.8s clips, the body whipping
~120 deg rather than ~180. Conventions are the same as the other sets: the sword's Handle hangs off a
"Handle" Motor6D in the Right Arm (C0 at the fist), legs keyed at Weight 0 except in the running
and aerial attacks, 60 fps, and the clips are 2x smoother than their keys (animkit).

Usage:  python3 generate_katana.py path/to/ANIMSFORCLAUDE.rbxmx
"""

import json
import math
import os
import sys
import xml.etree.ElementTree as ET

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ANIMS = os.path.dirname(HERE)
sys.path.insert(0, ANIMS)
sys.path.insert(0, os.path.join(ANIMS, "SwordCombo"))
from animkit import (  # noqa: E402
    FPS,
    Clip,
    build_string,
    clip_transforms,
    from_transform,
    prop,
    ref,
    reference_rig,
    sequence_xml,
    smoothstep,
    world_leg,
)
from generate_sword import (  # noqa: E402
    GRIP,
    MOTORS,
    _cf_of,
    _cframe_prop,
    _child,
    _joint,
    _model,
    _part,
    aim,
    cf,
    heading,
    inv,
    joint_cf,
)
from twohanded import fly, handle_cf, left_on, m1_path, ramp, root_path, slerp, spline, tame, unit  # noqa: E402
from twohanded import grip_pass as _grip_pass  # noqa: E402

JOINTS = ("Root", "Neck", "RArm", "LArm", "Handle")
FULL = JOINTS + ("RLeg", "LLeg")


def rx(deg):
    a = math.radians(deg)
    return np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])


def ry(deg):
    a = math.radians(deg)
    return np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])


# --------------------------------------------------------------------------- the katana
# Handle space: the right fist at the origin, just behind the tsuba; the blade runs along -Z with its
# edge (ha) on +Y and its back (mune) on -Y, curving gently toward the back (sori), so held edge-down
# the tip rises; the tsuka runs back along +Z, long enough for the left fist LEFT_GRIP behind the right.
STEEL, HAMON, IRON = (168, 174, 182), (226, 229, 233), (54, 52, 52)
ITO, SAME, GOLD = (24, 24, 34), (226, 220, 204), (196, 160, 72)
LACQUER, HORN = (22, 18, 18), (60, 50, 44)
LEFT_GRIP = 0.9
BLADE_FROM = 0.66  # where the blade leaves the habaki, studs in front of the fist
BLADE_LEN = 3.4  # habaki to the start of the point
POINT_LEN = 0.38  # the kissaki
SORI = 0.14  # how far the curve carries the point back toward the mune


def blade_point(s):
    """The blade's centreline s studs along from the habaki (Handle space)."""
    return np.array([0.0, -SORI * (s / BLADE_LEN) ** 2, -(BLADE_FROM + s)])


def blade_tilt(s):
    """How far (deg) the blade has turned toward the mune s studs along."""
    return math.degrees(math.atan(2 * SORI * s / BLADE_LEN**2))


def _katana_parts():
    parts = [
        # name, class, size, position, rotation, colour, material, reflectance
        ("Handle", "Part", (0.2, 0.26, 1.82), (0, 0, 0.47), None, ITO, "Fabric", 0),
        ("Same", "Part", (0.17, 0.27, 1.6), (0, 0, 0.47), None, SAME, "SmoothPlastic", 0),
        ("Kashira", "Part", (0.23, 0.29, 0.1), (0, 0, 1.42), None, IRON, "Metal", 0.05),
        ("MenukiR", "Part", (0.03, 0.09, 0.26), (0.105, 0, 0.55), None, GOLD, "Metal", 0.2),
        ("MenukiL", "Part", (0.03, 0.09, 0.26), (-0.105, 0, 0.45), None, GOLD, "Metal", 0.2),
        ("Tsuba", "Cylinder", (0.07, 0.64, 0.64), (0, 0, -0.5), ry(90), IRON, "Metal", 0.05),
        ("Seppa", "Part", (0.13, 0.3, 0.06), (0, 0, -0.565), None, GOLD, "Metal", 0.2),
        ("Habaki", "Part", (0.11, 0.25, 0.1), (0, 0.0, -BLADE_FROM + 0.05), None, GOLD, "Metal", 0.25),
    ]
    n = 4
    for i in range(n):
        s = (i + 0.5) * BLADE_LEN / n
        rot = rx(-blade_tilt(s))
        pos = blade_point(s)
        length = BLADE_LEN / n + 0.02
        parts.append(("Blade%d" % (i + 1), "Part", (0.07, 0.2, length), tuple(pos), rot, STEEL, "Metal", 0.2))
        parts.append(("Hamon%d" % (i + 1), "Part", (0.075, 0.05, length), tuple(pos + rot @ np.array([0, 0.085, 0])),
                      rot, HAMON, "Metal", 0.3))
    s = BLADE_LEN + POINT_LEN / 2
    rot = rx(-blade_tilt(BLADE_LEN))
    # one wedge: flat along the mune (-Y), the edge sweeping up into the point (fukura)
    parts.append(("Kissaki", "WedgePart", (0.07, 0.2, POINT_LEN), tuple(blade_point(s)), rot, STEEL, "Metal", 0.2))
    return parts


KATANA_PARTS = _katana_parts()
TIP_POINT = blade_point(BLADE_LEN + POINT_LEN) + rx(-blade_tilt(BLADE_LEN)) @ np.array([0, -0.1, 0])
TIP = float(np.linalg.norm(TIP_POINT))  # fist to the point

# worn at the left hip, edge up, through the belt: the mouth (koiguchi) at the front of the hip, the
# saya running back, down and out past the left thigh, the tsuka angled in across the belly (Torso space)
KOIGUCHI = np.array([-0.85, -0.74, -0.6])
SHEATH_DIR = unit([-0.42, -0.36, 0.83])  # the way the blade points in the saya


def _saya_parts():
    parts = [("Koiguchi", "Part", (0.2, 0.34, 0.1), tuple(blade_point(0.03)), None, HORN, "SmoothPlastic", 0.1)]
    n = 4
    length = BLADE_LEN + POINT_LEN + 0.12
    for i in range(n):
        s = 0.08 + (i + 0.5) * length / n
        parts.append(("Saya%d" % (i + 1), "Part", (0.18, 0.32, length / n + 0.02), tuple(blade_point(s)),
                      rx(-blade_tilt(s)), LACQUER, "SmoothPlastic", 0.15))
    s = 0.08 + length + 0.05
    parts.append(("Kojiri", "Part", (0.19, 0.33, 0.1), tuple(blade_point(s)), rx(-blade_tilt(s)), HORN,
                  "SmoothPlastic", 0.1))
    return parts


SAYA_PARTS = _saya_parts()  # in the sheathed sword's Handle space


def _sheath_cf():
    """Sheathed Handle CFrame (Torso space): in the saya, edge up."""
    z = -SHEATH_DIR
    y = np.array([0.0, 1.0, 0.0]) - z * z[1]
    y /= np.linalg.norm(y)
    x = np.cross(y, z)
    hilt = KOIGUCHI - (BLADE_FROM - 0.03) * SHEATH_DIR
    return cf(hilt, np.column_stack([x, y, z]))


SHEATH = _sheath_cf()


def grip_pass(c, baked, weight=None):
    """Lock the left fist onto the tsuka, LEFT_GRIP behind the right (see twohanded)."""
    return _grip_pass(c, baked, LEFT_GRIP, weight)


def tip_speeds(c, baked):
    """Speed (studs/s, root space) of the actual point, which sits a little off the grip's line."""
    tips = []
    for f in range(len(baked["Root"])):
        h = joint_cf("Root", baked["Root"][f]) @ handle_cf(baked["RArm"][f], baked["Handle"][f])
        tips.append((h @ np.append(TIP_POINT, 1.0))[:3])
    v = np.zeros(len(tips))
    v[1:] = np.linalg.norm(np.diff(np.array(tips), axis=0), axis=1) * FPS
    return v


# --------------------------------------------------------------------------- chudan / idle
# chudan-no-kamae: both hands on the tsuka in front of the navel, the point at the opponent's throat,
# the body turned a touch left as if the right foot were forward (the legs are the walk's)
GUARD_ROOT = [-4, 10, 0, 0, -0.18, 0]
GUARD = (np.array([0.12, -0.5, -1.4]), heading(0, 28), heading(0, -62))  # fist, blade, edge (world)
GUARD_NECK = [-4, 0, 0]
IDLE_FRAMES = 125  # 2.083s, one breath per loop, like the reference idles


def guard_keys(c, f=0, k="ease"):
    c.key("Root", f, GUARD_ROOT, k)
    c.key("Neck", f, GUARD_NECK, k)
    c.key("LArm", f, [0, 0, 0, 0, 0, 0], k)  # replaced by the grip


def idle():
    """Chudan, breathing: the torso rocking ~1 deg and bobbing with the breath, the head following,
    the point drifting a little."""
    c = Clip("idle", IDLE_FRAMES, hit=None, arm="RArm", joints=JOINTS)
    c.smooth = False
    c.loop = True
    guard_keys(c)
    roots = root_path(c)
    fly(c, roots, 0, *GUARD, "ease")
    baked = c.bake()
    t = np.arange(IDLE_FRAMES + 1) / IDLE_FRAMES * 2 * math.pi
    phase = 2 * math.pi * 0.16

    def wave(lag=0.0):
        return np.sin(t - phase - 2 * math.pi * lag / (IDLE_FRAMES / FPS))

    baked["Root"][:, 0] += 1.0 * wave()
    baked["Root"][:, 4] += -0.012 * np.sin(t - phase - math.pi / 2)
    baked["Neck"][:, 0] += 1.2 * wave(0.2)
    baked["RArm"][:, 0] -= 1.6 * wave(0.1)
    baked["Handle"][:, 0] += 1.2 * wave(0.25)
    c.baked = tame(grip_pass(c, baked))
    return c


# --------------------------------------------------------------------------- the M1s
def m1_1():
    """Kesa-giri: the point dips, the sword is thrown up over the right shoulder with the blade
    pointing back as the body winds right; a beat, then the hands cut down on the diagonal through
    the target from high right to low left, the point whipping behind them and the body whipping
    ~120 deg left; it finishes low by the left knee and holds."""
    c = Clip("m1-1", 48, hit=24, arm="RArm", joints=JOINTS)
    c.slerp = {"RArm", "Handle"}
    guard_keys(c)
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(4, [-2, 18, 0, 0, -0.17, 0.02], "decel")
    R(12, [6, -38, 8, 0, -0.24, 0.22], "coil")
    R(16, [7, -42, 9, 0, -0.26, 0.24], "slowin")
    R(27, [-16, 76, -10, 0, -0.38, -0.36], "whip")
    R(31, [-17, 82, -11, 0, -0.39, -0.39], "stop")
    R(38, [-12, 66, -6, 0, -0.32, -0.26], "settle")
    R(48, [-13, 68, -6, 0, -0.33, -0.26], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(12, [-6, 0, -5], "coil")
    N(17, [-5, 0, -5], "slowin")
    N(23, [-13, 0, 8], "snap")
    N(28, [-15, 0, 10], "stop")
    N(38, [-10, 0, 6], "settle")
    N(48, [-11, 0, 6], "drift")
    m1_path(
        c, GUARD,
        pre=[(4, [0.35, -0.32, -1.5], heading(-10, 48), "decel"),
             (12, [0.95, 1.45, 0.7], heading(195, 8), "coil"),  # up over the right shoulder, blade back
             (16, [1.0, 1.55, 0.8], heading(200, 2), "slowin")],
        arc=(16, 31, [0.15, 0.15, -1.95], [-1.35, -0.95, -0.75], "whip"),
        post=[(38, [-1.25, -0.9, -0.72], heading(-122, -34), "settle"),
              (48, [-1.25, -0.91, -0.71], heading(-121, -35), "drift")],
        lag=(16.0, -3.0),
    )
    c.baked = tame(grip_pass(c, c.bake()))
    return c


def m1_2():
    """Kiri-age, the rising cut back the other way: the hands drop to the left hip with the blade
    pointing back and down as the body winds left; a beat, then the cut rises on the diagonal through
    the target from low left to high right, the body whipping ~120 deg right, and finishes with the
    sword up by the right shoulder."""
    c = Clip("m1-2", 48, hit=24, arm="RArm", joints=JOINTS)
    c.slerp = {"RArm", "Handle"}
    guard_keys(c)
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(4, [-2, 4, 0, 0, -0.17, 0.0], "decel")
    R(12, [-4, 50, -6, 0, -0.3, 0.16], "coil")
    R(16, [-5, 54, -7, 0, -0.32, 0.18], "slowin")
    R(25, [8, -70, 9, 0, -0.26, -0.3], "whip")
    R(28, [9, -76, 10, 0, -0.25, -0.32], "stop")
    R(38, [5, -60, 6, 0, -0.24, -0.22], "settle")
    R(48, [5, -62, 6, 0, -0.25, -0.22], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(12, [-10, 0, 6], "coil")
    N(17, [-10, 0, 6], "slowin")
    N(24, [-4, 0, -8], "snap")
    N(29, [-2, 0, -10], "stop")
    N(38, [-4, 0, -6], "settle")
    N(48, [-4, 0, -6], "drift")
    m1_path(
        c, GUARD,
        pre=[(4, [0.0, -0.48, -1.55], heading(10, 34), "decel"),
             (12, [-1.05, -0.85, 0.3], heading(200, -30), "coil"),  # down by the left hip, blade back
             (16, [-1.1, -0.9, 0.4], heading(205, -34), "slowin")],
        arc=(16, 27, [0.05, -0.15, -1.95], [1.35, 1.3, -0.55], "whip"),
        post=[(38, [1.25, 1.25, -0.5], heading(62, 40), "settle"),
              (48, [1.25, 1.24, -0.5], heading(63, 39), "drift")],
        lag=(16.0, -3.0),
    )
    c.baked = tame(grip_pass(c, c.bake()))
    return c


def m1_3():
    """Finisher, shomen-giri: a dip, then the sword goes up into jodan, overhead with the blade
    pointing up and back, as the body rises and leans back; a beat, then the whole body lunges
    forward and drops as the sword comes over the top and straight down the centre through the
    target, stopping level at the target's middle, and holds there (zanshin)."""
    c = Clip("m1-3", 64, hit=30, arm="RArm", joints=JOINTS)
    c.slerp = {"RArm", "Handle"}
    guard_keys(c)
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(5, [-3, 14, 0, 0, -0.2, 0.02], "decel")
    R(16, [12, 4, 1, 0, -0.06, 0.28], "coil")  # rises into jodan, leaning back
    R(22, [13, 3, 1, 0, -0.05, 0.3], "slowin")
    R(30, [-26, 6, -1, 0, -0.48, -0.75], "whip")  # lunges forward and drops through the cut
    R(34, [-28, 6, -1, 0, -0.5, -0.8], "stop")
    R(50, [-22, 6, -1, 0, -0.44, -0.66], "settle")
    R(64, [-23, 6, -1, 0, -0.45, -0.66], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(5, [-6, 0, 0], "decel")
    N(16, [8, 0, 0], "coil")
    N(23, [5, 0, 0], "slowin")
    N(30, [-10, 0, 2], "snap")
    N(36, [-2, 0, 2], "stop")  # head up, eyes on the target over the blade
    N(50, [-4, 0, 1], "settle")
    N(64, [-4, 0, 1], "drift")
    m1_path(
        c, GUARD,
        pre=[(5, [0.15, -0.6, -1.45], heading(0, 18), "decel"),
             (16, [0.2, 2.45, 0.1], heading(180, 35), "coil"),  # jodan
             (22, [0.2, 2.55, 0.2], heading(180, 28), "slowin")],
        arc=(22, 32, [0.15, 1.0, -2.3], [0.15, -0.5, -2.05], "whip"),
        post=[(50, [0.15, -0.45, -2.0], heading(0, 2), "settle"),
              (64, [0.15, -0.46, -2.0], heading(0, 1.5), "drift")],
        lag=(16.0, 0.0),
        blade_end=heading(0, 2),
    )
    c.baked = tame(grip_pass(c, c.bake()))
    return c


M1S = [m1_1, m1_2, m1_3]


# --------------------------------------------------------------------------- running / aerial attacks
RUN = [-18, 0, 0, 0, -0.2, 0]


def running_attack():
    """A dash cut off a sprint: running with the katana held low in the right hand, the point
    trailing behind, the left foot plants and the body winds right as the left hand takes the
    tsuka, with the blade cocked back flat by the right hip; then one flat cut sweeps from the right
    across the front at waist height and on round to the left as the body whips ~145 deg into a
    deep lunge, right foot forward, and holds."""
    c = Clip("running attack", 58, hit=24, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "Handle", "LArm"}
    c.neck_auto = False
    wind = [-8, -70, 6, 0, -0.45, 0.15]
    lunge = [-20, 72, -8, 0, -0.66, -0.45]
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(0, RUN)
    R(8, wind, "coil")  # plants and winds right
    R(12, [-9, -74, 7, 0, -0.48, 0.17], "slowin")
    R(26, lunge, "whip")  # whips left into a deep lunge
    R(30, [-21, 78, -9, 0, -0.68, -0.48], "stop")
    R(44, [-16, 64, -6, 0, -0.6, -0.38], "settle")
    R(58, [-17, 66, -6, 0, -0.61, -0.38], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(0, [-10, 0, 0])
    N(8, [-12, 50, -4], "coil")  # eyes stay on the target as the body winds away
    N(14, [-12, 54, -4], "slowin")
    N(24, [-14, -40, 6], "snap")  # then follow the cut round
    N(30, [-14, -58, 6], "stop")
    N(44, [-12, -50, 5], "settle")
    N(58, [-12, -52, 5], "drift")
    m1_path(
        c, (np.array([1.25, -0.85, 0.75]), heading(160, -22), heading(160, 68)),  # trailing low behind
        pre=[(8, [1.45, -0.15, 0.6], heading(172, 2), "coil"),  # cocked flat back by the right hip
             (12, [1.5, -0.1, 0.7], heading(176, 0), "slowin")],
        arc=(12, 28, [0.1, -0.2, -2.1], [-1.6, -0.35, -0.55], "whip"),
        post=[(44, [-1.5, -0.4, -0.5], heading(-112, -14), "settle"),
              (58, [-1.5, -0.41, -0.5], heading(-111, -15), "drift")],
        lag=(16.0, -3.0),
    )
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)  # noqa: E731
    L(0, [40, 0, -8, 0, 0, 0])  # the running arm swing, until it takes the tsuka
    L(5, [30, -6, -12, 0, 0, -0.05])
    for leg, f, v, k in (
        ("RLeg", 0, world_leg("RLeg", RUN, 32, 4), "ease"),
        ("LLeg", 0, world_leg("LLeg", RUN, -28, 4), "ease"),
        ("RLeg", 8, world_leg("RLeg", wind, -28, 8, -30), "coil"),  # left foot planted ahead
        ("LLeg", 8, world_leg("LLeg", wind, 34, 8, -20), "coil"),
        ("RLeg", 26, world_leg("RLeg", lunge, 46, 10, 10), "whip"),  # right foot steps through
        ("LLeg", 26, world_leg("LLeg", lunge, -40, 10, 30), "whip"),
        ("RLeg", 30, world_leg("RLeg", lunge, 48, 10, 10), "stop"),
        ("LLeg", 30, world_leg("LLeg", lunge, -42, 10, 30), "stop"),
        ("RLeg", 44, world_leg("RLeg", lunge, 44, 9, 10), "settle"),
        ("LLeg", 44, world_leg("LLeg", lunge, -38, 9, 30), "settle"),
        ("RLeg", 58, world_leg("RLeg", lunge, 44, 9, 10), "drift"),
        ("LLeg", 58, world_leg("LLeg", lunge, -38, 9, 30), "drift"),
    ):
        c.key(leg, f, v, k)
    c.baked = tame(grip_pass(c, c.bake(), ramp(c.frames + 1, 5, 11)))
    return c


def aerial_attack():
    """In the air: the knees tuck and the body leans back as the sword goes up into jodan; a beat,
    then the body jack-knifes forward and the legs drop as the sword comes over the top and straight
    down through the target below."""
    c = Clip("aerial attack", 52, hit=27, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "Handle"}
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(0, [-4, 0, 0, 0, 0, 0])
    R(12, [18, -10, 3, 0, 0.32, 0.26], "coil")
    R(18, [20, -12, 4, 0, 0.35, 0.28], "slowin")
    R(29, [-38, 6, -3, 0, -0.45, -0.45], "whip")
    R(33, [-40, 7, -3, 0, -0.47, -0.48], "stop")
    R(44, [-33, 5, -2, 0, -0.4, -0.4], "settle")
    R(52, [-34, 5, -2, 0, -0.41, -0.4], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(0, [-6, 0, 0])
    N(12, [-14, 0, 0], "coil")
    N(18, [-16, 0, 0], "slowin")
    N(26, [6, 0, 2], "snap")
    N(31, [12, 0, 2], "stop")  # head up, eyes on the target below
    N(44, [9, 0, 1], "settle")
    N(52, [9, 0, 1], "drift")
    m1_path(
        c, (np.array([0.3, -0.35, -1.4]), heading(0, 30), heading(0, -60)),
        pre=[(12, [0.25, 2.4, 0.4], heading(180, 30), "coil"),  # jodan
             (18, [0.25, 2.5, 0.5], heading(180, 22), "slowin")],
        arc=(18, 32, [0.2, 0.4, -2.25], [0.2, -1.6, -1.25], "whip"),
        post=[(44, [0.2, -1.55, -1.3], heading(0, -42), "settle"),
              (52, [0.2, -1.56, -1.3], heading(0, -43), "drift")],
        lag=(16.0, 0.0),
        blade_end=heading(0, -40),
    )
    G = lambda leg, f, v, k="ease": c.key(leg, f, v, k)  # noqa: E731
    G("RLeg", 0, [8, 0, 4, 0, 0, 0])
    G("LLeg", 0, [-8, 0, -4, 0, 0, 0])
    G("RLeg", 12, [72, 0, 8, 0, 0, 0], "coil")  # knees tucked
    G("LLeg", 12, [62, 0, -8, 0, 0, 0], "coil")
    G("RLeg", 18, [76, 0, 8, 0, 0, 0], "slowin")
    G("LLeg", 18, [66, 0, -8, 0, 0, 0], "slowin")
    G("RLeg", 28, [12, 0, 8, 0, 0, 0], "snap")  # legs drop under the body to land
    G("LLeg", 28, [48, 0, -6, 0, 0, 0], "snap")
    G("RLeg", 42, [16, 0, 6, 0, 0, 0], "settle")
    G("LLeg", 42, [44, 0, -6, 0, 0, 0], "settle")
    G("RLeg", 52, [16, 0, 6, 0, 0, 0], "drift")
    G("LLeg", 52, [44, 0, -6, 0, 0, 0], "drift")
    c.baked = tame(grip_pass(c, c.bake()))
    return c


EXTRA = [running_attack, aerial_attack]

# --------------------------------------------------------------------------- unsheathe (iai)
GRAB_FRAME = 12
PULLED_FRAME = 20
DRAW_PULL = 1.8  # studs drawn straight out of the saya by PULLED_FRAME
CUT = [  # (frame, fist, blade) the draw-cut runs through, world space; it stops dead on the last
    (24, (0.5, -0.05, -1.95), heading(-70, -4)),  # out of the saya, the point sweeping out on the left
    (27, (1.35, 0.0, -1.55), heading(18, -3)),  # through the front: the cut
    (31, (1.95, -0.08, -0.55), heading(102, -8)),  # one-handed, out to the right, and stopped
]
RETURN = [  # (frame, fist, blade) back into chudan, the left hand joining; starts and ends at rest
    (43, (0.85, 0.55, -1.45), heading(28, 52)),
    (51, (0.25, -0.38, -1.45), heading(4, 34)),
    (57, tuple(GUARD[0]), tuple(GUARD[1])),
]


def unsheathe():
    """Iai: the right hand crosses to the tsuka at the left hip and the left hand takes the saya's
    mouth as the body sinks and turns right (the sword stays in the saya until the grab;
    "Sheathe/Unsheathe" fires on it). The blade is drawn straight out, picking up speed, as the
    hips turn back left and pull the saya away, and the moment it is out it cuts flat across the
    front one-handed (nukitsuke), the body whipping right, and stops dead with the arm out to the
    right side. Then the sword comes back up in front, the left hand takes the tsuka, and it settles
    into chudan. From the pull on, the sword follows smooth splines in world space."""
    c = Clip("unsheathe", 66, hit=None, arm="RArm", joints=JOINTS)
    c.slerp = {"RArm", "Handle"}
    c.peak = 27
    c.markers = {GRAB_FRAME: ["Sheathe/Unsheathe"]}
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(0, [0, 0, 0, 0, 0, 0])
    R(GRAB_FRAME, [-8, -24, -3, 0, -0.24, 0.0], "coil")  # sinks and turns right, hilt to hand
    R(PULLED_FRAME, [-10, 8, -2, 0, -0.3, -0.1], "accel")  # the hips turn back, pulling the saya away
    R(28, [-8, -36, 4, 0, -0.32, -0.2], "whip")  # whips right through the cut
    R(31, [-8, -40, 4, 0, -0.32, -0.21], "stop")
    R(46, [-6, -6, 1, 0, -0.24, -0.06], "ease")
    R(56, GUARD_ROOT, "settle")
    R(66, GUARD_ROOT, "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(0, [0, 0, 0])
    N(GRAB_FRAME, [-8, 0, 2], "coil")
    N(26, [-6, 0, -4], "snap")
    N(31, [-6, 0, -5], "stop")
    N(56, GUARD_NECK, "settle")
    N(66, GUARD_NECK, "drift")
    hilt = SHEATH[:3, 3]
    out_dir = -SHEATH_DIR  # out of the saya
    arm6, _ = aim(hilt + np.array([0.35, -0.15, -0.25]), out_dir)  # reaching across for the tsuka
    c.key("RArm", 0, [0, 0, 0, 0, 0, 0])
    c.key("RArm", 6, arm6, "decel")
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)  # noqa: E731
    hold_saya = left_on(KOIGUCHI + np.array([-0.08, 0.02, -0.08])).tolist()
    L(0, [0, 0, 0, 0, 0, 0])
    L(GRAB_FRAME, hold_saya, "coil")
    L(26, hold_saya, "ease")
    L(40, [36, -18, -26, 0.1, 0.05, -0.25], "ease")  # comes up to meet the tsuka
    roots = root_path(c)

    def slid(f):  # the sword in the saya, drawn s studs out of it (Torso space)
        u = max(0.0, (f - GRAB_FRAME) / (PULLED_FRAME - GRAB_FRAME))
        sword = SHEATH.copy()
        sword[:3, 3] = hilt + out_dir * DRAW_PULL * u**3  # picks up speed all the way, into the cut
        return sword

    def world(f, m):
        return joint_cf("Root", roots[f]) @ m

    # the cut: one spline from the pull to a dead stop, carrying the pull's speed on into it
    w0, w1 = world(PULLED_FRAME, slid(PULLED_FRAME)), world(PULLED_FRAME - 1, slid(PULLED_FRAME - 1))
    tip0, tip1 = (w0 @ np.append(TIP_POINT, 1.0))[:3], (w1 @ np.append(TIP_POINT, 1.0))[:3]
    frames = [PULLED_FRAME] + [f for f, _, _ in CUT]
    hands = [w0[:3, 3]] + [np.asarray(h, float) for _, h, _ in CUT]
    tips = [tip0] + [h + TIP * unit(b) for (_, _, b), h in zip(CUT, hands[1:], strict=True)]
    cut_hand = spline(frames, hands, w0[:3, 3] - w1[:3, 3], np.zeros(3))
    cut_tip = spline(frames, tips, tip0 - tip1, np.zeros(3))
    # and back: a second spline from the stop into chudan
    back = [CUT[-1]] + RETURN
    back_hand = spline([f for f, _, _ in back], [np.asarray(h, float) for _, h, _ in back], np.zeros(3), np.zeros(3))
    back_tip = spline([f for f, _, _ in back], [np.asarray(h, float) + TIP * unit(b) for _, h, b in back],
                      np.zeros(3), np.zeros(3))
    edge, target, prev_tip = None, {}, None
    for f in range(GRAB_FRAME, c.frames + 1):
        if f <= PULLED_FRAME:
            m = world(f, slid(f))
            hand, blade, edge = m[:3, 3], -m[:3, 2], m[:3, 1]
        else:
            path_hand, path_tip = (cut_hand, cut_tip) if f <= CUT[-1][0] else (back_hand, back_tip)
            g = min(f, back[-1][0])
            hand = path_hand(g)
            tip = path_tip(g)
            blade = unit(tip - hand)
            edge = unit(edge - blade * float(edge @ blade))  # carried along without twisting...
            moving = tip - prev_tip
            moving = moving - blade * float(moving @ blade)
            speed = float(np.linalg.norm(moving)) * FPS
            if f <= CUT[-1][0] and speed > 1e-6:  # ...turning to lead into the cut while it moves fast
                edge = slerp(edge, unit(moving), 0.6 * smoothstep((speed - 20) / 60))
        prev_tip = hand + TIP * blade
        guard_edge = unit(GUARD[2] - blade * float(GUARD[2] @ blade))
        e = slerp(edge, guard_edge, smoothstep((f - 33) / 20)) if f > 33 else edge
        y = unit(e - blade * float(e @ blade))
        fly(c, roots, f, hand, blade, y, "coil" if f == GRAB_FRAME else "linear")
        target[f] = inv(joint_cf("Root", roots[f])) @ cf(hand, np.column_stack([np.cross(y, -blade), y, -blade]))
    baked = c.bake()
    # the arm is smoothed, but the sword keeps to its path exactly: in the saya until the grab
    # whatever the arm is doing, drawn straight out of it, then along the splines (the wrist takes up
    # the difference)
    for f in range(c.frames + 1):
        t = inv(GRIP) @ inv(joint_cf("RArm", baked["RArm"][f])) @ (slid(f) if f <= PULLED_FRAME else target[f])
        baked["Handle"][f] = np.array(from_transform("Handle", t[:3, 3], t[:3, :3]))
    c.baked = tame(grip_pass(c, baked, ramp(c.frames + 1, 40, 50)))
    return c


# --------------------------------------------------------------------------- full-string preview
STRING_NAME = "m1 string (1,2,1,2,3)"
STRING_ORDER = ["m1-1", "m1-2", "m1-1", "m1-2", "m1-3"]
STRING_FADE = 0.15
STRING_END_FADE = 0.3


def _baked(c):
    b = getattr(c, "baked", None)
    if b is None:
        b = c.bake()
        c.baked = b
    return c, b


# --------------------------------------------------------------------------- rig + export
def add_katana(rig):
    """The katana in the right hand on a "Handle" Motor6D, its saya welded at the left hip."""
    torso, rarm = _child(rig, "Part", "Torso"), _child(rig, "Part", "Right Arm")
    for joint, motor in (("RArm", "Right Shoulder"), ("LArm", "Left Shoulder"), ("Neck", "Neck"),
                         ("RLeg", "Right Hip"), ("LLeg", "Left Hip")):
        m = _child(rig, "Motor6D", motor)
        assert np.allclose(_cf_of(m, "C0"), MOTORS[joint][0], atol=1e-4), motor
        assert np.allclose(_cf_of(m, "C1"), MOTORS[joint][1], atol=1e-4), motor
    t_world, a_world = _cf_of(torso), _cf_of(rarm)
    handle_world = a_world @ GRIP
    sword = _model("Katana")
    handle = None
    for name, cls, size, pos, rot, col, mat, refl in KATANA_PARTS:
        local = cf(pos, rot)
        if name == "Handle":
            local = cf((0, 0, 0))  # the Handle part's origin is the right fist; the tsuka is "Tsuka"
        part = _part(rarm, name, cls, size, handle_world @ local, col, mat, refl)
        sword.append(part)
        if name == "Handle":
            handle = part
        else:
            part.append(_joint("Weld", name, handle.get("referent"), part.get("referent"), local, np.eye(4)))
    # the wrapped tsuka itself, as a welded part centred down the grip (the Handle part is the fist point)
    name, cls, size, pos, rot, col, mat, refl = KATANA_PARTS[0]
    tsuka = _part(rarm, "Tsuka", cls, size, handle_world @ cf(pos), col, mat, refl)
    tsuka.append(_joint("Weld", "Tsuka", handle.get("referent"), tsuka.get("referent"), cf(pos), np.eye(4)))
    sword.append(tsuka)
    for name, point in (("SwingBase", blade_point(0.15)), ("SwingTip", blade_point(BLADE_LEN + 0.25))):
        att = ET.SubElement(handle, "Item", {"class": "Attachment", "referent": ref()})  # for CombatVFX.Swing
        aprops = ET.SubElement(att, "Properties")
        prop(aprops, "string", "Name", name)
        _cframe_prop(aprops, "CFrame", cf(point))
    rarm.append(_joint("Motor6D", "Handle", rarm.get("referent"), handle.get("referent"), GRIP, np.eye(4)))
    rig.append(sword)
    saya = _model("Saya")
    for name, cls, size, pos, rot, col, mat, refl in SAYA_PARTS:
        local = SHEATH @ cf(pos, rot)
        part = _part(rarm, name, cls, size, t_world @ local, col, mat, refl)
        part.append(_joint("Weld", name, torso.get("referent"), part.get("referent"), local, np.eye(4)))
        saya.append(part)
    rig.append(saya)


def build(rig_source, out_dir=HERE):
    clips = [idle(), unsheathe()] + [m() for m in M1S] + [m() for m in EXTRA]
    sequences, by_name, data = [], {}, {}
    for c in clips:
        c, baked = _baked(c)
        frames = clip_transforms(c, baked)
        by_name[c.name] = (c, frames)
        data[c.name] = {"hit": c.hit, "frames": c.frames, "loop": c.loop,
                        "channels": {j: np.asarray(baked[j]).tolist() for j in c.joints}}
        speed = tip_speeds(c, baked)
        print("%-15s %3d frames  hit %-4s smoothing %-26s tip peak %4.0f studs/s @f%d" % (
            c.name, c.frames, c.hit, c.smoothing, speed.max(), int(speed.argmax())))
        sequences.append(sequence_xml(c.name, frames, c.markers, loop=c.loop))
    guard = by_name["idle"][1][0]
    cancel = {n: (by_name[n][0].hit / FPS + 0.15) for n in ("m1-1", "m1-2")}
    string_frames, string_hits = build_string(
        [by_name[n] for n in STRING_ORDER], cancel, STRING_FADE, STRING_END_FADE, guard, guard)
    sequences.append(sequence_xml(STRING_NAME, string_frames, string_hits))
    with open(os.path.join(out_dir, "katana_data.json"), "w") as fh:
        json.dump(data, fh)
    rig, saves = reference_rig(rig_source, "Katana Rig")
    add_katana(rig)
    for s in sequences:
        saves.append(s)
    root = ET.Element("roblox", {"version": "4"})
    root.append(rig)
    out = os.path.join(out_dir, "KatanaCombo.rbxmx")
    ET.ElementTree(root).write(out, encoding="utf-8", xml_declaration=False)
    print("tip %.2f studs from the fist; string cancels: %s" % (TIP, {k: round(v, 3) for k, v in cancel.items()}))
    print("wrote", out)
    return out


if __name__ == "__main__":
    build(sys.argv[1])
