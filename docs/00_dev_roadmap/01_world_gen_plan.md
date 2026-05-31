# 01 - World Generation Plan

## Goal

Make the first generated Deepdraft world feel like a dwarven refuge carved into a dangerous mountain edge. The player should immediately read the map as a block-built world with a strong mountain face, a usable valley approach, water, wilderness edges, settlement candidates, and visible reasons to dig.

This is a planning document. Implementation should happen after the plan is reviewed.

## Current Implementation Checkpoint

This session moved the terrain prototype toward the Stonehearth-style plateau plan in several concrete ways:

- World height generation now starts from 32x32 macro cells, expands those cells into broad flat plates, then snaps them into readable bands.
- The vertical terrain contract is now explicit:
  - Y0-Y3: bedrock,
  - Y4-Y11: forced `base:terrain:rock:rock11` foundation,
  - Y12-Y19: lowland shelf,
  - Y20-Y43: valley/foothills shelves,
  - Y44-Y115: mountain shelves.
- Lowland columns whose generated height lands in Y12-Y19 are forced to the full Y19 shelf so the complete eight-layer lowland stack exists.
- Settlement/plain macro cells are a stricter subset of lowland: 32x32 cells forced flat to Y19 with no height variation.
- Lowland macro cells now require a real lowland majority before the whole 32x32 cell is classified as lowland. Non-anchor lowland cells with no cardinal lowland neighbor are promoted back to valley so a single lowland plate cannot appear inside the foothills.
- Valley/foothill terrain now uses 8-block shelves with tops at Y27, Y35, and Y43.
- The southeast highland/foothill region is authored at macro-cell scale. Its footprint is intentionally biased toward the southeast corner and uses all three foothill shelf tops instead of per-column lowland/foothill noise.
- Mountain terrain now uses 12-block shelves at Y44-Y55, Y56-Y67, Y68-Y79, Y80-Y91, Y92-Y103, and Y104-Y115.
- Mountain-to-foothill and lowland-to-foothill transitions are enforced on the same 32x32 macro grid as the base heightmap. Adjacent approach cells step one shelf at a time instead of creating thin diagonal or per-block stair artifacts.
- A unified macro shelf rule now caps all 8 neighboring cells, including diagonal corner contact: lowland -> foothill 1 -> foothill 2 -> foothill 3 -> mountain 1 -> mountain 2 -> mountain 3 -> mountain 4 -> mountain 5 -> mountain 6. No macro cell may jump more than one shelf rank across an edge or corner.
- Mountain shelf cells stay snapped to shelf tops after macro expansion. Local 0-2 block variation must not push a shelf 1 column from Y55 to Y56, because that crosses the material boundary into shelf 2.
- Foothill and lowland material stacks are forced from the spreadsheet instead of random surface picking.
- Foothill-or-higher columns use altitude-banded rock bodies below active surface shelves: `base:terrain:rock:rock10` in Y12-Y19, `base:terrain:rock:rock09` in Y20-Y27, `base:terrain:rock:rock08` in Y28-Y35, and `base:terrain:rock:rock07` in Y36-Y43.
- Mountain columns use the altitude rock body from Y12-Y43 before their mountain shelf material starts at Y44.
- `base:terrain:rock:rock01` through `base:terrain:rock:rock11` are authored terrain blocks, with a deliberately dark cool-slate color ramp from `rock01` `#879199` down to `rock11` `#151A22`. `rock11` should sit close to bedrock `#111116` so the foundation reads heavy instead of pale.
- Grass variants are restricted to eight active blocks:
  - `grass_01` through `grass_04` for lowland / settlement,
  - `grass_05` through `grass_08` for valley / foothills.
- Unused `grass_09` through `grass_16` block/resource entries were removed.
- Dirt variants now run from darkest `dirt_01` to lightest `dirt_04`, with seasonal palettes kept aligned.
- The legacy specialty rock blocks (`stone`, `granite`, `basalt`, `limestone`, `marble`, `obsidian`) were removed from the active terrain registry.
- `base:terrain:rock:rock11` is locked to Y4-Y11 as the hardcoded foundation band.
- The block inspector now reports both broad terrain `domain` and spreadsheet-driven `height band`, because those are intentionally different concepts.
- The lowland lake is generated from whole 32x32 macro cells. It is forced into the lowland band, fills water from Y12 through Y18, and guarantees at least one full 32x32 lake cell touches the southern map edge.
- The mountain shelf lake is generated from whole 32x32 macro cells on mountain shelf 1. Its floor is Y47, water fills Y48 through Y54, and its surrounding plateau ring is restored after shelf cleanup so it remains 32x32 mountain shelf 1 or shelf 2. Immediate outside transition cells may be raised to foothill shelf 3 to preserve the one-shelf rule. Because the restore pass can lower cells back to shelf 1 after the first cleanup, the macro shelf limiter runs again afterward so shelf 3 cannot remain adjacent to shelf 1.
- A final `_apply_edge_detail()` pass runs after lake carving and macro shelf cleanup. It pushes shallow blocky ledges outward from foothill and mountain shelf edges only, skips lowland/settlement/water columns, and keeps each pushed column inside the source shelf's valid height band so material strata remain correct.

Open terrain review notes:

- Rock distribution now follows the authored height bands: `rock11` in the Y4-Y11 foundation, `rock10` through `rock07` in the foothill-or-higher body bands, and `rock06` through `rock01` across the six mountain shelves.
- The overview renderer is still labeled as a block-face approximation. It now asks generated block identity for visible tops, but visual review should continue to verify that overview faces and inspector output agree after each terrain rule change.
- The southwest lake should continue to be reviewed for visual scale and shore readability now that it touches the south edge through at least one full macro cell.

## Highest Priority Terrain Rule

Start with the Stonehearth plateau pattern before adding any visual detail:

1. Build a low-resolution macro height map.
2. Expand each macro value into large flat terrain blocks.
3. Quantize the expanded heights into readable terrain bands.

This is the core shape recipe to preserve. Plains and settlement areas should have tiny local variation, about 0-2 blocks. Foothills should change height in 8-block shelves. Mountains should change height in 12-block shelves.

If a later terrain idea fights this rule, this rule wins. The world should read first as calm flat plates separated by strong blocky cuts, then as detailed wilderness after edge detail, water, materials, and scatter are layered on top.

## Highest Priority Surface Strata Rule

Settlement plains should use a real thick dirt and soil body under the grass cap.

Use the Stonehearth plains pattern as the reference:

1. The top visible layer is grass on normal plains.
2. The block directly below the grass is not rock.
3. The exposed side wall below the grass reads as multiple blocks of dirt and soil.
4. Soil strata can alternate in broad horizontal bands to make cliff faces readable.

For Deepdraft, the central valley and settlement plains should usually render as:

- 1 block grass cap,
- 4-8 blocks of dirt / light soil / dark soil beneath the cap,
- stone only below the soil body or where slope, mountain influence, bank rules, or exposed-rock rules override it.

This is important for the Stonehearth look. A grass top sitting directly on stone will make the plateaus feel too harsh and too Minecraft-like for the valley floor. The mountain should be rock-heavy; the plains should be earth-heavy.

## Highest Priority Grass Palette Rule

Use grass colour as domain language, not random speckle.

Deepdraft currently has more grass variants available, but this world-generation pass should use the first eight as the intentional Stonehearth-style surface set:

- Lower plains and settlement areas use `grass_01` through `grass_04`.
- Valley, highland, and foothill areas use `grass_05` through `grass_08`.

Within each domain, choose a calm base grass for the broad interior of a patch, then use lighter grass variants on patch edges and terrace lips. The edge-lightening should be region-aware: it outlines large grass areas and plateau borders, not individual random blocks.

The visual target is the screenshot pattern: broad muted green interiors, lighter green bands along edges, and no noisy checkerboard grass.

## Design North Star

Deepdraft should borrow Stonehearth's clarity, not copy Stonehearth's systems or assets.

Stonehearth's useful lessons:

- Large readable landforms matter more than noisy detail.
- Broad flat terraces make settlement choice legible.
- Terrain reads in calm macro regions: valley, foothills, mountain, water, forest, stone.
- Elevation changes are usually strong terrace drops, not gentle slopes.
- A visible terrace step often reads as roughly 8 blocks of vertical side wall between grass/dirt foothill elevations.
- Mountain terrain uses larger jumps than grassland terrain, now 12 blocks between authored rock shelves.
- Landform edges get detail after the broad shape is established.
- Visual props such as trees, rocks, flowers, and shrubs are separate scatter entities, not terrain-block noise.
- Distant map boundaries are softened by atmosphere, trees, and simple silhouettes.

Deepdraft's hard difference:

- Deepdraft is a true voxel/block simulation. World data decides block identity.
- Rendering may simplify exposed faces, but it must not invent a painted heightmap that disagrees with generated blocks.
- Terrain is not only scenery. It becomes mineable, pathable, inspectable, collapsible simulation space.

## Stonehearth Terrain Observations

The reference screenshot shows a terrain style built from large, flat stacked plates.

Important visible traits:

- The top surfaces are broad and quiet. They are not rolling height noise.
- Elevation changes happen as clean vertical terrace walls.
- Several adjacent grass/dirt plateaus differ by about 8-12 blocks of height. Use 8 blocks as the Deepdraft first-pass foothill target for major terrace steps.
- Mountain shelves differ by about 15 blocks of height in the reference. Use 12 blocks for Deepdraft's current six-shelf ladder so the mountain fits cleanly from Y44 through Y115.
- Terrain side walls use layered bands: a green grass cap, a pale dirt/soil band beneath it, then darker brown earth or stone below.
- The vertical faces are flat and readable, with occasional inset/protruding edge detail. They are not covered in one-block material static.
- The terrace outlines are mostly rectilinear or gently stepped, with diagonals and cut corners used sparingly to avoid a perfect square grid.
- Grass colour is domain- and edge-aware. Broad interior grass reads darker or calmer, while grass near terrace lips and patch borders is lighter.
- Trees and boulders sit on top of the terrain as separate objects. They do not define the terrain height.
- Forest density helps hide repetition, but the terrain slabs remain legible even without props.
- Wider shots show a large calm central plain reserved for settlement placement. The terrain gets busier around it: forested edges, terraced approaches, and mountain shelves.
- Large lakes can touch the map edge. This makes the playable slab feel like part of a larger world instead of an isolated pond inside a box.

Deepdraft translation:

- Foothill and highland elevation tiers should snap to 8-block intervals.
- Mountain elevation tiers should snap to 12-block intervals for major shelves and faces.
- Adjacent mountain macro cells should climb gradually: shelf 1 -> shelf 2 -> shelf 3 -> shelf 4 -> shelf 5 -> shelf 6. Do not allow shelf 1 to directly neighbor shelf 3 or higher.
- The central valley should include one very large, mostly flat buildable plate, not only scattered small candidate patches.
- The southwest lake should be an edge-connected basin, touching the south or west boundary rather than floating fully inland.
- Lakes should respect the same 32x32 macro language as the rest of terrain generation.
- Minor local variation should happen inside a tier only after the broad flat plate has been chosen.
- Local variation must not cross a mountain shelf material boundary.
- Side-face material should communicate strata: surface cap, dirt/soil layer, then rock.
- Grass variants should be assigned by region and edge distance:
  - lower plains / settlement: first four grass variants,
  - valley / highland / foothills: next four grass variants,
  - edge bands use the lighter variants within that domain set.
- The block inspector and renderer must agree on every visible cap and side material. If a side is dirt-colored, it should represent a dirt/soil block or a clearly documented LOD approximation.

## Stonehearth Source Findings

Local reference reviewed: `P:\stonehearth`, especially `services/server/world_generation/` and `data/biome/*_generation_data.json`.

Useful implementation lessons:

- Stonehearth defines `TILE_SIZE = 256`, `MACRO_BLOCK_SIZE = 32`, and `FEATURE_BLOCK_SIZE = 16`.
- Terrain generation starts from a low-resolution micro map.
- Each micro-map value is expanded into a 32 x 32 macro block of flat land.
- A `NonUniformQuantizer` snaps raw height values to allowed elevation centroids.
- The temperate biome uses:
  - plains `step_size = 2`,
  - foothills `step_size = 10`,
  - mountains `step_size = 15`.
- The desert biome confirms the pattern is biome-tunable:
  - foothills `step_size = 5`,
  - mountains `step_size = 20`.
- Plains are special-cased: values at or below plains max are flattened to the plains max before later valley detailing.
- Foothills and mountains are quantized into large vertical bands, producing the shelf look.
- Post-processing cleans up macro-block shapes:
  - remove juts,
  - fill holes,
  - grow isolated peaks into larger blocks,
  - stamp valley templates into high plains.
- Edge detail is added after the main quantization, not before.
- Terrain side protrusions/outcroppings are generated only along step edges, using layer thickness, layer count, and unit length settings.
- Rendering turns height rectangles into regions, then adds terrain material layers:
  - plains get a one-block grass cap at normal plain height,
  - lower plain depressions can use a one-block dirt cap instead,
  - everything below the plains cap is filled with alternating soil strata,
  - foothills also get soil strata, with grass only when the shelf height aligns to the foothill step size,
  - mountains become rock layers.
- Stonehearth's soil strata alternate every 2 vertical blocks between `soil_light` and `soil_dark`.
- This means the thick dirt-looking side wall in plains is real terrain volume, not a decorative overlay.
- Stonehearth defines terrain ring tessellation for surface colour edges:
  - dirt has an edge band width of 8,
  - grass has lighter edge bands at widths 4 and 6,
  - hill grass has lighter edge bands at widths 3 and 5.
- The important lesson is not the exact widths; it is that grass edges are deliberately lighter than grass interiors.
- Water is selected in feature space, biased toward flat ground, cleaned up across tile boundaries, and then cut into the terrain volume.
- Trees, boulders, and plants are placed from feature maps after terrain, with flatness checks.

Deepdraft adaptation:

- Use a lower-resolution macro height layer before per-block height assignment.
- Use quantizer centroids instead of raw rounded noise for major terrain bands.
- Use Deepdraft-tuned equivalents of Stonehearth's step sizes:
  - plains / settlement plain: 0-2 local variation,
  - foothill and highland terraces: 8 blocks,
  - mountain shelves: 12 blocks.
- Give settlement plains a one-block grass cap over a thick soil body, not grass directly over stone.
- Use broad horizontal soil bands on exposed valley and plain terrace sides.
- Assign grass variants from domain-specific ranges:
  - plains / settlement use `grass_01` to `grass_04`,
  - valley / highland / foothills use `grass_05` to `grass_08`.
- Use lighter variants along grass patch edges, terrace lips, and shelf borders.
- Add shelf-edge detail only after major tiers are locked.
- Add cleanup passes that remove one-cell juts and fill one-cell holes in the macro maps.
- Keep water and scatter as feature maps that modify or decorate the terrain after the height tiers exist.

## Non-Goals

Do not include these in the first world-generation pass:

- Dynamic water cellular automata.
- Full river simulation.
- Flora entity spawning.
- Dwarf placement or settlement founding flow.
- Mining, collapse, or task-system implementation.
- Day/night sky cycling.
- Imported Stonehearth assets or copied proprietary data.

## Current Constraints

- World size: 1024 x 128 x 1024 blocks.
- Chunk size: 16 x 16 x 16 blocks.
- Bedrock at `Y = 0..3` is unmineable and must always exist.
- Save data stores namespaced block strings, not runtime integer IDs.
- Static definitions live in JSON; runtime behavior lives in GDScript.
- Block storage is authoritative through `WorldData`.
- Block definitions are authoritative through `BlockRegistry`.
- Surface props remain placed entities later; terrain blocks only store terrain.

## Core World Composition

The first map should use authored macro layout before local noise.

### 1. Northwest Mountain

The northwest side is the dominant mountain mass.

- Target height: Y44-Y115.
- Major shelf bands should be 12 blocks: Y44-Y55, Y56-Y67, Y68-Y79, Y80-Y91, Y92-Y103, and Y104-Y115.
- Adjacent 32x32 mountain macro cells should step up by at most one shelf.
- Broad stepped shelves and strong exposed stone.
- Sparse sheltered dirt/grass pockets only on low ledges.
- This is the main dig-in face and the visual identity anchor.

### 2. Central Valley Corridor

A wide valley runs along the mountain base.

- Target height: Y 20-27, with the settlement plain centered near Y 27.
- Include one dominant settlement plain in the middle of the map.
- First-pass target: at least 80 x 80 mostly-flat blocks, with local variation no more than 0-2 blocks across the core.
- Flat enough for settlement and trade-road logic later.
- Material mix: grass patches, dirt, exposed rock, road-ready soil.
- Should produce several 20 x 20 mostly-flat candidate areas near the mountain.
- The central plain should feel open and readable before trees or props are added.

### 3. Foothill Band

The transition between valley and mountain is stepped, not noisy.

- Target height: Y20-Y43.
- Major terrace drops should be 8 blocks: Y20, Y28, and Y36 shelf starts.
- Minor surface shaping inside each shelf can use 2-4 block changes.
- Mixed grass, dirt, and rock.
- This is where Stonehearth-like readable shelves matter most.

### 4. Southwest Lake Basin

The southwest becomes a lower basin with a large lake.

- Target ground height: roughly Y 20-27.
- Fixed lake floor at Y11 and water from Y12 through Y18.
- The lake footprint should use whole 32x32 macro cells.
- At least one full 32x32 lake cell should touch the south map edge. West-edge contact is acceptable as an additional bonus, but south-edge contact is required for the current authored layout.
- The edge-connected water should read like a larger body continuing beyond the playable map.
- Banks use dirt, mud-like dirt, and stone, never grass immediately at the water edge.
- Use wide, irregular shores with open water large enough to read from a zoomed-out camera.
- Future reeds and shrubs should be entity scatter, not terrain blocks.

### 5. Southeast Highland

The southeast gets a smaller forest highland / plateau.

- Target height: roughly Y20-Y43.
- Lower and calmer than the northwest mountain.
- Broad shelves that can later hold dense forest scatter.

### 6. World Edge Wilderness

The outer 20-30 XZ blocks become a dense wilderness belt.

- Terrain should rise, roughen, or grow visually denser near the boundary.
- Later flora scatter should be dense here.
- Fog and sky can hide distance, but block identity must not depend on fog or camera distance.

## Generation Strategy

Use a coarse-to-fine pipeline inspired by Stonehearth's terrain readability.

The key idea: create a calm macro world first, then add edge detail and block identity.

### Macro Cells

Use macro cells to guide shape and material regions.

- Start with 32 x 32 XZ macro cells for material regions.
- Use 16 x 16 chunk-column awareness for performance and plateau metrics.
- Do not hard-flatten every chunk. Chunk alignment is a bias, not a visible grid.

Macro-cell outputs:

- Dominant domain.
- Target height band.
- Settlement-plain membership.
- Stone family.
- Soil/grass tendency.
- Forest density.
- Road/corridor tendency.
- Settlement flatness score.

### Height Bands

Use non-uniform quantization:

| Region | Step Size | Purpose |
|---|---:|---|
| Lake basin | 1-2 blocks | Shallow, readable banks |
| Lowland shelf | 0 blocks | Y12-Y19 stack forced to surface at Y19 |
| Settlement/plain macro cells | 0 blocks | Forced 32x32 plates at Y19 inside the lowland band |
| Valley floor minor detail | 0-2 blocks | Buildable flatness outside forced settlement/plain cells |
| Foothill terrace | 8 blocks | Stonehearth-like level changes at Y20, Y28, and Y36 |
| Southeast highland | 8 blocks | Calm plateau structure using the foothill band |
| Mountain | 12 blocks | Monumental rock shelf bands at Y44-Y55, Y56-Y67, Y68-Y79, Y80-Y91, Y92-Y103, and Y104-Y115 |

After quantization, add limited edge detail near cliffs and shelf boundaries. Do not re-noise entire flat areas.

Mountain shelf macro cells are special: once a cell has snapped into the mountain band, per-column local variation must not move it off its shelf top. Shelf 1 should remain Y55, shelf 2 Y67, shelf 3 Y79, shelf 4 Y91, shelf 5 Y103, and shelf 6 Y115. This keeps the material ladder stable and prevents small rock-band flecks caused by single-block height drift.

Transition cleanup must preserve the 32x32 macro-cell language. Do not use per-block distance fields for major shelf transitions; they create thin diagonal stair artifacts. The current approach is macro-cell based:

- Macro lowland classification requires at least 50% lowland samples and must beat valley count. Isolated non-anchor lowland macro cells with no cardinal lowland neighbor are promoted to valley. Southwest basin and settlement/plain anchors are protected.
- Mountain approach: cells one macro step from mountain are raised to Y43, two steps to Y35, and three steps to Y27.
- Lowland approach: cells one macro step from lowland are capped at Y27, two steps at Y35, and three steps at Y43.
- Final shelf limit: all neighboring macro cells, including diagonals, may differ by only one shelf rank across the combined ladder: lowland, foothill 1, foothill 2, foothill 3, mountain 1, mountain 2, mountain 3, mountain 4, mountain 5, mountain 6. This prevents lowland from touching foothill 2, foothill 2 from touching mountain 1, and mountain 1 from touching mountain 3 at corners.

Edge detail is a final heightmap pass, not a new material system. It applies only after water and shelf cleanup are complete:

- Source columns must be foothill shelf 1-3 or mountain shelf 1-6.
- Lowland, settlement/plain, lake, tarn, and water-bank columns are protected.
- A source edge must have exactly one lower cardinal neighbor direction; convex corners are left clean.
- Foothill detail pushes 1-2 columns outward. Mountain detail pushes 1-3 columns outward.
- Pushed heights stay within the source shelf band, so foothill detail continues to use the existing dirt/grass strata and mountain shelf 1 remains `rock06`, shelf 2 remains `rock05`, and so on.

The preferred first-pass rule is two-stage quantization:

1. Choose a broad terrace tier: 8 blocks for foothill/highland terrain, 12 blocks for mountain terrain.
2. Allow small 0-2 block surface offsets inside the tier only where they do not destroy buildable flatness.

This should create the Stonehearth read: large green plates separated by clear earth/stone walls.

Lowland columns whose generated height lands in Y12-Y19 should be forced to the full lowland shelf with surface top Y19. The material stack is Y12-Y13 `dirt_01`, Y14-Y15 `dirt_02`, Y16-Y17 `dirt_03`, Y18 `dirt_04`, and Y19 `grass_01..grass_04`. Settlement/plain macro cells are a stricter subset of lowland: they are forced as 32x32 plates with no height variation, and their surface top is Y19.

Foothill plateau tops should use the top of each 8-block shelf: Y27, Y35, and Y43. Within each foothill shelf, force the visible strata from bottom to top as `dirt_01`, `dirt_01`, `dirt_02`, `dirt_02`, `dirt_03`, `dirt_03`, `dirt_04`, then a `grass_05..grass_08` cap. This foothill rule should be tested before applying the same kind of forced strata to other domains.

For any foothill-or-higher column, body blocks below the active surface shelf should use the matching altitude rock band. `base:terrain:rock:rock10` appears in Y12-Y19, `base:terrain:rock:rock09` appears in Y20-Y27, `base:terrain:rock:rock08` appears in Y28-Y35, and `base:terrain:rock:rock07` appears in Y36-Y43.

Mountain shelves should use forced rock strata: Y44-Y55 `base:terrain:rock:rock06`, Y56-Y67 `base:terrain:rock:rock05`, Y68-Y79 `base:terrain:rock:rock04`, Y80-Y91 `base:terrain:rock:rock03`, Y92-Y103 `base:terrain:rock:rock02`, and Y104-Y115 `base:terrain:rock:rock01`. For any mountain column, Y12-Y43 uses the altitude-banded body rocks (`rock10`, `rock09`, `rock08`, `rock07`), while Y4-Y11 remains the hardcoded `base:terrain:rock:rock11` foundation.

The authored rock color ramp should stay dark enough for the overview renderer: `rock01` `#879199`, `rock02` `#78838C`, `rock03` `#697680`, `rock04` `#5B6973`, `rock05` `#4E5C67`, `rock06` `#424F5A`, `rock07` `#36444E`, `rock08` `#2D3943`, `rock09` `#25303A`, `rock10` `#1D2630`, and `rock11` `#151A22`. Keep `rock11` visually close to bedrock `#111116`.

## Pipeline

### Phase 1 - Seed and Noise Setup

Create deterministic noise layers once per world seed.

Required layers:

- `noise_domain`: broad macro layout.
- `noise_mountain`: ridge and peak detail.
- `noise_valley`: low-amplitude valley detail.
- `noise_material`: stable macro material field.
- `noise_cave`: underground voids.
- `noise_ore`: ore and gem veins.
- `noise_soil`: cave soil and local soil variation.

Rules:

- Use separate `FastNoiseLite` instances per logical layer.
- Use fixed seed offsets.
- Never use runtime random calls for block identity or surface variants.

### Phase 2 - Macro Layout Maps

Build 2D maps for every XZ column before any 3D chunks are filled.

Required maps:

- `domain_map`: mountain, foothill, valley, lowland, highland, edge.
- `domain_value_map`: raw value for blending and debug display.
- `settlement_plain_map`: large central buildable plate.
- `mountain_influence_map`: northwest mountain strength.
- `valley_corridor_map`: distance to valley path.
- `basin_map`: southwest lowland basin strength.
- `edge_lake_map`: southwest lake body that reaches the map boundary.
- `highland_map`: southeast plateau strength.
- `edge_belt_map`: boundary wilderness strength.

The map should not look like random blobs. It should have a clear authored composition:

- mountain in the northwest,
- broad settlement plain near the center,
- valley through the center,
- basin in the southwest,
- highland in the southeast,
- wilderness around the edge.

### Phase 3 - Heightmap

Compute raw height from macro layout, then quantize.

Height pass order:

1. Start with domain target height.
2. Blend between adjacent domains.
3. Stamp the central settlement plain as a large mostly-flat plate.
4. Pull valley corridor flatter and lower around that plate.
5. Pull southwest basin lower.
6. Raise southeast highland gently.
7. Add mountain ridge detail only inside strong mountain influence.
8. Assign broad terrace tiers where the landform should read like stacked plates: 8-block tiers for foothills/highlands and 12-block tiers for mountain shelves.
9. Add small intra-tier variation only on selected shelf edges and non-settlement areas.
10. Apply chunk-aware plateau smoothing only where local variance is already low.
11. Add edge detail around terrace boundaries.

Validation metrics:

- min, max, and average surface height,
- height range by domain,
- central settlement plain size and height variance,
- percentage of terraced columns,
- plateau-adjusted column count,
- number of settlement candidates.

### Phase 4 - Water Bodies

Create water bodies after the heightmap exists.

Water features:

- Large southwest lowland lake built from 32x32 macro cells.
- Smaller mountain shelf lake built from 32x32 macro cells.
- Bank mask around lake and tarn.

Rules:

- Water footprints should be broad and irregular, not circular noise dots.
- The southwest lake footprint should intentionally overlap the south boundary with at least one full 32x32 cell.
- Boundary water should continue cleanly to the edge-slab/void presentation instead of ending as an accidental hard shore.
- The lowland lake floor is Y11, with water blocks filling Y12-Y18.
- The mountain shelf lake must be on mountain shelf 1, with floor Y47 and water blocks filling Y48-Y54.
- The mountain shelf lake must be surrounded by 32x32 mountain shelf 1 or shelf 2 plateau cells. This surround is a hard lake invariant and should be restored after the first global shelf limiting pass.
- After restoring the mountain shelf lake surround, run the macro shelf limiter again. The restore pass can force cells back to mountain shelf 1; the second limiter preserves the global one-shelf adjacency rule so mountain shelf 3 cannot touch mountain shelf 1 across an edge or corner.
- Bank columns force dirt or stone surface materials.
- Dynamic water flow is out of scope for this plan.

Validation metrics:

- lake center,
- lake macro-cell count / footprint column count,
- lake edge contact side and contact width,
- lake waterline,
- lake floor min/max,
- tarn center,
- tarn waterline,
- mountain shelf lake macro-cell count,
- bank column count.

### Phase 5 - Material Region Maps

Pick material regions before choosing individual surface blocks.

Required maps:

- `stone_region_map`: deprecated; authored height bands now force `rock11` in Y4-Y11, `rock10` through `rock07` in Y12-Y43 body bands, and `rock06` through `rock01` in Y44-Y115 mountain shelves.
- `grass_region_map`: broad grass palette regions, domain palette group, and edge-lightening bands.
- `soil_region_map`: dirt depth, bank soil, road-ready soil, light/dark soil strata.
- `forest_density_map`: future scatter guidance.
- `scree_map`: steep rock and loose-stone visual areas.

Rules:

- Material regions should be contiguous enough to read at camera distance.
- Hash noise may choose variants inside a region, but must not decide the entire region one block at a time.
- Grass should never appear on steep slopes or immediate water banks.
- Mountain tops should be mostly exposed rock.
- Valley floors should mix grass, dirt, and rock in broad patches.
- Settlement plains should expose thick dirt/soil sides under grass caps.
- Soil depth should be region-scale, not one-block random noise.
- Grass colour must be selected from the domain palette group before local variation.
- Grass edge bands should use lighter variants to trace patch borders and terrace lips.
- Do not use all grass colours everywhere.

Target first-pass ratios:

| Domain | Target Surface Read |
|---|---|
| Mountain | 90-98% rock |
| Foothills | 30-50% grass, rest dirt/rock |
| Valley | 40-60% grass, with dirt and rock breaks |
| Lowland basin | dirt/grass mix away from water |
| Water banks | dirt/stone, no grass |

### Phase 6 - Block Fill

Fill chunk columns lazily or on demand after the 2D maps are ready.

Per-block rules:

1. `Y = 0..3` is always bedrock.
2. `Y = 4..11` is always `base:terrain:rock:rock11`.
3. The remaining underground mass above the foundation follows the authored strata and stone-selection rules.
4. Above visible terrain is void, except water columns up to waterline.
5. Surface block comes from material maps.
6. Plains and settlement areas use a one-block grass cap over a thick dirt/soil body.
7. The plains soil body should usually be 4-8 blocks deep, with broad light/dark horizontal strata.
8. Foothill shelves use only the active 8-block dirt/grass shelf above an altitude-banded rock body. Below the active foothill shelf, use `rock10` in Y12-Y19, `rock09` in Y20-Y27, `rock08` in Y28-Y35, and `rock07` in Y36-Y43; do not let those rocks bleed outside their bands.
9. Mountains are rock-first. For mountain shelf columns, Y12-Y43 follows the altitude-banded body ladder, then Y44-Y115 follows the shelf-specific `rock06` through `rock01` ladder.
10. Mountain shelf tops must stay snapped to their shelf top heights. Local variation should not create one-block material boundary noise.
11. Edge detail must preserve the source shelf's material contract by keeping pushed heights inside that shelf band.
12. Water banks override grass with dirt, mud, or stone.
13. Grass surface variants are chosen by domain and edge distance:
   - lower plains / settlement interiors: `grass_01` or `grass_03`,
   - lower plains / settlement edges: `grass_02` or `grass_04`,
   - valley / highland / foothill interiors: `grass_05` or `grass_07`,
   - valley / highland / foothill edges: `grass_06` or `grass_08`.
14. Caves are carved only below a surface buffer.
15. Ores and gems are selected by depth and noise threshold.
16. Cave soil appears in its depth band.
16. Remaining volume is stone.

Important:

- Missing ungenerated chunks may read as air, but renderer logic must avoid fake cut walls at streaming boundaries.
- Generated block identity must match inspector and renderer output.

### Phase 7 - Future Scatter Maps

Do not spawn flora in this milestone, but generate maps that make later placement easy.

Future scatter candidates:

- dense edge forest,
- valley trees,
- mountain pines / junipers,
- boulders,
- scree,
- flowers / shrubs,
- road-side detail,
- lake bank reeds.

Placement rules for later:

- Large props need local flatness checks.
- Plant visual overhangs do not create extra terrain collision.
- Props are placed entities, not terrain blocks.

## Rendering and Validation Plan

The renderer may simplify geometry, but it must simplify exposed block faces.

### Accepted Render Modes

1. Near streamed chunk mesh
   - Uses generated chunks.
   - Emits real exposed block faces.
   - Used for inspection, mining, selection, and close review.

2. Block-face overview mesh
   - Uses deterministic generated column data.
   - Emits top faces and vertical faces at sampled height drops.
   - Greedily merges same-material, same-plane faces.
   - Labels itself as an approximation in debug UI.

3. Future world-edge presentation slab
   - Large, calm boundary panels.
   - Not a per-block noisy side dump.
   - Must not contradict visible playable surface blocks.

### Rejected Render Modes

Do not use these as the main validation view:

- top-only painted heightmap,
- fake grass/dirt/rock side bands,
- screen-space or fog-dependent material choices,
- one vertical wall stripe per terrain sample at the world boundary.

## Debug Tools

The debug overlay should expose:

- map readiness,
- active render mode,
- overview step,
- overview sampled and merged face counts,
- overview validation mismatch count,
- domain percentages,
- surface material percentages,
- height min/max/average,
- water body stats,
- settlement candidate count,
- generated column count,
- mesh count and queue count.

The block inspector should show:

- render mode,
- hit source,
- face direction,
- hit block key,
- generated block key,
- agreement yes/no,
- coordinate,
- domain,
- surface Y,
- visible top Y,
- water/bank flags,
- kind,
- color.

## First Milestone

Implement only the low-risk shape and validation pass.

1. Build or preserve the macro layout maps.
2. Generate northwest mountain, central valley, southwest basin, southeast highland, and edge belt.
3. Quantize terrain into readable terraces.
4. Select surface materials from macro regions.
5. Carve lowland lake and mountain tarn.
6. Add or preserve debug metrics for the above.
7. Validate that inspector, generated blocks, and render output agree.

Definition of done:

- Mountain reads as exposed stone from the initial camera.
- Valley has several obvious settlement candidates.
- Lake and tarn exist with non-grass banks.
- Surface is not a grass blanket.
- Overview mode is block-face based, not top-only.
- Debug metrics print and overlay cleanly.

## Second Milestone

Improve presentation and performance after the first milestone is stable.

1. Add world-edge presentation slab.
2. Improve overview side-face merging.
3. Add sampled comparison tests between overview and generated chunks.
4. Add road/path mask through the valley.
5. Add scatter maps for future flora and boulders.
6. Add screenshots or repeatable debug captures for terrain review.

## Open Questions

- Should the mountain always be northwest, or should future seeds rotate the macro composition?
- Should the first trade road be visible immediately as packed dirt?
- Should snow or cold high-altitude stone exist in the first pass?
- Should settlement candidates become actual UI hints or remain debug-only?
- How calm should the eventual world-edge slab be compared with the current block-face overview?

## Implementation Notes

- Keep generation deterministic.
- Keep terrain identity in data, not renderer tricks.
- Keep block IDs namespaced at save boundaries.
- Keep bedrock immutable at `Y = 0..3`.
- Prefer metrics before visual tweaking.
- Use broad regions first, local detail second.
- Do not make decisions from screenshots of a top-only surface view.
