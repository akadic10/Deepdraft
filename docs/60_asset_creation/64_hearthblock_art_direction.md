# 64 — Hearthblock art direction

**Hearthblock is Deepdraft's only art direction.** It means cozy, warm, friendly chibi
voxels built from squares and rectangles on the 1:16 grid. Models are designed for the
gameplay camera and lit like a hearth. The owner chose it on 2026-10-20. By 2026-10-21
everything the game can show had been converted and the owner signed off the result.

- [255 — Lighting pass](../00_dev_roadmap/255_hearthblock_lighting_pass.md) records the lighting.
- [256 — Hearthblock art](../00_dev_roadmap/256_hearthblock_art_pilot.md) records the models,
  the terrain dressing and the menu pictures.
- [61 — Voxel art authoring guide](61_voxel_art_guide.md) explains how to build a model.
- [63 — Technical art standard](63_shared_art_standard.md) gives the renderer, pipeline
  and acceptance rules.
- The approved proposal models are kept verbatim in `tools/hearthblock/art/proposal.mjs`.
  They come from the owner's proposal page, "Deepdraft Hearthblock Style".

Earlier art directions were retired on 2026-10-21 and their documents removed:
faceted low-poly (2026-10-12/13), the first 1:16 voxel look and the hand-hewn timber
concept with its chibi refinements (2026-10-18/19). Git history before that cleanup
still holds them. Do not revive them as targets.

## Scope and grid

Hearthblock covers every solid non-terrain asset:
- dwarves and their work tools;
- animals, trees and wild plants;
- furniture, construction pieces and stored goods.

It also covers the dressing drawn on terrain blocks.

- One cell is **1/16 of a world block on each axis**: 0.0625 Godot units. Sixteen cells
  span one block edge, and a block is one Godot unit. Objects may span several blocks
  at the same cell size.
- World blocks stay one unit with simple voxels. Hearthblock only dresses the stone,
  grass and earth faces in the shader (`terrain_appearance.gdshaderinc`, values in
  `data/terrain/appearance_profiles.json` → `dressing`). Every mark is a whole cell,
  like the models.

## Shape language

- **Squares and rectangles.** Build from boxes, notched boxes (clipped corners) and
  steps. Suggest curves with steps and notches; never use round or spherical geometry.
- **Chibi proportions.** Characters and animals have big square heads, compact bodies
  and short limbs. Hands, boots and paws are chunky. Eyes are beads with a glint.
- **Light tops, dark undersides.** Give each mass a lit top layer and a darker skirt or
  underside. Baked corner occlusion adds the soft contact shade.
- **Big shapes first, then a few one-cell details.** Seams, growth rings, cracks, pegs,
  knots, rope bands and moss patches explain the object. Never add random per-cell
  colour noise.
- **Deliberate wear.** One or two chosen marks per object, such as a drying split, a
  chipped corner or an axe chop. Place them on purpose; don't scatter them.
- **Readable at colony distance.** Each object must read at gameplay zoom first. Detail
  is for the close view.

## Colour and materials

- Warm, readable palettes with semantic roles (wood, bark, grain, rope, hay, stone,
  iron, leather and so on).
- Wood roles map to the existing source palettes, so every wood still recolours for
  pine, oak, juniper and apple through `CraftMaterials`. Stone, rope, hay, char and the
  game counters are fixed colours.
- Baked shade is stored per vertex in UV2, so recolouring matches the unshaded swatch
  at that shade.
- Dwarves wear one of six tunic colours (`DwarfAssets.CLOTHING`): teal, rust, moss,
  slate, ochre and plum. In the world, bead eyes are untinted. Portraits show the eye
  colour on the glint.

## Lighting

The Hearthblock lighting pass ([255](../00_dev_roadmap/255_hearthblock_lighting_pass.md))
is part of the look:
- ACES tone mapping, with glow that only fire reaches;
- a cool fill for sealed air and a camera-facing fill on actors and props underground;
- warmer fire lights and darker, warmer slice caps;
- burlap stockpile overlays.

The values are in `data/sky/sky_settings.json` → `hearthblock_lighting`. Judge new art
in the game under this lighting at gameplay and colony zoom, not in studio light alone.

## Furniture tiers

- **Tier 1 · Axe-Hewn Era** is the furniture in the game now. Pieces are split slabs,
  bark, chopped stepped ends, notches, rope lashings and loose hay, with no iron and no
  wool.
- **Tier 2 · Carpenter Era** is for later, when the game adds that progression step: a
  plank dining table and a blanket bed. Its designs are in
  `data/art/studies/hearthblock_furniture_tiers.json`, next to the Tier 1 studies, and
  as `diningTable()` and `bed()` in `tools/hearthblock/art/proposal.mjs`.
  **Never delete either tier's designs.**

## Art over rigs (owner rule, 2026-10-21)

Old joints, pivots, envelopes and pinned shapes must not constrain the art. When the
art needs new proportions:
- move the joints into data (`visual_pose` in the animal definitions,
  `data/entities/dwarves/proportions.json`);
- change the rig;
- update tests that only pin old shapes.

Real gameplay contracts still hold. When one blocks the art, propose a change to the
owner instead of working around it. The current contracts:

- **Furniture** keeps its footprint, collision, seat and sleep heights, door openings
  and hinges, and walking surfaces. The heights, from the definitions in
  `data/furniture/`, are:
  - stool top 0.875 blocks;
  - bench seat 1.0;
  - log bed sleep surface 0.75, with the bed no taller than 15 cells;
  - table tops 1.5;
  - workbench top 1.0.

  The dining and game tables are 3 × 3 with four stools in a 5 × 5 layout. A seated
  dwarf sits 3 cells back on the stool, and no head cell may enter the tabletop
  (`test_log_table`). The bench is 2 × 1 with one seat. Door leaves are `leaf_left`
  and `leaf_right`, hinged at the outer edges.
- **Dwarves** grip tools at the palm, cell (17, 20, 3). The support grip is 10 cells up
  the haft. Strike points are axe (0, 17, 11) and pickaxe (0, 22, 15). The head obeys
  these layout rules:
  - fringes start at y 45 and brows sit at y 40–44;
  - nothing goes above y 54;
  - beards end at y ≥ 12 so a striding boot passes under them;
  - below y 18, anything on the head stays within z 11.

  A lying head rests on its lowest cell.
- **Animals** keep their navigation footprints and clearances. Deer need four blocks of
  headroom, and the rabbit fits one block. Squash and stretch keeps volume and feet,
  and no foot dips below ground.
- **Trees and plants** keep heights, clearance under the canopy, felling, variants and
  every growth, season, picked and packed state. Trunk footprints come from each tree
  definition. Saplings and wild plants never block movement.
- **Rocks:** boulders are 2 × 2 × 2 and block movement. Scree is 3 × 3 and stays low
  enough to walk over.
- **Goods** keep their footprints, so carrying, crates and stockpile tiles are
  unchanged.
- **Terrain** blocks stay one unit; the dressing is shader-only.

## What is Hearthblock today

| Family | Authored in |
| --- | --- |
| Dwarves, hair, beards, brows, work tools | `tools/hearthblock/art/dwarves.mjs` |
| Tier 1 furniture, hearth, kits, flag | `tools/hearthblock/art/tier1.mjs` |
| Animals | `tools/hearthblock/art/wildlife.mjs`, rigs in each animal's `visual_pose` |
| Trees | `tools/voxel_assets/trees.py` (square crowns, `square_pine`) |
| Bushes, wildflowers, reeds | `tools/voxel_assets/plants.py` (notched square clumps) |
| Stored goods the game can produce | `tools/voxel_assets/hearthblock_goods.py` |
| Boulders and scree | `tools/voxel_assets/rocks.py` |
| Plank floor, materials crate | `tools/voxel_assets/construction.py` |
| Terrain dressing | `terrain_appearance.gdshaderinc`, `appearance_profiles.json` |
| Menu pictures | `FurnitureCatalogThumbnails.gd`, `InventoryCatalogThumbnails.gd`, `GenerateFloorIcons.gd` |

Placeholders that are not Hearthblock yet, because the game cannot produce them yet:
crops; the stone floor (it needs a Stonemason); drinks, staves, cloth, honey, the water
bucket, grapes, hops, plump helmet, pig tail and their cuttings and seeds; the fossil
and the gold coin. Author each one in Hearthblock when its feature arrives. Don't
convert content ahead of its feature. The painted loading screens and the illustrated
menus are a separate medium.

## Making new art

1. Prove the idea with real cells. Use the proposal's box and notched-box vocabulary,
   not a painted concept that cannot be built at 1:16.
2. Build it through the normal pipeline ([61](61_voxel_art_guide.md)) and review the
   gallery.
3. Look at it in the game under Hearthblock lighting, close up and at colony zoom.
4. Keep the gameplay contracts above, or propose a change to them.
5. Re-render the menu pictures that show the model.
