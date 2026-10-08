# 54 — Place catalog

Implemented 2026-10-05 after approval of the Hearth cabinet concept. The native
game now uses **Place** for finished furniture. Crafting and future structural
building are separate systems; this screen does not create items from resources.

## Player flow

- The bottom dock opens a movable **Place an item** cabinet. Drag its title bar;
  UIWindowManager remembers its position. Opening another command menu closes it.
- Twenty actual furniture models have rendered thumbnails, organized into
  Dining, Storage, Lighting, Rooms and Workshops. All combines the categories.
  The default list starts with available or reserved designs. Those tiles stay
  in place for the current browsing session even if their count reaches zero
  while dwarves move them. Newly available designs append at the end. Reopening
  refreshes the list; **Show all designs** reveals every design immediately.
  Unavailable items remain selectable for inspection, with Place disabled.
- Empty lists show no furniture detail card or item actions. The selection is
  cleared when its design is filtered out, then chosen from visible designs only.
  The detail card returns when a visible design becomes available or the player
  deliberately browses all designs. Filtering away an active design stops its
  placement preview. This fixes the empty-stock Personal Dining Table label
  reported on 2026-10-06.
- Select an item to see its footprint, chair capacity or mounting hint, plus
  live Available, Reserved and Crafting counts. Since 2026-10-07, Crafting is the
  real requested output of Worker orders: finite batches plus batches needed for
  maintain targets. The new stump and wooden torch are produced through
  [Craft](64_worker_crafting.md); this catalog installs finished items.
- Clicking an available item tile immediately starts its world preview; there
  is no extra confirmation. Clicking a different available tile switches designs;
  re-clicking the active tile preserves rotation. Unavailable tiles show details
  and clear the previous preview. Opening the catalog alone does not start a tool.
  The **Place item** button remains an optional way to resume after Done/Escape.
  R rotates, table seats still
  snap chairs, and dwarves fetch the actual packed item and install it. The
  cabinet stays open for repeated placements and switching items. Exhausting
  available stock ends the tool and retains the catalog.
- **Done** or the first Escape finishes placement. A second Escape, Close or the
  Place dock button closes the catalog. **Undo last** cancels the most recent
  unfinished placement made through this catalog; installed furniture keeps its
  existing Uninstall action.

The default location is below the top-left time controls, clear of the right-hand
inspector. The three-column list scrolls independently of the world. At 960×540,
categories use a dropdown and details compact to keep a full item row, actions
and the bottom dock accessible. Saved or dragged positions remain player-owned.

For the current development build, **Menu → Development → DEV: Spawn Furniture** supplies
packed furniture for testing. Workers now produce the crude workbench/stump and
wooden torch through Craft. A carpenter production screen remains future work.

## Ownership and stock rules

- `UIRegistry` alone reads `data/ui/place_catalog.json`: category IDs, labels,
  item order and short captions. `FurniturePlacementController` remains the sole
  reader of furniture definitions. Item properties and footprints are not
  duplicated in the UI JSON.
- `FurniturePlacePanel` owns presentation and session Undo history; `DockUI`
  routes the existing exclusive-tool signal. The window uses UIWindowManager,
  and the cabinet/paper styles live in UITheme.
- Available is unreserved loose units plus StockpileManager totals (ground
  stockpiles and containers), minus pending requests that have no committed
  item. Claimed, fetched or carried units already left the available pool; their
  requests must not subtract the same unit again. Reserved counts pending
  placement requests, including restored requests from older saves.
- `FurnitureGhostComponent` tracks pickup until completion or release so a
  carrying dwarf's ghost cannot claim a second item. This tracking is runtime
  only; existing saves restore carried goods as loose items and rebuild claims.
- Item availability wakes are coalesced through `catalog_changed`; the panel
  refreshes only while open. There is no per-frame inventory scan. Placement
  checks stock again at confirmation, preventing rapid clicks from overbooking.
- Inventory refreshes update tile badges and action availability without
  refitting the window. Browsing membership/order stays stable until reopen;
  category and Show all changes are explicit user actions. The scrollbar gutter
  remains reserved, so a newly overflowing list does not change tile widths.
- Catalog activation opts into the stock guard. Restored standing requests and
  existing developer/art fixtures retain the unrestricted legacy path. Save
  formats, furniture footprints and chair rules are unchanged by this feature.

Thumbnails in `assets/ui/furniture/` come from the project's own placed-form GLBs.
Run `tools/FurnitureCatalogThumbnails.gd` with the native renderer to regenerate
them after model changes; import the generated PNGs through Godot normally.
No Stonehearth code or artwork was copied.

## Verification

- `FurniturePlaceTest.gd`: real native clicks, empty/category states, loose and
  ground/container stock, claims, pickup and interrupted fetches, restored
  requests, completed installation, rapid-click guard, repeat placement,
  item switching, Undo, R/Escape, title-bar drag and reopen position.
  Direct tile clicks start previews without placing through the UI; unavailable
  selections stop the previous preview and same-item clicks preserve rotation.
- Hauling regression in the same test: real reservation, pickup and stockpile
  deposit preserve every visible tile rectangle, the window rectangle, scroll,
  selection and keyboard focus at all three resolutions. A new design arriving
  during browsing also leaves existing click targets in place. Reopening prunes
  exhausted designs. `stable_before.log` records the reproduced failure;
  `stable_after.log` records the corrected run.
- Native captures at 960×540, 1280×720 and 2560×1440 verify the cabinet, fixed
  actions and dock fit. Captures and logs: `tmp/place_catalog_review/`.
- `NavigationPreview.gd -- --capture`: existing menu actions, save/load signals,
  live clock, dwarf inspector, camera Follow, and scrolling the catalog without
  zooming or stopping Follow. Includes `HearthThemePreview.gd` and inspector checks.
- `HaulingAnimationTest.gd`: physical stockpile fetch, pickup/carry/set-down,
  interruption and quantity conservation. `DiningPlacementTest.gd` retains
  the seating/snap/legacy-save regression coverage.

New global class: `FurniturePlacePanel`. Use **Project → Reload Current Project**
before playtesting in an editor that was already open.
