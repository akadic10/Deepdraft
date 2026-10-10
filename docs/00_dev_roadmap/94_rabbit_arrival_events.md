# 94 — Rabbit arrival events

2026-10-09. The player approved a shared arrival-event foundation with rabbits
as the first provider. Arrival opportunities are independent of deaths; wiping
out a population neither accelerates the next opportunity nor enlarges its group.

Deer and wolf providers subsequently shipped in
[95 — Deer/wolf arrivals](95_deer_wolf_arrivals.md). This document records the
original rabbit pilot; its arrival timing and population cap remain unchanged.

## Live behavior

- A seeded opportunity occurs every 2–4 game days, with 1–4 rabbits decided
  in advance. Seasonal success chances are spring 90%, summer 85%, autumn 80%,
  winter 45%. These are opportunities, not guaranteed replacement animals.
- Rabbit population is capped at 48, including animals still travelling inland.
  A group is reduced to available capacity; a full population skips the event.
  Unused members and failed opportunities expire instead of accumulating.
- A candidate must start on dry, supported lowland grass at an actual map edge
  and have a continuous walkable route to a connected grassy patch at least 32
  blocks inland. Corridors avoid nearby dwarves and recent hunting pressure;
  destinations stay at least 16 blocks from existing rabbit homes.
- Each member enters at the boundary, at least 1.5 simulation seconds apart,
  waiting if another animal occupies the entry. The whole corridor is checked
  again before every spawn. Walls, water, cliffs, pits and placed occupancy do
  not permit teleporting inland. Later live obstructions cancel pending members.
- Entered rabbits visibly travel toward their inland home. Fleeing, eating and
  sleeping retain priority. After displacement they try to rejoin their route
  through legal local hops. If blocked for 30 accumulated seconds, the journey
  becomes interrupted and ordinary safe wandering resumes toward the home area.
  An entered animal is never teleported or silently deleted for a failed journey.
- Opportunities expire six game hours after their due time. Large DEV clock
  jumps skip missed events and schedule one future opportunity; no catch-up wave.
  Pause and speed govern travelling animals and entry spacing.
- A quiet toast reports the number actually entered and their edge. The shared
  explorer adds Arrival: Travelling inland / Settled / Journey interrupted.

All tuning lives in `data/world_events/arrivals.json`; wildlife still owns its
species definitions and existing sounds. The wolf reserve floors remain 32
rabbits and 12 deer. Deer/wolf arrivals, breeding, player hunting, loot, raids
and trading are not part of this pilot.

## Hunting pressure connection

`WildlifeManager.remove_animal(animal, "player_hunt")` is the successful-removal
hook for future player hunting. Predation uses the same removal API with
`"predation"`, which does not add human hunting pressure. Invalid/repeated
removals cannot add pressure.

Pressure is aggregated in 64-block regions with an 80-block avoidance radius,
one point per kill, a six-point cap and decay of 0.5 per game day. The avoidance
threshold is 0.5: a single recent kill discourages settlement for about one day;
repeated hunting keeps that area unattractive longer. Unaffected regions remain
eligible. This is local danger, not a global population replacement score. It
never changes scheduled dates, group draws, probability rolls or RNG state.

## Ownership and extension

`WorldEventDirector` is a scene owner in `debug_world.tscn`, the sole loader of
the arrival table and owner of the `world_events` save section (priority 66).
No autoload or global class was added. It owns scheduling, bounded history,
local pressure, opportunity expiry and per-member progress.

Providers register with the `arrival_provider` group and implement:

- `arrival_provider_key()` and `arrival_ready()` for binding/readiness.
- `prepare_arrival(event, plan, director)` for one bounded candidate search,
  returning ready, retry or blocked and an accepted route/group.
- `spawn_arrival_member(event, batch, director)` for one atomic entry, returning
  spawned, wait or a terminal rejection reason.

WildlifeManager is the first provider; EdgeArrivalPlanner supplies its wildlife
navigation adapter. A probe examines at most 192 route nodes, one candidate per
frame, with at most 64 candidates per opportunity. Selected corridors are saved.
GrazerAgent stores the entered animal's route cursor, destination and movement.

Future visitors can supply a different navigation/entry adapter without changing
the clock scheduler. Wildlife uses `wilderness` entry. A future `trade_road`
adapter can preserve the merchant road design; goblin/orc groups need their own
eligibility, navigation and post-entry AI. Those providers are not implemented
by merely adding another JSON row. New event definitions receive delayed first
opportunities while preserving existing saved decisions.

## Persistence

The director saves its RNG as text, serial identity counter, next decisions,
candidate attempt, accepted route, issued-member count, stagger timer, history
and hunting pressure. Each arriving rabbit has a stable event/member identity
and saves its journey with the existing needs and partial hop.

Issued ordinals never rewind after predation. Saving does not make decisions or
advance the event. Restoring a half-entered group continues the remaining members
without repeating the first member or its notification. Loading is gated until
SaveManager finishes restoring the calendar. An older save without world_events
gets its first ordinary opportunity 2–4 days after its restored date, including
when its saved rabbit population is explicitly empty.

## Verification and playtest

Isolated engine profiles and logs are under `tmp/arrival_review/`.

- `ArrivalEventTest.gd`: complete deterministic edge routes on seeds 0, 42,
  1234 and 20261009; extinction does not affect future decisions; capacity and
  seasonal skips; zero-population arrival; staggered entry and inland settling;
  pause; JSON replay mid-stride/mid-group; consumed-member nonduplication;
  local pressure persistence/decay and predation exclusion; missed events;
  changed-route cancellation; sealed walls, water and gaps; restored-calendar
  migration and adding a new event definition without changing existing plans.
- `SaveManagerRoundTripTest.gd`: the actual main scene saves one travelling
  member, two pending members, a future decision and hunting pressure alongside
  the populated colony. Autosave, manual save and corrupt-primary backup
  restoration deep-compare all owners successfully; saves remain observational.
- RabbitWildlifeTest, DeerWildlifeTest and WolfWildlifeTest pass unchanged
  behavior expectations after the shared journey hook and removal API changes.
- `tools/ArrivalLivePreview.gd`: native seed 1234, real natural corridor and
  three entrants, public DEV locator, screen picking, inspector, Follow,
  journey and settled captures. No player save is read or changed.

Restart play. **Menu → Development → DEV: Arrival status** shows the next
opportunity and last result. **DEV: Next arrival** locates an entered rabbit,
including one that has settled. Normal opportunities take 2–4 game days and can
skip at full capacity; these DEV controls do not force a replacement wave.

Captures: `tmp/arrival_review/arrival_entry.png`, `arrival_journey.png`,
`arrival_settled.png`. No Project Reload is necessary; there are no new globals.
