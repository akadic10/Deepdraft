# 142 — Fixed time and Slice HUD

Implemented 2026-10-12 from the approved Hearth & iron mockup.

## Player behavior

Pause/resume, normal speed (1×), fast speed (2×) and Slice are permanent
illustrated controls at the bottom right. Names and help appear on hover or
keyboard focus. The current speed and Slice state have independent copper
outlines and notches. Pause resumes the previous speed; either speed command
resumes immediately at that speed.

The fixed tower above the Slice icon contains double up, single up, a level
readout, single down and double down. Single arrows move exactly one level;
double arrows move exactly four, including from heights between mining-cell
boundaries. Both directions clamp at Y4/Y127 and disable at their limit.

Turning Slice off keeps the tower in place, mutes its arrows and reads **Full
world**. Turning it back on restores the previous level. An active plane at
Y127 still reads **LEVEL 127**; the button indicates that stepping is enabled.
The first activation still seeds from the camera surface's four-block cell top.

| Input | Effect |
|---|---|
| `\` | Toggle Slice and retain the previous height |
| `]` / `[` | Raise / lower exactly four levels |
| `Ctrl+]` / `Ctrl+[` | Raise / lower one level |
| Wheel over tower | Raise / lower one level |
| Ctrl + wheel over tower | Raise / lower four levels |

Wheel input over the tower is consumed by UI. World wheel input remains
available for camera zoom. Inactive stepping never moves the plane.

The old upper-left transport strip, movable Slice window and Menu → Slice view
shortcut are removed. The Sky Dial remains the upper-right calendar/weather HUD.

## Layout and ownership

- `TimeSliceHUD.gd` is a preloaded Control on CanvasLayer 24 so ordinary windows
  cannot prevent access to time/Slice. Only the occupied row and tower capture
  pointer input; the empty area beside the tower passes through to the world.
- The command dock remains centered where space allows, moving left just enough
  to leave room beside the utility row. If both rows cannot fit, the utility row
  lifts above the main dock's right end. Command menus avoid the occupied controls.
  Verified at 800×600, 960×540, 1280×720 and 2560×1440.
- Transport icons are 48/56/64 px at compact/medium/large widths. Steppers remain
  28/36 px tall, with live level text rather than baked numbers.
- `DockUI` routes speed commands to WorldClock and registers SliceController
  with the HUD. `SliceController` retains its renderer, keys, seeding and save
  ownership, with UI/window construction removed. Cave focus uses its same
  `show_at_height(height)` entry point.
- UIRegistry owns `data/ui/time_slice.json`; `TimeSliceButton` reuses the dock's
  hover/focus help and adds an art aperture for the supplied atlas regions.
  No new autoload/global class or save schema is introduced.

## Artwork

Original copper-and-green painted button atlas:
`assets/ui/time_slice/controls_atlas.png`. Built-in image generation and the
complete prompts are recorded in [the prompt log](concepts/142_time_slice_prompts.md).
Existing main-dock and Sky Dial art remains in use.

## Verification

- `TimeSliceHUDTest`: native rendered checks with actual clicks, keyboard events
  and wheel input; first-use seeding, exact off-grid offsets, both bounds,
  inactive guards, saved off-state restoration, retained heights, pause/resume,
  current-speed selection and four viewport sizes. Also checks menus, Sky Dial
  and food-warning separation.
- `SkyDialTest`: passed headless with the new utility HUD.
- `NavigationPreview`: passed native; existing navigation, menus, inspector and
  actual transport controls remain usable.
- `RemainingMenusTest`: passed headless for existing menus and catalog flows.
- Updated RoomLightingTest and DockArtPreview assertions for the new layout and
  exact four-level steps. The generated-world lighting fixture was not rerun.

Logs and native captures: `tmp/time_slice_20261012/`. The fixture's pre-existing
empty WorldEnvironment warning is benign; these runs contain no script errors.

Restart Play to load the changed scene/UI and artwork. A project reload is not
required; no new autoload or global script class was added.
