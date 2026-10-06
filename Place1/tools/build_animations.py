"""Source of truth for the R6 combat animations.

Arms can be posed with IK: ik((x, y, z)) puts that fist at a point in HumanoidRootPart space
(X right, Y up, -Z forward; the HRP centre is 3 studs above the ground and the head centre is at
Y = 1.5). The solver turns targets into plain joint angles and writes
src/ReplicatedStorage/Combat/AnimationData.luau, so the game itself never runs IK.

    python3 tools/build_animations.py            # regenerate AnimationData.luau
    python3 tools/preview_poses.py Jab --out previews   # render keyframes to PNG
"""

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import preview_poses as pp  # noqa: E402

OUT = os.path.join(HERE, "..", "src", "ReplicatedStorage", "Combat", "AnimationData.luau")
JOINTS = ["Root", "Neck", "RArm", "LArm", "RLeg", "LLeg"]
ARM_PART = {"RArm": "Right Arm", "LArm": "Left Arm"}
FIST = np.array([0, -0.9, 0, 1.0])


class ik:
    def __init__(self, target, roll=0.0):
        self.target = np.array(target, float)
        self.roll = roll


def _fist(pose, arm):
    return (pp.solve(pose)[ARM_PART[arm]] @ FIST)[:3]


def solve_arm(pose, arm, spec):
    best = None
    for p in range(-70, 185, 5):
        for y in range(-95, 96, 5):
            q = dict(pose)
            q[arm] = [p, y, spec.roll]
            d = np.linalg.norm(_fist(q, arm) - spec.target)
            if best is None or d < best[0]:
                best = [d, float(p), float(y)]
    d, p, y = best
    step = 2.5
    while step > 0.1:
        moved = False
        for dp, dy in ((step, 0), (-step, 0), (0, step), (0, -step)):
            q = dict(pose)
            q[arm] = [p + dp, y + dy, spec.roll]
            dd = np.linalg.norm(_fist(q, arm) - spec.target)
            if dd < d:
                d, p, y, moved = dd, p + dp, y + dy, True
        if not moved:
            step /= 2
    if d > 0.35:
        print("  note: %s target %s unreachable by %.2f studs" % (arm, spec.target, d))
    return [round(p), round(y), spec.roll]


def resolve(pose_spec, poses):
    """pose_spec: name | dict(base=name, joint=values|ik). Returns (base, overrides) with numbers."""
    if isinstance(pose_spec, str):
        return pose_spec, {}
    base = pose_spec.get("base")
    full = dict(poses[base]) if base else {}
    over = {}
    # non-IK joints first, since the arm IK depends on the torso
    for j, v in pose_spec.items():
        if j != "base" and not isinstance(v, ik):
            full[j] = v
            over[j] = v
    for j, v in pose_spec.items():
        if isinstance(v, ik):
            full[j] = solve_arm(full, j, v)
            over[j] = full[j]
    return base, over


def full_pose(pose_spec, poses):
    base, over = resolve(pose_spec, poses)
    out = dict(poses[base]) if base else {}
    out.update(over)
    return out


# =============================================================================== poses
GUARD_ROOT = [-5, -12, 0, 0, -0.12, 0]
GUARD_LEGS = dict(RLeg=[-8, 8, 7], LLeg=[20, 8, -7])

POSE_SPECS = [
    ("Neutral", {}),
    (
        "Guard",
        dict(
            Root=GUARD_ROOT,
            Neck=[-6, 9, 0],
            LArm=ik((-0.15, 0.9, -1.95)),
            RArm=ik((0.4, 1.05, -1.25)),
            **GUARD_LEGS,
        ),
    ),
    (
        "Block",
        dict(
            Root=[-10, -4, 0, 0, -0.2, 0.05],
            Neck=[-14, 3, 0],
            RArm=ik((-0.25, 1.2, -1.35), roll=-12),
            LArm=ik((0.25, 1.45, -1.3), roll=12),
            RLeg=[-12, 6, 8],
            LLeg=[18, 6, -8],
        ),
    ),
    (
        "Jump",
        dict(
            Root=[4, 0, 0, 0, 0.05, 0],
            Neck=[-4, 0, 0],
            RArm=[40, 0, 20],
            LArm=[30, 0, -24],
            RLeg=[34, 0, 4],
            LLeg=[-20, 0, -4],
        ),
    ),
    (
        "Fall",
        dict(
            Root=[-4, 0, 0],
            Neck=[6, 0, 0],
            RArm=[125, 0, 38],
            LArm=[118, 0, -38],
            RLeg=[16, 0, 8],
            LLeg=[-10, 0, -8],
        ),
    ),
    (
        "Slide",
        dict(
            Root=[36, 0, 0, 0, -1.1, 0.3],
            Neck=[-30, 0, 0],
            RArm=[80, 30, 10],
            LArm=[-62, 0, -26],
            RLeg=[24, 0, 14],
            LLeg=[40, 0, -4],
        ),
    ),
]


def build_poses():
    poses = {}
    for name, spec in POSE_SPECS:
        poses[name] = full_pose(spec, poses)
    return poses


def guard(**over):
    d = {"base": "Guard"}
    d.update(over)
    return d


# =============================================================================== clips
# Each key: (t, ease, pose_spec). Markers: (t, name, arm or None).
ANIMS = []


def anim(name, length, keys, *, fade_in=0.03, fade_out=0.14, priority=3, looped=False,
         upper=False, markers=(), tremble=None, extra=None):
    ANIMS.append(dict(name=name, length=length, keys=keys, fade_in=fade_in, fade_out=fade_out,
                      priority=priority, looped=looped, upper=upper, markers=markers,
                      tremble=tremble, extra=extra or {}))


# ---------------------------------------------------------------- locomotion cycles
# Cycles are normalised to Length 1 and advanced by distance travelled (see Stride below),
# so feet never skate whatever the WalkSpeed is.
anim("Idle", 3.2, [
    (0, None, dict(Root=[0, 0, 0, 0, 0, 0], Neck=[0, 0, 0], RArm=[0, 0, 3], LArm=[0, 0, -3], RLeg=[0, 0, 2], LLeg=[0, 0, -2])),
    (1.6, "SineInOut", dict(Root=[-1, 0, 0, 0, -0.035, 0], Neck=[2, 0, 0], RArm=[3, 0, 5], LArm=[3, 0, -5], RLeg=[0, 0, 2], LLeg=[0, 0, -2])),
    (3.2, "SineInOut", dict(Root=[0, 0, 0, 0, 0, 0], Neck=[0, 0, 0], RArm=[0, 0, 3], LArm=[0, 0, -3], RLeg=[0, 0, 2], LLeg=[0, 0, -2])),
], looped=True, priority=0, fade_in=0.2, fade_out=0.2)

anim("CombatIdle", 0.9, [
    (0, None, "Guard"),
    (0.45, "SineInOut", guard(Root=[-6, -12, 0, 0, -0.2, 0], LArm=ik((-0.15, 0.82, -1.92)), RArm=ik((0.4, 0.98, -1.22)), RLeg=[-9, 8, 8], LLeg=[21, 8, -8])),
    (0.9, "SineInOut", "Guard"),
], looped=True, priority=0, fade_in=0.2, fade_out=0.2)

WALK_A = dict(Root=[-3, -5, 0, 0, -0.07, 0], Neck=[2, 5, 0], RArm=[-22, 0, 4], LArm=[26, 0, -4], RLeg=[28, 0, 3], LLeg=[-24, 0, -3])
WALK_P = dict(Root=[-3, 0, 0, 0, 0.03, 0], Neck=[2, 0, 0], RArm=[2, 0, 4], LArm=[2, 0, -4], RLeg=[0, 0, 3], LLeg=[3, 0, -3])
WALK_B = dict(Root=[-3, 5, 0, 0, -0.07, 0], Neck=[2, -5, 0], RArm=[26, 0, 4], LArm=[-22, 0, -4], RLeg=[-24, 0, 3], LLeg=[28, 0, -3])
WALK_Q = dict(Root=[-3, 0, 0, 0, 0.03, 0], Neck=[2, 0, 0], RArm=[2, 0, 4], LArm=[2, 0, -4], RLeg=[3, 0, 3], LLeg=[0, 0, -3])
anim("Walk", 1, [
    (0, None, WALK_A), (0.25, "SineInOut", WALK_P), (0.5, "SineInOut", WALK_B),
    (0.75, "SineInOut", WALK_Q), (1, "SineInOut", WALK_A),
], looped=True, priority=0, fade_in=0.15, fade_out=0.15,
    markers=[(0.0, "Step", "R"), (0.5, "Step", "L")], extra={"Stride": 5.6})

RUN_A = dict(Root=[-15, -9, 0, 0, -0.2, 0], Neck=[11, 8, 0], RArm=[-50, 8, 8], LArm=[70, -18, -6], RLeg=[50, 0, 4], LLeg=[-48, 0, -4])
RUN_P = dict(Root=[-15, 0, 0, 0, 0.12, 0], Neck=[11, 0, 0], RArm=[8, 0, 8], LArm=[12, 0, -8], RLeg=[6, 0, 4], LLeg=[-14, 0, -4])
RUN_B = dict(Root=[-15, 9, 0, 0, -0.2, 0], Neck=[11, -8, 0], RArm=[70, 18, 6], LArm=[-50, -8, -8], RLeg=[-48, 0, 4], LLeg=[50, 0, -4])
RUN_Q = dict(Root=[-15, 0, 0, 0, 0.12, 0], Neck=[11, 0, 0], RArm=[12, 0, 8], LArm=[8, 0, -8], RLeg=[-14, 0, 4], LLeg=[6, 0, -4])
anim("Run", 1, [
    (0, None, RUN_A), (0.25, "QuadOut", RUN_P), (0.5, "QuadIn", RUN_B),
    (0.75, "QuadOut", RUN_Q), (1, "QuadIn", RUN_A),
], looped=True, priority=0, fade_in=0.15, fade_out=0.15,
    markers=[(0.0, "Step", "R"), (0.5, "Step", "L")], extra={"Stride": 9.2})

anim("Land", 0.34, [
    (0, None, dict(Root=[-8, 0, 0, 0, -0.35, 0], Neck=[-4, 0, 0], RArm=[24, 0, 18], LArm=[24, 0, -18], RLeg=[12, 0, 8], LLeg=[-4, 0, -8])),
    (0.06, "QuadOut", dict(Root=[-12, 0, 0, 0, -0.55, 0], Neck=[-8, 0, 0], RArm=[30, 0, 22], LArm=[30, 0, -22], RLeg=[16, 0, 10], LLeg=[-6, 0, -10])),
    (0.34, "SineInOut", "Neutral"),
], fade_in=0.02, fade_out=0.16, priority=1, upper=False)

anim("Slide", 0.8, [
    (0, None, "Slide"),
    (0.4, "SineInOut", dict(base="Slide", Root=[35, 2, -2, 0, -1.12, 0.3], Neck=[-29, 2, 0], RArm=[84, 28, 10])),
    (0.8, "SineInOut", "Slide"),
], looped=True, priority=4, fade_in=0.09, fade_out=0.16)

# ---------------------------------------------------------------- M1 chain
GUARD_R = ik((0.4, 1.05, -1.28))
GUARD_L = ik((-0.45, 1.05, -1.2))

anim("Jab", 0.42, [
    (0, None, "Guard"),
    (0.05, "SineOut", guard(Root=[-4, -6, 0, 0, -0.1, 0.05], LArm=ik((-0.35, 0.75, -1.6)))),
    (0.11, "QuadIn", guard(Root=[-9, -30, 0, 0, -0.16, -0.3], Neck=[-6, 22, 0], LArm=ik((0.0, 0.95, -3.1)),
                           RArm=GUARD_R, LLeg=[26, 18, -7], RLeg=[-16, 18, 7])),
    (0.16, "Linear", guard(Root=[-9, -31, 0, 0, -0.16, -0.32], Neck=[-6, 23, 0], LArm=ik((0.0, 0.95, -3.15)),
                           RArm=GUARD_R, LLeg=[26, 18, -7], RLeg=[-16, 18, 7])),
    (0.29, "QuadOut", guard(Root=[-6, -16, 0, 0, -0.13, -0.05], LArm=ik((-0.2, 0.9, -2.1)))),
    (0.42, "SineInOut", "Guard"),
], upper=True, markers=[(0.04, "Swing", "L"), (0.11, "Impact", "L"), (0.2, "SwingEnd", "L")])

anim("Cross", 0.44, [
    (0, None, "Guard"),
    (0.05, "SineOut", guard(Root=[-6, -20, 0, 0, -0.14, 0.06], RArm=ik((0.55, 0.9, -1.0)))),
    (0.12, "QuadIn", guard(Root=[-12, 26, 0, 0, -0.18, -0.4], Neck=[-8, -20, 0], RArm=ik((0.0, 0.95, -3.2)),
                           LArm=GUARD_L, RLeg=[-22, -14, 7], LLeg=[22, -14, -7])),
    (0.17, "Linear", guard(Root=[-12, 27, 0, 0, -0.18, -0.42], Neck=[-8, -21, 0], RArm=ik((0.0, 0.95, -3.25)),
                           LArm=GUARD_L, RLeg=[-22, -14, 7], LLeg=[22, -14, -7])),
    (0.31, "QuadOut", guard(Root=[-7, -6, 0, 0, -0.13, 0], RArm=ik((0.45, 1.0, -1.5)))),
    (0.44, "SineInOut", "Guard"),
], upper=True, markers=[(0.05, "Swing", "R"), (0.12, "Impact", "R"), (0.21, "SwingEnd", "R")])

anim("Hook", 0.48, [
    (0, None, "Guard"),
    (0.07, "SineOut", guard(Root=[-6, 12, 4, 0, -0.16, 0.05], Neck=[-6, -6, 0], LArm=ik((-1.9, 0.95, -0.9), roll=-20))),
    (0.14, "QuadIn", guard(Root=[-10, -40, -6, 0, -0.2, -0.2], Neck=[-6, 30, 4], LArm=ik((0.2, 1.0, -2.3), roll=-25),
                           RArm=GUARD_R, LLeg=[22, 24, -8], RLeg=[-12, 24, 8])),
    (0.21, "QuadOut", guard(Root=[-10, -50, -6, 0, -0.2, -0.22], Neck=[-6, 36, 4], LArm=ik((1.2, 1.0, -1.7), roll=-25),
                            RArm=GUARD_R, LLeg=[22, 26, -8], RLeg=[-12, 26, 8])),
    (0.34, "QuadOut", guard(Root=[-7, -20, 0, 0, -0.13, 0], LArm=ik((-0.2, 0.9, -2.0)))),
    (0.48, "SineInOut", "Guard"),
], upper=True, markers=[(0.07, "Swing", "L"), (0.14, "Impact", "L"), (0.24, "SwingEnd", "L")])

anim("Uppercut", 0.62, [
    (0, None, "Guard"),
    (0.09, "SineOut", dict(Root=[-16, -26, -8, 0, -0.45, 0.1], Neck=[-2, 20, 6], RArm=ik((0.9, -0.6, -1.0), roll=15),
                           LArm=ik((-0.35, 0.95, -1.4)), RLeg=[-24, 16, 10], LLeg=[30, 16, -10])),
    (0.19, "QuadIn", dict(Root=[8, 26, 6, 0, 0.15, -0.3], Neck=[16, -10, 0], RArm=ik((0.05, 2.5, -1.5)),
                          LArm=ik((-0.5, 0.8, -1.0)), RLeg=[-10, -14, 6], LLeg=[12, -14, -6])),
    (0.27, "QuadOut", dict(Root=[12, 30, 6, 0, 0.2, -0.34], Neck=[18, -12, 0], RArm=ik((0.1, 2.8, -1.0)),
                           LArm=ik((-0.5, 0.8, -1.0)), RLeg=[-8, -16, 6], LLeg=[10, -16, -6])),
    (0.45, "SineInOut", guard(Root=[-2, 6, 2, 0, -0.06, -0.1], RArm=ik((0.4, 1.4, -1.4)))),
    (0.62, "SineInOut", "Guard"),
], fade_in=0.04, fade_out=0.16, markers=[(0.1, "Swing", "R"), (0.19, "Impact", "R"), (0.32, "SwingEnd", "R")])

# ---------------------------------------------------------------- heavy
anim("Heavy", 1.1, [
    (0, None, "Guard"),
    (0.14, "CubicOut", dict(Root=[6, -50, -6, 0, -0.25, 0.35], Neck=[-4, 40, 4], RArm=ik((1.6, 0.6, 1.0), roll=30),
                            LArm=ik((-0.2, 0.9, -2.0)), RLeg=[-26, 30, 8], LLeg=[26, 30, -8])),
    (0.44, "SineInOut", dict(Root=[8, -58, -8, 0, -0.3, 0.42], Neck=[-4, 46, 4], RArm=ik((1.7, 0.7, 1.3), roll=35),
                             LArm=ik((-0.2, 0.9, -2.0)), RLeg=[-28, 34, 8], LLeg=[28, 34, -8])),
    (0.52, "QuadIn", dict(Root=[-18, 34, 4, 0, -0.3, -0.9], Neck=[-6, -22, 0], RArm=ik((0.0, 0.9, -3.8)),
                          LArm=ik((-0.6, 0.7, -1.1)), RLeg=[-36, -20, 8], LLeg=[34, -20, -8])),
    (0.64, "QuadOut", dict(Root=[-20, 44, 4, 0, -0.32, -1.0], Neck=[-6, -28, 0], RArm=ik((-0.3, 0.85, -3.9)),
                           LArm=ik((-0.6, 0.7, -1.1)), RLeg=[-38, -26, 8], LLeg=[36, -26, -8])),
    (0.9, "SineInOut", guard(Root=[-10, 10, 0, 0, -0.18, -0.4], RArm=ik((0.4, 1.0, -1.8)))),
    (1.1, "SineInOut", "Guard"),
], fade_in=0.05, fade_out=0.2, tremble=(0.14, 0.5, 1.6),
    markers=[(0.02, "Charge", None), (0.46, "Swing", "R"), (0.52, "Impact", "R"), (0.7, "SwingEnd", "R")])

# ---------------------------------------------------------------- defence
anim("BlockHold", 1, [
    (0, None, "Block"),
    (0.5, "SineInOut", dict(base="Block", Root=[-11, -4, 0, 0, -0.23, 0.05])),
    (1, "SineInOut", "Block"),
], looped=True, priority=2, fade_in=0.06, fade_out=0.12, upper=True)

anim("BlockImpact", 0.24, [
    (0, None, "Block"),
    (0.04, "QuadOut", dict(base="Block", Root=[2, -8, 0, 0, -0.16, 0.3], Neck=[-4, 5, 0],
                           RArm=ik((-0.2, 1.3, -1.05), roll=-12), LArm=ik((0.2, 1.5, -1.0), roll=12))),
    (0.24, "SineInOut", "Block"),
], priority=4, fade_in=0.01, fade_out=0.08, upper=True)

anim("ParryDeflect", 0.4, [
    (0, None, "Block"),
    (0.05, "QuadOut", dict(Root=[-4, 18, 0, 0, -0.14, -0.1], Neck=[-6, -10, 0], RArm=ik((1.9, 1.6, -0.9), roll=25),
                           LArm=ik((-0.3, 0.8, -1.5)), RLeg=[-12, -6, 8], LLeg=[18, -6, -8])),
    (0.13, "SineOut", dict(Root=[-4, 20, 0, 0, -0.14, -0.12], Neck=[-6, -11, 0], RArm=ik((2.1, 1.5, -0.6), roll=30),
                           LArm=ik((-0.3, 0.8, -1.5)), RLeg=[-12, -6, 8], LLeg=[18, -6, -8])),
    (0.4, "SineInOut", "Guard"),
], priority=4, fade_in=0.02, fade_out=0.12, upper=True, markers=[(0.02, "Swing", "R"), (0.16, "SwingEnd", "R")])

# ---------------------------------------------------------------- getting hit
anim("HitA", 0.45, [
    (0, None, "Guard"),
    (0.04, "QuadOut", dict(Root=[12, 12, -4, 0, -0.1, 0.25], Neck=[16, 16, -8], RArm=[60, 10, 20], LArm=[70, -6, -12], RLeg=[-12, 4, 8], LLeg=[16, 4, -8])),
    (0.2, "SineOut", dict(Root=[6, 6, -2, 0, -0.12, 0.2], Neck=[6, 8, -4], RArm=[82, 24, 10], LArm=[84, -10, -6], RLeg=[-10, 6, 8], LLeg=[18, 6, -8])),
    (0.45, "SineInOut", "Guard"),
], priority=5, fade_in=0.02)

anim("HitB", 0.45, [
    (0, None, "Guard"),
    (0.04, "QuadOut", dict(Root=[12, -22, 4, 0, -0.1, 0.25], Neck=[14, -14, 8], RArm=[74, 10, 12], LArm=[58, -12, -20], RLeg=[-12, 12, 8], LLeg=[16, 12, -8])),
    (0.2, "SineOut", dict(Root=[6, -18, 2, 0, -0.12, 0.2], Neck=[6, 0, 4], RArm=[90, 26, 6], LArm=[80, -14, -10], RLeg=[-10, 10, 8], LLeg=[18, 10, -8])),
    (0.45, "SineInOut", "Guard"),
], priority=5, fade_in=0.02)

anim("HitBody", 0.5, [
    (0, None, "Guard"),
    (0.05, "QuadOut", dict(Root=[-18, -8, 0, 0, -0.32, 0.25], Neck=[-14, 6, 0], RArm=[40, 40, 0], LArm=[44, -40, 0], RLeg=[-16, 6, 8], LLeg=[18, 6, -8])),
    (0.24, "SineOut", dict(Root=[-12, -10, 0, 0, -0.24, 0.2], Neck=[-10, 8, 0], RArm=[70, 40, 0], LArm=[72, -30, 0], RLeg=[-12, 8, 8], LLeg=[20, 8, -8])),
    (0.5, "SineInOut", "Guard"),
], priority=5, fade_in=0.02)

anim("Knockback", 1.1, [
    (0, None, "Guard"),
    (0.06, "QuadOut", dict(Root=[30, 8, 0, 0, 0, 0.4], Neck=[-20, 0, 0], RArm=[120, -10, 30], LArm=[120, 10, -30], RLeg=[40, 0, 8], LLeg=[25, 0, -8])),
    (0.3, "SineInOut", dict(Root=[36, -6, 6, 0, 0, 0.4], Neck=[-14, 6, 4], RArm=[150, -20, 40], LArm=[100, 20, -50], RLeg=[30, 0, 12], LLeg=[46, 0, -10])),
    (0.55, "SineInOut", dict(Root=[28, 6, -6, 0, 0, 0.3], Neck=[-10, -6, -4], RArm=[110, -10, 50], LArm=[140, 10, -40], RLeg=[44, 0, 10], LLeg=[26, 0, -12])),
    (0.78, "QuadOut", dict(Root=[-14, -4, 0, 0, -0.55, 0.1], Neck=[-10, 4, 0], RArm=[50, 10, 30], LArm=[56, -10, -30], RLeg=[-18, 6, 14], LLeg=[30, 6, -14])),
    (1.1, "SineInOut", "Guard"),
], priority=6, fade_in=0.03, fade_out=0.2, markers=[(0.78, "Land", None)])

anim("Parried", 1.32, [
    (0, None, "Guard"),
    (0.08, "QuadOut", dict(Root=[22, 10, 8, 0, -0.1, 0.6], Neck=[24, 0, 0], RArm=[150, -20, 40], LArm=[120, 30, -40], RLeg=[18, 0, 8], LLeg=[-20, 0, -8])),
    (0.3, "SineOut", dict(Root=[14, 6, 4, 0, -0.14, 0.7], Neck=[10, 0, 0], RArm=[110, -10, 30], LArm=[90, 20, -30], RLeg=[10, 0, 8], LLeg=[-10, 0, -8])),
    (0.6, "SineInOut", dict(Root=[8, -4, -6, 0, -0.2, 0.6], Neck=[-10, 0, 10], RArm=[50, 0, 20], LArm=[40, 0, -20], RLeg=[-6, 0, 8], LLeg=[10, 0, -8])),
    (0.9, "SineInOut", dict(Root=[6, 4, 5, 0, -0.2, 0.55], Neck=[-8, 0, -8], RArm=[46, 0, 22], LArm=[44, 0, -18], RLeg=[-6, 0, 8], LLeg=[10, 0, -8])),
    (1.15, "SineInOut", guard(Root=[-2, -10, 0, 0, -0.14, 0.2], RArm=[80, 30, 6], LArm=[80, -14, -4])),
    (1.32, "SineInOut", "Guard"),
], priority=6, fade_in=0.03, fade_out=0.18)

anim("GuardBroken", 1.55, [
    (0, None, "Block"),
    (0.06, "QuadOut", dict(Root=[16, 0, 0, 0, -0.1, 0.4], Neck=[16, 0, 0], RArm=[70, -10, 60], LArm=[70, 10, -60], RLeg=[10, 0, 10], LLeg=[-12, 0, -10])),
    (0.35, "SineOut", dict(Root=[-24, 0, 0, 0, -0.4, 0.3], Neck=[-20, 0, 0], RArm=[10, 0, 8], LArm=[10, 0, -8], RLeg=[-12, 0, 10], LLeg=[16, 0, -10])),
    (0.7, "SineInOut", dict(Root=[-22, 4, 6, 0, -0.38, 0.3], Neck=[-16, 6, 10], RArm=[8, 0, 10], LArm=[14, 0, -6], RLeg=[-12, 0, 10], LLeg=[16, 0, -10])),
    (1.05, "SineInOut", dict(Root=[-22, -4, -6, 0, -0.38, 0.3], Neck=[-16, -6, -10], RArm=[14, 0, 6], LArm=[8, 0, -10], RLeg=[-12, 0, 10], LLeg=[16, 0, -10])),
    (1.55, "SineInOut", "Guard"),
], priority=6, fade_in=0.02, fade_out=0.2)

# ---------------------------------------------------------------- dodges
anim("DodgeForward", 0.38, [
    (0, None, "Guard"),
    (0.05, "QuadOut", dict(Root=[-28, 0, 0, 0, -0.3, 0], Neck=[18, 0, 0], RArm=[-44, 0, 12], LArm=[-44, 0, -12], RLeg=[-36, 0, 4], LLeg=[46, 0, -4])),
    (0.24, "Linear", dict(Root=[-25, 0, 0, 0, -0.26, 0], Neck=[16, 0, 0], RArm=[-40, 0, 14], LArm=[-40, 0, -14], RLeg=[-32, 0, 4], LLeg=[42, 0, -4])),
    (0.38, "SineInOut", "Guard"),
], priority=4, fade_in=0.03, fade_out=0.12)

anim("DodgeBack", 0.38, [
    (0, None, "Guard"),
    (0.05, "QuadOut", guard(Root=[16, -8, 0, 0, -0.22, 0], Neck=[-12, 6, 0], RLeg=[-14, 6, 6], LLeg=[34, 6, -6])),
    (0.24, "Linear", guard(Root=[14, -8, 0, 0, -0.2, 0], Neck=[-10, 6, 0], RLeg=[-10, 6, 6], LLeg=[30, 6, -6])),
    (0.38, "SineInOut", "Guard"),
], priority=4, fade_in=0.03, fade_out=0.12)

anim("DodgeLeft", 0.38, [
    (0, None, "Guard"),
    (0.05, "QuadOut", guard(Root=[-8, -6, 18, 0, -0.24, 0], Neck=[-6, 6, -14], RLeg=[-4, 6, 28], LLeg=[10, 6, -2])),
    (0.24, "Linear", guard(Root=[-8, -6, 16, 0, -0.22, 0], Neck=[-6, 6, -12], RLeg=[-4, 6, 24], LLeg=[10, 6, -2])),
    (0.38, "SineInOut", "Guard"),
], priority=4, fade_in=0.03, fade_out=0.12)

anim("DodgeRight", 0.38, [
    (0, None, "Guard"),
    (0.05, "QuadOut", guard(Root=[-8, -20, -18, 0, -0.24, 0], Neck=[-6, 18, 14], RLeg=[-4, 14, 2], LLeg=[10, 14, -28])),
    (0.24, "Linear", guard(Root=[-8, -20, -16, 0, -0.22, 0], Neck=[-6, 18, 12], RLeg=[-4, 14, 2], LLeg=[10, 14, -24])),
    (0.38, "SineInOut", "Guard"),
], priority=4, fade_in=0.03, fade_out=0.12)


# =============================================================================== emit
def fmt_num(v):
    v = float(v)
    if abs(v - round(v)) < 1e-9:
        return str(int(round(v)))
    return ("%.3f" % v).rstrip("0").rstrip(".")


def fmt_joint(vals):
    vals = list(vals)
    while len(vals) > 3 and abs(float(vals[-1])) < 1e-9:
        vals.pop()
    return "{ " + ", ".join(fmt_num(v) for v in vals) + " }"


def fmt_pose(base, over, indent):
    pad = "\t" * indent
    lines = ["{"]
    if base:
        lines.append(pad + '\tbase = "%s",' % base)
    for j in JOINTS:
        if j in over:
            lines.append(pad + "\t%s = %s," % (j, fmt_joint(over[j])))
    lines.append(pad + "}")
    return "\n".join(lines)


HEADER = """-- GENERATED by tools/build_animations.py (fist positions are solved with IK there).
-- You can still hand-edit the numbers here; just remember regenerating overwrites them.
--
-- R6 keyframe animation data, played back by ProceduralAnimator. The animator samples these
-- every rendered frame, so motion stays smooth at any framerate.
--
-- Joints: Root (torso, relative to HumanoidRootPart), Neck, RArm, LArm, RLeg, LLeg.
-- Each joint is { pitch, yaw, roll, x, y, z }: degrees, then studs. Values you leave off
-- count as 0. Everything is in the parent part's space: X = right, Y = up, Z = back.
--   Arms and legs: +pitch swings forward, +yaw turns toward the character's left,
--                  +roll swings toward the character's right.
--   Root: +pitch leans back, +yaw turns left, +roll leans left; x/y/z moves the torso.
--   Neck: +pitch looks up, +yaw looks left, +roll tilts left.
--
-- A keyframe pose is either the name of an entry in Poses, or a table with `base = "PoseName"`
-- plus the joints it changes. `ease` is a Roblox EasingStyle name followed by In/Out/InOut and
-- shapes the motion INTO that keyframe. Joint values are interpolated per component, so
-- spins past 180 degrees work. Markers fire named events (Swing, Impact, Step...) for VFX/SFX.
"""


def emit(poses, path=OUT):
    out = [HEADER, "local Data = {}", "", "Data.Poses = {"]
    for name, _ in POSE_SPECS:
        out.append("\t%s = %s," % (name, fmt_pose(None, poses[name], 1)))
    out.append("}")
    out.append("")
    out.append("Data.Animations = {")
    for a in ANIMS:
        out.append("\t%s = {" % a["name"])
        out.append("\t\tLength = %s," % fmt_num(a["length"]))
        if a["looped"]:
            out.append("\t\tLooped = true,")
        out.append("\t\tFadeIn = %s," % fmt_num(a["fade_in"]))
        out.append("\t\tFadeOut = %s," % fmt_num(a["fade_out"]))
        out.append("\t\tPriority = %d," % a["priority"])
        if a["upper"]:
            out.append("\t\tUpperBodyWhileMoving = true,")
        for k, v in a["extra"].items():
            out.append("\t\t%s = %s," % (k, fmt_num(v)))
        if a["tremble"]:
            f, t, amt = a["tremble"]
            out.append("\t\tTremble = { from = %s, to = %s, amount = %s }," % (fmt_num(f), fmt_num(t), fmt_num(amt)))
        out.append("\t\tKeyframes = {")
        for t, ease, spec in a["keys"]:
            if isinstance(spec, str):
                pose_txt = '"%s"' % spec
            else:
                base, over = resolve(spec, poses)
                pose_txt = fmt_pose(base, over, 4)
            ease_txt = (' ease = "%s",' % ease) if ease else ""
            out.append("\t\t\t{ t = %s,%s pose = %s }," % (fmt_num(t), ease_txt, pose_txt))
        out.append("\t\t},")
        if a["markers"]:
            out.append("\t\tMarkers = {")
            for t, name, arm in a["markers"]:
                arm_txt = (', arm = "%s"' % arm) if arm else ""
                out.append('\t\t\t{ t = %s, name = "%s"%s },' % (fmt_num(t), name, arm_txt))
            out.append("\t\t},")
        out.append("\t},")
    out.append("}")
    out.append("")
    out.append("return Data")
    out.append("")
    with open(path, "w") as f:
        f.write("\n".join(out))


if __name__ == "__main__":
    poses = build_poses()
    emit(poses)
    print("wrote", os.path.relpath(OUT))
