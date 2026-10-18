# 197 — Duck update performance · 2026-10-15

**October 17 follow-up:** The construction workflow discussed below is now
implemented in [205](205_construction_materials_crates.md). The current resume
point is [220 — Session handoff](220_session_handoff_2026_10_17.md), including the
subsequent user-reported X-ray fixes. Broader proactive performance work and the
water investigation remain parked; this note does not resume either backlog.

**Current direction, 2026-10-15:** pause proactive performance work and retain
these measurements as the baseline. Camera panning and slicing now feel much
better. Shift to gameplay and usability, starting with the fresh construction
workflow discussion in [193](193_arrival_preparation_performance.md). Revisit
profiling when ordinary play exposes a repeatable hitch or clear regression.

Duck body clearance now reuses raw-terrain and placed-obstacle results until the
world changes. In the normal-speed 30-dwarf profile, total duck CPU falls
**17–18%** and total wildlife CPU about **8%**. This saves roughly 0.24–0.30 ms
per frame in the measured duck population. Whole-frame timing remains variable;
this is not evidence of a reliable overall FPS improvement or a hitch fix.

Water work remains parked at the player's request, including its appearance and
the proposed water-focused profile. No water, art, lighting, construction or
population rules change here. Construction/eligibility still awaits the drop-box
and timed-building design discussion in [193](193_arrival_preparation_performance.md);
review findings in [177](177_project_review_deferred_2026_10_14.md) remain parked.

## What the profile found

The existing optimization in [186](186_duck_query_performance.md) already shares
queries within each synchronous wildlife update. It does not retain duck body
clearance into the next frame, so mostly stationary birds repeatedly traverse
the same raw terrain cells and placed-entity columns. Surface validation and
hydraulic safety both call that clearance path.

Temporary wrappers separate navigation, decisions, flight, animation, flock
scans and canopy queries. Timers are nested: **do not add their totals**.
All means below are accumulated milliseconds per frame, for all 11 ducks.

| Work | Stationary before → after | First pan before → after | Later pan before → after |
|---|---:|---:|---:|
| Raw body clearance | 0.486 → 0.178 | 0.419 → 0.147 | 0.318 → 0.107 |
| Duck movement/decisions/pose | 1.581 → 1.279 | 1.409 → 1.135 | 1.125 → 0.890 |
| All duck processing, including flock context | 1.784 → 1.479 | 1.605 → 1.331 | 1.316 → 1.081 |
| Whole wildlife callback | 3.198 → 2.953 | 2.983 → 2.749 | 2.621 → 2.413 |

Raw body-clearance mean cost falls 63–66%. Duck advance P95 falls from
2.128/1.947/1.538 ms to 1.650/1.501/1.191 ms. Animation remains around 0.14–0.15 ms
and flock context around 0.13–0.14 ms. Neither is changed.

Occasional cold flight planning remains expensive. Duck advance maxima are
15.67/16.94/14.56 ms before and 15.62/17.30/17.27 ms after. This change improves
ordinary repeated work, not those worst samples; first-time cache misses still
perform the original scans and pay cache lookup/storage overhead.

## Implementation and behavior contract

`AnimalNavigation.solid_bounds_clear(low, high)` caches inclusive integer bounds,
using the existing terrain tile cache and its existing invalidation signals.
`DuckNavigation._clear_bounds_live` delegates to it. Only these two existing
runtime files change.

- Each result depends on raw terrain solidity and placed occupancy. It is
  separate from terrestrial air/support queries, so water remains passable and
  flight above Y=127 still checks placed obstacles.
- Terrain edits and placed-obstacle changes immediately discard overlapping
  results. The largest queried horizontal footprint extends invalidation across
  tile seams. Streamed chunks retain the existing deferred invalidation.
- World/water resets, registry resets and generator identity changes clear the
  shared cache. Water occupancy notifications also invalidate conservatively.
- Body entries share the existing 128-tile and 1,024-entry-per-tile bounds with
  terrain, clearance and support entries. There is no unbounded per-duck history.
- Duck water height, waterfall safety and surface maps still expire at the end
  of the synchronous observation pass. Canopy intersections remain live. Every
  duck still advances and animates every active frame, including offscreen.
- Decisions, movement speed, reactions, feeding, flight cadence, random draws,
  pause/speed behavior and serialization retain their existing code.

No new autoload, global class, save field or rendering setting is introduced.

## Measurement method

The copied settlement and workload match [195](195_normal_speed_rendering_profile.md)
and [196](196_shared_atmosphere_performance.md): 30 dwarves, 79 animals including
11 ducks, 2,925 trees, 64 mining targets, 48 construction targets and 240 loose
supplies. All wildlife begin outside the camera frustum. Three 30-second phases
follow eight-second warmups: stationary active work, first pan and later pan.
Calendar speed is x1, 60 seconds per game hour. Autosaves and arrival scheduling
are disabled in these steady-cost samples.

Runs are sequential, native D3D12 Forward+ at 2560×1440, Godot 4.7.2 Steam,
Ryzen 7 9800X3D / Radeon RX 9070 XT, VSync disabled. There are two instrumented
before/after runs, two optimized runs without markers/wrappers, and one fresh
previous-code control between those optimized runs. The control changes only
the two navigation files, restoring exact optimized bytes afterward. Both
implementations include the shared atmosphere change from 196.

| Phase | Fresh previous-code mean ms | Optimized mean ms, two runs | Previous P95 ms | Optimized P95 ms |
|---|---:|---:|---:|---:|
| Stationary, initial active work | 19.84 | 20.20–20.95 | 37.34 | 37.61–38.28 |
| First camera pan | 15.32 | 15.92–16.02 | 28.33 | 29.59–30.03 |
| Later camera pan | 14.75 | 13.11–14.44 | 28.50 | 26.47–28.13 |

The fresh previous-code control is faster during initial work and the first pan;
the optimized runs are faster in the later pan. Two earlier controls of the same
previous code in 196 span 19.28–21.04 / 16.16–16.40 / 13.04–14.16 ms. Together,
these mixed results do **not** establish an overall FPS gain. GPU means remain
about 2.8–3.0 ms, and P95 still exceeds the 16.67 ms budget in every phase.

Optimized phase maxima are 76.12–82.52 / 85.26–104.53 / 43.04–44.28 ms; the fresh
previous-code maxima are 73.35 / 74.83 / 45.22 ms. One optimized first-pan frame
exceeds 100 ms. It is retained in the raw data, without attributing an unmarked
whole-frame stall to a particular system. No worst-frame improvement is claimed.
All three controls mine 48–49 blocks and build two during the stationary phase;
the subsequent pans continue hauling, storing 17–21 more items in the first pan.

Short live runs do not guarantee identical event scheduling or completed work.
The retained summary includes mined/built/stored-item deltas for each phase,
and the raw rows retain timing and process detail. The exact behavior fixture
below provides the controlled state comparison. These are not hours-long soaks.

## Validation and handoff

- New clearance fixture: 1,017 assertions, including authoritative raw-world
  comparisons, cache reuse, diagonal seams, terrain/occupancy addition and
  removal, streamed chunks, bulk/world resets, high-altitude obstacles and
  shared storage bounds. Its alternating 12,000-query comparison with the
  frozen immediate previous navigation takes 153.342 ms before and 17.499 ms
  after, an 88.6% reduction for warmed repeated clearance queries only.
- Existing differential fixture: all 1,200 updates and 882 navigation checks
  match exactly, including positions, routes, needs, timers and RNG. It exercises
  rising/falling/drained water, obstacles, threats, JSON restore, speed and pause.
  Its older reference predates 186; its timing is not used to attribute this
  change's gain.
- All 12 fixtures pass: `DuckSolidBoundsTest`, `AnimalNavigationCacheTest`,
  `DuckQueryReuseTest`, `DuckWildlifeTest`, `DuckPopulationTest`,
  `ArrivalPreparationTest`, `ArrivalEventTest`, `HerdArrivalTest`,
  `RabbitWildlifeTest`, `DeerWildlifeTest`, `WolfWildlifeTest`, and
  `SaveManagerRoundTripTest`. Arrival preparation retains 45 exact planner
  comparisons; the save fixture includes its worker/transaction checks.
- The first two native package attempts exposed an over-strict new diagnostic:
  it compared unrounded in-memory doubles across the existing default-precision
  JSON save boundary. The diagnostic capture finds 258 numeric differences,
  largest 7.11e-14, with no other field differences. The corrected check compares
  captured, committed and restored wildlife at the actual save precision, with
  exact IDs/RNG. Both failed attempts and the numeric diagnosis are retained;
  production save code and format are unchanged.
- The final native package run passes all 26 checks on the copied five-dwarf,
  79-animal settlement. All 11 initially offscreen ducks advance and seven move;
  pause, placed-obstacle invalidation, slice visibility, committed save contents
  and restored wildlife state at save precision pass. Before/after reload
  captures were inspected. This is a package integration check; the performance
  measurements above use 30 dwarves.
- The actual release EXE starts cleanly, finishes all 1,024 overview tiles and
  exits cleanly after about 42 seconds. Export checks include all runtime JSON
  and exclude development files. All final runtime logs are free of engine or
  script errors; expected startup and negative-test warnings are retained.
- The source audit checks all 344 existing GDScript/shader files against the
  task-start snapshot: only `AnimalNavigation.gd` and `DuckNavigation.gd` differ.
  Temporary instrumentation is restored exactly. The original player save and
  all water source files are unchanged. Existing unrelated work is preserved.

Restart Play in Godot or launch the new
[Windows release](P:/Deepdraft/build/windows/releases/20261015-201320-472-4cdcd7c3/Deepdraft/Deepdraft.exe).
The refreshed [playtest ZIP](P:/Deepdraft/build/windows/Deepdraft-Windows-Playtest.zip)
is 80,659,080 bytes, SHA256
`b5f8b83ed6eafa455c2aa0d81064776c131fa2b0aec3bf3d2365c6950b7dd7de`.
No project reload is needed for a new global class or autoload.

Evidence: [summary](concepts/duck_updates_20261015/summary.json),
[source/save/package audit](concepts/duck_updates_20261015/audit.json),
[clearance fixture](concepts/duck_updates_20261015/solid_bounds.json),
[differential fixture](concepts/duck_updates_20261015/query_reuse.json).
The evidence directory retains before/after sources, raw frames compressed as
JSON.gz, instrumentation/restoration manifests, fixture logs and package captures.

Reproduce using `tools/performance/RunSteadyRendering.ps1 -DuckDetails
-NoAblations -SavePath <private-copy> -Label <fresh-label>`. Omit `-DuckDetails`
and add `-NoMarkers` for whole-frame controls. Do not run a game benchmark, fixture
or export concurrently. `CollectDuckUpdateEvidence.py` checks source provenance,
save integrity and completed validation before collecting the durable evidence.

Performance work is paused. The longer normal-speed 30-dwarf soak through saves,
arrivals and season boundaries remains a later checkpoint. Slicing ordinary duck
flight preparation across frames remains a possible later hitch investigation;
arrival planning already has its own budget from 193. These are retained leads,
not the automatic next tasks. Water remains deferred.

Next focus: discuss the construction workflow in 193—stage all project materials
at a drop box, then perform timed building. Duration scaling with block count,
batch deliveries, carrying capacity and builder coordination need design decisions
before implementation. Keep routine performance awareness during gameplay work.
