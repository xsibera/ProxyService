"""Shared machinery for the two-handed weapon sets (GreatswordCombo, KatanaCombo): the sword held in
the right fist on a "Handle" Motor6D, the left fist locked onto its grip, swings flown along exact
circles in world space, smooth spline paths, and a cap on how fast the arms may turn and roll.

Spaces are the same as the one-handed set (../SwordCombo/generate_sword.py): Torso space is +x right,
+y up, -z forward; "world" is the HumanoidRootPart's space (HRP at the origin facing -z); in Handle
space the right fist is at the origin, the blade runs along -z and its edges along +-y.
"""

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "SwordCombo"))
from animkit import FPS, Clip, _slerp_channels, curve, from_transform, smoothstep, to_transform  # noqa: E402
from generate_sword import GRIP, MOTORS, aim, cf, inv, joint_cf  # noqa: E402


def handle_cf(rarm_ch, handle_ch):
    """The sword's Handle CFrame in Torso space for given Right Arm and Handle channels."""
    pos, rot = to_transform("Handle", handle_ch)
    return joint_cf("RArm", rarm_ch) @ GRIP @ cf(pos, rot)


def grab_channels(handle):
    """Right Arm channels putting the fist exactly on a Handle CFrame (Torso space), wrist straight."""
    c0, c1 = MOTORS["RArm"]
    t = inv(c0) @ handle @ inv(GRIP) @ c1
    return np.array(from_transform("RArm", t[:3, 3], t[:3, :3]))


# --------------------------------------------------------------------------- the left hand on the grip
L_SHOULDER = np.array([-1.5, 1.0, 0.0])  # top of the left arm at rest, Torso space
FIST = np.array([0.0, -0.95, 0.0])  # the fist in arm space (where GRIP sits on the right arm)


def _rot_between(a, b):
    a, b = a / np.linalg.norm(a), b / np.linalg.norm(b)
    axis = np.cross(a, b)
    s, c = np.linalg.norm(axis), float(a @ b)
    if s < 1e-9:
        return np.eye(3) if c > 0 else np.diag([1.0, -1.0, -1.0])
    k = axis / s
    kx = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + s * kx + (1 - c) * kx @ kx


def left_on(point):
    """Left Arm channels putting the left fist exactly on a point (Torso space), the arm pointing
    from the shoulder at it and sliding in or out of the socket as needed (as the reference does)."""
    d = np.asarray(point, float) - L_SHOULDER
    rot = _rot_between(np.array([0.0, -1.0, 0.0]), d)
    arm_cf = cf(point - rot @ FIST, rot)
    c0, c1 = MOTORS["LArm"]
    m = inv(c0) @ arm_cf @ c1
    return np.array(from_transform("LArm", m[:3, 3], m[:3, :3]))


def grip_pass(c, baked, left_grip, weight=None):
    """Put the left fist on the grip, left_grip studs below the right, every frame. `weight` (per frame,
    0..1) blends from the clip's own left-arm keys (0, free) to the grip (1)."""
    n = len(baked["Root"])
    w = np.ones(n) if weight is None else np.asarray(weight, float)
    prev = None
    for f in range(n):
        h = handle_cf(baked["RArm"][f], baked["Handle"][f])
        on = left_on((h @ np.array([0.0, 0.0, left_grip, 1.0]))[:3])
        if w[f] >= 1:
            ch = on
        elif w[f] <= 0:
            ch = baked["LArm"][f]
        else:
            ch = _slerp_channels(np.asarray(baked["LArm"][f], float), on, float(w[f]), prev)
        baked["LArm"][f] = ch
        prev = ch
    return baked


MAX_SWING = 2200.0  # deg/s an arm may turn; the reference weapon M1s peak at 2,300-2,800
MAX_TWIST = 1300.0  # deg/s an arm may roll about itself; they peak at 1,000-1,400


def _turn(axis, rad):
    k = unit(axis)
    kx = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + math.sin(rad) * kx + (1 - math.cos(rad)) * kx @ kx


def _limit(seq, step, cap, spread):
    """Diffuse the frames either side of any step faster than cap into their neighbours, until none
    is. The first and last frames are kept."""
    seq = np.array(seq, float)
    for _ in range(400):
        fast = [i for i in range(1, len(seq)) if step(seq[i - 1], seq[i]) * FPS > cap]
        if not fast:
            break
        new = seq.copy()
        for i in {k for f in fast for k in (f - 1, f) if 0 < k < len(seq) - 1}:
            new[i] = spread(0.25 * seq[i - 1] + 0.5 * seq[i] + 0.25 * seq[i + 1])
        seq = new
    return seq


def tame_arm(rows, joint):
    """Cap an arm's swing (its direction turning) at MAX_SWING and its twist (rolling about itself)
    at MAX_TWIST without moving the fist: the solvers point the arm from the shoulder at the fist,
    so a fist passing close to the shoulder whips the arm round, and a fist going overhead spins it.
    The arm slides in its socket to keep the fist where it was."""
    c0, c1 = MOTORS[joint]
    cfs = [joint_cf(joint, r) for r in rows]
    fist = [(m @ np.append(FIST, 1.0))[:3] for m in cfs]
    d = _limit([-m[:3, 1] for m in cfs], lambda a, b: math.acos(np.clip(unit(a) @ unit(b), -1, 1)),
               math.radians(MAX_SWING), unit)
    # roll: carry frame 0's sideways axis along the (new) arm direction without twisting, measure the
    # keyed roll against it, unwrap, cap its speed, and put it back
    carried = [cfs[0][:3, 0]]
    for i in range(1, len(d)):
        ax = np.cross(d[i - 1], d[i])
        s = np.linalg.norm(ax)
        x = _turn(ax, math.atan2(s, float(d[i - 1] @ d[i]))) @ carried[-1] if s > 1e-9 else carried[-1]
        carried.append(unit(x - d[i] * float(x @ d[i])))
    roll = []
    for i in range(len(d)):
        x = cfs[i][:3, 0]
        x = unit(x - d[i] * float(x @ d[i]))
        roll.append(math.atan2(float(np.cross(carried[i], x) @ d[i]), float(carried[i] @ x)))
    roll = _limit(np.unwrap(roll)[:, None], lambda a, b: abs(float(b[0] - a[0])), math.radians(MAX_TWIST),
                  lambda v: v)[:, 0]
    out = []
    for i in range(len(d)):
        x = _turn(d[i], roll[i]) @ carried[i]
        y = -d[i]
        rot = np.column_stack([x, y, np.cross(x, y)])
        m = inv(c0) @ cf(fist[i] - rot @ FIST, rot) @ c1
        out.append(np.array(from_transform(joint, m[:3, 3], m[:3, :3])))
    return np.array(out)


# --------------------------------------------------------------------------- arms out of the torso
TORSO_HALF = np.array([1.0, 1.0, 0.5])
# points through an R6 arm (1 x 2 x 1), in arm space, to measure how much of it is inside the torso
_ARM_GRID = np.array([[x, y, z, 1.0] for x in np.linspace(-0.45, 0.45, 4) for y in np.linspace(-0.95, 0.95, 9)
                      for z in np.linspace(-0.45, 0.45, 4)])
CLEAR_OK = 0.06  # share of an arm that may sit inside the torso
CLEAR_MAX = 1.6  # studs the upper end of an arm may swing forward to get out


def inside_torso(arm_cf):
    """Share of an arm (Torso-space CFrame) inside the torso box."""
    pts = (arm_cf @ _ARM_GRID.T).T[:, :3]
    return float(np.mean(np.all(np.abs(pts) < TORSO_HALF, axis=1)))


def _arm_toward(fist, top, rot):
    """The arm turned about its fist (which stays put) so its upper end points at `top`, rolled as
    little as possible from `rot`."""
    d = unit(np.asarray(top, float) - fist)
    turn = _rot_between(rot[:, 1], d)
    r = turn @ rot
    return cf(fist - r @ FIST, r)


def clear_torso(rows, joint):
    """Keep an arm out of the torso without moving its fist. An arm aimed from its shoulder at a fist
    in front of the body's centre (both hands on one grip) cuts through the chest; here its upper end
    swings forward, away from the shoulder, just far enough to clear it (sliding in the socket, as
    the reference arms do), eased in and out over a few frames so it never pops."""
    cfs = [joint_cf(joint, r) for r in rows]
    n = len(cfs)
    need = np.zeros(n)
    for f, m in enumerate(cfs):
        share = inside_torso(m)
        if share <= CLEAR_OK:
            continue
        fist = (m @ np.append(FIST, 1.0))[:3]
        top = (m @ np.array([0.0, 1.0, 0.0, 1.0]))[:3]
        best = (share, 0.0)
        for k in np.arange(0.1, CLEAR_MAX + 1e-9, 0.1):
            share = inside_torso(_arm_toward(fist, top + np.array([0.0, 0.0, -k]), m[:3, :3]))
            if share < best[0] - 1e-9:
                best = (share, float(k))
            if share <= CLEAR_OK:
                break
        need[f] = best[1]
    if not need.any():
        return np.asarray(rows, float)
    # widen, then ease: never less than a frame needs, and no sudden swings
    wide = np.array([need[max(0, f - 5):f + 6].max() for f in range(n)])
    kernel = np.exp(-0.5 * (np.arange(-12, 13) / 4.0) ** 2)
    kernel /= kernel.sum()
    padded = np.concatenate([np.full(12, wide[0]), wide, np.full(12, wide[-1])])
    eased = np.maximum(np.convolve(padded, kernel, mode="valid"), need)
    c0, c1 = MOTORS[joint]
    out = []
    for f, m in enumerate(cfs):
        if eased[f] <= 1e-6:
            out.append(np.asarray(rows[f], float))
            continue
        fist = (m @ np.append(FIST, 1.0))[:3]
        top = (m @ np.array([0.0, 1.0, 0.0, 1.0]))[:3] + np.array([0.0, 0.0, -eased[f]])
        t = inv(c0) @ _arm_toward(fist, top, m[:3, :3]) @ c1
        out.append(np.array(from_transform(joint, t[:3, 3], t[:3, :3])))
    return np.array(out)


def tame(baked):
    """tame_arm both arms and keep them out of the torso (clear_torso), turning the wrist so the
    sword stays exactly where it was."""
    swords = [handle_cf(a, h) for a, h in zip(baked["RArm"], baked["Handle"], strict=True)]
    for joint in ("RArm", "LArm"):
        # the two pull against each other (the cap can blend a fast swing back through the chest, and
        # clearing it can speed the arm up again), so alternate until both hold
        rows = clear_torso(baked[joint], joint)
        for _ in range(4):
            rows = clear_torso(tame_arm(rows, joint), joint)
        baked[joint] = tame_arm(rows, joint)
    for f, sword in enumerate(swords):
        t = inv(GRIP) @ inv(joint_cf("RArm", baked["RArm"][f])) @ sword
        baked["Handle"][f] = np.array(from_transform("Handle", t[:3, 3], t[:3, :3]))
    return baked


def ramp(n, f0, f1, up=True):
    """Per-frame weights: 0 before f0, smoothstep up to 1 at f1 (or down, if up is False)."""
    w = np.array([smoothstep((f - f0) / max(1, f1 - f0)) for f in range(n)])
    return w if up else 1 - w


# --------------------------------------------------------------------------- sword paths
def root_path(c):
    """The Root track as keyed (unsmoothed): world-space sword paths are placed against it."""
    path = Clip("root", c.frames, None, "RArm")
    path.keys["Root"] = c.keys["Root"]
    path.neck_auto = path.smooth = False
    return path.bake()["Root"]


def fly(c, roots, f, hand, blade, edge, k="linear"):
    """Key the Right Arm and the wrist (Handle) at frame f from a world (root space) fist position,
    blade direction and edge direction."""
    t = joint_cf("Root", roots[f])
    rot = t[:3, :3].T
    arm_ch, handle_ch = aim((inv(t) @ np.append(hand, 1))[:3], rot @ blade, edge=rot @ edge)
    c.key("RArm", f, arm_ch, k)
    c.key("Handle", f, handle_ch, k)


def spline(times, points, v0, v1):
    """Clamped cubic spline (C2) through points at times (frames), with velocities v0 and v1 (per
    frame) at the ends. Returns a function of the frame."""
    t = np.asarray(times, float)
    p = np.array([np.asarray(q, float) for q in points])
    n, h = len(t), np.diff(t)
    a, b = np.zeros((n, n)), np.zeros((n, p.shape[1]))
    a[0, 0] = a[-1, -1] = 1.0
    b[0], b[-1] = v0, v1
    for i in range(1, n - 1):
        a[i, i - 1], a[i, i], a[i, i + 1] = 1 / h[i - 1], 2 / h[i - 1] + 2 / h[i], 1 / h[i]
        b[i] = 3 * ((p[i] - p[i - 1]) / h[i - 1] ** 2 + (p[i + 1] - p[i]) / h[i] ** 2)
    v = np.linalg.solve(a, b)

    def at(f):
        i = int(np.clip(np.searchsorted(t, f, side="right") - 1, 0, n - 2))
        u = (f - t[i]) / h[i]
        return ((2 * u**3 - 3 * u**2 + 1) * p[i] + (u**3 - 2 * u**2 + u) * h[i] * v[i]
                + (-2 * u**3 + 3 * u**2) * p[i + 1] + (u**3 - u**2) * h[i] * v[i + 1])

    return at


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def slerp(a, b, t):
    a, b = unit(a), unit(b)
    th = math.acos(max(-1.0, min(1.0, float(a @ b))))
    if th < 1e-6:
        return a
    if abs(th - math.pi) < 1e-4:  # opposite: go round any perpendicular
        p = unit(np.cross(a, [0.0, 1.0, 0.0] if abs(a[1]) < 0.9 else [1.0, 0.0, 0.0]))
        return unit(a * math.cos(math.pi * t) + p * math.sin(math.pi * t))
    return (math.sin((1 - t) * th) * a + math.sin(t * th) * b) / math.sin(th)


def about(v, axis, deg):
    """Rotate v about a unit axis by deg."""
    a = math.radians(deg)
    k = unit(axis)
    return v * math.cos(a) + np.cross(k, v) * math.sin(a) + k * float(k @ v) * (1 - math.cos(a))


class Arc:
    """A circle through three points: the hands travel it from p0 through p1 to p2."""

    def __init__(self, p0, p1, p2):
        p0, p1, p2 = (np.asarray(p, float) for p in (p0, p1, p2))
        a, b = p1 - p0, p2 - p0
        axb = np.cross(a, b)
        self.centre = p0 + np.cross((a @ a) * b - (b @ b) * a, axb) / (2 * (axb @ axb))
        self.r = float(np.linalg.norm(p0 - self.centre))
        self.u = unit(p0 - self.centre)
        self.n = unit(axb)
        self.v = np.cross(self.n, self.u)

        def ang(p):
            d = p - self.centre
            return math.atan2(float(d @ self.v), float(d @ self.u)) % (2 * math.pi)

        self.mid, self.end = ang(p1), ang(p2)
        if self.mid > self.end:  # go the way that passes through p1
            self.n, self.v = -self.n, -self.v
            self.mid, self.end = ang(p1), ang(p2)

    def point(self, th):
        return self.centre + self.r * (math.cos(th) * self.u + math.sin(th) * self.v)

    def radial(self, th):
        return math.cos(th) * self.u + math.sin(th) * self.v

    def tangent(self, th):
        return -math.sin(th) * self.u + math.cos(th) * self.v


def m1_path(c, guard, pre, arc, post, lag=(20.0, -4.0), blade_end=None, hit_after=1):
    """Fly the sword through an M1. guard = (hand, blade, edge) at frame 0; pre = [(frame, hand,
    blade, curve)] poses into the wind-up; arc = (f0, f1, p_mid, p_end, curve): the swing from the
    last pre pose along the circle through p_mid to p_end, the blade pointing out from the circle's
    centre, trailing it by lag[0] deg at the start and leading by -lag[1] at the end (the whip), and
    turning toward blade_end over the last third if one is given; post = [(frame, hand, blade,
    curve)] settling poses. The edge leads into the cut. Sets the Hit marker as the hands pass
    p_mid. Returns the per-frame (hand, blade, edge)."""
    roots = root_path(c)
    f0, f1, p_mid, p_end, arc_curve = arc
    start_hand, start_blade = pre[-1][1], pre[-1][2]
    circle = Arc(start_hand, p_mid, p_end)
    cut_edge0 = circle.tangent(0.0)
    out = {}
    # into the wind-up: hands lerp, blade slerps, the edge turns from the guard toward the cut
    prev_f, prev_hand, prev_blade = 0, np.asarray(guard[0], float), unit(guard[1])
    edge0 = unit(guard[2])
    out[0] = (prev_hand, prev_blade, edge0)
    for f_key, hand, blade, k in pre:
        for f in range(prev_f + 1, f_key + 1):
            u = curve(k, (f - prev_f) / (f_key - prev_f))
            out[f] = (prev_hand + (np.asarray(hand) - prev_hand) * u, slerp(prev_blade, blade, u),
                      slerp(edge0, cut_edge0, f / f0))
        prev_f, prev_hand, prev_blade = f_key, np.asarray(hand, float), unit(blade)
    # the swing
    hit = None
    for f in range(f0 + 1, f1 + 1):
        u = curve(arc_curve, (f - f0) / (f1 - f0))
        th = circle.end * u
        lag_deg = lag[0] + (lag[1] - lag[0]) * u
        blade = about(circle.radial(th), circle.n, -lag_deg)
        blade = slerp(start_blade, blade, smoothstep(u / 0.25))  # leaves the wind-up smoothly
        if blade_end is not None and u > 0.66:
            blade = slerp(blade, blade_end, smoothstep((u - 0.66) / 0.34))
        out[f] = (circle.point(th), blade, circle.tangent(th))
        if hit is None and th >= circle.mid:
            hit = f + hit_after
    # settling
    prev_f, prev_hand, prev_blade, end_edge = f1, out[f1][0], out[f1][1], out[f1][2]
    for f_key, hand, blade, k in post:
        for f in range(prev_f + 1, f_key + 1):
            u = curve(k, (f - prev_f) / (f_key - prev_f))
            out[f] = (prev_hand + (np.asarray(hand) - prev_hand) * u, slerp(prev_blade, blade, u), end_edge)
        prev_f, prev_hand, prev_blade = f_key, np.asarray(hand, float), unit(blade)
    for f in range(c.frames + 1):
        hand, blade, edge = out[f]
        fly(c, roots, f, hand, blade, edge)
    c.hit = c.peak = hit
    c.markers = {hit: ["Hit"]}
    return out


def on_swing_line(hand, p_mid, p_end, lag, back=0.0):
    """The blade direction that starts a swing (hands at `hand`, through p_mid to p_end) already on
    its circle, trailing by `lag` deg, wound a further `back` deg: a wind-up pose with nothing left
    to turn when the swing starts."""
    circle = Arc(hand, p_mid, p_end)
    return about(circle.radial(0.0), circle.n, -(lag + back))


def tip_speeds(c, baked, tip):
    """Blade-tip speed (studs/s, root space) per frame for a tip `tip` studs out from the fist."""
    tips = []
    for f in range(len(baked["Root"])):
        h = joint_cf("Root", baked["Root"][f]) @ handle_cf(baked["RArm"][f], baked["Handle"][f])
        tips.append((h @ np.array([0, 0, -tip, 1]))[:3])
    tips = np.array(tips)
    v = np.zeros(len(tips))
    v[1:] = np.linalg.norm(np.diff(tips, axis=0), axis=1) * FPS
    return v
