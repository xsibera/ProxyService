# R6 greatsword set (two-handed)

An idle, an unsheathe, and a 1, 2, 1, 2, finisher M1 string for a two-handed greatsword, plus a running attack and an aerial attack. The format is the same as the one-handed sword set in `../SwordCombo`. The swings are modelled on the two-handed blade in `ANIMSFORCLAUDE.rbxm` (the kareemandbeast rig's m1-1, m1-2 and equip), then slowed and weighted so the sword reads as heavy (see **Weight** below).

| Clip | What it is | Length | Markers |
|---|---|---|---|
| `idle` | The two-handed guard, low and wide under the weight, breathing heavily: both hands on the grip at the belt, the blade angled up and forward. Loops. | 2.08s | none |
| `unsheathe` | Draws from the back: the right hand takes the hilt over the shoulder and pulls it up the scabbard, the tip swings slowly out behind the back, up over the head and down in front, then the left hand takes the grip and the knees give as the weight lands in both hands. | 1.43s | `Sheathe/Unsheathe` at 0.23s, when the hand takes the hilt |
| `m1-1` | Forehand cleave: heaved up and laid back over the right shoulder as the body winds right and sinks, held loaded, then hauled over the top and down from high right to low left, building speed. Its weight carries it on round by the left foot and drags the body after it, then it's hauled back up. | 1.40s | `Hit` at 0.82s |
| `m1-2` | Backhand cleave, the mirror: heaved back over the left shoulder, hauled across from high left to low right and carried round behind the right hip by its weight. | 1.40s | `Hit` at 0.82s |
| `m1-3` | Finisher, an overhead cleave: the body sinks, then heaves the sword up overhead, rising and leaning back under it. It holds at the top, then the whole body drops behind it as it comes straight down through the target, speeding up until it slams into the floor in front. It jars off the ground, the body sags over it, and it's dragged back up. | 1.67s | `Hit` at 0.93s |
| `running attack` | Off a sprint, the greatsword dragged behind in the right hand with its tip scraping the floor: the left foot plants, the body heaves round as the left hand takes the grip, then the sword's weight swings the whole body a full turn on the planted foot, the blade flat at waist height cleaving through the target as it comes round, the turn slowing into a low wide stance. **Keys the legs.** | 1.33s | `Hit` at 0.63s |
| `aerial attack` | In the air: the knees tuck and the sword is heaved up overhead and held at the top of the jump, then the body jack-knifes forward and the legs drop as it comes down through the target below, speeding up all the way. It lands with a jolt and a deep sag. **Keys the legs.** | 1.20s | `Hit` at 0.72s |
| `m1 string (1,2,1,2,3)` | m1-1, m1-2, m1-1, m1-2, m1-3 in one clip, to preview the whole string. | 5.83s | `Hit` on all five impacts |

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
4. **M1s:** cancel m1-1 and m1-2 into the next hit about 0.15s after their `Hit`, at 0.97s. Play every hit with `track:Play(0.15)` so the blend matches the string preview.
5. **Legs:** no M1 drives the legs. The guard sits the torso 0.3 studs low and the swings drop it to 0.65–0.7, so with a straight-legged walk driving the legs, the feet dip about that far below the floor. The one-handed set does the same.

## Two hands on one grip

The right fist holds the sword (the `Handle` Motor6D). The left arm is solved onto the grip after each clip is baked: every frame, the left fist sits exactly on the grip, 0.62 studs below the right fist (toward the pommel). The left arm points from its shoulder at that spot and slides in or out of the socket as needed, as the reference arms do.
- **When the left hand lets go:** in the unsheathe, it takes the grip as the blade comes down in front, at 0.77–0.95s. In the running attack, it takes the grip as the foot plants, at 0.12–0.23s. Otherwise it never lets go.

## Weight

What makes it heavy:
- **The lift:** the sword is heaved up slowly (about 0.3s) while the body sinks under it and winds the wrong way, then held loaded for a beat.
- **Wind-up:** the blade is laid back over the shoulder, or behind the head for the overheads, along the line it's about to swing. Nothing has to flip round when the swing starts, so the swing begins from rest.
- **The swing builds:** the cleaves use a `heave` curve, slow to start and fastest about two-thirds of the way round, just past the target. The overheads use `slam`, which speeds up all the way until the blade hits. The tips peak at about half the speed of the one-handed sword's.
- **Lag:** the blade trails the hands by 28° as they start to pull it, and runs on 10° ahead of them at the end.
- **Momentum:** the cleaves carry on well past the target on their own weight and drag the body further round than it wound (about 195–215°).
- **Impacts:** the overheads stop dead on the floor, jar back off it and sag before the sword is dragged back up.
- **Recovery:** the sword is hauled back slowly; nothing snaps back to the guard.

## The swings are circles

Each M1 flies the sword in world space:
- **Arc:** the hands travel an exact circle through three points: cocked, through the target, and the follow-through. The blade points out from the circle's centre, so the tip draws a clean arc.
- **Hit marker:** the `Hit` fires as the hands pass through the target point.
- **Arms:** both arms and the wrist are solved for every frame from that path, so the arc stays clean whatever the torso is doing.

The unsheathe works the same way. From the pull on, the sword follows one smooth spline in world space (`DRAW_PATH`), carrying the pull's speed into the swing, so the blade never jumps.

This machinery is shared with the katana set, in `../twohanded.py`.

## Arms: out of the torso, and speed limits

**Out of the torso.** An R6 arm pointed from its shoulder at a fist in front of the body's centre cuts straight through the chest. Two hands on one grip put a fist there almost all the time. So wherever an arm would sink into the torso, its upper end swings forward, away from the shoulder, just far enough to clear it. The fist stays where it is. The swing eases in and out over a few frames.
- **Result:** no arm is ever more than about 15% inside the torso, where before the left arm sat half inside it in the guard.
- **Slide:** the arms slide further out of their sockets than before, up to 2.9 studs in the running attack, where the left hand holds the grip out on the far right.

**Speed limits.** Pointing an arm from its shoulder at its fist goes wrong in two more places:
- **A fist passing close to the shoulder** whips the arm round. In the backhand, the left fist passes 0.4 studs from the left shoulder.
- **A fist going overhead** spins the arm about itself.

After the solve, `tame()` caps how fast each arm may turn (2,200°/s) and roll about itself (1,300°/s), a little under the fastest the reference weapon M1s go. Frames that go faster are blended into their neighbours. The fists don't move: the arm slides in its socket instead, and the wrist turns so the sword stays exactly on its path.

## Compared with the references

Kept from the kareemandbeast two-handed swings:
- **Grip:** the left fist rides 0.3–0.8 studs below the right through the whole swing.
- **Wind-up:** the sword is cocked far back over one shoulder, with the hands up behind the head.
- **Swing:** the torso winds the wrong way, then whips round.

Deliberately slower than the references, for weight: the swings take longer, the tip is slower, and the body turns further. Tip speed is compared in blade lengths per second, because the blades are different lengths: the reference is 4.8 studs from fist to tip, the greatsword 5.6.

| | Reference | This set |
|---|---|---|
| Left fist below the right | 0.3–0.8 studs | 0.62 studs, every frame |
| Forehand torso | −60° → +115° (kareemandbeast m1-1) | −68° → +124° (m1-1) |
| Backhand torso | +85° → −105° (kareemandbeast m1-2) | +86° → −125° (m1-2) |
| Hit timing | ~0.5s into 0.92s | 0.82s into 1.40s |
| Forehand tip speed | 61.5 blade lengths/s (kareemandbeast m1-1) | 29.5 (m1-1, 165 studs/s) |
| Backhand tip speed | 45.2 blade lengths/s (kareemandbeast m1-2) | 26.3 (m1-2, 147 studs/s) |
| Finisher / running / aerial tip speed | 45–61.5 blade lengths/s | 23.9 / 22.9 / 31.6 |
| Draw tip speed | 18.3 blade lengths/s (equip, 88 studs/s) | 11.4 (unsheathe, 64 studs/s) |
| Arm slide out of the shoulder | up to 2.6–2.7 studs | up to 2.4 studs, and 2.9 for the left hand reaching to the far right in the running attack |
| Arm turn / roll speed | up to 2,300–2,800 / 1,000–1,400°/s | capped at 2,200 / 1,300°/s |

**Hit timing:** the `Hit` comes within a frame of the tip's top speed in every strike except the running attack. There it comes 6 frames before the top speed, where the blade, held out at the front right, turns to face the target.

## Smoothness

These clips get the same smoothing pass as the other sets (see `../animkit.py`). The lightest smoothing that halves each clip's angular jerk is applied, and the strike's snap is kept:

| Clip | Smoother by |
|---|---|
| `unsheathe` | 2.52x |
| `m1-1` | 2.05x |
| `m1-2` | 2.02x |
| `m1-3` | 2.09x |
| `running attack` | 4.26x |
| `aerial attack` | 2.07x |

The idle is built directly from smooth breathing waves, so it isn't smoothed.

## Files

- `GreatswordCombo.rbxm` / `GreatswordCombo.rbxmx`: the rig, greatsword, scabbard and clips.
- `previews/key_poses.png`: the key poses of every clip, with the blade tip's path.
- `previews/m1_string.gif`: the string, in real time.
- `previews/unsheathe_idle.gif`: the unsheathe, then one loop of the idle.
- `previews/running_aerial_attacks.gif` / `running_aerial_key_poses.png`: the running and aerial attacks.
- `generate_greatsword.py`: the source for all of the above. It uses `../twohanded.py` and the rig helpers in `../SwordCombo/generate_sword.py`.
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
- **Weight:** `HEAVY_LAG`, and the `heave` and `slam` curves in `../animkit.py`.
- **Arm limits:** `MAX_SWING` and `MAX_TWIST`, in `../twohanded.py`.
