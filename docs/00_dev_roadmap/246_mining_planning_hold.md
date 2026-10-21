# 246 — Mining planning holds and retired furniture fixtures

The project review found three fixtures using retired furniture and a separate
mixed-job mining stall. The fixtures now use current definitions:

- `FurnitureMoveTest` uses the log torch and the existing synthetic storage
  fixture, retaining container filters, physical contents and exact-piece moves.
- `WallMountHeightTest` uses the log torch for height, access and serialization
  checks. Real worker installation and removal now run in all four orientations.
- `DwarfIdleBehaviorTest` uses the log stool and the current 3×3 log dining table,
  positioned at the stool's north seating guide. Its inherited idle-planning
  fixture also uses the current stool.

## Mining stall

`JobMixedWorldTest` combines four workers, unfinished ladder access, mining,
placement, uninstall, crafting, hauling and tree felling. It uses five-node route
slices, a two-probe wake limit, live leisure, sleep, water edits and stalled-worker
recovery. Before the correction, all work except mining completed; mining stayed
pending after 500 simulated seconds, with no assigned or blocked worker.

A diagnostic subclass recorded repeated changes to the pending mining routes'
starting cells, discarding hundreds of expanded nodes. Mining used the initial
four-second leisure hold but omitted the progress-based renewal already used by
pickup/delivery planning. When the hold expired, dwarves strolled and invalidated
their unfinished routes, even after ladder access was complete.

`TaskManager` now shares that renewal helper with mining. It extends an existing
hold only when an unfinished search expands more nodes. Completed searches and
checks without route progress do not renew it. Search budgets, scheduling quanta,
priority, navigation invalidation and exact mining-stand validation are unchanged.

## Validation

The three repaired fixtures and `DwarfIdlePlanningTest` pass before the scheduler
change. After the change, the original mixed-job fixture completes in 198.3
simulated seconds, reaches all seven fault-injected executors and passes 1,983
ownership checks with no pending or active tasks. Job planning, idle planning,
hauling route fairness and shared hauling route fixtures also pass.

The full default reliability gate passes **38/38**, including the three repaired
fixtures, ladder/mining, crafting, hauling, personal needs, construction and save
round-trip/recovery. Its mixed-job run again completes at 198.3 simulated seconds.
The two additional hauling route fixtures pass separately. Original quicksave,
autosave and both backup files retain their SHA-256 hashes.

`DwarfIdlePlanningTest` is now included in the default reliability gate to guard
the complementary requirement: unsuccessful planning checks must still permit
leisure, preserve seated dwarves and yield immediately to a real assignment.

Evidence and task-start source backups are under
`tmp/mining_stall_fix_20261019/`. Validation uses isolated application-data
directories. This is a native headless regression check, not a fresh graphical
playtest or a claim that every settlement scheduling issue is resolved.
