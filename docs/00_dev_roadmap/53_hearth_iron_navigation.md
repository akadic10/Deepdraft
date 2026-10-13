# 53 — Hearth & iron: navigation and layout

**Fixed time/Slice HUD (2026-10-12):** [142](142_fixed_time_slice_hud.md) replaces
the upper-left strip and movable Slice window with bottom-right illustrated
controls and a permanent ±1/±4 height tower. The main dock centers where space
allows and shifts left to clear the utility row; very narrow screens stack them.

**Remaining menus (2026-10-12):** [140](140_remaining_illustrated_menus.md)
extends the art through Craft, Colony, Menu, Development and both catalog category
strips. World Build and time/weather tests moved into Development; planned
catalogs stay browsable. Rooms retains direct inspection with small fact symbols.

**Current dock (2026-10-12):** [135 — Illustrated command dock](135_illustrated_command_dock.md)
replaces permanent text/copper line icons with the approved full-color artwork
and hover/focus names. Ten entries retain the current order, with Construction
between Rooms and Place and separate Development at the far right. The dated
milestones below describe earlier versions.

**Current follow-up (2026-10-07):** [64 — Worker crafting](64_worker_crafting.md)
adds Craft between Place and Colony, making eight dock entries. The dated
navigation milestones below describe the earlier layouts.

## Dedicated Rooms entry — 2026-10-06

Rooms now has its own bottom-toolbar entry beside Zones:
**Orders · Zones · Rooms · Place · Colony · Inventory · Menu**.
It directly toggles room inspection, with a copper floor-plan icon and an active
highlight. A second click or Escape exits. Switching to another dock group ends
room inspection; entering Rooms closes the tool shelf and ends the previous tool.
The duplicate Inspect rooms command has been removed from Colony.

Native NavigationPreview verifies those transitions, existing menu actions and
the seven-entry dock at 960×540, 1280×720 and 2560×1440. Logs use isolated user
data in `tmp/rooms_navigation_review/`. Simulation and save data are unchanged.

## Separate zones follow-up — 2026-10-06

The player selected **Separate zones** from the interactive navigation study.
This pass introduced **Orders · Zones · Place · Colony · Inventory · Menu**;
the subsequent Rooms entry above extends that layout.
Orders holds Mine blocks, Chop trees and Cancel orders. Zones holds Stockpile;
the unimplemented Farm plot tile is omitted. The new Zones icon extends the
existing copper line icon set. Place and Inventory retain their direct windows.

One shared tool shelf reads both groups from UIRegistry. Switching groups ends
the active drawing mode; closing the active group's shelf preserves that mode
and its dock highlight. Done ends it even with the shelf closed. Escape first
ends the tool, then closes its shelf. Opening a management menu ends an active
designation. Existing cancellation, creation receipts and Undo remain shared.

The mode banner now sits above the open shelf, or directly above the dock when
the shelf is closed. Instructions and actions sit side by side at wide sizes and
stack when space is limited beside an inspector. Feedback sits above the mode
banner. Smaller tool tiles and inspector avoidance preserve access at 960×540.
The live calendar, time controls and Slice button are unchanged.

Verified with native OrdersShelfTest (both families, Done/Escape, group switching,
real world input, safe undo/cancel, wheel isolation and 960/1280/2560 layouts),
NavigationPreview with `--capture` (management, persistence signal routing and
inspector checks), TreeFellingTest and FurniturePlaceTest. Logs use isolated user
data in `tmp/zones_navigation_review/`; captures are in `tmp/orders_review/`.
No save schema, autoload or simulation behavior changed. Restart play mode.

---

> Follow-ups: Build became Place (doc 54), and Stocks became the direct Colony
> Inventory window (doc 56). The Stockpile overview placeholder is retired.
> Colony → Dwarves now opens the player roster (doc 57); developer controls moved
> to Development. The seven-entry layout above supersedes the original dock below.

Implemented 2026-10-05 after approval of the shared theme and movable zone windows.

Later follow-up: [54 — Place catalog](54_place_catalog.md) replaces the furniture
Build list with a movable inventory cabinet. The delivered stage-3 behavior below
describes the original rollout; the current dock uses **Place** in that slot.

## Delivered

- Five labeled bottom-centered groups: Orders, Build, Colony, Stocks and Menu, with
  small copper SVG line icons. The open group remains highlighted in submenus.
- Mining, chopping and stockpile designation route through the existing
  `tool_requested` signal, preserving one-active-tool behavior. All 18 furniture
  options and the existing management, developer and save/load actions remain
  reachable. Future farming/military/forestry actions are disabled.
- One menu at a time, submenu Back, close control and Escape. Menus scroll at
  compact sizes, reset their scroll position when opened, and consume wheel input
  without zooming the world or stopping camera Follow.
- Live upper-right Sky Dial for season/day/time, weather and the seasonal cycle
  ([141](141_sky_dial.md)); fixed bottom-right Pause, 1×, 2× and Slice ([142](142_fixed_time_slice_hud.md)). The former
  Clock window/calendar button are removed. State comes from the owning systems.
- All object inspectors default to the right. Saved positions and player drags
  take precedence. Mining/storage windows keep their movable, saved placement.
- Menus reserve the inspector column at desktop widths and measure available
  vertical space from the dock's actual height. Build changes from four columns
  to two as needed, with an 8 px gap above the dock.

Follow-up: the player requested a centered bottom bar. It centers at startup and
on resize when space allows; milestone 142 moves it left enough for the utility
controls or stacks those above it at narrow widths, keeping the bottom margin.
The compact dwarf inspector reserves enough space above it for its action footer.
Submenus also center above the bar; if the inspector would cover them, they shift
to the nearest side with sufficient room. Inspector movement updates placement,
and closing it recenters the open menu.

## Ownership

`data/ui/dock.json` schema 2 stores the group order, icon paths, labels, menu titles,
parent links, tooltips, disabled states and command bindings. `UIRegistry` remains
its sole file reader. `get_dock_items()` and `get_menu()` expose validated data.
`DockUI` dispatches actions to existing owners; it does not own world state or save
I/O. The furniture catalog bindings remain with the existing placement dispatcher.

`UITheme` owns the shared styles; five original SVG icons live in `assets/ui/icons/`.
`ObjectExplorerController` owns first-use inspector placement. No autoload, save
schema, simulation behavior or input-map change is introduced by this stage.

At the original stage-3 checkpoint, Labor, Trade and Stockpile overview used
preview content. Labor and Trade remain previews; Colony Inventory has since
replaced Stockpile overview. The Orders shelf supplies mode feedback (doc 55),
and developer supplies/dwarf controls now live under Development
(docs 56/57). Bed use and dining AI remain deferred.

## Verification

- Editor import and script validation, including the native SVG imports.
- `ObjectExplorerTest.gd`: existing object picking, provider data and actions.
- `tools/HearthThemePreview.gd -- --capture`: shared controls and furniture placement.
- `tools/NavigationPreview.gd -- --capture`: actual GUI clicks through all groups,
  tool exclusivity, Back/Escape, all three persistence signals, clock controls,
  inspector position preference, compact scrolling and no world-input leakage.
  Native layouts and screenshots cover 960×540, 1280×720 and 2560×1440, including
  menu/dock/inspector separation. The inherited dwarf inspector fixture also passes.
- `SaveManagerRoundTripTest.gd`: full main-scene startup, nonempty colony save/load,
  independent autosave and corrupt-primary backup recovery with isolated APPDATA.

Captures and logs are in `tmp/navigation_review/`. The navigation fixture disables
layout writes and observes save/load signals with the persistence handlers
disconnected, so preview clicks do not write player saves or layout preferences.
