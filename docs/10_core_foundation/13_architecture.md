# 13 — Architecture

**Controller helpers (2026-10-22, doc 258 step 8):** `MiningDesignationController`
and `FurniturePlacementController` keep their tool state, piece/zone tables, save
sections and public API, and preload helper scripts from `scripts/components/`
(no `class_name`, no autoload). Mining: `MiningZoneOverlay` (preview, zone overlays,
rulers, mesh builders, visual cuts), `MiningZoneWork` (leases, block work and
execution, drops, DEV mine) and `MiningZoneWindow` (zone window, hint callout).
Furniture: `FurniturePlacementRules` (placement reasons, footprints, wall mounts,
visual bounds), `FurnitureGhostVisuals` (cursor ghost, hint label, materials, model
instancing) and `FurnitureWindow` (click-select, the ghost/installed window and the
object-explorer provider; the controller forwards `pick_explorer_object`,
`get_explorer_bounds`, `get_explorer_data` and `perform_explorer_action`). Helpers
share the owner's tables by reference and otherwise use its public methods, never
its private members.

**No save migration (2026-10-22):** SaveManager doesn't migrate removed content.
A save that names furniture, items or blocks the game no longer defines fails
validation and won't load. This follows the no-backward-compatibility rule in
CLAUDE.md. The retirement migration from 234 and 251, and
`data/content_retirements.json`, were deleted.

**Underground inspection ownership (2026-10-17):** `XrayController` is
scene-owned, wired to the renderer, slice controller, dock and placement tools.
`XrayGeometry` builds presentation geometry from `InteriorTracker`, which owns
discovered air and construction invalidation. The camera temporarily selects
inspection layer 19; terrain remains a shadow caster and simulation source.
Existing slice save state remains authoritative; X-ray/reference state is
transient. JSON tuning uses UIRegistry's existing time/slice definitions. See
[210](../00_dev_roadmap/210_underground_xray_and_level_reference.md).

**Loading presentation (2026-10-17, 206):** scene-owned `WorldLoadingScreen`
gates first startup and reloaded scenes on full terrain, water, light and scenery
readiness. Its CanvasLayer hides gameplay UI and blocks input. WorldClock holds
transient owner-keyed loading pauses separately from the saved player preference;
generation and presentation queues keep running. Reveal/teardown release the hold.
UIRegistry owns the loading screen JSON. No new autoload or global class. See
[206](../00_dev_roadmap/206_panorama_loading_screen.md).

**Food and dining (2026-10-12, 131):** per-dwarf `DwarfFoodBehavior` orchestrates
storage-first meals. `DwarfForaging` uses SurfaceDetailManager's transient crop
claims, saved harvest work and shared crop commit. `DwarfDining` uses furniture
seat/table claims and authored access/clearance; neither helper posts public jobs.
`DwarfMood` derives hunger effects and saves one dining outcome/timer.
`DwarfWorkExecution` applies labor speed and adjusts supervisor estimates.
`DwarfMealVisual` presents the item-owned serving palette without inventory;
`ColonyFoodWarning` presents actual failed food searches. TaskManager owns tuning;
ItemDropManager answers edible-item queries from `ContentRegistry` item definitions.

**Settlement flag ownership (2026-10-12, 133):** the founding controller owns
only the first-placement flow and founded/last-anchor history. Furniture owns
the installed flag, occupancy and Move plans through its JSON definition.
Furniture installation signals update the settlement anchor; physical flag
restoration happens only through furniture/item/cargo owners, never the founding
history section. See [133](../00_dev_roadmap/133_settlement_flag_furniture.md).

**Furniture Move (2026-10-12):** scene-owned `FurniturePlacementController`
owns the `FurnitureMoves` settings/identity ledger and its required save fields.
`FurnitureMovePlan` extends the ordinary fetch/build component for packer
continuation. Installed furniture remains the UNINSTALL source; items/storage/
dwarves remain the sole owners of physical goods. No new autoload or global
class is introduced. See [132](../00_dev_roadmap/132_furniture_move.md).

**Structural construction (2026-10-12):** `BlockRegistry` loads
`data/construction/blocks.json`. Scene-owned `ConstructionController` owns
unfinished areas, preview meshes and the `construction` save section
(priority 15). Since 2026-10-17, preloaded `ConstructionMaterials` extends normal
storage hauling for a project-owned temporary crate, while `ConstructionWork`
uses a work-only branch of the furniture fetch contract for retained per-block
hammering. Saved orders optionally include total blocks, crate location and actual
staged materials; runtime claims/routes rebuild. ColonyInventory includes staged
stock as reserved, never available to other consumers. No new autoload or
global class is introduced. `WorldData` holds solidity; the existing mining,
navigation, room and terrain-lighting systems consume it. See
[127 — Structural stone](../00_dev_roadmap/127_structural_stone_construction.md) and
[205 — Staged construction](../00_dev_roadmap/205_construction_materials_crates.md).

**Permanent floors (2026-10-12, roadmap 128):** the same owner holds typed plank
and stone floor plans, with normal worker work disabled. Their inspector's DEV
Build commits validated terrain cells. WorldRenderer now owns their presentation;
preloaded `ConstructionFloorArt` caches
the authored GLBs' boundary faces and appends only exposed faces to the terrain
batch. BlockRegistry owns their construction data and block IDs. RoomManager
owns `data/rooms/appeal.json`, deriving finished floor coverage and its +5 room
contribution. Pending orders now save their construction kind; full scene restore
covers both floor identities. There are no new autoloads or global classes.

## Global Autoload Singletons

**Water (2026-10-10):** `WaterManager`, after WorldGenerator, owns live finite water
and analytic soil moisture. WorldGenerator owns `water.json`; WaterFlow and
SoilMoisture are pure preloaded components. WaterRenderer, MoistureRenderer and
WaterSound are scene-owned presentation. WorldData exposes `get_terrain_block`
(raw, generated fallback) and `get_live_block` (including current water). The
`water` save owner restores at priority 11, after SaveManager restores final terrain. New
planting/navigation avoid standing water; existing plants are not flood-damaged.

**Item permissions and water stones (2026-10-10):** `ItemPermission` supplies the
shared allowed predicate; item nodes and storage stacks own and save the flag.
Selection, reservation, withdrawal and pickup/commit boundaries enforce it.
`WaterManager.stones` owns persistent source/drain identities, placement state,
head limits and packing progress. `WaterStones` renders the placed forms and owns
`WaterStonePacking` work sources (UNINSTALL). Furniture plans reuse FETCH_BUILD
to deliver exact inactive packed items; completion activates the same identity
at its new location. No new global or separate inventory owner. See roadmap 110.


**Ladders (2026-10-09):** FurniturePlacementController owns a scene child
`LadderSystem` and reads furniture definitions from `ContentRegistry`. The child owns
section plans, installed routes, inspector actions and save section `ladders`
(restore priority 41). Two non-global work components reuse FETCH_BUILD and
UNINSTALL. NavGrid owns explicit rung connections; DwarfAgent owns climbing
presentation and evacuation. No autoload or global class was added. See roadmap 86.

The following Autoloads are registered in **Project Settings → Autoload** (`project.godot` `[autoload]`) and are available globally via their node names. They are loaded in the exact order below; later autoloads may depend on earlier ones.

> **Registration:** The agent may register these autoloads directly by editing the `[autoload]` section of `project.godot` (see File Ownership Rules in `CLAUDE.md`). Preserve the load order exactly as listed.

Load order (matches `project.godot` `[autoload]` as of 2026-10-22):

```
CraftMaterials
SurfaceDetailRegistry
ContentRegistry
BlockRegistry
WorldClock
WorkFeedback
WorldData
WorldGenerator
WaterManager
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
AmbientAudio
```

> **Not autoloads:** `WorldRenderer`, `Camera`, `SurfaceFloraSpawner`, `SliceController`, `ItemDropManager`, the designation/placement controllers, `RoomOverlayController` (🚪 Rooms tool, 2026-08-07), and `DwarfDirector` are **scene nodes** in `scenes/main/debug_world.tscn`, not singletons. Do not reference them as autoloads. `Chunk`, `ChunkMesher`, `Task`, `MiningZoneComponent`, and `DwarfFactory` are plain classes (`class_name`), not autoloads either. The dividing line: **simulation state = autoload, presentation = scene node.**

Scripts reach `ItemDropManager` only through its typed lookup
`ItemDropManager.find(get_tree())` (null when the scene has none, as in standalone
tests) and call its methods directly; never through the raw group name or string
`.call()`. Storage, placement and planning components hold it in typed
`drop_manager: ItemDropManager` fields injected by their owning system.

The scene also owns `CraftingManager` (2026-10-07), the save owner for Worker
orders; its recipes come from `ContentRegistry`. It depends on the scene's items/furniture owners and
registers transient work sources with TaskManager. See `44_crafting_workshops.md`.

`WildlifeManager` (updated 2026-10-10) follows the same scene-owner lifetime: sole loader
of the species files in `data/entities/animals/` (rabbit, deer, wolf, duck; it scans the folder), seeded populations,
inspector provider and save section `wildlife` (priority 65). RabbitAgent and
DeerAgent receive their definitions and share GrazerAgent's gentle needs and
state machine. AnimalNavigation checks species footprints/clearance (rabbit
1×1×2, deer 2×2×4) independently of dwarf NavGrid and ladders. Deer adds local
herd steering and saved herd identity. WolfAgent reuses terrestrial movement/rest
and adds bounded pursuit, meal satisfaction and saved prey identity. The manager
owns prey claims, protected population minima and atomic capture/meal commits.
Wolf navigation is 2×2×2, with bounded local routing and supported contact checks.
DuckAgent shares common wildlife identity/needs but supplies swimming, shore
movement and flight. DuckNavigation reads live finite water, terrain and placed
obstacles; SurfaceFloraSpawner.flight_obstacles supplies nearby tree-canopy bounds
for swept flight clearance. DuckPopulation owns habitat and aerial-entry planning.
These are ordinary preloaded scripts, with no new global class or autoload.
See [Wildlife](../40_economy_colony/45_wildlife.md).

`WorldEventDirector` (2026-10-09) is another scene owner, loading only
`data/world_events/arrivals.json`. It owns calendar opportunities, seeded group
decisions, local hunting pressure and pending entry progress in `world_events`
(priority 66, immediately after wildlife). Providers join `arrival_provider`;
WildlifeManager supplies terrestrial rabbit, deer and wolf arrivals through
EdgeArrivalPlanner and the shared GrazerAgent journey hook, and duck aerial
arrivals through DuckPopulation/DuckAgent. Wide ground groups save separate connected
member routes; deer keep one herd identity and wolves recheck prey support before
each entry. Whole-map tree occupancy gates provider readiness.
`DuckArrivalPreparation` holds transient main-thread work across frames under the
event director's soft 2 ms preparation deadline. Habitat selection keeps seeded
ordering; sampled flight queries can resume between swept segments. Pending
work does not consume an attempt or enter the save. Restore/expiry discards it,
and the saved event seed/ordinal restarts preparation. Live checks still gate
each actor's actual entry; no worker reads the scene. See roadmap 193.

SaveManager.is_loading() prevents scheduling
until the restored calendar is available. Missing event definitions are added
with delayed opportunities without changing existing decisions. No new autoload
or global class is required. See [Rabbit arrivals](../00_dev_roadmap/94_rabbit_arrival_events.md)
and [Deer/wolf arrivals](../00_dev_roadmap/95_deer_wolf_arrivals.md), plus
[Ducks](../00_dev_roadmap/111_duck_wildlife.md) for edge-to-water flights.

`SurfaceDetailRegistry` (2026-10-08) loads `data/entities/surface_details.json`
(stones, seasonal flowers and reeds) and every `data/entities/flora/*_bush.json` once
(it owns the flora folder listing, `flora_files()`),
with no runtime world dependencies. Scene-owned `SurfaceDetailManager`
combines immutable seeded candidates with persistent clearing/removal deltas,
owns occupancy independently of its visuals, and registers adjacent clearing
work sources. Its `surface_details` save section restores at priority 16.
It also owns normalized seasonal shrub models, crop seasons/yields and wild
placement settings. The scene owner restores shrub action/progress/crop deltas
before WorldClock, then reconciles availability on its final season signal.
Placement and removal rules: `42_farming_brewing.md` §Surface details.

Mature shrub relocation keeps
generated identities stable while saving current origin/yaw and packed state.
Optional item `instance_id` links loose/carried/stored whole shrubs to those
records; container saves preserve identities alongside aggregate counts.
SurfaceDetailRegistry supplies plant definitions to shared furniture placement;
`ShrubPlantingComponent` specializes its fetch/carry source with persistent work.
Successful planting returns the record to SurfaceDetailManager. Exact Move claims
are transient and reconstructed before loose items and carried cargo restore.

Flower relocation ([85](../00_dev_roadmap/85_plant_habitats_spacing_flowers.md))
uses the same identity/carry/storage pipeline, with three catalog/item keys for
exact shape variants and JSON bloom seasons. SurfaceDetailPlacement supplies
planting-area geometry; the detail owner checks planted neighbours, and furniture
ghosts supply pending reservations. These areas never register NavGrid collision.
The future forage query returns only planted blooming clumps at their current
locations, independently of rendering or streaming. No new global class/autoload.

Player-created shrubs ([80](../00_dev_roadmap/80_shrub_cutting_growth.md)) save
explicit planted descriptors, a monotonic identity allocator and planting time in
the same section. Their IDs do not depend on generated candidates. Growth uses
WorldClock's read-only continuous calendar and seasonal interval integration;
only young records receive hourly maturity checks. Restore defers age reconciliation
until the final clock signals, preserving observational saves and winter dormancy.

### `ContentRegistry` *(doc 258 step 6)*

Sole loader of the static content a save can name: `data/furniture/*.json` (with
SurfaceDetailRegistry's plant place entries merged in, so it loads after it),
`data/entities/items/resources.json`, `data/workshops/worker_crafting.json` and the
tree species in `data/entities/flora/*_tree.json` (each file's `placement.pick_order`
is the seeded species pick order). API: `furniture_def`/`has_furniture`, `item_def`/`has_item`,
`recipe`/`has_recipe`, `tree_species`/`has_tree_species`, the read-only
dictionaries `furniture`, `items`, `recipes`, `recipe_sections`, `trees` and
`max_craft_orders`, and `save_catalogs()`. It loads before `SaveManager`, so startup
resume rejects saves naming unknown furniture, items, recipes, tree species or stages
and planted bushes before the scene exists; restore code therefore never skips unknown
ids. `FurniturePlacementController`, `ItemDropManager`, `CraftingManager` and
`SurfaceFloraSpawner` take their own copy of these definitions when created (so a
test or one manager can adjust it without touching the registry) and keep only runtime
state.

### `CraftMaterials` *(roadmap 118 — crafted materials and appeal)*

Sole loader of `data/materials/craft_materials.json`, registered first with no
runtime world dependencies. Owns stable material definitions, ingredient-to-material
mapping, product adjectives, material appeal bonuses and semantic wood palettes.
It computes object appeal as `design + material bonus × material factor` and
caches recolored meshes without modifying the original resources.

Recipes and catalogue entries remain grouped by design. Inventory, equipment and
installed-furniture owners retain and save each item's `material_id`; placement
plans separately retain `required_material_id`. `CraftMaterials` supplies shared
validation, naming, appeal and palette helpers, not inventory or save ownership.
See [118 — Crafted materials and appeal](../00_dev_roadmap/118_crafted_materials_and_appeal.md).

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
func block_keys() -> Array                        # every registered block key (save catalogs)
func construction_keys() -> Array                 # every construction definition key
```

> Runtime integer IDs are session-local array indices (assigned in JSON file order) and must **never** be written to save files. Save files always store the namespaced `StringName` key.

### `WorldClock`
Authoritative calendar for the whole simulation, **live and ticking** (data from `data/calendar/calendar.json`). All time-sensitive systems read these fields rather than tracking their own counters.

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
func game_hours_per_real_second() -> float   # honours speed; 0 while paused
func advance_hours(amount: float) -> void    # DEV/testing
func growth_rate_multiplier() -> float       # spring 1.2 / summer 1.0 / autumn 0.8 / winter 0.0
func day_of_year() -> int                    # 0–111
func daylight_hours(day_of_year: int) -> float  # solstice cosine curve (11_overview.md §5)
func season_visual_progress() -> float       # midnight-to-sunrise presentation progress on day 1
```

Season rules and signals remain immediate. As of [194](../00_dev_roadmap/194_gradual_season_transition.md),
flora, ground plants and existing terrain meshes use transient `SeasonalRefreshQueue`
instances to spread art changes across the first night. Queues share a soft 2 ms
admission/art budget; terrain still uses its existing worker/upload budgets.
Tree bodies, navigation and work sources survive art swaps. The transient
`restoring_state` flag lets paused loads catch up within frame budgets instead
of waiting for dawn. Neither that flag nor presentation queues enter saves.

### `WorldData`
Owns the chunk data matrix (a dictionary of `Chunk` objects, lazily created) and exposes thread-safe block read/write APIs. A `Mutex` guards the chunk dictionary; chunk byte arrays are written by only one party at a time (generator pre-submit, game logic post-submit).

```gdscript
func get_block(wx: int, wy: int, wz: int) -> int       # runtime block ID; AIR_ID if out of bounds / ungenerated
func set_block(wx: int, wy: int, wz: int, id: int) -> void
func submit_chunk(cx: int, cy: int, cz: int, chunk: Chunk) -> void   # atomic whole-chunk insert (first edit in a chunk; test column fills)
func get_chunk(cx: int, cy: int, cz: int) -> Chunk     # lazy-creates an empty chunk
func get_chunk_if_exists(cx: int, cy: int, cz: int) -> Chunk        # null if not generated
func chunk_exists(cx: int, cy: int, cz: int) -> bool
func mark_chunk_dirty(cx: int, cy: int, cz: int) -> void

signal chunk_dirtied(cx: int, cy: int, cz: int)   # emitted on the main thread; listeners connect with CONNECT_DEFERRED
signal block_changed(position: Vector3i, old_id: int, new_id: int) # exact main-thread terrain edit
```

`WorldRenderer` splits its work across three plain helpers in `scripts/components/`
(doc 258 step 8): `TerrainTileMesher` (`tiles`, the block-face overview tiles),
`TerrainCavityShell` (`cavity_shell`) and the DEV-only `BlockInspector`
(`block_inspector`). The renderer keeps the lifecycle, exports, slice plane, cut
sets, added terrain, VisibleVolume contract and material. Camera rig lookup and
auto-creation are `Camera.find_in()` / `Camera.create_rig()`.

`WorldRenderer` owns an `UndergroundLighting` presentation child (2026-10-06).
It listens to exact block edits, incrementally derives roof/skylight exposure,
and supplies the shared world-space material to terrain and live entity visuals.
It is neither an autoload nor a save owner. Its tuning comes from SkyController's
existing sky-settings registry; see `24_world_rendering.md` for the lighting contract.
Its `SceneAtmosphereData` helper owns a stable 20×1 RGBA float texture shared by
that owner's materials. Fog/sky/sun changes update it at the existing 20 Hz
maximum cadence, without broadcasting uniforms to each material. Colour fields
are converted to linear once; numeric fields and already-linear sunlight remain
raw. Each scene/viewport owner has independent data; it is derived presentation,
with no global shader state, autoload or save field. See [196](../00_dev_roadmap/196_shared_atmosphere_performance.md).

### `WorldGenerator`
Procedural world generation. Builds the 2D terrain maps on a background thread, which ends when the maps are done; blocks are then read on demand (`get_generated_block_id`) and the renderer draws the block-face overview from the maps. Full pipeline: `43_mining_materials.md`.

Two plain helper scripts in `scripts/components/` (preloaded, no `class_name`) hold parts of it (doc 258 step 8):
- `WorldBlockFill` (`WorldGenerator.block_fill`) — per-block identity: authored strata, surface skin, resource veins, the cached block ids, resource windows, shelf bands and metal noise fields, and the `fill_chunk_column` test helper. It reads the generator's maps through public members and `cave_layout()`; its own state is written on the main thread or by the generator phase that owns it before `maps_ready`, so `generate_block_id` stays safe on worker threads.
- `WorldGenerationMetrics` — static functions that build the generation metrics on the generator thread and print the startup report.

```gdscript
func generate(seed: int = 0) -> void              # 0 → random seed; spins the worker thread
func is_generating() -> bool                      # true until the maps are ready
func is_maps_ready() -> bool                      # every map query is valid
func get_streaming_stats() -> Dictionary          # maps_ready and map-phase timings
func get_generation_metrics() -> Dictionary
func get_surface_y(wx: int, wz: int) -> int
func get_visible_surface_y(wx: int, wz: int) -> int           # waterline for lake/tarn columns
func get_visible_surface_block_id(wx: int, wz: int) -> int
func get_overview_strata_block_id(wx: int, wy: int, wz: int) -> int  # authored strata only, no veins/caves; thread-safe (slice concealment)
func get_tile_visible_range(tx: int, tz: int) -> Vector2i     # per-32×32-tile min/max visible Y (sliced-overview invalidation)
func get_cave_column(index: int) -> Vector3i                  # cave span (floor, roof, id) of a column, or (-1, -1, -1)
func cave_layout() -> Dictionary                              # live {systems, columns, soil}; read-only for callers
func has_natural_cover(x: int, y: int, z: int, depth: int) -> bool  # burial against the original exterior
func construction_stone_id(cell: Vector3i) -> int             # natural stone for built blocks

signal world_complete()                             # main thread; the generator thread has finished
signal maps_ready()                                 # main thread; is_maps_ready() just became true
```

### `PlacedEntityRegistry`
Occupancy registry for placed entities (doc 12 pattern — the terrain grid never knows about entities). Trees register trunk footprints, the Settlement Flag its 1×1×3 box; future workshops/furniture follow. Storage is per-column Y-ranges, not per-cell.

```gdscript
func occupies(pos: Vector3i) -> bool
func register_box(box_min: Vector3i, box_size: Vector3i) -> int   # returns handle
func unregister(id: int) -> void
func column_ranges(column: Vector2i) -> Array                     # Vector3i(min_y, max_y, handle) per occupied range

signal occupancy_changed(box_min: Vector3i, box_size: Vector3i)   # NavGrid invalidates on this
```

### `NavGrid` *(spec: 32_navigation_3d.md)*
Custom 3D A*: solid floor + 3-air clearance + entity occupancy, ±1 steps, flat diagonals without corner cutting, string-pulling for straight walks. Terrain source is `WorldData` where chunks exist, else generated blocks. Per-chunk walkability cache invalidated by `chunk_dirtied` / `occupancy_changed`; path cache TTL 5 s.

```gdscript
func find_path(start: Vector3i, goal: Vector3i, max_nodes := DEFAULT_MAX_NODES) -> Array[Vector3i]
func probe_reachable(start: Vector3i, goal: Vector3i, node_cap := PROBE_NODE_CAP) -> bool  # cap from task_config.json
func is_walkable(cell: Vector3i) -> bool
func walkable_floor_at(wx: int, wz: int, near_y: int, scan := 4) -> Vector3i
func line_walkable_flat(a: Vector3i, b: Vector3i, radius := 0.3) -> bool
func ladder_at(cell: Vector3i) -> Dictionary                         # + ladder_records() for every ladder
```

### `TaskManager` *(the no-hang scheduler; spec: 31_task_system.md)*
Owns all tasks (dwarves hold task IDs only). Event-driven, time-budgeted, probe-capped matching with per-type sorted buckets, resumable cursors, and exponential backoff for unreachable tasks. Work sources (mining zones; later workshops/stockpiles) post intent-sized leases, never per-block tasks. Tunables live in `data/tasks/task_config.json`. Ladders, bridges, flora, surface details and furniture keep their sources in a `WorkSourceTable` component (`scripts/components/WorkSourceTable.gd`, not an autoload), which owns registration, retiring and task-event routing (release never re-posts). See [31](../30_simulation_systems/31_task_system.md).

The autoload keeps the public API, task tables, signals, config and wake
machinery. Two preloaded components (no `class_name`, not autoloads; doc 258
step 8) share its tables — TaskManager hands them the same Dictionary/Array
objects:
- `scripts/components/TaskScheduler.gd` — the matching: idle pass, buckets,
  specialised haul/craft/surface/move comparisons, route probes, worker
  rejection, `types_for` and the lease handoff `assign`. It owns the matching
  state and the scheduler limits; `_budget_usec`, `_max_probes_per_wake` and
  `_probe_node_cap` on TaskManager forward to it.
- `scripts/components/TaskSupervision.gd` — progress sampling
  (`DwarfAgent.work_sample()`), `_recover_attempt`, `_reconcile_workers`, and
  the bodies of `retry_order`, `worker_availability`, `job_diagnostics` and
  `lifecycle_errors`.

The components call TaskManager's public hooks: `request_wake()`,
`remove_pending()`, `apply_backoff()`, `static_priority()`, `progress_grace()`,
`backoff_max_seconds()`, `notify_dwarf_idle()`/`notify_dwarf_unavailable()`.
`TaskManager._run_scheduler()` remains the test entry point.

```gdscript
func add_task(type: int, target_pos: Vector3i, payload := {}, ...) -> Task
func cancel_task(task_id: int) -> void
func complete_dwarf_task(dwarf_id: int) -> void
func release_dwarf_task(dwarf_id: int, reason: int, requeue_dwarf := true) -> void  # always cheap, always legal (31 Release Protocol)
func fail_dwarf_task(dwarf_id: int, reason: String) -> void
func allocate_source_id() -> int                                    # new work-source families allocate here (10M+)
func register_work_source(source_id: int, source: Object) -> void   # + unregister / get / cancel_source_tasks
func register_dwarf(agent: DwarfAgent) -> void                      # + deregister
func get_agent(dwarf_id: int) -> DwarfAgent                         # null when unknown or freed
func get_agents() -> Array[DwarfAgent]                              # every valid registered dwarf
func matches_attempt(dwarf_id: int, task_id: int, generation: int) -> bool  # the dwarf still holds this lease attempt
func notify_dwarf_idle(dwarf_id: int) -> void
func notify_dwarf_unavailable(dwarf_id: int) -> void                # sleeper leaves the idle pool
func get_scheduler_stats() -> Dictionary                            # debug overlay row

signal task_added / task_assigned / task_released / task_completed / task_failed / task_unreachable
```

Other systems never read another script's `_private` members (doc 258 step 6;
`tools/lint_project.py` reports them). UI and other systems read a dwarf through
`DwarfAgent`'s read-only views (`get_task_phase()`, `get_mood()`, `get_food()`,
`get_equipment()`, `get_rest_behavior()`, `get_idle_behavior()`, `target_item()`,
`fetch_source()`, `work_sample()`, ...); only the agent's own behaviour components use its fields.
`DwarfAgent` is split into preloaded components (doc 258 step 8): `DwarfBodyRig`
(assembly, tinting, work/carry rigs, idle bob, the carried cargo), `DwarfMovement`
(path following, climbing, walk cycle, floor support) and `DwarfWorkExecution`,
which extends `DwarfCarryWork` (the job executors). The agent forwards the
fields older components read (`_task_phase`, `_exec_timer`, `_carried_entries`,
`_move_path`…) as properties; new code goes through the components' public members.
Furniture is read through `FurniturePlacementController.get_installed(id)`,
`get_ghost(id)`, `get_installed_pieces()`, `get_ghost_pieces()`, `get_installed_at(cell)`
and `get_ghost_at(cell)`; never mutate what they return.

### `InteriorTracker` *(fed by mining; X-ray presentation: 24_world_rendering.md)*
Data-only interior and exploration bookkeeping for X-ray. Mining (real and DEV) calls `on_blocks_mined()` after the void write; the tracker walks air upward (cap 4) and discovers adjacent caves. Known cells and cave IDs save separately from terrain; interior air indexes rebuild from that knowledge and current block values. Filling a known cell preserves its exploration without preserving a mined/built history.

### `RoomManager` *(spec: 34_temperature.md)*
Sealed-room detection and temperature. Not fed by a signal subscription — `FurniturePlacementController` (a scene node, not an autoload, so the dependency has to run this direction) calls `on_furniture_changed(key, cells, def, installed)` directly on every door/heat-source furniture install and uninstall — `cells` is the piece's full footprint, so every occupied door cell, not just the origin, is registered as a sealing boundary. Also listens to `WorldData.chunk_dirtied` (any block edit — throttled, full-rebuild-on-dirty, see the script header) and `WorldClock.hour_changed` (cheap per-room formula recompute, no flood-fill). Public read API: `get_room_at(cell) -> Dictionary` (empty if not sealed), `is_door_cell(cell)`, `get_stats()`. Never serialised: rooms are derived state, and furniture restore re-installing every door through the normal path rebuilds rooms automatically on load.

Room lighting also reads `get_door_boundaries()` and listens to the exact
`door_boundaries_changed(cells)` signal, separate from throttled room/temperature
updates. `count_room_lights(cells)` counts installed sources independently of
heating. `SaveManager` calls `clear_runtime_state()` before world reload so old
doors, heat and light counts cannot survive or duplicate during furniture restore.

### `StockpileManager`
Colony storage coordinator: registry of stockpile zone work sources (source ids at `1_000_000 + zone_id` — offset from mining's key space), throttled HAUL-lease wake plumbing (drop spawned / task events), the zone list (`get_zones()`) and the aggregate view (`get_total(item_key)`, `signal stockpile_changed`) that the doc 23 status-bar counters will consume. Reads its `hauling` config through `TaskManager.get_config_section()` (single-owner rule on `task_config.json`).

### `UIRegistry`
Owner of UI-layout JSON: `data/ui/dock.json`, `place_catalog.json`,
`inventory_catalog.json` and `dwarf_roster.json`. `get_dock_items()` returns the
five validated navigation groups; `get_menu(target)` returns menu titles, parent
links and command bindings; `get_place_catalog()` returns furniture categories,
short captions and order; `get_inventory_catalog()` returns inventory categories
and tag rules; `get_roster_filters()` returns workforce filter labels and order.
It also owns the development tools switch (`data/ui/dev_tools.json`):
`dev_tools_enabled`, `is_shown(entry)` for `"dev": true` dock entries and menus, and
`shown_actions(actions)` for object-window actions with the `dev` variant.
These files describe presentation, not simulation state. Furniture definitions
remain with FurniturePlacementController; stock with item/storage owners;
dwarf state with DwarfDirector and its agents; trait definitions with DwarfAssets.
Behavior remains in DockUI and the existing system controllers (23_user_interface.md,
roadmaps 54, 56 and 57).

### `SkyController` *(spec: 24_world_rendering.md, Fog & Sky System)*
Drives the scene `WorldEnvironment` sky/fog and Sun/Moon from keyframed curves in `data/sky/sky_settings.json`, animated against `WorldClock`; event hours, hours per day and seasonal day length all come from `data/calendar/calendar.json` through `WorldClock`. Fog colour tracks the sky horizon (24_world_rendering.md core principle). Blends weather overrides from `WeatherManager`.

### `WeatherManager`
Per-season weighted weather scheduler (every `data/weather/*.json`, in file-name order, and `data/calendar/weather_schedule.json`), seeded from the world seed. Hands overrides to `SkyController`. `set_weather()` / `cycle_weather()` for testing.

Saves the 64-bit RNG state as decimal text, like wildlife, to avoid JSON numeric
precision loss. Restoring it resumes the same sequence of daily weather choices.

### `DwarfAssets` *(spec: 41b_dwarf_appearance_glb.md)*
Owner of the ~41 dwarf part GLBs (preloaded PackedScenes) and the three generation JSON pools (`names` / `appearance` / `traits`). Parts are authored in neutral palettes; head/hands are runtime-tinted, body/feet baked (doc 17 §1 tint split).

Also owns `data/professions/professions.json`: runtime promotion availability,
career-map entries, Miner experience thresholds, cached work categories and the
profession ids (`profession_ids()`) every new dwarf's experience starts from.
`DwarfDirector` registers the promotion window; `DwarfProfessionPanel` presents
it. Roles, retained experience and work permissions belong to each `DwarfAgent`.
See milestone 96 for the live Worker/Miner scope and planned career previews.

### `SaveManager` *(save/load persistence — the save spec)*

Sole owner of runtime save-file I/O, the manual quick save at
`user://saves/quicksave.json`, and the independent five-minute save at
`user://saves/autosave.json`. It records the deterministic world seed, clock/weather, and
authoritative scene deltas while leaving tasks, reservations, navigation data, renderer
meshes, and other derived caches transient. The autosave timer advances only when world
generation is complete and no save or load is running. Manual saves do not reset it;
a completed load does, so a load is never followed by an immediate autosave.

At launch, the renderer asks SaveManager for its seed before generation. On this
first request only, SaveManager selects the newest valid quick save, autosave or
matching backup by `saved_at_utc` (file modification time is a fallback for old
metadata). It reads bounded headers to rank candidates, then validates in order.
Temporary transaction files are excluded. The selected world generates once and
uses the existing owner-restore pipeline behind the loading screen. Startup
fallback never repairs or overwrites files. With no valid save, generation starts
normally. Manual Load keeps its explicit slot and backup-repair behavior.

The gear menu's **New Game** uses the same scene-replacement/reset boundary,
bypasses startup resume, chooses a fresh seed and resets the configured calendar,
speed, pause and seeded weather. It discards unsaved session state and leaves
existing save files intact. Normal five-minute autosaving resumes in the new
world. Save/load/New Game cannot overlap an active save or restore.

Writes use a shared transactional path: its private `SaveFileStore` writes and validates a temporary
snapshot, rotates only the selected slot's valid primary to its own backup, then promotes
and revalidates the new primary. An invalid primary cannot displace a valid backup, and
autosave never touches manual-save files. Loading either slot falls back to its matching
backup when necessary and repairs its primary before replacing the world.

A save captures private owner data and registry catalogs on the main thread, then one
worker formats, encodes, validates, rotates, and frees that data. Water, mining and
items use `capture_save_state()` plus `SaveSnapshotPreparation`; other owners use a
deep copy of `serialize_state()`. Captures hold only privately owned data: no live
Nodes, Resources or containers shared with gameplay. A new capture format needs a
matching `SaveSnapshotPreparation` case and equality tests against its
`serialize_state()`. Workers never access the active scene or registries.
Normal frames join only completed tasks; shutdown joins an outstanding save.
Save request booleans mean acceptance. `save_finished` / `autosave_finished` report
commit completion. Additional saves and loads are rejected while a writer is busy.
See [192 — Autosave performance](../00_dev_roadmap/192_autosave_performance.md).

`SaveSnapshotValidator` checks metadata, clock/weather, all current owner sections,
required fields and typed collection records before load resets anything. Empty
collections are valid; missing sections, empty owner dictionaries and mistyped values
are rejected. The same check protects temporary commits and backup rotation.
Structural rules:

- Integer fields accept finite whole JSON numbers but never coerce strings or booleans.
- Cells are exactly three whole numbers; vectors are exactly three finite numbers.
- RNG state (weather, wildlife, world events) is canonical decimal text that fits a
  signed 64-bit integer; a JSON number cannot hold every bit of it.
- Named content (furniture, items, recipes, tree species and stages, plants,
  materials, blocks) must exist in the current registry catalogs.
- `project` must be `Deepdraft`, the world seed nonzero, and `schema_version` exactly
  the current version (2). Any other version, or an outdated water `layout_version`, is
  rejected; there are no migrations.

This is structural validation plus a few cross-section identity checks (water stones,
furniture Moves, bed owners), not exhaustive gameplay validation. Errors name the
failing field. If both generations of a slot are invalid, the load reports failure
without pausing, resetting or reloading the running colony.

Scene nodes opt in through the `save_state_owner` group and expose:

```gdscript
func save_section_key() -> String
func save_restore_priority() -> int
func serialize_state() -> Dictionary
func restore_state(state: Dictionary) -> void
```

Section keys must be unique. Restore priorities encode dependencies (lower restores
first; equal priorities have no dependency on each other):

| Priority | Section | Owner | Authoritative content |
|---:|---|---|---|
| before owners | `terrain` | `WorldData` via SaveManager | One final block key per changed cell |
| before owners | `exploration` | `InteriorTracker` via SaveManager | Known cells and discovered cave IDs |
| 5 | `jobs` | `TaskManager` (`WorkJournal`) | Order identities and bounded diagnostic history |
| 10 | `mining` | `MiningDesignationController` | Outstanding mining-zone block sets |
| 11 | `water` | `WaterManager` | Water volumes, active/displaced queues, spring/outlet state, water stones, moisture |
| 15 | `flora` | `SurfaceFloraSpawner` | Changed trees, felling/harvest work and crop cycles |
| 15 | `construction` | `ConstructionController` | Unfinished areas, staged materials, partial work, next ID |
| 16 | `surface_details` | `SurfaceDetailManager` | Removed/changed details, planted shrubs and flowers, growth and regrowth |
| 20 | `settlement_flag` | `FlagPlacementController` | Founded state and last anchor (the physical flag belongs to furniture/items) |
| 30 | `stockpiles` | `StockpileDesignationController` | Zones, filters and stored stacks |
| 40 | `furniture` | `FurniturePlacementController` | Ghosts, installed pieces, uninstall flags, Move records, container inventories |
| 41 | `ladders` | `LadderSystem` | Routes, build/removal progress, next ID |
| 42 | `bridges` | `BridgeSystem` | Routes, build/removal progress, next ID |
| 50 | `items` | `ItemDropManager` | Loose items: key, position, yaw, count, permission, identity, material |
| 60 | `dwarves` | `DwarfDirector` | Roster identity, appearance, professions, position, needs, mood, carried cargo, equipment |
| 65 | `wildlife` | `WildlifeManager` | Populations, needs, motion, herd/flock identity and RNG state |
| 66 | `world_events` | `WorldEventDirector` | Arrival schedules, active groups, hunting pressure, history |
| 70 | `worker_crafting` | `CraftingManager` | Orders, quantities/mode, pause state, partial work, allowed ingredients |
| 70 | `camera` | `Camera` | Target position, zoom, pitch, orbit |
| 80 | `slice` | `SliceController` | Active/seeded state, current plane, last manual plane |

`clock` and `weather` sit beside `scene` at the top level and are owned by
`WorldClock` and `WeatherManager`. Adding a new authoritative scene system requires
adding this contract, a row here, a matching `SaveSnapshotValidator` schema, and a
note on why its data is authoritative rather than seed-derived or transient.

Saving is observational: `serialize_state()` must not pause the simulation, release a
task, clear a reservation, move an entity, drop an item, or otherwise change gameplay.
Loading is a world-replacement boundary:

1. Read and validate the slot's primary file. If it is missing or invalid, validate its
   backup; a valid backup is copied back over the primary before the load continues.
2. Store the snapshot as the pending restore and pause the clock.
3. Reset transient autoload state: `TaskManager`, `StockpileManager`, `InteriorTracker`,
   `RoomManager`, `NavGrid`, `PlacedEntityRegistry`, `WorldGenerator` and `WorldData`.
4. Reload the current scene; `SkyController` rebinds to it.
5. The renderer takes the saved seed from `generation_seed_for_new_scene()` and the saved
   slice plane from `pending_slice_for_new_scene()`, so overview tiles are cut correctly
   on their first build.
6. Wait until the maps are ready and generation is idle, then two quiet frames for scene
   owners and seed-derived flora to finish their deferred hookups.
7. Inside one `WorldData` edit batch (with `WaterManager.begin_terrain_restore()` open),
   restore terrain, then exploration, then every owner in priority order. Closing the
   batch flushes one dirty notification per affected chunk.
8. Rebuild `StockpileManager` totals, then restore clock and weather last.
9. Print `LoadPerformance`, clear the pending snapshot, reset the autosave counter and
   report the result (backup recovery is reported explicitly).

Derived systems rebuild through their normal paths: installed entities repopulate
occupancy, designations and work sources post fresh leases, dwarves register with
`TaskManager`, doors rebuild rooms, and exploration plus terrain rebuild interior air.

| Persisted | Rebuilt or regenerated |
|---|---|
| World seed | Untouched terrain, water bodies, strata, resources and seeded flora |
| Calendar, speed/pause, weather and weather RNG | Render meshes, lighting and dirty queues |
| Final terrain and exploration | Interior air index, rooms and temperature |
| Every scene section in the table above | Task objects, statuses, assignments, leases and backoff |
| Job order identities and diagnostics | Item, block, seat and work reservations and claims |
| Loose, stored and carried item identity | Navigation caches and `PlacedEntityRegistry` occupancy |
| Partial work on plans, trees, shrubs and recipes | Stockpile totals, executor phases, animation timers, audio |

Assignments seen just after a load may differ from the moment of saving, because tasks
are reconstructed; the save itself never touched them. Carried cargo is the one
boundary case: the save records it in the carrier's `carried_items`, and only on load
does it become loose items around the carrier's saved feet, where rebuilt work sources
can reclaim it. Saving never drops a carried item.

Regression: `scripts/tests/SaveManagerRoundTripTest.gd` (in the gate and the `saves`
area) prints `SAVE_MANAGER_ROUND_TRIP_OK`. It uses its own `user://` directory and covers
manual/autosave round trips, slot isolation, backup rotation and recovery, malformed
snapshots, carried cargo and the weather sequence.

Terrain installation opens `WaterManager.begin_terrain_restore()` before applying
final block values. Water records affected columns without simulating intermediate
displacement; its priority-11 `restore_state()` installs saved mass, active/displaced
queues and moisture, rebuilds derived caches, and closes the boundary. This entire
phase is synchronous. Ordinary gameplay edits retain immediate water responses;
other terrain listeners still receive exact block events and coalesced chunk updates.
See [247 — Saved-world loading](../00_dev_roadmap/247_saved_world_loading.md).

`SurfaceFloraSpawner` saves only changed trees in the required `flora` section:
species/stage identity, floor origin, partial felling work, designation and felled
records. Seeded visuals remain derived; felled records prevent regeneration and
never replay item drops. An empty `trees` array represents the untouched forest;
missing sections are rejected under the current development-save policy.
Juniper picking adds an action, separate felling/harvest work, a harvest-work
cycle and a completed crop cycle to those same changed-tree records. Worker
leases remain transient. Crop visuals and readiness reconcile with the restored
clock, including a different year in the same season; see roadmap 84.

### `WorkFeedback` (doc 48 — chopping/mining sound and dust, 2026-10-04)

Owns `data/audio/work_feedback.json`, cached generated work/wildlife WAVs, the runtime
`Work` audio bus, a capped eight-voice pool, and up to twelve transient dust
bursts. This shared presentation service is a deliberate exception to the usual
scene-node presentation split: work executors and world owners can emit short
feedback without depending on a particular scene hierarchy. It has no simulation
state or save section. Scene exit/replacement stops sounds and frees all effects;
the shared asset bank and volume/mute setting remain available.

Promotion feedback (roadmap 102) adds one bounded nonspatial notification player
on the same Work bus. Only a completed profession change triggers it; it remains
audible while the world clock is paused and outside the camera/slice. Scene
cleanup stops it alongside world voices. Equipment previews remain read-only UI
data from the owning profession/item registries, not a second equipment inventory.

`Camera` provides the centre-screen, slice-aware terrain hit and actual camera-to-hit
distance through `get_work_audio_context()` and the `work_audio_view` group. The ray
is shared once per process frame by all sound owners; a terrain miss falls back to
the pivot, and detached cameras return no context (milestone 169). Horizontal
focus distance supplies attenuation, zoom reduces gain, and native positional
audio supplies subtle stereo panning. The `work_feedback_slice` group exposes
the current slice height. No world or yield RNG is consumed. `set_volume_db()`
and `set_muted()` control the work bus. Menu → Audio now exposes this as Effects,
beside the independent Ambience channel (milestone 168).

Chop and pick events originate at the dwarf's animation contact crossing.
Worker crafting reuses the wood-chop bank at axe contact, with its order's
clamped work progress driving timing across interruptions (see doc 64).
Mining reservations route impacts through their controller, which supplies the
struck face's visible material without revealing concealed resources. Completion
effects originate only from committed felling/mining paths, with material and
position captured before removal; restoration and streaming never replay them.
Particles use simulation time; brief audio tails finish in real time. Headless
simulations still exercise event/pool logic but do not start mixer playback.

Rabbit/deer/wolf feedback (roadmaps 91–93) extends this same bus/pool with per-kind profiles.
Selection allows paused playback and a real-time click cooldown. Grazing pauses
its current short phrase with simulation and requires a visible, living scene
source still in the Grazing activity (Eating for wolves). Weak source references update position
and retire tails on hide/removal/restore. WildlifeManager observes existing meal
progress crossings; these terrestrial cues add no animal RNG consumption or
save fields. Ducks also use the same bus/pool for quacks and landing splashes.
Their quack interval is a saved behavior timer driven by the duck's RNG;
playback variation uses cosmetic RNG and voices are not serialized. Work impacts
retain their existing real-time tail and attenuation defaults.

`WaterSound` separately owns two spatial loop players on the Work bus. Its
procedural waterfall/river banks use private cosmetic randomness and visible
measured currents; still lakes stay quiet. See [Water ambience](../00_dev_roadmap/108_water_ambience.md).

`AmbientAudio` (milestone 168) owns the environmental soundscape, its separate
Ambience bus, `data/audio/environment.json` and `user://audio.cfg` preferences.
It combines clock/sky anchors, weather, nearby flora and physical sky exposure.
Ten loop players and three shared phrase players are cleared at scene exit/loading;
cosmetic RNG and real-time playback never alter simulation state. The settings
panel calls this owner for both Ambience and existing Work/Effects controls.
See [168 — Environmental ambience](../00_dev_roadmap/168_environment_ambience.md).
Milestone [170](../00_dev_roadmap/170_environment_sound_details.md) adds read-only
habitat queries for shoreline, discovered wet caves, trees and actual wolves.
Wolf howls use Effects; the other environmental details use Ambience. Rain and
storm are registered, scheduled weather types; WeatherManager creates one
scene-owned WeatherPrecipitation mesh when needed. Roof/slice clipping and
cosmetic rain never modify water mass or simulation state.
Combat cues and music remain planned; the older proposed `AudioManager` name
does not identify a live system.

---

## Boot Sequence — JSON Parsing

On application startup, autoloads run their `_ready()` in registration order, before the main scene's nodes run `_ready()`. **The main scene is instantiated before any autoload's `_ready()`**, though, so scene-script member initializers (`var x = Registry.table`) and `_init()` see only what an autoload loaded in its own `_init()`. A registry whose tables scene scripts copy at construction must load in `_init()`; otherwise scene systems read it from `_ready()` on.

1. **`CraftMaterials._ready()`** — loads `data/materials/craft_materials.json` and builds the ingredient-to-material lookup before any consumers initialise.
2. **`SurfaceDetailRegistry._init()`** — loads `data/entities/surface_details.json` and every `data/entities/flora/*_bush.json` definition.
3. **`ContentRegistry._init()`** — loads furniture (plus the plant place entries from step 2), item, worker-recipe and tree-species definitions. `FurniturePlacementController`, `ItemDropManager` and `CraftingManager` copy these tables in member initializers.
4. **`BlockRegistry._ready()`** — loads `data/terrain/terrain_blocks.json` (block definitions: `kind` + `hex_color`) and `data/terrain/surface_palettes.json` (per-season grass/dirt colours), assigning runtime integer IDs in file order. It then resolves and caches `AIR_ID = get_id("base:terrain:void")`. Documentation-comment keys (any JSON key beginning with `__`) are skipped.
5. **`WorldClock._ready()`** — loads `data/calendar/calendar.json` and starts the live clock (`_process` advances `hour`/`day`/`season`, honouring `speed` and `paused`).
6. **`WorkFeedback._ready()`** — loads `data/audio/work_feedback.json`, caches its audio streams and configures the work-audio bus.
7. **`WorldData._ready()`** — allocates its `Mutex`. Chunks are **not** pre-allocated; they are created lazily on first write.
8. **`WorldGenerator._ready()`** — allocates its stats mutex and waits. Generation is **not** kicked off at boot; the renderer in the main scene calls `generate(seed)` explicitly, after which the generator builds the 2D maps on a background thread that then ends.
9. **The remaining autoloads** (`WaterManager` → `AmbientAudio`) follow in registration order. Each loads only its owned configuration where applicable; `NavGrid` and `TaskManager` read `data/tasks/task_config.json` tunables via TaskManager's config load. Once the main scene's renderer requests its initial seed, `SaveManager` selects the newest valid save and prepares restoration before generation begins.

No static game-data JSON is read with raw `FileAccess` outside its owning registry/system — all block data access goes through `BlockRegistry`, content a save can name through `ContentRegistry`, all block storage through `WorldData` (see the Registry Pattern in `CLAUDE.md`). Runtime user-save JSON is the separate responsibility of `SaveManager` and its private `SaveFileStore` transaction helper.

Every owner reads its static JSON through the shared reader
`scripts/registries/JsonData.gd` (no `class_name`; owners preload it as
`const JsonData = preload(...)`):

```gdscript
JsonData.read(path, expected_type := TYPE_DICTIONARY, optional := false) -> Variant  # data, or null
JsonData.read_dict(path, optional := false) -> Dictionary  # {} on failure
JsonData.read_array(path, optional := false) -> Array      # [] on failure
JsonData.inspect(path, expected_type := TYPE_DICTIONARY) -> Dictionary  # {data, error, missing}; never reports
```

- A missing or unreadable file, a parse error (with its 1-based line) or a top-level
  value of the wrong JSON type is reported with `push_error` naming the file and the
  reason. The owner then keeps its built-in defaults, exactly as before.
- Valid files parse exactly as `JSON.parse_string` would.
- `optional = true` keeps the absence of a file quiet; a present but broken file is
  still reported. No static data file is optional today.
- Field-level checks (for example UIRegistry's "needs a nonempty backgrounds list")
  stay with the owner.
- User files keep their own handling: `UIWindowManager` treats a missing
  `user://ui_layout.json` as the first run and warns about a corrupt one, and
  `SaveFileStore` returns save errors to `SaveManager`.

### Measuring performance

- Measure startup and load in a release export (Export With Debug unchecked, console
  wrapper included so prints show). Editor/debug runs are about 2.3× slower in the
  script-heavy generation and meshing loops; do not tune against them.
- Run twice and use the second run; the first launch pays shader and asset warmup.
- Startup prints a `StartupPerformance:` block (`TerrainTileMesher`): total to initial
  load, first visible terrain, map precompute and per-phase times, overview tile counts
  and `overview_state`. `startup_ready` marks only the tiles within
  `overview_startup_radius_tiles` of the start centre, not the whole map; for "fully
  built" read `full_complete_at` or the "built block-face overview tiles … since
  startup" line.
- Every load prints a `LoadPerformance:` block (`SaveManager`): request to restored,
  read/validate, `reload_regen_wait` (scene reload, full deterministic map regeneration
  and the quiet frames; usually most of the total), per-section `restore_owners` times,
  and totals/clock/weather. The overview rebuild after restore reports through
  `SliceTiming`.

---

*Prev: [12_world_grid.md](./12_world_grid.md) | Next: [21_camera.md](../20_player_interface/21_camera.md)*
