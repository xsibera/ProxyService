"""R6 two-handed sword (greatsword) set, in the style of the reference animations (ANIMSFORCLAUDE.rbxm)
and modelled on its two-handed blade: the kareemandbeast rig's m1-1, m1-2 and equip.

Clips: idle (looped), unsheathe (from the back), m1-1 (forehand cleave), m1-2 (backhand cleave),
m1-3 (overhead finisher), running attack (spinning cleave), aerial attack (overhead plunge), and
"m1 string (1,2,1,2,3)", which chains the M1s the way the game plays them, to preview the string.

Taken from the kareemandbeast two-handed swings: the left fist rides the grip 0.3-0.8 studs below
the right one (here it is locked there every frame: the left arm is solved onto the grip after the
clip is baked), the sword is cocked far back over one shoulder with the hands up behind the head,
and the torso winds the wrong way and then whips round.
Then made heavy: the sword is heaved up slowly with the body sinking under it and held loaded, its
blade laid back along the line it will swing (on_swing_line) so the swing starts from rest; the
cleaves build ("heave" curve: fastest just past the target) and the overheads speed up until they
slam into the floor ("slam"); the blade trails the hands by 28 deg as they pull and runs on ahead
of them at the end; the weight carries each cleave on round and drags the body after it (~195-215
deg), and the sword is hauled back slowly. Tips peak at about half the reference's speed; Hit
~0.82s into 1.4s clips.
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
    on_swing_line,
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
# the guard sits low and wide under the weight: both hands on the grip at the belt, the blade
# angled up and forward rather than held upright
GUARD_ROOT = [-6, 18, 1, 0, -0.3, 0]
GUARD = (np.array([0.32, -0.55, -1.45]), heading(6, 50), heading(6, -40))  # fist, blade, edge (world)
GUARD_NECK = [-5, 0, 0]
IDLE_FRAMES = 125  # 2.083s, one breath per loop, like the reference idles


def guard_keys(c, f=0, k="ease"):
    c.key("Root", f, GUARD_ROOT, k)
    c.key("Neck", f, GUARD_NECK, k)
    c.key("LArm", f, [0, 0, 0, 0, 0, 0], k)  # replaced by the grip


def idle():
    """The two-handed guard, breathing heavily under the weight: the torso rocking ~1.5 deg and
    sinking with each breath, the head following, the blade tip dipping and lifting."""
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

    baked["Root"][:, 0] += 1.5 * wave()
    baked["Root"][:, 4] += -0.024 * np.sin(t - phase - math.pi / 2)
    baked["Neck"][:, 0] += 1.8 * wave(0.2)
    baked["RArm"][:, 0] -= 2.6 * wave(0.12)
    baked["Handle"][:, 0] += 2.0 * wave(0.3)
    c.baked = tame(grip_pass(c, baked))
    return c


# --------------------------------------------------------------------------- the M1s
# Heavy: the sword is heaved up slowly with the body sinking under it and held loaded; the swing
# starts slow and builds ("heave": fastest about two thirds of the way round, after the target), the
# blade trailing the hands as they pull it and running on ahead of them at the end; its weight drags
# the body on past the finish, and it is hauled back slowly.
HEAVY_LAG = (28.0, -10.0)


def m1_1():
    """Forehand cleave: a counter-move (the tip dips toward the target), then the sword is heaved
    up and back over the right shoulder, the blade hanging down behind the back, as the body winds
    right and sinks; it holds loaded, then the hands haul it over the top and down through the target
    from high right to low left, the swing building speed as it goes, and its weight carries it on
    round and down by the left foot, dragging the body ~195 deg round after it. Hauled back up."""
    c = Clip("m1-1", 84, hit=45, arm="RArm", joints=JOINTS)
    c.slerp = {"RArm", "Handle"}
    guard_keys(c)
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(8, [-3, 26, 0, 0, -0.3, 0.02], "decel")
    R(26, [8, -64, 10, 0, -0.44, 0.32], "ease")  # heaves it up, winding and sinking
    R(34, [9, -70, 11, 0, -0.47, 0.35], "slowin")
    R(56, [-24, 126, -15, 0, -0.66, -0.5], "heave")  # thrown round after the sword, and past
    R(72, [-17, 104, -10, 0, -0.52, -0.36], "ease")  # hauls back
    R(84, [-18, 106, -10, 0, -0.53, -0.36], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(8, [-6, 0, 0], "decel")
    N(26, [-8, 0, -6], "ease")
    N(36, [-7, 0, -6], "slowin")
    N(46, [-16, 0, 9], "accel")
    N(56, [-20, 0, 12], "decel")
    N(72, [-13, 0, 8], "ease")
    N(84, [-14, 0, 8], "drift")
    cocked, through, end = [1.05, 1.62, 1.5], [0.3, 0.1, -2.0], [-1.85, -1.3, 0.25]
    m1_path(
        c, GUARD,
        pre=[(8, [0.55, -0.3, -1.65], heading(-12, 58), "decel"),
             # heaved back over the right shoulder, the blade laid back along the line it will swing
             (26, [1.0, 1.5, 1.35], on_swing_line(cocked, through, end, HEAVY_LAG[0], -10), "ease"),
             (34, cocked, on_swing_line(cocked, through, end, HEAVY_LAG[0]), "slowin")],
        arc=(34, 56, through, end, "heave"),
        post=[(72, [-1.55, -0.9, -0.35], heading(-130, -32), "ease"),  # hauled back up
              (84, [-1.55, -0.91, -0.34], heading(-129, -33), "drift")],
        lag=HEAVY_LAG,
    )
    c.baked = tame(grip_pass(c, c.bake()))
    return c


def m1_2():
    """Backhand cleave: the mirror of m1-1. Heaved back over the left shoulder as the body winds
    left and sinks, held, then hauled across the front from high left to low right, building speed,
    and carried on round behind the right hip by its weight, the body dragged ~215 deg round."""
    c = Clip("m1-2", 84, hit=45, arm="RArm", joints=JOINTS)
    c.slerp = {"RArm", "Handle"}
    guard_keys(c)
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(8, [-3, 10, 0, 0, -0.3, 0.0], "decel")
    R(26, [9, 82, -9, 0, -0.44, 0.32], "ease")
    R(34, [10, 88, -10, 0, -0.47, 0.35], "slowin")
    R(56, [-23, -128, 14, 0, -0.66, -0.5], "heave")
    R(72, [-16, -104, 8, 0, -0.52, -0.34], "ease")
    R(84, [-17, -106, 8, 0, -0.53, -0.34], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(8, [-6, 0, 0], "decel")
    N(26, [-8, 0, 6], "ease")
    N(36, [-7, 0, 6], "slowin")
    N(46, [-15, 0, -9], "accel")
    N(56, [-19, 0, -12], "decel")
    N(72, [-12, 0, -8], "ease")
    N(84, [-13, 0, -8], "drift")
    cocked, through, end = [-1.4, 1.55, 1.25], [0.0, 0.25, -2.05], [2.05, -1.05, 0.5]
    m1_path(
        c, GUARD,
        pre=[(8, [0.15, -0.25, -1.7], heading(16, 56), "decel"),
             # heaved back over the left shoulder, laid back along its swing line
             (26, [-1.3, 1.42, 1.1], on_swing_line(cocked, through, end, HEAVY_LAG[0], -10), "ease"),
             (34, cocked, on_swing_line(cocked, through, end, HEAVY_LAG[0]), "slowin")],
        arc=(34, 56, through, end, "heave"),
        post=[(72, [1.7, -0.6, -0.15], heading(125, -25), "ease"),
              (84, [1.7, -0.61, -0.14], heading(124, -26), "drift")],
        lag=HEAVY_LAG,
    )
    c.baked = tame(grip_pass(c, c.bake()))
    return c


def m1_3():
    """Finisher, an overhead cleave: the body sinks, then heaves the sword up high overhead with the
    blade hanging down the back, rising and leaning back under it; it holds at the top, then the
    whole body drops behind it as it comes over and straight down through the target, speeding up
    all the way until it slams into the floor in front. It jars to a stop and kicks back off the
    ground, the body sagging over it, and is dragged back up out of the ground."""
    c = Clip("m1-3", 100, hit=54, arm="RArm", joints=JOINTS)
    c.slerp = {"RArm", "Handle"}
    guard_keys(c)
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(8, [-5, 22, 0, 0, -0.36, 0.02], "decel")  # sinks to lift
    R(30, [16, 8, 2, 0, -0.14, 0.36], "ease")  # heaves it overhead, rising and leaning back
    R(40, [18, 6, 3, 0, -0.1, 0.4], "slowin")
    R(58, [-40, 12, -2, 0, -0.72, -0.7], "slam")  # the whole body drops behind it
    R(63, [-35, 12, -2, 0, -0.66, -0.66], "decel")  # jarred back off the floor
    R(70, [-39, 12, -2, 0, -0.71, -0.68], "ease")  # sags over it
    R(88, [-30, 10, -1, 0, -0.56, -0.54], "ease")  # dragged back up
    R(100, [-31, 10, -1, 0, -0.57, -0.54], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(8, [-8, 0, 0], "decel")
    N(30, [12, 0, 0], "ease")  # looks up at the blade... then at the target
    N(42, [6, 0, 0], "slowin")
    N(56, [-10, 0, 3], "accel")
    N(62, [-2, 0, 3], "decel")  # head snaps up with the jolt
    N(72, [-8, 0, 2], "ease")
    N(100, [-6, 0, 2], "drift")
    cocked, through, end = [0.4, 2.75, 0.8], [0.3, 0.6, -2.35], [0.3, -1.3, -1.5]
    m1_path(
        c, GUARD,
        pre=[(8, [0.4, -0.7, -1.45], heading(8, 36), "decel"),
             # heaved up overhead, the blade laid back behind the head along its swing line
             (30, [0.4, 2.6, 0.6], on_swing_line(cocked, through, end, 26.0, -10), "ease"),
             (40, cocked, on_swing_line(cocked, through, end, 26.0), "slowin")],
        arc=(40, 58, through, end, "slam"),
        post=[(63, [0.3, -1.12, -1.53], heading(2, -9), "decel"),  # kicks back off the floor
              (70, [0.3, -1.28, -1.5], heading(2, -15), "ease"),
              (88, [0.3, -1.0, -1.55], heading(2, -5), "ease"),  # dragged back up
              (100, [0.3, -1.01, -1.55], heading(2, -5.5), "drift")],
        lag=(26.0, 0.0),
        blade_end=heading(2, -16),
    )
    c.baked = tame(grip_pass(c, c.bake()))
    return c


M1S = [m1_1, m1_2, m1_3]


# --------------------------------------------------------------------------- running / aerial attacks
def running_attack():
    """Off a sprint with the greatsword dragged behind in the right hand, its tip scraping the
    floor: the left foot plants and the body heaves round to the right as the left hand takes the
    grip; then the sword's weight takes over and swings the whole body a full turn on the planted
    foot, leaning out against it with the blade flat at waist height, cleaving through the target
    as it comes round, the turn slowing as it carries on into a low wide stance."""
    c = Clip("running attack", 80, hit=None, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "Handle", "LArm"}
    c.neck_auto = False
    run = [-18, 0, 0, 0, -0.2, 0]
    wind = [-6, -72, 7, 0, -0.46, 0.2]
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(0, run)
    R(12, wind, "ease")  # plants and heaves round to the right
    R(20, [-8, -78, 8, 0, -0.5, 0.22], "slowin")
    R(58, [-18, 312, -12, 0, -0.62, -0.32], "heave")  # one full turn, and a bit, slowing at the end
    R(70, [-14, 296, -8, 0, -0.55, -0.28], "ease")
    R(80, [-15, 297, -8, 0, -0.56, -0.28], "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(0, [-10, 0, 0])
    N(12, [-12, 40, -4], "ease")  # eyes stay on the target as the body winds away
    N(22, [-12, 45, -4], "slowin")
    N(36, [-14, -35, 6], "accel")  # then whip round with the body
    N(52, [-16, -10, 8], "decel")
    N(68, [-12, -30, 6], "ease")
    N(80, [-12, -32, 6], "drift")
    roots = root_path(c)

    def torso_fly(f, hand_t, blade_t, edge_t, k="linear"):
        """Key the sword arm from Torso-space fist, blade and edge (it rides the spin)."""
        arm_ch, handle_ch = aim(hand_t, blade_t, edge=edge_t)
        c.key("RArm", f, arm_ch, k)
        c.key("Handle", f, handle_ch, k)

    # the run: dragged behind in the right hand, the tip scraping the floor
    fly(c, roots, 0, np.array([1.3, -1.05, 0.95]), heading(165, -38), heading(165, 52), "ease")
    fly(c, roots, 7, np.array([1.35, -0.95, 1.05]), heading(168, -36), heading(168, 54), "ease")
    # heaved up: out to the right side and back, flat, edge leading round (Torso space from here)
    torso_fly(12, [2.0, -0.4, 0.65], unit([0.75, -0.05, 0.66]), [0.66, 0.0, -0.75], "ease")
    torso_fly(20, [2.05, -0.35, 0.75], unit([0.7, -0.02, 0.72]), [0.72, 0.0, -0.7], "slowin")
    # the turn: held out flat in front of the right side, swept forward as the body turns
    for f, (hand, blade) in {
        28: ([2.0, -0.35, -0.4], [0.9, -0.04, -0.42]),
        34: ([1.6, -0.35, -1.4], [0.6, -0.06, -0.8]),
        40: ([1.3, -0.37, -1.65], [0.45, -0.07, -0.89]),
        54: ([1.2, -0.4, -1.7], [0.4, -0.09, -0.91]),
    }.items():
        b = unit(blade)
        torso_fly(f, hand, b, unit(np.cross([0.0, 1.0, 0.0], b)), "linear")
    # coming out of the turn, the blade's weight carries it on round to the left and down
    torso_fly(60, [0.2, -0.5, -2.0], unit([-0.55, -0.24, -0.8]), [-0.82, 0.0, 0.57], "decel")
    torso_fly(70, [-0.6, -0.6, -1.85], unit([-0.85, -0.32, -0.42]), [-0.42, 0.0, 0.9], "ease")
    torso_fly(80, [-0.62, -0.61, -1.84], unit([-0.85, -0.33, -0.42]), [-0.42, 0.0, 0.9], "drift")
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)  # noqa: E731
    L(0, [40, 0, -8, 0, 0, 0])  # running arm swing until it takes the grip
    L(7, [30, -6, -12, 0, 0, -0.05])
    for leg, f, v, k in (
        ("RLeg", 0, world_leg("RLeg", run, 32, 4), "ease"),
        ("LLeg", 0, world_leg("LLeg", run, -28, 4), "ease"),
        ("RLeg", 12, world_leg("RLeg", wind, -30, 10, -40), "ease"),
        ("LLeg", 12, world_leg("LLeg", wind, 40, 10, -20), "ease"),
        # through the turn the legs turn with the hips (a pivot), set wide
        ("RLeg", 40, [-24, 0, 12, 0, 0.05, 0], "linear"),
        ("LLeg", 40, [28, 0, -12, 0, 0.05, 0], "linear"),
        ("RLeg", 60, [-36, 0, 17, 0, 0.1, 0], "decel"),
        ("LLeg", 60, [38, 0, -17, 0, 0.1, 0], "decel"),
        ("RLeg", 70, [-31, 0, 14, 0, 0.08, 0], "ease"),
        ("LLeg", 70, [34, 0, -14, 0, 0.08, 0], "ease"),
        ("RLeg", 80, [-31, 0, 14, 0, 0.08, 0], "drift"),
        ("LLeg", 80, [34, 0, -14, 0, 0.08, 0], "drift"),
    ):
        c.key(leg, f, v, k)
    # the Hit is where the blade, held out at the front right, comes round to face the target: the
    # turn's yaw reaching the blade's own angle to the right of the chest
    blade_side = math.degrees(math.atan2(0.45, 0.89))
    c.hit = c.peak = next(f for f in range(20, c.frames) if roots[f][1] >= blade_side)
    c.markers = {c.hit: ["Hit"]}
    baked = c.bake()
    c.baked = tame(grip_pass(c, baked, ramp(c.frames + 1, 7, 14)))
    return c


def aerial_attack():
    """In the air: the knees tuck and the body leans back as the sword is heaved up overhead in
    both hands, blade hanging down the back; it holds at the top of the jump, then the body
    jack-knifes forward and the legs drop as the sword comes over and down through the target below,
    speeding up all the way, and lands with the weight: a jolt, a deep sag, and back up."""
    c = Clip("aerial attack", 72, hit=None, arm="RArm", joints=FULL)
    c.slerp = {"RArm", "Handle"}
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(0, [-4, 0, 0, 0, 0, 0])
    R(20, [22, -10, 4, 0, 0.38, 0.32], "ease")
    R(28, [24, -12, 5, 0, 0.4, 0.34], "slowin")
    R(44, [-46, 8, -4, 0, -0.6, -0.55], "slam")
    R(49, [-41, 8, -4, 0, -0.52, -0.5], "decel")  # jolt
    R(56, [-45, 8, -4, 0, -0.62, -0.52], "ease")  # sags under it
    R(72, [-38, 7, -3, 0, -0.5, -0.46], "ease")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(0, [-6, 0, 0])
    N(20, [-16, 0, 0], "ease")
    N(30, [-18, 0, 0], "slowin")
    N(40, [6, 0, 2], "accel")
    N(46, [14, 0, 2], "decel")  # head up, eyes on the target below
    N(60, [10, 0, 1], "ease")
    N(72, [10, 0, 1], "drift")
    cocked, through, end = [0.35, 2.75, 0.9], [0.25, 0.3, -2.3], [0.25, -1.9, -1.0]
    m1_path(
        c, (np.array([0.35, -0.45, -1.45]), heading(6, 48), heading(6, -42)),
        pre=[(20, [0.35, 2.6, 0.75], on_swing_line(cocked, through, end, 26.0, -10), "ease"),  # overhead
             (28, cocked, on_swing_line(cocked, through, end, 26.0), "slowin")],
        arc=(28, 45, through, end, "slam"),
        post=[(49, [0.25, -1.75, -1.12], heading(0, -44), "decel"),
              (56, [0.25, -1.85, -1.08], heading(0, -50), "ease"),
              (72, [0.25, -1.75, -1.1], heading(0, -46), "ease")],
        lag=(26.0, 0.0),
        blade_end=heading(0, -48),
    )
    G = lambda leg, f, v, k="ease": c.key(leg, f, v, k)  # noqa: E731
    G("RLeg", 0, [8, 0, 4, 0, 0, 0])
    G("LLeg", 0, [-8, 0, -4, 0, 0, 0])
    G("RLeg", 20, [72, 0, 8, 0, 0, 0], "ease")  # knees tucked
    G("LLeg", 20, [62, 0, -8, 0, 0, 0], "ease")
    G("RLeg", 28, [76, 0, 8, 0, 0, 0], "slowin")
    G("LLeg", 28, [66, 0, -8, 0, 0, 0], "slowin")
    G("RLeg", 42, [12, 0, 8, 0, 0, 0], "accel")  # legs drop under the body to land
    G("LLeg", 42, [50, 0, -6, 0, 0, 0], "accel")
    G("RLeg", 56, [18, 0, 7, 0, 0, 0], "ease")
    G("LLeg", 56, [48, 0, -6, 0, 0, 0], "ease")
    G("RLeg", 72, [16, 0, 6, 0, 0, 0], "drift")
    G("LLeg", 72, [46, 0, -6, 0, 0, 0], "drift")
    c.baked = tame(grip_pass(c, c.bake()))
    return c


EXTRA = [running_attack, aerial_attack]

# --------------------------------------------------------------------------- unsheathe
GRAB_FRAME = 14
PULLED_FRAME = 22
DRAW_PULL = 1.3  # studs up the scabbard by PULLED_FRAME
DRAW_PATH = [  # (frame, fist, blade) after the pull, world space
    (30, (1.45, 3.05, 0.45), (0.0, -0.75, 0.66)),  # hilt up by the right ear, the tip swinging out behind
    (37.5, (1.3, 3.05, -0.15), (0.15, 0.45, 0.88)),  # tip up behind the head
    (45, (1.05, 2.4, -0.95), (0.2, 0.97, -0.1)),  # blade overhead, coming forward
    (54.5, (0.75, 0.75, -1.55), tuple(heading(5, 26))),  # down in front, the left hand coming to it
    (66, (0.45, -0.45, -1.55), tuple(heading(4, 42))),  # the weight lands in both hands
    (74, tuple(GUARD[0]), tuple(GUARD[1])),
]


def unsheathe():
    """Draw from the back: the right hand reaches up over the shoulder and takes the hilt (the
    sword stays in the scabbard until then; "Sheathe/Unsheathe" fires on the grab) and pulls it up
    the scabbard, picking up speed; the hilt carries on up past the right ear as the tip swings out
    behind the back, up behind the head and over the top, and the blade comes down in front, where
    the left hand takes the grip, dips past the guard and settles into it. From the pull on, the
    sword follows one smooth spline (DRAW_PATH) in world space, so its speed never jumps."""
    c = Clip("unsheathe", 86, hit=None, arm="RArm", joints=JOINTS)
    c.slerp = {"RArm", "Handle"}
    c.peak = 38
    c.markers = {GRAB_FRAME: ["Sheathe/Unsheathe"]}
    R = lambda f, v, k="ease": c.key("Root", f, v, k)  # noqa: E731
    R(0, [0, 0, 0, 0, 0, 0])
    R(GRAB_FRAME, [4, -14, -4, 0, -0.08, 0.04], "coil")  # turns the right shoulder back to the hilt
    R(20, [5, -16, -5, 0, -0.08, 0.05], "slowin")
    R(44, [-8, 30, 4, 0, -0.28, -0.08], "ease")  # unwinds as the blade comes over
    R(60, [-10, 16, 0, 0, -0.44, 0.0], "ease")  # the weight lands in both hands: the knees give
    R(74, GUARD_ROOT, "ease")
    R(86, GUARD_ROOT, "drift")
    N = lambda f, v, k="ease": c.key("Neck", f, v, k)  # noqa: E731
    N(0, [0, 0, 0])
    N(GRAB_FRAME, [-4, 0, 6], "coil")
    N(44, [-10, 0, -2], "ease")
    N(74, GUARD_NECK, "ease")
    N(86, GUARD_NECK, "drift")
    sheath_hilt = SHEATH[:3, 3]
    out_dir = -SHEATH[:3, :3] @ np.array([0.0, 0.0, -1.0])  # back up the scabbard
    A = lambda f, v, k="ease": c.key("RArm", f, v, k)  # noqa: E731
    A(0, [0, 0, 0, 0, 0, 0])
    A(6, [-40, 14, 30, 0.0, 0.05, 0.05], "decel")
    L = lambda f, v, k="ease": c.key("LArm", f, v, k)  # noqa: E731
    L(0, [0, 0, 0, 0, 0, 0])
    L(GRAB_FRAME, [10, 10, 14, 0.04, 0, -0.06], "coil")
    L(44, [40, -20, -30, 0.1, 0.05, -0.3], "ease")  # comes up to meet the grip
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
        e = slerp(edge, guard_edge, smoothstep((f - 34) / 34)) if f > 34 else edge
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
    c.baked = tame(grip_pass(c, baked, ramp(c.frames + 1, 46, 57)))
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
