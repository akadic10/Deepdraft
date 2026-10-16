# 190 — Lighting buffer disposal performance · 2026-10-15

The lighting hitch identified in [189](189_session_handoff_2026_10_14.md)
comes from clearing the previous calculation's large CPU work buffers at the
start of the next update. Those buffers now transfer to a worker for disposal.
In the matched native 30-dwarf yard, the largest lighting update falls from
**231.49 ms to 5.78 ms**. A separate **168.18 ms** frame stall remains.

This is a hitch reduction, with a small and mixed effect on ordinary frame
times. The player's copied five-dwarf settlement does not reproduce the large
stall and runs essentially unchanged. The intended maximum remains 30 dwarves.
Review findings in 177 stay parked; fog of war and population enforcement are
outside this change.

## Cause and implementation

The original solver already uses a soft 2.5 ms per-frame budget, but one call
to `Dictionary.clear()` cannot yield to that budget. The yard's initial large
lighting calculation leaves **1,304,812 air-cache entries** and **1,267,577
visited entries**. The next terrain edit clears those and four other containers
in the `idle` step before starting its new calculation.

A separate instrumented original-code run attributes **225.436 ms** to that
single reset step: solver 225.440 ms, actor synchronization 0.957 ms and texture
upload 0.002 ms. The normal, uninstrumented original reproduces a 231.491 ms
lighting update inside a 260.739 ms frame. Actor lighting and GPU upload are
not the cause of this particular stall.

`UndergroundLighting.gd` now replaces `_air`, `_visited`, `_queue`, `_light`,
`_light_queue` and `_affected` with fresh containers, then sends the retired
containers to `WorkerThreadPool`. They contain only coordinates, numbers and
booleans. The worker clears exclusively owned data; it never reads the scene,
world, published light samples, images or textures.

Only one cleanup task may be outstanding. Completion is polled and collected
before reusing that slot. A current light calculation may continue while the
old buffers are cleared; another calculation waits with edits coalesced until
the cleanup slot is available. `_exit_tree()` joins an outstanding task.

The light propagation algorithm, texture uploads, actor sampling, door
boundaries, slice/discovery behavior and save format are unchanged. This does
not remove cleanup CPU or guarantee a hard frame-time ceiling. It temporarily
retains one retired set alongside the current set, may delay starting a new
calculation under worker contention, and can wait during scene teardown.

## Measurements

Godot 4.7.2 Steam, D3D12 Forward+, Ryzen 7 9800X3D / Radeon RX 9070 XT,
2560×1440, VSync off and uncapped. Runs execute sequentially with isolated
application data and no concurrent tests or exports. Native performance runs
use the standalone editor executable; packaged checks are functional validation,
not an exported FPS comparison.

The 30-dwarf yard has the same fixed mining, construction, hauling and supply
setup before and after. Each pan records at least 20 seconds. This is an
artificial work yard, not a mature colony. Times below are milliseconds.

| Run | Pan | Frame mean | P95 | P99 | Maximum | Lighting mean | Lighting maximum | Frames >50 ms |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| Before | First | 18.121 | 32.732 | 41.861 | 260.739 | 3.240 | 231.491 | 5 |
| After | First | 17.038 | 31.526 | 40.189 | 168.178 | 2.899 | 5.775 | 1 |
| Before | Later | 16.664 | 29.096 | 36.554 | 46.253 | 1.991 | 13.044 | 0 |
| After | Later | 16.603 | 30.424 | 37.188 | 47.874 | 1.765 | 4.269 | 0 |

The first-pan lighting maximum is 97.5% lower. First-pan frame mean is 6%
lower, while later mean is almost unchanged and later P95/P99 are slightly
higher. These are one matched pair, not a claim of a general FPS improvement.
World activity evolves differently: final counts are 176 mined / 12 built /
62 stored before and 181 / 16 / 46 after. Both make progress in all three jobs.
End-of-run active/idle worker counts are 21/9 before and 28/2 after; these are
snapshots, not average wait times. Full assignment and worker samples remain
in the reports.

The remaining 168.178 ms frame contains only **11.052 ms** of measured scene
CPU, including **0.492 ms** of lighting. An analogous 167.595 ms frame appears
before the change. Its cause is unresolved and must be attributed separately.

The copied settlement contains five dwarves, 79 wildlife, 20 furniture pieces
and 19,322 water columns. Each recorded phase lasts at least eight seconds,
with clear weather held constant. Original and fixed code load identical
copied input; this is a newer save than the one used in 188.

| Run | Pan | Frame mean | P95 | P99 | Maximum | Lighting maximum |
|---|---|---:|---:|---:|---:|---:|
| Before | First | 7.687 | 17.683 | 22.075 | 26.397 | 2.874 |
| After | First | 7.797 | 17.365 | 22.728 | 26.966 | 3.063 |
| Before | Later | 7.912 | 17.904 | 22.816 | 29.147 | 3.088 |
| After | Later | 7.868 | 18.266 | 23.070 | 28.168 | 3.183 |

No saved-game pan has a frame over 33.3 ms. Differences are small and mixed;
the heavy buffer-clear trigger is absent here. Paused/static phases are also
retained in the full reports.

## Validation and package

The new `LightingBufferDisposalTest` compares the original and current code
through **eight exact scenarios**, checking published sky samples, tile mapping,
GPU lookup image bytes and every light texture layer. Coverage includes sealed
and reopened entrances, skylights, edits during calculation, door addition and
removal, and pending edits while the sole cleanup slot is held busy.

A controlled large-buffer case puts 250,000 entries in each of six containers.
Original clearing takes **58.715 ms**; transferring those buffers takes
**0.034 ms** on the main thread. Immediate teardown then waits **60.623 ms**
for cleanup. This explicitly confirms the work is moved, not eliminated, and
that teardown joins the worker safely. These controlled timings differ from
the native yard's much larger cache and are not whole-frame measurements.

All **13 distinct fixtures** pass without script/engine errors and with
verified success markers:

- `LightingBufferDisposalTest` (eight exact scenarios and disposal/teardown).
- `RoomRebuildSchedulingTest` (15 exact comparisons), `ConstructionTest`,
  `JobMixedWorldTest` (2,124 lifecycle invariant checks), `HaulingSelectionTest`,
  `NavigationRegressionTest`, `SaveManagerRoundTripTest` and
  `WorldTerrainStartupTest`.
- Native `UndergroundLightingTest`, `DoorLightingTest`,
  `DwarfLimbLightingTest` (32 paired color samples), `RoomLightingTest` and
  `BedroomLightingTest`.

Native captures of the work yard, covered tunnel with/without torches, dark
door face, dwarf skin/limbs and lit room were visually inspected. The fixtures
also check door rotations and animation, sealed-room darkness, daylight,
night, distance fog, room panels and replayed mining.

The native exported PCK loads the copied settlement with five dwarves and 79
animals. A repeated lighting refresh completes, joins cleanup, and preserves
exact sky samples and all **14 texture layers**. Existing checks also pass for
245 construction rejection comparisons, five hauling quotes, offscreen wildlife,
pause and slice concealment. All 79 animals start offscreen and 65 move during
the active interval. A separate release-EXE startup generates its world without
script/engine errors. These are functional checks, not exported FPS measurements.

Windows build:

- Play: `build/windows/releases/20261015-162315-800-7102fe5b/Deepdraft/Deepdraft.exe`.
- Share: `build/windows/Deepdraft-Windows-Playtest.zip` (76.9 MiB).
- ZIP SHA256: `2fbaa791e1ae51d1bb6527ea8cef302654a7d541af9c7aed59938d536055ed0f`.
- Restart Play or launch this release. No save migration or new autoload is
  required; older release directories remain available.

The archive contains only runtime files and matches the tested release byte
for byte. The player's original save still matches the copied input hash.
Historical tracked scratch screenshots were restored after preserving today's
captures in this report's evidence folder. `git diff --check` passes.

## Evidence and reproduction

```powershell
& tools/performance/RunScaling.ps1 -Population 30 -Label lighting_review_30 -Seconds 20
& tools/performance/Run.ps1 -Label lighting_review_save -SavePath <copied-save-path> -Seconds 8 -NoAblations -Weather base:weather:clear
```

Use fresh labels. For a before run, install the frozen original lighting source
in a disposable checkout, then restore the final source before final tests and
export. Never use the instrumented source for a before/after FPS comparison.
`CameraBenchmark.gd` now records the lighting source hash. The initial yard
pair predates that metadata field; frozen source snapshots and the audit record
the versions used.

The diagnostic run completed its measurement phases but its strict runner
failed on two existing dwarf shutdown errors: `_exit_tree` → rest cancellation
→ walking completion → hauling pickup reads a global transform after leaving
the tree (`DwarfAgent.gd:1111/1114`). It is retained for attribution only,
excluded from clean validation and FPS claims. The uninstrumented yard and
copied-save pairs finish without script/engine errors. Common startup warnings
about the deliberately empty initial scene and unseeded pre-world weather are
retained in logs.

The original player save and benchmark input have SHA256
`f223eee6dfe52fefe6add9a763362640f02c439fb2f33687f550661fb9cc148b`.
No benchmark writes to the player's profile.

- [Evidence guide](concepts/lighting_20261015/README.md)
- [Phase comparisons](concepts/lighting_20261015/comparison.json)
- [Exact comparison and disposal timings](concepts/lighting_20261015/disposal.json)
- [Regression results](concepts/lighting_20261015/regressions_results.json)
- [Native lighting results](concepts/lighting_20261015/native_tests_results.json)
- [Packaged settlement checks](concepts/lighting_20261015/packed_packed_smoke.json)
- [Release startup](concepts/lighting_20261015/packed_release_startup.json)
- [Source/package audit](concepts/lighting_20261015/audit.json)

## Next work

Proceed with 189's long-session/event review at **5/20/30 dwarves**: autosave,
arrivals, day/season changes, repeated edits and growing inventories/rooms.
Use a mature settlement and track completed work, assignment waits and memory
alongside frame times. First attribute the remaining wall-frame outlier and
separate startup stalls from recurring hitches. This change does not complete
that review. The diagnostic-only dwarf shutdown issue is recorded above for
a later lifecycle investigation; it is not changed in this performance pass.
