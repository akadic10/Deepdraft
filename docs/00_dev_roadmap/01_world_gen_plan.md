# 01 - World Generation Plan

## Goal

Make the first generated world read immediately as Deepdraft: a dwarven mountain refuge with a high, dangerous mountain side, a usable valley approach, exposed stone, water features, dense wilderness edges, and clear settlement candidates. The map should look less like a grass blanket over noise and more like a carved, playable landscape.

This is a planning document only. Implementation should happen after the plan is reviewed.

## Implementation Progress

Status key:

- Done: implemented, verified with Godot headless parsing or a debug-world run, and committed.
- Partial: some useful implementation exists, but the item still needs validation, cleanup, or a follow-up pass.
- Not started: no meaningful implementation yet.

| Item | Status | Notes |
| --- | --- | --- |
| Baseline Audit | Done | Current `WorldGenerator.gd`, `WorldRenderer.gd`, `ChunkMesher.gd`, terrain JSON, and this plan were reviewed before terrain changes. The old top-only preview problem was identified and documented in the course-correction section. |
| Debug Metrics First | Done | Debug overlay and logs now report domain ratios, height range/average, surface ratios, per-domain surface ratios, terrace/plateau counts, lake/tarn/bank positions, settlement candidate count, generated chunk count, and mesh count. |
| Macro Layout Pass | Done | Northwest mountain mass, central/foothill valley corridor, southwest basin, southeast highland, and world-edge belt placeholder are implemented as deterministic influence fields and surfaced in metrics. |
| Heightmap & Terrace Pass | Done | Directional mountain influence, curved valley corridor flattening, domain-specific terrace quantization, southeast highland terraces, and chunk-aware plateau bias are implemented. Plateau smoothing is now a selective bias rather than whole-chunk flattening. |
| Surface Material Pass | Done | Surface material selection now uses stable macro regions, slope/elevation/domain rules, rock-heavy mountains, valley grass/dirt patches, dirt/stone water banks, and exposed rock on steep slopes. Per-domain metrics validate the ratios. |
| Water Body Validation | Done | Lake and tarn placement, irregular shoreline footprints, waterline/floor-depth metrics, basin carving, and dirt/stone bank masks are implemented and validated in debug metrics. Dynamic water simulation remains out of scope for this plan. |
| Block Inspector Agreement | Partial | Existing inspector reports clicked block key/type/coordinates and helped validate rendering fixes. It still needs explicit domain, surface Y, and overview-vs-real face/source debug text. |
| Surface Diorama Decision | Partial | The misleading top-only surface view has been replaced for current terrain review by a block-face overview path that includes top/side faces and actual sampled materials. It still needs a formal quarantine/rename and clearer debug labeling as overview approximation. |
| Block-Faithful Overview Renderer | Partial | Current overview emits block-derived top faces and side faces with deterministic vertical material approximation. Greedy/region merging and stronger sampled-coordinate validation remain. |
| Streaming Chunk Compatibility | Partial | Near chunk generation and overview both resolve block IDs from `WorldGenerator`; spot checks have been done through inspector/render iteration. A repeatable sampled comparison test is still needed. |
| World Edge Slab | Not started | Current boundary still exposes terrain edge behavior from the overview path. The planned calm, coarse presentation slab has not been implemented. |
| Validation Scene/Workflow | Partial | We have a repeatable manual loop using the debug world, headless parse, metrics logs, screenshots, and inspector checks. A scripted/captured validation workflow is still needed. |

## Current Problem

The current world is technically functional but visually bland:

- Too much of the top surface resolves to grass.
- Terrain shape is mostly noise-driven, so it lacks a strong readable composition.
- The mountain, valley, lake, and tarn exist conceptually, but the player does not yet see a dramatic "dwarves at the mountain" staging.
- The surface view needs larger flat or gently stepped regions, similar to Stonehearth's readable plateau style, while preserving underground voxel simulation.

## Course Correction: Blocks Are the Source of Truth

The recent preview work exposed a major planning error: we tried to judge and improve a block world through a renderer that only drew the top surface. That is not acceptable for Deepdraft.

Deepdraft terrain is made of blocks. A visible block has up to six visible faces, and any overview, diorama, or performance LOD must preserve that basic truth. A top-only heightmap preview can be useful for a minimap or debug overlay, but it must not be used as the main world view, material validation view, or Stonehearth-style terrain presentation.

What went wrong:

- We treated the surface diorama as if it represented the block world, but it only drew top faces.
- We added fake side bands that were not derived from actual block material, causing grass/dirt/rock mismatches.
- We then tried to patch those side bands locally, which produced stripes, floating carpets, and other artifacts.
- We toggled between top-only preview and full chunk rendering, creating either visual lies or performance problems.

Correct rule going forward:

- World data decides block identity.
- Rendering may simplify geometry, but it must simplify exposed block faces, not invent unrelated surfaces.
- The visual validation path must show the same block identities that the inspector reports.
- Any optimization must be designed as a block-face LOD/meshing problem, not a 2D heightmap paint problem.

No further terrain-look decisions should be made from a top-only preview.

## Stonehearth Reference Takeaways

Stonehearth is useful as a visual and performance reference, not as a system we should copy exactly.

Observed / usable lessons:

- Large readable landforms matter more than noisy detail.
- Big flat terraces make settlement choice legible and keep the world friendly to building.
- Terrain types are visually grouped: plains, foothills, mountains, mountain peaks, water, forest.
- Edges are hidden with atmosphere, trees, and distance rather than obvious walls.
- Chunks exist as a debug/rendering concept, but we should not assume Stonehearth flattens terrain per 16x16x16 chunk without engine/source proof.

Additional screenshot takeaways:

- The world is visibly made of blocks, but the presentation is calm and macro-shaped.
- Map edges render as clean, simple stone slabs. They do not expose noisy per-block side detail.
- Mountains use large flat plateaus and broad shelf steps.
- High mountain stone appears in large contiguous fields, such as broad limestone/gray stone regions, not per-block scatter.
- Grass variation is patch-based and regional. It uses large, smooth color/material fields rather than hash noise.
- Grass color/material should never be chosen because of fog, camera distance, or any screen-space effect. Fog can affect final screen color, but block identity must come from world data only.
- Forests, flowers, stones, and detail objects are separate scatter/prop systems. They should not be simulated by noisy terrain colors.
- The overall composition appears anchored by major regions:
  - northwest main mountain,
  - southwest lowland lake basin,
  - southeast smaller highland / forest plateau,
  - central valley and foothill terraces.

Inference:

Stonehearth's larger flat areas are likely a design/product of terrain shaping, quantization, and buildability constraints, not necessarily "one 16x16x16 mesh equals one height." We can intentionally produce similar readability by quantizing height into terraces and using chunk-aligned plateau hints where they help performance.

## Stonehearth Asset Review Notes

Reviewed local reference files under `P:\stonehearth`, especially:

- `services/server/world_generation/terrain_generator.lua`
- `services/server/world_generation/micro_map_generator.lua`
- `services/server/world_generation/terrain_detailer.lua`
- `services/server/world_generation/landscaper.lua`
- `services/server/world_generation/biome.lua`
- `services/server/world_generation/height_map_renderer.lua`
- `services/server/world_generation/overview_map.lua`
- `data/constants.json`
- `data/biome/*_generation_data.json`
- `data/terrain/terrain_blocks.json`
- `data/terrain/valley_shapes.json`
- `data/calendar/sky_settings.json`

Key findings:

- Stonehearth uses a coarse-to-fine terrain pipeline.
- Constants from `data/constants.json`:
  - `TILE_SIZE = 256`
  - `MACRO_BLOCK_SIZE = 32`
  - `FEATURE_BLOCK_SIZE = 16`
  - `Y_CELL_SIZE = 5` for mining/slice cells
- Their terrain generator first creates a coarse `micro_map`, then expands it into a larger tile heightmap.
- The code comments define a `macro_block` as a square unit of flat land, `32x32`, allowed to shift a bit due to topology.
- Height is quantized through a `NonUniformQuantizer`, not left as raw noise.
- Terrain types are derived from elevation bands: `plains`, `foothills`, `mountains`.
- Plains are deliberately flattened: values at or below the plains max become the plains max during quantization.
- Foothills and mountains use large step sizes, which creates the broad shelf/terrace look.
- Terrain detail is added mostly at edges after quantization, via protrusion/inset passes, not by making the base heightmap noisy everywhere.
- Stonehearth has explicit post-process cleanup to remove awkward macro-block shapes: jut removal, hole filling, peak growth, and valley shape placement.
- Valley depressions are authored as small template masks in `data/terrain/valley_shapes.json`, then randomly rotated/reflected and stamped into high plains.
- Water is chosen in feature space, pushed away from non-flat terrain, cleaned up across tile boundaries, and converted to shallow/deep bodies.
- Trees/plants/boulders are not part of terrain blocks. They are selected on a feature map and placed as entities only if their ground-radius flatness checks pass.
- Height rendering converts heightmaps into optimized regions, adds soil strata, rock layers, grass caps, and a bedrock slab. It is not naively meshing every internal voxel face.
- Stonehearth's bedrock is a rendered/generated region below the surface terrain, not evidence that every world chunk must be visible.

Implications for Deepdraft:

- We should adopt the idea of macro-block terraces, but at a scale appropriate for our 16x16x16 chunks.
- A Deepdraft `macro_cell` can be 16x16 or 32x32 XZ. Start with 16x16 because it aligns with chunk columns and makes performance metrics easy.
- Generate a coarse macro heightmap first, then expand/detail it into per-block columns.
- Use non-uniform height bands:
  - valley floors: 1-2 block steps,
  - foothills: 4-6 block steps,
  - mountain shelves: 8-12 block steps.
- Add edge detail after quantization so cliffs and shelves get visual richness without destroying broad flat play areas.
- Use feature maps for water, forest, boulders, scree, road, and settlement candidates.
- Use flatness checks before placing large tree/flora/rock entities.
- Do not directly import or depend on Stonehearth assets. Use this review as design/technical reference only.

## Core World Composition

Use a macro layout before adding noise:

1. Mountain side
   - The northwest corner becomes the dominant mountain mass.
   - Height target: Y 88-124, with large flat shelves and broad stone plateaus.
   - Surface material should be mostly exposed stone, scree, snow/tundra accents at high elevation, and sparse pine/juniper.
   - This side is the intended dwarf dig-in face.

2. Valley floor
   - A broad valley runs along the mountain base.
   - Height target: Y 60-70.
   - Mostly flat, but not grass-only: dirt paths, mud, rock outcrops, shrubs, meadow patches, and tree clusters.
   - This is where the trade road and early approach should live.

3. Foothills / transition band
   - Between valley and mountain, create stepped foothills.
   - Height target: Y 70-85.
   - Terraces and ledges should create Stonehearth-like readable shelves.
   - Use mixed grass, dirt, exposed rock, and forest.

4. Lowland / water basin
   - The southwest becomes a lower basin with a large lake and wetland.
   - Height target: Y 58-64.
   - Lake, reeds/future flora, mud banks, dense trees around edges.

5. Southeast highland
   - The southeast corner gets a smaller raised plateau / forest highland.
   - Height target: Y 72-88.
   - It should be lower than the northwest mountain and visually calmer.
   - Use broad flat tops, stone/soil surface regions, and dense forest scatter later.

6. World-edge wilderness
   - Outer 20-30 blocks should become a dense forest/slope/fog belt.
   - This helps hide map boundaries and reinforces the surface as hostile wilderness.
   - Terrain/block selection must not depend on fog; fog is render-only atmosphere.

## Heightmap Strategy

Replace "pure noise decides domain" with a shaped macro mask:

1. Directional mountain gradient
   - Use a northwest mountain influence field, not a simple north or west stripe.
   - Compute `mountain_influence` from distance to the northwest region/corner.
   - Add broad ridge noise only inside the mountain influence.

2. Valley spline / corridor
   - Define a curved valley path running roughly parallel to the mountain base.
   - Use distance-to-spline to flatten and lower nearby terrain.
   - This gives the player a clear settlement and trade-road corridor.

3. Terrace quantization
   - After raw height is computed, quantize broad areas into 2-4 block height steps.
   - Stronger quantization in valley/foothills, weaker on peaks.
   - Add small deterministic breaks so terraces are not perfect rectangles.

4. Chunk-aware plateau hints
   - For each 16x16 XZ chunk column, compute a dominant terrace height.
   - If local slope variance is below a threshold, snap most columns in that chunk to the dominant height.
   - Keep ravines, roads, lakes, and cliffs allowed to cross chunk boundaries naturally.

5. Secondary highland mask
   - Add a weaker southeast highland influence.
   - Keep it lower than the northwest mountain.
   - Flatten it aggressively into forested plateau shelves.

6. Southwest lake basin mask
   - Reserve the southwest for the largest lake/basin feature.
   - Keep surrounding elevation low and gently rolled.
   - Use broad authored-looking shorelines, not puddle noise.
   - First-pass shoreline reshaping now uses deterministic irregular footprints; revisit later only if art direction wants more authored banks, reeds, or flowing water features.

This gives us Stonehearth-style flat regions without forcing every 16x16 area to a single height.

## Surface Materials

Reduce grass by making top material depend on elevation, slope, moisture, and feature masks.

Important material rule:

- Do not choose block material from per-block random/hash noise except as a very rare local detail.
- Use macro material fields: plateau regions, biome regions, forest density, moisture, slope, elevation, and authored feature masks.
- Material regions should be stable and contiguous enough that a player reads "limestone shelf", "green meadow", "forest floor", or "muddy bank" instead of visual static.

Suggested surface rules:

- High mountain: exposed granite/basalt, sparse dirt, optional snow/cold rock later.
- Steep slope: exposed rock or scree, not grass.
- Foothill terrace top: mixed grass/dirt/rock.
- Valley floor: grass patches, dirt, packed road, meadow, bare soil.
- Lake/tarn bank: mud/dirt/stone, no grass immediately adjacent to water.
- Forest floor: darker dirt/needle litter under dense tree masks.
- Trade road: packed dirt or gravel strip through valley.

Target first-pass ratios:

- Mountain: 90-98% exposed rock top surface in the main northwest mountain; grass/dirt should be rare and clustered only on low sheltered shelves.
- Foothills: 30-50% grass, rest dirt/rock.
- Valley: 40-60% grass, but broken by roads, dirt, water, and tree shade.
- Lowland basin: mud/dirt around water, grass only outside the bank band.

## Macro Material Fields

The material pass should be planned as its own 2D map layer, not mixed directly into single-block generation logic.

Required maps:

- `stone_region_map`
  - Assigns dominant stone family by macro region or terrace.
  - Mountain plateaus should have large contiguous granite/basalt/limestone fields.
  - Avoid single-block limestone/stone scatter.

- `grass_region_map`
  - Assigns grass family/tint by large patches.
  - Open lowland and meadow areas can be lighter.
  - Forest interiors can use darker/cooler grass or forest-floor material.
  - This must be based on stable world maps, not fog or camera distance.

- `soil_region_map`
  - Mud/dirt around water, roads, banks, low slopes, and sheltered shelves.
  - Mountain dirt exists only as rare clustered shelf patches.

- `forest_density_map`
  - Drives later tree scatter.
  - Can also influence forest-floor material, but trees remain entities/instances.

Implementation rules:

- Pick material by macro cell, e.g. 16x16 or 32x32 XZ, then optionally soften or detail edges.
- Use deterministic region IDs and low-frequency masks.
- Use hash only inside a selected macro region for rare chips/details.
- Validate material ratios by domain: mountain, foothill, valley, lowland, lake bank.
- The inspector should show stable block identity; visual color variation should correspond to actual block variants or render palette rules.

## Side Map / Diorama Outline

The indestructible Y=0 bedrock layer should remain simulation bedrock. The renderer should never fake a decorative side shell that disagrees with the actual terrain blocks.

Replace the old "top surface plus side bands" idea with a block-faithful overview mesh:

1. Keep Y=0 bedrock as the absolute data floor.
2. Build overview geometry from exposed block faces:
   - top faces where a solid block has air/void/water above,
   - side faces where neighboring columns are lower,
   - boundary faces only where we intentionally show the edge of the playable world.
3. Coalesce faces into larger rectangles using greedy meshing by material and plane.
4. Derive every face color/material from the actual block ID represented by that face.
5. Do not draw fake grass/dirt/rock bands unless the underlying block data has those materials.
6. Do not draw one vertical wall panel per sampled tile; that creates stripes.
7. If a coarse overview is needed, simplify the exposed-face mesh, not the world into a flat top-only sheet.

Stonehearth-like presentation should come from broad terraces, clean face merging, and readable material zones, not from a painted heightmap.

Important: do not create visible 16x16x16 cube outlines for every chunk in normal play. That would reveal the engine grid and fight the natural Stonehearth look. Chunk size can guide generation and greedy mesh batches, but the final visual should read as natural block terrain.

## Block-Faithful Rendering Plan

We need two renderer modes that share the same rule: visible faces come from blocks.

1. Near / interactive mode
   - Use real generated chunks.
   - Mesh actual exposed block faces with `ChunkMesher`.
   - Stream only the camera neighborhood.
   - Use this mode for mining, inspection, selection, and close terrain review.

2. Far / overview mode
   - Do not generate every full chunk.
   - Use heightmap plus deterministic surface/material lookup to create a coarse exposed-face mesh.
   - Include vertical faces between neighboring sampled columns when their heights differ.
   - Merge coplanar same-material faces into rectangles.
   - Use a coarser sample step only when it still preserves cliffs and terraces well enough.

3. World-edge slab mode
   - Render the outside map boundary as a clean, coarse stone slab.
   - This is a presentation mesh, not a per-block side dump.
   - It should use large panels, simple dark stone, and minimal material variation.
   - It should hide or abstract internal block strata unless a deliberate cutaway/mining view is active.

The overview mesh should answer the same question as the chunk mesh: "which block face is visible here?" It may reduce face count, but it must not invent top-only terrain or decorative side colors.

Recommended overview algorithm:

1. Sample columns at `step = 1`, `2`, or `4` depending on zoom and performance.
2. For each sample, determine:
   - visible surface block ID,
   - visible surface Y,
   - neighboring sampled heights.
3. Emit:
   - one top quad for the surface block,
   - side quads only where neighbor height is lower,
   - material-specific side quads based on a cheap vertical material resolver.
4. Merge adjacent quads with same plane, Y range, normal, and material.
5. Never emit faces down to Y=0 except at intentional world-border cutaway views.

Recommended world-edge slab algorithm:

1. Trace the playable world boundary.
2. Build large vertical panels per edge segment, not per terrain sample.
3. Top of the slab follows a simplified/quantized boundary height profile.
4. Side material is mostly dark stone, with optional broad horizontal bands only if they are large and calm.
5. Do not expose every local height change on the outside wall.
6. Keep the slab visually behind/under the playable top surface.

Vertical material resolver:

- Top 1 block: actual surface block.
- Below top:
  - mountain domain: stone by default,
  - valley/lowland: shallow dirt/soil cap, then stone,
  - water banks: mud/dirt cap, then stone.
- This resolver must be deterministic and documented as an LOD approximation.
- When close enough for real chunks, the actual chunk mesh replaces the approximation.

Validation:

- Clicking a face in overview should report the block/material that face represents.
- A selected rock face should not display as grass or dirt.
- A selected dirt face should not have a rock top unless that is an actual neighboring block face.
- The inspector, overview mesh, and close chunk mesh must agree at sampled coordinates.

## Performance Plan

The generator should stay column-first and chunk-friendly:

- Compute 2D maps first: domain, height, slope, moisture, forest density, road mask, water masks.
- Generate 3D chunks lazily only where the camera or simulation needs them.
- Skip all-void chunk layers above each column's max visible Y.
- Skip fully buried solid chunks during mesh building.
- Keep the zoomed-out surface view as a coarse exposed-face mesh, not a top-only heightmap.
- Use a clean coarse world-edge slab for presentation, not per-block side walls.
- Use deterministic hash-based variation; never random runtime calls per chunk.
- Store placed flora as entities or later scatter batches, not terrain blocks.

Chunk plateau benefit:

- Flat terraces reduce exposed vertical faces and vertex count.
- Larger same-height areas make exposed-face overview meshes cheaper and cleaner.
- Chunk-aligned flat candidates reduce visual churn as nearby regions stream.

Risk:

- Over-aligning terrain to 16x16 chunks can look artificial. Use chunk-aware smoothing as a bias, not a hard rule.

## Generation Pipeline Proposal

Phase 1 - Macro Layout

- Choose northwest main mountain, southwest lake basin, southeast secondary highland.
- Build mountain/highland/basin influence fields.
- Build valley spline and distance field.
- Build lowland basin and water catchment areas.

Phase 2 - Terrain Height

- Compute base height from macro layout.
- Add ridge detail to mountain only.
- Add gentle detail to valley/lowland only.
- Carve lake basin and mountain tarn.
- Apply terrace quantization.
- Apply chunk-aware plateau smoothing.

Phase 3 - Feature Masks

- Slope map from heightmap.
- Moisture map from distance to water and lowland.
- Forest density map.
- Road mask through valley to mountain entrance.
- Settlement candidate flatness map.
- Stone region map.
- Grass region map.
- Soil/mud region map.

Phase 4 - Surface Blocks

- Pick top material from macro material fields plus elevation, slope, moisture, and feature masks.
- Use region-scale material assignment before local detail.
- Mountain: large contiguous stone fields, almost no grass/dirt.
- Grass: broad smooth patches, not per-block noise.
- Add dirt/mud around water and road as contiguous masks.
- Keep variant selection deterministic and region-aware.

Phase 5 - Underground Fill

- Preserve bedrock at Y=0.
- Fill stone layers, caves, ores, soil patches.
- Keep cave carving below surface buffer.
- Keep placed entities separate from terrain grid.

Phase 6 - Visual Scatter

- Place trees by biome/feature mask.
- Dense trees on map edges.
- Sparse trees on mountain shelves.
- Shrubs/meadow objects in valley.
- Rocks/scree on steep slopes.

Phase 7 - Preview / Validation

- Add debug overlays or exported metrics:
  - grass/rock/dirt/water ratios,
  - average slope per domain,
  - flat settlement candidate count,
  - generated chunk count,
  - mesh vertex count,
  - time to first visible terrain.
- Add render validation:
  - inspector block key at clicked coordinate,
  - clicked face material,
  - whether the current view is real chunk mesh or overview LOD,
  - visible face count by material,
  - overview LOD step size.

Phase 8 - Block-Faithful Overview Rendering

- Replace top-only diorama review with a coarse exposed-face overview mesh.
- Add greedy face merging.
- Add clean world-edge slab renderer.
- Keep overview fast without lying about block faces.
- Compare sampled overview faces against generated chunk mesh in a debug validation mode.

## Settlement Candidate Rules

The map should produce 3-5 good settlement banner spots:

- Near mountain face.
- Within pathing range of valley/trade road.
- At least 20x20 mostly flat blocks.
- Not inside dense forest.
- Not below waterline.
- Adjacent to rock exposure for mining identity.

These candidates can be used later for UI hints or automatic camera framing.

## Open Questions

- Which side should the first mountain occupy: west, north, or seed-selected?
- Should the valley road be visible immediately as packed dirt, or only implied by flatter terrain?
- Do we want snow/cold stone now, or save it for seasonal rendering?
- Should the first implementation prioritize visual surface quality or underground cave/ore interest?

## First Implementation Milestone

Implement only the low-risk terrain shaping and validation pass:

1. Directional mountain side.
2. Valley corridor.
3. Terrace quantization.
4. Slope/elevation-based surface material selection.
5. Block inspector for clicked block ID and coordinate validation.
6. Metrics printed to the debug overlay/log.

Do not continue iterating on the current top-only diorama as the main world view.

Next rendering milestone, after this plan is reviewed:

1. Remove or quarantine misleading top-only terrain previews from material/shape review.
2. Define a block-faithful overview mesh that emits top and side exposed faces.
3. Add greedy merging for overview faces by material and plane.
4. Keep real chunk meshes for near/interactive mode.
5. Validate that inspector, overview LOD, and near chunk mesh agree at sampled coordinates.

Do not implement dynamic day/night, water CA, pathfinding, or new flora entity spawning as part of this milestone.
