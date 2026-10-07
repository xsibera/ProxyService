"""Leorio Paladiknight's warp punches (R6), in the style of the reference animations
(ANIMSFORCLAUDE.rbxm: the fist M1s and the "abilities" rig, the ice downslam above all) and of the
Jajanken and Killua sets they sit next to, built with animkit and the Jajanken solvers (arms placed
by where the fist goes, legs by where the foot goes, slid into the hip to fake a bent knee).

Leorio is a big, open brawler, not a technician: everything is a wide, heavy, committed swing that
he throws his whole weight behind. The reference rhythm still runs every strike: counter-move ->
coil (the torso winds the wrong way, the striking fist chambers) -> a loaded slow-in -> a 3-4 frame
whip -> overshoot -> settle -> a slow drift on the held silhouette. His Hatsu is an Emitter's: he
punches something near him and the blow comes out of a warp hole by his target, so most of these
punch the floor and stay down on it while the fist travels.

  Leorio Warp Punch    1.2s   the ground punch: he rears back with the right fist cocked high and the
                              left hand pointing at the floor, then drives the fist down into it, the
                              torso whipping round and plunging as in the ice downslam; held down
                              while the fist comes out by the target (Hit = the fist in the floor,
                              Warp = the blow landing)
  Leorio Remote Jab    0.7s   a snapped left jab into a warp hole at his knuckles, the arm left in it a
                              beat while the fist comes out behind the target, then snapped back
  Leorio Barrage       1.6s   down low, hammering the floor with alternating fists (five), then
                              rearing up and a last double-handed hammer into it
  Leorio Burst         1.0s   both fists raised overhead together and slammed into the floor between
                              his feet: the warp holes open all round him

Every clip keys the legs, the way the reference ability animations do (Shared/stance.py): the feet
planted at hip width, the lead leg nearly upright, the other stretched out behind on the big hits.
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


def rest(c, f=0):
    for joint in c.joints:
        c.key(joint, f, [0, 0, 0, 0, 0, 0] if joint != "Neck" else [0, 0, 0])


def R(c):
    return lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731


def N(c):
    return lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731


STANDING_FEET = {"LLeg": (-0.5, 0.0), "RLeg": (0.5, 0.0)}


def lerp(a, b, t):
    return list(np.array(a, float) + (np.array(b, float) - np.array(a, float)) * t)


# --------------------------------------------------------------------------- Warp Punch
PUNCH_HIT = 22  # the fist goes into the floor (the Hit marker; Config.WarpPunch.PunchAt)
PUNCH_WARP = 37  # the blow lands out of the warp hole (the Warp marker; Config.WarpPunch.HitDelay)


def warp_punch():
    """Leorio's Warp Punch, as he first throws it at Ging, on the body mechanics of the reference ice
    downslam: a counter-move (the weight rocks back and the right fist drops), then he rears up
    with the torso wound right round (90 deg), the right fist cocked high behind his head and the
    left hand stretched out pointing down at the floor where he'll hit; loaded a beat, then the
    torso whips 150 deg back round, plunges and rolls, the right shoulder diving at the floor as he
    drives the fist down into it (into the warp hole) - the left foot pivoting out and the right
    sliding back long, as in the reference. He stays down on it, the arm buried, while the blow comes
    out of the warp hole by his target; it lands with a jolt back up his arm, then he settles."""
    c = Clip("Leorio Warp Punch", 72, hit=PUNCH_HIT, arm="RArm", joints=FULL)
    c.markers = {PUNCH_HIT: ["Hit"], PUNCH_WARP: ["Warp"]}
    c.slerp = {"RArm", "LArm"}
    rest(c)
    back = [-3, 10, -2, 0, -0.1, 0.08]
    coil = [11, -88, 5, 0, -0.44, 0.17]  # the reference's wind-up (f20)
    loaded = [15, -82, 10, 0, -0.42, 0.16]
    slam = [-56, 67, -50, 0, -1.43, -0.16]  # the reference's slam (f34)
    over = [-58, 72, -54, 0, -1.48, -0.17]
    held = [-54, 70, -52, 0, -1.44, -0.17]
    jolt = [-50, 66, -48, 0, -1.38, -0.15]
    drift = [-54, 73, -53, 0, -1.43, -0.17]
    r = R(c)
    r(5, back, "decel")
    r(14, coil, "coil")
    r(18, loaded, "slowin")
    r(PUNCH_HIT, slam, "slam")
    r(PUNCH_HIT + 4, over, "stop")
    r(PUNCH_WARP - 1, held, "settle")
    r(PUNCH_WARP + 1, jolt, "snap")
    r(PUNCH_WARP + 7, held, "settle")
    r(72, drift, "drift")
    # the head: down at the spot he'll hit while he winds up, then up on his target as the fist goes in
    gaze(c, 0, (0, 0, -1))
    gaze(c, 5, (0, -0.15, -1), "decel")
    gaze(c, 14, (0.1, -0.5, -1), "coil")
    gaze(c, 18, (0.1, -0.52, -1), "slowin")
    gaze(c, PUNCH_HIT, (0.05, -0.12, -1), "snap")
    gaze(c, 72, (0.04, -0.15, -1), "settle")
    # the right fist: dropped, cocked high behind his head, driven down into the floor ahead of him
    rf = lambda f, root, fist, twist, k: c.key("RArm", f, arm_w("RArm", root, fist, twist=twist), k)  # noqa: E731
    c.key("RArm", 5, reach("RArm", back, heading(20, -80), 0.05, twist=10), "decel")
    rf(14, coil, [0.9, 2.3, 1.6], 40, "coil")
    rf(18, loaded, [0.7, 2.6, 1.7], 45, "slowin")
    rf(PUNCH_HIT - 3, lerp(loaded, slam, 0.25), [0.6, 2.7, 0.4], 60, "snap")  # brought over the top
    rf(PUNCH_HIT - 1, lerp(loaded, slam, 0.75), [1.0, 0.2, -1.6], 80, "linear")
    rf(PUNCH_HIT, slam, [1.25, -3.15, -1.75], 85, "armstrike")
    rf(PUNCH_HIT + 4, over, [1.25, -3.25, -1.8], 88, "stop")
    rf(PUNCH_WARP - 1, held, [1.25, -3.2, -1.78], 88, "settle")
    rf(PUNCH_WARP + 1, jolt, [1.28, -2.95, -1.72], 88, "snap")  # the blow landing kicks back up the arm
    rf(PUNCH_WARP + 7, held, [1.25, -3.2, -1.78], 88, "settle")
    rf(72, drift, [1.25, -3.12, -1.75], 85, "drift")
    # the left hand: points down at the spot, then flung out and back as the right comes over
    c.key("LArm", 5, reach("LArm", back, heading(-25, -70), 0.05, twist=-10), "decel")
    c.key("LArm", 14, reach("LArm", coil, heading(-8, -38), 0.45, twist=-30), "coil")
    c.key("LArm", 18, reach("LArm", loaded, heading(-5, -40), 0.5, twist=-30), "slowin")
    c.key("LArm", PUNCH_HIT, arm_w("LArm", slam, [-1.95, -0.75, 0.1], twist=-40), "snap")
    c.key("LArm", PUNCH_HIT + 4, arm_w("LArm", over, [-1.6, -0.2, 0.7], twist=-40), "stop")
    c.key("LArm", PUNCH_WARP + 7, arm_w("LArm", held, [-0.7, 0.25, 1.0], twist=-30), "settle")
    c.key("LArm", 72, arm_w("LArm", drift, [-0.9, 0.05, 1.1], twist=-30), "drift")
    # legs, where the reference puts its feet: the left foot leads, the right steps back for the
    # wind-up; on the slam the left pivots out under him, standing upright, and the right slides
    # back with the leg stretched out long
    plant(c, 0, STANDING_FEET, {"LLeg": 0.0, "RLeg": 0.0})
    plant(c, 5, {"LLeg": (-0.55, -0.1), "RLeg": (0.6, 0.35)}, {"LLeg": 0.05, "RLeg": 0.3}, "decel")
    wound = plant(c, 14, {"LLeg": (-0.5, -1.15), "RLeg": (0.45, 1.5)}, {"LLeg": 0.1, "RLeg": 0.6}, "coil")
    keep(c, 18, wound, "slowin")
    planted = plant(c, PUNCH_HIT, {"LLeg": (-1.05, -0.25), "RLeg": (1.45, 2.33)}, {"LLeg": 0.0, "RLeg": 1.0}, "slam")
    keep(c, 72, planted)
    return c


# --------------------------------------------------------------------------- Remote Jab
JAB_HIT = 10  # the fist goes into the warp hole at his knuckles (Hit; Config.RemoteJab.JabAt)
JAB_WARP = 24  # it comes out by the target (Warp; Config.RemoteJab.HitDelay)
GUARD_R = [0.55, 0.85, -0.95]  # Torso space: the right fist up by the chin


def remote_jab():
    """A snapped left jab - the quickest thing he has: the left shoulder draws back a touch and the
    weight sinks (the counter-move), then the torso turns right to throw the left shoulder in and the
    arm snaps out straight at shoulder height, the lead foot stepping in (Hit at f10: the fist into
    the warp hole that opens at his knuckles). The arm stays in it, locked, while the fist comes out
    of the other hole behind his target (Warp at f24, with a kick back up the arm), then snaps back
    to his guard; the right fist stays up by his chin the whole way."""
    c = Clip("Leorio Remote Jab", 42, hit=JAB_HIT, arm="LArm", joints=FULL)
    c.markers = {JAB_HIT: ["Hit"], JAB_WARP: ["Warp"]}
    c.slerp = {"RArm", "LArm"}
    rest(c)
    draw = [-5, 14, -2, 0, -0.32, 0.1]
    jab = [-12, -30, 5, 0, -0.45, -0.3]
    over = [-13, -34, 6, 0, -0.47, -0.34]
    held = [-12, -31, 5, 0, -0.46, -0.32]
    kick = [-9, -27, 4, 0, -0.43, -0.26]
    guard = [-5, -10, 1, 0, -0.32, -0.05]
    r = R(c)
    r(4, draw, "decel")
    r(JAB_HIT, jab, "whip")
    r(JAB_HIT + 3, over, "stop")
    r(JAB_WARP - 1, held, "settle")
    r(JAB_WARP + 1, kick, "snap")
    r(32, guard, "decel")
    r(42, lerp(guard, [0, 0, 0, 0, -0.1, 0], 0.4), "settle")
    gaze(c, 0, (0, 0, -1))
    gaze(c, 4, (0, -0.08, -1), "decel")
    gaze(c, JAB_HIT, (0, -0.05, -1), "snap")
    gaze(c, 42, (0, -0.05, -1), "settle")
    # the left fist: back by the chin, snapped straight out (knuckles up, palm down), left in the
    # hole, then snapped back
    c.key("LArm", 4, J.arm_t("LArm", [-0.55, 0.75, -1.0], twist=-60), "decel")
    c.key("LArm", JAB_HIT - 2, reach("LArm", lerp(draw, jab, 0.6), heading(-6, 10), 0.3, twist=-80), "snap")
    c.key("LArm", JAB_HIT, reach("LArm", jab, heading(-3, 4), 0.85, twist=-90), "armstrike")
    c.key("LArm", JAB_HIT + 3, reach("LArm", over, heading(-3, 3), 0.95, twist=-90), "stop")
    c.key("LArm", JAB_WARP - 1, reach("LArm", held, heading(-3, 3), 0.9, twist=-90), "settle")
    c.key("LArm", JAB_WARP + 1, reach("LArm", kick, heading(-3, 6), 0.7, twist=-90), "snap")
    c.key("LArm", 32, J.arm_t("LArm", [-0.6, 0.7, -1.05], twist=-60), "decel")
    c.key("LArm", 42, J.arm_t("LArm", [-0.75, 0.2, -0.9], twist=-40), "settle")
    for f, k in ((4, "decel"), (JAB_HIT, "snap"), (32, "decel")):
        c.key("RArm", f, J.arm_t("RArm", GUARD_R, twist=60), k)
    c.key("RArm", 42, J.arm_t("RArm", [0.75, 0.15, -0.85], twist=40), "settle")
    # legs: the left foot leads and steps in with the jab, then draws back under him
    plant(c, 0, STANDING_FEET, {"LLeg": 0.0, "RLeg": 0.0})
    plant(c, 4, {"LLeg": (-0.55, -0.2), "RLeg": (0.6, 0.55)}, {"LLeg": 0.05, "RLeg": 0.5}, "decel")
    plant(c, JAB_HIT - 4, {"LLeg": (-0.58, -2.72, -0.55), "RLeg": (0.6, 0.55)}, k="ease")  # the step: foot up...
    stepped = plant(c, JAB_HIT, {"LLeg": (-0.6, -0.95), "RLeg": (0.62, 0.6)}, {"LLeg": 0.05, "RLeg": 0.8}, "decel")
    keep(c, JAB_WARP + 1, stepped)
    plant(c, 42, {"LLeg": (-0.6, -0.6), "RLeg": (0.6, 0.6)}, {"LLeg": 0.05, "RLeg": 0.5}, "settle")
    return c


# --------------------------------------------------------------------------- Warp Barrage
BARRAGE_HITS = (16, 24, 32, 40, 48, 70)  # each fist into the floor (Hit markers; Config.WarpBarrage.Hits)
BARRAGE_SIDES = ("RArm", "LArm", "RArm", "LArm", "RArm", None)  # None: both (the last)


def barrage():
    """Down low over the floor, hammering it: he drops into a wide, low crouch, torso pitched right
    over, and pounds the floor in front of him with alternating fists like pistons (right, left,
    right, left, right; Hit markers 16-48), the shoulder of the striking side diving each time and
    the torso rocking side to side over planted feet; then he rears up with both fists locked
    together high over his head and brings them down into the floor in one double-handed hammer
    (f70), held, then rising."""
    c = Clip("Leorio Barrage", 96, hit=BARRAGE_HITS[0], arm="RArm", joints=FULL)
    c.markers = {f: ["Hit"] for f in BARRAGE_HITS}
    c.peak = BARRAGE_HITS[-1]
    c.slerp = {"RArm", "LArm"}
    rest(c)
    crouch = [-34, 0, 0, 0, -1.1, -0.1]
    strike = {"RArm": [-44, 16, -14, 0, -1.28, -0.22], "LArm": [-44, -16, 14, 0, -1.28, -0.22]}
    lift = {"RArm": [-36, 6, -5, 0, -1.14, -0.12], "LArm": [-36, -6, 5, 0, -1.14, -0.12]}
    rear = [8, 0, 0, 0, -0.55, 0.2]
    loaded = [12, 0, 0, 0, -0.5, 0.24]
    slam = [-56, 0, 0, 0, -1.48, -0.32]
    over = [-59, 0, 0, 0, -1.53, -0.35]
    held = [-55, 0, 0, 0, -1.47, -0.32]
    up = [-24, 0, 0, 0, -0.75, -0.1]
    r = R(c)
    r(8, crouch, "coil")
    floor = {"RArm": [0.75, -3.15, -1.55], "LArm": [-0.75, -3.15, -1.55]}
    high = {"RArm": [1.15, 0.85, -0.75], "LArm": [-1.15, 0.85, -0.75]}
    for joint, s in (("RArm", 1), ("LArm", -1)):  # both fists up, ready
        c.key(joint, 8, arm_w(joint, crouch, high[joint], twist=s * 70), "coil")
    for n, (f, side) in enumerate(zip(BARRAGE_HITS[:-1], BARRAGE_SIDES[:-1], strict=True)):
        other = "LArm" if side == "RArm" else "RArm"
        s = 1 if side == "RArm" else -1
        r(f - 4, lift[side], "slowin" if n == 0 else "ease")
        r(f, strike[side], "slam")
        # the striking fist comes down into the floor; the other pulls back up, ready for the next
        c.key(side, f - 4, arm_w(side, lift[side], [s * 1.1, 1.05, -0.6], twist=s * 70), "ease")
        c.key(side, f, arm_w(side, strike[side], floor[side], twist=s * 85), "armstrike")
        c.key(other, f, arm_w(other, strike[side], high[other], twist=-s * 70), "decel")
    # the last one: reared up, both fists locked overhead, then down together
    last = BARRAGE_HITS[-1]
    r(BARRAGE_HITS[-2] + 3, lerp(strike["RArm"], crouch, 0.4), "decel")
    r(last - 10, rear, "coil")
    r(last - 4, loaded, "slowin")
    r(last, slam, "slam")
    r(last + 4, over, "stop")
    r(86, held, "settle")
    r(96, up, "settle")
    for joint, s in (("RArm", 1), ("LArm", -1)):
        c.key(joint, last - 10, arm_w(joint, rear, [s * 0.18, 2.75, 0.55], twist=s * 40), "coil")
        c.key(joint, last - 4, arm_w(joint, loaded, [s * 0.15, 2.85, 0.75], twist=s * 40), "slowin")
        c.key(joint, last - 2, arm_w(joint, lerp(loaded, slam, 0.4), [s * 0.2, 2.3, -1.2], twist=s * 60), "snap")
        c.key(joint, last, arm_w(joint, slam, [s * 0.45, -3.2, -1.85], twist=s * 85), "armstrike")
        c.key(joint, last + 4, arm_w(joint, over, [s * 0.45, -3.28, -1.9], twist=s * 88), "stop")
        c.key(joint, 86, arm_w(joint, held, [s * 0.45, -3.22, -1.85], twist=s * 88), "settle")
        c.key(joint, 96, reach(joint, up, heading(s * 15, -60), 0.1, twist=s * 40), "settle")
    gaze(c, 0, (0, 0, -1))
    gaze(c, 8, (0, -0.2, -1), "coil")
    gaze(c, last - 10, (0, -0.1, -1), "coil")
    gaze(c, last, (0, -0.12, -1), "snap")
    gaze(c, 96, (0, -0.12, -1), "settle")
    # legs: a wide, low stance, the left foot a little ahead; both stand under him as he pounds,
    # and the right slides back long for the last one
    plant(c, 0, STANDING_FEET, {"LLeg": 0.0, "RLeg": 0.0})
    low = plant(c, 8, {"LLeg": (-0.8, -0.45), "RLeg": (0.8, 0.55)}, {"LLeg": 0.05, "RLeg": 0.2}, "coil")
    keep(c, last - 4, low)
    long = plant(c, last, {"LLeg": (-0.85, -0.5), "RLeg": (0.95, 1.7)}, {"LLeg": 0.0, "RLeg": 1.0}, "slam")
    keep(c, 96, long)
    return c


# --------------------------------------------------------------------------- Portal Burst
BURST_HIT = 24  # both fists into the floor (Hit; Config.PortalBurst.HitDelay)


def burst():
    """Portal Burst: a dip, then he rises tall with both fists locked together high over his head,
    leaning back into it; loaded a beat, then he drops into a deep, square squat and slams both
    fists into the floor right in front of his feet (Hit at f24) - the warp holes open in a ring
    round him and the fists come up out of them. Held down on it while they do, then he rises."""
    c = Clip("Leorio Burst", 60, hit=BURST_HIT, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "LArm"}
    rest(c)
    dip = [-6, 0, 0, 0, -0.35, 0.05]
    tall = [14, 0, 0, 0, -0.05, 0.22]
    loaded = [17, 0, 0, 0, -0.08, 0.25]
    slam = [-40, 0, 0, 0, -1.35, -0.18]
    over = [-43, 0, 0, 0, -1.4, -0.2]
    held = [-39, 0, 0, 0, -1.34, -0.18]
    up = [-12, 0, 0, 0, -0.5, -0.04]
    r = R(c)
    r(5, dip, "decel")
    r(15, tall, "coil")
    r(20, loaded, "slowin")
    r(BURST_HIT, slam, "slam")
    r(BURST_HIT + 4, over, "stop")
    r(44, held, "settle")
    r(60, up, "settle")
    for joint, s in (("RArm", 1), ("LArm", -1)):
        c.key(joint, 5, reach(joint, dip, heading(s * 25, -75), 0.05, twist=s * 20), "decel")
        c.key(joint, 15, arm_w(joint, tall, [s * 0.2, 3.0, 0.4], twist=s * 40), "coil")
        c.key(joint, 20, arm_w(joint, loaded, [s * 0.18, 3.1, 0.6], twist=s * 40), "slowin")
        c.key(joint, BURST_HIT - 2, arm_w(joint, lerp(loaded, slam, 0.45), [s * 0.25, 1.8, -1.35], twist=s * 60),
              "snap")
        c.key(joint, BURST_HIT, arm_w(joint, slam, [s * 0.8, -3.2, -1.3], twist=s * 85), "armstrike")
        c.key(joint, BURST_HIT + 4, arm_w(joint, over, [s * 0.8, -3.28, -1.35], twist=s * 88), "stop")
        c.key(joint, 44, arm_w(joint, held, [s * 0.8, -3.22, -1.3], twist=s * 88), "settle")
        c.key(joint, 60, reach(joint, up, heading(s * 30, -65), 0.1, twist=s * 30), "settle")
    gaze(c, 0, (0, 0, -1))
    gaze(c, 5, (0, -0.25, -1), "decel")
    gaze(c, 15, (0, 0.05, -1), "coil")
    gaze(c, BURST_HIT, (0, -0.3, -1), "snap")
    gaze(c, 60, (0, -0.1, -1), "settle")
    # legs: square and wide, both upright: the body drops straight down between them
    plant(c, 0, STANDING_FEET, {"LLeg": 0.0, "RLeg": 0.0})
    wide = plant(c, 5, {"LLeg": (-0.8, 0.1), "RLeg": (0.8, 0.2)}, {"LLeg": 0.05, "RLeg": 0.05}, "decel")
    keep(c, 20, wide, "slowin")
    squat = plant(c, BURST_HIT, {"LLeg": (-0.85, 0.5), "RLeg": (0.85, 0.6)}, {"LLeg": 0.1, "RLeg": 0.1}, "slam")
    keep(c, 44, squat)
    keep(c, 60, wide, "settle")
    return c


CLIPS = [warp_punch, remote_jab, barrage, burst]


def bake_all():
    """[(clip, baked)] with the feet kept on (never through) the floor."""
    out = []
    for make in CLIPS:
        c = make()
        baked = solve_feet(c, c.bake())
        check_legs(c, baked)
        out.append((c, baked))
    return out


def marker_times(name="Hit"):
    """Clip name -> times (s) of its markers called `name`, for checking the server's settings against."""
    out = {}
    for make in CLIPS:
        c = make()
        frames = sorted(f for f, names in c.markers.items() if name in names)
        out[c.name] = [f / FPS for f in frames]
    return out


if __name__ == "__main__":
    for c, baked in bake_all():
        speed = float(np.linalg.norm(np.diff(np.asarray(baked["Root"])[:, :3], axis=0), axis=1).max()) * FPS
        print("%-20s %3d frames  markers %-30s smoothing %s  root peak %.0f deg/s" % (
            c.name, c.frames, sorted(c.markers.items()), c.smoothing, speed))
