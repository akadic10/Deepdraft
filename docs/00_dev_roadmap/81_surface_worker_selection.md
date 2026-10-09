# 81 — Nearby workers for surface jobs

2026-10-09. Fix for a distant idle dwarf walking to uproot a blueberry bush
while another available dwarf stood on it.

## Cause and behavior

Milestone 60 made HAUL compare available workers at the pickup. Tree and surface
jobs still accepted the first reachable dwarf in idle-queue order. A nearer
dwarf later in that queue never got considered. The new regression reproduced
this for uprooting, harvesting and clearing before the fix.

New FELL_TREE, CLEAR_BOULDER, GATHER_SCREE, HARVEST_SHRUB, CLEAR_SHRUB,
CLEAR_PLANT and UPROOT_SHRUB assignments compare every eligible idle worker with
the source's valid adjacent work cells. Manhattan distance ranks worker/stand
pairs, with idle order breaking distance ties. A dwarf standing on a walkable
shrub can take the one-step route to its side. Failed probes try other sides and
workers; task backoff happens only after those alternatives are exhausted.

Priority buckets are visited before choosing workers. Higher-priority work
still comes first, sleeping/unavailable workers are excluded, and existing
assignments are not transferred when a nearer worker later becomes free.
HAUL retains its pickup/delivery comparison. Other source families retain their
existing per-worker probe contracts; this is not a global shortest-route or
whole-colony task-allocation optimizer. In particular, FETCH_BUILD remains the
separate pickup/carry/replant stage of a shrub Move. Its remaining worker handoff
gap was subsequently corrected in [82 — Shrub Move handoff](82_shrub_move_handoff.md).

## Implementation boundaries

- `TaskManager` keeps one transient surface comparison with resumable ranking
  and probe cursors. Its existing time and probe budgets still apply. Pending
  tasks remain intent-sized leases in priority buckets; there is no frame scan
  of world objects or global path-distance matrix.
- `TreeFellingComponent.stand_cells()` provides read-only quotes. Ranking does
  not mutate the source's rotating retry cursor or reserve work. Only the chosen
  reachable side is passed to `prefer_work_stand()` before normal execution.
- Idle membership changes invalidate comparisons, including assignment,
  unavailability and deregistration. Navigation changes clear route candidates.
  Cancellation is rechecked before assignment; scene reset clears the cache.
- No task priorities, work durations, yields, persistent state formats, new
  autoloads or global classes were added.

## Verification

`scripts/tests/SurfaceWorkSelectionTest.gd` uses real dwarves, the scheduler,
plant owner, work components and world navigation. It covers:

1. An older distant idle dwarf losing to the worker on the shrub for uproot,
   harvest and clear, including real execution and the resulting plant/items.
2. Sleeping and busy workers, higher-priority work, stable equal-distance ties,
   and preserving an assignment when a closer worker arrives later.
3. Blocked nearby workers, blocked nearest work sides, all routes blocked,
   backoff and terrain reopening, with only one probe allowed per wake.
4. Forced budget yields without reservations, workers becoming available or
   unavailable mid-comparison, cancellation and scene reset.
5. Nearby selection for boulders, scree, flowers and reeds.

Existing HaulingSelectionTest, ShrubTransplantTest, ShrubCuttingTest,
WorkerCraftingTest, MiningAnimationTest and TreeFellingTest pass. Evidence is in
`tmp/worker_selection_review/`; `before.log` records the reproduced failures.

For manual confirmation, restart the running game, leave several dwarves idle,
and order harvesting, uprooting or clearing beside one of them. The closest
eligible worker to a reachable work side should start. A busy or sleeping dwarf
is correctly skipped. Repeat with a stone or tree to check the shared behavior.
