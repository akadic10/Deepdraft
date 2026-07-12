# 31 — Task System

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
> `max_haulers` HAUL leases; the `DwarfAgent` executor pulls pouch BUNDLES (up to 4 items per
> trip, SH backpack parity) from `ItemDropManager`'s loose-item index, with owner-guarded item
> reservations and the §2.8 release protocol (any interrupt drops the whole pouch at the
> dwarf's feet as loose items). Stockpile source ids live at `1_000_000 + zone_id`
> (`StockpileManager`); hauling tunables in `task_config.json` `hauling`. Workshops are next.

## Overview

The Task System is a **global asynchronous job queue** that decouples player designations from dwarf agent execution. Players issue high-level orders (mine this zone, haul these goods); the Task System assigns work to available dwarves. Orders are represented as **intent-sized tasks** (zone leases, future item-batch hauls) — the atomic block-level unit of work never exists as a queued Task object (doc 16 §2.1).

## Task Object Schema

```gdscript
# scripts/systems/Task.gd — as shipped (doc 16 §2.2)
class_name Task extends RefCounted

enum Type   { MINE, HAUL, FARM, BREW, BUILD, IDLE, PATROL }   # SMELT/FORGE later (doc 44)
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

Default priority values — these may be overridden by the player via the Labor window.

| Task Type | Default Priority | Rationale |
|---|---|---|
| `MINE` | 50 | Core progression, moderate urgency |
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

> **As implemented (doc 16 §2.4–2.6 — supersedes the original pure-polling engine).** The
> scheduler runs on **wake events** (task added, dwarf idle, zone destination changed, chunk
> dirtied near a blocked target), flushed at most once per frame; the `POLL_INTERVAL = 0.5 s`
> heartbeat survives as the safety net that catches `retry_at` expiries. Every wake is bounded
> by `scheduler_budget_usec` (1 ms) and `max_probes_per_wake` (8); the loop stops mid-scan and
> resumes from the per-type cursor on the next wake.

Matching loop per wake, for each idle dwarf (skill match descending):

```
1. Order the dwarf's compatible type buckets by (static + colony_bonus(type)) desc
2. Scan the top bucket from _scan_cursor[type]:
     skip if status != PENDING, or now < retry_at
     reachability probe (capped A*, node cap from task_config.json — default 1200)
     reachable   → assign; done for this dwarf
     unreachable → blocked_count += 1; retry_at = now + backoff(blocked_count); continue
3. Budget exhausted mid-scan → remember cursor, stop; next wake resumes there
4. No compatible reachable task → dwarf stays idle (IDLE is agent behaviour, not a queued task)
```

`backoff(n) = min(2^n, 30)` seconds. After 3 consecutive blocked probes → `task_unreachable(task)` fires for the UI; the task keeps retrying on its backoff schedule, re-armed early when `chunk_dirtied` touches terrain near its target.

### Skill Compatibility

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
