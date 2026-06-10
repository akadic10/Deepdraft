# 16 - First Dwarf Milestone (Agents, Navigation, Task System, Real Mining)

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = decided / ready to build</span> |
> <span style="color:#d29922;">Yellow = decision needed or tune-in-engine</span> |
> <span style="color:#f85149;">Red = explicitly out of scope for this milestone</span>

Status: plan, drafted 2026-06-10. Nothing implemented.

**Why this milestone:** everything shipped so far is a sandbox with no actors. Real mining
execution is the named blocker across the docs — X-Ray's interior tracker
(`11_slice_xray_plan.md` Phase X0 "build with mining execution"), the zone block-state split
(`43_mining_materials.md` backlog), fog-of-war (doc 06, needs sight sources), and the DEV
instant-mine button itself ("replaced by real mining execution later"). The dwarf GLB asset
rework (doc 15) is complete and unused. This milestone turns Deepdraft into a game: designate
a zone, watch dwarves walk there and dig it out for real.

Deliverable: **dwarves spawn, path, take MINE tasks from designated zones, mine blocks into
`WorldData`, and can be interrupted mid-task — with the scheduler architecturally incapable of
hanging a frame**, regardless of how many tasks are pending.

---

## 1. Where Deepdraft stands today (gap analysis)

| Piece | State today | Gap |
|---|---|---|
| Dwarf assets | All ~41 GLBs generated, torso-only contract verified (doc 15) | No `DwarfAgent`, no factory, no asset registry autoload |
| Dwarf generation data | `names.json` / `appearance.json` / `traits.json` complete | No generator code |
| Navigation | Spec only (`32_navigation_3d.md`) | No A* grid, no walkability source |
| Task system | Spec only (`31_task_system.md`) | No `TaskManager`, no `Task` class |
| Mining zones | `MiningDesignationController` — designation as renderer visual cuts; DEV instant-mine writes void where chunks exist | Zones never mutate `WorldData` through work; no destination/reserved split; no drops |
| Renderer exposure pipeline | `add_mined_blocks()` + unified exposure principle shipped (doc 11 SO-2b) | Already correct — real mining plugs straight in |
| Interruptions | Nothing | Dwarf state machine + task release protocol |

**This doc supersedes nothing.** Doc 31 remains the task-system spec; the architecture below
refines its storage and scheduling model for scale and adds the no-hang guarantees. Doc 31
gets a cross-reference note when this ships.

---

## 2. TASK ARCHITECTURE (the core design of this milestone)

### <span style="color:#3fb950;">2.0 Decisions recorded with Alen, 2026-06-10</span>

1. **Tasks are first-class entities**, owned by a `TaskManager` autoload — never stored on the
   dwarf. A dwarf holds only a *claim* (task id); the task holds the assignment.
2. **Dwarves are matched to tasks by an event-driven, time-budgeted scheduler.** The game must
   never hang or hitch because of pending tasks — not at 100 tasks, not at 10,000.
3. **Mid-task interruption is a day-one requirement**, not a later feature: attack, sleepiness,
   need resolution, player cancellation, and terrain invalidation all release a task back to
   the pool cleanly.

### 2.1 The scaling insight: task count is O(intents), not O(blocks)

The naive reading of doc 31 ("break orders into atomic Task objects") would turn one
40×8×4 mining zone into **1,280 pending MINE tasks**. Ten zones = 12,800 tasks, all needing
priority sorting and reachability checks. That is the architecture that hangs.

**Stonehearth's model instead (verified in doc 43 §Worker Assignment Flow): the zone is the
work *source*, not the work.** Adopt it:

- A mining zone posts **at most `MAX_WORKERS` (4) MINE tasks** — one per worker slot, each a
  *lease on the zone*, not on a block.
- A dwarf holding a zone lease pulls **one block at a time** from the zone's *destination set*
  (reachable, unreserved blocks), reserves it, mines it, releases the reservation, pulls the
  next. The atomic unit of work never exists as a queued Task object.
- When the zone empties, its leases complete and the zone entity is destroyed (existing flow).

Consequence: with 25 dwarves and heavy play, the pending pool holds **tens to low hundreds of
intent-sized tasks** (zone leases, future hauls, future workshop batches) — never thousands of
block-sized ones. Everything below is sized for "hundreds" with headroom, but the first line of
defence is that the count stays small by construction.

The same pattern generalises later: a workshop posts one BREW lease per idle station; a
stockpile system posts haul tasks per item-batch, not per item.

### 2.2 Task entity

```gdscript
# scripts/systems/Task.gd
class_name Task extends RefCounted

enum Type   { MINE, HAUL, FARM, BREW, BUILD, IDLE, PATROL }     # doc 31; SMELT/FORGE later (doc 44)
enum Status { PENDING, ASSIGNED, IN_PROGRESS, BLOCKED, COMPLETED, FAILED, CANCELLED }

var id:           int           # unique, auto-increment
var type:         Task.Type
var status:       Task.Status
var priority:     int           # STATIC base priority (doc 31 table); dynamic bonuses applied at match time
var target_pos:   Vector3i      # representative position (zone centroid for leases) — used for distance + reachability
var payload:      Dictionary    # type data; MINE lease: { "zone_id": int }
var assigned_to:  int           # dwarf id, or -1
var source_id:    int           # owning work source (zone id, workshop id), or -1
var created_at:   int           # Time.get_ticks_msec()
var retry_at:     int           # msec; BLOCKED tasks are invisible to the scheduler until then
var blocked_count: int          # consecutive blocked probes (drives backoff + task_unreachable signal)
```

Notes:

- `priority` stores only the **static** value. Colony-state bonuses (+20 BREW when ale < 10,
  etc.) are computed **once per scheduler wake, per type** — never written into tasks, so no
  re-sort storm when colony state changes.
- Tasks are `RefCounted`, owned exclusively by `TaskManager`'s tables. Nothing else holds a
  strong reference except the assigned dwarf's `current_task_id: int` (an id, not the object —
  lookups go through the manager, so a cancelled task can be freed safely).

### 2.3 Storage — TaskManager tables

```gdscript
# scripts/systems/TaskManager.gd (autoload, registered after WorldGenerator)

var _tasks: Dictionary = {}            # id -> Task                  (authoritative store)
var _pending: Dictionary = {}          # Task.Type -> Array[int]     (ids, sorted by static priority desc)
var _active: Dictionary = {}           # dwarf_id -> task_id
var _idle_dwarves: Array[int] = []     # event-maintained, never rebuilt by scanning
var _completed_log: Array = []         # ring buffer, last 200 (doc 31; feeds the future task log UI)
var _scan_cursor: Dictionary = {}      # Task.Type -> int            (resumable scan position, §2.5)
```

Why per-type sorted arrays and not one global heap:

- **Skill matching is per-type** (doc 31): a dwarf's compatible types are known up front, so
  the scheduler only touches the buckets that dwarf can take — a Brewer never pays for 80
  pending MINE leases.
- Insertion is binary search on static priority (doc 31's rule), O(log n) per insert into a
  small array. At hundreds of entries this is microseconds.
- Cross-type ordering (which bucket to scan first for a given dwarf) uses
  `static_bucket_priority + colony_bonus(type)` — at most 7 additions per wake, computed once.
- BLOCKED tasks stay in their bucket but are skipped while `now < retry_at` (no separate
  blocked queue to migrate between; one field check per scan step).

<span style="color:#d29922;">Alternative considered — binary min-heap keyed on effective
priority: rejected for v1. Dynamic colony bonuses would force re-heap on colony-state change,
and per-type filtering becomes awkward. Revisit only if profiling shows bucket scans hot,
which at O(intents) counts it will not be.</span>

### 2.4 The scheduler — event-driven with a heartbeat, never a frame scan

The scheduler runs on **wake events**, with a slow heartbeat as the safety net. It never
iterates all dwarves × all tasks per frame.

Wake events (each sets a dirty flag; flush happens at most once per frame in `_process`):

| Event | Source |
|---|---|
| `task_added` | any system posting work |
| dwarf became idle | task completed / failed / released / dwarf spawned |
| zone destination changed | mining zone recomputed reachable blocks |
| `retry_at` expiry | cheapest: caught by the heartbeat (no timer per task) |
| nav region changed near a BLOCKED target | `chunk_dirtied` → clear `retry_at` for tasks targeting that chunk (re-arm early) |
| heartbeat | every `POLL_INTERVAL = 0.5 s` regardless |

Matching loop per wake, for each idle dwarf (skill-match descending, doc 31):

```
1. Order this dwarf's compatible type buckets by (static + colony_bonus(type)) desc
2. Scan the top bucket from _scan_cursor[type]:
     skip if status != PENDING, or now < retry_at
     reachability probe (capped A*, §2.6) from dwarf to task.target_pos
     reachable  -> assign: status=ASSIGNED, _active[dwarf]=id, emit task_assigned; done for this dwarf
     unreachable-> blocked_count += 1; retry_at = now + backoff(blocked_count); continue
3. Budget exhausted mid-scan -> remember cursor, stop; the NEXT wake resumes where this one left off
4. No compatible reachable task -> dwarf stays idle (IDLE behaviour is the agent's, not a queued task)
```

`backoff(n) = min(2^n, 30) seconds` — an unreachable task costs the scheduler one capped probe,
then goes silent for exponentially longer. After `UNREACHABLE_SIGNAL_THRESHOLD = 3` consecutive
blocks, emit `task_unreachable(task)` (doc 31) so the UI can warn the player; the task keeps
retrying on its backoff schedule (terrain changes re-arm it early via the chunk hook).

### <span style="color:#3fb950;">2.5 No-hang guarantees (hard rules of this design)</span>

1. **Time budget per wake:** `SCHEDULER_BUDGET_USEC = 1000` (1 ms) measured with
   `Time.get_ticks_usec()`. The matching loop checks the budget between tasks and stops
   mid-scan, resuming from `_scan_cursor` on the next wake. A pathological pile of pending
   tasks degrades into *slower assignment latency*, never a longer frame.
2. **Probe cap per wake:** `MAX_PROBES_PER_WAKE = 8` reachability probes, whichever limit hits
   first. Probes are the only non-trivial cost in the loop.
3. **Each probe is itself capped:** 200-node A* expansion (doc 32). A capped failure counts as
   unreachable → backoff. No probe can run long.
4. **One flush per frame max** — wake events set a flag; `_process` flushes once (the
   `visible_volume_changed` pattern from doc 11 Phase 3, already proven).
5. **No per-frame scanning of anything.** Idle set, pending buckets, cursors are all
   incrementally maintained by events. The heartbeat exists only to catch `retry_at` expiries
   and belt-and-braces missed events.
6. **Assignment-latency watchdog (debug):** the overlay (`DebugLoadingOverlay`) gains a row —
   pending count, idle count, oldest-pending age, probes/sec, worst wake µs. If oldest-pending
   age grows while idle dwarves exist, the scheduler is misbehaving and the numbers say where.

Targets (validate in a release build, doc-07 lesson):

| Metric | Target |
|---|---|
| Worst scheduler wake | ≤ 1 ms (the budget), typical ≤ 0.2 ms |
| Assignment latency, normal load (≤ 50 pending, idle dwarf available) | ≤ 1 heartbeat (0.5 s) |
| Assignment latency, stress (500 synthetic pending tasks) | bounded, frame time unaffected |
| Frame cost with 25 dwarves idle + 200 pending unreachable tasks | no measurable spike (backoff silences them) |

### 2.6 Reachability probes & the nav grid contract

- Probe = A* from the dwarf's current cell toward `target_pos` with a 200-node expansion cap
  and early-out on reaching any cell adjacent to the target (zone leases use *any destination
  block adjacent cell*, see §2.7).
- <span style="color:#d29922;">Main thread for v1.</span> At ≤ 8 capped probes per wake this is
  well inside budget. If profiling ever disagrees, the probe is a pure function over chunk
  data — the proven `WorkerThreadPool` batch pattern (`_ovt_*`) applies. Do not pre-build the
  threaded version (doc 11 lesson: one variable at a time).
- Path cache keyed `(start_cell, goal_cell)`, TTL 5 s (doc 32); invalidated on `chunk_dirtied`
  overlap. Probe results are NOT cached beyond the task's backoff state — the backoff IS the
  negative-result cache.

### 2.7 Mining zone as work source — the block-state split lands here

`MiningZoneComponent` (new, owned by the designation controller's zone bookkeeping) finally
implements the doc-43 backlog split. Per zone:

```
region        — all designated blocks (existing)
completed     — mined blocks (mirrors renderer _mined_blocks for this zone)
destination   — blocks currently minable: in region, not completed, not reserved,
                AND adjacent to a reachable stand cell (recomputed on terrain change, lazily)
reserved      — Dictionary[Vector3i -> dwarf_id], at most one block per working dwarf
```

Worker loop for a dwarf holding a MINE lease on zone Z:

```
1. pull = nearest destination block to dwarf with a free adjacent stand cell
   none available -> lease completes early (other workers finish the zone) or zone empty -> zone destroyed
2. reserve block; path to stand cell                       (path fail -> unreserve, try next block, 3 fails -> release lease w/ backoff)
3. swing timer = base_time × hardness / mining skill speed (doc 43); durability counts down per swing (block_resources.json)
4. on zero: WorldData.set_block(pos, AIR) … bedrock guard y > 3 (Hard Rule 1, checked AGAIN here)
            renderer add_mined_blocks([pos])               (exposure pipeline — already shipped, SO-2b)
            zone: completed += pos, unreserve
            drops: spawn per block_resources.json          (v1: simple floating item node, no hauling yet)
            nav grid: invalidate affected cells
5. goto 1   (interruption can fire at any step — §2.8)
```

Destination recompute is **lazy and local**: triggered by blocks completing in that zone or
`chunk_dirtied` touching the zone's bounds, budgeted, never global.

### 2.8 Interruption & release protocol (attack, sleepy, anything)

The dwarf state machine (doc 41) owns *when* to interrupt; TaskManager owns *what happens to
the work*. The contract:

```gdscript
# Dwarf side — at any point in MOVING_TO_TASK or EXECUTING_TASK:
TaskManager.release(dwarf_id, reason)   # reason: NEED_INTERRUPT | COMBAT | PLAYER | PATH_INVALID | …

# Manager side:
#  - task.status = PENDING, assigned_to = -1, re-inserted at its bucket position (static priority unchanged)
#  - zone lease: the dwarf's reserved block is unreserved (returns to destination set);
#    zone-level progress (completed set) is NEVER lost
#  - partial swing progress on the current block: DISCARDED (block keeps full durability)
#  - dwarf enters _idle_dwarves only after its interrupt behaviour resolves (sleep finishes, combat ends)
```

<span style="color:#3fb950;">**Rule: releasing a task is always cheap and always legal.**</span>
No task type may be designed such that abandoning it mid-way corrupts state. (Future hauls:
a carried item is dropped at the dwarf's feet as a normal item entity — recorded now as the
pattern.)

Pre-emption (combat tasks at priority 85 interrupting economy work, doc 52) is *not* built in
this milestone, but the release path is exactly what it will call — nothing to redesign.

For v1 testing, two interrupt producers ship:

1. **Sleep-lite:** a single `sleep` stat draining per doc 41 (−0.003/s); below 0.25 the dwarf
   releases its task, plays a sleep state at its current position (no beds yet) for the
   required hours, then re-enters the idle pool. This is deliberately minimal — the full needs
   system (hunger/thirst/mood/thoughts) is its own later milestone.
2. **DEV interrupt button** on the dwarf inspect panel: force-release with reason PLAYER —
   instant, deterministic interruption testing without waiting for stats.

### 2.9 Signals

```gdscript
signal task_added(task: Task)
signal task_assigned(task: Task, dwarf_id: int)
signal task_released(task: Task, dwarf_id: int, reason: int)
signal task_completed(task: Task)
signal task_failed(task: Task, reason: String)
signal task_unreachable(task: Task)          # 3+ consecutive blocked probes (doc 31)
```

---

## 3. Milestone phases

### Phase 0 — Instrument first (doc-07 lesson)

Add the scheduler/agent rows to the debug overlay before any tuning: dwarf count, idle count,
pending per type, oldest-pending age, probes/sec, worst wake µs, nav cache hit rate. Add a DEV
"spawn N synthetic pending tasks" button to stress the no-hang budget from day one.

### Phase 1 — Dwarf spawning & visuals

- `DwarfAppearanceData` resource, `DwarfAssets` autoload (preloaded GLB tables),
  `DwarfFactory.build_dwarf()` — all code-sketched in doc 41b; implement as written.
- Procedural generation from `names.json` / `appearance.json` / `traits.json`: seeded from
  `world_seed + birth_index` (deterministic roster per world, doc 41). Trait slots per
  `generation_config`, exclusion groups enforced.
- `DwarfAgent` (CharacterBody3D, `scripts/entities/DwarfAgent.gd`): four-part mesh hierarchy,
  tint shader application, procedural hand/feet bob (transform offsets, no AnimationPlayer).
- Runtime tint shader (doc 41b colour strategy) — first use of a `tint` uniform material;
  world assets stay baked (doc 61).
- <span style="color:#3fb950;">**Spawn flow — Decided (Alen, 2026-06-10): the Settlement Flag,
  Stonehearth-embark style.**</span> The player places the flag; the starter dwarves arrive at
  it. This implements the *minimal slice* of `06_world_start_placement.md` (the flag as
  world-start anchor) — the bounded placement-preview world, fog gating, and post-flag
  handoff stay in doc 06's backlog.
  - Assets exist: `base:items:special:settlement_flag` (`resources.json`) +
    `assets/models/items/misc/settlement_flag.glb` (1-tile footprint, 3 blocks tall).
  - Placement tool: a simple click-to-place mode (dock entry or DEV button for now) reusing
    the designation raycast. Validity: standable surface block (solid top, 3-air clearance),
    not water, not bedrock-adjacent edge; invalid hover tints the ghost red (existing
    hover-outline language, doc 22).
  - On confirm: flag spawns as a placed entity (registers its 1×1 footprint in
    `PlacedEntityRegistry` — it is the registry's second customer after trees), the camera
    centers on it, and **5 starter dwarves spawn on nearby walkable cells** (nav-validated,
    expanding ring search from the flag).
  - The flag is the colony's future settlement anchor (doc 06): store it as
    `settlement_anchor: Vector3i` on a thin `SettlementState` (member of TaskManager or its
    own minimal autoload — <span style="color:#d29922;">decide at build, lean toward a field
    on TaskManager until a second consumer exists</span>).
  - One flag per world for now; re-placement and flag-as-item hauling are out of scope.
- Slice rule: dwarves obey the existing flora pattern — `visible = grid_y <= slice_y` via
  `SliceController.slice_changed` (doc 11 Phase 5 says this hook generalises; it does).

Acceptance: player places the flag on valid ground (invalid spots reject visibly); 5 visibly
distinct dwarves (name, skin, hair, beard, age) spawn around it, bobbing idle, correct
3.3-block height against terrain, hidden correctly by the slice; the flag blocks pathing
through its tile.

### Phase 2 — Navigation

- `NavGrid` — <span style="color:#3fb950;">**Decided (Alen, 2026-06-10): autoload.**</span>
  Pure simulation state (no render output), queried by TaskManager (autoload) and every
  spawned DwarfAgent — global access removes per-agent NodePath wiring. Follows the
  project's dividing line: simulation state = autoload, presentation = scene node. Load
  order: after `PlacedEntityRegistry` (walkability reads it), before `TaskManager`
  (probes need it).
- Walkability per doc 32: solid floor + 3 air above, step ±1, lazy per-chunk node build,
  cached, invalidated on `chunk_dirtied` and on mined blocks.
- Walkability reads `WorldData` runtime ids via `BlockRegistry.is_solid` — water is not solid,
  not walkable (already correct in the registry).
- Placed-entity obstacles (trees): <span style="color:#3fb950;">**Decided (Alen, 2026-06-10):
  dwarves walk around trees.** Build the thin `PlacedEntityRegistry` (doc 12/32 shape): an
  autoload holding `occupies(pos: Vector3i) -> bool` over registered footprints.
  `SurfaceFloraSpawner` registers each mature/ancient tree's trunk-footprint cells
  (footprint × footprint XZ at ground level, full `clearance_height` Y — mirrors the existing
  collision box) on spawn and unregisters on despawn/season-rebuild. Saplings register
  nothing (clutter, Hard Rule 5 spirit). Nav walkability checks
  `WorldData solid` **and** `not PlacedEntityRegistry.occupies()` per doc 32; nav cells
  covered by a registered footprint invalidate on register/unregister (emit through the same
  chunk-granular invalidation path as terrain edits).</span>
- A* per doc 32 cost table; diagonals stay disabled; 200-node capped probe variant shares the
  same code path.
- Movement: agent follows the path with simple per-cell lerp + the step-assist vertical
  interpolation; repath once on invalidation, then release (PATH_INVALID).

Acceptance: dwarves walk to clicked debug targets across terraces (step up/down), refuse
unreachable targets fast (capped probe), never enter water or 2-high gaps.

### Phase 3 — TaskManager + scheduler

Everything in §2. MINE leases + IDLE behaviour only; the enum carries the future types.
Stress test: 500 synthetic pending tasks + 25 dwarves → frame time flat, watchdog numbers
sane, assignments drain in priority order.

### Phase 4 — Real mining execution

- The §2.7 worker loop. `WorldData.set_block` void writes, renderer `add_mined_blocks`,
  durability swings, drops as inert item nodes (hauling is a later milestone).
- <span style="color:#3fb950;">**Drop visuals — Decided (Alen, 2026-06-10): real micro-voxel
  GLBs, generated 2026-06-10.** `tools/generate_ore_glbs.py` produces the full metal-ore drop
  set (`assets/models/items/ore/` — copper, tin, iron, silver, coal, gold — plus
  `stone/rough_stone`; a gold-nugget item was cut 2026-06-10, gold ore is enough):
  ONE shared rock shape with identical fleck patches, only fleck colours differing per
  ore (Stonehearth-style, per Alen's reference). The rock body is **Alen-authored**
  (Voxelator, 2026-06-10 — `tools/ore_base_shape.obj`, octahedrally symmetric, parsed and
  solid-filled by the generator). Paths match the existing
  `model` fields in `resources.json`. Item class: 8 vox/block, 0.125 baked into vertex
  positions (dwarf-generator convention), import Root Scale stays 1.0. Spec:
  `61_voxel_art_guide.md` §5.7. Gem, soil, stone, and flora drop models follow later with
  their own shapes via the same generator pattern.</span>
- The DEV instant-mine button **stays** (testing tool) but its semantics are now the same
  pipeline minus the dwarf (`43_mining_materials.md` §DEV note gets updated).
- Designation raycast/overlay behaviour unchanged — zones now also drive real work.
- <span style="color:#f85149;">Out of scope: collapse/support model (doc 43 §Collapse) — the
  support-score check is stubbed to always-safe; its own pass later.</span>
- <span style="color:#3fb950;">**X-Ray interior tracker (X0) — Decided (Alen, 2026-06-10):
  piggybacked here.** The mining loop runs the doc-11 X0 bookkeeping on every mined block:
  walk air upward from the mined position, capped at `INTERIOR_HEIGHT = 4` (one dig cell),
  add the column to a per-chunk interior set; block placement (future) subtracts and locally
  recomputes. Verification without a consumer: a debug-overlay row ("interior cells: N") —
  the count must grow with digging and match expectations on a known-size tunnel. X-Ray
  *rendering* (X1/X2) stays strictly out of scope; this is data-only, so the future X-Ray
  milestone never has to reopen the mining loop. Persistence note (doc 11 X0): the interior
  set is derivable from the mined set — the save system persists mined blocks only and
  rebuilds interiors on load.</span>

Acceptance: designate a 8×8×4 zone on a plateau → ≤4 dwarves walk over, dig it out block by
block over real time; cut floors/walls reveal exact colours (exposure principle already
handles it); zone window shows progress; zone auto-destroys; drops litter the pit.

### Phase 5 — Interruptions live

Sleep-lite + DEV interrupt (§2.8). Acceptance: interrupting a mining dwarf mid-swing releases
the lease, another idle dwarf picks it up within one heartbeat, the sleeping dwarf resumes
work after waking, no block is double-reserved, no progress is corrupted, repeated
interrupt-spam (button mashing) never errors or leaks tasks.

---

## 4. Hard rules honoured (checklist for review)

1. Bedrock Protocol — mining execution re-validates `y > 3` at the moment of the void write,
   independent of designation-time filters.
2. Namespaced IDs — drops resolve via `block_resources.json` keys; no runtime ints persisted.
3. 3-block clearance — nav uses logical height 3, never the 3.3 visual mesh (doc 41).
4. JSON vs GDScript — scheduler constants that designers may tune (`POLL_INTERVAL`, budgets,
   backoff curve, `MAX_WORKERS`) go to `data/tasks/task_config.json`, loaded by TaskManager
   (registry pattern); logic stays in code.
5. Scene decoupling — agents are spawned scenes; controller/manager references via `@export`
   paths or autoload access, signals for cross-system events.
6. Determinism — dwarf *generation* is seed-deterministic (doc 41). Scheduler/agent runtime
   behaviour is explicitly NOT required to be deterministic (frame-time dependent); recorded
   here so nobody chases replay determinism later.

---

## 5. Build order & file touch list

| Step | Files | Depends on |
|---|---|---|
| 0. Instrumentation rows + DEV stress button | `DebugLoadingOverlay.gd`, `DockUI.gd` | — |
| 1. Task entity + config | new `scripts/systems/Task.gd`, new `data/tasks/task_config.json` | — |
| 2a. Dwarf assets + factory + agent | new `scripts/entities/DwarfAgent.gd`, `scripts/entities/DwarfFactory.gd`, `scripts/registries/DwarfAssets.gd` (autoload), `scripts/entities/DwarfAppearanceData.gd`, tint shader | — |
| 2b. Settlement Flag placement + spawn | new `scripts/systems/FlagPlacementController.gd` (scene node; reuses the designation raycast pattern), `DockUI.gd`, `debug_world.tscn` | 2a, 3a |
| 3a. PlacedEntityRegistry | new `scripts/registries/PlacedEntityRegistry.gd` (autoload), `SurfaceFloraSpawner.gd` (register/unregister hooks) | — |
| 3b. NavGrid | new `scripts/systems/NavGrid.gd` (autoload) | 3a |
| 4. TaskManager + scheduler | new `scripts/systems/TaskManager.gd` (autoload, after WorldGenerator) | 1, 3 |
| 5. Zone work source (block-state split) | `MiningDesignationController.gd` + new `scripts/components/MiningZoneComponent.gd` | 4 |
| 6. Mining execution + drops | `DwarfAgent.gd`, `WorldData` (no change expected), renderer hook (exists) | 2, 3, 4, 5 |
| 7. Sleep-lite + interrupts | `DwarfAgent.gd`, `TaskManager.gd` | 6 |

`project.godot` `[autoload]` additions (order): `… WorldGenerator, PlacedEntityRegistry,
NavGrid, TaskManager, …` plus `DwarfAssets` (position flexible; before the main scene needs
it). Allowed per AGENT.md ownership rules.

Docs to update on completion: `31_task_system.md` (storage/scheduler refined → cross-ref this
doc), `43_mining_materials.md` (worker flow live, DEV-mine semantics, block-state split done),
`41_dwarf_agents.md` (implemented-state notes), `13_architecture.md` (new autoloads),
`AGENT.md` (autoload list in doc 13 reference; possible new Hard Rule: "releasing a task must
always be cheap and legal").

---

## 6. Build log

| Date | Steps | State |
|---|---|---|
| 2026-06-10 | 0 (overlay instrumentation), 1 (`Task.gd` + `task_config.json`), 2a (DwarfAssets, DwarfAppearanceData, DwarfFactory, DwarfAgent, DwarfDirector + DEV spawn window, dock `dwarves` entry, autoload, scene wiring) | **VERIFIED in-engine by Alen, 2026-06-10 — BANKED.** DEV spawn produces distinct, bobbing, slice-culled dwarves. |
| 2026-06-10 | 3a (`PlacedEntityRegistry` autoload — column-range occupancy, `occupies()`, `register_box`/`unregister`, `occupancy_changed`; flora spawner registers mature/ancient trunk footprints, unregisters on despawn), 2b (`FlagPlacementController` — height-field hover ray, green/red ghost, click-to-place, one per world; flag registers 1×1×3 occupancy; `DwarfDirector.spawn_squad_at` + `settlement_anchor` (interim home — migrate to TaskManager at step 4); dock `flag` entry) | **VERIFIED in-engine by Alen, 2026-06-10 — BANKED.** Ghost validity works (red on water); flag places; squad spawns at it. Deviations: camera does not auto-center on the flag (the player just clicked there — pointless pan); mining tool and flag tool are not yet mutually exclusive (both DEV-era; revisit if it bites). Note: editing `[autoload]` on disk while the editor is open leaves stale "identifier not declared" analyzer errors until **Project → Reload Current Project** — runtime is unaffected; remember this for every future autoload addition (NavGrid, TaskManager). |
| 2026-06-10 | 3b (`NavGrid` autoload — doc-32 A* with 3-air clearance + entity occupancy, ±1 step, cardinal-only, binary heap, per-chunk walkable cache invalidated by `chunk_dirtied`/`occupancy_changed`, path cache TTL 5 s with per-path chunk sets, capped `probe_reachable` for the scheduler; terrain source = WorldData where chunks exist else generated blocks — **known DEV wart:** DEV-instant-mined blocks in ungenerated chunks are invisible to nav until real mining writes through `WorldData.set_block`; `DwarfAgent.walk_to` + walking bob; DwarfDirector walk-test mode; overlay nav stats row) | **VERIFIED in-engine by Alen, 2026-06-10 — BANKED.** Iterations during verification: two GDScript-4.6 Variant-inference parse errors fixed (typed loop vars/consts — house rule going forward); **flat diagonals enabled** (Alen — cardinal-only L-routes read wrong; no corner cutting, vertical steps stay cardinal; octile heuristic; doc 32 updated); **string-pulling added** (Alen — grid-literal following zigzagged at non-45° bearings): agents walk straight at any angle toward the furthest same-level waypoint with a clear sampled line (`NavGrid.line_walkable_flat`, agent radius 0.3, rescans every 0.3 s), elevation steps stay waypoint-exact; **facing fixed** — dwarf part GLBs are authored face-on-+Z (not Godot's −Z forward), so the yaw math needed a 180° flip; turns are now smoothed (`lerp_angle`, ~0.1 s) instead of snapping. Visual-quality review (Alen): name tags now default OFF (DEV toggle added); remaining items — bigger heads, better hands/feet, basic clothes, distance-driven gait, slower walk — captured as the **doc 17 backlog** (`17_dwarf_visual_polish.md`), deliberately NOT blocking this milestone's critical path. |
| 2026-06-10 | 4 (`TaskManager` autoload — event-driven budgeted scheduler per §2: per-type sorted buckets, resumable cursors, per-wake time budget + probe cap, exponential backoff with `task_unreachable` at threshold, chunk-dirtied early re-arm gated behind a blocked-count fast path, release/complete/fail/cancel protocol, colony-bonus stub computed once per wake per type; `DwarfAgent` v1 generic executor — walk to target → 1 s work → complete, release on path failure; DEV buttons "+50 tasks here" and "stress +500 random"; settlement anchor migration to TaskManager deferred until a second consumer exists) | **VERIFIED in-engine by Alen, 2026-06-10 — BANKED.** Stress test passes: dwarves drain the reachable subset (their plateau), the steep-terrace majority correctly lands in backoff (terraces > 1 block are impassable by design until stairs/ramps/mining exist — doc 32), repeated +500 presses stay smooth and re-feed reachable work. Scheduler behaves exactly per §2.5: overload = latency, never frame time. |
| 2026-06-10 | 5 (`MiningZoneComponent` work source — the §2.7 region/completed/destination/reserved split; lease posting + top-up at `min(max_workers, unreserved remaining)`; `TaskManager` work-source registry (`register/get/unregister`, `cancel_source_tasks`) + PATH_INVALID releases now apply backoff; controller routes released/completed/failed/cancelled to the owning component; zero-lease zone revival on `chunk_dirtied` near a stalled zone), 6 (`DwarfAgent` zone-lease executor — pull → reserve → path to stand cell (on the block or laterally ±1) → swing timer (`base × hardness ÷ durability` per swing, `mining_config.json execution`) → `commit_mined`, partial swings discarded per §2.8, post-mine floor snap, work bob; `execute_zone_block_mined` pipeline: bedrock re-guard at the void write, **chunk materialisation from the generator before first write** (lazy WorldData chunks are all-void — writing blind would delete 4,095 neighbours; this also closes the 3b DEV nav wart), `WorldData.set_block` void, renderer `add_mined_blocks`, drops, X0; drops via new `ItemDropManager` scene node (owns `resources.json` per the registry pattern, GLB cache, inert nodes, slice-culled like dwarves); X0 `InteriorTracker` autoload (column rule capped at 4, per-chunk sets, 3×3×3 dirty, overlay row "mining: interior cells N / drops N"); DEV Mine rerouted through the same pipeline minus dwarf/drops) | **Implemented 2026-06-10 — NOT yet verified in-engine.** Verify per Phase 4 acceptance: designate 8×8×4 on a plateau → ≤4 dwarves dig it out, exact-colour reveal, zone window counts down, zone auto-destroys, drops litter the pit, interior counter matches volume. REMINDER: new autoload `InteriorTracker` → editor needs **Project → Reload Current Project** to clear stale analyzer errors. Known v1 limits, accepted: cross-zone revival only via the chunk-dirtied hook; drops are inert (hauling is a later milestone); excess leases self-correct by completing early; first write into an ungenerated chunk pays a one-time ~4k-call materialisation (thread only if it ever hitches). Step 7 (sleep-lite + DEV interrupt) not started. |
| 2026-06-10 | 5/6 fix pass (first in-engine session: zone on a high shelf wall showed no reaction — correct backoff behaviour, but it exposed three gaps): (1) **reachable-representative** — lease targets now prefer the zone's DESTINATION set; the raw top-center of a side dig is interior rock with no adjacent floor and probed unreachable forever; (2) lease targets re-point + re-arm (`retry_at = 0`) as mining opens new stand cells; (3) zone window now live-refreshes (0.5 s) with "Workers: N" and a "No worker can reach this zone — retrying." line when every lease sits in backoff (interim UX until toasts exist); plus `probe_node_cap` actually wired from `task_config.json` → `NavGrid.probe_reachable` (was documented but hardcoded — it bounds how far away dwarves notice work). | Implemented — verify together with the step 5/6 acceptance run. |
| 2026-06-10 | Mining reach (Alen, in-engine: dwarves could not work a wall block 2 above their floor — stand cells were limited to floor ±1): **vertical reach envelope** added to `MiningZoneComponent` — a dwarf beside a block can work it up to `reach_up_blocks` (5) above and `reach_down_blocks` (1) below their stand floor; data-driven in `mining_config.json execution.*`. Lease probe targets now aim at a destination block's STAND CELL (the probe's ±1 adjacency early-out is narrower than the reach envelope, so targeting the block itself would re-create the unreachable-probe bug at reach > 1). Swing pacing also retuned: `swing_base_time_s` 2.0 → 0.5 (rock 6 s → 1.5 s per block). | Implemented — verify with a wall-face dig: dwarves standing at the foot of a 5-high face should clear it without stairs. |
| 2026-06-10 | Probe horizon (Alen, in-engine: reachable zone ~60 blocks from the squad showed "no worker can reach — retrying" forever): `probe_node_cap` 200 → **1200** in `task_config.json` (200 expansions ≈ 30–40 blocks of seen path — every probe to a distant-but-reachable zone hit the cap, counted as unreachable, and backed off). Doc 32 probe note updated (cap is data-driven; latency/cost dial, never frame time — probes remain inside the wake budget, which stops mid-scan when exceeded). Worst case per probe at 1200 nodes is still well under a millisecond; the budget guard makes the number safe to tune freely. | Implemented — re-test the same zone; dwarves should engage within a heartbeat once a probe lands. |
| 2026-06-10 | Stale-lease-target fix (Alen, in-engine: a zone designated into rock that a LATER dig exposed never started — "no worker can reach"): the revival hook only watched zones with ZERO leases, so blocked leases kept probing the interior target computed at confirm time even after the face opened. `_on_world_chunk_dirtied` now refreshes EVERY intersecting zone without an assigned worker — destination recomputed, leases re-targeted to a live stand cell and re-armed, missing leases reposted (per-zone 250 ms throttle; actively-worked zones skip, they self-maintain). Zone window gains a **Faces: N** diagnostic (current destination size) — "Faces: 0" = nothing workable yet (sealed/unstandable), "Faces: >0 + retrying" = probe/path problem. | Implemented — verify: designate a sealed interior zone, then dig into it; dwarves should start within ~a heartbeat of the face opening. |
| 2026-06-10 | **Session close (Alen).** In-engine state at end of day: real mining WORKS — wall-face zones, top digs, and previously-sealed zones all engage after the day's three fixes (reachable-representative, probe cap 200→1200, stuck-zone lease re-targeting). Drops spawn and pile in the pit (rough stone visible in play). Formal Phase 4 acceptance run (8×8×4 plateau checklist) still to be banked next session. **Step 7 (sleep-lite + DEV interrupt) not started.** Pending on Alen's machine: delete stale `.git/index.lock`, then commit steps 0–4 and today's 5/6 work as separate commits. |

### Next session — logged 2026-06-10 (Alen's playtest notes)

1. **Reach-aware block selection (mining efficiency).** Dwarves mine a block, then walk to a
   new stand cell even when another reserved-able block was workable from where they already
   stand. Fix in `MiningZoneComponent.reserve_next`: prefer destination blocks workable from
   the dwarf's CURRENT cell before nearest-by-distance — a block is workable-from(cell) if
   `cell == block`, or laterally adjacent with `block.y - cell.y` inside the reach envelope
   (`[-reach_down, +reach_up]`). Sort key: (0 if workable-from-current else 1, distance).
   The agent already passes its current cell; zero new plumbing.
2. **Rough stone drop rate too high** — floods the future inventory. Tune
   `data/terrain/block_resources.json` rock bands: `chance` 0.50 → ~0.20–0.30 (designer
   call). Pure data. Revisit properly in the economy balance pass; today it is only visual
   clutter + future hauling load (stockpiles don't exist yet).
3. **Soil drop GLBs missing.** `light_soil`, `dark_soil`, `cave_soil` currently spawn the
   ItemDropManager fallback cube (warn-once per model in the log). Author the soil drop
   family per doc 61 §5.7's one-shape-per-family rule — "low mound" shape, own generator
   (`tools/generate_soil_glbs.py` following the ore-generator pattern), colour-coded per
   soil type, paths matching the `model` fields in `resources.json`.

---

## 7. Open decisions (resolve before or during build)

1. <span style="color:#3fb950;">~~Tree obstacles in nav v1~~ — **DECIDED (Alen, 2026-06-10): yes, dwarves walk around trees.** Thin `PlacedEntityRegistry` autoload; spec moved into Phase 2.</span>
2. <span style="color:#3fb950;">~~NavGrid as autoload vs scene node~~ — **DECIDED (Alen, 2026-06-10): autoload.** Simulation state, not presentation; spec in Phase 2.</span>
3. <span style="color:#3fb950;">~~X0 interior-column bookkeeping~~ — **DECIDED (Alen, 2026-06-10): piggybacked on Phase 4.** Data-only, debug-counter verified; spec in Phase 4.</span>
4. <span style="color:#3fb950;">~~Starter dwarf spawn~~ — **DECIDED (Alen, 2026-06-10): player places the Settlement Flag (Stonehearth embark), dwarves spawn at it.** Minimal slice of doc 06; spec in Phase 1. Existing flag asset + item entry are used.</span>
5. <span style="color:#3fb950;">~~Drop visuals~~ — **DECIDED (Alen, 2026-06-10): real micro-voxel GLBs, generated same day.** Shared rock shape, per-ore colour-coded flecks (`tools/generate_ore_glbs.py`); spec in Phase 4 + doc 61 §5.7.</span>

All five milestone decisions are now resolved. The plan is build-ready.

---

*Prev: [15_dwarf_asset_rework.md](./15_dwarf_asset_rework.md)*
