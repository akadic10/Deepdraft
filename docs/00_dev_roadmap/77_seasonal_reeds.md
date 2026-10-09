# 77 — Seasonal lakeside reeds

Status: **live, 2026-10-08.** The fifth surface-detail category in
[72 — Surface details plan](72_surface_details_plan.md).

Short and tall reed clumps grow on suitable dry lake and tarn banks. They have
four seasonal appearances, remain walkable, and can be permanently removed with
**Clear reeds** in Object explorer or **Orders → Clear plants**. Clearing takes
1.5 seconds of hand work and yields no items. Cancelled work is retained;
construction and support loss also remove the clump without rewards.

## Quick playtest

Use **Menu → Development → DEV: Next reeds** to focus and inspect a real
generated clump. The locator does not modify terrain, clear reeds or grant items.

1. Check the roots and nearby water at close and ordinary play zoom.
2. Use the DEV season controls to compare all four appearances.
3. Clear one clump or drag **Clear plants** across several plants. Cancel, Undo
   and reissue; then let a worker finish. No loose item should appear.
4. Save/load and change seasons: removed reeds stay removed. Harvest plants and
   Clear stones ignore reeds.

There is no forced reed count or guarantee at every tarn. A sparse first pass
leaves most banks open; density can be reviewed with the other surface details.

## Assets and data

`tools/generate_reeds.py` produces eight GLBs in `assets/models/details/reeds/`:
two heights × spring, summer, autumn and winter. Four rooted stems per clump
have ascending blades and visible gaps. Spring has fresh green shoots; summer
adds brown seedheads; autumn uses straw/gold; winter retains fewer dry blades.

Models use eight voxels/block, baked 0.125 scale, root scale 1, linear vertex
colors and ground Y0. Both shapes fit a 1.5×2×1.5-block envelope, supported by
one logical tile. Overhangs have no colliders. Each visual uses the existing
shared meshes/materials and twelve-per-frame creation queue; individual stems
are not nodes and clumps do not process independently.

All authored settings live in `data/entities/surface_details.json`, loaded only
by `SurfaceDetailRegistry`:

- Salt 77001, six-block candidate grid, priority 5 below all established details.
- Y4–114, actual grass/dirt/rock support; rock permits low shelves beside tarns.
- Local density 0.85 multiplied by a patch mask, frequency 0.04 and zero floor.
- Flat, dry 3×3 envelope; two-block tree margin plus the envelope; four-block
  separation from other accepted detail footprints.
- At most four horizontal blocks from actual water, using Manhattan distance.
  The support block is 0–2 Y levels above that water body's local waterline.

`SurfaceDetailPlacement.shore_info()` uses the bank mask only to cheaply reject
distant candidates. It then checks nearby generated water blocks and their
individual waterlines. Wet columns, high cliff tops above water, submerged
supports and uneven envelopes are rejected. No fixed Y18 assumption is used.
The immutable record keeps the chosen water column, level, distance and body
type for diagnostics. Terrain and water generation are not modified.

## Shared behavior

Flowers and reeds share seasonal-array selection and `CLEAR_PLANT` hand work.
Inspector descriptions, clear labels and working activity names come from JSON.
The existing six Orders tiles remain; the internal `clear_shrubs` tool now covers
shrubs, flowers and reeds. Only shrubs provide their existing cutting yields.

The manager keeps the same `surface_details` save section and small persistent
deltas. Candidate arbitration precedes saved removals, so clearing a nearby
object never creates previously rejected reeds on reload. Season changes affect
only appearance. Construction, support loss, slicing, picking and restoration
use the established surface-detail lifecycle.

## Verification

- **ReedPilotTest, native:** reuses the decorative-plant lifecycle fixture from
  FlowerPilotTest. All eight imported assets are grounded and within bounds;
  stable origin/yaw/variant, no colliders and walkable support; actual worker
  routing, hand pose and reed activity; pause, interruption, cancellation,
  partial restore, seasonal swaps, completion without loot, duplicate-completion
  rejection, persistent removal, building/support displacement and slice checks.
- **OrdersShelfTest, native:** real reed mesh picking, mixed shrub/flower/reed
  rectangle clearing, correct task types, partial-work Undo, cross-tool receipts,
  Cancel orders and stone/harvest exclusion. Responsive shelf checks still pass.
- **SurfaceDetailLayoutTest:** eight seeds in forward/reverse order and fresh
  owner restore; actual water blocks/local levels; dry envelopes, spacing and
  high/underwater rejection; preserved removals. Terrain/water/tree fingerprints
  and exact previous boulder, scree, shrub and flower populations match.
- **FlowerPilotTest, ShrubPilotTest, BoulderPilotTest and ScreePilotTest:** shared
  lifecycle and previous harvest/clearing behavior still pass.
- **ReedLivePreview:** native game scene, real DEV locator, clear/cancel input,
  seasonal swaps, close/play/wide views, lowland lake Y18 and tarn Y54.
- **SaveManagerRoundTripTest:** removed, active-partial and cancelled-partial
  reeds survive full-scene manual save, autosave and corrupt-primary backup
  recovery; complete owner snapshots compare equal after each load.

| Seed | Lake clumps | Tarn clumps |
|---|---:|---:|
| 0 | 15 | 3 |
| 1 | 9 | 0 |
| 2 | 6 | 2 |
| 7 | 11 | 0 |
| 42 | 17 | 3 |
| 1234 | 14 | 1 |
| 65535 | 10 | 0 |
| 20261007 | 4 | 0 |

Counts reflect natural acceptance, not quotas. Zero tarn reeds can mean no tarn
or no accepted habitat. Native evidence and logs are under `tmp/reed_review/`,
including `seasonal_art.png`, `worker_scale.png`, `orders_reeds.png`,
`world_orders.png`, four seasonal close views, `world_tarn.png`, play/wide views,
`asset_manifest.json` and `layout_report.json`. Runs use isolated APPDATA and
LOCALAPPDATA; the user's game saves and settings are not used.

## Performance sample and follow-up

Sequential native runs, seed 1234, 1600×1000, paused summer, matching seasonal
cache warmup and camera targets. Ninety frames per view:

| View | Reeds | Median frame, ms | P95 frame, ms | Draw calls | Rendered objects |
|---|---|---:|---:|---:|---:|
| Lake, zoom 100 | Absent | 8.191 | 12.699 | 101 | 208 |
| Lake, zoom 100 | Present | 8.186 | 8.894 | 105 | 212 |
| Map center, zoom 180 | Absent | 8.296 | 9.368 | 217 | 492 |
| Map center, zoom 180 | Present | 8.242 | 8.882 | 217 | 492 |

Fifteen clumps add 45 visual nodes. Full detail layout/registration measured
500.9 ms without reeds and 562.9 ms with reeds, excluding visual spawning.
Renderer memory differs by about 19.4 MiB and engine static memory by 2.9 MiB
at the final view. These are whole-run deltas including inspection/camera/cache
differences, not isolated reed allocations. Near-cap frame timings and the
baseline's higher P95 do not imply reeds improve performance. No reeds are
visible at the central wide view. Detailed measurements are in
`live_report.json` and `baseline_report.json`.

The combined surface-detail density, readability and performance review is now
recorded in [78](78_surface_detail_review.md), including independent seeds and
matched scenes with all details disabled. Reed/fiber crafting, underwater planting and reed regrowth
remain future work. The required flower/honey connection stays recorded in
[42 — Beehives](../40_economy_colony/42_farming_brewing.md#required-future-connection-wildflower-forage).
