"""The Brawler's basic fighting moves (R6): punches, kicks, a slam, and grabs with the throws and slams
that follow them, in the style of the reference animations (ANIMSFORCLAUDE.rbxm: the fist M1s and the
"abilities" rig's ice downslam, leg sweep and leg axe) and of the ability kits beside them. Built
with animkit, the Jajanken solvers and the shared leg solver (Shared/stance.py): feet planted and
solved on every frame, the support leg standing upright, a kicking leg aimed from its hip.

Every strike runs the reference rhythm: counter-move -> coil -> a loaded slow-in -> a 3-5 frame whip
-> overshoot -> settle -> a slow drift on the held silhouette.

The attacker's clips:
  Brawler Haymaker     0.9s   a wide right hook thrown from the back foot, stepping in (Hit 22)
  Brawler Uppercut     0.8s   dropped low and wound right, then driven up through the chin (Hit 16)
  Brawler Roundhouse   0.85s  a spinning right roundhouse at head height, pivoting on the left foot (Hit 17)
  Brawler Axe Kick     1.0s   the right leg swung straight up past his head and the heel dropped (Hit 30)
  Brawler Teep         1.23s  a heavy push kick off the back leg: a long wind-up with the knee held at the
                              chest, the foot shoved straight out into their middle as he leans back
                              behind it, and a stamp down after (Hit 31)
  Brawler Ground Slam  1.2s   a crouch, a hop with both fists locked overhead, and both brought down
                              into the floor as he lands (Hit 32)
  Brawler Grab         0.7s   a lunging two-handed grab (Grab 10); whiffed, he stumbles and recovers
  Brawler Suplex       1.2s   lift, arch back and spike them over his head behind him (Hit 36)
  Brawler Chokeslam    1.3s   lifted high by the throat one-handed and slammed down in front (Hit 44)
  Brawler Throw        0.8s   swung round a half turn by the collar and hurled (Release 26)

The victim's clips (played on whoever is held, while every client carries their body along
GRAB_PATHS, the path the attacker's hands take):
  Brawler Held Suplex / Held Chokeslam / Held Throw   their body in his hands
  Brawler Get Up       0.9s   from flat on the back, sitting up and getting back on their feet
"""

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "Animations"))
sys.path.insert(0, os.path.join(HERE, "..", "Shared"))
from animkit import FPS, Clip  # noqa: E402
from stance import J, check_legs, gaze, keep, plant, solve_feet  # noqa: E402

FULL = J.FULL
arm_w, reach, heading = J.arm_w, J.reach, J.heading
GROUND = J.GROUND
STANDING_FEET = {"LLeg": (-0.5, 0.0), "RLeg": (0.5, 0.0)}
GUARD = {"RArm": [0.6, 0.85, -1.0], "LArm": [-0.6, 0.85, -1.0]}  # Torso space: fists up by the chin


def rest(c, f=0):
    for joint in c.joints:
        c.key(joint, f, [0, 0, 0, 0, 0, 0] if joint != "Neck" else [0, 0, 0])


def R(c):
    return lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731


def lerp(a, b, t):
    return list(np.array(a, float) + (np.array(b, float) - np.array(a, float)) * t)


def guard(c, f, joint, k="ease", lift=0.0):
    s = 1 if joint == "RArm" else -1
    x, y, z = GUARD[joint]
    c.key(joint, f, J.arm_t(joint, [x, y + lift, z], twist=s * 60), k)


def leg_out(root, joint, azimuth, elevation, length):
    """A foot spot `length` studs out from its hip along a world direction (azimuth clockwise from
    straight ahead, elevation up), for Root channels `root`: a kicking leg aimed out at full length."""
    from stance import hips

    return tuple(float(v) for v in hips(root)[joint] + length * heading(azimuth, elevation))


def arc(center, radius, a0, a1, y, n):
    """n points round a circle in the floor's plane (degrees clockwise from straight ahead)."""
    out = []
    for i in range(n + 1):
        a = np.radians(a0 + (a1 - a0) * i / max(n, 1))
        out.append((center[0] + radius * np.sin(a), y, center[1] - radius * np.cos(a)))
    return out


# --------------------------------------------------------------------------- Haymaker
def haymaker():
    """A wide right hook thrown from the back foot: the weight rocks forward (the counter-move), then
    he winds right, the right fist drawn back wide by the ear and the left out in front measuring;
    loaded a beat, then the torso whips round and he steps in, the fist swinging round flat at head
    height through the target and on across his body, the left pulled back to the chin. Settles low
    and turned, then back to the guard."""
    c = Clip("Brawler Haymaker", 54, hit=22, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "LArm"}
    rest(c)
    lean = [-6, 10, -2, 0, -0.25, -0.05]
    coil = [6, -58, 8, 0, -0.55, 0.3]
    loaded = [8, -64, 9, 0, -0.6, 0.34]
    hook = [-18, 30, -10, 0, -0.75, -0.55]
    over = [-20, 34, -11, 0, -0.8, -0.6]
    held = [-16, 28, -8, 0, -0.74, -0.52]
    back = [-6, 8, -2, 0, -0.35, -0.15]
    r = R(c)
    r(4, lean, "decel")
    r(13, coil, "coil")
    r(18, loaded, "slowin")
    r(22, hook, "whip")
    r(26, over, "stop")
    r(40, held, "settle")
    r(54, back, "settle")
    gaze(c, 0, (0, 0, -1))
    gaze(c, 13, (0, -0.05, -1), "coil")
    gaze(c, 54, (0, -0.05, -1), "settle")
    rf = lambda f, root, fist, twist, k: c.key("RArm", f, arm_w("RArm", root, fist, twist=twist), k)  # noqa: E731
    guard(c, 4, "RArm", "decel")
    rf(13, coil, [1.9, 1.0, 1.0], 30, "coil")
    rf(18, loaded, [2.0, 1.1, 1.25], 30, "slowin")
    rf(20, lerp(loaded, hook, 0.55), [2.35, 0.75, -1.1], 60, "snap")  # coming round wide, flat
    rf(22, hook, [0.25, 0.65, -2.65], 85, "armstrike")
    rf(26, over, [-1.25, 0.45, -1.9], 90, "stop")  # carried on across his body
    rf(40, held, [-0.9, 0.4, -1.95], 90, "settle")
    guard(c, 54, "RArm", "settle")
    lf = lambda f, root, fist, twist, k: c.key("LArm", f, arm_w("LArm", root, fist, twist=twist), k)  # noqa: E731
    guard(c, 4, "LArm", "decel")
    lf(13, coil, [-0.1, 0.55, -2.4], -70, "coil")  # out in front, measuring
    lf(18, loaded, [-0.05, 0.5, -2.45], -70, "slowin")
    c.key("LArm", 22, J.arm_t("LArm", [-0.55, 0.9, -1.0], twist=-60), "snap")  # yanked back to the chin
    c.key("LArm", 40, J.arm_t("LArm", [-0.6, 0.8, -1.0], twist=-60), "settle")
    guard(c, 54, "LArm", "settle")
    plant(c, 0, STANDING_FEET, {"LLeg": 0.0, "RLeg": 0.0})
    stance = plant(c, 4, {"LLeg": (-0.55, -0.45), "RLeg": (0.6, 0.55)}, {"LLeg": 0.05, "RLeg": 0.3}, "decel")
    keep(c, 13, {"LLeg": (-0.5, -0.45), "RLeg": (0.65, 0.75)}, "coil", {"LLeg": 0.1, "RLeg": 0.5})
    keep(c, 18, {"LLeg": (-0.5, -0.45), "RLeg": (0.65, 0.75)}, "slowin")
    plant(c, 19, {"LLeg": (-0.65, -2.72, -0.6), "RLeg": (0.85, 0.6)}, k="ease")  # the step in: foot up...
    stepped = plant(c, 22, {"LLeg": (-0.85, -0.6), "RLeg": (1.05, 0.4)}, {"LLeg": 0.15, "RLeg": 1.0}, "decel")
    keep(c, 40, stepped)
    plant(c, 54, {"LLeg": (-0.6, -0.65), "RLeg": (0.6, 0.45)}, {"LLeg": 0.05, "RLeg": 0.4}, "settle")
    _ = stance
    return c


# --------------------------------------------------------------------------- Uppercut
def uppercut():
    """Dropped low and wound right, the right fist down by the hip (the counter-move: a little bob
    first), then he drives up off the back foot, the torso unwinding and rising, and the fist goes
    up through the chin and on over his head; up on the balls of the feet a beat, then settles."""
    c = Clip("Brawler Uppercut", 48, hit=16, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "LArm"}
    rest(c)
    bob = [-4, 6, 0, 0, -0.2, 0]
    low = [-24, -32, 6, 0, -1.05, 0.15]
    loaded = [-26, -36, 7, 0, -1.1, 0.17]
    rise = [12, 26, -6, 0, -0.05, -0.35]
    over = [15, 30, -7, 0, 0.0, -0.38]
    held = [9, 22, -4, 0, -0.15, -0.3]
    back = [-4, 6, 0, 0, -0.3, -0.1]
    r = R(c)
    r(3, bob, "decel")
    r(9, low, "coil")
    r(12, loaded, "slowin")
    r(16, rise, "whip")
    r(20, over, "stop")
    r(34, held, "settle")
    r(48, back, "settle")
    gaze(c, 0, (0, 0, -1))
    gaze(c, 9, (0, -0.15, -1), "coil")
    gaze(c, 16, (0, 0.25, -1), "snap")  # following the fist up
    gaze(c, 48, (0, 0, -1), "settle")
    rf = lambda f, root, fist, twist, k: c.key("RArm", f, arm_w("RArm", root, fist, twist=twist), k)  # noqa: E731
    guard(c, 3, "RArm", "decel")
    rf(9, low, [1.3, -1.6, -0.2], 70, "coil")
    rf(12, loaded, [1.35, -1.75, -0.1], 75, "slowin")
    rf(14, lerp(loaded, rise, 0.5), [0.9, -0.4, -1.4], 85, "snap")
    rf(16, rise, [0.35, 2.05, -1.55], 90, "armstrike")
    rf(20, over, [0.3, 2.5, -1.2], 90, "stop")
    rf(34, held, [0.45, 2.1, -1.3], 90, "settle")
    guard(c, 48, "RArm", "settle")
    guard(c, 3, "LArm", "decel")
    guard(c, 9, "LArm", "coil", lift=-0.2)
    guard(c, 16, "LArm", "snap", lift=0.1)
    guard(c, 48, "LArm", "settle")
    plant(c, 0, STANDING_FEET, {"LLeg": 0.0, "RLeg": 0.0})
    feet = plant(c, 3, {"LLeg": (-0.75, -0.45), "RLeg": (0.85, 0.5)}, {"LLeg": 0.05, "RLeg": 0.3}, "decel")
    keep(c, 9, feet, "coil", {"LLeg": 0.05, "RLeg": 0.6})
    keep(c, 12, feet, "slowin")
    keep(c, 16, feet, "whip", {"LLeg": 0.0, "RLeg": 0.9})
    keep(c, 48, feet, "settle", {"LLeg": 0.05, "RLeg": 0.4})
    return c


# --------------------------------------------------------------------------- Roundhouse
def roundhouse():
    """A spinning right roundhouse at head height: a dip and a half step (the counter-move), the right
    knee chambered up across, then he pivots on the planted left foot - the torso turning left and
    leaning away, rolled off to the left to counterbalance - and the leg whips round flat through
    the target at head height and on past it; the leg folds back in and comes down where it started
    as he turns back square."""
    c = Clip("Brawler Roundhouse", 51, hit=17, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "LArm"}
    rest(c)
    dip = [-6, -12, 2, 0, -0.35, 0.05]
    chamber = [6, 30, 14, 0, -0.25, 0.1]
    wind = [8, 52, 22, 0, -0.2, 0.08]
    kick = [12, 92, 36, 0, -0.18, 0.05]
    through = [10, 128, 30, 0, -0.22, 0.05]
    fold = [2, 70, 12, 0, -0.3, 0.05]
    square = [-4, 6, 0, 0, -0.3, 0.0]
    r = R(c)
    r(4, dip, "decel")
    r(10, chamber, "coil")
    r(13, wind, "slowin")
    r(17, kick, "whip")
    r(21, through, "stop")
    r(31, fold, "decel")
    r(42, square, "ease")
    r(51, [-2, 2, 0, 0, -0.15, 0], "settle")
    gaze(c, 0, (0, 0, -1))
    gaze(c, 10, (0.1, -0.05, -1), "coil")
    gaze(c, 17, (0, 0.05, -1), "snap")  # eyes stay on the target through the spin
    gaze(c, 51, (0, 0, -1), "settle")
    # arms: guard up, then flung out for balance as he spins, the left one tucked across
    guard(c, 4, "RArm", "decel")
    guard(c, 4, "LArm", "decel")
    c.key("RArm", 10, reach("RArm", chamber, heading(110, -35), 0.1, twist=20), "coil")
    c.key("LArm", 10, J.arm_t("LArm", [-0.5, 0.8, -1.1], twist=-60), "coil")
    c.key("RArm", 17, reach("RArm", kick, heading(-60, -50), 0.1, twist=20), "snap")
    c.key("LArm", 17, reach("LArm", kick, heading(-160, -10), 0.2, twist=-30), "snap")
    c.key("RArm", 21, reach("RArm", through, heading(-30, -55), 0.1, twist=20), "stop")
    c.key("LArm", 21, reach("LArm", through, heading(150, -15), 0.2, twist=-30), "stop")
    guard(c, 42, "RArm")
    guard(c, 42, "LArm")
    # legs: the left foot planted throughout (it pivots); the right chambers, whips round flat at head
    # height straight out from its hip (full length), through the front, and folds back down
    left = (-0.55, -0.25)
    plant(c, 0, STANDING_FEET, {"LLeg": 0.0, "RLeg": 0.0})
    plant(c, 4, {"LLeg": left, "RLeg": (0.6, 0.45)}, {"LLeg": 0.05, "RLeg": 0.2}, "decel")
    roots = {10: chamber, 13: wind, 15: lerp(wind, kick, 0.55), 17: kick, 19: lerp(kick, through, 0.5),
             21: through, 26: lerp(through, fold, 0.5), 31: fold}
    for f, az, el, length, k in ((10, 35, -25, 1.2, "coil"), (13, 85, 0, 1.9, "slowin"), (15, 45, 18, 2.0, "linear"),
                                 (17, 0, 26, 2.0, "linear"), (19, -35, 18, 2.0, "linear"), (21, -60, 4, 1.95, "decel"),
                                 (26, -30, -20, 1.5, "ease"), (31, 15, -45, 1.2, "ease")):
        plant(c, f, {"LLeg": left, "RLeg": leg_out(roots[f], "RLeg", az, el, length)},
              {"LLeg": 0.0, "RLeg": 1.0} if f == 10 else None, k)
    plant(c, 38, {"LLeg": left, "RLeg": (0.95, -2.6, 0.35)}, k="ease")
    plant(c, 42, {"LLeg": left, "RLeg": (0.75, 0.45)}, {"LLeg": 0.05, "RLeg": 0.3}, "accel")
    plant(c, 51, {"LLeg": (-0.55, -0.15), "RLeg": (0.55, 0.3)}, {"LLeg": 0.05, "RLeg": 0.1}, "settle")
    c.peak = 17
    return c


# --------------------------------------------------------------------------- Axe Kick
def axe_kick():
    """The right leg swung straight up past his head and the heel dropped like an axe: a small
    step (the counter-move), the leg rising high in front as he leans back into it, a hang at the
    top, then the heel chopped down hard and planted out in front, the torso whipping forward over
    it into a deep lunge (the leg axe reference's landing). Held low, then back up."""
    c = Clip("Brawler Axe Kick", 60, hit=30, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "LArm"}
    rest(c)
    step = [-4, -6, 2, 0, -0.25, 0.05]
    rising = [14, 10, 6, 0, -0.15, 0.2]
    top = [22, 14, 8, 0, -0.1, 0.3]
    loaded = [24, 15, 8, 0, -0.1, 0.32]
    chop = [-34, 6, -6, 0, -1.25, -1.0]
    over = [-38, 4, -8, 0, -1.32, -1.05]
    held = [-33, 5, -6, 0, -1.24, -1.0]
    up = [-10, 3, -1, 0, -0.45, -0.25]
    r = R(c)
    r(5, step, "decel")
    r(15, rising, "accel")
    r(22, top, "decel")
    r(26, loaded, "slowin")
    r(30, chop, "slam")
    r(34, over, "stop")
    r(46, held, "settle")
    r(60, up, "settle")
    gaze(c, 0, (0, 0, -1))
    gaze(c, 22, (0, 0.05, -1), "decel")
    gaze(c, 30, (0, -0.25, -1), "snap")
    gaze(c, 60, (0, -0.05, -1), "settle")
    guard(c, 5, "RArm", "decel")
    guard(c, 5, "LArm", "decel")
    for joint, s in (("RArm", 1), ("LArm", -1)):  # arms out wide for balance at the top...
        c.key(joint, 22, reach(joint, top, heading(s * 95, 10), 0.1, twist=s * 30), "decel")
        c.key(joint, 26, reach(joint, loaded, heading(s * 100, 15), 0.1, twist=s * 30), "slowin")
        c.key(joint, 30, reach(joint, chop, heading(s * 55, -55), 0.1, twist=s * 30), "snap")  # ...and swung down
        c.key(joint, 46, reach(joint, held, heading(s * 60, -50), 0.1, twist=s * 30), "settle")
    guard(c, 60, "RArm", "settle")
    guard(c, 60, "LArm", "settle")
    left = (-0.55, 0.3)
    plant(c, 0, STANDING_FEET, {"LLeg": 0.0, "RLeg": 0.0})
    plant(c, 5, {"LLeg": left, "RLeg": (0.6, 0.3)}, {"LLeg": 0.05, "RLeg": 0.1}, "decel")
    # the right leg swung straight up from the hip, past his head, and chopped down
    for f, root, el, length, k in ((11, lerp(step, rising, 0.4), -15, 1.4, "accel"), (17, rising, 50, 2.0, "decel"),
                                   (22, top, 74, 2.0, "decel"), (26, loaded, 78, 2.0, "slowin"),
                                   (28, lerp(loaded, chop, 0.55), 15, 2.0, "linear")):
        plant(c, f, {"LLeg": left, "RLeg": leg_out(root, "RLeg", 4, el, length)},
              {"LLeg": 0.0, "RLeg": 1.0} if f == 11 else None, k)
    planted = plant(c, 30, {"LLeg": left, "RLeg": (0.5, -1.5)}, {"LLeg": 1.0, "RLeg": 0.3}, "accel")  # ...planted
    keep(c, 46, planted)
    plant(c, 60, {"LLeg": (-0.55, 0.3), "RLeg": (0.55, -1.5)}, {"LLeg": 0.6, "RLeg": 0.1}, "settle")
    return c


# --------------------------------------------------------------------------- Teep
def teep():
    """A heavy push kick (the teep), thrown off the back leg. A dip (the counter-move), then a long
    wind-up: he rises and leans far back over the planted left foot, the right side turned away and
    the right arm cocked back, the knee pulled right up to the chest and held there, sinking a touch
    deeper (the load). Then everything goes at once: the hips whip round and drive through, the foot
    is shoved straight out flat into the target's middle as he throws his weight back behind it and
    slams the right arm down past the hip, the left fist up by the chin; the hips carry on through
    (the push) and hold. The knee folds back, and the foot stamps down in front, the weight dropping
    onto it, before he settles."""
    c = Clip("Brawler Teep", 74, hit=31, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "LArm"}
    rest(c)
    dip = [-8, -6, 1, 0, -0.45, -0.1]
    rising = [8, -12, -3, -0.08, -0.2, 0.2]
    loaded = [20, -18, -5, -0.12, -0.1, 0.38]  # leaned far back, the right side turned away
    deep = [23, -20, -6, -0.13, -0.13, 0.44]
    kick = [30, 24, -2, -0.08, -0.22, -0.5]  # the hips whipped round and driven through
    through = [34, 22, -1, -0.06, -0.26, -0.78]
    hold = [31, 18, -1, -0.05, -0.27, -0.74]
    fold = [8, 8, 0, -0.02, -0.36, -0.62]
    stamp = [-10, 4, 0, 0, -0.62, -0.72]  # the weight dropped onto the foot as it stamps down
    recoil = [-6, 3, 0, 0, -0.46, -0.7]
    r = R(c)
    r(6, dip, "decel")
    r(14, rising, "coil")
    r(22, loaded, "decel")
    r(27, deep, "slowin")
    r(31, kick, "whip")
    r(35, through, "stop")
    r(43, hold, "decel")
    r(50, fold, "ease")
    r(56, stamp, "accel")
    r(62, recoil, "decel")
    r(74, [-3, 0, 0, 0, -0.22, -0.55], "settle")
    gaze(c, 0, (0, 0, -1))
    gaze(c, 22, (0.05, -0.04, -1), "decel")
    gaze(c, 31, (0, -0.15, -1), "snap")  # eyes down the leg at the target's middle
    gaze(c, 56, (0, -0.08, -1), "accel")
    gaze(c, 74, (0, -0.03, -1), "settle")
    guard(c, 6, "RArm", "decel")
    guard(c, 6, "LArm", "decel")
    guard(c, 14, "RArm", "coil", lift=0.15)
    guard(c, 14, "LArm", "coil", lift=0.2)
    c.key("RArm", 22, reach("RArm", loaded, heading(125, -12), 0.05, twist=30), "decel")  # cocked back
    c.key("RArm", 27, reach("RArm", deep, heading(138, -6), 0.05, twist=30), "slowin")
    guard(c, 22, "LArm", "decel", lift=0.3)
    guard(c, 27, "LArm", "slowin", lift=0.3)
    c.key("RArm", 31, reach("RArm", kick, heading(170, -62), 0.15, twist=20), "snap")  # slammed down past the hip
    c.key("RArm", 35, reach("RArm", through, heading(176, -46), 0.15, twist=20), "stop")
    c.key("RArm", 43, reach("RArm", hold, heading(165, -50), 0.1, twist=20), "decel")
    guard(c, 31, "LArm", "snap", lift=0.1)
    guard(c, 35, "LArm", "stop", lift=0.1)
    c.key("RArm", 50, reach("RArm", fold, heading(80, -62), 0.05, twist=30), "ease")
    guard(c, 56, "RArm", "accel")
    guard(c, 50, "LArm")
    guard(c, 74, "RArm", "settle")
    guard(c, 74, "LArm", "settle")
    # legs: the left foot planted throughout; the right knee pulled up to the chest and held, the foot
    # shoved out straight from the hip at full length a touch above level (the target's stomach),
    # held through the push, folded and stamped down ahead
    left = (-0.55, 0.05)
    plant(c, 0, STANDING_FEET, {"LLeg": 0.0, "RLeg": 0.0})
    plant(c, 6, {"LLeg": left, "RLeg": (0.6, 0.45)}, {"LLeg": 0.1, "RLeg": 0.3}, "decel")
    for f, root, el, length, k in ((12, lerp(dip, rising, 0.7), -60, 1.5, "accel"),
                                   (18, lerp(rising, loaded, 0.5), -32, 1.15, "decel"),
                                   (22, loaded, -18, 0.95, "decel"), (27, deep, -14, 0.9, "slowin"),
                                   (29, lerp(deep, kick, 0.45), -2, 1.5, "linear"), (31, kick, 9, 2.0, "linear"),
                                   (35, through, 6, 2.0, "stop"), (43, hold, 4, 2.0, "decel"),
                                   (47, lerp(hold, fold, 0.5), -20, 1.5, "ease"), (50, fold, -45, 1.25, "ease")):
        plant(c, f, {"LLeg": left, "RLeg": leg_out(root, "RLeg", 3, el, length)},
              {"LLeg": 0.0, "RLeg": 1.0} if f == 12 else None, k)
    planted = plant(c, 56, {"LLeg": left, "RLeg": (0.6, -1.15)}, {"LLeg": 0.6, "RLeg": 0.2}, "accel")  # stamped
    keep(c, 74, planted, "settle", {"LLeg": 0.45, "RLeg": 0.1})
    return c


# --------------------------------------------------------------------------- Ground Slam
SLAM_HIT = 32


def ground_slam():
    """A deep crouch with the arms swung back, a hop (the body rises 2.6 studs, knees tucked) with both
    fists locked together high overhead, then he comes down with both fists hammered into the floor
    in front of him as he lands in a deep squat (Hit at f32). Held down on it, then up."""
    c = Clip("Brawler Ground Slam", 72, hit=SLAM_HIT, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "LArm"}
    rest(c)
    crouch = [-22, 0, 0, 0, -1.2, 0.15]
    takeoff = [8, 0, 0, 0, 0.6, -0.1]
    apex = [16, 0, 0, 0, 2.6, -0.4]
    falling = [-6, 0, 0, 0, 1.6, -0.6]
    slam = [-52, 0, 0, 0, -1.45, -0.55]
    over = [-55, 0, 0, 0, -1.5, -0.58]
    held = [-51, 0, 0, 0, -1.44, -0.55]
    up = [-14, 0, 0, 0, -0.5, -0.2]
    r = R(c)
    r(8, crouch, "coil")
    r(14, takeoff, "accel")
    r(22, apex, "decel")
    r(28, falling, "accel")
    r(SLAM_HIT, slam, "accel")
    r(SLAM_HIT + 4, over, "stop")
    r(54, held, "settle")
    r(72, up, "settle")
    gaze(c, 0, (0, 0, -1))
    gaze(c, 8, (0, -0.3, -1), "coil")
    gaze(c, 22, (0, -0.4, -1), "decel")
    gaze(c, SLAM_HIT, (0, -0.35, -1), "snap")
    gaze(c, 72, (0, -0.1, -1), "settle")
    for joint, s in (("RArm", 1), ("LArm", -1)):
        c.key(joint, 8, reach(joint, crouch, heading(s * 160, -40), 0.1, twist=s * 20), "coil")  # swung back
        c.key(joint, 14, reach(joint, takeoff, heading(s * 15, 60), 0.2, twist=s * 30), "accel")
        c.key(joint, 22, arm_w(joint, apex, [s * 0.2, 3.0 + 2.6, 0.2], twist=s * 40), "decel")  # locked overhead
        c.key(joint, 28, arm_w(joint, falling, [s * 0.22, 3.2 + 1.6, 0.0], twist=s * 40), "accel")
        c.key(joint, SLAM_HIT - 2, arm_w(joint, lerp(falling, slam, 0.6), [s * 0.3, 0.6, -2.0], twist=s * 70), "snap")
        c.key(joint, SLAM_HIT, arm_w(joint, slam, [s * 0.45, -3.2, -2.05], twist=s * 85), "armstrike")
        c.key(joint, SLAM_HIT + 4, arm_w(joint, over, [s * 0.45, -3.28, -2.1], twist=s * 88), "stop")
        c.key(joint, 54, arm_w(joint, held, [s * 0.45, -3.22, -2.05], twist=s * 88), "settle")
        c.key(joint, 72, reach(joint, up, heading(s * 20, -65), 0.1, twist=s * 30), "settle")
    # legs: planted for the crouch, tucked up under him in the air, landing wide and square
    crouched = {"LLeg": (-0.6, 0.15), "RLeg": (0.6, 0.25)}
    plant(c, 0, STANDING_FEET, {"LLeg": 0.0, "RLeg": 0.0})
    plant(c, 8, crouched, {"LLeg": 0.1, "RLeg": 0.1}, "coil")
    plant(c, 14, crouched, k="accel")
    plant(c, 18, {"LLeg": (-0.5, -1.4, 0.3), "RLeg": (0.5, -1.3, 0.35)}, {"LLeg": 1.0, "RLeg": 1.0}, "decel")
    plant(c, 22, {"LLeg": (-0.55, 0.5, -0.15), "RLeg": (0.55, 0.55, -0.05)}, k="decel")  # knees tucked up
    plant(c, 28, {"LLeg": (-0.6, -1.1, -0.2), "RLeg": (0.6, -1.0, -0.1)}, k="accel")  # reaching for the floor
    landed = plant(c, SLAM_HIT, {"LLeg": (-0.75, 0.2), "RLeg": (0.75, 0.35)}, {"LLeg": 0.1, "RLeg": 0.1}, "accel")
    keep(c, 72, landed)
    return c


# --------------------------------------------------------------------------- grabs
# A grab is two people animated together. The victim's torso follows a path authored in the
# attacker's root space (V: torso poses written as Root channels, [pitch, yaw, roll, x, y, z], and
# slerped); the attacker's hands are solved onto it on every frame, so they really hold it; and the
# victim's HumanoidRootPart follows V less whatever their own clip does with their torso, so the
# game can carry them along that path (BrawlerServer anchors them; every client moves them).
GRAB_AT = 10  # the hands close (Brawler Grab's Hit marker; Config.Grab.At)
LIE = [90, 0, 0, 0, -2.5, 0]  # flat on the back on the floor, head behind the HumanoidRootPart
FACING = [0, 180, 0, 0, 0, -2.3]  # the victim standing in front, facing him, when the hands close
GRAB_ROOT = [-20, 0, 0, 0, -0.75, -0.7]  # him, lunging, hands out (Brawler Grab at GRAB_AT)


def reach_hands(c, f, root, k="ease"):
    for joint, s in (("RArm", 1), ("LArm", -1)):
        c.key(joint, f, arm_w(joint, root, [s * 0.55, -0.1, -2.45], twist=s * 90), k)


def grab():
    """The reach: a dip (the counter-move), then a lunge with both hands shot out at chest height
    (Hit at f10: the hands close). Whiffed, he over-reaches a stumbling half step, then recovers
    to his guard."""
    c = Clip("Brawler Grab", 42, hit=GRAB_AT, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "LArm"}
    rest(c)
    dip = [-6, 0, 0, 0, -0.4, 0.15]
    stumble = [-26, 5, -3, 0, -0.9, -0.85]
    back = [-6, 0, 0, 0, -0.35, -0.3]
    r = R(c)
    r(4, dip, "decel")
    r(GRAB_AT, GRAB_ROOT, "whip")
    r(15, stumble, "decel")
    r(30, back, "ease")
    r(42, [-2, 0, 0, 0, -0.15, -0.1], "settle")
    gaze(c, 0, (0, 0, -1))
    gaze(c, 42, (0, 0, -1), "settle")
    for joint, s in (("RArm", 1), ("LArm", -1)):
        c.key(joint, 4, arm_w(joint, dip, [s * 1.25, -1.1, -0.4], twist=s * 70), "decel")  # drawn back low
    reach_hands(c, GRAB_AT, GRAB_ROOT, "armstrike")
    reach_hands(c, 15, stumble, "decel")
    guard(c, 30, "RArm")
    guard(c, 30, "LArm")
    guard(c, 42, "RArm", "settle")
    guard(c, 42, "LArm", "settle")
    plant(c, 0, STANDING_FEET, {"LLeg": 0.0, "RLeg": 0.0})
    plant(c, 4, {"LLeg": (-0.55, -0.1), "RLeg": (0.6, 0.35)}, {"LLeg": 0.05, "RLeg": 0.3}, "decel")
    plant(c, 7, {"LLeg": (-0.6, -2.7, -0.6), "RLeg": (0.65, 0.4)}, k="ease")
    lunged = plant(c, GRAB_AT, {"LLeg": (-0.75, -1.15), "RLeg": (0.85, 0.55)}, {"LLeg": 0.1, "RLeg": 1.0}, "decel")
    keep(c, 15, lunged, "decel")
    plant(c, 42, {"LLeg": (-0.6, -0.8), "RLeg": (0.6, 0.2)}, {"LLeg": 0.05, "RLeg": 0.3}, "settle")
    return c


class Grab:
    """One throw: the attacker's clip, the victim's clip, and V (the victim's torso path)."""

    def __init__(self, name, attacker, victim, path, grips, hold_until, release, lie_from=None):
        self.name = name  # Config / GrabPaths key ("Suplex", ...)
        self.attacker, self.victim, self.path = attacker, victim, path
        self.grips = grips  # {"RArm": (x, y, z) in the victim's torso space, ...}: where each hand holds
        self.hold_until = hold_until  # the hands let go after this frame (the slam)
        self.release = release  # the game lets the victim go (unanchors them) at this frame
        self.lie_from = lie_from  # the victim lies still from here (None: thrown, no lying)


def path_clip(name, frames, keys):
    """V as a one-joint clip (Root keyed with torso poses, slerped, not smoothed)."""
    c = Clip(name + " Path", frames, hit=None, arm="RArm", joints=("Root",))
    c.slerp = {"Root"}
    c.smooth = False
    c.neck_auto = False
    for f, v, k in keys:
        c.key("Root", f, v, k)
    return c


def victim_limbs(c, f, arms, legs, k="ease"):
    """The victim's arms and legs in their own torso's terms: arms = (azimuth, elevation) per side in
    the torso's frame, legs = (pitch, roll) per side (J.leg-style swings, not planted)."""
    for joint, s in (("RArm", 1), ("LArm", -1)):
        az, el = arms
        c.key(joint, f, reach(joint, [0, 0, 0, 0, 0, 0], heading(s * az, el), 0.0, twist=s * 30), k)
    for joint, s in (("RLeg", 1), ("LLeg", -1)):
        pitch, roll = legs
        c.key(joint, f, list(J.world_leg(joint, [0, 0, 0, 0, 0, 0], pitch + (4 if s == 1 else -4), roll)), k)


def suplex():
    """Belly-to-belly suplex: holding them round the waist he drops under them, stands up lifting
    them off their feet, arches back over into a bridge and spikes them head-first into the floor
    behind him (Hit at f36); they flop over flat on their back, and he rolls back up to his feet."""
    a = Clip("Brawler Suplex", 72, hit=36, arm="RArm", joints=FULL)
    a.slerp = {"RArm", "LArm"}
    r = R(a)
    r(0, GRAB_ROOT)
    r(8, [-14, 0, 0, 0, -1.3, -0.35], "decel")  # dropped under them
    r(18, [8, 0, 0, 0, -0.25, 0.0], "accel")  # standing up with them
    r(26, [52, 0, 0, 0, -0.55, 0.45], "ease")  # arching back
    r(32, [78, 0, 0, 0, -1.15, 0.75], "accel")
    r(36, [86, 0, 0, 0, -1.45, 0.85], "slam")  # the bridge
    r(40, [84, 0, 0, 0, -1.48, 0.85], "stop")
    r(54, [30, 0, 0, 0, -1.25, 0.35], "ease")  # rolling back up
    r(72, [-4, 0, 0, 0, -0.3, 0.0], "settle")
    gaze(a, 0, (0, -0.1, -1))
    gaze(a, 18, (0, 0.4, -1), "accel")
    gaze(a, 32, (0, 0.2, 1), "ease")  # looking back over his head as he goes over
    gaze(a, 46, (0, -0.2, 1), "ease")
    gaze(a, 72, (0, -0.05, -1), "settle")
    for joint, s in (("RArm", 1), ("LArm", -1)):  # after letting go: arms out, then back to the guard
        a.key(joint, 42, reach(joint, [84, 0, 0, 0, -1.48, 0.85], heading(s * 70, -40), 0.1, twist=s * 30), "decel")
        a.key(joint, 54, reach(joint, [30, 0, 0, 0, -1.25, 0.35], heading(s * 40, -50), 0.1, twist=s * 30), "ease")
    guard(a, 72, "RArm", "settle")
    guard(a, 72, "LArm", "settle")
    wide = {"LLeg": (-0.75, -0.85), "RLeg": (0.85, 0.4)}
    plant(a, 0, wide, {"LLeg": 0.1, "RLeg": 1.0})
    square = plant(a, 8, {"LLeg": (-0.8, -0.5), "RLeg": (0.8, -0.35)}, {"LLeg": 0.15, "RLeg": 0.15}, "decel")
    keep(a, 18, square, "accel", {"LLeg": 0.05, "RLeg": 0.05})
    keep(a, 72, square, "ease")
    v = Clip("Brawler Held Suplex", 72, hit=36, arm="RArm", joints=FULL)
    v.neck_auto = False
    v.key("Root", 0, [0, 0, 0, 0, 0, 0])
    v.key("Root", 36, [0, 0, 0, 0, 0, 0])
    v.key("Root", 42, LIE, "decel")
    v.key("Root", 72, LIE)
    victim_limbs(v, 0, (18, 12), (0, 4))  # hands on his shoulders, pushing him off
    victim_limbs(v, 10, (22, 25), (8, 6))
    victim_limbs(v, 18, (75, 40), (-10, 10))  # off their feet, kicking
    victim_limbs(v, 24, (85, 55), (25, 14))
    victim_limbs(v, 30, (95, 70), (-20, 18), "accel")
    victim_limbs(v, 36, (110, 40), (10, 25), "stop")  # the impact: flung out
    victim_limbs(v, 42, (95, -5), (2, 8), "decel")  # flat, limp
    victim_limbs(v, 72, (90, -10), (0, 6), "settle")
    v.key("Neck", 0, [10, 0, 0])
    v.key("Neck", 30, [-25, 0, 0])
    v.key("Neck", 36, [30, 0, 0], "stop")
    v.key("Neck", 72, [5, 0, 0], "settle")
    path = path_clip("Brawler Suplex", 72, [
        (0, FACING, "ease"),
        (8, [0, 180, 0, 0, -0.1, -1.95], "decel"),  # pulled in tight
        (18, [-6, 180, 0, 0, 1.5, -0.9], "accel"),  # lifted off the floor
        (26, [-85, 180, 0, 0, 2.5, 0.4], "ease"),  # over his head, face down
        (32, [-150, 180, 0, 0, 0.9, 2.1], "accel"),
        (36, [-172, 180, 0, 0, -0.95, 2.6], "slam"),  # head-first into the floor behind him
        (42, [90, 180, 0, 0, -2.5, 3.6], "decel"),  # flopped over flat on the back, head toward him
        (72, [90, 180, 0, 0, -2.5, 3.6], "ease"),
    ])
    grips = {"RArm": (0.95, -0.55, 0.45), "LArm": (-0.95, -0.55, 0.45)}  # round the waist, behind
    return Grab("Suplex", a, v, path, grips, hold_until=36, release=42, lie_from=42)


def chokeslam():
    """Chokeslam: the right hand clamps on the throat and he lifts them clean off the floor, holding
    them up high at arm's length while they kick; leaning back to load it, he brings them down with
    his whole weight and slams them flat on their back in front of him (Hit at f44), following them
    down to a knee-deep crouch, the hand pinning them, then rises."""
    a = Clip("Brawler Chokeslam", 78, hit=44, arm="RArm", joints=FULL)
    a.slerp = {"RArm", "LArm"}
    r = R(a)
    r(0, GRAB_ROOT)
    r(12, [8, -18, -6, 0, -0.3, -0.25], "decel")  # lifting, right shoulder forward
    r(30, [12, -22, -8, 0, -0.1, -0.15], "ease")  # holding them up high
    r(37, [18, -26, -10, 0, -0.05, 0.05], "slowin")  # leaning back to load it
    r(44, [-48, 8, 6, 0, -1.45, -0.85], "slam")  # down with them
    r(48, [-52, 10, 7, 0, -1.5, -0.9], "stop")
    r(62, [-46, 8, 6, 0, -1.42, -0.85], "settle")
    r(78, [-10, 2, 0, 0, -0.4, -0.2], "settle")
    gaze(a, 0, (0, 0, -1))
    gaze(a, 12, (0.1, 0.45, -1), "decel")  # looking up at them
    gaze(a, 37, (0.1, 0.5, -1), "slowin")
    gaze(a, 44, (0, -0.6, -1), "snap")  # down at them on the floor
    gaze(a, 78, (0, -0.1, -1), "settle")
    a.key("LArm", 0, arm_w("LArm", GRAB_ROOT, [-0.55, -0.1, -2.45], twist=-90))
    a.key("LArm", 12, reach("LArm", [8, -18, -6, 0, -0.3, -0.25], heading(-60, -20), 0.1, twist=-30), "decel")
    a.key("LArm", 37, reach("LArm", [18, -26, -10, 0, -0.05, 0.05], heading(-80, 0), 0.1, twist=-30), "slowin")
    a.key("LArm", 44, reach("LArm", [-48, 8, 6, 0, -1.45, -0.85], heading(-70, -45), 0.1, twist=-30), "snap")
    a.key("LArm", 62, reach("LArm", [-46, 8, 6, 0, -1.42, -0.85], heading(-60, -50), 0.1, twist=-30), "settle")
    guard(a, 78, "LArm", "settle")
    a.key("RArm", 62, arm_w("RArm", [-46, 8, 6, 0, -1.42, -0.85], [0.35, -2.55, -2.2], twist=90), "settle")
    guard(a, 78, "RArm", "settle")
    plant(a, 0, {"LLeg": (-0.75, -0.85), "RLeg": (0.85, 0.4)}, {"LLeg": 0.1, "RLeg": 1.0})
    braced = plant(a, 12, {"LLeg": (-0.8, -0.7), "RLeg": (0.9, 0.55)}, {"LLeg": 0.05, "RLeg": 0.6}, "decel")
    keep(a, 37, braced, "slowin")
    deep = plant(a, 44, {"LLeg": (-0.85, -0.95), "RLeg": (0.95, 0.75)}, {"LLeg": 0.1, "RLeg": 1.0}, "slam")
    keep(a, 78, deep)
    v = Clip("Brawler Held Chokeslam", 78, hit=44, arm="RArm", joints=FULL)
    v.neck_auto = False
    v.key("Root", 0, [0, 0, 0, 0, 0, 0])
    v.key("Root", 42, [0, 0, 0, 0, 0, 0])
    v.key("Root", 48, LIE, "decel")
    v.key("Root", 78, LIE)
    victim_limbs(v, 0, (18, 25), (0, 4))  # clawing at the hand on their throat
    victim_limbs(v, 12, (20, 70), (14, 8))
    victim_limbs(v, 20, (25, 75), (-12, 12))  # kicking
    victim_limbs(v, 28, (20, 72), (18, 6))
    victim_limbs(v, 37, (30, 78), (-8, 10))
    victim_limbs(v, 44, (100, 30), (20, 14), "stop")  # the impact
    victim_limbs(v, 50, (95, -5), (2, 8), "decel")
    victim_limbs(v, 78, (90, -10), (0, 6), "settle")
    v.key("Neck", 0, [15, 0, 0])
    v.key("Neck", 44, [30, 0, 0], "stop")
    v.key("Neck", 78, [5, 0, 0], "settle")
    path = path_clip("Brawler Chokeslam", 78, [
        (0, FACING, "ease"),
        (12, [4, 180, 0, 0.4, 1.3, -2.05], "decel"),  # lifted by the throat
        (30, [2, 180, 0, 0.5, 1.75, -1.95], "ease"),  # held up high
        (37, [-6, 180, 0, 0.55, 1.9, -1.75], "slowin"),
        (41, [50, 180, 0, 0.45, 0.2, -2.4], "accel"),  # brought down...
        (44, [90, 180, 0, 0.35, -2.5, -3.0], "slam"),  # ...flat on the back in front of him
        (78, [90, 180, 0, 0.35, -2.5, -3.0], "ease"),
    ])
    grips = {"RArm": (0.0, 1.2, -0.45)}  # the throat
    return Grab("Chokeslam", a, v, path, grips, hold_until=46, release=50, lie_from=48)


def throw():
    """Grabbing them by the collar he hauls them in and up onto their toes, winds right, then steps
    through and swings them round, hurling them off to his left (Release at f26), and unwinds."""
    a = Clip("Brawler Throw", 54, hit=26, arm="RArm", joints=FULL)
    a.slerp = {"RArm", "LArm"}
    r = R(a)
    r(0, GRAB_ROOT)
    r(9, [-4, -40, 6, 0, -0.55, -0.1], "decel")  # hauled in and wound right
    r(14, [-6, -46, 7, 0, -0.6, -0.05], "slowin")
    r(24, [-14, 62, -12, 0, -0.75, -0.35], "whip")  # swung round to the left, stepping through...
    r(27, [-16, 72, -14, 0, -0.8, -0.4], "stop")  # ...and let go
    r(40, [-8, 28, -4, 0, -0.45, -0.25], "ease")
    r(54, [-2, 0, 0, 0, -0.15, 0], "settle")
    gaze(a, 0, (0, 0, -1))
    gaze(a, 14, (0.5, 0, -1), "slowin")
    gaze(a, 26, (-1, 0, -0.4), "snap")  # watching them fly
    gaze(a, 54, (0, 0, -1), "settle")
    for joint, s in (("RArm", 1), ("LArm", -1)):
        a.key(joint, 30, reach(joint, [-16, 72, -14, 0, -0.8, -0.4], heading(-80 + s * 25, 0), 0.4,
                                twist=s * 60), "decel")
        a.key(joint, 40, reach(joint, [-8, 28, -4, 0, -0.45, -0.25], heading(-30 + s * 30, -40), 0.1,
                                twist=s * 40), "ease")
    guard(a, 54, "RArm", "settle")
    guard(a, 54, "LArm", "settle")
    plant(a, 0, {"LLeg": (-0.75, -0.85), "RLeg": (0.85, 0.4)}, {"LLeg": 0.1, "RLeg": 1.0})
    feet = plant(a, 9, {"LLeg": (-0.8, -0.6), "RLeg": (0.85, 0.45)}, {"LLeg": 0.1, "RLeg": 0.5}, "decel")
    keep(a, 14, feet, "slowin")
    plant(a, 19, {"LLeg": (-0.8, -0.6), "RLeg": (0.85, -2.6, -0.45)}, k="ease")  # stepping through
    through = plant(a, 23, {"LLeg": (-0.8, -0.6), "RLeg": (0.8, -1.35)}, {"LLeg": 0.4, "RLeg": 0.1}, "decel")
    keep(a, 40, through)
    plant(a, 54, {"LLeg": (-0.7, -0.55), "RLeg": (0.75, -0.95)}, {"LLeg": 0.1, "RLeg": 0.1}, "settle")
    v = Clip("Brawler Held Throw", 30, hit=26, arm="RArm", joints=FULL)
    v.neck_auto = False
    victim_limbs(v, 0, (30, 30), (0, 4))
    victim_limbs(v, 14, (50, 20), (-6, 8))
    victim_limbs(v, 24, (100, 30), (20, 25), "accel")  # flung out by the swing
    victim_limbs(v, 30, (110, 40), (30, 30))
    # V rides with his torso: held at arm's length in front of his chest, up on their toes
    path = path_clip("Brawler Throw", 30, [(0, FACING, "ease")])
    path.rides = [8, 180, 0, 0, 0.85, -2.3]  # V held in his torso's space: at arm's length, leaning back
    grips = {"RArm": (0.55, 0.85, -0.5), "LArm": (-0.55, 0.85, -0.5)}  # the collar
    return Grab("Throw", a, v, path, grips, hold_until=26, release=26)


def get_up():
    """Flat on the back (where a throw left them) they sit up, pushing off the floor with both hands
    behind them, gather their feet under them and stand."""
    c = Clip("Brawler Get Up", 54, hit=None, arm="RArm", joints=FULL)
    c.peak = 16
    c.slerp = {"RArm", "LArm"}
    r = R(c)
    r(0, LIE)
    r(4, [86, 0, 0, 0, -2.5, 0.05], "decel")
    r(16, [22, 0, 0, 0, -2.05, 0.35], "ease")  # sat up
    r(28, [-24, 0, 0, 0, -1.55, -0.1], "ease")  # feet under, leaning over them
    r(40, [-10, 0, 0, 0, -0.6, -0.05], "ease")
    r(54, [0, 0, 0, 0, 0, 0], "settle")
    gaze(c, 0, (0, 1, 0.05))
    gaze(c, 16, (0, -0.2, -1), "ease")
    gaze(c, 54, (0, 0, -1), "settle")
    for joint, s in (("RArm", 1), ("LArm", -1)):
        c.key(joint, 0, [0, 0, 0, 0, 0, 0])
        sat = [22, 0, 0, 0, -2.05, 0.35]
        c.key(joint, 16, arm_w(joint, sat, [s * 1.3, -2.85, 1.0], twist=s * 20), "ease")  # pushing off the floor
        c.key(joint, 28, reach(joint, [-24, 0, 0, 0, -1.55, -0.1], heading(s * 20, -50), 0.1, twist=s * 20), "ease")
        c.key(joint, 54, [0, 0, 0, 0, 0, 0], "settle")
    # legs: straight along the floor while lying and sitting, then drawn under him and planted
    plant(c, 0, {"LLeg": (-0.5, -2.5, -2.05), "RLeg": (0.5, -2.5, -2.05)}, {"LLeg": 1.0, "RLeg": 1.0})
    plant(c, 16, {"LLeg": (-0.55, -2.55, -1.55), "RLeg": (0.55, -2.55, -1.55)}, k="ease")
    plant(c, 24, {"LLeg": (-0.6, -2.7, -0.6), "RLeg": (0.6, -2.7, -0.5)}, k="ease")
    under = plant(c, 28, {"LLeg": (-0.6, -0.35), "RLeg": (0.6, -0.25)}, {"LLeg": 0.1, "RLeg": 0.1}, "ease")
    keep(c, 40, under, "ease", {"LLeg": 0.05, "RLeg": 0.05})
    plant(c, 54, STANDING_FEET, {"LLeg": 0.0, "RLeg": 0.0}, "settle")
    return c


GRABS = [suplex, chokeslam, throw]


def _grip_frame(baked_path, f):
    return J.torso_of(baked_path["Root"][min(f, len(baked_path["Root"]) - 1)])


def bake_grab(g):
    """Bake one throw: V per frame (riding with the attacker's torso, for the throw), the attacker's
    hands solved onto the victim while he holds them (blended out over 4 frames after), and the
    victim's HumanoidRootPart path = V less their own torso pose. Returns (attacker baked, victim
    baked, [4x4 HumanoidRootPart transform per frame, in the attacker's root space])."""
    att = solve_feet(g.attacker, g.attacker.bake())
    vic = g.victim.bake()
    path = g.path.bake()
    n = len(att["Root"])
    rides = getattr(g.path, "rides", None)
    V = []
    for f in range(n):
        if rides is not None:
            V.append(J.torso_of(att["Root"][f]) @ J.torso_of(rides))
        else:
            V.append(_grip_frame(path, f))
    for joint, point in g.grips.items():
        s = 1 if joint == "RArm" else -1
        for f in range(min(n, g.hold_until + 5)):
            hand = (V[f] @ np.append(point, 1.0))[:3]
            held = np.array(arm_w(joint, att["Root"][f], hand, twist=s * 90))
            u = 1.0 if f <= g.hold_until else 1.0 - (f - g.hold_until) / 5.0
            att[joint][f] = held * u + np.asarray(att[joint][f]) * (1 - u)
    hrp = []
    for f in range(len(vic["Root"])):
        hrp.append(V[min(f, n - 1)] @ np.linalg.inv(J.torso_of(vic["Root"][f])))
    return att, vic, hrp


def grab_clips():
    """[(clip, baked)] for the grab's own clips: the reach, every throw (attacker and victim) and the
    get-up; and {grab name: path} for GrabPaths."""
    out, paths = [], {}
    for make in GRABS:
        g = make()
        att, vic, hrp = bake_grab(g)
        check_legs(g.attacker, att)
        out += [(g.attacker, att), (g.victim, vic)]
        paths[g.name] = {"hrp": hrp, "hit": g.attacker.hit, "release": g.release, "length": g.attacker.frames,
                         "victim": g.victim.name, "attacker": g.attacker.name}
    return out, paths


CLIPS = [haymaker, uppercut, roundhouse, axe_kick, teep, ground_slam, grab, get_up]

def bake_all():
    """[(clip, baked)] for every clip (the throws' too): the feet and head solved on every frame and
    the legs checked. The grab paths are on GRAB_PATHS afterwards."""
    out = []
    for make in CLIPS:
        c = make()
        baked = solve_feet(c, c.bake())
        if c.name != "Brawler Get Up":
            check_legs(c, baked)
        out.append((c, baked))
    grabbed, paths = grab_clips()
    GRAB_PATHS.clear()
    GRAB_PATHS.update(paths)
    return out + grabbed


GRAB_PATHS = {}


if __name__ == "__main__":
    for c, baked in bake_all():
        speed = float(np.linalg.norm(np.diff(np.asarray(baked["Root"])[:, :3], axis=0), axis=1).max()) * FPS
        print("%-22s %3d frames  markers %-34s root peak %.0f deg/s" % (
            c.name, c.frames, sorted(c.markers.items()), speed))
