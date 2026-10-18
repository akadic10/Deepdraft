# 213 — Hauling route fairness

**Follow-up:** [215 — Shared hauling routes](215_shared_hauling_routes.md) fixes
the remaining duplicated-search and inventory-invalidation delays reproduced
with the player's newer, adequately fed colony. The observations below describe
the earlier save and the initial fairness change.

The player's 2026-10-17 quicksave reproduced four awake, idle dwarves and
16 waiting HAUL leases. All four storage zones had space, accepted the loose
goods and were reachable. There were 26 loose item piles. Direct route checks
reached the furniture, ore, soil, stone and logs, but the two closer loose
torches on lower levels exhausted the initial route-search allowance.

The scheduler previously finished one ranked worker/pickup search before
considering the next candidate. All storage leases selected the same difficult
pickup first. Hunger checks repeatedly changed the idle pool and reset those
searches, so reachable work never received an assignment. The unmodified copied
save stored no additional goods during a 60-second observation.

TaskManager now retains separate pickup/delivery search contexts for each
worker, start position and pickup cell. A searching candidate receives the
existing eight-slice planning quantum, then temporarily defers that pickup and
re-ranks workers against their next available goods. This also helps a lone
worker whose closest pickup has a difficult route. Once all alternatives have
had a turn, deferred pickups become eligible again and their retained searches
resume. Deferral is not an unreachable result. Completed pickup proofs are checked against
navigation dependencies before reuse; claims still happen only after both legs
are proven reachable.

Availability changes re-rank current workers without discarding unchanged route
searches. A new available worker still gets the normal proximity comparison.
Deferred pickups survive pool reordering along with their route frontiers,
instead of repeatedly restarting at the first. Changed starts, supplies and
navigation retain their existing invalidation rules. CPU/probe limits, carry
capacity, filters, priorities and personal needs are unchanged. No save format
or player-save edits are needed.

The save also contains no edible stored or loose food. Packed elderberry bushes
are planting goods, not edible portions. Food shortage and its normal work
interruptions are a separate gameplay condition.

## Validation

`HaulingRouteFairnessTest` creates two large disconnected levels with a nearby
lower pickup and a farther reachable load. It repeatedly changes worker
availability every three scheduler wakes, limits each wake to one probe and
verifies the helper receives and actually delivers the reachable item. The
other item remains intact, unfinished search frontiers survive, and task
ownership remains valid. A single-worker case verifies alternative selection
and delivery; a distant, reachable pickup with no alternatives verifies that
long searches resume across multiple planning quanta and eventually assign.

Nine native regression scripts pass: route fairness, hauling selection,
carrying capacity, storage filtering, job planning/lifecycle, crafting,
construction staging and placement/hauling priority. The
crafting fixture now initializes its waterline map as well as its heightmap,
matching final-terrain comparison requirements introduced in 212.

The copied player quicksave completed deliveries during a 120-second normal
simulation: stored goods increased from 62 to 67, all 89 goods remained accounted
for in every sample, and task lifecycle checks passed. Food/sleep behavior was
left active. SHA-256 checks confirm the original quicksave, autosave and both
backups are unchanged. The source project also imports successfully.

Copied player-save observations, final delivery/conservation results and native
test logs are recorded in
[hauling_save_20261017](concepts/hauling_save_20261017/summary.json).
Original saves remain untouched. Restart Play to load the scheduler change.
No Windows playtest/export was created.
