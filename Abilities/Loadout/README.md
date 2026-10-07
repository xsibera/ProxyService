# Loadout: the ability menu

A hotbar and an ability menu for a game with more than one ability kit. Each player picks which four abilities sit on **Z X C V** (gamepad X Y B R1, plus on-screen buttons on touch devices), from every kit in the game: the Brawler's fighting moves, Gon's Jajanken, Killua's lightning and Leorio's warp punches in the ability place.

- **The hotbar**, along the bottom of the screen, shows the four slots: each one's key, its ability (coloured by character) and its cooldown. It flashes red when a press is refused.
- **Press M** (or the **Abilities** button) to open the menu. There's a card for every ability, grouped by character, each with a line on what it does.
  - Pick an ability and then a key, or a key and then an ability.
  - Putting an ability that's already equipped on another key swaps the two keys.
  - **Right-click** a key to empty it.
  - **Presets** fill all four at once: **Gon** (Rock, Paper, Scissors), **Killua** (Lightning Palm, Thunderbolt, Whirlwind, Lightning Dash) **Leorio** (Warp Punch, Remote Jab, Warp Barrage, Portal Burst), and for the Brawler **Striker** (Haymaker, Uppercut, Roundhouse, Axe Kick), **Grappler** (Grab & Throw, Suplex, Chokeslam, Ground Slam) and **Kickboxer** (Teep, Roundhouse, Axe Kick, Haymaker).
  - The menu has a column of cards per character, and grows wider as kits are added. A column with more cards than fit (the Brawler's eight) scrolls.
- New players start with the **Killua** preset (`Loadout.Default`).
- The server keeps each player's choice in their `Loadout` attribute. It refuses changes mid-attack or while stunned, and the kits refuse to cast anything that isn't equipped.

## Files

The folder is in the kits (`Killua.rbxm`, `Leorio.rbxm` and `Jajanken.rbxm`, as an optional folder) and in the ability place:

| | Put it in |
|---|---|
| `Loadout` (the `Loadout` module, `Remote`) | **ReplicatedStorage** |
| `LoadoutServer` | **ServerScriptService** |
| `LoadoutClient` | **StarterPlayer › StarterPlayerScripts** |

## Adding abilities

The registry is `Loadout.Abilities` in `src/Loadout.luau`: each ability's kit, character, display name and hint. `Loadout.Order` sets the order of the menu, and `Loadout.Presets` holds the presets.

A kit plugs in on the client with `Loadout.bind`: LoadoutClient owns the keys and sends each press (and the release that goes with it) to the kit whose ability is on that slot:

```lua
Loadout.bind("LightningPalm", function(state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then castPalm() end
end)
Loadout.setCooldown("LightningPalm", readyAtOsClock, totalSeconds) -- the hotbar's cooldown shade
Loadout.deny("LightningPalm")                                      -- flash the slot red
```

On the server, a kit checks `Loadout.has(player, ability)` before it lets anything be cast.

Both kits use the menu when the place has it, and fall back to their own fixed keys when it doesn't.

## Files and rebuilding

- `src/`:
  - `Loadout.luau`: the registry, presets, parsing, `bind` and cooldowns.
  - `LoadoutServer.server.luau`: the `Set` and `Preset` requests, and the default on join.
  - `LoadoutClient.client.luau`: the hotbar, the menu and the keys.
- `generate_loadout.py` writes `build/Loadout.rbxmx`. `../Jajanken/build.sh` builds it with everything else.

Tests (`luaurun`, from this folder):
- `tests/server.luau`, 57 checks: the module (every ability listed exists), the requests, bad input, and no changes mid-attack.
- `tests/client.luau`, 25 checks: the hotbar, the menu, presets, emptying a slot, and routing presses and releases to the kits.
