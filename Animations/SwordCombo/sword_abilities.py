"""One-handed sword abilities for the sword set (generate_sword.py builds them into SwordCombo.rbxm):

  heavy rising slash  1.4s  a long, low wind-up with the sword drawn back past the left hip, its point
                            all but scraping the floor, then one heavy cut rising from his bottom left
                            to his top right as he steps through and comes up out of the crouch onto
                            his toes, the sword finishing high over the right shoulder (Hit 0.6s)
  spinning slash      1.2s  wound right with the sword drawn back low behind him, then a hop and a
                            full spin and a half, the blade held out flat at arm's length sweeping all
                            the way round him twice past the front, landing low in a wide stance and
                            coming back up into the stance (Hit at both passes, 0.47s and 0.62s)

Both drive the whole body. The sword is flown in world space the way the running and aerial attacks
fly it (the fist along a curve, the wrist keeping the blade on its own curve with the edge leading
the cut), and the legs are planted and solved on every frame by the shared leg solver
(Abilities/Shared/stance.py), the way the ability kits' attacks do it: feet at hip width, a support
leg standing upright, a stepping or kicking leg aimed from its hip.
"""

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, os.path.join(HERE, "..", "..", "Abilities", "Shared"))
import generate_sword as G  # noqa: E402
from animkit import Clip, curve  # noqa: E402
from stance import J, check_legs, gaze, keep, plant, solve_feet  # noqa: E402

FULL = G.JOINTS + ("RLeg", "LLeg")
heading = G.heading
SHOULDER = np.array([1.0, 0.5, 0.0, 1.0])  # the Right Shoulder's pivot, Torso space


def shoulder_world(root):
    return (G.joint_cf("Root", root) @ SHOULDER)[:3]


def through(points, u):
    """Catmull-Rom through [(u, point)] at u (clamped to the ends)."""
    us = [p[0] for p in points]
    ps = [np.asarray(p[1], float) for p in points]
    if u <= us[0]:
        return ps[0]
    if u >= us[-1]:
        return ps[-1]
    i = max(n for n in range(len(us) - 1) if us[n] <= u)
    p0, p1, p2, p3 = ps[max(i - 1, 0)], ps[i], ps[i + 1], ps[min(i + 2, len(ps) - 1)]
    u0, u1, u2, u3 = us[max(i - 1, 0)], us[i], us[i + 1], us[min(i + 2, len(us) - 1)]
    h = u2 - u1
    m1 = (p2 - p0) / max(u2 - u0, 1e-9) * h
    m2 = (p3 - p1) / max(u3 - u1, 1e-9) * h
    s = (u - u1) / h
    s2, s3 = s * s, s * s * s
    return (2 * s3 - 3 * s2 + 1) * p1 + (s3 - 2 * s2 + s) * m1 + (-2 * s3 + 3 * s2) * p2 + (s3 - s2) * m2


def finish(c):
    """Bake, solve the legs and head on every frame, check the legs, and keep the result for the
    sword set's build."""
    baked = c.bake()
    solve_feet(c, baked)
    check_legs(c, baked)
    c.baked = baked
    return c


# --------------------------------------------------------------------------- heavy rising slash
# The cut runs in a tilted plane: the blade turns through it from pointing back down past his left
# hip, through straight at the target, to up over his right shoulder.
FORWARD = np.array([0.0, 0.0, -1.0])
DIAGONAL = np.array([0.8, 0.6, 0.0])  # his bottom left to his top right


def rising_blade(theta):
    a = math.radians(theta)
    return math.cos(a) * FORWARD + math.sin(a) * DIAGONAL


def rising_edge(theta):
    a = math.radians(theta)
    return -math.sin(a) * FORWARD + math.cos(a) * DIAGONAL  # the way the blade's going


# the fist's path through the cut (world), by the blade's angle in the plane
RISING_HANDS = [
    (-125, (-1.15, -0.62, 0.12)),  # drawn back past the left hip (the point just off the floor)
    (-60, (-1.05, -0.8, -1.05)),
    (0, (0.0, -0.15, -2.15)),  # out at the target
    (60, (1.2, 0.95, -1.5)),
    (120, (1.5, 1.95, -0.35)),
    (140, (1.35, 2.25, 0.1)),  # high over the right shoulder
]
RISING_SWING = (30, 42)  # frames of the cut (the whip)
RISING_FROM, RISING_TO = -125, 132


def rising_theta(f):
    a, b = RISING_SWING
    return RISING_FROM + (RISING_TO - RISING_FROM) * curve("whip", (f - a) / (b - a))


def heavy_rising_slash():
    """A long, low wind-up: a small rise (the counter-move), then he sinks deep into a lunge, the
    torso wound hard to the left and the right foot stepped back, the sword drawn back low past the
    left hip with its point all but scraping the floor and the off hand out at the target; a beat
    loaded there, sinking deeper. Then one heavy cut: the torso unwinds and he comes up out of the
    crouch as the back foot drives through into a step, and the blade rises from his bottom left
    across the target to his top right, the off hand flung back the other way. He finishes up on his
    toes, the sword high over the right shoulder, holds it, and comes back to the stance."""
    c = Clip("heavy rising slash", 84, hit=None, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "Handle", "LArm"}
    G.stance_keys(c)
    counter = [0, 6, 0, 0, -0.12, 0.05]
    coil = [-24, 64, 12, 0, -0.62, 0.22]
    loaded = [-26, 68, 13, 0, -0.66, 0.24]
    rising = [-8, 14, 2, 0, -0.36, -0.2]
    up = [10, -50, -10, 0, -0.06, -0.45]
    over = [13, -57, -12, 0, 0.02, -0.5]
    held = [11, -53, -10, 0, -0.04, -0.48]
    end = [-3, -12, 1, 0, -0.2, -0.3]  # the left foot leading now: turned a touch right
    r = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    r(8, counter, "decel")
    r(24, coil, "coil")
    r(30, loaded, "slowin")
    r(36, rising, "snap")
    r(42, up, "decel")
    r(46, over, "stop")
    r(60, held, "settle")
    r(84, end, "ease")
    roots = G.root_path(c)

    def sword(f, theta, k="linear"):
        hand = through(RISING_HANDS, theta)
        G.fly(c, roots, f, hand, rising_blade(theta), rising_edge(theta), k)

    c.key("Handle", 0, [0, 0, 0, 0, 0, 0])
    c.key("RArm", 8, G.STANCE_RARM, "decel")
    c.key("Handle", 8, [0, 0, 0, 0, 0, 0], "decel")
    sword(24, -122, "coil")
    sword(30, RISING_FROM, "slowin")
    for f in range(RISING_SWING[0] + 1, RISING_SWING[1] + 1):
        sword(f, rising_theta(f))
    sword(46, 140, "stop")
    sword(60, 138, "settle")
    c.key("RArm", 84, G.STANCE_RARM, "ease")
    c.key("Handle", 84, [0, 0, 0, 0, 0, 0], "ease")
    c.hit = next(f for f in range(RISING_SWING[0], RISING_SWING[1] + 1) if rising_theta(f) >= 0)
    c.peak = c.hit
    c.markers = {c.hit: ["Hit"]}
    # the off hand: out at the target through the wind-up, flung back the other way through the cut
    c.key("LArm", 8, G.STANCE_LARM, "decel")
    c.key("LArm", 24, J.reach("LArm", coil, heading(8, 4), 0.1, twist=-20), "coil")
    c.key("LArm", 30, J.reach("LArm", loaded, heading(6, 4), 0.1, twist=-20), "slowin")
    c.key("LArm", 38, J.reach("LArm", rising, heading(-115, -35), 0.1, twist=-20), "snap")
    c.key("LArm", 46, J.reach("LArm", over, heading(-135, -28), 0.15, twist=-20), "stop")
    c.key("LArm", 60, J.reach("LArm", held, heading(-130, -32), 0.1, twist=-20), "settle")
    c.key("LArm", 84, G.STANCE_LARM, "ease")
    gaze(c, 0, (0, -0.05, -1))
    gaze(c, 24, (0, -0.08, -1), "coil")
    gaze(c, 46, (0, 0.06, -1), "stop")
    gaze(c, 84, (0, -0.05, -1), "ease")
    # legs: the left foot steps back into the lunge (the right one turned in, leading), then drives
    # through into a step forward as he cuts
    plant(c, 0, {"LLeg": (-0.6, -0.3), "RLeg": (0.55, 0.15)}, {"LLeg": 0.1, "RLeg": 0.25})
    plant(c, 8, {"LLeg": (-0.6, -0.3), "RLeg": (0.55, 0.15)}, None, "decel")
    plant(c, 15, {"LLeg": (-0.6, -2.6, 0.25), "RLeg": (0.58, 0.0)}, {"LLeg": 1.0, "RLeg": 0.1}, "ease")
    lunge = plant(c, 22, {"LLeg": (-0.5, 0.75), "RLeg": (0.6, -0.15)}, None, "decel")
    keep(c, 32, lunge, "slowin")
    plant(c, 35, {"LLeg": (-0.58, -2.6, 0.45), "RLeg": (0.6, -0.15)}, {"LLeg": 1.0, "RLeg": 0.3}, "accel")
    plant(c, 39, {"LLeg": (-0.62, -2.45, -0.45), "RLeg": (0.6, -0.15)}, None, "linear")
    step = plant(c, 43, {"LLeg": (-0.6, -1.35), "RLeg": (0.6, -0.15)}, {"LLeg": 0.15, "RLeg": 0.9}, "decel")
    keep(c, 60, step, "settle")
    keep(c, 84, step, "ease", {"LLeg": 0.1, "RLeg": 0.6})
    return finish(c)


# --------------------------------------------------------------------------- spinning slash
SPIN = (18, 40)  # frames of the spin
SPIN_FROM, SPIN_TO = -70, 450  # torso yaw: wound right, then a spin and a half to the left
ARM_OUT = 82  # the sword arm out to the right of the way the torso faces (deg)


def spin_yaw(f):
    a, b = SPIN
    u = min(1.0, max(0.0, (f - a) / (b - a)))
    s = u * u * u * (u * (6 * u - 15) + 10)  # smootherstep: wound up, flat out, unwinding
    return SPIN_FROM + (SPIN_TO - SPIN_FROM) * s


def spin_root(f):
    """The torso through the spin: crouched and leaning forward, rolled away from the sword, up off
    the floor in a hop in the middle and dropping into the landing."""
    a, b = SPIN
    u = (f - a) / (b - a)
    hop = math.sin(math.pi * min(1.0, max(0.0, (u - 0.1) / 0.8)))
    return [-16 + 6 * hop, spin_yaw(f), 9, 0, -0.55 + 0.95 * hop, 0.0]


def blade_azimuth(f):
    """Where the blade points (azimuth, clockwise from ahead): out past the sword arm, trailing it
    early in the spin and leading it at the end (the wrist whipping it through)."""
    a, b = SPIN
    u = min(1.0, max(0.0, (f - a) / (b - a)))
    return -spin_yaw(f) + ARM_OUT + 22 * (1 - u) - 12 * u


def spinning_slash():
    """Wound to the right in a low crouch, the sword drawn back flat behind him at waist height and
    the off hand out across the front; a beat loaded. Then a hop and a spin and a half to the left,
    the blade held out flat at arm's length, whipping all the way round him and past the front
    twice, the off hand out to the other side to balance it, the legs tucked under him; he lands low
    and wide, the sword carried on round to his left, then comes back up into the stance."""
    c = Clip("spinning slash", 72, hit=None, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "Handle", "LArm"}
    c.neck_auto = False  # the head goes round with him
    G.stance_keys(c)
    counter = [-2, 22, 2, 0, -0.25, 0.02]
    coil = [-18, SPIN_FROM, 6, 0, -0.62, 0.05]
    loaded = [-19, SPIN_FROM - 4, 6, 0, -0.66, 0.06]
    r = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    r(5, counter, "decel")
    r(14, coil, "coil")
    r(SPIN[0], loaded, "slowin")
    for f in range(SPIN[0] + 1, SPIN[1] + 1):
        r(f, spin_root(f), "linear")
    landed = [-20, SPIN_TO + 4, 4, 0, -0.68, -0.05]
    r(46, landed, "decel")
    r(54, [-14, SPIN_TO - 8, 2, 0, -0.55, -0.03], "settle")
    r(72, [G.STANCE_ROOT[0], G.STANCE_ROOT[1] + 360] + G.STANCE_ROOT[2:], "ease")
    roots = G.root_path(c)

    def spin_sword(f, k="linear"):
        az = -roots[f][1] + ARM_OUT
        hand = shoulder_world(roots[f]) + heading(az, -14) * 2.15
        baz = blade_azimuth(f)
        G.fly(c, roots, f, hand, heading(baz, -4), heading(baz - 90, 0), k)

    c.key("Handle", 0, [0, 0, 0, 0, 0, 0])
    c.key("RArm", 5, G.STANCE_RARM, "decel")
    c.key("Handle", 5, [0, 0, 0, 0, 0, 0], "decel")
    for f, k in ((14, "coil"), (SPIN[0], "slowin")):  # drawn back flat behind him, the point trailing
        az = -roots[f][1] + ARM_OUT + 8
        hand = shoulder_world(roots[f]) + heading(az, -18) * 2.05
        G.fly(c, roots, f, hand, heading(az + 28, -6), heading(az - 62, 0), k)
    for f in range(SPIN[0] + 1, SPIN[1] + 1):
        spin_sword(f)
    for f, k in ((46, "decel"), (54, "settle")):  # carried on round to his left
        az = -roots[f][1] + ARM_OUT - 18
        hand = shoulder_world(roots[f]) + heading(az, -16) * 2.1
        G.fly(c, roots, f, hand, heading(az - 14, -8), heading(az - 104, 0), k)
    c.key("RArm", 72, G.STANCE_RARM, "ease")
    c.key("Handle", 72, [0, 0, 0, 0, 0, 0], "ease")
    passes = [f for f in range(SPIN[0], SPIN[1] + 1)
              if math.floor(blade_azimuth(f) / 360) != math.floor(blade_azimuth(f + 1) / 360)]
    c.hit = passes[0]
    c.peak = c.hit
    c.markers = {f + 1: ["Hit"] for f in passes}
    # the off hand: across the front in the wind-up, out the other side through the spin (it turns
    # with the torso), down and back on landing
    c.key("LArm", 5, G.STANCE_LARM, "decel")
    c.key("LArm", 14, J.arm_t("LArm", [0.2, 0.4, -1.6], twist=-30), "coil")
    c.key("LArm", SPIN[0], J.arm_t("LArm", [0.3, 0.4, -1.55], twist=-30), "slowin")
    c.key("LArm", SPIN[0] + 6, J.arm_t("LArm", [-2.7, 0.9, 0.4], twist=-20), "accel")
    c.key("LArm", SPIN[1] - 4, J.arm_t("LArm", [-2.6, 0.7, 0.6], twist=-20), "linear")
    c.key("LArm", 46, J.arm_t("LArm", [-1.9, -0.6, 0.9], twist=-20), "decel")
    c.key("LArm", 54, J.arm_t("LArm", [-1.8, -0.5, 0.8], twist=-20), "settle")
    c.key("LArm", 72, G.STANCE_LARM, "ease")
    # the head turns with him, leading into the spin, and comes back to the target on landing
    n = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    n(5, G.STANCE_NECK, "decel")
    n(14, [-10, 55, 0], "coil")  # eyes on the target over the left shoulder, wound right
    n(SPIN[0], [-10, 58, 0], "slowin")
    n(SPIN[0] + 8, [-8, 35, 0], "linear")  # leading into the turn
    n(SPIN[1] - 4, [-8, 20, 0], "linear")
    n(46, [-10, -55, 0], "decel")  # past the front: looking back at the target
    n(54, [-8, -45, 0], "settle")
    n(72, G.STANCE_NECK, "ease")
    # legs: planted wide for the wind-up, tucked under him (turning with him) through the hop, and
    # landing wide
    plant(c, 0, {"LLeg": (-0.55, -0.15), "RLeg": (0.55, 0.2)}, {"LLeg": 0.1, "RLeg": 0.25})
    wide = plant(c, 14, {"LLeg": (-0.7, -0.55), "RLeg": (0.78, 0.55)}, {"LLeg": 0.15, "RLeg": 1.0}, "coil")
    keep(c, SPIN[0] + 2, wide, "slowin")
    for f in range(SPIN[0] + 4, SPIN[1] - 3):
        t = J.torso_of(roots[f])
        spots = {j: tuple((t @ np.array([x, -2.45, z, 1.0]))[:3]) for j, x, z in (("LLeg", -0.55, -0.35),
                                                                                  ("RLeg", 0.55, 0.1))}
        plant(c, f, spots, {"LLeg": 1.0, "RLeg": 1.0}, "linear")
    landing = plant(c, SPIN[1], {"LLeg": (-0.6, 0.6), "RLeg": (0.65, -0.55)}, {"LLeg": 0.9, "RLeg": 0.2}, "accel")
    keep(c, 54, landing, "settle")
    keep(c, 72, landing, "ease", {"LLeg": 0.5, "RLeg": 0.1})
    return finish(c)


ABILITIES = [heavy_rising_slash, spinning_slash]


def clips():
    return [make() for make in ABILITIES]


if __name__ == "__main__":
    for c in clips():
        print(c.name, c.frames, "frames, hits", sorted(c.markers), "smoothing", c.smoothing)
