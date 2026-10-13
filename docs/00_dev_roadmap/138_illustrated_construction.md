# 138 — Illustrated Construction menus

Status: **implemented** — 2026-10-12.

## Player experience

Construction now uses original Hearth & iron illustrations with names and
descriptions on hover or keyboard focus. The compact row anchors above the
Construction dock icon and uses the same copper connector as the other
illustrated menus. Icons are 64 px on desktop and 56 px on compact windows.

The existing hierarchy remains:

- **Stone block:** a solid rock cube. Starts the normal construction tool;
  hover explains the one-rough-stone cost and natural layer matching.
- **Floors:** a sample of plank and laid stone flooring. Opens a second row
  with **Simple plank floor** and **Simple stone floor**, plus a back arrow.

Both floor icons carry a small flask badge. They are usable **DEV previews**:
players can still draw blue floor plans and complete them through the plan's
DEV Build action. Hover explains the required future Carpenter or Stonemason,
the separate floor excavation, and +5 appeal for fully floored rooms. These are
not locked entries like the planned Farming and Animal pasture buttons.

Choosing a material closes the menu and starts its existing tool. Construction
stays highlighted while the tool is active; Escape ends it. Costs, worker
availability, construction validation, floor meshes, appeals and saves remain
owned by their existing systems. No wall finishes or extra wall types were added.

## Implementation

- `data/ui/dock.json` specifies the four icon regions, hover text, floor preview
  status, illustrated menu presentation and Construction anchor.
- `UIRegistry` exposes the menu presentation metadata and creates AtlasTextures.
- `DockUI` presents illustrated action menus without their ordinary title bar,
  positions them beside inspectors when necessary, and retains the existing
  dispatch and parent/back navigation. Other action menus retain labeled layouts.
- `DockIconButton` shows the floor preview flask and tooltip status, separately
  from planned-entry locks. The source is `assets/ui/dock/construction_atlas.png`.

No new global script class, autoload or save format. Restart Play to load it.

## Verification

`ConstructionInputTest` covers real stone designation and inspection, plus
mouse/keyboard navigation, both floor tool selections, Back, hover/focus,
preview help, active highlights and the switch back to ordinary Menu. Layouts
are checked at 960×540, 1280×720 and 2560×1440. Native captures were reviewed.

`FloorConstructionTest` covers real floor planning, worker restrictions, DEV
completion, occupancy/support validation, room appeal, mining and current-save
restoration. Both fixtures passed headlessly; native construction input passed.
Logs and captures: `tmp/construction_art_20261012/`. The native fixture emits
its existing empty-environment warning, with no script errors.

The shared native `DockArtPreview` also passed for all ten main commands,
ordinary menu layouts, tooltips and connector cleanup following these changes.

## Artwork provenance

Created with the built-in imagegen tool. The existing Deepdraft Zones atlas
provided the style reference; the installed floor thumbnails supplied pattern
and shape references. The generated sheet is kept intact and sampled by Godot.
Full prompt: [138 — Construction art prompt](concepts/138_construction_prompt.md).
