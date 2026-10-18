# 193 — Wildlife arrival preparation performance · 2026-10-15

The large arrival stall comes from **duck habitat and flight preparation**.
The first traced 30-dwarf run spends 224 and 252 ms in two duck attempts;
rabbit and deer preparation takes about 8 and 10 ms. Duck planning now resumes
across main-thread frames instead of finishing the entire search in one call.

This pass targets the arrival hitch identified in [191](191_event_hitch_review.md).
It keeps the 30-dwarf design direction, prior lighting/dust/autosave improvements,
and the unchanged original player save. Findings in 177 remain parked.

## Attribution and implementation

Temporary baseline instrumentation times provider preparation, terrestrial
search/group planning, duck habitat generation and candidate pools. In the
30-dwarf trace, duck habitat generation takes 51–56 ms, including 13–16 ms
building/sorting pools. Most remaining time checks alternative swept flight
paths. A fixed number of attempts did not bound the cost of a single frame.

`WorldEventDirector._process()` now supplies a shared **soft 2 ms preparation
deadline**. Providers may return `pending`, which retains the same candidate
ordinal and does not draw another opportunity or increment the attempt count.
The current terrestrial planner still completes a probe synchronously; only
the expensive duck search needs a continuation for these measured cases.

`DuckArrivalPreparation` retains water-pool construction, habitat iteration,
landing selection and flight-search progress. Pool entries are sorted packed
x/z integers with the same order and duplicates as the former Vector2i array.
The same random draws, habitat rules, candidate order and flight arches apply.
`DuckNavigation` exposes resumable sampled-flight queries; its ordinary
`flight_path()` uses the same implementation to completion.

All this work stays on the main thread. Duck navigation reuses queries only
within one synchronous slice and clears them before yielding. No stale query
cache, scene reference access from a worker, or temporary search data enters
the save. Expiry and restore cancel the continuation. Loading a partially
prepared event starts the saved seed/attempt again. Pause stops progress.

Actual entry still checks population capacity, safety near dwarves/hunting,
landing water, entry spacing and the complete live flight. An invalidated plan
cannot bypass these checks. Already flying ducks continue their existing swept
movement checks. Save schema, caps, chance rolls, flight shape, offscreen
simulation and ordinary animal needs/animation are unchanged.

The deadline is not a hard callback limit. Copying/sorting pools, one bounded
habitat probe, terrestrial searches and final member entry are still atomic.
The flight search yields between swept segments. Delaying preparation changes
when animals enter, and an evolving world may change which candidate succeeds.
Frozen-world comparisons establish equivalent decisions under identical data;
they are not a claim of frame-identical live scheduling.

## Native measurement

Use the same developed settlement and real-terrain work from 191/192: 79
wildlife, 2,716 mined blocks, 86 built blocks, 20 furniture pieces; 64 additional
mining blocks, 48 construction blocks and 240 loose items. Expand the roster to
5/20/30 through normal spawning. Pan continuously at speed 1 in clear weather.
Each isolated native process samples 40 seconds and makes one opportunity batch
due at 6 seconds, with passing chance rolls and a proposed count of two.
Provider eligibility/caps still apply. Autosaves are disabled for this focused
experiment. This is a controlled trigger, not a natural arrival-frequency test.

Hardware: Ryzen 7 9800X3D / Radeon RX 9070 XT; Godot 4.7.2 Steam, D3D12
Forward+, VSync disabled. Runs are sequential. Process brackets include all
WorldEventDirector work; whole-frame measurements also include other simulation
and rendering. Instrumentation and raw source identities are retained.

| Dwarves | Event CPU maximum ms, before → after | Whole-frame maximum ms, before → after | Mean frame ms, before → after | P95 frame ms, before → after |
|---|---|---|---|---|
| 5 | 253.88 → 13.59 | 297.21 → 71.00 | 17.33 → 18.75 | 33.62 → 36.03 |
| 20 | 258.29 → 13.05 | 321.79 → 87.56 | 25.02 → 26.24 | 44.30 → 45.75 |
| 30 | 260.25 → 13.38 | 312.97 → 84.23 | 30.19 → 29.18 | 50.88 → 49.47 |

Every before run contains two frames above 100 ms; every final after run has
zero. Peak event CPU falls about **95%**. Ordinary averages are mixed: the
5/20-dwarf runs are about 8%/5% slower on average, while 30 improves about 3%.
These short, single live runs do not establish a broad FPS improvement.
The clear result is removal of the arrival spikes.

Each run admits **one rabbit, one deer and two ducks**, respecting the copied
settlement's available population slots. Ducks finish entering at 8.95/9.01/9.02
seconds before and 11.88/13.16/13.45 after, for 5/20/30 dwarves. Entry is delayed
by roughly 3–4.4 seconds while planning is distributed across frames.

Net mined/built/stored counts before → after are **64/0/8 → 63/0/8** at five,
**64/2/29 → 64/2/29** at twenty, and **64/3/32 → 64/2/31** at thirty. No work
system is frozen to obtain the improvement. The construction wait identified
in 191 remains a separate target; these counts are not a throughput proof.

The first trial at 30 dwarves reduces maximum event CPU from 260.25 to 13.75 ms
and whole-frame maximum from 312.97 to 97.08 ms. It admits the same one rabbit,
one deer and two ducks; duck completion moves from 9.02 to 13.54 seconds after
sampling starts. Final matrix results supersede the trial for the main table.

The five-dwarf baseline writes complete samples and then reports the previously
documented DwarfAgent shutdown/global-transform errors from 190/191. The runner
rejects it. Its timings remain diagnostic evidence; it is **not a clean test
pass**. This change does not alter dwarf teardown or suppress its errors.

## Validation and package

The new fixture compares against frozen former DuckPopulation and
DuckNavigation scripts on four generated worlds. **45 exact comparisons**
cover 12 preparation outcomes and 33 full sampled flight paths. More than
11,000 short preparation slices exercise continuation boundaries. It checks
that query caches are empty between slices, pending work does not consume an
attempt, pause holds state, restore discards transient work, expiry cancels it,
and a newly obstructed landing rejects entry. Its 0.2 ms test target is soft;
the largest measured slice is 2.85 ms on the bounded habitat operation.

Existing duck reuse tests retain **1,200 exact simulation updates and 882
navigation comparisons**. All **12 fixtures** pass on final production sources:
ArrivalPreparationTest, ArrivalEventTest, HerdArrivalTest, DuckPopulationTest,
DuckQueryReuseTest, DuckWildlifeTest, AnimalNavigationCacheTest,
RabbitWildlifeTest, DeerWildlifeTest, WolfWildlifeTest,
SaveManagerRoundTripTest and WorldTerrainStartupTest. Full save tests retain
190 malformed-file rejections, worker capture/failure checks and all four
species' partial movement/arrival records. No final fixture reports a script
or engine error.
Two intermediate failures were confined to the new test harness: inferred
Variant warnings and assigning a frozen script into a concretely typed field.
The oracle now uses a separate owner adapter. Failed logs remain labeled;
neither failure is counted as a pass.

Native PCK verification passes with loose workspace scripts unavailable. It
saves a genuinely pending duck search through manual/autosave transactions,
corrupts only the disposable primary, recovers the backup and restarts the
saved decision. Exactly two ducks enter, with one completion record and no
duplicates. The arrival screenshot was inspected. Existing lighting/dust,
slice, offscreen movement, construction and hauling checks also pass. The
separate release EXE builds its world and exits without script/engine errors.
Expected startup warnings and the deliberately corrupted-save warning remain
in the logs. Original player save, ground planner, event tuning and earlier
performance sources retain their hashes.

The release is `build/windows/releases/20261015-175703-165-d9607ed8/Deepdraft/Deepdraft.exe`.
The refreshed `build/windows/Deepdraft-Windows-Playtest.zip` is 76.9 MiB, SHA256
`959ff956c59c2742be05bc08012cb3437ab146544f26919b5fa8b250e4b933f7`.
ZIP contents exactly match the four runtime files in the release directory.
Export includes every runtime data definition and excludes development files.
Restart editor Play or launch this release to use the change.

## Reproduce and next work

`tools/performance/RunArrivals.ps1 -Population 5|20|30 -Label <new_label>
-SavePath <copied_save> -Seconds 40 -NoAblations -Weather base:weather:clear`
creates isolated user data and checks the source save hash. Do not overlap
native measurements with another test, export or editor Play session.
`ArrivalBenchmark.gd` writes event CPU, whole frames, history, actor counts and
work progress. `arrival_frames.json` stores flat rows of five numbers: seconds,
wall ms, event CPU ms, process ms, draw ms.

[Evidence](concepts/arrivals_20261015/README.md) retains the original/profiled
sources, final source hashes, raw reports/logs, failed diagnostic attempts and
package checks. `CollectArrivalEvidence.py` refreshes the evidence without
copying runtime saves or user profiles. Baseline reproduction uses the retained
`.profile.txt` scripts with the unchanged director and navigation before files;
restore final bytes afterward, with no overlapping game/test process.

## Next construction discussion: project material staging

**Resolved, 2026-10-17:** the user approved temporary materials crates and the
existing dwarf carry capacity. [205](205_construction_materials_crates.md)
implements staging, up to two haulers, one builder, three seconds of hammering
per voxel, progressive completion and unused-material refunds. The discussion
below records the earlier deferral; it no longer blocks this approved feature.
The longer 30-dwarf performance soak remains a later checkpoint.

**Priority update, 2026-10-15:** proactive performance work is now paused after
[197](197_duck_update_performance.md). The next focus is gameplay and usability,
beginning with this workflow in a fresh discussion. Retain the existing
performance measurements as a baseline; resolve the design questions below
before changing construction behavior.

User direction on 2026-10-15: defer **construction waiting and repeated job
eligibility checks** to a fresh discussion later. Redesign the workflow before
optimizing its current behavior. The intended sequence is:

1. Dwarves deliver all required project materials to a project drop box.
2. Once all materials are staged, builders hammer the project for a duration.
3. That duration may scale with the number of blocks to construct; the formula
   is a design question, not a settled requirement.

The user wants to address the inefficiency of carrying one stone at a time.
Discuss batch carrying and deliveries explicitly: adding a drop box alone does
not reduce those trips. Carry capacity, multiple builders, block completion
timing, and cancellation/material recovery remain open design topics. This is
a recorded direction for later discussion, not an implementation task now.

Keep the construction order that remained pending in every 191 settlement run
as a regression scenario for the redesigned workflow. Revisit access, worker
needs, eligibility checks and actual completion when that design is agreed.
The season transition was subsequently spread overnight in
[194](194_gradual_season_transition.md). A longer normal-speed 30-dwarf soak
remains a later checkpoint while performance targets are paused. Reopen profiling
when ordinary play exposes a repeatable hitch or clear regression.
