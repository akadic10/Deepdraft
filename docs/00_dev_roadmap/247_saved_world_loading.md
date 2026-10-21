# 247 — Saved-world loading

The small saved colony loaded much more slowly than its matching fresh world.
Its five dwarves were inexpensive to restore; 49,312 final terrain differences
were repeatedly triggering live water simulation, and overview batches repeatedly
copied large, unchanged terrain dictionaries.

## Changes

- SaveManager opens an explicit synchronous water restore context before final
  terrain installation. WaterManager records affected columns, then restores saved
  volumes, active/displaced queues and soil moisture once through its normal owner
  contract. It clears derived soil-kind caches before rebuilding moisture contacts.
  Live edits still displace water, irrigate soil and notify consumers immediately.
- Overview workers reuse immutable terrain/discovery/cut snapshots until input
  invalidation. Replacement waits until the previous batch is consumed; existing
  per-tile revision and global epoch checks still reject stale results.
- Underground lighting gets a 12 ms work budget while the loading cover holds
  simulation, returning to the existing 2.5 ms gameplay budget afterward. Its
  solver and readiness requirements are unchanged.
- LoadPerformance now lists terrain and exploration restoration separately.

The save schema and final-state terrain representation are unchanged. There is
still one final value per changed coordinate, not an edit history.

## Measurements

Sequential Godot 4.7.2 native Direct3D 12 / Forward+ processes, AMD Radeon RX 9070
XT, 1280×720, seed 3968477758. Each saved run uses an isolated copy of the same
12.5 MB quicksave. Time runs from scene startup through actual loading-cover
release, including rendering and lighting readiness.

| Measurement | Original code | Fixed code |
| --- | ---: | ---: |
| Saved world ready to play | 71.510 s | 26.943 s |
| Longest loading frame | 40.015 s | 5.856 s |
| Matching fresh world | 15.681 s (earlier review) | 15.596 s |

The saved load is 44.567 seconds shorter (62.3%). It remains about 1.73 times the
fresh start: terrain materialization and restoration, additional scene objects,
and derived geometry/lighting still require work. This does not eliminate every
loading hitch or establish performance for every settlement or machine.

Headless profiling corroborates the removed work: water's 49,312 block callbacks
fall from approximately 33–35 seconds to 25.458 ms; overview snapshot preparation
falls from 128 copies / 3,137.474 ms to 2 copies / 23.317 ms. The latter two copies
cover initial generation and restored inputs. The optimized profiled load takes
23.400 seconds; CPU counters are not additive wall time.

## Verification

- Native original/fixed runs produce identical serialized colony state, ignoring
  only the new snapshot's wall-clock timestamp.
- Water state after another 20 simulation ticks matches exactly.
- All 1,024 overview tile mesh-array hashes, published lighting samples, and
  lighting lookup/texture byte hashes match exactly between native runs.
- New `WaterTerrainRestoreTest` verifies unchanged provisional flow during bulk
  installation, one final occupancy notification, correct topology, exact active
  and displaced queues, soil moisture and deterministic continuation. It also
  checks that ordinary mining immediately floods a lake breach without losing
  water, and reset clears the temporary restore context.
- New `OverviewSnapshotTest` verifies dictionary reuse and immutable in-flight
  snapshots, mining, designation removal, cave preview/discovery, solid overrides
  and global invalidation.
- TerrainEditBatchTest, WaterFlowTest, WaterFlowCacheTest,
  SaveManagerRoundTripTest, FinalTerrainStateTest, WorldTerrainStartupTest,
  WorldLoadingScreenTest, WaterMeshSchedulingTest and MoistureSchedulingTest pass.
- LightingBufferDisposalTest alternates gameplay/loading budgets and passes eight
  comparisons against its frozen solver, including exact texture bytes. The native
  DoorLightingTest passes. SaveWorkerShutdownTest completes its owned transaction
  and produces the isolated save on exit.

The initial generic headless invocations of RoomLightingTest, DoorLightingTest
and SaveWorkerShutdownTest stopped at their required profile-isolation guards.
Door and shutdown were rerun with their required isolated harnesses and passed.
RoomLightingTest additionally still references retired wall_torch and brazier
fixtures; it was not used as validation for this change. Native full-world mesh
and lighting equality, native doors and the solver differential provide the
rendering checks above.

Evidence, frozen task-start sources, copied input, test logs and benchmark
harnesses are in `tmp/load_fix_20261019/`; the prior review is in
`tmp/load_review_20261019/`. `comparison.json` contains the exact differential and
timings. The original player saves are unchanged. No export or commit.

Restart Play to use the loading corrections.
