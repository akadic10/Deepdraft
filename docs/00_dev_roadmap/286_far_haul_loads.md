# 286 — Hauling loads behind a long detour

2026-10-30. Built. The owner's look in game is next.

From the owner, with a screenshot of their latest quick save: dwarves say they are ready
to work but are not hauling the loose lumber to storage.

## What happened

The quick save (Oststadt, day 1, 20:22) has five Workers by the stockpile and 24 logs and
seeds on the shelf above it, 12 blocks up. The only way up is the stairs at the shelf's far
end, so every route walks round, climbs and walks back (50–80 steps).

- **Nothing was broken, only slow.** The scheduler never gave up on the logs, but at the
  game's 60 fps the first shelf load was assigned 75 seconds after loading. All that time the
  idle dwarves stood under a planning hold, which the panel shows as Ready for work. The
  save's own job journal shows the same wait before it was saved.
- **Why.** A pickup search proves one dwarf's route to one load. A turn of that search is 8
  scheduler wakes, and a 1 ms wake expands only about 40 route nodes in play, while a route to
  the shelf takes 400–2,700. After its turn a search waits while every other dwarf and load
  gets one. With four dwarves and 22 load cells that is 88 searches, about 13 seconds a round
  at 60 fps, and most of them went over the same ground to the stairs.
- **Strolling made it worse.** A dwarf's planning hold lasts 4 seconds and is renewed only
  while its own search runs, so between turns idle dwarves wandered off, and a moved dwarf's
  searches start again.

## What changed

- **One search covers the loads lying the same way** (`StorageComponent.pickup_group`). The
  quoted load comes first, then the nearest other eligible loads, up to
  `hauling.pickup_search_cells` (16), that keep the search's distance estimate at least half
  the quoted load's. The search ends at whichever load it reaches first, which is also the
  nearest by the route.
  - A load the other side of the dwarf, or on a level below it, would weaken the estimate, so
    it keeps a search of its own. A load without a route therefore still gets only its turn,
    and never holds up one that has a route (the fairness rule from milestone 213).
  - The whole group waits its turn together, and a failed search rules out its whole group
    for that dwarf.
- **The dwarf takes the load the search reached.** The assignment carries it
  (`haul_pickup_cell`), and `reserve_haul` builds the bundle round it rather than round the
  load nearest in a straight line. Before, the claim always matched the quote, because a
  search had only one load.
- **Claims elsewhere don't restart searches.**
  - Loads claimed since a search began are taken out of its goals on the next turn
    (`_prune_pickup_goals`). Every lease on a shared search holds the same goal dictionary,
    and a cache entry whose search was pruned is dropped rather than restarted in place.
  - A quote that lands in a group the dwarf is already searching carries on with that search
    (`_pickup_route_key`). So when Snorbar picks up the logs he dropped, the others keep their
    searches.
  - A finished proof whose load was claimed before the dwarf got it carries on to the group's
    next load (`NavGrid.reopen_search`, a copy of the finished search with its end cell opened
    again). If it can't, the pickup is planned again. Such a proof is never handed to a dwarf:
    before this check, a later dwarf could be sent off with a route to a log someone had
    already taken.

## Results

- **The owner's save, at 60 fps:** the first shelf load is assigned after about 13–15 s
  instead of 75 s, and all five dwarves are hauling by about 24 s. Some then go to bed: it is
  evening.
- **`HaulingFarLoadsTest` (new, hauling area):** a walled yard, a six-high shelf with its
  stairs at the far side, three dwarves and twelve logs, 40 nodes a wake.
  - The old code assigned its first load at wake 1,427 and had all three working at 1,476.
  - Now the first comes at wake 158 and all three by 395.
  - The first dwarf takes the log beside the stairs, the nearest by the route, and every dwarf
    claims a log at the end of its own proven route. With the claimed-proof check disabled,
    that last assertion fails.
- **Under a real 1 ms budget** the same yard needs 13,400 route nodes instead of 63,600. A
  grouped search expands about 44 nodes a wake instead of 62, but the budget is wall-clock, so
  frame time is unchanged. Resuming a finished search costs about 0.3–0.4 ms for a typical
  1,000–1,200-node search.

Gate 55/55, the lint finds nothing new, and the hauling, jobs, storage and construction areas
pass. Restart Play; no reload needed.

## Not done

- **The route back to storage** is still searched once per pickup stand. Once the first dwarf
  is on its way, most of the rest of the wait is these delivery searches.
- **A crowd at the stockpile** still searches one route per dwarf. With 20 or more idle
  dwarves all heading for the same far loads, expect a wait that grows with the crowd.
- **Resuming a very long finished search** (towards the 24,000-node limit) copies it whole:
  roughly 8 ms, once. It only happens when that search's load is claimed first.
