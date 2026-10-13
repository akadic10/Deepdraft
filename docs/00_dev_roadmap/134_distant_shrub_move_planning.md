# 134 — Distant shrub Move planning

2026-10-12. The player's seed 16155431 save contained five strawberry Moves:
one already packed plant near camp and four bushes roughly 150–180 blocks away.
The distant bushes remained marked for uprooting while available dwarves idled.

## Cause and correction

All four bushes had legal routes. Their searches needed roughly 700–2,700 node
expansions, spread across the scheduler's bounded wakes and competing orders.
The four-second planning hold expired before some searches finished. Leisure
then moved the selected dwarf, invalidating the search start and discarding its
frontier. Repeated wandering prevented assignment despite available workers.

`TaskManager._advance_worker_probe()` renews an existing leisure hold when a
surface-work or exact-item Move search actually expands more nodes. A finished,
cancelled or inactive search stops renewing it. The ordinary expiry/cooldown,
per-wake time/probe caps and total search allowance remain in force. Sleep,
food, external movement and higher-priority assignments keep their usual rules.

Surface assignment now proves the exact adjacent work stand, rather than a cell
next to that stand. Navigation caches that proof for the worker's execution,
avoiding a redundant full search and a mismatch between assignment and approach.
Pickup and delivery searches for exact plant/furniture Moves share the hold
renewal. No work costs, speeds, yields, cargo ownership or save fields changed.

## Verification

`ShrubMoveHandoffTest` now runs a distant uproot/carry/replant sequence at ×3 with
real leisure and supervision ticking. One-node, one-probe slices deliberately make
both outward and return planning exceed the initial hold. It checks completion,
exact plant identity, no duplicate cargo, lifecycle consistency and expiry after
planning stops. Existing cases cover priority, sleeping workers, cancellation,
interruption and inaccessible pickup/destination alternatives.

The player-save investigation uses an isolated copy under
`tmp/berry_move_20261012/`. The original save is never rewritten. This archived
save predates milestone 133's flag schema, so only the investigation copy maps
its founding flag to the current furniture representation before loading; this
is not a production compatibility path.

All 31 fixtures in `tools/run_job_reliability.ps1` pass, including current
save/load and backup recovery. The final copied-save replay at ×1 completes all
five exact-identity Moves in 184.736 seconds, with no orphan work or reservations
and no script errors (`complete_probe.out`). The player's original quicksave
still matches the archived original's SHA-256. `compatible_quicksave.json` is
the starting save with only the flag representation updated, available for
resuming that world; it does not include the test's simulated progress.
