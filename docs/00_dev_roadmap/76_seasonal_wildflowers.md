# 76 — Seasonal wildflowers

Implemented 2026-10-08 as step 7 of [72 — Surface details](72_surface_details_plan.md).
Lakeside reeds remain the next milestone.

## Required later use: honey production

**User requirement, 2026-10-08:** these wildflowers must contribute to future
beekeeping and honey production. Nearby blooming clumps should support hive
productivity, giving players a reason to preserve flower patches near their
apiaries. Bees use the living flowers; no flower item or harvesting job is needed.

Seasonal blooming and permanent removal must affect forage supply. Use saved
world records rather than rendered instances, so slicing, streaming and camera
distance cannot alter honey production. Exact forage radius, production effects,
caps, other forage sources and hive competition remain balance decisions for
the beekeeping milestone. The owning design is
[42 — Beehives](../40_economy_colony/42_farming_brewing.md#required-future-connection-wildflower-forage).
No honey production behavior is implemented by this flower milestone.

## Behavior and review

Wildflowers are small, walkable decorative clumps. They have no harvest action,
resource drop, planting loop or navigation obstacle. **Clear plants** replaces
the visible **Clear shrubs** label and selects both shrubs and flowers by click
or rectangle. Shrubs still yield one cutting; clearing flowers yields nothing.
The internal `clear_shrubs` tool ID is retained.

An individual flower inspector offers **Clear flowers**. A worker uses the
existing hand-gathering pose for **1.5 seconds**, configured in JSON. Cancel,
interruption, pause and reload keep partial work. Clearing is permanent; seasons
never regrow removed flowers. Committed construction or loss of the supporting
ground also removes the clump and safely cancels its work, without items.

Use **Menu → Development → DEV: Next flowers** to focus and inspect a generated
clump. It does not clear, reveal terrain or change plant state. Then:

1. Inspect the flowers close up and at normal play zoom.
2. Use the existing DEV season controls to inspect all four appearances.
3. Mark a clump with Clear flowers or Orders → Clear plants. Cancel partway
   through, reissue, and let a worker finish. No crate should appear.
4. Save/load and advance seasons: completed removal persists. Harvest plants
   and Clear stones must ignore flowers; Cancel orders and Undo handle them.

## Art and habitat

`tools/generate_flowers.py` authors **12 GLBs** under
`assets/models/details/flowers/`: three clump shapes, each with four seasons.
Each clump groups four small rooted stems with open ground between them. Cream,
muted heather and straw petals provide restrained accents. Spring has two early
blooms, summer four blooms, autumn dry seedheads, and winter short dormant stems.
Roots, identity, yaw and shape variant remain fixed through appearance changes.

Assets use eight voxels/block, baked 0.125 scale, root scale 1, linear vertex
colors and ground Y0. Maximum envelope is under 1.5×1×1.5 blocks; summer height
is 0.875 blocks and winter height 0.25. Each clump has one logical support tile,
no collider and no per-instance process. Shared meshes/materials and the existing
twelve-per-frame creation queue are used. Flower stems are not separate nodes.

All static settings are in `data/entities/surface_details.json`, loaded solely
by `SurfaceDetailRegistry`. Flower settings:

- Independent salt 76001 and 12-block candidate grid, below shrub/stone priority.
- Y4–70, actual grass or dirt support, moisture 0.15–0.90.
- A broad patch field at frequency 0.018 with zero floor, local density 0.55
  below Y36 and 0.40 above it. This is a starting visual density, not economy tuning.
- Flat, dry 3×3 clearance envelope; a three-block tree margin plus that envelope;
  four-block margins from other accepted details.

Rock, water, steep edges, occupied supports and unsuitable moisture/heights are
rejected. Original tree candidates are respected even before streaming.
Candidate arbitration precedes saved removals, so clearing another detail cannot
create a new flower on reload. There is no terrain smoothing, reserved starting
area, new water body or resource-generation change.

## Ownership

`SurfaceDetailPlacement` now applies authored ground/moisture restrictions to any
definition that supplies them, retaining the existing shrub behavior.
`SurfaceDetailManager` owns seasonal flower models, visual picking, construction/
support displacement, saved work/removal and inspector presentation.

Appended `CLEAR_PLANT` tasks use priority 50 and the existing adjacent work-source
lease. The shared completion path supports an empty item yield without requiring
an item-drop manager. Stone rewards and shrub harvest/cutting paths are unchanged.
The existing `surface_details` save section remains at restore priority 16.
Flower visual refreshes follow the final WorldClock season when loading.

## Verification

- **FlowerPilotTest, headless/native:** all twelve imported models grounded and
  within the envelope; fixed origins/variants/yaw; walkability and no colliders;
  inspector/action filtering; real worker routing and hand pose; pause, interrupt,
  cancellation, active/cancelled restore, seasonal changes during work, no yield,
  duplicate completion rejection, persistent removal, support/building displacement,
  and slice visibility/order exclusion. Native worker reference includes a dwarf
  and one-block cube.
- **OrdersShelfTest, native:** actual flower mesh click, mixed shrub/flower area
  clearing, stone/harvest exclusion, partial-work Undo, cross-tool receipts,
  Cancel orders and the renamed six-tile shelf at 960/1280/2560 widths.
- **SurfaceDetailLayoutTest:** eight seeds, forward/reverse candidates, fresh
  owner restore, terrain/tree fingerprints, suitable dry flower envelopes,
  detail gaps, exact preserved stone/shrub populations and removed flower identity.
- **SaveManagerRoundTripTest:** full-scene manual save, autosave and corrupt-primary
  backup recovery with removed, active-partial and cancelled-partial flowers;
  complete owner snapshots compare equal after load.
- **ShrubPilotTest:** seasonal berry/cutting behavior, guaranteed cutting yields,
  interruption, item persistence and actual hauling still pass.
- **BoulderPilotTest / ScreePilotTest:** stone work, rewards, release, occupancy
  and persistent removal still pass after the shared completion-path change.
- **FlowerLivePreview:** real generated world, actual DEV menu/inspector, clear
  and cancel tools, seasonal swaps, close/play/wide native captures.

| Seed | Flower clumps | Full detail layout + registration, ms |
|---|---:|---:|
| 0 | 914 | 431.0 |
| 1 | 835 | 444.7 |
| 2 | 850 | 466.4 |
| 7 | 974 | 487.2 |
| 42 | 793 | 467.2 |
| 1234 | 804 | 466.0 |
| 65535 | 908 | 504.8 |
| 20261007 | 933 | 493.5 |

Layout times exclude visual creation and cover all surface details. Populations
are naturally sampled, not forced guarantees. The maximum sampled flower
support coverage is below 0.1% of the 1024×1024 map, with gaps between clumps.

Evidence lives in `tmp/flower_review/`: `seasonal_art.png`, `worker_scale.png`,
`orders_flowers.png`, `world_orders.png`, all four seasonal close views,
`world_play_zoom.png`, `world_wide_zoom.png`, `layout_report.json` and test logs.
All runs use isolated APPDATA/LOCALAPPDATA. Art and game screenshots were reviewed
in the native renderer. `FlowerLivePreview --baseline` compares the same camera,
seed and seasonal-cache warmup with flowers omitted from its temporary registry;
live JSON is never changed by that comparison.

## Performance sample

Sequential native runs, seed 1234, 1600×1000, paused summer scene, same target
(521.5, 36, 487.5), with identical seasonal-cache warmup. Ninety frames per view:

| View | Flowers absent / present | Median frame, ms | P95 frame, ms | Draw calls | Rendered objects |
|---|---|---:|---:|---:|---:|
| Play zoom 100 | Absent | 8.238 | 8.828 | 174 | 308 |
| Play zoom 100 | Present | 8.135 | 9.084 | 183 | 324 |
| Wide zoom 180 | Absent | 8.233 | 8.992 | 206 | 449 |
| Wide zoom 180 | Present | 8.217 | 9.022 | 217 | 492 |

The full detail layout takes 375.6 ms without flowers and 468.8 ms with flowers
in this matched seed (visual creation excluded). There are 804 flower clumps,
each using three lightweight nodes for a total of 2,412 flower visual nodes.
At wide zoom, renderer-reported video memory differs by about 23.9 MiB and
engine static memory by about 11.4 MiB; these are whole-run deltas, including
small inspection/cache differences, not isolated allocation accounting.
The twelve source GLBs total 337,964 bytes; see `asset_manifest.json`.

These views run near the display frame cap, so they do not establish uncapped
GPU headroom or an FPS guarantee. Results cover two cameras on one seed and
are sufficient for this restrained starting density. Larger populations,
region batching and combined reed/flower costs remain later performance work.
Detailed samples: `live_report.json` and `baseline_report.json`.
