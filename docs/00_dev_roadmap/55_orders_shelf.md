# 55 — Orders shelf

> **2026-10-08 — reeds:** **Clear plants** also selects reeds, individually or
> alongside shrubs and flowers. Reeds yield no items. Actual mesh clicks, mixed
> rectangles, Undo, Cancel and harvest/stone exclusion pass. See
> [77 — Seasonal reeds](77_seasonal_reeds.md).

> **2026-10-08 — flowers:** **Clear shrubs** is now labelled **Clear plants** and
> selects shrubs and flowers, individually or in a mixed rectangle. Shrub
> cuttings remain unchanged; flower clearing yields nothing. Harvest plants and
> Clear stones reject flowers. Cancel, Undo and View retain source guards and
> partial work. The six-tile layout is unchanged; the internal tool ID remains
> `clear_shrubs`. See [76 — Seasonal wildflowers](76_seasonal_wildflowers.md).

> **2026-10-08 — shrubs:** adds **Harvest plants** and **Clear shrubs**, keeping
> stone tools category-specific. Harvest selects ripe plants; clearing selects
> shrubs regardless of season. Cancel/Undo/View use the same source identities.
> Six tiles form one row at ≥1100px and two rows on smaller screens; compact
> banners fit beside inspectors. Real-input native tests pass at 960, 1280 and
> 2560px widths. See [75 — Seasonal shrubs](75_seasonal_shrubs.md).

> **2026-10-08 — stones:** Orders adds **Clear stones** between Chop trees
> and Cancel orders. It shares click/ground-rectangle selection, live counts,
> Undo and View order; Cancel orders handles mining, trees, boulders and scree together.
> Source identity guards and partial clearing progress are preserved. Four tiles
> fit in a row, with wrapped compact labels. Headless/native Orders tests and
> tree/boulder worker regressions pass. The renamed tool also gathers walkable
> scree. See [74 — Gatherable scree](74_gatherable_scree.md).

> **2026-10-06 follow-up:** the shared shelf now serves separate Orders and Zones
> groups. Orders contains Mine blocks, Chop trees and Cancel orders; Zones contains
> Stockpile. Farm plot / Later is omitted. The mode banner is attached above the
> shelf/dock instead of the upper screen, and feedback stays above the banner.
> Instructions/actions adapt beside inspectors. Switching groups ends the current
> tool; closing a shelf retains its mode. The active group stays highlighted until
> Done/Escape. See [53 — Navigation](53_hearth_iron_navigation.md) for verification.

> **Mining zoom correction (2026-10-06):** plain wheel input reaches the camera
> while Mine blocks is selected. Shift + wheel and Alt + wheel remain brush
> width/depth controls. UI scrolling never zooms the world. OrdersShelfTest
> verifies both camera/tool input orders; evidence is in `tmp/mining_zoom_review/`.

Implemented 2026-10-05 after approval of the interactive Orders shelf study.
Stonehearth informed the nearby tool shelf and persistent mode instructions;
the delivered controls retain Deepdraft's Hearth & iron theme and input rules.

## Original delivery (superseded where noted above)

- Orders opens a centered shelf above the dock: Mine blocks, Chop trees,
  Stockpile, Cancel orders and a disabled Farm plot / Later tile.
- Selecting a tile starts its tool immediately and keeps the shelf available.
  The active tile and Orders group stay highlighted. Selecting the same tool
  preserves its brush. Closing the shelf keeps the active mode.
- One shared upper banner gives the active tool, live selection count and
  relevant instructions, with Done / Esc and Undo last order. Mining retains
  Ctrl removal and Shift/Alt + wheel width/depth controls. Right-drag remains
  camera orbit. Standalone fixtures without a dock retain their old hints.
- Confirmed designations produce short feedback with View order, which finishes
  the tool and opens its existing mining, stockpile or tree inspector.
- Cancel orders clicks a marked block/tree or drags a screen rectangle over
  slice-visible block centres and visible tree centres. A red preview and live
  counts describe the selection. It cancels unfinished mining/chopping through
  their original owners; it does not remove stockpiles, furniture or terrain.
  Rectangle candidates refresh every 0.08 seconds and again on release.
- Undo last order keeps up to 20 transient creation receipts. It cancels only
  remaining work from that designation, preserving completed mining/felling and
  partial tree work. Stockpile undo uses ordinary removal, releasing haulers and
  stored goods. Source identity guards prevent stale receipts from cancelling a
  later re-mark or a loaded zone with the same numeric ID. Cancellation itself
  is not undoable through this button; the tooltip describes creation undo.
- Mining and storage now capture the end of an existing gesture. Releasing over
  UI or losing focus discards it instead of leaving a stuck drag. Pointer events
  supply the current preview position so a release uses the final cursor position.
- The shelf and banner clear the object inspector where there is available room.
  At compact widths the five tools use smaller tiles; tree inspector supplemental
  text scrolls sooner to keep its actions and the dock accessible. Player window
  positioning remains supported.

## Ownership

`data/ui/dock.json` supplies tile order, labels, icons and tooltips through
`UIRegistry`. `OrdersShelf.gd` is a preloaded Control under DockUI's CanvasLayer;
it presents data and opaque receipts without modifying world state. `UITheme`
owns its panel styles; new SVG tool icons extend Deepdraft's existing icon set.

MiningDesignationController and StockpileDesignationController supply receipt,
undo, inspection and hint APIs. TreeFellingController also coordinates the cancel
gesture, calling mining, flora and surface-detail cancellation APIs. Existing task leases,
progress, terrain mutation and save owners remain authoritative. No new global
script class, autoload, input action or save schema is introduced.

## Verification

- `OrdersShelfTest.gd`: real GUI/world input for all four tools, repeated selection,
  actual mine rectangles, tree source leases, mixed cancellation, progress-safe
  undo, stale receipt guards, release over UI and Escape. Native captures include
  960×540, 1280×720 and 2560×1440 with and without the inspector.
- `TreeFellingTest.gd`, `MiningAnimationTest.gd`, `FurniturePlaceTest.gd`:
  existing worker, animation, hauling and direct placement regressions.
- `NavigationPreview.gd`: real grouped commands, clock, persistence signals,
  inspector behavior, compact UI and world-input isolation.
- `SaveManagerRoundTripTest.gd`: main-scene startup, nonempty saves, autosave and
  corrupt-primary backup restore with isolated APPDATA.

Native screenshots are under `tmp/orders_review/`.
