# Lightning Beams (vendored)

Quasiduck's open-source lightning module, the one many Roblox games use (Elemental Battlegrounds among them):
- Source: https://github.com/SamyBlue/Lightning-Beams, v1.1 at commit `406c3b9`.
- License: MIT, see `LICENSE`.
- PartCache: bundled with it. It's EtiTheSpirit's, also MIT.

| File | From |
|---|---|
| `LightningBolt.luau` | `src/LightningBolt.lua`, with three small edits (see below) |
| `PartCache/PartCache.luau`, `PartCache/Table.luau` | `src/PartCache/`, unchanged |
| `LightningSparks.luau` | `src/LightningSparks.lua` as of `039627d^`. The repo set Sparks aside when v1.1 came out. |

**The patches**, all marked `[Killua kit patch]`.

**Sparks.** v1.1 returns a destroyed bolt's parts to the PartCache, and the cache keeps them parented. The old LightningSparks decided a bolt was gone when its first part had no parent, so with v1.1 its sparks never cleared. Two small edits fix it:
- `LightningBolt:Destroy()` now sets `self._Destroyed = true`.
- `LightningSparks` checks that flag instead.

**Cache size.** The kit draws a lot of lightning at once: a see-through halo round every bolt, arcs over the body, and Narukami's three bolts with their branches. The cache now starts at 2,500 parts instead of 1,000. When it does run out, it grows 250 at a time instead of 10, so it warns once instead of every 10 parts.

LightningExplosion isn't included. It needs three textured emitters that only shipped in the Roblox model, not the repo. The Killua kit builds its explosions from LightningBolt and the game's own emitters instead.

The module is used only on clients, by `KilluaVFX`. Requiring LightningBolt fills a cache of 2,500 bolt parts under `workspace.Terrain`.
