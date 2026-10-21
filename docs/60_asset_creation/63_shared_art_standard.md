# 63 — Shared world art standard

> **2026-10-20:** the visual target has moved to the Hearthblock direction; see the
> update at the top of [64](64_hand_hewn_art_direction.md). The technical rules below
> are unchanged. World lighting presentation is owned by `SkyController`'s
> `hearthblock_lighting` block ([255](../00_dev_roadmap/255_hearthblock_lighting_pass.md)).

**Current direction (2026-10-18): 1:16 chibi / stylized voxel craft on the existing
simple world blocks.** [64 — Hand-hewn art direction](64_hand_hewn_art_direction.md)
and its original concept image are the visual authority. The player accepted
the native timber models provisionally; their present quality does not replace
the concept's higher target. [237 — Production installation](../00_dev_roadmap/237_hand_hewn_timber_activation.md)
records their integration.
The player-approved chunky resource extension is recorded in
[238](../00_dev_roadmap/238_chunky_mined_resources.md). Ten stone/ore/soil variants
remain after the four unused stone types were removed in
[251](../00_dev_roadmap/251_retired_stone_types.md).

All **382** current production models use the 1:16 object pipeline. The complete
migration and retirement history is recorded in [224](../00_dev_roadmap/224_voxel_migration_progress.md)
and [234](../00_dev_roadmap/234_retired_uncraftable_furniture.md). This standard
supersedes earlier faceted geometry instructions. Historical milestone reports
remain evidence of their own revisions, not current build commands.

## Scale and form

One world block is one Godot unit. The **1:16 ratio is linear on every axis**:
sixteen micro-voxel cells span one world-block edge. One cell is **1/16 block =
0.0625 Godot unit**; a full block volume contains 16×16×16 possible cells. Objects
may span multiple world blocks; they are not all limited to 16×16×16 cells.
Solid object vertices lie on this local grid, with unit export/root transforms.
Author occupied cells or analytic solid shapes and bake their exposed surfaces
using the shared greedy mesher.
Never create a node per voxel. Wider two/four-cell steps are useful for substantial
wood or foliage when they preserve the approved silhouette at colony zoom.

**Chibi describes proportions and readability, not spherical geometry.** Favor
chunky silhouettes, expressive features, broad clipped forms and deliberate
asymmetry. Use the original concept in [64](64_hand_hewn_art_direction.md) as the
visual target; the [221 study](../00_dev_roadmap/221_micro_voxel_art_study.md)
and native galleries in 224 remain technical and historical references. Preserve
broad expressive heads, substantial boots and mittens, distinct animal silhouettes, clustered
foliage and readable crafted joinery. Detail should explain the object: bark,
end grain, pegs, seams, fruit, flowers or metal fittings. Avoid random per-cell
color noise. The grid is an authoring rule, not a requirement to expose every
possible tiny step.

- Trees retain species-specific crowns, growth stages, seasons, fruit/picked
  forms and deterministic variants. Bushes retain growth, harvest and packed roots.
  [242](../00_dev_roadmap/242_chibi_tree_refinement.md) gives trees substantial
  offset foliage lobes, fuller pine boughs, broad oak crowns, compact apple crowns
  and dense upright junipers. `voxel_trees.json` and `trees.py` own these forms.
  Preserve existing height envelopes, ground contact, trunk footprints and
  four-block low-geometry clearance. Fruit/blossoms must touch the final canopy
  and remain visible; juniper picking removes only berries. Bare branch geometry
  remains connected to the grounded trunk. The earlier pine pilot's exact
  silhouette is superseded; its grid, material and proxy contracts remain.
- Wild plants use the complete 76-model refinement in
  [243](../00_dev_roadmap/243_chibi_plant_refinement.md): broader shrub foliage,
  exposed berries, substantial flowers and thicker reed blades. `plants.py` and
  `voxel_plants.json` retain every young/seasonal/picked/packed path. Young crowns
  must fit below their existing clearance with real depth; do not truncate a
  mature canopy into a flat lid. Packing translates the exact plant; picking
  removes only fruit, preserving the remaining colors. Fine stems stay connected.
  Crop helpers retain their earlier contract; this revision does not add farming.
- Dwarves retain detached hands/feet, all appearance pools, contacts and occupations.
  Balanced body/head widths are baked into vertices; runtime width factors are 1.
  [241](../00_dev_roadmap/241_chibi_dwarf_refinement.md) sculpts broad hair locks,
  substantial beards, cheeks/brows and workwear in `voxel_dwarves.json`. Preserve
  the eye layout, hand/foot envelopes, torso front at or behind cell Z8, maximum
  54-cell height and logical 1×3×1 body. Do not restore the pilot's full silhouette
  merely to satisfy obsolete geometry-equality tests; retain its actual contacts.
- Animals use rigid pivots. Deer/wolf knees and duck wings fold without nonuniform
  scaling. Large-wolf proportions are baked; its presentation scale is 1.
- Starter furniture uses rough logs, pegs and hay. The workbench remains a stump;
  bridges remain whole logs; log doors are frameless. Later tiers add joinery,
  dressed stone, metal or upholstery only where the existing item calls for them.
- Tiny produce and tools must read at inventory/carrying scale. Crates have distinct
  low/half/full contents and preserve their wooden shell.

Keep local origins and articulation coordinates. Most standing forms are centered
horizontally with ground at Y0; cell-aligned floors fill [0,1]^3, bridges sit below
their walking plane, and limbs/tools retain joint-local coordinates. Do not recenter
parts. Uniform fitting in storage/catalogues is intentional; nonuniform actor
stretching is not. Navigation, occupancy, interaction coordinates and save IDs are
owned by gameplay definitions and must not be redesigned to fit art.

## Production inventory and sources

| Family | Location under `assets/models/` | GLBs |
|---|---|---:|
| Trees | `flora/trees/` | 94 |
| Bushes, flowers, reeds | `flora/{bushes,flowers,reeds}/` | 76 |
| Defined crops | `flora/crops/` | 14 |
| Ground stones | `rocks/` | 6 |
| Dwarves and their work tools | `characters/dwarves/` | 43 |
| Eyelids and meal servings | `presentation/` | 3 |
| Wildlife | `animals/` | 21 |
| Furniture, support forms and flame libraries | `furniture/` | 33 |
| Loose goods | `items/` | 88 |
| Structural floors and materials crate | `construction/` | 4 |
| **Total** | | **382** |

Crops fill previously missing **defined art paths**; their existence does not add
new farming behavior. Milestone 234 removes fifteen unavailable furniture designs
and their old saved forms. Sixteen craftable designs, the settlement flag and
wet/dry stones remain. Historical studies remain under `studies/`, outside production.

Current authoring inputs are `data/art/voxel_*.json`, semantic swatches in
`data/materials/craft_materials.json`, and native shape layouts in
`tools/voxel_assets/`. `build.py FAMILY` writes a complete staged manifest and GLBs.
`Gallery.gd --family=FAMILY` reviews the staged bytes in Godot. `activate.py` requires
that complete, exact-hash review before installing. `build.py FAMILY --check`
regenerates and compares every installed byte. `test_retirements.py` checks current
production coverage, hashes, retirement guards and retained recipes. The older
`final_audit.py` is the frozen milestone-224 audit against its original saves and
presentation-only scope. Retirement exceptions are explicit in
`data/content_retirements.json`; full furniture builds prune retired staged files.

The frozen migration inventory remains historical evidence. Subsequent approved
models are listed by family in `data/art/voxel_additions.json`; coverage requires
both the original paths and these additions.

The 14 mined stone/ore/soil items use the approved chunky resource concept,
implemented by `mined_resources.py` with authored heights, clefts, chips and
deposits in `voxel_mined_resources.json`. Species palettes in `voxel_items.json`
distinguish five stones, six ores including coal, and three soils. Stone, ore and
soil have three distinct connected silhouettes within the unchanged
12×12×12-cell envelope (0.75 units), unit root and ground contact. Broad ore
deposits replace repeated stripes; soil has joined clods and embedded pebbles.
[238](../00_dev_roadmap/238_chunky_mined_resources.md) records the native models,
scope, tests and costs. Current editable VOXs are under
`VoxelFeed/colored/chunky_resources/`.

The original player model at `data/art/sources/stone_ore_dirt.vox` and its source
fingerprint remain preserved as `mined_original_source` for recovery. The exact
spherical occupancy requirement from [225](../00_dev_roadmap/225_player_mined_resource_shape.md)
was superseded by the player's explicit approval of the chunky design. Gem,
terrain, scenery boulders and wet/dry stone devices retain their existing owners.
The live VoxelFeed original is not overwritten by builders.

The accepted timber family now comes from `voxel_hand_hewn_timber.json` and
`tools/voxel_assets/hand_hewn_timber.py`. The `hand_hewn_vox` furniture operation
routes stools, dining tables, game tables and workbenches through that shared
owner. Loose timber uses its exact rotated stool occupancy. These source shapes
match the provisionally accepted native study; preserve the original concept
as the artistic target, rather than treating this implementation as finished art.

Stools remain 14×14×14 cells, with the established 0.875-unit seat contact. The
dining table has a 46×46-cell, eight-cell-thick slab above a centered 16×16×16-cell
pedestal. Its total size is 2.875×1.5×2.875 units, inside the 3×3 footprint. Four
separate stools at the existing close guides retain the complete 5×5 arrangement.
The game table shares its exact body, adding painted board marks and six supported
square counters at Y24. Their tops are at 1.5625; the existing counter-clearance
region now encloses their complete width. The workbench remains a 46×16×46-cell
solid stump with shallow scars, a 3×3 footprint and four-sided working contacts.

Each of oak, pine, juniper and applewood has a dedicated set of `hewn_*` semantic
swatches in CraftMaterials. These four furniture definitions and the log bench
use the `hand_hewn_timber` palette; other wooden furniture and tools retain their prior
palettes. Game-counter colors stay fixed. The four loose wood resources bake the
same species colors and stool shape rotated onto its side, at 0.875-unit size.
Ground storage, carrying and ordinary uniform shelf fitting remain unchanged.

Current editable models are in `VoxelFeed/colored/hand_hewn_timber/` (five designs
in four woods). Original player VOXs and the earlier `log_chair.py`, `log_table.py`,
`workbench.py` and organic-log helper remain historical source/recovery material.
Their older `VoxelFeed/colored/` outputs are superseded for this family. Do not
run an older authoring recipe to replace the accepted production models. Current
full-family builders and `author_furniture.py` preserve the accepted routing.

The table-local chair profiles, footprint, working point, material IDs and saved
identities remain owned by gameplay. [239](../00_dev_roadmap/239_thicker_log_tabletops.md)
records the approved four-to-eight-cell slab change and its matching hand/meal
contacts. The head pose rises two cells to clear long beards during idle bobbing
and game nods; the torso remains supported on the unchanged stool. Ordinary
stools retain their original profile. Keep these contracts when improving art.
See [237](../00_dev_roadmap/237_hand_hewn_timber_activation.md) for source, imported
palette, interaction, save and reproducibility evidence.

[244](../00_dev_roadmap/244_chibi_timber_refinement.md) refines this same family with
authored unequal bark plates, chipped shoulders, incomplete grain and deeper
splits. The dimensions, source palette mapping and gameplay contacts above remain
unchanged. Extra edge geometry is recorded in the milestone; retain the separate
shadow proxies and validate real imported material variants after regeneration.

[248](../00_dev_roadmap/248_chibi_log_bench.md) adds the two-cell log bench through
`voxel_log_bench.json`, `log_bench.py` and the `log_bench_vox` operation. Its native
32×16×16-cell envelope reserves 2×1 floor cells, or 1×2 after rotation, with the
seat at Y16. The chibi torso rests on that plane and the boots stand ahead of it;
the definition owns their corrected pose and clearance. It uses the same four
wood palettes and one greedy visual mesh plus a shadow-only proxy. Its four
editable models live separately in `VoxelFeed/colored/log_bench/`.

Installed manifests in `data/art/voxel_manifests/` are the current export authority.
Historical faceted builders are guarded against overwriting these paths. Do not
hand-edit `.import` or `.tres`; use Godot's importer. Root scale stays 1.

The [245 furniture extension](../00_dev_roadmap/245_chibi_buildable_furniture.md)
uses the opt-in hewn beam sampler in `solid_shapes.py`, authored by
`author_furniture.py` into `voxel_furniture.json`. Keep the continuous twelve-cell
bed sleep plane, exact shared gate/fence post cells, flush bridge gap and lowered
landing tails. Wood appearance must use the existing semantic palette roles.
All three flame libraries, light settings, moving pivots and furniture definitions
are unchanged. The new native captures and geometry costs are recorded in 245.

## Materials and shadows

Use one opaque vertex-color surface per rigid mesh, with shared/cached resources
through the existing owner. Convert authored sRGB to linear `COLOR_0` exactly once.
No palette texture is needed for this pipeline. A shared material helps reuse but
does not guarantee one draw call for unrelated MeshInstances.

Preserve runtime skin/hair/eye tints and baked clothing/boot colors. Furniture and
starter tools use exact semantic wood colors from CraftMaterials; hay, stone,
metal, leaves and flame must not accidentally share recolorable wood swatches.
Test pine, oak, juniper and applewood on actual imported geometry. Recolor copies
through the owner without modifying cached source meshes. Retain established gem
gloss, flame emission and underground/slice lighting.

Each casting rigid part contains **VoxelVisual / VoxelShadowProxy** siblings
(or globally unique suffixed names) under the same moving pivot. The shared baker
uses coarser inscribed density where possible. Thin branches/limbs and tiny objects
may retain fine proxies when a coarse version would erase their silhouette.
Do not claim every proxy has fewer triangles; manifests record those fallbacks.

`VoxelShadowSetup.configure(root)` sets the detailed mesh to **Off** and the proxy
to **Shadows Only**, with proxy GI disabled. Every loader must configure its output
before rendering, including isolated galleries and special placement paths. Bare
GLBs cannot encode Godot's casting flags. `set_casting(root, false)` preserves a
noncasting policy through later world-light binding, for ghosts, thumbnails,
portraits and lights whose existing definition disables body casting.

Flames, eyelids and servings carry explicit noncasting metadata. Never assign
visible/emissive/transparent materials to a proxy. Picking, bounds, recoloring,
readability outlines, portrait cloning and terrain floor baking use visual meshes
only. A proxy remains scene-tree-visible so Godot can draw it into the shadow pass.

Rigid reflections use `RigidMeshReflection.gd`: reflected vertices, corrected
normals/tangents/winding and cached immutable meshes, with positive render scales.
Closed voxel actors/furniture use backface culling. The closed and existing
underground shaders share the same lighting body; do not fork lighting equations.

## World and effect boundaries

World terrain, liquid simulation, sky, fog and weather retain their established
owners and styles. The atmosphere remains the quiet diorama backdrop from
[166](../00_dev_roadmap/166_diorama_sky.md). Grass is a full seasonal world voxel;
subtle terrain edge shading and damp-ground behavior remain unchanged.

Structural floor models are solid unit tiles. ConstructionFloorArt extracts only
visual boundary faces into the terrain batch, where exposed-face culling still
operates at world-block scale. No extra per-tile proxy node is needed in that batch.

Existing bounded noncasting cube dust/chips, splash foam and duck wakes are
intentional effects. Keep their opacity, fading and motion appropriate to the
effect instead of replacing them with dense solid voxel objects. The illustrated
menus, HUD, icons and outlines retain their own established visual language.
The final coverage report records these exceptions explicitly.

## Required acceptance for a family revision

1. Regenerate all defined variants, not only the mature summer example. Preserve
   state availability, IDs, paths, pivots and saved forms.
2. Pass source mesher/proxy tests and imported root/grid/palette/part checks.
   Source vertices are exact; imported compression uses the documented tolerance.
3. Review native close and colony views with matched lighting/camera, all relevant
   poses/materials, proxies, portraits, catalogue and carrying/packed states.
4. Exercise affected gameplay: worker tasks, contacts, storage, placement, picking,
   navigation, season refresh and save/restore. Do not waive behavior assertions
   to accommodate art; adapt obsolete single-mesh fixtures to paired visuals.
5. Record byte-identical regeneration, full coverage, geometry/file cost and native
   performance evidence. Save a checkpoint with remaining failures stated plainly.

Use copied saves in isolated profiles. Do not touch player originals or create a
Windows playtest export unless explicitly requested. Compare full-world frame/GPU
cost against a matched fixture; a static gallery or triangle reduction is not a
whole-game speedup. One fast GPU does not establish low-end hardware support.
