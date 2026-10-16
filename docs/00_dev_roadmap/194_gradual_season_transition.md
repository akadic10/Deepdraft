# 194 — Gradual season transition · 2026-10-15

Seasonal tree, shrub, flower, reed and terrain refreshes now spread from midnight
to sunrise on the first day of the new season. The user explicitly requested a
gradual overnight change rather than replacing the world in one frame.

The old forest path removed all loaded tree instances and then repopulated the
map. Native measurement shows the visible tree count briefly falling from
2,925 to 14. The new path retains every tree body and replaces only changed art.
Logical season, crop eligibility, weather scheduling and calendar signals still
advance at midnight. Construction remains parked for the separate drop-box and
timed-building design discussion recorded in [193](193_arrival_preparation_performance.md).

## Behavior and implementation

`WorldClock.season_visual_progress()` derives the first night's progress from
the calendar's solar noon and seasonal daylight curve, matching the current
sky's sunrise. At normal speed the transition takes about 6–10 real minutes,
depending on the season. Pause freezes its game-time progress; speed changes
advance it with the clock. This uses the remaining night after midnight, not
the evening before the calendar rolls over.

`SeasonalRefreshQueue` holds transient object IDs and admits a proportional
number as the night progresses. The three owners share a soft 2 ms budget and
each services at most four entries per call; a terrain entry is one normal
worker batch (eight tiles with current settings). Large time jumps and daytime debug
season changes catch up over bounded frames instead of flushing the whole queue.
One model load/instance swap is atomic and may exceed that soft budget. Terrain
mesh generation/uploads retain the renderer's existing separate worker/frame
budgets; the shared budget covers admission and plant art replacement, not all
terrain or GPU work.
Taking ID snapshots and reconciling expired crop orders still run at the season
boundary; the queue budget is not a hard limit on that entire clock callback.

- `SurfaceFloraSpawner` retains root nodes, collision shapes, navigation
  occupancy, selection and felling sources. Its crop-art replacement helper
  also handles ordinary seasonal foliage, skipping unchanged model paths.
- `SurfaceDetailManager` gives seasonal presentation its own queue. Initial
  spawning, harvesting, growth and transplant updates keep their normal queue;
  expired harvest orders reconcile immediately with the logical season.
- `WorldRenderer` admits existing overview tiles, regions and chunks gradually.
  Old meshes remain visible until replacements are ready. Edits and slice
  concealment retain immediate invalidation; added terrain and cavity-shell
  dirty flags retain their existing handling.

This is a gradual sequence of discrete art/tile replacements, not a shader
crossfade. Newly spawned objects and direct harvest/edit refreshes can show the
current season before surrounding objects have caught up. Sky/weather retain
their existing continuous presentation, and damp-ground rendering retains its
existing incremental refresh.

Queues re-check live IDs, so felling, clearing, uprooting or streaming out an
object cannot be undone by a delayed refresh. A subsequent season replaces the
old queue. The queue has no save section. A paused mid-night load restores the
saved calendar and gameplay state, then rebuilds the target seasonal appearance
within frame budgets rather than recreating the exact intermediate visual mix.
`WorldClock.restoring_state` only marks that synchronous restore notification;
it is not serialized. Scene reload discards all previous presentation jobs.

## Measurement

The focused benchmark uses the unchanged copied settlement from 191–193,
expanded to 5/20/30 dwarves with the same nearby mining/building/hauling workload.
Each native sample pans for 55 seconds. Only the test changes calendar timing
to five real seconds per game hour, allowing a complete summer-to-autumn night
within one run. Actor speed stays at x1, but calendar-driven needs/growth see
the accelerated night. Autosaves and arrival scheduling are disabled for this
focused comparison. This does not measure their interaction or a normal-speed
long session.

Hardware remains Ryzen 7 9800X3D / Radeon RX 9070 XT, Godot 4.7.2 Steam,
D3D12 Forward+, 2560×1440, VSync disabled. Native runs are sequential.

| Dwarves | Clock CPU maximum ms, before → after | Whole-frame maximum ms, before → after | Mean frame ms, before → after | P95 frame ms, before → after |
|---|---|---|---|---|
| 5 | 18.81 → 6.78 | 85.00 → 79.35 | 15.39 → 16.81 | 33.15 → 34.69 |
| 20 | 18.89 → 5.62 | 87.88 → 86.79 | 23.85 → 24.64 | 44.90 → 45.69 |
| 30 | 20.41 → 5.95 | 113.72 → 82.35 | 28.10 → 29.52 | 52.29 → 51.17 |

The clock timer includes all its synchronous signal listeners. Its maximum falls
**64–71%**. Every final run retains all **2,925 tree bodies** throughout the
night; every baseline briefly falls to 14. The final runs have zero frames over
100 ms, versus one in the 30-dwarf baseline and zero at 5/20.

This is **not an average-FPS improvement**: mean frame times are 3–9% higher in
these short accelerated-night runs, and P95 is mixed. Keeping the scenery present
and distributing work changes when rendering and simulation costs overlap.
The first trial was worse because single-tile terrain admission repeated snapshot
and whole-overview statistics work. Normal worker-sized batches reduce that
overhead, but do not establish a throughput gain. Remaining large frames contain
substantial scheduler, water, wildlife and renderer work. The construction/scheduler
redesign stays deferred; this pass does not suppress work to improve the numbers.

Both five-dwarf runs mine 63 blocks and build none; both 20/30-dwarf pairs mine
64 and build three. Net stored-item changes are −3/+19/+7 before and +8/+19/0
after at 5/20/30 dwarves; live work ordering and consumption diverge. All 79
wildlife remain. See the retained raw data for final colony counts and subsystem
costs. These are progress observations, not a job-throughput equivalence claim.

The first diagnostic 30-dwarf run took screenshots inside sampling, introducing
237–404 ms readback/encoding stalls. Its images and logs are retained as
diagnostics, but its frame statistics are excluded. The clean baseline and all
comparison runs take no screenshots while sampling.

## Validation and handoff

The focused fixture passes **243 checks** covering all four season boundaries, every tree species and
growth stage, partial-night progress, pause, speed, year rollover, large jumps,
shared frame budgets, live removal, slice concealment, retained chopping work
and paused-night restore. All **14 headless fixtures** pass with exit 0 and no
script/engine errors: `SeasonalRefreshTest`, `TreeFellingTest`,
`ObjectExplorerTest`, `JuniperHarvestTest`, `ShrubPilotTest`,
`ShrubTransplantTest`, `ShrubRegrowthTest`, `FlowerPilotTest`, `ReedPilotTest`,
`TerrainAppearanceTest`, `WorldTerrainStartupTest`, `SaveManagerRoundTripTest`,
`WeatherPersistenceTest`, and `SkySceneLifecycleTest`.

The existing forestry/inspector tests now verify that the original tree body
survives a seasonal art change. The juniper restore test distinguishes immediate
crop eligibility from presentation that completes through bounded frames.
The first attempt caught that old same-frame art expectation; two earlier
fixture setup attempts caught a type annotation and a preload/autoload dependency.
The queue now receives the clock explicitly. Failed attempts remain in the
evidence and are not counted as validation passes.

The native D3D12 check loads the exported PCK with loose workspace files
unavailable. It verifies all 2,925 tree bodies and occupancy IDs survive midnight
and the half-night refresh; 1,463 tree IDs remain queued halfway through.
All existing terrain tiles receive a new revision by completion. Every live
tree/shrub/flower/reed resolves to the correct final model. Slice concealment
remains immediate. A real manual save during the partial transition preserves
the captured scene state, reloads its paused 04:00 calendar and reconstructs
the target art without waiting for dawn. All five dwarves and 79 wildlife return.
The check passes 22,270 assertions; half-night, dawn and restored-daylight
screenshots were inspected.

Windows release: `build/windows/releases/20261015-185405-935-6fcc4149/Deepdraft/Deepdraft.exe`.
The refreshed `build/windows/Deepdraft-Windows-Playtest.zip` is 76.9 MiB;
SHA-256 `635fea5cdba9230223e0ee3833a62964c2afbce529fb8ee25384044b53b51ccf`.
Its four entries exactly match the release directory. Export checks confirm
runtime JSON inclusion and development-file exclusion. The actual release EXE
also builds its complete terrain overview and exits cleanly. The original player save
and benchmark input retain SHA-256
`f223eee6dfe52fefe6add9a763362640f02c439fb2f33687f550661fb9cc148b`.
All prior arrival, save, lighting and work-effect source hashes remain unchanged.
Restart Play or launch this release; no new global class/autoload requires a
project reload.

[Evidence and reproduction notes](concepts/seasons_20261015/README.md) retain
the raw runs, source versions, failed attempts, regression logs and package audit.

No fog of war, population-cap enforcement, construction redesign or parked
177 findings are included. Steady CPU work and a longer settlement soak remain
the next performance investigations after this transition change.
