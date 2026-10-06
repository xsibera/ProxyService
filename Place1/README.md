# Place1: R6 fist combat, parry and movement

A complete R6 fist-fighting system for Roblox with:
- a 4-hit punch combo, a charged heavy, block, parry and posture/guard break
- sprinting, sliding and dodging
- procedural high-framerate animations, layered VFX and SFX
- a training ground with five test dummies

## Open it

**Option A, just play it:** open `Place1.rbxlx` in Roblox Studio and press **Play**.

**Option B, sync into an existing place:**
1. Install [Rojo](https://rojo.space) and its Studio plugin.
2. Run `rojo serve` in this folder.
3. Click **Connect** in the plugin. Rojo copies the scripts, the arena, the dummies and the lighting into whatever place you have open.

If you copy the scripts into another place by hand, also set **Avatar Settings → Avatar Type → R6**. The server rebuilds any non-R6 character as R6 anyway, but the setting is cleaner.

## Controls

| Input | Action |
|---|---|
| **LMB** (hold to chain) | Punch: jab, cross, hook, then an uppercut finisher that knocks the target back |
| **F** | Block. Pressing it right before a hit lands is a **Parry**: the attacker is stunned and wide open |
| **R** | Heavy: a charged haymaker that breaks blocks but can be parried |
| **Q** | Dodge with i-frames. WASD picks the direction (no input = backstep). It can cancel the end of a punch |
| **W W** / hold **Ctrl** | Sprint |
| **C** (while sprinting) | Slide. Speeds up downhill and steers with WASD. Jump out of it to keep the speed |
| **H** | Show/hide the controls panel |

Gamepad: R2 punch, L2 block, Y heavy, B dodge, X slide, L3 sprint. Phones and tablets get on-screen buttons automatically.

### The combat triangle
- **Punches** beat heavies, because they're faster.
- **Block** beats punches, at the cost of posture.
- **Heavy** beats block (guard break).
- **Parry** beats everything if your timing is right.

Blocking only covers your front. Every blocked hit drains **posture**, and empty posture means a guard break. Posture refills after a short break.

Mashing block doesn't work. Re-pressing within 0.7s of a missed parry gives a plain block. A successful parry never locks you out.

## Test dummies

| Dummy | What it does | What to practise |
|---|---|---|
| **Punching Bag** (grey) | Stands still | Combos, heavies, hit feel |
| **Blocker** (blue) | Always blocks | Posture damage, guard breaking with R |
| **Parrier** (gold) | Parries about 85% of attacks | What getting parried feels like; baiting |
| **Attacker** (red) | Chases you and throws combos and heavies | Blocking and parry timing |
| **Sparring Partner** (purple) | Blocks, parries, dodges and counter-attacks | Everything |

Dummies respawn 3 seconds after dying and start healing after 4 seconds without being hit.

To add more, duplicate any model in `Workspace.Dummies` and set its `DummyType` attribute (`Bag`, `Blocker`, `Parrier`, `Attacker`, `Sparring`) and `DisplayName`.

The map also has a **movement course** to the east, with a runway and a slide hill. To the west there are **landing steps** for testing fall and landing animations.

## Sounds (toolbox IDs)

Every sound lives in `ReplicatedStorage.Combat.SoundIds`. Paste Creator Store / toolbox audio IDs into an entry's `Ids` list:

```lua
Parry = {
	Ids = { "rbxassetid://1234567890", "rbxassetid://2345678901" }, -- one is picked at random
	Volume = 1,
	Pitch = { 0.98, 1.06 },
	...
},
```

With no IDs (or if an ID fails to load), the sound plays its `Fallback` instead. Fallbacks are layered, pitched and EQ'd built-in engine sounds, so nothing is ever silent.

Sound names:
- `Swing`, `SwingHeavy`
- `Hit`, `HitFinisher`, `HitHeavy`
- `Block`, `Parry`, `GuardBreak`, `HeavyCharge`
- `Dodge`, `SlideStart`, `SlideLoop`, `Land`, `BodySlam`, `SprintWind`

## Tuning

Everything is in `ReplicatedStorage.Combat.Config`:
- damage, windups, stun and knockback per punch
- parry window and cooldown, posture
- sprint speed and FOV, slide friction and slope gravity, dodge speed and i-frames
- hitstop durations and dummy behaviour

Set `Config.Debug.ShowHitboxes = true` to see the server's hitboxes.

## How it works

- **Server-authoritative combat** (`ServerScriptService.CombatServer.CombatService`):
  - Players and dummies share one state machine.
  - The client only *requests* actions. The server checks timing and state, runs the hitboxes and resolves each hit in order: dodge i-frames, then parry, then guard break, then block, then a clean hit.
  - It replicates the result as `CombatState` and `Posture` attributes, plus FX events.
  - Requests that arrive slightly early (lag) are queued rather than dropped.
- **Client prediction** (`CombatController`):
  - Your punch animation, swing sound and lunge start the instant you press.
  - The server echoes each action with a sequence number. The client corrects the combo index if they disagree, and rolls back on a reject.
- **Procedural animation** (`ReplicatedStorage.Combat.ProceduralAnimator`):
  - No uploaded animation assets are needed. Every client poses every R6 character by writing `Motor6D.Transform` each frame, so animation runs at the display's full framerate.
  - Keyframes use easing curves. Walk and run cycles advance with the distance actually travelled, so feet don't skate.
  - Characters lean into acceleration, bank into turns, and turn their legs toward the travel direction when strafing or backpedalling.
  - Clips blend with fades and an upper-body mask while moving. Hits get hitstop and impact shake.
  - Foot planting stops rigid R6 legs sinking into the floor.
  - Roblox's default Animate script is replaced by an empty one, so the procedural animator is the only thing driving the joints.
- **VFX** (`ReplicatedStorage.Combat.VFX`):
  - Hits: impact flashes, expanding shockwave rings, anime impact stars, spark streaks, a hit highlight, light flashes and damage numbers.
  - Characters: fist trails, the heavy charge orb, dodge afterimages, slide dust and sparks, landing dust rings.
  - Guard breaks: glass shards. Stuns: dizzy stars.
  - It only uses textures that ship with the client, so nothing needs uploading.
- **Camera** (`CameraFX`): trauma-based shake that never drifts the camera, FOV kicks, sprint FOV, colour flashes, blur pulses and anime speed lines.

## Project layout

```
Place1/
  Place1.rbxlx                 built place, open this in Studio
  default.project.json         Rojo project
  build.sh                     rebuilds Place1.rbxlx
  src/
    ReplicatedStorage/Combat/  Config, SoundIds, AnimationData, ProceduralAnimator, VFX, SFX, Util
    ServerScriptService/CombatServer/  CombatService, DummyAI, CharacterSetup
    StarterPlayer/StarterPlayerScripts/CombatClient/  CombatController, MovementController,
                                                      FXHandler, CameraFX, HUD
    StarterPlayer/StarterCharacterScripts/Animate      (empty on purpose, see above)
    Workspace/                 arena + dummies (generated by tools/build_world.py)
  tools/
    build_animations.py        animation source; solves fist IK and writes AnimationData.luau
    preview_poses.py           renders keyframes to PNG (same joint maths as the game)
    build_world.py             generates the arena and dummy rigs
    check_api.py               checks every property/enum/class used against Roblox's API dump
    strip_rojo_attrs.py        cleans Rojo helper attributes out of the built place
  tests/
    mock.luau                  tiny fake Roblox engine
    run.luau                   animator + server combat rule tests
    client_smoke.luau          boots the client, presses buttons, feeds server events
```

## Development

```bash
./build.sh                       # regenerate world + build Place1.rbxlx
./build.sh --anims               # also regenerate AnimationData.luau (needs numpy)
python3 tools/preview_poses.py Jab --out previews    # look at a clip's keyframes
python3 tools/check_api.py       # API sanity check (downloads the API dump)
stylua src && selene src         # format + lint (selene needs `selene generate-roblox-std` once)
luaurun tests/run.luau && luaurun tests/client_smoke.luau
```

`luaurun` is a minimal Luau VM with a `loadfile` global (`tests/luaurun.cpp`). To build it, compile that file together with the Ast, Compiler, Bytecode, Common and VM sources from [Luau](https://github.com/luau-lang/luau):

```bash
L=path/to/luau
g++ -O1 -std=c++17 -I$L/Common/include -I$L/Ast/include -I$L/Compiler/include -I$L/Bytecode/include \
    -I$L/VM/include -I$L/VM/src $L/{Ast,Compiler,Bytecode,Common,VM}/src/*.cpp tests/luaurun.cpp -o luaurun
```
