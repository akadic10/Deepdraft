# Hearthblock furniture tiers (art proposal, 2026-10-20)

Editable MagicaVoxel copies of the Hearthblock proposal's furniture. Nothing in
the game loads these files yet; production art is unchanged. One voxel is one
1:16 cell (1/16 of a world block). Each file holds a single model, Z up in
MagicaVoxel, and reads back through `tools/voxel_assets/vox_source.py`
(`read_models` + `grounded_cells`) exactly as authored.

The cell layouts, as box/cutbox-style operations with fingerprints and the
gameplay contacts each model keeps, are in
`data/art/studies/hearthblock_furniture_tiers.json`.

## Tier 1 · Axe-Hewn Era (`tier1_axe_hewn/`)

Split, chopped and notched with an axe alone. Bark stays on, ends are chopped
in steps, joints are notches, bedding is loose hay. Meant for the early game now.

| File | Cells (W×H×D) | Keeps |
|---|---|---|
| `split_slab_bench.vox` | 46 × 24 × 46 | The primitive table: two halves of one split log on a crossed, lap-notched log support. Top at Y24 (1.5 blocks) over the 3×3 footprint; the support stays in the middle, clear of seated legs, so the four-stool 5×5 layout still works. |
| `notched_log_bed.vox` | 64 × 16 × 48 | Side logs on the floor, end logs saddle-notched over them with their ends running past the corners, a thicker head log. Loose hay heap with a continuous layer at Y12 (0.75 block) and tufts up to Y14. Head toward −X, 4×3 footprint, nothing above 1 block. |

## Tier 2 · Carpenter Era (`tier2_carpenter/`)

Dressed planks, pegs, a butterfly key, a wool blanket and a linen pillow. Saved
unchanged from the first Hearthblock proposal for later in development.

| File | Cells (W×H×D) | Keeps |
|---|---|---|
| `plank_dining_table.vox` | 46 × 24 × 46 | Three hewn planks on a square post and cross foot; top at Y24; 5×5 stool layout. |
| `blanket_bed.vox` | 64 × 20 × 48 | Squared rails and posts, straw tick, striped wool blanket; posts reach Y20. |

Colours are oak. In-game wood species would come from the existing
CraftMaterials recolouring once a tier is installed.
