# 13 — Architecture

## Global Autoload Singletons

The following Autoloads are registered in **Project Settings → Autoload** (`project.godot` `[autoload]`) and are available globally via their node names. They are loaded in the exact order below; later autoloads may depend on earlier ones.

> **Registration:** The agent may register these autoloads directly by editing the `[autoload]` section of `project.godot` (see File Ownership Rules in `AGENT.md`). Preserve the load order exactly as listed.

Load order (matches `project.godot` `[autoload]` as of 2026-10-04):

```
BlockRegistry
WorldClock
WorkFeedback
WorldData
WorldGenerator
PlacedEntityRegistry
NavGrid
TaskManager
InteriorTracker
RoomManager
StockpileManager
UIRegistry
SkyController
WeatherManager
DwarfAssets
SaveManager
```

> **Not autoloads:** `WorldRenderer`, `Camera`, `SurfaceFloraSpawner`, `SliceController`, `ItemDropManager`, the designation/placement controllers, `RoomOverlayController` (🚪 Rooms tool, 2026-08-07), and `DwarfDirector` are **scene nodes** in `scenes/main/debug_world.tscn`, not singletons. Do not reference them as autoloads. `Chunk`, `ChunkMesher`, `Task`, `MiningZoneComponent`, and `DwarfFactory` are plain classes (`class_name`), not autoloads either. The dividing line (doc 16 decision): **simulation state = autoload, presentation = scene node.**

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
Authoritative calendar for the whole simulation, **live and ticking** (shipped with the sky work, doc 08; data from `data/calendar/calendar.json`). All time-sensitive systems read these fields rather than tracking their own counters.

```gdscript
var day:    int      # 1–28 within the current season
var season: String   # "spring" | "summer" | "autumn" | "winter"
var year:   int
var hour:   float    # 0.0–23.99
var speed:  float    # player time-speed multiplier
var paused: bool

signal hour_changed(new_hour: int)
signal day_changed(new_day: int)
signal season_changed(new_season: String)

func set_speed(new_speed: float) -> void
func set_paused(value: bool) -> void
func game_hours_per_real_second() -> float   # honours speed; 0 while paused (sleep-lite timing, doc 16 step 7)
func advance_hours(amount: float) -> void    # DEV/testing
func growth_rate_multiplier() -> float       # spring 1.2 / summer 1.0 / autumn 0.8 / winter 0.0
func day_of_year() -> int                    # 0–111
func daylight_hours(day_of_year: int) -> float  # solstice cosine curve (11_overview.md §5)
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
signal block_changed(position: Vector3i, old_id: int, new_id: int) # exact main-thread terrain edit
```

`WorldRenderer` owns an `UndergroundLighting` presentation child (2026-10-06).
It listens to exact block edits, incrementally derives roof/skylight exposure,
and supplies the shared world-space material to terrain and live entity visuals.
It is neither an autoload nor a save owner. Its tuning comes from SkyController's
existing sky-settings registry; see `24_world_rendering.md` for the lighting contract.

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
func is_column_pending(cx: int, cz: int) -> bool              # queued/in-flight; renderer defers region rebuilds (doc 11 Phase 1e)
func get_overview_strata_block_id(wx: int, wy: int, wz: int) -> int  # authored strata only, no veins/caves; thread-safe (slice concealment)
func get_tile_visible_range(tx: int, tz: int) -> Vector2i     # per-32×32-tile min/max visible Y (sliced-overview invalidation)

signal chunk_generated(cx: int, cy: int, cz: int)   # CONNECT_DEFERRED — mesh work is main-thread only
signal world_complete()                             # CONNECT_DEFERRED
```

### `PlacedEntityRegistry` *(doc 16 step 3a)*
Occupancy registry for placed entities (doc 12 pattern — the terrain grid never knows about entities). Trees register trunk footprints, the Settlement Flag its 1×1×3 box; future workshops/furniture follow. Storage is per-column Y-ranges, not per-cell.

```gdscript
func occupies(pos: Vector3i) -> bool
func register_box(box_min: Vector3i, box_size: Vector3i) -> int   # returns handle
func unregister(id: int) -> void

signal occupancy_changed(box_min: Vector3i, box_size: Vector3i)   # NavGrid invalidates on this
```

### `NavGrid` *(doc 16 step 3b; spec: 32_navigation_3d.md)*
Custom 3D A*: solid floor + 3-air clearance + entity occupancy, ±1 steps, flat diagonals without corner cutting, string-pulling for straight walks. Terrain source is `WorldData` where chunks exist, else generated blocks. Per-chunk walkability cache invalidated by `chunk_dirtied` / `occupancy_changed`; path cache TTL 5 s.

```gdscript
func find_path(start: Vector3i, goal: Vector3i, max_nodes := DEFAULT_MAX_NODES) -> Array[Vector3i]
func probe_reachable(start: Vector3i, goal: Vector3i, node_cap := PROBE_NODE_CAP) -> bool  # cap from task_config.json
func is_walkable(cell: Vector3i) -> bool
func walkable_floor_at(wx: int, wz: int, near_y: int, scan := 4) -> Vector3i
func line_walkable_flat(a: Vector3i, b: Vector3i, radius := 0.3) -> bool
```

### `TaskManager` *(doc 16 §2 — the no-hang scheduler)*
Owns all tasks (dwarves hold task IDs only). Event-driven, time-budgeted, probe-capped matching with per-type sorted buckets, resumable cursors, and exponential backoff for unreachable tasks. Work sources (mining zones; later workshops/stockpiles) post intent-sized leases, never per-block tasks. Tunables live in `data/tasks/task_config.json`.

```gdscript
func add_task(type: int, target_pos: Vector3i, payload := {}, ...) -> Task
func cancel_task(task_id: int) -> void
func complete_dwarf_task(dwarf_id: int) -> void
func release_dwarf_task(dwarf_id: int, reason: int, requeue_dwarf := true) -> void  # §2.8: always cheap, always legal
func fail_dwarf_task(dwarf_id: int, reason: String) -> void
func allocate_source_id() -> int                                    # doc 19: new work-source families allocate here (10M+)
func register_work_source(source_id: int, source: Object) -> void   # + unregister / get / cancel_source_tasks
func register_dwarf(agent: DwarfAgent) -> void                      # + deregister
func notify_dwarf_idle(dwarf_id: int) -> void
func notify_dwarf_unavailable(dwarf_id: int) -> void                # sleeper leaves the idle pool
func get_scheduler_stats() -> Dictionary                            # debug overlay row

signal task_added / task_assigned / task_released / task_completed / task_failed / task_unreachable
```

### `InteriorTracker` *(doc 11 Phase X0, piggybacked on mining — doc 16 Phase 4)*
Data-only interior-column bookkeeping for the future X-Ray mode. Mining (real and DEV) calls `on_blocks_mined()` after the void write; the tracker walks air upward (cap 4) into per-chunk interior sets. Never serialised — rebuilt from the mined set on load.

### `RoomManager` *(doc 34 temperature system, doc 22 doors — 2026-08-03)*
Sealed-room detection and temperature. Not fed by a signal subscription — `FurniturePlacementController` (a scene node, not an autoload, so the dependency has to run this direction) calls `on_furniture_changed(key, cells, def, installed)` directly on every door/heat-source furniture install and uninstall — `cells` is the piece's full footprint (doc 22b, 2026-08-06: doors widened to 2×1, so every occupied cell, not just the origin, is registered as a sealing boundary). Also listens to `WorldData.chunk_dirtied` (any block edit — throttled, full-rebuild-on-dirty, see the script header) and `WorldClock.hour_changed` (cheap per-room formula recompute, no flood-fill). Public read API: `get_room_at(cell) -> Dictionary` (empty if not sealed), `get_stats()`. Never serialised — same DERIVABLE-state precedent as `InteriorTracker`; furniture restore re-installing every door through the normal path rebuilds rooms automatically on load.

Room lighting also reads `get_door_boundaries()` and listens to the exact
`door_boundaries_changed(cells)` signal, separate from throttled room/temperature
updates. `count_room_lights(cells)` counts installed sources independently of
heating. `SaveManager` calls `clear_runtime_state()` before world reload so old
doors, heat and light counts cannot survive or duplicate during furniture restore.

### `StockpileManager` *(doc 18 Phase 3)*
Colony storage coordinator: registry of stockpile zone work sources (source ids at `1_000_000 + zone_id` — offset from mining's key space), throttled HAUL-lease wake plumbing (drop spawned / task events), and the aggregate view (`get_total(item_key)`, `signal stockpile_changed`) that the doc 23 status-bar counters will consume. Reads its `hauling` config through `TaskManager.get_config_section()` (single-owner rule on `task_config.json`).

### `UIRegistry`
Owner of UI-layout JSON: `data/ui/dock.json`, `place_catalog.json`,
`inventory_catalog.json` and `dwarf_roster.json`. `get_dock_items()` returns the
five validated navigation groups; `get_menu(target)` returns menu titles, parent
links and command bindings; `get_place_catalog()` returns furniture categories,
short captions and order; `get_inventory_catalog()` returns inventory categories
and tag rules; `get_roster_filters()` returns workforce filter labels and order.
These files describe presentation, not simulation state. Furniture definitions
remain with FurniturePlacementController; stock with item/storage owners;
dwarf state with DwarfDirector and its agents; trait definitions with DwarfAssets.
Behavior remains in DockUI and the existing system controllers (23_user_interface.md,
roadmaps 54, 56 and 57).

### `SkyController` *(doc 08 — day/night live)*
Drives the scene `WorldEnvironment` sky/fog and Sun/Moon from keyframed curves in `data/sky/sky_settings.json`, animated against `WorldClock`. Fog colour tracks the sky horizon (24_world_rendering.md core principle). Blends weather overrides from `WeatherManager`.

### `WeatherManager` *(doc 08)*
Per-season weighted weather scheduler (`data/weather/*.json`, `data/calendar/weather_schedule.json`), seeded from the world seed. Emits `weather_changed(weather_id)`; hands overrides to `SkyController`. `set_weather()` / `cycle_weather()` for testing.

### `DwarfAssets` *(doc 16 step 2a; spec: 41b)*
Owner of the ~41 dwarf part GLBs (preloaded PackedScenes) and the three generation JSON pools (`names` / `appearance` / `traits`). Parts are authored in neutral palettes; head/hands are runtime-tinted, body/feet baked (doc 17 §1 tint split).

### `SaveManager` *(doc 20 — save/load persistence)*

Sole owner of runtime save-file I/O, the manual quick save at
`user://saves/quicksave.json`, and the independent five-minute save at
`user://saves/autosave.json`. It records the deterministic world seed, clock/weather, and
authoritative scene deltas while leaving tasks, reservations, navigation data, renderer
meshes, and other derived caches transient. The autosave timer advances only when world
generation is complete and no load is running.

Writes use a shared transactional path: `SaveManager` writes and validates a temporary
snapshot, rotates only the selected slot's valid primary to its own backup, then promotes
and revalidates the new primary. An invalid primary cannot displace a valid backup, and
autosave never touches manual-save files. Loading either slot falls back to its matching
backup when necessary and repairs its primary before replacing the world.

Scene nodes opt in through the `save_state_owner` group and expose:

```gdscript
func save_section_key() -> String
func save_restore_priority() -> int
func serialize_state() -> Dictionary
func restore_state(state: Dictionary) -> void
```

Section keys must be unique. Restore priorities encode dependencies: mining 10,
flora 15, settlement flag 20, stockpiles 30, furniture 40, loose items 50, dwarves 60, camera 70,
and slice 80. Adding a new authoritative scene system requires adding this contract and
documenting whether its data is authoritative, seed-derived, or transient.

Saving is observational: `serialize_state()` must not pause the simulation, release a
task, clear a reservation, move an entity, or otherwise change gameplay. Loading is a
world-replacement boundary: `SaveManager` validates the snapshot, resets transient
autoload state, reloads the current scene with the saved seed, waits for deterministic
generation to finish, restores owners in priority order, rebuilds stockpile totals, and
finally restores clock/weather. Full schema and lifecycle: `00_dev_roadmap/20_save_load.md`.

`SurfaceFloraSpawner` saves only changed trees in the optional `flora` section:
species/stage identity, floor origin, partial felling work, designation and felled
records. Seeded visuals remain derived; felled records prevent regeneration and
never replay item drops. Missing flora sections remain compatible with older saves.

### `WorkFeedback` (doc 48 — chopping/mining sound and dust, 2026-10-04)

Owns `data/audio/work_feedback.json`, cached generated work WAVs, the runtime
`Work` audio bus, a capped eight-voice pool, and up to twelve transient dust
bursts. This shared presentation service is a deliberate exception to the usual
scene-node presentation split: work executors and world owners can emit short
feedback without depending on a particular scene hierarchy. It has no simulation
state or save section. Scene exit/replacement stops sounds and frees all effects;
the shared asset bank and volume/mute setting remain available.

`Camera` provides the smoothed focus position and actual camera-to-pivot zoom
through `get_work_audio_context()` and the `work_audio_view` group. Horizontal
focus distance supplies attenuation, zoom reduces gain, and native positional
audio supplies subtle stereo panning. The `work_feedback_slice` group exposes
the current slice height. No world or yield RNG is consumed. `set_volume_db()`
and `set_muted()` control the work bus; a general audio settings UI is future work.

Chop and pick events originate at the dwarf's animation contact crossing.
Mining reservations route impacts through their controller, which supplies the
struck face's visible material without revealing concealed resources. Completion
effects originate only from committed felling/mining paths, with material and
position captured before removal; restoration and streaming never replay them.
Particles use simulation time; brief audio tails finish in real time. Headless
simulations still exercise event/pool logic but do not start mixer playback.

> **Still planned:** the broader `AudioManager` for ambient loops and combat cues
> referenced by `52_combat_military.md` is not implemented. Reuse/extend the work
> playback ownership when that scope arrives instead of duplicating its bus/pool.

---

## Boot Sequence — JSON Parsing

On application startup, autoloads run their `_ready()` in registration order, before the main scene's nodes initialise:

1. **`BlockRegistry._ready()`** — loads `data/terrain/terrain_blocks.json` (block definitions: `kind` + `hex_color`) and `data/terrain/surface_palettes.json` (per-season grass/dirt colours), assigning runtime integer IDs in file order. It then resolves and caches `AIR_ID = get_id("base:terrain:void")`. Documentation-comment keys (any JSON key beginning with `__`) are skipped.
2. **`WorldClock._ready()`** — loads `data/calendar/calendar.json` and starts the live clock (`_process` advances `hour`/`day`/`season`, honouring `speed` and `paused`).
3. **`WorldData._ready()`** — allocates its `Mutex`. Chunks are **not** pre-allocated; they are created lazily on first write or handed over by the generator via `submit_chunk()`.
4. **`WorldGenerator._ready()`** — allocates its request mutex and waits. Generation is **not** kicked off at boot; the renderer in the main scene calls `generate(seed)` explicitly, after which the generator builds the 2D maps and then services `request_chunk_column()` calls.
5. **The remaining autoloads** (`PlacedEntityRegistry` → `SaveManager`) follow in registration order. Each loads only its owned configuration where applicable; `NavGrid` and `TaskManager` read `data/tasks/task_config.json` tunables via TaskManager's config load. `SaveManager` performs no save-file read at boot—the file is opened only when the player requests Load.

No static game-data JSON is read with raw `FileAccess` outside its owning registry/system — all block data access goes through `BlockRegistry`, all block storage through `WorldData` (see the Registry Pattern in `AGENT.md`). Runtime user-save JSON is the separate responsibility of `SaveManager`; no other script opens it.

---

*Prev: [12_world_grid.md](./12_world_grid.md) | Next: [21_camera.md](../20_player_interface/21_camera.md)*
