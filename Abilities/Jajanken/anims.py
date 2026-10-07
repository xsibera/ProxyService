"""Gon's Jajanken animations (R6), in the style of the reference animations (ANIMSFORCLAUDE.rbxm: the
fist M1s and the "abilities" rig: nen burst, ice downslam, leg axe), built with animkit.

What Gon does: "Saisho wa guu!" - he drops into a deep squat, turns his body away from the target
and presses his right fist into his open left palm while the aura gathers in it. "Jan... Ken..." -
the fist leaves the palm and draws back. Then the release:
  Rock      ("Guu!")  he springs out of the squat into a lunging straight right
  Paper     ("Paa!")  a right palm thrust that throws the ball of aura, the body kicked back by it
  Scissors  ("Chii!") the two-finger blade swept flat across the front, right to left

The reference rhythm, applied to every release: a counter-move (the fist pops off the palm) ->
the coil (the torso winds 40-50 deg further away and the arm chambers out of its socket: "Jan...
Ken...") -> a loaded slow-in -> a 4-frame whip where the torso swings 140-180 deg and the strike
shoots out -> overshoot -> settle -> a slow drift on the held silhouette. The ability references
move big (torso swings of 180-220 deg, the body dropping up to 1.5 studs, arms sliding up to 1.3
studs out of the socket, legs sliding up into the hip to fake bent knees) and so do these.

  Jajanken Charge   0.45s  standing -> the squat, fist smacked into the palm
  Jajanken Hold     1.2s   looped while charging: breathing in the squat, the fist trembling in the palm
  Jajanken Rock     0.95s  Hit at 0.4s
  Jajanken Paper    0.9s   Hit at 0.367s (the ball leaves the palm)
  Jajanken Scissors 0.9s   Hit at 0.333s (crossing the front)

Every release starts on the squat pose exactly, so it can cut in from the hold at any frame. The
legs are keyed: aimed in world space, then slid up into the hip just enough for the foot to meet the
floor (how the reference fakes a bent knee on a rigid R6 leg).
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
# The legs are left to the walk: every clip keys them at Weight 0, so the player can walk while
# charging. With the legs free the body can't drop as far without the feet going through the floor,
# so the root's drop and lunge are scaled down to what the M1s use (a low hunch, not a deep squat).
LEGS_FREE = True
DROP_SCALE = 0.28  # root y (the squat drop) x this
LUNGE_SCALE = 0.6  # root z (forward / back shift) x this
GROUND = -3.0  # the floor in root space (HumanoidRootPart centre 3 studs up)
MAX_TUCK = 1.25  # studs a leg may slide up into the hip (the reference slides its legs up to ~1.2)

# virtual shoulders (top centre of each arm at rest) that arms are aimed from, Torso space
SHOULDER = {"RArm": np.array([1.5, 1.0, 0.0]), "LArm": np.array([-1.5, 1.0, 0.0])}


# --------------------------------------------------------------------------- solvers
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


def arm_t(joint, fist, twist=0.0):
    """Arm channels putting the fist (bottom of the arm) at `fist`, in Torso space. The arm points
    from its shoulder to the fist and slides out of the socket as far as that needs; a fist closer
    than an arm's length goes a full arm's length out along the same line instead (a rigid R6 arm
    would otherwise poke up out of the shoulder). `twist` turns the arm about its length (deg)."""
    f = np.asarray(fist, float)
    d = f - SHOULDER[joint]
    if np.linalg.norm(d) < 2.0:
        f = SHOULDER[joint] + d / np.linalg.norm(d) * 2.0
        d = f - SHOULDER[joint]
    rot = _rot_between(np.array([0.0, -1.0, 0.0]), d)
    if twist:
        rot = _about(d, twist) @ rot
    arm_cf = cf(f - rot @ np.array([0.0, -1.0, 0.0]), rot)
    c0, c1 = MOTORS[joint]
    m = inv(c0) @ arm_cf @ c1
    return [round(float(v), 4) for v in from_transform(joint, m[:3, 3], m[:3, :3])]


def arm_w(joint, root, fist, twist=0.0):
    """arm_t with the fist given in world (root) space for Root channels `root`."""
    f = (inv(torso_of(root)) @ np.append(np.asarray(fist, float), 1))[:3]
    return arm_t(joint, f, twist)


def heading(azimuth, elevation=0.0):
    """World direction: azimuth clockwise from straight ahead (deg), elevation up (deg)."""
    a, e = math.radians(azimuth), math.radians(elevation)
    return np.array([math.sin(a) * math.cos(e), math.sin(e), -math.cos(a) * math.cos(e)])


def reach(joint, root, direction, extra, twist=0.0):
    """Arm swung about its shoulder joint to point along a world direction, then slid `extra` studs
    out along itself for reach (the reference strikes slide 0.5-1.3)."""
    d = inv(torso_of(root))[:3, :3] @ np.asarray(direction, float)
    d = d / np.linalg.norm(d)
    rot = _rot_between(np.array([0.0, -1.0, 0.0]), d)
    if twist:
        rot = _about(d, twist) @ rot
    c0, c1 = MOTORS[joint]
    m = inv(c0)[:3, :3] @ rot @ c1[:3, :3]
    ch = from_transform(joint, np.zeros(3), m)
    return [round(float(v), 4) for v in list(ch[:3]) + list(d * extra)]


def foot(joint, root, ch):
    """World (root space) bottom centre of a foot."""
    c0, c1 = MOTORS[joint]
    pos, rot = to_transform(joint, ch)
    leg = torso_of(root) @ c0 @ cf(pos, rot) @ inv(c1)
    return (leg @ np.array([0, -1.0, 0, 1]))[:3]


def leg(joint, root, pitch, roll, yaw=0.0, max_tuck=MAX_TUCK):
    """Leg aimed in world space (pitch + forward, roll out to its side, yaw about the vertical), then
    slid up along itself into the hip just far enough that the foot lands on the floor (up to
    max_tuck studs, as far as the reference slides its legs). A foot already clear of the floor is
    left in the air."""
    ch = list(world_leg(joint, root, pitch, roll, yaw))
    c0, c1 = MOTORS[joint]
    pos, rot = to_transform(joint, ch)
    up = (c0[:3, :3] @ rot @ inv(c1)[:3, :3]) @ np.array([0.0, 1.0, 0.0])  # leg's up axis, Torso space
    up_parent = up  # the translation channels are in Torso (parent) space
    y0 = foot(joint, root, ch)[1]
    if y0 >= GROUND:
        return [round(float(v), 4) for v in ch]
    probe = ch[:3] + list(up_parent)
    y1 = foot(joint, root, probe)[1]
    s = min(max_tuck, (GROUND - y0) / (y1 - y0)) if y1 != y0 else 0.0
    return [round(float(v), 4) for v in ch[:3] + list(up_parent * s)]


def leg_to(joint, root, target):
    """leg_to_once, re-aimed a few times so the foot lands on the point itself (sliding along the
    leg doesn't move the foot exactly along the aim line)."""
    target = np.asarray(target, float)
    aim = target.copy()
    for _ in range(6):
        ch = leg_to_once(joint, root, aim)
        aim = aim + (target - foot(joint, root, ch))
    return ch


def leg_to_once(joint, root, target):
    """Leg channels putting the foot (bottom centre) on a world (root space) point: the leg is
    aimed from its hip joint at the point, turned about itself so its front faces the way the torso
    faces (the knee follows the hips), and slid up into the hip by however much the point is closer
    than a leg's length (how the reference fakes a bent knee)."""
    t = torso_of(root)
    c0, c1 = MOTORS[joint]
    hip = (t @ c0)[:3, 3]
    j = c1[:3, 3]  # the hip joint, in leg space
    v = np.array([0.0, -1.0, 0.0]) - j  # joint -> foot, leg space
    d = np.asarray(target, float) - hip
    rot = _rot_between(v, d)
    dn = d / np.linalg.norm(d)
    want = -t[:3, 2] - dn * float(-t[:3, 2] @ dn)
    have = rot @ np.array([0.0, 0.0, -1.0])
    have = have - dn * float(have @ dn)
    if np.linalg.norm(want) > 1e-6 and np.linalg.norm(have) > 1e-6:
        want, have = want / np.linalg.norm(want), have / np.linalg.norm(have)
        rot = _about(dn, math.degrees(math.atan2(float(dn @ np.cross(have, want)), float(have @ want)))) @ rot
    up = rot @ np.array([0.0, 1.0, 0.0])
    slide = (np.linalg.norm(v) - np.linalg.norm(d)) / max(0.3, float(up @ -dn))
    slide = min(MAX_TUCK, max(-0.05, slide))
    leg_torso = inv(t) @ cf(hip - rot @ j, rot)
    m = inv(c0) @ leg_torso @ c1
    ch = from_transform(joint, np.zeros(3), m[:3, :3])
    return [round(float(x), 4) for x in list(ch[:3]) + list(inv(t)[:3, :3] @ (up * slide))]


def feet_at(c, f, root, left, right, k="ease"):
    """Key both legs at frame f with the feet on world points (x, z on the floor, or (x, y, z))."""
    if "LLeg" not in c.joints:
        return
    for joint, spot in (("LLeg", left), ("RLeg", right)):
        p = [spot[0], GROUND, spot[1]] if len(spot) == 2 else list(spot)
        c.key(joint, f, leg_to(joint, root, p), k)


def legs(c, f, root, front, back, k="ease"):
    """Key both legs at frame f. front / back = (pitch, roll, yaw) for the left (lead) / right leg."""
    if "LLeg" not in c.joints:
        return
    c.key("LLeg", f, leg("LLeg", root, *front), k)
    c.key("RLeg", f, leg("RLeg", root, *back), k)


# --------------------------------------------------------------------------- the squat ("Saisho wa guu!")
# Root: [pitch (+ leans back), yaw (+ turns left), roll, x, y, z]
STANDING = [0, 0, 0, 0, 0, 0]
SQUAT = [-17, -62, 6, 0.08, -1.2, 0.0]  # deep, turned away (left shoulder at the target), hunched over
SQUAT_LEFT = (-1.0, -1.25)  # floor spots (x, z) of the feet in the squat: left foot forward and out,
SQUAT_RIGHT = (0.9, 1.35)  # right foot back and out (wide, along the line to the target)
PALM = [-0.15, -0.32, -1.38]  # Torso space: the open left palm, in front of the belly
FIST_IN_PALM = [-0.06, 0.0, -1.34]  # the right fist pressed down into it
SQUAT_NECK = [-9, 0, -4]  # chin down, glaring at the target (the counter-yaw is added by animkit)


def squat_rarm(push=0.0):
    return arm_t("RArm", np.array(FIST_IN_PALM) + [0, -push, 0], twist=-20)


def squat_larm(push=0.0):
    return arm_t("LArm", np.array(PALM) + [0, push * 0.6, 0], twist=70)


def key_squat(c, f, k="ease"):
    c.key("Root", f, SQUAT, k)
    c.key("Neck", f, SQUAT_NECK, k)
    c.key("RArm", f, squat_rarm(), k)
    c.key("LArm", f, squat_larm(), k)
    feet_at(c, f, SQUAT, SQUAT_LEFT, SQUAT_RIGHT, k)


def charge():
    """Standing -> the squat (0.45s): a counter-move up and back, then he drops and turns away, the
    left palm comes up and the right fist smacks down into it at f14; the body sinks past the squat
    and settles into it."""
    c = Clip("Jajanken Charge", 27, hit=None, arm="RArm", joints=UPPER if LEGS_FREE else FULL)
    c.peak = 13
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(0, STANDING)
    R(4, [6, 8, -2, 0, 0.05, 0.02], "decel")  # rises and leans back a touch
    R(9, [-10, -40, 4, 0.05, -0.7, 0.12], "accel")
    R(15, [-21, -70, 8, 0.1, -1.32, 0.04], "coil")  # drops and turns away, sinking past the squat
    R(27, SQUAT, "settle")
    c.key("Neck", 0, [0, 0, 0])
    c.key("Neck", 4, [4, 0, 2], "decel")
    c.key("Neck", 15, [-12, 0, -6], "coil")
    c.key("Neck", 27, SQUAT_NECK, "settle")
    # right arm: swings back with the counter-move, then comes over the top and smacks into the palm
    c.key("RArm", 0, [0, 0, 0, 0, 0, 0])
    c.key("RArm", 5, [-28, 6, 14, 0.04, 0.08, 0.12], "decel")
    c.key("RArm", 11, arm_t("RArm", [0.25, -0.05, -1.25], twist=-20), "slowin")
    c.key("RArm", 14, arm_t("RArm", np.array(FIST_IN_PALM) + [0, -0.1, 0], twist=-20), "stop")
    c.key("RArm", 18, arm_t("RArm", np.array(FIST_IN_PALM) + [0, 0.04, 0], twist=-20), "ease")
    c.key("RArm", 27, squat_rarm(), "settle")
    # left arm: palm up in front of the belly a beat ahead of the fist, giving a little as it lands
    c.key("LArm", 0, [0, 0, 0, 0, 0, 0])
    c.key("LArm", 4, [8, -4, -10, -0.02, 0.04, -0.08], "decel")
    c.key("LArm", 12, arm_t("LArm", PALM, twist=70), "coil")
    c.key("LArm", 15, squat_larm(-0.1), "stop")
    c.key("LArm", 27, squat_larm(), "settle")
    if "LLeg" in c.joints:
        c.key("LLeg", 0, [0, 0, 0, 0, 0, 0])
        c.key("RLeg", 0, [0, 0, 0, 0, 0, 0])
    feet_at(c, 4, [6, 8, -2, 0, 0.05, 0.02], (-0.55, -0.05), (0.55, 0.05), "decel")
    feet_at(c, 9, [-10, -40, 4, 0.05, -0.7, 0.12], (-0.85, -2.7, -0.8), (0.8, -2.75, 0.95), "accel")  # a hop out into it
    feet_at(c, 15, [-21, -70, 8, 0.1, -1.32, 0.04], SQUAT_LEFT, SQUAT_RIGHT, "coil")
    feet_at(c, 27, SQUAT, SQUAT_LEFT, SQUAT_RIGHT, "settle")
    return c


def hold():
    """Looped while charging (1.2s): breathing in the squat, the shoulders rising and the body
    hunching down over the hands on each breath, the fist grinding into the palm and trembling with
    the aura building in it. Keyed like the reference idles: a handful of eased poses, not waves."""
    c = Clip("Jajanken Hold", 72, hit=None, arm="RArm", joints=UPPER if LEGS_FREE else FULL)
    c.loop = True
    c.smooth = False
    breaths = {  # frame: (root offset [pitch, yaw, roll, x, y, z], fist push, neck offset)
        0: ([0, 0, 0, 0, 0, 0], 0.0, [0, 0, 0]),
        18: ([2.2, 1.5, -1.2, 0, 0.05, -0.02], 0.05, [-1.5, 0, 1]),  # breathe in: up and back
        36: ([-2.5, -1.5, 1.4, 0, -0.06, 0.03], -0.06, [1.5, 0, -1]),  # hunch down over the hands
        54: ([1.4, 1, -0.6, 0, 0.03, -0.01], 0.03, [-1, 0, 0.6]),
        72: ([0, 0, 0, 0, 0, 0], 0.0, [0, 0, 0]),
    }
    for f, (off, push, neck) in breaths.items():
        root = list(np.array(SQUAT) + np.array(off))
        c.key("Root", f, root, "ease")
        c.key("Neck", f, list(np.array(SQUAT_NECK) + neck + [0, -0.95 * root[1], 0]), "ease")
        c.key("LArm", f, squat_larm(push), "ease")
        feet_at(c, f, root, SQUAT_LEFT, SQUAT_RIGHT, "ease")
    c.neck_auto = False
    # the fist trembles in the palm: small uneven twitches on top of the breathing
    shake = [0, 0.03, -0.02, 0.035, -0.01, 0.025, -0.03, 0.02, 0.0, -0.025, 0.03, -0.015, 0]
    for i, f in enumerate(range(0, 73, 6)):
        base = np.interp(f, list(breaths), [b[1] for b in breaths.values()])
        c.key("RArm", f, arm_t("RArm", np.array(FIST_IN_PALM) + [shake[i] * 0.6, -base + shake[i], 0],
                               twist=-20 + 60 * shake[i]), "ease")
    return c


# --------------------------------------------------------------------------- the releases
def counter_move(c, f=4):
    """The fist pops up off the palm and both hands give a little: the counter-move every release
    opens with."""
    c.key("RArm", f, arm_t("RArm", np.array(FIST_IN_PALM) + [0.15, 0.25, 0.1], twist=-20), "decel")
    c.key("LArm", f, arm_t("LArm", np.array(PALM) + [-0.05, -0.08, -0.05], twist=70), "decel")
    c.key("Root", f, list(np.array(SQUAT) + [-1.5, 6, -1, 0, -0.04, 0]), "decel")


def rock():
    """Rock ("Guu!"): the fist pops off the palm, draws back past the right hip as he winds further
    away and sinks ("Jan... Ken..."), holds loaded, then the legs drive him up and forward out of the
    squat as the torso whips 165 deg round and the right fist rips straight out at chest height;
    the left hand is yanked back to the hip. Hit at 0.4s; the punch stays out and drifts."""
    c = Clip("Jajanken Rock", 57, hit=24, arm="RArm", joints=UPPER if LEGS_FREE else FULL)
    key_squat(c, 0)
    counter_move(c, 4)
    coil = [-22, -104, 10, 0.12, -1.34, 0.22]
    loaded = [-23, -110, 11, 0.12, -1.36, 0.25]
    drive = [-27, 34, -8, -0.06, -0.95, -0.9]
    over = [-26, 43, -9, -0.06, -0.93, -1.0]
    held = [-21, 28, -6, -0.05, -0.97, -0.86]
    drift = [-20, 26, -5, -0.05, -0.98, -0.84]
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(15, coil, "coil")
    R(19, loaded, "slowin")
    R(23, drive, "whip")
    R(27, over, "stop")
    R(42, held, "settle")
    R(57, drift, "drift")
    c.key("Neck", 4, [-8, 0, -3], "decel")
    c.key("Neck", 15, [-11, 0, -6], "coil")
    c.key("Neck", 22, [-16, 0, 6], "snap")
    c.key("Neck", 26, [-19, 0, 10], "stop")
    c.key("Neck", 42, [-14, 0, 7], "settle")
    c.key("Neck", 57, [-15, 0, 7], "drift")
    # punching arm: chambers back past the hip ("Jan... Ken..."), cocks, then snaps out to the target
    c.key("RArm", 13, arm_w("RArm", coil, [1.8, -1.45, 1.15], twist=-40), "coil")
    c.key("RArm", 19, arm_w("RArm", loaded, [1.85, -1.4, 1.35], twist=-45), "slowin")
    c.key("RArm", 22, reach("RArm", drive, heading(18, -24), 0.0), "snap")
    c.key("RArm", 24, reach("RArm", drive, heading(-4, -3), 0.85), "armstrike")
    c.key("RArm", 27, reach("RArm", over, heading(-5, -4), 1.05), "stop")
    c.key("RArm", 42, reach("RArm", held, heading(-3, -3), 0.8), "settle")
    c.key("RArm", 57, reach("RArm", drift, heading(-3, -4), 0.76), "drift")
    # off hand: reaches out at the target in the coil, then yanked back to the hip in the whip
    c.key("LArm", 14, reach("LArm", coil, heading(-20, -12), 0.45, twist=40), "coil")
    c.key("LArm", 19, reach("LArm", loaded, heading(-18, -10), 0.5, twist=40), "slowin")
    c.key("LArm", 23, arm_w("LArm", drive, [-1.9, -1.55, 0.25]), "snap")
    c.key("LArm", 27, arm_w("LArm", over, [-1.95, -1.6, 0.4]), "stop")
    c.key("LArm", 42, arm_w("LArm", held, [-1.85, -1.55, 0.2]), "settle")
    c.key("LArm", 57, arm_w("LArm", drift, [-1.85, -1.6, 0.15]), "drift")
    # legs: sink onto the back leg in the coil, then drive off it into a long lunge
    feet_at(c, 4, list(np.array(SQUAT) + [-1.5, 6, -1, 0, -0.04, 0]), SQUAT_LEFT, SQUAT_RIGHT, "decel")
    feet_at(c, 15, coil, SQUAT_LEFT, SQUAT_RIGHT, "coil")
    feet_at(c, 19, loaded, SQUAT_LEFT, SQUAT_RIGHT, "slowin")
    feet_at(c, 23, drive, (-1.0, -1.35), (0.85, 0.5), "whip")  # the back foot is dragged in behind the drive
    feet_at(c, 27, over, (-1.0, -1.35), (0.82, 0.4), "stop")
    feet_at(c, 42, held, (-1.0, -1.35), (0.82, 0.45), "settle")
    feet_at(c, 57, drift, (-1.0, -1.35), (0.82, 0.45), "drift")
    return c


def paper():
    """Paper ("Paa!"): the fist pops off the palm and opens, the right hand draws back to the hip
    palm-forward as he winds away, then he pushes up out of the squat and drives the open palm
    straight out at chest height; the ball leaves the palm on Hit (0.367s) and its kick knocks the
    arm and body back a step before he settles behind the extended palm."""
    c = Clip("Jajanken Paper", 54, hit=22, arm="RArm", joints=UPPER if LEGS_FREE else FULL)
    key_squat(c, 0)
    counter_move(c, 4)
    coil = [-19, -98, 9, 0.12, -1.3, 0.2]
    loaded = [-20, -103, 10, 0.12, -1.32, 0.22]
    push = [-14, 30, -6, -0.04, -0.98, -0.62]
    kick = [-6, 24, -4, -0.03, -0.95, -0.38]  # the recoil of the emission
    held = [-10, 27, -5, -0.03, -0.98, -0.48]
    drift = [-9, 26, -5, -0.03, -0.99, -0.46]
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(14, coil, "coil")
    R(18, loaded, "slowin")
    R(22, push, "whip")
    R(26, kick, "stop")
    R(40, held, "settle")
    R(54, drift, "drift")
    c.key("Neck", 4, [-8, 0, -3], "decel")
    c.key("Neck", 14, [-10, 0, -5], "coil")
    c.key("Neck", 22, [-12, 0, 4], "snap")
    c.key("Neck", 26, [-4, 0, 3], "stop")
    c.key("Neck", 40, [-9, 0, 3], "settle")
    c.key("Neck", 54, [-10, 0, 3], "drift")
    # the palm: back by the hip, then straight out with the hand turned palm-forward
    c.key("RArm", 12, arm_w("RArm", coil, [1.75, -1.35, 1.05], twist=60), "coil")
    c.key("RArm", 18, arm_w("RArm", loaded, [1.8, -1.3, 1.2], twist=70), "slowin")
    c.key("RArm", 20, reach("RArm", push, heading(16, -20), 0.0, twist=80), "snap")
    c.key("RArm", 22, reach("RArm", push, heading(-6, 10), 0.85, twist=90), "armstrike")
    c.key("RArm", 26, reach("RArm", kick, heading(-6, 12), 0.35, twist=90), "stop")  # kicked up and back
    c.key("RArm", 40, reach("RArm", held, heading(-6, 9), 0.6, twist=90), "settle")
    c.key("RArm", 54, reach("RArm", drift, heading(-6, 8), 0.55, twist=90), "drift")
    # the left hand stays out in front, then braces against the chest as the palm goes
    c.key("LArm", 13, reach("LArm", coil, heading(-18, -12), 0.4, twist=40), "coil")
    c.key("LArm", 18, reach("LArm", loaded, heading(-16, -10), 0.45, twist=40), "slowin")
    c.key("LArm", 23, arm_w("LArm", push, [-0.9, -0.6, -1.6], twist=60), "snap")
    c.key("LArm", 27, arm_w("LArm", kick, [-1.0, -0.5, -1.4], twist=60), "stop")
    c.key("LArm", 40, arm_w("LArm", held, [-0.95, -0.6, -1.5], twist=60), "settle")
    c.key("LArm", 54, arm_w("LArm", drift, [-0.95, -0.65, -1.45], twist=60), "drift")
    feet_at(c, 4, list(np.array(SQUAT) + [-1.5, 6, -1, 0, -0.04, 0]), SQUAT_LEFT, SQUAT_RIGHT, "decel")
    feet_at(c, 14, coil, SQUAT_LEFT, SQUAT_RIGHT, "coil")
    feet_at(c, 18, loaded, SQUAT_LEFT, SQUAT_RIGHT, "slowin")
    feet_at(c, 22, push, (-1.0, -1.3), (0.85, 0.75), "whip")
    feet_at(c, 26, kick, (-1.0, -1.3), (0.85, 0.85), "stop")
    feet_at(c, 40, held, (-1.0, -1.3), (0.85, 0.8), "settle")
    feet_at(c, 54, drift, (-1.0, -1.3), (0.85, 0.8), "drift")
    return c


def scissors():
    """Scissors ("Chii!"): the fist pops off the palm, the two fingers come out and the hand swings
    up and out wide to the right as he winds away and rises out of the squat, then the torso whips
    195 deg round and the blade is swept flat across the front at chest height, right to left, and
    carried on round to the left; Hit as it crosses the front (0.333s)."""
    c = Clip("Jajanken Scissors", 54, hit=20, arm="RArm", joints=UPPER if LEGS_FREE else FULL)
    c.slerp = {"RArm"}
    c.peak = 20
    key_squat(c, 0)
    counter_move(c, 4)
    coil = [-14, -108, 14, 0.12, -1.05, 0.3]
    loaded = [-14, -112, 15, 0.12, -1.04, 0.31]
    over = [-15, 98, -14, -0.06, -0.98, -0.5]
    held = [-12, 86, -11, -0.05, -1.0, -0.42]
    drift = [-11, 82, -10, -0.05, -1.01, -0.4]
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(13, coil, "coil")
    R(16, loaded, "slowin")
    # the sweep: root and arm keyed together each frame of the whip so the hand rides the arc
    sweep = [16, 17, 18, 19, 20, 21, 22, 23]
    for i, f in enumerate(sweep):
        u = i / (len(sweep) - 1)
        w = float(np.interp(u, np.linspace(0, 1, 16), [0, 0.001, 0.01, 0.028, 0.055, 0.096, 0.154, 0.233, 0.356,
                                                       0.534, 0.732, 0.878, 0.947, 0.977, 0.993, 1.0]))
        w = 0.25 * u + 0.75 * w  # keep it moving from the first frame
        root = list(np.array(loaded) + (np.array(over) - np.array(loaded)) * w)
        if i:
            R(f, root, "linear")
        az = 95 - 205 * w  # out on the right -> across the front -> round to the left
        c.key("RArm", f, reach("RArm", root, heading(az, -4 - 6 * w), 0.55, twist=-90), "linear" if i else "slowin")
    R(38, held, "settle")
    R(54, drift, "drift")
    c.key("RArm", 13, reach("RArm", coil, heading(100, 18), 0.35, twist=-90), "coil")
    c.key("RArm", 38, reach("RArm", held, heading(-112, -12), 0.45, twist=-90), "settle")
    c.key("RArm", 54, reach("RArm", drift, heading(-114, -13), 0.42, twist=-90), "drift")
    c.key("Neck", 4, [-8, 0, -3], "decel")
    c.key("Neck", 13, [-8, 0, -8], "coil")
    c.key("Neck", 19, [-12, 0, -2], "snap")
    c.key("Neck", 23, [-14, 0, 8], "stop")
    c.key("Neck", 38, [-10, 0, 6], "settle")
    c.key("Neck", 54, [-11, 0, 6], "drift")
    # left hand: out at the target while he winds, then thrown back behind for balance
    c.key("LArm", 13, reach("LArm", coil, heading(-22, -14), 0.35, twist=40), "coil")
    c.key("LArm", 17, reach("LArm", loaded, heading(-20, -12), 0.4, twist=40), "slowin")
    c.key("LArm", 22, reach("LArm", over, heading(120, -40), 0.3), "snap")
    c.key("LArm", 26, reach("LArm", over, heading(140, -35), 0.35), "stop")
    c.key("LArm", 38, reach("LArm", held, heading(130, -42), 0.3), "settle")
    c.key("LArm", 54, reach("LArm", drift, heading(128, -44), 0.28), "drift")
    feet_at(c, 4, list(np.array(SQUAT) + [-1.5, 6, -1, 0, -0.04, 0]), SQUAT_LEFT, SQUAT_RIGHT, "decel")
    feet_at(c, 13, coil, SQUAT_LEFT, SQUAT_RIGHT, "coil")
    feet_at(c, 16, loaded, SQUAT_LEFT, SQUAT_RIGHT, "slowin")
    feet_at(c, 20, list(np.array(loaded) * 0.4 + np.array(over) * 0.6), (-1.0, -1.25), (1.05, 0.9), "linear")
    feet_at(c, 23, over, (-1.05, -1.2), (1.2, 0.55), "stop")  # the back foot pivots round behind the turn
    feet_at(c, 38, held, (-1.05, -1.2), (1.2, 0.6), "settle")
    feet_at(c, 54, drift, (-1.05, -1.2), (1.2, 0.6), "drift")
    return c


CLIPS = [charge, hold, rock, paper, scissors]
HIT_TIMES = {}  # filled by bake_all: release name -> Hit marker time (s)


def _leg_up(joint, ch):
    c0, c1 = MOTORS[joint]
    _, rot = to_transform(joint, list(ch[:3]) + [0, 0, 0])
    return (c0[:3, :3] @ rot @ inv(c1)[:3, :3]) @ np.array([0.0, 1.0, 0.0])


def plant(baked):
    """Every frame, slide each leg along itself so its foot sits on the floor (blending between leg
    keys would otherwise let a foot sink through it or hover over it). A leg too short to reach the
    floor even fully out stays in the air."""
    for f in range(len(baked["Root"])):
        root = baked["Root"][f]
        for joint in ("LLeg", "RLeg"):
            ch = baked[joint][f]
            up = _leg_up(joint, ch)
            y0 = foot(joint, root, list(ch[:3]) + [0, 0, 0])[1]
            y1 = foot(joint, root, list(ch[:3]) + list(up))[1]
            s = 0.0
            if y0 < GROUND and y1 != y0:
                s = min(MAX_TUCK, (GROUND - y0) / (y1 - y0))
            baked[joint][f] = np.array(list(ch[:3]) + list(up * s))
    return baked


def bake_all():
    out = []
    for make in CLIPS:
        c = make()
        if LEGS_FREE:
            for _, v, _ in c.keys["Root"]:
                v[4] *= DROP_SCALE
                v[5] *= LUNGE_SCALE
        baked = c.bake()
        if "LLeg" in baked:
            plant(baked)
        out.append((c, baked))
        if c.hit is not None:
            HIT_TIMES[c.name] = c.hit / FPS
    return out
