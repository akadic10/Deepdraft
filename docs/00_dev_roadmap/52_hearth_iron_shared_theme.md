# 52 — Hearth & iron: shared UI theme

Implemented 2026-10-05 after the player accepted the dwarf inspector and requested
stage 2 of the approved UI concept.

## Delivered

- A shared charcoal, copper and warm-text palette with compact 3 px corners.
  Georgia headings and Segoe UI body text use Noto/DejaVu system font fallbacks.
- Consistent panels, headers, close controls, button states, separators, scrollbars,
  progress bars, tooltips and success/error toasts. Removal actions use red text;
  developer actions retain warm orange text.
- The same style on the Clock, placeholder management windows, Dwarves, Slice,
  dwarf/tree/furniture explorers, dock menus, storage zones, mining zones, room
  information, fallback furniture windows, World Build and Block Inspector.
- Dock icons and spacing adapt to available width; every command stays visible
  at 1280×720. The command order and familiar icons remain intact.
- UI panels consume wheel input so scrolling over a window does not zoom the world.

## Ownership and scope

`scripts/ui/UITheme.gd` builds and caches the shared native Godot Theme in code.
`apply_surface()` assigns it to each root Control; dynamic children inherit it.
`apply_title()`, `apply_close_button()` and button variants handle the few deliberate
differences. All `StyleBoxFlat` construction now lives in this file. The initial
style pass added no `.tres`, autoload, scene wiring, JSON schema or save schema.

The standard `UIWindow` uses the theme automatically. Independently managed legacy
panels use the same definitions while keeping their current ownership, position and
behavior. This does not finish the older doc 24 plan to move every window into
`UIWindowManager`. Window rearrangement, navigation groups and broader input/feedback
changes belong to subsequent stages. Existing simulation and furniture behavior stay
with their current owners.

## Follow-up: movable mining and storage windows

The player reported that the newly styled Mining Zone and Storage Zone panels
could not move. Both now use `UIWindowManager` context windows (`mining_zone_info`
and `storage_zone_info`) with the same title-bar drag, bring-to-front, viewport
clamping and position persistence as the Clock. Their controllers export
`window_manager_path`, wired to the existing manager in `debug_world.tscn`.

Selecting a different zone reuses the window at its current position. Closing
clears the context selection; removing/mining out the selected zone closes its
window. Only positions are restored at startup, never an orphaned zone window.
Mining's periodic text refresh does not raise its window over another panel.
The informational mining hint remains on HUD layer 24; interactive zone windows
now share the manager's layer 22.

`ZoneWindowTest.gd` exercises actual GUI drags, close/remove clicks, body versus
title behavior, clamping, focus, live updates, world-input isolation, and an actual
layout-file reload. It requires APPDATA inside `tmp/zone_window_review/` and refuses
to run against player preferences. Headless and native runs pass, as do the mining
animation and full save/load regressions. Review logs and a native capture live
in `tmp/zone_window_review/`.

## Verification

- Editor import and script validation.
- `DwarfInspectorTest.gd` and `ObjectExplorerTest.gd`: actor/object picking, live
  information, actions, Follow/Locate, wheel isolation and responsive inspector.
- `tools/HearthThemePreview.gd -- --capture`: native Godot captures of the actual
  controls; menus and all dock commands fit at 1280×720 and 2560×1440; build clicks
  activate placement, unavailable forestry options stay disabled, close controls
  update visibility and dock state, and storage consumes wheel input.
- `SaveManagerRoundTripTest.gd`: full main-scene initialization and nonempty colony
  save/load/autosave/backup recovery, using isolated test storage.
- Review images and logs live in `tmp/hearth_theme_review/`. The preview fixture
  arranges windows for visual review without writing player layout preferences.

Follow-up: [53 — Navigation and layout](53_hearth_iron_navigation.md) implements
the approved grouped commands, live status strip and consistent inspector defaults.
