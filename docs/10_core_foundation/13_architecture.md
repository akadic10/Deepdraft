# 13 — Architecture

## Global Autoload Singletons

The following Autoloads are registered in **Project Settings → Autoload** (`project.godot` `[autoload]`) and are available globally via their node names. They are loaded in the exact order below; later autoloads may depend on earlier ones.

> **Registration:** The agent may register these autoloads directly by editing the `[autoload]` section of `project.godot` (see File Ownership Rules in `AGENT.md`). Preserve the load order exactly as listed.

Load order:

```
BlockRegistry
WorldClock
WorldData
WorldGenerator
```

> **Not autoloads:** `WorldRenderer` and `Camera` are **scene nodes** in `scenes/main/debug_world.tscn`, not singletons. Do not reference them as autoloads. `Chunk` and `ChunkMesher` are plain classes (`class_name`), not autoloads either.

### `BlockRegistry`
Parses and holds the data-driven block definitions and seasonal surface palettes. Provides fast `StringName` ↔ runtime-int translation and per-season block colours.

```gdscript
var AIR_ID: int                                   # runtime id of base:terrain:void, resolved on _ready
func get_id(key: StringName) -> int               # "base:terrain:rock:rock06" → runtime int (-1 if absent)
func get_key(id: int) -> StringName               # runtime int → "base:terrain:rock:rock06"
func get_def(key: StringName) -> Dictionary       # full block definition dict ({} if absent)
func is_solid(id: int) -> bool                     # false for void and water (nav walkability)
func is_transparent(id: int) -> bool              # true only for void (mesher face culling)
func get_color(id: int, season := "summer") -> Color  # surface variants from surface_palettes.json; others from hex_color
```

> Runtime integer IDs are session-local array indices (assigned in JSON file order) and must **never** be written to save files. Save files always store the namespaced `StringName` key.

### `WorldClock`
Authoritative calendar for the whole simulation. All time-sensitive systems read these fields rather than tracking their own counters. (Timer advancement is not yet implemented — the clock is currently a static stub; signals are declared so other systems can connect now.)

```gdscript
var day:    int      # 1–28 within the current season
var season: String   # "spring" | "summer" | "autumn" | "winter"
var year:   int
var hour:   float    # 0.0–23.99

signal season_changed(new_season: String)
signal day_changed(new_day: int)

func growth_rate_multiplier() -> float   # spring 1.2 / summer 1.0 / autumn 0.8 / winter 0.0
func day_of_year() -> int                # 0–111
```

### `WorldData`
Owns the chunk data matrix (a dictionary of `Chunk` objects, lazily created) and exposes thread-safe block read/write APIs. A `Mutex` guards the chunk dictionary; chunk byte arrays are written by only one party at a time (generator pre-submit, game logic post-submit).

```gdscript
func get_block(wx: int, wy: int, wz: int) -> int       # runtime block ID; AIR_ID if out of bounds / ungenerated
func set_block(wx: int, wy: int, wz: int, id: int) -> void
func submit_chunk(cx: int, cy: int, cz: int, chunk: Chunk) -> void   # generator-thread bulk insert
func get_chunk(cx: int, cy: int, cz: int) -> Chunk     # lazy-creates an empty chunk
func get_chunk_if_exists(cx: int, cy: int, cz: int) -> Chunk        # null if not generated
func chunk_exists(cx: int, cy: int, cz: int) -> bool
func mark_chunk_dirty(cx: int, cy: int, cz: int) -> void

signal chunk_dirtied(cx: int, cy: int, cz: int)   # connect with CONNECT_DEFERRED — may fire from the generator thread
```

### `WorldGenerator`
Procedural world generation. Builds the 2D terrain maps on a background thread, then streams 3D chunk columns on demand as the renderer requests them. Full pipeline: `43_mining_materials.md`.

```gdscript
func generate(seed: int = 0) -> void              # 0 → random seed; spins the worker thread
func is_generating() -> bool
func request_chunk_column(cx: int, cz: int) -> void   # renderer asks for a 16×16 XZ column near the camera
func get_streaming_stats() -> Dictionary
func get_generation_metrics() -> Dictionary
func get_surface_y(wx: int, wz: int) -> int
func get_visible_surface_y(wx: int, wz: int) -> int           # waterline for lake/tarn columns
func get_visible_surface_block_id(wx: int, wz: int) -> int

signal chunk_generated(cx: int, cy: int, cz: int)   # CONNECT_DEFERRED — mesh work is main-thread only
signal world_complete()                             # CONNECT_DEFERRED
```

> **Planned (not yet implemented):** an `AudioManager` autoload (procedural spatial audio, ambient loops, combat cues) is referenced as forward-looking infrastructure by `24_world_rendering.md` and `52_combat_military.md`. It does **not** exist in the project yet and is not a registered autoload. Add it to the load order here when it ships.

---

## Boot Sequence — JSON Parsing

On application startup, autoloads run their `_ready()` in registration order, before the main scene's nodes initialise:

1. **`BlockRegistry._ready()`** — loads `data/terrain/terrain_blocks.json` (block definitions: `kind` + `hex_color`) and `data/terrain/surface_palettes.json` (per-season grass/dirt colours), assigning runtime integer IDs in file order. It then resolves and caches `AIR_ID = get_id("base:terrain:void")`. Documentation-comment keys (any JSON key beginning with `__`) are skipped.
2. **`WorldClock._ready()`** — initialises the static calendar fields (no timer is started yet).
3. **`WorldData._ready()`** — allocates its `Mutex`. Chunks are **not** pre-allocated; they are created lazily on first write or handed over by the generator via `submit_chunk()`.
4. **`WorldGenerator._ready()`** — allocates its request mutex and waits. Generation is **not** kicked off at boot; the renderer in the main scene calls `generate(seed)` explicitly, after which the generator builds the 2D maps and then services `request_chunk_column()` calls.

No game data JSON is read with raw `FileAccess` outside its owning registry/system — all block data access goes through `BlockRegistry`, all block storage through `WorldData` (see the Registry Pattern in `AGENT.md`).

---

*Prev: [12_world_grid.md](./12_world_grid.md) | Next: [21_camera.md](../20_player_interface/21_camera.md)*
