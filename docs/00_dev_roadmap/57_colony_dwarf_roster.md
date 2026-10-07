# 57 — Colony dwarf roster

**Layout update (2026-10-06):** [61 — Colony overview](61_colony_overview.md)
supersedes the separate-window arrangement below. The compact roster and the
same personal-details component now share one window; existing data and guards
remain. Escape closes the combined overview.

Implemented 2026-10-05. **Colony → Dwarves** now opens a player roster in the
shared Hearth & iron style. Stonehearth's character references informed the
portrait, readable identity and separation of overview from personal details;
the panel uses Deepdraft's own models, theme and existing game state.

## Player experience

- Each row shows the actual dwarf portrait, name, profession, current activity,
  carried goods and rest. Cargo thumbnails reuse existing item/furniture renders;
  crate quantities report contents.
- All, Working, Resting and Idle filters show live counts. A name search is case
  insensitive. Typing and moving the caret cannot pan the camera.
- Rows retain birth order, selection, scroll and keyboard focus as activity
  changes. Arrivals append; removed actors disappear. Filters change the visible
  membership, but never sort rows by their changing status.
- Click a row to open the existing dwarf inspector, with Overview, Details,
  Locate and Follow. The roster stays open beside its default position. There
  is no second personal-details screen or duplicated simulation state.
  Details includes trait descriptions and their inactive gameplay-effect status
  (see [doc 51](51_hearth_iron_dwarf_inspector.md)).
- A row's **Locate** centers the camera without changing selection, zoom or work
  assignments. Slice-hidden dwarves stay counted but cannot be inspected or
  located until visible again.
- The title bar drags and its position survives reopening. First Escape closes
  an open inspector; the next closes the roster. The roster compacts on narrow
  viewports and scrolls above the dock.
- Developer spawning, walking, stress tasks, interruption and tiredness controls
  remain under **Menu → Development → DEV: Dwarf tools**.

## Ownership

`DwarfDirector` supplies live actor references and validates inspect/locate
actions. Selection uses node identity, so loading a new dwarf with a reused ID
cannot silently redirect the inspector.

`DwarfInspection.roster_state()` derives the short activity and work/rest group
from the same read model as the inspector. Working includes active tasks and
walking; Resting means the existing sleeping state. No health, morale, skills,
equipment or profession-changing systems were added.

`DwarfRosterPanel` updates existing controls every 0.35 seconds while open and
stops polling while closed. It renders portraits only as rows enter the visible
scroll area, then reuses them. The shared `DwarfPortrait` helper clones visual
parts into static isolated viewports; it never creates or registers live agents.

`UIRegistry` owns `data/ui/dwarf_roster.json` for filter labels and order. Action
logic remains in GDScript. No autoload, global class or save schema was added.

## Verification

`DwarfRosterTest.gd` exercises the native Colony menu, real pickup/deposit and
sleep transitions, cargo thumbnails, search/filters, camera input isolation,
stable rows, lazy portraits, selection/removal/ID reuse, slice guards, pause,
scrolling, title dragging, reopen/Escape and 960×540, 1280×720 and 2560×1440 layouts.
Captures are in `tmp/roster_review/`. Regressions cover `DwarfInspectorTest`,
`NavigationPreview -- --capture` and `SaveManagerRoundTripTest`, with test user
data isolated from player saves and window preferences.
