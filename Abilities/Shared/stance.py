"""Legs the way the reference ability animations do them (ANIMSFORCLAUDE.rbxm, the "abilities" rig's
ice downslam), shared by the kits whose attacks key the legs (Killua, Leorio):

  - the feet are planted on the floor at hip width (a touch outside it), staggered front and back;
  - the torso turns and sinks above them, and the body gets low by sliding the legs up into the
    hips (the reference's bent knee);
  - the lead leg (the side of the body facing forward) stays nearly upright; the other is the one
    that stretches out behind on a big hit.

check_legs holds every baked frame to that: the feet never come within MIN_FEET_GAP of each other
side to side (no crossing), and with both feet down one leg is always within MAX_SUPPORT_TILT of
upright (no splayed A-frame stances).

Two ways to key them:
  - set_stance / hold key the legs like any other joint (aimed from the hip at the foot, slid up
    into it), and the bake blends between the keys (Killua);
  - plant / keep record where the feet are, and solve_feet then places the legs on every baked
    frame (Leorio). The feet stay exactly where they're put however far the torso whips round
    between keys, and a support leg stands upright the way the reference's does: at the ice
    downslam's slam its lead leg stands at 5 deg, slid 1.3 studs up into the pitched, rolled torso,
    while the back leg is aimed from the hip and stretched out at 65 deg (`lean`: 0 upright,
    1 aimed from the hip).

Built on the Jajanken solvers (Abilities/Jajanken/anims.py): J here is that module.
"""

import importlib.util
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))


def _jajanken_solvers():
    """Jajanken's anims.py, loaded once under its own name (every kit's file is anims.py)."""
    if "jajanken_anims" in sys.modules:
        return sys.modules["jajanken_anims"]
    spec = importlib.util.spec_from_file_location("jajanken_anims", os.path.join(HERE, "..", "Jajanken", "anims.py"))
    module = importlib.util.module_from_spec(spec)
    sys.modules["jajanken_anims"] = module
    spec.loader.exec_module(module)
    return module


J = _jajanken_solvers()
GROUND = J.GROUND
MIN_FEET_GAP = 0.9  # studs: the feet never come closer than this side to side (the reference: 0.96+)
MAX_SUPPORT_TILT = 25  # deg: with both feet down, one leg is always this close to upright (reference: 24)


def hips(root):
    """Where each leg hangs from (the top centre of the leg), in the HumanoidRootPart's space."""
    t = J.torso_of(root)
    return {j: (t @ np.array([x, -1.0, 0.0, 1.0]))[:3] for j, x in (("LLeg", -0.5), ("RLeg", 0.5))}


def set_stance(c, f, root, back=0.8, front=-0.15, lead=None, out=0.15, k="ease"):
    """Key the legs the way the reference ability animations do (ice downslam): the lead foot (on
    the side of the body that faces forward: the left when the torso is turned right) just ahead of
    its own hip, so that leg stays almost upright, and the other foot `back` studs behind its hip -
    a short stagger while winding up, stretched out long on the big hit. Both sit at hip width, a
    touch outside it, and the body gets low by sliding the legs up into the hips (the reference's
    bent knee). Returns the floor spots, so later keys can keep the feet planted there (hold)."""
    yaw = (root[1] + 180) % 360 - 180
    lead = lead or ("LLeg" if yaw <= 0 else "RLeg")
    h = hips(root)
    spots = {}
    for joint in ("LLeg", "RLeg"):
        side = -1 if joint == "LLeg" else 1
        spots[joint] = (h[joint][0] + side * out, h[joint][2] + (front if joint == lead else back))
    hold(c, f, root, spots, k)
    return spots


def hold(c, f, root, spots, k="ease"):
    """Key the legs with the feet still planted on `spots` (the torso turns and sinks above them)."""
    J.feet_at(c, f, root, spots["LLeg"], spots["RLeg"], k)


def feet_gap(baked, f):
    """Side-to-side distance between the feet at frame f, in the torso's frame (right minus left)."""
    torso = J.torso_of(baked["Root"][f])
    inv = np.linalg.inv(torso)
    xs = {}
    for joint in ("LLeg", "RLeg"):
        foot = J.foot(joint, baked["Root"][f], baked[joint][f])
        xs[joint] = (inv @ np.append(foot, 1))[0]
    return xs["RLeg"] - xs["LLeg"]


def leg_tilt(joint, root, ch):
    """How far a leg leans from upright (deg), and where its foot is (root space)."""
    t = J.torso_of(root)
    c0, c1 = J.MOTORS[joint]
    pos, rot = J.to_transform(joint, list(ch))
    leg = t @ c0 @ J.cf(pos, rot) @ J.inv(c1)
    top, bottom = (leg @ np.array([0, 1.0, 0, 1]))[:3], (leg @ np.array([0, -1.0, 0, 1]))[:3]
    v = bottom - top
    return math.degrees(math.acos(-v[1] / np.linalg.norm(v))), bottom


def check_legs(c, baked):
    """The legs as the reference ability animations have them, in every frame of a clip that keys
    them: the feet never come within MIN_FEET_GAP of each other side to side (no crossing), and
    while both feet are on the floor at least one leg stands nearly upright (MAX_SUPPORT_TILT; the
    reference's never leans past 24 deg) - no splayed A-frame stances."""
    if "LLeg" not in baked:
        return
    for f in range(len(baked["Root"])):
        gap = feet_gap(baked, f)
        assert gap >= MIN_FEET_GAP, "%s: the feet come %.2f studs apart at f%d (crossing)" % (c.name, gap, f)
        tilts = [leg_tilt(j, baked["Root"][f], baked[j][f]) for j in ("LLeg", "RLeg")]
        grounded = all(foot[1] < GROUND + 0.1 for _, foot in tilts)
        upright = min(t for t, _ in tilts)
        assert not grounded or upright <= MAX_SUPPORT_TILT, "%s: both legs lean %.0f+ deg at f%d (splayed)" % (
            c.name, upright, f)


# --------------------------------------------------------------------------- feet planted per frame
MAX_SLIDE = 1.6  # studs: how far a leg's top may sit from its hip (the reference's goes 1.3 into the torso)


def stand(joint, root, spot, lean=0.0, toe=0.0):
    """Leg channels with the foot (bottom centre) on `spot` (root space, (x, z) on the floor or
    (x, y, z)). The leg leans from upright toward its hip by `lean` (0 upright, 1 aimed straight
    from the hip at the foot, as leg_to does), faces the way the torso faces (turned out by `toe`
    deg), and is slid in the torso's space to wherever that puts its top: up into the hip for a
    support leg under a low, tilted body, as the reference does."""
    t = J.torso_of(root)
    c0, c1 = J.MOTORS[joint]
    spot = np.array([spot[0], GROUND, spot[1]] if len(spot) == 2 else spot, float)
    hip = hips(root)[joint]
    to_hip = hip - spot
    up = (1 - lean) * np.array([0.0, 1.0, 0.0]) + lean * to_hip / np.linalg.norm(to_hip)
    up = up / np.linalg.norm(up)
    face = -t[:3, 2]
    face = np.array([face[0], 0.0, face[2]])
    face = face / np.linalg.norm(face) if np.linalg.norm(face) > 1e-6 else np.array([0.0, 0.0, -1.0])
    if toe:
        side = -1 if joint == "LLeg" else 1
        a = math.radians(toe * -side)
        face = np.array([face[0] * math.cos(a) + face[2] * math.sin(a), 0.0,
                         -face[0] * math.sin(a) + face[2] * math.cos(a)])
    front = face - up * float(face @ up)
    front = front / np.linalg.norm(front)
    rot = np.column_stack([np.cross(up, -front), up, -front])
    pulled = float((spot + up * 2.0 - hip) @ up)  # < 0: the leg would have to come out of the hip
    if pulled < -0.05:
        spot = spot + up * (-0.05 - pulled)  # too far to reach: the foot comes off the floor instead
    m = J.inv(c0) @ J.inv(t) @ J.cf(spot + up, rot) @ c1
    ch = [round(float(v), 4) for v in J.from_transform(joint, m[:3, 3], m[:3, :3])]
    top = spot + up * 2.0
    slid = float(np.linalg.norm(top - hip))
    return ch, slid


def plant(c, f, spots, lean=None, k="ease"):
    """Put the feet at frame f: spots {"LLeg": (x, z) | (x, y, z), "RLeg": ...} in root space, and
    how far each leg leans toward its hip (default: the lead leg upright, the other aimed). Between
    two of these the feet move from one spot to the next along curve `k` (a pivot or a slide; give
    a lifted (x, y, z) spot in between for a step)."""
    keys = c.__dict__.setdefault("feet", [])
    keys[:] = [key for key in keys if key[0] != f]
    keys.append((f, {j: tuple(v) for j, v in spots.items()}, dict(lean or {}), k))
    keys.sort(key=lambda key: key[0])
    return spots


def stagger(c, f, root, back=0.8, front=-0.15, lead=None, out=0.15, k="ease", lean=None):
    """plant with the feet where set_stance puts them: the lead foot just ahead of its own hip, the
    other `back` studs behind its hip, both a touch outside hip width. By default the lead leg
    stands upright and the back one is aimed from its hip. Returns the spots (for keep)."""
    yaw = (root[1] + 180) % 360 - 180
    lead = lead or ("LLeg" if yaw <= 0 else "RLeg")
    h = hips(root)
    spots = {}
    for joint in ("LLeg", "RLeg"):
        side = -1 if joint == "LLeg" else 1
        spots[joint] = (h[joint][0] + side * out, h[joint][2] + (front if joint == lead else back))
    other = "RLeg" if lead == "LLeg" else "LLeg"
    return plant(c, f, spots, lean or {lead: 0.1, other: 1.0}, k)


def keep(c, f, spots, k="ease", lean=None):
    """The feet still where they were (the body moves above them)."""
    return plant(c, f, spots, lean, k)


def gaze(c, f, direction, k="ease", roll=0.0):
    """Turn the head at frame f to look along a world (root space) direction, kept upright (rolled
    `roll` deg), whatever the torso is doing: the reference keeps its head level and on its mark
    through the slam while the torso dives and rolls under it. Solved per frame by solve_feet."""
    keys = c.__dict__.setdefault("gazes", [])
    keys[:] = [key for key in keys if key[0] != f]
    d = np.asarray(direction, float)
    keys.append((f, d / np.linalg.norm(d), roll, k))
    keys.sort(key=lambda key: key[0])
    c.neck_auto = False


def head_toward(root, direction, roll=0.0):
    """Neck channels pointing the head's face along a world direction, its top as close to world up
    as that allows (then rolled by `roll`)."""
    t = J.torso_of(root)
    c0, c1 = J.MOTORS["Neck"]
    fwd = np.asarray(direction, float) / np.linalg.norm(direction)
    up = np.array([0.0, 1.0, 0.0]) - fwd * fwd[1]
    up = up / np.linalg.norm(up) if np.linalg.norm(up) > 1e-6 else -t[:3, 2]
    if roll:
        a = math.radians(roll)
        right = np.cross(fwd, up)
        up = up * math.cos(a) + right * math.sin(a)
    rot = np.column_stack([np.cross(up, -fwd), up, -fwd])
    neck = (t @ c0)[:3, 3]  # the neck joint, root space
    head = J.cf(neck - rot @ c1[:3, 3], rot)
    m = J.inv(c0) @ J.inv(t) @ head @ c1
    return [round(float(v), 4) for v in J.from_transform("Neck", np.zeros(3), m[:3, :3])][:3]


def solve_feet(c, baked):
    """Place both legs on every baked frame from the feet planted with plant/stagger/keep (the
    spots and leans blended between keys along each key's curve), on the baked torso. A leg whose
    top would have to sit more than MAX_SLIDE from its hip is an authoring error."""
    from animkit import curve  # (on the path whenever a clip is)

    _solve_gaze(c, baked)
    keys = c.__dict__.get("feet")
    if not keys or "LLeg" not in baked:
        return baked
    lean_now = {"LLeg": 1.0, "RLeg": 1.0}
    leans = []
    for _, _, lean, _ in keys:
        lean_now = dict(lean_now, **lean)
        leans.append(dict(lean_now))
    for f in range(len(baked["Root"])):
        i = max([n for n, key in enumerate(keys) if key[0] <= f] or [0])
        a, b = keys[i], keys[min(i + 1, len(keys) - 1)]
        u = 0.0 if b[0] == a[0] or f <= a[0] else curve(b[3], (f - a[0]) / (b[0] - a[0]))
        for joint in ("LLeg", "RLeg"):
            p = np.array(_spot3(a[1][joint])) + (np.array(_spot3(b[1][joint])) - np.array(_spot3(a[1][joint]))) * u
            lean = leans[i][joint] + (leans[min(i + 1, len(keys) - 1)][joint] - leans[i][joint]) * u
            ch, slid = stand(joint, baked["Root"][f], p, lean)
            assert slid <= MAX_SLIDE, "%s: the %s's top sits %.2f studs off its hip at f%d" % (c.name, joint, slid, f)
            baked[joint][f] = np.array(ch)
    return baked


def _solve_gaze(c, baked):
    """The head on every baked frame from the gaze keys (directions slerped along each key's curve)."""
    from animkit import curve

    keys = c.__dict__.get("gazes")
    if not keys:
        return
    for f in range(len(baked["Root"])):
        i = max([n for n, key in enumerate(keys) if key[0] <= f] or [0])
        a, b = keys[i], keys[min(i + 1, len(keys) - 1)]
        u = 0.0 if b[0] == a[0] or f <= a[0] else curve(b[3], (f - a[0]) / (b[0] - a[0]))
        d = a[1] + (b[1] - a[1]) * u
        roll = a[2] + (b[2] - a[2]) * u
        neck = head_toward(baked["Root"][f], d, roll)
        baked["Neck"][f] = np.array(neck + [0.0, 0.0, 0.0])


def _spot3(spot):
    return (spot[0], GROUND, spot[1]) if len(spot) == 2 else tuple(spot)
