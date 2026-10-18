# 215 — Shared hauling route searches

The player's newer October 17 quicksave has four awake dwarves with adequate
food, 25 loose units, and four storage zones with space and compatible filters.
It reproduces a further hauling stall after 213: sixteen storage leases each
spend a full planning quantum on the same difficult lower-level torch pickups.
Claims, pickups and deposits change the inventory revision and discard other
leases' accumulated route progress. The inspector reports Looking around while
these redundant searches delay assignments.

TaskManager now shares bounded, read-only pickup and delivery geometry between
leases with identical start, target and approach cells. Searches and their
planning quantum are shared, so another lease cannot spend a fresh full quantum
on a route that has already yielded. Finished proofs are reusable. Supply quotes,
filters, reservations, destination capacity and actual item ownership remain
separate and are checked through the existing assignment and executor paths.

Inventory and idle-pool changes rebuild pickup quotes while retaining routes
and deferred alternatives for unchanged worker positions. Movement re-ranks
without clearing other workers' searches. Terrain, occupancy and ladder
dependencies still invalidate stale geometry, including failed proofs when an
approach opens. Finite search-budget exhaustion stays unknown and retries after
the existing maximum backoff. Planning holds extend only while a worker's search
advances, so leisure movement cannot erase active progress.

The shared cache is bounded to 64 entries by `hauling.route_cache_entries`.
Eviction removes sharing, not a lease's own unfinished frontier; that frontier
can rejoin later. Scene/save restoration clears all shared state. The existing
1 ms scheduler budget, per-wake probe cap, carry capacity, needs, recreation,
permissions and job priorities are unchanged. No save migration is required.

## Validation

Both observations loaded an isolated copy of the current quicksave, waited for
normal loading to finish, and ran 90 seconds at normal speed with self-care
active. Neither observation pre-warmed routes with synchronous path checks.

| Observation | First assignment | Awake workers assigned | Stored units |
| --- | --- | --- | --- |
| Before | 27.35 s | 1 during the observation | 80 → 82 |
| After | 2.97 s | All 4 by 6.49 s | 80 → 94 |

The fixed run completed eight trips and assigned twelve, with all four awake
dwarves on another load at the end. All 105 units remained accounted for in every
sample; task lifecycle checks passed. Further goods were still being collected
when the observation ended. SHA-256 comparisons confirm the original quicksave,
autosave and both backups were untouched.

`HaulingSharedRoutesTest` covers sharing an unfinished frontier across inventory
changes, reusing successful proofs, blocking and reopening an approach, bounded
cache size, eviction without lost progress, and world-reset cleanup. Its real
four-worker/four-storage scenario includes two disconnected lower pickups,
normal idle behavior, ongoing claims and deliveries, and a one-probe/eight-node
budget. All eight reachable logs reach storage; the two lower logs remain intact.
The test also checks that all four workers receive work and claims remain valid.
Sharing only search state still delayed that fixture for 1,051 wakes; sharing
the planning quantum reduced it to 168, covered by a 256-wake bound.

Ten native source fixtures pass: shared routes, route fairness, hauling
selection, carrying capacity, storage filters, job planning, job lifecycle,
construction staging, placement/hauling priority and idle behavior. The extended
eviction check passes, and native editor import succeeds. The copied-save run
used the shared-search/quantum implementation; the final eviction safeguard was
additionally checked by the extended regression.

Evidence: [summary and native logs](concepts/idle_work_20261017/summary.json).
Restart Play and load the existing save. No Windows playtest/export was created.
