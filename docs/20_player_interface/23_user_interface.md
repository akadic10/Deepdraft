# 23 — User Interface

**Audio preferences (2026-10-13):** Menu → Audio opens separate Ambience and
Effects sliders with mute buttons and Restore defaults. Preferences persist
across settlements. Ambience includes the new weather/season-aware woodland
soundscape and softens on pause; Effects includes existing work, wildlife,
water, fires and notifications. See [168](../00_dev_roadmap/168_environment_ambience.md).
The [170](../00_dev_roadmap/170_environment_sound_details.md) expansion adds rain,
thunder, seasonal textures, shoreline, frogs and cave drips to Ambience. Actual
wolf howls use Effects. The sky dial displays Rain and Storm with cloud/rain
marks and a storm lightning symbol; its tooltip names the actual weather.

**Fixed time/Slice HUD (2026-10-12, 142):** illustrated Pause, 1×, 2× and Slice
sit permanently at the bottom right. Slice's fixed tower has exact ±1/±4 arrows
and a live level. Off reads Full world and retains the last height. Wheel over
the tower steps the plane. The old upper-left strip, movable Slice window and
Menu shortcut are removed. See [142](../00_dev_roadmap/142_fixed_time_slice_hud.md).

**Sky Dial (2026-10-12, 141):** the upper-right illustrated HUD now presents
season/day/time, current weather and the seasonal day/night cycle. Hover/focus
adds year, phase and sunrise/sunset. It replaces the Clock window and Menu
shortcut. Pause/speed/Slice now live at bottom-right; food warnings sit beneath the dial,
and ordinary windows make room. See [141](../00_dev_roadmap/141_sky_dial.md).

**Remaining illustrated menus (2026-10-12, 140):** Craft, Colony, Menu and
Development now share the illustrated submenu rail. Place and Inventory have
matching illustrated category filters, with a dropdown at short window heights;
Room furnishings replaces the Place category name Rooms. Room facts have small
supporting symbols. Colony's flag entry now locates/inspects its existing flag or
order, or opens its packed recovery in Place. Planned crafting catalogs remain
browsable with explicit status. See [140 — Delivery](../00_dev_roadmap/140_remaining_illustrated_menus.md).

**Illustrated Construction (2026-10-12, 138):** Stone block and Floors now use
the same Hearth & iron art and hover/focus names as the dock. Floors opens plank
and stone illustrations with a Back arrow; a flask badge identifies each as a
usable DEV preview. Existing construction and DEV Build behavior remains intact.
See [138 — Construction menus](../00_dev_roadmap/138_illustrated_construction.md).

**Illustrated Zones (2026-10-12, 137):** Storage, Farming and Animal pasture use
the same icon-only rail and parent anchoring as Orders. Storage is usable;
Farming and Animal pasture are dimmed with lock badges and explain their planned
status on hover, focus or activation. They cannot dispatch work or switch tools.
See [137 — Zones submenu](../00_dev_roadmap/137_illustrated_zones.md).

**Illustrated Orders (2026-10-12, 136):** six caption-free command icons form a
short rail above Orders, with hover/focus names, active copper borders and a gap
before Cancel. The 64/56 px icons wrap beside moved inspectors. Compact mode
feedback retains live counts, mining width/depth, contextual Undo and Done/Esc.
Zones subsequently adopted matching art in 137; all order ownership remains intact.
See [136 — Orders submenu](../00_dev_roadmap/136_illustrated_orders_plan.md).

**Illustrated command dock (2026-10-12, 135):** the bottom bar uses ten approved
Hearth & iron illustrations with no permanent captions. Hover or keyboard focus
shows a name and explanation; the active command has a copper outline and bottom
notch. Square 72 px desktop / 56 px compact buttons retain the existing order,
with gaps before Menu and Development. Menus fit above the measured rail.
See [135 — Illustrated dock](../00_dev_roadmap/135_illustrated_command_dock.md).

**Settlement flag (2026-10-12, 133):** the placed banner is ordinary furniture
in Object explorer, including Move/Uninstall, occlusion and slice picking rules.
Packed flags appear in Place → Room furnishings. Reinstallation updates the settlement
anchor; the initial founding command remains once-only. See
[133 — Settlement flag](../00_dev_roadmap/133_settlement_flag_furniture.md).

**Furniture Move (2026-10-12):** installed furniture, crafting stations and
containers offer Move in Object explorer. Aim/rotate the normal preview and click
to queue worker relocation; Escape before confirming leaves the piece installed.
Source and destination offer Cancel move. The chosen piece retains its material,
bed ownership and storage filters. Containers empty their contents when packed.
See [132 — Furniture Move](../00_dev_roadmap/132_furniture_move.md).

**Storage inspector styling (2026-10-12):** ground storage and containers share
Object explorer's framed chrome, inset type/name card and stacked action buttons.
Ground zones retain their movable Storage inspector with Filters/Contents;
short contents lists use less empty space. See [59 — Storage filters](../00_dev_roadmap/59_storage_filters.md).

**Food indicator (2026-10-12, 131):** the shared dwarf inspector/Colony detail
panel shows Food beside Rest, with Satisfied/Hungry/Famished states and a tooltip
for the last meal and food-search status. Overview shows actual hunger effects;
Details shows the last food/time/arrangement and temporary dining thoughts.
Current activity distinguishes food search, emergency berry picking, dining and
eating. A quiet HUD warning counts hungry dwarves unable to find reachable food,
with harvesting/storage-access guidance. The larger tab redesign remains stage 3
in [131](../00_dev_roadmap/131_dwarf_food_and_dining.md).

**Development menu (2026-10-12):** Development is its own dock entry at the far
right, after Menu. It opens directly with no parent/back link. Its nine actions
are Block inspector, World Build, Cave explorer, Dwarf tools, Water tools,
Arrival status, Spawn Drops, Spawn Furniture and Time & weather. The last panel
owns +1 Hour, +1 Season and weather cycling; the player clock shows facts only.
Block Inspector moved here in 130; World Build and time/weather tests in 140.
All 15 cycling locator commands and their runtime handlers/state
have been removed. Normal click inspection and Locate/Follow remain available.
Native menu routing and layouts pass at 960×540, 1280×720 and 2560×1440;
captures and checks are in `tmp/development_menu_20261012/`.

**Construction (2026-10-12):** the dock entry sits between **Rooms** and **Place**
and opens **Stone block · 1 stone**.
Click a terrain face or drag a footprint to plan full voxels in adjoining air.
Alt + wheel adjusts height; the displayed slice limits the actual order. Green
previews show the selected cells and cost, blue cells mark pending work. Ctrl +
click cancels an unfinished area; Escape ends the tool. Click a blue cell, during
construction mode or afterward, to inspect its whole pending area in Object
explorer. The outline and live rows show remaining blocks, required stone,
assigned worker and current block progress. **Cancel construction** removes the
remaining plan while keeping completed stone and unconsumed materials. Hidden
plans cannot be clicked through terrain; completion, cancellation or lowering the
slice below the whole area closes the inspector. Existing solid terrain
must be mined first. **Construction → Floors** now offers simple plank and stone
plans, with the required profession marked Planned. Their inspectors expose
**DEV Build**; workers cannot claim these plans. Rooms displays floor coverage
and +5 flooring appeal for complete coverage. Decorative coverings remain
deferred. See [128 — Floors](../00_dev_roadmap/128_permanent_floor_preview.md) and
[127 — Structural stone](../00_dev_roadmap/127_structural_stone_construction.md).

**Crafting browser (2026-10-11):** Craft → profession now opens compact recipe
icons grouped by the categories in recipe data, with case-insensitive search
by name or category. Recipes / Orders (count) tabs share the left column; the
selected recipe has one illustrated parchment detail card on the right.
Crafting keeps the browser open and updates the order count. Materials and
descriptions scroll independently of the fixed wood, quantity, Queue and Place
controls. Live stock changes preserve focused icons, order rows and scrolling.
Planned professions retain their preview without recipe/order tabs or actions.
As of 2026-10-13, Rudimentary uses Workshops, Lighting, Access, Rooms, Dining and
Starter tools. Rooms groups beds, hearths and doors; Dining groups stools and
benches; Lighting groups torches and campfires, matching their Place categories.
See [114 — Crafting browser](../00_dev_roadmap/114_crafting_browser.md).

**Object permissions (updated 2026-10-11):** loose goods and placed water stones
expose Allow/Disallow in Object explorer. Stored goods have no permission action
and are available colony stock. Inventory still reports Disallowed for goods
outside storage alongside available/reserved goods. Disallow never hides an
object or stops a placed stone's water effect.
Allowed placed stones offer Move and Pack for storage; allowed packed stones
can be placed through their inspector or Place → Water. See
[110 — Permissions and movable stones](../00_dev_roadmap/110_item_permissions_and_water_stones.md).

**Profession crafting (2026-10-09):** Craft opens profession icon submenus above
the dock. Choosing Rudimentary opens Worker recipes with grouped categories and
that section's live Orders tab; Crafters returns to the chooser.
Planned profession sections preview their purpose without enabling fake crafts;
Miner's equipment preview is separate from its already playable profession.
Campfires and log stools are new Rudimentary recipes. Campfires center on the
cursor tile within a visible 3×3 placement area. Queue and Place remain
visible at 960×540; windows settle their wrapped layout and stay above the dock.
See [100 — Camp crafting](../00_dev_roadmap/100_profession_crafting_camp.md).

**Ladder workflow (2026-10-09):** Craft offers ladder sections at the crude
workbench. Place → Access shows the complete route, height and required section
count; R rotates and Esc finishes. The ladder inspector pauses/resumes building
and requests or cancels dismantling. Dwarf inspection identifies installation,
climbing with cargo and safe descent. Craft's recipe list scrolls on small
windows. See [86 — Rudimentary ladders](../00_dev_roadmap/86_rudimentary_ladders.md).

**Plant placement update (2026-10-09):** bushes, cuttings and flowers display a
3×3 cursor/queued outline and a specific overlap reason. Flower inspectors add
Move/Uproot; Place → Plants lists three stored flower shapes with thumbnails.
The dwarf inspector labels flower lifting/carrying/replanting appropriately.
See [85 — Plant habitats and flowers](../00_dev_roadmap/85_plant_habitats_spacing_flowers.md).

## Overview

All UI is implemented as Godot `Control` nodes on a `CanvasLayer`. No 3D world-space UI elements. The interface is divided into four zones: **Status Bar** (top), **Side Panel** (right), **Dock** (bottom — a floating command bar), and **Notification Layer** (overlay).

**Storage inspection (updated 2026-10-11):** clicking a ground zone, chest, barrel or
shelf opens the shared Hearth & iron storage panel. Filters and Contents share
a persistent capacity readout: occupied physical cells/slots and total goods.
Players can select whole categories, individual items, or mixtures; partial
categories show a dash. Accept all goods and Clear all filters act immediately.
Contents groups totals by item/material in alphabetical order, preserving wood
variants and counting all units in produce crates. It has no Allow/Disallow
buttons. Goods excluded by the filters remain listed with Awaiting relocation;
dwarves move them only after reserving accepting storage with room. Zone removal,
container uninstall, native window dragging and world-input isolation remain.
See [59 — Storage filters](../00_dev_roadmap/59_storage_filters.md).

## Object explorers (implemented 2026-10-04)

**Terrain faces (2026-10-12):** bare walls, floors and ceilings are clickable.
Object explorer names the visible material and shows type, surface, level and
natural/constructed status, with a block outline. Slice caps and planned openings
keep ore/gems concealed. Ordinary object, mining-zone and storage-zone inspectors
take precedence; active tools keep their inputs. Technical block diagnostics are
under Development. See [130 — Terrain inspection](../00_dev_roadmap/130_terrain_inspection.md).

**Wildlife (updated 2026-10-10):** rabbits, deer, wolves and ducks share Object
explorer, Locate and Follow. Ducks remain inspectable while swimming, on shore
and in flight; wakes/splashes do not enlarge their pick bounds. Hidden slice
levels hide birds and effects together; full-world view includes high flights.
Click a visible duck to inspect it or use Follow, including birds from later
flocks. See
[111 — Duck wildlife](../00_dev_roadmap/111_duck_wildlife.md).

**Juniper berries (2026-10-09):** tree Fruit/Fruit season rows now show juniper's
autumn crop, including too young, out of season, ready, worker progress and
picked states. **Harvest berries / Cancel harvest** keeps the tree standing.
**Orders → Harvest plants** accepts ripe junipers and shrubs in one rectangle;
live counts, Cancel orders, Undo and View order work across both owners. See
[84 — Juniper harvesting](../00_dev_roadmap/84_juniper_berry_harvesting.md).

**Surface stones (2026-10-08):** Object explorer exposes Clear boulder / Cancel
clearing for boulders, Gather stones / Cancel gathering for walkable scree, plus
work status/progress and rough-stone yield. Projected markers identify active orders.
**Orders → Clear stones** supports single clicks and ground rectangles with a
live count. Cancel orders includes both categories alongside blocks and trees; Undo and
View order use the shared banner. Cancellation retains partial clearing work.
Click a visible boulder or loose-stone clump to inspect it without changing
its work state.
Dwarf inspection and the roster distinguish hand gathering, boulder breaking
and tree chopping. See [74 — Gatherable scree](../00_dev_roadmap/74_gatherable_scree.md).

**Cabinet follow-up (2026-10-07):** the shared Object explorer now uses the same
gold border, wood-toned title bar and serif heading as Slice and Rooms. Generic
tree, furniture and resource inspection has an inset identity card, copper kind
label, and a scrolling facts/description body with actions kept outside it. The
whole window stays inside the viewport; saved/dragged positions are preserved.
Selection outlines use the shared copper accent. Dwarf and storage inspection
retain their specialized content within the same cabinet chrome. See
[63 — Loose item support and explorer](../00_dev_roadmap/63_loose_item_support_and_explorer.md).

Trees and furniture in the main scene share a movable context window through
`ObjectExplorerController` and `UIWindowManager`. All trees keep Growth stage,
Fruit, Fruit season, Felling yield, and Felling status in fixed rows, including N/A values.
The **Orders → Chop trees** command supports single clicks and ground rectangles
with a live tree count. Release commits the rectangle; Escape cancels the gesture
and exits the tool. The rectangle redraws every frame after camera movement, with
the tree count refreshed separately. The Orders group highlights its open menu;
the active tile and shared tool banner indicate the selected mode.
Marked trees retain a mouse-transparent 🪓 above their canopy,
projected on a CanvasLayer and hidden with sliced-out trees.
The explorer offers Fell tree / Cancel felling. Forestry Zone
and Clear Stumps remain disabled until their systems are implemented.
Furniture retains its own status, storage information and actions in the same
window. See [48 — Object explorers and tree felling](../00_dev_roadmap/48_object_explorer_and_tree_felling.md)
for input behavior, provider ownership, validation, and the next tool-animation milestone.

**Dwarf inspection (2026-10-05):** visible dwarves now use the same selection
system. Their inspector is the first **Hearth & iron** surface: a portrait of the
actual dwarf, live activity/destination, rest, exact cargo and carry load, plus
Locate and Follow. Details shows location, current work explanation and each
trait's name and description. It explicitly labels trait effects as inactive;
Light Sleeper's authored seven-hour sleep duration is not yet a runtime modifier.
The body scrolls at smaller resolutions while actions remain visible. See
[51 — Dwarf inspection](../00_dev_roadmap/51_hearth_iron_dwarf_inspector.md).

**Shared Hearth & iron theme (2026-10-05, stage 2):** all current UI surfaces now
use `UITheme`: charcoal panels, copper accents, warm text, serif titles and compact
corners. Standard windows, object explorers, dock menus, independent storage/mining/
room/furniture panels, debug windows, tooltips and toasts share these definitions.
Danger actions retain red text; developer actions use warm orange. See
[52 — Shared UI theme](../00_dev_roadmap/52_hearth_iron_shared_theme.md) for ownership
and verification.

**Worker crafting (2026-10-07):** the Craft cabinet presents Worker recipes,
live timber/finished stock and a stable make/maintain order queue. Allowed-wood
checklists default to Pine and can be changed per recipe draft or existing order;
empty choices never mean all wood. The cabinet also opens from the installed
crafting stump's explorer action. Dwarf inspection shows the actual crafting
spot or stump stand, not the scheduler's placeholder coordinates. See
[64 — Worker crafting](../00_dev_roadmap/64_worker_crafting.md).

**Grouped navigation (updated 2026-10-12):** ten illustrated entries with hover
names replace the labeled copper line icons. Orders, Zones, Rooms, Construction, Place, Craft, Colony, Inventory, Menu and Development
sit along the bottom, making room for the fixed time/Slice controls at the right.
The Sky Dial shows calendar/weather at the upper right. Menus stay
beside the default right-hand inspector and scroll at smaller resolutions. All
object inspectors now start on the right; existing saved or dragged positions take
precedence. See [53 — Navigation and layout](../00_dev_roadmap/53_hearth_iron_navigation.md).

**Place catalog (2026-10-05 follow-up):** the furniture Build list is now a movable
cabinet with model thumbnails, categories and a paper detail area. It lists finished
furniture with live Available/Reserved counts; Show all designs also reveals unavailable
items. Starter production now lives in Craft; Place displays the real queued
output count and installs its finished items. The catalog stays open while placing,
and clicking an available tile immediately starts its placement preview. It
supports Undo of unfinished requests and stops when stock runs out. Inventory
updates preserve tile positions and scroll while browsing; zero-count tiles stay
visible until reopen, and newly available designs append at the end. See
[54 — Place catalog](../00_dev_roadmap/54_place_catalog.md).

**Plants in Place (2026-10-08):** the Plants category lists whole uprooted
blueberry, elderberry and wild-strawberry bushes with species thumbnails and
real Available/Reserved counts. **Replant shrub** starts the normal ground
preview. Cuttings cannot satisfy it. Individual shrub inspectors offer **Move**
to choose a destination before uprooting, or **Uproot** for storage and later
placement, alongside Harvest/Clear. Cancelling a placed Move request also cancels
unfinished uprooting; an already lifted plant stays intact. See
[79 — Shrub transplanting](../00_dev_roadmap/79_shrub_transplanting.md).

**Cuttings in Place (2026-10-08):** Plants also has three cutting entries with
young-model thumbnails, separate stock counts and **Plant cutting**. The detail
area explains one-cutting cost, growth days and winter dormancy. Young shrub
inspectors show growth percentage/remaining days and **DEV: Grow to maturity**;
Move/Uproot and berries are enabled only at maturity. See
[80 — Shrub cutting growth](../00_dev_roadmap/80_shrub_cutting_growth.md).

**Zone window movement (2026-10-05 follow-up):** Mining Zone and Storage Zone now
register context windows with `UIWindowManager`. Drag their title bars to move them;
positions are remembered in `user://ui_layout.json` across reopening and game
restarts. They stay closed on startup until a zone is selected. Live mining counts
refresh without bringing the panel to the front. Closing clears the inspected zone,
and removing a selected zone also closes its window. Mining's instruction callout
uses the shared Orders banner when a dock is present.

**Tool shelves (updated 2026-10-08):** Orders opens Mine blocks, Chop trees,
Clear stones and Cancel orders; Zones opens Stockpile. Unimplemented Farm plot is omitted.
Selecting a tool starts it directly and keeps its shelf open. Switching groups
ends the active tool; closing its shelf retains the tool and its group highlight.
The shared banner sits above the shelf (or dock when closed), showing live
selection feedback, Done / Esc and Undo last order. Feedback
offers View order through the existing inspectors. Cancel clicks or drags over
unfinished mining/chopping/stone clearing or gathering; Undo cancels the last designation's remaining work
without recreating completed terrain. See
[55 — Orders shelf](../00_dev_roadmap/55_orders_shelf.md).

**Colony Inventory (2026-10-05 follow-up):** Inventory opens directly from the
bottom dock into a movable cabinet with real model thumbnails, categories and
parchment details. Total is Stored + Loose + Carried; Reserved is a subset,
and Available excludes goods assigned to hauling or placement. Crates count
contents. Locate and Inspect storage resolve current owners. Furniture remains
counted here; furnishing happens through the separate Place dock entry.
Tiles stay fixed through hauling. Developer spawn
controls now live in Development. See
[56 — Colony Inventory](../00_dev_roadmap/56_colony_inventory.md).

**Colony Dwarves (updated 2026-10-06):** Colony → Dwarves opens a wider movable
overview with a compact roster on the right and the shared dwarf details on the
left. Actual portraits, activity/cargo, rest, live workforce filters and name
search remain; rows keep their positions during updates. Selection uses the same
world controller and embeds Overview/Details, traits, Locate and Follow without
opening another window. The two columns scroll independently. Escape closes the
combined overview; ordinary world inspection resumes after closing. This pass
initially added no labor controls; milestone 96 adds Work and Profession views. Developer tools remain in Development → DEV: Dwarf
tools. See [57 — Roster](../00_dev_roadmap/57_colony_dwarf_roster.md) and
[61 — Colony overview](../00_dev_roadmap/61_colony_overview.md).

## Stockpile Display Readouts (planned)

Resource counters below are a future design. The Sky Dial shows the live calendar
and weather; the fixed bottom-right utility dock holds pause/speed and Slice.

### Layout

```
[ 🪨 Stone: 1,204 ]  [ 🍺 Ale: 47 ]  [ 🌾 Food: 312 ]  [ ⛏ Ore: 88 ]  [ 💰 Trade Goods: 5 ]
```

### Item Counter Rules

- Counters update via signal (`StockpileManager.stockpile_changed`) — **never poll per frame**.
- Numbers above 9,999 are displayed as `9.9k`, `10k`, `100k` etc.
- A counter flashes **red** for 2 seconds if the quantity drops to zero.
- A counter flashes **green** for 1 second when a batch of goods is received (trade delivery).

## Floating Dock (Bottom Command Bar)

The bottom-centered **floating dock** is a Hearth & iron bar on a `CanvasLayer`.
Ten illustrated entries use original atlas art from `assets/ui/dock/`, with
names on hover or keyboard focus. An open group stays highlighted, including while a submenu is
open. Only one action menu opens at a time; a second click or Escape closes it,
and submenus have a Back button. Active tools retain their existing Escape handling.

**Craft** opens a Crafters submenu of profession icon buttons above the dock,
not a recipe window or profession dropdown. Selecting Rudimentary, Carpenter,
Stonemason, Blacksmith or another entry opens that profession's titled crafting
menu. Planned entries remain browsable previews without craft/place actions.
The recipe window's **‹ Crafters** button returns to the profession submenu.
The submenu uses one desktop row and balanced compact rows; its open state
keeps Craft highlighted. Orders shown belong to the selected section, while
switching menus preserves the actual production queue and chosen Worker recipe.

### Data-Driven Layout

Dock order, icons, menu labels and action bindings live in `data/ui/dock.json` and are loaded by the
`UIRegistry` autoload (Registry Pattern — no other script reads the file directly). The
data file's scope is **layout only**: order, icon, label, tooltip, disabled state and action bindings.
The action *logic* lives in GDScript — the dock node maps each `action` string to a handler
via a dispatch table — per the JSON-vs-GDScript rule (*JSON = what things are, GDScript =
what things do*). Buildable-entry catalogs (costs, `action_type`, `requires_floor`) are a
separate concern and are **not** part of `dock.json`. When those catalogs are specced they
will be JSON loaded by their owning registry, never `.tres` Resources (see AGENT.md).

`data/ui/place_catalog.json`, also owned by UIRegistry, holds furniture categories,
short captions and display order. Physical definitions stay with
FurniturePlacementController; Available and Reserved are derived from actual items
and pending placement requests, not UI data.

```json
{
  "schema_version": 2,
  "items": [
    { "id": "orders", "icon": "res://assets/ui/icons/orders.svg", "label": "Orders", "action": "open_panel", "target": "orders" }
  ],
  "menus": {
    "orders": {
      "title": "Give an order",
      "items": [
        { "id": "mine", "label": "Mine blocks", "action": "activate_tool", "target": "mine_precision" }
      ]
    }
  }
}
```

`UIRegistry.get_dock_items()` returns the ordered navigation buttons;
`get_menu(target)` returns a title, optional parent group and validated command
entries, illustrated state, dock anchor and desktop/compact column limits.
Buttons require `id`, `label`, `action` and `target`; `icon`, `icon_region`,
`tooltip`, `planned`, `preview` and `status_label` supply presentation.
Malformed entries are skipped with a warning at load. Place and Inventory
category definitions also carry atlas metadata through UIRegistry.

### Action Types

| `action` | Effect |
|---|---|
| `open_panel` | Opens a build/designation panel above the dock. Panels are **mutually exclusive** — opening one closes any other. `target` names the panel. |
| `toggle_window` | Toggles a movable floating window (labor, inventory, trade). `target` names the window. |
| `activate_tool` | Emits the existing `tool_requested` signal. Orders keeps its shelf open; other command menus close. Controllers retain the one-active-tool contract. |
| `panel_action` | Save and developer commands dispatch by stable item `id`; legacy actions retain their existing handler. |
| `open_crafting` | Closes the profession chooser and opens the recipe/preview menu for the section named by `target`. |

### Save / Load Menu

**Menu → Save / Load** opens an illustrated child row with Back above
the dock. Hover/focus names identify **Save game**, **Load game**, and
**Load autosave**. Stable action IDs route the callbacks. `DockUI` emits
`save_game_requested`, `load_game_requested`, or `load_autosave_requested`; `SaveManager`
owns the timer, file I/O, and state serialization.

The dock finishes closing the menu before emitting persistence signals, because
a load listener can synchronously remove the old scene. Deferred layout and
position callbacks return when the dock is outside the scene tree. This lifecycle
is covered by `DockPersistenceLifecycleTest` and menu-driven scene reloads in
`SaveManagerRoundTripTest` (roadmap 161).

The manual quick save lives at `user://saves/quicksave.json`; a separate automatic save is
written every five minutes of ready, non-generating world time to
`user://saves/autosave.json`. Both use schema version 1, validate a temporary snapshot
before replacement, and retain one matching backup. If a selected primary is corrupt,
Load recovers that slot's backup and repairs its primary automatically. Autosaving shows a
brief **Autosaved.** toast and never replaces the player's manual save.
The save records the deterministic world seed plus authoritative deltas/state: mined
blocks and designations, the settlement flag and dwarf roster, stockpile zones and
contents, furniture ghosts/installed pieces and container inventories, loose items,
calendar/weather, finite water and stone identities, item/stack permissions,
wildlife/arrival progress, camera, and slice state. Load regenerates the seed-identical base
world and reapplies those sections in dependency order. Tasks, leases, reservations,
navigation/render caches, and interior-region tables are transient or derived and are
rebuilt. Snapshot creation is observational: it never releases a worker, changes an
assignment, or clears a reservation. Items currently in transit are recorded with their
carrier and materialize loose at that dwarf's saved position on load, where rebuilt work
sources can reclaim them. The dock shows a short success/error toast, including the
no-save-yet and world-still-generating cases. Required owner sections and typed
records are validated before changing the world; an empty scene or malformed
section cannot bypass backup recovery. Older development saves are not migrated.

The complete schema, ownership contract, restore lifecycle, and verification record live
in `00_dev_roadmap/20_save_load.md`.

Some `toggle_window` targets are intercepted in `DockUI._toggle_window` and routed to a real
system instead of a generic window: `world_info` / `block_inspector` toggle their overlay
CanvasLayers, `slice` toggles the **Slice tool**
(see below), and `rooms` toggles the **Rooms tool** (see below). `xray` remains a stub
until the X-Ray tool exists (`11_slice_xray_plan.md` §4).

### Developer cave explorer (2026-10-07)

**Development → DEV: Cave explorer** opens a nonpersistent inspection
window. Choose a cave and use **Focus + slice**; **Previous/Next** steps through
the cave catalog. Outlines project through terrain on a CanvasLayer. **Preview
interior with DEV lighting** temporarily exposes the selected cave with enough
light to inspect its walls, floor, veins and soil. Counts distinguish usable
floor area, air volume, exposed resources and soil blocks.

Highlighting or previewing does not discover, excavate or save a cave. Closing
the window restores the prior camera/slice and lighting, while preserving actual
mining and discoveries. Normal play reveals a connected system when mining
breaches its wall, with a short discovery toast. The real cave remains dark until
lit. See [68](../00_dev_roadmap/68_caves_and_discovery.md) for repeatable playtesting.

### The Slice Tool (shipped 2026-06-05 — doc 11 Phase 2)

The bottom-right **Slice** mountain icon toggles the slice view. `SliceController`
owns the plane and its saved state; the permanent `TimeSliceHUD` tower presents
double up, single up, a level readout, single down and double down. Single arrows
move one level and double arrows move exactly four. Buttons disable at their
bounds. Off retains the tower with muted arrows and **Full world**; reactivation
restores the last height. No movable window or duplicate Menu command remains.
An active plane at the upper limit reads **LEVEL 127**. Updated 2026-10-12 (142).

| Input | Effect |
|---|---|
| `\` | Toggle the slice view |
| `]` / `[` | Step exactly four levels up / down |
| `Ctrl+]` / `Ctrl+[` | Step one block up / down |
| Wheel over tower | Step one level up / down; Ctrl modifies this to four |

Clamps: Y4 floor (Bedrock Protocol — one mineable layer always visible) to Y127 (world top).
First activation seeds the plane from the camera's surface column; afterwards the height is
fully manual and remembered across toggles. Its active state, current height, seeded flag,
and last manual height persist in the version-1 quick save.
Activating Slice will force the future X-Ray tool off, and vice versa — mutual exclusion
lives in the tool layer, never the renderer.

### The Rooms Tool (shipped 2026-08-07 — doc 22 close-out follow-up)

The dedicated **Rooms** toolbar button toggles the **Rooms tool**, owned by `RoomOverlayController`
(scene node; DockUI only announces `tool_requested("rooms")` — the controller self-toggles
on its own id and every other click-tool deactivates, the standard one-active-tool
contract). While active, every sealed room draws a **volume outline** with a faint
floor tint: **green** for sealed rooms, **icy blue** for Frozen Vaults. Coplanar
interior edges are deduped. The 2026-10-06 follow-up removed filled walls and ceilings:
their stacked, unshaded green faces made unlit rooms appear bright. Floor opacity
is only 0.3%, or 0.6% when selected, so the actual room lighting remains legible.
Overlays render with **no depth test** (the mining ghost-layer treatment), so a room
reads through the mountain whether or not the slice is cut down to it; rooms above the
slice plane hide (the flora convention).

Left-click marches the mouse ray through the grid and selects the first room whose
interior air it crosses — clicks are as x-ray as the overlays, so a room visible through
rock is clickable through rock. Selection opens a movable **Room** inspector using
the shared cabinet chrome and remembered window position. **Overview** shows sealed/
Frozen-Vault state, temperature, depth zone, installed light count, volume and doors.
A room with no installed light says **No light sources** and suggests a torch or
brazier. **Details** retains heat units and +°C bonus, seasonal influence and average
floor level. The body scrolls on short displays. Readouts refresh at 2 Hz without
raising the window; closing clears selection. ESC
exits the tool; right-mouse stays camera-orbit (`21_camera.md` contract). Overlays and
selection are derived presentation state — never saved, rebuilt from `RoomManager` on
activation and on `room_updated`/`room_removed` (throttled 0.3 s). Selection survives
RoomManager's id churn by re-resolving through the clicked cell.

### Navigation Groups

| Group | Commands |
|---|---|
| Orders | Mine blocks, Chop trees, Clear stones, Harvest plants, Clear plants, Cancel orders |
| Zones | Storage; planned Farming and Animal pasture |
| Rooms | Direct room inspection toggle; active highlight, second click or Escape to exit |
| Construction | Stone block (one rough stone each) and Floors (plank/stone DEV previews) |
| Place | Finished furniture catalog: thumbnails, categories, live availability, repeated placement and Undo |
| Craft | Ten illustrated profession entries; working Rudimentary recipes and explicitly marked specialist catalog previews |
| Colony | Dwarves, Settlement flag, Labor and Trade |
| Inventory | Colony supplies with real thumbnails, live physical counts, Locate and Inspect storage |
| Menu | Save / Load |
| Development | Block inspector, World Build, Cave explorer, Dwarf tools, Water tools, Arrival status, Spawn Drops, Spawn Furniture, Time & weather |

Farming and Animal pasture explain their planned state without dispatching tools.
Labor opens the roster's real Work view; Trade retains a clearly marked preview.
Inventory uses live
supplies. Development is the rightmost dock entry; cycling object locators have
been removed from the game.

### Live Status HUD

The upper-right Sky Dial reads `WorldClock` and `WeatherManager`: its plaques show
time and season/day, while a sun/moon rim and changing landscape show the cycle
and weather. `SkyController` supplies the same seasonal rise/set times used by
world lighting. Hover or focus shows details; the old Clock window is removed.
The bottom-right Pause icon toggles pause/resume; play and fast resume at 1× and
2× respectively. Slice and its height tower remain fixed above the mountain icon.
Hover/focus supplies labels. The main dock shifts left to make room when needed;
at narrow widths the utility row lifts above its right end. Menus clear the
utility controls. See [141](../00_dev_roadmap/141_sky_dial.md) and
[142](../00_dev_roadmap/142_fixed_time_slice_hud.md).

### Panels (opened by `open_panel`)

| Panel | Contents |
|---|---|
| Place | **Eighteen furniture designs:** Barrel, Storage Chest, Storage Shelf, Tavern Bar, Bench, Hearth, Door, Trade Counter, Personal Dining Table, Communal Dining Table, Wooden Chair, Dwarven Bed, Brewing Vat, Wall Torch, Anvil, Smelter, Aging Rack and Brazier. Click an available tile to begin placing immediately; a dwarf fetches the packed item and installs it. Installed pieces retain **📤 Uninstall**. Crafting shows an unavailable dash until production exists. |
| Farming | Disabled future plot and crop commands |
| Military | Disabled future military commands |

Action menus center above the dock with an 8 px gap. If an open inspector would
overlap, they shift to the nearest side with enough room. Closing the inspector
recenters the open menu. These command menus use two columns. The Place cabinet
instead opens below the time strip on the left, with a three-column scrolling list,
fixed details/actions and a compact category dropdown on short viewports. It uses
the shared movable-window system. Long command menus scroll while their
header stays visible, and reopen at the top. At desktop widths the layout reserves
space for the default inspector on the right. Verified at 960×540, 1280×720 and
2560×1440; saved or dragged floating-window positions are still player-controlled.

Both torches take their mounting height and facing from the selected wall cell.
Alt + wheel adjusts height one block at a time; aiming at the adjoining floor
starts at the design's default height and keeps R rotation available. The hint
shows mount level and explains missing support, flame clearance or work access.
Workers install/remove within five blocks above a reachable work floor. Object
explorer shows mount level and **Waiting for reachable work position** when access
is lost. A pending plan retains its chosen position. See
[129 — Wall mount heights](../00_dev_roadmap/129_wall_mount_heights.md).
The hint is a screen-space `Label` on a `CanvasLayer`. Installed torches are
selected by visible model bounds, with terrain occlusion and slices respected.

### Emoji Rendering Requirement

Emoji icons require an **emoji-capable fallback font** in the project theme (e.g. Noto
Color Emoji). Godot's default theme font does not render emoji. Godot 4 supports
color-glyph fonts (COLR/CPAL, CBDT/CBLC, sbix) once one is loaded. Verify with a small
smoke test (a `Label` reading `⛏️🌾⚔️` on a `CanvasLayer`) before building the full dock.

## Stockpile Zone System

> **IMPLEMENTED (doc 18 — Stockpiles & Hauling, banked 2026-07-11).** Ground zones shipped:
> `StockpileZoneComponent` (work source posting HAUL leases), `StockpileDesignationController`
> (marquee tool, per-zone overlay, zone window with Remove — zones stay click-selectable with
> the tool off, mining parity), `StockpileManager` autoload (zone registry + aggregates), and
> the loose-item index on `ItemDropManager`. v1 zones accept everything; the filter panel below
> remains the design for the UI pass. Item defs are queried through `ItemDropManager`
> (registry pattern) — there is no separate ItemRegistry autoload.
>
> **Capacity rule SUPERSEDED (Alen, 2026-07-06 — Stonehearth parity):** ground zones store
> **one item per tile, no stacking** — quantity is WYSIWYG and capacity = empty cells. The
> `tile_count × 8` rule and `stack_max` below are retired from ground zones and reserved for
> the storage-container path (barrel/chest/shelf — doc 18 §2.5 follow-on).

A **stockpile zone** is a player-designated rectangular region of floor tiles that dwarves haul items into and workshops draw inputs from. Zones are defined by their **filter** — a set of accepted `material_tags` that controls which item categories are accepted.

### Zone Designation Flow

1. Player selects **Orders → Stockpile** and drag-paints floor tiles.
2. A `StockpileZone` node is created covering those tiles. Its default filter accepts `["stockpile_stone", "stockpile_ore", "stockpile_gem", "stockpile_soil", "stockpile_wood", "stockpile_food", "stockpile_drink", "stockpile_seed", "stockpile_misc"]` — i.e., everything.
3. The player can open the zone's filter panel (click the zone) to toggle individual tag categories on or off.

### StockpileZone Data Model

```gdscript
class_name StockpileZone extends Node3D

var zone_id:      int                  # unique ID, used by HaulTask payload
var tile_cells:   Array[Vector3i]      # all floor cells belonging to this zone
var filter_tags:  Array[String]        # accepted material_tags; empty = accept nothing
var inventory:    Dictionary           # { item_uri: int } — current counts per item type
# capacity is IMPLICIT (superseded rule, see note above): one item per tile —
# a zone is full when no empty unreserved cell remains
```

### Filter Tag Categories

These are the top-level tag groups shown in the filter panel UI:

| UI Label | Filter Tag | Covers |
|---|---|---|
| Stone | `stockpile_stone` | Mined rock and construction stone |
| Ore | `stockpile_ore` | Copper, tin, iron, silver, coal, gold |
| Gems | `stockpile_gem` | Ruby, sapphire — brilliant when mined |
| Soil | `stockpile_soil` | Cave soil, light soil, dark soil |
| Wood | `stockpile_wood` | Pine, oak, juniper logs, apple wood, and crafted staves |
| Food | `stockpile_food` | Mushrooms, grains, berries, seeds |
| Drink | `stockpile_drink` | Ale, mead (finished brews) |
| Seeds | `stockpile_seed` | Planting seeds of all species |
| Misc | `stockpile_misc` | Cloth, water buckets, fossil fragments |

### Acceptance Check

When a dwarf carrying an item looks for a valid stockpile destination, the check is:

```gdscript
func accepts_item(zone: StockpileZone, item_uri: String) -> bool:
    var item_def := ItemRegistry.get(item_uri)   # loaded from resources.json
    var overlap  := item_def.material_tags.filter(func(t): return t in zone.filter_tags)
    return overlap.size() > 0 and zone.inventory.values().reduce(func(a,b): return a+b, 0) < zone.capacity
```

An item is accepted if **at least one** of its `material_tags` matches a tag in the zone's `filter_tags` and the zone is not at capacity.

### Workshop Input Lookup

Workshops do not maintain their own input buffer. When a BREW/BUILD task begins, the worker polls `StockpileManager` for the nearest zone that:
1. Accepts the required input item (via the acceptance check above).
2. Has `inventory[item_uri] >= required_count`.
3. Is reachable via the navigation graph.

`StockpileManager` (Autoload) owns all zones and exposes:

```gdscript
func find_nearest_zone_with(item_uri: String, count: int, from: Vector3i) -> StockpileZone
func register_zone(zone: StockpileZone) -> void
func deregister_zone(zone: StockpileZone) -> void
signal stockpile_changed(zone: StockpileZone, item_uri: String, delta: int)
```

> **Agent note:** Item counts in `StockpileZone.inventory` are the authoritative source. The top status bar counters (Stone, Ale, Food, etc.) are aggregated from all zones by `StockpileManager` on every `stockpile_changed` signal — not tracked separately.

## Warning Toast Notifications

Short-lived overlay messages alerting the player to critical colony events.

### Toast Parameters

| Parameter | Value |
|---|---|
| Display duration | 4 seconds |
| Fade out | 0.5 s ease-out |
| Max simultaneous | 5 (oldest dismissed first if exceeded) |
| Position | Top-right, stacked vertically with 8 px gap |

### Severity Levels

| Level | Colour | Example trigger |
|---|---|---|
| `INFO` | White | "New migrants have arrived" |
| `WARN` | Amber | "Ale stockpile is low" |
| `ALERT` | Red | "A dwarf has died" |
| `CRITICAL` | Flashing red | "Flood detected on level 12" |

```gdscript
# Usage
ToastManager.push("Ale stockpile is low", ToastManager.WARN)
```

## Labor Assignment — live first pass (2026-10-09)

**Colony → Labor** opens the Work view of Colony Dwarves. Haul, Gather, Mine,
Build and Craft checkboxes control each real dwarf; Craft remains Worker-only.
Transport inside an allowed job and automatic rest are independent of those
checkboxes. Overview retains its activity/cargo/rest display. **Profession** in
the selected dwarf panel opens a career map with immediate Worker/Miner changes,
Carpenter promotion through physical kit collection, retained experience and
clearly marked future roles. See
[96 — Professions and Miner](../00_dev_roadmap/96_professions_and_miner.md) and
[101 — Tool promotion](../00_dev_roadmap/101_tool_based_promotion.md).

### Equipment and promotion feedback — live (2026-10-09)

The shared selected-dwarf panel has **Overview**, **Details** and **Equipment**
views alongside the **Profession** action. Equipment shows the actual owned
tool, picture, tier, materials and benefit. Carpenter's iron saw and Miner's iron
pickaxe are clearly marked planned/not craftable, with their future maker and
assignment flow. Narrow Colony details use two navigation rows; compact screens
omit the duplicate tool summary to preserve scrolling. Completed specialist
promotions play a short chime through the existing Work audio controls, including
immediate Miner promotion while paused. Request/cancel/demotion/load are silent.
See [102 — Equipment feedback](../00_dev_roadmap/102_equipment_view_promotion_feedback.md).

### Historical extended labor proposal (not implemented)

The implemented **Colony → Dwarves** roster shows current work and rest, with
selection and Locate actions. The assignment controls below remain future design.

### Columns

| Column | Description |
|---|---|
| Name | Dwarf name + health dot (green / amber / red) |
| Job | Current active task label |
| Priority | Drag-sortable priority score (1–10) |
| Skills | Icon row: mining, hauling, farming, brewing |
| Idle | Checkbox — manually force dwarf to idle |

### Rules

- Assignments are suggestions; the **Task System** (see `31_task_system.md`) retains final allocation authority.
- Forcing a dwarf idle via the checkbox inserts a high-priority `TaskIdle` token that blocks other task allocation for that dwarf.

## Active Task Tracking Log

A scrollable log in the right panel below the labor window. Shows the last 50 completed and in-progress tasks with timestamps.

```
[12:04]  ⛏  Urist mines Granite (Level 7)       ✓ done
[12:05]  📦  Bomrek hauls Stone × 8 to Stockpile  ⟳ in progress
[12:05]  🍺  Dastot brews Longbeard Ale            ⟳ in progress
```

---

*Prev: [22_mouse_input.md](./22_mouse_input.md) | Next: [31_task_system.md](../30_simulation_systems/31_task_system.md)*
