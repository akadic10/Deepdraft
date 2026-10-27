# 31 — Task System

**Fruit hauling (2026-10-19, 253):** HAUL reuses the scheduler’s successful
pickup/delivery proofs to plan bounded matching-fruit top-ups. A load whose one
item is edible produce (crate capacity above 1, no unique instance) may fill that
basket up to the item's `crate_capacity` (24 for current fruit) from other loose
baskets of the same item key and material. Forbidden, claimed, unique-instance
and unreachable goods are skipped, and the basket keeps its normal crate carry
cost. `StorageComponent.plan_fruit_haul` and `FruitHaulPlanner` take sources
reached by short out-and-back spurs from legal ground-handling stands on the
proven route, bounded by `task_config.json` `hauling`: `fruit_detour_blocks` (8
extra steps per load), `fruit_planning_budget_usec` (750), `fruit_probe_nodes`
(128), `fruit_route_cells` (512) and `fruit_candidate_limit` (16). A distant or
costly basket waits for another trip. Storage owns each source's exclusive claim
and exact destination quantity tokens, which may span partial and empty slots.
At hand contact only the reserved portion leaves a source and joins the one
carried basket (one hand holds it while the other gathers); leftovers stay on
the ground. Delivery validates every token before distributing the basket, and
cancellation releases all claims and drops the actual contents once. Saves keep
real counts on either side of contact; routes and reservation groups are
transient. Planning also runs at completed-pickup boundaries; it is not a
per-frame loose-item scan. A missing proof or exhausted optional budget falls
back to ordinary delivery. `fruit_pickup_path` returns a typed empty
`Array[Vector3i]` when nothing is cached: `Dictionary.get`'s untyped `[]` fails
that typed return and once broke the fallback. HARVEST_TREE 50 and HAUL 40
remain unchanged, so a batch may be picked before it is hauled; consolidation is
an optimization, not a harvest-to-haul continuation.

**Mining planning holds (2026-10-19, 246):** mining renews the temporary leisure
hold while its bounded route search expands nodes, using the same helper as
pickup/delivery planning (`TaskScheduler._extend_planning_hold`). This prevents
strolling from repeatedly changing a long search's start cell; before it, mixed
work left mining pending with no worker assigned. Checks without progress and
completed searches never renew the hold, so it can expire; budgets, priorities
and navigation invalidation remain unchanged.

**Shared hauling geometry (2026-10-17, 215):** identical pickup/delivery searches
and their planning quanta are shared across storage leases in a bounded cache.
Inventory changes refresh quotes without discarding valid navigation progress;
terrain/occupancy/ladder changes still invalidate proofs. Physical claims and
capacity remain source-owned.
- The cache (`TaskScheduler._haul_route_cache`) is keyed by start, target and
  approach cells and holds `hauling.route_cache_entries` (64) searches. Sharing the
  quantum matters: otherwise each storage lease spent a fresh full quantum on the
  same hard pickup before any lease tried the next load.
- Eviction ends sharing, never a lease's own unfinished frontier, which rejoins the
  cache on its next turn. A finished proof is reused while its navigation
  dependencies are current. A search that ran out of allowance (reachability
  unknown) is retried only after the maximum backoff (`backoff_max_s`, 30 simulated
  seconds).
- Load, New game and quitting to the title clear it with the rest of the
  scheduler's runtime state (`TaskManager.reset_runtime_state`).

**Hauling fairness (2026-10-17, 213):** pickup/delivery searches retain one
context per worker/start/pickup within a lease. Long searches yield after the
existing planning quantum so reachable alternatives can run. Idle-pool changes
re-rank workers while preserving unchanged searches; repeated personal-need
checks cannot continually erase progress. Proximity, navigation validation,
budgets and contact-time inventory ownership remain authoritative. A pickup
deferred after its quantum is not unreachable: once every alternative has had a
turn, deferred pickups become eligible again and resume their retained searches
(`TaskScheduler._yield_haul_candidate`). This also helps a lone worker whose
nearest pickup is hard to reach. Before, every storage lease chose the same hard
pickup first and need checks kept resetting the search, so reachable loads were
never assigned. Completed pickup proofs are rechecked against their navigation
dependencies before reuse, and goods are claimed only after both legs are proven.
`HaulingRouteFairnessTest` and `HaulingSharedRoutesTest` (hauling area) cover
this and the shared geometry above.

**Furniture Move (2026-10-12, 132):** installed furniture posts its normal
UNINSTALL job after the player confirms a destination. The destination reserves
the resulting exact item and posts FETCH_BUILD when it exists. The packer gets
the same continuation preference as shrub Move. Interrupted workers preserve
cargo; destination cancellation releases claims and either cancels uninstall or
leaves the packed piece for storage. Invalid destinations never consume it.
The reliability gate includes FurnitureMoveTest (30 fixtures).

**Food self-care (2026-10-12, 131):** hungry dwarves release work using the normal
NEED_INTERRUPT protocol. The personal food component uses bounded supply/route
searches, reserves one stored portion without withdrawing remotely, collects it
at a legal access cell and consumes it only after eating. All assignment and
reconciliation paths exclude active eaters. Failure releases claims, preserves
cargo and returns the dwarf to work until the game-time retry. There is no public
EAT job. The reliability gate now includes food and shrub regrowth (29 fixtures).

**Stone construction (2026-10-17):** an area owns `ConstructionWork` and a
`ConstructionMaterials` storage destination. Up to two HAUL leases stage real
stone in its temporary crate using the existing carrying budget, and their
reservations never exceed the stone still needed. Loose goods
reuse normal bundles; stored portions are reserved, collected at legal source
stands and deposited together. Once all remaining stone is delivered, one
FETCH_BUILD lease proves access and performs three seconds of hammer work per
voxel at normal labor speed, without another pickup. The builder works from stands
outside unfinished blueprint cells, so later blocks cannot bury it. Final support/occupancy and
worker contact checks precede consumption. Release preserves project stock and
per-cell progress. Cancellation drops unused stock at the crate; completed blocks remain.
Cells are internal units, not tasks (doc 205). Since 2026-10-26 a plan stages its
material's own good (rough stone, soil or logs). The crate keeps goods by item, then
material, so a crate of mixed logs builds each block from the log it used, and blocks taken
out of a plan drop the goods it no longer needs beside the crate
(`ConstructionMaterials.refund_excess`).
- The crate is automatic packaging, placed on level, walkable ground within six blocks
  of the blueprint (`materials_crate_radius` in `data/construction/blocks.json`, beside
  `cost`, `work_seconds` and the builder's reach). It needs four walkable sides and
  keeps clear of plans, storage, furniture, access structures and fence barriers. It
  occupies one voxel, so nothing is built into it.
- With no site the project reports **No delivery access** and keeps looking. If the
  crate loses its floor or fills with water, its delivery leases are cancelled, the
  staged stone drops there and a new site is chosen.

**Shared lifecycle implemented (2026-10-11, 126):** the contract proposed by the
jobs and dwarves architecture review (doc 125).
Sources own persistent work and physical inventory; the saved journal owns order
identity/diagnostics; attempts own transient fencing and meaningful progress.
The simulation-time supervisor releases stalled work safely, and repeated stalls
become Needs attention in Dwarf development's Job inspector. Fetch planning checks
pickup and delivery, including later craft ingredients. Searches retain frontiers
across family/order yields and distinguish budget exhaustion from proven no route.
Runtime commit receipts prevent stale/duplicate/reentrant effects; source state
and current save snapshots remain the recovery authority. Timing limits,
configuration and boundaries are in
[Orders, attempts and supervision](#orders-attempts-and-supervision).

**Permissions (updated 2026-10-11, 110):** disallowed goods outside storage are excluded
from haul, material and tool queries and rejected at reservation/pickup/commit.
Stored goods are always available colony stock; storage filters control acceptance
and relocation, independently of outside-item permission.
Toggling Disallow releases affected work and reservations, returning carried
goods to the worker's feet intact, flag included. Placed water stones are never
automatic haul targets: explicit packing reuses UNINSTALL (`WaterStonePacking`),
while Move reserves the resulting exact-instance item
for a FETCH_BUILD plan. Packing progress survives interruption; the water effect
stays active until the physical item is packed. The stones' rules are in doc 33.

> **Implemented.** `TaskManager` autoload + `Task` class. The implementation **refines** this spec:
> tasks are **intent-sized leases posted by work sources** (a mining zone posts ≤ `MAX_WORKERS`
> zone leases, never per-block tasks — O(intents), not O(blocks)); storage is **per-type sorted
> buckets** with resumable scan cursors; the scheduler is **event-driven with a heartbeat**,
> time-budgeted (1 ms/wake) and probe-capped so overload degrades into assignment latency, never
> frame time; `priority` stores only the **static** value;
> unreachable tasks carry `retry_at`/`blocked_count` exponential backoff (BLOCKED is a status,
> not a separate queue). Tunables live in `data/tasks/task_config.json`. Release protocol:
> releasing a task is always cheap and always legal (see Release Protocol). The tables below remain the
> design source for priorities and skill mapping; colony-state bonuses are planned only.
>
> **HAUL live:** stockpile zones are the
> second work-source family, proving the lease pattern generalises. A zone posts ≤
> `max_haulers` HAUL leases; the `DwarfAgent` executor pulls bundles within the JSON
> `hauling.carry_capacity` budget (4 points: rock/ore 1, raw log 2, crate 4)
> from `ItemDropManager`'s loose-item index, with owner-guarded item
> reservations and the release protocol (any interrupt drops the whole pouch at the
> dwarf's feet as loose items). When mining or a removed bridge takes away support,
> `ItemDropManager` coalesces the changed columns and settles only the loose items
> in them; a settling item's pickup reservation is invalidated, and stored or
> carried goods are never moved. Stockpile source ids live at `1_000_000 + zone_id`
> (`StockpileManager`); hauling tunables in `task_config.json` `hauling`. Workshops are next.
>
> **FETCH_BUILD + UNINSTALL live:** the furniture pipeline's two
> first-class types (SH parity — placement is a dedicated task group whose band TOPS
> restock, hence FETCH_BUILD 45 > HAUL 40). A ghost posts ONE type-matched fetch lease; a
> 📤-flagged piece posts ONE uninstall lease. Source ids for new families come from
> `TaskManager.allocate_source_id()` (monotonic from 10M). The zone re-based onto the shared `StorageComponent` contract with containers as
> the second face; five work-source families now ride one scheduler unchanged.
>
> **Placement over storage hauling (doc 87):** storage hauling never hides owned
> goods from placement. Goods a HAUL pull has reserved, is carrying or is moving
> between storage areas still count as ready in Place and in the colony inventory:
> `TaskManager.placement_haul_offers()` adds `StorageComponent.placement_haul_items()`
> to `FurniturePlacementController.get_catalog_stock()`, with outgoing stored claims
> counted once. Plants, ladder sections and bridge kits share that stock. Only live
> HAUL pulls qualify, never crafting, fetching or another plan, and an exact
> instance promised to another plan stays out.
> - Browsing Place and choosing a design leave hauling alone. Once a designation
>   exists, `FurnitureGhostComponent.update_lease()` takes the nearest matching offer
>   through `TaskManager.redirect_haul_to_placement()`, also while paused. The haul
>   is cancelled and releases its storage tokens, so the same unit cannot be taken
>   twice.
> - Before pickup the ghost claims the item and the normal fetch collects it. A
>   hauler already carrying a single packed object keeps it
>   (`DwarfAgent.detach_placement_cargo`) and starts the fetch at its
>   travel-to-install phase: no storage detour, no second pickup. Other cargo, such
>   as a multi-unit cutting crate, drops loose so the fetch can split one unit.
> - Cancelling, sleep or a lost site follow the release protocol and keep the item.
>   No extra inventory store or save field is involved. `PlacementHaulPriorityTest`
>   (gate) covers the handoff.

**2026-10-11 furniture dispatch fix:** an unreachable idle dwarf no longer puts
an entire furniture order into backoff. Ordinary work-source probes retain failed
worker/lease pairs across budget yields and try every other eligible idle dwarf
before delaying the order, using the same rule as mining. Worker movement,
navigation changes and idle-pool/work-permission changes invalidate those failures.
Completed or cancelled leases discard their records. `FurnitureAssignmentTest`
covers a campfire with an isolated first worker, bounded one-probe wakes, fully
blocked backoff, item conservation and recovery after a route opens.

**2026-10-11 scheduling fairness:** a fresh pass starts in priority order, but a
bucket that exhausts its wake yields to the next nonempty job type on the next
wake. Ordinary and surface searches retain separate frontiers per type; haul,
craft and Move retain their existing comparisons. This lets reachable access
construction proceed while higher-priority mining routes are still unproven.
The 1 ms budget, probe limits, worker eligibility and assigned-work ownership
are unchanged. Completed passes and a newly available idle pool start at the
highest priority again. What broke before: higher-priority mining searches above an
unfinished ladder spent every wake, so the ladder job that would open their route
never got a turn (roadmap 88; `LadderSchedulingTest`).

> **FELL_TREE live (2026-10-04):** each designated tree posts one lease at
> priority 50. `SurfaceFloraSpawner` owns persistent work and felled records;
> `TreeFellingComponent` owns the transient lease/reservation and trunk-side stand
> candidates. `DwarfAgent` tries one full route per frame, works only from a valid
> adjacent floor cell, and releases safely on interruption. Saved work survives
> cancellation, sleep, seasonal model changes and reload; task IDs do not.

> **CRAFT live (2026-10-07):** scene-owned `CraftingManager` posts one
> lease per runnable Worker order at priority 46. `WorkerCraftOrder` owns recipe,
> quantity, allowed wood and partial progress; it reuses physical fetch/work/
> set-down and cheap release. Only current Workers receive these starter jobs.
> First benches are made at the ingredient pickup spot; workshop recipes use
> a reachable open side of a claimed stump. The lease's
> placeholder `target_pos` is not the worksite: routing and inspection use the
> order's actual `work_cell`.

> **CRAFT pickup selection fixed (2026-10-09, doc 98):** compare every eligible
> idle Worker at the first physical ingredient (the recipe's first
> `additional_ingredients` entry, such as Rough Stone, else an allowed log). Rank
> read-only loose/storage quotes by Manhattan pickup distance, with idle order only
> breaking ties (`TaskScheduler._try_assign_crafts`). Bounded, resumable searches
> prove a handling stand and a free workbench edge before reservation; a recipe
> without a workshop works at the pickup stand. Execution receives the exact quoted
> material, pickup stand and delivery stand; a blocked candidate does not hide other
> workers/materials/benches. Priorities and work permissions run first. Idle-pool,
> work-policy, goods, storage and workbench changes restart a pending comparison, and
> terrain edits along either proven leg (a finished pickup leg included) clear it. An
> assigned Worker retains the current batch, including later inputs
> (`CraftIngredientPlanner`); the next batch returns to normal selection.

## Overview

**Idle leisure live (2026-10-09):** available dwarves can stroll locally or sit
on an installed log stool or bench without creating an IDLE lease or leaving
`_idle_dwarves`. `receive_task` cancels leisure movement and releases any seat
before the work executor starts. Existing priority, profession, permission and
proximity rules remain responsible for selecting workers. Sleep still removes
a dwarf from availability. Leisure rules: `41_dwarf_agents.md`, Idle activity
(doc 99).

**2026-10-17 planning hold correction (216):** read-only work checks retain stationary
leisure timers and seated poses. Only an owned leisure walk is cancelled to
stabilize the route start, with the existing privacy-exit exception. Repeated
unproductive holds must allow idle progress between checks; they cannot restart
the start delay forever. Actual assignments still cancel leisure and release
chairs through `receive_task`. Active bounded route searches retain their
progress-based hold extension.
- `TaskManager.hold_for_planning()` holds an available dwarf the scheduler is
  considering for `supervision.planning_hold_seconds` (4 simulated seconds). A new
  hold starts only 2 s after the last one ended (a constant in that function).
  While held, `DwarfIdleBehavior` freezes its timers and pose; between holds they
  run on.
- Only a bounded search that expands nodes renews the hold: haul pickup/delivery,
  surface work, exact-item Move and mining. A dwarf holding a task, or on a walk
  leisure does not own (such as a DEV walk), is never held.
- The chair is validated before the hold, so uninstalling it, lost support or
  changed access still frees the seat at once.
- Before this, each hold cancelled all leisure, so the 2.5–5 s start delay
  restarted in every gap and never finished: a dwarf could stand Looking around
  while planning never assigned it work. `DwarfIdlePlanningTest` (gate) guards it.

**HARVEST_TREE live (2026-10-09, 84):** appended priority-50 hand-picking work for
juniper, extended to apples in 252. The existing adjacent-work source respects the actual trunk footprint
and nearest eligible worker selection. One source per marked tree prevents
simultaneous picking/felling. Separate progress and saved crop cycles prevent
work transfer or duplicate yields; leaving the season cancels harvest leases.
Only stages with an authored `fruit_harvest.work_seconds` post the job; the crop
rules are in [42 §Fruit Trees](../40_economy_colony/42_farming_brewing.md#fruit-trees).

**CLEAR_PLANT live (2026-10-08):** appended priority-50 adjacent hand-work lease
for decorative flower and reed clearing. JSON defines 1.5 seconds and no item yield.
It shares cheap release and source-level partial progress with other surface
details. Construction/support displacement retires work without rewards.

**CLEAR_BOULDER live (2026-10-08):** one priority-50 lease per marked stone.
`SurfaceDetailManager` owns removal and partial work; the adjacent work component
shares tree felling's side routing/release protocol with a separate task type and
tombstone key. Dwarves use the mining pick and stone feedback. Cancellation,
sleep and reload retain progress; completion awards two Rough Stone by JSON.

**GATHER_SCREE live (2026-10-08):** a priority-50 adjacent work lease collects one
walkable loose-stone clump by hand in three seconds for one rough stone. It uses
the same source-level progress/release contract; displacement cancels without
loot.

> **HARVEST_SHRUB / CLEAR_SHRUB live (2026-10-08):** appended priority-50
> types use the adjacent work/release contract and hand-gathering pose. Harvest
> retains the plant and grants one saved crop per eligible calendar season;
> completed clearing permanently removes it and yields one cutting. Partial work is separate per
> action. Season end cancels harvest leases safely.

**UPROOT_SHRUB live (2026-10-08):** appended priority-50 adjacent hand
work lifts a mature shrub without fruit/cutting rewards. Partial work belongs
to its persistent plant record. Replanting uses the existing priority-45
`FETCH_BUILD` pipeline with a `ShrubPlantingComponent` destination plan and
saved work progress. Move reserves one exact plant identity through interruption;
generic Place accepts any available whole shrub of that species. Release drops
the intact plant, and destination validity is checked before consuming it.
Despite the names, UPROOT_SHRUB and `ShrubPlantingComponent` also lift and replant
wildflowers, matched by their per-shape packed item (doc 85).

**Move continuation (doc 82):** exact-plant Move fetches compare workers at the
packed plant's pickup sides. The uprooter is preferred among workers already at
a side, while higher-priority work and sleep still take precedence. Both pickup
and destination routes are checked before claim transfer, with resumable ranking
and probes. Interrupted Moves clear worker preference and immediately reclaim the
dropped plant for the plan; nearby replacements can finish. Ordinary Place and
other fetch sources retain their existing selection contract.
- `move_worker_quote()` (`ShrubPlantingComponent`; `FurnitureMovePlan` for
  furniture) lists the claimed item's walkable pickup sides without changing the
  claim. Its signature (claim, cell, preference, sides) and the idle-pool version
  invalidate a stale comparison.
- Candidates rank by Manhattan distance, then continuation, then idle order. The
  preference counts only for the uprooter standing at a side, so it never pulls a
  dwarf off other work, wakes a sleeper or recalls a distant former worker.
  `continuation_worker` is transient: it clears when the fetch is reserved or
  released and is never saved.
- The winner receives the proven pickup and delivery stands (`prefer_fetch_plan`).
  The rest of the pass skips a worker a Move comparison has just assigned, so a
  second job cannot replace the Move.
- Pickup and delivery searches renew the worker's planning hold while they expand
  nodes (doc 134), so leisure strolling cannot keep restarting a long route.

**Cutting planting live (doc 80):** the same planting source uses `FETCH_BUILD`
with one cutting as its input. The whole crate is reserved only until pickup,
which splits one unit (`take_planting_item`) and retargets the animation to the
new cargo; the remainder stays in place, and its spare units can back other
standing Place requests (`spare_claimed_units`). Cancelling before pickup keeps
the stock, cancelling while carrying drops the intact cutting at the worker's
feet, interruption retains plan work, and removing the plan abandons its work
without spending a cutting. Completion creates one young player plant after the
final site check. Calendar-driven growth needs no worker lease.

**Planting animation (doc 83):** planting work drives reach/lower/release from
arrival (or at once if the dwarf already stands at the site), then commits
directly without a second `FETCH_DEPOSIT`. Mature shrubs and flowers take 1.25
seconds (`transplant.plant_seconds`) and cuttings three (`wild.planting.work_seconds`);
the registry hands either to the plan as `planting_seconds`, so the set-down lies
inside that time. The packed plant's base meets the destination ground while the
feet stay planted; pause and clock speed scale work and pose together.
Interrupted work resumes an animated reach over its remaining duration; cargo
stays worker-owned, and saves record its exact identity as carried goods, until
the final valid-site commit.

The Task System is a **global asynchronous job queue** that decouples player designations from dwarf agent execution. Players issue high-level orders (mine this zone, haul these goods); the Task System assigns work to available dwarves. Orders are represented as **intent-sized tasks** (zone leases, future item-batch hauls) — the atomic block-level unit of work never exists as a queued Task object.

Every task needs a work source whose executor performs it (a MINE or HAUL lease
carries its `zone_id`; other families carry `source_id`). There is no generic
walk-and-wait executor: a task that reaches `DwarfAgent.receive_task` without one
is failed at once (`fail_dwarf_task`, "No work source can perform this task") so
it can neither hang the worker nor cycle through PENDING. Tests that need
stand-in work post a one-block mining designation instead.

The executors live in the dwarf's work-execution component (doc 258 step 8):
`receive_task` hands the lease to `DwarfWorkExecution.start`, which runs the
MINE zone lease, UNINSTALL and adjacent clearing itself; its base script
`DwarfCarryWork` holds the HAUL and FETCH_BUILD/CRAFT executors and the shared
pickup/carry/set-down presentation. Walk results, aborts, sleep and
`force_interrupt` reach them through `walk_finished`, `abort` and
`clear_task_state`.

**Shared work-source table (doc 258 step 6, 2026-10-22).** Ladders, bridges, tree
felling/harvest (`SurfaceFloraSpawner`), surface details (`SurfaceDetailManager`) and
furniture ghosts and uninstall leases (`FurniturePlacementController`) keep their
sources in one helper, `scripts/components/WorkSourceTable.gd` (a plain `RefCounted`,
not an autoload). It owns the owner key ↔ source map, source-id allocation,
`register_work_source`/`unregister_work_source`, retiring, and the routing of
TaskManager events:

- completed → `work_task_gone(task, -1)`; cancelled/failed →
  `work_task_gone(task, assigned_to)`. The source may re-post its lease.
- released → `work_task_released(task, dwarf)` only. The lease stays PENDING,
  so only the worker's transient claim is freed and nothing is re-posted
  (Hard Rule 12).
- `retire(key, cancel_tasks)` forgets the source *before* cancelling its tasks, so
  cancellation cannot re-post, then unregisters it and calls
  `work_source_retired()` (ghosts release their item claim).

`FurnitureGhostComponent`, `InstalledFurnitureComponent` and `TreeFellingComponent`
implement the three hooks, and the ladder and bridge sources inherit them. The table
saves nothing: owners save their own records and rebuild their sources on restore,
which gives each source a fresh id. Mining, stockpiles, construction, crafting and
water stones keep their own routing. The work-journal key
(`WorkSourceAdapter.locator`) names the task type (`task_type=FELL_TREE`), not its
enum number, so reordering `Task.Type` does not orphan saved journal entries.
`WorkSourceTableTest` (gate) covers the contract.

## Task Object Schema

```gdscript
# scripts/systems/Task.gd — as shipped
class_name Task extends RefCounted

enum Type   { MINE, HAUL, FETCH_BUILD, UNINSTALL, FELL_TREE, CRAFT, CLEAR_BOULDER, GATHER_SCREE, HARVEST_SHRUB, CLEAR_SHRUB, CLEAR_PLANT, UPROOT_SHRUB, HARVEST_TREE }   # SMELT/FORGE later (doc 44)
enum Status { PENDING, ASSIGNED, IN_PROGRESS, BLOCKED, COMPLETED, FAILED, CANCELLED }

# Task-type categories, listed only here (doc 258 step 6):
const SURFACE_WORK := [...]  # tree, boulder, scree, shrub and plant work: one executor, the surface matcher
const GATHER_WORK  := [...]  # surface work done by hand (gather pose and contact)
const SHRUB_WORK   := [...]  # HARVEST_SHRUB, CLEAR_SHRUB
const COMMON_WORK  := [...]  # what any dwarf may take before permissions; Workers add CRAFT

var id:            int           # unique auto-incremented ID
var type:          Task.Type
var status:        Task.Status
var priority:      int           # STATIC base priority
var target_pos:    Vector3i      # representative position (zone stand cell for leases)
var payload:       Dictionary    # type-specific data; MINE lease: { "zone_id": int }
var assigned_to:   int           # dwarf id, or -1 if unassigned
var source_id:     int           # owning work source (zone id), or -1
var created_at:    int           # Time.get_ticks_msec()
var retry_at:      int           # msec; BLOCKED tasks invisible to the scheduler until then
var blocked_count: int           # consecutive blocked probes (backoff + task_unreachable)

# Lifecycle (see Orders, attempts and supervision):
var order_key:        String     # stable journal key ("order:N")
var order_locator:    String     # WorkSourceAdapter.locator of the owning source
var wait_reason:      String     # why a pending order waits (Job inspector)
var attempt:          RefCounted # WorkAttempt.gd for the current assignment; replaced on each assign
var planning_context: Dictionary # per-worker route frontiers, kept across yields
var recovery_paused:  bool       # Needs attention: skipped until retried
```

## Global Task Queue

`TaskManager` (Autoload) holds the authoritative tables (per-type buckets, not one global queue):

```gdscript
var _tasks: Dictionary            # id -> Task                (authoritative store)
var _pending: Dictionary          # Task.Type -> Array[int]   (ids, sorted by static priority desc)
var _active: Dictionary           # dwarf_id -> task_id
var _idle_dwarves: Array[int]     # event-maintained, never rebuilt by scanning
var _completed_log: Array         # ring buffer, last 200
```

The matching itself runs in `scripts/components/TaskScheduler.gd` (doc 258
step 8), which receives these same table objects. It owns the resumable scan
cursors (`_scan_cursor`, Task.Type -> int), the specialised haul/craft/surface/move
comparisons, worker rejections and the lease handoff (`assign`). Attempt
supervision — progress samples, `_recover_attempt`, `_reconcile_workers`,
retries and job diagnostics — runs in `scripts/components/TaskSupervision.gd`.
`TaskManager` keeps the public API, tables, signals and config.

> **Agent note:** pending buckets must remain sorted at all times. Insert new tasks using binary search on static `priority` rather than appending and re-sorting each frame. Dwarves hold task **IDs**, never Task references — lookups go through the manager so a cancelled task can be freed safely.

### Orders, attempts and supervision

The lifecycle contract (docs 125 and 126): every accepted order is progressing,
waiting for a named reason, completed, cancelled or visibly failed. No order or
assigned dwarf may sit in unexplained inactivity. Completion still depends on a
feasible world, eligible workers, available supplies and fair scheduling, so a
permanent obstruction needs the player. Recovery never invents supplies,
teleports a dwarf, creates prerequisite work (no automatic ladders or bridges) or
marks unfinished work complete.

- **Orders.** The work source owns the order and its physical progress (mined
  blocks, staged ingredients, installed furniture, paid ladder sections), which is
  authoritative between attempts. `WorkJournal` (`TaskManager.journal`, saved as
  the `jobs` section, doc 13) holds identity and diagnostics only.
  `WorkSourceAdapter.locator` derives the order from the source's saved ID
  (`zone_id`, `ghost_id`, `installed_id`, `id`; craft orders save theirs for this)
  or stable coordinates, so a ladder keeps one order as its sections advance. The
  journal gives each order a key (`order:N`) and each assignment a monotonic
  attempt generation that a load never reuses. It keeps 200 transitions and at
  most 200 retired records; paths, claims and executor phases are never journaled.
- **Attempts.** `TaskScheduler.assign` gives each assignment a fresh `WorkAttempt`:
  phase, work unit, last useful progress, phase deadline and commit receipts. It
  is never an inventory or a second owner of world state.
- **Fencing.** An executor's complete, release, fail and commit calls carry its
  task id and attempt generation (`matches_attempt`), so an old attempt's
  completion cannot finish a newer one. `commit_step` marks a work unit
  committing *before* it calls the world owner, so a duplicate or reentrant
  callback cannot repeat the effect; a rejected validation clears the receipt. Receipts are runtime guards, not a
  durable log: commits are synchronous, a load rebuilds attempts from source and
  inventory state, and crash durability is the last successful save. Durable
  orchestration with event replay (Temporal) was considered and rejected in 125: a
  retry cannot fix a route, geometry, a missing material or a logic error.
- **Supervision.** `TaskSupervision` runs on simulation time, honours pause and
  loading, and checks a bounded set of active attempts per pass. Useful progress
  is a shorter remaining route, finished handling or more source work
  (`DwarfAgent.work_sample()`); a running `_process` is not progress. An attempt
  with no useful progress for `no_progress_seconds`, or past its phase deadline
  (expected duration × 2 + `no_progress_seconds`), is aborted and released with
  `NO_PROGRESS`: cargo returns intact, claims are freed and the order replans.
  After `recovery_limit` such failures without a successful commit, the order
  shows **Needs attention** (`recovery_paused`) with the reason. A commit resets
  the count; **Retry selected order**, a ladder change or, for mining, a nearby
  obstruction change lifts the pause. Ordinary route changes and resource races
  are not quarantined.
- **Reconciliation.** Each pass also checks four registered workers: a missed idle
  notification is repaired, and an orphan executor drops its cargo before the
  dwarf rejoins the pool. `worker_availability` reports Available, Working,
  Self-care, Recovering access or Trapped: no navigable footing.
- **Job inspector.** DEV only (Development → Dwarf tools → DEV: Job inspector,
  `JobInspectorPanel`), refreshed only while open: orders, waiting reasons, the
  active worker, attempt, phase and progress age, rejected-worker counts and the
  last 12 transitions. **Retry selected order** (`TaskManager.retry_order`) clears
  an unassigned order's plans, backoff and attention and reassesses the real
  world; it never bypasses validation or finishes work.

**Two-leg planning.** No physical claim is made until the plan proves worker →
pickup stand → work stand.
- `FurnitureFetchPlanner` quotes supplies read-only, then tries other items and
  every legal approach rather than trusting the nearest cell. The source receives
  the material, exact instance and both stands; reservation and physical transfer
  validate them again. A ladder section installs from the floor or the section
  below, a bridge from either legal bank; those sources keep paid sections, decks
  and safe departure.
- Hauling proves pickup access and the route on to storage. Opportunistic bundle
  extras check their own access during execution and can be skipped
  (`StorageComponent.skip_item`).
- Crafting proves both legs for the first and every later ingredient.
  `CraftIngredientPlanner` (the `FETCH_PLANNING` phase) keeps the batch's staged
  goods and bench while it searches; interruption returns goods through
  `WorkerCraftOrder.cancel_fetch`.
- Mining keeps its exact multi-stand search (doc 32), surface work its stands, and
  uninstall revalidates its source at commit.

**Search fairness.** An expensive search yields to other job types and, after
`planning_quantum_slices` yielded slices, to other orders of its family. Frontiers
survive the yield: ordinary searches per worker in `task.planning_context`,
specialised ones per order (`TaskScheduler._family_frontiers`). Relevant nav-chunk
dependencies, the ladder revision and supply revisions invalidate plans;
unrelated terrain edits keep rejected-worker evidence. Exhausting the finite
allowance means reachability unknown ("Route search budget exhausted"), never a
proven missing route: `WorkRouteProbe` doubles the allowance from 6,000 nodes up
to `maximum_search_nodes`, keeping the frontier, and only then does the order
back off with that reason (doc 32). Construction changes wake route assessment;
blocked mining waits while existing access orders get their planning time.

**Configuration.** Only `TaskManager` reads `data/tasks/task_config.json`; other
components use `get_config_section()`. Its `supervision` section:

| Key | Default |
|---|---:|
| `interval_seconds` / `budget_usec` / `attempts_per_pass` | 0.5 simulated s / 500 µs / 8 |
| `no_progress_seconds` | 12 simulated s |
| `recovery_limit` | 3 supervised failures |
| `planning_hold_seconds` | 4 simulated s (then a 2 s gap, in code) |
| `planning_quantum_slices` | 8 yielded slices |
| `maximum_search_nodes` | 24,000 |
| `ingredient_planning_budget_usec` / `ingredient_planning_node_cap` | 250 µs / 32 nodes per tick |

Budgets are cooperative: one bounded query or operation can cross its deadline,
and preparation, final validation and assignment run synchronously, so a wake can
exceed the 1 ms scheduler budget. Ingredient planning adds up with active
crafters. Scheduler retry timestamps and backoff use wall-clock milliseconds;
work deadlines, handling and planning holds use simulated time, and pausing stops
execution and supervision even when a retry falls due. `JobLifecycleTest`,
`JobPlanningTest` and `JobMixedWorldTest` (gate) cover the contract.

## Action Weight Priorities

Static priority values come from `data/tasks/task_config.json`. Player overrides
through a Labor window remain planned.

| Task Type | Default Priority | Rationale |
|---|---|---|
| `MINE` | 50 | Core progression, moderate urgency |
| `FELL_TREE` | 50 | Player-designated raw timber supply |
| `HARVEST_TREE` | 50 | Pick seasonal fruit from a standing juniper or apple tree |
| `CLEAR_BOULDER` | 50 | Clear a marked surface stone; modest rough-stone yield |
| `GATHER_SCREE` | 50 | Gather a walkable loose-stone clump; one rough stone |
| `CRAFT` | 46 | Worker bench/torch orders; after mining/felling, before placement/hauling |
| `FETCH_BUILD` | 45 | Install finished furniture |
| `UNINSTALL` | 40 | Pack marked furniture for storage |
| `HAUL` | 40 | Keeps workshops fed; slightly less urgent than mining |

Farming, brewing and patrol have no task types yet; each gets its type and
priority when its feature arrives (doc 52 plans `PATROL` at 60). Dwarves idle
without a queued task.

**Planned, not implemented:** colony-state bonuses added to the static priority:

```
+20  if ale stockpile < 10 and task type == BREW
+15  if food stockpile < 20 and task type == FARM
+30  if collapse risk detected near task target and task type == MINE (remove blocks to relieve stress)
```

## Scheduler — Event-Driven with a Heartbeat

**2026-10-06 — proximity when assigning HAUL:** previously the idle queue's
first reachable dwarf claimed a storage lease. A cutter finishing a tree was
appended behind older idle dwarves, so distant workers could reserve all the
lumber first. New assignments compare available dwarves by distance to an actual
accepted pickup, after each dwarf has considered higher-priority work. Pickup and
storage reachability are checked before assignment. Failed nearby workers or
piles do not hide reachable alternatives. Existing assignments are preserved.
Successful bundle delivery completes the HAUL lease and returns the worker to
matching. Returning haulers cannot pull their next load directly, bypassing nearby
idle workers or higher-priority jobs. Storage replenishes its bounded intake leases
through the normal coalesced wake; no per-item task queue is introduced.

Every eligible idle worker receives a read-only pickup quote
(`StorageComponent.advance_haul_quote`) before one is chosen; quotes never
reserve goods, and `reserve_haul` still owns claims and bundling
(`TaskScheduler`). Distance is a floor-cell Manhattan estimate from the worker to
the quoted pickup, followed by bounded pickup and delivery reachability probes; it
is not an optimal assignment or a shortest-path comparison. Equal distances keep
idle-queue order. A pickup cell that fails its probe is excluded for that worker
only and the candidates are ranked again, so a farther worker or other supplies
can still win. The chosen executor receives that worker's exclusions, so its
reservation matches the quote.

> **As implemented (supersedes the original pure-polling engine).** The
> scheduler runs on **wake events** (task added, dwarf idle, zone destination changed, chunk
> dirtied near a blocked target), flushed at most once per frame; the `POLL_INTERVAL = 0.5 s`
> heartbeat survives as the safety net that catches `retry_at` expiries. Every wake is bounded
> by `scheduler_budget_usec` (1 ms) and `max_probes_per_wake` (8); the loop stops mid-scan and
> resumes from the per-type cursor on the next wake.

**2026-10-09 — proximity for adjacent surface work (doc 81):** the
`Task.SURFACE_WORK` types (tree felling and fruit picking, stone/scree
collection, shrub harvesting/clearing/uprooting and decorative plant clearing)
compare all eligible idle dwarves against valid adjacent work cells. Candidates
are ranked by Manhattan distance, then idle order, and checked with bounded route
probes. Failed sides/workers do not back off the job until alternatives have
been exhausted. Ranking is read-only: the source's `stand_cells(from)` neither
reserves work nor turns its retry cursor, and only the successful side reaches
`prefer_work_stand()` before the normal reservation. Each probe proves that exact
work stand, not a cell beside it, and caches the route
(`NavGrid.remember_reachable_path`) for the worker's approach, so assignment and
execution agree without a second full search. While a probe expands nodes it
renews the worker's planning hold (doc 134). Ranking and probing resume across
wakes, and idle membership/navigation changes invalidate stale comparisons. An
assigned job never moves to a closer worker who becomes free later; this is a
proximity heuristic, not a global shortest-route optimizer.

Matching loop per wake for non-hauling work:

```
1. Order pending type buckets by static priority desc, type ID for ties
2. For adjacent surface types and exact-plant Move fetches, compare eligible idle workers as above.
   For other types, visit compatible idle workers and scan from _scan_cursor[type]:
     skip if status != PENDING, or now < retry_at
     reachability probe (capped A*, node cap from task_config.json — default 1200)
     reachable   → assign; remove this dwarf from the idle pool
     unreachable → blocked_count += 1; retry_at = now + backoff(blocked_count); continue
3. Budget exhausted mid-scan → remember cursor, stop; next wake resumes there
4. No compatible reachable task → dwarf stays idle (IDLE is agent behaviour, not a queued task)
```

`backoff(n) = min(2^n, 30)` seconds. After 3 consecutive blocked probes → `task_unreachable(task)` fires for the UI; the task keeps retrying on its backoff schedule, re-armed early when `chunk_dirtied` touches terrain near its target.

Mining leases also recover when nearby placed-entity occupancy changes. The
mining controller invalidates the zone's cached work positions immediately,
then coalesces footprint changes into a deferred target refresh. It calls
`retry_order(order_key, "Nearby obstruction changed")` for pending leases,
clearing stale plans, worker rejections, backoff and attention state. The retry
API's optional reason defaults to `"Retry requested"`. Active ownership and
distant orders are preserved; this is not a global retry reset. The refresh is
deferred rather than throttled because a Move removes and installs a footprint in
the same frame; the terrain hook's 250 ms throttle would drop the removal (doc 174,
`MiningZoneWork.on_occupancy_changed`).

When HAUL leases are pending, matching uses three passes: compatible types above
HAUL's current bucket priority, the HAUL comparison, then remaining types.
Priority buckets and scan cursors remain; eligible workers are considered within
each bucket so proximity cannot bypass higher-priority work. HAUL compares read-only
pickup quotes for every eligible idle dwarf, ranked by Manhattan distance to the
pickup; queue order breaks equal-distance ties. It is a proximity heuristic with
reachability checks, not a global shortest-route optimizer.

Quotes scan incrementally under the wake deadline. The comparison, quote cursor,
and separate pickup/delivery probe stages survive a budget yield. Goods and slot
reservations only occur through the chosen dwarf's normal hauling executor.
Changed inventory/claims/rules, newly idle dwarves, and changed navigation
invalidate stale comparisons. A failed pickup is excluded for that dwarf's
comparison; the executor receives those exclusions for its initial pull. A task
backs off only after its worker/pickup alternatives are exhausted.

### Skill Compatibility

**Runtime update (2026-10-09):** Workers retain normal mining speed; the older
0.7 off-profession proposal below is not applied. Miner levels shorten digging
duration by 0/5/10/15/20 percent. Idle Miners get first refusal within the existing
mining bucket, without bypassing higher priorities or reachability. Work permissions
filter eligibility and safely release disallowed current jobs. An unreachable Miner
never holds a lease back from a reachable Worker. Profession rules:
`41_dwarf_agents.md`, Profession System (doc 96).

Each `Task.Type` maps to a preferred dwarf skill. A dwarf without the preferred skill can still take the task at reduced efficiency (×0.7 speed multiplier).

| Task Type | Preferred Skill |
|---|---|
| MINE | `skill_mining` |
| HAUL | `skill_hauling` |

**2026-10-14 — construction work-position cost:** a synchronous
`ConstructionWork.work_stands` call captures dwarf bounds and loose-item cells
once and shares them across candidate blocks. The snapshot ends with the call;
route yields and final construction commitment never reuse it. Other build
constraints remain live. This reduces repeated obstacle scans without changing
scheduler budgets, priorities or reservations (`ConstructionController.obstacle_snapshot()`,
doc 187). Before, `build_reason` enumerated every dwarf and loose item for each
candidate block; with hundreds of loose items that preparation used up the 1 ms
wake before the route search expanded a node, so construction was never assigned.

**2026-10-14 — planning progress at 30 dwarves:** hauling comparisons now share
one incremental eligible-item snapshot across workers for the same source and
inventory revision. Item-key acceptance/capacity checks happen once per key;
distances and route exclusions remain per worker. Inventory, claims, filters,
storage capacity, idle-pool and navigation invalidation remain authoritative.
Quotes make no physical claims. The shared snapshot is the `pickup_snapshot` that
`StorageComponent.advance_haul_quote` passes to
`ItemDropManager.advance_nearest_haul_query`. Before it, each worker repeated the
full eligibility scan, and with inventory changes restarting the scans a 30-dwarf
work yard never finished ranking a haul.

Fetch/build planning retains prepared delivery goals across route-search
slices, preventing stand preparation from consuming every slice before A*
can advance (`FurnitureFetchPlanner`'s `delivery_goals`;
`ConstructionWork.advance_fetch_plan` likewise prepares its goals in one slice
and searches in the next). Before accepting a reachable plan it refreshes legal stands and
the construction target mapping; invalid endpoints replan. Final reservation
and construction commitment retain live checks. The obstacle snapshot itself
still lasts only for one synchronous `work_stands` call. No transient planning
data is saved, and priorities and the soft 1 ms budget are unchanged.

The 30-dwarf yard now completes construction and hauling, but later frame
times are higher and some planning waits remain (doc 188). This is not a runtime
population cap or a guarantee against starvation in every settlement.

**Probe results are not stored as lasting data.** A failed reachability probe
either backs the task off or, while other idle workers remain, records a worker
rejection that is valid only for the current navigation and idle-pool revision.
Backoff (`retry_at`/`blocked_count`) is the only negative result that outlives
those changes.

**Runtime is not deterministic.** Only dwarf generation is seeded (doc 41).
Scheduler and agent behaviour depend on frame timing and wake order, so do not
chase replay determinism here.

## Release Protocol (Hard Rule 12)

Releasing a task is always cheap and always legal. No task type may be designed
so that abandoning it mid-way corrupts state. The dwarf decides *when* to
interrupt (doc 41); `TaskManager.release_dwarf_task(dwarf_id, reason, requeue_dwarf)`
decides what happens to the work:

- The task returns to `PENDING` with `assigned_to = -1` and is re-inserted in its
  type bucket. Its static priority is unchanged. Release reasons that prove a dead
  end (`PATH_INVALID`, `NO_PROGRESS`, `MATERIAL_UNAVAILABLE`, `PLAN_CHANGED`,
  `SEARCH_BUDGET_EXHAUSTED`) also apply backoff.
- Reservations are freed by the work source on `task_released`. A mining lease's
  reserved block returns to the zone's destination set.
- Source-level progress is never lost (completed blocks, saved per-source work).
  Progress on the current atomic unit, such as a partial swing on a block, is
  discarded.
- A carried item is dropped at the dwarf's feet as a normal loose item.
- The dwarf rejoins `_idle_dwarves` only after its interrupt behaviour finishes
  (sleep, eating, combat). A dwarf holding a task releases with
  `requeue_dwarf = false`; one holding no task calls
  `TaskManager.notify_dwarf_unavailable`, and both return with
  `notify_dwarf_idle`. An assignment that lands in the same frame the dwarf became
  unavailable is bounced straight back to `PENDING` by `DwarfAgent.receive_task`.

`Task.ReleaseReason` values: `NEED_INTERRUPT`, `COMBAT`, `PLAYER`, `PATH_INVALID`,
`SOURCE_EMPTY`, `NO_PROGRESS`, `MATERIAL_UNAVAILABLE`, `PLAN_CHANGED`,
`SEARCH_BUDGET_EXHAUSTED`.

Planned combat pre-emption (priority-85 combat work interrupting economy work,
doc 52) will call this same release path.

## Signals

```gdscript
signal task_added(task: Task)
signal task_assigned(task: Task, dwarf_id: int)
signal task_released(task: Task, dwarf_id: int, reason: int)   # see Release Protocol
signal task_completed(task: Task)
signal task_failed(task: Task, reason: String)
signal task_unreachable(task: Task)
```

---

*Prev: [23_user_interface.md](../20_player_interface/23_user_interface.md) | Next: [32_navigation_3d.md](./32_navigation_3d.md)*
