# 73 — Surface-detail foundation and boulder pilot

Status: **boulder pilot and Orders accepted by the user, 2026-10-08.** This implements
the first milestone of [72 — Surface details](72_surface_details_plan.md).
[74 — Gatherable scree](74_gatherable_scree.md) now implements the next milestone
and renames the shared Orders tool to **Clear stones**. Shrubs, flowers and reeds
remain planned. The implementation history below records the boulder pilot.

## Playtest

1. **Project → Reload Current Project** after this update: the project now has
   a `SurfaceDetailRegistry` autoload. Then run the normal debug-world scene.
2. Choose **Menu → Development → DEV: Next boulder**. This cycles through the
   generated stones, restores full-world view, focuses the camera and opens
   Object explorer. It does not designate, remove or reward anything.
3. Select **Clear boulder** in the inspector, or **Orders → Clear stones** to
   click individual stones or drag a ground rectangle around several. The live
   banner shows the selected count; mouse release confirms the designation.
   With a settlement and an available worker nearby,
   the worker walks to a reachable side and breaks it using the mining pick.
   Distant or isolated shelves still require a route; the locator is not a
   worker teleport. A pick marker remains while the order is active.
4. Try **Orders → Cancel orders**, the inspector's **Cancel clearing**, or
   **Undo last order**, then reissue partway through; completed work is retained.
   The finished stone yields **two Rough Stone** items and opens its footprint.
   Save/load preserves removal, designation and partial work.

Ordinary world clicks also inspect stones. Initial density is deliberately low;
these are occasional obstacles, not a new continuous terrain layer. Shape,
size and density should be reviewed before adding more surface clutter.

## Implementation boundaries

### Orders follow-up (2026-10-08)

The user approved an explicit **Clear boulders** tile alongside Mine blocks,
Chop trees and Cancel orders. The four tiles stay on one row; compact layouts
wrap the Clear boulders / Cancel orders labels within their tiles.

`TreeFellingController` now shares its established surface-selection gesture
between trees and boulders. The scene wires its `details_path` to
`SurfaceDetailManager`; the same manager APIs serve menu orders and inspection.
Clicks use normal terrain-occluded object picking. Ground rectangles include
visible boulder footprint centres, exclude sliced/removed/streamed-out visuals,
and refresh the preview count every 0.08 seconds plus at commit. The marquee
reprojects every frame while the camera moves. Escape, tool changes, focus loss
and release over UI discard unfinished gestures.

Cancel orders can click a marked boulder or cancel blocks, trees and boulders in
one screen rectangle. It only cancels work, retaining partial progress and the
stone itself. Undo receipts contain the live source identity, so re-marking or
loading the same ID cannot let an old Undo cancel a new job. Receipts also retain
their correct owner when changing tools. View order exits the tool and opens the
normal boulder inspector. No new autoload, class name, input binding or save
schema was introduced for this follow-up.

`OrdersShelfTest.gd` now exercises all of these with real GUI/world input,
including mixed cancellation of all three work types, repeat/reverse selection,
partial-work preservation, stale receipts after restore and compact layouts.
Its synthetic flat world now initializes the waterline map required by the
earlier world-generation changes. Passing headless/native logs are
`tmp/boulder_review/orders_fixed.log` and `orders_native.log`.
`TreeFellingTest.gd` and `BoulderPilotTest.gd` also pass (`tree_orders.log` and
`pilot_orders.log`). Native captures include
`tmp/boulder_review/orders_rectangle.png` and the responsive views under
`tmp/orders_review/`. `BoulderLivePreview.gd -- --orders` additionally checks the
normal scene's menu/owner wiring, designation and cancellation on a generated
boulder, saving `tmp/boulder_review/world_orders.png`.

### Placement, work and persistence

- `SurfaceDetailRegistry` is the sole reader of
  `data/entities/surface_details.json`. Models, seed salt, spacing, height,
  patch/density settings, footprint and clearing rewards live there.
- `SurfaceDetailPlacement` uses immutable generated heights and water masks,
  independently salted jitter/presence/model/yaw and a broad patch field.
  Stable IDs contain category, world seed and scatter-cell coordinates.
- `SurfaceFloraSpawner.generated_tree_candidate()` extracts the existing tree
  selector without changing its arithmetic or spawn behavior. Detail placement
  checks those candidates across neighboring cells, including chunk borders,
  before any tree visuals need to exist. Tree removals do not later create new
  boulders. The current tree margin is conservative, not an exact canopy mesh test.
- Each 24-block detail cell has one possible stone, with a five-block inset.
  The two-block footprint and its three-block surrounding ring must all lie on
  the same dry surface height. The layout rejects cliff lips, thin shelves and
  tree conflicts instead of flattening terrain. Elevation at Y36 separates the
  pilot's upland/lowland density weights; this is not regional geology.
- `SurfaceDetailManager` owns the scene records and saved deltas. All accepted
  footprints register before visual spawning (12 visuals/frame). Visibility,
  camera position and season do not change navigation. The small pilot keeps
  its visuals resident; larger categories need separate instance/performance
  decisions as they are added.
- Boulders occupy a 2×2 footprint, two cells high, in `PlacedEntityRegistry`.
  Their physics boxes use layer 2, never the camera's terrain layer 1. This is
  a solid-stone exception, not permission to add plant-overhang collision.
- `CLEAR_BOULDER` is a first-class priority-50 work type. It shares the adjacent
  lease, alternative-side routing and release protocol of `TreeFellingComponent`,
  with a separate removed-state key. The dwarf uses the pick pose and stone
  impact feedback. Dwarf inspection/roster text describes clearing stone.
- Seven simulation seconds complete a stone. One lease/reservation belongs to
  each player designation; interruption, sleep and cancellation retain work.
  A tombstone is committed before rewards, preventing repeat yields on reload.
- Terrain support loss or terrain added inside a stone removes it and releases
  active work immediately, without loot. Ordinary building respects occupancy;
  committed/restored structure overlaps win over detail. Replacing support or
  removing a structure does not resurrect a tombstoned stone.
- Save section `surface_details`, priority 16, restores after mined terrain and
  tree state, before furniture/items/dwarves. Only stable IDs, removal reasons,
  designations and work seconds are saved. Nodes, occupancy handles, task IDs,
  reservations and runtime block IDs are reconstructed.
- The generic inspector, slice visibility, underground-lighting material and
  CanvasLayer markers are reused. No terrain block represents a prop.

The terrain generator, lake levels, rough cliffs/shores, summit guarantees,
caves and ore fields were not modified. No starting area is reserved.
The current placement helper supports the boulder pilot; nonblocking displacement,
species habitats and arbitration between additional detail categories will be
implemented with those categories rather than declared complete in advance.

## Asset manifest

Generator: `tools/generate_boulders.py`, using the shared voxel GLB writer.
Eight voxels/block, **0.125 scale baked into positions**, root scale 1.0,
centered X/Z, ground at Y0. Exported `COLOR_0` is linear, converted from the
authored display palette. Runtime material stays lit, rough and double-sided.
Godot generates import metadata; none is hand-edited.

All assets are under `assets/models/details/boulders/`:

| Asset | Actual bounds X / Y / Z | Size in blocks | Role |
|---|---|---|---|
| `boulder_1.glb` | −1…1 / 0…1.5 / −1…0.875 | 2 × 1.5 × 1.875 | Broad broken shoulder |
| `boulder_2.glb` | −1…1 / 0…1.375 / −1…1 | 2 × 1.375 × 2 | Low layered mound |
| `boulder_3.glb` | −1…1 / 0…1.75 / −1…0.875 | 2 × 1.75 × 1.875 | Taller asymmetric stone |

Each has four seeded quarter-turn orientations. The total source GLBs occupy
about 542 KiB; visuals share three imported meshes and the world material.
Large boulders, snow variants and clusters with multiple stones per cell remain
possible art follow-ups, not requirements for this pilot.

## Verification

**PASS — `BoulderPilotTest.gd`:** actual scheduler/DwarfAgent execution, imported
mesh picking and bounds, inspector actions, correct pick tool and worker labels,
navigation obstruction, idempotent designation, pause, interruption, sleep,
cancellation/resumption, JSON restore of active/cancelled/removed states,
exactly two stone drops, no replay/resurrection, support loss during active work,
restored support, season continuity, slice-hidden occupancy, blocked-side retry,
opening one work side and committed structure overlap.

**PASS — `SurfaceDetailLayoutTest.gd`:** eight real terrain maps, full detail
candidate scans in forward/reverse order, identical regenerated records on a
fresh owner, partial-job reconstruction, immutable terrain/tree fingerprints,
existing summit/layout validation and valid live support/occupancy.

| Seed | Boulders | Lowland | Upland | Layout + occupancy, ms |
|---|---:|---:|---:|---:|
| 0 | 81 | 41 | 40 | 26.3 |
| 1 | 83 | 37 | 46 | 31.0 |
| 2 | 64 | 28 | 36 | 37.0 |
| 7 | 76 | 48 | 28 | 25.9 |
| 42 | 62 | 20 | 42 | 24.3 |
| 1234 | 58 | 22 | 36 | 35.5 |
| 65535 | 77 | 33 | 44 | 28.4 |
| 20261007 | 51 | 27 | 24 | 26.9 |

These are startup costs on the development machine, excluding visual creation,
not FPS guarantees. Full rejection counts and fingerprints are in
`tmp/boulder_review/layout_report.json`. The pilot's small instance count is not
a performance proxy for future flowers/reeds.

**PASS — `TreeFellingTest.gd`:** existing chopping, side routing, sleep/resumption,
markers, seasonal changes, save state, timber drops and hauling still work after
sharing the clearing executor.

**PASS — `SaveManagerRoundTripTest.gd`:** normal game scene and actual save/reload,
autosave and backup recovery, with removed, designated/partial and cancelled/partial
boulders added to its full scene-state comparisons. This checks the save owner
order, not just isolated serialization.

**PASS — native `BoulderLivePreview.gd`:** normal world scene at seed 1234, normal
terrain/flora/lighting, development-menu routing and explorer selection. Native
captures inspected after fixing the initial palette's color-space conversion:

- `tmp/boulder_review/pilot.png` — all three assets beside a working dwarf.
- `tmp/boulder_review/world_close.png` — placed stone near a rough cliff.
- `tmp/boulder_review/world_play_zoom.png` — wider gameplay context.

All test processes use separate `APPDATA`/`LOCALAPPDATA` folders beneath
`tmp/boulder_review/`; user save files are not used. Logs contain no script errors.
Use the installed Godot executable with `--headless --path P:\Deepdraft --script`
and the relevant `res://scripts/tests/...gd`; use native rendering (no
`--headless`) for `BoulderPilotTest.gd -- --capture` or the live preview tool.

## Next

The user accepted boulders and their Orders tool. Gatherable scree is now live
in [74](74_gatherable_scree.md). Review scree, then proceed to shrubs, flowers
and reeds as separate milestones.
