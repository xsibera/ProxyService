# Jajanken: Gon Freecss's Hatsu

Gon's Jajanken from Hunter x Hunter as a working Roblox ability, with animations, effects and scripts. To cast, hold a key to gather aura into the fist, then let go:

| Key | Mode | What it does |
|---|---|---|
| **Z** | Rock (グー) | A lunging punch that sets off the aura in the fist. Close range, heavy, big knockback. |
| **X** | Paper (パー) | An open-palm thrust that throws the aura as a ball, which explodes on whatever it hits. Ranged, with blast damage. |
| **C** | Scissors (チー) | Two fingers become a blade of aura, swept flat across the front. Wide and fast. |

**Charging:** tap the key for a quick cast, or hold it for up to **3 seconds** for full power. Letting go at any point casts it, and at full charge it casts by itself. Damage, knockback, hitbox size, the ball's speed, range and blast, and the effects all scale with how long you held it. While you hold, Gon chants "Saisho wa guu… Jan… Ken…" over a charge bar, then shouts GUU! / PAA! / CHII! on release.

Gamepad uses X / Y / B. Touch devices get on-screen buttons. In the ability place, the keys are the hotbar's slots: press **M** and pick the **Gon** preset (Rock, Paper, Scissors on Z, X, C), or put any of them on any key (see [Loadout](../Loadout/README.md)).

**In a parry-style fight** (when the place has [the parry system](../Combat/README.md), as the ability place does):
- Every Jajanken hit can be **blocked** (F) or **parried** (tap F just before it lands, and Gon staggers).
- A **fully charged Rock breaks a guard** outright.
- The longer the charge, the longer the stun on a clean hit.
- Getting hit while charging cuts the charge short.
- You can't charge while blocking or stunned.

## Files

- **`Jajanken.rbxl`**: the ability place. Open it in Studio and press **Play**. It contains:
  - **M1s on left click** ([Melee](../Melee/README.md)): a five-hit stun string;
  - Gon's Jajanken;
  - **Killua's lightning** ([Killua](../Killua/README.md));
  - the **parry system** (F to block, tap F to parry);
  - the **ability menu** (M) and hotbar.

  You start with Killua's abilities: press M and pick the Gon preset for Jajanken, or mix them. It also has **sprinting** (hold Left Ctrl or double-tap W) and **rolling** (Q), see [Movement](../Movement/README.md).

  The map is **Whale Island** ([Village](../Village/README.md)), a small HxH-style village:
  - you spawn in the plaza;
  - east down the yard road is the **training yard**, with the plain dummies and the parry system's Blocking, Parrying and Sparring dummies, plus the animation rigs;
  - through the village gate and up the forest path, **bandits** guard their camp and fight you with the same M1 stun system.

  Every hit shows its damage (and BLOCKED, COUNTER, EVADED).
- **`Jajanken.rbxm`**: the same ability as a kit for your own game. It's one folder of labelled folders, each named for where its contents go:

  | Folder in the kit | Put it in |
  |---|---|
  | `1. Put the Jajanken folder in ReplicatedStorage` | `Jajanken` (Config, JajankenVFX + effects + sounds, Animations, Remote) → **ReplicatedStorage** |
  | `2. Put JajankenServer in ServerScriptService` | `JajankenServer` → **ServerScriptService** |
  | `3. Put JajankenClient in StarterPlayer - StarterPlayerScripts` | `JajankenClient` → **StarterPlayer › StarterPlayerScripts** |
  | `4. Optional - Workspace` | the animation rig (for publishing) and a test dummy |
  | `5. Optional - the parry system (Combat)` | `Combat` → ReplicatedStorage, `CombatServer` → ServerScriptService, `CombatClient` → StarterPlayerScripts |
  | `6. Optional - the ability menu (Loadout)` | `Loadout` → ReplicatedStorage, `LoadoutServer` → ServerScriptService, `LoadoutClient` → StarterPlayerScripts |

  The kit also has a `READ ME` script with the same instructions. Your game needs **R6** avatars (Game Settings › Avatar).

### Before a live game: publish the animations

The animations are KeyframeSequences, and unpublished animations only play in Studio. To publish them:
1. Open **Jajanken Animation Rig** in the Animation Editor.
2. Load each of `Jajanken Charge`, `Hold`, `Rock`, `Paper` and `Scissors` and publish it.
3. Paste the ids into `Jajanken › Config › Config.Animations`.

The client registers the KeyframeSequences itself while you test in Studio. It warns once if it can't.

## Settings (`Jajanken › Config`)

Everything is a `{ tapped, fully charged }` pair, so a value in between is used for a part charge.

| | Rock | Paper | Scissors |
|---|---|---|---|
| Damage | 12 → 45 | 10 → 38 (direct). The blast falls off to half at its edge. | 9 → 32 |
| Knockback (studs/s) | 35 → 95 | 25 → 80 | 15 → 40 |
| Reach | box 5×5×6 → 9×8×10 in front | flies at 75 → 120 studs/s, out to 70 → 140 studs, blast radius 7 → 15 | box 10×5×7 → 16×6×12, wide |
| Cooldown | 4s | 5s | 3.5s |

Global settings:
- `MaxCharge` (3s).
- `ChargeWalkSpeed`: 8 while charging and casting (the animations leave the legs to the walk); set it to 0 to root Gon in place.
- `CanJumpWhileCharging`.
- `SharedCooldown`: 0.8s between any two casts.
- `HitPlayers` and `TeamCheck`.
- Paper's `AimWithCamera`: it's thrown where the camera looks, within 70° of the facing.
- The keys.
- `Chant`.

Each `HitDelay` is the time from the release to the hit. It must match the animation's `Hit` marker (Rock 24/60s, Paper 22/60s, Scissors 20/60s), and the generator checks that it does.

## How it works

The server owns everything that matters:
- **Charge:** measured from when the server hears the key go down to when it hears it come up, so a client can't fake a full charge.
- **At 3s:** the server casts it by itself.
- **Checks and hits:** it checks cooldowns, runs the hitboxes and the Paper ball (spherecast every frame), and deals the damage and knockback.

The client asks with `Charge` and `Release`, plays the animations, and draws:
- **Your own charge:** your aura and charge bar show the instant you press.
- **Everyone else's:** other players' charges, casts, hits and the ball come from the server's broadcasts.
- **Timing:** they're timed with `workspace:GetServerTimeNow()`, so the ball flies along the server's line on every screen.

With the parry system in the place, every hit goes through `Combat.resolve` instead (block, parry, guard, stun), and each cast is announced to it (`Combat.announce`). With the menu, only equipped modes can be cast. Both are optional: without them it plays exactly as before.

Other server scripts can react to hits, for stun, combos, quests and so on:

```lua
game.ServerScriptService.JajankenServer:WaitForChild("OnHit").Event:Connect(function(attacker, victim, mode, damage, charge)
end)
```

Knockback is a short `LinearVelocity` on the victim's HumanoidRootPart. That pushes players too, not just NPCs, because it replicates to whoever owns their physics.

## Animations (R6, 60 fps, legs keyed)

These follow what Gon does in the anime, in the style of your reference animations: your fist M1s and your `abilities` rig (nen burst, ice downslam, leg axe).

1. **"Saisho wa guu!":** he hunches down, turns his body away from the target, and presses his right fist into his open left palm while the aura gathers in it. That's the charge pose, held while charging.
2. **"Jan… Ken…":** the fist leaves the palm and draws back as he winds further away.
3. **The release:**
   - **"Guu!":** a lunging straight right.
   - **"Paa!":** a palm thrust that throws the ball.
   - **"Chii!":** a two-finger blade swept across the front.

Motion previews of the full casts are in `previews/rock_full_cast.gif`, `paper_full_cast.gif` and `scissors_full_cast.gif`.

![stance and rock](previews/stance_and_rock.png)
![paper and scissors](previews/paper_and_scissors.png)

| Clip | Length | What it is |
|---|---|---|
| `Jajanken Charge` | 0.45s | A counter-move up and back, then a hop out into the squat as he turns away. The left palm comes up and the right fist smacks down into it, and the body sinks past the squat before settling. |
| `Jajanken Hold` | 1.2s loop | Breathing in the squat: the shoulders rise and the body hunches over the hands, while the fist grinds and trembles in the palm. |
| `Jajanken Rock` | 0.95s | The fist pops off the palm and draws back past the hip as he winds 110° away and sinks ("Jan… Ken…"), with the left hand out at the target. He holds it loaded, then drives up and forward out of the squat: the torso whips round, the right fist rips straight out and the left hand is yanked to the hip. The rear foot is dragged in behind the drive. **Hit** is at 0.4s, and the punch stays out and drifts. |
| `Jajanken Paper` | 0.9s | The same wind-up with the hand open by the hip, then the open palm is driven straight out at the target. The ball leaves the palm on **Hit** (0.367s), and its kick knocks the arm and body back before he settles behind the palm. |
| `Jajanken Scissors` | 0.9s | The fist pops off the palm and the hand swings up and out wide to the right as he winds away and rises. The torso then whips about 200° round, sweeping the two-finger blade flat across the front from right to left and on round to the left, with the left arm thrown back for balance. **Hit** is at 0.333s, as the blade crosses the front. |

**How they're built (the reference rhythm):**
- **The beats:** counter-move → coil (the torso winds 40–50° further away and the arm chambers out of its socket) → loaded slow-in → a 4-frame whip (the torso swings 140–200° and the strike shoots out) → overshoot → settle → a slow drift on the held pose.
- **Curves:** the coil, whip, settle and drift curves are the ones measured from your reference animations.
- **Head:** it counter-turns so the eyes stay on the target, and tucks at the hit.
- **Scale:** the torso turns as far as your ability animations do, and arms slide up to 1 stud out of the socket for reach.
- **Legs:** every clip keys them at **Weight 0**, so the walk drives them and you can walk while charging (`ChargeWalkSpeed`, 8 by default). That's also why the body only drops about 0.35 studs, as your M1s do: any lower and the walking legs would sink into the floor. (`anims.py` can still key planted legs and a deep squat: set `LEGS_FREE = False`.)
- **Smoothing:** angular jerk is cut 2.1–2.3×, like the M1s.

Every release starts on the exact squat pose, so it cuts in from the hold at any frame. The `HitDelay` values in Config are the Hit markers (Rock 24/60s, Paper 22/60s, Scissors 20/60s), and the build fails if they ever drift apart.

The rig's AnimSaves also has a **full-cast preview** per mode (charge → 1s hold → release) to watch in the Animation Editor.

## Effects

They're built from your game's own emitters (`nen.rbxm`):
- **Jajanken:** the RockRA fist fire, PaperProjectile orb and ScissorsSlash crescents, plus the RockHit, PaperHit and ScissorsCast sounds.
- **The nen auras:** Ken and Ren.
- **The realistic wind pack:** for the physical side.

The aura is gold-orange nen, in the game's Jajanken orange. The hits are the nen going off, with the physical side done the realistic way: wind, pressure rings, smoke, dust, rocks and cracks. There are no star bursts, flash frames or black contrast frames.

| Effect | When | What |
|---|---|---|
| `Aura` | while charging, on the body | Nen rising off the body, a swirl of aura and smoke at the feet and dust blown out across the floor. Power lines come in at 35% charge, a second layer at 70%, and pebbles lift off the floor at 45%. It thickens and brightens with the charge. |
| `HandCharge` | while charging, at the fist | The RockRA fire round a white core and its glow, growing with the charge. It's the same for all three modes: as in the anime, you can't tell which one is coming until the release. |
| `Release` | on letting go | The aura flares off the body, and a ring of air and dust is pushed out across the floor. |
| `RockBlast` | Rock's hit, at the fist | The nen detonates forward. Wind bursts, a spinning gust, pressure rings and streaks blast out, with a cone of smoke that hangs. On the floor: wind, a wall of dust, rocks (30%+) and cracks (60%+). |
| `PaperBall` | in flight | The PaperProjectile orb, trailing air streaks and thin smoke. |
| `PaperBlast` | where the ball bursts | The nen goes off in every direction, with wind, rings, streaks and smoke. On the floor: dust, rocks and a scorch at 50%+. |
| `ScissorsSlash` | Scissors' hit | Your ScissorsSlash crescents and wind arcs lying flat across the front, a wind crescent and air streaks. |
| `NenHit` | on each victim | A small burst of nen through them, a puff of air, a ring, streaks and dust. |

`JajankenVFX` plays them:
- `Play` is for bursts.
- `Attach` is for charging effects, with `:SetCharge(0..1)` and `:Stop()`.
- `Projectile` is for the ball.
- `Sound` plays the sounds.

The emitter attributes are the same as in CombatVFX, plus `MinCharge`, `Grow` and `RateGrow` for charging.

The textures can't be downloaded here, so the effects were tuned from your emitters' settings, not by looking at them. Check them in Studio and tell me what to change. Every layer is one line in `effects.py`.
- The Scissors crescents keep the rotation they had in your ScissorsSlash. If the cut curves the wrong way, flip the `Rotation` on `Effects › ScissorsSlash`'s Slash layers.

## Files and rebuilding

- `anims.py`: the five animations, built with `Animations/animkit.py`.
- `effects.py`: the effects, built with `VFX/CombatVFX/generate_vfx.py`'s layer builder.
- `generate_jajanken.py`: puts it all together.
- `src/`: the scripts:
  - `Config.luau`
  - `JajankenVFX.luau`
  - `JajankenServer.server.luau`
  - `JajankenClient.client.luau`
- `place.project.json` + `build.sh`: build the ability place with Rojo, from every package's folder:
  - Melee, Movement, Killua, Combat and Loadout;
  - the effects pack;
  - the village (`../Village`), whose scripts are the dummies' and bandits' brains and the damage numbers.

  `build.sh` builds those too, and the kits: `Jajanken.rbxm`, `../Killua/Killua.rbxm`, `../Melee/Melee.rbxm` and `../Movement/Movement.rbxm`.

```bash
./build.sh path/to/ANIMSFORCLAUDE.rbxmx path/to/nen.rbxmx path/to/rbxconv   # rbxconv: any rbx-dom rbxmx -> rbxm converter
```

There are headless tests against Place1's mock engine (`luaurun`, see `Place1/README.md`). Run them from this folder:
- `luaurun tests/server.luau`, 45 checks:
  - tap, half and full charge damage;
  - the auto-cast at 3s;
  - cooldowns;
  - Rock's reach against Scissors' width;
  - the Paper ball hitting a dummy, a wall and its range, and its aim (including NaN aims);
  - death, bad input, teams and leaving.
- `luaurun tests/client.luau`, 62 checks:
  - the keys, the Studio animation registration and the animations played;
  - the aura building with the charge;
  - the bar and chant, release and auto-release;
  - every server event drawn with the real effect tree: other players' charges, the ball's flight, bursts, hits and denials;
  - dying mid-charge.
- `luaurun tests/combat.luau`, 22 checks, with the parry system and the menu:
  - casts announced, and busy while they play out;
  - blocked, parried, and a full Rock breaking a guard;
  - a stun cutting a charge short;
  - no charging while blocking or stunned;
  - only equipped modes.
The training dummies' tests moved to `../Village` with the map.
