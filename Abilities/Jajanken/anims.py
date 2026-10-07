"""Gon's Jajanken animations (R6), in the style of the reference animations and built with animkit.

  Jajanken Charge   0.4s   drops from standing into Gon's stance: a deep lunge, left foot forward,
                           body turned side-on, right fist drawn back by the hip, left hand
                           reaching out at the target
  Jajanken Hold     1s     looped while charging: the stance breathing and the fist trembling
  Jajanken Rock     0.9s   lunging straight right from the hip, the whole body behind it   (Hit)
  Jajanken Paper    0.85s  open-palm thrust from the hip that throws the aura ball         (Hit)
  Jajanken Scissors 0.85s  two-finger blade swept flat across the front, right to left      (Hit)

Every release starts on the stance pose exactly, so it can cut in from the hold at any frame.
The legs are keyed (it's a planted stance), aimed in world space with animkit.world_leg.
"""

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ANIMS = os.path.join(HERE, "..", "..", "Animations")
sys.path.insert(0, ANIMS)
sys.path.insert(0, os.path.join(ANIMS, "SwordCombo"))
from animkit import FPS, UPPER, Clip, from_transform, to_transform, world_leg  # noqa: E402
from generate_sword import MOTORS, cf, inv, joint_cf  # noqa: E402

FULL = UPPER + ("RLeg", "LLeg")

# virtual shoulders (top centre of each arm at rest) that arms are aimed from, Torso space
SHOULDER = {"RArm": np.array([1.5, 1.0, 0.0]), "LArm": np.array([-1.5, 1.0, 0.0])}


def _rot_between(a, b):
    a, b = a / np.linalg.norm(a), b / np.linalg.norm(b)
    axis = np.cross(a, b)
    s, c = np.linalg.norm(axis), float(a @ b)
    if s < 1e-9:
        return np.eye(3) if c > 0 else np.diag([1.0, -1.0, -1.0])
    k = axis / s
    kx = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + s * kx + (1 - c) * kx @ kx


def _about(axis, deg):
    k = axis / np.linalg.norm(axis)
    a = math.radians(deg)
    kx = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + math.sin(a) * kx + (1 - math.cos(a)) * kx @ kx


def torso_of(root):
    return joint_cf("Root", root)


def arm_to(joint, root, fist, arm_dir=None, twist=0.0):
    """Arm channels that put the fist (bottom centre of the arm) at `fist`, given in world (root)
    space for Root channels `root`. The arm points from its shoulder to the fist unless `arm_dir`
    (world) is given; it slides out of the socket as far as that needs, like the reference arms.
    `twist` turns the arm about its own length (deg)."""
    t = torso_of(root)
    to_torso = inv(t)
    f = (to_torso @ np.append(np.asarray(fist, float), 1))[:3]
    if arm_dir is None and np.linalg.norm(f - SHOULDER[joint]) < 2.0:
        # closer than an arm's length: the rigid R6 arm would poke up out of the shoulder, so the
        # fist goes a full arm's length out along the same line instead
        f = SHOULDER[joint] + (f - SHOULDER[joint]) / np.linalg.norm(f - SHOULDER[joint]) * 2.0
    a = (to_torso[:3, :3] @ np.asarray(arm_dir, float)) if arm_dir is not None else f - SHOULDER[joint]
    rot = _rot_between(np.array([0.0, -1.0, 0.0]), a)
    if twist:
        rot = _about(a, twist) @ rot
    arm_cf = cf(f - rot @ np.array([0.0, -1.0, 0.0]), rot)
    c0, c1 = MOTORS[joint]
    m = inv(c0) @ arm_cf @ c1
    return [round(float(v), 4) for v in from_transform(joint, m[:3, 3], m[:3, :3])]


GROUND = -3.0  # the floor, in root space (HumanoidRootPart centre 3 studs up)


def foot(joint, root, ch):
    """World (root space) bottom centre of a foot."""
    c0, c1 = MOTORS[joint]
    pos, rot = to_transform(joint, ch)
    leg = torso_of(root) @ c0 @ cf(pos, rot) @ inv(c1)
    return (leg @ np.array([0, -1.0, 0, 1]))[:3]


def planted(joint, root, direction, roll, yaw=0.0):
    """Leg channels swinging the leg forward (direction +1) or back (-1) just far enough that the
    foot lands on the floor, rolled out `roll` degrees and turned `yaw` about the vertical."""
    lo, hi = 0.0, 85.0
    for _ in range(40):
        mid = (lo + hi) / 2
        y = foot(joint, root, world_leg(joint, root, direction * mid, roll, yaw))[1]
        if y < GROUND:
            lo = mid  # still through the floor: swing it further
        else:
            hi = mid
    return world_leg(joint, root, direction * hi, roll, yaw)


def legs(c, f, root, front_roll=10, back_roll=12, k="ease", front_yaw=0.0, back_yaw=0.0):
    """Key both legs at frame f, planted: the left (lead) leg forward, the right leg back."""
    c.key("LLeg", f, planted("LLeg", root, 1, front_roll, front_yaw), k)
    c.key("RLeg", f, planted("RLeg", root, -1, back_roll, back_yaw), k)


def reach(joint, root, direction, extra, twist=0.0):
    """Arm channels pointing the arm along a world direction from its shoulder, sliding `extra`
    studs out of the socket for reach (the reference punches slide 0.5-1.2)."""
    d = np.asarray(direction, float)
    d = d / np.linalg.norm(d)
    shoulder = (torso_of(root) @ np.append(SHOULDER[joint], 1))[:3]
    return arm_to(joint, root, shoulder + d * (2.0 + extra), twist=twist)


def heading(azimuth, elevation=0.0):
    """World direction: azimuth clockwise from straight ahead (deg), elevation up (deg)."""
    a, e = math.radians(azimuth), math.radians(elevation)
    return [math.sin(a) * math.cos(e), math.sin(e), -math.cos(a) * math.cos(e)]


# --------------------------------------------------------------------------- the stance
# Root channels: [pitch (+ leans back), yaw (+ turns left), roll, x, y, z]
STANDING = [0, 0, 0, 0, 0, 0]
STANCE = [-8, -30, 3, 0.05, -0.6, 0.05]  # deep and side-on: right shoulder back, leaning in
STANCE_RFIST = [1.6, -0.95, 1.45]  # world: drawn back past the right hip
STANCE_LFIST = [-0.75, -0.95, -2.45]  # world: reaching out low at the target
STANCE_NECK = [-6, 0, 0]


def stance_rarm(root=STANCE):
    return arm_to("RArm", root, STANCE_RFIST, twist=-30)


def stance_larm(root=STANCE):
    return arm_to("LArm", root, STANCE_LFIST, twist=20)


def key_stance(c, f, k="ease"):
    c.key("Root", f, STANCE, k)
    c.key("Neck", f, STANCE_NECK, k)
    c.key("RArm", f, stance_rarm(), k)
    c.key("LArm", f, stance_larm(), k)
    legs(c, f, STANCE, 14, 14, k=k)


def charge():
    """Standing -> the stance: a quick drop with the fist pulled back, sinking past the stance and
    settling into it (0.4s)."""
    c = Clip("Jajanken Charge", 24, hit=None, arm="RArm", joints=FULL)
    c.peak = 10
    c.key("Root", 0, STANDING)
    c.key("Neck", 0, [0, 0, 0])
    c.key("RArm", 0, [0, 0, 0, 0, 0, 0])
    c.key("LArm", 0, [0, 0, 0, 0, 0, 0])
    c.key("LLeg", 0, [0, 0, 0, 0, 0, 0])
    c.key("RLeg", 0, [0, 0, 0, 0, 0, 0])
    sink = [-11, -34, 4, 0.05, -0.72, 0.1]
    c.key("Root", 14, sink, "accel")
    c.key("Neck", 14, [-9, 0, 0], "accel")
    c.key("RArm", 10, arm_to("RArm", sink, [1.7, -1.0, 1.25], twist=-30), "accel")
    c.key("LArm", 12, arm_to("LArm", sink, [-0.6, -0.75, -2.45], twist=20), "accel")
    c.key("LLeg", 7, planted("LLeg", [-5, -16, 2, 0.02, -0.3, 0.03], 1, 10), "accel")
    c.key("RLeg", 7, planted("RLeg", [-5, -16, 2, 0.02, -0.3, 0.03], -1, 10), "accel")
    legs(c, 14, sink, 14, 14, k="accel")
    key_stance(c, 24, "settle")
    return c


def hold():
    """Looped while charging (1s): the stance breathing slowly while the drawn fist trembles with the
    aura building in it. Keyed every frame from waves that repeat exactly each second."""
    c = Clip("Jajanken Hold", 60, hit=None, arm="RArm", joints=FULL)
    c.loop = True
    c.smooth = False
    c.neck_auto = False
    for f in range(61):
        u = f / 60
        breath = math.sin(2 * math.pi * u)
        shake = math.sin(2 * math.pi * 6 * u)
        shake2 = math.sin(2 * math.pi * 9 * u + 1.3)
        root = list(STANCE)
        root[0] += 0.8 * breath
        root[2] += 0.35 * shake2
        root[4] += 0.03 * breath
        c.key("Root", f, root, "linear")
        c.key("Neck", f, [STANCE_NECK[0] - 0.6 * breath, -0.95 * STANCE[1], 0.3 * shake], "linear")
        fist = np.array(STANCE_RFIST) + np.array([0.02 * shake2, 0.025 * shake, 0.02 * shake2])
        c.key("RArm", f, arm_to("RArm", root, fist, twist=-30 + 2.5 * shake), "linear")
        c.key("LArm", f, arm_to("LArm", root, np.array(STANCE_LFIST) + [0, 0.04 * breath, 0], twist=20), "linear")
        legs(c, f, root, 14, 14, k="linear")
    return c


def rock():
    """Rock: from the stance the hips drive and the right fist rips straight out from the hip at
    chest height, the body lunging in behind it and the left hand yanked back. Hit at 0.2s; the
    fist stays out through the blast, then the body comes up out of the stance."""
    c = Clip("Jajanken Rock", 54, hit=12, arm="RArm", joints=FULL)
    key_stance(c, 0)
    load = [-10, -38, 4, 0.05, -0.66, 0.12]
    drive = [-16, 48, -6, -0.05, -0.62, -0.7]
    held = [-13, 40, -4, -0.04, -0.6, -0.58]
    up = [-5, 16, -1, 0, -0.25, -0.2]
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(4, load, "coil")
    R(13, drive, "whip")
    R(32, held, "settle")
    R(54, up, "ease")
    c.key("Neck", 4, [-8, 0, 0], "coil")
    c.key("Neck", 12, [-14, 0, 6], "snap")
    c.key("Neck", 32, [-11, 0, 4], "settle")
    c.key("Neck", 54, [-4, 0, 1], "ease")
    # the punch: chambered a touch further back, then out along the target line at chest height
    c.key("RArm", 4, arm_to("RArm", load, [1.75, -1.0, 1.3], twist=-30), "coil")
    c.key("RArm", 9, reach("RArm", drive, heading(20, -32), 0.0), "slowin")
    c.key("RArm", 12, reach("RArm", drive, heading(-6, -4), 0.2), "armstrike")
    c.key("RArm", 15, reach("RArm", drive, heading(-6, -5), 0.3), "stop")
    c.key("RArm", 32, reach("RArm", held, heading(-5, -5), 0.15), "settle")
    c.key("RArm", 54, arm_to("RArm", up, [0.9, 0.1, -1.6]), "ease")
    c.key("LArm", 4, arm_to("LArm", load, [-0.65, -0.5, -2.45], twist=20), "coil")
    c.key("LArm", 12, arm_to("LArm", drive, [-1.35, -0.35, 0.35]), "snap")
    c.key("LArm", 32, arm_to("LArm", held, [-1.4, -0.4, 0.3]), "settle")
    c.key("LArm", 54, arm_to("LArm", up, [-1.45, -0.9, -0.3]), "ease")
    legs(c, 4, load, 14, 14, k="coil")
    legs(c, 13, drive, 12, 12, "whip", back_yaw=20)
    legs(c, 32, held, 12, 12, "settle", back_yaw=20)
    legs(c, 54, up, 8, 8, "ease", back_yaw=12)
    return c


def paper():
    """Paper: the right hand comes up from the hip into an open-palm thrust straight at the target,
    the ball of aura leaving the palm on the Hit marker; the left hand stays forward to guide it."""
    c = Clip("Jajanken Paper", 51, hit=13, arm="RArm", joints=FULL)
    key_stance(c, 0)
    load = [-9, -36, 4, 0.05, -0.65, 0.1]
    push = [-5, 26, -3, 0, -0.58, -0.42]
    held = [-4, 22, -2, 0, -0.56, -0.36]
    up = [-3, 10, -1, 0, -0.25, -0.15]
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(4, load, "coil")
    R(14, push, "whip")
    R(32, held, "settle")
    R(51, up, "ease")
    c.key("Neck", 4, [-8, 0, 0], "coil")
    c.key("Neck", 13, [-10, 0, 4], "snap")
    c.key("Neck", 32, [-8, 0, 2], "settle")
    c.key("Neck", 51, [-3, 0, 0], "ease")
    # palm out: the arm straight along the line with the hand cocked up (twisted palm-forward)
    c.key("RArm", 4, arm_to("RArm", load, [1.7, -0.95, 1.2], twist=-30), "coil")
    c.key("RArm", 9, reach("RArm", push, heading(15, -28), 0.0, twist=40), "slowin")
    c.key("RArm", 13, reach("RArm", push, heading(-8, 2), 0.1, twist=90), "armstrike")
    c.key("RArm", 16, reach("RArm", push, heading(-8, 2), 0.2, twist=90), "stop")
    c.key("RArm", 32, reach("RArm", held, heading(-7, 1), 0.05, twist=90), "settle")
    c.key("RArm", 51, arm_to("RArm", up, [0.9, 0.0, -1.5], twist=30), "ease")
    c.key("LArm", 4, arm_to("LArm", load, [-0.6, -0.55, -2.5], twist=20), "coil")
    c.key("LArm", 13, arm_to("LArm", push, [-0.95, 0.05, -2.2], twist=20), "snap")
    c.key("LArm", 32, arm_to("LArm", held, [-1.0, -0.05, -2.1], twist=20), "settle")
    c.key("LArm", 51, arm_to("LArm", up, [-1.4, -0.9, -0.4]), "ease")
    legs(c, 4, load, 14, 14, k="coil")
    legs(c, 14, push, 12, 12, "whip", back_yaw=12)
    legs(c, 32, held, 12, 12, "settle", back_yaw=12)
    legs(c, 51, up, 8, 8, "ease", back_yaw=8)
    return c


def scissors():
    """Scissors: the two-finger blade of aura swept flat across the front at chest height, from out
    on the right round to the left, the torso whipping through with it. Hit as it crosses the
    middle; it follows through to the left and holds before coming up."""
    c = Clip("Jajanken Scissors", 51, hit=13, arm="RArm", joints=FULL)
    c.slerp = {"RArm"}
    key_stance(c, 0)
    load = [-9, -55, 5, 0.05, -0.64, 0.1]
    held = [-8, 58, -6, -0.04, -0.6, -0.3]
    up = [-4, 22, -2, 0, -0.25, -0.12]
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(5, load, "coil")
    # the sweep itself: root and arm keyed together every 2 frames so the hand rides the arc
    sweep = list(range(7, 20, 2))
    for i, f in enumerate(sweep):
        u = i / (len(sweep) - 1)
        root = [-9 + 1 * u, -55 + 125 * u, 5 - 11 * u, 0.05 - 0.09 * u, -0.64 + 0.04 * u, 0.1 - 0.4 * u]
        R(f, root, "linear" if i else "slowin")
        az = 75 - 155 * u  # from out on the right (+) to the left (-)
        c.key("RArm", f, reach("RArm", root, heading(az, -6), 0.1, twist=-90), "linear" if i else "slowin")
    R(30, held, "settle")
    R(51, up, "ease")
    c.key("RArm", 30, reach("RArm", held, heading(-95, -10), 0.0, twist=-90), "settle")
    c.key("RArm", 51, arm_to("RArm", up, [-0.2, 0.0, -1.7]), "ease")
    c.key("RArm", 5, arm_to("RArm", load, [1.9, -0.6, 0.6], twist=-60), "coil")
    c.key("Neck", 5, [-8, 0, 0], "coil")
    c.key("Neck", 13, [-12, 0, -5], "snap")
    c.key("Neck", 30, [-9, 0, -3], "settle")
    c.key("Neck", 51, [-3, 0, 0], "ease")
    c.key("LArm", 5, arm_to("LArm", load, [-0.5, -0.6, -2.4], twist=20), "coil")
    c.key("LArm", 13, arm_to("LArm", [-8, 0, 0, 0, -0.62, 0], [-1.3, -0.6, 0.3]), "snap")
    c.key("LArm", 30, arm_to("LArm", held, [-1.2, -0.7, 0.9]), "settle")
    c.key("LArm", 51, arm_to("LArm", up, [-1.45, -0.9, 0.1]), "ease")
    legs(c, 5, load, 14, 14, k="coil")
    legs(c, 19, [-8, 70, -6, -0.04, -0.6, -0.3], 12, 12, "whip", back_yaw=18)
    legs(c, 30, held, 12, 12, "settle", back_yaw=18)
    legs(c, 51, up, 8, 8, "ease", back_yaw=10)
    return c


CLIPS = [charge, hold, rock, paper, scissors]
HIT_TIMES = {}  # filled by bake_all: release name -> Hit marker time (s)


def bake_all():
    out = []
    for make in CLIPS:
        c = make()
        baked = c.bake()
        out.append((c, baked))
        if c.hit is not None:
            HIT_TIMES[c.name] = c.hit / FPS
    return out
