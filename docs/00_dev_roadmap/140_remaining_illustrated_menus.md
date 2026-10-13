# 140 — Remaining illustrated menus

Status: **implemented** — 2026-10-12, following approval of [139](139_remaining_menu_art_plan.md).

## Delivered experience

The remaining navigation now uses the same original Hearth & iron artwork as
the dock, Orders, Zones and Construction. Commands show their names and purpose
on hover or keyboard focus. Existing item names, quantities, descriptions and
actions remain readable inside their destination panels.

| Area | Change |
|---|---|
| Craft | Ten profession illustrations, one desktop row or two compact rows. Planned crafting catalogs have muted art and a lock, remain browsable, and explicitly say **Catalog preview**. Miner gameplay and Carpenter promotion retain their existing availability. |
| Place | Nine illustrated category filters, with **Room furnishings** replacing the visible Rooms category name. The selected category name appears beside the design count. The short-window layout keeps its labeled dropdown. |
| Colony | Illustrated Dwarves, Settlement flag, Labor and Trade. Trade is an explicitly planned informational preview. The flag command now inspects its installed source or pending placement/move; a packed available flag opens Place with that flag selected. Carrying and unavailable states give truthful feedback. Founding still grants only one flag and squad. |
| Menu | Save / Load and Slice view. The Clock & weather entry introduced here was replaced by the permanent Sky Dial in [141](141_sky_dial.md). Save / Load has a child row for the three existing operations and a Back arrow. |
| Development | Nine icons in three rows: Block inspector, World Build, Cave explorer; Dwarf tools, Water tools, Arrival status; Spawn Drops, Spawn Furniture, Time & weather. World Build and the clock's +1 Hour, +1 Season and weather-cycle controls moved here. |
| Inventory | Nine illustrated category filters share matching art with Place. Counts, ownership breakdowns, Locate and Inspect storage retain their existing behavior. Compact windows use the labeled dropdown. |
| Rooms | Small furnishing, flooring, comfort, weather and light symbols accompany the existing facts. Room selection stays direct; Overview and Details keep their text, numeric values and scrolling. |

Place and Inventory still open directly. Their existing item thumbnails,
availability, focus, scroll and live-stock behavior are retained. Only Craft
had a search field before this pass; its search remains. This corrects the
plan's accidental reference to existing search in Place/Inventory.

The shared illustrated menu wraps beside a moved Object explorer before reducing
icon size. Icons remain 64 px desktop / 56 px compact; browser category icons
are 56 px. Back, Escape, parent highlighting, hover cleanup and viewport bounds
use the existing menu and window owners. A slice-hidden settlement flag keeps
normal concealment and gives guidance to change the slice for inspection.
The detached dwarf inspector's scrolling area is 16 px shorter where needed to
clear the dock at 720p; its tabs and contents are unchanged. The room inspector
can use another 100 px on taller windows to accommodate its new symbols.

## Ownership and assets

`UIRegistry` owns all menu/category atlas metadata in the existing UI JSON files,
including row limits and small room-symbol definitions. `DockIconButton` provides
shared hover/focus presentation and planned/DEV status badges. `DockUI` dispatches
the existing actions. Touched save and developer commands use stable item IDs,
so translated or edited captions cannot break their routes.

`FurniturePlacementController.get_catalog_location()` supplies current installed,
pending, packed, carried or unavailable state. `FlagPlacementController.is_founded()`
exposes the existing founding record. Neither query creates an item or changes a
job. Save format, simulation rules and production capabilities are unchanged.

Unmodified generated sheets are retained under `assets/ui/dock/`:
`craft_atlas.png`, `categories_atlas.png`, `colony_atlas.png` and
`utilities_atlas.png`. Runtime AtlasTextures select individual regions.
[Source prompts and generation method](concepts/140_remaining_menu_prompts.md)
record the built-in image generation tool and the existing Construction art
used as the style reference. No Stonehearth assets are used.

## Verification

Targeted headless fixtures pass: ProfessionCraftingTest, FurniturePlaceTest,
ColonyInventoryTest, SettlementFlagMoveTest, ConstructionInputTest,
CraftingBrowserTest, OrdersShelfTest and RemainingMenusTest. The flag fixture
covers the new navigation during founding, transport and packed recovery while
retaining real worker movement and save restoration.
The focused DwarfInspectorTest also passes after the footer clearance adjustment.

Native RemainingMenusTest, DockArtPreview, FurniturePlaceTest and
ColonyInventoryTest pass at 960×540, 1280×720 and 2560×1440. Native NavigationPreview
also passes tool exclusivity, every persistence callback, Back/Escape, clock
controls and inspector clearance. Its simulated wheel input now includes the
release event, preventing the test from capturing subsequent menu clicks.
Captures were inspected
for art, readability and layout. The new fixture covers stable save/spawn IDs,
time/weather separation, Back, focus tooltips, moved-inspector wrapping and
unchanged room facts. Save signals use isolated probes in navigation tests;
those clicks do not write or load a player save.

Logs and menu captures: `tmp/remaining_menus_20261012/`.
Additional browser captures: `tmp/place_catalog_review/` and
`tmp/inventory_review/`; full dock captures: `tmp/dock_art_20261012/`.

Restart **Play** to load the menus and imported art. No new autoload or
`class_name` was introduced. The dwarf character-screen overhaul remains the
separate stage 3 in [131](131_dwarf_food_and_dining.md).
