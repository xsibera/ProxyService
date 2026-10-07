"""Builds the ability place's map: a small Hunter x Hunter style village, after Whale Island (Gon's home).

  python3 generate_village.py path/to/ANIMSFORCLAUDE.rbxmx [--preview]

White plaster houses with orange clay-tile roofs on cobbled streets round a plaza (a well, market
stalls, lamps), Mito's tavern, a harbour with a pier and a boat off a sandy beach, the big tree on
its hill, a fenced training yard with the training dummies and the animation rigs, and past the
village gate, a bandit camp in a forest clearing with its bandits. Writes:
  build/Village.rbxmx           the Workspace model (with its scripts: DummyRespawn, DummyBrains,
                                BanditBrains, DamageNumbers)
  previews/village_map.png      a map from above, and previews/village_plaza.png (with --preview)
The layout is checked as it's built: nothing overlaps, everything is on the island, and the bandit
camp is well out of the bandits' reach of the spawn.
"""

import math
import os
import random
import sys
import xml.etree.ElementTree as ET

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ABILITIES = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ABILITIES, "Shared"))
import rbxbuild as B  # noqa: E402

SRC = os.path.join(HERE, "src")
BUILD = os.path.join(HERE, "build")
jajanken = B.load("village_generate_jajanken", os.path.join(ABILITIES, "Jajanken", "generate_jajanken.py"))

MAT = {
    "Plastic": 256, "SmoothPlastic": 272, "Neon": 288, "Wood": 512, "WoodPlanks": 528, "Slate": 800,
    "Concrete": 816, "Brick": 848, "Cobblestone": 880, "Rock": 896, "Metal": 1088, "Grass": 1280,
    "LeafyGrass": 1284, "Sand": 1296, "Fabric": 1312, "Ground": 1360, "Glass": 1568,
    "ClayRoofTiles": 2307, "Plaster": 2310,
}
C = {  # colours
    "grass": (96, 148, 70), "sand": (226, 206, 152), "sea": (52, 126, 160), "road": (142, 138, 130),
    "plaza": (160, 154, 144), "dirt": (122, 98, 72), "plaster": (238, 232, 218), "timber": (104, 70, 44),
    "roof": (196, 96, 50), "roof2": (176, 78, 44), "stone": (128, 124, 118), "door": (92, 58, 36),
    "glass": (70, 92, 110), "shutter": (64, 108, 120), "plank": (150, 112, 74), "dark_wood": (78, 56, 38),
    "leaf": (70, 124, 56), "leaf2": (88, 140, 60), "trunk": (96, 70, 48), "fabric": (190, 160, 110),
    "awning_red": (176, 62, 52), "awning_blue": (60, 98, 150), "metal": (60, 60, 64), "lamp": (255, 214, 150),
    "flower_red": (200, 60, 70), "flower_yellow": (236, 196, 70), "tent": (150, 126, 92), "tent2": (120, 100, 72),
    "rock": (112, 110, 104),
}
GROUND_TOP = 0.0
ISLAND = (-210, -235, 210, 140)  # x0, z0, x1, z1 of the grass (the beach runs on south of it)
SPAWN = (0, 16)
BANDIT_REACH = 45  # the bandits' aggro range (BanditBrains); the camp must be far beyond it from the spawn


# --------------------------------------------------------------------------- parts
def rot_y(deg):
    a = math.radians(deg)
    return np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])


def rot_z(deg):
    a = math.radians(deg)
    return np.array([[math.cos(a), -math.sin(a), 0], [math.sin(a), math.cos(a), 0], [0, 0, 1]])


def rot_x(deg):
    a = math.radians(deg)
    return np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])


UPRIGHT = rot_z(90)  # cylinders lie along X: this stands them up
ALL_PARTS = []  # (class, size, matrix, colour, shape) for the previews


def part(name, size, pos, color, mat, rot=None, cls="Part", shape=None, transparency=None, collide=True,
         shadow=True, reflectance=None, **extra):
    if shape is not None:
        extra["shape"] = ("token", str({"Ball": 0, "Block": 1, "Cylinder": 2}[shape]))
    if transparency is not None:
        extra["Transparency"] = ("float", repr(float(transparency)))
    if reflectance is not None:
        extra["Reflectance"] = ("float", repr(float(reflectance)))
    if not collide:
        extra["CanCollide"] = ("bool", "false")
    if not shadow:
        extra["CastShadow"] = ("bool", "false")
    m = np.eye(4)
    m[:3, 3] = pos
    if rot is not None:
        m[:3, :3] = rot
    ALL_PARTS.append((cls, tuple(size), m, color, shape, transparency or 0))
    return jajanken.part(name, size, pos, color, MAT[mat], rot=rot, cls=cls, **extra)


def model(name, children):
    return B.item("Model", name, children)


def light(rng, brightness, color=(255, 214, 160)):
    return B.item("PointLight", "Light", Range=("float", repr(float(rng))),
                  Brightness=("float", repr(float(brightness))),
                  Color=("Color3", {"R": color[0] / 255, "G": color[1] / 255, "B": color[2] / 255}),
                  Shadows=("bool", "true"))


def fire():
    return B.item("Fire", "Fire", Size=("float", "4"), Heat=("float", "6"))


def sign(text, width_px=400, height_px=100):
    gui = B.item("SurfaceGui", "Sign", [
        B.item("TextLabel", "Text", Text=("string", text), BackgroundTransparency=("float", "1"),
               Size=("UDim2", {"XS": 1, "XO": 0, "YS": 1, "YO": 0}), TextScaled=("bool", "true"),
               TextColor3=("Color3", {"R": 0.95, "G": 0.9, "B": 0.78}),
               Font=("token", "18")),  # Fantasy? (18 = Garamond-ish); any serif reads as a painted sign
    ], CanvasSize=("Vector2", {"X": width_px, "Y": height_px}), Face=("token", "5"))  # Front (-Z)
    return gui


# --------------------------------------------------------------------------- the layout check
FOOTPRINTS = []  # (name, x0, z0, x1, z1, kind)


# what may overlap what: roads cross roads and run into squares (the plaza, the camp); props (the
# well, stalls, lamps) stand on squares; nothing else may overlap anything
MAY_OVERLAP = {("road", "road"), ("road", "square"), ("square", "road"), ("prop", "square"), ("square", "prop")}


def claim(name, x0, z0, x1, z1, kind="building"):
    """Reserve a rectangle of ground; it may not overlap anything else claimed (but see MAY_OVERLAP)."""
    x0, x1 = sorted((x0, x1))
    z0, z1 = sorted((z0, z1))
    ix0, iz0, ix1, iz1 = ISLAND
    assert ix0 <= x0 and x1 <= ix1 and iz0 <= z0 and z1 <= iz1 + 70, "%s is off the island" % name
    for other, a0, b0, a1, b1, okind in FOOTPRINTS:
        if (kind, okind) in MAY_OVERLAP:
            continue
        if x0 < a1 and a0 < x1 and z0 < b1 and b0 < z1:
            raise AssertionError("%s overlaps %s" % (name, other))
    FOOTPRINTS.append((name, x0, z0, x1, z1, kind))


def free(x, z, r):
    """Is a circle of ground clear of everything claimed?"""
    for _, a0, b0, a1, b1, _ in FOOTPRINTS:
        if a0 - r < x < a1 + r and b0 - r < z < b1 + r:
            return False
    return True


# --------------------------------------------------------------------------- the ground
def ground():
    out = [
        part("Grass", (ISLAND[2] - ISLAND[0], 6, ISLAND[3] - ISLAND[1]),
             ((ISLAND[0] + ISLAND[2]) / 2, GROUND_TOP - 3, (ISLAND[1] + ISLAND[3]) / 2), C["grass"], "Grass"),
        # the beach, then the sand running down under the sea
        part("Beach", (ISLAND[2] - ISLAND[0], 1, 30), (0, GROUND_TOP - 0.45, 155), C["sand"], "Sand"),
        part("Shore", (ISLAND[2] - ISLAND[0], 6, 48), (0, -2.95, 194), C["sand"], "Sand", cls="WedgePart",
             rot=rot_y(180)),
        part("Seabed", (1400, 2, 1400), (0, -7, 0), (194, 178, 132), "Sand"),
        part("Sea", (1400, 1, 1400), (0, -1.9, 0), C["sea"], "Glass", transparency=0.35, collide=False,
             reflectance=0.15, shadow=False),
        # the hill with the big tree, west of the village
        part("Hill", (72, 72, 72), (-128, -27, 0), C["grass"], "Grass", shape="Ball"),
    ]
    # invisible walls round the island's edge (the sea isn't swimmable)
    w = 200
    for name, size, pos in (
        ("Edge N", (1000, w, 2), (0, w / 2 - 6, ISLAND[1] - 6)),
        ("Edge S", (1000, w, 2), (0, w / 2 - 6, 212)),  # where the sea is about waist deep
        ("Edge W", (2, w, 1000), (ISLAND[0] - 6, w / 2 - 6, 0)),
        ("Edge E", (2, w, 1000), (ISLAND[2] + 6, w / 2 - 6, 0)),
    ):
        out.append(part(name, size, pos, (255, 255, 255), "SmoothPlastic", transparency=1, shadow=False))
    claim("the hill", -158, -30, -98, 30, "square")
    return model("Ground", out)


def road(name, x0, z0, x1, z1, color=None, mat="Cobblestone", top=0.12, kind="road"):
    claim(name, x0, z0, x1, z1, kind)
    return part(name, (abs(x1 - x0), 0.4, abs(z1 - z0)), ((x0 + x1) / 2, top - 0.2, (z0 + z1) / 2),
                color or C["road"], mat)


def streets():
    return model("Streets", [
        road("Plaza", -24, -24, 24, 24, C["plaza"], top=0.14, kind="square"),
        road("Main Street", -6, -24, 6, -122),
        road("Harbour Road", -6, 24, 6, 140),
        road("Yard Road", 24, -6, 68, 6),
        road("Hill Road", -24, -6, -92, 6),
        road("Bandit Path 1", -6, -122, 6, -150, C["dirt"], "Ground", top=0.1),
        road("Bandit Path 2", -40, -150, 6, -162, C["dirt"], "Ground", top=0.1),
        road("Bandit Path 3", -52, -150, -40, -168, C["dirt"], "Ground", top=0.1),
    ])


# --------------------------------------------------------------------------- buildings
def window(name, center, facing, w=2.4, h=2.8):
    """A window on a wall: dark glass in a timber frame with shutters either side. facing: unit
    vector out of the wall (X or Z)."""
    fx, fz = facing
    rot = rot_y(0 if fz else 90)
    out = []
    p = np.array(center, float)
    off = np.array([fx, 0, fz]) * 0.12
    out.append(part(name + " Glass", (w, h, 0.2), p + off, C["glass"], "Glass", rot=rot, reflectance=0.2))
    for piece, dy in (("Frame", -h / 2 - 0.1), ("Lintel", h / 2 + 0.1)):
        out.append(part(name + " " + piece, (w + 0.5, 0.35, 0.4), p + off + [0, dy, 0], C["timber"], "Wood", rot=rot))
    side = np.array([1, 0, 0]) if fz else np.array([0, 0, 1])  # along the wall
    for s in (-1, 1):
        out.append(part(name + " Shutter", (w * 0.5, h, 0.2), p + off * 1.6 + side * s * (w * 0.75 + 0.1), C["shutter"],
                        "WoodPlanks", rot=rot))
    # a flower box under it
    out.append(part(name + " Box", (w + 0.4, 0.6, 0.7), p + off * 3 + [0, -h / 2 - 0.55, 0], C["timber"], "WoodPlanks",
                    rot=rot))
    for i, col in enumerate((C["flower_red"], C["flower_yellow"], C["flower_red"])):
        q = p + off * 3 + [0, -h / 2 - 0.05, 0] + side * (i - 1) * (w / 3)
        out.append(part(name + " Flowers", (0.7, 0.7, 0.7), q, col, "LeafyGrass", shape="Ball", collide=False))
    return out


def house(name, cx, cz, w, d, h, door, roof=None, storeys=1, sign_text=None):
    """A Whale Island house: a stone footing, white plaster walls framed in dark timber, an orange
    clay-tile gable roof with overhangs and a chimney, a door with a step and windows with shutters
    and flower boxes. door: the side it faces, "E", "W", "N" or "S" (the street)."""
    claim(name, cx - w / 2 - 1, cz - d / 2 - 1, cx + w / 2 + 1, cz + d / 2 + 1)
    roof = roof or C["roof"]
    out = []
    base = GROUND_TOP
    out.append(part("Footing", (w + 0.8, 1.2, d + 0.8), (cx, base + 0.6, cz), C["stone"], "Cobblestone"))
    out.append(part("Walls", (w, h, d), (cx, base + 1.2 + h / 2, cz), C["plaster"], "Plaster"))
    top = base + 1.2 + h
    # timber: corner posts, a band at the top and between the storeys
    for sx in (-1, 1):
        for sz in (-1, 1):
            corner = (cx + sx * w / 2, base + 1.2 + h / 2, cz + sz * d / 2)
            out.append(part("Post", (0.7, h, 0.7), corner, C["timber"], "Wood"))
    for y in [top - 0.3] + ([base + 1.2 + h / 2] if storeys > 1 else []):
        out.append(part("Beam", (w + 0.6, 0.6, 0.6), (cx, y, cz - d / 2), C["timber"], "Wood"))
        out.append(part("Beam", (w + 0.6, 0.6, 0.6), (cx, y, cz + d / 2), C["timber"], "Wood"))
        out.append(part("Beam", (0.6, 0.6, d + 0.6), (cx - w / 2, y, cz), C["timber"], "Wood"))
        out.append(part("Beam", (0.6, 0.6, d + 0.6), (cx + w / 2, y, cz), C["timber"], "Wood"))
    # the roof: two wedges meeting at a ridge along the long side
    rh = min(w, d) * 0.42
    ridge_along_x = w >= d
    span, length = (d, w) if ridge_along_x else (w, d)
    over = 1.2
    for s in (-1, 1):
        if ridge_along_x:
            size = (length + 2 * over, rh, span / 2 + over)
            pos = (cx, top + rh / 2, cz + s * (span / 4 + over / 2))
            rot = rot_y(0 if s < 0 else 180)
        else:
            size = (length + 2 * over, rh, span / 2 + over)
            pos = (cx + s * (span / 4 + over / 2), top + rh / 2, cz)
            rot = rot_y(-90 if s > 0 else 90)  # the tall side toward the ridge
        out.append(part("Roof", size, pos, roof, "ClayRoofTiles", rot=rot, cls="WedgePart"))
    if ridge_along_x:
        out.append(part("Ridge", (length + 2 * over, 0.5, 0.8), (cx, top + rh + 0.1, cz), C["roof2"], "ClayRoofTiles"))
    else:
        out.append(part("Ridge", (0.8, 0.5, length + 2 * over), (cx, top + rh + 0.1, cz), C["roof2"], "ClayRoofTiles"))
    # chimney
    ch = (cx + w * 0.28, cz - d * 0.18) if ridge_along_x else (cx - w * 0.18, cz + d * 0.28)
    out.append(part("Chimney", (1.6, rh + 3, 1.6), (ch[0], top + (rh + 3) / 2, ch[1]), C["stone"], "Brick"))
    # door and windows, by the side facing the street
    normal = {"E": (1, 0), "W": (-1, 0), "N": (0, -1), "S": (0, 1)}[door]
    nx, nz = normal
    face = np.array([cx + nx * (w / 2), 0, cz + nz * (d / 2)])
    along = np.array([abs(nz), 0, abs(nx)])  # along the wall
    wall_len = w if nz else d
    rot = rot_y(0 if nz else 90)
    out.append(part("Door", (2.8, 5.2, 0.3), face + [0, base + 1.2 + 2.6, 0] + np.array([nx, 0, nz]) * 0.1, C["door"],
                    "WoodPlanks", rot=rot))
    out.append(part("Door Frame", (3.6, 0.5, 0.5), face + [0, base + 1.2 + 5.4, 0] + np.array([nx, 0, nz]) * 0.15,
                    C["timber"], "Wood", rot=rot))
    step = face + [0, base + 0.3, 0] + np.array([nx, 0, nz]) * 1.1
    out.append(part("Step", (4, 0.6, 1.6), step, C["stone"], "Slate", rot=rot))
    for k, offset in enumerate((-wall_len * 0.3, wall_len * 0.3)):
        y = base + 1.2 + (h / storeys) * 0.55
        out += window("Window %d" % k, face + [0, y, 0] + along * offset, normal)
    if storeys > 1:
        for k, offset in enumerate((-wall_len * 0.3, 0, wall_len * 0.3)):
            out += window("Upper Window %d" % k, face + [0, base + 1.2 + h * 0.75, 0] + along * offset, normal, h=2.4)
    # windows on the other walls too
    for other in ("E", "W", "N", "S"):
        if other == door:
            continue
        ox, oz = {"E": (1, 0), "W": (-1, 0), "N": (0, -1), "S": (0, 1)}[other]
        f2 = np.array([cx + ox * (w / 2), 0, cz + oz * (d / 2)])
        out += window("Side Window " + other, f2 + [0, base + 1.2 + (h / storeys) * 0.55, 0], (ox, oz))
    if sign_text:
        board = part("Sign Board", (8, 2, 0.4), face + [0, base + 1.2 + h * 0.48, 0] + np.array([nx, 0, nz]) * 0.6,
                     C["dark_wood"], "WoodPlanks", rot=rot_y({"S": 180, "N": 0, "E": -90, "W": 90}[door]))
        board.append(sign(sign_text))
        out.append(board)
        out.append(light(14, 1.2))
    return model(name, out)


def houses():
    out = [
        house("House (Main Street W1)", -20, -42, 14, 12, 9, "E"),
        house("House (Main Street W2)", -20, -68, 12, 14, 9, "E", roof=C["roof2"]),
        house("House (Main Street W3)", -21, -96, 14, 12, 12, "E", storeys=2),
        house("House (Main Street E1)", 20, -44, 14, 12, 9, "W", roof=C["roof2"]),
        house("House (Main Street E2)", 21, -72, 16, 14, 12, "W", storeys=2),
        house("House (Main Street E3)", 19, -98, 12, 12, 9, "W"),
        house("House (Harbour Road W1)", -20, 42, 14, 12, 9, "E", roof=C["roof2"]),
        house("House (Harbour Road W2)", -21, 70, 14, 14, 12, "E", storeys=2),
        house("Mito's Tavern", 24, 56, 22, 18, 13, "W", storeys=2, sign_text="MITO'S"),
        house("House (Harbour Road E2)", 19, 92, 12, 12, 9, "W", roof=C["roof2"]),
        house("House (Hill Road N)", -50, -20, 14, 12, 9, "S"),
        house("House (Hill Road S)", -52, 22, 14, 12, 9, "N", roof=C["roof2"]),
        house("House (Yard Road N)", 44, -22, 12, 12, 9, "S", roof=C["roof2"]),
        # the back row, behind the streets
        house("House (back, NW)", -46, -64, 14, 12, 9, "E", roof=C["roof2"]),
        house("House (back, NE)", 48, -66, 12, 14, 12, "W", storeys=2),
        house("House (back, SW)", -48, 60, 14, 12, 9, "E"),
        house("House (back, SE)", 54, 92, 14, 12, 9, "W", roof=C["roof2"]),
        house("House (back, S)", -46, 98, 12, 12, 9, "E"),
    ]
    out += [garden("Garden (west)", -72, 72), garden("Garden (east)", 66, -96), garden("Garden (south)", 58, 120)]
    return model("Houses", out)


def garden(name, cx, cz, w=18, d=12):
    """A fenced vegetable plot: rows of greens on tilled earth."""
    claim(name, cx - w / 2 - 0.5, cz - d / 2 - 0.5, cx + w / 2 + 0.5, cz + d / 2 + 0.5)
    out = [part("Soil", (w, 0.4, d), (cx, 0.05, cz), (98, 72, 50), "Ground")]
    rnd = random.Random(hash(name) & 0xFFFF)
    for row in range(4):
        z = cz - d / 2 + 1.8 + row * (d - 3.6) / 3
        for i in range(int(w / 2.2)):
            x = cx - w / 2 + 1.4 + i * 2.2
            col = (C["leaf2"], (120, 160, 70), (90, 130, 60))[rnd.randrange(3)]
            out.append(part("Greens", (1.4, 1.1, 1.4), (x, 0.7, z), col, "LeafyGrass", shape="Ball", collide=False))
    for x in np.arange(cx - w / 2, cx + w / 2 + 0.1, 3):
        for z in (cz - d / 2, cz + d / 2):
            out.append(part("Fence Post", (0.4, 2.4, 0.4), (x, 1.2, z), C["timber"], "Wood"))
    for z in np.arange(cz - d / 2, cz + d / 2 + 0.1, 3):
        for x in (cx - w / 2, cx + w / 2):
            out.append(part("Fence Post", (0.4, 2.4, 0.4), (x, 1.2, z), C["timber"], "Wood"))
    for z in (cz - d / 2, cz + d / 2):
        out.append(part("Fence Rail", (w, 0.3, 0.2), (cx, 1.8, z), C["plank"], "WoodPlanks"))
    for x in (cx - w / 2, cx + w / 2):
        out.append(part("Fence Rail", (0.2, 0.3, d), (x, 1.8, cz), C["plank"], "WoodPlanks"))
    return model(name, out)


# --------------------------------------------------------------------------- the plaza
def well(cx, cz):
    claim("the well", cx - 4, cz - 4, cx + 4, cz + 4, "prop")
    out = [part("Well Wall", (2.4, 6, 6), (cx, 1.2, cz), C["stone"], "Cobblestone", rot=UPRIGHT, shape="Cylinder")]
    out.append(part("Well Water", (0.2, 4.8, 4.8), (cx, 2.0, cz), (40, 70, 80), "Glass", rot=UPRIGHT, shape="Cylinder",
                    reflectance=0.3))
    for s in (-1, 1):
        out.append(part("Well Post", (0.6, 5, 0.6), (cx + s * 2.6, 4.9, cz), C["timber"], "Wood"))
    out.append(part("Well Beam", (6.2, 0.5, 0.5), (cx, 7.2, cz), C["timber"], "Wood"))
    for s in (-1, 1):
        out.append(part("Well Roof", (7, 1.6, 2.4), (cx, 8.1, cz + s * 1.15), C["roof"], "ClayRoofTiles",
                        cls="WedgePart",
                        rot=rot_y(0 if s < 0 else 180)))
    out.append(part("Bucket", (1, 1.1, 1.1), (cx, 5.6, cz), C["plank"], "WoodPlanks", rot=UPRIGHT, shape="Cylinder"))
    return model("Well", out)


def stall(name, cx, cz, awning, yaw=0):
    claim(name, cx - 4.5, cz - 3.5, cx + 4.5, cz + 3.5, "prop")
    r = rot_y(yaw)

    def at(x, y, z):
        return np.array([cx, 0, cz]) + r @ np.array([x, y, z])

    out = [part("Counter", (8, 3, 2.4), at(0, 1.5, 1.2), C["plank"], "WoodPlanks", rot=r)]
    for sx in (-1, 1):
        for sz in (-1, 1):
            out.append(part("Pole", (0.4, 7, 0.4), at(sx * 3.8, 3.5, sz * 2.6), C["timber"], "Wood", rot=r))
    out.append(part("Awning", (8.8, 0.3, 6.2), at(0, 7.1, 0), awning, "Fabric", rot=r @ rot_x(-8)))
    for i in range(4):  # crates of produce on the counter
        col = (C["flower_red"], C["flower_yellow"], (110, 150, 60), (220, 130, 50))[i]
        out.append(part("Produce", (1.5, 1, 1.5), at(-2.7 + i * 1.8, 3.5, 1.2), col, "Grass", rot=r))
    return model(name, out)


def lamp(name, x, z):
    claim(name, x - 0.6, z - 0.6, x + 0.6, z + 0.6, "prop")
    lantern = part("Lantern", (1.2, 1.6, 1.2), (x, 10.2, z), C["lamp"], "Neon", collide=False)
    lantern.append(light(22, 1.6))
    return model(name, [
        part("Base", (1.4, 1, 1.4), (x, 0.5, z), C["metal"], "Metal"),
        part("Pole", (0.5, 9.6, 0.5), (x, 5.3, z), C["metal"], "Metal"),
        lantern,
        part("Cap", (1.8, 0.4, 1.8), (x, 11.2, z), C["metal"], "Metal"),
    ])


def plaza():
    out = [well(0, 0)]
    out += [
        stall("Stall (fish)", -15, -15, C["awning_blue"]),
        stall("Stall (fruit)", 15, -15, C["awning_red"], yaw=180),
        stall("Stall (bread)", -15, 15, C["awning_red"]),
    ]
    lamps = [(-21, -21), (21, -21), (-21, 21), (21, 21), (-9, -50), (9, -76), (-9, -104), (9, 50), (-9, 80),
             (9, 112), (40, -9), (-40, 9), (-74, -9)]
    out += [lamp("Lamp %d" % i, x, z) for i, (x, z) in enumerate(lamps)]
    claim("the spawn", SPAWN[0] - 5, SPAWN[1] - 5, SPAWN[0] + 5, SPAWN[1] + 5, "prop")
    spawn = part("SpawnLocation", (10, 0.4, 10), (SPAWN[0], 0.3, SPAWN[1]), C["plaza"], "Slate", cls="SpawnLocation",
                 Neutral=("bool", "true"), Duration=("int", "0"))
    out.append(spawn)
    return model("Plaza", out)


# --------------------------------------------------------------------------- the harbour
def harbour():
    out = []
    x0, z0, z1 = 24, 128, 206
    claim("the pier", x0 - 5, z0, x0 + 5, z1)
    for z in np.arange(z0 + 2, z1, 2.2):
        out.append(part("Plank", (9, 0.4, 2), (x0, 1.0, z), C["plank"] if int(z) % 3 else C["dark_wood"], "WoodPlanks"))
    for z in np.arange(z0 + 6, z1, 12):
        for s in (-1, 1):
            out.append(part("Pier Post", (0.9, 10, 0.9), (x0 + s * 4.6, -3.2, z), C["dark_wood"], "Wood"))
    for s in (-1, 1):
        rail = (x0 + s * 4.6, 2.8, (z0 + 10 + z1) / 2)
        out.append(part("Pier Rail", (0.4, 0.4, z1 - z0 - 10), rail, C["dark_wood"], "Wood"))
    # a moored boat
    bx, bz = x0 + 14, 190
    out += [
        part("Hull", (6, 3, 16), (bx, -0.6, bz), (150, 64, 46), "WoodPlanks"),
        part("Bow", (6, 3, 5), (bx, -0.6, bz - 10.5), (150, 64, 46), "WoodPlanks", cls="WedgePart", rot=rot_y(180)),
        part("Deck", (5.4, 0.3, 15.6), (bx, 1.0, bz), C["plank"], "WoodPlanks"),
        part("Mast", (0.6, 14, 0.6), (bx, 8, bz - 2), C["dark_wood"], "Wood"),
        part("Sail", (0.2, 9, 7), (bx, 9.5, bz + 1.6), (236, 230, 214), "Fabric", collide=False),
    ]
    # crates and barrels on the beach end
    rnd = random.Random(7)
    for i in range(6):
        x, z = x0 - 11 + rnd.uniform(-3, 3), 132 + i * 2.6
        if i % 2:
            out.append(part("Barrel", (2.6, 2, 2), (x, 1.3, z), C["timber"], "WoodPlanks", rot=UPRIGHT,
                            shape="Cylinder"))
        else:
            out.append(part("Crate", (2.2, 2.2, 2.2), (x, 1.1, z), C["plank"], "WoodPlanks",
                            rot=rot_y(rnd.uniform(0, 40))))
    claim("the beach crates", x0 - 15.5, 128, x0 - 6.5, 150, "prop")
    return model("Harbour", out)


# --------------------------------------------------------------------------- trees and the forest
def tree(name, x, z, scale=1.0, base=0.0, rnd=None):
    rnd = rnd or random.Random(hash(name) & 0xFFFF)
    h = 10 * scale
    out = [part("Trunk", (h, 1.6 * scale, 1.6 * scale), (x, base + h / 2, z), C["trunk"], "Wood", rot=UPRIGHT,
                shape="Cylinder")]
    for i in range(3):
        r = (7 + rnd.uniform(-1, 2)) * scale
        dx, dz = rnd.uniform(-2, 2) * scale, rnd.uniform(-2, 2) * scale
        out.append(part("Leaves", (r, r, r), (x + dx, base + h + (i - 0.5) * 2.2 * scale, z + dz),
                        C["leaf"] if i % 2 else C["leaf2"], "LeafyGrass", shape="Ball", shadow=True))
    return model(name, out)


def big_tree():
    """Whale Island's great tree on its hill."""
    x, z, base = -128, 0, 8.6
    out = [part("Trunk", (24, 5, 5), (x, base + 12, z), C["trunk"], "Wood", rot=UPRIGHT, shape="Cylinder")]
    for ang in range(0, 360, 72):  # roots
        a = math.radians(ang)
        out.append(part("Root", (9, 1.6, 1.6), (x + math.cos(a) * 3.2, base + 0.6, z + math.sin(a) * 3.2), C["trunk"],
                        "Wood", rot=rot_y(-ang) @ rot_z(-12), shape="Cylinder"))
    rnd = random.Random(3)
    for i in range(7):
        r = rnd.uniform(14, 19)
        a = math.radians(i * 51)
        out.append(part("Leaves", (r, r, r), (x + math.cos(a) * 6, base + 25 + rnd.uniform(-2, 4), z + math.sin(a) * 6),
                        C["leaf"] if i % 2 else C["leaf2"], "LeafyGrass", shape="Ball"))
    return model("The Great Tree", out)


def forest():
    rnd = random.Random(11)
    out = []
    n = 0
    tries = 0
    while n < 70 and tries < 4000:
        tries += 1
        x, z = rnd.uniform(ISLAND[0] + 8, ISLAND[2] - 8), rnd.uniform(ISLAND[1] + 8, 120)
        inside_village = -130 < x < 130 and -125 < z < 125
        if inside_village or not free(x, z, 6):
            continue
        out.append(tree("Tree", x, z, rnd.uniform(0.85, 1.35), rnd=rnd))
        n += 1
    # a few in the village too
    for x, z in ((-36, -122), (36, -122), (-34, 112), (40, 118), (-70, 40), (60, 30), (-36, 0)):
        if free(x, z, 3):
            out.append(tree("Village Tree", x, z, 0.9, rnd=rnd))
    for _ in range(18):  # rocks
        x, z = rnd.uniform(ISLAND[0] + 10, ISLAND[2] - 10), rnd.uniform(ISLAND[1] + 10, 120)
        if not (-130 < x < 130 and -125 < z < 125) and free(x, z, 4):
            s = rnd.uniform(2.5, 5)
            out.append(part("Rock", (s * 1.4, s, s), (x, s * 0.3, z), C["rock"], "Rock", rot=rot_y(rnd.uniform(0, 90))))
    return model("Forest", out)


def village_fence():
    """A low timber fence along the north edge of the village, with the gate on the main street."""
    out = []
    for x in np.arange(-100, 101, 6):
        if abs(x) < 9:
            continue
        out.append(part("Fence Post", (0.6, 4, 0.6), (x, 2, -124), C["timber"], "Wood"))
        if abs(x + 3) >= 9 and x < 100:
            out.append(part("Fence Rail", (6, 0.4, 0.3), (x + 3, 2.8, -124), C["plank"], "WoodPlanks"))
            out.append(part("Fence Rail", (6, 0.4, 0.3), (x + 3, 1.6, -124), C["plank"], "WoodPlanks"))
    for s in (-1, 1):
        out.append(part("Gate Post", (1.4, 12, 1.4), (s * 8, 6, -124), C["dark_wood"], "Wood"))
    board = part("Gate Beam", (18, 1.6, 1.2), (0, 12.4, -124), C["dark_wood"], "WoodPlanks", rot=rot_y(180))
    board.append(sign("WHALE ISLAND"))
    out.append(board)
    claim("the village fence", -101, -125, -9, -123)
    claim("the village fence (east)", 9, -125, 101, -123)
    return model("Village Fence", out)


# --------------------------------------------------------------------------- the training yard
def training_yard(rig_source):
    x0, z0, x1, z1 = 68, -32, 128, 32
    claim("the training yard", x0, z0, x1, z1)
    out = [part("Yard Floor", (x1 - x0, 0.4, z1 - z0), ((x0 + x1) / 2, -0.08, (z0 + z1) / 2), C["dirt"], "Ground")]
    for x in np.arange(x0, x1 + 0.1, 5):
        for z in (z0, z1):
            out.append(part("Fence Post", (0.6, 4, 0.6), (x, 2, z), C["timber"], "Wood"))
    for z in np.arange(z0, z1 + 0.1, 5):
        for x in (x0, x1):
            if x == x0 and -7 < z < 7:
                continue  # the way in
            out.append(part("Fence Post", (0.6, 4, 0.6), (x, 2, z), C["timber"], "Wood"))
    for z in (z0, z1):
        out.append(part("Fence Rail", (x1 - x0, 0.4, 0.3), ((x0 + x1) / 2, 2.8, z), C["plank"], "WoodPlanks"))
    out.append(part("Fence Rail", (0.3, 0.4, z1 - z0), (x1, 2.8, (z0 + z1) / 2), C["plank"], "WoodPlanks"))
    for zs, ze in ((z0, -7), (7, z1)):
        out.append(part("Fence Rail", (0.3, 0.4, ze - zs), (x0, 2.8, (zs + ze) / 2), C["plank"], "WoodPlanks"))
    # the dummies (facing the way in, west)
    d = jajanken.dummy
    dummies = [
        d(rig_source, "Dummy", (86, -10), 90),
        d(rig_source, "Dummy", (86, 0), 90),
        d(rig_source, "Dummy", (86, 10), 90),
        d(rig_source, "Blocking Dummy", (104, -16), 90),
        d(rig_source, "Parrying Dummy", (104, 0), 90),
        d(rig_source, "Sparring Dummy", (104, 16), 90),
        d(rig_source, "Dummy (far, for Paper)", (124, 0), 90),
    ]
    out.append(B.item("Model", "Test Dummies", dummies + [
        B.script("Script", "DummyRespawn", os.path.join(SRC, "DummyRespawn.server.luau")),
        B.script("Script", "DummyBrains", os.path.join(SRC, "DummyBrains.server.luau")),
    ]))
    # the animation rigs, in a row along the north fence, for publishing the animations
    rigs = []
    for i, (package, file) in enumerate((
        ("Jajanken", "JajankenRig.rbxmx"),
        ("Killua", "KilluaRig.rbxmx"),
        ("Melee", "MeleeRig.rbxmx"),
        ("Movement", "MovementRig.rbxmx"),
        ("Leorio", "LeorioRig.rbxmx"),
    )):
        rig = jajanken.built(os.path.join(package, "build", file))
        if rig is not None:
            rigs.append(jajanken._reref(jajanken.moved(rig, jajanken.at(76 + i * 9, 3, -26, 180))))
    out.append(B.item("Model", "Animation Rigs", rigs))
    return model("Training Yard", out)


# --------------------------------------------------------------------------- the bandit camp
def bandit(rig_source, name, x, z, yaw):
    """A bandit: the reference rig in a dark tunic and trousers, a red bandana and a scarf over the
    face. The model's name is what BanditBrains looks for."""
    rig = jajanken.dummy(rig_source, name, (x, z), yaw)
    for it in rig.iter("Item"):
        if it.get("class") == "BodyColors":
            props = it.find("Properties")
            colours = {"HeadColor3": (204, 160, 120), "LeftArmColor3": (204, 160, 120),
                       "RightArmColor3": (204, 160, 120), "TorsoColor3": (92, 52, 40),
                       "LeftLegColor3": (52, 46, 40), "RightLegColor3": (52, 46, 40)}
            for el in list(props):
                if el.get("name") in colours:
                    props.remove(el)
            for key, (r, g, b) in colours.items():
                c3 = ET.SubElement(props, "Color3", {"name": key})
                for k, v in zip("RGB", (r, g, b), strict=True):
                    ET.SubElement(c3, k).text = repr(v / 255)
        if it.get("class") == "Humanoid":
            p = it.find("Properties")
            for key, val in (("MaxHealth", "140"), ("Health_XML", "140"), ("WalkSpeed", "14")):
                el = p.find("float[@name='%s']" % key)
                if el is None:
                    el = ET.SubElement(p, "float", {"name": key})
                el.text = val
    head = next(c for c in rig.findall("Item") if c.find("Properties/string[@name='Name']").text == "Head")
    hv = {c.tag: float(c.text) for c in head.find("Properties/CoordinateFrame[@name='CFrame']")}
    head_m = np.eye(4)
    head_m[:3, :3] = [[hv["R%d%d" % (i, j)] for j in range(3)] for i in range(3)]
    head_m[:3, 3] = [hv["X"], hv["Y"], hv["Z"]]
    for piece, size, offset, colour in (
        ("Bandana", (2.1, 0.45, 1.1), (0, 0.32, 0), (150, 36, 36)),
        ("Scarf", (2.1, 0.42, 1.12), (0, -0.28, -0.02), (70, 62, 56)),
    ):
        m = head_m @ np.array([[1, 0, 0, offset[0]], [0, 1, 0, offset[1]], [0, 0, 1, offset[2]], [0, 0, 0, 1]])
        p = jajanken.part(piece, size, m[:3, 3], colour, MAT["Fabric"], rot=m[:3, :3], Anchored=("bool", "false"),
                          CanCollide=("bool", "false"), Massless=("bool", "true"))
        weld = B.item("Weld", "Weld", Part0=("Ref", head.get("referent")), Part1=("Ref", p.get("referent")),
                      C0=("CoordinateFrame", B.cframe_props(np.array([[1, 0, 0, offset[0]], [0, 1, 0, offset[1]],
                                                                      [0, 0, 1, offset[2]], [0, 0, 0, 1]]))),
                      C1=("CoordinateFrame", B.cframe_props(np.eye(4))))
        p.append(weld)
        rig.append(p)
    return jajanken._reref(rig)


def tent(name, x, z, yaw, colour):
    r = rot_y(yaw)

    def at(dx, dy, dz):
        return np.array([x, 0, z]) + r @ np.array([dx, dy, dz])

    out = []
    for s in (-1, 1):
        out.append(part("Canvas", (9, 6, 3.6), at(s * 1.8, 3, 0), colour, "Fabric", cls="WedgePart",
                        rot=r @ rot_y(90 if s < 0 else -90)))
    out.append(part("Ridge Pole", (0.4, 0.4, 9.6), at(0, 6.1, 0), C["dark_wood"], "Wood", rot=r))
    return model(name, out)


def bandit_camp(rig_source):
    cx, cz, radius = -70, -190, 24
    claim("the bandit camp", cx - radius - 2, cz - radius - 2, cx + radius + 2, cz + radius + 2, "square")
    out = [part("Camp Floor", (2 * radius, 0.4, 2 * radius), (cx, -0.08, cz), C["dirt"], "Ground")]
    # a palisade of sharpened logs, open toward the path (north-east)
    for ang in range(0, 360, 9):
        a = math.radians(ang)
        if 20 < ang < 70:
            continue  # the way in, facing the path to the village
        x, z = cx + math.cos(a) * radius, cz - math.sin(a) * radius
        out.append(part("Palisade", (8, 1.4, 1.4), (x, 4, z), C["dark_wood"], "Wood", rot=UPRIGHT, shape="Cylinder"))
    out += [
        tent("Tent", cx - 10, cz - 8, 20, C["tent"]),
        tent("Tent", cx + 8, cz - 12, -30, C["tent2"]),
        tent("Tent", cx - 12, cz + 9, 80, C["tent"]),
    ]
    # the campfire
    fire_logs = []
    for ang in range(0, 360, 45):
        a = math.radians(ang)
        fire_logs.append(part("Fire Stone", (1.2, 0.8, 1.2), (cx + math.cos(a) * 2.2, 0.4, cz + math.sin(a) * 2.2),
                              C["rock"], "Rock"))
    for ang in (0, 60, 120):
        fire_logs.append(part("Log", (3.2, 0.6, 0.6), (cx, 0.5, cz), C["trunk"], "Wood", rot=rot_y(ang),
                              shape="Cylinder"))
    embers = part("Embers", (1.6, 0.3, 1.6), (cx, 0.6, cz), (255, 120, 40), "Neon", collide=False)
    embers.append(fire())
    embers.append(light(26, 2.2, (255, 150, 80)))
    fire_logs.append(embers)
    out.append(model("Campfire", fire_logs))
    # crates, barrels and a lookout
    rnd = random.Random(5)
    for i in range(7):
        a = math.radians(200 + i * 20)
        x, z = cx + math.cos(a) * 15, cz - math.sin(a) * 15
        out.append(part("Crate", (2.4, 2.4, 2.4), (x, 1.2, z), C["plank"], "WoodPlanks", rot=rot_y(rnd.uniform(0, 45))))
    lx, lz = cx + 14, cz + 12
    for sx in (-1, 1):
        for sz in (-1, 1):
            out.append(part("Lookout Leg", (0.8, 12, 0.8), (lx + sx * 2.5, 6, lz + sz * 2.5), C["dark_wood"], "Wood"))
    out.append(part("Lookout Floor", (6.4, 0.6, 6.4), (lx, 12, lz), C["plank"], "WoodPlanks"))
    out.append(part("Lookout Roof", (7, 0.4, 7), (lx, 16, lz), C["tent2"], "Fabric"))
    # the bandits, round the fire
    bandits = [bandit(rig_source, "Bandit", cx + math.cos(math.radians(a)) * 7, cz + math.sin(math.radians(a)) * 7,
                      (-a + 90) % 360) for a in (20, 95, 170, 245, 315)]
    out.append(B.item("Model", "Bandits", bandits + [
        B.script("Script", "BanditBrains", os.path.join(SRC, "BanditBrains.server.luau")),
    ]))
    camp_distance = math.hypot(cx - SPAWN[0], cz - SPAWN[1])
    assert camp_distance > BANDIT_REACH * 3, "the bandit camp is too close to the spawn (%.0f studs)" % camp_distance
    return model("Bandit Camp", out)


# --------------------------------------------------------------------------- the whole village
def village(rig_source):
    FOOTPRINTS.clear()
    ALL_PARTS.clear()
    parts_ = [ground(), streets(), plaza(), houses(), harbour(), training_yard(rig_source), village_fence(),
              bandit_camp(rig_source)]
    parts_ += [big_tree(), forest()]
    numbers = B.script("Script", "DamageNumbers", os.path.join(SRC, "DamageNumbers.server.luau"))
    return model("Whale Island", parts_ + [numbers])


def preview(out_dir):
    """A map from above, and a 3D look at the plaza (boxes, wedges, balls and cylinders, roughly)."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Circle, Polygon
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection

    def corners(size, m):
        sx, sy, sz = [s / 2 for s in size]
        pts = np.array([[x, y, z, 1] for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)])
        return (m @ pts.T).T[:, :3]

    os.makedirs(out_dir, exist_ok=True)
    fig, ax = plt.subplots(figsize=(13, 13))
    items = sorted(ALL_PARTS, key=lambda p: p[2][1, 3] + p[1][1] / 2)
    for _cls, size, m, col, shape, transp in items:
        if transp >= 0.99 or size[0] > 900:
            continue
        rgb = tuple(v / 255 for v in col)
        if shape == "Ball":
            ax.add_patch(Circle((m[0, 3], m[2, 3]), size[0] / 2, color=rgb, alpha=0.9))
            continue
        c = corners(size, m)
        top = c[:, :][np.argsort(c[:, 1])][-4:]
        hull = top[:, [0, 2]]
        centre = hull.mean(axis=0)
        order = np.argsort(np.arctan2(hull[:, 1] - centre[1], hull[:, 0] - centre[0]))
        ax.add_patch(Polygon(hull[order], closed=True, color=rgb, alpha=0.9 if transp < 0.3 else 0.5, lw=0))
    ax.plot(*SPAWN, "w*", ms=16, mec="k")
    ax.set_xlim(ISLAND[0] - 10, ISLAND[2] + 10)
    ax.set_ylim(ISLAND[3] + 40, ISLAND[1] - 10)
    ax.set_aspect("equal")
    ax.set_facecolor(tuple(v / 255 for v in C["sea"]))
    ax.set_title("Whale Island village (north up; the star is the spawn)")
    fig.tight_layout()
    fig.savefig(os.path.join(out_dir, "village_map.png"), dpi=70)
    plt.close(fig)

    fig = plt.figure(figsize=(14, 10))
    ax = fig.add_subplot(111, projection="3d")
    faces, colours = [], []
    for cls, size, m, col, _shape, transp in ALL_PARTS:
        x, z = m[0, 3], m[2, 3]
        if transp >= 0.99 or size[0] > 300 or not (-40 < x < 50 and -60 < z < 75):
            continue
        c = corners(size, m)
        idx = [(0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5)]
        if cls == "WedgePart":  # the slope: drop the top-front edge to the bottom
            c = c.copy()
            sx, sy, sz = [s / 2 for s in size]
            local = np.array([[px, py, pz] for px in (-sx, sx) for py in (-sy, sy) for pz in (-sz, sz)])
            for k, (px, py, pz) in enumerate(local):
                if py > 0 and pz < 0:
                    c[k] = (m @ np.array([px, -sy, pz, 1]))[:3]
        for f in idx:
            faces.append([(c[i][0], c[i][2], c[i][1]) for i in f])
            colours.append(tuple(v / 255 for v in col))
    ax.add_collection3d(Poly3DCollection(faces, facecolors=colours, edgecolors=(0, 0, 0, 0.15), linewidths=0.2))
    ax.set_xlim(-40, 50)
    ax.set_ylim(75, -60)
    ax.set_zlim(0, 40)
    ax.set_box_aspect((90, 135, 40))
    ax.view_init(28, -60)
    ax.set_axis_off()
    fig.tight_layout()
    fig.savefig(os.path.join(out_dir, "village_plaza.png"), dpi=70)
    plt.close(fig)
    print("wrote previews")


def build(rig_source, with_preview=False):
    v = village(rig_source)
    os.makedirs(BUILD, exist_ok=True)
    B.write([v], os.path.join(BUILD, "Village.rbxmx"))
    print("%d parts, %d footprints checked" % (len(ALL_PARTS), len(FOOTPRINTS)))
    if with_preview:
        preview(os.path.join(HERE, "previews"))
    return v


if __name__ == "__main__":
    build(sys.argv[1], "--preview" in sys.argv)
