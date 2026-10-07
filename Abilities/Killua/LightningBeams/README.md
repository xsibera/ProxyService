# Lightning Beams (vendored)

Quasiduck's open-source lightning module, the one many Roblox games use (Elemental Battlegrounds among them):
- Source: https://github.com/SamyBlue/Lightning-Beams, v1.1 at commit `406c3b9`.
- License: MIT, see `LICENSE`.
- PartCache: bundled with it. It's EtiTheSpirit's, also MIT.

| File | From |
|---|---|
| `LightningBolt.luau` | `src/LightningBolt.lua`, with one added line (see below) |
| `PartCache/PartCache.luau`, `PartCache/Table.luau` | `src/PartCache/`, unchanged |
| `LightningSparks.luau` | `src/LightningSparks.lua` as of `039627d^`. The repo set Sparks aside when v1.1 came out. |

**The patch.** v1.1 returns a destroyed bolt's parts to the PartCache, and the cache keeps them parented. The old LightningSparks decided a bolt was gone when its first part had no parent, so with v1.1 its sparks never cleared. Two small edits fix it, both marked `[Killua kit patch]`:
- `LightningBolt:Destroy()` now sets `self._Destroyed = true`.
- `LightningSparks` checks that flag instead.

LightningExplosion isn't included. It needs three textured emitters that only shipped in the Roblox model, not the repo. The Killua kit builds its explosions from LightningBolt and the game's own emitters instead.

The module is used only on clients, by `KilluaVFX`. Requiring LightningBolt fills a cache of 1,000 bolt parts under `workspace.Terrain`.
