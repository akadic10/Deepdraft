# 118 — Crafted materials and appeal

Implemented 2026-10-11. Finished starter crafts retain the selected timber:
pine, oak, juniper or applewood. Names, wood palettes and object appeal follow
that identity while recipes, inventory rows and Place tiles stay grouped by design.

## Player behavior

- Craft's allowed-wood control chooses possible materials. The actual consumed
  log determines every output in that batch. Maintain orders count only spare
  outputs made from their allowed wood.
- Completed names include **Oak log stool** and **Applewood log bench**. Packed,
  carried, stored, equipped and installed goods keep that identity. Shared crates
  retain neutral packing art.
- Place has an **Any material / wood** selector inside the selected design card.
  Claims, storage withdrawal, redirected hauls and saved plans honor it.
- Inventory shows material counts inside the design's detail card. Craft shows
  the selected wood's appeal or a range for several allowed woods. Inspectors
  show **design + material**; packed goods say **Appeal when installed**.

## Data and ownership

`CraftMaterials` owns `data/materials/craft_materials.json`: stable material IDs,
ingredient mappings, adjectives, appeal bonuses and semantic wood swatches.
Recipe `material_group` opts into inheritance. Furniture/item definitions own
`appeal.design`, `appeal.material_factor` and `material_palette`.

Appeal = `design + material bonus × design material factor`. Wood bonuses are
Pine 0, Oak 1, Juniper 1.5, Applewood 2. The stool has base 1, yielding scores
1, 2, 2.5 and 3. Torches and campfires scale wood's bonus down to 25%.

Iron, Copper and Gold profiles reserve bonuses 1, 4 and 25 for future refined-metal
recipes. These are initial tuning values; raw ore does not become furniture and
no new brazier recipe is enabled. A future base-3 design with material factor 1
would score 7 in copper and 28 in gold.

`material_id` is an item property, not a new item key. It survives splitting,
ground/container storage, relocation, equipment, saves, installation and recovery.
Different materials never share a physical stack. Bridges keep one kit identity;
ladders keep an ordered material per paid section, including interrupted extension
and support-loss recovery. Plans save `required_material_id` separately.

The executor captures properties just before consuming cargo. Interrupted work
keeps the original physical item. Material-less DEV goods remain unspecified and
use original artwork/base appeal. No provenance is guessed for existing goods.

## Artwork

The registry caches recolored meshes by original mesh, material and source palette.
It replaces exact authored wood swatches, including Godot's truncated RGBA8 colors,
without modifying source resources. Bark, cut wood, rings and highlights retain
their roles. Flames, stone, fibre and other unmapped colors remain unchanged.
Starter tools recolor only their wood; camp assets retain their existing encoding
through separate source profiles.

`tools/MaterialFurniturePreview.gd` renders the native comparison to
`tmp/material_furniture_20261011/palettes.png`.

## Verification and scope

`CraftMaterialTest` covers four real worker crafts, ground/container hauling,
filtered withdrawal and installation, delivery/installed save properties, refunds,
unknown material validation, maintain targets, stack separation, mesh safety and
flame preservation. Native Place captures cover 1920×1080, 1280×720 and 960×540.

Surrounding regressions: WorkerCraftingTest, LogFurnitureTest, LogBridgeTest,
LadderTest, StorageFilterTest, ColonyInventoryTest, ToolPromotionTest and
CraftingBrowserTest. SaveManagerRoundTripTest includes a material-bearing door,
packed furniture in a container, loose tools and equipped tools through full scene
replacement, autosave and backup recovery. Fresh-editor production diagnostics
include the new autoload.

Appeal is currently an object property and presentation foundation. Appeal-driven
room scoring and mood effects, craftsmanship/quality, prices and precious-metal
crafting are later systems. Personal-bedroom and temperature sleep thoughts are
live separately in milestones 121–122. Reload Current Project in Godot to register
`CraftMaterials` before playing.
