"""The movement animations (R6, 60 fps), in the style of the reference animations and built with
the Jajanken solvers and the shared leg solver (Shared/stance.py: feet placed on every frame):

  Run      0.5s loop, played as Sprint: a sprint for Config.SprintSpeed. Each foot is down for 15%
           of the stride and slides back at exactly 26 studs/s while it is, so it stays planted (the
           client plays the run at the speed really gone). He leans in, sinks onto each planted foot
           and rises through each flight; each leg kicks up behind, folds and drives the knee up in
           front, reaches and claws back down; the arms swing against the legs; the head stays level.
  Jump     0.4s from the push off the floor (Roblox launches the instant the jump's pressed):
           stretched out tall with the arms thrown up, the knees tucked as he rises, opening out into
           the fall pose.
  Fall     0.8s loop: arms out for balance, the right knee up and the left leg trailing, drifting.
  Land     0.5s: the feet set down at hip width, a deep squat to soak it up (hips back over the
           heels, arms out front), and up again to stand.
  Roll     a forward roll: a dip, a dive with the hands reaching for the floor, tucked tight (knees
           to the chest, arms hugging the shins) as the body turns over, the feet coming back down at
           hip width and a rise out of the crouch. The client turns the character to face the way it
           rolls, so it only ever rolls forward.

Every clip keys the legs (they're the whole body), planted at hip width as in the reference ability
animations wherever the feet are on the floor.
"""

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "Animations"))
sys.path.insert(0, os.path.join(HERE, "..", "Shared"))
from animkit import FPS, Clip  # noqa: E402
from stance import J, check_legs, gaze, hips, plant, solve_feet  # noqa: E402

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


# --------------------------------------------------------------------------- shared
FORWARD = (0.0, -0.05, -1.0)  # where the head looks: straight down the line he's running
STILL = [0, 0, 0, 0, 0, 0]


def swing_arm(joint, forward, out=0.0, inward=0.0, extra=0.0, twist=0.0):
    """Arm channels for an arm swung `forward` deg from hanging (Torso space; negative: back), out to
    the side `out` deg and across the body `inward` deg, slid `extra` studs out of the shoulder."""
    s = 1 if joint == "RArm" else -1
    a, side = math.radians(forward), math.radians(out - inward)
    d = np.array([s * math.sin(side), -math.cos(side) * math.cos(a), -math.cos(side) * math.sin(a)])
    return J.arm_t(joint, J.SHOULDER[joint] + d * (2.0 + extra), twist * s)


def leg_spot(root, joint, forward, length=2.0, out=0.0):
    """Where a leg hanging in the air puts its foot: swung `forward` deg from straight down (world
    space; negative: back) and `out` deg to its side, `length` studs from its hip (under 2: the
    knee's bent, the leg slid up into the hip)."""
    s = -1 if joint == "LLeg" else 1
    a, b = math.radians(forward), math.radians(out)
    d = np.array([s * math.sin(b), -math.cos(b) * math.cos(a), -math.cos(b) * math.sin(a)])
    return tuple(hips(root)[joint] + d * length)


def _hermite(p0, m0, p1, m1, h, s):
    s2, s3 = s * s, s * s * s
    return (2 * s3 - 3 * s2 + 1) * p0 + (s3 - 2 * s2 + s) * h * m0 + (-2 * s3 + 3 * s2) * p1 + (s3 - s2) * h * m1


def _through(points, ends, u):
    """A smooth curve through [(u, point)] at u (Catmull-Rom tangents inside, `ends` at the ends)."""
    us = [p[0] for p in points]
    ps = [np.asarray(p[1], float) for p in points]
    ms = [np.asarray(ends[0], float)]
    for i in range(1, len(ps) - 1):
        ms.append((ps[i + 1] - ps[i - 1]) / (us[i + 1] - us[i - 1]))
    ms.append(np.asarray(ends[1], float))
    for i in range(len(ps) - 1):
        if us[i] <= u <= us[i + 1]:
            h = us[i + 1] - us[i]
            return _hermite(ps[i], ms[i], ps[i + 1], ms[i + 1], h, (u - us[i]) / h)
    return ps[-1]


# --------------------------------------------------------------------------- the run
RUN_FRAMES = 30  # one stride (a step on each foot): 0.5 s, looped
RUN_SPEED = 26  # studs/s the planted foot goes back at (Config.SprintSpeed); the client plays the run
#                 at the character's real speed over this, so the feet never skate
STANCE = 0.15  # of the stride each foot is down: a sprinter's short contacts and long flights
STRIDE = RUN_SPEED * RUN_FRAMES / FPS  # studs covered per stride
FOOT_X = 0.48
UNDER_HIP = 0.24  # z of the planted foot at mid-stance: under the hip (which sits back: he leans in)
# The right leg's swing between toe-off (at STANCE) and touching down again (at 1), as (phase, deg
# swung forward from straight down, studs from hip to foot: under 2 is the knee bending, the leg
# slid up into the hip). The left leg runs half a stride behind.
SWING = [
    (0.27, -56, 1.85),  # kicked up behind
    (0.37, -46, 1.6),  # the heel folding up as it starts through
    (0.50, 2, 1.35),  # tucked up under him, passing the planted leg
    (0.65, 60, 1.72),  # the knee driven up in front
    (0.80, 48, 1.97),  # reaching out
    (0.92, 37, 2.0),  # clawing back down onto the floor
]
TOE_OFF_TURN = -180.0  # deg per stride the leg is still swinging back at as the foot leaves the floor
TOUCHDOWN_TURN = -140.0  # and already sweeping back at as it lands


def run_foot(root, joint, phase):
    """Where a foot is at a phase of the stride (root space, for Root channels `root`): on the floor
    and going back at the run's speed for STANCE, then swung through and set down ahead again."""
    phase %= 1.0
    x = FOOT_X if joint == "RLeg" else -FOOT_X
    contact = UNDER_HIP - STRIDE * STANCE / 2
    if phase <= STANCE:
        return (x, GROUND, contact + STRIDE * phase)
    hip = hips(root)[joint]

    def angles(z, at):  # (deg forward, length) of a foot on the floor at z, from the hip at that phase
        h = hips(run_root(at if joint == "RLeg" else at + 0.5))[joint]
        return np.array([math.degrees(math.atan2(h[2] - z, h[1] - GROUND)), math.hypot(h[2] - z, h[1] - GROUND)])

    points = [(STANCE, angles(contact + STRIDE * STANCE, STANCE))]
    points += [(u, np.array([deg, length])) for u, deg, length in SWING]
    points += [(1.0, angles(contact, 1.0))]
    deg, length = _through(points, ((TOE_OFF_TURN, 0.0), (TOUCHDOWN_TURN, 0.0)), phase)
    a = math.radians(deg)
    return (x, hip[1] - length * math.cos(a), hip[2] - length * math.sin(a))


def run_root(phase):
    """The torso over the stride: leaning into the run, sinking onto each planted foot and rising
    through each flight, turning with the arms and rocking a touch over the foot that's down."""
    sink = (0.5 + 0.5 * math.cos(4 * math.pi * (phase - STANCE / 2))) ** 1.5  # 1 at mid-stance
    over = math.cos(2 * math.pi * (phase - STANCE / 2))  # +1 over the right foot, -1 the left
    pitch = -14 - 2.0 * sink
    yaw = -7 * math.cos(2 * math.pi * (phase - 0.03))  # the right shoulder forward with the right arm
    return [pitch, yaw, -2.2 * over, 0.06 * over, -0.18 - 0.27 * sink, 0.0]


def run_arm(joint, phase):
    """The arms swing against the legs: the right one furthest back as the right foot lands."""
    q = phase if joint == "RArm" else phase + 0.5
    swing = -math.cos(2 * math.pi * (q - 0.03))  # -1 back, +1 forward
    forward = 22 + 48 * swing  # (he leans in 16 deg: in the world, 54 forward to 42 back)
    reach = max(0.0, math.sin(math.radians(forward)))
    return swing_arm(joint, forward, out=6 * max(0.0, -swing), inward=22 * reach ** 1.3, twist=-10 * swing)


def run():
    c = Clip("Run", RUN_FRAMES, hit=None, arm="RArm", joints=FULL)
    c.loop = True
    c.smooth = False  # every frame is keyed from smooth, periodic curves
    for f in range(RUN_FRAMES + 1):
        phase = f / RUN_FRAMES
        c.key("Root", f, run_root(phase), "linear")
        for joint in ("RArm", "LArm"):
            c.key(joint, f, run_arm(joint, phase), "linear")
        root = run_root(phase)
        spots = {"RLeg": run_foot(root, "RLeg", phase), "LLeg": run_foot(root, "LLeg", phase + 0.5)}
        plant(c, f, spots, {"RLeg": 1.0, "LLeg": 1.0}, "linear")  # aimed from the hip: knees bend
    gaze(c, 0, FORWARD)
    return c


# --------------------------------------------------------------------------- jumping and landing
JUMP_FRAMES = 24
FALL_FRAMES = 48


def fall_pose(t):
    """The airborne pose at time t (s) of the fall loop: arms out for balance, the right knee up and
    the left leg trailing, all drifting slowly, so a long fall stays alive."""
    w = 2 * math.pi * t / (FALL_FRAMES / FPS)
    root = [-8 + 2 * math.sin(w), 3 * math.sin(w + 1.0), 3 * math.sin(w + 0.4), 0, 0.12, 0]
    arms = {
        "RArm": dict(forward=22 + 8 * math.sin(w + 0.6), out=52 + 7 * math.sin(w)),
        "LArm": dict(forward=14 + 8 * math.sin(w + 2.4), out=58 + 7 * math.sin(w + 1.9)),
    }
    legs = {
        "RLeg": (34 + 7 * math.sin(w + 0.3), 1.45, 6),
        "LLeg": (-14 + 6 * math.sin(w + 2.2), 1.8, 4),
    }
    return root, arms, legs


def key_fall(c, f, root, arms, legs, k="ease"):
    c.key("Root", f, root, k)
    for joint, a in arms.items():
        c.key(joint, f, swing_arm(joint, **a), k)
    plant(c, f, {j: leg_spot(root, j, *v) for j, v in legs.items()}, {"RLeg": 1.0, "LLeg": 1.0}, k)


def jump():
    """From the push off the floor (Roblox launches the instant the jump's pressed, so it starts
    there): stretched out tall, arms thrown up, then the knees tucked as he rises and opening out
    into the fall pose near the top."""
    c = Clip("Jump", JUMP_FRAMES, hit=None, arm="RArm", joints=FULL)
    c.peak = 4
    push = [-16, 0, 0, 0, -0.5, 0.05]
    reach = [-3, 0, 0, 0, 0.15, 0]
    tuck = [-12, 0, 1, 0, 0.2, 0]
    c.key("Root", 0, push)
    c.key("Root", 4, reach, "decel")
    c.key("Root", 11, tuck, "ease")
    for joint in ("RArm", "LArm"):
        c.key(joint, 0, swing_arm(joint, -38, out=8), "linear")
        c.key(joint, 4, swing_arm(joint, 128, out=14, inward=0), "decel")  # thrown up
        c.key(joint, 11, swing_arm(joint, 70, out=34), "ease")
    plant(c, 0, {"LLeg": (-0.5, 0.1), "RLeg": (0.5, 0.25)}, {"LLeg": 0.6, "RLeg": 0.6})
    plant(c, 4, {j: leg_spot(reach, j, -10, 2.0) for j in ("LLeg", "RLeg")}, {"LLeg": 1.0, "RLeg": 1.0}, "decel")
    plant(c, 11, {"RLeg": leg_spot(tuck, "RLeg", 52, 1.25, 4), "LLeg": leg_spot(tuck, "LLeg", 22, 1.45, 4)},
          None, "ease")
    root, arms, legs = fall_pose(0.0)
    key_fall(c, JUMP_FRAMES, root, arms, legs, "ease")
    gaze(c, 0, (0, -0.15, -1))
    gaze(c, 6, (0, 0.08, -1))
    gaze(c, JUMP_FRAMES, FORWARD)
    return c


def fall():
    c = Clip("Fall", FALL_FRAMES, hit=None, arm="RArm", joints=FULL)
    c.loop = True
    c.smooth = False
    for f in range(0, FALL_FRAMES + 1, 2):
        root, arms, legs = fall_pose(f / FPS)
        key_fall(c, f, root, arms, legs, "linear")
    gaze(c, 0, FORWARD)
    return c


def land():
    """Touching down out of the fall pose: the feet set down at hip width, the body dropping into a
    deep squat to soak it up (arms out front for balance), then standing back up."""
    c = Clip("Land", 30, hit=None, arm="RArm", joints=FULL)
    c.peak = 5
    root, arms, legs = fall_pose(0.0)
    touch = [-6, 0, 0, 0, 0, 0]
    impact = [-25, 0, 0, 0, -1.08, 0.18]
    soak = [-20, 0, 0, 0, -0.95, 0.12]
    rise = [-7, 0, 0, 0, -0.3, 0.03]
    c.key("Root", 0, touch)
    c.key("Root", 5, impact, "decel")
    c.key("Root", 10, soak, "ease")
    c.key("Root", 19, rise, "ease")
    c.key("Root", 30, STILL, "settle")
    for joint in ("RArm", "LArm"):
        c.key(joint, 0, swing_arm(joint, **arms[joint]))
        c.key(joint, 5, swing_arm(joint, 40, out=26), "decel")  # thrown out in front for balance
        c.key(joint, 10, swing_arm(joint, 34, out=22), "ease")
        c.key(joint, 19, swing_arm(joint, 10, out=8), "ease")
        c.key(joint, 30, STILL, "settle")
    feet = {"LLeg": (-0.58, 0.05), "RLeg": (0.58, -0.2)}
    plant(c, 0, {"LLeg": (-0.55, -2.85, 0.15), "RLeg": (0.55, -2.85, -0.25)}, {"LLeg": 0.4, "RLeg": 0.4})
    plant(c, 3, feet, {"LLeg": 0.9, "RLeg": 0.9}, "accel")  # hips sat back over the heels
    plant(c, 19, feet, {"LLeg": 0.6, "RLeg": 0.6}, "ease")
    plant(c, 30, {"LLeg": (-0.5, 0.0), "RLeg": (0.5, 0.0)}, {"LLeg": 0.0, "RLeg": 0.0}, "settle")
    gaze(c, 0, FORWARD)
    gaze(c, 5, (0, -0.22, -1), "decel")
    gaze(c, 19, FORWARD, "ease")
    return c


CLIPS = [roll, run, jump, fall, land]


def bake_all():
    out = []
    for make in CLIPS:
        c = make()
        baked = c.bake()
        if c.__dict__.get("feet") or c.__dict__.get("gazes"):
            solve_feet(c, baked)
            check_legs(c, baked)
        else:
            J.plant(baked)
        out.append((c, baked))
    return out


if __name__ == "__main__":
    for c, _baked in bake_all():
        print(c.name, c.frames, "frames")
