# 31 — Task System

**2026-10-10 permissions:** disallowed physical goods are excluded from haul,
material and tool queries and rejected at reservation/pickup/withdrawal/commit.
Toggling Disallow releases affected work and reservations, returning carried
goods intact. Placed water stones are never automatic haul targets: explicit
packing reuses UNINSTALL, while Move reserves the resulting exact-instance item
for a FETCH_BUILD plan. Packing progress survives interruption; the water effect
stays active until the physical item is packed. See milestone 110.

> **IMPLEMENTED (2026-06-10, doc 16 §2 — read that section first).** `TaskManager` autoload +
> `Task` class shipped with the First Dwarf Milestone. The implementation **refines** this spec:
> tasks are **intent-sized leases posted by work sources** (a mining zone posts ≤ `MAX_WORKERS`
> zone leases, never per-block tasks — O(intents), not O(blocks)); storage is **per-type sorted
> buckets** with resumable scan cursors; the scheduler is **event-driven with a heartbeat**,
> time-budgeted (1 ms/wake) and probe-capped so overload degrades into assignment latency, never
> frame time; `priority` stores only the **static** value with colony bonuses computed per wake;
> unreachable tasks carry `retry_at`/`blocked_count` exponential backoff (BLOCKED is a status,
> not a separate queue). Tunables live in `data/tasks/task_config.json`. Release protocol:
> releasing a task is always cheap and always legal (doc 16 §2.8). The tables below remain the
> design source for priorities, bonuses, and skill mapping.
>
> **HAUL live (doc 18 — Stockpiles & Hauling, banked 2026-07-11):** stockpile zones are the
> second work-source family, proving the lease pattern generalises. A zone posts ≤
> `max_haulers` HAUL leases; the `DwarfAgent` executor pulls bundles within the JSON
> `hauling.carry_capacity` budget (4 points: rock/ore 1, raw log 2, crate 4; doc 49)
> from `ItemDropManager`'s loose-item index, with owner-guarded item
> reservations and the §2.8 release protocol (any interrupt drops the whole pouch at the
> dwarf's feet as loose items). Stockpile source ids live at `1_000_000 + zone_id`
> (`StockpileManager`); hauling tunables in `task_config.json` `hauling`. Workshops are next.
>
> **FETCH_BUILD + UNINSTALL live (doc 19, 2026-07-11):** the furniture pipeline's two
> first-class types (SH parity — placement is a dedicated task group whose band TOPS
> restock, hence FETCH_BUILD 45 > HAUL 40). A ghost posts ONE type-matched fetch lease; a
> 📤-flagged piece posts ONE uninstall lease. Source ids for new families come from
> `TaskManager.allocate_source_id()` (monotonic from 10M — the doc 18 allocator debt,
> paid). The zone re-based onto the shared `StorageComponent` contract with containers as
> the second face; five work-source families now ride one scheduler unchanged.

> **FELL_TREE live (doc 48, 2026-10-04):** each designated tree posts one lease at
> priority 50. `SurfaceFloraSpawner` owns persistent work and felled records;
> `TreeFellingComponent` owns the transient lease/reservation and trunk-side stand
> candidates. `DwarfAgent` tries one full route per frame, works only from a valid
> adjacent floor cell, and releases safely on interruption. Saved work survives
> cancellation, sleep, seasonal model changes and reload; task IDs do not.

> **CRAFT live (doc 64, 2026-10-07):** scene-owned `CraftingManager` posts one
> lease per runnable Worker order at priority 46. `WorkerCraftOrder` owns recipe,
> quantity, allowed wood and partial progress; it reuses physical fetch/work/
> set-down and cheap release. Only current Workers receive these starter jobs.
> First benches are made at the ingredient pickup spot; workshop recipes use
> a reachable open side of a claimed stump. The lease's
> placeholder `target_pos` is not the worksite: routing and inspection use the
> order's actual `work_cell`. See [64 — Crafting](../00_dev_roadmap/64_worker_crafting.md).

> **CRAFT pickup selection fixed (2026-10-09, doc 98):** compare every eligible
> idle Worker at the first physical ingredient (stone for starter tools, timber
> for earlier recipes). Rank read-only loose/storage quotes by Manhattan pickup
> distance, with idle order only breaking ties. Bounded, resumable searches prove
> a handling stand and a free workbench before reservation. Execution receives
> the exact quoted material, pickup stand and delivery stand; a blocked candidate
> does not hide other workers/materials/benches. Priorities and work permissions
> run first. An assigned Worker retains the current batch, including later inputs;
> the next batch returns to normal selection. See
> [98 — Crafting selection](../00_dev_roadmap/98_crafting_worker_selection.md).

## Overview

**Idle leisure live (2026-10-09):** available dwarves can stroll locally or sit
in an installed wooden chair without creating an IDLE lease or leaving
`_idle_dwarves`. `receive_task` cancels leisure movement and releases any seat
before the work executor starts. Existing priority, profession, permission and
proximity rules remain responsible for selecting workers. Sleep still removes
a dwarf from availability. See [99 — Idle activity](../00_dev_roadmap/99_dwarf_idle_activity.md).

**HARVEST_TREE live (2026-10-09):** appended priority-50 hand-picking work for
juniper. The existing adjacent-work source respects the actual trunk footprint
and nearest eligible worker selection. One source per marked tree prevents
simultaneous picking/felling. Separate progress and saved crop cycles prevent
work transfer or duplicate yields; leaving the season cancels harvest leases.
See [84 — Juniper harvesting](../00_dev_roadmap/84_juniper_berry_harvesting.md).

**CLEAR_PLANT live (2026-10-08):** appended priority-50 adjacent hand-work lease
for decorative flower and reed clearing. JSON defines 1.5 seconds and no item yield.
It shares cheap release and source-level partial progress with other surface
details. Construction/support displacement retires work without rewards. See
[76 — Seasonal wildflowers](../00_dev_roadmap/76_seasonal_wildflowers.md) and
[77 — Seasonal reeds](../00_dev_roadmap/77_seasonal_reeds.md).

**CLEAR_BOULDER live (2026-10-08):** one priority-50 lease per marked stone.
`SurfaceDetailManager` owns removal and partial work; the adjacent work component
shares tree felling's side routing/release protocol with a separate task type and
tombstone key. Dwarves use the mining pick and stone feedback. Cancellation,
sleep and reload retain progress; completion awards two Rough Stone by JSON.
See [73 — Boulder pilot](../00_dev_roadmap/73_boulder_pilot.md).

**GATHER_SCREE live (2026-10-08):** a priority-50 adjacent work lease collects one
walkable loose-stone clump by hand in three seconds for one rough stone. It uses
the same source-level progress/release contract; displacement cancels without
loot. See [74 — Gatherable scree](../00_dev_roadmap/74_gatherable_scree.md).

> **HARVEST_SHRUB / CLEAR_SHRUB live (doc 75, 2026-10-08):** appended priority-50
> types use the adjacent work/release contract and hand-gathering pose. Harvest
> retains the plant and grants one saved crop per eligible calendar season;
> completed clearing permanently removes it and yields one cutting. Partial work is separate per
> action. Season end cancels harvest leases safely. See
> [75 — Seasonal shrubs](../00_dev_roadmap/75_seasonal_shrubs.md).

**UPROOT_SHRUB live (doc 79, 2026-10-08):** appended priority-50 adjacent hand
work lifts a mature shrub without fruit/cutting rewards. Partial work belongs
to its persistent plant record. Replanting uses the existing priority-45
`FETCH_BUILD` pipeline with a `ShrubPlantingComponent` destination plan and
saved work progress. Move reserves one exact plant identity through interruption;
generic Place accepts any available whole shrub of that species. Release drops
the intact plant, and destination validity is checked before consuming it. See
[79 — Shrub transplanting](../00_dev_roadmap/79_shrub_transplanting.md).

**Move continuation (doc 82):** exact-plant Move fetches compare workers at the
packed plant's pickup sides. The uprooter is preferred among workers already at
a side, while higher-priority work and sleep still take precedence. Both pickup
and destination routes are checked before claim transfer, with resumable ranking
and probes. Interrupted Moves clear worker preference and immediately reclaim the
dropped plant for the plan; nearby replacements can finish. Ordinary Place and
other fetch sources retain their existing selection contract. See
[82 — Shrub Move handoff](../00_dev_roadmap/82_shrub_move_handoff.md).

**Cutting planting live (doc 80):** the same planting source uses `FETCH_BUILD`
with one cutting as its input. Physical pickup splits one unit from a crate and
retargets the animation to the new cargo; the remainder stays in place. Cancel
returns the cutting, interruption retains plan work, and completion creates one
young player plant after the final site check. Calendar-driven growth needs no
worker lease. See [80](../00_dev_roadmap/80_shrub_cutting_growth.md).

**Planting animation (doc 83):** planting work drives reach/lower/release from
arrival, then commits directly without a second `FETCH_DEPOSIT`. Mature shrubs
take 1.25 seconds and cuttings three seconds, both configured per species in JSON.
Interrupted work resumes an animated reach over its remaining duration; cargo
stays worker-owned until the final valid-site commit. See
[83 — Shrub planting animation](../00_dev_roadmap/83_shrub_planting_animation.md).

The Task System is a **global asynchronous job queue** that decouples player designations from dwarf agent execution. Players issue high-level orders (mine this zone, haul these goods); the Task System assigns work to available dwarves. Orders are represented as **intent-sized tasks** (zone leases, future item-batch hauls) — the atomic block-level unit of work never exists as a queued Task object (doc 16 §2.1).

## Task Object Schema

```gdscript
# scripts/systems/Task.gd — as shipped (doc 16 §2.2)
class_name Task extends RefCounted

enum Type   { MINE, HAUL, FARM, BREW, BUILD, IDLE, PATROL, FETCH_BUILD, UNINSTALL, FELL_TREE, CRAFT, CLEAR_BOULDER, GATHER_SCREE, HARVEST_SHRUB, CLEAR_SHRUB, CLEAR_PLANT, UPROOT_SHRUB, HARVEST_TREE }   # SMELT/FORGE later (doc 44)
enum Status { PENDING, ASSIGNED, IN_PROGRESS, BLOCKED, COMPLETED, FAILED, CANCELLED }

var id:            int           # unique auto-incremented ID
var type:          Task.Type
var status:        Task.Status
var priority:      int           # STATIC base priority; colony bonuses applied at match time
var target_pos:    Vector3i      # representative position (zone stand cell for leases)
var payload:       Dictionary    # type-specific data; MINE lease: { "zone_id": int }
var assigned_to:   int           # dwarf id, or -1 if unassigned
var source_id:     int           # owning work source (zone id), or -1
var created_at:    int           # Time.get_ticks_msec()
var retry_at:      int           # msec; BLOCKED tasks invisible to the scheduler until then
var blocked_count: int           # consecutive blocked probes (backoff + task_unreachable)
```

## Global Task Queue

`TaskManager` (Autoload) holds the authoritative tables (doc 16 §2.3 — per-type buckets, not one global queue):

```gdscript
var _tasks: Dictionary            # id -> Task                (authoritative store)
var _pending: Dictionary          # Task.Type -> Array[int]   (ids, sorted by static priority desc)
var _active: Dictionary           # dwarf_id -> task_id
var _idle_dwarves: Array[int]     # event-maintained, never rebuilt by scanning
var _completed_log: Array         # ring buffer, last 200
var _scan_cursor: Dictionary      # Task.Type -> int          (resumable scan position)
```

> **Agent note:** pending buckets must remain sorted at all times. Insert new tasks using binary search on static `priority` rather than appending and re-sorting each frame. Dwarves hold task **IDs**, never Task references — lookups go through the manager so a cancelled task can be freed safely.

## Action Weight Priorities

Static priority values come from `data/tasks/task_config.json`. Player overrides
through a Labor window remain planned.

| Task Type | Default Priority | Rationale |
|---|---|---|
| `MINE` | 50 | Core progression, moderate urgency |
| `FELL_TREE` | 50 | Player-designated raw timber supply |
| `HARVEST_TREE` | 50 | Pick a standing juniper's seasonal berries |
| `CLEAR_BOULDER` | 50 | Clear a marked surface stone; modest rough-stone yield |
| `GATHER_SCREE` | 50 | Gather a walkable loose-stone clump; one rough stone |
| `CRAFT` | 46 | Worker bench/torch orders; after mining/felling, before placement/hauling |
| `FETCH_BUILD` | 45 | Install finished furniture |
| `UNINSTALL` | 40 | Pack marked furniture for storage |
| `HAUL` | 40 | Keeps workshops fed; slightly less urgent than mining |
| `FARM` | 35 | Seasonal; deprioritised when food stores are high |
| `BREW` | 30 | Comfort; deprioritised when drink stocks are sufficient |
| `BUILD` | 45 | Infrastructure investment |
| `IDLE` | 1 | Lowest — only taken when nothing else is available |
| `PATROL` | 60 | Safety; pre-empts most economic tasks |

Priority is **additive** — bonuses are applied based on colony state:

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
See [60 — Hauling worker selection](../00_dev_roadmap/60_hauling_worker_selection.md).

> **As implemented (doc 16 §2.4–2.6 — supersedes the original pure-polling engine).** The
> scheduler runs on **wake events** (task added, dwarf idle, zone destination changed, chunk
> dirtied near a blocked target), flushed at most once per frame; the `POLL_INTERVAL = 0.5 s`
> heartbeat survives as the safety net that catches `retry_at` expiries. Every wake is bounded
> by `scheduler_budget_usec` (1 ms) and `max_probes_per_wake` (8); the loop stops mid-scan and
> resumes from the per-type cursor on the next wake.

**2026-10-09 — proximity for adjacent surface work:** tree felling, stone/scree
collection, shrub harvesting/clearing/uprooting and decorative plant clearing
compare all eligible idle dwarves against valid adjacent work cells. Candidates
are ranked by Manhattan distance, then idle order, and checked with bounded route
probes. Failed sides/workers do not back off the job until alternatives have
been exhausted. Ranking is read-only; only the successful work side is handed
to the source before its normal reservation. Ranking and probing resume across
wakes, and idle membership/navigation changes invalidate stale comparisons.
See [81 — Surface worker selection](../00_dev_roadmap/81_surface_worker_selection.md).

Matching loop per wake for non-hauling work:

```
1. Order pending type buckets by (static + colony_bonus(type)) desc, type ID for ties
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
filter eligibility and safely release disallowed current jobs. See milestone 96.

Each `Task.Type` maps to a preferred dwarf skill. A dwarf without the preferred skill can still take the task at reduced efficiency (×0.7 speed multiplier).

| Task Type | Preferred Skill |
|---|---|
| MINE | `skill_mining` |
| HAUL | `skill_hauling` |
| FARM | `skill_farming` |
| BREW | `skill_brewing` |
| BUILD | `skill_building` |

## Signals

```gdscript
signal task_added(task: Task)
signal task_assigned(task: Task, dwarf_id: int)
signal task_released(task: Task, dwarf_id: int, reason: int)   # §2.8 release protocol
signal task_completed(task: Task)
signal task_failed(task: Task, reason: String)
signal task_unreachable(task: Task)
```

---

*Prev: [23_user_interface.md](../20_player_interface/23_user_interface.md) | Next: [32_navigation_3d.md](./32_navigation_3d.md)*
