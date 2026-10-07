# Hit sounds: fists and bloody blade hits

22 hit sounds in four kinds, each with several takes, plus a Roblox module that plays a different take every time.

| Kind | Takes | What it is |
|---|---|---|
| `FistHit` | 8 | Punches and kicks, from light jabs (1) to solid crosses (8). A skin slap, the meaty smack in two or three quick contacts, the body's thump, a tick of knuckle and a brush of clothing, in a small room. |
| `FistHeavy` | 4 | Big hits: the same plus a sub boom, a crunch of bone and cartilage, a harder second slap and a bigger room. |
| `BloodySlash` | 6 | Sharp cuts. The blade's edge (a bright tick with a faint metallic ring), the cut opening (a sweeping, tearing slice), a wobbling wet splat, blood (bubbles and splashes thinning out) and the body's thud. |
| `BloodyStab` | 4 | Stabs and gory hits. A shorter slice, a heavier squelch and thud, more blood and a sucking pull-out. |

Listen to them all in order: `preview.ogg`.

## Files

- `ogg/`: the sounds to upload to Roblox (Vorbis, quality 8, 48 kHz mono, peaks at -1 dBFS).
- `wav/`: the 24-bit masters, if you want to edit them.
- `HitSounds.luau` / `HitSounds.rbxmx`: the module.
- `generate_hits.py`: everything is synthesised by this script (Python 3 + numpy, and ffmpeg for the .ogg files). It's seeded, so it rebuilds the same sounds.
- `tests/hitsounds.luau`: the module's tests.

## Using them

1. Upload the `.ogg` files: Creator Dashboard → Development Items → Audio, or Studio's Asset Manager.
2. Put **HitSounds** in ReplicatedStorage. Insert `HitSounds.rbxmx`, or paste `HitSounds.luau` into a ModuleScript. The ability place already has it.
3. Paste the ids into `HitSounds.Ids`, in the order of the files' numbers.
4. Play one from a client: `HitSounds.Play("FistHit", position)`.

```lua
local HitSounds = require(game.ReplicatedStorage.HitSounds)
HitSounds.Play("BloodySlash", victim.HumanoidRootPart)        -- on a part: moves with it
HitSounds.Play("FistHeavy", hitPosition, { Volume = 1.2 })   -- at a point
```

**Variation:**
- Each play picks a take, never the one its kind played last.
- The pitch is nudged up to ±6% (`Spread`) and the volume up to ±10% (`VolumeSpread`). A string of hits never sounds like one sound on repeat.

**Options:**
- `Volume`: times the kind's volume.
- `Pitch`: the playback speed before the nudge.
- `Spread`: overrides the pitch nudge.

**Settings in the module:**
- Each kind's volume (`HitSounds.Volume`).
- The roll-off distances (10 to 160 studs).

**Without ids:** a kind with no ids plays nothing, and `Play` returns nil.

## In the kits

The **Brawler** and the **Melee** kit use it when it's in ReplicatedStorage with ids filled in:

| Kit | Hits | Finishers and heavy hits |
|---|---|---|
| Melee | `FistHit` | the finisher plays `FistHeavy` |
| Brawler | `FistHit` | heavy hits play `FistHeavy` |

Until the ids are in, both kits keep playing their own sounds. The bloody kinds are for blade hits in your own sword combat.

## Not checked

I made these without being able to listen to them. Each one was checked on a spectrogram, for:
- its balance across the bands (the fists sit in the low mids, the cuts in the upper mids);
- its length;
- its peak level.

Tell me what to change: more thump, more crack, wetter, drier, shorter.
