"""R6 one-handed sword set, authored in the style of the reference animations (ANIMSFORCLAUDE.rbxm).

Clips: idle (looped), unsheathe, m1-1 (forehand), m1-2 (backhand), m1-3 (finisher), the running and
aerial attacks, the abilities in sword_abilities.py (heavy rising slash, spinning slash), and
"m1 string (1,2,1,2,3)", which chains the M1s the way the game plays them, to preview the string.

Weapon conventions copied from the reference weapon rigs (dagger rig, kareemandbeast, pistol rig):
  * The weapon is its own model whose "Handle" part hangs off a Motor6D called "Handle" inside the
    Right Arm (C0 at the fist, no rotation), so the blade points straight out of the fist.
  * Every clip keys the Handle pose under the Right Arm. The M1s keep the wrist all but locked; the
    unsheathe animates it to hold the sword in the scabbard until the hand grabs it, and fires a
    "Sheathe/Unsheathe" marker at the grab, like the reference equip.
  * Every clip keys the legs at Weight 0, so the walk (or whatever else is playing) drives them.
  * The idle loops, is 2.083s long and breathes once per loop, like the reference idles.
"""

import json
import math
import os
import sys
import copy
import xml.etree.ElementTree as ET

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from animkit import (  # noqa: E402
    world_leg,
    FPS,
    SMOOTHNESS,
    Clip,
    angular_jerk,
    curve,
    build_string,
    clip_transforms,
    euler_yxz,
    from_transform,
    prop,
    ref,
    reference_rig,
    sequence_xml,
    smoothstep,
    to_transform,
)

HERE = os.path.dirname(os.path.abspath(__file__))
JOINTS = ("Root", "Neck", "RArm", "LArm", "Handle")

# --------------------------------------------------------------------------- R6 + weapon geometry
ROOT_R = np.array([[-1, 0, 0], [0, 0, 1], [0, 1, 0]], float)
RIGHT_R = np.array([[0, 0, 1], [0, 1, 0], [-1, 0, 0]], float)
LEFT_R = np.array([[0, 0, -1], [0, 1, 0], [1, 0, 0]], float)


def cf(pos=(0, 0, 0), rot=None):
    m = np.eye(4)
    m[:3, :3] = np.eye(3) if rot is None else rot
    m[:3, 3] = pos
    return m


def inv(m):
    r = m[:3, :3].T
    return cf(-r @ m[:3, 3], r)


MOTORS = {  # standard R6 Motor6D C0 / C1 (checked against the reference rig in build())
    "Root": (cf((0, 0, 0), ROOT_R), cf((0, 0, 0), ROOT_R)),
    "Neck": (cf((0, 1, 0), ROOT_R), cf((0, -0.5, 0), ROOT_R)),
    "RArm": (cf((1, 0.5, 0), RIGHT_R), cf((-0.5, 0.5, 0), RIGHT_R)),
    "LArm": (cf((-1, 0.5, 0), LEFT_R), cf((0.5, 0.5, 0), LEFT_R)),
    "RLeg": (cf((1, -1, 0), RIGHT_R), cf((0.5, 1, 0), RIGHT_R)),
    "LLeg": (cf((-1, -1, 0), LEFT_R), cf((-0.5, 1, 0), LEFT_R)),
}
GRIP = cf((0, -0.95, 0))  # Handle Motor6D C0 inside the Right Arm: the fist; C1 is identity
TIP = 4.245  # studs from the grip centre to the point, along the Handle's -Z


def joint_cf(joint, ch):
    """Part CFrame relative to its parent part for a joint's channels."""
    c0, c1 = MOTORS[joint]
    pos, rot = to_transform(joint, ch)
    return c0 @ cf(pos, rot) @ inv(c1)


def rz(deg):
    a = math.radians(deg)
    return np.array([[math.cos(a), -math.sin(a), 0], [math.sin(a), math.cos(a), 0], [0, 0, 1]])


# Sword parts in Handle space (grip centre at the origin, blade along -Z, edges up/down at rest).
STEEL, DARK, LEATHER = (200, 205, 212), (74, 70, 68), (52, 36, 26)
SWORD_PARTS = [
    # name, class, size, position, rotation, colour, material, reflectance
    ("Handle", "Part", (0.24, 0.24, 0.95), (0, 0, 0), None, LEATHER, "Fabric", 0),
    ("Pommel", "Ball", (0.36, 0.36, 0.36), (0, 0, 0.62), None, DARK, "Metal", 0.05),
    ("Guard", "Part", (0.26, 1.3, 0.22), (0, 0, -0.585), None, DARK, "Metal", 0.05),
    ("Blade", "Part", (0.1, 0.42, 3.0), (0, 0, -2.195), None, STEEL, "Metal", 0.15),
    ("Fuller", "Part", (0.11, 0.09, 2.5), (0, 0, -1.99), None, (140, 145, 152), "Metal", 0.1),
    ("TipTop", "WedgePart", (0.1, 0.21, 0.55), (0, 0.105, -3.97), None, STEEL, "Metal", 0.15),
    ("TipBottom", "WedgePart", (0.1, 0.21, 0.55), (0, -0.105, -3.97), rz(180), STEEL, "Metal", 0.15),
]
# Scabbard parts in the sheathed sword's Handle space (the same axes as the sword).
SCABBARD_PARTS = [
    ("Scabbard", "Part", (0.2, 0.54, 3.6), (0, 0, -2.52), None, LEATHER, "Fabric", 0),
    ("Locket", "Part", (0.26, 0.62, 0.24), (0, 0, -0.82), None, DARK, "Metal", 0.05),
    ("Chape", "Part", (0.24, 0.58, 0.3), (0, 0, -4.2), None, DARK, "Metal", 0.05),
]

# Where the sword sits when sheathed, in Torso space: the hilt rides at the front of the left hip
# and the scabbard runs back and down along the outside of the left thigh (a cross-draw, like the
# reference equip). Picked by a search for the shortest reach that clears the left arm and leg.
SHEATH_HILT = np.array([-1.05, -0.85, -0.7])
SHEATH_DIR = np.array([-0.21, -0.48, 0.85])
GRAB_STRETCH = 1.2  # studs the arm may slide out of the shoulder to reach the hilt (reference: up to 2.6)


def _sheath_cf():
    """The sheathed Handle CFrame in Torso space. The sword's roll about its own axis is picked so
    the right hand can reach the grip with the least arm stretch."""
    d = SHEATH_DIR / np.linalg.norm(SHEATH_DIR)
    z = -d
    ref_axis = np.array([0, 1, 0]) - z * z[1]
    ref_axis /= np.linalg.norm(ref_axis)
    best = None
    for deg in range(0, 360, 2):
        a = math.radians(deg)
        y = ref_axis * math.cos(a) + np.cross(z, ref_axis) * math.sin(a)
        x = np.cross(y, z)
        s = cf(SHEATH_HILT, np.column_stack([x, y, z]))
        stretch = np.linalg.norm(grab_channels(s)[3:])
        if best is None or stretch < best[0]:
            best = (stretch, s)
    return best[1]


def grab_channels(handle_cf):
    """Right Arm channels that put the fist exactly on a Handle CFrame given in Torso space."""
    c0, c1 = MOTORS["RArm"]
    arm = handle_cf @ inv(GRIP)
    t = inv(c0) @ arm @ c1
    return np.array(from_transform("RArm", t[:3, 3], t[:3, :3]))


def sheathed_handle(arm_ch):
    """Handle channels that keep the sword in the scabbard for a given Right Arm pose."""
    arm = joint_cf("RArm", arm_ch)
    t = inv(GRIP) @ inv(arm) @ SHEATH
    return np.array(from_transform("Handle", t[:3, 3], t[:3, :3]))


SHEATH = _sheath_cf()
GRAB = grab_channels(SHEATH)
# if the hilt is out of reach the fist stops short and the sword closes the gap into the hand as
# the draw starts, like the reference equip
GRAB[3:] *= min(1.0, GRAB_STRETCH / np.linalg.norm(GRAB[3:]))


def arm(hand, blade):
    """Right Arm channels that put the fist (grip centre) at `hand` with the blade pointing along
    `blade`, both in Torso space (+x right, +y up, -z forward). The wrist is locked like the
    reference M1s, so the blade always leaves the fist at 90 degrees to the arm; of the ways to hold
    it, the one whose arm points from the shoulder to the fist (least stretch) is used."""
    d = np.asarray(blade, float)
    z = -d / np.linalg.norm(d)
    seed = np.array([0.0, 1.0, 0.0]) if abs(z[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    seed = seed - z * (seed @ z)
    seed /= np.linalg.norm(seed)
    best = None
    for deg in range(0, 360, 2):
        a = math.radians(deg)
        y = seed * math.cos(a) + np.cross(z, seed) * math.sin(a)
        ch = grab_channels(cf(hand, np.column_stack([np.cross(y, z), y, z])))
        stretch = np.linalg.norm(ch[3:])
        if best is None or stretch < best[0]:
            best = (stretch, ch)
    return [round(float(v), 4) for v in best[1]]


def torso_dir(world, root):
    """A world-space direction expressed in Torso space for given Root channels."""
    return (joint_cf("Root", root)[:3, :3].T @ np.asarray(world, float)).tolist()


# --------------------------------------------------------------------------- the clips
# Stance (idle, start of every M1, end of the unsheathe): right side a little forward, fist held out
# in front of the chest with the blade standing up, off hand up in a loose guard. This is the
# one-handed version of the reference sword stance (blade upright in front of the chest).
STANCE_ROOT = [-3, 16, 1, 0, -0.18, 0]
STANCE_RARM = arm([0.62, 0.15, -1.6], torso_dir([-0.18, 0.95, -0.25], STANCE_ROOT))
STANCE_LARM = [28, -14, -22, 0.12, 0.02, -0.18]
STANCE_NECK = [-5, 0, 0]


def stance_keys(c):
    c.key("Root", 0, STANCE_ROOT)
    c.key("RArm", 0, STANCE_RARM)
    c.key("LArm", 0, STANCE_LARM)
    c.key("Neck", 0, STANCE_NECK)


def m1_1():
    """Forehand: cocks the sword back over the right shoulder (blade pointing behind), then whips it
    over the top and down across the body from high right to low left, ending across the chest."""
    c = Clip("m1-1", 50, hit=26, arm="RArm", joints=JOINTS)
    c.slerp = {"RArm"}
    stance_keys(c)
    R = lambda f, v, k="ease": c.key("Root", f, v, k)
    R(14, [7, -56, 9, 0, -0.27, 0.34], "coil")
    R(30, [-16, 98, -11, 0, -0.33, -0.38], "whip")
    R(44, [-12, 76, -5, 0, -0.27, -0.12], "settle")
    R(50, [-13, 79, -6, 0, -0.27, -0.1], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)
    N(14, [-9, 0, -4], "coil")
    N(22, [-7, 0, 2], "slowin")
    N(26, [-16, 0, 9], "snap")
    N(30, [-19, 0, 12], "stop")
    N(44, [-13, 0, 8], "settle")
    N(50, [-14, 0, 9], "drift")
    A = lambda f, hand, blade, k="ease": c.key("RArm", f, arm(hand, blade), k)
    A(4, [0.75, 0.0, -1.7], [-0.1, 0.92, -0.38])  # counter-move: blade tips toward the target
    A(9, [1.95, 1.1, -0.45], [0.41, 0.58, 0.7])
    A(14, [1.95, 1.85, 1.1], [-0.34, 0.08, 0.94], "coil")  # cocked behind the right shoulder
    A(21, [1.9, 1.75, 1.25], [-0.49, -0.28, 0.82], "slowin")
    A(24, [2.25, 1.25, -1.05], [0.34, 0.79, 0.52], "snap")  # over the top
    A(26, [2.05, 0.5, -1.85], [0.81, 0.41, 0.41], "armstrike")
    A(29, [0.1, 0.05, -2.1], [0.94, -0.16, -0.29], "stop")  # through the target, across the body
    A(33, [-0.85, 0.02, -1.4], [0.32, 0.12, -0.94], "ease")
    A(44, [-0.4, -0.2, -1.55], [0.47, 0.24, -0.85], "settle")
    A(50, [-0.45, -0.22, -1.55], [0.47, 0.22, -0.85], "drift")
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)
    L(5, [40, -24, -26, 0.16, 0.06, -0.3])
    L(14, [74, -36, -30, 0.26, 0.2, -0.62], "coil")  # reaches toward the target as the body winds
    L(21, [78, -44, -36, 0.26, 0.22, -0.66], "slowin")
    L(26, [16, -14, -40, 0.3, -0.3, 0.48], "snap")  # yanked back to the hip on the whip
    L(30, [4, -8, -38, 0.34, -0.32, 0.56], "stop")
    L(44, [10, -10, -40, 0.32, -0.3, 0.52], "settle")
    L(50, [10, -12, -40, 0.32, -0.31, 0.53], "drift")
    return c


def m1_2():
    """Backhand: the sword arm reaches across and cocks the blade over the left shoulder, then whips
    it back over the top and across from high left to low right, ending out on the right side."""
    c = Clip("m1-2", 50, hit=27, arm="RArm", joints=JOINTS)
    c.slerp = {"RArm"}
    stance_keys(c)
    R = lambda f, v, k="ease": c.key("Root", f, v, k)
    R(14, [9, 78, -7, 0, -0.28, 0.32], "coil")
    R(32, [-17, -114, 10, 0, -0.34, -0.42], "whip")  # keeps turning through the follow-through
    R(46, [-12, -106, 6, 0, -0.28, -0.18], "settle")
    R(50, [-13, -108, 6, 0, -0.28, -0.16], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)
    N(14, [-8, 0, 5], "coil")
    N(22, [-6, 0, -2], "slowin")
    N(27, [-15, 0, -9], "snap")
    N(32, [-18, 0, -12], "stop")
    N(46, [-12, 0, -8], "settle")
    N(50, [-13, 0, -9], "drift")
    A = lambda f, hand, blade, k="ease": c.key("RArm", f, arm(hand, blade), k)
    A(4, [0.5, 0.2, -1.75], [-0.3, 0.9, -0.3])
    A(9, [-1.4, 1.3, -2.12], [-0.31, 0.41, 0.86])
    # cocked behind the left shoulder, held out toward the left side so the arm clears the head
    A(14, [-2.15, 1.61, -0.58], [0.15, -0.11, 0.98], "coil")
    A(22, [-2.59, 1.59, 0.07], [0.45, -0.31, 0.83], "slowin")
    A(25, [-2.77, 1.32, -0.04], [0.07, -0.01, 1.0], "snap")
    A(27, [-1.95, 0.48, -0.88], [-0.63, 0.27, 0.73], "armstrike")
    A(29, [-0.2, -0.1, -2.05], [-0.96, 0.2, 0.2], "decel")
    # follow-through: the blade carries on round to the right side and down before it settles
    A(33, [1.6, -0.15, -1.35], torso_dir([0.92, -0.3, -0.25], [-17, -112, 10, 0, 0, 0]), "decel")
    A(38, [2.0, -0.4, -0.7], torso_dir([0.9, -0.38, 0.22], [-15, -112, 9, 0, 0, 0]), "ease")
    A(46, [1.95, -0.38, -0.72], torso_dir([0.92, -0.34, 0.18], [-12, -106, 6, 0, 0, 0]), "settle")
    A(50, [1.95, -0.39, -0.72], torso_dir([0.92, -0.34, 0.19], [-13, -108, 6, 0, 0, 0]), "drift")
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)
    # the off hand stays down by the side, swinging back a little as the body turns
    L(5, [4, -4, -8, 0.0, 0.0, 0.0])
    L(14, [-8, -6, -12, 0.0, 0.0, 0.06], "coil")
    L(22, [-10, -6, -13, 0.0, 0.0, 0.08], "slowin")
    L(27, [-14, -4, -16, 0.0, 0.0, 0.1], "snap")
    L(32, [-16, -4, -18, 0.0, 0.0, 0.12], "stop")
    L(46, [-10, -3, -13, 0.0, 0.0, 0.08], "settle")
    L(50, [-10, -3, -13, 0.0, 0.0, 0.08], "drift")
    return c


def aim(hand, blade, arm_dir=None, edge=None):
    """Right Arm + Handle channels for a free wrist: the fist sits at `hand` with the arm pointing
    along `arm_dir` (default: from the shoulder to the fist), twisting as little as possible from
    hanging at rest, and the Handle turns the sword in the fist so the blade points along `blade`
    with an edge facing `edge` (default: edges up and down). All in Torso space."""
    c0, c1 = MOTORS["RArm"]
    pivot = c0[:3, 3]
    hand = np.asarray(hand, float)
    a = np.asarray(arm_dir, float) if arm_dir is not None else hand - pivot
    a = a / np.linalg.norm(a)
    rest = np.array([0.0, -1.0, 0.0])
    axis = np.cross(rest, a)
    s, c = np.linalg.norm(axis), float(rest @ a)
    if s < 1e-9:
        rot = np.eye(3)
    else:
        k = axis / s
        kx = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
        rot = np.eye(3) + s * kx + (1 - c) * kx @ kx
    arm_cf = cf(hand - rot @ GRIP[:3, 3], rot)
    t = inv(c0) @ arm_cf @ c1
    arm_ch = from_transform("RArm", t[:3, 3], t[:3, :3])
    z = -np.asarray(blade, float) / np.linalg.norm(blade)
    if edge is not None:
        up = np.asarray(edge, float)
    else:
        up = np.array([0.0, 1.0, 0.0]) if abs(z[1]) < 0.9 else -a
    y = up - z * (up @ z)
    y /= np.linalg.norm(y)
    sword = np.column_stack([np.cross(y, z), y, z])
    handle_ch = from_transform("Handle", np.zeros(3), rot.T @ sword)
    return [round(float(v), 4) for v in arm_ch], [round(float(v), 4) for v in handle_ch]


def m1_3():
    """Finisher: a lunging stab. Draws the sword back by the right side with the point turned toward
    the target and the off hand aiming, holds it loaded, then drives the whole body behind a dead
    straight thrust. Through the thrust the fist travels a straight line in world space and the
    wrist (Handle) keeps the blade pointing down that line, so the point leads all the way; the arm
    shoots out of the shoulder for reach and the lunge is held."""
    c = Clip("m1-3", 66, hit=32, arm="RArm", joints=JOINTS)
    c.slerp = {"RArm", "Handle"}
    stance_keys(c)
    c.key("Handle", 0, [0, 0, 0, 0, 0, 0])
    R = lambda f, v, k="ease": c.key("Root", f, v, k)
    R(16, [6, -40, 6, 0, -0.3, 0.36], "coil")  # turns the right side away, sits back
    R(24, [7, -46, 7, 0, -0.32, 0.42], "slowin")
    R(33, [-20, 40, -8, 0, -0.48, -0.66], "snap")  # drives the right shoulder through the target
    R(37, [-23, 46, -10, 0, -0.5, -0.74], "stop")
    R(52, [-17, 38, -6, 0, -0.44, -0.56], "settle")
    R(66, [-18, 39, -6, 0, -0.45, -0.56], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)
    N(16, [-8, 0, -4], "coil")
    N(24, [-9, 0, -4], "slowin")
    N(30, [-14, 0, 6], "snap")
    N(37, [-16, 0, 8], "stop")
    N(52, [-12, 0, 5], "settle")
    N(66, [-13, 0, 5], "drift")
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)
    L(6, [40, -16, -22, 0.14, 0.06, -0.3])
    L(16, [86, -10, -14, 0.18, 0.26, -0.6], "coil")  # aims at the target
    L(24, [88, -12, -14, 0.18, 0.28, -0.62], "slowin")
    L(30, [-18, -24, -40, 0.2, -0.24, 0.42], "snap")  # thrown back for the lunge
    L(37, [-28, -28, -46, 0.24, -0.28, 0.5], "stop")
    L(52, [-20, -26, -44, 0.22, -0.26, 0.46], "settle")
    L(66, [-20, -27, -44, 0.22, -0.26, 0.47], "drift")

    def A(f, hand, blade, k="ease"):
        arm_ch, handle_ch = aim(hand, blade)
        c.key("RArm", f, arm_ch, k)
        c.key("Handle", f, handle_ch, k)

    # the root's path, to place the fist on the thrust line in world space frame by frame
    path = Clip("root", c.frames, None, "RArm")
    path.keys["Root"] = c.keys["Root"]
    path.neck_auto = path.smooth = False
    roots = path.bake()["Root"]
    torso = lambda f: joint_cf("Root", roots[f])

    chamber = np.array([2.2, 0.0, 0.4])  # out by the right side, clear of the body
    start = (torso(24) @ np.append(chamber, 1))[:3]
    target = np.array([0.8, 0.5, -6.0])  # chest height, straight ahead (the sword side leads)
    line = (target - start) / np.linalg.norm(target - start)
    end = start + line * ((start[2] + 2.4) / -line[2])  # fist ends 2.4 studs in front
    to_torso = lambda f, p: (inv(torso(f)) @ np.append(p, 1))[:3]
    dir_torso = lambda f, d: torso(f)[:3, :3].T @ d

    A(5, [0.75, -0.05, -1.7], torso_dir([0, 0.75, -0.66], STANCE_ROOT))  # counter-move: point dips
    A(16, to_torso(16, start + [0.05, -0.02, -0.25]), dir_torso(16, line), "coil")
    # the arm swings from hanging back at the chamber to pointing down the line; it is turned
    # smoothly with the thrust rather than aimed at the fist, which passes close to the shoulder
    pivot = MOTORS["RArm"][0][:3, 3]
    drawn = (chamber - pivot) / np.linalg.norm(chamber - pivot)

    def swing(out, u):
        """Arm direction a fraction u of the way from drawn back to pointing along `out`."""
        t = min(1.0, max(0.0, u))
        th = math.acos(max(-1.0, min(1.0, float(drawn @ out))))
        return (math.sin((1 - t) * th) * drawn + math.sin(t * th) * out) / math.sin(th)

    reach = {}  # thrust progress along the line, shaped like the reference whip, then held
    for f in range(24, 34):
        reach[f] = curve("whip", (f - 24) / 9)
    for f in range(34, 38):
        reach[f] = 1 + 0.06 * curve("stop", (f - 33) / 4)
    for f in range(38, 53):
        reach[f] = 1.06 - 0.1 * curve("settle", (f - 37) / 15)
    for f in range(53, 67):
        reach[f] = 0.96 + 0.01 * curve("drift", (f - 52) / 14)
    for f, u in reach.items():
        out = dir_torso(f, line)
        arm_ch, handle_ch = aim(to_torso(f, start + (end - start) * u), out, swing(out, u))
        c.key("RArm", f, arm_ch, "linear")
        c.key("Handle", f, handle_ch, "linear")
    # Smoothing the arm and the wrist separately would bow the line, so the thrust is placed exactly
    # on the final torso instead, and smoothed along the line: its progress gets the lightest
    # Gaussian that makes the clip SMOOTHNESS times smoother than the raw keys, like every other clip.
    def place(baked, progress):
        for f, u in progress.items():
            t = joint_cf("Root", baked["Root"][f])
            hand = (inv(t) @ np.append(start + (end - start) * u, 1))[:3]
            out = t[:3, :3].T @ line
            baked["RArm"][f], baked["Handle"][f] = aim(hand, out, swing(out, u))
        return baked

    c.smooth = False
    raw = place(c.bake(), reach)
    c.smooth = True
    smoothed = c.bake()
    frames = sorted(reach)
    u = np.array([reach[f] for f in frames])
    for sigma in np.arange(0.3, 3.01, 0.1):
        r = int(math.ceil(3 * sigma))
        k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
        padded = np.concatenate([np.zeros(r), u, np.full(r, u[-1])])  # held drawn before the thrust
        out = place({j: v.copy() for j, v in smoothed.items()}, dict(zip(frames, np.convolve(padded, k / k.sum(), "valid"))))
        factor = angular_jerk(raw) / angular_jerk(out)
        if factor >= SMOOTHNESS:
            break
    c.smoothing = (round(float(sigma), 2), factor)
    c.baked = out
    return c


M1S = [m1_1, m1_2, m1_3]

# --------------------------------------------------------------------------- running / aerial attacks
# These two drive the legs, and the sword is flown along a path in world space: the fist follows a
# curve around the body and the wrist (Handle) keeps the blade along its own curve with the edge
# leading into the cut, whatever the torso is doing.
FULL = JOINTS + ("RLeg", "LLeg")


def heading(azimuth, elevation=0.0):
    """World direction: azimuth clockwise from straight ahead (90 = right, 180 = behind)."""
    a, e = math.radians(azimuth), math.radians(elevation)
    return np.array([math.sin(a) * math.cos(e), math.sin(e), -math.cos(a) * math.cos(e)])


def root_path(c):
    """The Root track as keyed (unsmoothed), to place world-space targets frame by frame."""
    path = Clip("root", c.frames, None, "RArm")
    path.keys["Root"] = c.keys["Root"]
    path.neck_auto = path.smooth = False
    return path.bake()["Root"]


def fly(c, roots, f, hand, blade, edge, k="linear"):
    """Key the sword arm and wrist at frame f from world-space fist position, blade and edge."""
    t = joint_cf("Root", roots[f])
    rot = t[:3, :3].T
    arm_ch, handle_ch = aim((inv(t) @ np.append(hand, 1))[:3], rot @ blade, edge=rot @ edge)
    c.key("RArm", f, arm_ch, k)
    c.key("Handle", f, handle_ch, k)


def running_attack():
    """Off a sprint with the sword trailing low behind: the left foot plants long, the body winds,
    then the blade is whipped round the right side and across the front at waist height in one
    flat sweep as the body drops into a deep lunge. Sword arm and wrist follow world-space curves."""
    c = Clip("running attack", 54, hit=30, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "Handle"}
    run = [-18, 0, 0, 0, -0.2, 0]
    coil = [-6, -55, 6, 0, -0.32, 0.25]
    lunge = [-24, 85, -10, 0, -0.74, -0.6]
    held = [-20, 72, -6, 0, -0.65, -0.48]
    R = lambda f, v, k="ease": c.key("Root", f, v, k)
    R(0, run)
    R(10, coil, "coil")
    R(34, lunge, "whip")
    R(46, held, "settle")
    R(54, [-21, 74, -6, 0, -0.66, -0.48], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)
    N(0, [-10, 0, 0])
    N(10, [-12, 0, -4], "coil")
    N(29, [-16, 0, 8], "snap")
    N(34, [-18, 0, 10], "stop")
    N(46, [-14, 0, 7], "settle")
    N(54, [-15, 0, 7], "drift")
    roots = root_path(c)

    def at(f, hand_az, reach, height, blade_az, blade_el, k="linear"):
        hand = heading(hand_az) * reach + np.array([0.0, height, 0.0])
        blade = heading(blade_az, blade_el)
        edge = -np.array([math.cos(math.radians(blade_az)), 0.0, math.sin(math.radians(blade_az))])
        fly(c, roots, f, hand, blade, edge, k)

    at(0, 140, 1.5, -0.9, 180, -20, "ease")  # trailing low behind on the run
    at(4, 145, 1.6, -0.7, 178, -15, "ease")
    at(10, 150, 1.9, -0.3, 180, -6, "coil")
    at(18, 158, 2.0, -0.25, 188, -5, "slowin")
    for f in range(19, 35):  # the sweep: round the right side and across the front, edge leading
        u = curve("whip", (f - 18) / 16)
        at(f, 158 - 208 * u, 2.0 + 0.3 * u, -0.25 - 0.1 * u, 188 - 278 * u, -5 - 4 * u)
    at(46, -46, 2.25, -0.38, -86, -10, "settle")
    at(54, -47, 2.25, -0.38, -87, -10, "drift")
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)
    L(0, [40, 0, -8, 0, 0, 0])
    L(10, [30, -10, -16, 0.04, 0.02, -0.1], "coil")
    L(29, [-30, -8, -20, 0, 0, 0.12], "snap")  # swings back behind for balance
    L(34, [-36, -8, -22, 0, 0, 0.14], "stop")
    L(46, [-28, -6, -18, 0, 0, 0.1], "settle")
    L(54, [-28, -6, -18, 0, 0, 0.1], "drift")
    for f, root, k, right, left in (
        (0, run, "ease", (32, 4), (-28, 4)),
        (10, coil, "coil", (-12, 5), (34, 6)),
        (34, lunge, "whip", (-58, 7), (52, 8)),
        (46, held, "settle", (-52, 6), (48, 7)),
    ):
        twist = 0.4 * root[1]
        c.key("RLeg", f, world_leg("RLeg", root, right[0], right[1], twist), k)
        c.key("LLeg", f, world_leg("LLeg", root, left[0], left[1], twist), k)
    return c


def aerial_attack():
    """In the air: rises leaning back with the knees tucked and the sword cocked behind the head,
    holds it, then cleaves over the top and down through the target from high right to low left
    as the body folds forward and the legs drop to land. Sword arm and wrist follow world curves."""
    c = Clip("aerial attack", 56, hit=31, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "Handle"}
    R = lambda f, v, k="ease": c.key("Root", f, v, k)
    R(0, [-4, 0, 0, 0, 0, 0])
    R(14, [18, -35, 8, 0, 0.35, 0.3], "coil")
    R(21, [20, -38, 9, 0, 0.38, 0.32], "slowin")
    R(34, [-36, 38, -10, 0, -0.5, -0.5], "snap")
    R(46, [-30, 32, -7, 0, -0.42, -0.42], "settle")
    R(56, [-31, 33, -7, 0, -0.43, -0.43], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)
    N(0, [-6, 0, 0])
    N(14, [-20, 0, -4], "coil")
    N(21, [-22, 0, -4], "slowin")
    N(27, [4, 0, 6], "snap")
    N(31, [10, 0, 8], "stop")
    N(45, [6, 0, 5], "settle")
    N(56, [7, 0, 5], "drift")
    roots = root_path(c)
    # blade and fist waypoints (world), slerped between with the whip curve
    blades = [heading(170, 25), heading(165, 10), heading(20, 75), heading(-25, -20), heading(-45, -42)]
    hands = [np.array([1.3, 1.9, 0.6]), np.array([1.4, 1.8, 0.8]), np.array([1.0, 1.7, -1.5]),
             np.array([-0.2, 0.2, -2.2]), np.array([-0.7, -0.5, -1.8])]

    def along(points, u):
        """Piecewise slerp (vectors) / lerp (points) through the waypoints, u in [0, 1]."""
        seg = min(len(points) - 2, int(u * (len(points) - 1)))
        t = u * (len(points) - 1) - seg
        a, b = points[seg], points[seg + 1]
        if np.isclose(np.linalg.norm(a), 1.0) and np.isclose(np.linalg.norm(b), 1.0):
            th = math.acos(max(-1.0, min(1.0, float(a @ b))))
            return a if th < 1e-6 else (math.sin((1 - t) * th) * a + math.sin(t * th) * b) / math.sin(th)
        return a + (b - a) * t

    def at(f, u, k="linear"):
        blade = along(blades, u)
        ahead = along(blades, min(1.0, u + 0.02))
        edge = ahead - blade if np.linalg.norm(ahead - blade) > 1e-6 else heading(0, -90)
        fly(c, roots, f, along(hands, u), blade, edge, k)

    fly(c, roots, 0, np.array([0.7, 0.1, -1.4]), heading(-10, 55), heading(0, -90), "ease")  # stance-ish
    at(14, 0.0, "coil")  # cocked behind the head
    at(21, 0.25, "slowin")
    for f in range(22, 37):  # over the top and down through the target
        at(f, 0.25 + 0.75 * curve("whip", (f - 21) / 15))
    at(45, 0.97, "settle")
    at(56, 0.97, "drift")
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)
    L(0, [10, 0, -10, 0, 0, 0])
    L(14, [40, -12, -30, 0.06, 0.04, -0.12], "coil")  # out in front for balance as the body leans back
    L(21, [42, -12, -32, 0.06, 0.04, -0.12], "slowin")
    L(27, [-24, -8, -34, 0, 0, 0.1], "snap")  # swept back as the body folds
    L(31, [-30, -8, -38, 0, 0, 0.12], "stop")
    L(45, [-24, -6, -32, 0, 0, 0.1], "settle")
    L(56, [-24, -6, -32, 0, 0, 0.1], "drift")
    G = lambda leg, f, v, k="ease": c.key(leg, f, v, k)
    G("RLeg", 0, [8, 0, 4, 0, 0, 0])
    G("LLeg", 0, [-8, 0, -4, 0, 0, 0])
    G("RLeg", 14, [70, 0, 8, 0, 0, 0], "coil")  # knees tucked
    G("LLeg", 14, [60, 0, -8, 0, 0, 0], "coil")
    G("RLeg", 21, [74, 0, 8, 0, 0, 0], "slowin")
    G("LLeg", 21, [64, 0, -8, 0, 0, 0], "slowin")
    G("RLeg", 31, [10, 0, 8, 0, 0, 0], "snap")  # legs drop under the body to land
    G("LLeg", 31, [48, 0, -6, 0, 0, 0], "snap")
    G("RLeg", 45, [14, 0, 6, 0, 0, 0], "settle")
    G("LLeg", 45, [44, 0, -6, 0, 0, 0], "settle")
    G("RLeg", 56, [14, 0, 6, 0, 0, 0], "drift")
    G("LLeg", 56, [44, 0, -6, 0, 0, 0], "drift")
    return c


EXTRA = [running_attack, aerial_attack]

# --------------------------------------------------------------------------- idle
IDLE_FRAMES = 125  # 2.083s, one breath per loop, like the reference idles


def idle():
    """The stance, breathing. Measured from the reference idles: the torso rocks 1.1 deg either
    side of its lean and bobs 0.012 studs, the head follows ~0.2s later, the free arm sways ~1 deg
    and the weapon arm ~2.5 deg against the torso."""
    c = Clip("idle", IDLE_FRAMES, hit=None, arm="RArm", joints=JOINTS)
    c.smooth = False
    c.loop = True
    stance_keys(c)
    baked = c.bake()
    t = np.arange(IDLE_FRAMES + 1) / IDLE_FRAMES * 2 * math.pi
    phase = 2 * math.pi * 0.16  # torso pitch peaks a third of a second into the loop
    wave = lambda lag=0.0: np.sin(t - phase - 2 * math.pi * lag / (IDLE_FRAMES / FPS))
    baked["Root"][:, 0] += 1.1 * wave()
    baked["Root"][:, 4] += -0.012 * np.sin(t - phase - math.pi / 2)
    baked["Neck"][:, 0] += 1.4 * wave(0.2)
    baked["RArm"][:, 0] -= 2.5 * wave(0.1)
    baked["RArm"][:, 2] += 0.8 * wave(0.15)
    baked["LArm"][:, 0] -= 1.0 * wave(0.1)
    baked["LArm"][:, 2] -= 0.6 * wave(0.15)
    baked["Handle"][:, 0] += 1.5 * wave(0.25)  # the blade tip drifts with the breath
    c.baked = baked
    return c


# --------------------------------------------------------------------------- unsheathe
GRAB_FRAME = 12


def draw_channels(s):
    """Right Arm channels holding the sword pulled s studs out of the scabbard along its axis."""
    d = SHEATH[:3, :3] @ np.array([0, 0, -1.0])
    return grab_channels(cf(SHEATH[:3, 3] - d * s, SHEATH[:3, :3])).tolist()


def unsheathe():
    """Cross-draw from the left hip, timed like the reference equip: the right hand reaches across
    and takes the grip (the sword stays in the scabbard until then), pauses, rips the blade out
    along the scabbard, sweeps it out low in front and rises into the stance."""
    c = Clip("unsheathe", 60, hit=None, arm="RArm", joints=JOINTS)
    c.slerp = {"RArm"}
    c.peak = 28
    c.markers = {GRAB_FRAME: ["Sheathe/Unsheathe"]}
    R = lambda f, v, k="ease": c.key("Root", f, v, k)
    R(0, [0, 0, 0, 0, 0, 0])
    R(GRAB_FRAME, [-6, 22, -3, 0, -0.16, 0.04], "coil")  # turns toward the hilt
    R(17, [-7, 24, -4, 0, -0.17, 0.05], "slowin")
    R(29, [4, -14, 4, 0, -0.22, -0.06], "ease")  # unwinds as the blade comes out
    R(40, [-5, 22, 2, 0, -0.2, 0.02], "ease")
    R(50, STANCE_ROOT, "settle")
    R(60, STANCE_ROOT, "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)
    N(0, [0, 0, 0])
    N(GRAB_FRAME, [-18, 0, 4], "coil")  # glances down at the hilt
    N(17, [-16, 0, 4], "slowin")
    N(30, [-2, 0, -2], "ease")  # eyes back up to the target
    N(50, STANCE_NECK, "settle")
    N(60, STANCE_NECK, "drift")
    A = lambda f, v, k="ease": c.key("RArm", f, v, k)
    A(0, [0, 0, 0, 0, 0, 0])
    A(4, [10, 14, 10, -0.06, 0.0, -0.12])
    A(GRAB_FRAME, GRAB.tolist(), "coil")
    A(17, draw_channels(0.3), "slowin")
    A(22, draw_channels(1.3), "accel")  # draws it out along the scabbard
    A(26, draw_channels(2.3), "linear")
    A(35, arm([1.9, -0.55, -1.55], [-0.35, -0.45, -0.82]), "decel")  # sweeps out low in front
    A(43, arm([0.9, 0.55, -1.75], [-0.25, 0.96, 0.12]), "ease")  # rises past the stance
    A(50, STANCE_RARM, "settle")
    A(60, STANCE_RARM, "drift")
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)
    L(0, [0, 0, 0, 0, 0, 0])
    L(GRAB_FRAME, [14, 14, 10, 0.12, 0.02, -0.18], "coil")  # steadies the scabbard
    L(17, [16, 16, 10, 0.12, 0.02, -0.2], "slowin")
    L(29, [-8, -6, -24, 0.0, 0.0, 0.1], "ease")
    L(50, STANCE_LARM, "settle")
    L(60, STANCE_LARM, "drift")
    baked = c.bake()
    # until the grab the sword stays put in the scabbard whatever the arm does; after it, any gap
    # the smoothing left between fist and grip closes over a few frames
    for f in range(c.frames + 1):
        if f <= GRAB_FRAME:
            baked["Handle"][f] = sheathed_handle(baked["RArm"][f])
    residual = baked["Handle"][GRAB_FRAME].copy()
    for f in range(GRAB_FRAME + 1, c.frames + 1):
        baked["Handle"][f] = residual * (1 - smoothstep((f - GRAB_FRAME) / 5))
    c.baked = baked
    return c


# --------------------------------------------------------------------------- full-string preview
STRING_NAME = "m1 string (1,2,1,2,3)"
STRING_ORDER = ["m1-1", "m1-2", "m1-1", "m1-2", "m1-3"]
STRING_CANCEL = {"m1-1": 0.58, "m1-2": 0.6}  # 0.15s after each impact
STRING_FADE = 0.15
STRING_END_FADE = 0.3


def _baked(c):
    b = getattr(c, "baked", None)
    if b is None:
        b = c.bake()
        c.baked = b
    return c, b


# --------------------------------------------------------------------------- rig + export
def _part(template, name, cls, size, world, colour, material, reflectance):
    MATERIAL = {"Metal": "1088", "Fabric": "1312", "SmoothPlastic": "272"}
    item = copy.deepcopy(template)
    for child in list(item.findall("Item")):
        item.remove(child)
    item.set("class", "WedgePart" if cls == "WedgePart" else "Part")
    item.set("referent", ref())
    props = item.find("Properties")
    for el in list(props):
        n = el.get("name")
        if n == "Name":
            el.text = name
        elif n == "CFrame":
            props.remove(el)
        elif n == "size":
            for k, v in zip("XYZ", size):
                el.find(k).text = repr(float(v))
        elif n == "Color3uint8":
            el.text = str((colour[0] << 16) | (colour[1] << 8) | colour[2])
        elif n == "Material":
            el.text = MATERIAL[material]
        elif n == "Reflectance":
            el.text = repr(float(reflectance))
        elif n in ("CanCollide", "CanTouch", "CanQuery", "CastShadow"):
            el.text = "true" if n == "CastShadow" else "false"
        elif n == "Massless":
            el.text = "true"
        elif n == "shape":
            if cls == "WedgePart":
                props.remove(el)
            else:
                el.text = {"Ball": "0", "Cylinder": "2"}.get(cls, "1")
        elif n.endswith("Surface"):
            el.text = "0"
    _cframe_prop(props, "CFrame", world)
    return item


def _cframe_prop(props, name, m):
    el = ET.SubElement(props, "CoordinateFrame", {"name": name})
    for k, v in zip("XYZ", m[:3, 3]):
        ET.SubElement(el, k).text = repr(float(v))
    for i in range(3):
        for j in range(3):
            ET.SubElement(el, "R%d%d" % (i, j)).text = repr(float(m[i, j]))


def _joint(cls, name, part0, part1, c0, c1):
    item = ET.Element("Item", {"class": cls, "referent": ref()})
    props = ET.SubElement(item, "Properties")
    prop(props, "string", "Name", name)
    _cframe_prop(props, "C0", c0)
    _cframe_prop(props, "C1", c1)
    prop(props, "bool", "Enabled", "true")
    prop(props, "Ref", "Part0", part0)
    prop(props, "Ref", "Part1", part1)
    return item


def _model(name):
    item = ET.Element("Item", {"class": "Model", "referent": ref()})
    prop(ET.SubElement(item, "Properties"), "string", "Name", name)
    return item


def _child(rig, cls, name):
    for item in rig.iter("Item"):
        n = item.find("Properties/string[@name='Name']")
        if item.get("class") == cls and n is not None and n.text == name:
            return item
    raise KeyError(name)


def _cf_of(item, name="CFrame"):
    el = item.find("Properties/CoordinateFrame[@name='%s']" % name)
    v = {c.tag: float(c.text) for c in el}
    m = np.eye(4)
    m[:3, :3] = [[v["R00"], v["R01"], v["R02"]], [v["R10"], v["R11"], v["R12"]], [v["R20"], v["R21"], v["R22"]]]
    m[:3, 3] = [v["X"], v["Y"], v["Z"]]
    return m


def add_sword(rig):
    """Sword in the right hand on a "Handle" Motor6D, scabbard welded to the torso's left hip."""
    torso, rarm = _child(rig, "Part", "Torso"), _child(rig, "Part", "Right Arm")
    for joint, motor in (("RArm", "Right Shoulder"), ("LArm", "Left Shoulder"), ("Neck", "Neck"), ("RLeg", "Right Hip"), ("LLeg", "Left Hip")):
        m = _child(rig, "Motor6D", motor)
        assert np.allclose(_cf_of(m, "C0"), MOTORS[joint][0], atol=1e-4), motor
        assert np.allclose(_cf_of(m, "C1"), MOTORS[joint][1], atol=1e-4), motor
    t_world, a_world = _cf_of(torso), _cf_of(rarm)
    handle_world = a_world @ GRIP

    sword = _model("Sword")
    handle = None
    for name, cls, size, pos, rot, col, mat, refl in SWORD_PARTS:
        local = cf(pos, rot)
        part = _part(rarm, name, cls, size, handle_world @ local, col, mat, refl)
        sword.append(part)
        if name == "Handle":
            handle = part
        else:
            part.append(_joint("Weld", name, handle.get("referent"), part.get("referent"), local, np.eye(4)))
    # where the blade starts and ends, for the swing trails in CombatVFX (CombatVFX.Swing)
    for name, z in (("SwingBase", -0.75), ("SwingTip", -TIP + 0.05)):
        att = ET.SubElement(handle, "Item", {"class": "Attachment", "referent": ref()})
        aprops = ET.SubElement(att, "Properties")
        prop(aprops, "string", "Name", name)
        _cframe_prop(aprops, "CFrame", cf((0, 0, z)))
    rarm.append(_joint("Motor6D", "Handle", rarm.get("referent"), handle.get("referent"), GRIP, np.eye(4)))
    rig.append(sword)

    scabbard = _model("Scabbard")
    for name, cls, size, pos, rot, col, mat, refl in SCABBARD_PARTS:
        local = SHEATH @ cf(pos, rot)
        part = _part(rarm, name, cls, size, t_world @ local, col, mat, refl)
        part.append(_joint("Weld", name, torso.get("referent"), part.get("referent"), local, np.eye(4)))
        scabbard.append(part)
    rig.append(scabbard)


def build(rig_source, out_dir=HERE):
    import sword_abilities  # (it builds on this module: loaded here, once this one is)

    clips = [idle(), unsheathe()] + [m() for m in M1S] + [m() for m in EXTRA] + sword_abilities.clips()
    sequences, by_name, data = [], {}, {}
    for c in clips:
        c, baked = _baked(c)
        frames = clip_transforms(c, baked)
        by_name[c.name] = (c, frames)
        data[c.name] = {"hit": c.hit, "frames": c.frames, "loop": c.loop, "channels": {j: baked[j].tolist() for j in c.joints}}
        if c.smoothing:
            print("%s: strike sigma %.2f, jerk cut x%.2f" % ((c.name,) + c.smoothing))
        sequences.append(sequence_xml(c.name, frames, c.markers, loop=c.loop))
    stance = by_name["idle"][1][0]
    string_frames, string_hits = build_string(
        [by_name[n] for n in STRING_ORDER], STRING_CANCEL, STRING_FADE, STRING_END_FADE, stance, stance
    )
    sequences.append(sequence_xml(STRING_NAME, string_frames, string_hits))
    json.dump(data, open(os.path.join(out_dir, "sword_data.json"), "w"))

    rig, saves = reference_rig(rig_source, "Sword Rig")
    add_sword(rig)
    for s in sequences:
        saves.append(s)
    root = ET.Element("roblox", {"version": "4"})
    root.append(rig)
    out = os.path.join(out_dir, "SwordCombo.rbxmx")
    ET.ElementTree(root).write(out, encoding="utf-8", xml_declaration=False)
    print("wrote", out)
    return out


if __name__ == "__main__":
    build(sys.argv[1])
