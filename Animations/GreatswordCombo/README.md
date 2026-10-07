# R6 greatsword set (two-handed)

An idle, an unsheathe, and a 1, 2, 1, 2, finisher M1 string for a two-handed greatsword, plus a running attack and an aerial attack. The format is the same as the one-handed sword set in `../SwordCombo`. The swings are modelled on the two-handed blade in `ANIMSFORCLAUDE.rbxm`: the kareemandbeast rig's m1-1, m1-2 and equip.

| Clip | What it is | Length | Markers |
|---|---|---|---|
| `idle` | The two-handed guard, breathing: both hands on the grip in front of the chest, blade standing up. Loops. | 2.08s | none |
| `unsheathe` | Draws from the back: the right hand takes the hilt over the shoulder and pulls it up the scabbard, the tip swings out behind the back, up over the head and down in front, then the left hand takes the grip. | 1.20s | `Sheathe/Unsheathe` at 0.23s, when the hand takes the hilt |
| `m1-1` | Forehand cleave: cocked far back over the right shoulder with the body wound right, then ripped over the top and down from high right to low left as the body whips round. | 0.93s | `Hit` at 0.55s |
| `m1-2` | Backhand cleave, the mirror: cocked over the left shoulder, ripped across from high left to low right and carried round behind the right hip. | 0.93s | `Hit` at 0.55s |
| `m1-3` | Finisher, an overhead cleave: the sword is raised high with the blade hanging down the back as the body rises and leans back, then the body folds forward and drops as the sword comes straight down through the target, the tip stopping just short of the floor. | 1.20s | `Hit` at 0.65s |
| `running attack` | Off a sprint, the greatsword dragged low behind in the right hand: the left foot plants, the left hand takes the grip, and the whole body spins a full turn with the blade flat at waist height, cleaving through the target as it comes round, into a low wide stance. **Keys the legs.** | 1.10s | `Hit` at 0.52s |
| `aerial attack` | In the air: the knees tuck and the sword goes up overhead, then the body jack-knifes forward and the legs drop as the sword comes down through the target below. **Keys the legs.** | 0.97s | `Hit` at 0.57s |
| `m1 string (1,2,1,2,3)` | m1-1, m1-2, m1-1, m1-2, m1-3 in one clip, to preview the whole string. | 4.30s | `Hit` on all five impacts |

Every clip is baked at 60 fps with Linear easing and Priority **Action**, the same as the references.

## The rig

`GreatswordCombo.rbxm` contains **Greatsword Rig**: the reference "normal player" R6 rig, with all the clips in `AnimSaves`.
- **Greatsword:** a model whose `Handle` part hangs off a Motor6D called **`Handle`** inside the Right Arm, built the same way as the reference weapon rigs and the one-handed sword. The Motor6D's C0 is the fist, `(0, -0.95, 0)`, with no rotation, so the blade points straight out of the fist.
- **Sword parts:** the blade, fuller, crossguard, pommel, a two-wedge point and a 1.35-stud leather grip (the `Grip` part) are welded to `Handle`. It's 5.6 studs from the right fist to the tip, and the grip is long enough for both hands.
- **Swing attachments:** `Handle` holds **`SwingBase`** (just past the guard) and **`SwingTip`** (the point). The swing trails in `VFX/CombatVFX` run between them, for example `CombatVFX.Swing("SwordSwing", …)`.
- **Scabbard:** welded to the Torso, across the back. The hilt sits up behind the right shoulder and the blade runs down to the left hip.
- **Physics:** no part collides and every part is massless.
- **Legs:** every clip keys the legs at Weight 0, so your walk (or whatever else is playing) drives them. The exceptions are the running and aerial attacks, which drive the legs themselves.

To use it on your own character, copy the `Greatsword` model, the `Handle` Motor6D and the `Scabbard` model over. Then set the Motor6D's `Part0` to your character's Right Arm and the scabbard welds' `Part0` to its Torso.

## Using the clips

1. In Studio, right-click Workspace → **Insert from File…** → `GreatswordCombo.rbxm`, then open **Greatsword Rig** in the Animation Editor. To see the whole string, load `m1 string (1,2,1,2,3)`.
2. **Publish** each clip and put the IDs in your weapon handler.
3. **Unsheathe:** until the `Sheathe/Unsheathe` marker, the animation holds the sword in the scabbard by itself. If you show a separate sheathed sword while unequipped, swap it for the real one on that marker.
4. **M1s:** cancel m1-1 and m1-2 into the next hit about 0.15s after their `Hit`, at 0.70s. Play every hit with `track:Play(0.15)` so the blend matches the string preview.
5. **Legs:** no M1 drives the legs. The guard sits the torso 0.2 studs low and the finisher drops it to 0.58, so with a straight-legged walk driving the legs, the feet dip about that far below the floor. The one-handed set does the same.

## Two hands on one grip

The right fist holds the sword (the `Handle` Motor6D). The left arm is solved onto the grip after each clip is baked: every frame, the left fist sits exactly on the grip, 0.62 studs below the right fist (toward the pommel). The left arm points from its shoulder at that spot and slides in or out of the socket as needed, as the reference arms do.
- **When the left hand lets go:** in the unsheathe, it takes the grip as the blade comes down in front, at 0.62–0.77s. In the running attack, it takes the grip as the foot plants, at 0.10–0.20s. Otherwise it never lets go.

## The swings are circles

Each M1 flies the sword in world space:
- **Arc:** the hands travel an exact circle through three points: cocked, through the target, and the follow-through. The blade points out from the circle's centre, so the tip draws a clean arc.
- **Whip:** the blade trails the hands by 20° as the swing starts and leads them by 4° at the end, so the tip whips through.
- **Hit marker:** the `Hit` fires as the hands pass through the target point.
- **Arms:** both arms and the wrist are solved for every frame from that path, so the arc stays clean whatever the torso is doing.

The unsheathe works the same way. From the pull on, the sword follows one smooth spline in world space (`DRAW_PATH`), carrying the pull's speed into the swing, so the blade never jumps.

## Arm speed limits

Pointing an arm from its shoulder at its fist goes wrong in two places:
- **A fist passing close to the shoulder** whips the arm round. In the backhand, the left fist passes 0.4 studs from the left shoulder.
- **A fist going overhead** spins the arm about itself.

After the solve, `tame()` caps how fast each arm may turn (2,200°/s) and roll about itself (1,300°/s), a little under the fastest the reference weapon M1s go. Frames that go faster are blended into their neighbours. The fists don't move: the arm slides in its socket instead, and the wrist turns so the sword stays exactly on its path.

## What was measured from the references

Measured from the kareemandbeast two-handed swings, and copied here:
- **Guard:** both fists on the grip in front of the chest, the blade standing up.
- **Grip:** the left fist rides 0.3–0.8 studs below the right through the whole swing.
- **Wind-up:** the sword is cocked far back over one shoulder, with the hands up behind the head.
- **Swing:** the torso winds about 60° the wrong way, then whips about 175°. The `Hit` comes about 0.5s into a 0.92s clip.

The greatsword clips were checked against those numbers. Tip speed is compared in blade lengths per second, because the blades are different lengths: the reference is 4.8 studs from fist to tip, the greatsword 5.6.

| | Reference | This set |
|---|---|---|
| Left fist below the right | 0.3–0.8 studs | 0.62 studs, every frame |
| Forehand torso | −60° → +115° (kareemandbeast m1-1) | −65° → +115° (m1-1) |
| Backhand torso | +85° → −105° (kareemandbeast m1-2) | +85° → −117° (m1-2) |
| Hit timing | ~0.5s into 0.92s | 0.55s into 0.93s |
| Forehand tip speed | 61.5 blade lengths/s (kareemandbeast m1-1) | 64.8 (m1-1, 363 studs/s) |
| Backhand tip speed | 45.2 blade lengths/s (kareemandbeast m1-2) | 54.8 (m1-2, 307 studs/s) |
| Finisher / running / aerial tip speed | 45–61.5 blade lengths/s | 59.5 / 57.5 / 52.1 |
| Draw tip speed | 18.3 blade lengths/s (equip, 88 studs/s) | 15.4 (unsheathe, 86 studs/s) |
| Arm slide out of the shoulder | up to 2.6–2.7 studs | up to 2.2 studs |
| Arm turn / roll speed | up to 2,300–2,800 / 1,000–1,400°/s | capped at 2,200 / 1,300°/s |

**Hit timing:** the `Hit` comes 0–1 frames after the tip's top speed in m1-1 and m1-2. In the overhead strikes (m1-3 and aerial), it comes 5–6 frames after, because the tip is fastest coming over the top and the hands only reach the target on the way down. In the running attack, it comes 2 frames before.

## Smoothness

These clips get the same smoothing pass as the other sets (see `../animkit.py`). The lightest smoothing that halves each clip's angular jerk is applied, and the strike's snap is kept:

| Clip | Smoother by |
|---|---|
| `unsheathe` | 2.07x |
| `m1-1` | 2.09x |
| `m1-2` | 2.05x |
| `m1-3` | 2.04x |
| `running attack` | 3.24x |
| `aerial attack` | 2.09x |

The idle is built directly from smooth breathing waves, so it isn't smoothed.

## Files

- `GreatswordCombo.rbxm` / `GreatswordCombo.rbxmx`: the rig, greatsword, scabbard and clips.
- `previews/key_poses.png`: the key poses of every clip, with the blade tip's path.
- `previews/m1_string.gif`: the string, in real time.
- `previews/unsheathe_idle.gif`: the unsheathe, then one loop of the idle.
- `previews/running_aerial_attacks.gif` / `running_aerial_key_poses.png`: the running and aerial attacks.
- `generate_greatsword.py`: the source for all of the above. It reuses the rig and solvers from `../SwordCombo/generate_sword.py`.
- `greatsword_data.json`: the baked channels.

## Changing it

```bash
python3 generate_greatsword.py path/to/ANIMSFORCLAUDE.rbxmx
```

- **M1s:** each is an `m1_path(...)` call: the wind-up poses (`pre`), the arc (`arc`: start frame, end frame, the point it passes through, where it ends) and the settle (`post`). Positions are in world space (+x right, +y up, −z forward).
- **Unsheathe:** the swing is `DRAW_PATH`, a list of (frame, fist, blade direction) points the spline runs through.
- **Other joints:** they use `(frame, [pitch, yaw, roll, x, y, z], curve)` keys, the same as the other sets.

Some placements are constants you can change:
- **Scabbard:** `SHEATH_HILT` and `SHEATH_DIR`.
- **Sword geometry:** `SWORD_PARTS` and `TIP`.
- **The left hand:** `LEFT_GRIP`, how far down the grip it sits.
- **Arm limits:** `MAX_SWING` and `MAX_TWIST`.
