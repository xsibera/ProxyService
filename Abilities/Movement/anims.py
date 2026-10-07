"""The movement animations (R6, 60 fps):

  Sprint   the run from the reference file (ANIMSFORCLAUDE.rbxm, "normal player" > "new run"): the
           game's own run, looped, used as-is (generate_movement.py copies it over)
  Roll     a forward roll, in the style of the reference animations and built with the Jajanken
           solvers: a dip, a dive with the hands reaching for the floor, tucked tight (knees to the
           chest, arms hugging the shins) as the body turns over, the feet coming back down at hip
           width and a rise out of the crouch. The client turns the character to face the way it
           rolls, so it only ever rolls forward.

The roll keys the legs (it's the whole body), planted at hip width as in the reference ability
animations wherever the feet are on the floor.
"""

import importlib.util
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "Animations"))
from animkit import Clip  # noqa: E402


def _jajanken_solvers():
    spec = importlib.util.spec_from_file_location("jajanken_anims", os.path.join(HERE, "..", "Jajanken", "anims.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


J = _jajanken_solvers()
FULL = J.FULL
GROUND = J.GROUND
ROLL_FRAMES = 42


def tuck_legs(c, f, root, k="ease"):
    """The legs folded up in front of the belly (knees to the chest), each in its own lane."""
    t = J.torso_of(root)
    for joint, x in (("LLeg", -0.5), ("RLeg", 0.5)):
        foot = (t @ np.array([x, -0.45, -1.15, 1.0]))[:3]
        c.key(joint, f, J.leg_to(joint, root, foot), k)


def roll():
    c = Clip("Roll", ROLL_FRAMES, hit=None, arm="RArm", joints=FULL)
    c.peak = 12
    c.neck_auto = False
    stand = [0, 0, 0, 0, 0, 0]
    dip = [-22, 0, 0, 0, -0.5, -0.1]
    dive = [-80, 0, 0, 0, -1.3, -0.5]
    over = [-165, 0, 0, 0, -1.5, -0.3]  # the shoulders on the floor, the head just clear
    under = [-250, 0, 0, 0, -1.55, -0.1]
    out = [-312, 0, 0, 0, -1.35, 0.05]
    crouch = [-346, 0, 0, 0, -0.8, 0.05]
    rise = [-358, 0, 0, 0, -0.25, 0.0]
    up = [-360, 0, 0, 0, 0, 0]
    r = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    r(0, stand)
    r(4, dip, "decel")
    r(9, dive, "accel")
    r(15, over, "linear")
    r(21, under, "linear")
    r(26, out, "decel")
    r(31, crouch, "decel")
    r(37, rise, "ease")
    r(42, up, "settle")
    n = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    n(0, [0, 0, 0])
    n(4, [-12, 0, 0], "decel")
    n(9, [-30, 0, 0], "accel")  # chin tucked into the chest for the roll
    n(26, [-28, 0, 0], "linear")
    n(31, [-8, 0, 0], "decel")
    n(42, [0, 0, 0], "settle")
    for joint, s in (("RArm", 1), ("LArm", -1)):
        c.key(joint, 0, [0, 0, 0, 0, 0, 0])
        c.key(joint, 4, J.reach(joint, dip, J.heading(s * 15, -45), 0.15), "decel")
        c.key(joint, 9, J.reach(joint, dive, J.heading(s * 10, -75), 0.35), "accel")  # hands to the floor
        c.key(joint, 15, J.arm_t(joint, [s * 0.75, -0.95, -1.2], twist=s * 20), "linear")  # hugging the shins
        c.key(joint, 21, J.arm_t(joint, [s * 0.75, -0.95, -1.2], twist=s * 20), "linear")
        c.key(joint, 26, J.reach(joint, out, J.heading(s * 30, -10), 0.2), "decel")
        c.key(joint, 31, J.reach(joint, crouch, J.heading(s * 28, -25), 0.2), "decel")  # out for balance
        c.key(joint, 37, J.reach(joint, rise, J.heading(s * 12, -70), 0.05), "ease")
        c.key(joint, 42, [0, 0, 0, 0, 0, 0], "settle")
    for joint in ("LLeg", "RLeg"):
        c.key(joint, 0, [0, 0, 0, 0, 0, 0])
    J.feet_at(c, 4, dip, (-0.5, -0.1), (0.5, 0.25), "decel")
    J.feet_at(c, 9, dive, (-0.5, 0.45), (0.5, 0.6), "accel")  # pushing off
    tuck_legs(c, 15, over, "linear")
    tuck_legs(c, 21, under, "linear")
    tuck_legs(c, 26, out, "decel")
    J.feet_at(c, 31, crouch, (-0.5, -0.15), (0.5, 0.25), "decel")  # back on the floor at hip width
    J.feet_at(c, 37, rise, (-0.5, -0.1), (0.5, 0.15), "ease")
    for joint in ("LLeg", "RLeg"):
        c.key(joint, 42, [0, 0, 0, 0, 0, 0], "settle")
    return c


CLIPS = [roll]


def bake_all():
    out = []
    for make in CLIPS:
        c = make()
        baked = c.bake()
        J.plant(baked)
        out.append((c, baked))
    return out


if __name__ == "__main__":
    for c, _baked in bake_all():
        print(c.name, c.frames, "frames")
