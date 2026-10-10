# 95 — Deer and wolf arrivals

2026-10-09. The player approved deer and wolf arrivals after the rabbit pilot.
Both now use WorldEventDirector's saved calendar opportunities, staggered edge
entry, local hunting pressure, expiry and provider interface.

## Live tuning

| Species | Opportunity interval | Planned group | Population cap | Inland depth |
|---|---|---|---|---|
| Rabbit (unchanged) | 2–4 days | 1–4 | 48 | 32 blocks |
| Deer | 4–7 days | 2–4 | 18 | 40 blocks |
| Wolf | 7–12 days | 1–2 | 4 | 48 blocks |

These are opportunities, not guaranteed reinforcements. Deer seasonal chances
are 85% spring, 80% summer, 90% autumn and 40% winter. Wolves use 50%, 50%, 65%
and 55%. Population capacity can reduce a group, including a single deer when
only one place remains. A full population, unsafe corridor or unsuitable habitat
skips entry. No death changes the planned dates, sizes, chance rolls or route seeds.
Missed opportunities never accumulate. Settings remain solely in
`data/world_events/arrivals.json`.

## Deer groups and wide navigation

Deer use their complete 2×2 footprint and four-cell clearance along every stride,
including the swept step-up space. Wolves use 2×2×2. Entry spacing checks live
body footprints and reserved stride destinations, including partial overlaps at
corners. Every footprint column at a destination must have dry grassy support.

Each deer group shares a stable `herd:<event ID>` identity. Members receive saved,
connected destinations at least four blocks apart within an eight-block habitat
patch. The planner sends the furthest branch destinations first so later members
can reach their homes without walking through a settled group member. Ordinary
deer personal space and loose herd steering still apply. Entry spacing is 2.5
simulation seconds for deer and three for wolves; a busy entry waits longer.

Wilderness routes stay away from dwarves and recent player hunting. Deer homes
stay 48 blocks from existing deer homes; wolf homes stay 96 blocks from existing
wolf homes. Whole-map tree occupancy must finish registering before the provider
is ready, preventing startup routes through trunks that have not spawned yet.
Live route checks still cancel unentered members if construction changes a route.

## Predator limits

Wolf arrivals require five surplus prey animals per living wolf, including the
incoming wolves. Surplus is counted only above the existing protected reserves:
32 rabbits and 12 deer. For example, 48 rabbits plus 18 deer provide 22 surplus
prey and permit at most four wolves; populations at both reserve floors permit
no additional wolves. The hard wolf cap remains four regardless of abundance.

Each arriving wolf's destination also needs at least two eligible prey within
64 blocks. Capacity and nearby prey are checked during planning and immediately
before each member enters. If prey disappears or moves away, pending members
are cancelled; wolves already on the map remain ordinary animals. Counts do not
guarantee successful future hunts across obstacles—existing bounded pursuit and
reserve floors continue to govern captures.

New wolves enter content (0.35 appetite) and cannot acquire prey until their
arrival journey ends. They still flee dwarves and can sleep. Once settled—or if
their route becomes interrupted—they resume normal hunger-gated hunting. Groups
of two are travelling pairs; coordinated pack hunting is not introduced.

## Saves and presentation

The existing `world_events` section gains delayed deer/wolf opportunities after
loading a rabbit-only save, using the restored calendar. Existing rabbit plans
remain unchanged. Each batch saves individual member routes, accepted count,
issued ordinal and entry timer. Deer herd identity and both species' in-flight
movement use their existing wildlife records. No new autoload, global class,
asset, audio bus or save schema version is needed.

Arrival toasts name the actual species/count and entry edge. Object explorer
shows the journey alongside the existing herd/hunting fields; a wolf travelling
inland reports **Hunting: Settling in**. **DEV: Arrival status** lists all three
species and their own latest result, with six seconds to read it.

Restart play and use **Menu → Development → DEV: Next deer arrival** or
**DEV: Next wolf arrival** to find an entered animal. **DEV: Next arrival** still
cycles all species, including settled entrants. Full starting populations skip
arrival opportunities until there is room; the controls do not force replacements.

## Verification

Engine profiles and logs are isolated under `tmp/herd_arrival_review/`.

- `HerdArrivalTest.gd`: natural eligible four-deer/two-wolf corridors on seeds
  0, 42, 1234 and 20261009, including wolf routes from all four edges; complete
  stride support/clearance; separated destinations; one herd identity; staggered
  entry and settling; pause and mid-group/mid-stride JSON replay; upper-footprint
  obstruction, missing partial support and partially overlapping entry bodies;
  prey reserves, local presence and changing food/capacity checks; hunger gating;
  kills preserving schedules; saved pressure and old-save event migration.
  Floating needs are compared within 1e-9 to allow JSON decimal round-off;
  IDs, RNG state, route progress and other discrete behavior remain exact.
- `ArrivalEventTest.gd`: rabbit opportunities, route validation, extinction,
  population caps, pressure, expired events and save behavior remain valid.
- `RabbitWildlifeTest`, `DeerWildlifeTest`, `WolfWildlifeTest`: ordinary grazing,
  herd movement, rest, fleeing, hunting/capture and save expectations still pass.
- `SaveManagerRoundTripTest`: a partially entered deer herd and travelling wolf
  join the existing rabbit batch, meal cooldown and hunt fixtures. Full saves,
  autosaves and recovery from a corrupted primary deep-compare all owners.
- `tools/ArrivalLivePreview.gd -- --deer` / `--wolf`: native seeded world,
  species-specific DEV locator, screen picking, inspector, Follow, actual group
  entry and settling. The deer check exposed the tree-registration startup race;
  provider readiness now waits for the complete tree occupancy pass.

Captured entry/journey/settled views are in `tmp/herd_arrival_review/`, prefixed
`deer_arrival_` and `wolf_arrival_`. Native QA does not read or modify player saves.
Goblins, orcs, traders, coordinated packs, breeding and player hunting remain
separate milestones.
