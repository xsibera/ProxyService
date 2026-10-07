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
import os
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from animkit import (  # noqa: E402
    UPPER,
    Clip,
    build_string,
    clip_transforms,
    mirror,
    prop,
    ref,
    reference_rig,
    rest_pose,
    sequence_xml,
    world_leg,
)

HERE = os.path.dirname(os.path.abspath(__file__))
JOINTS = list(UPPER)
FULL = UPPER + ("RLeg", "LLeg")  # moves that are allowed to drive the legs


# --------------------------------------------------------------------------- the combo
def m1_1():
    """Lead (left) snap jab: short coil, fastest whip, aimed high."""
    c = Clip("m1-1", 50, hit=20, arm="LArm")
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
    c = Clip("m1-2", 50, hit=24, arm="RArm")
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
    c = Clip("m1-3", 50, hit=24, arm="LArm")
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


def _rear_uppercut():
    """Rear (right) uppercut: sinks low and forward, then explodes up and back on the rising fist."""
    c = Clip("m1-4", 50, hit=25, arm="RArm")
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


def m1_4():
    """Finisher: the uppercut thrown with the left hand (the rear uppercut, mirrored), so it comes
    straight off the right overhand of m1-2."""
    return _rear_uppercut().mirrored()


def m1_5():
    """Finisher: spinning backfist. Coils, pirouettes 330 deg clockwise with the right arm flung out,
    and lands the back of the fist side-on, then holds the pose longer."""
    c = Clip("m1-5", 60, hit=39, arm="RArm")
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


def running_attack():
    """Off a sprint: the left foot plants long, the body sits back and winds, then drives a right
    cross through the target as the torso whips round and drops into a deep lunge, rear leg
    trailing. Keys the legs (world-aimed, so the stride stays along the run)."""
    c = Clip("running attack", 54, hit=22, arm="RArm", joints=FULL)
    run = [-18, 0, 0, 0, -0.2, 0]
    coil = [-8, -45, 6, 0, -0.38, 0.25]
    lunge = [-26, 70, -8, 0, -0.74, -0.62]
    held = [-20, 58, -5, 0, -0.66, -0.5]
    R = lambda f, v, k="ease": c.key("Root", f, v, k)
    R(0, run)
    R(10, coil, "coil")
    R(26, lunge, "whip")
    R(42, held, "settle")
    R(54, [-21, 60, -5, 0, -0.67, -0.5], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)
    N(0, [-10, 0, 0])
    N(10, [-12, 0, -4], "coil")
    N(22, [-16, 0, 8], "snap")
    N(26, [-18, 0, 10], "stop")
    N(42, [-14, 0, 7], "settle")
    N(54, [-15, 0, 7], "drift")
    # the cross: from the run swing, chambered at the hip, then out of the side toward the target
    Rr = lambda f, v, k="ease": c.key("RArm", f, v, k)
    Rr(0, [-45, 0, 8, 0, 0, 0])
    Rr(4, [-34, 6, 12, 0.02, 0.06, 0.1])
    Rr(10, [-22, 20, 30, 0.1, 0.24, 0.6], "coil")
    Rr(17, [-26, 24, 36, 0.12, 0.3, 0.7], "slowin")
    Rr(22, [30, 10, 97, 0.58, -0.08, -0.26], "armstrike")
    Rr(24, [16, 4, 92, 0.72, -0.14, -0.34], "stop")  # reaches further than a standing cross
    Rr(27, [19, 7, 97, 0.64, -0.16, -0.2], "ease")
    Rr(42, [12, 3, 94, 0.54, -0.16, 0.02], "settle")
    Rr(54, [13, 2, 95, 0.56, -0.15, -0.02], "drift")
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)
    L(0, [45, 0, -8, 0, 0, 0])
    L(10, [56, -36, -40, 0.26, 0.2, -0.6], "coil")  # reaches for the target as the body winds
    L(17, [60, -40, -44, 0.26, 0.22, -0.64], "slowin")
    L(22, [26, -10, -52, 0.34, -0.27, 0.58], "snap")  # yanked back to the hip
    L(26, [18, -8, -50, 0.36, -0.3, 0.62], "stop")
    L(42, [18, -10, -55, 0.34, -0.3, 0.6], "settle")
    L(54, [17, -12, -55, 0.33, -0.31, 0.61], "drift")
    # legs: mid-stride -> left foot swings through and plants long -> lunge with the rear leg trailing
    for f, root, k, right, left in (
        (0, run, "ease", (32, 4), (-28, 4)),
        (10, coil, "coil", (-12, 5), (34, 6)),
        (26, lunge, "whip", (-55, 7), (50, 8)),
        (42, held, "settle", (-50, 6), (46, 7)),
    ):
        twist = 0.4 * root[1]  # the hips follow the torso a little, the feet stay on the run line
        c.key("RLeg", f, world_leg("RLeg", root, right[0], right[1], twist), k)
        c.key("LLeg", f, world_leg("LLeg", root, left[0], left[1], twist), k)
    return c


def aerial_attack():
    """In the air: tucks the knees up and leans back with the right fist cocked over the head, holds
    it loaded, then dives forward and down through a hammering downward punch as the legs kick out
    behind. Built to spike a target toward the ground."""
    c = Clip("aerial attack", 54, hit=26, arm="RArm", joints=FULL)
    air = [-5, 0, 0, 0, 0, 0]
    tuck = [22, -30, 8, 0, 0.35, 0.3]
    load = [24, -34, 9, 0, 0.38, 0.32]
    dive = [-48, 25, -10, 0, -0.45, -0.45]
    held = [-40, 20, -6, 0, -0.35, -0.35]
    R = lambda f, v, k="ease": c.key("Root", f, v, k)
    R(0, air)
    R(14, tuck, "coil")
    R(20, load, "slowin")
    R(30, dive, "snap")
    R(44, held, "settle")
    R(54, [-41, 21, -6, 0, -0.36, -0.36], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)
    N(0, [-6, 0, 0])
    N(14, [-24, 0, -4], "coil")  # eyes down on the target past the knees
    N(20, [-26, 0, -4], "slowin")
    N(26, [10, 0, 6], "snap")  # head comes up against the dive
    N(30, [16, 0, 8], "stop")
    N(44, [12, 0, 6], "settle")
    N(54, [13, 0, 6], "drift")
    Rr = lambda f, v, k="ease": c.key("RArm", f, v, k)
    Rr(0, [10, 0, 10, 0, 0, 0])
    Rr(4, [36, 10, 30, 0.0, 0.06, -0.1])
    Rr(14, [160, 20, 40, -0.2, 0.4, 0.4], "coil")  # cocked straight up behind the head
    Rr(20, [168, 24, 44, -0.2, 0.45, 0.5], "slowin")
    Rr(26, [88, 4, 14, 0.1, -0.2, -0.6], "armstrike")  # hammers down and forward
    Rr(29, [78, 0, 12, 0.12, -0.32, -0.72], "stop")
    Rr(32, [84, 2, 14, 0.1, -0.28, -0.64], "ease")
    Rr(44, [86, 4, 15, 0.1, -0.26, -0.6], "settle")
    Rr(54, [85, 4, 15, 0.1, -0.26, -0.6], "drift")
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)
    L(0, [10, 0, -10, 0, 0, 0])
    L(14, [70, -20, -20, 0.2, 0.1, -0.4], "coil")  # aims down at the target
    L(20, [74, -22, -22, 0.2, 0.12, -0.42], "slowin")
    L(26, [-30, -20, -60, 0.1, 0.1, 0.4], "snap")  # thrown back for balance
    L(30, [-38, -22, -66, 0.12, 0.12, 0.44], "stop")
    L(44, [-30, -20, -60, 0.1, 0.1, 0.4], "settle")
    L(54, [-31, -20, -61, 0.1, 0.1, 0.41], "drift")
    G = lambda leg, f, v, k="ease": c.key(leg, f, v, k)
    G("RLeg", 0, [10, 0, 4, 0, 0, 0])
    G("LLeg", 0, [-10, 0, -4, 0, 0, 0])
    G("RLeg", 14, [72, 0, 8, 0, 0, 0], "coil")  # knees up
    G("LLeg", 14, [62, 0, -8, 0, 0, 0], "coil")
    G("RLeg", 20, [76, 0, 8, 0, 0, 0], "slowin")
    G("LLeg", 20, [66, 0, -8, 0, 0, 0], "slowin")
    G("RLeg", 30, [-36, 0, 10, 0, 0, 0], "snap")  # kicked out behind with the dive
    G("LLeg", 30, [-22, 0, -14, 0, 0, 0], "snap")
    G("RLeg", 44, [-30, 0, 8, 0, 0, 0], "settle")
    G("LLeg", 44, [-16, 0, -10, 0, 0, 0], "settle")
    G("RLeg", 54, [-30, 0, 8, 0, 0, 0], "drift")
    G("LLeg", 54, [-17, 0, -10, 0, 0, 0], "drift")
    return c


CLIPS = [m1_1, m1_2, m1_3, m1_4, m1_5, running_attack, aerial_attack]

# --------------------------------------------------------------------------- full-string preview
# Every hit is cancelled into the next one this long after it starts (about 0.15s after its
# impact), crossfading over STRING_FADE (use AnimationTrack:Play(0.15) in game for the same blend).
STRING_NAME = "m1 string (1,2,1,2,4)"
STRING_ORDER = ["m1-1", "m1-2", "m1-1", "m1-2", "m1-4"]
STRING_CANCEL = {"m1-1": 0.48, "m1-2": 0.55, "m1-3": 0.55, "m1-4": 0.58}
STRING_FADE = 0.15
STRING_END_FADE = 0.3


def build(rig_source=None, out_dir=HERE):
    baked_all = {}
    sequences = []
    by_name = {}
    for make in CLIPS:
        clip = make()
        baked = clip.bake()
        baked_all[clip.name] = {"hit": clip.hit, "frames": clip.frames, "channels": {j: baked[j].tolist() for j in clip.joints}}
        frames = clip_transforms(clip, baked)
        by_name[clip.name] = (clip, frames)
        print("%s: strike sigma %.2f, jerk cut x%.2f" % ((clip.name,) + clip.smoothing))
        sequences.append(sequence_xml(clip.name, frames, clip.markers))
    # always ship the whole string as one animation so the combo can be previewed in one go
    rest = rest_pose(JOINTS)
    string_frames, string_hits = build_string(
        [by_name[n] for n in STRING_ORDER], STRING_CANCEL, STRING_FADE, STRING_END_FADE, rest, rest
    )
    sequences.append(sequence_xml(STRING_NAME, string_frames, string_hits))
    json.dump(baked_all, open(os.path.join(out_dir, "combo_data.json"), "w"))

    root = ET.Element("roblox", {"version": "4"})
    if rig_source:
        # reuse the reference "normal player" rig (same parts, joints and look) with new AnimSaves
        rig, saves = reference_rig(rig_source, "Fist Combo Rig")
        for s in sequences:
            saves.append(s)
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
