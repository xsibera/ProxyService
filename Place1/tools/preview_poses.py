"""Render R6 keyframe poses from AnimationData.luau to PNG contact sheets.

Usage: python3 tools/preview_poses.py [AnimName ...] --out previews/

Uses the same joint math as ProceduralAnimator.luau (standard R6 Motor6D C0/C1, poses in the
parent part's space, Euler order Y*X*Z), so what you see here is what plays in game.
"""

import argparse
import math
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "src", "ReplicatedStorage", "Combat", "AnimationData.luau")


# ---------------------------------------------------------------------------- Luau table parser
TOKEN = re.compile(
    r"""\s*(?:
        (?P<comment>--[^\n]*)
      | (?P<num>\d+\.\d*|\.\d+|\d+)
      | (?P<str>"[^"]*")
      | (?P<name>[A-Za-z_][A-Za-z_0-9]*)
      | (?P<sym>[{}=,;\-\[\].])
    )""",
    re.X,
)


def tokenize(src):
    pos, out = 0, []
    while pos < len(src):
        m = TOKEN.match(src, pos)
        if not m or m.end() == pos:
            if src[pos:].strip() == "":
                break
            raise SyntaxError("bad token at %d: %r" % (pos, src[pos : pos + 30]))
        pos = m.end()
        kind = m.lastgroup
        if kind == "comment":
            continue
        out.append((kind, m.group(kind)))
    return out


class Parser:
    def __init__(self, toks):
        self.t, self.i = toks, 0

    def peek(self, k=0):
        return self.t[self.i + k] if self.i + k < len(self.t) else (None, None)

    def take(self, val=None):
        tok = self.t[self.i]
        if val is not None and tok[1] != val:
            raise SyntaxError("expected %r got %r" % (val, tok))
        self.i += 1
        return tok

    def value(self):
        kind, v = self.peek()
        if v == "{":
            return self.table()
        if v == "-":
            self.take()
            return -float(self.take()[1])
        if kind == "num":
            self.take()
            return float(v)
        if kind == "str":
            self.take()
            return v[1:-1]
        if kind == "name" and v in ("true", "false"):
            self.take()
            return v == "true"
        raise SyntaxError("unexpected %r" % (v,))

    def table(self):
        self.take("{")
        arr, rec = [], {}
        while self.peek()[1] != "}":
            if self.peek()[0] == "name" and self.peek(1)[1] == "=":
                key = self.take()[1]
                self.take("=")
                rec[key] = self.value()
            else:
                arr.append(self.value())
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        if rec and arr:
            raise SyntaxError("mixed table")
        return rec if rec or not arr else arr


def load_data(path=DATA):
    src = open(path).read()
    out = {}
    for key in ("Poses", "Animations"):
        m = re.search(r"Data\.%s\s*=\s*" % key, src)
        p = Parser(tokenize(src[m.end() :]))
        out[key] = p.table()
    return out


# ---------------------------------------------------------------------------- R6 kinematics
def cf(x, y, z, r):
    m = np.eye(4)
    m[:3, :3] = np.array(r, dtype=float).reshape(3, 3)
    m[:3, 3] = (x, y, z)
    return m


def rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def inv(m):
    r = m[:3, :3].T
    o = np.eye(4)
    o[:3, :3] = r
    o[:3, 3] = -r @ m[:3, 3]
    return o


ROOT_R = [-1, 0, 0, 0, 0, 1, 0, 1, 0]
RIGHT_R = [0, 0, 1, 0, 1, 0, -1, 0, 0]
LEFT_R = [0, 0, -1, 0, 1, 0, 1, 0, 0]

# joint: (part0, part1, C0, C1)
JOINTS = {
    "Root": ("HumanoidRootPart", "Torso", cf(0, 0, 0, ROOT_R), cf(0, 0, 0, ROOT_R)),
    "Neck": ("Torso", "Head", cf(0, 1, 0, ROOT_R), cf(0, -0.5, 0, ROOT_R)),
    "RArm": ("Torso", "Right Arm", cf(1, 0.5, 0, RIGHT_R), cf(-0.5, 0.5, 0, RIGHT_R)),
    "LArm": ("Torso", "Left Arm", cf(-1, 0.5, 0, LEFT_R), cf(0.5, 0.5, 0, LEFT_R)),
    "RLeg": ("Torso", "Right Leg", cf(1, -1, 0, RIGHT_R), cf(0.5, 1, 0, RIGHT_R)),
    "LLeg": ("Torso", "Left Leg", cf(-1, -1, 0, LEFT_R), cf(-0.5, 1, 0, LEFT_R)),
}
ORDER = ["Root", "Neck", "RArm", "LArm", "RLeg", "LLeg"]
SIZES = {
    "Torso": (2, 2, 1),
    "Head": (2, 1, 1),
    "Right Arm": (1, 2, 1),
    "Left Arm": (1, 2, 1),
    "Right Leg": (1, 2, 1),
    "Left Leg": (1, 2, 1),
}
COLORS = {
    "Torso": "#3b6fd6",
    "Head": "#f2c94c",
    "Right Arm": "#e05a47",
    "Left Arm": "#47b36b",
    "Right Leg": "#7a5ccf",
    "Left Leg": "#2bb3c0",
}


def joint_cf(vals):
    v = list(vals) + [0.0] * (6 - len(vals))
    p, yw, rl, x, y, z = [float(a) for a in v]
    m = np.eye(4)
    m[:3, :3] = ry(math.radians(yw)) @ rx(math.radians(p)) @ rz(math.radians(rl))
    m[:3, 3] = (x, y, z)
    return m


def resolve_pose(poses, pose):
    if isinstance(pose, str):
        return dict(poses[pose])
    out = {}
    if "base" in pose:
        out.update(poses[pose["base"]])
    for k, v in pose.items():
        if k != "base":
            out[k] = v
    return out


def solve(pose):
    parts = {"HumanoidRootPart": np.eye(4)}
    for j in ORDER:
        p0, p1, c0, c1 = JOINTS[j]
        rc = c0.copy()
        rc[:3, 3] = 0
        pj = joint_cf(pose.get(j, []))
        transform = inv(rc) @ pj @ rc
        parts[p1] = parts[p0] @ c0 @ transform @ inv(c1)
    return parts


# ---------------------------------------------------------------------------- rendering
def box_faces(m, size):
    sx, sy, sz = [s / 2 for s in size]
    corners = np.array(
        [[x, y, z, 1] for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)]
    )
    w = (m @ corners.T).T[:, :3]
    idx = [
        (0, 1, 3, 2),
        (4, 5, 7, 6),
        (0, 1, 5, 4),
        (2, 3, 7, 6),
        (0, 2, 6, 4),
        (1, 3, 7, 5),
    ]
    return [[w[i] for i in f] for f in idx]


def to_plot(p):
    # Roblox (x right, y up, z back) -> plot (x, depth forward, up)
    return (p[0], -p[2], p[1])


def draw(ax, parts, view):
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection

    for name, size in SIZES.items():
        faces = [[to_plot(v) for v in f] for f in box_faces(parts[name], size)]
        pc = Poly3DCollection(faces, facecolor=COLORS[name], edgecolor="k", linewidths=0.4, alpha=0.9)
        ax.add_collection3d(pc)
    # nose marker on head front (-Z)
    h = parts["Head"]
    nose = (h @ np.array([0, 0, -0.9, 1]))[:3]
    ax.scatter(*to_plot(nose), color="k", s=8)
    # ground line at y = -3 (feet of a standing R6 rig)
    xs = np.array([-3, 3, 3, -3, -3])
    zs = np.array([-3, -3, 3, 3, -3])
    ax.plot(xs, zs, [-3] * 5, color="#888", lw=0.5)
    ax.set_xlim(-3, 3)
    ax.set_ylim(-3, 3)
    ax.set_zlim(-3.2, 2.8)
    ax.set_box_aspect((1, 1, 1))
    ax.view_init(*view)
    ax.set_axis_off()


VIEWS = [("front", (8, 90)), ("side", (5, 0)), ("3/4 front", (20, 50)), ("top", (89, -90))]


def render_anim(data, name, out_dir):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    anim = data["Animations"][name]
    keys = anim["Keyframes"]
    fig = plt.figure(figsize=(2.4 * len(VIEWS), 2.6 * len(keys)))
    for r, k in enumerate(keys):
        pose = resolve_pose(data["Poses"], k["pose"])
        parts = solve(pose)
        for c, (vname, view) in enumerate(VIEWS):
            ax = fig.add_subplot(len(keys), len(VIEWS), r * len(VIEWS) + c + 1, projection="3d")
            draw(ax, parts, view)
            ax.set_title("%s t=%.2f %s" % (name, k["t"], vname), fontsize=7)
    fig.tight_layout()
    path = os.path.join(out_dir, "%s.png" % name)
    fig.savefig(path, dpi=70)
    plt.close(fig)
    return path


def render_poses(data, out_dir):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    names = list(data["Poses"].keys())
    fig = plt.figure(figsize=(2.4 * len(VIEWS), 2.6 * len(names)))
    for r, n in enumerate(names):
        parts = solve(resolve_pose(data["Poses"], n))
        for c, (vname, view) in enumerate(VIEWS):
            ax = fig.add_subplot(len(names), len(VIEWS), r * len(VIEWS) + c + 1, projection="3d")
            draw(ax, parts, view)
            ax.set_title("%s %s" % (n, vname), fontsize=7)
    fig.tight_layout()
    path = os.path.join(out_dir, "_Poses.png")
    fig.savefig(path, dpi=70)
    plt.close(fig)
    return path


def validate(data):
    """Sanity checks: sorted keyframe times, known poses/joints, markers inside the clip."""
    problems = []
    joints = set(ORDER)
    for pname, pose in data["Poses"].items():
        for j in pose:
            if j not in joints:
                problems.append("pose %s: unknown joint %s" % (pname, j))
    for name, a in data["Animations"].items():
        last = -1
        for k in a["Keyframes"]:
            if k["t"] <= last:
                problems.append("%s: keyframe times not increasing at t=%s" % (name, k["t"]))
            last = k["t"]
            p = k["pose"]
            base = p if isinstance(p, str) else p.get("base")
            if base is not None and base not in data["Poses"]:
                problems.append("%s: unknown pose %s" % (name, base))
            if isinstance(p, dict):
                for j in p:
                    if j != "base" and j not in joints:
                        problems.append("%s: unknown joint %s" % (name, j))
        if abs(a["Keyframes"][-1]["t"] - a["Length"]) > 1e-6:
            problems.append("%s: last keyframe %.3f != Length %.3f" % (name, a["Keyframes"][-1]["t"], a["Length"]))
        for m in a.get("Markers", []):
            if not (0 <= m["t"] <= a["Length"]):
                problems.append("%s: marker %s outside clip" % (name, m["name"]))
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("anims", nargs="*")
    ap.add_argument("--out", default="previews")
    ap.add_argument("--check", action="store_true", help="only validate the data")
    args = ap.parse_args()
    data = load_data()
    problems = validate(data)
    for p in problems:
        print("PROBLEM:", p)
    if args.check:
        sys.exit(1 if problems else 0)
    os.makedirs(args.out, exist_ok=True)
    print(render_poses(data, args.out))
    for n in args.anims or data["Animations"].keys():
        print(render_anim(data, n, args.out))


if __name__ == "__main__":
    main()
