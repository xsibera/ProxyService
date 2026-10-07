# R6 fist M1 combo (5 hits)

These five M1 animations are built to match the style of the reference animations in `ANIMSFORCLAUDE.rbxm`.

| Clip | Move | Length | Hit marker |
|---|---|---|---|
| `m1-1` | Lead jab (left hand), short coil, fastest whip | 0.83s | 0.33s |
| `m1-2` | Rear overhand (right hand), chambers above the head, drops over the top | 0.83s | 0.40s |
| `m1-3` | Lead hook (left hand), wide flat arc, body tilts into it | 0.83s | 0.40s |
| `m1-4` | Rear uppercut (right hand), sinks low, then explodes up and back | 0.83s | 0.42s |
| `m1-5` | Finisher: spinning backfist (right hand), 330° pirouette, lands side-on and holds | 1.00s | 0.65s |

All five are R6, Priority **Action**, not looped, and baked at 60 fps with Linear easing, exactly like the references. The legs are keyed at **Weight 0**, as in the reference M1s, so your walk and idle keep driving them. Each clip has a `Hit` KeyframeMarker on its impact frame:

```lua
track:GetMarkerReachedSignal("Hit"):Connect(function() ... end)
```

## Files

- `FistCombo.rbxm`: the reference "normal player" rig, renamed **Fist Combo Rig**, with the five KeyframeSequences in `AnimSaves`.
- `FistCombo.rbxmx`: the same thing in XML.
- `previews/key_poses.png`: start, coil, load, impact, overshoot and held pose for every hit.
- `previews/compare_realtime.gif`: the reference fist m1-1 next to all five hits, in real time.
- `previews/combo_chain.gif`: the full combo chained with the Animator's 0.1s crossfades, then fading back to idle.
- `generate_combo.py`: the source that bakes all of the above.
- `style_profiles.json`: curves measured from the reference.

## Using it

1. In Studio, right-click Workspace → **Insert from File…** → `FistCombo.rbxm`.
2. Select **Fist Combo Rig** and open the **Animation Editor**. The clips are under *Load* (`m1-1` … `m1-5`).
3. Publish each clip (**… → Publish to Roblox**) and put the IDs in your M1 handler. Each hit is meant to be cancelled into the next one, usually 0.45–0.6s after it starts. The final pose is held until the clip ends, the same as the references.

## What the reference style is (measured, not guessed)

**Baked data.** Every frame is a keyframe at 60 fps with Linear/Out easing. So the curves are hand-shaped, not eased between a few keys.

**Upper body only.** M1s key the torso (RootJoint), the neck and both shoulders. The legs are present at Weight 0, or not keyed at all.

**Rhythm.** Every reference M1 has the same speed profile:
1. **Counter-move.** In the first 4 frames the punching arm nudges forward about 25% before it chambers.
2. **Coil.** About 13 frames of smooth ease-in-out. The torso winds 60–110° the "wrong" way, and the punching arm is pulled out of its socket by up to 1 stud (back and up).
3. **Loaded slow-in.** About 7 frames where the torso has started to unwind (0.1% → 23% of the whip) while both arms keep cocking further.
4. **Whip.** 3–5 frames. The torso swings 140–230° in total, up to about 2,100°/s. The punching arm accelerates *through* the impact, gets pushed about 0.6 studs past the shoulder toward the target, and the off hand yanks back to the hip.
5. **Overshoot.** The torso and the punching arm go past the target pose. In the fist M1 the arm swings 77% past its strike range, then snaps back.
6. **Settle and drift.** An ease back of 10–15°, then a slow drift while the final silhouette is held until the clip ends. There's no return to idle; the crossfade does that.

**Side-on silhouettes.** A straight punch ends with the torso turned about 90–105° side-on and the punching arm abducted about 95°. The arm sticks straight out of the side of the torso, toward the target. The fist travels a big circular arc to get there.

**Head.** The neck counter-rotates at about -0.95× the torso yaw (capped at about ±71°), so the eyes stay on the target. It trails the torso slightly during the whip (about 0.77×), tucks down 15–18° at impact, and tilts against the torso roll.

**Body.** The root dips 0.2–0.3 studs (much lower on big moves). It leans back and tilts during the coil, then leans forward 12–19° and flips its tilt on the strike. It shifts back about 0.35 studs on the coil and forward about 0.25–0.4 on the hit.

The combo uses those exact curves (coil, whip, settle, drift, plus slices of the whip for the slow-in, snap and stop, and the measured arm-strike curve). Its joint speeds land in the reference range:

| Joint | Reference (°/s) | This combo (°/s) |
|---|---|---|
| Torso | 1,600–2,100 | 1,860–2,530 |
| Head | 1,200–1,700 | 1,600–2,500 |
| Arms | 1,500–2,800 | 1,200–2,200 |

## Changing it

Edit the key poses in `generate_combo.py`, then run:

```bash
python3 generate_combo.py path/to/ANIMSFORCLAUDE.rbxmx
```

Each key is `(frame, [pitch, yaw, roll, x, y, z], curve_into_this_key)` in the joint's parent space:
- **Torso:** +yaw turns left, +pitch leans back.
- **Arms:** +pitch swings forward, roll ±90 raises the arm out to the side.

Converting the generated `.rbxmx` to `.rbxm` uses the `rbx_binary` / `rbx_xml` crates. Studio can also insert the `.rbxmx` directly.
