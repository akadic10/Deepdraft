# 56 — Colony Inventory

Implemented 2026-10-05. The bottom navigation now reads **Orders · Place ·
Colony · Inventory · Menu**. Inventory opens **Colony Inventory** directly;
the old stockpile-summary placeholder is gone. Storage zones remain stockpiles.

## Player experience

- A movable cabinet shows existing model thumbnails, category filters and a
  parchment detail column. Materials, furniture, storage, lighting, food/seeds,
  drink and other supplies use the shared Hearth & iron theme.
- **Total = Stored + Loose + Carried**. Quantities are units of contents, so a
  crate holding 24 seeds counts as 24. Installed furniture is already in use
  and is excluded from supplies.
- **Reserved** is a subset of Total: goods assigned to hauling or furniture
  placement. **Available** is the remaining pool for new orders. The Reserved
  tooltip explains that it is not an additional quantity. Legacy unfulfilled
  placement requests never invent physical goods.
- Inventory reports what the colony owns and where it is. Furniture stays in
  the counts, but there is no Place item button here. Use the separate **Place**
  dock entry to furnish the world, with its existing repeat placement and Undo.
- **Locate** resolves a current stored, loose or carried item and moves the
  camera without changing zoom or giving dwarf orders. **Inspect storage**
  opens the actual stockpile or installed container holding the item. Both
  re-query ownership at click time and respect the current slice.
- Tiles retain order, focus and scroll during hauling. New item types append;
  exhausted types stay at zero until reopening. Filtering is an explicit
  player action. Counts never refit or move the window.
- Drag the title bar; Escape or the dock button closes it. The position is
  remembered by UIWindowManager. The compact layout uses a category dropdown
  and scrollable details with actions always visible above the dock.
- Developer supplies moved to **Menu → Development → DEV: Spawn Drops /
  DEV: Spawn Furniture**. Create a stockpile through **Orders → Stockpile**.
  Crafting remains future work.

## Ownership

`UIRegistry` reads `data/ui/inventory_catalog.json` for category names and tag
rules. Item definitions still belong to ItemDropManager, and furniture definitions
to FurniturePlacementController. Existing Place captions and thumbnails are reused.

`ColonyInventory.gd` derives the read model from owners. StockpileManager provides
stored totals and current locations; ItemDropManager exposes loose quantities and
weak references to picked-up objects until storage, interruption or consumption.
Those references never own cargo. Stockpile and container visuals cannot double
count stored goods. Save formats and restoration ownership are unchanged.

`ColonyInventoryPanel.gd` handles presentation; `DockUI` routes actions. Updates
are deferred/coalesced from existing item, storage and furniture signals and do
not scan every frame. Rebuilding stored totals now also wakes open inventory.
No global class or autoload was introduced.

Resource thumbnails in `assets/ui/items/` are renders of the existing GLBs,
including rough stone and iron ore. Regenerate with the native Godot renderer
using `tools/InventoryCatalogThumbnails.gd`, then let Godot import the PNGs.
Missing resource models get the existing neutral supplies icon, never invented art.

## Verification

`ColonyInventoryTest.gd` exercises native dock/category/actions, live counts,
reservation/pickup/deposit/interruption, shelf contents, partial crates, slice
concealment, storage removal, the separate Place workflow, stable browsing, title dragging,
reopen/Escape and 960×540 / 1280×720 / 2560×1440 layouts. Native captures are in
`tmp/inventory_review/`. Regression checks cover FurniturePlaceTest,
HaulingAnimationTest, ProduceCrateTest and NavigationPreview (including dwarf
inspection, shared theme and existing save/load action routing).
