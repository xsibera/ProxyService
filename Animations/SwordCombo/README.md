# R6 one-handed sword set

An idle, an unsheathe and a 1, 2, 1, 2, finisher M1 string for a one-handed sword. They follow the style of the weapon animations in `ANIMSFORCLAUDE.rbxm`: the dagger rig, the kareemandbeast blade and the pistol rig.

| Clip | What it is | Length | Markers |
|---|---|---|---|
| `idle` | The sword stance, breathing. Loops. | 2.08s | none |
| `unsheathe` | Cross-draw from the left hip into the stance. | 1.00s | `Sheathe/Unsheathe` at 0.20s, when the hand takes the grip |
| `m1-1` | Forehand: cocks the sword behind the right shoulder, then cuts over the top from high right to low left. | 0.83s | `Hit` at 0.43s |
| `m1-2` | Backhand: cocks the sword over the left shoulder, then cuts back across from high left to low right and follows through round to the right side, with the off hand down by the side. | 0.83s | `Hit` at 0.45s |
| `m1-3` | Finisher: a lunging stab. It draws the sword back by the right side with the point toward the target and the off hand aiming, then drives a dead-straight thrust and holds the lunge. | 1.10s | `Hit` at 0.53s |
| `m1 string (1,2,1,2,3)` | m1-1, m1-2, m1-1, m1-2, m1-3 in one clip, to preview the whole string. | 3.77s | `Hit` on all five impacts |

Every clip is baked at 60 fps with Linear easing and Priority **Action**, the same as the references.

## The rig

`SwordCombo.rbxm` contains **Sword Rig**: the reference "normal player" R6 rig, with all six clips in `AnimSaves`.
- **Sword:** a model whose `Handle` part hangs off a Motor6D called **`Handle`** inside the Right Arm. The reference weapon rigs are built the same way. The Motor6D's C0 is the fist, `(0, -0.95, 0)`, with no rotation, so the blade points straight out of the fist.
- **Sword parts:** the blade, fuller, crossguard, pommel and a two-wedge point are welded to `Handle`. It's about 4.25 studs from the grip to the tip.
- **Scabbard:** welded to the Torso. The hilt sits at the front of the left hip and the scabbard runs back and down along the outside of the left thigh.
- **Physics:** no part collides and every part is massless.
- **Legs:** every clip keys the legs at Weight 0, so your walk (or whatever else is playing) drives them.

To use it on your own character, copy the `Sword` model, the `Handle` Motor6D and the `Scabbard` model over. Then set the Motor6D's `Part0` to your character's Right Arm and the scabbard welds' `Part0` to its Torso.

## Using the clips

1. In Studio, right-click Workspace → **Insert from File…** → `SwordCombo.rbxm`, then open **Sword Rig** in the Animation Editor. To see the whole string, load `m1 string (1,2,1,2,3)`.
2. **Publish** each clip and put the IDs in your weapon handler.
3. **Unsheathe:** until the `Sheathe/Unsheathe` marker, the animation holds the sword in the scabbard by itself. If you show a separate sheathed sword while unequipped, swap it for the real one on that marker.
4. **M1s:** cancel each hit into the next about 0.15s after its `Hit` (m1-1 at 0.58s, m1-2 at 0.60s). Play every hit with `track:Play(0.15)` so the blend matches the string preview.
5. **Legs:** no clip drives the legs. The finisher's lunge drops the torso 0.5 studs, so with the walk driving the legs, the feet dip that far below the floor during the lunge.

## The stab and the wrist

The slashes keep the wrist locked like the reference M1s. The stab is the one move that animates `Handle` as a wrist:
- **Chamber:** the sword is turned in the fist so the point aims at the target while the arm hangs back.
- **Thrust:** the fist travels a straight line in world space, whatever the torso is doing. The wrist turns the blade in line with the arm, so the point leads the whole way, and the arm slides out of the shoulder for reach.
- **Smoothing:** the thrust is smoothed along its line, so it never bows.

## What was measured from the references

**Weapon rigs.** Every reference weapon animation keys the `Handle` pose under the Right Arm.
- **M1s:** the wrist stays locked at identity, so the blade always leaves the fist at 90° to the arm. The cut comes from the arm and torso, not the wrist.
- **Equip:** this is the only clip that moves `Handle`. It holds the weapon in the sheath while the hand reaches for it.

**Swings (kareemandbeast m1-1 / m1-2).**
- **Start:** the same stance as the equip's end: the arm held out in front with the blade upright.
- **Coil:** the sword is cocked behind one shoulder with the blade pointing back, and the torso wound 60–85° the wrong way.
- **Whip:** the arm comes over the top, and the blade turns from pointing back, to up, to forward, while the torso swings 150–190°.
- **Finish:** the arm ends across the body with the blade forward.
- **Reach:** the arm slides out of the shoulder for reach, up to 2.6 studs.
- **Hit marker:** 1–3 frames after the blade tip's peak speed.

**Equip.**
- **0–0.17s:** the hand reaches across to the hip, and the sword stays sheathed.
- **0.23s:** the `Sheathe/Unsheathe` marker fires.
- **Draw:** the blade sweeps out low to the front, then rises into the stance, with a gentle tip speed of about 88 studs/s.

**Idles.** Both are 2.083s, loop, and key every joint, legs included.
- **Torso:** it rocks 1.1° either side of its lean and bobs 0.012 studs, once per loop.
- **Head:** it follows about 0.2s behind the torso.
- **Arms:** the free arm sways about ±1°. The weapon arm sways about ±2.5°.

The sword clips were checked against those numbers. Tip speed is compared in blade lengths per second, because the kareemandbeast blade is longer:

| | Reference | This set |
|---|---|---|
| Forehand tip speed | 61.5 blade lengths/s (kareemandbeast m1-1) | 61.2 (m1-1) |
| Backhand tip speed | 45.2 blade lengths/s (kareemandbeast m1-2) | 53.7 (m1-2, with a longer follow-through) |
| Sword arm peak | 1,480–2,530°/s | 1,530–2,080°/s |
| Draw tip speed | 88 studs/s (equip) | 97 studs/s (unsheathe) |
| Hit after tip peak | 1–3 frames | 1–3 frames |

## Smoothness

These clips get the same smoothing pass as the fist combo (see `../animkit.py`). The lightest smoothing that halves each clip's angular jerk is applied, and the strike's snap is kept:

| Clip | Smoother by |
|---|---|
| `unsheathe` | 2.18x |
| `m1-1` | 2.02x |
| `m1-2` | 2.05x |
| `m1-3` | 2.04x |

The idle is built directly from smooth breathing waves, so it isn't smoothed.

## Files

- `SwordCombo.rbxm` / `SwordCombo.rbxmx`: the rig, sword, scabbard and clips.
- `previews/key_poses.png`: the key poses of every clip, with the blade tip's path.
- `previews/m1_string.gif`: the string, in real time.
- `previews/unsheathe_idle.gif`: the unsheathe, then one loop of the idle.
- `generate_sword.py`: the source for all of the above.
- `sword_data.json`: the baked channels.

## Changing it

```bash
python3 generate_sword.py path/to/ANIMSFORCLAUDE.rbxmx
```

The sword arm is posed by target rather than by angle: `arm(fist_position, blade_direction)` in Torso space (+x right, +y up, -z forward). The solver picks the way of holding the sword whose arm points from the shoulder to the fist. Its keys interpolate as rotations, so poses near straight-ahead never wobble.

The other joints use `(frame, [pitch, yaw, roll, x, y, z], curve)` keys, the same as the fist combo.

Two placements are constants you can change:
- **Scabbard:** `SHEATH_HILT` and `SHEATH_DIR`.
- **Sword geometry:** `SWORD_PARTS`.
