# 88 — Ladder routes and task reachability

The player reported that miners refused to climb two connected ladders, while
the DEV walk test could reach the plateau. After manually walking there, the
dwarves eventually began mining.

## Cause and correction

Task assignment treated its small reachability-probe limit as a failed route.
Ordinary walking used a larger search. The slower cost of climbing made A*
explore a wide area of lower ground before committing to a tall ladder route.
The reproduction required 2,231 expansions for a full path; the scheduler's
1,200-node probe returned false and backed off the mining lease.

NavGrid now exposes a resumable reachability search with three outcomes:
searching, reachable, and unreachable. TaskManager keeps the frontier across
wakes. Running out of the wake's time or node budget means searching, without
raising blocked counters or starting retry delays. Mining, ordinary fetch/build,
surface work, exact-plant Moves and hauling use this shared gate.

The existing 1 ms scheduler budget, per-wake probe limit and 1,200-node slice
remain unchanged. The forward search can reach the ordinary walking limit of
6,000 expansions, spread across frames. A preliminary reverse search of at most
64 nodes quickly rejects a sealed destination pocket; closing ladder routes
skip that optimization so their directional access restrictions remain intact.
Only an exhausted frontier or full forward limit produces failure/backoff.

Queries record the chunks examined, including rejected neighbours and body
clearance. Relevant terrain/occupancy changes invalidate the search; edits or
streaming elsewhere preserve its progress. Ladder changes restart searches and
wake blocked tasks. Scheduler state is transient and resets during loading.
Normal walkability, three-block clearance, mining reach and paid ladder sections
remain the movement authorities. Dwarves climb the route physically.

## Verification

`LadderMiningTest.gd` reproduces a wide plateau, two offset sixteen-block ladders,
and a 48-block mining zone. It checks:

- The legacy short probe fails while the full walk succeeds.
- Automatic assignment, climbing, mining animation and actual block removal,
  with the dev path cache cleared and no manual walk command.
- Tiny node slices and expired deadlines preserve pending search state without
  marking the zone blocked.
- A missing upper ladder rejects the route; completing it wakes mining at once.
- Terrain and placed occupancy invalidate route proofs; unrelated terrain edits
  preserve pending search progress.
- The complete search stays bounded.

Native captures: `tmp/ladder_mining_review/automatic_climb.png` and
`automatic_mining.png`. Logs are in the same folder. Related checks cover mining
animation/feedback, surface and haul worker selection, shrub Move handoff,
physical hauling, ladder construction/removal, placement-over-hauling and full
save/load/backup recovery.

Manual check: designate mining on a ledge reachable only by completed ladders.
Leave the dwarves below. They should claim the work, climb, and mine without
using DEV Walk. An unfinished route should remain unavailable until connected.

## Follow-up — isolated cliff shelves (2026-10-09)

The next player test still failed. The initial wide-plateau fixture covered the
search budget but omitted natural cliff shelves. A separate copy of the player's
autosave reproduced the second cause: seed `3912970522`, completed ladder at
`(415,35,575)` rising eight blocks, and 32 mining blocks at X419–422,
Z576–583, Y43. From `(410,35,570)`, the old nearest stand `(419,39,575)` was
walkable but disconnected. The upper stand `(418,43,576)` was reachable through
the ladder in 208 expansions. Rejecting the nearest shelf rejected the entire
zone; moving workers upstairs changed the nearest stand and hid the problem.

Mining now supplies every distinct valid work position to one resumable search.
Success requires reaching an exact work position, with the normal mining reach
and clearance rules. A bounding-box distance supplies a constant-cost
heuristic; cells inside the box are not automatically accepted. All alternatives
share the existing 6,000-node forward bound and 64-node destination preflight.
This also avoids repeating an exhausted search separately for every block in
a genuinely disconnected zone.

The successful block, stand and route pass directly to the chosen worker.
The source revalidates the reservation, and the worker reuses the exact proved
route instead of selecting the unreachable shelf again. These hints are transient;
cancellation and release discard them, and terrain changes invalidate the proof.

`MiningLedgeAccessTest.gd` regenerates that seed without reading player saves,
restores the real ladder through its owner, and starts five workers below the
cliff. It verifies the isolated nearest shelf, alternate exact goals, shared
search bounds, small slices without false backoff, route handoff and completion
of all 32 mining blocks. Native capture:
`tmp/ladder_mining_live/seeded_mining.png`. The original two-ladder test retains
its missing-ladder backoff and terrain/occupancy invalidation checks.

**Player confirmation, 2026-10-09:** following the section-height correction in
[86](86_rudimentary_ladders.md), the player reported working ladder access and a
successfully mined staircase. This closes the reported ladder/mining workflow
for this session. The older mining-face stall in Issue 001 has not been reproduced
against these fixes and remains open; see [89 — Handoff](89_session_handoff_2026_10_09.md).
