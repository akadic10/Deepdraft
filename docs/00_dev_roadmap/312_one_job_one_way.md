# 312 — One job, one way

**Status (2026-11-16):** built the same day on the owner's "proceed with your recommendations",
and not yet seen in play. All 244 tests and the lint pass. Almost nothing reads differently in
the game (see "What the player may notice"). The rules now live in doc 13 ("One job, one way") and CLAUDE.md ("Code: one job,
one way"). This doc stays until the owner has looked: "accepted" retires it, and "What is left"
moves to `00_todo.md` then.

## What the owner asked

After the wording review (doc 311):

> can we do a code review to find other inconsistent or not best practice approaches

and, on the review's findings and its suggested order: "proceed with your recommendations".

## What the review found

Every approach was counted across the 256 game scripts, the tests, the tools and the data, and
the outliers were read. Where the project has a written rule or a lint check, the code follows
it almost without exception. The inconsistencies sat where a new feature had no shared part to
use and copied its neighbour instead. The main findings:

- **Three zone tools, two of them copies.** Farming and Fishing shared 25 functions that were
  identical or nearly so (172 lines); Storage had the same shape in its own words.
- **Hotkeys were handled two ways.** 12 were input actions; the rest were key constants in 21
  scripts, and the Controls page typed 17 keys as words. Esc was read in 21 places, 16 of them
  without a check for key repeat.
- **Picture paths were built by hand** in 25 lines of 19 scripts, under two naming rules: item
  pictures carried the whole id, furniture pictures its last part.
- **Systems were found and called by names typed as text:** 124 group lookups and about 280
  calls or checks by method name. All resolved, but a typo or a rename would have failed
  nowhere.
- **Smaller ones:** a self-check that knew only five kinds of job source, three wordings held
  twice since doc 311, world numbers typed in several files, five colours declared in up to 12
  panels each, and two key names for the same thing in data.

The full report, with file and line for each, is `tmp/code_review_20261116/report.md`
(scratch, not in git).

## What was built

**One zone tool.** `scripts/components/ZoneTool.gd` (a `Node3D`, no class name, used through
`preload`) holds the drag, its preview, the hover, the zones drawn on the ground, the slice and
the click that opens a zone's window. `FishingSystem`, `FarmingSystem` and
`StockpileDesignationController` each add one as a child and say only what is theirs: why a
cell can't be taken, which zone stands on a cell, and what a finished drag means. The three
scripts are about 690 lines shorter between them, and the shared tool is 327. The cross-checks between zone kinds ("A field is here")
are asked in one place, `taken_by_another`, so a fourth kind of zone needs no line in the
others. Doc 23, "The zone tool".

**One way to register a tool.** `DockUI.register_tool(controller, shelf_ids)`. The dock's
`register_fishing_controller`, `register_farming_controller` and `register_mining_controller`
are gone; the tools the dock builds a window for keep their own function, which calls it.
Controllers call the dock through its type, not through `has_method` and `call`. A tool that
starts on its own says so with `DockUI.announce_tool(id)` instead of firing the dock's signal
from outside.

**Esc in one place.** `DockUI.cancel()` decides what Esc finishes, in a fixed order (doc 23,
"Esc's order"). Fifteen scripts dropped their own Esc branch: eleven tools, the DEV walk
test, the object explorer, the Professions page and the tool bar's menu. Each offers the step the dock asks for
(`deactivate()`, `cancel_step()`, `cancel_selection()`, `close_menu()`, `end_walk_test()`).
Esc is the `ui_cancel` input action, which leaves key repeat out. The game menu still takes
the key last, and the two name fields while they have focus.

**Keys in the input map.** Ten new actions in `project.godot`: `camera_forward`, `camera_back`,
`camera_left`, `camera_right` (each its letter and its arrow), `camera_slow` (Shift),
`tool_rotate` (R), `tool_toggle` (F), `tool_material_previous` and `tool_material_next`
(Q, E) and `tool_shape_next` (Tab). `Camera`, `ConstructionController`,
`BlueprintController` and `FurniturePlacementController` ask the actions. The Controls page
(`data/ui/controls.json`) reads every keyboard key from the input map, Esc included.

**One function for pictures.** `scripts/components/Pictures.gd`: `item(id)`, `furniture(id)`
and `of(id)` for goods that may be a packed piece. Nothing else names the two picture folders,
and the two tools that draw the pictures name their files through it. The 84 item pictures
were renamed to the last part of their id (`base_item_apple.png` to `apple.png`), as the
naming rule says and as furniture pictures already were.

**The small fixes.**
- Every job source that keeps a worker's claim answers `claimed_workers()` itself, so
  TaskManager's self-check now sees fishing spots, farm tiles and hanging batches too (doc 31).
- The temperature scale, "Badly hurt" and the food-shortage advice are read from the data
  that already held them (`TimeSliceHUD`, `DwarfConcern`, `EventLog.advice`).
- The top bedrock row and a chunk's edge are typed once, in `WorldSize.gd`.
- `MUTED`, `HAY`, `RULE`, `MOSS` and `RUST` are `UITheme` colours; 14 panels alias them.
- In data, the 15 keys that ended in `_s` end in `_seconds`, and the name shown for a recipe,
  a recipe section, a terrain block, a craft material, a stat and a fishing water is
  `display_name`.
- `WorldClock.game_seconds(delta)` gives game time for a frame; three scripts use it.

**The lint.** Three new rules, each with nothing to record on the day it was added:
`unknown-name` (a method, signal or group named in text that nothing defines), `picture-path`
(a picture folder named outside `Pictures.gd`) and `hand-key` (a key read by its constant).
The lint's own check of a piece's name against its recipe reads `display_name` now.

## What the player may notice

- **Storage's tool says why a cell is refused,** as Fishing and Farming do: "Can't store
  here", then "Furniture stands here", "A field is here", "A dwarf can't stand here" and the
  like.
- **A held Esc finishes one thing,** where it used to close one after another.
- **With the mining tool on and Crafting or Colony's inventory open,** Esc ends the tool
  first and the window second. Every other tool already did.

## Decisions of mine

For the owner's look; each is easy to change.

1. **Storage says why.** The shared tool works with a reason, and Storage had only yes or no,
   so it gained the sentences above. "Storage can't stand in water" is new wording.
2. **Esc's order is today's, written down,** apart from the mining tool (above). The
   Professions page still closes before a tool ends, as it did.
3. **F is `tool_toggle`,** not `tool_fill`: it fills a shape, switches Build's Replace and
   takes a copy's floor.
4. **The page writes "Esc",** though the input map calls the key Escape.
5. **Also renamed to `display_name`:** recipe sections and the fishing waters, which the
   review had not listed. A starter blueprint's `name` and the title screen's stayed: the
   first shares its format with the player's own blueprint files, and the second is the
   game's title, not a record.
6. **The pictures were renamed, not drawn again,** so each file is unchanged.
7. **`WorldClock.game_seconds` is used in three places** where it changes nothing
   (TaskManager, WaterManager, WorkFeedback). The other 14 places that multiply by the speed
   themselves were left.
8. **A dwarf's hunger card reads its advice from the event line** for the same trouble,
   rather than keep a second copy of the sentence.
9. **Three lint rules were added** without asking, since none needed a recorded list.
10. **Three background helpers** did the pictures and colours, the data keys and the hotkeys
    while I did the rest; the test runner was shared through a lock.

## What is left

- **Key names still typed as words:** the tool bar's hints (`data/ui/tool_bar.json`), its
  hover cards (`tool_bar_state` in `ConstructionController` and `BlueprintController`) and a
  few tooltips say "R", "Q / E", "Tab" and "F" as text.
- **Five plural lines** in the three zone systems ("%d spot%s") are still built in code. They
  were recorded as known by doc 311 and did not grow.
- **From the review's section 3, not built** (rules are in doc 13; each moves when its file is
  next changed):
  - functions for an item's `instance_id` and `stored`, and reading them through those;
  - the six small helpers that panels each carry (`_label`, `_text` and the like);
  - the 252 fallbacks in restore code that can never run;
  - the five task owners that still route task events themselves (doc 31 records them);
  - prints during normal play (each catch, harvest and furniture install);
  - `find(tree)` on the most looked-up scene systems, in place of group names in text;
  - small repeated constants outside the zone tools (the pick ray's 600 and 700, "no cell"
    under two names, neighbour tables under five);
  - `SurfaceFloraSpawner.gd` at 1,499 lines of 1,500;
  - mining drops on the engine's shared random source.
- **Still open from 2026-11-09:** asserts that guard data in the registries, and duplicate
  ids that silently let the last one win.
- **84 `.import` files** of the pictures' old names are left on disk; agents may not touch
  them. They are listed in `tmp/code_review_20261116/leftover_imports.txt`.
- **Doc 21** cites `OrdersShelfTest`, which does not exist.
- **Not checked:** the zone tools' hover outline, which follows the pointer and cannot be
  read in a headless test, and anything on screen.

## A correction to the review

The review said nothing wrote down that the scheduler's route waits count real time. Doc 31
did say so. It now also says why.

## What went wrong on the way

Moving the zone tools, I removed `try_select_zone_at_screen` from the three systems. The
object explorer asks every click tool for that function by name, behind `has_method`, before
it selects the bare ground. Nothing failed, and a click on a zone with the tool off would have
selected the ground instead. It is back, `FishingTest` now clicks a zone with the tool off, and
the test names the three scripts that must answer. This is the failure the review warned of,
and the lint cannot see it: the name still existed elsewhere.
