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
  and 193). Not re-run since, but the call chain is unchanged. The owner's own game logged it
  on quitting, 19 errors each time, in the runs of 2026-11-10 (evening) and 2026-11-12
  (morning): a hauler's search for goods to move read a container's place
  (`ContainerStorageComponent.anchor_position`) after the world had left the tree. Both
  quicksaves were written before it, so no save was touched.
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
- **Founding dwarves can start in a river.** `DwarfDirector._standable_ground_y` skips
  lake, tarn and occupied cells but never asks `NavGrid.is_walkable`, so a river column
  passes.

---

### Stats and hit points left for later

Left open when the stats and hit points milestone was retired (2026-10-31); the rules are
in doc 41 ("Stats", "Health"), doc 45 (animals) and docs 52 and 62 (doors).

- **Calling traits and stats.** A Born Miner with Poor Strength reads oddly. Recommended:
  each calling trait also guarantees its profession's main stat at Good or better, as Iron
  Constitution does for Toughness: Strength for Born Miner and Born Hauler, Wisdom for Green
  Thumb and Brewmaster's Intuition, Wits for Architect's Eye, Charisma for Merchant's Tongue
  and Warm Host.
- **Colony → Dwarves sorted by fit,** to find the best miner among 30. Recommended next to
  the career map's fit.
- **Agility's first live job.** Walking and climbing speed, at a smaller 3% a step, would
  show it now. It touches every trip, so it waits for the owner's word.
- **Charisma** does nothing until a Merchant, an Innkeeper or a squad leader exists.
- **With the Ranger's hunting:** spear blows against animal hit points, fleeing when struck,
  carcasses and experience for each animal; Agility and Wisdom at work (doc 45). Hunting also
  brings the Ranger more workbenches, such as a rack for drying hides into leather (owner,
  2026-11-01).
- **With combat:** invaders breaking doors, armour, weapons, death and forced bed rest;
  Strength, Agility and Toughness in the damage formula; whether dwarves can lock doors
  during a raid, and whether mending a door takes a log (doc 52).
- **A Medic:** Wisdom heals others, and a bed or an infirmary heals faster.
- **Better doors:** iron with the Smelter and Forge, stone with the Stonemason (doc 62).

### The Blacksmith left for later

Left open when doc 297 (the basic smelter) was retired (2026-11-02); the rules are in doc 44
("Specialist workbenches", "The Smelter"), doc 41, doc 31 (COLLECT) and doc 34 (batch heat).

- **Iron:** the Smelter and the Forge as the advanced benches, for a level-2 Blacksmith; tin
  bars with them (owner, 2026-11-02: "tin waits"). No bronze yet. The Forge's forged anvil
  replaces the anvil stone, which works copper and whatever else comes before iron (owner,
  2026-11-14: "copper, bronze, etc... until the iron anvil arrives later"; doc 44, "The anvil
  stone").
- **Bronze:** the owner named it on 2026-11-14 among the metals the anvil stone would work.
  Nothing is planned for it yet; it needs tin and the owner's word on where it sits before iron.
- **Copper tongs and hammer,** the better tool the career map previews.
- **Copper's later use:** the brewery and the aging cellar take copper bars. There are no copper
  fittings (owner, 2026-11-13: "we'll just simplify this scenario and use copper bars").
- **Charcoal** as a fuel of its own. Logs burn in the basic smelter since 2026-11-13 (doc 44, a
  recipe's `one_of`); charcoal would be a good made from them.
- **The fire answering the breath:** the coals could brighten with each breath, and the fire's
  sound could swell with it. Today they glow and burn evenly from the moment the charge is in
  (the smelter's sounds are doc 307; see "The smelter's sounds left for later").
- **Tune in play:** the melt's 4 hours, the smelter's 2,400 heat, the anvil stone's cost (three
  Rough Stones) and where a bar lies on it while it is hammered (the middle of its left cell).
- **The anvil stone left for later (doc 310):** the casting stone still shows the peck marks of
  the days when tools were hammered on it; the bar always lies along the world's X, so on a
  stone turned a quarter it lies across the face; no binding motion shows the haft going on.

### The profession path left for later

Left open by doc 306 (2026-11-13); the rules are in doc 41 ("The profession path"), doc 44 (at
the top, and "Specialist workbenches"), doc 43 ("Pickaxe upgrades") and doc 23 (the career map).

- **Step 2, the tools in hand.** The copper pick in the mining pose (Workers keep the stone
  pick), the pull saw in the Carpenter's hands with a sawing motion at the bench in place of the
  adze stroke (`craft_tool` and `craft_motion` in `professions.json` still name the stone adze),
  the chisel in the Stonemason's off hand under the maul, and the careers' icons, which still
  show stone tools.
- **Step 3, what copper tools make.** The copper Carpenter and Stonemason make the goods they
  made with stone kits. Planks and dressed stone were held "until iron tools" (2026-11-01); a
  saw and a chisel in hand make that worth a second look, and the owner left it for later
  (2026-11-13). See "The Stonemason and the Carpenter left for later" below.
- **Choosing the fuel and the haft.** A batch takes the first choice in stock: a coal before
  logs, pine before the finer woods. When iron needs coal, a colony will want to keep its coal
  from the copper: a switch on the order, or logs first, would do it.
- **Signs of copper on the surface.** Ore is hidden until a tunnel touches it, so a start can
  need a long dig (doc 41 has the numbers). A stained boulder or loose ore among the scree over
  a shallow vein would let a player read the land; it must come from the generated blocks
  (Hard Rules 8, 9 and 11).
- **More than one tool a bar.** Each tool costs a whole bar; tune in play.
- **A Miner loaded without a pick** keeps the trade and digs at a Worker's pace. Nothing sends
  it for a pick.

### Trade hats left for later

Left open by doc 304 (2026-11-12); the rules are in doc 41 ("Profession System"), doc 41b
("Trade hats"), doc 64 (the dwarves' contracts) and doc 24 ("Underground Lighting Model").

- **A career that goes live needs its `hat`** in `professions.json`, or its dwarves read as
  Workers. (The Farmer's straw hat came with farming, doc 309.)
- **Doors and the candle.** Only rock and built log walls shadow the candle's light, so it
  passes a closed door. A door's leaf could carry the built-wall shadow layer
  (`TerrainLighting.BUILT_LAYER`).
- **The hats on the career map.** Its cards show each career's icon; the hat could sit beside
  it, so a player learns the hats before promoting anyone.
- **Many Miners at once.** Six lit candles cost about half a millisecond of CPU a frame; the
  cost at 30 dwarves with many Miners was not measured.
- **A dwarf at a table or on a ladder in a hat** was not looked at.

### The Stonemason and the Carpenter left for later

Left open when doc 293 was retired (2026-11-02); the rules are in doc 44 ("Specialist
workbenches", with the ladder), doc 41 (Profession System) and doc 64 ("Furniture tiers").

- **Iron tools and the advanced benches.** With the Blacksmith (doc 44): the iron saw and the
  iron chisels, which the career map already previews, then the joiner's and the carver's
  benches made with them. Since 2026-11-13 both trades already start with a copper saw and a
  copper chisel (doc 306), so iron is their second tool. A recipe names the tool its maker must hold (`tool`), so an order
  waits "Needs a Carpenter with an iron saw".
- **Planks arrived with the copper saw** (doc 308, 2026-11-13): the hold of 2026-11-01 ("I
  don't know how the dwarves can make these without a saw yet") ended when every Carpenter came
  to hold one. What is left of them is under "Sawn timber left for later" below.
- **Dressed stone,** still held (owner, 2026-11-13: "Stonemason later"). As planned, a
  Stonemason dresses a Rough Stone into one block of dressed stone, hauled and stored like
  stones; its finer pieces take it, and Build too ("Build textures by progression"). Dressed
  faces want a warm grey like the older stone colours (`stone`, `stone_light`), which the hearth
  wore until 2026-11-11; the Rough Stone's cool grey read as ice on a sunlit wall.
- **Later pieces,** at the owner's choice: a plank bed, a standing stone for appeal and a great
  hearth that can warm a hall. The stone door is under "Better doors" above.
- **Recordings.** The maul borrows the builder's hammer knock (`craft_sound` "hammer" in
  `professions.json`) and the adze the axe's chop. Record an adze on wood and stone struck with
  stone, by the sound workflow; the Worker's chop stays for Rudimentary.

## Furniture

Found by the 2026-10-14 review (doc 177, parked by the owner) and the 2026-10-20 project
review (doc 254), and re-checked against the code on 2026-10-26.

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

### Nightly fires left for later

- **Fix direction.** The nightly fires plan (2026-10-28) left four things for later. The
  rules are in doc 34 ("Nightly fires", "Bedtime fires"), doc 31 and doc 62:
  - **a lighting step:** setting the log in is the lighting itself; there is no separate
    action to light the fire;
  - **dark weather by day:** fires light only at dusk or at bedtime, never under a dark sky
    by day as Stonehearth's do. `FurnitureFires` follows `WorldClock.is_night()`; this would
    also read the day's weather (`WeatherManager.current_definition()`) and need a rule for
    when a fire lit by day goes out;
  - **torches** stay lit day and night and take no fuel; feeding them too is the owner's
    call;
  - **`FireLightingTest` in the job gate:** it runs only in the furniture area. Adding it
    makes the gate 56 tests, the count CLAUDE.md gives.

---

## Rooms

### Room types left for later

Left out when the dining room, the pantry and the freezer came (2026-11-12; doc 34, "Room
types").

- **A storage zone set to food only** could count as a food store, so a larder kept on the
  floor would be a pantry too. Today only storage furniture that takes food counts (the food
  shelf): a zone takes every good until the player narrows it. It needs a rule for "food
  only" (the zone's categories and its item exceptions), a count of such zones by room when
  rooms are typed, and a signal from `StockpileManager` when zones or their filters change.
- **"Food only" is by order alone.** A cool room with a food shelf is a pantry whatever else
  stands in it, unless it fits a bed type or the dining room first. If a pantry should hold
  nothing but storage, give the types needs with a `most` of 0 and words for "take out".
- **Room types on the Rooms tool's outlines.** Every sealed room is green and a frozen one icy
  blue. A colour for each type with a legend above the dock (as the Appeal view's scale is)
  would show a colony's rooms at a glance.
- **More types:** a workshop (a career's bench), a storeroom (storage furniture that takes no
  food) and a cellar for aging (doc 42) when aging exists.
- **Seats at the table.** A dining room counts every seat in the room, so a stool by the wall
  or at the board game satisfies it. Counting stools on a dining table's guides would be
  stricter.

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
- **Reproduce** with the shader-slot review in its mining mode. The review and its
  launcher (`ShaderSlotReview.gd`, `RunShaderSlots.ps1`) were deleted in commit
  `b3a95478`: restore the review from git history and start it as doc 13, "Measuring
  performance", describes. Its report lists the mined blocks in order, and the first one
  carries the hitch.
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
  `tools/performance/LongSessionBenchmark.gd` (started as doc 13, "Measuring performance",
  describes), whose triggers
  squeeze a save, a midnight, arrivals and a season change into the first few minutes.
  First fix its `arrival_finished` handler (`LongSessionBenchmark.gd:90`): a
  three-argument lambda on a signal that now has four. Method: doc 13, "Measuring
  performance".
- **Done when** the run shows no unexplained growth in frame time or memory, or the cause
  of any growth is found.

### Far hauls still wait on searches

- **What happens.** Since 2026-10-30 one pickup search covers the loads lying the same way
  (doc 31, "Pickup searches by direction"). In the owner's save, with logs on a shelf reached by
  a long detour, the first load is now assigned after about 13–15 s at 60 fps instead of 75 s.
  What is left of the wait:
  - the route back to storage is still searched once per pickup stand; once the first dwarf is
    on its way, most of the rest of the wait is these delivery searches;
  - a crowd at the stockpile still searches one route per dwarf, so with 20 or more idle dwarves
    heading for the same far loads the wait grows with the crowd;
  - resuming a very long finished search (towards the 24,000-node limit) copies it whole, about
    8 ms once, when its load is claimed first (`NavGrid.reopen_search`).
- **Fix direction.** Only if play shows idle dwarves on Ready for work beside far loads: group
  delivery searches the way pickups are grouped (`StorageComponent.pickup_group`), and share one
  search among dwarves setting out from the same place. `HaulingFarLoadsTest` (hauling area)
  counts the wait in scheduler wakes.

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
- **Count** with the shader-slot review (`ShaderSlotReview.gd`, deleted in commit
  `b3a95478`; restore it from git history) on a copy of a save in a throwaway profile. The
  report gives users, the cap and a per-system breakdown.
- **Done when** a slot count over a large save shows only actors and doors reserving
  slots, and dwarves, animals and doorways light exactly as before.

### Sliced lights ignore furniture above the cut

Left open when doc 287 was accepted (2026-10-30); not seen in play.

- **What happens.** While the slice cuts a torch away, its light burns on and the rock above
  the cut still stops it, but furniture above the cut casts no shadow. A closed door above
  the cut no longer stops the light, so it could pass that doorway and reach a shown floor
  beyond, if one lies low enough.
- **Why.** `SliceLightOccluders` keeps only terrain in the shadows, and the slice hides
  furniture through `node.visible`. A hidden node casts nothing (doc 24, "Sliced lights").
- **Fix direction.** While a light is lifted, keep the shadow proxies of hidden doors in its
  reach casting, or add installed doors' boxes to the shadow rock.
- **Done when** a closed door above the cut stops a sliced torch's light as it does with the
  slice off, and nothing else changes for pieces the slice shows.

### Weather looks left for later

- **Idea.** Left out when rain and snow were redrawn (doc 291, 2026-11-01):
  - snow cover on open ground (its planned rates are in doc 24, "Planned weather effects") and
    wet-looking ground in rain;
  - cloud shadows drifting over the ground, so cloudy days read from the RTS angle: the sky is
    almost never on screen at the default pitch;
  - wind: the drops' `slant` always leans toward −X, and nothing sways trees or grass in a storm.
- **Fix direction.** Snow cover and wet ground can start from the landing map the precipitation
  already keeps, the top solid block and any water in each column (doc 24, "Drops land on what
  is really there"). Wind needs a direction in the weather data that the drops and the foliage
  both read.

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
  - Weather changes play since doc 309: on a day of rain or storm every open field is damp, so
    crops grow a quarter faster and pumpkins grow at all. The forecast would now tell the
    player something to act on.
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

### A third game speed

- **Idea.** A 3× speed was discussed with the shorter days (2026-10-29) and not added: the
  player has 1× and 2× (`play` and `fast` in `data/ui/time_slice.json`, keys 1 and 2). Other
  colony sims stop at 3× to 7×.
- **Fix direction.** A 3× button beside 2× under the Sky Dial, with its own input action,
  through `WorldClock.set_speed`. Check that a 30-dwarf colony keeps up at 3×.

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
- **Fungi and cave plants.** The farming loop exists (doc 309; doc 42, "Fields"), but a field
  needs the open sky today. Still needed: ground and water underground, light, art and
  placement ("Farming left for later", Underground crops).
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
  on rocky high-ground soil for best results" (`base:item:blueberry_cutting` in
  `data/items/items.json`). Since 2026-10-09 (doc 85) cultivated blueberries
  need grass, dirt or soil (`wild.transplant.ground_kinds`), bare rock is refused, and
  neither height nor soil changes growth. Reword it like the elderberry cutting's ("Root
  it in surface soil to grow a new bush"), and check the strawberry cutting's "good
  surface soil" and the unused hops and grape cuttings with it.

---

## Forestry

- **Wild tree growth and regrowth.** Wild trees keep their generated growth stage: wild
  saplings never grow and felled wild trees never come back. Only planted trees grow (doc 42,
  "Planting Seeds"). A sapling, wild or planted, floats if the ground under it is mined.
- **Forestry Zone and Clear Stumps.** Planned dock actions; neither is in
  `data/ui/dock.json`, and there are no persistent stump objects.

### Tree planting's open picks

Left open when tree planting was retired (2026-11-02); the rules are in doc 42, "Planting
Seeds".

- **Growth speed.** Every species reaches ancient in its first spring: planted on spring's
  first day, a pine is ancient by day 6, a juniper by day 8, an apple by day 10 and an oak by
  day 16. Slower, if planting should feel like a long investment, as the oak's JSON calls it.
- **Seed returns.** A felled mature oak gives an acorn one time in five, an ancient one 0.7 on
  average; pine, apple and juniper are similar. A planted forest gives back fewer seeds than it
  took, so wild trees stay the seed supply.
- **Fix direction.** Both are the owner's pick and data only: `stages.*.growth_duration_days`
  and each stage's `harvest.yields` in `data/flora/*_tree.json`. Wild trees don't
  grow, so the growth days change only planted trees.

---

## Construction

Build, Shapes, Copy and Blueprints were built on 2026-10-26 (doc 23, from "Build" to "Copy
and Blueprints"; changelog, doc 273). What follows keeps Deepdraft's per-voxel model: tools
only create ordinary block plans, every block is built and mined on its own, and nothing
becomes a building object (the weak spot of Stonehearth's building editor).

- **Dig and build.** Placing a blueprint also orders the mining of the rock in its way, for
  rooms cut into the mountain. Today that rock shows in rust and its blocks are left out.
  Build's Replace (doc 285) already plans solid blocks and swaps each in one job; a blueprint
  block in rock could be one of those.
- **Replace in Shapes and blueprints** (doc 285): Shapes could take Build's Replace switch,
  for paths and borders inlaid in a floor.
- **Replace's smaller pieces** (doc 285): turning a log in place (today a log of the same wood
  counts as a match, so Replace leaves it), and a picture of its own for the block panel's
  Replace… action, which uses Build's.
- **Furniture in blueprints,** kept as placement plans that wait for their items.
- **To the ceiling.** Walls raised to the rock above, so a room built in a cavern seals.
- **Roofs and other shapes,** only if homes outside the mountain come.
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

- **Planned, then held (2026-11-01):** doc 293 proposed dressed stone and planks as the first
  two textures, made by the Stonemason and the Carpenter. Dressed stone joins Stone's menu
  beside native stone and a planked block joins Wood's menu in each wood; each costs one of its
  good and gives it back when mined, and both work with Replace (doc 285), so a dug room's walls
  and floor are dressed in one drag. Each face of them a room shows, floor, walls and ceiling
  alike, adds a little appeal: a 7 × 7 bedroom dressed on its floor and walls shows about 160
  faces and gains about 5. The owner held them until the dwarves have iron tools ("let's hold
  off on these, they look too advanced"); the goods wait with "The Stonemason and the Carpenter
  left for later" (Dwarves).
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

### Built logs left for later

- **Fix direction.** The logs plan (2026-10-26) left four things for later. The rules are in
  doc 23 ("Build", "Shapes", "Copy and Blueprints") and doc 24 ("Built logs"):
  - **joints between lying logs and upright posts:** a lying log against an upright one just
    ends;
  - **a Crossed corners switch** for a hollow rectangle of logs: each side runs one block
    past the corner, so every corner is a +, as on the owner's Pokopia reference cabin.
    Today a hollow rectangle's corners are L joints;
  - **choosing the wood when placing a blueprint:** each log keeps the wood it was copied
    in;
  - **ghost logs for pending plans and a blueprint's placing ghost,** which show cubes. Only
    a Build or Shapes drag draws them (`BuiltLogs.ghost`).

### Builders reach only 5 blocks up

- **What happens.** A builder works only from floors at most 5 blocks below a block (doc 31,
  "Reach"), and nothing lifts it higher. On flat ground the owner's Blueprint 7, an 11-tall oak
  cabin with a grass roof, builds 188 of its 367 blocks; everything on layers 6 to 11 needs DEV:
  Finish construction. A Shapes stair flight longer than 8 steps leaves holes at layers 6 and
  up, and its plan stays on "No construction access".
- **The owner's pick (2026-11-09):** the reach stays at 5: "dwarves reaching 5 blocks is good, I
  don't think we should make it higher or lower". `reach_up` is not to change.
- **Fix direction.** Unscheduled. The builder-reach study (`tmp/builder_reach_20261027/README.md`,
  "Options" and "Recommendation") recommends:
  - first, marking the blocks no floor reaches in Place, Build and Shapes, counting them on the
    tag and naming them on the plan's panel;
  - then automatic scaffolding, as its own milestone: towers the plan puts up beside such
    blocks, builds first and takes down when done;
  - not raising `reach_up`: the cabin still fails at 11, and the hammer pose can't strike
    higher.
- **Done when** Blueprint 7 (a copy is `tmp/builder_reach_20261027/blueprint_7.json`), placed
  on flat ground, is finished by dwarves without DEV.

### Smaller construction leftovers

- **The Blueprints card and the placing tag count a shared good twice.** They list each
  construction kind against the stock (`BlueprintLibrary.goods` groups by kind and wood), so the
  Garden terrace shows "24 soil" for its dirt and again for its grass, against the same soil, and
  can miss a shortage. The plan's crate counts right. Count each good once.
- **A plan that starts high can find no crate site.** The crate search looks only 2 blocks up or
  down from the floor under the plan's lowest block (doc 31), so a Build or Shapes plan such as a
  slab off a ledge can stay on "No delivery access". It could search from a floor a builder can
  stand on, as a Replace plan does (`ConstructionController._replace_origin`).
- **More builders for a big project.** One builder works each plan (the owner's pick,
  2026-10-27: in a building the second material mostly waits on the first, so a second builder
  would rarely have work). More can follow if play shows big plans slow.

---

## Storage

- **More storage furniture.** The tool rack and the raw materials crate came first (doc 294;
  doc 31, "Storage priority and storage furniture"). Still to come, each with its own `storage`
  block and under the owner's container rule (doc 23, "The storage window"): barrels and chests
  for food and drink, shelves, and a valuables chest or vault, which is where raw gems go (the
  crate leaves them out). The food shelf came next (doc 299; doc 42, "Spoilage"). A planked shelf would
  come with the iron saw (doc 44), and a shelf for drink or seeds wasn't asked for: nothing makes drink
  yet.

### The finished goods pallet's later goods

- **Built with packed furniture** (doc 296, 2026-11-02): one piece to each of its four quarters.
- **Metal goods joined it** (2026-11-12): copper bars, three to a quarter
  (`per_slot_of` in its `storage`); copper fittings went on 2026-11-13.
- **Planks joined it** (2026-11-13, doc 308), four to a quarter.
- **Still to come.** Its first plan was "a Finished Goods pallets for metal bars, refined stones,
  planks, etc..." (owner, 2026-11-02). Refined stone waits for the Stonemason's turn (doc 44).
  With it, add its storage category (a `stockpile_*` tag, with its entry in
  `data/ui/storage_filters.json` and in `StockpileZoneComponent.DEFAULT_FILTER_TAGS`), add the
  tag to the pallet's `accepts`, and give it its number to a quarter in `per_slot_of`.
- **A quarter shows one of its goods,** however many it holds, as the crate's quarters do.
  Three bars could lie stacked on it.
- **A pallet placed before a new kind of good joins it keeps its saved choice of goods.** The
  owner's pallets of before 2026-11-12 take furniture only until All is pressed in their
  storage windows. A container could remember what it leaves out instead of what it takes, so
  that new kinds start accepted.

### Storage furniture's small leftovers

- **The storage window is tall for a tool rack.** It keeps the zones' body height
  (`StorageInspectorPanel`), so the rack's five tool pictures sit at the top of a mostly empty
  grid. Furniture may want a shorter body.
- **A crate's quarter shows one good,** whether it holds one or three. A heap would need smaller
  goods or a pile model: a good is 12 cells wide, and a quarter is 12 inside.
- **The settlement's storage meter says "cells used"** and counts a crate's goods among them
  (`SettlementPanel`, from `storage_used()`: a zone's cells, a crate's goods, a shelf's places). Its
  words should fit all three, or furniture should be counted apart.
- **Several food shelves share a line in Events** ("on the food shelf"), one line for each food, where
  each stockpile has its own number.

---

## Code health

### Godot's stricter GDScript warnings are off

- **Fix direction.** The 2026-10-22 code review (doc 258, step 5) postponed Godot's opt-in
  GDScript warnings (untyped declarations, unsafe property and method access) until the
  largest files were split, which its step 8 did. Turning them on changes `project.godot`
  (`debug/gdscript/warnings/...`), so it needs the owner's OK. Then fix what they report.

### Climate, view and spoilage tests are outside the gate

- **Idea.** `ClimateTest`, `TemperatureViewTest` and `FoodSpoilageTest` run in their areas
  (rooms, ui, dwarves and storage) but not in the job gate. Whether they join it was left to the
  owner (2026-10-29).
- **Fix direction.** If the owner agrees, add them to `gate` in `tools/test_suite.json`; the
  gate's test count in CLAUDE.md's Tests rule changes with it.

---

## Tools and builds

Left from the move to Linux (2026-11-02). Doc 13, "Platform", has the setup.

### The art capture launchers are still PowerShell

- **Cause.** `tools/voxel_assets/Run.ps1`, `tools/sky_art/Run.ps1` and `Verify.ps1`, and
  `tools/terrain_art/Capture.ps1`, `CaptureShoreline.ps1` and `Verify.ps1` were written for
  Windows (the Steam `.exe` path, `APPDATA`) and can't run on Linux. They stay as guides.
- **Fix direction.** When art work needs one, port it to Python on `isolated_env()` in
  `tools/run_job_reliability.py`, as `tools/import_assets.py` is, and delete the `.ps1`.

### No benchmark launcher on Linux

- **Cause.** The Windows benchmark launchers (`tools/performance/Run*.ps1`) were deleted in
  the move, at the owner's pick. Doc 13, "Measuring performance", says how to start a
  benchmark by hand.
- **Fix direction.** When performance work resumes, write one Python launcher: an isolated
  profile, a new label per run, the save copied in as `user://saves/quicksave.json`, and the
  original save's hash checked afterwards. The old launchers are in commit `4a300e8c`.

### A Linux build

- **Cause.** `export_presets.cfg` has one preset, Windows Desktop, still saved with the
  Windows path `D:/Deepdraft.exe`.
- **Fix direction.** Only when the owner asks for a build: install the 4.7.2 export
  templates, add a Linux preset with the fonts' licences ("The fonts' licences are not in
  the export yet", above), and point the Windows preset at `build/windows/manual_export/`.

---

## Food

### Winter food

Left open when the temperature and spoilage milestone was retired (2026-11-02); the rules are
in doc 34 and doc 42 ("Spoilage").

- **What happens.** Too little food grows near a start to last a winter. Counted in a copy of
  the owner's colony (2026-10-29), within 48–64 blocks of the flag and three other spots stand
  0–2 apple trees, 2–8 junipers and 0–7 elderberry bushes: 10–25 apples and juniper berries an
  autumn. Five dwarves eat 15 portions a day, 315 in a 21-day winter, and a day-by-day model
  left every start hungry for 15–21 of winter's days, cellar or yard. Given 300 apples and
  juniper berries and six elderberry bushes, a valley cellar fed the whole winter and the yard
  left 12 hungry days, so the keeping times do their job. Fishing (doc 289) came after the
  count.
- **From the owner (2026-10-29):** dwarves stock up for winter, and hunting comes later in the
  game. The keeping times stay; meat will carry its own `keeps_days`.
- **From the owner (2026-11-05):** winter food counts all food: berries, apples, juniper, fresh and
  dried fish, and meat once hunting comes. No single food has to carry it.
- **Counted with all food (2026-11-05):** a day-by-day model from the game's data, not a game run,
  from the real start (summer, day 1), with one Ranger, the plant counts within 64 blocks above, and
  an assumed lake of 240 fish (`tmp/winter_food_20261105/model4.py`, `model5.py`). Hungry winter days
  of 21, cellar and yard:
  - bushy starts, 2 racks: 0 and 4–7 with every bush picked as it ripens. Half picked: 0 and 7–10.
    With 4 racks the yard falls to 0–4;
  - starts with few bushes (the flag, the mountain): 21 and 21. No Ranger: 16–21 anywhere;
  - why: bushes regrow every 1.5 days in season, so they can feed the colony through summer and
    autumn while the fish go to the racks. If dwarves eat the fish before the racks get them, bushy
    starts fall to 13–15 and 18–20, so this needs a game run;
  - three moved elderberry bushes bring the flag to 0 and 3 if every crop is picked, but only 17 and
    17 if half are;
  - no yield or regrowth setting tried fixes poor starts and keeps the gap: where the flag recovers
    (regrowth 0.05, or apple ×6 and juniper ×8) the yard is fed too. Lakes smaller than 240 aren't covered by this.
- **Bushes need marking again after every crop.** A pick clears the harvest mark (`_stamp_crop` in
  `SurfaceDetailManager`), so all this bush food takes a new order every 1.5 game days, 18 minutes at
  ×1.
- **From the owner (2026-11-06):** no standing harvest order. Once the Farmer is built, bushes inside a
  farming zone get picked by the Farmer (doc 42, "Required future connection: bushes in a farming
  zone"). Until then, the "every bush picked" counts above take a new order for every crop.
- **The Farmer is built (2026-11-14, doc 309).** Bushes and fruit trees in a field are picked
  with no order, and a field adds a food the colony sows. The model run again with a field
  (`tmp/farmer_20261114/winter_model.py`: carrots in summer, turnips in autumn, dry soil; a
  model, not a game run). Hungry winter days of 21, cellar and yard:
  - one Ranger and a 6 × 6 field: 0 and 0 at all four starts, the flag and the mountain included,
    which had 21 and 21. A Farmer who arrives only on autumn's first day gives the same;
  - no Ranger, a 6 × 6 field: 14 and 14 at the starts with few bushes, 0 to 3 and 11 at the bushy
    ones. Two such fields: 0 and 11 everywhere;
  - so a field lifts the poor starts, which no yield setting did. But with fish and a field the
    yard is fed too: late turnips last half the winter in the open, and fresh fish carry the
    rest. The cellar still decides it when the field is the colony's only food (0 against 11).
    Whether the yard should fail there is the owner's call; the game run below comes first.
- **Fix direction.** Hold the yields until the Farmer picks zoned bushes. Then a real game run from a
  bushy start and from the flag to replace the model, then tune what's left. Tune the supply, not the
  keeping times. Whether fish reach the racks before dwarves eat them doesn't depend on the Farmer, so
  a game run can answer that sooner.
- **Done when** a five-dwarf colony that keeps its autumn harvest in a cool cellar gets through
  its first winter with at most a few hungry days, and one that leaves it in the yard goes
  hungry for most of the winter.

### Farming left for later

Left open by doc 309 (2026-11-14); the rules are in doc 42 ("Fields"), doc 41 ("Profession
System"), doc 23 ("Fields") and doc 31 (FARM).

- **Numbers to settle in play.** Every crop's days and yield, the levels (25, 100, 250 and 800
  tiles), the two-day sowing margin and a quarter faster in damp soil are starting values. A
  third round of carrots needs the Farmer to keep pace: the last sowing day is Summer 14.
- **Underground crops.** Mushrooms in the dark, all year, are the dwarves' own crop. A field
  needs grass or dirt under the open sky today. Needed: ground underground (dirt the colony
  builds is already a field's ground), water there, a rule for light, the plump helmet's place
  beside brewing, and the level that sows it.
- **The brewing and weaving crops** (hops, grape vine, pig tail), with the Brewer. They join
  `field_crops.json` with a `farmer_level`; their models are still placeholders (doc 64).
- **Cooking.** A pot of stew, the crops that want it (potatoes, beans), and whether a cooked
  meal fills more than a raw portion (also under "Grilling left for later").
- **Seeds from traders:** new crops as goods a merchant brings (doc 51).
- **Wildlife in the fields.** Rabbits and deer leave crops alone. Nibbling wants a small loss a
  plant, a claim so two animals don't share one, and something to keep them out: the log fence
  has no use yet (doc 45, "Planned food connections").
- **A Keep for a field,** if rot becomes a nuisance. The owner chose none (2026-11-14): everything
  ripe is picked and stored.
- **Tending.** No weeding and no watering by hand: a Farmer's work is hoeing, sowing and
  pulling. A bucket from the water would give a field above the spring something but rain.
- **Height and frost.** A crop grows the same in the valley and under the summit, and no frost
  takes it. The calendar's autumn runs from 9°C to −3°C, so a frost rule needs the crops'
  seasons thought through first.
- **Soil that tires, and compost** from food that rots (also under "Food keeping left for later").
- **The harvest's crates** lie in the field until haulers come, in the open, where food spoils
  fastest. A Farmer could carry its own pulls to the store.
- **A field cannot be reshaped:** remove it and lay it again; its tilled soil stays. A tile that
  is dug away stays in the field, and the field's edge is still drawn over the hole.
- **Trees in a field** are found by their trunk's centre inside the field's rectangle, so a tree
  on the edge of an odd-shaped field can be picked without standing on one of its tiles.
- **A plant cannot be inspected.** A click on a tile opens the field's window; the object
  explorer does not know a tile's plant, and there is no hover card for it.
- **Drawing.** A field's plants are a node a tile, as bushes are. 30 dwarves' fields are some
  300 to 1,500 tiles. A tile's model is 56 to 1,536 triangles (ripe kale is the most), and
  its shadow proxy 80 to 764, since a one-cell ridge cannot fill a coarser grid. A full
  16 × 16 field was not profiled. Batch them by crop and stage, or draw the ridges once a
  field, only if a profile shows the need (the standing decision on performance work).
- **A Farmer's craft page** (Crafters → Farmer) is still a preview: beehives and what else a
  Farmer makes.
- **Level 6 and the Green Thumb trait** (doc 41, "Planned trait effects").
- **Picking in a field is silent,** as all hand gathering is ("Actions without a sound of their
  own").
- **The field's sounds wait on the owner's ear** (`tmp/farmer_20261114/sounds/review.html`).
  If the mattock is too heavy for a hoe, a hoe in mud (Freesound 124916) is next to try; if the
  four pulls sound like two things, the weed alone can supply them; the sowing may sit too low
  to hear. The hoe's draw back through the soil has no sound, and all four sources are MP3
  previews, not the lossless originals.

### Food keeping left for later

Left out of the temperature and spoilage milestone (2026-10-29).

- **Ice.** Only cellars just under the summit freeze, for about two weeks around winter's first
  day. A freezer all year needs ice cut in winter and kept in a cellar, or a steeper height
  rule. Ice on the tarn and lake, and fishing through it (doc 289), would come with it.
- **Barrels and chests that slow spoiling,** with storage furniture's later steps (Storage).
- **A rotten item,** when farming wants compost. Rotten food is simply gone today.
- **Wildlife raiding food left outside,** and frost on crops once farm plots exist. A food shelf would be
  a natural answer to the raiding.
- **Fix direction.** Spoilage is one hourly rule (`FoodSpoilage`, `food.spoilage` in
  `data/tasks/task_config.json`; doc 42, "Spoilage"): a container would scale its speed, and a
  rotten item would replace the units it removes. Ice works through a room's temperature, and
  the climate keeps no stored warmth, so ice would be the first feature to need thermal mass
  (doc 34, "No warm-up").

### Sawn timber left for later

Left open by doc 308 (2026-11-13); the rules are in doc 44 ("Specialist workbenches", Planks)
and doc 64 ("Furniture tiers").

- **Every piece on doc 308's list is built** (2026-11-13): seven plank pieces. The ideas the
  owner passed over are kept under `tmp/plank_pieces_20261113/` and `tmp/plank_look_20261113/`.
- **The fence and the gate stay logs** (doc 308; doc 64, "Field work stays hewn"). Their two
  plank ideas are kept in `tmp/plank_pieces_20261113/fence_gate/` should that change.
- **The saw in the Carpenter's hand.** A Carpenter still swings the stone adze at the bench and
  is heard as an axe (doc 306, step 2; "Actions without a sound of their own" below). Sawing
  planks wants the pull saw, a sawing motion and a saw's strokes.
- **A plank bed, a plank door and a plank stool** on the Carpenter's page, beside the camp's
  rough ones.
- **Building with planks** ("Build textures by progression").
- **A new promise for iron.** Planks were the iron saw's reward. It becomes finer work: the
  joiner's bench, joinery and carving (doc 44, the ladder).
- **The Stonemason's turn:** dressed stone and a dressed look, with its copper chisel (owner,
  2026-11-13: "Stonemason later").
- **One recipe for all planks.** Each wood has its own sawing recipe today. If four cards are
  too many, one recipe could take any log and give that wood's planks; a recipe's output would
  then depend on its goods, which standing orders and the cards' counts do not allow for yet.

### Actions without a sound of their own (review 2026-11-13)

From the owner: "can we see what other actions exist that might require sound, do some carpenter
sounds need changed because they have a saw now". A review only: nothing here is chosen or built,
and each wants real recordings (the sound workflow in CLAUDE.md). What plays today is in doc 13
("WorkFeedback").

- **Borrowed today, and due to change with the copper tools in hand** (doc 306, step 2):
  - the Carpenter's bench work plays the axe's chop under an adze stroke; with the pull saw it
    wants a saw's strokes, timed to the sawing motion;
  - the Stonemason's bench work plays two stones struck together (the builders' hammer); with the
    chisel under the maul it wants a chisel tapped into stone;
  - the Blacksmith hammering a copper tool plays the same two stones; it wants stone on copper.
  - The sound should come with the motion, as the smelter's did: a saw heard under an adze swing
    would be worse than the chop.
- **A field's work has its own cues** since doc 309 (the hoe in earth, a tile sown, a ripe one
  pulled); picking a bush or a tree in a field is still silent, as below.
- **Silent, and seen all the time:** goods picked up and set down (hauling, and every delivery);
  gathering by hand (stones, berries, apples, juniper; clearing shrubs and plants; uprooting,
  replanting and planting); furniture placed, packed and removed; ladders set and climbed; doors
  swinging on their hinges.
- **Silent, at rest:** eating; the board game; a log put on a nightly fire and the fire catching.
  Grilling's sizzle and the drying rack are under their own headings below.
- **Silent ends:** a mined block breaking and a boulder cleared show dust and make no sound; the
  copper setting.
- **The interface has no sounds** beyond the promotion chime: no click, no order placed, no
  refusal, no event (the event log's own list has "a sound for new entries"). Whether the game
  wants any is the owner's call.
- **Fits as it is:** the Miner's copper pick (the recording is a metal pickaxe on rock, which the
  Worker's stone pick shares), the Worker's axe at the crude workbench, a boulder cleared with
  the pick, built wood taken down with the axe.

### The smelter's sounds left for later

Left open by doc 307 (2026-11-13); the cues are in doc 13 ("WorkFeedback") and doc 44 ("Charging
the basic smelter", "Its batch on show").

- **The owner's listening.** None of it has been heard; levels and choices wait on the owner's
  ear (`tmp/smelter_sounds_20261113/review.html`).
- **A roar under the crackle.** The fire is a kiln's crackle. No natural recording of a steady
  roar turned up that is long enough to loop and audible on small speakers; one would suit a
  blown fire better.
- **A copper tool hammered on the anvil stone** still knocks as stone on stone (the builders'
  hammer). Stone on copper wants its own recording.
- **The copper setting** is silent: the coals go out and the bar shows. A tick or a hiss could
  mark it.
- **The basic smelter being made, and other benches' work,** have no sounds of their own beyond
  the axe and the hammer.
- **Lossless originals.** The nine masters are decoded HQ MP3 previews, as the other recorded
  sounds are; the original uploads need a Freesound login.

### Fishing sounds left for later

Left open by doc 305 (2026-11-12); the cues are in doc 13 ("WorkFeedback") and doc 42 ("Fishing").

- **The drying rack is silent:** hanging wet fish and taking down dry ones. Each wants a
  recording of its own, through the sound workflow (CLAUDE.md).
- **The wait is silent** by choice. A line's faint creak or the float's lapping could mark a long
  wait if it reads as empty in play.
- **Lossless originals.** The eight masters are decoded HQ MP3 previews, as the other recorded
  sounds are; the original uploads need a Freesound login. With them the masters could be made
  again from `source.json`'s pages.
- **The grill's sizzle** is under "Grilling left for later".

### Fishing ideas left for later

- **Idea.** Left out when fishing was built (doc 289, 2026-10-31); fishing through ice is in
  "Food keeping left for later":
  - stocking a pond the player made, since water the colony makes holds no fish;
  - fish in cave pools other than the spring cave's, once caves hold water ("World / caves");
  - ducks reacting to fishers;
  - fish in trade.
- **Fix direction.** Each is its own feature. A water a zone can fish is an entry in
  `fishing.waters` (`data/tasks/task_config.json`) matched to a generated footprint by
  `FishingSystem.water_of_cell` (doc 42, "Fishing").

### Grilling left for later

- **Idea.** Left for later when grilling was built (doc 290, 2026-10-31):
  - **the hearth,** also an open fire; the owner's pick was the campfire first;
  - **a sizzle,** which needs a new free recording, downloaded only with the owner's OK; until
    then the campfire's crackle carries the moment;
  - **other foods,** such as meat once hunting brings it (fruit and dried fish aren't grilled);
  - **whether a grilled fish should fill more than a raw one,** once winter food is weighed
    ("Winter food");
  - **a Cook** and cooked meals that can be stored (doc 41's Loves to Cook trait reserves one).
- **Fix direction.**
  - A fire grills when its definition says `grilling` (only `campfire.json` today). A grill's
    places are the stools facing the fire, then the camp area's sides (`DwarfDining`); a hearth
    against its wall needs places of its own.
  - A food grills with `food.grill` in `items.json` and its own stick models, raw and
    grilled (`DwarfAssets.grill_sticks`).
  - The sizzle would be a `fish_sizzle` bank in `data/audio/work_feedback.json`, through the
    sound workflow (CLAUDE.md), played while the fish browns (`DwarfGrillPose`).
  - Grilling's numbers, still to be settled in Play, are `food.grilling` and `mood.grilled` in
    `data/tasks/task_config.json`.

### The Ranger's step 4: rare fish

- **Idea.** The owner's picks (2026-11-01), not built yet: one rare fish for each water,
  perhaps pike in the lake, salmon in the river, golden trout in the tarn and a cave eel in the
  spring cave.
  - They bite from level 4: 3% of catches at level 4 and 6% at level 5, and those levels'
    rewards say so ("rare fish start to bite", "rare fish bite twice as often").
  - A rare fish lands as three portions.
  - The journal names it: "Runbrin landed a pike at the lowland lake".
  - The Ranger gets "Landed a rare fish", +4 for 12 game hours.
  - The catch log gains a rare-fish row.
- **Fix direction.** Art first, in the fish's look (doc 42, "Fishing"): each rare fish in
  crates at three fills, on the line, raw and grilled on the stick, and its inventory picture.
  Then the rare fish in `items.json`, each water's rare fish and odds in `fishing.waters`,
  the rewards' words in the Ranger's `experience` (`professions.json`), the memory in
  `DwarfMood` with its journal lines, and the row in `CatchLog`.

### The Ranger's later ideas

- **Idea.** Left open when the Ranger was built (doc 292, 2026-11-01):
  - **smoked fish,** beside the drying rack's dried fish;
  - **better rods,** made by other careers; the kit's rod is Tier 1;
  - **wild berries and fruit:** whether Rangers also pick them, which is Gather work for
    everyone today;
  - **rare fish worth more than food,** through trade or a trophy on the wall;
  - **the levels and the big-fish odds,** still to be settled in Play (the Ranger's
    `experience` in `professions.json`).
- **Fix direction.** Ask the owner when step 4 or hunting is planned. A career does only the
  work its `work` list in `professions.json` names (doc 41, "Each career's work"), so picking
  for Rangers means adding the harvest tasks there; a better rod is an equipment upgrade (doc
  41, "Agreed equipment progression").
