# 174 — Mining furniture access

The player moved a bed away from a wall but the existing mining zone continued
to report two blocks left, zero faces and no reachable worker after three retries.

Navigation correctly removed the bed's occupied cells. The mining component,
however, retained its cached empty list of workable blocks. The controller only
refreshed that list for terrain changes, so furniture movement never refreshed
the mining candidates. Repeated scheduling could also retain an empty route
goal list and worker rejection/backoff state.

The mining controller now listens to placed-entity occupancy changes. Nearby
zones invalidate their cached work positions immediately, and a deferred batch
refreshes their pending targets after all footprint updates have completed.
This handles removal and installation in the same frame without the terrain
hook's timing throttle discarding the removal. The existing order retry API
clears stale route plans, worker rejections, backoff and attention state, with
the journal reason “Nearby obstruction changed”. Active leases retain their
worker ownership; distant orders retain their retry state.

Standing clearance, mining reach, voxel identity, selected blocks and completed
work are unchanged. Loading an existing save recomputes the live work positions;
no migration or replacement designation is required.

## Verification

- `MiningFurnitureAccessTest` reproduces the failure before the fix: navigation
  becomes walkable after bed relocation but the zone stays at zero faces and
  neither block is mined. After the fix it checks three blocked retries, an
  attention-paused lease, same-frame removal/installation, rapid re-obstruction
  and removal, an unaffected distant order, both actual block removals and work
  ownership consistency.
- `MiningAnimationTest`, `MiningLedgeAccessTest`, `LadderMiningTest`,
  `FurnitureMoveTest`, `NavigationRegressionTest` and `JobLifecycleTest` pass.
  Minimal test scenes emit the existing missing-sky-environment warning; no
  script errors occur in the passing runs.
- `tools/windows_playtest/ReviewMiningBed.gd` loads a copied player quicksave
  through the actual dock, seed 2520450404. The two remaining targets are
  `(646,47,460)` and `(647,47,460)`, above the room floor at Y43. The saved bed is
  already at `(642,43,461)`, yaw 3, and a fresh load sees both work faces.
  In the isolated copy, the review restores the old obstructing bed position
  `(645,43,461)`, verifies zero faces and three blocked attempts, then issues a
  real Move order to the player's new position. The worker packs the bed,
  mines both blocks from the exposed room-side floor, and finishes relocating
  the bed. Both voxel removals and lease ownership checks pass. Terrain is not
  edited by the harness, and mining follows normal scheduling and swings.
- Native screenshots record [blocked work](concepts/174_mining_furniture_access/blocked.png),
  [resumed mining](concepts/174_mining_furniture_access/mining.png) and
  [completion](concepts/174_mining_furniture_access/finished.png).
  [Review results](concepts/174_mining_furniture_access/copied_save_review.json)
  show `faces_after_move: 0` because mining finished before the final bed
  installation; `blocks_removed` and `mining_finished` are both true.

All tests use isolated APPDATA. The player's original save files are read only.

## Windows playtest

Historical build produced for this fix:
`build/windows/releases/20261013-211518-239-0f154074/Deepdraft/`.
The share ZIP at this milestone had SHA256
`388A2344EA6A115751D398E480179B14AF3AA866B4C286479744F9E820495355`.
It has since been refreshed with the limb-lighting fix; use
[176 — Session handoff](176_session_handoff_2026_10_13.md) for the current
release and ZIP hash.
The pack audit loads all 41 furniture models, including all three door widths.
The exported Windows game starts, generates its world and exits cleanly with
no warnings or errors in its captured output.
Launch the new EXE and load the existing save; extract the ZIP to a new folder
when distributing it. Previous playable directories are not overwritten.
