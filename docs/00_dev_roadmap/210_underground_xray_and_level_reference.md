# Underground X-ray and lower-level reference

Performance follow-up: [218](218_xray_performance.md) removes redundant physical
cavity rebuilds, retains Full/Flat meshes when switching modes, and limits
water-only updates to water geometry. It includes copied-save measurements at
7680×2160 and additional mesh-retention regressions.
The [slice-cache follow-up](219_xray_slice_cache.md) also retains unaffected
chunks and reuses recent slice variants across Slice and X-ray Off/On toggles.

2026-10-17. The player needed to align an upper room and constructed stairs with
an excavated room below. The implementation follows the reviewed Stonehearth
Full/Flat idea, while keeping Deepdraft's slice controls available for working
between levels. It supersedes the mutual-exclusion proposal in 11.

## Player workflow

1. Show the lower room at its usual slice height and enable **X-ray**, beside
   the bottom-right slice tower. The first activation pins that height.
2. Choose **Full** for floors and full walls, or **Flat** for floors and low
   wall sections. Flat requires the normal three-block floor clearance; it
   does not collapse multiple floors onto one height.
3. Use **Pin this level** whenever changing the reference, then raise the slice
   with the existing arrows or shortcuts. Dashed cyan outlines mark the pinned
   lower room's perimeter and stair-height boundaries at the same X/Z coordinates
   on the current plane. **Lower level** toggles the guide independently.
4. Open mining or construction. Normal terrain and targeting return at the
   current work slice, with the lower outline retained. Closing the tool resumes
   the chosen Full/Flat inspection. Other placement tools follow the same rule.

The reference selects the highest discovered floor in each column at or below
the pinned height. It appears only above that height. It marks boundaries rather
than restoring an individual-voxel grid, has no collision or picking, and cannot
create designations. Guides cover the nearby camera area (160-voxel radius,
chunk-aligned); panning refreshes them. Ordinary mining/construction permissions,
resource costs, dwarf reach and navigation are unchanged.

## Ownership and rendering

- `InteriorTracker` remains data-only, derived from mined space and discovered
  caves. Solid construction removes occupied air and invalidates neighboring
  chunks. Queries use underlying terrain, so flooding does not erase discovery.
- Scene-owned `XrayController` builds a discovered interior shell incrementally
  through `XrayGeometry`. Full emits facing walls and supported floors, with no
  ceilings. Flat emits supported floors with headroom and one-block wall strips.
  Construction floors retain their authored face geometry/material colours.
- Inspection uses camera layer 19. Existing terrain remains available for
  shadows and simulation; only camera visibility changes. Known furnishings and
  actors retain normal animation/slice visibility and gain the inspection layer.
  Outside geometry does not intercept inspection clicks. Terrain selection
  follows emitted faces, excluding hidden wall tops and floor undersides.
- Broad outdoor water/moisture batches are omitted. Known interior pools have
  still surfaces at live fractional water heights, updated from water changes.
  Individual water stones remain eligible for normal interior visibility.
  This does not revise normal water appearance or simulation.
- The inspection camera has a dark background and a modest terrain readability
  floor. Its prior environment/mask restore while working, on exit, and during
  scene teardown. Normal room darkness and lighting remain unchanged.
- Mesh and reference assembly share a soft 2.5 ms per-frame budget; static
  visual filtering uses 1.2 ms. Mesh uploads remain atomic. No broad settlement
  performance claim is made. Tuning lives in `data/ui/time_slice.json`, loaded
  through the existing UI registry.
- `TimeSliceHUD` presents the controls. X-ray mode and reference are transient;
  existing saved slice height/state and save schema are unchanged. There is no
  new global class or autoload.

## Verification

Native Godot 4.7.2 / Forward+ / D3D12 source tests pass:

- `XrayViewTest`: generated-world stacked rooms and five constructed steps;
  Full/Flat differences; pinned projection at the working plane; lower-floor
  picking through hidden rock; hidden-prop exclusion and furniture selection;
  live fractional pool fill/drain; current-slice mining and construction; live
  block placement/removal; reference toggle/re-pin; original camera restoration.
  Actual HUD clicks and captures cover 960×540, 1280×720, 1680×720 and 2560×720,
  including dock/time-row separation. Full/Flat fixture geometry has 2,368/1,152
  vertices respectively. View changes do not modify mined/built world data.
- `TimeSliceHUDTest`: existing stepping, time controls and layout.
- `TerrainExplorerTest`: discovery concealment, rendered cuts, terrain facts,
  construction, object priority and active-tool selection.
- `ConstructionInputTest`: existing construction interaction and 32×32 drags.
- `BedroomLightingTest`: normal furnished-room lighting and door shadows.
- `SaveManagerRoundTripTest`: normal world restore, scene lifecycle, owner data,
  validation, backup recovery and save-worker checks.

Inspected captures and final logs are in
[the evidence folder](concepts/xray_20261017/summary.json). Early fixture runs
exposed test-only typed-array/preload errors; those were corrected. The pool
check also caught live water being treated as undiscovered air, fixed by using
the underlying terrain in `InteriorTracker`.

Restart Play. No Windows playtest was created or updated.
