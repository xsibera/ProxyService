"""Shared machinery for the R6 animation generators in this folder.

Everything here encodes the style measured from the reference animations (ANIMSFORCLAUDE.rbxm):
  * 60 fps baked keys, Linear easing (the HumanoidRootPart pose is EasingDirection In, the rest Out).
  * Keys are authored as (frame, [pitch, yaw, roll, x, y, z], curve) in each joint's parent space,
    and segments are shaped with curves measured from the reference (style_profiles.json).
  * The head counter-rotates against the torso so the eyes stay on the target.
  * A smoothing pass takes the hitch out of the keyed curves while keeping the strike's snap.

Joints: Root (RootJoint), Neck, RArm / LArm (shoulders), RLeg / LLeg (hips) and Handle, the weapon
Motor6D inside the Right Arm, which is how the reference weapon rigs are built.
"""

import json
import math
import os
import xml.etree.ElementTree as ET

import numpy as np

FPS = 60
HERE = os.path.dirname(os.path.abspath(__file__))
UPPER = ("Root", "Neck", "RArm", "LArm")
PART = {
    "Root": "Torso",
    "Neck": "Head",
    "RArm": "Right Arm",
    "LArm": "Left Arm",
    "RLeg": "Right Leg",
    "LLeg": "Left Leg",
    "Handle": "Handle",
}

# --------------------------------------------------------------------------- curve profiles
P = json.load(open(os.path.join(HERE, "style_profiles.json")))


def _norm(arr):
    a = np.array(arr, float)
    return (a - a[0]) / (a[-1] - a[0])


WHIP = np.array(P["whip"])
PROFILES = {
    "coil": np.array(P["coil"]),
    "whip": WHIP,
    "settle": np.array(P["settle"]),
    "drift": np.array(P["drift"]),
    "slowin": _norm(WHIP[0:8]),  # the loaded build-up at the start of the whip
    "snap": _norm(WHIP[7:13]),  # the explosive middle of the whip
    "stop": _norm(WHIP[11:16]),  # the hard stop at the end of the whip
    "armstrike": np.array(P["arm_strike_z"]),  # the striking arm accelerating through impact
    "ease": None,
    "linear": None,
    "accel": None,
    "decel": None,
}


def curve(name, u):
    u = min(1.0, max(0.0, u))
    if name == "linear":
        return u
    if name == "ease":
        return u * u * (3 - 2 * u)
    if name == "accel":
        return u * u
    if name == "decel":
        return 1 - (1 - u) * (1 - u)
    prof = PROFILES[name]
    xs = np.linspace(0, 1, len(prof))
    return float(np.interp(u, xs, prof))


# --------------------------------------------------------------------------- clip authoring
class Clip:
    def __init__(self, name, frames, hit, arm, joints=UPPER):
        self.name = name
        self.frames = frames  # last frame index
        self.hit = hit  # frame of the "Hit" marker (None for clips without one)
        self.peak = hit  # frame the smoothing keeps sharp; defaults to the hit
        self.arm = arm  # the striking arm ("RArm" / "LArm")
        self.joints = tuple(joints)
        self.keys = {j: [] for j in self.joints}
        self.neck_auto = True
        self.smooth = True
        self.loop = False
        self.markers = {hit: ["Hit"]} if hit is not None else {}
        self.smoothing = None  # (strike sigma, jerk reduction) once baked
        # joints whose keys are interpolated (and smoothed) as rotations rather than Euler channels:
        # use this for poses solved from targets, which can sit near the Euler gimbal (arm pointing
        # straight ahead) where channel-wise interpolation would wobble
        self.slerp = set()

    def mirrored(self, name=None):
        """The same clip performed with the other side of the body (left <-> right)."""
        swap = {"RArm": "LArm", "LArm": "RArm", "RLeg": "LLeg", "LLeg": "RLeg"}
        c = Clip(name or self.name, self.frames, self.hit, swap.get(self.arm, self.arm), self.joints)
        c.peak, c.neck_auto, c.smooth, c.loop = self.peak, self.neck_auto, self.smooth, self.loop
        c.markers = dict(self.markers)
        c.slerp = {swap.get(j, j) for j in self.slerp}
        for j, ks in self.keys.items():
            for frame, vals, curve_in in ks:
                c.key(swap.get(j, j), frame, mirror(vals), curve_in)
        return c

    def key(self, joint, frame, vals, curve_in="ease"):
        v = list(vals) + [0.0] * (6 - len(vals))
        self.keys[joint].append((frame, np.array(v, float), curve_in))
        self.keys[joint].sort(key=lambda k: k[0])
        return self

    def bake(self):
        out = {}
        for j in self.joints:
            ks = self.keys[j]
            rows = []
            for f in range(self.frames + 1):
                if not ks:
                    rows.append(np.zeros(6))
                    continue
                if f <= ks[0][0]:
                    rows.append(ks[0][1].copy())
                    continue
                if f >= ks[-1][0]:
                    rows.append(ks[-1][1].copy())
                    continue
                for a, b in zip(ks, ks[1:]):
                    if a[0] <= f <= b[0]:
                        p = curve(b[2], (f - a[0]) / (b[0] - a[0]))
                        if j in self.slerp:
                            rows.append(_slerp_channels(a[1], b[1], p, rows[-1] if rows else None))
                        else:
                            rows.append(a[1] + (b[1] - a[1]) * p)
                        break
            out[j] = np.array(rows)
        if self.neck_auto:
            # head keeps facing the target: counter the torso yaw (capped), following it with a
            # slight lag so it trails the torso during the whip like the reference does
            yaw = out["Root"][:, 1]
            wrapped = (yaw + 180) % 360 - 180
            target = np.clip(-0.95 * wrapped, -71, 71)
            follow = np.zeros_like(target)
            follow[0] = target[0]
            alpha = 1 - math.exp(-(1 / FPS) / 0.022)
            for i in range(1, len(target)):
                follow[i] = follow[i - 1] + (target[i] - follow[i - 1]) * alpha
            out["Neck"][:, 1] += follow
        return smooth(self, out) if self.smooth else out


def euler_from_matrix(r, prev=None):
    """YXZ Euler angles (deg) of a rotation; with prev, the equivalent set closest to prev."""
    pitch = math.degrees(math.asin(max(-1.0, min(1.0, -r[1, 2]))))
    if math.hypot(r[1, 0], r[1, 1]) < 1e-7:
        # gimbal lock (pitch +-90): only yaw -+ roll is defined, so keep roll where it was
        roll = prev[2] if prev is not None else 0.0
        if pitch > 0:
            yaw = math.degrees(math.atan2(r[0, 1], r[0, 0])) + roll
        else:
            yaw = math.degrees(math.atan2(-r[0, 1], r[0, 0])) - roll
    else:
        yaw = math.degrees(math.atan2(r[0, 2], r[2, 2]))
        roll = math.degrees(math.atan2(r[1, 0], r[1, 1]))
    if prev is None:
        return [pitch, yaw, roll]
    best = None
    for cand in ([pitch, yaw, roll], [180 - pitch, yaw + 180, roll + 180]):
        c = [v + 360 * round((pv - v) / 360) for v, pv in zip(cand, prev[:3])]
        d = sum((v - pv) ** 2 for v, pv in zip(c, prev[:3]))
        if best is None or d < best[0]:
            best = (d, c)
    return best[1]


def _slerp_channels(a, b, u, prev):
    qa, qb = _quat(euler_yxz(*a[:3])), _quat(euler_yxz(*b[:3]))
    if np.dot(qa, qb) < 0:
        qb = -qb
    d = min(1.0, float(np.dot(qa, qb)))
    if d > 0.9995:
        q = qa + (qb - qa) * u
    else:
        th = math.acos(d)
        q = (math.sin((1 - u) * th) * qa + math.sin(u * th) * qb) / math.sin(th)
    rot = euler_from_matrix(_mat(q / np.linalg.norm(q)), prev if prev is not None else a)
    return np.array(rot + list(a[3:] + (b[3:] - a[3:]) * u))


def mirror(v):
    """Mirror a channel vector left<->right (pitch, yaw, roll, x, y, z)."""
    p, y, r, x, yy, z = (list(v) + [0] * 6)[:6]
    return [p, -y, -r, -x, yy, z]


# --------------------------------------------------------------------------- smoothing
# Every keyed segment eases in and out on its own, so on their own the arms hitch at each key.
# This pass runs a Gaussian over the baked curves: wide through the coil, settle and drift, and
# narrow around each joint's whip so the strike keeps its snap. The torso, the striking arm and the
# weapon get the lightest smoothing that cuts the clip's angular jerk by SMOOTHNESS; the off hand,
# the legs and the head don't need the snap, so they are always smoothed harder.
SMOOTHNESS = 2.0  # angular jerk of the raw keyed curves / angular jerk of the output
SMOOTH_FAR = 2.0  # Gaussian sigma (frames) away from the whip
SMOOTH_NEAR = {"off": 1.8, "neck": 1.4}  # sigma at the whip for the off hand and the head
SMOOTH_WIDTH = 3.0  # frames over which sigma narrows into the whip


def _rotvec(r):
    c = max(-1.0, min(1.0, (np.trace(r) - 1) / 2))
    th = math.acos(c)
    if th < 1e-9:
        return np.zeros(3)
    v = np.array([r[2, 1] - r[1, 2], r[0, 2] - r[2, 0], r[1, 0] - r[0, 1]]) / (2 * math.sin(th))
    return v * th


def _angular_velocity(ch):
    """Per-frame angular velocity vectors (rad/s, parent space) of a channel track."""
    rs = [euler_yxz(*row[:3]) for row in ch]
    return np.array([rs[i] @ _rotvec(rs[i - 1].T @ rs[i]) * FPS for i in range(1, len(rs))])


def angular_speed(ch):
    w = np.linalg.norm(_angular_velocity(ch), axis=1) * 180 / math.pi
    return np.concatenate([w[:1], w])


def angular_jerk(tracks):
    """RMS angular jerk (deg/s^3) over all joints of a clip."""
    total = 0.0
    for ch in tracks.values():
        jk = np.diff(_angular_velocity(ch), n=2, axis=0) * FPS * FPS
        total += (np.linalg.norm(jk, axis=1) ** 2).mean()
    return math.sqrt(total) * 180 / math.pi


def _gauss_varying(ch, sigma, as_rotation=False):
    n = len(ch)
    out = np.empty_like(ch)
    if as_rotation:
        # average neighbouring frames as quaternions (sign-aligned), so the result never depends
        # on how the rotation happens to be split into Euler angles
        qs = [_quat(euler_yxz(*row[:3])) for row in ch]
        for i in range(1, n):
            if np.dot(qs[i], qs[i - 1]) < 0:
                qs[i] = -qs[i]
        qs = np.array(qs)
    for i in range(n):
        r = max(1, int(math.ceil(3 * sigma[i])))
        idx = np.clip(np.arange(i - r, i + r + 1), 0, n - 1)
        w = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma[i]) ** 2)
        w = w / w.sum()
        out[i] = w @ ch[idx]
        if as_rotation:
            q = w @ qs[idx]
            out[i, :3] = euler_from_matrix(_mat(q / np.linalg.norm(q)), out[i - 1] if i else ch[0])
    return out


def smooth(clip, raw):
    lo, hi = max(0, clip.peak - 8), clip.peak + 3
    off = "LArm" if clip.arm == "RArm" else "RArm"
    fixed = {"Neck": SMOOTH_NEAR["neck"], off: SMOOTH_NEAR["off"], "RLeg": SMOOTH_NEAR["off"], "LLeg": SMOOTH_NEAR["off"]}
    f = np.arange(len(raw["Root"]))
    centre = {j: lo + int(np.argmax(angular_speed(raw[j])[lo:hi])) for j in clip.joints}
    base = angular_jerk(raw)
    for strike in np.arange(0.3, 1.501, 0.05):
        out = {}
        for j in clip.joints:
            near = fixed.get(j, strike)
            sig = SMOOTH_FAR - (SMOOTH_FAR - near) * np.exp(-0.5 * ((f - centre[j]) / SMOOTH_WIDTH) ** 2)
            out[j] = _gauss_varying(raw[j], sig, j in clip.slerp)
        factor = base / angular_jerk(out)
        if factor >= SMOOTHNESS:
            break
    clip.smoothing = (round(float(strike), 2), factor)
    return out


# --------------------------------------------------------------------------- R6 conversion
C0_ROT = {  # standard R6 Motor6D C0 rotations (rows); the weapon joint has none
    "Root": [[-1, 0, 0], [0, 0, 1], [0, 1, 0]],
    "Neck": [[-1, 0, 0], [0, 0, 1], [0, 1, 0]],
    "RArm": [[0, 0, 1], [0, 1, 0], [-1, 0, 0]],
    "LArm": [[0, 0, -1], [0, 1, 0], [1, 0, 0]],
    "RLeg": [[0, 0, 1], [0, 1, 0], [-1, 0, 0]],
    "LLeg": [[0, 0, -1], [0, 1, 0], [1, 0, 0]],
    "Handle": [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
}


def euler_yxz(p, y, r):
    p, y, r = map(math.radians, (p, y, r))
    cx, sx, cy, sy, cz, sz = math.cos(p), math.sin(p), math.cos(y), math.sin(y), math.cos(r), math.sin(r)
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return ry @ rx @ rz


def to_transform(joint, ch):
    """Parent-space channels -> Motor6D Transform (what a Pose.CFrame stores)."""
    rc = np.array(C0_ROT[joint], float)
    pr = euler_yxz(ch[0], ch[1], ch[2])
    rot = rc.T @ pr @ rc
    pos = rc.T @ np.array(ch[3:6])
    return pos, rot


def from_transform(joint, pos, rot):
    """Motor6D Transform -> parent-space channels (inverse of to_transform)."""
    rc = np.array(C0_ROT[joint], float)
    pr = rc @ np.asarray(rot) @ rc.T
    return euler_from_matrix(pr) + list(rc @ np.asarray(pos))


# --------------------------------------------------------------------------- XML export
_ref = [0]


def ref():
    _ref[0] += 1
    return "RBXCOMBO%06d" % _ref[0]


def prop(parent, tag, name, text=None):
    el = ET.SubElement(parent, tag, {"name": name})
    if text is not None:
        el.text = text
    return el


def cframe(parent, name, pos, rot):
    el = ET.SubElement(parent, "CoordinateFrame", {"name": name})
    for k, v in zip(["X", "Y", "Z"], pos):
        ET.SubElement(el, k).text = repr(float(v))
    for i in range(3):
        for j in range(3):
            ET.SubElement(el, "R%d%d" % (i, j)).text = repr(float(rot[i][j]))


def pose(parent, name, pos, rot, weight=1.0, direction=1):
    item = ET.SubElement(parent, "Item", {"class": "Pose", "referent": ref()})
    props = ET.SubElement(item, "Properties")
    prop(props, "string", "Name", name)
    cframe(props, "CFrame", pos, rot)
    prop(props, "token", "EasingDirection", str(direction))
    prop(props, "token", "EasingStyle", "0")
    prop(props, "float", "Weight", repr(float(weight)))
    return item


IDENTITY = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]


def clip_transforms(clip, baked):
    """Per frame: {joint: (pos, rot)} Motor6D transforms."""
    return [{j: to_transform(j, baked[j][f]) for j in clip.joints} for f in range(clip.frames + 1)]


def sequence_xml(name, frames, markers, loop=False, zero_weight=("RLeg", "LLeg")):
    """frames: per frame {joint: (pos, rot)}; markers: {frame: [marker names]}.
    Joints in zero_weight that a frame doesn't drive are keyed at Weight 0 (as the reference M1s do
    for the legs), so walk and idle keep driving them."""
    seq = ET.Element("Item", {"class": "KeyframeSequence", "referent": ref()})
    props = ET.SubElement(seq, "Properties")
    prop(props, "string", "Name", name)
    prop(props, "bool", "Loop", "true" if loop else "false")
    prop(props, "token", "Priority", "2")
    for f, transforms in enumerate(frames):
        kf = ET.SubElement(seq, "Item", {"class": "Keyframe", "referent": ref()})
        kp = ET.SubElement(kf, "Properties")
        prop(kp, "string", "Name", "Keyframe")
        prop(kp, "float", "Time", repr(f / FPS))
        hrp = pose(kf, "HumanoidRootPart", (0, 0, 0), IDENTITY, 1.0, direction=0)
        pos, rot = transforms["Root"]
        torso = pose(hrp, "Torso", pos, rot)
        for joint in ["Neck", "RArm", "LArm", "RLeg", "LLeg"]:
            if joint in transforms:
                pos, rot = transforms[joint]
                item = pose(torso, PART[joint], pos, rot)
                if joint == "RArm" and "Handle" in transforms:
                    pos, rot = transforms["Handle"]
                    pose(item, PART["Handle"], pos, rot)
            elif joint in zero_weight:
                pose(torso, PART[joint], (0, 0, 0), IDENTITY, 0.0)
        for marker_name in markers.get(f, []):
            marker = ET.SubElement(kf, "Item", {"class": "KeyframeMarker", "referent": ref()})
            mp = ET.SubElement(marker, "Properties")
            prop(mp, "string", "Name", marker_name)
            prop(mp, "string", "Value", marker_name)
    return seq


# --------------------------------------------------------------------------- string preview
def _quat(m):
    m = np.asarray(m, float)
    tr = m[0, 0] + m[1, 1] + m[2, 2]
    if tr > 0:
        sq = math.sqrt(tr + 1.0) * 2
        q = [0.25 * sq, (m[2, 1] - m[1, 2]) / sq, (m[0, 2] - m[2, 0]) / sq, (m[1, 0] - m[0, 1]) / sq]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        sq = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [(m[2, 1] - m[1, 2]) / sq, 0.25 * sq, (m[0, 1] + m[1, 0]) / sq, (m[0, 2] + m[2, 0]) / sq]
    elif m[1, 1] > m[2, 2]:
        sq = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 2] - m[2, 0]) / sq, (m[0, 1] + m[1, 0]) / sq, 0.25 * sq, (m[1, 2] + m[2, 1]) / sq]
    else:
        sq = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[1, 0] - m[0, 1]) / sq, (m[0, 2] + m[2, 0]) / sq, (m[1, 2] + m[2, 1]) / sq, 0.25 * sq]
    q = np.array(q)
    return q / np.linalg.norm(q)


def _mat(q):
    w, x, y, z = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def blend(a, b, w):
    """Blend two {joint: (pos, rot)} poses: slerp rotations, lerp positions."""
    out = {}
    for j in a:
        (pa, ra), (pb, rb) = a[j], b[j]
        qa, qb = _quat(ra), _quat(rb)
        d = float(np.dot(qa, qb))
        if d < 0:
            qb, d = -qb, -d
        if d > 0.9995:
            q = qa + (qb - qa) * w
        else:
            th = math.acos(d)
            q = (math.sin((1 - w) * th) * qa + math.sin(w * th) * qb) / math.sin(th)
        q = q / np.linalg.norm(q)
        out[j] = (np.array(pa) + (np.array(pb) - np.array(pa)) * w, _mat(q))
    return out


def rest_pose(joints):
    return {j: ((0.0, 0.0, 0.0), np.eye(3)) for j in joints}


def smoothstep(u):
    u = min(1.0, max(0.0, u))
    return u * u * (3 - 2 * u)


def build_string(clips, cancel, fade, end_fade, start_pose, end_pose):
    """Chain clips the way the Animator plays them in game: each one starts when the previous one
    is cancelled (cancel[name] seconds in, or at its end) and crossfades in over `fade`. The last
    clip plays out and then fades to end_pose. clips: list of (clip, frames) in order.
    Returns (frames, {frame: ["Hit"]})."""
    starts, t = [], 0.0
    for clip, _ in clips:
        starts.append(t)
        t += cancel.get(clip.name, clip.frames / FPS)
    last_clip, last_frames = clips[-1]
    end = starts[-1] + last_clip.frames / FPS + end_fade
    total = int(round(end * FPS))

    def sample(frames, local):
        return frames[min(len(frames) - 1, max(0, int(round(local * FPS))))]

    out = []
    for f in range(total + 1):
        t = f / FPS
        pose_now = start_pose
        for i, (clip, frames) in enumerate(clips):
            if t < starts[i]:
                break
            local = t - starts[i]
            w = smoothstep(local / fade) if i > 0 else 1.0
            pose_now = blend(pose_now, sample(frames, local), w)
        tail = t - (starts[-1] + last_clip.frames / FPS)
        if tail > 0:
            pose_now = blend(pose_now, end_pose, smoothstep(tail / end_fade))
        out.append(pose_now)
    hits = {}
    for i, (clip, _) in enumerate(clips):
        if clip.hit is not None:
            hits.setdefault(int(round((starts[i] + clip.hit / FPS) * FPS)), []).append("Hit")
    return out, hits


# --------------------------------------------------------------------------- rig
def reference_rig(rig_source, name):
    """The reference "normal player" R6 rig from ANIMSFORCLAUDE.rbxmx, renamed, with an empty
    AnimSaves. Returns (rig item, AnimSaves item)."""
    src = ET.parse(rig_source).getroot()
    rig = None
    for item in src.findall("Item"):
        n = item.find("Properties/string[@name='Name']")
        if n is not None and n.text == "normal player":
            rig = item
    assert rig is not None, "normal player rig not found"
    saves = None
    for child in list(rig.findall("Item")):
        cname = child.find("Properties/string[@name='Name']")
        if child.get("class") == "ObjectValue" and cname is not None and cname.text == "AnimSaves":
            saves = child
            for old in list(child.findall("Item")):
                child.remove(old)
    rig.find("Properties/string[@name='Name']").text = name
    # drop Studio-regenerated caches that point into the source file's SharedStrings table
    for props in rig.iter("Properties"):
        for el in list(props):
            if el.tag == "SharedString":
                props.remove(el)
    return rig, saves
