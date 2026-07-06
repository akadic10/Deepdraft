# Deepdraft — Agent Navigation Index

This file is the **entry point** for any AI agent working on this codebase. Read it first. It maps every design document to its purpose and tells you which file to consult before touching any system.

---

## Project Identity

| Field | Value |
|---|---|
| Engine | Godot 4.x |
| Language | GDScript |
| Genre | Subterranean colony-builder RTS |
| Core loop | Dig → Brew → Trade |
| Perspective | Top-down RTS only (no WASD direct control) |
| Godot install path | `S:\STEAM\steamapps\common\Godot Engine` |

---

## Document Map

### 📁 Core Foundation — `docs/10_core_foundation/`

| File | Read before you… |
|---|---|
| [`11_overview.md`](docs/10_core_foundation/11_overview.md) | Start any work at all. Contains the invariant design boundaries. |
| [`12_world_grid.md`](docs/10_core_foundation/12_world_grid.md) | Touch block storage, chunk loading, JSON static data registries, registry lookups, or save files. |
| [`13_architecture.md`](docs/10_core_foundation/13_architecture.md) | Add or modify Autoloads, Autoload registration, boot sequence, JSON file-loading systems, or serialisation logic. |

### 📁 Player Interface — `docs/20_player_interface/`

| File | Read before you… |
|---|---|
| [`21_rts_camera.md`](docs/20_player_interface/21_rts_camera.md) | Work on the camera rig, orbital controls, or layer slicing. |
| [`22_mouse_input.md`](docs/20_player_interface/22_mouse_input.md) | Implement raycasting, voxel selection, or drag-to-select. |
| [`23_user_interface.md`](docs/20_player_interface/23_user_interface.md) | Build or modify any UI panel, counter, toast, or labor window. |
| [`24_world_rendering.md`](docs/20_player_interface/24_world_rendering.md) | Work on fog, sky, atmosphere, world-edge treatment, or the slice view's visual behaviour. |

### 📁 Simulation & Systems — `docs/30_simulation_systems/`

| File | Read before you… |
|---|---|
| [`31_task_system.md`](docs/30_simulation_systems/31_task_system.md) | Add task types, change priorities, or modify the worker polling loop. |
| [`32_navigation_3d.md`](docs/30_simulation_systems/32_navigation_3d.md) | Modify pathfinding, walkability rules, or step-assist logic. |
| [`33_water_simulation.md`](docs/30_simulation_systems/33_water_simulation.md) | Touch the CA water loop, pressure model, or water shaders. |
| [`34_temperature.md`](docs/30_simulation_systems/34_temperature.md) | Work on room sealing, heat sources, the aging cellar temperature check, or food preservation. |

### 📁 Economy & Colony Content — `docs/40_economy_colony/`

| File | Read before you… |
|---|---|
| [`41_dwarf_agents.md`](docs/40_economy_colony/41_dwarf_agents.md) | Work on dwarf stats, needs, state machine, or skill system. |
| [`42_farming_brewing.md`](docs/40_economy_colony/42_farming_brewing.md) | Add crops, recipes, farm logic, or plant visual meshes. |
| [`43_mining_materials.md`](docs/40_economy_colony/43_mining_materials.md) | Add block types, change noise generation, or touch collapse logic. |
| [`44_crafting_workshops.md`](docs/40_economy_colony/44_crafting_workshops.md) | Work on the Smelter or Forge workshops, Blacksmith/Weaponsmith/Armorsmith professions, metalworking recipes, or ingot stockpile logic. |

### 📁 World Events — `docs/50_world_events/`

| File | Read before you… |
|---|---|
| [`51_visitors.md`](docs/50_world_events/51_visitors.md) | Work on any visitor type — merchants, travelers, or invaders. Touch `VisitorManager`, spawn logic, tavern infrastructure, or combat triggers. |
| [`52_combat_military.md`](docs/50_world_events/52_combat_military.md) | Work on military professions, the Armory room, enlistment/arming flow, patrol routes, invader waves, or combat resolution. |

### 📁 Asset Creation — `docs/60_asset_creation/`

| File | Read before you… |
|---|---|
| [`61_voxel_art_guide.md`](docs/60_asset_creation/61_voxel_art_guide.md) | Author or review any GLB asset — trees, bushes, cave flora, farm crops, furniture, workshop props, or world decoratives. Contains the master colour palette, MagicaVoxel scale rules, per-asset bounding boxes, naming conventions, and the Dwarven fantasy aesthetic brief. |


---

## Session Start Protocol

> **On every new session, read ALL files listed in the Document Map below using the `Read` tool before performing any work. Do not rely on shell directory listings to discover files — use the paths listed here directly.**

---

## Hard Rules (Never Violate)

These constraints appear in individual documents but are listed here for quick reference:

1. **Bedrock Protocol**: Never allow any action to modify or mine `Y = 0`. (`12_world_grid.md`)
2. **RTS-only camera**: No first-person, no WASD direct control. (`11_overview.md`)
3. **Block ID format**: Save files store namespaced strings, never runtime integers. (`12_world_grid.md`, `13_architecture.md`)
4. **3-block nav clearance**: Pathfinding requires 3 empty air blocks above every floor node. (`32_navigation_3d.md`)
5. **Single-tile plant footprint**: Plant visual overhangs must never have collision shapes. (`42_farming_brewing.md`)
6. **Visual vs logical dwarf height**: Use 3-block logical height for nav/collision, not the 3.3-block visual mesh. (`41_dwarf_agents.md`)
7. **No 3D UI elements**: All UI lives on a `CanvasLayer`. (`23_user_interface.md`)
8. **Deterministic world generation**: Generation must be fully deterministic from `world_seed`; use position-derived hashes or seeded noise, never `randi()` / `randf()` for streamed terrain identity. (`43_mining_materials.md`)
9. **Terrain identity lives in data**: Block identity must come from generated block data and JSON registries, not renderer tricks, fog, camera distance, or painted heightmaps. (`24_world_rendering.md`, `43_mining_materials.md`)
10. **Scene Decoupling Contract (recommended default)**: Prefer `@export` variables for scene references and signals for cross-node communication over explicit node paths (`$Node` / `get_node()`). The agent MAY now create and edit `.tscn` files and register autoloads / set the main scene / register `[input]` actions in `project.godot` — but keep logic scene-agnostic by default and only hardcode node paths when there is a clear reason. Never edit `.tres` or `.import` files. (`13_architecture.md`, File Ownership Rules)
11. **Slice concealment**: The slice view must never reveal undiscovered resources. Plane-cut floors render authored strata only — everywhere, at every zoom; veins, gems, and caves become visible exclusively through mining. (`24_world_rendering.md`, `43_mining_materials.md`)
12. **Releasing a task is always cheap and always legal**: No task type may be designed such that abandoning it mid-way corrupts state. Release returns the task to PENDING, frees reservations, and never loses source-level progress; a future carried item is dropped at the dwarf's feet. (`16_first_dwarf_milestone.md` §2.8, `31_task_system.md`)

---

## Godot Project Structure (expected)

```
DwarfVoxel/
├── AGENT.md                  ← you are here
├── docs/
│   ├── 10_core_foundation/
│   │   ├── 11_overview.md
│   │   ├── 12_world_grid.md
│   │   └── 13_architecture.md
│   ├── 20_player_interface/
│   │   ├── 21_rts_camera.md
│   │   ├── 22_mouse_input.md
│   │   ├── 23_user_interface.md
│   │   └── 24_world_rendering.md
│   ├── 30_simulation_systems/
│   │   ├── 31_task_system.md
│   │   ├── 32_navigation_3d.md
│   │   ├── 33_water_simulation.md
│   │   └── 34_temperature.md
│   ├── 40_economy_colony/
│   │   ├── 41_dwarf_agents.md
│   │   ├── 42_farming_brewing.md
│   │   ├── 43_mining_materials.md
│   │   └── 44_crafting_workshops.md
│   └── 50_world_events/
│       ├── 51_visitors.md
│       └── 52_combat_military.md
├── project.godot             ← agent may edit [autoload], main scene, and [input] only; leave other config to human
├── data/                     ← agent-owned JSON definitions
│   ├── biome/
│   ├── entities/
│   ├── furniture/
│   ├── professions/
│   ├── terrain/
│   ├── visitors/
│   ├── workshops/
│   └── world_gen/
├── scripts/                  ← agent-owned GDScript
│   ├── registries/           ← registry autoloads (BlockRegistry, PlacedEntityRegistry,
│   │                            DwarfAssets, UIRegistry)
│   ├── systems/              ← simulation autoloads (WorldClock, WorldData, WorldGenerator,
│   │                            NavGrid, TaskManager, InteriorTracker, SkyController,
│   │                            WeatherManager) + scene-node systems (WorldRenderer, Camera,
│   │                            SliceController, MiningDesignationController,
│   │                            FlagPlacementController, SurfaceFloraSpawner, ItemDropManager…)
│   │                            — authoritative autoload list + load order: docs/10_core_foundation/13_architecture.md
│   ├── components/           ← reusable logic components, no autoload (MiningZoneComponent)
│   ├── entities/             ← agent scripts (DwarfAgent, DwarfFactory, DwarfDirector,
│   │                            DwarfAppearanceData)
│   └── ui/                   ← UI logic scripts (DockUI, DebugLoadingOverlay)
└── scenes/                   ← agent may create and edit scenes (git-tracked)
    ├── main/
    ├── ui/
    └── entities/
        └── resources/
```

---

## File Naming Conventions

When creating any new file, follow the convention for its type:

| File type | Convention | Examples |
|---|---|---|
| `.gd` scripts | `PascalCase` | `MiningSystem.gd`, `BlockRegistry.gd` |
| `.json` data | `snake_case` | `terrain_blocks.json`, `aging_cellar.json` |
| `.md` docs | `NN_snake_case` (numbered prefix) | `43_mining_materials.md` |
| `.glb` assets | `snake_case` | `apple_mature_autumn.glb` |

GDScript filenames must match their `class_name` declaration exactly — this is a Godot requirement, not a style choice.

---

## File Ownership Rules

### Agent MAY read and write:
- `data/**/*.json` — all static definitions and content tables
- `scripts/**/*.gd` — all GDScript logic and autoloads
- `docs/**/*.md` — design documents
- `scenes/**/*.tscn` — create and edit scenes freely (see Scene Editing Protocol below)

### Agent MAY edit, but only for specific purposes:
- `project.godot` — the `[autoload]` section (register/reorder autoloads), the main scene setting (`run/main_scene`), and the `[input]` section (register input actions for tools/hotkeys — approved 2026-06-05; first use: the Slice tool, `11_slice_xray_plan.md` Phase 2). Do not change rendering, physics, display, or other config unless explicitly asked.

### Agent MUST NEVER touch:
- Any `.tres` file
- Any `.import` file (editor-generated on asset import; hand-editing desyncs the asset)

---

## JSON vs GDScript: The Decision Rule

> **JSON = what things are. GDScript = what things do.**

| Use JSON for… | Use GDScript for… |
|---|---|
| Block definitions and stats | Block registry loader |
| Item and material definitions | Task scheduler |
| Recipe tables | Pathfinding logic |
| Dwarf trait and skill definitions | State machines |
| Biome and noise parameters | Combat resolver |
| Visitor and invader spawn tables | Water CA simulation |
| Temperature thresholds | Signal handlers and events |
| Crafting costs and unlock conditions | Runtime behavior and AI |

If a designer could edit it in a spreadsheet → **JSON**.
If it contains logic, conditionals, or runtime state → **GDScript**.

**No custom Resource instances as data stores.** All static definitions live in JSON, loaded by a registry Autoload. Never use `.tres` files to store game data.

---

## Registry Pattern (Mandatory)

All JSON loading goes through a dedicated registry Autoload. Raw JSON file I/O is never scattered across scripts.

```
scripts/registries/
└── BlockRegistry.gd     ← loads data/terrain/terrain_blocks.json
                            and data/terrain/block_resources.json
```

Workshop, recipe, flora, and visitor data is loaded by the Autoload that owns that system (e.g. `VisitorManager` loads `data/visitors/merchant_catalog.json`). No separate registry Autoload is created for these — each system owns its own data loading.

**Rule:** No script may call `FileAccess.open()` on a JSON file directly. All data access goes through the owning registry or system Autoload:

```gdscript
# Correct
var block = BlockRegistry.get("dwarf:stone_granite")

# Never do this in a non-registry script
var f = FileAccess.open("res://data/terrain/terrain_blocks.json", FileAccess.READ)
```

---

## Script-to-Scene Contract

The agent may now author scenes, but the decoupling discipline below is still the **recommended default** — it keeps logic testable and resilient to scene reorganisation. Deviate only with a clear reason.

1. **Prefer `@export` over hardcoded node paths.** Avoid `get_node("UI/HealthBar")` / `$NavigationAgent3D` in logic scripts where an `@export` reference would do.
2. **Declare node dependencies as `@export` variables** at the top of each script. The wiring can now be done by the agent directly in the scene — it is no longer a human-only step.
3. **Signals are the preferred interface** between scene structure and script logic.
4. **Keep scripts scene-agnostic** where practical — logic should not break if a script is moved in the tree.

### Scene Editing Protocol

`.tscn` is a structured text format with fragile internal references. When creating or editing a scene:

- **Read before edit.** Always read the existing `.tscn` before modifying it.
- **Preserve UIDs.** Keep existing `uid://…` ext_resource IDs and the scene's own UID intact. Scripts are referenced by the UID stored in their `.gd.uid` file.
- **Commit first.** Prefer committing pending work to git before a large scene edit, so the change lands as an isolated, revertible diff.
- **Verify it loads.** After editing, sanity-check that every referenced resource path/UID exists and that node and `[connection]` blocks are well-formed.

```gdscript
# Correct — human wires this in the editor
@export var health_bar: ProgressBar
@export var nav_agent: NavigationAgent3D

# Never do this
func _ready():
    var health_bar = get_node("UI/HealthBar")
```
