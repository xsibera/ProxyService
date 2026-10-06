"""Generates the training ground (arena, dummies, movement course) as Rojo .model.json files.

    python3 tools/build_world.py

Writes src/Workspace/Arena.model.json and src/Workspace/Dummies/*.model.json. Edit the layout
constants below and re-run; then rebuild the place with `rojo build -o Place1.rbxlx`.
"""

import json
import math
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.join(HERE, "..", "src", "Workspace")

# ------------------------------------------------------------------------------- CFrame helpers


def rot_y(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return [[c, 0, s], [0, 1, 0], [-s, 0, c]]


def rot_z(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return [[c, -s, 0], [s, c, 0], [0, 0, 1]]


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def apply(r, v):
    return [sum(r[i][k] * v[k] for k in range(3)) for i in range(3)]


IDENTITY = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]


def cf(pos, r=IDENTITY):
    clean = [[round(x, 6) + 0.0 for x in row] for row in r]
    return {"CFrame": {"position": [round(p, 4) for p in pos], "orientation": clean}}


def raw_cf(x, y, z, *r):
    return {"CFrame": {"position": [x, y, z], "orientation": [list(r[0:3]), list(r[3:6]), list(r[6:9])]}}


def rgb(r, g, b):
    return [r / 255, g / 255, b / 255]


# ------------------------------------------------------------------------------- instance helpers


def inst(class_name, name=None, props=None, children=None, attributes=None):
    node = {"className": class_name}
    if name:
        node["name"] = name
    if props:
        node["properties"] = props
    if attributes:
        node["attributes"] = attributes
    if children:
        node["children"] = children
    return node


def part(name, size, cframe, color, material="SmoothPlastic", cls="Part", **extra):
    props = {
        "Anchored": True,
        "Size": list(size),
        "CFrame": cframe,
        "Color": color,
        "Material": material,
        "TopSurface": "Smooth",
        "BottomSurface": "Smooth",
    }
    props.update(extra)
    return inst(cls, name, props)


def sign(name, pos, yaw, width, height, title, body, accent):
    """A standing sign whose front faces `yaw` (0 = facing -Z, 180 = facing +Z)."""
    r = rot_y(yaw)
    board = part(name, (width, height, 0.4), cf(pos, r), rgb(22, 24, 30), "SmoothPlastic", CanCollide=False)
    gui = inst(
        "SurfaceGui",
        "Text",
        {"Face": "Front", "SizingMode": "PixelsPerStud", "PixelsPerStud": 50, "LightInfluence": 0},
        [
            inst(
                "TextLabel",
                "Title",
                {
                    "Size": {"UDim2": [[1, 0], [0.42, 0]]},
                    "Position": {"UDim2": [[0, 0], [0.04, 0]]},
                    "BackgroundTransparency": 1,
                    "Text": title,
                    "TextScaled": True,
                    "TextColor3": accent,
                    "Font": "GothamBlack",
                },
            ),
            inst(
                "TextLabel",
                "Body",
                {
                    "Size": {"UDim2": [[0.9, 0], [0.46, 0]]},
                    "Position": {"UDim2": [[0.05, 0], [0.5, 0]]},
                    "BackgroundTransparency": 1,
                    "Text": body,
                    "TextScaled": True,
                    "TextWrapped": True,
                    "TextColor3": [0.9, 0.92, 0.95],
                    "Font": "GothamBold",
                },
            ),
        ],
    )
    board["children"] = [gui]
    # posts
    post_h = pos[1] - height / 2
    off = apply(r, [width / 2 - 0.5, 0, 0.3])
    posts = []
    for sgn in (-1, 1):
        px = pos[0] + off[0] * sgn
        pz = pos[2] + off[2] * sgn
        posts.append(part(name + "Post", (0.6, post_h, 0.6), cf([px, post_h / 2, pz]), rgb(40, 42, 50), "Metal"))
    return [board] + posts


def floor_circle(name, center, radius, thickness, color, segments=64, y=0.03):
    parts = []
    for i in range(segments):
        a0 = 2 * math.pi * i / segments
        a1 = 2 * math.pi * (i + 1) / segments
        mid = (a0 + a1) / 2
        length = 2 * radius * math.sin((a1 - a0) / 2) + thickness * 0.6
        pos = [center[0] + radius * math.cos(mid), y, center[2] + radius * math.sin(mid)]
        # long axis (Z) along the tangent
        yaw = -math.degrees(mid)
        parts.append(
            part(name, (thickness, 0.06, length), cf(pos, rot_y(yaw)), color, "Neon", CanCollide=False, CastShadow=False)
        )
    return parts


def disc(name, center, diameter, height, color, material="SmoothPlastic", **extra):
    # Cylinders point along X; roll 90 degrees so the flat faces point up.
    return part(name, (height, diameter, diameter), cf(center, rot_z(90)), color, material, cls="Part", Shape="Cylinder", **extra)


# ------------------------------------------------------------------------------- R6 dummy

ROOT_R = (-1, 0, 0, 0, 0, 1, 0, 1, 0)
RIGHT_R = (0, 0, 1, 0, 1, 0, -1, 0, 0)
LEFT_R = (0, 0, -1, 0, 1, 0, 1, 0, 0)


def motor(name, part0_id, part1_id, c0, c1):
    return inst(
        "Motor6D",
        name,
        {"C0": c0, "C1": c1, "MaxVelocity": 0.1},
        attributes={"Rojo_Target_Part0": part0_id, "Rojo_Target_Part1": part1_id},
    )


def r6_dummy(key, display, dtype, pos, yaw, torso_color, limb_color, head_color):
    """pos = feet position on the floor. The rig faces `yaw` (0 = -Z)."""
    r = rot_y(yaw)
    root_pos = [pos[0], pos[1] + 3, pos[2]]

    def at(offset):
        o = apply(r, offset)
        return cf([root_pos[0] + o[0], root_pos[1] + o[1], root_pos[2] + o[2]], r)

    ids = {n: "%s-%s" % (key, n.replace(" ", "")) for n in ["HRP", "Torso", "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg"]}

    def body(name, size, offset, color, collide, extra_children=None, transparency=0):
        p = part(name, size, at(offset), color, "SmoothPlastic", Anchored=False, CanCollide=collide, Transparency=transparency)
        p["attributes"] = {"Rojo_Id": ids["HRP" if name == "HumanoidRootPart" else name]}
        if extra_children:
            p["children"] = extra_children
        return p

    hrp = body(
        "HumanoidRootPart",
        (2, 2, 1),
        [0, 0, 0],
        torso_color,
        False,
        [
            motor("RootJoint", ids["HRP"], ids["Torso"], raw_cf(0, 0, 0, *ROOT_R), raw_cf(0, 0, 0, *ROOT_R)),
            inst("Attachment", "RootAttachment"),
        ],
        transparency=1,
    )
    torso = body(
        "Torso",
        (2, 2, 1),
        [0, 0, 0],
        torso_color,
        True,
        [
            motor("Neck", ids["Torso"], ids["Head"], raw_cf(0, 1, 0, *ROOT_R), raw_cf(0, -0.5, 0, *ROOT_R)),
            motor("Right Shoulder", ids["Torso"], ids["Right Arm"], raw_cf(1, 0.5, 0, *RIGHT_R), raw_cf(-0.5, 0.5, 0, *RIGHT_R)),
            motor("Left Shoulder", ids["Torso"], ids["Left Arm"], raw_cf(-1, 0.5, 0, *LEFT_R), raw_cf(0.5, 0.5, 0, *LEFT_R)),
            motor("Right Hip", ids["Torso"], ids["Right Leg"], raw_cf(1, -1, 0, *RIGHT_R), raw_cf(0.5, 1, 0, *RIGHT_R)),
            motor("Left Hip", ids["Torso"], ids["Left Leg"], raw_cf(-1, -1, 0, *LEFT_R), raw_cf(-0.5, 1, 0, *LEFT_R)),
        ],
    )
    head = body(
        "Head",
        (2, 1, 1),
        [0, 1.5, 0],
        head_color,
        True,
        [
            inst("SpecialMesh", "Mesh", {"MeshType": "Head", "Scale": [1.25, 1.25, 1.25]}),
            inst("Decal", "face", {"Texture": "rbxasset://textures/face.png", "Face": "Front"}),
        ],
    )
    limbs = [
        body("Right Arm", (1, 2, 1), [1.5, 0, 0], limb_color, False),
        body("Left Arm", (1, 2, 1), [-1.5, 0, 0], limb_color, False),
        body("Right Leg", (1, 2, 1), [0.5, -2, 0], limb_color, False),
        body("Left Leg", (1, 2, 1), [-0.5, -2, 0], limb_color, False),
    ]
    humanoid = inst(
        "Humanoid",
        "Humanoid",
        {"RigType": "R6", "HipHeight": 0, "MaxHealth": 150, "Health": 150, "DisplayDistanceType": "None"},
        [inst("Animator", "Animator")],
    )
    colors = inst(
        "BodyColors",
        "Body Colors",
        {
            "HeadColor3": head_color,
            "TorsoColor3": torso_color,
            "LeftArmColor3": limb_color,
            "RightArmColor3": limb_color,
            "LeftLegColor3": limb_color,
            "RightLegColor3": limb_color,
        },
    )
    model = inst(
        "Model",
        None,
        children=[hrp, torso, head] + limbs + [humanoid, colors],
        attributes={"DummyType": dtype, "DisplayName": display, "Rojo_Target_PrimaryPart": ids["HRP"]},
    )
    return model


# ------------------------------------------------------------------------------- layout

SPAWN = [0, 0, 44]

DUMMIES = [
    # key, display name, type, position, torso colour, sign text
    ("Bag", "Punching Bag", "Bag", [-30, 0, -6], rgb(150, 152, 160),
     "Stands still and takes hits. Practise the 4-hit combo, the heavy and your timing."),
    ("Blocker", "Blocker", "Blocker", [-16, 0, -20], rgb(60, 120, 230),
     "Always blocking. Drain its posture with punches or break its guard with a heavy (R)."),
    ("Parrier", "Parrier", "Parrier", [0, 0, -26], rgb(240, 190, 60),
     "Parries most attacks. See what getting parried feels like, then bait and punish it."),
    ("Attacker", "Attacker", "Attacker", [16, 0, -20], rgb(220, 60, 60),
     "Chases you and attacks. Tap F right before its punches land to PARRY."),
    ("Sparring", "Sparring Partner", "Sparring", [30, 0, -6], rgb(150, 90, 230),
     "Fights back: blocks, parries, dodges and counters. Use everything you've got."),
]


def yaw_towards(src, dst):
    dx, dz = dst[0] - src[0], dst[2] - src[2]
    # yaw so that the rig's -Z (look vector) points at dst
    return math.degrees(math.atan2(-dx, -dz))


def build_arena():
    children = []
    floor_color = rgb(44, 46, 54)
    children.append(part("Floor", (360, 8, 360), cf([0, -4, 0]), floor_color, "Slate"))

    # combat circle markings
    children += floor_circle("RingOuter", [0, 0, -6], 46, 0.5, rgb(255, 170, 70), segments=72)
    children += floor_circle("RingInner", [0, 0, -6], 44.8, 0.15, rgb(255, 120, 60), segments=72)
    children.append(disc("CenterMark", [0, 0.02, -6], 10, 0.04, rgb(60, 63, 74), "SmoothPlastic", CanCollide=False, CastShadow=False))

    # dummy pads + signs
    for key, display, dtype, pos, torso, text in DUMMIES:
        accent = torso
        children.append(disc(key + "Pad", [pos[0], 0.03, pos[2]], 8, 0.06, rgb(30, 32, 40), "SmoothPlastic", CanCollide=False, CastShadow=False))
        children += floor_circle(key + "PadRing", pos, 4.3, 0.22, accent, segments=32, y=0.05)
        yaw = yaw_towards(pos, SPAWN)
        back = apply(rot_y(yaw), [0, 0, 6.5])
        sign_pos = [pos[0] + back[0], 7.2, pos[2] + back[2]]
        children += sign(key + "Sign", sign_pos, yaw, 9, 3.6, display.upper(), text, accent)

    # spawn + welcome sign
    children.append(
        inst(
            "SpawnLocation",
            "Spawn",
            {
                "Anchored": True,
                "Size": [10, 0.4, 10],
                "CFrame": cf([SPAWN[0], 0.2, SPAWN[2]]),
                "Color": rgb(255, 170, 70),
                "Material": "Neon",
                "Duration": 0,
                "Neutral": True,
                "TopSurface": "Smooth",
                "BottomSurface": "Smooth",
            },
        )
    )
    children += sign(
        "WelcomeSign",
        [0, 17, -46],
        180,
        24,
        6,
        "FIST COMBAT TRAINING",
        "Punch (LMB)  Block / Parry (F)  Heavy (R)  Dodge (Q)  Sprint (W W)  Slide (C)",
        rgb(255, 190, 90),
    )

    # ---------------------------------------------------------------- movement course (east)
    cx = 84
    children.append(part("Runway", (18, 0.06, 200), cf([cx, 0.03, -40]), rgb(70, 74, 86), "Concrete", CanCollide=False, CastShadow=False))
    for i in range(10):
        z = 50 - i * 20
        children.append(part("Marker", (18, 0.08, 0.4), cf([cx, 0.05, z]), rgb(255, 255, 255), "Neon", CanCollide=False, CastShadow=False, Transparency=0.3))
    # slide hill: gentle way up (-Z), flat top, steeper way down
    hill_color = rgb(96, 102, 118)
    children.append(part("HillUp", (16, 14, 60), cf([cx, 7, -10], rot_y(180)), hill_color, "Concrete", cls="WedgePart"))
    children.append(part("HillTop", (16, 14, 16), cf([cx, 7, -48]), hill_color, "Concrete"))
    children.append(part("HillDown", (16, 14, 40), cf([cx, 7, -76]), hill_color, "Concrete", cls="WedgePart"))
    children.append(part("HillEdgeL", (0.4, 0.3, 16), cf([cx - 7.8, 14.15, -48]), rgb(255, 170, 70), "Neon", CanCollide=False))
    children.append(part("HillEdgeR", (0.4, 0.3, 16), cf([cx + 7.8, 14.15, -48]), rgb(255, 170, 70), "Neon", CanCollide=False))
    movement_sign = [cx - 12, 7.5, 38]
    children += sign(
        "MovementSign",
        movement_sign,
        yaw_towards(movement_sign, SPAWN),
        12,
        4.2,
        "MOVEMENT COURSE",
        "Double-tap W to sprint. Press C while sprinting to slide. Slide down the hill to build speed, jump to keep it.",
        rgb(120, 200, 255),
    )

    # ---------------------------------------------------------------- landing steps (west)
    wx = -80
    heights = [4, 8, 13, 18]
    for i, h in enumerate(heights):
        z = 20 - i * 14
        children.append(part("Step%d" % (i + 1), (12, h, 12), cf([wx, h / 2, z]), rgb(80 + i * 12, 86 + i * 10, 104 + i * 8), "Concrete"))
        children.append(part("StepEdge%d" % (i + 1), (12.2, 0.2, 0.3), cf([wx, h + 0.1, z + 6]), rgb(120, 200, 255), "Neon", CanCollide=False))
    steps_sign = [wx + 12, 7.5, 34]
    children += sign(
        "StepsSign",
        steps_sign,
        yaw_towards(steps_sign, SPAWN),
        12,
        4.2,
        "LANDING STEPS",
        "Climb up and jump off. Bigger falls give bigger landings. Try sliding off the edge too.",
        rgb(120, 200, 255),
    )

    return inst("Model", None, children=children)


def write(path, node):
    with open(path, "w") as f:
        json.dump(node, f, indent=1)
        f.write("\n")


def main():
    os.makedirs(WS, exist_ok=True)
    write(os.path.join(WS, "Arena.model.json"), build_arena())
    dummies_dir = os.path.join(WS, "Dummies")
    if os.path.isdir(dummies_dir):
        shutil.rmtree(dummies_dir)
    os.makedirs(dummies_dir)
    for key, display, dtype, pos, torso, _ in DUMMIES:
        yaw = yaw_towards(pos, SPAWN)
        model = r6_dummy(key, display, dtype, pos, yaw, torso, rgb(120, 124, 134), rgb(235, 215, 185))
        write(os.path.join(dummies_dir, "%s.model.json" % key), model)
    print("wrote", os.path.relpath(WS))


if __name__ == "__main__":
    main()
