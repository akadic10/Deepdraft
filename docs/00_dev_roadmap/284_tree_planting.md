# 284 — Planting tree seeds

2026-10-29. Built. The owner picked the planting sizes (the mature crown); the picks under
"Open" still wait.

From the owner: "when felling a tree, we can get a seed, but we cannot plant it yet, can we
implement planting seeds dropped from bushes or trees and recommend a size for each assuming
it could grow to ancient".

## What was there

- **Felling drops tree seeds** by chance (each stage's `harvest.yields`): oak acorns, pine
  cones, apple seeds and juniper seeds. Nothing used them.
- **Bush cuttings could already be planted** (doc 80): clearing a wild bush always gives a
  cutting, and Place → Plants plants it as a young shrub with a 3 × 3 planting area.
- **Hops cuttings, grape cuttings and pig tail seeds** are farm crops. They wait for farm
  plots, which aren't built; this milestone leaves them alone.
- **Trees never grew.** Wild trees keep the stage world-gen gives them, and doc 42 said an
  ancient tree was world-gen only.

## What's built

- **Place → Plants lists Oak acorn, Apple seed, Pine cone and Juniper seed.** Placing one
  makes a plan like a cutting's: a dwarf takes one seed from its crate, carries it over and
  plants it in three seconds. Cancelling keeps the seed. The ghost shows the sapling with two
  outlines: the grown tree's area and, inside it, its ancient trunk.
- **A sapling grows by the calendar:** sapling → mature → ancient over each stage's
  `growth_duration_days`, weighted by season (spring ×1.2, summer ×1, autumn ×0.8, winter
  paused), the same way cuttings grow. Saved credit plus calendar days, so pause stops it and
  loading never ages it. A clock jump can take two stages at once.
- **The trunk grows round the seed.** Odd trunks stay centred on it. The one even trunk, the
  pine's mature 2 × 2, takes the seed's +X/+Z side until its 3 × 3 ancient trunk centres
  again. The ancient juniper was 2 × 2 too; see "The juniper's trunk".
- **Growth waits for room.** A stage takes its new trunk (footprint × clearance height) only
  while that space is level ground and open air with no blocks, furniture, stockpile, loose
  items, dwarf or animal in it. The tree's panel says what is in the way, and it grows on
  the next hour once that is gone. Growth also waits while a felling or picking order is on
  the tree, so the order keeps the trunk it started on.
- **Planted trees are trees:** they fell, give logs and seeds, pick fruit (apple, juniper),
  block dwarves when mature, and save. A seed may go where a felled tree stood; the wild tree
  of that spot never comes back. A replanted spot rolls its seed drops afresh.
- **The tree's panel** shows "Growth: Mature in 1.2 growth days", "Sapling · growing 40%",
  "dormant" in winter or "waiting for room". DEV: Grow to next stage, behind the DEV switch.

## Sizes

Measured from every installed tree model: all four seasons, picked models and the shape
variants, widest of each, in blocks. "Square" is the smallest square centred on the seed
that holds the crown; the pine's mature 2 × 2 trunk sits half a block off the seed, and the
ancient juniper's crown reaches a block further east (+X) than west.

| Tree | Stage | Solid trunk | Crown width | Height | Square |
|---|---|---|---|---|---|
| Oak | Sapling | none (walk-through) | 4.3 × 3.5 | 6.8 | 5 × 5 |
| Oak | Mature | 3 × 3, 7 high | 12.0 × 11.0 | 16.5 | 13 × 13 |
| Oak | Ancient | 5 × 5, 10 high | 18.5 × 16.8 | 23.5 | 19 × 19 |
| Apple | Sapling | none | 3.4 × 3.4 | 5.9 | 5 × 5 |
| Apple | Mature | 3 × 3, 5 high | 12.1 × 10.7 | 11.9 | 13 × 13 |
| Apple | Ancient | 5 × 5, 7 high | 18.4 × 17.2 | 17.7 | 19 × 19 |
| Pine | Sapling | none | 2.3 × 2.2 | 8.0 | 3 × 3 |
| Pine | Mature | 2 × 2, 16 high | 6.0 × 5.8 | 20.0 | 7 × 7 |
| Pine | Ancient | 3 × 3, 22 high | 8.0 × 7.8 | 27.0 | 9 × 9 |
| Juniper | Sapling | none | 1.9 × 1.8 | 4.9 | 3 × 3 |
| Juniper | Mature | 1 × 1, 6 high | 6.2 × 5.8 | 11.8 | 7 × 7 |
| Juniper | Ancient | 3 × 3, 10 high | 9.0 × 8.0 | 15.8 | 11 × 11 |

- **Planting area: the mature crown** (the owner's pick, 2026-10-29): oak and apple 13 × 13,
  pine and juniper 7 × 7. It was first built as the ancient crown (19, 19, 9, 11); the owner
  planted an oak and found 19 × 19 too big. The third option, the trunk plus one ring (7, 7,
  5, 5), would merge ancient crowns into dense forest.
- **What it means:** no other tree may stand in the area, and planted areas may touch but
  never overlap, so mature crowns never meet. Grown ancients overlap by up to about 5½
  blocks for oak and apple, 2 for juniper and 1 for pine, worst case with the widest variants
  facing; wild trees stand about 14 apart and overlap as much.
- **The crown costs nothing on the ground.** Below four blocks a tree is only its trunk
  (doc 63's walking clearance), so bushes, flowers, furniture, stockpiles and paths still go
  under it.
- **The ancient trunk's ground is kept from the start** (the inner square: oak and apple
  5 × 5, pine and juniper 3 × 3): it must be level, solid and open to the sky when the seed
  goes in, with no plant, stone, furniture or stockpile on it, and no bush or flower may be
  planted on it later. The seed itself needs grass, dirt or soil.
- Bush cuttings keep their 3 × 3 planting areas. Each tree's size is one number,
  `planting.area`, in its JSON.

### The juniper's trunk

The ancient juniper's trunk was 2 × 2. An even square can't centre on the seed's cell, so a
planted juniper's trunk sat on the seed's +X/+Z side inside its 7 × 7 area. The owner asked
for it to be 3 × 3 (2026-10-29):
- `placement.footprint.ancient` is 3, for planted and wild junipers alike. The trunk centres
  on the seed, and the collision box is about half a block wider than the bark (trunk about
  1.8 wide).
- The eight ancient juniper models were rebuilt (`build.py trees`, reviewed in the native
  gallery, installed and imported): their root flare and walking clearance follow the
  footprint. The crowns are unchanged; the 11 × 11 square comes from a crown that reaches a
  block further east than west, not from the trunk.
- World generation now needs a level 3 × 3 for an ancient juniper, so a few on rough ground
  are gone from existing worlds, and the rest stand half a block further +X/+Z. Saves keep
  no compatibility for this (CLAUDE.md, Saves).
- Details keep clear of tree footprints, so a stone or two near ancient junipers is no
  longer placed: `SurfaceDetailLayoutTest` re-pins its boulder and scree counts (1–2 fewer on
  six of its eight seeds). With the old footprint it passes unchanged, so nothing else
  changed.

## Growth times

Existing `growth_duration_days`, unchanged; a season is 21 days.

| Tree | Sapling → mature | Mature → ancient | Planted on spring's first day, ancient by |
|---|---|---|---|
| Oak | 6 | 12 | spring day 16 |
| Apple | 3.75 | 7.5 | spring day 10 |
| Pine | 2.25 | 4.5 | spring day 6 |
| Juniper | 3 | 6 | spring day 8 |

## Rules (doc 42 has them now)

- `TreePlanting` (scripts/components) holds the rules: the site check, the trunk and area
  boxes, growth and the room check. `SurfaceFloraSpawner` owns the records, visuals,
  occupancy and saves; a planted tree's id is its seed's column and its change carries
  `planted`, `anchor`, `planted_at` and `growth_credit`.
- Wild trees count from their seeded candidates, so a tree not streamed in yet still keeps
  a seed out. Queued seeds reserve their trunk ground and area like planted ones.
- `ContentRegistry` makes the Place entries from each species' `planting` block;
  `SurfaceDetailRegistry.place_model` gives a seed's ghost the sapling.

## Open

The sizes are decided (the mature crown, above).

1. **Growth speed.** Every species reaches ancient in its first spring. Slower if planting
   should feel like a long investment (the oak's JSON calls it one).
2. **Seed returns.** A felled mature oak gives an acorn one time in five, an ancient one 0.7
   on average; pine, apple and juniper are similar. A planted forest gives back fewer seeds
   than it took, so wild trees stay the seed supply.
3. **Wild trees still don't grow,** and a sapling floats if the ground under it is mined (as
   wild saplings always have). Neither was asked for.

The owner planted an oak in Play (first sizes); the mature-crown areas aren't seen in Play yet.

## Files

- Data: the four `data/entities/flora/*_tree.json` (`planting`; the juniper's ancient
  footprint), `data/ui/place_catalog.json`.
- Art: the eight `assets/models/flora/trees/juniper/juniper_ancient*.glb` and
  `tools/art_data/voxel_manifests/trees.json`; review captures in
  `tmp/settlement_art_20261013/juniper_trunk_gallery/` and `juniper_trunk_focus/`.
- New: `scripts/components/TreePlanting.gd`, `scripts/tests/TreePlantingTest.gd` (flora area).
- Tests changed: `SurfaceDetailLayoutTest` (re-pinned counts for the 3 × 3 juniper).
- Changed: `SurfaceFloraSpawner`, `ContentRegistry`, `SurfaceDetailRegistry`,
  `SurfaceDetailManager`, `FurniturePlacementController`, `FurniturePlacementRules`,
  `FurnitureGhostVisuals`, `FurnitureWindow`, `FurniturePlacePanel`, `ShrubPlantingComponent`,
  `DwarfInspection`, `SaveSnapshotValidator`, `ColonyInventoryPanel` (seeds stay in Food &
  seeds rather than taking the Place entry's caption and group).
