# 98 — Crafting worker selection

Implemented 2026-10-09 after the player showed Keltin crossing the map for Rough
Stone while Hilka stood beside it, awake and ready for work.

## Cause and rule

Earlier proximity fixes covered hauling, surface work and shrub Move handoffs.
CRAFT still used the ordinary per-worker idle queue. Its unassigned source gave
the scheduler a workbench position, so the first eligible Worker with a route to
that bench claimed the order and only then chose an ingredient. Neither the
nearby Worker nor the actual material pickup participated in that comparison.

Every Worker recipe now compares all eligible idle Workers at its first physical
ingredient. Starter tools begin with stone; timber-only recipes begin with an
allowed log. Manhattan distance to the pickup floor ranks candidates, with stable
idle-order ties. This is a proximity estimate with route validation, not a global
shortest-path optimization. Higher-priority work, current profession, permissions,
sleep and existing assignments still determine eligibility.

## Ownership and execution

- `TaskManager._try_assign_crafts` owns the resumable comparison. It shares the
  scheduler's time budget, node cap and per-wake probe allowance.
- `CraftingManager` obtains read-only quotes from `ItemDropManager` and
  `StockpileManager`. Loose and stored ingredients compete by distance. Quotes
  exclude claimed goods, disallowed wood and suspended storage.
- Navigation proves an accessible handling stand, then a reachable open edge of
  a free workbench. Bootstrap recipes use the pickup stand as their worksite.
  Multiple pickup sides and workbenches are alternative goals in bounded searches.
- A failed material location is excluded for that worker, then candidates are
  ranked again. Other workers and other material locations remain eligible.
  Backoff follows exhausted candidates, not one failed near worker.
- Only the selected `WorkerCraftOrder` claims goods and a bench. It receives the
  exact loose node or stored slot, plus the proven pickup/delivery stands. The
  executor does not repeat an unrestricted nearest-item lookup for that pickup.
- Stored quotes preview the existing withdrawal's physical spawn location,
  including container stands. Withdrawal rechecks availability and promised units.
- Idle-pool, work-policy, material, storage and workshop changes invalidate pending
  comparisons. Terrain and ladder invalidation includes completed pickup legs
  while delivery probes are pending. Cancellation and scene reset release query
  references; read-only queries never own physical goods.

A Worker keeps the current batch, including subsequent ingredient trips. A newly
idle dwarf does not steal active work. Completed batches return to the scheduler.
No save fields, global classes, autoloads or priority values changed.

## Regression evidence

`CraftingSelectionTest` first failed on the former implementation with Keltin
first in the idle queue and close to the bench, and Hilka next to the stone.
It passes with the fix and runs the winner through a complete real tool batch.
It also covers every Worker recipe, ground storage versus loose goods, container
withdrawal, Craft permission, sleep, priorities, stable ties, active-batch ownership,
blocked workers/piles, alternate workbenches, one-probe wakes, read-only budget
yields, changed goods, newly idle workers, cancellation and reset.

Related regression suites: StarterToolsTest, WorkerCraftingTest,
WorkerCraftingWoodTest, WorkerCraftingStumpTest, WorkerCraftingAudioTest,
HaulingSelectionTest, SurfaceWorkSelectionTest, ShrubMoveHandoffTest,
MinerProfessionTest and SaveManagerRoundTripTest.

Logs are in `tmp/crafting_selection_review/`, using isolated test user profiles.
Restart play mode to load the code; existing saves retain their normal data format.
