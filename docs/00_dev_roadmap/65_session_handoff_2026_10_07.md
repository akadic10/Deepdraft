# 65 — Session handoff: 2026-10-07

This is the current starting point, superseding
[62 — Previous handoff](62_session_handoff_2026_10_06.md). The session repaired
loose-item support and Object explorer styling, tuned shallow-tunnel darkness,
and added a playable Worker crafting loop. The player accepted the revised
darkness and liked the Worker's axe animation. Their later requests produced
crafting sounds, a rough stump in place of the fitted bench, and a correction to
where the first bench is crafted. Those changes passed the checks below; final
player acceptance of every follow-up is not assumed.

No next feature has been chosen. This documentation pass adds no gameplay changes.

## Current player experience

The dock is **Orders · Zones · Rooms · Place · Craft · Colony · Inventory · Menu**.
Hearth & iron remains the visual direction. Stonehearth informed the initial
workshop/queue interaction through the supplied screenshots and installed source;
the models, code and UI implementation are Deepdraft's own.

| Area | Result | Reference |
|---|---|---|
| Loose goods | Mining away support settles loose goods onto terrain below. Loading repairs unsupported old positions. Reserved pickups release safely; carried/stored goods retain their owners. | [63 — Loose items](63_loose_item_support_and_explorer.md) |
| Object explorer | Shared cabinet chrome, identity card, scrolling facts and fixed actions now match Slice/Rooms. Remembered positions and specialized dwarf/storage content remain supported. | [63 — Explorer](63_loose_item_support_and_explorer.md), [23 — UI](../20_player_interface/23_user_interface.md) |
| Shallow tunnels | Entrance reach increased from 7 to 12 individual voxel blocks; sealed rooms retain the 0.008 readability floor. Dwarves overlapping solid terrain no longer inherit the bright slice-surface fallback. | [24 — Rendering](../20_player_interface/24_world_rendering.md) |
| Worker crafting | Craft opens recipes and finite-batch/maintain-stock orders. Any current Worker can make a bench without Carpenter promotion, then use the installed bench for torches. | [64 — Worker crafting](64_worker_crafting.md) |
| Allowed wood | Pine only by default. Each order can explicitly allow Juniper, Oak or Apple; excluded wood never substitutes when selected wood runs out. Choices are editable and saved. | [64 — Material rules](64_worker_crafting.md) |
| Crude Workbench | A rough 1×1 stump replaces the initial 2×1 trestle design. Workers use any open cardinal side at any placement rotation and reconsider the closest side after pickup. One Worker at a time. | [64 — Stump redesign](64_worker_crafting.md), [art guide](../60_asset_creation/61_voxel_art_guide.md) |
| Work sounds | Both recipes play the existing six axe-on-wood variants at animation contact. Camera distance/zoom, slice visibility, pause and the shared Work bus control playback. | [64 — Audio](64_worker_crafting.md) |
| First-bench location | The dwarf now crafts beside collected timber. The old logic returned to the job-assignment position, which could be near the settlement flag. The flag has no crafting role. | [64 — Pickup-site correction](64_worker_crafting.md) |
| Inspector destination | Crafting shows the actual ground work spot or claimed stump position, instead of the scheduler's placeholder zero coordinates. Pickup still identifies the ingredient location. | [51 — Dwarf inspection](51_hearth_iron_dwarf_inspector.md) |

## Playable crafting loop

| Recipe | Cost per batch | Output | Work time | Requirement |
|---|---|---|---|---|
| Crude workbench | 1 allowed log | 1 packed bench | 8 simulation seconds | None; shape timber at its pickup spot |
| Wooden torch | 1 allowed log | 4 packed torches | 6 simulation seconds | Installed crude workbench/stump |

Use **Craft**, queue the bench, then **Place → Workshops** to install it. Queue
torches and use **Place → Lighting** to mount them. **Place finished item** in
Craft opens the matching placement design; the installed stump's explorer also
offers **Craft items**. Place's Crafting count now reflects real queued output.

Orders support batches, spare-stock targets, pause/resume, cancellation and
reordering of unassigned work. Maintain targets count available spares, not
installed/reserved/carried items; full four-torch batches may exceed a target.
Updating a maintain order also updates its allowed-wood list.

Only permitted raw timber qualifies. Workers prefer the nearest available loose
log, then the nearest allowed stored unit across zones and containers, using the
existing Manhattan distance estimate. This is not a species preference order.
Oak staves and finished furniture are not inputs. Removing the active log's
species returns that log and preserves partial progress.

The stump has a 0.875-block cut working top and 1-block maximum height. The wooden
torch is an iron-free fork/peg design with a 1.5-block model mounted 1.5 blocks
above the floor, fitting starter three-block-high tunnels. Installed torches
provide range 6, energy 1.3 and heat 150; packed torches are unlit. Fuel and
burn-out are not implemented.

## Ownership and compatibility

- `CraftingManager` is a scene node and the single recipe-data owner for
  `data/workshops/worker_crafting.json`. `WorkerCraftOrder` owns player intent,
  partial work and one transient `CRAFT` lease. Priority is 46: below mining and
  felling, above placement and hauling. Current tasks are not preempted.
- Ingredients stay physical until completion. Interruptions, sleep, lost access,
  order pause and bench removal release reservations and return unconsumed cargo.
  Cancelling removes the order; pausing preserves it.
- Save section `worker_crafting` restores at priority 70, after furniture,
  items and dwarves. It stores recipe keys, quantities/mode, pause state, work
  progress and allowed-ingredient keys. Claims, task IDs, selected work positions
  and audio are transient. Carried timber belongs to the existing dwarf save
  owner and returns as loose goods on load.
- Old saves without this section start with an empty queue. Orders without a
  wood list adopt Pine; explicit empty/invalid lists stay empty. Furniture/item/
  recipe keys remain stable. Saved benches become the smaller stump at their
  original placement cell, releasing the previous second tile.
- The lighting correction changes shading only. Three-block navigation
  clearance, bedrock protection, work eligibility and slice concealment remain
  the existing contracts.

## Verification and review evidence

These are successful checks from the relevant implementation passes, not a claim
that every suite ran after every later edit. The **last gameplay correction**
(pickup-site crafting and inspector destination) reran `WorkerCraftingTest` and
`DwarfInspectorTest`. This documentation pass checks references and consistency
without rerunning gameplay.

| Pass | Checks and retained evidence |
|---|---|
| Loose support/explorer | `LooseItemSupportTest`, native `ObjectExplorerTest`, hauling/capacity, inspector, storage filters and real save/load. See doc 63 and `tmp/loose_support_review/final/`, `tmp/object_explorer_review/cabinet_fix/`. |
| Entrance lighting | Native `TunnelEntranceTest`, `UndergroundLightingTest`, `RoomLightingTest`; reports have empty failure lists. `tmp/underground_lighting_review/entrance_fix/`, `tmp/room_lighting_review/entrance_fix/`. |
| Initial crafting | Real crafting/installation, four-torch conservation, cancellation/sleep, maintain stock, exclusive bench access and torch light; furniture/hauling/mining/Orders regressions and eight-entry navigation at 960/1280/2560. `tmp/worker_crafting_review/regression/`, `navigation/`. |
| Wood selection/save | `WorkerCraftingWoodTest`: loose/stored/container exclusions, proximity, opt-ins, active edits, suspended containers, menu and migration. `SaveManagerRoundTripTest`: nondefault wood lists through quicksave/autosave/backup scene reloads. `tmp/worker_crafting_review/wood_filters/test.log`, `wood_filters/save/test.log`. |
| Sound | `WorkerCraftingAudioTest`: contact/hold/wrap/stall, pause/speed, interruption/resume, hidden/distant work, sound position and completion bounds. Native Work-bus recordings for both recipes had peaks about 0.414/0.429 without clipping. `tmp/worker_crafting_review/audio/`; sound timing reran after the stump change in `stump/audio/`. |
| Stump | `WorkerCraftingStumpTest`: 16 completed batches across four approach sides × four rotations; model/occupancy bounds, material and axe alignment, saved identities, opposite-side pickup and three blocked sides. `tmp/worker_crafting_review/stump/test.log`. Main crafting also passed. |
| Final pickup-site correction | `WorkerCraftingTest`: distant pickup, no return trip, local finished item and live ground/workshop destinations, plus the crafting loop. `DwarfInspectorTest`: existing selection/UI/cargo behavior. `tmp/worker_crafting_review/pickup_site/test.log`, `pickup_site/inspector/test.log`. |

Useful previews: [stump from four sides](../../tmp/worker_crafting_review/stump/four_sides.png),
[wood checklist](../../tmp/worker_crafting_review/wood_filters/allowed_wood_menu.png).
The checklist capture predates the stump redesign and still shows the old bench art.
The generated stump thumbnail is `assets/ui/furniture/crude_workbench.png`.
WAVs recorded from the game are in `tmp/worker_crafting_review/audio/`.

Runtime tests used isolated APPDATA/LOCALAPPDATA folders. The existing fixture
sky/weather startup warnings remain; final named runs passed without script
errors. Earlier failed or pre-fix diagnostic logs may also remain in `tmp/`.

## Remaining work and next-session entry

1. Read this handoff, [64](64_worker_crafting.md) and the relevant system docs.
   Restart play mode for the latest code/art. This session added no global
   `class_name` or autoload, so a project reload is not required.
2. Choose further work with the player. Carpenter/specialist production,
   profession progression/labor controls, multiple ingredients, quality, fuel,
   farming, full needs, bed use and autonomous dining remain future work.
3. Keep [Issue 002](00_open_issues.md) **parked**: dwarf overlap with unmined
   terrain needs a movement/visual-overlap reproduction. Fixing its brightness
   did not fix collision or establish the route's root cause.
4. Keep [Issue 001](00_open_issues.md) **open**: the older mining-face idle stall
   was not resolved by these crafting, support or lighting changes.
5. Treat lighting-dependent work restrictions as a separate decision; current
   darkness only affects presentation.

Implementation, assets, data and docs remain uncommitted in the shared workspace.
No commit or repository reset was requested or performed for this handoff.
