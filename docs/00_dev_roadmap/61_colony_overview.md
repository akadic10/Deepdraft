# 61 — Colony overview

Implemented 2026-10-06. The player requested a Stonehearth-inspired screen for
seeing all dwarves and chose **roster and details first**, leaving labor controls
for a separate pass.

## Player experience

**Colony → Dwarves** now opens one wider Hearth & iron window. A compact roster
on the right shows actual portraits, names, professions, current work/cargo,
rest and Locate. The selected dwarf's portrait, Overview and Details occupy the
left column, including activity, destination, rest, carry load, trait descriptions,
Locate and Follow. Trait effects remain explicitly labeled inactive.

The existing All / Working / Resting / Idle filters and name search stay live.
Rows retain birth order, keyboard focus and scroll during updates; arrivals
append. Changing a filter does not redirect the selected dwarf. Opening the
overview transfers an already inspected dwarf into its detail column; otherwise
it selects the first inspectable dwarf matching the current view, if any.

Closing the window or pressing Escape clears its dwarf selection and follow
target. Selecting a dwarf from the world after closing uses the ordinary detached
inspector again. Other object inspectors remain available. Slice-hidden dwarves
remain counted and listed; their world inspection/Locate guard is preserved.
Removal clears details by node identity, including when a numeric ID is reused.

Rows are 54–56 pixels tall. The roster and details scroll independently, without
zooming the world. At short viewport heights the portrait header compacts and
long names truncate with a full-name tooltip, keeping Locate/Follow and the
bottom dock accessible. Title dragging and remembered positions remain intact.

## Ownership

- `DwarfRosterPanel` owns the table, filters, layout and an embedded instance of
  the existing `DwarfInspectorPanel`; there is no second personal-data model.
- `ObjectExplorerController.set_dwarf_inspector_host()` transfers presentation
  while keeping selection, outline, provider validation and actions in the
  existing controller. Hiding the detached window during transfer does not clear
  selection or stop camera follow.
- The shared inspector has an embedded layout mode. Its ordinary world-window
  layout remains unchanged.
- Portrait rendering waits for container layout, then builds only visible rows.
  The static visual clones do not register actors or participate in simulation.

No labor controls, job preferences, skills, morale, new autoloads, global script
classes or save data were added. Restart play mode to try the overview.

## Verification

`DwarfRosterTest` passes with twenty actual fixture dwarves, real hauling/deposit
and sleep transitions, live search/filter counts, selected-details tabs, camera
actions, selection transfer with Follow, slice/removal/reused-ID guards, stable
rows/focus/scroll, lazy portraits, title dragging, Escape and reopening.

Native renders were inspected at 960×540, 1280×720 and 2560×1440, including a long
name. Captures and logs are in `tmp/colony_overview_review/`; the normal-name
preview is `colony-dwarves.png`.

Regressions passed: `DwarfInspectorTest`, `NavigationPreview -- --capture`
(including shared-theme checks), and `StorageFilterTest`. All runs isolated
user-data directories from player saves and window preferences.
