# 72 — Surface details plan

Status: **boulders, gatherable scree, seasonal shrubs, flowers and reeds live, 2026-10-08.**
[73 — Boulder pilot](73_boulder_pilot.md) records the initial assets, deterministic
placement/removal foundation, worker clearing, developer locator and checks.
[74 — Gatherable scree](74_gatherable_scree.md) records the second milestone.
[75 — Seasonal shrubs](75_seasonal_shrubs.md) records the third milestone.
[76 — Seasonal wildflowers](76_seasonal_wildflowers.md) records the fourth milestone.
[77 — Seasonal reeds](77_seasonal_reeds.md) records the fifth milestone.
[78 — Combined review](78_surface_detail_review.md) completes the initial
density/readability/performance pass with twelve-seed checks, four native seed
comparisons and a targeted seasonal queue optimization. Density stays unchanged.
**Later extensions complete, 2026-10-09:** [79](79_shrub_transplanting.md) and
[80](80_shrub_cutting_growth.md) add shrub relocation and cutting growth;
[85](85_plant_habitats_spacing_flowers.md) supersedes the original mountain-berry
recommendation with soil below Y44, exclusive 3×3 bush/flower planting space and
movable flowers. Planting is implemented; honey and food processing remain later
work. The original numbered recommendations below are retained as plan history.
The user requested
a numbered plan for boulders, scree, shrubs, flowers and lakeside reeds after the
world-layout, cave and ore work. Resource placement stays depth-based for now;
regional resource bias and economy tuning are separate work.

The aim is to give open lowlands, foothills and shores local character while
keeping terrain and usable space readable at the normal RTS camera distance.
This does not reserve or clear a starting area. Players continue to choose their
own site. The seeded geography, Y115 summit requirement, rough cliffs/shores,
water levels, caves, ore fields and existing tree distribution remain intact.

The numbered steps below are the implementation order. Placement and interaction
defaults are recommendations for this feature, not claims about shipped behavior.

## 1. Establish the asset inventory and visual targets

The original filesystem/code audit below is historical; completed assets are
recorded in milestone documents 73–77:

| Category | Current evidence | Work required |
|---|---|---|
| Boulders | No dedicated world-boulder models or placement definitions found | Author grounded stone silhouettes and placement/clearing data |
| Scree | No dedicated scree models or placement definitions found | Author low stone groups with several arrangements |
| Shrubs | Blueberry, elderberry and wild-strawberry JSON definitions exist; no `placement` blocks; all 12 referenced model paths are missing | Build and validate the models, then add wild placement |
| Flowers | No dedicated wildflower models or placement definitions found | Author a small, restrained set of flowering clumps |
| Reeds | No dedicated reed models or placement definitions found | Author short/tall clumps and shore-specific placement |

The existing `rough_stone.glb` is a loose item, not a finished world-boulder asset.
The current `SurfaceFloraSpawner` explicitly loads four tree files; adding a bush
JSON alone will not make shrubs appear. Its tree selector uses one shared grid
and is coupled to tree stages/felling. New detail should not compete in that
selector or change existing trees when another detail species is added.

Prepare one representative model per category first, beside a dwarf, one terrain
block and existing trees. Check silhouettes and color at close and ordinary
play zoom before expanding the variant set. Use real Godot renders for review.

**Acceptance:** a verified asset manifest, actual dimensions, origin, material
and role for every planned asset; missing art is explicit rather than silently
substituted with tree saplings or enlarged item drops.

## 2. Author a small, consistent asset set

Use the existing voxel GLB tooling and flat-shaded vertex-color conventions.
Start with approximately three boulder silhouettes, three scree arrangements,
the three existing shrub identities, two or three flower clumps, and two reed
heights. These are starting art targets, not mandatory final counts.

- **Stone:** broad, irregular masses with restrained highlights and recesses;
  palettes compatible with nearby authored rock bands. Boulders must read as
  separate objects, and scree as low rubble rather than new terrain steps.
- **Shrubs:** elderberry as a fuller leafy bush, blueberry as a compact hardy
  mound, strawberry as ground cover. Keep their shapes distinct from saplings.
- **Flowers:** small accents on grass, not saturated fields of color everywhere.
- **Reeds:** upright grouped stems with visible gaps and grounded bases; use
  chunky silhouettes that survive the normal camera distance.

Resolve the stale scale instructions before exporting. Art doc 61's current
anchor is **one block = one Godot unit**; older shrub subsections still say
0.0625 for eight voxels/block, conflicting with the current 0.125 conversion.
Some old shrub dimensions also exceed their JSON clearance heights. Reconcile
the target dimensions and data together. Bake the chosen scale into newly
generated GLBs, verify the imported size, and never hand-edit `.import` or `.tres`.
Small-prop detail must not inherit the tree spawner's 1:1 voxel scale blindly.

**Acceptance:** no floating bases, incorrect scale, overly thin geometry or
clearance mismatches. Seasonal changes may replace appearance, never placement
identity or occupied space. The user subsequently requested all four seasons
for shrubs; that full art set ships in milestone 75.

## 3. Build deterministic placement and removal foundations

Use a separate detail placement layer alongside the established tree layer.
Keep all species settings in JSON and load them through one dedicated owning
registry/system. Recommended structure: a `SurfaceDetailRegistry` for definitions,
a scene-owned detail manager for placement/removal state, and pure candidate
selection helpers. Definitions must not be independently opened by renderers,
worker tasks or preview tools. New names are proposed, not existing APIs.

Candidate identity should derive from seed, category, scatter-cell coordinates
and a fixed candidate index. Give each category independent hash salts. Resolve
overlapping candidates with stable priorities and deterministic neighbor checks,
including chunk-border neighbors; never let camera order or whichever node
spawned first decide the accepted layout. Sample immutable generated terrain for
the base layout, then apply saved player edits and removal deltas.

Shared inputs: actual support material/height, nearby height differences,
moisture, actual waterline, shoreline proximity, tree trunk/canopy distances and
other accepted detail footprints. Use actual seeded lake/tarn positions; old
documents' compass locations and fixed water heights are not placement rules.

Data should cover habitat, density, clustering, spacing, height/slope limits,
support footprint, water tolerance, model variants, logical occupancy and removal
behavior. Keep broad gaps between clusters and conservative initial densities.
Do not guarantee every category on every seed if suitable habitat is absent.

Design lifecycle handling now, before adding blocking props:

- Untouched details regenerate deterministically; save stable removed/changed
  identities and any in-progress clearing work, not an entire visual-instance list.
- Player construction, excavation and support removal invalidate affected detail
  records. A removed object must not return on season change, camera movement or
  load. Unsupported props must not hover or relocate unpredictably.
- Trees and existing built objects take precedence. Small details can be
  displaced by successful construction without changing terrain. Check final
  committed placement, not the player's preview cursor.
- Keep gameplay occupancy independent of visual streaming. Use existing picking,
  slice, lighting and scene-save interfaces; do not paint details into block data.

**Acceptance:** same seed and edits produce identical records in forward/reverse
streaming order and after reload; tree placements remain identical to baseline.

## 4. Introduce boulders, with clearing available immediately

Place occasional boulders on supported rocky ground, foothill shelves and
mountain shoulders, plus sparse lowland outliers. Use isolated stones and small
groups, leaving generous gaps. Reject unsupported footprints, steep cliff lips,
water, tree trunks, structures and narrow ledges where a stone would close the
only usable passage. Do not flatten ground to make a model fit.

Recommended gameplay: substantial boulders occupy their actual solid footprint
through `PlacedEntityRegistry` and can be selected and broken/cleared by workers.
Build that clearing path before enabling them in ordinary generation. It must
support reachable work positions, cancellation/resumption, persistent removal
and a modest data-defined rough-stone yield using the existing item. No ore
rewards or new mining tier are introduced. Reuse mining feedback and work-system
conventions without pretending a placed prop is a terrain voxel.

If a physics shape is needed, keep it off the camera's terrain collision layer.
Document this explicit non-plant obstacle case alongside the existing tree rules;
it must not authorize collision on shrub or flower overhangs.

**Acceptance:** dwarves route around stones, can clear an obstructing stone,
camera movement is unaffected, and the stone stays removed after save/load.

## 5. Add localized scree at the foot of cliffs

Use nearby higher terrain and the lower supporting shelf to find cliff-foot
habitat. Place short broken patches with varied stone sizes, strongest near the
base and thinning outward. Avoid regular strips along every terrace, uniformly
ringed mountains, unsupported faces and continuous rubble carpets.

**User-approved revision, 2026-10-08:** scree is gatherable loose stone, giving
it a modest gameplay purpose. Each clump is one nonblocking work target, with
three seconds of hand gathering yielding one rough stone. Boulders retain their
seven-second breaking job and two-stone yield. These are initial tuning values.
There is no per-pebble collider or task. Players can select **Gather stones** in
the inspector or use **Orders → Clear stones** for boulders and scree together.
Cancellation retains partial work; collected clumps stay removed across load.
Committed construction and excavation can displace it without a reward. It does
not raise terrain, hide rough cliffs or add a new pathfinding slope.

**Acceptance:** patches visibly relate to a nearby cliff, stay grounded across
terrace boundaries and leave enough exposed rock/grass to read the terrain.
Workers can gather them, movement remains open, and partial/removal state persists.

## 6. Add shrubs and ground cover in habitat patches

Use the existing species identities as starting niches:

- **Elderberry:** sheltered, moderately moist lowland/foothill patches and some
  woodland edges.
- **Blueberry:** sparse rocky foothill and mountain pockets, tapering where the
  height/moisture combination becomes unsuitable.
- **Wild strawberry:** low ground cover in grassy openings and lower edges.

Use clustered placement with open gaps rather than one shrub beside every tree.
Tree-distance checks can approximate openings; this does not require a new
sunlight/ecology simulation. Keep logical plant origins small and visual
overhangs nonblocking, with no `CollisionShape3D` on shrubs.

**User-approved revision, 2026-10-08:** ship separate berry harvest and permanent
clearing alongside four-season voxel art. Each mature plant provides one crop
per eligible season using the existing JSON fruit yields: blueberry 3 in summer,
elderberry 4 in autumn, strawberry 3 each spring and summer. Picking leaves the
plant and removes visible berries; completed worker clearing is permanent and
yields one cutting (100% for all three species, configured in JSON).
Both support partial progress, cancellation, Orders and saved state. Placement
and harvest rules are implemented in [75](75_seasonal_shrubs.md). Planting,
growth from seedlings, food consumption and brewing remain separate work.

**Acceptance:** shrub forms and habitat differences read clearly, no trunk or
structure intersections, and clearing/building does not leave persistent clutter.

## 7. Add restrained flower patches

**Implemented, 2026-10-08:** three clump variants with spring/summer/autumn/winter
models. **Clear plants** replaces the Clear shrubs label and includes flowers;
each clump takes 1.5 seconds of worker hand clearing with no yield. Partial work
and removal persist. **DEV: Next flowers** supports review. Data, art, native
captures and verification are recorded in [76](76_seasonal_wildflowers.md).

Favor grassy lowland openings, gentler foothill shelves and selected moist edges.
Use a broad patch mask plus sparse local clumps, with a small harmonious palette.
Leave ordinary grass between patches; avoid bare rock, water, dense tree trunks,
scree concentrations and high summits unless a later alpine species is designed.

Flowers remain nonblocking, with no individual harvest jobs or new resource
outputs. They are displaced when the player commits construction or removes
their supporting ground. Seasonal appearance changes must not shift patches.

**Required later use, 2026-10-08:** the user wants flowers tied to honey production.
Future beekeeping must account for nearby blooming flower forage and its loss
through clearing or seasonal changes. Flowers remain living forage rather than
harvested recipe ingredients. See [42 — Beehives](../40_economy_colony/42_farming_brewing.md#required-future-connection-wildflower-forage)
for the proposed approach and tuning decisions held for that milestone.

**Acceptance:** flowers add readable accents at play zoom without covering the
ground, competing with selection highlights or creating excessive instance counts.

## 8. Add reeds using actual shoreline geometry

**Implemented, 2026-10-08:** two heights with four seasonal appearances, dry
bank placement within four horizontal blocks and 0–2 support levels above the
local waterline. **Clear plants** includes reeds, with 1.5-second hand clearing,
no yield and persistent removal. **DEV: Next reeds** locates generated clumps.
Lake and tarn native captures, eight-seed and lifecycle checks are in [77](77_seasonal_reeds.md).

Start with reeds rooted on **dry banks near the local waterline**, beside the
lowland lake and suitable tarn edges. Use broken shoreline clusters, leaving
open sections of water and bank. Initial tolerance should be a few horizontal
blocks from water and a small vertical difference from that body's waterline;
exact values are tunable after viewing rough shore samples.

The tree helper `_is_water()` currently includes `water_bank_columns` and is
therefore unsuitable as the reed rejection rule. The bank mask also records
horizontal proximity without proving the bank is near water vertically. Check
actual nearby water, its waterline and local support height so reeds do not
appear high above a lake on an adjacent cliff. Do not assume the waterline is Y18.

Reeds must not form a solid border, cover deep water or change fluid cells. Keep
them nonblocking and clearable/displaceable. Fully submerged roots and shallows
placement can follow once their rendering and support rules are reviewed.

**Acceptance:** correct grounding on irregular shores, visible gaps, no cliff-top
false positives, and both lake and eligible tarn examples reviewed.

## 9. Integrate presentation, diagnostics and performance

**Reviewed, 2026-10-08:** four native seeds, identical enabled/disabled camera
paths and seasonal cache warmup, GPU timing, draw calls, memory and startup
measurements are recorded in [78](78_surface_detail_review.md). Picking and slice
checks pass. Current populations do not warrant batching. A small queue lookup
optimization reduces seasonal enqueue work; broader rebuild hitches remain
explicit follow-up rather than a claimed performance guarantee.

Budget population work across frames and reuse meshes/materials. Batch suitable
noninteractive details by spatial region/model where useful; avoid a full scene,
physics body or per-frame update for every flower or pebble. Preserve per-object
identity for removal and region-level updates. Whole-map versus distance-culling
choices must be measured at the game's actual overview zoom, with no details
appearing to follow the camera.

Verify slices hide above-plane details, seasonal rebuilds preserve edits, and
existing lighting/material conventions keep props consistent with the terrain.
Keep boulder picking distinct from terrain and plants. Reuse Object explorer for
selectable entities; provide concise DEV counts and rejection reasons per category
and fixed-seed captures. Add a temporary category highlight only if it helps
inspect dense placements; developer inspection must not alter player state.

**Acceptance:** record generation time, instance/draw-call counts, frame-time and
memory against the same scene without details, plus panning/zooming/slicing checks.
Set density caps from those measurements rather than promise unmeasured FPS.

## 10. Validate several seeds and tune each category before expanding

**Reviewed, 2026-10-08:** all twelve seeds pass placement, deterministic order,
fresh restore, support/water/spacing checks and preserved terrain/tree identity.
Four independent seeds were selected before review. Native samples support
retaining the current density and art scales. See [78](78_surface_detail_review.md)
for counts, coverage, screenshots and the boundaries of this initial review.

Use a repeatable seed set containing wet/dry lowlands, wooded openings, steep
cliffs, high terrain, the main lake and at least one suitable tarn. Include the
established 7/1234/65535/20261007 seeds plus additional seeds selected before
tuning; retain some for independent checks. Inspect at normal play zoom and close
up, with daylight and at least one alternate season.

Automated checks should cover deterministic records and stream-order independence,
footprint/support/water exclusions, bounds and overlaps, no new terrain/cave/ore
changes, unchanged tree candidates, correct navigation occupancy, boulder clearing
interruption, construction displacement, mining support removal, saved removals,
seasonal changes and slice visibility. Tests must exercise actual integrated
placement and actions, not just a duplicate sampler.

Capture counts and coverage by habitat/category, accepted/rejected candidates,
and representative wide/close views. Check broad natural gaps and the absence of
grid patterns, uniform shore rings, rubble bands or accidental reserved areas.
Tune one category at a time, then inspect their combined density.

**Acceptance:** the user can assess each addition from a small set of native
captures; integrated behavior and persistence pass before the next category is
expanded. First implementation should cover **steps 1–3 and one small boulder
pilot**, including its clearing behavior. Scree, shrubs, flowers and reeds follow
in that order, with visual review at each milestone rather than one large drop.

## Scope held for later

Berry harvesting/regrowth and the food economy; reed/fiber crafting; detailed
erosion; slope simulation; snow/alpine biomes; underwater plants; new lakes or
rivers; trade roads; cave flora; resource region bias; and changes to the current
ore or item-drop balance. Proposed supporting infrastructure above is only what
is needed for safe placement, clearing, persistence and readable rendering.

## References

- [14 — Mixed forest](14_flora_distribution_plan.md): established tree ecology;
  use current seeded geography rather than historical compass/settlement wording.
- [13 — Flora conventions](13_flora_scatter_pine.md): grounding/material/camera
  collision conventions, with current scale corrections in the art guide.
- [12 — World grid](../10_core_foundation/12_world_grid.md): placed entities versus
  terrain, occupancy and save ownership.
- [42 — Farming](../40_economy_colony/42_farming_brewing.md): plant footprint and
  overhang rules; crop/harvest design is not proof of current implementation.
- [61 — Art guide](../60_asset_creation/61_voxel_art_guide.md): voxel style and the
  current scale anchor; reconcile the older shrub subsections in step 2.
