"""R6 two-handed sword (greatsword) set, in the style of the reference animations (ANIMSFORCLAUDE.rbxm)
and modelled on its two-handed blade: the kareemandbeast rig's m1-1, m1-2 and equip.

Clips: idle (looped), unsheathe (from the back), m1-1 (forehand cleave), m1-2 (backhand cleave),
m1-3 (overhead finisher), running attack (spinning cleave), aerial attack (overhead plunge), and
"m1 string (1,2,1,2,3)", which chains the M1s the way the game plays them, to preview the string.

Measured from the kareemandbeast two-handed swings and copied here:
  * Guard: both fists together on the grip in front of the chest, the blade standing up.
  * The left fist rides the grip 0.3-0.8 studs below the right one (toward the pommel) through the
    whole swing. Here it is locked there every frame: the left arm is solved onto the grip after
    the clip is baked.
  * Wind-up: the sword is cocked far back over one shoulder, the hands up behind the head.
  * The swing: the hands rip through a big circle round the body with the tip lagging behind them
    like a whip, then whipping through; Hit ~0.5s into ~0.92s clips; the torso winds ~65 deg the
    wrong way and then whips ~175 deg (forehand -60 -> +115, backhand +85 -> -105).
The arcs are exact circles: the hands travel a circle through three points (cocked, through the
target, follow-through) and the blade points out from its centre, so the tip draws a clean arc.
Both arms are solved from where their fists must be, then tame() caps how fast each arm may turn
(2,200 deg/s) and roll about itself (1,300 deg/s), within the reference's range, without moving a fist.
Conventions are the same as the one-handed set: the sword's Handle hangs off a "Handle" Motor6D in
the Right Arm (C0 at the fist), legs keyed at Weight 0 except in the running and aerial attacks,
60 fps, and the clips are 2x smoother than their keys (animkit).

Usage:  python3 generate_greatsword.py path/to/ANIMSFORCLAUDE.rbxmx
"""

import json
import math
import os
import sys
import xml.etree.ElementTree as ET

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ANIMS = os.path.dirname(HERE)
sys.path.insert(0, ANIMS)
sys.path.insert(0, os.path.join(ANIMS, "SwordCombo"))
from animkit import (  # noqa: E402
    FPS,
    Clip,
    build_string,
    clip_transforms,
    from_transform,
    prop,
    ref,
    reference_rig,
    sequence_xml,
    smoothstep,
    world_leg,
)
from generate_sword import (  # noqa: E402
    GRIP,
    MOTORS,
    _cf_of,
    _cframe_prop,
    _child,
    _joint,
    _model,
    _part,
    aim,
    cf,
    heading,
    inv,
    joint_cf,
    rz,
)

JOINTS = ("Root", "Neck", "RArm", "LArm", "Handle")
FULL = JOINTS + ("RLeg", "LLeg")

# --------------------------------------------------------------------------- the greatsword
# Handle space: the right fist at the origin (top of the grip, by the guard), blade along -Z, edges
# along +-Y, the grip running back along +Z to the pommel; the left fist sits LEFT_GRIP down it.
STEEL, DARK, LEATHER = (196, 201, 208), (66, 62, 60), (48, 33, 24)
TIP = 5.6
LEFT_GRIP = 0.62
SWORD_PARTS = [
    # name, class, size, position, rotation, colour, material, reflectance
    ("Handle", "Part", (0.26, 0.26, 1.35), (0, 0, 0.42), None, LEATHER, "Fabric", 0),
    ("Pommel", "Ball", (0.42, 0.42, 0.42), (0, 0, 1.18), None, DARK, "Metal", 0.05),
    ("Guard", "Part", (0.32, 1.9, 0.26), (0, 0, -0.4), None, DARK, "Metal", 0.05),
    ("Blade", "Part", (0.14, 0.62, 4.4), (0, 0, -2.73), None, STEEL, "Metal", 0.15),
    ("Fuller", "Part", (0.15, 0.13, 3.7), (0, 0, -2.45), None, (136, 141, 148), "Metal", 0.1),
    ("TipTop", "WedgePart", (0.14, 0.31, 0.68), (0, 0.155, -5.27), None, STEEL, "Metal", 0.15),
    ("TipBottom", "WedgePart", (0.14, 0.31, 0.68), (0, -0.155, -5.27), rz(180), STEEL, "Metal", 0.15),
]
# carried on the back: the hilt up behind the right shoulder, the blade running down across the back
# to the left hip (Torso space)
SHEATH_HILT = np.array([0.72, 1.85, 0.85])
SHEATH_DIR = np.array([-0.49, -0.87, -0.04])  # the way the blade points
SCABBARD_PARTS = [  # in the sheathed sword's Handle space
    ("Scabbard", "Part", (0.24, 0.78, 4.9), (0, 0, -3.0), None, LEATHER, "Fabric", 0),
    ("Locket", "Part", (0.3, 0.86, 0.3), (0, 0, -0.62), None, DARK, "Metal", 0.05),
    ("Chape", "Part", (0.28, 0.8, 0.36), (0, 0, -5.38), None, DARK, "Metal", 0.05),
]


def _sheath_cf():
    """Sheathed Handle CFrame (Torso space): blade down the back, its flat against the back."""
    z = -SHEATH_DIR / np.linalg.norm(SHEATH_DIR)
    x = np.array([0.0, 0.0, 1.0]) - z * z[2]
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return cf(SHEATH_HILT, np.column_stack([x, y, z]))


SHEATH = _sheath_cf()


from twohanded import (  # noqa: E402
    fly,
    m1_path,
    ramp,
    root_path,
    slerp,
    spline,
    tame,
    unit,
)
from twohanded import grip_pass as _grip_pass  # noqa: E402
from twohanded import tip_speeds as _tip_speeds  # noqa: E402


def grip_pass(c, baked, weight=None):
    """Lock the left fist onto the greatsword's grip, LEFT_GRIP below the right (see twohanded)."""
    return _grip_pass(c, baked, LEFT_GRIP, weight)


def tip_speeds(c, baked):
    return _tip_speeds(c, baked, TIP)


# --------------------------------------------------------------------------- guard / idle
GUARD_ROOT = [-4, 18, 1, 0, -0.22, 0]
GUARD = (np.array([0.32, -0.38, -1.5]), heading(4, 66), heading(4, -24))  # fist, blade, edge (world)
GUARD_NECK = [-5, 0, 0]
IDLE_FRAMES = 125  # 2.083s, one breath per loop, like the reference idles


def guard_keys(c, f=0, k="ease"):
    c.key("Root", f, GUARD_ROOT, k)
    c.key("Neck", f, GUARD_NECK, k)
    c.key("LArm", f, [0, 0, 0, 0, 0, 0], k)  # replaced by the grip


def idle():
    """The two-handed guard, breathing: the sword held up in front with both hands, the torso
    rocking ~1 deg and bobbing with the breath, the head following, the blade tip drifting."""
    c = Clip("idle", IDLE_FRAMES, hit=None, arm="RArm", joints=JOINTS)
    c.smooth = False
    c.loop = True
    guard_keys(c)
    roots = root_path(c)
    fly(c, roots, 0, *GUARD, "ease")
    baked = c.bake()
    t = np.arange(IDLE_FRAMES + 1) / IDLE_FRAMES * 2 * math.pi
    phase = 2 * math.pi * 0.16

    def wave(lag=0.0):
        return np.sin(t - phase - 2 * math.pi * lag / (IDLE_FRAMES / FPS))

    baked["Root"][:, 0] += 1.1 * wave()
    baked["Root"][:, 4] += -0.014 * np.sin(t - phase - math.pi / 2)
    baked["Neck"][:, 0] += 1.4 * wave(0.2)
    baked["RArm"][:, 0] -= 2.0 * wave(0.1)
    baked["Handle"][:, 0] += 1.4 * wave(0.25)
    c.baked = tame(grip_pass(c, baked))
    return c


# --------------------------------------------------------------------------- the M1s
def m1_1():
    """Forehand cleave: a counter-move (the tip dips toward the target), then the sword is cocked
    far back over the right shoulder, the blade hanging down behind the back, as the body winds
    right; it holds loaded, then the hands rip over the top and down through the target from high
    right to low left with the tip whipping round behind them, the body whipping ~175 deg left."""
    c = Clip("m1-1", 56, hit=30, arm="RArm", joints=JOINTS)
    c.slerp = {"RArm", "Handle"}
    guard_keys(c)
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(5, [-2, 26, 0, 0, -0.2, 0.02], "decel")
    R(16, [6, -62, 10, 0, -0.3, 0.3], "coil")
    R(22, [7, -68, 11, 0, -0.32, 0.33], "slowin")
    R(33, [-18, 108, -12, 0, -0.42, -0.4], "whip")
    R(37, [-19, 116, -13, 0, -0.43, -0.44], "stop")
    R(48, [-14, 96, -8, 0, -0.36, -0.28], "settle")
    R(56, [-15, 98, -8, 0, -0.37, -0.28], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(16, [-8, 0, -6], "coil")
    N(24, [-7, 0, -6], "slowin")
    N(30, [-16, 0, 9], "snap")
    N(35, [-19, 0, 12], "stop")
    N(48, [-13, 0, 8], "settle")
    N(56, [-14, 0, 8], "drift")
    m1_path(
        c, GUARD,
        pre=[(5, [0.55, -0.12, -1.65], heading(-12, 74), "decel"),
             (16, [1.0, 1.6, 1.4], heading(200, -20), "coil"),  # cocked over the right shoulder
             (22, [1.05, 1.75, 1.55], heading(205, -28), "slowin")],
        arc=(22, 38, [0.3, 0.2, -2.0], [-1.7, -0.8, -0.1], "whip"),
        post=[(48, [-1.55, -0.75, -0.35], heading(-130, -30), "settle"),
              (56, [-1.55, -0.77, -0.33], heading(-128, -31), "drift")],
    )
    c.baked = tame(grip_pass(c, c.bake()))
    return c


def m1_2():
    """Backhand cleave: the mirror of m1-1. Cocked far back over the left shoulder as the body winds
    left, then ripped across the front from high left to low right, carried round behind the right
    hip, the body whipping ~200 deg right."""
    c = Clip("m1-2", 56, hit=31, arm="RArm", joints=JOINTS)
    c.slerp = {"RArm", "Handle"}
    guard_keys(c)
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(5, [-2, 10, 0, 0, -0.2, 0.0], "decel")
    R(16, [7, 82, -8, 0, -0.3, 0.3], "coil")
    R(22, [8, 88, -9, 0, -0.32, 0.33], "slowin")
    R(34, [-17, -112, 11, 0, -0.42, -0.4], "whip")
    R(38, [-18, -118, 12, 0, -0.43, -0.43], "stop")
    R(48, [-13, -100, 7, 0, -0.36, -0.28], "settle")
    R(56, [-14, -102, 7, 0, -0.37, -0.28], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(16, [-8, 0, 6], "coil")
    N(24, [-7, 0, 6], "slowin")
    N(31, [-15, 0, -9], "snap")
    N(36, [-18, 0, -12], "stop")
    N(48, [-12, 0, -8], "settle")
    N(56, [-13, 0, -8], "drift")
    m1_path(
        c, GUARD,
        pre=[(5, [0.15, -0.08, -1.7], heading(16, 72), "decel"),
             (16, [-1.3, 1.5, 1.15], heading(152, -16), "coil"),  # cocked over the left shoulder
             (22, [-1.4, 1.62, 1.3], heading(157, -22), "slowin")],
        arc=(22, 37, [0.0, 0.35, -2.05], [1.85, -0.5, 0.05], "whip"),
        post=[(48, [1.7, -0.55, -0.15], heading(125, -25), "settle"),
              (56, [1.7, -0.56, -0.14], heading(124, -26), "drift")],
    )
    c.baked = tame(grip_pass(c, c.bake()))
    return c


def m1_3():
    """Finisher, an overhead cleave: a dip, then the sword is raised high overhead with the blade
    hanging down the back as the body rises and leans back; it holds loaded, then the body folds
    forward and drops as the sword comes over the top and straight down through the target and on
    into the floor in front, the tip striking just short of the ground. Held there, then drifts."""
    c = Clip("m1-3", 72, hit=36, arm="RArm", joints=JOINTS)
    c.slerp = {"RArm", "Handle"}
    guard_keys(c)
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(6, [-3, 22, 0, 0, -0.26, 0.02], "decel")
    R(20, [14, 8, 2, 0, -0.1, 0.32], "coil")  # rises and leans back, sword overhead
    R(28, [16, 6, 3, 0, -0.08, 0.36], "slowin")
    R(39, [-34, 12, -2, 0, -0.55, -0.62], "whip")  # folds forward and drops into it
    R(43, [-37, 13, -2, 0, -0.58, -0.68], "stop")
    R(58, [-31, 10, -1, 0, -0.52, -0.56], "settle")
    R(72, [-32, 10, -1, 0, -0.53, -0.56], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(6, [-8, 0, 0], "decel")
    N(20, [12, 0, 0], "coil")  # looks up at the blade's arc... then at the target
    N(30, [6, 0, 0], "slowin")
    N(37, [-10, 0, 3], "snap")
    N(43, [-4, 0, 3], "stop")  # head up, eyes on the target over the blade
    N(58, [-6, 0, 2], "settle")
    N(72, [-6, 0, 2], "drift")
    m1_path(
        c, GUARD,
        pre=[(6, [0.4, -0.55, -1.45], heading(8, 48), "decel"),
             (20, [0.4, 2.7, 0.55], heading(180, -55), "coil"),  # overhead, blade down the back
             (28, [0.4, 2.85, 0.75], heading(180, -66), "slowin")],
        arc=(28, 43, [0.3, 0.7, -2.35], [0.3, -1.25, -1.5], "whip"),
        post=[(58, [0.3, -1.15, -1.55], heading(2, -16), "settle"),
              (72, [0.3, -1.16, -1.55], heading(2, -16.5), "drift")],
        lag=(20.0, 0.0),
        blade_end=heading(2, -16),
    )
    c.baked = tame(grip_pass(c, c.bake()))
    return c


M1S = [m1_1, m1_2, m1_3]


# --------------------------------------------------------------------------- running / aerial attacks
def running_attack():
    """Off a sprint with the greatsword dragged low behind in the right hand: the left foot plants
    and the body winds right as the left hand takes the grip, then the whole body spins a full turn
    on the planted foot with the blade held flat out at waist height, cleaving through the target
    as it comes round, and the spin carries on into a low wide stance."""
    c = Clip("running attack", 66, hit=31, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "Handle", "LArm"}
    c.neck_auto = False
    run = [-18, 0, 0, 0, -0.2, 0]
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(0, run)
    R(10, [-6, -72, 7, 0, -0.42, 0.2], "coil")  # plants and winds right
    R(16, [-8, -78, 8, 0, -0.46, 0.22], "slowin")
    R(42, [-16, 300, -10, 0, -0.56, -0.3], "whip")  # one full turn, and a bit
    R(47, [-17, 312, -11, 0, -0.58, -0.34], "stop")
    R(56, [-13, 294, -7, 0, -0.52, -0.28], "settle")
    R(66, [-14, 296, -7, 0, -0.53, -0.28], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(0, [-10, 0, 0])
    N(10, [-12, 40, -4], "coil")  # eyes stay on the target as the body winds away
    N(18, [-12, 45, -4], "slowin")
    N(30, [-14, -35, 6], "snap")  # then whip round with the body
    N(42, [-16, -10, 8], "stop")
    N(56, [-12, -30, 6], "settle")
    N(66, [-12, -32, 6], "drift")
    roots = root_path(c)

    def torso_fly(f, hand_t, blade_t, edge_t, k="linear"):
        """Key the sword arm from Torso-space fist, blade and edge (it rides the spin)."""
        arm_ch, handle_ch = aim(hand_t, blade_t, edge=edge_t)
        c.key("RArm", f, arm_ch, k)
        c.key("Handle", f, handle_ch, k)

    # the run: dragged low behind in the right hand, tip trailing on the floor
    fly(c, roots, 0, np.array([1.3, -1.0, 0.9]), heading(165, -32), heading(165, 58), "ease")
    fly(c, roots, 6, np.array([1.35, -0.9, 1.0]), heading(168, -30), heading(168, 60), "ease")
    # wound up: out to the right side and back, flat, edge leading round (Torso space from here)
    torso_fly(10, [2.0, -0.35, 0.65], unit([0.75, 0.0, 0.66]), [0.66, 0.0, -0.75], "coil")
    torso_fly(16, [2.05, -0.3, 0.75], unit([0.7, 0.02, 0.72]), [0.72, 0.0, -0.7], "slowin")
    # the spin: held out flat in front of the right side, swept forward as the body turns
    for f, (hand, blade) in {
        22: ([2.0, -0.3, -0.4], [0.9, -0.02, -0.42]),
        26: ([1.6, -0.3, -1.4], [0.6, -0.05, -0.8]),
        30: ([1.3, -0.32, -1.65], [0.45, -0.06, -0.89]),
        42: ([1.2, -0.35, -1.7], [0.4, -0.08, -0.91]),
    }.items():
        b = unit(blade)
        torso_fly(f, hand, b, unit(np.cross([0.0, 1.0, 0.0], b)), "linear")
    # coming out of the spin, the blade swings on round to the left and down
    torso_fly(47, [0.2, -0.45, -2.0], unit([-0.55, -0.2, -0.81]), [-0.82, 0.0, 0.57], "stop")
    torso_fly(56, [-0.6, -0.55, -1.85], unit([-0.85, -0.3, -0.42]), [-0.42, 0.0, 0.9], "settle")
    torso_fly(66, [-0.62, -0.56, -1.84], unit([-0.85, -0.31, -0.42]), [-0.42, 0.0, 0.9], "drift")
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)  # noqa: E731
    L(0, [40, 0, -8, 0, 0, 0])  # running arm swing until it takes the grip
    L(6, [30, -6, -12, 0, 0, -0.05])
    for leg, f, v, k in (
        ("RLeg", 0, world_leg("RLeg", run, 32, 4), "ease"),
        ("LLeg", 0, world_leg("LLeg", run, -28, 4), "ease"),
        ("RLeg", 10, world_leg("RLeg", [-6, -72, 7, 0, -0.42, 0.2], -30, 10, -40), "coil"),
        ("LLeg", 10, world_leg("LLeg", [-6, -72, 7, 0, -0.42, 0.2], 40, 10, -20), "coil"),
        # through the spin the legs turn with the hips (a pivot), set wide
        ("RLeg", 30, [-24, 0, 12, 0, 0.05, 0], "linear"),
        ("LLeg", 30, [28, 0, -12, 0, 0.05, 0], "linear"),
        ("RLeg", 47, [-34, 0, 16, 0, 0.1, 0], "stop"),
        ("LLeg", 47, [36, 0, -16, 0, 0.1, 0], "stop"),
        ("RLeg", 56, [-30, 0, 14, 0, 0.08, 0], "settle"),
        ("LLeg", 56, [33, 0, -14, 0, 0.08, 0], "settle"),
        ("RLeg", 66, [-30, 0, 14, 0, 0.08, 0], "drift"),
        ("LLeg", 66, [33, 0, -14, 0, 0.08, 0], "drift"),
    ):
        c.key(leg, f, v, k)
    baked = c.bake()
    c.baked = tame(grip_pass(c, baked, ramp(c.frames + 1, 6, 12)))
    return c


def aerial_attack():
    """In the air: the knees tuck and the body leans back as the sword is raised overhead in both
    hands, blade hanging down the back; it holds, then the body jack-knifes forward and the legs
    drop as the sword comes over the top and straight down through the target below."""
    c = Clip("aerial attack", 58, hit=32, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "Handle"}
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(0, [-4, 0, 0, 0, 0, 0])
    R(14, [20, -10, 4, 0, 0.35, 0.3], "coil")
    R(22, [22, -12, 5, 0, 0.38, 0.32], "slowin")
    R(35, [-42, 8, -4, 0, -0.5, -0.5], "whip")
    R(39, [-45, 9, -4, 0, -0.52, -0.54], "stop")
    R(50, [-38, 7, -3, 0, -0.45, -0.46], "settle")
    R(58, [-39, 7, -3, 0, -0.46, -0.46], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(0, [-6, 0, 0])
    N(14, [-16, 0, 0], "coil")
    N(22, [-18, 0, 0], "slowin")
    N(30, [6, 0, 2], "snap")
    N(35, [14, 0, 2], "stop")  # head up, eyes on the target below
    N(50, [10, 0, 1], "settle")
    N(58, [10, 0, 1], "drift")
    m1_path(
        c, (np.array([0.35, -0.3, -1.45]), heading(4, 62), heading(4, -28)),
        pre=[(14, [0.35, 2.6, 0.75], heading(180, -50), "coil"),  # overhead, blade down the back
             (22, [0.35, 2.75, 0.9], heading(180, -60), "slowin")],
        arc=(22, 38, [0.25, 0.3, -2.3], [0.25, -1.9, -1.0], "whip"),
        post=[(50, [0.25, -1.8, -1.1], heading(0, -50), "settle"),
              (58, [0.25, -1.81, -1.1], heading(0, -51), "drift")],
        lag=(20.0, 0.0),
        blade_end=heading(0, -48),
    )
    G = lambda leg, f, v, k="ease": c.key(leg, f, v, k)  # noqa: E731
    G("RLeg", 0, [8, 0, 4, 0, 0, 0])
    G("LLeg", 0, [-8, 0, -4, 0, 0, 0])
    G("RLeg", 14, [72, 0, 8, 0, 0, 0], "coil")  # knees tucked
    G("LLeg", 14, [62, 0, -8, 0, 0, 0], "coil")
    G("RLeg", 22, [76, 0, 8, 0, 0, 0], "slowin")
    G("LLeg", 22, [66, 0, -8, 0, 0, 0], "slowin")
    G("RLeg", 33, [12, 0, 8, 0, 0, 0], "snap")  # legs drop under the body to land
    G("LLeg", 33, [50, 0, -6, 0, 0, 0], "snap")
    G("RLeg", 46, [16, 0, 6, 0, 0, 0], "settle")
    G("LLeg", 46, [46, 0, -6, 0, 0, 0], "settle")
    G("RLeg", 58, [16, 0, 6, 0, 0, 0], "drift")
    G("LLeg", 58, [46, 0, -6, 0, 0, 0], "drift")
    c.baked = tame(grip_pass(c, c.bake()))
    return c


EXTRA = [running_attack, aerial_attack]

# --------------------------------------------------------------------------- unsheathe
GRAB_FRAME = 14
PULLED_FRAME = 22
DRAW_PULL = 1.3  # studs up the scabbard by PULLED_FRAME
DRAW_PATH = [  # (frame, fist, blade) after the pull, world space
    (28, (1.45, 3.05, 0.45), (0.0, -0.75, 0.66)),  # hilt up by the right ear, the tip swinging out behind
    (33.5, (1.3, 3.05, -0.15), (0.15, 0.45, 0.88)),  # tip up behind the head
    (39, (1.05, 2.4, -0.95), (0.2, 0.97, -0.1)),  # blade overhead, coming forward
    (46.5, (0.75, 0.9, -1.55), tuple(heading(5, 30))),  # down in front, the left hand coming to it
    (55, (0.45, -0.25, -1.55), tuple(heading(4, 55))),
    (60, tuple(GUARD[0]), tuple(GUARD[1])),
]


def unsheathe():
    """Draw from the back: the right hand reaches up over the shoulder and takes the hilt (the
    sword stays in the scabbard until then; "Sheathe/Unsheathe" fires on the grab) and pulls it up
    the scabbard, picking up speed; the hilt carries on up past the right ear as the tip swings out
    behind the back, up behind the head and over the top, and the blade comes down in front, where
    the left hand takes the grip, dips past the guard and settles into it. From the pull on, the
    sword follows one smooth spline (DRAW_PATH) in world space, so its speed never jumps."""
    c = Clip("unsheathe", 72, hit=None, arm="RArm", joints=JOINTS)
    c.slerp = {"RArm", "Handle"}
    c.peak = 33
    c.markers = {GRAB_FRAME: ["Sheathe/Unsheathe"]}
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(0, [0, 0, 0, 0, 0, 0])
    R(GRAB_FRAME, [4, -14, -4, 0, -0.08, 0.04], "coil")  # turns the right shoulder back to the hilt
    R(20, [5, -16, -5, 0, -0.08, 0.05], "slowin")
    R(38, [-8, 30, 4, 0, -0.26, -0.08], "ease")  # unwinds as the blade comes over
    R(50, [-3, 14, 0, 0, -0.2, 0.02], "ease")
    R(60, GUARD_ROOT, "settle")
    R(72, GUARD_ROOT, "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(0, [0, 0, 0])
    N(GRAB_FRAME, [-4, 0, 6], "coil")
    N(38, [-10, 0, -2], "ease")
    N(60, GUARD_NECK, "settle")
    N(72, GUARD_NECK, "drift")
    sheath_hilt = SHEATH[:3, 3]
    out_dir = -SHEATH[:3, :3] @ np.array([0.0, 0.0, -1.0])  # back up the scabbard
    A = lambda f, v, k="ease": c.key("RArm", f, v, k)  # noqa: E731
    A(0, [0, 0, 0, 0, 0, 0])
    A(6, [-40, 14, 30, 0.0, 0.05, 0.05], "decel")
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)  # noqa: E731
    L(0, [0, 0, 0, 0, 0, 0])
    L(GRAB_FRAME, [10, 10, 14, 0.04, 0, -0.06], "coil")
    L(36, [40, -20, -30, 0.1, 0.05, -0.3], "ease")  # comes up to meet the grip
    roots = root_path(c)

    def slid(f):  # the sword in the scabbard, slid s studs up it (Torso space)
        u = max(0.0, (f - GRAB_FRAME) / (PULLED_FRAME - GRAB_FRAME))
        s = DRAW_PULL * u**3  # picks up speed all the way, into the swing
        sword = SHEATH.copy()
        sword[:3, 3] = sheath_hilt + out_dir * s
        return sword

    def world(f, m):
        return joint_cf("Root", roots[f]) @ m

    # one continuous path from the grab into the guard (world space, keyed every frame): up out of
    # the scabbard, then the hilt rises over the right shoulder while the tip swings out behind the
    # back, up over the head and down in front; the spline carries the pull's speed on into the swing
    w22, w21 = world(PULLED_FRAME, slid(PULLED_FRAME)), world(PULLED_FRAME - 1, slid(PULLED_FRAME - 1))
    tip22, tip21 = (w22 @ np.array([0, 0, -TIP, 1]))[:3], (w21 @ np.array([0, 0, -TIP, 1]))[:3]
    frames = [PULLED_FRAME] + [f for f, _, _ in DRAW_PATH]
    hands = [w22[:3, 3]] + [np.asarray(h, float) for _, h, _ in DRAW_PATH]
    tips = [tip22] + [h + TIP * unit(b) for (_, _, b), h in zip(DRAW_PATH, hands[1:], strict=True)]
    hand_at = spline(frames, hands, w22[:3, 3] - w21[:3, 3], np.zeros(3))
    tip_at = spline(frames, tips, tip22 - tip21, np.zeros(3))
    edge, target = None, {}
    for f in range(GRAB_FRAME, c.frames + 1):
        if f <= PULLED_FRAME:
            m = world(f, slid(f))
            hand, blade, edge = m[:3, 3], -m[:3, 2], m[:3, 1]
        else:
            g = min(f, frames[-1])
            hand = hand_at(g)
            blade = unit(tip_at(g) - hand)
            edge = unit(edge - blade * float(edge @ blade))  # carried along without twisting
        guard_edge = unit(GUARD[2] - blade * float(GUARD[2] @ blade))
        e = slerp(edge, guard_edge, smoothstep((f - 30) / 26)) if f > 30 else edge
        fly(c, roots, f, hand, blade, e, "coil" if f == GRAB_FRAME else "linear")
        y = unit(e - blade * float(e @ blade))
        target[f] = inv(joint_cf("Root", roots[f])) @ cf(hand, np.column_stack([np.cross(y, -blade), y, -blade]))
    baked = c.bake()
    # the arm is smoothed, but the sword keeps to its path exactly: in the scabbard until the grab
    # whatever the arm is doing, slid straight up it, then along the spline (the wrist takes up the
    # difference)
    for f in range(c.frames + 1):
        t = inv(GRIP) @ inv(joint_cf("RArm", baked["RArm"][f])) @ (slid(f) if f <= PULLED_FRAME else target[f])
        baked["Handle"][f] = np.array(from_transform("Handle", t[:3, 3], t[:3, :3]))
    c.baked = tame(grip_pass(c, baked, ramp(c.frames + 1, 37, 46)))
    return c


# --------------------------------------------------------------------------- full-string preview
STRING_NAME = "m1 string (1,2,1,2,3)"
STRING_ORDER = ["m1-1", "m1-2", "m1-1", "m1-2", "m1-3"]
STRING_FADE = 0.15
STRING_END_FADE = 0.3


def _baked(c):
    b = getattr(c, "baked", None)
    if b is None:
        b = c.bake()
        c.baked = b
    return c, b


# --------------------------------------------------------------------------- rig + export
def add_greatsword(rig):
    """The greatsword in the right hand on a "Handle" Motor6D, its scabbard welded across the back."""
    torso, rarm = _child(rig, "Part", "Torso"), _child(rig, "Part", "Right Arm")
    for joint, motor in (("RArm", "Right Shoulder"), ("LArm", "Left Shoulder"), ("Neck", "Neck"),
                         ("RLeg", "Right Hip"), ("LLeg", "Left Hip")):
        m = _child(rig, "Motor6D", motor)
        assert np.allclose(_cf_of(m, "C0"), MOTORS[joint][0], atol=1e-4), motor
        assert np.allclose(_cf_of(m, "C1"), MOTORS[joint][1], atol=1e-4), motor
    t_world, a_world = _cf_of(torso), _cf_of(rarm)
    handle_world = a_world @ GRIP
    sword = _model("Greatsword")
    handle = None
    for name, cls, size, pos, rot, col, mat, refl in SWORD_PARTS:
        local = cf(pos, rot)
        if name == "Handle":
            # the Handle part's origin is the right fist: keep the part centred on the grip but
            # the motor's frame at the fist by offsetting the part, not the joint
            local = cf((0, 0, 0))
        part = _part(rarm, name, cls, size, handle_world @ local, col, mat, refl)
        sword.append(part)
        if name == "Handle":
            handle = part
        else:
            part.append(_joint("Weld", name, handle.get("referent"), part.get("referent"), local, np.eye(4)))
    # the grip itself, as a welded part centred down the handle (the Handle part is the fist point)
    grip = _part(rarm, "Grip", "Part", SWORD_PARTS[0][2], handle_world @ cf(SWORD_PARTS[0][3]), LEATHER, "Fabric", 0)
    grip.append(_joint("Weld", "Grip", handle.get("referent"), grip.get("referent"), cf(SWORD_PARTS[0][3]), np.eye(4)))
    sword.append(grip)
    for name, z in (("SwingBase", -0.6), ("SwingTip", -TIP + 0.06)):  # for CombatVFX.Swing
        att = ET.SubElement(handle, "Item", {"class": "Attachment", "referent": ref()})
        aprops = ET.SubElement(att, "Properties")
        prop(aprops, "string", "Name", name)
        _cframe_prop(aprops, "CFrame", cf((0, 0, z)))
    rarm.append(_joint("Motor6D", "Handle", rarm.get("referent"), handle.get("referent"), GRIP, np.eye(4)))
    rig.append(sword)
    scabbard = _model("Scabbard")
    for name, cls, size, pos, rot, col, mat, refl in SCABBARD_PARTS:
        local = SHEATH @ cf(pos, rot)
        part = _part(rarm, name, cls, size, t_world @ local, col, mat, refl)
        part.append(_joint("Weld", name, torso.get("referent"), part.get("referent"), local, np.eye(4)))
        scabbard.append(part)
    rig.append(scabbard)


def build(rig_source, out_dir=HERE):
    clips = [idle(), unsheathe()] + [m() for m in M1S] + [m() for m in EXTRA]
    sequences, by_name, data = [], {}, {}
    for c in clips:
        c, baked = _baked(c)
        frames = clip_transforms(c, baked)
        by_name[c.name] = (c, frames)
        data[c.name] = {"hit": c.hit, "frames": c.frames, "loop": c.loop,
                        "channels": {j: np.asarray(baked[j]).tolist() for j in c.joints}}
        speed = tip_speeds(c, baked)
        print("%-15s %3d frames  hit %-4s smoothing %-26s tip peak %4.0f studs/s @f%d" % (
            c.name, c.frames, c.hit, c.smoothing, speed.max(), int(speed.argmax())))
        sequences.append(sequence_xml(c.name, frames, c.markers, loop=c.loop))
    guard = by_name["idle"][1][0]
    cancel = {n: (by_name[n][0].hit / FPS + 0.15) for n in ("m1-1", "m1-2")}
    string_frames, string_hits = build_string(
        [by_name[n] for n in STRING_ORDER], cancel, STRING_FADE, STRING_END_FADE, guard, guard)
    sequences.append(sequence_xml(STRING_NAME, string_frames, string_hits))
    json.dump(data, open(os.path.join(out_dir, "greatsword_data.json"), "w"))
    rig, saves = reference_rig(rig_source, "Greatsword Rig")
    add_greatsword(rig)
    for s in sequences:
        saves.append(s)
    root = ET.Element("roblox", {"version": "4"})
    root.append(rig)
    out = os.path.join(out_dir, "GreatswordCombo.rbxmx")
    ET.ElementTree(root).write(out, encoding="utf-8", xml_declaration=False)
    print("string cancels:", {k: round(v, 3) for k, v in cancel.items()})
    print("wrote", out)
    return out


if __name__ == "__main__":
    build(sys.argv[1])
