# Deepdraft — Agent Guide

Rules and standing decisions for agents working on Deepdraft. This file is not a
changelog: record finished work as described under "Recording Changes".

---

## Project Identity

| Field | Value |
|---|---|
| Engine | Godot 4.7 (Forward+, Direct3D 12 on Windows) |
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
| [`21_camera.md`](docs/20_player_interface/21_camera.md) | Work on the camera rig, orbital controls, or layer slicing. |
| [`22_mouse_input.md`](docs/20_player_interface/22_mouse_input.md) | Implement raycasting, voxel selection, or drag-to-select. |
| [`23_user_interface.md`](docs/20_player_interface/23_user_interface.md) | Build or modify any UI panel, counter, toast, or labor window. |
| [`24_world_rendering.md`](docs/20_player_interface/24_world_rendering.md) | Work on fog, sky, atmosphere, world-edge treatment, or the slice view's visual behaviour. |

### 📁 Simulation & Systems — `docs/30_simulation_systems/`

| File | Read before you… |
|---|---|
| [`31_task_system.md`](docs/30_simulation_systems/31_task_system.md) | Add task types, change priorities, or modify the worker polling loop. |
| [`32_navigation_3d.md`](docs/30_simulation_systems/32_navigation_3d.md) | Modify pathfinding, walkability rules, or step-assist logic. |
| [`33_water_simulation.md`](docs/30_simulation_systems/33_water_simulation.md) | Touch springs, rivers, water volume/levels, flooding, irrigation or water rendering. |
| [`34_temperature.md`](docs/30_simulation_systems/34_temperature.md) | Work on room sealing, heat sources, the aging cellar temperature check, or food preservation. |

### 📁 Economy & Colony Content — `docs/40_economy_colony/`

| File | Read before you… |
|---|---|
| [`41_dwarf_agents.md`](docs/40_economy_colony/41_dwarf_agents.md) | Work on dwarf stats, needs, state machine, or skill system. |
| [`42_farming_brewing.md`](docs/40_economy_colony/42_farming_brewing.md) | Add crops, recipes, farm logic, or plant visual meshes. |
| [`43_mining_materials.md`](docs/40_economy_colony/43_mining_materials.md) | Add block types, change noise generation, or touch collapse logic. |
| [`44_crafting_workshops.md`](docs/40_economy_colony/44_crafting_workshops.md) | Work on the Smelter or Forge workshops, Blacksmith/Weaponsmith/Armorsmith professions, metalworking recipes, or ingot stockpile logic. |
| [`45_wildlife.md`](docs/40_economy_colony/45_wildlife.md) | Work on rabbits/deer/wolves/ducks, wildlife needs, ground/swim/flight navigation, flocks, hunting, spawning, inspection or future food connections. |

### 📁 World Events — `docs/50_world_events/`

| File | Read before you… |
|---|---|
| [`51_visitors.md`](docs/50_world_events/51_visitors.md) | Work on live wildlife arrival events and `WorldEventDirector`, or planned merchants, travelers, invaders, taverns and combat triggers. |
| [`52_combat_military.md`](docs/50_world_events/52_combat_military.md) | Work on military professions, the Armory room, enlistment/arming flow, patrol routes, invader waves, or combat resolution. |

### 📁 Asset Creation — `docs/60_asset_creation/`

| File | Read before you… |
|---|---|
| [`61_voxel_art_guide.md`](docs/60_asset_creation/61_voxel_art_guide.md) | Build or change a model: where the Hearthblock sources live, the cell vocabulary, the build/gallery/install workflow, file naming and the checklist. |
| [`62_furniture_catalog.md`](docs/60_asset_creation/62_furniture_catalog.md) | Plan a furniture milestone: every piece in the game with its Tier 1 design, the retired and planned pieces, and the Stonehearth catalogue comparison. |
| [`63_shared_art_standard.md`](docs/60_asset_creation/63_shared_art_standard.md) | Touch the voxel pipeline: grid, family contracts, production inventory, baked occlusion, materials, shadow proxies and the acceptance workflow. |
| [`64_hearthblock_art_direction.md`](docs/60_asset_creation/64_hearthblock_art_direction.md) | Make or review any art. The Hearthblock direction, furniture tiers, the art-over-rigs rule and the gameplay contracts every model keeps. |


---

## Session Start Protocol

1. Read this file.
2. Read the docs in the Document Map that cover the area you are about to change; the
   "Read before you…" column says which. Do not read every doc up front.
3. For recent context, skim the top of the changelog
   (`docs/00_dev_roadmap/00_changelog.md`) and any milestone doc it links for your area.

---

## Hard Rules (Never Violate)

These constraints appear in individual documents but are listed here for quick reference:

1. **Bedrock Protocol**: Never allow any action to modify or mine `Y = 0`. (`12_world_grid.md`)
2. **RTS-only camera**: No first-person, no WASD direct control. (`11_overview.md`)
3. **Block ID format**: Save files store namespaced strings, never runtime integers. (`12_world_grid.md`, `13_architecture.md`)
4. **3-block dwarf nav clearance**: Dwarf pathfinding requires 3 empty air blocks above every floor node. (`32_navigation_3d.md`) Wildlife uses separate species clearance; never relax dwarf NavGrid for animals. (`45_wildlife.md`)
5. **Single-tile plant footprint**: Plant visual overhangs must never have collision shapes. (`42_farming_brewing.md`)
6. **Visual vs logical dwarf height**: Use 3-block logical height for nav/collision, not the 3.3-block visual mesh. (`41_dwarf_agents.md`)
7. **No 3D UI elements**: All UI lives on a `CanvasLayer`. (`23_user_interface.md`)
8. **Deterministic world generation**: Generation must be fully deterministic from `world_seed`; use position-derived hashes or seeded noise, never `randi()` / `randf()` for streamed terrain identity. (`43_mining_materials.md`)
9. **Terrain identity lives in data**: Block identity must come from generated block data and JSON registries, not renderer tricks, fog, camera distance, or painted heightmaps. (`24_world_rendering.md`, `43_mining_materials.md`)
10. **Scene Decoupling Contract (recommended default)**: Prefer `@export` variables for scene references and signals for cross-node communication over explicit node paths (`$Node` / `get_node()`). The agent MAY now create and edit `.tscn` files and register autoloads / set the main scene / register `[input]` actions in `project.godot` — but keep logic scene-agnostic by default and only hardcode node paths when there is a clear reason. Never edit `.tres` or `.import` files. (`13_architecture.md`, File Ownership Rules)
11. **Slice concealment**: The normal slice view must never reveal undiscovered resources. Plane-cut floors render authored strata only; mining into a cave reveals its connected air and facing resources. The explicitly requested DEV Cave explorer is a temporary inspection exception, never saved discovery. (`24_world_rendering.md`, `43_mining_materials.md`, roadmap `68_caves_and_discovery.md`)
12. **Releasing a task is always cheap and always legal**: No task type may be designed such that abandoning it mid-way corrupts state. Release returns the task to PENDING, frees reservations, and never loses source-level progress; a future carried item is dropped at the dwarf's feet. (`16_first_dwarf_milestone.md` §2.8, `31_task_system.md`)

---

## Standing Decisions (owner)

These come from the owner and override older guidance in milestone docs.

- **Art: Hearthblock only.**
  - The direction and its rules live in three docs:
    - [64](docs/60_asset_creation/64_hearthblock_art_direction.md) defines the look and
      the gameplay contracts every model keeps;
    - [61](docs/60_asset_creation/61_voxel_art_guide.md) is the authoring workflow;
    - [63](docs/60_asset_creation/63_shared_art_standard.md) holds the technical rules.
  - Author in `tools/hearthblock/art/*.mjs` and regenerate
    `data/art/voxel_hearthblock.json` with `write_data.py`, or edit the family builders in
    `tools/voxel_assets/`. Install through `build.py`.
  - After model changes, re-render the menu pictures with:
    - `FurnitureCatalogThumbnails.gd`
    - `InventoryCatalogThumbnails.gd`
    - `GenerateFloorIcons.gd`
  - Old joints, pivots, envelopes and shape pins must not constrain the art. Change the rig
    data and the tests instead, but keep real gameplay contracts.
  - Content the game cannot produce yet keeps its placeholder model until its feature
    arrives.
  - Never delete the Tier 2 · Carpenter designs:
    - `data/art/studies/hearthblock_furniture_tiers.json`;
    - `diningTable()` and `bed()` in `tools/hearthblock/art/proposal.mjs`.
- **Builds only when asked.** Do not create, rebuild or package a Windows playtest unless
  the owner explicitly asks. Normal work uses the source project. When a build is wanted,
  export from the editor (Project → Export).
- **Focus: gameplay and usability.** Proactive performance work has been paused since
  2026-10-15. Profile again only for a repeatable hitch or a clear regression.
- **Colony size: 30 dwarves.** That is the intended maximum. Use 5, 20 and 30 dwarves for
  performance checks; larger counts are optional stress tests, not targets.
- **Saves: no backward compatibility during development.** Do not add legacy definitions,
  migrations or compatibility branches just to keep old development saves loading, unless
  the owner asks. Keep current-version save and load working.
- **Gems: no Jeweller.** There is no Jeweller profession or workshop and no
  cutting/polishing stage. Gem ids keep their `_raw` suffix; display names leave out "Raw".
- **Honey (future requirement).** Wildflowers must support honey production through nearby
  seasonal forage, and beekeeping must account for bloom state and clearing.
  - This isn't implemented yet; see
    [42](docs/40_economy_colony/42_farming_brewing.md#required-future-connection-wildflower-forage).
  - Resource placement stays depth-based.
- **Tests.** The job gate (the 46 tests listed in `tools/run_job_reliability.ps1`) is the
  regression bar for gameplay changes, so keep it green.
  - Add a focused regression test with each real bug fix.
  - Delete stale or broken tests rather than repairing them, unless other tests are built
    on them.
- **Verification stays proportionate.** For art and lighting, run one focused check and
  hand over for the owner's look. Stop when the owner says a change works.
- **Scratch and evidence.** Test output, review screenshots and reports go to `tmp/`,
  which git and Godot both ignore. Do not copy them into `docs/` unless the owner asks.

---

## Recording Changes

- Substantial work gets a milestone doc: `docs/00_dev_roadmap/NNN_snake_case.md`, using
  the next free number.
- Add a short dated entry at the top of
  [`00_changelog.md`](docs/00_dev_roadmap/00_changelog.md). Give what changed for the
  player, the milestone doc link, and whether the owner should restart Play or reload the
  project (see the Playtest Handoff Note below).
- When a rule or behaviour changes, update the design doc for that area.
- Do not add dated entries to this file.

---

## Godot Project Structure

```
Deepdraft/
├── AGENT.md              ← you are here (rules only)
├── CLAUDE.md             ← loads AGENT.md into Claude Code sessions
├── project.godot         ← agents may edit [autoload], the main scene and [input] only
├── docs/                 ← design docs (10–60) and milestone docs; Godot ignores this folder
│   └── 00_dev_roadmap/   ← 00_changelog.md, 00_open_issues.md, 00_todo.md (deferred work),
│                            one NNN_*.md per milestone
├── data/                 ← JSON definitions (art, audio, calendar, camera, construction,
│                            entities, furniture, materials, professions, rooms, sky, tasks,
│                            terrain, ui, visitors, weather, workshops, world_events, world_gen)
├── scripts/
│   ├── registries/       ← registry autoloads (BlockRegistry, CraftMaterials, DwarfAssets,
│   │                        PlacedEntityRegistry, SurfaceDetailRegistry, UIRegistry)
│   ├── systems/          ← simulation autoloads and scene-node systems; the authoritative
│   │                        autoload list and load order is in
│   │                        docs/10_core_foundation/13_architecture.md
│   ├── components/       ← reusable logic components, no autoload
│   ├── entities/         ← dwarf and animal agents
│   ├── ui/               ← UI scripts
│   ├── shaders/
│   └── tests/            ← headless tests: godot --headless --script res://scripts/tests/<Name>.gd
├── scenes/main/debug_world.tscn   ← the main scene
├── assets/               ← models, audio and UI art
├── tools/                ← art pipeline (hearthblock/, voxel_assets/), test runners, previews
└── tmp/                  ← scratch output; ignored by git and Godot
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
var block = BlockRegistry.get_def("base:terrain:rock:rock01")

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

### Playtest Handoff Note

Godot caches global script classes. After any work session that **adds a new `class_name`
script or registers an autoload**, tell the human to run **Project → Reload Current
Project** before playtesting — a stale cache half-loads the changes and produces ghost
bugs (first hit: doc 16 autoloads; second: doc 19 Phase 3, where pending tasks were
silently never assigned until the reload). Sessions that only edit existing scripts don't
need it.
