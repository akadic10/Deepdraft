# 114 — Crafting category browser

Implemented 2026-10-11 following the user's Stonehearth crafting reference.
The previous cabinet stacked large recipe tiles in one narrow list and kept a
third column of orders open while browsing, making the growing catalog hard to
scan.

## Player flow

- Craft still opens the existing profession chooser; Rudimentary contains the
  real Worker recipes. Crafters returns to the chooser.
- Recipes are small illustrated buttons under Workshops, Lighting, Access,
  Camp furnishings and Starter tools. Groups come from recipe data; new recipes
  join their group even if appended elsewhere in the data file. All five groups
  fit together at 1280×720 and above; the browser scrolls on compact screens.
- Search matches recipe names and categories without case sensitivity. Empty
  groups disappear, the first remaining recipe becomes selected if needed, and
  a no-results state prevents queuing a hidden recipe. Hover reveals item names
  and descriptions. Recipe deep links clear a conflicting search.
- The single parchment card shows the selected illustration, output/time,
  required materials and workshop, description and purpose, allowed wood, stock,
  quantity/mode, Queue and Place. Information scrolls inside the card; actions
  remain visible at 960×540. Compact cards retain the short purpose text.
- Orders (count) replaces the browser when selected, retaining the detail card.
  Queuing does not force a tab change. Pause/resume, reorder, cancel and allowed
  wood remain attached to stable order rows. Search does not filter orders.
- Live stock updates preserve the active tab, keyboard recipe focus and queue
  scroll position. Returning from a planned profession remembers the selected
  real recipe. Planned professions have no actionable recipes or Orders tab.

`WorkerCraftingPanel.gd` owns this presentation. CraftingManager remains the
only work/data owner. No recipe costs, inventory rules, professions, save format,
assets, global classes or autoloads changed in this milestone.

## Verification

- `CraftingBrowserTest`: native rendering/input at 1920×1080, 1280×720 and
  960×540; grouped icons, selected illustration, case-insensitive category
  search, no-results gating, real tile clicks, typed batch quantities, stock
  targets, badge updates, pause, reorder, cancel, stable controls/focus/scroll,
  planned previews and returning selection all pass.
- `WorkerCraftingTest`: real bootstrap, workbench installation, material
  conservation, physical torch crafting, maintain stock, interruption/save state,
  cancellation, placement and compact UI pass.
- `ProfessionCraftingTest`: profession navigation/previews, campfire and stool
  costs, crafting, placement, animation, seating, restore and compact actions pass.
- Godot editor diagnostics: all 120 production scripts returned diagnostics;
  no errors or warnings. The test fixture alone reports its existing missing
  SkyController Environment warning.
- Reviewed native captures: `tmp/crafting_browser_20261011/recipes_1280.png`,
  `recipes_960.png`, `orders_1280.png`, plus captures at 1920×1080.

Restart the running game to load the UI edits. No project reload or new save is
required for this menu change.
