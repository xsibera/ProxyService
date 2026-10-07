"""Killua Zoldyck's lightning animations (R6), in the style of the reference animations
(ANIMSFORCLAUDE.rbxm: the fist M1s and the "abilities" rig) and of the Jajanken set they sit next to,
built with animkit and the Jajanken solvers (arms placed by where the hand goes, legs by where the
foot goes, slid into the hip to fake a bent knee).

Killua moves like the assassin he is: low, loose, hands open like claws, and everything starts and
stops dead. The reference rhythm still runs every strike: counter-move -> coil (the torso winds the
wrong way, the striking hand chambers) -> a loaded slow-in -> a 3-4 frame whip (the torso swings
110-200 deg) -> overshoot -> settle -> a slow drift on the held silhouette.

  Killua Palm             0.95s  Lightning Palm: coiled low with the palm back by the hip, then a lunge
                                 and the palm driven out at chest height. Hit at 0.35s
  Killua Thunderbolt      0.95s  Narukami: a crouch, the leap, both hands gathered overhead at the top,
                                 then both palms slammed down at the target as the bolt drops. Hit at
                                 0.55s; it ends falling, legs reaching for the floor
  Killua Land             0.4s   the landing after Thunderbolt (played when the feet touch down)
  Killua Stance           1.1s   Whirlwind (Shippu Jinrai): dropped into a low ready stance, hands loose,
                                 swaying, for the counter window; then up again (a whiff)
  Killua Counter          0.9s   Whirlwind's counter, after the blink behind the attacker: a rising
                                 claw, a spinning heel kick and a double palm. Hits at 7, 15, 26 / 60s
  Killua Dash 1 / 2 / 3   0.45 / 0.45 / 0.6s   Lightning Dash: arriving low out of the teleport and
                                 striking - a right claw, a left claw, then a lunging double palm.
                                 Hits at 6, 6, 7 / 60s

Every clip keys the legs (these are committed attacks: the walk doesn't drive them).
"""

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "Animations"))
sys.path.insert(0, os.path.join(HERE, "..", "Shared"))
from animkit import FPS, Clip  # noqa: E402
from stance import J, check_legs, hold, set_stance  # noqa: E402

FULL = J.FULL
arm_w, arm_t, reach, heading, plant = J.arm_w, J.arm_t, J.reach, J.heading, J.plant

STANDING = [0, 0, 0, 0, 0, 0]
GROUND = J.GROUND


def rest(c, f=0):
    for joint in c.joints:
        c.key(joint, f, [0, 0, 0, 0, 0, 0] if joint != "Neck" else [0, 0, 0])


def R(c):
    return lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731


def N(c):
    return lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731


# --------------------------------------------------------------------------- Lightning Palm
def palm():
    """Lightning Palm, as in the anime: Killua shocks someone by putting his palms on them. He sinks
    into his low, hunched assassin's crouch with both hands drawn back by his hips, fingers open and
    the lightning crackling between them; the client blurs him forward (LungeAt) and he drives both
    palms flat into the target's chest, square on, leaning his whole weight in (Hit at 0.35s). He
    keeps them there while the shock surges through - the arms locked and shaking - then eases off,
    still low, palms out."""
    c = Clip("Killua Palm", 60, hit=21, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "LArm"}
    rest(c)
    dip = [-8, 6, -1, 0, -0.2, 0.05]
    crouch = [-20, -16, 4, 0, -0.95, 0.4]
    loaded = [-22, -20, 5, 0, -1.02, 0.45]
    drive = [-32, -3, -1, 0, -0.82, -1.3]
    contact = [-33, -1, -1, 0, -0.8, -1.42]
    held = [-24, -4, 0, 0, -0.86, -1.15]
    drift = [-23, -4, 0, 0, -0.87, -1.12]
    r = R(c)
    r(4, dip, "decel")
    r(12, crouch, "coil")
    r(17, loaded, "slowin")
    r(21, drive, "whip")
    r(24, contact, "stop")
    r(44, held, "settle")
    r(60, drift, "drift")
    n = N(c)
    n(4, [-6, 0, 0], "decel")
    n(12, [-16, 0, -3], "coil")  # chin down, glaring up from under the fringe
    n(17, [-18, 0, -3], "slowin")
    n(21, [-20, 0, 2], "snap")
    n(24, [-22, 0, 3], "stop")
    n(44, [-15, 0, 1], "settle")
    n(60, [-14, 0, 1], "drift")
    for joint, s in (("RArm", 1), ("LArm", -1)):
        # a flick of the hands forward, then drawn back by the hips, palms open and turned out
        c.key(joint, 4, reach(joint, dip, heading(s * 15, -60), 0.15, twist=s * 30), "decel")
        c.key(joint, 12, arm_w(joint, crouch, [s * 1.35, -1.55, 0.75], twist=s * 75), "coil")
        c.key(joint, 17, arm_w(joint, loaded, [s * 1.4, -1.6, 0.95], twist=s * 85), "slowin")
        # both palms driven flat into the chest, fingers up
        c.key(joint, 19, reach(joint, drive, heading(s * 20, -25), 0.1, twist=s * 90), "snap")
        c.key(joint, 21, reach(joint, drive, heading(s * 7, 1), 0.95, twist=s * 90), "armstrike")
        c.key(joint, 24, reach(joint, contact, heading(s * 6, 0), 1.1, twist=s * 90), "stop")
        # the shock surging through: the locked arms shake against the target
        for f, jitter in ((27, 4), (30, -3), (33, 3), (36, -2)):
            c.key(joint, f, reach(joint, contact, heading(s * (6 + jitter * 0.6), jitter * 0.8), 1.08, twist=s * 90))
        c.key(joint, 44, reach(joint, held, heading(s * 6, 0), 0.8, twist=s * 88), "settle")
        c.key(joint, 60, reach(joint, drift, heading(s * 6, -1), 0.75, twist=s * 88), "drift")
    # legs: planted at hip width, left foot leading; the right foot steps back as he sinks, then the
    # lunge: the left foot steps in under him and the right leg is stretched out long behind
    set_stance(c, 4, dip, back=0.25, front=-0.05, lead="LLeg", k="decel")
    wound = set_stance(c, 12, crouch, back=1.0, front=-0.2, lead="LLeg", k="coil")  # the right foot steps back
    hold(c, 17, loaded, wound, "slowin")
    lunge = set_stance(c, 21, drive, back=1.3, front=-0.15, lead="LLeg", k="whip")  # steps in, back leg out long
    hold(c, 24, contact, lunge, "stop")
    hold(c, 44, held, lunge, "settle")
    hold(c, 60, drift, lunge, "drift")
    return c


# --------------------------------------------------------------------------- Thunderbolt (Narukami)
TAKE_OFF = 7  # the client launches him on this frame (Config.Thunderbolt.LeapAt)


def thunderbolt():
    """Narukami: a crouch with the arms swung back, the leap (the client launches him at f7), both
    hands sweeping up and meeting overhead as he rises with the knees tucked and the body arched
    back; he hangs at the top a beat with the lightning gathering between the hands, then jack-knifes
    forward and slams both palms down at the target as the bolt drops (Hit at 0.55s), the legs
    kicking down; it ends falling, legs reaching for the floor (Killua Land takes over on touchdown)."""
    c = Clip("Killua Thunderbolt", 57, hit=33, arm="RArm", joints=FULL)
    rest(c)
    crouch = [-16, 0, 0, 0, -0.75, 0.1]
    launch = [8, 0, 0, 0, 0.1, 0.0]
    rise = [16, 0, 0, 0, 0.2, 0.1]
    top = [20, 0, 0, 0, 0.25, 0.15]
    slam = [-38, 0, 0, 0, 0.1, -0.35]
    over = [-42, 0, 0, 0, 0.05, -0.4]
    fall = [-22, 0, 0, 0, 0.0, -0.2]
    r = R(c)
    r(5, crouch, "decel")
    r(TAKE_OFF + 3, launch, "accel")
    r(20, rise, "decel")
    r(29, top, "slowin")
    r(33, slam, "whip")
    r(37, over, "stop")
    r(57, fall, "settle")
    c.neck_auto = False
    n = N(c)
    n(5, [-12, 0, 0], "decel")
    n(14, [10, 0, 0], "ease")  # looks up at his hands
    n(29, [-4, 0, 0], "slowin")
    n(33, [-22, 0, 0], "snap")  # then down at the target
    n(37, [-26, 0, 0], "stop")
    n(57, [-18, 0, 0], "settle")
    for joint, side in (("RArm", 1), ("LArm", -1)):
        c.key(joint, 5, reach(joint, crouch, heading(180 - side * 20, -35), 0.1, twist=side * 20), "decel")
        c.key(joint, TAKE_OFF + 3, reach(joint, launch, heading(side * 30, 60), 0.2, twist=side * 40), "accel")
        # the hands meet overhead
        c.key(joint, 20, arm_w(joint, rise, [side * 0.35, 3.0, 0.25], twist=side * 70), "decel")
        c.key(joint, 29, arm_w(joint, top, [side * 0.3, 3.15, 0.55], twist=side * 75), "slowin")
        # slammed down and out at the target, palms first
        c.key(joint, 31, reach(joint, slam, heading(side * 8, 10), 0.2, twist=side * 80), "snap")
        c.key(joint, 33, reach(joint, slam, heading(side * 6, -48), 0.9, twist=side * 90), "armstrike")
        c.key(joint, 37, reach(joint, over, heading(side * 6, -52), 1.0, twist=side * 90), "stop")
        c.key(joint, 57, reach(joint, fall, heading(side * 12, -35), 0.55, twist=side * 80), "settle")
    G = lambda leg, f, v, k="ease": c.key(leg, f, v, k)  # noqa: E731
    set_stance(c, 5, crouch, back=0.3, front=-0.05, lead="LLeg", k="decel")
    G("RLeg", TAKE_OFF + 3, [-8, 0, 3, 0, 0, 0], "accel")  # pushed off: legs straight under him
    G("LLeg", TAKE_OFF + 3, [-4, 0, -3, 0, 0, 0], "accel")
    G("RLeg", 20, [70, 0, 10, 0, 0.35, 0], "decel")  # knees tucked
    G("LLeg", 20, [58, 0, -10, 0, 0.35, 0], "decel")
    G("RLeg", 29, [76, 0, 10, 0, 0.4, 0], "slowin")
    G("LLeg", 29, [64, 0, -10, 0, 0.4, 0], "slowin")
    G("RLeg", 33, [-10, 0, 6, 0, 0.1, 0], "snap")  # kicked down and back as he slams
    G("LLeg", 33, [24, 0, -6, 0, 0.1, 0], "snap")
    G("RLeg", 37, [-14, 0, 6, 0, 0.05, 0], "stop")
    G("LLeg", 37, [28, 0, -6, 0, 0.05, 0], "stop")
    G("RLeg", 57, [8, 0, 5, 0, 0, 0], "settle")  # reaching down for the floor
    G("LLeg", 57, [18, 0, -5, 0, 0, 0], "settle")
    return c


def land():
    """Touchdown after Thunderbolt: the knees give and the body drops low with the hands out for
    balance, then he rises back up."""
    c = Clip("Killua Land", 24, hit=None, arm="RArm", joints=FULL)
    c.peak = 5
    fall = [-22, 0, 0, 0, 0.0, -0.2]
    low = [-24, 6, 0, 0, -1.05, 0.0]
    up = [-6, 2, 0, 0, -0.25, 0.0]
    r = R(c)
    r(0, fall)
    r(5, low, "decel")
    r(24, up, "settle")
    n = N(c)
    n(0, [-18, 0, 0])
    n(5, [-14, 0, 0], "decel")
    n(24, [-6, 0, 0], "settle")
    for joint, side in (("RArm", 1), ("LArm", -1)):
        c.key(joint, 0, reach(joint, fall, heading(side * 12, -35), 0.55, twist=side * 80))
        c.key(joint, 5, reach(joint, low, heading(side * 60, -30), 0.3, twist=side * 40), "decel")
        c.key(joint, 24, reach(joint, up, heading(side * 30, -70), 0.05, twist=side * 20), "settle")
    c.key("RLeg", 0, [8, 0, 5, 0, 0, 0])
    c.key("LLeg", 0, [18, 0, -5, 0, 0, 0])
    set_stance(c, 5, low, back=0.35, front=-0.1, lead="LLeg", k="decel")
    set_stance(c, 24, up, back=0.15, front=0.0, lead="LLeg", k="settle")
    return c


# --------------------------------------------------------------------------- Whirlwind (Shippu Jinrai)
STANCE = [-20, -18, 4, 0, -1.05, 0.15]  # low, weight forward on the balls of the feet, a touch turned


def stance():
    """The counter window: he drops into a low ready stance in 5 frames, hands open and low out in
    front like claws, the lightning crackling over him, and sways on the balls of his feet; at 0.65s
    the window closes and he rises again (a whiff leaves him open until the end)."""
    c = Clip("Killua Stance", 66, hit=None, arm="RArm", joints=FULL)
    c.peak = 4
    rest(c)
    sway = {5: (0, 0, 0), 16: (2, 4, 0.03), 28: (-1.5, -3, -0.02), 39: (1, 2, 0.02)}
    ready = None
    for f, (dp, dy, dh) in sway.items():
        root = list(np.array(STANCE) + [dp, dy, 0, 0, dh, 0])
        c.key("Root", f, root, "coil" if f == 5 else "ease")
        c.key("RArm", f, arm_w("RArm", root, [0.85, -0.55 + dh, -1.6], twist=-60), "coil" if f == 5 else "ease")
        c.key("LArm", f, arm_w("LArm", root, [-0.7, -0.35 + dh, -1.75], twist=60), "coil" if f == 5 else "ease")
        if ready is None:
            ready = set_stance(c, f, root, back=0.9, front=-0.2, lead="LLeg", k="coil")
        else:
            hold(c, f, root, ready)  # swaying on planted feet
    up = [-6, -6, 1, 0, -0.3, 0.05]
    c.key("Root", 54, up, "ease")
    c.key("Root", 66, [-2, -2, 0, 0, -0.1, 0], "settle")
    c.key("RArm", 54, reach("RArm", up, heading(20, -70), 0.05, twist=-20), "ease")
    c.key("LArm", 54, reach("LArm", up, heading(-20, -70), 0.05, twist=20), "ease")
    c.key("RArm", 66, [0, 0, 0, 0, 0, 0], "settle")
    c.key("LArm", 66, [0, 0, 0, 0, 0, 0], "settle")
    set_stance(c, 54, up, back=0.45, front=-0.1, lead="LLeg", k="ease")
    set_stance(c, 66, [-2, -2, 0, 0, -0.1, 0], back=0.1, front=0.0, lead="LLeg", k="settle")
    c.key("Neck", 5, [-12, 0, 0], "coil")
    c.key("Neck", 39, [-10, 0, 0], "ease")
    c.key("Neck", 66, [0, 0, 0], "settle")
    return c


COUNTER_HITS = (7, 15, 26)


def counter():
    """Whirlwind's counter, played the moment he reappears behind the attacker, crouched low: a
    rising right claw up across their back (7), the torso keeps turning into a full spin and a
    spinning heel kick with the right leg (15), then he lands it square and drives both palms into
    them (26) with the lightning going off; held, then settles."""
    c = Clip("Killua Counter", 54, hit=COUNTER_HITS[0], arm="RArm", joints=FULL)
    c.peak = COUNTER_HITS[1]
    c.markers = {f: ["Hit"] for f in COUNTER_HITS}
    c.slerp = {"RArm", "LArm"}
    low = [-22, -45, 6, 0.05, -1.05, 0.2]
    claw = [-12, 55, -8, 0, -0.75, -0.3]
    spin1 = [-6, 170, 0, 0, -0.4, -0.2]
    kick = [10, 330, 12, 0, -0.3, -0.1]  # most of a turn: the heel comes round into them
    land_ = [-14, 380, -4, 0, -0.85, -0.2]
    palms = [-24, 360, 0, 0, -0.8, -0.9]
    held = [-18, 360, 0, 0, -0.82, -0.75]
    r = R(c)
    r(0, low)
    r(4, [-23, -52, 7, 0.05, -1.08, 0.22], "slowin")
    r(7, claw, "whip")
    r(11, spin1, "linear")  # an even, flat-out turn into the kick
    r(13, [2, 250, 6, 0, -0.35, -0.15], "linear")
    r(15, kick, "linear")
    r(20, land_, "decel")
    r(23, [-20, 352, 2, 0, -0.95, -0.3], "slowin")
    r(26, palms, "whip")
    r(30, [-26, 358, 0, 0, -0.78, -1.0], "stop")
    r(54, held, "settle")
    c.neck_auto = False
    n = N(c)
    n(0, [-10, 40, 0])
    n(7, [-12, -40, 4], "snap")
    n(13, [-6, -60, 0], "linear")  # the head leads the spin
    n(16, [-6, 20, 0], "snap")
    n(26, [-16, 0, 0], "snap")
    n(54, [-12, 0, 0], "settle")
    # right arm: claw chambered low behind, rips up across, flung out for the spin, then the palm
    c.key("RArm", 0, arm_w("RArm", low, [1.6, -1.4, 0.9], twist=60))
    c.key("RArm", 4, arm_w("RArm", [-23, -52, 7, 0.05, -1.08, 0.22], [1.7, -1.5, 1.0], twist=60), "slowin")
    c.key("RArm", 7, reach("RArm", claw, heading(-60, 40), 0.7, twist=80), "armstrike")
    c.key("RArm", 11, reach("RArm", spin1, heading(80, 5), 0.4, twist=20), "linear")
    c.key("RArm", 15, reach("RArm", kick, heading(60, -10), 0.3, twist=10), "linear")
    c.key("RArm", 20, arm_w("RArm", land_, [1.6, -1.2, 0.9], twist=70), "decel")
    c.key("RArm", 23, arm_w("RArm", [-20, 352, 2, 0, -0.95, -0.3], [1.5, -1.25, 1.1], twist=80), "slowin")
    c.key("RArm", 26, reach("RArm", palms, heading(4, 0), 1.0, twist=90), "armstrike")
    c.key("RArm", 30, reach("RArm", [-26, 358, 0, 0, -0.78, -1.0], heading(4, -2), 1.1, twist=90), "stop")
    c.key("RArm", 54, reach("RArm", held, heading(4, 0), 0.8, twist=90), "settle")
    # left arm: out for balance through the claw and the spin, then the second palm
    c.key("LArm", 0, reach("LArm", low, heading(-40, -20), 0.3, twist=40))
    c.key("LArm", 7, reach("LArm", claw, heading(150, -30), 0.3), "snap")
    c.key("LArm", 11, reach("LArm", spin1, heading(-100, 5), 0.4, twist=-20), "linear")
    c.key("LArm", 15, reach("LArm", kick, heading(-60, -10), 0.3, twist=-10), "linear")
    c.key("LArm", 20, arm_w("LArm", land_, [-1.6, -1.2, 0.9], twist=-70), "decel")
    c.key("LArm", 23, arm_w("LArm", [-20, 352, 2, 0, -0.95, -0.3], [-1.5, -1.25, 1.1], twist=-80), "slowin")
    c.key("LArm", 26, reach("LArm", palms, heading(-4, 0), 1.0, twist=-90), "armstrike")
    c.key("LArm", 30, reach("LArm", [-26, 358, 0, 0, -0.78, -1.0], heading(-4, -2), 1.1, twist=-90), "stop")
    c.key("LArm", 54, reach("LArm", held, heading(-4, 0), 0.8, twist=-90), "settle")
    G = lambda leg, f, v, k="ease": c.key(leg, f, v, k)  # noqa: E731
    crouched = set_stance(c, 0, low, back=0.9, front=-0.2, lead="LLeg")
    hold(c, 4, [-23, -52, 7, 0.05, -1.08, 0.22], crouched, "slowin")
    set_stance(c, 7, claw, back=0.8, front=-0.2, lead="RLeg", k="whip")  # steps through
    # the spinning heel kick: the right leg swings up and round, the left foot pivots
    G("RLeg", 11, [40, 0, 40, 0, 0.1, 0], "linear")
    G("LLeg", 11, [-6, 0, -6, 0, 0.2, 0], "linear")
    G("RLeg", 15, [10, 0, 95, 0, 0.15, 0], "whip")  # the leg out at hip height
    G("LLeg", 15, [-10, 0, -8, 0, 0.25, 0], "whip")
    landed = set_stance(c, 20, land_, back=0.8, front=-0.2, lead="LLeg", k="decel")
    hold(c, 23, [-20, 352, 2, 0, -0.95, -0.3], landed, "slowin")
    drove = set_stance(c, 26, palms, back=1.25, front=-0.15, lead="LLeg", k="whip")
    hold(c, 30, [-26, 358, 0, 0, -0.78, -1.0], drove, "stop")
    hold(c, 54, held, drove, "settle")
    return c


# --------------------------------------------------------------------------- Lightning Dash
def dash(n):
    """One Lightning Dash: he arrives out of the teleport already low and moving, the striking hand
    chambered, and strikes at once (Hit at f6-7): 1 a right claw ripping across, 2 a left claw back
    the other way, 3 a lunging double palm with the lightning going off. Then he stays low, ready to
    go again."""
    length = {1: 27, 2: 27, 3: 36}[n]
    hit = 7 if n == 3 else 6
    c = Clip("Killua Dash %d" % n, length, hit=hit, arm="RArm" if n != 2 else "LArm", joints=FULL)
    c.slerp = {"RArm", "LArm"}
    side = -1 if n == 2 else 1  # 2 is the mirror of 1
    if n in (1, 2):
        arrive = [-24, side * -55, side * 8, 0, -0.95, 0.15]
        strike = [-18, side * 20, side * -8, 0, -0.85, -0.35]
        over = [-17, side * 28, side * -9, 0, -0.84, -0.4]
        held = [-20, side * 15, side * -6, 0, -0.95, -0.25]
        hand, other = ("RArm", "LArm") if side == 1 else ("LArm", "RArm")
        r = R(c)
        r(0, arrive)
        r(3, list(np.array(arrive) + [-1, side * -5, 0, 0, -0.03, 0.02]), "slowin")
        r(hit, strike, "whip")
        r(hit + 3, over, "stop")
        r(length, held, "settle")
        c.key(hand, 0, arm_w(hand, arrive, [side * 1.7, -1.1, 1.0], twist=side * 70))
        c.key(hand, 3, arm_w(hand, arrive, [side * 1.8, -1.0, 1.15], twist=side * 75), "slowin")
        c.key(hand, hit, reach(hand, strike, heading(side * -55, -12), 0.8, twist=side * 90), "armstrike")
        c.key(hand, hit + 3, reach(hand, over, heading(side * -80, -18), 0.75, twist=side * 90), "stop")
        c.key(hand, length, reach(hand, held, heading(side * -60, -30), 0.45, twist=side * 80), "settle")
        c.key(other, 0, reach(other, arrive, heading(side * -20, -15), 0.4, twist=side * -40))
        c.key(other, hit, reach(other, strike, heading(side * 150, -35), 0.3), "snap")
        c.key(other, length, reach(other, held, heading(side * 140, -40), 0.25), "settle")
        # planted on arrival, left foot leading for 1 (right for 2); the torso whips round and the
        # back foot slides round with it (as the reference's does on its slam), then stays put
        lead = "LLeg" if side == 1 else "RLeg"
        set_stance(c, 0, arrive, back=0.85, front=-0.2, lead=lead)
        swung = set_stance(c, hit, strike, back=0.95, front=-0.2, lead=lead, k="whip")
        hold(c, length, held, swung, "settle")
        c.key("Neck", 0, [-12, 0, 0])
        c.key("Neck", hit, [-14, 0, side * 6], "snap")
        c.key("Neck", length, [-12, 0, side * 4], "settle")
    else:
        arrive = [-22, -30, 4, 0, -1.0, 0.3]
        loaded = [-23, -36, 5, 0, -1.05, 0.33]
        drive = [-28, 8, -2, 0, -0.8, -1.2]
        over = [-30, 10, -2, 0, -0.78, -1.3]
        held = [-22, 6, -1, 0, -0.85, -1.1]
        r = R(c)
        r(0, arrive)
        r(4, loaded, "slowin")
        r(hit, drive, "whip")
        r(hit + 4, over, "stop")
        r(length, held, "settle")
        for joint, s in (("RArm", 1), ("LArm", -1)):
            c.key(joint, 0, arm_w(joint, arrive, [s * 1.4, -1.3, 0.9], twist=s * 70))
            c.key(joint, 4, arm_w(joint, loaded, [s * 1.5, -1.25, 1.1], twist=s * 80), "slowin")
            c.key(joint, hit, reach(joint, drive, heading(s * 5, 2), 1.0, twist=s * 90), "armstrike")
            c.key(joint, hit + 4, reach(joint, over, heading(s * 5, 0), 1.15, twist=s * 90), "stop")
            c.key(joint, length, reach(joint, held, heading(s * 5, 1), 0.85, twist=s * 90), "settle")
        arrived = set_stance(c, 0, arrive, back=0.9, front=-0.2, lead="LLeg")
        hold(c, 4, loaded, arrived, "slowin")
        drove = set_stance(c, hit, drive, back=1.25, front=-0.15, lead="LLeg", k="whip")
        hold(c, hit + 4, over, drove, "stop")
        hold(c, length, held, drove, "settle")
        c.key("Neck", 0, [-12, 0, 0])
        c.key("Neck", hit, [-18, 0, 0], "snap")
        c.key("Neck", length, [-14, 0, 0], "settle")
    return c


CLIPS = [palm, thunderbolt, land, stance, counter, lambda: dash(1), lambda: dash(2), lambda: dash(3)]


def bake_all():
    """[(clip, baked)] with the feet kept on (never through) the floor."""
    out = []
    for make in CLIPS:
        c = make()
        baked = c.bake()
        plant(baked)
        check_legs(c, baked)
        out.append((c, baked))
    return out


def hit_times():
    """Clip name -> Hit marker times (s), for checking the server's settings against."""
    out = {}
    for make in CLIPS:
        c = make()
        frames = sorted(f for f, names in c.markers.items() if "Hit" in names)
        out[c.name] = [f / FPS for f in frames]
    return out


if __name__ == "__main__":
    for c, baked in bake_all():
        speed = max(float(np.linalg.norm(np.diff(np.asarray(baked["Root"])[:, :3], axis=0), axis=1).max()) * FPS, 0)
        print("%-20s %3d frames  hits %-14s smoothing %s  root peak %.0f deg/s" % (
            c.name, c.frames, sorted(f for f, m in c.markers.items() if "Hit" in m), c.smoothing, speed))
