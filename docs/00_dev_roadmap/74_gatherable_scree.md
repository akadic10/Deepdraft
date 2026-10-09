# 74 — Gatherable scree

Status: **live, 2026-10-08; ready for visual review.** Boulders and their Orders
tool were accepted by the user. This implements step 5 of
[72 — Surface details](72_surface_details_plan.md), revised with the user's
approval from decoration to useful loose-stone gathering. Shrubs, flowers and
reeds remain the next separate milestones.

## Playtest

1. Restart the game and choose **Menu → Development → DEV: Next scree**.
   This cycles through generated clumps and opens **Loose stones** in Object
   explorer. If a canopy obscures one, cycle again or rotate the camera.
2. Choose **Gather stones**, or **Orders → Clear stones** to click a clump or
   drag across several. That tool also retains boulder clearing. The count is
   the number of clumps/boulders selected, not their eventual item yield.
3. With a nearby settlement and an available worker, a reachable clump takes
   **three simulation seconds** to gather by hand and yields **one Rough Stone**.
   Boulders still take seven seconds with a pick and yield two stones.
4. Cancel through the inspector, **Cancel orders**, or **Undo last order**.
   Reissuing preserves partial work. View order opens the normal inspector.
5. Walk through a clump, collect it, and save/load. Scree never blocks movement;
   gathered clumps stay gone. Construction and mining can displace scree without
   granting free stone; removed support/structures do not regenerate it.

No new autoload or global script class was added. New GLBs use ordinary Godot
import; no manual scene wiring or import-setting changes are required.

## Placement and assets

- Three dedicated low stone groups, five or six stones per clump, with open
  ground between stones. No boulder or inventory mesh is enlarged/reused.
- One seeded candidate per 10-block cell, broad patch noise and independent
  distance falloff create sparse broken clusters. A dry, flat 3×3 footprint
  must have nearby terrain at least four blocks higher, within seven sampling
  steps from its edge. A ray crossing water, lower ground or an intervening
  smaller step is rejected. Flat tops and unsupported cliff faces are excluded.
- Existing immutable tree candidates take precedence. Base boulders are resolved
  before scree, then stable IDs resolve ties. The overlap pass happens before
  saved removals, so clearing an obstacle never creates new scree on load.
- JSON owns density, habitat limits, category priority, blocking, model paths,
  work duration and yield. `SurfaceDetailRegistry` remains the sole definition
  loader. The generated terrain, lakes, cliffs, caves and ore fields are untouched.
- One scene node and imported shared mesh per interactive clump, no physics
  body/collider and no `PlacedEntityRegistry` occupancy. Visuals populate under
  the existing 12-per-frame budget; clumps have no individual process callbacks.

Generator: `tools/generate_scree.py`, shared voxel GLB writer, eight voxels per
block and 0.125 baked scale. Root scale 1, ground at Y0, linear `COLOR_0` using
the lit world material. Godot-generated import files are never hand-edited.

| Asset under `assets/models/details/scree/` | Imported size X / Y / Z |
|---|---|
| `scree_1.glb` | 2.375 / 0.375 / 2.25 |
| `scree_2.glb` | 2.375 / 0.5 / 2.5 |
| `scree_3.glb` | 2.625 / 0.375 / 2.5 |

All footprints use the same three-block support envelope at any quarter-turn.
Every constituent stone touches the ground; terrain is never flattened to fit.

## Work, removal and presentation

`GATHER_SCREE` is an appended priority-50 task type. It reuses the adjacent-side
work source, reservation/retry/release and owner-progress contract of boulders
and trees. The dwarf uses a two-handed gathering reach without an axe, pick,
mining chips or chopping sounds. Inspection and roster text name gathering.
Rewards enter the existing loose-item/hauling pipeline on completion.

The detail owner commits removal before dropping the reward. Support loss and
committed occupancy changes retire the source and remove the visual without
loot. Nonblocking details still listen for construction overlaps; registering a
boulder's own occupancy does not accidentally remove that boulder.

The existing `surface_details` save section stores stable category/seed/cell IDs,
removed flags/reasons, designation and work seconds. Restoring now recognizes
both boulder and scree categories with their own work limits. Sources, occupancy
handles, visual nodes and task IDs are reconstructed. Seasons and slicing do
not change identities or resurrect removals.

The renamed **Clear stones** tool uses the existing ground marquee and refresh
rules. Receipts keep live-source identity for safe Undo after cancel/reissue,
load and tool changes. Cancel orders includes both types. Inspection/picking
still respects intervening terrain and other objects; the DEV locator selects
a target directly for inspection without gathering it.

## Verification

**Pass — `ScreePilotTest.gd` headless and native:** imported bounds, exact mesh
picking without colliders, walkability of every support cell, inspector actions,
actual scheduler and dwarf execution, hand pose, configured duration/yield,
pause, interrupt, sleep/resume, cancellation, restored active/partial work,
single reward, persistent removal, mining support loss, season/slice behavior,
and committed construction displacement. Native stage: `tmp/scree_review/pilot.png`.

**Pass — `SurfaceDetailLayoutTest.gd`:** eight generated maps, forward/reverse
candidate order, fresh-owner restoration, partial boulder work and removed
scree, dry support and nearby higher terrain, no overlapping scree, preserved
terrain/tree fingerprints, original boulder populations and world-layout checks.

| Seed | Scree clumps | Boulders | Combined layout + registration, ms |
|---|---:|---:|---:|
| 0 | 205 | 81 | 171.4 |
| 1 | 183 | 83 | 180.0 |
| 2 | 227 | 64 | 197.0 |
| 7 | 180 | 76 | 197.3 |
| 42 | 208 | 62 | 177.6 |
| 1234 | 192 | 58 | 186.5 |
| 65535 | 140 | 77 | 178.6 |
| 20261007 | 170 | 51 | 180.8 |

These are startup measurements on the development machine, excluding visual
creation; they are not FPS guarantees. Three meshes are shared by the scree
instances. Larger vegetation populations will need their own rendering budget.
Detailed rejection counts: `tmp/scree_review/layout_report.json`.

**Pass — `OrdersShelfTest.gd` headless/native:** the prior boulder controls plus
actual scree clicks, mixed boulder/scree rectangles, counts, Undo across modes,
cancellation preserving partial work, slice exclusion and responsive layouts
at 960×540, 1280×720 and 2560×1440. The mixed-drag fixture ends above the tool
banner, preserving the intended cancel-on-release-over-UI behavior.

**Pass — `BoulderPilotTest.gd`, `TreeFellingTest.gd`, and
`SaveManagerRoundTripTest.gd`:** boulder/tree work regressions and full-scene
save/load/autosave/backup recovery, including removed, active-partial and
cancelled-partial scree alongside the existing boulder states.

**Pass — `BoulderLivePreview.gd -- --scree --orders`:** real scene, DEV locator,
normal picking/designation/cancellation, and inspected native captures
`tmp/scree_review/world_orders.png`, `world_close.png`, `world_play_zoom.png`.
The preview cycles past canopy-occluded examples to inspect an exposed clump;
it does not bypass ordinary world-picking occlusion. Generated clumps are small
and localized, with exposed ground and rough cliffs remaining readable.

All final logs under `tmp/scree_review/` are free of script errors. Tests use
isolated `APPDATA` and `LOCALAPPDATA` below that directory, never player saves.

## Next

Review the size, visibility and density in play. Then proceed to **shrubs and
ground cover**: elderberry, blueberry and wild strawberry. Harvesting/regrowth
and berry food production still require a separate gameplay decision.
