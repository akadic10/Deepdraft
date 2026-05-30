# 31 — Task System

## Overview

The Task System is a **global asynchronous job queue** that decouples player designations from dwarf agent execution. Players issue high-level orders (mine this zone, haul these goods); the Task System breaks them into atomic `Task` objects and assigns them to available dwarves.

## Task Object Schema

```gdscript
class_name Task extends RefCounted

enum Type { MINE, HAUL, FARM, BREW, BUILD, IDLE, PATROL }
enum Status { PENDING, ASSIGNED, IN_PROGRESS, COMPLETED, FAILED, CANCELLED }

var id:          int           # unique auto-incremented ID
var type:        Task.Type
var status:      Task.Status
var priority:    int           # 1 (lowest) – 100 (highest)
var target_pos:  Vector3i      # primary world block coordinate
var payload:     Dictionary    # type-specific data (item key, quantity, etc.)
var assigned_to: int           # DwarfAgent node ID, or -1 if unassigned
var created_at:  float         # Time.get_ticks_msec()
var deadline:    float         # 0 = no deadline
```

## Global Task Queue

`TaskManager` (Autoload) holds the authoritative queue:

```gdscript
var pending_queue:    Array[Task]   # unassigned tasks, sorted by priority desc
var active_tasks:     Dictionary    # { dwarf_id: Task }
var completed_log:    Array[Task]   # last 200 completed tasks (circular buffer)
```

> **Agent note:** `pending_queue` must remain sorted at all times. Insert new tasks using binary search on `priority` rather than appending and re-sorting each frame.

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

## Worker Slot Polling Engine

Every `POLL_INTERVAL` seconds (default: `0.5`), the polling engine runs:

```
1. Collect all idle dwarves (no active task assigned)
2. For each idle dwarf (sorted by skill match descending):
   a. Pop the highest-priority compatible task from pending_queue
   b. Check reachability: can the dwarf path to task.target_pos? (fast A* probe)
   c. If reachable → assign task, update active_tasks[dwarf.id]
   d. If unreachable → push task back with a BLOCKED flag; skip for this dwarf
3. Tasks with BLOCKED flag and no reachable worker after 3 consecutive polls → emit signal TaskManager.task_unreachable(task)
```

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
signal task_assigned(task: Task, dwarf_id: int)
signal task_completed(task: Task)
signal task_failed(task: Task, reason: String)
signal task_unreachable(task: Task)
```

---

*Prev: [23_user_interface.md](../20_player_interface/23_user_interface.md) | Next: [32_navigation_3d.md](./32_navigation_3d.md)*
