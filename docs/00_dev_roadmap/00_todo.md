# 00 — To do

Work the owner has deferred. Each item has a confirmed cause and a fix direction, but
none is scheduled: start one only when the owner asks. When an item is finished, delete
it here and add an entry to [00 — Changelog](00_changelog.md).

Playtest reports that still need investigating live in [00 — Open issues](00_open_issues.md).

---

## Save and load

Deferred by the owner on 2026-10-21: saving is not a priority during development. The
first two items come from the 2026-10-20 project review (doc 254, §4.7 and §4.9) and
were re-checked against the code on 2026-10-21. The last two were left open by that
review (§4.2) and by the 2026-10-22 code review (doc 258), and were re-checked on
2026-10-26.

### Saves from another build are deleted by the next save

- **What happens.** A save written by a different build fails validation at startup:
  a newer `schema_version`, or a river layout that doesn't match `RiverLayout.VERSION`.
  The game quietly starts a new world, and the next quicksave or autosave deletes the
  old file. The colony is gone, and the player never saw a warning.
- **Why.**
  - `SaveFileStore._rotate_primary_to_backup_if_valid` (`SaveFileStore.gd:88`) won't
    move an invalid primary into the backup slot, and `_replace_primary_with_temp`
    (line 122) then removes it.
  - The notice "No valid save could be loaded…" (`SaveManager.gd:166`) is raised from
    `WorldRenderer._ready` (line 314), before `DockUI` registers (`DockUI.gd:132`). It
    only reaches `push_warning`. Its text also says existing saves are unchanged.
- **Fix direction.** Old saves still don't need to load (no backward compatibility
  during development), but the file must not be destroyed.
  - Delete only a primary that fails to parse as JSON. Rename any other invalid file
    aside, for example `quicksave.rejected-<utc>.json`.
  - Queue notices until the dock registers, so the player sees why a new world started.
- **Done when** a save with a bumped `schema_version` is set aside rather than deleted
  by the next save, and the notice shows on screen.

### Starting with a save present comes back paused

- **What happens.** When the game starts with a save present (the normal startup
  resume), the colony comes back paused. The player's saved pause setting is also
  overwritten with "paused". The review also reported this after Load and New Game;
  only the startup case was re-checked.
- **Why.** `WorldClock.paused` (`WorldClock.gd:33-35`) also reports the loading
  screen's hold. `SaveManager` stores that combined value as the pre-load state
  (`SaveManager.gd:194, 371`) and sets the player's own pause (`set_paused(true)`,
  lines 195 and 376). The loading hold leaks into the player's setting.
- **Test.** `WorldLoadingScreenTest` covers it, but it only fails once a save exists:
  - on a fresh profile it passes, because there is nothing to resume;
  - its second run resumes the quicksave the first run left, and fails "loading hold
    never changes the saved pause preference" and "original running state restored"
    (checked 2026-10-21).
  - It is not in the job gate.
- **Fix direction.** Store the player's own pause (`_player_paused`, through an accessor
  on `WorldClock`) instead of the combined getter, so the loading hold never reaches
  the saved setting. Make the test write its own save first, so it fails on a fresh
  profile too.
- **Done when** that test passes with a save present at startup, and resuming an
  unpaused save comes back running.

### Saves don't record which world generator made them

- **What happens.** A save stores the world seed, not the rules that turn it into a
  world. After a change to `data/world_gen/caves.json`, the macro layout or the block
  rules, an old save still loads. Its terrain edits land on a different base world, and
  its discovered caves, saved as indexes into the cave list
  (`InteriorTracker.serialize_exploration`), can reveal a cave the player never found
  (Hard Rule 11). Named saves (2026-10-26) keep old saves around longer, so this matters
  more.
- **Why.** `SaveSnapshotValidator.validate_captured` checks only `schema_version` and the
  river's `layout_version`; nothing identifies the generation inputs. Cave ids are list
  positions (`CaveLayout`).
- **Fix direction.** Old saves still don't need to load. Save a fingerprint of the
  generation inputs (the world-generation data files and a generator version) and reject
  a mismatch with the "start a new world" notice, as for a schema change. Key discovered
  caves by a stable cell instead of their list index. Until the first item above is
  fixed, a refused save is also deleted by the next save.
- **Done when** editing `caves.json` makes an existing save be refused instead of loading
  with another cave revealed.

### A construction crate can come back on another cell

- **What happens.** On load, a construction project's materials crate moves to another
  cell whenever its saved site no longer passes the site check. The staged stone counts
  are kept. The check fails when furniture was installed or a block built on one of the
  crate's four sides, or a construction plan sits above one; possibly also when a dwarf
  stands in the cell at load.
- **Why.** `ConstructionController.place_materials_crate` rechecks the saved `crate_cell`
  with `_crate_site_clear`, which needs those sides walkable, and otherwise searches for a
  new site.
- **Fix direction.** Restore the crate on its saved cell without the site check.
- **Done when** a saved crate with furniture beside it comes back on the same cell.

---

## Dwarves

Found by the 2026-10-20 project review (doc 254) and re-checked against the code on
2026-10-26, apart from the teardown item, which comes from the 2026-10-15 benchmarks.

### A ladder or bridge change interrupts meals, games and promotions

- **What happens.** Building, extending or removing any ladder or bridge, even one section
  far away, makes every walking dwarf replan. A dwarf walking to a meal gives it up
  ("Meal interrupted by movement."), one walking to a game cancels it, and one fetching a
  promotion's tool cancels the promotion ("Promotion cancelled: the route to the tool
  changed."). Work, rest and meal walks each run a new path search in that frame, after
  the path cache is cleared.
- **Why.** Each ladder or bridge change raises `NavGrid.ladder_revision` and clears the
  path cache (`_rebuild_ladders`). `DwarfMovement.follow_path` then calls
  `_repath_walk()`, which cancels recreation outright and otherwise calls
  `DwarfAgent.walk_to`, whose first lines cancel a meal. `DwarfEquipment.tick` cancels a
  promotion on its own revision check.
- **Fix direction.** Replan without the cancellations: let the activity that owns the walk
  replan its route (or call `DwarfMovement.walk_to` directly), and replan only the walks
  whose route uses the changed ladder or bridge.
- **Done when** finishing a ladder section elsewhere leaves dwarves walking to a meal, a
  game or a tool still on their way.

### Hunger stops work before knowing there is food

- **What happens.** A hungry dwarf drops its job, and any cargo, before it looks for food.
  With no reachable food it gives up and works again. A quarter of a game hour later it
  drops everything again, for as long as the shortage lasts.
- **Why.** `DwarfFoodBehavior.begin_if_needed` aborts and releases the current task (its
  `clear_task_state` drops the cargo), then searches. After "No reachable food; will try
  again." the next try waits only `food.retry_hours` (0.25 in
  `data/tasks/task_config.json`), and the `shortage` flag doesn't hold it back.
- **Fix direction.** Search first (the search is already budgeted and resumable) and take
  the dwarf off work only once food is quoted. Or, while `shortage` stands, skip the
  interruption until stock changes. A famished dwarf's foraging must keep working.
- **Done when** a hungry hauler with no food in reach keeps hauling, and one with food in
  reach still goes to eat.

### Proven routes a worker cannot walk

- **What happens.** Traced in the code, not yet seen in play: work the scheduler proved
  reachable can fail once the worker sets off, because the walk searches less far than
  the proof did. A failed delivery drops the cargo; a haul is released after three failed
  pulls and assigned again.
- **Why.** Scheduler searches (`WorkRouteProbe`) grow to
  `supervision.maximum_search_nodes` (24,000). Executors walk with `NavGrid.find_path`
  and its 6,000-node limit (`DEFAULT_MAX_NODES`), which
  `DwarfCarryWork._walk_to_handling_stand` also uses for each candidate stand. Only the
  5-second path cache (`NavGrid.remember_reachable_path`) carries a longer proof across.
- **Fix direction.** Hand the proven route to the executor for every task family, or let
  executors search to the bound the proof used.
- **Done when** a haul whose delivery route needs more than 6,000 search nodes completes
  even when its pickup leg takes longer than five seconds.

### A dwarf leaving the scene mid-walk runs job code

- **What happens.** When the world is freed (Load, New game, Quit to main menu) while a
  dwarf walks to haul, its hauling code runs during the teardown: a haul skips to its
  next item, a delivery drops its cargo, and the code reads a global transform after
  leaving the tree. Benchmarks logged the error three times on 2026-10-15 (docs 190, 191
  and 193). Not re-run since, but the call chain is unchanged.
- **Why.** `DwarfAgent._exit_tree()` calls `DwarfRestBehavior.cancel()` whether or not the
  dwarf rests. `cancel()` calls `agent.stop_walking()`, which emits `walk_finished(false)`,
  and `DwarfWorkExecution.walk_finished` takes that as a failed walk
  (`DwarfCarryWork._haul_skip_current`, `drop_carried_at_feet`).
- **Fix direction.** During teardown, clear only the walk (its path or phase) without
  emitting `walk_finished`. Don't reuse `_begin_sleep()`'s way: its `clear_task_state()`
  drops carried goods.
- **Done when** a test frees a world with dwarves walking to haul and to deliver, and the
  log shows no errors and no new drops, skips or task events.

### Small dwarf defects

- **A promotion treats an exhausted route search as reachable.** `DwarfEquipment._find_tool`
  handles `SEARCHING` and `UNREACHABLE` but lets `BUDGET_EXHAUSTED` through: it reserves
  the tool and starts a walk with no path, and the next tick cancels with "Promotion
  cancelled: the route to the tool changed." instead of trying another tool. Treat it as
  unreachable.
- **Leaving a closing bridge counts as a full night's sleep.**
  `DwarfAgent._process_bridge_exit` wakes a sleeper through `_wake_up()`, which sets
  `sleep = 1.0`. Wake without the rest.
- **Founding dwarves can start in a river.** `DwarfDirector._standable_ground_y` skips
  lake, tarn and occupied cells but never asks `NavGrid.is_walkable`, so a river column
  passes.

---

## Furniture

Found by the 2026-10-14 review (doc 177, parked by the owner) and the 2026-10-20 project
review (doc 254), and re-checked against the code on 2026-10-26.

### Floor furniture installs without rechecking its spot

- **What happens.** A floor piece installs even when its spot changed after it was
  planned. With the floor under it removed, at any time before or during the set-down,
  it installs hanging over the hole and uses up the packed item. It also installs over a
  dwarf standing in its footprint and registers its occupancy around them.
- **Why.** `FurniturePlacementController._can_build_ghost`, run just before the item is
  used, rechecks walkability only for Moves and chairs; any other floor piece passes
  after the seating check. Nothing rechecks or cancels floor plans when terrain changes,
  and ghost work stands exclude only the ghost's own footprint
  (`FurnitureGhostComponent.work_stands`). `ConstructionController.build_reason` already
  refuses a cell a dwarf occupies.
- **Fix direction.** Before using the item, recheck every floor piece's footprint with the
  placement rules (support, clearance, occupancy) and refuse while a dwarf stands in it.
  A refused install keeps the exact packed item.
- **Done when** a test that removes the floor before the set-down, and one that parks a
  dwarf in the footprint, both end with no installed piece and the packed item intact.

### Mining under furniture or a stockpile leaves it floating

- **What happens.** Mining the block under an installed floor piece (a bed, table, stool,
  bench, workbench, hearth, campfire, door or the flag) or under a stocked storage cell
  leaves the piece or the stored goods hanging in the air, and haulers keep delivering to
  that cell.
- **Why.** `MiningDesignationController._filter_mineable_blocks` doesn't skip blocks under
  furniture, ghosts or storage cells. After the edit only wall pieces
  (`_revalidate_wall_mounts`) and grid fences and gates (`GridFence.revalidate_support`)
  are rechecked, and storage doesn't listen to terrain edits. Loose items settle
  (`ItemDropManager._settle_changed_columns`), but stored goods keep their owners.
- **Fix direction.** Choose per kind: keep those blocks out of mining plans, or react when
  the support goes (pack the piece, drop stored goods as loose items so they settle, and
  remove the unsupported storage cell).
- **Done when** mining the floor under a bed and under a stocked cell leaves nothing
  floating, and no hauler targets the cell.

### Removing floor furniture tries only the nearest side

- **What happens.** When the nearest side of a floor piece is walled off but another side
  is open, Uninstall backs off with "No route for eligible workers". Every Move starts
  with an uninstall, so Moves stall the same way.
- **Why.** `InstalledFurnitureComponent.nearest_stand_target` picks the nearest walkable
  side without a route check, and the executor walks to that one cell. The scheduler
  probes every side as a goal only for wall pieces and grid fences (`TaskScheduler`).
- **Fix direction.** Probe every walkable side of floor pieces too, and hand the proven
  stand to the executor. Cover Uninstall and Move.
- **Done when** a Log Stool at (45, 20, 40) whose nearest stand (44, 20, 40) is walled in
  is uninstalled from (45, 20, 39).

---

## Performance

### The first mined block after a load hitches once

- **What happens.** The first block mined after loading a save stalls the game once,
  for 0.4–0.6 s. Later blocks cost 15–30 ms. Before the 2026-10-21 stutter fix, one
  block in a run showed the same extra ~0.4 s (695 ms against ~280 ms for the others).
- **Measured** on a copy of the owner's save (49k edits, 5 dwarves), headless, with the
  clock paused, across three runs:
  - 47 ms inside `MiningDesignationController._mine_block_world`, then a 394 ms frame;
    the next five blocks took under 1 ms in the call and 15–29 ms per frame;
  - 68 ms in the call, then a 573 ms frame;
  - a 439 ms frame, then 16, 38, 17 and 19 ms.
- **Not the renderer.** The renderer's own work for that block took 16 ms, and its
  overview snapshot patch is negligible. The long frame comes from another system.
  Unchecked candidates: the first dropped item (model load), the first underground
  lighting or NavGrid update after a load, water, and cave discovery.
- **Reproduce** with `tools/performance/RunShaderSlots.ps1 -Mining`. Its report lists
  the mined blocks in order, and the first one carries the hitch.
- **Fix direction.** Profile that one frame to find the system doing first-time work,
  then do that work while the loading screen is still up.
- **Done when** the first mined block after a load costs about the same as the next
  ones.

### A season change spikes single frames

- **Observed, not pursued** (performance work is paused). A season change rebuilds the
  whole world's seasonal visuals in one go; single frames reached about 180 ms without
  surface details and about 194 ms with them. Thinning details would not remove it.
- **Fix direction**, if season changes become a playtest problem: profile trees,
  materials and the rebuild together, then spread the rebuild over several frames.

### Duck flight planning spikes a frame

- **Observed, not pursued** (performance work is paused; on 2026-10-15 the owner kept it
  recorded for later investigation). A duck that decides to fly (danger, drained water, a
  blocked flight or its relocation every 70–140 s) samples 24 random landing spots plus
  four nearby columns and sweeps flight arches for each in that one frame
  (`DuckAgent._try_flight`). A failed search repeats every 5 s. Duck processing peaked at
  about 15–17 ms in a frame in the 30-dwarf profile of 2026-10-15 (doc 197).
- **Fix direction**, if duck flights show up as a hitch in play: spread the search across
  frames with `DuckNavigation.begin_flight_path` / `advance_flight_path` under a small
  budget, as arrival preparation does (`DuckArrivalPreparation`), the duck carrying on
  until a path is ready. `DuckQueryReuseTest` compares duck states with a frozen copy that
  has only `flight_path`, so rework or retire it with the change.

### A long soak at 30 dwarves

- **Observed, not pursued** (performance work is paused; on 2026-10-15 the owner kept this
  as a later checkpoint). Every frame-time profile so far ran for a few minutes. In the
  2026-10-15 runs, 30-second frame means rose after a season change (13.8 → 15.0 ms at 5
  dwarves, 17.9 → 19.7 ms at 30) and engine memory grew a few MiB; runs that short can't
  tell a leak from world growth or noise.
- **Fix direction.** Run 30–60 minutes at normal speed on a copied mature save with 30
  dwarves, through autosaves, arrivals and a season change, recording frame times, engine
  memory, node and resource counts and job progress. Start from
  `tools/performance/RunLongSession.ps1` (`LongSessionBenchmark.gd`), whose triggers
  squeeze a save, a midnight, arrivals and a season change into the first few minutes.
  First fix its `arrival_finished` handler (`LongSessionBenchmark.gd:90`): a
  three-argument lambda on a signal that now has four. Method: doc 13, "Measuring
  performance".
- **Done when** the run shows no unexplained growth in frame time or memory, or the cause
  of any growth is found.

---

## Rendering

### Lit-shader per-object slots (8,192 cap)

Owner decision 2026-10-21: log the proper fix and leave `buffer_size` unchanged
(the 2026-10-20 project review, doc 254, §4.3).

- **Limit.** `scripts/shaders/underground_lighting_common.gdshaderinc` declares three
  `instance uniform`s (`actor_sky_access`, `doorway_light_plane`, `doorway_light_span`).
  Every mesh whose shader includes it reserves a 16-slot block of the global shader
  buffer, used or not. `project.godot` sets
  `rendering/limits/global_shader_variables/buffer_size=131072`, which is 8,192 objects.
  Past that, Godot logs "Too many instances using shader instance variables" and the
  extra meshes render black. At the old 4,096 default, a benchmark with the full forest,
  24 dwarves, wildlife and 48 furniture pieces turned some dwarf parts black
  ([24](../20_player_interface/24_world_rendering.md)). Doubling the buffer only moved
  the limit.
- **Measured** on a copy of the owner's save (5 dwarves, 2026-10-20): 4,147 of 8,192 (51%).
  - By system: surface details 2,175, terrain renderer 1,191, wildlife 543, item drops 98,
    furniture 80, dwarves 60.
  - The per-column cavity and built-block meshes (2026-10-21) add one slot per 16×16
    column that has them: +54 at that save's slice (4,201 in all), about +100 with the
    slice off.
  - Most slots go to plants and animals. Each dwarf takes about 12, so 30 dwarves add
    about 300.
- **Proper fix.** Only actors (`actor_sky_access`) and door meshes (`doorway_light_*`)
  read these values. Move the `instance uniform`s into an actor/door-only variant of
  the include, so terrain, plants, props and items reserve no slots. Doors keep their
  values per instance, so cached door materials stay shared across rotations
  (`UndergroundLighting.bind_door_tree`).
- **Fallback.** Raising `buffer_size` lifts the cap at 16 bytes of GPU memory per slot.
  It changes a rendering setting, so it needs the owner's OK.
- **Count** with `tools/performance/RunShaderSlots.ps1` (copy of a save, throwaway
  profile). The report gives users, the cap and a per-system breakdown.
- **Done when** a slot count over a large save shows only actors and doors reserving
  slots, and dwarves, animals and doorways light exactly as before.

---

## UI

### The fonts' licences are not in the export yet

- **Fix direction.** The SIL Open Font License asks that each font's licence travel with
  it. Add `assets/ui/fonts/*.txt` to the Windows export's non-resource files (Project →
  Export → Resources), an export setting the owner keeps. The fonts and their licences are
  in doc 23, "Type".

### The Sky Dial's forecast

- **Idea.** Stonehearth's clock shows the next days' weather. The Sky Dial's plate could
  show tomorrow's and the next day's as small pictures from the dial's own pieces (a
  sun, a cloud, a storm cloud). The forecast was drawn as plate iii in doc 272 and left
  for later (owner, 2026-10-26).
- **Fix direction.**
  - The weather draws each day from one saved stream (`WeatherManager`), so the next days
    can be read exactly by drawing ahead on a copy of the stream, without moving it.
  - Add it once weather changes play, when rain waters crops or storms keep dwarves
    indoors. Until then it would be flavour only.
  - The dial's plate is in doc 23, "The Sky Dial".

### Choosing keys

- **Idea.** Settings' Controls tab lists the keys but cannot change them; choosing keys
  was left for later (owner, 2026-10-25), and again for much later on 2026-10-26.
- **Fix direction.**
  - Most keys are input actions in `project.godot`, matched by the key's place on the
    keyboard (doc 23, "Keys"). Hover cards read their keys from the input map, so a
    rebound key shows everywhere.
  - Some tool keys are still checked in code and become input actions first:
    - Q and E (Build's material), Tab (Shapes' shape) and F (fill) in
      `ConstructionController._key_setting`;
    - R (turn) and F (Copy's floor) in `BlueprintController._unhandled_input`, and R in
      `FurniturePlacementController`;
    - Alt + wheel (height) and Shift + wheel (door width) in the construction tools.
  - Rebinding needs a way to pick a key per action in the Controls tab, with a clash
    warning.
  - The choices are saved in the player's settings in `user://`, never in the save.

### Named saves' later ideas

- **Idea.** Two pieces were left for later when Save as… was planned and built (doc 274,
  2026-10-26):
  - renaming a save from the Load page;
  - a picture of the colony on each save. For the title, the owner chose painted art over
    the colony as the save left it (2026-10-25).
- **Fix direction.**
  - A save's name is kept inside its file (`save_name`, doc 13), so Rename means writing
    the whole file again, about 12 MB for a 5-dwarf colony. Do it on the save worker, as
    Blueprints' Rename moves its file (doc 23, "Copy and Blueprints").
  - A picture would be taken when the save is written, beside the file, as Blueprints keep
    theirs.

### The item stamper's later ideas

- **Idea.** The DEV item stamper's first plan had two more pieces, left out of the
  accepted design (owner, 2026-10-25):
  - a short list of recent items to stamp again;
  - stamping furniture already installed, through the normal placement rules.
- **Fix direction.** Both belong to the stamper's window (doc 23, "The item stamper"),
  behind the DEV switch.

### Development still uses painted pictures

- **Fix direction.** The Development menu's entries still show the painted
  `assets/ui/dock/utilities_atlas.png` (`data/ui/dock.json`), the last painted sheet. The
  menu is DEV-only, so it may stay simple. Hearthblock icons, or plain text, would let the
  sheet go.

### DEV windows still build their own chrome

- **Fix direction.** Move the block inspector (`scripts/components/BlockInspector.gd`)
  and World Build (`DebugLoadingOverlay.gd`) onto `UIWindowManager`, then reword the
  comment above `DockUI._toggle_window` (`scripts/ui/DockUI.gd:667-670`) that says they
  "stay overlay-toggles until their doc 24 Phase U2 migrations land".

### Video settings left for later

- **Fix direction.** The approved Settings concept (2026-10-24) left three video settings
  for later: brightness, a Screen choice for two or more screens, and FSR 2 for Render
  scale. FSR 2 is temporal, so check it against moving dwarves and water first. Each is a
  setting in `data/video/video_settings.json`, which the Video tab builds its rows from,
  with its own case in `VideoSettings._apply()` (doc 23, the Settings page).

### Events left for later

- **Fix direction.** The approved Events concept (2026-10-24) left four things for later:
  - **critical entries in red,** for deaths and invaders, once something produces them
    (doc 52). They need a kind in `data/events/event_log.json`, a tone beside the
    warning's rust in toasts, the Events cards and the bell, and a place in the pinned
    order;
  - **entries that ask for a decision,** such as traders and migrants (doc 51);
  - **filters,** if the log grows busy;
  - **a sound** for new entries.
- The log, its toasts, the window and the bell are in doc 23, "Toasts and the event log".

---

## World start

### Bounded start presentation (optional)

- **Idea.** Before play, frame the camera and fog on the settlement anchor with no
  simulation running. Open question: just frame the existing ~5 s full boot, or
  generate a bounded area.

### Fog of war around the anchor

- **Idea.** Reveal the area around the settlement anchor and fog the rest.
  `TerrainTileMesher.SLICE_CUT_DIM` (slice-cut floor dimming) is meant to fold into that
  fog multiply and be removed.

### Starting wildlife can spawn inside tree trunks

- **What happens.** In a new world, a starting animal can be placed in a cell that a tree
  trunk claims a moment later. Which cells count as free also depends on how fast the
  forest loads. Found by the 2026-10-20 project review (doc 254); re-checked on
  2026-10-26.
- **Why.** `WildlifeManager._process` places the starting population once the maps and
  ground details are ready, but whole-map trunks register their occupancy over several
  later frames (`SurfaceFloraSpawner`, `spawn_budget_per_frame`). `arrival_ready()`
  already waits for the forest (`flora.get_spawn_stats()`: something loaded, nothing
  pending); `initialize_population()` doesn't.
- **Fix direction.** Gate `initialize_population()` on the same forest check.
- **Done when** no starting animal overlaps a trunk, and the same seed places them the
  same way however long the forest takes.

---

## World / caves

Principle for all of these: ordinary tunnelling must stay a viable way to build a
colony. A cave is a choice, not what makes a seed work. Rules for the current caves are
in [43 §Cave discovery](../40_economy_colony/43_mining_materials.md#cave-discovery).

### Multi-seed cave playtest (deferred)

- **Idea.** A visual and playable pass across several seeds: chamber shape, size,
  spacing, depth and the effort to reach them. Tune from play before adding any of the
  rewards or risks below.

### Cave content and structure

- **Pools, springs and irrigation.** Needs fluid containment, saturation, drainage and
  flooding first; never connect live lakes blindly.
- **Fungi and cave plants.** Needs the farming/harvest loop, regrowth, light and water
  needs, art and placement.
- **Ruins and signs of earlier inhabitants.** Needs discovery content, item uses and
  placement that keeps the space usable.
- **Inhabitants and hazards.** Needs combat/hazard systems, readable warnings and
  counterplay, with no unavoidable early punishment.
- **Multiple levels and shafts.** Needs stairs or ramps, worker reachability,
  floor/ceiling integrity and a usable slice view.
- **Cave specialisations.** Measure ore left after carving, exposed veins and access
  cost before giving regions distinct reasons to explore.
- **Progressive discovery.** Line-of-sight or dwarf exploration, partial reveal
  rendering and saving, beyond the first wall breach.
- **Logistics.** Playtest whether adapting a cave (travel, hauling, light, doors,
  sealing, temperature) beats digging custom rooms.

---

## Surface details

- **Reed/fiber crafting.** Reeds can only be cleared today and yield nothing.
- **Reed regrowth and shallow-water reeds.** Reeds grow only on dry banks near the
  waterline; nothing regrows or roots underwater.
- **Alpine/snow species and cave flora.** No species is designed for high summits or
  caves yet.
- **The blueberry cutting still asks for rocky ground.** Its description says "Plant it
  on rocky high-ground soil for best results" (`base:resources:seed:blueberry_cutting` in
  `data/entities/items/resources.json`). Since 2026-10-09 (doc 85) cultivated blueberries
  need grass, dirt or soil (`wild.transplant.ground_kinds`), bare rock is refused, and
  neither height nor soil changes growth. Reword it like the elderberry cutting's ("Root
  it in surface soil to grow a new bush"), and check the strawberry cutting's "good
  surface soil" and the unused hops and grape cuttings with it.

---

## Forestry

- **Tree growth and regrowth.** Trees keep their generated growth stage; saplings never
  grow and felled trees never come back.
- **Forestry Zone and Clear Stumps.** Planned dock actions; neither is in
  `data/ui/dock.json`, and there are no persistent stump objects.

---

## Construction

Build, Shapes, Copy and Blueprints were built on 2026-10-26 (doc 23, from "Build" to "Copy
and Blueprints"; changelog, doc 273). What follows keeps Deepdraft's per-voxel model: tools
only create ordinary block plans, every block is built and mined on its own, and nothing
becomes a building object (the weak spot of Stonehearth's building editor).

- **Dig and build.** Placing a blueprint also orders the mining of the rock in its way, for
  rooms cut into the mountain. Today that rock shows in rust and its blocks are left out.
- **Furniture in blueprints,** kept as placement plans that wait for their items.
- **To the ceiling.** Walls raised to the rock above, so a room built in a cavern seals.
- **Roofs and other shapes,** only if homes outside the mountain come.
- **Each wood its colour.** Built oak, pine and juniper share one timber look; each could
  take its wood's colour, as log furniture does.
- **Copy inside Blueprints,** if the shelf feels long: Copy can move into the Blueprints
  window. The owner chose two shelf entries on 2026-10-26.
- **Building vision (pencilled in).** Only if Deepdraft gets homes outside the mountain,
  which is undecided: a view toggle that lowers or hides constructed walls and roofs so
  the player can see inside. Underground rooms already have the slice and X-ray's Flat
  mode.
- **Stonehearth's building editor, for reference** (the owner's screenshots,
  `tmp/ui_review_20261023/stonehearth/05_*`). Its shape palette and saved templates are
  built as Shapes and Blueprints; its storey stepper is not, and could come with roofs or
  dig and build. What was not taken is in doc 23 (Construction).

### Other stones and thinner walls

- **What happens.** Build (doc 23) places full blocks of stone, dirt, grass and logs. A
  stone block is always the natural rock of its layer, and nothing is thinner than a
  block.
- **Why.** The owner left other stone and finer geometry for later (2026-10-12, doc 127).
  Logs replaced the planked wood block on 2026-10-26 (doc 275).
- **Fix direction.**
  - Another stone is a kind in `data/construction/blocks.json` with `tool: build`, its
    `item_key`, `block_key`, `cost` and `type_label`. Listed under stone's `kinds` in
    `data/construction/materials.json`, it joins Stone's menu (doc 275).
  - A thinner wall fills cleared space and never covers kept natural terrain; wall
    finishes such as panelling and facing stay out (doc 43, "Built blocks").
- **Done when** the owner's first chosen stone or thin wall plans, stages its material,
  builds, mines and saves like a block.

### Build textures by progression

- **What happens.** Each of Build's materials has one look. The plank and stone floors,
  the only finer looks, were removed on 2026-10-26: every block is a whole cell, so a
  floor is just a block a dwarf stands on, and a floor block could always be stacked into
  a wall (doc 12, "No separate floor blocks").
- **Why.** The owner plans a texture choice under a Build material (stone first) that
  grows with the colony's progression, in place of separate floor tools (owner,
  2026-10-26).
- **Fix direction.** Decisions from the 2026-10-26 review:
  - **Cost or look.** Recommended: each texture costs the good that makes it (dressed
    stone from the Stonemason, planks from the Carpenter), and rough stone stays the
    cheap default. Build's Stone and Wood menus (doc 275) are where new types join, a
    planked block among Wood's beside the logs. A free cosmetic unlock needs its own
    unlock rule. Either way, show locked textures greyed with what unlocks them.
  - **Identity.** Each texture is its own block key, like `base:construction:wood:<log>`,
    never a look the renderer adds (Hard Rule 9; saves store keys). Decide what mining one
    gives back.
  - **Rendering.** A built block is a colour plus its kind's appearance profile, and the
    vertex alpha holds profile ids 1–7, five of them taken (`appearance_profiles.json`).
    Several textures need that packing widened, or authored pieces as built logs have
    (`BuiltLogs`, doc 24).
  - **Appeal.** Let the finished blocks a room shows, floor and walls alike, add appeal,
    so whether a block is "a floor" or "a wall" never matters.
  - **Blueprints** store blocks by material; they need the texture too, and a rule for a
    blueprint whose texture the colony has not unlocked.
- **Done when** the owner's first chosen texture can be picked in Build, costs its good,
  builds, mines and saves like a block, and shows its own look.

---

## Storage

- **Storage furniture (barrels, chests, shelves).** Removed on 2026-10-22; it returns
  with its own milestone (doc 258). Owner, 2026-10-23: each container type accepts only
  certain goods (for example a supply shelf takes raw goods: resources, ores, metals),
  and its filter lists only those. A container may hold one chosen item type, named in
  its title, and shows its capacity (Used 9 / 12). Reference: Stonehearth's supply shelf
  (the owner's screenshots, `tmp/ui_review_20261023/stonehearth/15_supply_shelf*`).

---

## Code health

### Godot's stricter GDScript warnings are off

- **Fix direction.** The 2026-10-22 code review (doc 258, step 5) postponed Godot's opt-in
  GDScript warnings (untyped declarations, unsafe property and method access) until the
  largest files were split, which its step 8 did. Turning them on changes `project.godot`
  (`debug/gdscript/warnings/...`), so it needs the owner's OK. Then fix what they report.
