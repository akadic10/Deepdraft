# 254 — Full project review · 2026-10-20

**Status: REVIEW ONLY.** No production code, data, scenes or existing docs were
changed; this file is the only addition. Nothing here is scheduled work. Pick from
§3 and §8. Appendix B lists every side effect of the review's engine runs and how each
was reverted.

**Scope.** The working tree as of 2026-10-20: HEAD `d9414c44` plus 627 modified,
99 deleted and ~3,150 untracked files. That is ~53.6K lines of game GDScript (180
files), ~33K lines of tests (210 files), ~22K lines of tool GDScript plus ~180
Python tools, 59 scenes, 16 shaders and 126 JSON files. Ten parallel subsystem
reviews were run, plus cross-cutting checks and headless engine runs.

**Verification legend.**
- **✔** Verified first-hand: the code path was traced end to end, or the behaviour was
  reproduced in an engine run.
- **◐** Reported by a subsystem reviewer with file:line evidence, but not
  independently re-traced.
- **?** The mechanism was traced, but the cost or frequency is estimated.

---

## 1. Verdict

Deepdraft is an ambitious, unusually well-documented colony sim, and its hardest
engineering is genuinely good:
- worker threads never touch the scene tree;
- saves are written transactionally and validated, with fault-injection tests;
- attempt-generation fencing makes stale task callbacks harmless;
- world generation is deterministic from the seed;
- the water solver works in integer units and conserves volume;
- slice concealment is handled carefully on the main render paths.

The weak spots form a pattern rather than a scatter:
- **Features were added by growing about ten very large classes.** Those classes reach
  into each other's private state.
- **The same rules are re-implemented in several places that have drifted apart.**
  This covers terrain picking, concealment, footprint exclusion and item eligibility.
  The drift produced most of the bug classes below: Rule 11 leaks, "entombment"
  siblings and floating furniture.
- **Many paths rebuild everything on every edit.** These produce performance cliffs
  that grow with the colony's age.

**Overall grade: C+.** Subsystems range from B to C−. Nothing is unsalvageable, and the
highest-value work is small:
1. Protect the uncommitted work.
2. Fix one crash and one save-loss path.
3. Introduce four or five shared services that retire whole bug classes (§5).

| Subsystem | Grade |
|---|---|
| World simulation: water, wildlife, flora, time, audio | B |
| World core & generation | B− |
| Task system & navigation | B− |
| Storage, items, crafting, rooms | B− |
| Save/load | B− |
| Rendering, camera, slice/X-ray | C+ |
| UI | C+ |
| Dwarf agent & behaviours | C |
| Designation, placement & construction controllers | C− |
| Tests & tooling | C− (test content ≈ B, plumbing ≈ D) |

**Product note ✔.** Two of the three core-loop pillars have no code yet. No script
loads `data/workshops/brewery.json`, `aging_cellar.json`, `beehive.json` or
`data/visitors/merchant_catalog.json`, and the brewing and trading furniture was
retired in milestone 234. "Dig" and colony life are deep; "Brew → Trade" exists only as
data.

---

## 2. What was checked

| Check | Result |
|---|---|
| Headless load/compile of every script and scene (575 `.gd`, 14 `.tscn`) | ✔ All game code compiles. Two tools fail:<br>• `tools/BedBuildPanelFixture.gd` — `_build_styles()` no longer exists.<br>• `tools/performance/ProfileSaveManager.gd` — calls functions that moved to SaveFileStore. |
| JSON data (126 files) parsed with Godot's parser; every `res://` string resolved | ✔ 0 parse errors; 535/535 references resolve. |
| The 15 retired furniture definitions | ✔ No live code or data references remain. Save migration through `data/content_retirements.json` covers every site. |
| Gate: the 44 tests in `tools/run_job_reliability.ps1` | ✔ **44/44 pass** under the gate's own rule: exit 0, a pass marker, and stderr free of `ERROR:`/`SCRIPT ERROR:` lines. |
| Full suite, headless (208 runnable tests) | ✔ **159 pass, 49 fail.** Of the 49:<br>• 19 are environment-gated by design;<br>• 8 time out headless (probably need a GPU);<br>• 6 break on the furniture retirement;<br>• 5 are art checks run against the new art;<br>• 4 are fixture errors;<br>• 2 surface production errors;<br>• 2 are test API drift;<br>• 3 need investigation.<br>Details in Appendix A. |
| Export safety | ✔ Game code reads no plain files outside `data/`, and the export include filter covers `data/`. |
| Doc 177 deferred findings (2026-10-14) | ✔ **All three are still present** (§4.5, §4.7). |

---

## 3. Do first

Ranked by impact × likelihood ÷ effort.

| # | Issue | Sev | Ver | Effort |
|---|---|---|---|---|
| 1 | A stale `.git/index.lock` (since Oct 18 19:17) blocks commits and checkouts; 3 days of work are uncommitted — **fixed 2026-10-21: the lock is gone and the work is committed (`d367736d`, `1238cfa1`, `2add8fdc`)** | HIGH | ✔ | minutes |
| 2 | Hidden cave air in a mining zone → unbounded recursion and a stack overflow (§4.1) — **fixed 2026-10-21** | CRITICAL | ✔ | small |
| 3 | Saves from another build are deleted by the next save; the startup notice is never shown (§4.7) — **deferred by the owner; logged in [00 — To do](00_todo.md) 2026-10-21** | HIGH | ✔ | small |
| 4 | New Game / Load throw the colony away on one click, with no confirmation (§4.9) — **deferred by the owner; logged in [00 — To do](00_todo.md) 2026-10-21** | HIGH | ✔ | small |
| 5 | Load and New Game leave the clock paused and overwrite the saved pause preference; regression in uncommitted code (§4.7) — **deferred by the owner; logged in [00 — To do](00_todo.md) 2026-10-21** | MED | ✔ | small |
| 6 | The gate runner and `Export.ps1` are broken under Windows PowerShell 5.1 (§4.10) — **runner fixed 2026-10-21; `Export.ps1` deleted** | HIGH | ✔ | one line each |
| 7 | 6 tests broken by the furniture retirement; 2 tools don't compile; ~13 tools reference retired keys | MED | ✔ | small |
| 8 | `docs/` has no `.gdignore` (1,343 images get imported); 4,648 scratch files are still tracked in git (§6) — **fixed 2026-10-21: `tmp/` cleared, `docs/.gdignore` added, concept evidence removed** | MED | ✔ | small |
| 9 | Every terrain edit triggers whole-world rebuilds in the renderer and WorldData (§4.3) — **fixed 2026-10-21: per-column meshes and an in-place snapshot patch; a mined block's frame went from 284 ms to ~19 ms on the owner's save copy** | HIGH | ✔ | medium |
| 10 | The shared shader's instance uniforms cap the scene at ~8,192 lit objects; past that, meshes render black (§4.3) — **logged in [00 — To do](00_todo.md) 2026-10-21; `buffer_size` unchanged (owner)** | HIGH | ✔ | medium |

---

## 4. Findings by subsystem

Each finding gives the location, then what happens, then the fix. Paths are relative
to the project root.

### 4.1 Critical

**[CRITICAL][✔] Hidden cave air in a mining zone sends the miner into unbounded recursion**

Locations:
- [DwarfAgent.gd:784-789](../../scripts/entities/DwarfAgent.gd), with the same pattern at :802-805
- [MiningZoneComponent.gd:124-171](../../scripts/components/MiningZoneComponent.gd)
- [MiningDesignationController.gd:174, 915-920, 1919-1922](../../scripts/systems/MiningDesignationController.gd)

How it happens:
1. Designation deliberately treats undiscovered cave air as solid
   (`_designation_block_id_at` returns strata), so air cells end up in the zone.
2. `get_zone_block_work` reads the live block, finds air and returns `{}`.
3. `_begin_swinging` unreserves the block and calls `_zone_pull_next()`, but **does not
   add the block to `_pull_exclude`**.
4. `reserve_next` has no solidity filter, and its stand cells are sorted nearest-first.
   It therefore returns the same block, with the dwarf's own cell as the first stand.
5. `_zone_try_stand` sees `stand == current_cell()` and calls `_begin_swinging`
   again, which repeats step 3 without end.

When it triggers:
- When a dwarf mines into a cave, the cave is discovered, but the cleanup
  (`caves_discovered → _remove_blocks_from_zones`) is `CONNECT_DEFERRED`. A pull in the
  same frame can therefore pick an air cell that was just revealed.
- It can also trigger without any discovery, when a hidden cave cell is within reach
  of the dwarf's stand.

Consequences:
- In the editor: a stack-overflow break.
- In a release export: probably a hard crash.

Confidence: two reviewers found this independently, and every link in the chain was
re-traced against the code. It has not yet been reproduced in-engine.

Fix:
- On empty work, set `_pull_exclude[_zone_block] = true` and count a pull failure, at
  both call sites.
- Skip non-solid live blocks in `reserve_next` and `_recompute_destination`.
- Consider removing discovered cells synchronously.
- Add a regression test with a hidden cave behind a designated face.

**Resolved 2026-10-21.** The new `MiningHiddenAirTest` reproduced the crash
in-engine first: 16 GDScript stack overflows, then 2,048 `Stack underflow! (Engine
Bug)` errors. The fix differs from the sketch above, so that no cell can stall a zone
forever:
- **Dwarf** (`DwarfAgent._skip_zone_block`, used by `_begin_swinging` and
  `_process_swinging`): a reserved block with nothing to mine is unreserved and
  excluded for the rest of the lease before the next pull. It doesn't count as a path
  failure, because a cave the previous commit revealed isn't the worker's failure.
  Recursion is now bounded by the at most 29 blocks workable from one stand.
- **Controller** (`get_zone_block_work`, `play_zone_mining_impact`): when the live
  block isn't solid, the work falls back to `_designation_block_id_at`.
  - Undiscovered cave air is worked and struck as the strata the slice shows. The
    existing commit path then breaks into the cave, reveals it, spawns no goods and
    marks the cell done.
  - Known air yields no work, and is skipped as above until the deferred cleanup
    removes it from the plan.
  - Solid blocks behave exactly as before.
- **Checks.** `MiningHiddenAirTest` was added to the job gate (it covers both cases on
  real seed-1234 caves). The mining, ladder, job, support, navigation and construction
  regressions pass. `MiningLedgeAccessTest`'s pre-existing failure is unchanged.
- **Docs.** The rule is recorded in doc 43's "Cave discovery" section.

### 4.2 World core & generation — B−

- **[HIGH][✔] Every terrain edit re-serializes all solid edits and re-meshes every placed
  block.**
  - Where: `WorldData.gd:276-290` (`serialize_edits` walks every edit, allocates a dict
    and a String for each, and sorts with a GDScript lambda); `WorldRenderer.gd:2920-2922,
    2948-2981`.
  - Cost grows with the number of edits in the world, and it is paid on every mined
    block.
  - Fix: keep a per-chunk solid-override index in `set_block`, rebuild only the chunks
    that were touched, and keep `serialize_edits` for saves only. This is the same issue
    as §4.3 #1.
- **[MED][◐] Saves aren't tied to the generator version, and cave discovery is saved as
  list indices.**
  - Where: `InteriorTracker.gd:184-198`, `CaveLayout.gd:70,77`, `WorldGenerator.gd:243`,
    `SaveSnapshotValidator.gd:137`.
  - Changing `caves_v1.json`, the macro profile or the block-id rules can cause:
    - on load, a *different* undiscovered cave being revealed (a Rule 11 breach);
    - edits applied to a changed base world;
    - a seed that now fails validation never setting `_maps_ready`. The loading screen
      then soft-locks, and the same save is re-picked on every launch.
  - Fix: save a generation fingerprint, key caves by a stable anchor cell, and give
    generation failure an exit.
- **[MED][◐] The surface-material rules never run.**
  - Where: `WorldGenerator.gd:1654-1656, 1664-1742, 1800-1808`.
  - The strata branches cover every reachable height before the
    `y == surf_y → _pick_surface_block()` branch can fire. As a result:
    - lake and river banks get grass, against the "banks never grass" rule;
    - there is no steep-slope rock;
    - `_surface_slope`, `_is_water_bank`, `_dirt_variant` and related helpers are dead.
  - Fix: route surface cells through those rules on purpose, or delete them.
- **[LOW][◐] `set_block` can write into a chunk that was replaced mid-call.**
  - Where: `WorldData.gd:136-157`.
  - The chunk is fetched outside the mutex, so a concurrent `submit_chunk` can swap it
    first.
- **[LOW][◐] Generator teardown can hang.**
  - Where: `WorldGenerator.gd:459, 467-483, 524-527, 831-852`.
  - The map phases never check `_abort`, so quitting during loading blocks on
    `wait_to_finish`.
  - The `world_complete → _cleanup_thread` connection stays armed across reloads.
- **[LOW][◐] Registry robustness.**
  - Where: `BlockRegistry.gd:40-48, 230`, `WorldData.gd:121`.
  - `get_id` returns −1 unchecked. It is stored as 255 and serialized as `""`, after
    which every save fails validation.
  - JSON is parsed into typed dictionaries without checks.
  - Nothing asserts `AIR_ID == 0` or that there are at most 256 block types.
- **[LOW][◐] Diagnostics sit on the loading path.**
  - About 3M iterations of metrics run before any column is served.
  - `_generation_metrics` races with `DebugLoadingOverlay`.
  - A 45-line block report is printed every 16 columns.
  - About 250 lines are dead: `_fill_all_chunks*`, the listener-less `chunk_generated`
    signal, `get_column_top_y`, and others.
- **[LOW][◐] The burial radius is hard-coded to 10** (`WorldGenerator.gd:1877, 1896-1903`).
  If tin's `min_burial` changes, every sample falls back to a 441-read scan.
- **Note ✔ (from the test run).** OrdersShelf, Boulder, Scree and DwarfProfessionPanel
  test fixtures set the private `_maps_ready` flag over partial maps. This causes
  out-of-bounds `SCRIPT ERROR`s in `_generate_block_id`. The public
  `get_generated_block_id` is bounds-checked; the private function is not.

### 4.3 Rendering, camera, slice/X-ray — C+

- **[HIGH][✔] Every mining commit rebuilds world-wide structures on the main thread.**
  - Where: `WorldRenderer.gd:879-952, 2006-2014, 2920-2992`.
  - Each commit rebuilds the added terrain, re-walks all of `_visual_cut_blocks` for
    the cavity shell, and duplicates the overview snapshot.
  - Stutter therefore grows with the colony's age. The estimate for a 20k-mined /
    2k-placed colony is 50–200 ms per commit frame.
  - Fix: key the shell and added-terrain meshes by chunk, and dirty only the chunks
    around each edit.
  - **Fixed 2026-10-21.** The shell and added terrain are one mesh per 16×16 column
    (all heights), and edits rebuild only the columns they touch. The overview snapshot
    is patched per changed cell. Measured on a copy of the owner's save (49k edits):
    284 ms → ~19 ms per mined-block frame, against 6.9 ms idle. The rest is mostly the
    one shell column (8–12 ms). See [00 — Changelog](00_changelog.md).
- **[HIGH][✔] Instance uniforms in the shared lit shader cap the scene at ≈8,192 lit
  instances.**
  - Where: `scripts/shaders/underground_lighting_common.gdshaderinc:16-22`; `project.godot`
    `buffer_size=131072`.
  - Each instance uses 16 slots. Past the cap, the excess meshes render black.
  - Doc 153 already hit the default limit of 4,096 (dwarf parts rendered black), and
    raising the buffer only moved the limit.
  - Fix: move `actor_sky_access` and `doorway_light_*` into an actor/door-only shader
    variant, or into material parameters.
  - **Logged as a to-do 2026-10-21** in [00 — To do](00_todo.md). The owner
    chose to keep `buffer_size` as it is. Measured: 4,147 of 8,192 slots with 5 dwarves.
- **[MED][◐] With X-ray on, every interior change hides and rebuilds every water and
  damp-ground tile.**
  - Where: `XrayController.gd:245,279`; `WaterRenderer.gd:37,93,128-142`;
    `MoistureRenderer.gd:43,171-175`.
  - The rebuild has no budget, and the epoch bump discards jobs in flight.
- **[MED][◐] X-ray frees cached geometry before re-meshing it**
  (`XrayController.gd:190-195, 232-245`), so shells flicker while dwarves dig.
- **[MED][◐] Camera floor, cursor zoom, grab-drag and orbit pivot ignore the slice
  plane.**
  - Where: `Camera.gd:402-432, 668-708, 750-789`.
  - Under a high mountain, the cut floor can't be approached closer than about 80
    blocks, and drag locks onto the invisible surface.
- **[LOW][◐] Rain uses UndergroundLighting's private buffers.**
  - Where: `WeatherPrecipitation.gd:61-62`; `UndergroundLighting.gd:136-148, 375-393`.
  - The `_air` and `_roof` caches it fills are unbounded.
- **[LOW][◐] The Block Inspector breaks Rule 11** (`WorldRenderer.gd:681-694`). It sits in
  the ungated Development dock and prints exact `hit:`/`generated:` ids for cut floors.
- **[LOW][◐] No face is drawn between a placed block and a designation**
  (`WorldRenderer.gd:907, 2974-2975`), leaving a see-through hole.
- **[LOW][◐] Steady per-frame overhead:**
  - `visible = true` is set on 1,024 tiles every frame, and a mutex-guarded deep copy of
    stats is taken every frame (`WorldRenderer.gd:1853,1856`);
  - X-ray re-filters every dwarf sub-mesh;
  - the sky uses REALTIME radiance;
  - each new lighting slot re-uploads the whole `Texture2DArray` page;
  - camera X/Z is never clamped.
- **Architecture:**
  - About 600 lines are a dead streamed-renderer path: `_rebuild_chunk` and
    `_rebuild_surface_region` have no callers, and `ChunkMesher` is only used for
    `_add_quad`.
  - The rule for "which block id may this face show" is implemented 5 times: overview
    top, overview sides, cavity shell, XrayGeometry and TerrainExplorerProvider.
  - `slice_debug_timing` defaults to true and prints on every slice step.
- **Strengths:**
  - Rule 11 holds on every normal render path.
  - Overview threading is correct: epochs, revisions, budgeted uploads, and workers
    joined on exit and reload.
  - No RID or MultiMesh leaks.

### 4.4 Dwarf agent & behaviours — C

- **[CRITICAL]** The mining recursion lives here; see §4.1.
- **[HIGH][✔] Any ladder or bridge change anywhere cancels every in-flight meal, game and
  promotion.**
  - Where: `DwarfAgent.gd:1807-1811, 1891, 1959-1967`; `NavGrid.gd:108-122`.
  - `ladder_revision` bumps on every ladder or bridge edit. `_repath_walk()` then calls
    `walk_to()`, and the first lines of `walk_to()` cancel recreation, eating and
    promotion. Every walking dwarf also runs a synchronous A* in the same frame.
  - Fix: route repaths through whoever owns the current walk, and repath only routes
    that touch the changed structure.
- **[HIGH][?] Seat validity re-runs placement checks costing chairs × furniture.**
  - Where: `FurnitureSeating.gd:163-198`, via `DwarfIdleBehavior.gd:278-280`,
    `DwarfDining.gd:159-161` and `BoardGameRecreation.gd:155`.
  - It happens on every `navigation_revision` change, which covers every mined block.
- **[MED][◐] Interrupting a dwarf mid-step cancels the activity it just started.**
  - Where: `DwarfAgent.gd:866-873, 882-893`.
  - A meal start or a player promotion triggers `_settle_missing_support → abort_task`.
- **[MED][◐] Hunger aborts work (dropping cargo) before knowing whether food exists.**
  - Where: `DwarfFoodBehavior.gd:59-75, 143, 287`.
  - It retries every 0.25 h even when the shortage flag is set.
- **[MED][?] String pulling costs O(lookahead²) per walking dwarf** (`DwarfAgent.gd:1871-1883`).
- **[MED][?] Bursts of synchronous full A* inside one tick.**
  - Where: `DwarfAgent.gd:752-773, 1176-1193, 1765-1766, 1801`; `DwarfBedRest.gd:88-96`.
  - Sources: stand-cell tries, handling stands, privacy-filtered bed searches that
    bypass the cache, and ladder/bridge exit retries every frame.
- **[LOW][◐] Smaller issues:**
  - Promotion treats BUDGET_EXHAUSTED as reachable and leaves the tool loose
    (`DwarfEquipment.gd:101-127`).
  - Bridge evacuation grants a full night's sleep (`DwarfAgent.gd:1751, 594`).
  - A Label3D DEV name tag breaks Rule 7 (`DwarfAgent.gd:2105-2118`).
  - Idle and rest validators do linear scans every frame.
  - `_exit_tree` neither deregisters the dwarf nor drops its cargo. That is a latent
    risk for any future death or emigration path.
- **Architecture:**
  - Path ownership is implicit: about 8 behaviours write `_move_path` directly.
  - About 25 scattered idle-pool notifications are healed by a slow reconcile (about
    12.5 s at 100 dwarves).
  - Outcomes depend on frame rate.
  - Each dwarf has about 12 unique materials plus duplicated silhouette meshes.
- **Strengths:**
  - Attempt fencing.
  - No `await`, timers or tweens.
  - Claims are temporary and checked against their owner.
  - Rule 6 is respected.

### 4.5 Designation, placement & construction controllers — C−

- **[HIGH][✔] Installing furniture registers occupancy over another dwarf standing in the
  footprint.** This is a sibling of the builder-entombment bug.
  - Where: `FurniturePlacementController.gd:1185-1208, 1289-1292`;
    `FurnitureGhostComponent.gd:239-257`.
  - `_can_build_ghost` returns true for plain floor pieces with no actor check. Stand
    selection excludes only the ghost's own footprint.
  - `ConstructionController.build_reason` (320-325) already performs this check.
- **[HIGH][✔] `max_drag_length` (40) is never enforced** (`MiningDesignationController.gd:966-967`).
  `extent = maxi(size, extent - size)` subtracts one brush width instead of clamping,
  so screen-height drags create zones of 20k+ blocks.
  **Fixed 2026-10-21:** the owner set the cap to 32. Each axis now stops at the most whole
  brush steps that fit; covered by the gate test `MiningDragLimitTest`.
- **[HIGH][◐] Every mined block re-processes the whole zone.**
  - Where: `MiningDesignationController.gd:1420-1526, 1983-1985`;
    `MiningZoneComponent.gd:245-275, 380-382`.
  - The overlay edges are deduplicated with string keys, and the destination is
    recomputed for the whole zone.
- **[HIGH][◐] Construction preview costs cells × world on every mouse motion.**
  - Where: `ConstructionController.gd:129-130, 187-193, 310-349, 364-366`;
    `ConstructionWork.gd:33-50`.
  - `obstacle_snapshot()` exists, but the preview doesn't use it.
- **[MED][◐] Rule 11 leak: furniture, stockpile and construction rays see through hidden
  caves.**
  - Where: `FurniturePlacementController.gd:1638-1643`;
    `StockpileDesignationController.gd:729-734`; `ConstructionController.gd:172, 313-314`.
  - Players can place furniture or zones inside an undiscovered cave.
- **[MED][✔] Doc 177 #3 is still open: no floor-support revalidation for floor
  furniture.**
  - Where: `FurniturePlacementController.gd:713-730, 1199-1208`.
  - Ghosts install in mid-air, and mining under a bed leaves it floating. Mining
    designation ignores ghost, installed and stockpile footprints
    (`MiningDesignationController.gd:885-906`).
- **[MED][✔] Doc 177 #2 is still open: uninstall picks the nearest stand with no route
  check.**
  - Where: `InstalledFurnitureComponent.gd:92-110`; `TaskManager.gd:609-615`.
  - Multi-goal probing exists for wall pieces only.
- **[MED][◐] LadderSystem treats `task_released` as "task gone" and posts duplicate leases**
  (`LadderSystem.gd:27, 234-236`). BridgeSystem (310-314) avoids this.
- **[MED][◐] The inactive stockpile tool's click handler steals clicks from the active
  mining tool** (`StockpileDesignationController.gd:160-170`).
- **[MED][◐] Zone overlays go stale under X-ray** (`MiningDesignationController.gd:184-198`).
- **[LOW][◐] Smaller issues:**
  - Label3D drag readouts break Rule 7 (`MiningDesignationController.gd:474-493`;
    `StockpileDesignationController.gd:338-349`).
  - `ObjectPicking.gd:9` calls `is_proxy(node)` before `is_instance_valid` (uncommitted
    change).
- **Architecture:**
  - There are four drifted voxel DDA raycasts: Mining (1025), Furniture (1614),
    Stockpile (706) and `ObjectPicking.terrain_hit` (72). Only Mining handles
    concealment.
  - Ladder and Bridge are copy-paste twins, and `describe()` doubles as the structural
    integrity check.
  - Cross-designation exclusion is pairwise and lopsided: mining checks nothing.
  - Work-source ID ranges are kept by convention only.
- **Strengths:**
  - Hard Rule 1 is enforced in depth, at designation and again at every write.
  - The ghost item claim/re-claim protocol.
  - Gestures handle their own release.

### 4.6 Storage, items, crafting, rooms — B−

- **[HIGH][◐] Loose-item scans cost O(loose items × zone cells).**
  - Where: `StorageComponent.gd:57-58, 423, 453, 462`; `ItemDropManager.gd:316, 427, 461`;
    `StorageStackSlots.gd:21-25`.
  - `_can_haul_key → has_room` runs for every loose node, with no per-key cache.
- **[HIGH][◐] A full inventory snapshot is taken up to every frame, even with no orders.**
  - Where: `CraftingManager.gd:32-34, 56-60, 71-74`; `ColonyInventory.gd:40-44`;
    `StockpileManager.gd:356-372`.
- **[MED][◐] Any release throws away a craft batch's staged ingredients.**
  - Where: `WorkerCraftOrder.gd:99-105, 122-124, 177-184`.
  - This breaks the spirit of Rule 12. Fix: hold staged items under an order-owned
    claim.
- **[MED][◐] Stockpile zones never react to terrain edits.** Mining under a stocked cell
  leaves the node floating, and haulers keep depositing there
  (`ItemDropManager.gd:691-709, 723-731`).
- **[MED][?] `hauling_revision` is bumped by almost every event, so planners keep
  restarting** (`StockpileManager.gd:61, 459-461, 480-509`; `FurnitureFetchPlanner.gd:10`).
  A multi-wake fetch plan may never finish.
- **[MED][?] Room detection runs almost continuously near mining, and can be starved.**
  - Where: `RoomManager.gd:144-146, 339-343, 356-362`; `RoomRebuild.gd:82-101`.
- **[LOW][◐] Container restore drops units above capacity** (`ContainerStorageComponent.gd:70-81`).
  Current content can't reach this.
- **Note ✔.** No current furniture definition has a `storage` block. That leaves
  `ContainerStorageComponent`, the StockpileManager container registry and about 9
  `is ContainerStorageComponent` checks dormant (test-only).
- **Strengths:**
  - No item duplication was found, and the only loss path is the unreachable container
    restore above.
  - `commit_haul` validates before it mutates.
  - Teardown ordering is correct.

### 4.7 Save/load — B−

- **[HIGH][✔] Intact saves from another build are treated as corrupt and deleted.**
  - Where: `SaveFileStore.gd:88-97, 122-125, 151-157`; `SaveSnapshotValidator.gd:134-137`;
    `SaveManager.gd:125-131, 144-166, 617-624`.
  - Validation rejects a newer `schema_version` or any
    `water.layout_version != RiverLayout.VERSION`. An invalid primary is never rotated
    to the backup slot, and the next save deletes it.
  - At startup the "No valid save could be loaded" notice reaches only `push_warning`:
    `WorldRenderer._ready` (line 306) resolves the startup save before
    `DockUI._ready` (line 132) registers.
  - Scenario: the player runs a build with a changed river layout. They silently get a
    new world, and within a couple of autosaves and quicksaves the old colony is gone.
  - Fix:
    - Delete only a primary that fails JSON parsing.
    - Rename any other invalid file aside as `*.rejected-<utc>.json`.
    - Queue notices until the dock registers.
  - **Logged as a to-do 2026-10-21** in [00 — To do](00_todo.md).
- **[MED][✔] Doc 177 #1 is still open: unknown furniture or item keys silently destroy
  pieces and their contents on load.**
  - Where: `FurniturePlacementController.gd:1457-1458, 1496-1497`;
    `ItemDropManager.gd:203-205, 236-238`.
  - Fix: route unknown keys through the retirement spill path, or reject the file and
    set it aside.
- **[MED][✔] Pause regression in the uncommitted code.**
  - Where: `SaveManager.gd:194-195, 200, 354, 371, 376`, together with the
    `WorldClock.paused` getter (`WorldClock.gd:34`).
  - The getter includes loading holds. During startup or a load, SaveManager therefore
    captures "paused" while the loading screen's hold is active, sets the *player* pause,
    and later restores that captured `true`.
  - Result: the game resumes paused, and the saved pause preference is overwritten.
    `WorldLoadingScreenTest` fails on both of its checks.
  - **Logged as a to-do 2026-10-21** in [00 — To do](00_todo.md). The code is committed
    now (`d367736d`). Re-check: the test passes on a fresh profile and fails these two
    checks once a save exists at startup.
- **[MED][◐] The main-thread autosave stall is back.**
  - Where: `SaveManager.gd:253`; `WorldData.gd:276-287`; `InteriorTracker.gd:180-186`.
  - Schema 2 serializes edits and exploration synchronously, with lambda sorts.
  - Exploration also saves cave air cells that the restore re-derives anyway.
- **[MED][◐] Each save validates 5 times and parses 4 times.**
  - Where: `SaveFileStore.gd:37, 52, 71, 92, 104, 139`.
  - Peak memory holds about 3 parsed 12.5 MB trees, and the output is pretty-printed with
    tabs.
- **[LOW][◐] Smaller issues:**
  - Files are replaced by remove-then-rename, and a validated `.tmp` is never recovered
    (`SaveFileStore.gd:109-130, 177`).
  - The retirement report is computed and then discarded (`SaveFileStore.gd:207-212`).
  - The test-storage guard accepts `user://saves` itself (`SaveManager.gd:78-81`).
  - The validator hard-codes data values, for example duck `y < 158`
    (`SaveSnapshotValidator.gd:117, 211, 362`).
  - The water-restore guard is an `assert`, which release builds strip
    (`SaveManager.gd:485`).
- **Architecture:**
  - One broken record blocks all saving for the session; consider a rescue slot.
  - Ties between equal restore priorities (15, 70) depend on an unstable sort.
  - There is no generator fingerprint (§4.2).
- **Strengths:**
  - The worker thread is isolated correctly.
  - An invalid primary can never overwrite a good backup.
  - Every write is read back and validated.
  - Migrations run in memory.
  - Rules 3 and 8 hold.

### 4.8 World simulation — B

- **[MED][◐] Starting wildlife is placed before about 99% of tree trunks register.**
  - Where: `WildlifeManager.gd:61-64`; `SurfaceFloraSpawner.gd:217-224`.
  - Animals can spawn inside trunks and stay stuck permanently.
  - Which animals spawn where depends on load timing.
  - Fix: wait for `flora.get_spawn_stats().ready`.
- **[MED][◐] Every save load holds the loading screen for at least (seasonal plants ÷ 4)
  frames of refreshes that change nothing.**
  - Where: `SeasonalRefreshQueue.gd:7, 23, 35-38, 53`; `SurfaceDetailManager.gd:636-647,
    852`.
  - That is about 7.8 s for seed 1234, and the visual queue is also doubled on restore.
- **[MED][?] Water occupancy has no hysteresis.**
  - Where: `WaterManager.gd:190-193, 262-263`; `NavGrid.gd:165-170`.
  - Each threshold flip invalidates about 15 NavGrid chunks per column, so navigation
    churns along rivers.
- **[LOW][◐] Smaller issues:**
  - Removing any block anywhere below a water stone cancels its pack order
    (`WaterStones.gd:89-97`).
  - The water topology cache grows without bound, fed by ambient-audio scans
    (`WaterFlow.gd:41-43`).
  - Land-animal arrival searches ignore the 2 ms budget (`EdgeArrivalPlanner.gd:28-51`).
  - Water catch-up debt is unbounded and is saved (`WaterManager.gd:148-157, 289`).
- **Weather RNG ✔:** deterministic in every real flow. The startup warning is a
  headless, no-world artifact, and weather is presentation-only.
- **Architecture:**
  - WildlifeManager is a per-species switchboard.
  - `DuckAgent` re-implements `GrazerAgent.advance`.
  - Water speed depends on how many cells are active.
  - `WaterManager.initialize()` loops over 1M columns in one frame.
- **Strengths:**
  - The water solver is conservative and persists exactly.
  - Gameplay RNG is persisted.
  - Rule 4 holds: wildlife never touches NavGrid.
  - Time handling is analytic.

### 4.9 UI — C+

- **[HIGH][✔] New Game and Load discard the colony on one click.**
  - Where: `data/ui/dock.json:581-589` (uncommitted); `DockUI.gd:699-710`;
    `SaveManager.gd:185-203`.
  - No confirmation dialog exists anywhere in the UI.
  - **Logged as a to-do 2026-10-21** in [00 — To do](00_todo.md).
- **[MED][◐] Keyboard focus is never released on world clicks.**
  - Where: `Camera.gd:359-361`; `DwarfRosterPanel.gd:54-60`; `WorkerCraftingPanel.gd:82-90`;
    `DockIconButton.gd:24, 52-55`.
  - After typing in a search field, the camera keys stay dead.
  - Dock icons use FOCUS_ALL, so arrow-key panning also moves GUI focus around the dock.
- **[MED][✔] The Development menu ships in every build.**
  - Where: `data/ui/dock.json:133-145, 678-816`.
  - It offers spawners, +500 tasks, dam edits, time skips, the Cave explorer and the Block
    Inspector.
  - Only `SaveManager.gd:75` uses `OS.is_debug_build()`, and no code uses feature tags.
- **[MED][◐] UI does not scale above 2560×1440.**
  - Where: `project.godot` [display]; `UITheme.gd:27-30`.
  - There is no stretch mode, and fonts are fixed at 11–17 px. On 4K the UI renders at
    about 67% of its 1440p physical size.
- **[MED][?] Per-dwarf UI work is bunched into single frames.**
  - Where: `DwarfRosterPanel.gd:169-235`; `DwarfNeedIndicators.gd:21-35, 91-107`.
  - Every 0.35 s the roster runs a full `describe()` for each dwarf.
  - Every 0.25 s each flagged dwarf gets an occlusion DDA ray, all in the same frame.
- **[LOW][✔] Portrait updates can get permanently stuck.**
  - Where: `DwarfRosterPanel.gd:340-348`.
  - `_queue_portrait_update` awaits `get_tree().process_frame` twice. If the panel leaves
    the tree in between, the second await errors and `_portraits_pending` stays true.
  - `StartupSaveTest` surfaced this.
- **[LOW][◐] Smaller issues:**
  - Esc in Professions also closes the roster (`DockUI.gd:475-479`).
  - The food-warning tooltip can never show (`ColonyFoodWarning.gd:12, 41`).
  - Hidden pollers keep running: DebugLoadingOverlay every 0.15 s (it also resets
    TaskManager's probes/s window) and OrdersShelf every 0.1 s.
  - The layout file is rewritten synchronously, and not atomically, on every window
    open and close (`UIWindowManager.gd:123, 132, 193-254`).
  - The legacy World Build and Block Inspector windows can be dragged off-screen.
  - About 150 lines of legacy menu code are dead.
- **Architecture:**
  - DockUI is a god-object with about 12 concerns.
  - Esc precedence is implicit across 6 nodes.
  - `_label` is re-implemented in 9 files, and the catalog tile builder exists 3 times.
  - The tool protocol is duck-typed.
  - Registration depends on scene child order.
- **Strengths:**
  - Input routing is sound, with no click-through.
  - Layout persistence tolerates corrupt files and clamps windows on screen.
  - Signal hygiene is good.
  - Refreshes are throttled and deep-compared.

### 4.10 Tests & tooling — C−

- **[HIGH][✔] The gate runner and the export script fail under Windows PowerShell 5.1.**
  - Where: `tools/run_job_reliability.ps1:25,34` and `tools/windows_playtest/Export.ps1:22,31`.
  - Neither caches the process handle, so `ExitCode` is null under 5.1. Every test then
    "FAILs" and every export "fails". They only work under pwsh 7.
  - Fix: add `$null = $process.Handle` right after `Start-Process`. This review's own
    first run reproduced the failure.
- **[HIGH][✔] No CI and no hooks.**
  - The gate covers 44 of 210 tests, with no world-generation, water, lighting or art
    tests.
  - The furniture retirement broke at least 6 tests, and nothing flagged it.
- **[HIGH][◐] Many tests can't run with the documented command.**
  - 14 tests require a test-specific APPDATA substring.
  - GPU-only tests aren't tagged.
  - Some tests read inputs from `tmp/`, including player-save copies.
  - Five tests write into `res://tmp/...` without a mkdir, overwriting tracked files.
- **[MED][✔] Tests write into the developer's real profile.**
  - `WaterPresentationTest` saved the water dev window into the real
    `user://ui_layout.json`. It was restored; see Appendix B.
- **[MED][◐] Inheritance is used as a fixture library.**
  - Example: `ObjectExplorerTest` has 129 transitive descendants.
  - Chains run up to 7 levels deep.
  - About 90 tests drive `_run_scheduler()` and `_process(.05)` by hand instead of
    running the real frame order.
- **[MED][✔/◐] Tests are heavily coupled to private internals.**
  - There are about 5,400–5,600 private-member accesses, including 26 `call("_x")`
    string calls.
  - Two oracles depend on overrides: the DijkstraGrid `_heuristic`, and fault injection
    on the Nth `_read_snapshot` call.
  - 11 tests compile frozen `docs/**/*.before.txt` copies of old sources.
- **[MED][◐] Timing and shared-state flakiness.**
  - Gate tests use 100 ms wall-clock budgets and real-time hover sleeps.
  - One test reseeds the global RNG to predict a mining drop.
  - `while not _maps_ready` loops have no watchdog.
  - Two tests share one save directory, and one of them wipes it.
- **[MED][◐] Baseline harness scripts in `docs/` swap production sources in place**
  (for example `concepts/autosave_20261015/Repeat30.ps1`). A hard kill leaves stale
  code behind. Fix: run baselines from a `git worktree`.
- **[LOW][◐] Smaller issues:**
  - Two tests can never fail (`WaterPresentationTest`, `WaterFloodPresentationTest`).
  - The gate's marker regex is unanchored, so intermediate `_OK` markers satisfy it.
  - Tool rot:
    - `TunnelLightingStudy`, `UndergroundWorldReview` and 10 `Verify*.gd` tools
      reference retired keys;
    - `AuditPack.gd` requires at least 41 furniture models, but the tree has 29;
    - `RunShutdown.ps1` expects save schema 1.
  - The export doesn't exclude the 59 MB `assets/models/studies`.
- **[LOW][◐] Python tooling hygiene.**
  - 184 files and no requirements file.
  - 65 retired stubs are still imported as libraries.
  - 37 files hard-code absolute paths, including the developer's real save and Codex's
    private Python runtime.
  - Audio generators write straight into `assets/` with no `--check` mode. (12 live
    generators do have a good `--check` mode.)
- **Coverage:**

  | Area | Strength |
  |---|---|
  | NavGrid | Strong (Dijkstra oracle) |
  | TaskManager release | Strong |
  | Save atomicity | Strong |
  | Water | Strong, but ungated |
  | Storage conservation | Medium-strong |
  | Generation determinism | Medium: same-process only; a hash is computed but never compared |

---

## 5. Cross-cutting architecture

**Shape.**
- The main scene (`debug_world.tscn`) holds 29 sibling systems and 7 CanvasLayers, with
  zero `[connection]` entries, alongside 20 autoloads.
- Systems find each other through 129 group lookups and through globals.
- Nine files over 900 lines hold about 19K of the 53.6K game lines.
- About 1,100 dead lines were identified, mostly in WorldRenderer, WorldGenerator,
  DockUI and the mining controller, and the container-storage code is dormant.

**Coupling (✔ counts).**
- NavGrid, WorldGenerator, BlockRegistry and TaskManager are each used directly by 39–46
  of the 180 game files.
- Game code makes 73 private-member accesses into autoloads alone (for example
  `TaskManager._agents` ×26 and `WorldGenerator._maps_ready` ×11). There are many more
  into scene nodes, such as `furniture._installed`, `renderer._cavity_shell_dirty` and
  `drops._loose`.
- `SaveManager.pack_v`/`unpack_v` (79 call sites) make 32 files depend on the save
  system just for vector encoding.
- WorldGenerator doubles as the world-dimensions service (`WORLD_SIZE_X/Z`, `world_seed`,
  `get_surface_y`).

**Drifted duplicates:**
- 4 voxel DDA raycasts;
- 5 "may this face show this id" rules;
- Ladder/Bridge twins;
- 5 TaskManager matchers;
- about 10 StockpileManager eligibility scanners;
- per-species wildlife loaders;
- 9 copies of the UI `_label` builder.

**The registry rule is bent.** Several scene nodes parse their own JSON:
MiningDesignationController, FurniturePlacementController, WildlifeManager,
WorldEventDirector, SurfaceFloraSpawner, CraftingManager and ItemDropManager.

**Shared services that would retire whole bug classes:**

| Service | Retires |
|---|---|
| `TerrainQuery`: one concealment-aware ray/pick/sample | Rule 11 leaks; raycast drift (§4.3, §4.5) |
| `FootprintClaims`: one registry for furniture, ghosts, zones, construction, designations and actors | Entombment siblings, floating furniture, zone floors (§4.5, §4.6) |
| `MovementOwner` in DwarfAgent: one owner per walk, with a repath callback | Ladder/bridge cancellations; implicit path ownership (§4.4) |
| Per-chunk indices for edits, zones and rooms, with incremental rebuilds | Per-edit whole-world cost (§4.2–§4.6) |
| A typed `RouteProof` handed from the scheduler to the executor | The 24k/6k mismatch; stale proofs (§4.4, below) |
| `SaveCodec` utility plus a generation fingerprint | 32-file coupling; safe handling of saves across versions (§4.7) |

**Task system & navigation — B−.** Folded in here because these issues span the
scheduler and its executors.
- **[HIGH][✔/?] The scheduler proves routes the executors cannot walk.**
  - Where: `NavGrid.gd:38-39`; `WorkRouteProbe.gd:7-16`; `task_config.json:66`;
    `DwarfAgent.gd:1815, 973-977`.
  - Scheduler proofs escalate up to 24,000 nodes, but executors walk with a synchronous
    6,000-node `find_path`. The only bridge between them is a path cache with a 5 s TTL.
  - Result: proven work fails at execution. The cargo is dropped, this repeats three
    times, then the task is released, with a frame hitch each time.
- **[MED][?] Unrelated churn discards long planning searches.**
  - Where: `TaskManager.gd:745-749, 834-838, 973-976`; `WorkerCraftOrder.gd:28`.
- **[MED][?] The backoff for unreachable tasks is defeated near active work.**
  - Where: `TaskManager.gd:636, 1305, 1379, 1451-1464`.
  - `_blocked_count` is never decremented.
- **[MED][◐] The progress watchdog treats a detour as a stall.**
  - Where: `WorkAttempt.gd:19-31`; `TaskManager.gd:1573-1592`.
  - Cargo gets dropped mid-tunnel, and the order is paused as "Needs attention".
- **[MED][✔] The NavGrid path cache has no size limit, and every invalidation scans all
  of it** (`NavGrid.gd:187-205, 285, 715-727`).
- **[LOW][◐] Smaller issues:**
  - Journal pruning costs O(records × live sources) (`WorkJournal.gd:48-51`).
  - Spawning ignores NavGrid, so a dwarf can start trapped in a river column
    (`DwarfDirector.gd:286-303`).
  - `_craft_match` never records `ladder_revision`, so pickup proofs go stale after a
    ladder is removed.
  - `barrier_blocks_segment` allocates on every A* edge once any fence exists.
- **Strengths:**
  - No reservation leak, double-assign or orphaned ASSIGNED task was found across any
    way a task can end.
  - Rules 4 and 12 hold.
  - Supervision and reconcile give real self-healing.

---

## 6. Repository & process health (all ✔)

- **The repo is locked.** `.git/index.lock` is 0 bytes and was created 2026-10-18 at
  19:17. No git process is running. Commits and checkouts fail until it is removed.
  There are also 66 garbage temporary objects (382 MB) from interrupted git writes, and
  `_to_delete/git_index.lock.stale` shows this has happened before. **Fixed 2026-10-21:**
  the lock and the garbage objects are gone, and `_to_delete/` is deleted.
- **Uncommitted work.** 627 modified, 99 deleted and about 3,150 untracked files,
  including 101 changed scripts, the furniture retirement, about 540 asset files and
  `VoxelFeed/`. The last commit was on Oct 17. **Fixed 2026-10-21:** all of it is
  committed (`d367736d`, `1238cfa1`, `2add8fdc`).
- **Commit style.** One-word messages, with 600–2,600 files per commit. History is not
  reviewable, and bisecting is impractical.
- **Repository weight.**
  - The HEAD tree is 1,118 MB:

    | Directory | Size | Share |
    |---|---|---|
    | tmp/ | 668 MB | 60% |
    | docs/ | 308 MB | 28% |
    | assets/ | 134 MB | 12% |
    | scripts/ | 4 MB | <1% |

  - History contains an 84 MB `ffmpeg.exe`, a 13 MB `.pck`, AVI renders and copies of
    player saves.
  - There is no LFS, and `.git` is 1.5 GB.
- **`tmp/` is 8.3 GB on disk.** 4,648 files are still tracked even though `.gitignore`
  covers the folder.
- **`docs/` has no `.gdignore`.** Godot imports 1,343 doc images (1,331 `.import` files,
  475 of them tracked). That swells `.godot/imported` to 405 MB and slows editor start.
  Opening the editor during this review created new `.import` files under
  `docs/00_dev_roadmap/concepts/252_apple_harvest/`.
- **AGENT.md is 155 KB, and its first 1,898 lines are a changelog.** The Session Start
  Protocol requires reading about 744 KB (~186K tokens) before any work, which is more
  than most agent context windows. The structure section is stale (it describes
  "DwarfVoxel/"). **Fixed 2026-10-21:**
  - AGENT.md is rules only (317 lines);
  - the entries moved to `00_changelog.md`;
  - agents now read only the docs for their area;
  - a new `CLAUDE.md` imports AGENT.md.
- **Root clutter.** 9 `Launch *.cmd` files and `godot_streaming_test.log`. The main scene
  is `debug_world.tscn`.

---

## 7. Strengths worth keeping

- **Threading discipline.** Overview building, water meshing, the save worker and the
  generator never touch the scene tree or RenderingServer from workers, and all are
  joined on teardown and reload.
- **Saves.** Transactional and validated, with fault-injection tests; seeds are
  deterministic, ids are namespaced, and RNG states are stored as exact text.
- **Task lifecycle.** Attempt-generation fencing, a consistent release protocol, and
  supervision plus reconcile; no reservation leaks were found.
- **Hard Rules.** Rule 1 is enforced at a single write chokepoint and again at
  designation time. Rules 3, 4, 6 and 8 hold throughout.
- **Items and water.** No item duplication anywhere, and a conservative integer water
  solver.
- **Documentation.** Decisions and evidence are recorded, and fixes come with
  regression tests. Few projects have this discipline.

---

## 8. Suggested plan

**Phase 0: protect the work (today).**
1. Remove the stale `.git/index.lock`.
2. Commit the working tree in a few logical commits (retirement, art migration,
   fruit/apples, save schema 2, …).
3. Add `docs/.gdignore`.
4. Run `git rm -r --cached tmp`. Files stay on disk.
5. Keep player-save copies out of git.

**Phase 1: crash and data safety.**
1. Fix the mining recursion (§4.1) and add a regression test.
2. Never delete saves that fail validation; set them aside instead.
3. Queue startup notices until the dock registers.
4. Add confirmation dialogs for New Game and Load.
5. Fix the pause regression.
6. Route unknown save keys through the retirement spill path.
7. Fix the handle bug in the runner and in `Export.ps1`.
8. Repair the 6 retirement-broken tests and the 2 broken tools.

**Phase 2: performance cliffs.**
- Per-edit whole-world rebuilds.
- The shader instance-uniform cap.
- Zone re-processing and the drag cap.
- The construction preview.
- Loose-item scans and the inventory snapshot.
- Seat validity.
- Capping the path cache.

**Phase 3: gameplay correctness.**
- Ladder/bridge repath cancellations.
- Scheduler proofs that executors can walk.
- `FootprintClaims`: covers the entombment sibling, floor support and stockpile terrain
  edits.
- `TerrainQuery`: covers the Rule 11 ray leaks.
- Rule 7 Label3D readouts.
- Wildlife spawn ordering.
- Gating the dev tools.

**Phase 4: structure and process.**
- Introduce the §5 services.
- Split the god objects along the seams named above, and delete dead code.
- Set up CI on a self-hosted Windows runner:
  1. `--import`;
  2. the compile check;
  3. the gate, plus the water and world-generation tests;
  4. a grep for retired keys.
- Use one test-profile environment variable, and tag GPU-only tests.
- Restructure AGENT.md:
  - a short index plus the rules;
  - move the changelog to its own file;
  - replace "read ALL docs" with "read the docs for the area you touch".

---

## Appendix A — Full-suite results

**Run:** 208 tests, headless, 3 at a time, below-normal priority. Pass rule as in the
gate.

**Result:** 159 passed. The 49 that did not pass:

| Category | Count | Tests |
|---|---|---|
| Environment-gated by design: isolated APPDATA or profile | 14 | CaveGeneration, WorldGeneration, WorldLayout, WorldResourceBalance, WorldResourceDiagnostics, ResourceProgression, OreFieldIntegration, DoorLighting, RoomLighting, TunnelEntrance, UndergroundLighting, StorageFilter, ZoneWindow, SaveWorkerShutdown |
| Environment: native rendering (self-declared) | 2 | AtmosphereSharing, DwarfLimbLighting |
| Environment: probably need a real audio device (unverified) | 3 | PromotionAudioPlayback, RabbitAudioPlayback, WorkAudioPlayback |
| Headless timeouts, probably GPU-dependent (unverified) | 8 | ConstructionPresentation, BedroomLighting, DwarfNeedIndicators, DwarfSliceMovement, TerrainSunShadow, TorchReach, XrayView, LoadingArtwork |
| Broken by the furniture retirement (retired keys indexed) | 6 | CampfireStool, FurniturePilotSeating, DiningPlacement, DwarfInspector, FurniturePlace, TerrainExplorer. RoomLighting also indexes retired keys. |
| Art checks run against the new micro-voxel art (uncommitted) | 5 | DeerPilotArt, DwarfPilotArt, FurniturePilotArt, GemDropArt, ProportionIntegration |
| Fixture world setup: out-of-bounds `SCRIPT ERROR`s, some while printing PASS | 4 | BoulderPilot, ScreePilot, OrdersShelf, DwarfProfessionPanel |
| Production errors surfaced | 2 | StartupSave (DwarfRosterPanel await, §4.9), WorldLoadingScreen (pause regression, §4.7) |
| Test-code API drift | 2 | StarterTools (`:33`), ToolPromotion (`:103`) |
| Need investigation | 3 | MiningLedgeAccess (hard-coded cliff-shelf coordinates, plus ladder/mining assertions), TerrainAppearance (mineral-profile alpha in the cavity shell), SavedLadderJob (reads a player-save copy from tracked `tmp/`) |

---

## Appendix B — Review side effects and how each was reverted

| Item | Before the runs | After / action taken |
|---|---|---|
| Player saves (`quicksave*`, `autosave*`) and `audio.cfg` | Backed up and SHA-256 hashed in the session scratchpad | Unchanged |
| `ui_layout.json` | Backed up | `WaterPresentationTest` wrote to it; **restored** from the backup |
| 15 tracked `tmp/` files (audio WAVs, JSON reports) | Clean | Rewritten by tests; **restored** byte-for-byte from HEAD via `git show`, because the stale index lock blocks `git checkout`. Hashes were re-verified. |
| 1 tracked `tmp/` file | Already dirty | Rewritten with identical content |

**Left in place:**
- New gitignored evidence files under `tmp/`.
- Three `.uid` files that Godot generated for new scripts: `FruitHaulPlanner`,
  `AppleHarvestTest` and `FruitHaulingTest`. The editor creates these anyway.

**Caused by the editor, not the review:** the editor was opened at 19:18, during the
review. It re-saved `project.godot` with unchanged content and created `.import` files
for four PNGs in `docs/`.

Review harness scripts and logs live only in the session scratchpad, outside the
project.
