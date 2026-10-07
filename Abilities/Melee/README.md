# Melee: the M1 stun system

A basic stun fighting system: a five-hit fist M1 string on left click.

| Hit | Move | Damage | Stun |
|---|---|---|---|
| 1 | Lead jab | 4 | 0.75s |
| 2 | Rear overhand | 4 | 0.75s |
| 3 | Lead hook | 4 | 0.75s |
| 4 | Uppercut | 4 | 1.0s |
| 5 | Spinning backfist: the finisher. It knocks the target away and ends the string. | 6 | 0.9s, knocked back |

**The stun is what makes it a combo.** Each hit stuns the target for longer than the gap to the next one, so if you keep clicking in time the whole string lands and they can't act, block or get out in between. The server test checks this frame by frame. Being stunned means:
- no attacks and no blocking;
- walking at 3;
- the hit reaction plays.

**Timing:**
- **Clicking:** click to throw the next hit, or hold the button and the string keeps going. A click up to 0.35s early is remembered and thrown the moment the next hit opens.
- **Starting over:** wait more than 0.6s past the point where the next hit could go, and the string starts over from the jab.
- **After the finisher:** a 1.15s wait before a new string.
- **While swinging:** you walk at 10 and step in a little on each hit. You can't block or use an ability until the next hit could be thrown.

**It plays with the rest of the fighting:**
- A target holding **F** blocks the hits from the front: they take chip damage and lose guard.
- Tapping F just before a hit lands **parries** it: you stagger and your string ends.
- Getting hit mid-swing cancels the swing.
- M1s cancel into abilities once the next hit could be thrown, so you can go from a string straight into Lightning Palm or a Rock.

Gamepad uses R2. Touch devices get a **Punch** button.

## Effects

They're from the combat effects pack (`VFX/CombatVFX`), which goes in **ReplicatedStorage** as `CombatVFX` (it's in the kit):

| Effect | When |
|---|---|
| `FistSwing` | Every swing: a streak behind the punching fist, with air pulled along behind it and a push of air at the fastest point. The motion drives it, so it matches each hit. Everyone sees everyone's. |
| `M1Hit` | Hits 1–4: a puff of air through the target. |
| `M1Final` | The finisher: a bigger blast of air, smoke out the far side and a dust ring on the floor. |

Set `Config.Color` to tint the wind for a coloured style.

Blocked and parried hits show the parry system's sparks instead. The camera gives a small shake when your hit lands or you're hit, and a bigger one on the finisher.

The sounds are your game's own, re-pitched: `Swing` (Slash), and `Hit` and `Finisher` (RockHit). Swap in your own in `Melee › Sounds`.

## Animations

They're the fist combo's five hits (`Animations/FistCombo`), renamed `Fist M1 1`–`Fist M1 5`:
- **Upper body only:** the legs are at weight 0, so you can walk while you punch.
- **Markers:** each hit lands on its `Hit` marker, and the build checks that `Config.Hits`' `HitDelay`s match them.

Unpublished animations only play in Studio. To publish them:
1. Open **Melee Animation Rig** in the Animation Editor.
2. Publish the five hits.
3. Paste the ids into `Melee › Config › Config.Animations`.

## Files

- **`../Jajanken/Jajanken.rbxl`**: the ability place has it, alongside the abilities, the parry system and the training dummies.
- **`Melee.rbxm`**: the kit for your own game. It's one folder of labelled folders, each named for where its contents go:

  | Folder in the kit | Put it in |
  |---|---|
  | `1. Put the Melee folder in ReplicatedStorage` | `Melee` (Config, Animations, Sounds, Remote) → **ReplicatedStorage** |
  | `2. Put MeleeServer in ServerScriptService` | `MeleeServer` → **ServerScriptService** |
  | `3. Put MeleeClient in StarterPlayer - StarterPlayerScripts` | `MeleeClient` → **StarterPlayer › StarterPlayerScripts** |
  | `4. Put CombatVFX in ReplicatedStorage` | the combat effects pack (skip it if you already have it) |
  | `5. Needed - the stun system (Combat)` | `Combat` → ReplicatedStorage, `CombatServer` → ServerScriptService, `CombatClient` → StarterPlayerScripts |
  | `6. Optional - Workspace` | the animation rig, for publishing |

  The stun itself lives in the **Combat** module (see [Combat](../Combat/README.md)): the stun timer, the hit reactions, and being unable to act while it lasts. That's why the kit needs it. Your game needs **R6** avatars.

## Settings (`Melee › Config`)

| Setting | Default | |
|---|---|---|
| `Hits` | see above | each hit's animation, `HitDelay` (the Hit marker), `Next` (when the next hit can be thrown), `Damage`, `Stun`, and the finisher's `Knockback` and `Lift` |
| `ComboWindow` | 0.6 | seconds after `Next` to keep the string going |
| `FinisherRecovery` / `FinisherCooldown` | 0.8 / 1.15 | after the finisher: until you can block or use an ability / until a new string |
| `Hitbox` | 5 × 5.5 × 6 | the box in front of you at each hit |
| `Push` / `Lunge` | 8 / 10 | studs/s the target is pushed and you step in on hits 1–4, so you stay in range |
| `AttackWalkSpeed` | 10 | |
| `TurnToCamera` | true | each swing turns you to face where the camera looks |
| `HitPlayers`, `TeamCheck` | true | |

## How it works

The server owns the string:
- which hit is next, and whether it's too early or too late;
- the hitbox, the damage, and the stun (through `Combat.resolve`).

It also tells the parry system when each hit will land (`Combat.announce`), which the training dummies use.

The client:
- plays your swing at once (the animation, the swing trail and the step in) and asks the server with `M1`;
- draws everyone else's swings and hits from the server's broadcasts;
- follows the server's count if they ever disagree.

**NPCs fight with it too.** The village's bandits throw their strings from the server, through the same rules:
- **Throwing:** `ServerScriptService.MeleeServer.NpcM1:Invoke(model)` throws the next hit of that NPC's string. It returns which hit (1–5), or nil if it's too early, or the NPC is stunned or blocking.
- **Who they hit:** an NPC's hits only land on players (not on other NPCs), for `Config.NpcDamage` (0.75) of a player's damage.
- **Animation:** every client plays an NPC's swing on it locally, since NPCs have no client of their own to animate them.

Other server scripts can react to hits (`attacker` is the attacking character):

```lua
game.ServerScriptService.MeleeServer:WaitForChild("OnHit").Event:Connect(function(attacker, victim, index, damage, outcome)
end)
```

## Rebuilding and tests

`generate_melee.py` builds `build/Melee.rbxmx`, `build/MeleeRig.rbxmx` and the labelled kit `Melee.rbxmx`. `../Jajanken/build.sh` builds it with everything else.

Tests (`luaurun`, from this folder):
- `tests/server.luau`, 62 checks:
  - each hit's timing, damage, stun and push;
  - the whole string landing as a true combo, never out of stun between hits;
  - the finisher's knockback and cooldown;
  - the string starting over when you're too slow;
  - blocked and parried hits, being hit mid-swing, and being busy with an ability;
  - walk speed, reach, players and teams, bad input and death;
  - NPCs: their strings through `NpcM1`, hitting players only for the NPC share, and being cut short.
- `tests/client.luau`, 46 checks:
  - a click, the swing trail, the step in and turning to the camera;
  - early clicks being remembered;
  - holding through the whole string, each hit as it opens;
  - the hit effects and camera shake;
  - other players' swings, and NPCs' swings animated here;
  - the server's denials and stops;
  - no swinging while stunned, blocking, busy or clicking on the UI;
  - gamepad and touch.
