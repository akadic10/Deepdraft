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

**Underground inspection ownership (2026-10-17, 210):** `XrayController` is
scene-owned, wired to the renderer, slice controller, dock and placement tools.
`XrayGeometry` builds presentation geometry from `InteriorTracker`, which owns
discovered air and construction invalidation. The camera temporarily selects
inspection layer 19; terrain remains a shadow caster and simulation source.
Existing slice save state remains authoritative; X-ray/reference state is
transient. JSON tuning uses UIRegistry's existing time/slice definitions (the `xray`
section of `data/ui/time_slice.json`). The view is in doc 23 ("Underground X-ray") and
its rendering in doc 24.

**Loading presentation (2026-10-17, 206):** scene-owned `WorldLoadingScreen`
gates first startup and reloaded scenes on full terrain, water, light and scenery
readiness. Its CanvasLayer hides gameplay UI and blocks input. WorldClock holds
transient owner-keyed loading pauses separately from the saved player preference;
generation and presentation queues keep running. Reveal/teardown release the hold
(see `WorldClock` below). UIRegistry owns the loading screen JSON. No new autoload or
global class. The gate's conditions and the art's crop are in doc 23 ("Panoramic
loading").

**Food and dining (2026-10-12, 131):** per-dwarf `DwarfFoodBehavior` orchestrates
storage-first meals. `DwarfForaging` uses SurfaceDetailManager's transient crop
claims, saved harvest work and shared crop commit. `DwarfDining` uses furniture
seat/table claims and authored access/clearance; neither helper posts public jobs.
`DwarfMood` derives hunger effects and saves one dining outcome/timer.
`DwarfWorkExecution` applies labor speed and adjusts supervisor estimates.
`DwarfMealVisual` presents the item-owned serving palette without inventory;
EventLog's food warning presents actual failed food searches. TaskManager owns tuning;
ItemDropManager answers edible-item queries from `ContentRegistry` item definitions.

**Settlement flag ownership (2026-10-12, 133):** the founding controller owns
only the first-placement flow and founded/last-anchor history. Furniture owns
the installed flag, occupancy and Move plans through its JSON definition.
Furniture installation signals update the settlement anchor; physical flag
restoration happens only through furniture/item/cargo owners, never the founding
history section. `FlagPlacementController` hears `furniture_installed` for
`base:furniture:settlement_flag` and passes the cell to
`DwarfDirector.set_settlement_anchor`. Its `settlement_flag` section (priority 20)
saves `founded`, the last installed `cell`, the settlement's `name` and `founded_day`,
and restores the anchor without making a flag. An installed flag or a plan restores with furniture (40), and a packed flag
with the loose, stored or carried goods, so a load during a Move never makes a second
flag. `data/furniture/settlement_flag.json` gives the banner a 1×1×3 occupancy box.

**Furniture Move (2026-10-12):** scene-owned `FurniturePlacementController`
owns the `FurnitureMoves` settings/identity ledger and its required save fields.
`FurnitureMovePlan` extends the ordinary fetch/build component for packer
continuation. Installed furniture remains the UNINSTALL source; items/storage/
dwarves remain the sole owners of physical goods. No new autoload or global
class is introduced (doc 132).
- Confirming a destination gives the Move an id, `furniture_move:<serial>`, marks the
  source for UNINSTALL and has the destination plan reserve the packed item by that
  id. Packing drops the exact item at the source with the id as its instance id.
- The ledger is not inventory: it keeps the bed owner until the item is installed,
  even if the destination is cancelled after packing. A newer assignment of that
  dwarf to another bed wins. A blocked destination keeps the plan and the item.
- Saves need `furniture.moves` (`next_id`, `records`), and destination plans save
  `move_id`. Claims rebuild before loose items and cargo restore. Validation rejects
  missing or duplicate sources, items and destinations.

**Structural construction (2026-10-12):** `BlockRegistry` loads
`data/construction/blocks.json`, and since 2026-10-26 (doc 275) Build's materials and the
woods logs are built from in `data/construction/materials.json`. Scene-owned
`ConstructionController` owns
unfinished areas, preview meshes and the `construction` save section
(priority 15). Since 2026-10-17, preloaded `ConstructionMaterials` extends normal
storage hauling for a project-owned temporary crate, while `ConstructionWork`
uses a work-only branch of the furniture fetch contract for retained per-block
hammering. Saved orders always include their construction kind and total blocks, and
optionally the crate location and actual staged materials; a log order also names its wood
and each cell's direction (doc 275). Runtime claims/routes rebuild. ColonyInventory includes staged
stock as reserved, never available to other consumers. No new autoload or
global class is introduced. `WorldData` holds solidity; the existing mining,
navigation, room and terrain-lighting systems consume it. A restored crate is placed
again only after loading finishes, so furniture and storage are back first, and scene
teardown cancels orders without refunding stone into the dying scene (roadmaps 127
and 205).

## Global Autoload Singletons

**Water (2026-10-10):** `WaterManager`, after WorldGenerator, owns live finite water
and analytic soil moisture. WorldGenerator owns `water.json`; WaterFlow and
SoilMoisture are pure preloaded components. WaterRenderer, MoistureRenderer and
WaterSound are scene-owned presentation. WorldData exposes `get_terrain_block`
(raw, generated fallback) and `get_live_block` (including current water). The
`water` save owner restores at priority 11, after SaveManager restores final terrain. New
planting/navigation avoid standing water; existing plants are not flood-damaged.

**Item permissions and water stones (2026-10-10, 110):** `ItemPermission` supplies
the shared allowed predicate, a small helper rather than an inventory owner. Loose
and carried goods own the `disallowed` flag as node metadata and save it with their
owner; stored stacks keep it false, as stored goods are always available stock
(deposit and restore clear it). Selection, reservation, withdrawal and
pickup/commit boundaries enforce it.
`WaterManager.stones` owns persistent source/drain identities, placement state,
head limits and packing progress. `WaterStones` renders the placed forms and owns
`WaterStonePacking` work sources (UNINSTALL). Furniture plans reuse FETCH_BUILD
to deliver exact inactive packed items; completion activates the same identity
at its new location. Loose nodes, cargo and storage stacks own the packed form,
and each stone identity has exactly one physical owner. No new global or separate
inventory owner.


**Ladders (2026-10-09):** FurniturePlacementController owns a scene child
`LadderSystem` and reads furniture definitions from `ContentRegistry`. The child owns
section plans, installed routes, inspector actions and save section `ladders`
(restore priority 41). Two non-global work components reuse FETCH_BUILD and
UNINSTALL. NavGrid owns explicit rung connections; DwarfAgent owns climbing
presentation and evacuation. No autoload or global class was added (roadmap 86).
`BridgeSystem` (2026-10-11, roadmap 113) is a sibling child built the same way:
`BridgeBuildComponent` and `BridgeRemovalComponent` reuse FETCH_BUILD and
UNINSTALL, completed decks register NavGrid floor supports and `PlacedEntityRegistry`
boxes, and terrain and water never hold bridge blocks. Its save section `bridges`
restores at priority 42, before loose goods and dwarves.

The following Autoloads are registered in **Project Settings → Autoload** (`project.godot` `[autoload]`) and are available globally via their node names. They are loaded in the exact order below; later autoloads may depend on earlier ones.

> **Registration:** The agent may register these autoloads directly by editing the `[autoload]` section of `project.godot` (see File Ownership Rules in `CLAUDE.md`). Preserve the load order exactly as listed.

Load order (matches `project.godot` `[autoload]` as of 2026-10-26):

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
BlueprintLibrary
SkyController
WeatherManager
DwarfAssets
EventLog
ColonyJournal
SaveManager
AmbientAudio
VideoSettings
GameMenu
```

**`GameMenu`** (`scripts/ui/GameMenu.gd`, doc 23 "The game menu, saving and loading") is the one
presentation autoload, for three reasons:
- as an autoload it hears Esc after every scene node, so it opens only when nothing else
  used the key;
- it outlives the scene reload that Load and New game cause;
- it owns quitting: it turns auto-accept quit off and answers the window's close request
  with its Exit question.

It loads last because it reads `UIRegistry`, `WorldClock` and `SaveManager` in `_ready`,
and builds its Settings page (`SettingsPanel.gd`) from `AmbientAudio` and `VideoSettings`.
Tests give it a stand-in for SaveManager (`saves`) and for quitting (`quit_game`).

**`VideoSettings`** (`scripts/systems/VideoSettings.gd`, doc 23 "The game menu, saving and
loading" and "The UI scale") owns the player's video settings: display mode, render scale,
frame rate, VSync, shadows and anti-aliasing, and the UI scale the Interface tab shows.
- It reads `data/video/video_settings.json`: the settings in the page's order, with their
  titles, lines, choices, defaults, presets and Settings section. Each Video default is
  what the game does unaided; the UI scale starts at Auto, the scale Windows sets for the
  screen.
- It is the one owner of the window's content scale, which is the UI scale. It applies the
  scale while the window draws at its own size, and keeps it at 1 for a tool that
  stretches the window. Scripts change it with `set_value("ui_scale", …)`.
- It keeps the player's choices in `user://video.cfg`, for every colony. Malformed values
  fall back to the defaults, and the windowed size is kept there too.
- Each change applies at once, to the window (`DisplayServer`), the root viewport, the
  shadow atlases (`RenderingServer`) or `Engine.max_fps`, and emits
  `preferences_changed`.
- At startup it applies the player's choices. The window mode and VSync change only when
  they differ from the defaults, so command-line flags such as `--windowed` still count.
- The frame cap starts when the camera rig calls `pace_frames()` (doc 21), so tools that
  never start the camera stay uncapped. Headless, the display calls and the cap are skipped
  and the values still change.

**`EventLog`** (`scripts/systems/EventLog.gd`, doc 23 "Toasts and the event log") is the
colony's event log: arrivals, caverns found, colony news and warnings, with their
pictures, times and places.
- It reads `data/events/event_log.json` and loads after WorldClock, WaterManager and
  InteriorTracker, whose signals it hears: `season_changed`, `flood_warning` and
  `cavern_found`. WorldEventDirector and DwarfAgent post arrivals and promotions to it.
- It checks for hungry dwarves once a second (TaskManager's agents) and raises or
  resolves the food warning.
- It is a `save_state_owner` like TaskManager and WaterManager: the `events` section
  (priority 90). SaveManager clears it with the other runtime state before a load or
  New game, and it takes no entries while a save loads.
- `entry_added` feeds the toasts (`ToastStack`); `changed` refreshes the Events window
  (`EventsPanel`) and the dock bell's count. `pinned()` lists the standing warnings and
  `last_seen()` the newest entry already seen.

**`ColonyJournal`** (`scripts/systems/ColonyJournal.gd`, doc 23 "Colony's page") is the
colony's journal: what the dwarves said, a line per topic a day, shown on Colony's page.
- It reads `data/colony/journal_lines.json`: how many days it keeps, how often it looks,
  how far a memory's age must fall back to count as coming again, and a few lines for each
  thought, keyed by the thought's id in `DwarfMood.thoughts()`.
- Every `check_seconds` it reads each of TaskManager's dwarves' thoughts. A thought begins
  when it is new to that dwarf since the last look, or when its memory came again. What a
  dwarf already thinks when the journal first sees them (after a load, or on arrival) is
  not news. It rests while the clock is paused and while a save loads. Looking, rather
  than DwarfMood announcing each thought, catches every source of a thought, hunger
  included, with no hook in each.
- It is a `save_state_owner`: the `journal` section (priority 90), at most 200 lines, one
  per topic a day, each spoken by one of its dwarves. SaveManager clears it with the other
  runtime state before a load or New game.
- `lines()` gives the lines newest first; `changed` fires when one opens or gains a dwarf.
- `note_taste(agent, thing, kind)` adds the line for a taste found that day (doc 41
  "Tastes"), its topic `found_<kind>:<thing>`.

> **Not autoloads:** `WorldRenderer`, `Camera`, `SurfaceFloraSpawner`, `SliceController`, `ItemDropManager`, the designation/placement controllers, `RoomOverlayController` (🚪 Rooms tool, 2026-08-07), `AppealViewController` (the Appeal view, 2026-10-25), and `DwarfDirector` are **scene nodes** in `scenes/main/debug_world.tscn`, not singletons. Do not reference them as autoloads. `Chunk`, `ChunkMesher`, `Task`, `MiningZoneComponent`, and `DwarfFactory` are plain classes (`class_name`), not autoloads either. The dividing line: **simulation state = autoload, presentation = scene node.**

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
Wolf navigation is 4×4×3, with bounded local routing and supported contact checks.
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
each entry. Whole-map tree occupancy gates provider readiness, so startup routes
never pass through trunks that have not registered yet.
`DuckArrivalPreparation` holds transient main-thread work across frames under the
event director's soft 2 ms preparation deadline. Habitat selection keeps seeded
ordering; sampled flight queries can resume between swept segments. Pending
work does not consume an attempt or enter the save. Restore/expiry discards it,
and the saved event seed/ordinal restarts preparation. Live checks still gate
each actor's actual entry; no worker reads the scene (roadmap 193).

No new autoload or global class is required. The scheduling rules and provider contract are in
[51 — Visitors](../50_world_events/51_visitors.md), and each species' entry rules,
including edge-to-water duck flights, in [Wildlife](../40_economy_colony/45_wildlife.md)
(roadmap 94, 95 and 111).

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
records; each stockpile stack saves its own (the furniture containers that saved
identities beside aggregate counts were deleted on 2026-10-22, doc 258).
SurfaceDetailRegistry supplies plant definitions to shared furniture placement;
`ShrubPlantingComponent` specializes its fetch/carry source with persistent work.
Successful planting returns the record to SurfaceDetailManager. Exact Move claims
are transient and reconstructed before loose items and carried cargo restore.

Flower relocation (doc 85)
uses the same identity/carry/storage pipeline, with three catalog/item keys for
exact shape variants and JSON bloom seasons. SurfaceDetailPlacement supplies
planting-area geometry; the detail owner checks planted neighbours, and furniture
ghosts supply pending reservations. These areas never register NavGrid collision.
The future forage query returns only planted blooming clumps at their current
locations, independently of rendering or streaming. No new global class/autoload.

Player-created shrubs (doc 80) save
explicit planted descriptors, a monotonic identity allocator and planting time in
the same section. Their IDs, `planted:<world_seed>:<serial>` from `next_plant_id`,
do not depend on generated candidates. Restore accepts only shrub records of the
current seed, so flowers exist only under their generated identities (why the DEV
item stamper refuses uprooted wildflowers). Growth uses
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
Recipes opt in with `material_group`; furniture definitions carry `appeal` (`design`,
`material_factor`), and furniture and item definitions `material_palette`. The gameplay
rules are in `44_crafting_workshops.md`, "Material identity and appeal".

### `BlockRegistry`

Parses and holds the data-driven block definitions and seasonal surface palettes. Provides fast `StringName` ↔ runtime-int translation and per-season block colours.

```gdscript
var AIR_ID: int                                   # runtime id of base:terrain:void, resolved on _ready
func get_id(key: StringName) -> int               # "base:terrain:rock:rock06" → runtime int (-1 if absent)
func get_key(id: int) -> StringName               # runtime int → "base:terrain:rock:rock06"
func get_def(key: StringName) -> Dictionary       # full block definition dict ({} if absent)
func is_solid(id: int) -> bool                     # false for void and water (nav walkability)
func is_transparent(id: int) -> bool              # true only for void (mesher face culling)
func get_color(id: int, season := "summer") -> Color  # surface grass and dirt from surface_palettes.json; others from hex_color
func block_keys() -> Array                        # every registered block key (save catalogs)
func construction_keys() -> Array                 # every construction definition key
func build_materials() -> Array                   # Build's materials in tool bar order (doc 275)
func get_build_material(id: String) -> Dictionary # its label, kinds and menu headings
func woods() -> Array                             # the woods logs are built from, in menu order
func get_wood(id: String) -> Dictionary           # label, craft material, good, words, blocks by direction
func log_block(wood: String, direction: String) -> StringName  # "base:construction:log:pine:x"
func log_of(id: int) -> Dictionary                # a built log's {wood, direction}, {} otherwise
func fills_cell(id: int) -> bool                  # solid and hides the faces it touches: not a log
func construction_goods(kind: String, wood := "") -> Array[String]  # the goods a kind takes
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
func days_per_season() -> int                # calendar.json days_per_season
func season_order() -> Array[String]         # calendar.json season_order (a copy)
func hold_for_loading(holder: Node, held: bool) -> void   # transient hold, keyed by holder
func is_loading_held() -> bool
```

**Clock holds (doc 206).** The loading screen, the title screen and the open game menu
freeze time with a hold, never with the player's pause. `paused` reads true while the
player has paused or any hold stands, but `serialize_state()` saves only the player's own
pause, so restoring a running save cannot start actors behind the loading screen and a
hold never becomes the player's choice. Taking or releasing a hold twice changes
nothing; each holder releases its own when it closes or leaves the tree.

Season rules and signals remain immediate. Since 2026-10-15 (doc 194),
flora, ground plants and existing terrain meshes use transient `SeasonalRefreshQueue`
instances to spread art changes across the first night. Queues share a soft 2 ms
admission/art budget; terrain still uses its existing worker/upload budgets.
- `season_visual_progress()` is `hour ÷ sunrise` on a season's first day, with sunrise
  from the calendar's solar noon and that day's daylight, as the sky has it. The change
  uses the night after midnight, about 6–10 real minutes at normal speed; pause holds it
  and speed follows the clock.
- A queue admits the share of its IDs that this progress allows, at most four entries
  per owner per frame. One model swap is atomic and may run over the budget.
- A DEV season jump outside a first night (+1 Season in Development → Time & weather
  tools), a load or a
  large time jump catches up over bounded frames instead of flushing at once. The
  boundary's own work (ID snapshots, cancelling harvest orders that are no longer
  valid) still runs at midnight.
- Entries are IDs, re-checked when due, so felling, clearing, uprooting or streaming an
  object out is never undone by a late refresh. A new season replaces the queue, and a
  scene reload discards it. `SeasonalRefreshTest` covers the schedule.

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
with no global shader state, autoload or save field (doc 196; the packet's layout
contract is in `24_world_rendering.md`, "Shared live atmosphere").

### `WorldGenerator`
Procedural world generation. Builds the 2D terrain maps on a background thread, which ends when the maps are done; blocks are then read on demand (`get_generated_block_id`) and the renderer draws the block-face overview from the maps. Full pipeline: `43_mining_materials.md`.

Two plain helper scripts in `scripts/components/` (preloaded, no `class_name`) hold parts of it (doc 258 step 8):
- `WorldBlockFill` (`WorldGenerator.block_fill`) — per-block identity: authored strata, surface skin, resource veins, the cached block ids, resource windows, shelf bands and metal noise fields, and the `fill_chunk_column` test helper. It reads the generator's maps through public members and `cave_layout()`; its own state is written on the main thread or by the generator phase that owns it before `maps_ready`, so `generate_block_id` stays safe on worker threads.
  For speed it holds direct references to the cave columns and soil, the gem, soil and domain noise, and the lake, tarn and bank dictionaries (`bind_layers()`). The generator binds them in `_init`, and its setters for `_cave_layout` and the three noise fields rebind them; the lake, tarn and bank dictionaries have no setter and are only changed in place, so never assign them a new dictionary. The packed maps and `world_seed` stay live reads, because tests edit them in place through the generator and a cached packed array would copy-on-write away from those edits.
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
signal generation_failed(reason: String)            # the maps never become ready; reason also in generation_error
```

A failed generation (an invalid macro-layout profile, a failed layout, or finished terrain
that fails validation) sets `generation_error` and emits `generation_failed`. The loading
screen then shows the reason instead of revealing (doc 23, "Panoramic loading"; doc 258;
`WorldGenerationFailureTest`, gate).

### `PlacedEntityRegistry`
Occupancy registry for placed entities (doc 12 pattern — the terrain grid never knows about entities). Trees register trunk footprints and installed furniture one box per `collision_regions` entry (the settlement flag's 1×1×3 box among them, doc 133). Storage is per-column Y-ranges, not per-cell. Fence posts and rails are thin barrier AABBs instead (doc 201): they block crossing between cells without filling either cell.

```gdscript
func occupies(pos: Vector3i) -> bool
func register_box(box_min: Vector3i, box_size: Vector3i) -> int   # returns handle
func unregister(id: int) -> void
func column_ranges(column: Vector2i) -> Array                     # Vector3i(min_y, max_y, handle) per occupied range
func register_barrier(bounds: AABB) -> int                       # thin fence barrier; unregister() removes it too
func barrier_blocks_segment(from: Vector3, to: Vector3, radius := .3, height := 3.0) -> bool  # swept body test

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
`DwarfAgent`'s read-only views (`get_task_phase()`, `get_mood()`, `get_food()`, `get_tastes()`,
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

Placing a solid block (construction) removes that cell's interior air, and any edit that
touches interior air marks the 3×3×3 chunk neighbourhood for X-ray, which drains it with
`take_dirty_chunks()`. Air tests read the underlying terrain (`WorldData.get_terrain_block`),
never the live water overlay: reading live water once dropped flooded rooms from the
interior, so standing water must never erase discovery (doc 210).

### `RoomManager` *(spec: 34_temperature.md)*
Sealed-room detection and temperature. Not fed by a signal subscription — `FurniturePlacementController` (a scene node, not an autoload, so the dependency has to run this direction) calls `on_furniture_changed(key, cells, def, installed)` directly on every door/heat-source furniture install and uninstall — `cells` is the piece's full footprint, so every occupied door cell, not just the origin, is registered as a sealing boundary. Also listens to `WorldData.chunk_dirtied` (any block edit — coalesced for 0.5 s, then the preloaded `RoomRebuild` re-detects every room across frames under a soft budget; doc 34 "Room scheduling") and `WorldClock.hour_changed` (cheap per-room formula recompute, no flood-fill). Public read API: `get_room_at(cell) -> Dictionary` (empty if not sealed), `is_door_cell(cell)`, `get_stats()`. Never serialised: rooms are derived state, and furniture restore re-installing every door through the normal path rebuilds rooms automatically on load.

Room lighting also reads `get_door_boundaries()` and listens to the exact
`door_boundaries_changed(cells)` signal, separate from throttled room/temperature
updates. `count_room_lights(cells)` counts installed sources independently of
heating. `SaveManager` calls `clear_runtime_state()` before world reload so old
doors, heat and light counts cannot survive or duplicate during furniture restore.

Room kinds come from `data/rooms/room_kinds.json`. `classify()` decides a
room's kind, and the room window reads `room_kind()`, `nearest_kind()`,
`missing_needs()`, `room_counts()`, `room_furniture(room)` and `room_appeal(room)`.

Room appeal (doc 23 "Room appeal") is worked out when asked and never saved:
`room_appeal(room)` returns its parts, total, floor tiles, the share its size counts, the
floor's bonus, the score and its word, and `appeal_at(cell)` does the same for the room
around a cell ({} outside rooms). The preloaded component `RoomAppeal` adds it up from
FurniturePlacementController's installed pieces, ItemDropManager's loose goods and
StockpileManager's stocked cells, with CraftMaterials' piece values. `appeal_step(score)`
gives the word's entry in `data/rooms/appeal.json` and `appeal_word_ids()` the lower-case
words a save may name; SaveManager passes those to the save validator as `appeal_words`.
`all_room_appeals()` scores every room in one pass for the Appeal view (doc 23 "The
Appeal view"), with each room's counted nodes. `AppealViewController` registers with
DockUI (`register_appeal_view`, its button in TimeSliceHUD before X-ray's), opens rooms
through `RoomOverlayController.open_room_at(cell, "appeal")`, and is one of
ObjectExplorerController's `click_tool_paths`, taking bare-terrain clicks on room floors
through `try_select_zone_at_screen` without an `is_active()` that would stop selection.
`room_furniture()` asks `FurniturePlacementController.room_cells(piece)` for the
anchors that lights and heat are counted by.

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
`get_title_screen()` returns the title screen's art, name and line (`data/ui/title_screen.json`).
`get_item_stamper()` returns the DEV item stamper's groups, amounts and recent count
(`data/ui/item_stamper.json`).
`get_controls()` returns Settings' key list (`data/ui/controls.json`, doc 23 "Keys"); its
loader warns when an entry names an input action `project.godot` does not define.
These files describe presentation, not simulation state. Furniture definitions
remain with FurniturePlacementController; stock with item/storage owners;
dwarf state with DwarfDirector and its agents; trait definitions with DwarfAssets.
Behavior remains in DockUI and the existing system controllers (23_user_interface.md,
roadmaps 54, 56 and 57).

### `BlueprintLibrary`
Blueprints (doc 23 "Copy and Blueprints", doc 273): the starters in
`data/construction/blueprints.json` and the player's own, one JSON file each in
`user://blueprints/`, outside the saves. It owns that folder's JSON: `blueprints()`,
`get_blueprint(id)`, `save(name, size, blocks)`, `rename(id, name)` (the file moves with it),
`delete(id)`, `rescan()` and `refused()` (each unreadable file with why), `open_folder()`, and
`picture(id)`, rendered once in a SubViewport and kept as a PNG beside the file (not in a
headless run). `parse(data, fallback_name)` checks every file, since a shared file may come
from anyone: format 1 only, a size of at most 32 × 16 × 32, construction kinds it knows,
cells inside the size and one block a cell. Another format is refused, never converted,
while the game is in development, as saves are. Blocks are named by construction kind,
never a runtime number (Hard Rule 3). It loads after `BlockRegistry`, whose construction kinds it
checks against. Tests reach it through the tree (`root.get_node("BlueprintLibrary")`) and
load the scripts that name it at run time, as a test script compiles before autoloads exist.

A blueprint file. Cells sit relative to the low corner of the blueprint's box, and R turns
them when it is placed:

```json
{
  "deepdraft_blueprint": 1,
  "name": "Stone hut",
  "size": [5, 3, 5],
  "blocks": {"stone": [[0, 0, 0], [1, 0, 0]], "wood": [[2, 2, 2]]}
}
```

### `SkyController` *(spec: 24_world_rendering.md, Fog & Sky System)*
Drives the scene `WorldEnvironment` sky/fog and Sun/Moon from keyframed curves in `data/sky/sky_settings.json`, animated against `WorldClock`; event hours, hours per day and seasonal day length all come from `data/calendar/calendar.json` through `WorldClock`. Fog colour tracks the sky horizon (24_world_rendering.md core principle). Blends weather overrides from `WeatherManager`.

A scene with neither a `WorldEnvironment` nor a sun, such as the title screen, is left
alone, without a warning. SaveManager rebinds the sky when it enters or reloads the world.
The autoload outlives the scene, so it drops its scene references when the
WorldEnvironment leaves the tree and reads no lights until that rebind (doc 24, "Sky
scene lifetime").

### `WeatherManager`
Per-season weighted weather scheduler (every `data/weather/*.json`, in file-name order, and `data/calendar/weather_schedule.json`), seeded from the world seed. Hands overrides to `SkyController`. `set_weather()` / `cycle_weather()` for testing.

On the title screen there is no world seed yet, so it waits: New game seeds it
(`reset_for_new_game()`), and Continue or Load restore the saved weather and RNG.

Saves the 64-bit RNG state as decimal text, like wildlife, to avoid JSON numeric
precision loss. Restoring it resumes the same sequence of daily weather choices.

### `DwarfAssets` *(spec: 41b_dwarf_appearance_glb.md)*
Owner of the ~41 dwarf part GLBs (preloaded PackedScenes) and the three generation JSON pools (`names` / `appearance` / `traits`). Parts are authored in neutral palettes; head/hands are runtime-tinted, body/feet baked (doc 17 §1 tint split).

Also owns `data/professions/professions.json`: runtime promotion availability,
career-map entries, Miner experience thresholds, cached work categories and the
profession ids (`profession_ids()`) every new dwarf's experience starts from.
`DwarfDirector` registers the promotion window; `DwarfProfessionPanel` presents
it. Roles, retained experience and work permissions belong to each `DwarfAgent`.
Availability is the explicit `promotion_enabled` flag (`profession_enabled()`);
`work_category()` caches each task type's permission category. The live scope and the
planned careers are in `41_dwarf_agents.md`, Profession System (doc 96).

### `SaveManager` *(save/load persistence — the save spec)*

Sole owner of runtime save-file I/O, the manual quick save at
`user://saves/quicksave.json`, the independent five-minute save at
`user://saves/autosave.json`, and the player's named saves in `user://saves/named/` (Save
as…, doc 23). It records the deterministic world seed, clock/weather, and
authoritative scene deltas while leaving tasks, reservations, navigation data, renderer
meshes, and other derived caches transient. The autosave timer advances only when world
generation is complete and no save or load is running. Manual saves do not reset it;
a completed load does, so a load is never followed by an immediate autosave.

**The title screen and the world (2026-10-25, doc 23 "The title screen").** The game opens on
`scenes/main/title_screen.tscn` (`TITLE_SCENE`), which holds the clock and is in the
`title_screen` group.
- From the title, `request_continue()`, `request_new_game()` and Load enter
  `debug_world.tscn` (`WORLD_SCENE`) with `change_scene_to_file`. In a world they reload it as
  before.
- Either way Godot takes the old scene out of the tree before the request returns. Code
  that runs after it on the old scene must not need the tree, and queued layout callbacks
  return when `is_inside_tree()` is false (`DockUI`, `TitleScreen`). A callback on a detached
  dock once stopped a load with a null viewport (doc 161).
- `request_continue()` loads the newest valid save, ranked as startup resume ranks them.
- `request_quit_to_title()` clears the world's runtime state, as New game and Load clear it
  (`_clear_world_runtime()`), then shows the title. It saves nothing; the game menu saves
  first when the player asks it to.

When the world scene starts on its own (the editor's Run Current Scene, tests, tools), the
renderer asks SaveManager for its seed before generation. On this first request only,
SaveManager selects the newest valid quick save, autosave, named save or matching backup by
`saved_at_utc` (file modification time is a fallback for old metadata). Equal times rank a
primary above its backup, then the newer file, then the quick save, the named saves and
the autosave in that order (doc 240). It reads bounded headers to rank candidates, then validates in order.
Temporary transaction files are excluded. The selected world generates once and
uses the existing owner-restore pipeline behind the loading screen. Startup
fallback never repairs or overwrites files. With no valid save, generation starts
normally. Manual Load keeps its explicit slot and backup-repair behavior.

The game menu's **New game** (once its question is confirmed) uses the same scene-replacement/reset boundary,
bypasses startup resume, chooses a fresh seed and resets the configured calendar,
speed, pause and seeded weather. It discards unsaved session state and leaves
existing save files intact. Normal five-minute autosaving resumes in the new
world. Save/load/New Game cannot overlap an active save or restore.

For the game menu it also reads:
- `save_slots()`: the quick save, the autosave, then the named saves that exist, newest
  first. Each slot gives its existence, `saved_at_utc`, the settlement's name
  (`colony_name`) and clock (season, day, year, hour) from the first 8 KB of its file,
  where the clock and the names always come first (JSON sorts the keys). A named slot
  (`named`, id `named_<file>`) also gives its `save_name`, its `world_seed` from the last
  4 KB, where it sorts, and `bytes`, the size of its file and backup;
- `colony_saved_unix()`: when this colony was last saved. SaveManager keeps, by slot, the
  save the colony was loaded from and then each save of it, and gives the newest. Deleting
  a slot takes its save out, so the menu never names a save that is gone. It is 0 after New
  game, Quit to main menu, or once every save of the colony is deleted.

**Named saves** (2026-10-26, doc 274):
- `request_save_as(name)` writes the colony under a name the rules in `SaveName.gd` allow,
  through the same transaction and backup as the two slots, with `save_name` beside the
  clock. A name already in use, capitals aside, replaces that save; the game menu asks first.
- Each lives in `named/<file>.json` with its backup and temporary files. The file is named
  after the save, as a blueprint's is ("Before the flood" is `before_the_flood.json`, with a
  number added while the name is taken; a Windows device name gets `_save`). The name itself
  is kept inside, so any letters work. Any save file put in the folder is listed, its name
  falling back to the file's.
- `request_load_save(id)` loads a slot by its `save_slots()` id, the quick save and the
  autosave too. `request_delete_save(id)` deletes any slot's save, the quick save and the
  autosave too (owner, 2026-10-26), with its backup and unfinished writes, whether or not it
  would load. The player's own go to the Recycle Bin (`OS.move_to_trash`); test storage
  (`configure_storage_for_testing`, which also moves the named folder) deletes outright, so
  tests never fill the player's bin. A deleted quick save or autosave is written again by
  the next Save game or autosave. `open_saves_folder()` shows the named saves' folder.
- Notices name a named save in quotes: "Saved as "Before the flood".", "Loading "Before the
  flood"…".
- There is no limit on named saves (owner, 2026-10-26); the Load page shows how many there
  are and the room they take. A 5-dwarf colony writes about 12.5 MB, indented with tabs
  (about half that without indentation), so a save and its backup take about 25 MB and
  twenty named saves about 500 MB.
- A named save is replaced or deleted only when the player says so. After a schema change,
  or content the game removes, it stays on disk but cannot load, and Load says why; Delete
  clears it. The todo's "Saves from another build are deleted by the next save" concerns
  the quick save and the autosave.

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
`serialize_state()`. `SaveManager._build_snapshot()` / `_collect_scene_state()` build the
same snapshot directly on the main thread; the game never calls them, but they are the
independent reference `SaveWorkerChecks` (gate, through `SaveManagerRoundTripTest`)
compares the worker's output against, so they are not dead code (doc 258).
Workers never access the active scene or registries.
Normal frames join only completed tasks; shutdown joins an outstanding save.
Save request booleans mean acceptance. `save_finished` / `autosave_finished` report
commit completion, so a caller that loads or quits after a save waits for them.
Additional saves and loads are rejected while a writer is busy. Most of a save's cost is
validation (reading the files back) and the backup rotation; they moved to the worker
rather than being trimmed, since they are the save contract (doc 192).

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
- A field the game always writes is required; only genuinely optional data carries the
  schema's `?` prefix. Restorers read required fields directly, never with a fallback
  default (doc 258).
- `project` must be `Deepdraft`, the world seed nonzero, and `schema_version` exactly
  the current version (2). Any other version, or an outdated water `layout_version`, is
  rejected; there are no migrations.

This is structural validation plus a few cross-section identity checks (water stones,
furniture Moves, bed owners), not exhaustive gameplay validation. Errors name the
failing field. If both generations of a slot are invalid, the load reports failure
without pausing, resetting or reloading the running colony.

Scene nodes, and the autoloads TaskManager, WaterManager, EventLog and ColonyJournal, opt in through the
`save_state_owner` group and expose:

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
| 20 | `settlement_flag` | `FlagPlacementController` | Founded state, last anchor, the settlement's name and founding day (the physical flag belongs to furniture/items) |
| 30 | `stockpiles` | `StockpileDesignationController` | Zones, filters and stored stacks |
| 40 | `furniture` | `FurniturePlacementController` | Ghosts, installed pieces, uninstall flags, Move records (no storage: the container code and its save fields were deleted in doc 258) |
| 41 | `ladders` | `LadderSystem` | Routes, build/removal progress, next ID |
| 42 | `bridges` | `BridgeSystem` | Routes, build/removal progress, next ID |
| 50 | `items` | `ItemDropManager` | Loose items: key, position, yaw, count, permission, identity, material |
| 60 | `dwarves` | `DwarfDirector` | Roster identity, appearance, professions, position, needs, mood, carried cargo, equipment |
| 65 | `wildlife` | `WildlifeManager` | Populations, needs, motion, herd/flock identity and RNG state |
| 66 | `world_events` | `WorldEventDirector` | Arrival schedules, active groups, hunting pressure, history |
| 70 | `worker_crafting` | `CraftingManager` | Orders, quantities/mode, pause state, partial work, allowed ingredients |
| 70 | `camera` | `Camera` | Target position, zoom, pitch, orbit |
| 80 | `slice` | `SliceController` | Active/seeded state, current plane, last manual plane |
| 90 | `events` | `EventLog` | The event log's entries (at most 200), pinned warnings, the next id and the last seen |
| 90 | `journal` | `ColonyJournal` | The journal's lines (at most 200): day, topic, the thought's words, complaint or praise, the dwarves sharing it, the speaker, their name and words |

`clock` and `weather` sit beside `scene` at the top level and are owned by
`WorldClock` and `WeatherManager`. `colony_name` beside them is a copy of the flag's name
for the Load list; restoring reads the name from `settlement_flag`. Adding a new
authoritative scene system requires
adding this contract, a row here, a matching `SaveSnapshotValidator` schema, and a
note on why its data is authoritative rather than seed-derived or transient.

Saving is observational: `serialize_state()` must not pause the simulation, release a
task, clear a reservation, move an entity, drop an item, or otherwise change gameplay.
Loading is a world-replacement boundary:

1. Read and validate the slot's primary file. If it is missing or invalid, validate its
   backup; a valid backup is copied back over the primary before the load continues.
2. Store the snapshot as the pending restore and pause the clock.
3. Reset transient autoload state: `TaskManager`, `StockpileManager`, `InteriorTracker`,
   `RoomManager`, `NavGrid`, `PlacedEntityRegistry`, `EventLog`, `ColonyJournal`,
   `WorldGenerator` and `WorldData`.
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
manual/autosave round trips, a named save written, replaced and loaded through the game
menu, then deleted (after which the colony no longer counts as saved), the quick save and
autosave deleted even when broken, slot isolation, backup rotation and recovery, malformed
snapshots, carried cargo and the weather sequence. `StartupSaveTest` ranks a newer named
save first.

Terrain installation opens `WaterManager.begin_terrain_restore()` before applying
final block values. Water records affected columns without simulating intermediate
displacement; its priority-11 `restore_state()` installs saved mass, active/displaced
queues and moisture, rebuilds derived caches, and closes the boundary. This entire
phase is synchronous. Ordinary gameplay edits retain immediate water responses;
other terrain listeners still receive exact block events and coalesced chunk updates.
Why the boundary exists is in doc 33, "Saved-world restoration" (doc 247).

`SurfaceFloraSpawner` saves only changed trees in the required `flora` section:
species/stage identity, floor origin, partial felling work, designation and felled
records. Seeded visuals remain derived; felled records prevent regeneration and
never replay item drops. An empty `trees` array represents the untouched forest;
missing sections are rejected under the current development-save policy.
Fruit picking (roadmap 84, extended to apples in 252) adds an action, separate
felling/harvest work, a harvest-work cycle and a completed crop cycle to those
same changed-tree records. Worker leases remain transient. Crop visuals and
readiness reconcile with the restored clock, including a different year in the
same season; restoring or streaming a picked tree never renews its crop.

### `WorkFeedback` (doc 48 — chopping/mining sound and dust, 2026-10-04)

Owns `data/audio/work_feedback.json`, cached generated work/wildlife WAVs, the runtime
`Work` audio bus, a capped eight-voice pool, and up to twelve transient dust
bursts. This shared presentation service is a deliberate exception to the usual
scene-node presentation split: work executors and world owners can emit short
feedback without depending on a particular scene hierarchy. It has no simulation
state or save section. Scene exit/replacement stops sounds and frees all effects;
the shared asset bank and volume/mute setting remain available. When it binds to a
scene it adds one hidden dust instance (skipped headless) so the bursts' shared
mesh/material pipeline compiles while the world loads, not at the first impact; it
is freed with the other transients (doc 24, "Work effect preparation").

Promotion feedback (roadmap 102) adds one bounded nonspatial notification player
on the same Work bus. Only a completed profession change triggers it; it remains
audible while the world clock is paused and outside the camera/slice. Scene
cleanup stops it alongside world voices. Equipment previews remain read-only UI
data from the owning profession/item registries, not a second equipment inventory.
The chime is `assets/audio/ui/promotion.wav`, synthesized mallet tones with no samples,
generated by `tools/generate_promotion_audio.py`; its `promotion` profile in
`work_feedback.json` sets the level and a 0.2-second cooldown against rapid repeats.

`Camera` provides the centre-screen, slice-aware terrain hit and actual camera-to-hit
distance through `get_work_audio_context()` and the `work_audio_view` group. The ray
is shared once per process frame by all sound owners; a terrain miss falls back to
the pivot, and detached cameras return no context (milestone 169). Horizontal
focus distance supplies attenuation, zoom reduces gain, and native positional
audio supplies subtle stereo panning. The `work_feedback_slice` group exposes
the current slice height. No world or yield RNG is consumed. `set_volume_db()`
and `set_muted()` control the work bus. The Audio tab of the game menu's Settings exposes this as Effects,
beside the independent Ambience channel (milestone 168).

Chop and pick events originate at the dwarf's animation contact crossing.
Worker crafting reuses the wood-chop bank at axe contact, with its order's
clamped work progress driving timing across interruptions (see doc 64).
Construction's stone-hammer knocks (`WorkFeedback.play_hammer`, six procedural
samples from `tools/generate_hammer_audio.py`) fire when the builder's clamped work
progress crosses the 0.72 contact phase of each one-second cycle
(`DwarfConstructionPose.CONTACT_PHASE`), so a stalled frame plays at most one hit and
resumed work never replays old ones. They pause with the simulation, and game speed
changes their cadence, not their pitch (doc 205).
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

`WaterSound`, a child of `WaterRenderer` (doc 108), owns exactly two spatial loop
players on the Work bus: a waterfall rush and a softer river bed. `WaterAudioSynth`
makes their nine-second loops once per process on a background thread, with a
private fixed-seed RNG, and caches them; there are no sound assets. Every
quarter-second it samples visible falling faces (drops over one block) and the
sparse measured current field near the listening focus. Nearby sources set each
voice's position, and its loudness is the loudest contribution, never a sum per
voxel; position and gain ease over 0.7 s, and the river recedes beneath a close
waterfall. Still lakes, films, and dry, undiscovered or sliced-away water supply no
voice. Pause, zero speed, loading, hidden water or a missing camera silences both,
and speed never changes pitch. Tuning is `audio` in `data/world_gen/water.json`:
the waterfall plays at −19 dB out to 65 blocks, 10 dB under its first mix because
its continuous rush masked work, fire and dwarf sounds in playtesting (2026-10-11);
the river at −17 dB out to 30 blocks. Beyond each layer's `max_zoom` it fades out.

`FurnitureFireSound`, a child of `FurniturePlacementController` (doc 117), gives
installed fires their crackle: every definition with a `fire_sound` (`campfire` for
the campfire and the hearth, `torch` for the log torch). It keeps at most four spatial
loop players on the Work bus and every quarter-second picks the strongest visible
sources by camera focus, zoom and height difference. Voices share one power budget,
keep their playback phase while chosen, and fade. Pause, zero speed, loading, a
missing camera, hidden or sliced-away sources and removed pieces are silent; plans
and packed pieces never sound, and speed never changes pitch. Tuning is `fire_ambience`
in `data/audio/work_feedback.json` (campfire 20 blocks at −10 dB, torch 12 at −15 dB).
The two twelve-second loops in `assets/audio/ambience/` are original, made offline by
`tools/generate_fire_audio.py`; the player loops a duplicated stream rather than
hand-edited import settings.

`AmbientAudio` (docs 168 and 170), an autoload after SaveManager, owns the
environmental soundscape, its separate Ambience bus, `data/audio/environment.json`
and the `user://audio.cfg` preferences. It combines clock/sky anchors, weather,
nearby flora and physical sky exposure. Only a scene whose live camera is in
`work_audio_view` gets sound, so asset viewers and unrelated fixtures stay silent.
Per scene it builds ten loop players and a shared three-voice phrase pool (at most
one phrase per family), and frees them synchronously at scene exit, on loading or
when the listening view goes; a restored scene builds one fresh set. Every 0.75 s
it reads physical sky exposure at the listening focus from UndergroundLighting: a
slice that removes a roof only visually never brings outdoor sound in, and enclosed
space gets a quiet sheltered-air bed instead.

The layers follow the sky's own seasonal sunrise and sunset anchors, the weather
and the season (weights in `environment.json`). Wind stays audible at overview
zoom; foliage rustle comes from nearby live, visible trees; birds sing by day, with
shorter gaps around sunrise; crickets, owls and chirps come with the dark; autumn
adds dry leaves and winter a wind texture and tree creaks; winter and snow silence
insects and frogs. Overcast strengthens the wind and thins the calls, fog quiets
everything, rain plays outdoors and recedes to roof patter under a nearby roof,
deep underground stays quiet, and only storms thunder. `EnvironmentSoundSources`
makes bounded, read-only queries of live state for the local details: shoreline
laps (and warm-night frogs) need standing water beside a solid bank, cave drips a
discovered natural cave with real water, and howls a nearby awake wolf. Hidden,
sleeping, hunting, eating or fleeing wolves stay quiet; a howl follows its wolf and
stops when the wolf no longer qualifies. Sources are weak references. Wolf howls
use Effects; every other layer uses Ambience.

Playback runs in real time: pause softens the loops to 25% (`pause_gain`) and stops
phrases, gains move over four seconds, and game speed never changes pitch.
Cosmetic choices use AmbientAudio's own RNG, never simulation or weather RNG, and
nothing enters a save. Every environment sound is original seeded synthesis
(`tools/generate_environment_audio.py`, `tools/generate_environment_details.py`);
no recordings are used. The game menu's Settings page (its Audio tab) calls this
owner for both Ambience and the Work/Effects controls; a change is written to
`audio.cfg` 0.4 s after the last one, and on exit. Rain and storm are registered,
scheduled weather types; WeatherManager creates one scene-owned
WeatherPrecipitation mesh when needed. Roof/slice clipping and cosmetic rain never
modify water mass or simulation state. Combat cues and music remain planned; the
older proposed `AudioManager` name does not identify a live system.

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
9. **The remaining autoloads** (`WaterManager` → `GameMenu`) follow in registration order. Each loads only its owned configuration where applicable; `NavGrid` and `TaskManager` read `data/tasks/task_config.json` tunables via TaskManager's config load. `VideoSettings` applies the player's video choices and the UI scale, so the title already
has it. The main scene is the title screen, which holds the clock until a choice enters the world. A world scene started on its own instead asks for its initial seed through its renderer, and `SaveManager` selects the newest valid save and prepares restoration before generation begins.

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
  and the quiet frames; usually most of the total), per-section `restore_owners` times
  (terrain and exploration first), and totals/clock/weather. The overview rebuild after
  restore reports through `SliceTiming`.
- Fix a stall where it happens. Offscreen simulation keeps its normal rate, and a fog of
  war (an idea in `00_todo.md`) must never hide simulation stalls (docs 189, 192).
- Colony work at the 5/20/30-dwarf cases (doc 41):
  `tools/performance/RunScaling.ps1 -Population 30 -Label <new label> -Seconds 20`
  runs `ColonyScalingBenchmark.gd` (docs 187, 188), a seed-1234 elevated yard of
  mining, construction plans, loose stone and logs and wood stockpiles, with an
  isolated profile, saving off and a new label per run. It extends
  `CameraBenchmark.gd`, so the camera-pan rules below apply too. Run the cases one
  after another, with no tests or exports alongside.
  - Report the work done (mined, built, stored) and idle workers beside frame times.
    Stalled workers make a run look faster, and a change that lets more jobs run
    changes the world being measured.
  - Temporary scheduler counters eat into the 1 ms wake budget, so frame times from
    an instrumented run never back a before/after claim.
  - The yard is artificial, not a mature colony.
- Camera pans (docs 178, 190, 191, 195): `tools/performance/Run.ps1 -Label <new label>
  -Seconds 30 [-SavePath <save>]` runs `CameraBenchmark.gd` on a copy of the save in an
  isolated profile; the original is only read. It uses real-time delta, not
  `--fixed-fps`, and runs uncapped unless `-Paced` (doc 21). `-NoMarkers` gives the
  production-source control.
  - Match the save, seed, camera path, resolution, speed, weather and warmup, and
    compare at least three repeats before trusting a small change.
  - Report median, P95, P99, the maximum and the frames over 16.7/33.3/50/100 ms, with
    GPU time and render setup CPU (`RenderingServer.get_frame_setup_time_cpu()`).
    Viewport-only render timing misses setup, where first-use pipeline compiles and
    per-material uniform writes land. GPU timestamps can lag, so compare distributions.
  - Process markers include same-priority children (the renderer's bracket holds water
    and lighting), so never add nested timings. A 720p run that barely changes frame
    time means the scene is CPU-bound.
  - The freeze phases (skipped with `-NoAblations`) only locate costs: stopping water
    simulation also stops most water-mesh work, and the phases advance one world, so
    their differences are not additive savings.
  - Take no screenshots while sampling; each readback stalled 0.2–0.4 s (doc 194).
  - Time loading, saves, first shader use, season changes, slicing and edits as events
    of their own, not inside steady-pan averages.
- Saves (doc 192): `tools/performance/RunAutosave.ps1 -Population <5|20|30> -SavePath
  <save> -Label <new label> -Seconds 24 -NoAblations` runs `AutosaveBenchmark.gd`, which
  turns saving back on (the other benchmarks keep it off) and requests two saves during
  the pan: a fresh file at 6 s, then a backup rotation at 14 s. It records each request's
  main-thread time and the worker's completion beside the frame rows, and fails if the
  source save changed. The five-minute timer itself is covered by
  `SaveManagerRoundTripTest`.

---

## Builds and tests

### Windows builds

Builds are made only when the owner asks (CLAUDE.md), from the editor: Project → Export →
Windows Desktop (doc 171).
- `export_presets.cfg` adds every runtime JSON file (`data/**/*.json`) and leaves out docs,
  tools, tests, studies, scratch and build output.
- It writes `build/windows/manual_export/Deepdraft.exe`, which git ignores. Never export
  over a game that is still running: replacing a running game's PCK once lost its door
  previews (doc 173).
- `Deepdraft.pck` stays beside the EXE; `Deepdraft.console.exe` is the same game with a
  console for its log. Saves and preferences live in the player's user-data folder and are
  never packaged.
- The owner asked for a clean debugger: a GDScript warning is fixed where it arises, or
  silenced in that script with `@warning_ignore` and a reason. The project's warning
  settings stay on.

### Running tests

`tools/run_job_reliability.ps1` runs the headless tests in `scripts/tests`; CLAUDE.md says
when to run which (doc 257). `tools/test_suite.json` holds the selection and what each test
needs:
- `gate` (run with no arguments) and `areas`, wildcard groups for `-Area`. `-Tests` takes
  names or wildcards, `-All` runs every `*Test.gd`, and `-List` prints the selection.
- `timeouts` (default 180 s; the longest start first), `phases` (argument sets run in turn
  in one profile, such as `StartupSaveTest`'s `--prepare` then a plain resume),
  `shared_output` (tests that write the same `tmp/` folder never overlap) and
  `profile_roots` (a test whose guard checks its profile path gets its profile there).
- `expected_errors`: error lines a test triggers on purpose, left out of the check.

Each test gets a throwaway `APPDATA`/`LOCALAPPDATA`, eight at a time (`-Parallel`).
- **Pass rule.** Exit 0 within the timeout, the pass marker (`_OK`, `_PASS` or
  `<Test>: PASS`) and no `SCRIPT ERROR` on stderr. A runtime error in an awaited coroutine
  ends only that coroutine, so a test can still print its marker and exit 0 with its later
  checks skipped. Plain `ERROR` and `WARNING` lines (audio drivers, `push_warning`
  backtraces) don't fail a test.
- **Output.** One summary line, and each failure with its distinct script errors first
  (`-ShowPasses` lists passes too). Full success deletes the run's logs, profiles and new
  `tmp/` folders unless `-KeepOutput` is given; a failure keeps them and prints the log
  folder. The run warns when it changed a tracked file's `git status`.
- **Headless.** Screenshots run only with `--capture`. A few tests (sky, audio, the
  loading screen) skip their render or audio checks without a display, so the runner does
  not cover those checks.
- **The player's saves.** Tests and tools that start the world or save point
  `SaveManager.configure_storage_for_testing()` (debug builds only) at their own `user://`
  folder, so startup resume never picks up another save. A player's save is reproduced
  from a copy in an isolated profile, never in the real save folder. A world scene started
  there on its own resumes the copy, and an explicit Load sent while that restore runs is
  refused as busy.
- **A named colony in a capture.** Found it as the founding card's Found does
  (`FlagPlacementController._place_flag(cell, true, name)`). Setting `settlement_name` on an
  unfounded flag makes every save fail its checks (2026-10-26).

---

*Prev: [12_world_grid.md](./12_world_grid.md) | Next: [21_camera.md](../20_player_interface/21_camera.md)*
