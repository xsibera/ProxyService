"""The combat reactions (R6), in the same style as the ability animations, built with animkit and the
Jajanken solvers. They key the upper body only (legs at Weight 0), so the walk keeps the feet moving:
a stunned player can still shuffle, a blocking one can still step.

  Block       1.0s loop   forearms crossed up in front of the face, hunched behind them, breathing
  Parry       0.3s        a sharp outward beat with the right forearm, from the centre out to the
                          right, then into the block
  Hit         0.45s       the head snaps back and the torso is knocked back and twisted, the arms flung;
                          recovers
  Shocked     0.5s loop   electrocuted: the body locked rigid, arms stiff out from the sides, jittering
  GuardBreak  1.2s        the guard knocked apart: arms flung wide, bent back, staggering, then hunched
  Parried     0.9s        the strike knocked back: the arm thrown up and back, the torso twisted away
"""

import importlib.util
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "Animations"))
from animkit import UPPER, Clip  # noqa: E402


def _jajanken_solvers():
    spec = importlib.util.spec_from_file_location("jajanken_anims", os.path.join(HERE, "..", "Jajanken", "anims.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


J = _jajanken_solvers()
arm_w, reach, heading = J.arm_w, J.reach, J.heading

ZERO = [0, 0, 0, 0, 0, 0]
GUARD_ROOT = [-10, 6, 0, 0, -0.18, 0.08]


def guard_arms(root, dy=0.0):
    """Forearms crossed up in front of the face: fists up by the opposite temple."""
    return (arm_w("RArm", root, [-0.35, 1.55 + dy, -1.15], twist=-70),
            arm_w("LArm", root, [0.4, 1.4 + dy, -1.25], twist=70))


def block():
    c = Clip("Combat Block", 60, hit=None, arm="RArm", joints=UPPER)
    c.loop = True
    c.smooth = False
    for f, (dp, dy) in {0: (0, 0.0), 30: (-2.0, -0.04), 60: (0, 0.0)}.items():
        root = list(np.array(GUARD_ROOT) + [dp, 0, 0, 0, dy, 0])
        c.key("Root", f, root, "ease")
        ra, la = guard_arms(root, dy * 0.5)
        c.key("RArm", f, ra, "ease")
        c.key("LArm", f, la, "ease")
        c.key("Neck", f, [-14 + dp, 0, 0], "ease")
    return c


def parry():
    """Into the guard with a sharp outward beat of the right forearm (centre -> out to the right)."""
    c = Clip("Combat Parry", 18, hit=None, arm="RArm", joints=UPPER)
    c.peak = 5
    for joint in UPPER:
        c.key(joint, 0, ZERO if joint != "Neck" else [0, 0, 0])
    beat = [-8, -14, 2, 0, -0.15, 0.05]
    r = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    r(3, [-9, 10, 0, 0, -0.12, 0.05], "accel")
    r(6, beat, "whip")
    r(18, GUARD_ROOT, "settle")
    c.key("RArm", 3, arm_w("RArm", [-9, 10, 0, 0, -0.12, 0.05], [-0.3, 1.2, -1.3], twist=-70), "accel")
    c.key("RArm", 6, reach("RArm", beat, heading(55, 30), 0.6, twist=-40), "whip")  # beaten out
    ra, la = guard_arms(GUARD_ROOT)
    c.key("RArm", 18, ra, "settle")
    c.key("LArm", 4, arm_w("LArm", [-9, 10, 0, 0, -0.12, 0.05], [0.4, 1.3, -1.2], twist=70), "decel")
    c.key("LArm", 18, la, "settle")
    c.key("Neck", 6, [-10, 0, 6], "snap")
    c.key("Neck", 18, [-14, 0, 0], "settle")
    return c


def hit():
    c = Clip("Combat Hit", 27, hit=None, arm="RArm", joints=UPPER)
    c.peak = 3
    for joint in UPPER:
        c.key(joint, 0, ZERO if joint != "Neck" else [0, 0, 0])
    knocked = [16, 18, -8, 0, -0.1, 0.35]
    r = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    r(3, knocked, "whip")
    r(9, [12, 14, -6, 0, -0.15, 0.3], "stop")
    r(27, [-4, 4, 0, 0, -0.1, 0.05], "settle")
    c.key("Neck", 3, [22, 0, -8], "whip")  # the head snaps back
    c.key("Neck", 10, [12, 0, -4], "stop")
    c.key("Neck", 27, [-6, 0, 0], "settle")
    c.key("RArm", 3, reach("RArm", knocked, heading(120, -10), 0.2, twist=-20), "whip")
    c.key("RArm", 27, reach("RArm", [-4, 4, 0, 0, -0.1, 0.05], heading(20, -75), 0.05), "settle")
    c.key("LArm", 3, reach("LArm", knocked, heading(-140, 5), 0.25, twist=20), "whip")
    c.key("LArm", 27, reach("LArm", [-4, 4, 0, 0, -0.1, 0.05], heading(-20, -75), 0.05), "settle")
    return c


def shocked():
    """Electrocuted, looped: rigid, arms stiff out from the sides and down, head back, jittering on
    uneven little twitches (keyed every 3 frames, no smoothing: it's meant to be harsh)."""
    c = Clip("Combat Shocked", 30, hit=None, arm="RArm", joints=UPPER)
    c.loop = True
    c.smooth = False
    rng = np.random.default_rng(7)
    base = [8, 0, 0, 0, 0.05, 0.05]
    frames = list(range(0, 31, 3))
    for i, f in enumerate(frames):
        last = i == len(frames) - 1
        j = np.zeros(6) if (i == 0 or last) else rng.uniform(-1, 1, 6) * [5, 6, 5, 0, 0.04, 0.03]
        root = list(np.array(base) + j)
        c.key("Root", f, root, "linear")
        jr = np.zeros(3) if (i == 0 or last) else rng.uniform(-1, 1, 3)
        right = reach("RArm", root, heading(95 + 12 * jr[0], -35 + 10 * jr[1]), 0.15, twist=30 * jr[2])
        left = reach("LArm", root, heading(-95 - 12 * jr[1], -35 + 10 * jr[2]), 0.15, twist=30 * jr[0])
        c.key("RArm", f, right, "linear")
        c.key("LArm", f, left, "linear")
        c.key("Neck", f, [18 + 6 * jr[0], 0, 8 * jr[1]], "linear")
    c.neck_auto = False
    return c


def guard_break():
    c = Clip("Combat GuardBreak", 72, hit=None, arm="RArm", joints=UPPER)
    c.peak = 4
    ra, la = guard_arms(GUARD_ROOT)
    c.key("Root", 0, GUARD_ROOT)
    c.key("RArm", 0, ra)
    c.key("LArm", 0, la)
    c.key("Neck", 0, [-14, 0, 0])
    flung = [22, -6, 4, 0, -0.05, 0.45]
    r = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    r(4, flung, "whip")
    r(12, [18, 8, -6, 0, -0.15, 0.55], "stop")
    r(28, [-20, 4, 2, 0, -0.35, 0.2], "ease")  # doubles over
    r(56, [-14, 2, 0, 0, -0.25, 0.1], "settle")
    r(72, [-6, 0, 0, 0, -0.1, 0.02], "drift")
    c.key("RArm", 4, reach("RArm", flung, heading(110, 30), 0.3, twist=-30), "whip")
    c.key("LArm", 4, reach("LArm", flung, heading(-110, 30), 0.3, twist=30), "whip")
    c.key("RArm", 28, reach("RArm", [-20, 4, 2, 0, -0.35, 0.2], heading(30, -70), 0.05), "ease")
    c.key("LArm", 28, reach("LArm", [-20, 4, 2, 0, -0.35, 0.2], heading(-30, -70), 0.05), "ease")
    c.key("RArm", 72, [0, 0, 0, 0, 0, 0], "drift")
    c.key("LArm", 72, [0, 0, 0, 0, 0, 0], "drift")
    c.key("Neck", 4, [24, 0, 0], "whip")
    c.key("Neck", 28, [-18, 0, 0], "ease")
    c.key("Neck", 72, [-4, 0, 0], "drift")
    return c


def parried():
    c = Clip("Combat Parried", 54, hit=None, arm="RArm", joints=UPPER)
    c.peak = 4
    for joint in UPPER:
        c.key(joint, 0, ZERO if joint != "Neck" else [0, 0, 0])
    knocked = [18, 35, -10, 0, -0.05, 0.4]
    r = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    r(4, knocked, "whip")
    r(14, [14, 28, -8, 0, -0.1, 0.45], "stop")
    r(40, [-6, 8, -2, 0, -0.15, 0.1], "settle")
    r(54, [-4, 4, 0, 0, -0.1, 0.05], "drift")
    c.key("RArm", 4, reach("RArm", knocked, heading(150, 55), 0.25, twist=-40), "whip")  # the strike thrown back
    c.key("RArm", 40, reach("RArm", [-6, 8, -2, 0, -0.15, 0.1], heading(30, -60), 0.05), "settle")
    c.key("LArm", 4, reach("LArm", knocked, heading(-70, -10), 0.3, twist=30), "whip")
    c.key("LArm", 40, reach("LArm", [-6, 8, -2, 0, -0.15, 0.1], heading(-25, -70), 0.05), "settle")
    c.key("Neck", 4, [16, 0, 10], "whip")
    c.key("Neck", 40, [-8, 0, 0], "settle")
    return c


CLIPS = [block, parry, hit, shocked, guard_break, parried]
# the Animation names the client looks up -> the KeyframeSequence clip
NAMES = {"Block": "Combat Block", "Parry": "Combat Parry", "Hit": "Combat Hit", "Shocked": "Combat Shocked",
         "GuardBreak": "Combat GuardBreak", "Parried": "Combat Parried"}


def bake_all():
    return [(c, c.bake()) for c in (make() for make in CLIPS)]


if __name__ == "__main__":
    for c, _baked in bake_all():
        print("%-20s %3d frames  loop %-5s smoothing %s" % (c.name, c.frames, c.loop, c.smoothing))
