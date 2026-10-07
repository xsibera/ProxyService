# Combat: the parry system

The rules every ability's hits go through, for a parry-style fight. The ability kits ([Jajanken](../Jajanken/README.md) and [Killua](../Killua/README.md)) don't deal damage themselves when this is in the place: they call `Combat.resolve` for each target. That way blocking, parrying, guard breaks, stuns and counters work the same against every attack.

## Playing

- **Hold F** (gamepad L1, or the on-screen Block button) to **block**. A blocked hit from the front:
  - deals 15% of its damage;
  - pushes you back a little;
  - wears your **guard** down by its guard damage.

  Your guard is a thin bar just above the hotbar, 100 when full. It refills at 20 a second once it hasn't been hit for 1.5s. You walk at 9 while blocking.
- **Tap F just before a hit lands** to **parry** it. The first **0.25s** of a block is the parry window. A parried hit does nothing to you, and the attacker **staggers for 0.9s**, which is your opening.
  - Press-spamming doesn't work: a parry that caught nothing can't be retried for 0.6s. Holding F still blocks.
  - A parry that lands keeps the window open for the next hit, so a quick string can be parried hit after hit.
- **Guard break:** when the guard runs out, or a guard-breaking hit lands on it (a fully charged Rock), the block breaks and you're stunned for 1.4s.
- **Stuns:** a clean hit stuns for a moment. While stunned you can't attack or block, and you walk at 3. Stuns don't stack; the longer one wins. Getting stunned cuts your own attack short.
- **Blocks and parries only cover the front** (a 150° arc), facing where the hit comes from. Some attacks say otherwise:
  - Thunderbolt comes from above: it can be blocked from any side and can't be parried.
  - Whirlwind's counter can't be blocked or parried.
  - Lightning Dash strikes come from where Killua started the dash.

You see **PARRY**, **PARRIED** or **GUARD BROKEN** on screen when it happens to you, and everyone sees sparks for parries, blocks and guard breaks. Reactions play on whoever is hit: a recoil, the electrocuted jitter for a Shock, a stagger for a guard break or a parry. They play on NPCs too, so the test dummies react.

## Files

The folder is in both kits (`Killua.rbxm` and `Jajanken.rbxm`, as an optional folder) and in the ability place:

| | Put it in |
|---|---|
| `Combat` (the `Combat` module, `CombatVFX` + effects + sounds, the reaction `Animations`, `Remote`) | **ReplicatedStorage** |
| `CombatServer` | **ServerScriptService**: the F key, and guard regeneration |
| `CombatClient` | **StarterPlayer › StarterPlayerScripts**: the F key, the block pose and reactions, the guard bar, the words and the sparks |

The reaction animations need publishing before a live game, like the abilities'. Publish `Combat Block`, `Parry`, `Hit`, `Shocked`, `GuardBreak` and `Parried`, then set each `Animation`'s `AnimationId` in `Combat › Animations`. They key the upper body only, with the legs at weight 0, so a stunned or blocking player can still shuffle.

## Settings (`Combat.Settings`)

| Setting | Default | |
|---|---|---|
| `ParryWindow` | 0.25 | seconds after pressing F that a hit is parried |
| `ParryCooldown` | 0.6 | a missed parry can't be retried for this long |
| `ParriedStun` | 0.9 | the attacker's stagger when parried |
| `ChipDamage` | 0.15 | share of a blocked hit's damage that goes through |
| `BlockPush` | 0.25 | share of a blocked hit's knockback |
| `GuardMax` | 100 | |
| `GuardRegen` | 20 | guard per second, once `GuardRegenDelay` (1.5s) has passed since it was hit |
| `GuardBreakStun` | 1.4 | |
| `BlockAngle` | 150 | degrees: the front arc a block or parry covers |
| `BlockWalkSpeed`, `StunWalkSpeed` | 9, 3 | |
| `DefaultStun` | 0.35 | for hits that don't say |

## For your own attacks (and AI)

Put any attack behind it with one call per target:

```lua
local Combat = require(game.ReplicatedStorage.Combat.Combat)

local outcome = Combat.resolve(attackerModel, victimModel, {
	Damage = 10,
	Ability = "MyPunch",
	Knockback = look * 30,      -- on a clean hit
	Stun = 0.4,
	StunKind = "Hit",          -- "Hit" | "Shock" | "Launch" | ...: picks the reaction animation
	GuardDamage = 20,          -- default 2 x Damage
	GuardBreak = false,        -- true: breaks a block outright
	Parryable = true, Blockable = true, Counterable = true,
	FromAbove = false,         -- true: blockable from any side, never parryable
	From = attackerRoot.Position, -- where it comes from (default: the attacker)
})
-- "Hit" | "Blocked" | "GuardBroken" | "Parried" | "Countered" | "Evaded" | "Immune"
```

Before an attack:
- **Check** `Combat.canAct(model)`: not stunned, blocking or mid-attack.
- **Mark** the attacker busy with `Combat.setBusy(model, seconds)`.
- **Announce** it with `Combat.announce(model, hitAt, ability, position?)`, so AI can react.

When something stuns your attacker, cancel the attack: listen for `Combat.Interrupted`.

All the state lives in attributes on the character, so client code and NPCs can read it:
- `Blocking` and `ParryAt`;
- `Guard`;
- `StunnedUntil` and `StunKind`;
- `CounterUntil` and `IntangibleUntil`;
- `BusyUntil`.

Times are `workspace:GetServerTimeNow()`. The full API is at the top of `src/Combat.luau`.

Server signals (BindableEvents, so connect to `.Event`):

| Signal | Arguments | Fires when |
|---|---|---|
| `Resolved` | `(attacker, victim, outcome, hit)` | every resolved hit. The ability place's damage numbers use it. |
| `Countered` | `(victim, attacker, hit)` | a counter stance caught a hit |
| `Interrupted` | `(model)` | a stun cut the model's action short |
| `Announced` | `(attacker, hitAt, ability, position)` | an attack is on its way |

The ability place's **training dummies** (`Jajanken/src/DummyBrains.server.luau`) are written against this API:
- a **Blocking Dummy** that keeps its guard up and turns to face you, though not instantly;
- a **Parrying Dummy** that parries what it sees coming, using `Announced`;
- a **Sparring Dummy** that throws a telegraphed punch to practise parrying and Whirlwind's counter on.

## Files and rebuilding

- `anims.py`: the six reaction animations.
- `effects.py`: `ParrySpark`, `BlockSpark` and `GuardBreak`.
- `generate_combat.py`: puts it together into `build/Combat.rbxmx`.
- `src/`: the module and the two scripts.

`../Jajanken/build.sh` builds it with everything else.

Tests (`luaurun`, from this folder):
- `tests/server.luau`, 61 checks: the rules, the F key's parry and cooldown rules, and guard regeneration.
- `tests/client.luau`, 29 checks: the F key, the block pose, every reaction, NPC reactions, the guard bar, the words and the effects.
