"""5-hit R6 fist M1 combo, authored in the style of the reference animations (ANIMSFORCLAUDE.rbxm).

Style rules measured from the references and applied here:
  * Baked at 60 fps, every pose Linear/Out, Priority Action, legs keyed at Weight 0 so walk/idle
    keep driving them.
  * Rhythm per hit: arm counter-move -> smooth coil (torso winds 40-75 deg the "wrong" way,
    punching arm chambers out of its socket) -> loaded slow-in while the arms keep cocking ->
    3-5 frame whip where the torso swings 140-170 deg and the punch shoots out -> overshoot ->
    ease-back settle -> slow drift while the final silhouette is held until the clip ends.
  * The whip, coil, settle and drift curves are the exact normalised curves measured from the
    reference fist M1 (style_profiles.json).
  * The head counter-rotates against the torso (-0.95 x torso yaw, capped at +-71 deg) so the eyes
    stay on the target, tucks down at impact and tilts against the torso roll.
  * Arms translate up to ~1 stud off the shoulder to fake elbows / reach, exactly like the reference.

Outputs (next to this file):
  FistCombo.rbxmx   the reference "normal player" rig with the 5 KeyframeSequences in AnimSaves
  combo_data.json   baked channels for previews/tests
"""

import json
import math
import os
import sys
import xml.etree.ElementTree as ET

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
FPS = 60
JOINTS = ["Root", "Neck", "RArm", "LArm"]
PART = {"Root": "Torso", "Neck": "Head", "RArm": "Right Arm", "LArm": "Left Arm"}

# --------------------------------------------------------------------------- curve profiles
P = json.load(open(os.path.join(HERE, "style_profiles.json")))


def _norm(arr):
    a = np.array(arr, float)
    return (a - a[0]) / (a[-1] - a[0])


WHIP = np.array(P["whip"])
PROFILES = {
    "coil": np.array(P["coil"]),
    "whip": WHIP,
    "settle": np.array(P["settle"]),
    "drift": np.array(P["drift"]),
    "slowin": _norm(WHIP[0:8]),  # the loaded build-up at the start of the whip
    "snap": _norm(WHIP[7:13]),  # the explosive middle of the whip
    "stop": _norm(WHIP[11:16]),  # the hard stop at the end of the whip
    "armstrike": np.array(P["arm_strike_z"]),  # the punching arm accelerating through impact
    "ease": None,
    "linear": None,
    "accel": None,
    "decel": None,
}


def curve(name, u):
    u = min(1.0, max(0.0, u))
    if name == "linear":
        return u
    if name == "ease":
        return u * u * (3 - 2 * u)
    if name == "accel":
        return u * u
    if name == "decel":
        return 1 - (1 - u) * (1 - u)
    prof = PROFILES[name]
    xs = np.linspace(0, 1, len(prof))
    return float(np.interp(u, xs, prof))


# --------------------------------------------------------------------------- clip authoring
class Clip:
    def __init__(self, name, frames, hit):
        self.name = name
        self.frames = frames  # last frame index
        self.hit = hit  # frame of the "Hit" marker
        self.keys = {j: [] for j in JOINTS}
        self.neck_auto = True

    def key(self, joint, frame, vals, curve_in="ease"):
        v = list(vals) + [0.0] * (6 - len(vals))
        self.keys[joint].append((frame, np.array(v, float), curve_in))
        self.keys[joint].sort(key=lambda k: k[0])
        return self

    def bake(self):
        out = {}
        for j in JOINTS:
            ks = self.keys[j]
            rows = []
            for f in range(self.frames + 1):
                if not ks:
                    rows.append(np.zeros(6))
                    continue
                if f <= ks[0][0]:
                    rows.append(ks[0][1].copy())
                    continue
                if f >= ks[-1][0]:
                    rows.append(ks[-1][1].copy())
                    continue
                for a, b in zip(ks, ks[1:]):
                    if a[0] <= f <= b[0]:
                        p = curve(b[2], (f - a[0]) / (b[0] - a[0]))
                        rows.append(a[1] + (b[1] - a[1]) * p)
                        break
            out[j] = np.array(rows)
        if self.neck_auto:
            # head keeps facing the target: counter the torso yaw (capped), following it with a
            # slight lag so it trails the torso during the whip like the reference does
            yaw = out["Root"][:, 1]
            wrapped = (yaw + 180) % 360 - 180
            target = np.clip(-0.95 * wrapped, -71, 71)
            follow = np.zeros_like(target)
            follow[0] = target[0]
            alpha = 1 - math.exp(-(1 / FPS) / 0.022)
            for i in range(1, len(target)):
                follow[i] = follow[i - 1] + (target[i] - follow[i - 1]) * alpha
            out["Neck"][:, 1] += follow
        return out


def mirror(v):
    """Mirror a channel vector left<->right (pitch, yaw, roll, x, y, z)."""
    p, y, r, x, yy, z = (list(v) + [0] * 6)[:6]
    return [p, -y, -r, -x, yy, z]


# --------------------------------------------------------------------------- the combo
def m1_1():
    """Lead (left) snap jab: short coil, fastest whip, aimed high."""
    c = Clip("m1-1", 50, hit=20)
    R = lambda f, v, k="ease": c.key("Root", f, v, k)
    R(0, [-4, -12, 0.4, 0, -0.24, 0])
    R(10, [4, 46, -5, 0, -0.28, 0.28], "coil")
    R(23, [-13, -101, 5, 0, -0.22, -0.2], "whip")
    R(38, [-10, -88, 1.5, 0, -0.23, -0.02], "settle")
    R(50, [-11.5, -92, 2.5, 0, -0.23, 0], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)
    N(0, [0, 0, 1])
    N(10, [-10, 0, -3], "coil")
    N(17, [-8, 0, 2], "slowin")
    N(21, [-16, 0, 8], "snap")
    N(24, [-19, 0, 12], "stop")
    N(38, [-13, 0, 9], "settle")
    N(50, [-15, 0, 10], "drift")
    # punching (left) arm: counter-move forward, chamber back out of the socket, cock, snap out
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)
    L(0, [0, 0, 0, 0, 0, 0])
    L(4, mirror([30, 28, 22, -0.11, 0.02, -0.21]))
    L(8, mirror([56, 36, 60, -0.33, -0.44, 0.86]))
    L(10, mirror([34, 32, 79, -0.28, -0.32, 0.93]))
    L(16, mirror([38, 64, 104, -0.24, 0.1, 0.9]), "slowin")
    L(20, mirror([30, 10, 97, 0.58, -0.08, -0.26]), "armstrike")
    L(22, mirror([16, 4, 92, 0.66, -0.14, -0.3]), "stop")
    L(25, mirror([19, 7, 97, 0.6, -0.16, -0.18]), "ease")
    L(38, mirror([12, 3, 94, 0.5, -0.16, 0.02]), "settle")
    L(50, mirror([13, 2, 95, 0.52, -0.15, -0.02]), "drift")
    # rear (right) arm: reaches forward during the coil, yanks back to the hip on the whip
    Rr = lambda f, v, k="ease": c.key("RArm", f, v, k)
    Rr(0, [0, 0, 0, 0, 0, 0])
    Rr(4, mirror([6, -18, -7, 0.09, 0.01, -0.25]))
    Rr(10, mirror([34, -50, -48, 0.19, 0.17, -0.62]), "coil")
    Rr(16, mirror([50, -110, -122, 0.07, -0.34, -0.3]), "slowin")
    Rr(21, mirror([34, -24, -55, 0.25, -0.3, 0.5]), "snap")
    Rr(24, mirror([25, -9, -52, 0.36, -0.27, 0.58]), "stop")
    Rr(38, mirror([18, -10, -54, 0.34, -0.3, 0.6]), "settle")
    Rr(50, mirror([17, -15, -55, 0.32, -0.32, 0.61]), "drift")
    return c


def m1_2():
    """Rear (right) overhand: chambers high behind the head, drops over the top, deep lean."""
    c = Clip("m1-2", 50, hit=24)
    R = lambda f, v, k="ease": c.key("Root", f, v, k)
    R(0, [-4, 13, -0.3, 0, -0.24, 0])
    R(13, [8, -68, 7, 0, -0.27, 0.38], "coil")
    R(28, [-19, 108, -6, 0, -0.3, -0.36], "whip")
    R(44, [-14, 93, -1, 0, -0.26, -0.08], "settle")
    R(50, [-15, 96, -2.5, 0, -0.26, -0.06], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)
    N(0, [0, 0, -1])
    N(13, [-6, 0, 4], "coil")
    N(20, [-4, 0, -2], "slowin")
    N(24, [-17, 0, -8], "snap")
    N(28, [-22, 0, -13], "stop")
    N(44, [-15, 0, -9], "settle")
    N(50, [-17, 0, -10], "drift")
    Rr = lambda f, v, k="ease": c.key("RArm", f, v, k)
    Rr(0, [0, 0, 0, 0, 0, 0])
    Rr(4, [36, 30, 26, -0.13, 0.04, -0.24])
    Rr(8, [104, 34, 70, -0.36, 0.08, 0.86])
    Rr(13, [132, 26, 88, -0.3, 0.32, 0.92])
    Rr(20, [140, 58, 112, -0.26, 0.42, 0.82], "slowin")
    Rr(24, [38, 14, 95, 0.55, -0.02, -0.22], "armstrike")
    Rr(26, [18, 8, 91, 0.66, -0.16, -0.26], "stop")
    Rr(29, [24, 9, 97, 0.58, -0.18, -0.1], "ease")
    Rr(44, [14, 3, 93, 0.48, -0.18, 0.06], "settle")
    Rr(50, [15, 2, 94, 0.5, -0.17, 0.02], "drift")
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)
    L(0, [0, 0, 0, 0, 0, 0])
    L(4, [6, -18, -7, 0.09, 0.01, -0.25])
    L(8, [16, -42, -26, 0.19, 0.06, -0.58])
    L(13, [38, -55, -52, 0.2, 0.2, -0.66], "coil")
    L(20, [50, -120, -130, 0.06, -0.38, -0.2], "slowin")
    L(23, [44, -40, -66, 0.2, -0.32, 0.42], "snap")
    L(26, [26, -10, -52, 0.34, -0.27, 0.58], "stop")
    L(44, [18, -10, -55, 0.34, -0.3, 0.6], "settle")
    L(50, [17, -15, -55, 0.32, -0.32, 0.61], "drift")
    return c


def m1_3():
    """Lead (left) hook: arm cocked back at shoulder height, rips across in a flat arc and finishes
    across the face (fist in front of the opposite shoulder), body tilting into it."""
    c = Clip("m1-3", 50, hit=24)
    R = lambda f, v, k="ease": c.key("Root", f, v, k)
    R(0, [-4, -10, 0.5, 0, -0.24, 0])
    R(13, [6, 64, 12, 0, -0.3, 0.3], "coil")
    R(28, [-12, -62, -14, 0, -0.32, -0.22], "whip")
    R(44, [-9, -50, -8, 0, -0.27, -0.06], "settle")
    R(50, [-10, -53, -9, 0, -0.27, -0.04], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)
    N(0, [0, 0, 1])
    N(13, [-8, 0, -8], "coil")
    N(20, [-6, 0, -2], "slowin")
    N(24, [-14, 0, 10], "snap")
    N(28, [-17, 0, 13], "stop")
    N(44, [-12, 0, 8], "settle")
    N(50, [-13, 0, 9], "drift")
    # hook arm: never sticks out sideways at the end, it wraps across the front of the face
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)
    L(0, [0, 0, 0, 0, 0, 0])
    L(5, [26, -26, -24, 0.12, 0.03, -0.22])
    L(13, [34, 18, -86, -0.16, 0.12, 0.5], "coil")
    L(19, [36, 25, -94, -0.18, 0.16, 0.46], "slowin")
    L(24, [18, -90, -92, 0.3, 0.08, -0.36], "armstrike")
    L(27, [14, -118, -90, 0.5, 0.1, -0.26], "stop")
    L(30, [16, -110, -91, 0.46, 0.1, -0.28], "ease")
    L(44, [14, -106, -90, 0.42, 0.08, -0.26], "settle")
    L(50, [15, -108, -90, 0.43, 0.08, -0.27], "drift")
    # rear hand stays up as a guard by the chin
    Rr = lambda f, v, k="ease": c.key("RArm", f, v, k)
    Rr(0, [0, 0, 0, 0, 0, 0])
    Rr(4, [10, 16, 8, -0.08, 0.02, -0.2])
    Rr(13, [76, 40, 26, -0.36, 0.3, -0.34], "coil")
    Rr(20, [82, 52, 34, -0.4, 0.34, -0.3], "slowin")
    Rr(24, [70, 34, 30, -0.42, 0.18, -0.12], "snap")
    Rr(27, [66, 28, 32, -0.44, 0.12, -0.06], "stop")
    Rr(44, [64, 26, 32, -0.42, 0.12, -0.08], "settle")
    Rr(50, [65, 25, 32, -0.43, 0.11, -0.08], "drift")
    return c


def m1_4():
    """Rear (right) uppercut: sinks low and forward, then explodes up and back on the rising fist."""
    c = Clip("m1-4", 50, hit=25)
    R = lambda f, v, k="ease": c.key("Root", f, v, k)
    R(0, [-4, 12, -0.4, 0, -0.24, 0])
    R(14, [-24, -56, 14, 0, -0.66, 0.24], "coil")
    R(21, [-26, -62, 16, 0, -0.72, 0.28], "slowin")
    R(29, [21, 64, -10, 0, 0.16, -0.34], "whip")
    R(45, [13, 52, -5, 0, -0.04, -0.14], "settle")
    R(50, [14, 54, -6, 0, -0.03, -0.15], "drift")
    c.neck_auto = True
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)
    N(0, [0, 0, -1])
    N(14, [14, 0, -6], "coil")
    N(21, [16, 0, -8], "slowin")
    N(25, [-2, 0, 6], "snap")
    N(29, [6, 0, 10], "stop")
    N(45, [2, 0, 6], "settle")
    N(50, [3, 0, 7], "drift")
    Rr = lambda f, v, k="ease": c.key("RArm", f, v, k)
    Rr(0, [0, 0, 0, 0, 0, 0])
    Rr(4, [22, 14, 14, -0.06, 0.04, -0.22])
    Rr(9, [-16, 12, 22, 0.08, -0.34, 0.48])
    Rr(14, [-22, 14, 28, 0.12, -0.42, 0.58])
    Rr(20, [-26, 20, 32, 0.12, -0.46, 0.64], "slowin")
    Rr(25, [112, 26, 18, -0.24, 0.32, -0.34], "armstrike")
    Rr(28, [158, 30, 12, -0.32, 0.54, -0.3], "stop")
    Rr(31, [150, 27, 14, -0.28, 0.48, -0.3], "ease")
    Rr(45, [144, 22, 15, -0.22, 0.42, -0.24], "settle")
    Rr(50, [146, 21, 15, -0.23, 0.43, -0.25], "drift")
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)
    L(0, [0, 0, 0, 0, 0, 0])
    L(5, [20, -30, -16, 0.12, 0.04, -0.3])
    L(14, [58, -48, -40, 0.26, 0.22, -0.66], "coil")
    L(21, [62, -60, -48, 0.26, 0.26, -0.7], "slowin")
    L(25, [14, -24, -52, 0.32, -0.34, 0.5], "snap")
    L(28, [6, -14, -50, 0.36, -0.36, 0.58], "stop")
    L(45, [8, -14, -52, 0.34, -0.34, 0.56], "settle")
    L(50, [8, -16, -52, 0.34, -0.35, 0.57], "drift")
    return c


def m1_5():
    """Finisher: spinning backfist. Coils, pirouettes 330 deg clockwise with the right arm flung out,
    and lands the back of the fist side-on, then holds the pose longer."""
    c = Clip("m1-5", 60, hit=39)
    R = lambda f, v, k="ease": c.key("Root", f, v, k)
    R(0, [-4, -10, 0.4, 0, -0.24, 0])
    R(16, [6, 44, 12, 0, -0.44, 0.32], "coil")
    R(24, [8, 52, 14, 0, -0.5, 0.34], "slowin")
    R(32, [-8, -109, -2, 0, -0.6, 0.0], "accel")  # dips low mid-spin
    R(40, [-15, -270, -9, 0, -0.36, -0.38], "decel")
    R(43, [-16, -282, -10, 0, -0.33, -0.4], "stop")
    R(57, [-12, -267, -4, 0, -0.3, -0.12], "settle")
    R(60, [-13, -270, -5, 0, -0.3, -0.12], "drift")
    c.neck_auto = False  # the head spots the target through the spin (authored)
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)
    N(0, [0, 11, 1])
    N(16, [-10, -40, -6], "coil")
    N(24, [-12, -49, -6], "slowin")
    N(32, [-12, 71, 0], "ease")  # looks back over the shoulder as the body turns away
    N(37, [-16, -71, 10], "ease")  # then whips round to spot the target before the fist lands
    N(43, [-20, -71, 14], "stop")
    N(57, [-14, -70, 9], "settle")
    N(60, [-15, -70, 10], "drift")
    Rr = lambda f, v, k="ease": c.key("RArm", f, v, k)
    Rr(0, [0, 0, 0, 0, 0, 0])
    Rr(5, [30, 30, 20, -0.12, 0.04, -0.24])
    Rr(16, [74, 52, 22, -0.42, 0.22, -0.46], "coil")  # wrapped across the chest
    Rr(24, [80, 62, 24, -0.46, 0.26, -0.48], "slowin")
    Rr(33, [24, 4, 92, 0.24, -0.04, 0.1], "ease")  # flung out as the spin starts
    Rr(39, [10, 4, 98, 0.66, -0.08, -0.22], "armstrike")
    Rr(42, [4, 6, 104, 0.74, -0.12, -0.2], "stop")
    Rr(45, [8, 5, 98, 0.66, -0.14, -0.12], "ease")
    Rr(57, [7, 3, 95, 0.56, -0.16, 0.02], "settle")
    Rr(60, [8, 2, 96, 0.58, -0.15, 0.0], "drift")
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)
    L(0, [0, 0, 0, 0, 0, 0])
    L(5, [8, -18, -10, 0.1, 0.02, -0.24])
    L(16, [40, -40, -44, 0.24, 0.12, -0.56], "coil")
    L(24, [44, -48, -50, 0.26, 0.16, -0.6], "slowin")
    L(33, [70, -70, -20, 0.3, 0.2, -0.3], "ease")  # tucked tight through the spin
    L(39, [30, -20, -56, 0.3, -0.26, 0.5], "snap")
    L(42, [22, -8, -54, 0.36, -0.28, 0.6], "stop")
    L(57, [17, -10, -55, 0.34, -0.3, 0.6], "settle")
    L(60, [16, -14, -55, 0.33, -0.31, 0.61], "drift")
    return c


CLIPS = [m1_1, m1_2, m1_3, m1_4, m1_5]

# --------------------------------------------------------------------------- R6 conversion
C0_ROT = {  # standard R6 Motor6D C0 rotations (rows)
    "Root": [[-1, 0, 0], [0, 0, 1], [0, 1, 0]],
    "Neck": [[-1, 0, 0], [0, 0, 1], [0, 1, 0]],
    "RArm": [[0, 0, 1], [0, 1, 0], [-1, 0, 0]],
    "LArm": [[0, 0, -1], [0, 1, 0], [1, 0, 0]],
}


def euler_yxz(p, y, r):
    p, y, r = map(math.radians, (p, y, r))
    cx, sx, cy, sy, cz, sz = math.cos(p), math.sin(p), math.cos(y), math.sin(y), math.cos(r), math.sin(r)
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return ry @ rx @ rz


def to_transform(joint, ch):
    """Parent-space channels -> Motor6D Transform (what a Pose.CFrame stores)."""
    rc = np.array(C0_ROT[joint], float)
    pr = euler_yxz(ch[0], ch[1], ch[2])
    rot = rc.T @ pr @ rc
    pos = rc.T @ np.array(ch[3:6])
    return pos, rot


# --------------------------------------------------------------------------- XML export
_ref = [0]


def ref():
    _ref[0] += 1
    return "RBXCOMBO%06d" % _ref[0]


def prop(parent, tag, name, text=None):
    el = ET.SubElement(parent, tag, {"name": name})
    if text is not None:
        el.text = text
    return el


def cframe(parent, name, pos, rot):
    el = ET.SubElement(parent, "CoordinateFrame", {"name": name})
    for k, v in zip(["X", "Y", "Z"], pos):
        ET.SubElement(el, k).text = repr(float(v))
    for i in range(3):
        for j in range(3):
            ET.SubElement(el, "R%d%d" % (i, j)).text = repr(float(rot[i][j]))


def pose(parent, name, pos, rot, weight=1.0, direction=1):
    item = ET.SubElement(parent, "Item", {"class": "Pose", "referent": ref()})
    props = ET.SubElement(item, "Properties")
    prop(props, "string", "Name", name)
    cframe(props, "CFrame", pos, rot)
    prop(props, "token", "EasingDirection", str(direction))
    prop(props, "token", "EasingStyle", "0")
    prop(props, "float", "Weight", repr(float(weight)))
    return item


IDENTITY = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]


def clip_transforms(clip, baked):
    """Per frame: {joint: (pos, rot)} Motor6D transforms."""
    return [{j: to_transform(j, baked[j][f]) for j in JOINTS} for f in range(clip.frames + 1)]


def sequence_xml(name, frames, hit_frames, loop=False):
    seq = ET.Element("Item", {"class": "KeyframeSequence", "referent": ref()})
    props = ET.SubElement(seq, "Properties")
    prop(props, "string", "Name", name)
    prop(props, "bool", "Loop", "true" if loop else "false")
    prop(props, "token", "Priority", "2")
    for f, transforms in enumerate(frames):
        kf = ET.SubElement(seq, "Item", {"class": "Keyframe", "referent": ref()})
        kp = ET.SubElement(kf, "Properties")
        prop(kp, "string", "Name", "Keyframe")
        prop(kp, "float", "Time", repr(f / FPS))
        hrp = pose(kf, "HumanoidRootPart", (0, 0, 0), IDENTITY, 1.0, direction=0)
        pos, rot = transforms["Root"]
        torso = pose(hrp, "Torso", pos, rot)
        for joint in ["Neck", "RArm", "LArm"]:
            pos, rot = transforms[joint]
            pose(torso, PART[joint], pos, rot)
        pose(torso, "Right Leg", (0, 0, 0), IDENTITY, 0.0)
        pose(torso, "Left Leg", (0, 0, 0), IDENTITY, 0.0)
        if f in hit_frames:
            marker = ET.SubElement(kf, "Item", {"class": "KeyframeMarker", "referent": ref()})
            mp = ET.SubElement(marker, "Properties")
            prop(mp, "string", "Name", "Hit")
            prop(mp, "string", "Value", "Hit")
    return seq


# --------------------------------------------------------------------------- full-string preview
# Every hit is cancelled into the next one this long after it starts (about 0.15s after its
# impact), crossfading over STRING_FADE like AnimationTrack:Play(0.1) does in game.
STRING_NAME = "m1 string (1,2,1,2,3)"
STRING_ORDER = ["m1-1", "m1-2", "m1-1", "m1-2", "m1-3"]
STRING_CANCEL = {"m1-1": 0.48, "m1-2": 0.55, "m1-3": 0.55, "m1-4": 0.58}
STRING_FADE = 0.1
STRING_END_FADE = 0.3


def _quat(m):
    m = np.asarray(m, float)
    tr = m[0, 0] + m[1, 1] + m[2, 2]
    if tr > 0:
        sq = math.sqrt(tr + 1.0) * 2
        q = [0.25 * sq, (m[2, 1] - m[1, 2]) / sq, (m[0, 2] - m[2, 0]) / sq, (m[1, 0] - m[0, 1]) / sq]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        sq = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [(m[2, 1] - m[1, 2]) / sq, 0.25 * sq, (m[0, 1] + m[1, 0]) / sq, (m[0, 2] + m[2, 0]) / sq]
    elif m[1, 1] > m[2, 2]:
        sq = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 2] - m[2, 0]) / sq, (m[0, 1] + m[1, 0]) / sq, 0.25 * sq, (m[1, 2] + m[2, 1]) / sq]
    else:
        sq = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[1, 0] - m[0, 1]) / sq, (m[0, 2] + m[2, 0]) / sq, (m[1, 2] + m[2, 1]) / sq, 0.25 * sq]
    q = np.array(q)
    return q / np.linalg.norm(q)


def _mat(q):
    w, x, y, z = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def _blend(a, b, w):
    """Blend two {joint: (pos, rot)} poses: slerp rotations, lerp positions."""
    out = {}
    for j in JOINTS:
        (pa, ra), (pb, rb) = a[j], b[j]
        qa, qb = _quat(ra), _quat(rb)
        d = float(np.dot(qa, qb))
        if d < 0:
            qb, d = -qb, -d
        if d > 0.9995:
            q = qa + (qb - qa) * w
        else:
            th = math.acos(d)
            q = (math.sin((1 - w) * th) * qa + math.sin(w * th) * qb) / math.sin(th)
        q = q / np.linalg.norm(q)
        out[j] = (np.array(pa) + (np.array(pb) - np.array(pa)) * w, _mat(q))
    return out


REST = {j: ((0.0, 0.0, 0.0), np.eye(3)) for j in JOINTS}


def build_string(clips):
    """clips: list of (clip, frames) in combo order -> (frames, hit frame indices)."""
    starts, t = [], 0.0
    for clip, _ in clips:
        starts.append(t)
        t += STRING_CANCEL.get(clip.name, clip.frames / FPS)
    last_clip, last_frames = clips[-1]
    end = starts[-1] + last_clip.frames / FPS + STRING_END_FADE
    total = int(round(end * FPS))

    def sample(frames, local):
        return frames[min(len(frames) - 1, max(0, int(round(local * FPS))))]

    out = []
    for f in range(total + 1):
        t = f / FPS
        pose_now = REST
        for i, (clip, frames) in enumerate(clips):
            if t < starts[i]:
                break
            local = t - starts[i]
            w = min(1.0, local / STRING_FADE) if i > 0 else 1.0
            pose_now = _blend(pose_now, sample(frames, local), w)
        tail = t - (starts[-1] + last_clip.frames / FPS)
        if tail > 0:
            pose_now = _blend(pose_now, REST, min(1.0, tail / STRING_END_FADE))
        out.append(pose_now)
    hits = {int(round((starts[i] + clip.hit / FPS) * FPS)) for i, (clip, _) in enumerate(clips)}
    return out, hits


def build(rig_source=None, out_dir=HERE):
    baked_all = {}
    sequences = []
    by_name = {}
    for make in CLIPS:
        clip = make()
        baked = clip.bake()
        baked_all[clip.name] = {"hit": clip.hit, "frames": clip.frames, "channels": {j: baked[j].tolist() for j in JOINTS}}
        frames = clip_transforms(clip, baked)
        by_name[clip.name] = (clip, frames)
        sequences.append(sequence_xml(clip.name, frames, {clip.hit}))
    # always ship the whole string as one animation so the combo can be previewed in one go
    string_frames, string_hits = build_string([by_name[n] for n in STRING_ORDER])
    sequences.append(sequence_xml(STRING_NAME, string_frames, string_hits))
    json.dump(baked_all, open(os.path.join(out_dir, "combo_data.json"), "w"))

    root = ET.Element("roblox", {"version": "4"})
    if rig_source:
        # reuse the reference "normal player" rig (same parts, joints and look) with new AnimSaves
        src = ET.parse(rig_source).getroot()
        rig = None
        for item in src.findall("Item"):
            name = item.find("Properties/string[@name='Name']")
            if name is not None and name.text == "normal player":
                rig = item
        assert rig is not None, "normal player rig not found"
        for child in list(rig.findall("Item")):
            cname = child.find("Properties/string[@name='Name']")
            if child.get("class") == "ObjectValue" and cname is not None and cname.text == "AnimSaves":
                for old in list(child.findall("Item")):
                    child.remove(old)
                for s in sequences:
                    child.append(s)
        rig.find("Properties/string[@name='Name']").text = "Fist Combo Rig"
        # drop Studio-regenerated caches that point into the source file's SharedStrings table
        for props in rig.iter("Properties"):
            for el in list(props):
                if el.tag == "SharedString":
                    props.remove(el)
        root.append(rig)
    else:
        saves = ET.SubElement(root, "Item", {"class": "Folder", "referent": ref()})
        sp = ET.SubElement(saves, "Properties")
        prop(sp, "string", "Name", "FistComboAnimations")
        for s in sequences:
            saves.append(s)
    out = os.path.join(out_dir, "FistCombo.rbxmx")
    ET.ElementTree(root).write(out, encoding="utf-8", xml_declaration=False)
    print("wrote", out)
    return out


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else None)
