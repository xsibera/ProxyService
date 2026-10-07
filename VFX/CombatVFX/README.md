# Combat VFX pack

Basic combat effects: hits, a ground slam, dashing and movement. They're **realistic wind**: everything is moving air, smoke and dust, with no flashes, stars, glows or lights.
- **Faint air:** the air layers are as faint as your own wind layers in `VFXFORCLAUDE.rbxm` / `nen.rbxm`, peaking at 15–55% opacity in greys, and they stack up to give the shape.
- **Your textures:** every layer is built from one of your emitters, picked by texture, so each texture keeps its flipbook and look. Each layer is then resized, re-timed, re-aimed and recoloured.

`CombatVFX.rbxm` is a ModuleScript called **CombatVFX** with the effects inside it, in `CombatVFX/Effects`. Put it in ReplicatedStorage.

| Effect | What it is | Place it at | Layers | Lasts |
|---|---|---|---|---|
| `M1Hit` | A puff of air through the target: wind burst, swirls, pressure ring, wind arcs, air streaks and a little dust | The victim's torso, facing along the hit | 6 | 0.6s |
| `M1Final` | A bigger blast of air, plus a smoke puff out the far side and a dust ring on the floor | The same | 12 | 1s |
| `HeavyHit` | A cone of wind in three waves, spinning wind, pressure waves, and smoke that hangs, plus wind and dust across the floor | The same | 19 | 1.6s |
| `GroundSlam` | Air blasting out flat across the floor, a radial wall of smoke, billows, dirt and rocks, cracks, and dust that hangs | The floor point | 20 | 4s |
| `DashBurst` | A gust tearing off behind the body, and a ring of wind and dust under the feet | The HumanoidRootPart, facing the dash | 9 | 0.9s |
| `DashTrail` | Wind arcs and air streaks off the body, dust off the feet (continuous) | `Start` on the HumanoidRootPart | 3 | until `Stop` |
| `Footstep` | A small puff and grains | The foot's floor point, facing the run | 3 | 0.6s |
| `Land` | A ring of air and a swirl, and dust blown out to both sides | The floor point under the character | 6 | 0.9s |
| `Jump` | A ring of air and a swirl under the feet, and a puff of dust | The floor point under the character | 3 | 0.6s |
| `SlideDust` | A dust and grit spray (continuous) | `Start` on the HumanoidRootPart | 3 | until `Stop` |
| `RunDust` | A light dust trail (continuous) | `Start` on the HumanoidRootPart | 1 | until `Stop` |

Pass `Color` to tint the wind (the **Accent** layers) for elemental or nen moves. Without it, the wind stays white and grey.

## Using it

```lua
local CombatVFX = require(game.ReplicatedStorage.CombatVFX)

-- a hit: at the victim, LookVector = the direction the hit travels
local at = victimRoot.Position
CombatVFX.Play("M1Hit", CFrame.lookAt(at, at + attackerRoot.CFrame.LookVector),
	{ Ignore = { attacker, victim } })

-- last hit of the string, in the move's colour
CombatVFX.Play("M1Final", CFrame.lookAt(at, at + dir), { Ignore = { attacker, victim }, Color = Color3.fromRGB(133, 255, 231) })

-- slam: at the floor point
CombatVFX.Play("GroundSlam", CFrame.new(floorPosition), { Ignore = { attacker } })

-- dash: a burst at the start, a trail while it lasts
CombatVFX.Play("DashBurst", CFrame.lookAt(root.Position, root.Position + dashDirection), { Ignore = { character } })
local trail = CombatVFX.Start("DashTrail", root)
task.delay(dashTime, function() trail:Stop() end)

-- movement
CombatVFX.Play("Land", CFrame.new(root.Position - Vector3.new(0, 3, 0)), { Scale = math.clamp(fallSpeed / 60, 0.6, 1.6) })
local slide = CombatVFX.Start("SlideDust", root) -- slide:Stop() when the slide ends
```

`Play(name, cframe, options)` returns the holder part, which cleans itself up once the last particle dies. `Start(name, part, options)` returns a handle with `:Stop()`. Options are all optional:
- **`Color`:** the move's colour, applied to the wind (Accent) layers.
- **`Scale`:** scales sizes, speeds and offsets. Use it for bigger characters or heavier landings.
- **`Ignore`:** instances the floor raycast skips. Pass the characters involved. Players' characters are always skipped.
- **`Parent`:** where one-shot holders go. The default is workspace.

Play effects on the client for the best feel. Fire a remote event and have every client call `Play`.

### How the effects behave

- **Emit attributes:** bursts use the same attributes as your existing VFX (`EmitCount`, `EmitDelay`, `EmitDuration`), so your own emit code can play these too.
- **Ground layers:** dust, rocks, cracks and floor rings sit in a `Ground` attachment. `Play` drops it onto the floor under the effect and tilts it to the slope.
  - `GroundOnly` layers are skipped when there's no floor within 14 studs, e.g. a hit in mid-air.
  - `UseGroundColor` layers are tinted 60% toward the floor's colour, so dust on grass reads green and dust on sand reads tan.
- **Continuous effects** follow the floor under the part every frame, and switch their ground layers off in the air.

## What your files use (measured)

The pack uses your wind, air, smoke and dust layers. Your files also have bright flash, star and eruption layers, which give the anime look, and the pack leaves those out.

About 600 emitters across Jajanken, BigBang, CrazySlots, Swordsmans Slash, Disrupt, SweepKick and the nen auras.

**Structure.** An effect is many single-purpose burst emitters: 25–100 on a big move, about 10 on a small one.
- **Firing:** they're disabled and fired with `EmitCount` (usually 1–5, up to 16 for debris) and `EmitDelay` (almost always 0).
- **Timing:** everything lands on the same frame, and the timing comes from the lifetimes.
- **Look:** most textures are 4×4 one-shot flipbooks, and sizes grow from 0.

**Layers of an impact, front to back:**
1. **Flash.** Camera-facing, 0.03–0.15s, Brightness 10–65, ZOffset 1–11 so it draws on top. It often shrinks from full size to 0.
2. **Contrast frame.** A black, flat layer under the flash, the anime "black flash" look, sometimes with negative LightEmission.
3. **Shockwave rings.** Flat (velocity-perpendicular), grow from 0 to 12–30 studs in 0.1–0.35s, LightEmission 1, grey or white. One ring often lingers about 1s.
4. **Wind and crescents.** Flat on the ground or along the hit, spinning 50–4,600°/s, 0.1–1.3s, grey (7e7e7e / 848484).
5. **Streaks and shards.** Velocity-parallel, fired at 70–1,000 studs/s with drag 15–44 so they stop dead. Squash stretches them.
6. **Eruptions.** Camera-up flipbooks thrown out at 75–200 studs/s.
7. **Debris.** The rock texture (626588936), 0.1–0.4 studs, gravity -18 to -74, spinning. Plus dirt chunks.
8. **Smoke.** Bursts out at 50–130 studs/s with drag 10–16, so it forms a ring that hangs. Darker dust lingers 2–5s.
9. **Floor marks.** Cracks and scorches lie flat for 1–4s.

**Colour.** One accent per move (Jajanken orange `ff5725`, BigBang red `ff1d1d` / `760f0f`) on the flashes, eruptions and glows. Everything else is white, grey and black.

**Scale.** A move-sized hit is 4–10 studs. A finisher or ground slam is 20–33 studs, with smoke out to 50.

**Auras (nen), for later.**
- **Emitters:** continuous (not bursts), locked to the body, firing 2–60 a second.
- **Look:** cyan `85ffe7`, LightEmission 1.5 and Brightness 8, layered 4×4 energy flipbooks, rising line streaks, and four scrolling beams on Ken.
- **Light:** a white PointLight with range 7.

## Files

- `CombatVFX.rbxm` / `.rbxmx`: the module and its effects.
- `CombatVFX.luau`: the module source. It's also embedded in the rbxm.
- `generate_vfx.py`: builds the rbxmx from your reference file. Each effect is a list of layers, with a reference emitter and the changes to it.
- `tests/smoke.luau`: a headless test of the module against Place1's mock engine. Run it with `luaurun tests/smoke.luau` from this folder.

```bash
python3 generate_vfx.py path/to/nen.rbxmx   # nen.rbxm converted to XML
```

The particle textures can't be downloaded in this environment, so the effects were tuned from your emitters' settings, not by looking at them. Check them in Studio and tell me what to change. Every value is one line in `generate_vfx.py`.
