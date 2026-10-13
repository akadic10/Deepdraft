# 126 — Shared job lifecycle and recovery

**Implemented 2026-10-11**, following the four steps in
[125 — Jobs and dwarves architecture review](125_jobs_and_dwarves_architecture_review.md).

The scheduler now distinguishes a persistent player order from each temporary
worker attempt. It explains waiting work, checks meaningful progress, safely
releases stalled attempts and gives competing searches planning time. A blocked
route still requires a feasible route; recovery never invents supplies, teleports
a dwarf or calls an unfinished order complete.

## 1. Order and attempt diagnostics

- `WorkSourceAdapter` derives order locators from saved source IDs, with stable
  coordinates for coordinate-owned sources. A ladder retains one order identity
  as its paid sections advance. Craft orders now save their IDs.
- `WorkJournal` assigns stable order keys and monotonic attempt generations.
  Its global transition ring holds at most 200 events; retired diagnostic records
  are bounded too. Active paths and claims are not part of this journal.
- `WorkAttempt` records the current phase/work unit, time since useful progress
  and a phase deadline. Moving closer, finishing handling and increasing actual
  source work count as progress. Merely running `_process` does not.
- Worker diagnostics distinguish work, self-care, access recovery and lack of
  navigable footing. The bounded reconciliation pass repairs missed idle
  notifications and cleans up orphan executors.

Open **Dwarf development → DEV: Job inspector** for live orders, waiting reasons,
active worker/attempt/phase, progress age, rejected-worker count and recent
transitions. **Retry selected order** clears an inactive order's planning/backoff
state and reassesses the real world. It does not bypass validation or finish work.
The panel is a development tool, refreshed only while visible.

## 2. Furniture and access construction pilot

`FurnitureFetchPlanner` makes read-only supply quotes, then proves worker → pickup
stand → work stand before physical reservation. It tries alternative items and
all legal approaches instead of trusting the nearest cell. The selected material,
exact-instance promise, pickup and delivery stand pass to the source. Reservation
and physical transfer validate them again.

Ladder builders work from the current paid rung; bridge builders can use either
legal bank. Source owners still control paid sections, completed decks and safe
departure. Ordinary furniture still commits during its set-down animation.

All dwarf work mutations pass an attempt/task/worker fence. `commit_step` marks a
unit as committing **before** calling the world owner, so duplicate or reentrant
callbacks cannot repeat its effects. A rejected validation releases that receipt.
Old-generation completions cannot finish a newer assignment.

These receipts are **runtime, per-attempt guards**, not a persistent transaction
log. The source's physical checkpoint is authoritative between attempts: mined
blocks, staged ingredients, installed furniture and paid ladder sections. Commits
are synchronous in the game process; current save/load reconstructs attempts
from source and inventory state. This is deliberately smaller than Temporal's
durable event replay. Crash durability remains the last successful game save.

The supervisor runs on simulation time, honors pause/loading and examines a
bounded subset of active attempts. A stalled attempt uses normal abort/release:
real cargo returns intact, source claims are released and work is replanned.
Three supervised failures without a successful commit put the order in **Needs
attention**, with a visible reason and explicit retry. It does not automatically
quarantine every ordinary route change or resource race.

## 3. Shared execution and fair planning

`DwarfWorkExecution` owns attempt identity, timed work dispatch and progress
sampling. `DwarfAgent` retains locomotion, support, rest, presentation and the
family-specific physical handling helpers. Existing source owners remain the
authorities for inventory and partial work; there is no parallel inventory.

Hauling, crafting, mining, surface work and uninstall use the same fencing and
supervision contract. Their specialized selection rules remain:

- Hauling proves pickup access and a route from the pickup to storage. Container
  delivery considers its walkable perimeter. Opportunistic bundle extras still
  validate access individually during execution and can be skipped safely.
- Crafting proves both legs for the first **and later** ingredients. A bounded
  continuation planner retains the batch's staged goods and bench. Interrupting
  that planner returns goods through the normal source cancellation path.
- Mining preserves multi-goal exact working-position searches; surface work
  preserves its valid stands and source-owned work. Uninstall revalidates its
  source at commit.
- An expensive search yields across job types and, after a configurable quantum,
  within its family. Frontiers survive the yield. Ordinary searches retain
  separate worker/order contexts; specialized searches retain order contexts.
- Relevant nav-chunk dependencies, ladder revision and supply revisions invalidate
  plans. Unrelated terrain edits no longer discard all rejected-worker evidence.
- A short planning hold limits idle wandering from repeatedly moving the search
  start. It expires and has a cooldown; sleep, legitimate work, private-room exits
  and developer walk commands keep their own rules.
  [Milestone 134](134_distant_shrub_move_planning.md) renews this hold while a
  surface-work or exact-item Move search expands nodes, so distant routes can
  finish without leisure repeatedly invalidating their start. Inactive searches
  stop renewing it; per-wake and total search limits still apply.
- Exhausting a finite A* allowance means **reachability unknown**, distinct from
  a completed search proving no route. Searches can expand their total allowance
  from 6,000 to 12,000 to 24,000 nodes while retaining their frontier and the normal
  per-wake budget. At the maximum they yield to backoff/other work with an honest
  diagnostic rather than marking an order complete or permanently unreachable.

Construction changes wake route assessment. There is no inferred prerequisite
graph or automatic creation of ladders/bridges: blocked mining waits and existing
access orders receive fair planning time.

### Configuration and timing

`TaskManager` remains the sole owner of `data/tasks/task_config.json`; other
components use its accessor. Defaults:

| Setting | Default |
|---|---:|
| Scheduler cooperative time budget / probes per wake | 1,000 µs / 8 |
| Supervisor interval / cooperative budget / attempts per pass | 0.5 simulated seconds / 500 µs / 8 |
| No useful progress tolerance | 12 simulated seconds |
| Phase deadline | expected duration × 2 + tolerance |
| Supervised failures before attention | 3 |
| Planning hold / cooldown | 4 / 2 simulated seconds |
| Same-family planning quantum | 8 yielded slices |
| Maximum search allowance | 24,000 nodes |
| Later-ingredient planner budget / expansion slice | 250 µs / 32 nodes per active planning tick |

Budgets are cooperative: a single bounded query/operation can cross the deadline.
They are not strict real-time guarantees, and per-worker ingredient planning adds
up with active crafters. Existing scheduler retry timestamps/backoff still use
wall-clock milliseconds; work deadlines, handling and planning holds use simulated
time. Pausing prevents execution/supervision even if a retry becomes due.

## 4. Regression gate and evidence

Run the tracked gate from PowerShell, using the local Godot executable:

```powershell
./tools/run_job_reliability.ps1 -Godot 'path/to/godot.exe'
```

It runs 23 fixtures sequentially with bounded process timeouts, requires a success
marker and exit zero, rejects runtime script errors, and writes individual logs
plus `results.json`. `-Tests` accepts a smaller fixture list; `-LogDirectory` selects
an output directory. It does not load or overwrite the player's quicksave.

| New coverage | Assertions |
|---|---|
| `JobLifecycleTest` | Freeze real furniture at pickup, transit and set-down; preserve cargo/material; pause-safe supervision; new generations; stale/duplicate/reentrant callbacks; attention/retry; saved order identity; bounded journal; real inspector data. |
| `JobPlanningTest` | Inaccessible nearest supply with a usable alternative; unknown versus failed route searches; retained frontier/escalation; relevant versus unrelated invalidation; same-family fairness; later craft ingredient alternatives. |
| `JobMixedWorldTest` | Four actual workers; seven injected family stalls (haul, felling, ladder, furniture, craft, uninstall, mining); real leisure, sleep and water obstruction; continuous worker/source/lease ownership checks and eventual completion. |
| `SavedLadderJobTest` | Archived player colony's partial ladder advances 4 → 8 → 12; exactly two stored pine kits consumed and three paid sections retain pine identity. |

The gate also covers existing placement/animation, ladder/mining, material
crafting, hauling, surface selection, shrub Move, support, idle, bridge corner,
navigation and full save/load fixtures. The save test still compares physical
owner state; diagnostic phase/timestamp transitions are deliberately revalidated
on load, while stable order identity is checked.

The saved-colony fixture is optional because it needs an external archived save:

```powershell
& 'path/to/godot.exe' --headless --path . --script res://scripts/tests/SavedLadderJobTest.gd -- --save=path/to/archived.json
```

It adapts missing diagnostic fields **inside the isolated fixture** and loads
through a dedicated test slot. Production has no legacy migration. The original
player quicksave remains unchanged. Current saves include the `jobs` section and
craft order IDs; older development saves may fail validation under the existing
development-save policy.

Final results and exact run locations are recorded in the session handoff.
Native inspector rendering was checked at 1280×720; its labels, list selection,
detail panel and retry control are readable and within the window.

## Boundaries and remaining playtests

This makes stalls observable and gives failed attempts a common recovery path.
It does not establish that every possible world/order combination can complete.
Continue player testing of large colonies, many simultaneous crafters, changing
water/access and long-running orders. **2026-10-12 disposition:** Alen considers
[issue 001](00_open_issues.md) resolved after these changes; it is provisionally
closed without a confirmed original cause and will reopen only if reported again.
Alen also provisionally closed issue 002 on the same date, with no further
investigation unless the player reports it again. Its original cause remains unconfirmed.
