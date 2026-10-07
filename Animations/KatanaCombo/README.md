# R6 katana set (two-handed)

An idle, an iai unsheathe, and a 1, 2, 1, 2, finisher M1 string for a two-handed katana, plus a running attack and an aerial attack. The format is the same as `../SwordCombo` and `../GreatswordCombo`. The cuts follow the reference style (the kareemandbeast two-handed swings in `ANIMSFORCLAUDE.rbxm`): big wind-ups with the body wound the wrong way, a whip through the target, and a held finish. They're cut the way a katana is used, though: from a centre guard, quicker and tighter than the greatsword's.

| Clip | What it is | Length | Markers |
|---|---|---|---|
| `idle` | Chudan-no-kamae, breathing: both hands on the tsuka in front of the navel, the point at the opponent's throat. Loops. | 2.08s | none |
| `unsheathe` | Iai. The right hand takes the tsuka at the left hip and the left hand takes the saya's mouth. The blade is drawn straight out as the hips turn back, and the moment it's out it cuts flat across the front one-handed (nukitsuke) and stops dead with the arm out to the right. Then it comes back up and the left hand joins it in chudan. | 1.10s | `Sheathe/Unsheathe` at 0.20s, when the hand takes the tsuka |
| `m1-1` | Kesa-giri: the sword is thrown up over the right shoulder, blade pointing back, then cuts down on the diagonal from high right to low left, finishing by the left knee. | 0.80s | `Hit` at 0.45s |
| `m1-2` | Kiri-age: the hands drop to the left hip with the blade back and down, then the cut rises on the diagonal from low left to high right, finishing up by the right shoulder. | 0.80s | `Hit` at 0.40s |
| `m1-3` | Finisher, shomen-giri: up into jodan (overhead, blade up and back) as the body rises, then the whole body lunges forward and drops as the sword comes straight down the centre, stopping level at the target's middle, and holds (zanshin). | 1.07s | `Hit` at 0.50s |
| `running attack` | A dash cut: off a sprint with the katana low in the right hand, point trailing, the left foot plants, the left hand takes the tsuka and the blade cocks flat by the right hip. One flat cut then sweeps right to left at waist height as the body whips into a deep lunge, right foot forward. **Keys the legs.** | 0.97s | `Hit` at 0.38s |
| `aerial attack` | A falling cut: in the air the knees tuck and the sword goes up into jodan, then the body jack-knifes forward and the legs drop as it comes straight down through the target below. **Keys the legs.** | 0.87s | `Hit` at 0.47s |
| `m1 string (1,2,1,2,3)` | m1-1, m1-2, m1-1, m1-2, m1-3 in one clip, to preview the whole string. | 3.67s | `Hit` on all five impacts |

Every clip is baked at 60 fps with Linear easing and Priority **Action**, the same as the references.

## The rig

`KatanaCombo.rbxm` contains **Katana Rig**: the reference "normal player" R6 rig, with all the clips in `AnimSaves`.
- **Katana:** a model whose `Handle` part hangs off a Motor6D called **`Handle`** inside the Right Arm, built the same way as the other weapon rigs. The Motor6D's C0 is the fist, `(0, -0.95, 0)`, with no rotation.
- **Katana parts:** these are welded to `Handle`:
  - the wrapped tsuka (`Tsuka`, with the rayskin `Same` showing through, `Menuki` and a `Kashira` cap)
  - a round `Tsuba`, the `Seppa` and the `Habaki`
  - a curved blade in four segments with a lighter `Hamon` strip along the edge
  - a one-wedge `Kissaki`

  The point is 4.44 studs from the right fist. The edge is on the Handle's +Y side and the blade curves gently toward its back, so held edge-down the point rises.
- **Swing attachments:** `Handle` holds **`SwingBase`** (just past the habaki) and **`SwingTip`** (near the point). The swing trails in `VFX/CombatVFX` run between them, for example `CombatVFX.Swing("SwordSwing", …)`.
- **Saya:** welded to the Torso at the left hip, edge up, the way a katana is worn. The mouth (`Koiguchi`) sits at the front of the hip, the saya runs back, down and out past the left thigh, and the tsuka angles in across the belly.
- **Physics:** no part collides and every part is massless.
- **Legs:** every clip keys the legs at Weight 0, so your walk (or whatever else is playing) drives them. The exceptions are the running and aerial attacks, which drive the legs themselves.

To use it on your own character, copy the `Katana` model, the `Handle` Motor6D and the `Saya` model over. Then set the Motor6D's `Part0` to your character's Right Arm and the saya welds' `Part0` to its Torso.

## Using the clips

1. In Studio, right-click Workspace → **Insert from File…** → `KatanaCombo.rbxm`, then open **Katana Rig** in the Animation Editor. To see the whole string, load `m1 string (1,2,1,2,3)`.
2. **Publish** each clip and put the IDs in your weapon handler.
3. **Unsheathe:** until the `Sheathe/Unsheathe` marker, the animation holds the sword in the saya by itself. If you show a separate sheathed katana while unequipped, swap it for the real one on that marker.
   - **Quick-draw attack:** the draw is a real cut. The blade crosses the front at about 0.45s, so if you want a quick-draw attack, add a hit there.
4. **M1s:** cancel each hit into the next about 0.15s after its `Hit`: m1-1 at 0.60s, m1-2 at 0.55s. Play every hit with `track:Play(0.15)` so the blend matches the string preview.
5. **Legs:** no M1 drives the legs. Chudan sits the torso 0.18 studs low, and the finisher's lunge drops it to 0.5 and carries it 0.8 forward. With a straight-legged walk driving the legs, the feet dip and slide that much. The other sets do the same.

## How it's built

The katana uses the same two-handed machinery as the greatsword (`../twohanded.py`):
- **The left hand:** it's locked on the tsuka every frame, 0.9 studs behind the right fist. A katana's hands sit apart, at either end of the long grip, where the greatsword's overlap.
- **Cuts are circles:** the hands travel an exact circle through three points: cocked, through the target, and the follow-through. The blade points out from the circle's centre and trails it by 16° as the cut starts, so the point whips through. The `Hit` fires as the hands pass the target point.
- **The iai draw:** the sword is held exactly in the saya until the grab and drawn straight out along it. From there, it runs along two splines in world space:
  - the cut, carrying the draw's speed on into it, with the edge turned to lead while it moves fast, ending in a dead stop
  - the return into chudan
- **Arm limits:** after the solve, `tame()` caps how fast each arm may turn (2,200°/s) and roll about itself (1,300°/s). Those caps are just under the reference weapon M1s' fastest. The fists don't move: the arms slide in their sockets instead.
- **The saya:** the blade is drawn 1.8 studs straight out of it before it swings free, so the last of the blade passes through the saya's mouth during the first frames of the cut. A full straight draw would need a 4-stud reach that an R6 arm doesn't have, and at that speed it doesn't show.

## Measured

Tip speed is compared in blade lengths per second, because the blades are different lengths (fist to point: kareemandbeast 4.8, this katana 4.44, the greatsword 5.6):

| | Reference (kareemandbeast) | This set |
|---|---|---|
| Hit timing | ~0.5s into 0.92s | 0.40–0.45s into 0.80s |
| Torso, cut 1 | −60° → +115° (m1-1) | −39° → +80° (kesa-giri) |
| Torso, cut 2 | +85° → −105° (m1-2) | +51° → −75° (kiri-age) |
| Tip speed, cut 1 / cut 2 | 61.5 / 45.2 blade lengths/s | 67.1 / 61.0 |
| Finisher / running / aerial tip speed | 45–61.5 | 50.2 / 49.8 / 49.1 |
| Draw tip speed | 18.3 (equip) | 34.9 (the iai is a cut) |
| `Hit` after the tip's top speed | 1–3 frames | 1–2 frames |
| Arm slide out of the shoulder | up to 2.6–2.7 studs | up to 1.5 studs |

## Smoothness

These clips get the same smoothing pass as the other sets (see `../animkit.py`): the lightest smoothing that halves each clip's angular jerk is applied, and the strike's snap is kept.

| Clip | Smoother by |
|---|---|
| `unsheathe` | 2.16x |
| `m1-1` | 2.06x |
| `m1-2` | 2.00x |
| `m1-3` | 2.13x |
| `running attack` | 2.04x |
| `aerial attack` | 2.13x |

The idle is built directly from smooth breathing waves, so it isn't smoothed.

## Files

- `KatanaCombo.rbxm` / `KatanaCombo.rbxmx`: the rig, katana, saya and clips.
- `previews/key_poses.png`: the key poses of every clip, with the point's path.
- `previews/m1_string.gif`: the string, in real time.
- `previews/unsheathe_idle.gif`: the iai draw, then one loop of the idle.
- `previews/running_aerial_attacks.gif` / `running_aerial_key_poses.png`: the running and aerial attacks.
- `generate_katana.py`: the source for all of the above. It uses `../twohanded.py` and the rig helpers in `../SwordCombo/generate_sword.py`.
- `katana_data.json`: the baked channels.

## Changing it

```bash
python3 generate_katana.py path/to/ANIMSFORCLAUDE.rbxmx
```

- **Cuts:** each is an `m1_path(...)` call: the wind-up poses (`pre`), the arc (`arc`: start frame, end frame, the point it passes through, where it ends) and the settle (`post`). Positions are in world space (+x right, +y up, −z forward).
- **The iai:** it's `CUT` and `RETURN`, lists of (frame, fist, blade direction) points the splines run through.
- **The katana:** `BLADE_LEN`, `POINT_LEN`, `SORI` (the curve) and `LEFT_GRIP`.
- **The saya:** `KOIGUCHI` and `SHEATH_DIR`.
