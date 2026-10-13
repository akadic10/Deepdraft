# 141 — Sky Dial

Status: **implemented** — 2026-10-12, following approval of the Hearth & iron
clock/weather concept in this chat.

## Player experience

A permanent illustrated Sky Dial occupies the upper-right corner. Its rim runs
from midnight on the left to midnight on the right, with gold daylight and blue
night segments. A sun/moon marker follows the actual game hour. Daylight length
uses the same seasonal sunrise/sunset anchors as world lighting.

The mountain painting changes with the season and crossfades between day and
night through dawn/dusk. Current Clear, Overcast, Foggy and Snow weather have
distinct scenery overlays and badges. Clear nights use a moon. Rain in the
approved concept is illustrative; it is not a current simulation weather type
and has not been added as part of this UI work.

The lower plaques show exact 24-hour time and season/day. Hover, click or keyboard
focus reveals the current weather, day phase, year, sunrise/sunset and pause
state. Escape dismisses focused details. The details appear beside the dial so
they do not cover the food warning underneath. Dial clicks/scrolling stay in UI.

The old Clock window, Menu → Clock & weather entry and top-left calendar button
are removed. [142](142_fixed_time_slice_hud.md) subsequently moves Pause, 1×,
2× and Slice to the fixed bottom-right utility dock with a permanent height tower.
Development → Time & weather still owns the existing simulation test commands.

## Layout and ownership

- `DockUI` creates the HUD and anchors it 16 px from the right, 12 px from the top.
  The square artwork canvas is 184 / 204 / 224 px at compact / medium / large widths.
- The food warning is below the dial. Ordinary windows are clamped beside it
  (or below it when that fits). Large browsers at compact resolutions retain
  normal window priority and their full usable area. Existing nonoverlapping
  window positions are retained.
- `SkyDial.gd` is a preloaded Control, not an autoload/global class. It reads
  WorldClock and WeatherManager at 10 Hz and never advances or saves time.
- `SkyController.current_event_hours()` returns a copy of the same seasonal
  anchors its lighting curves consume. The HUD does not duplicate the calendar
  curve. Restore, day/season/year rollover and speed/pause remain authoritative.
- `UIRegistry` owns `data/ui/sky_dial.json`, including original art references,
  atlas regions and weather-to-symbol mapping. Images are cached Godot resources.
- Status is on CanvasLayer 21, windows on 22, focus details on 30. Full-screen
  HUD root ignores input; only the dial catches pointer events.

## Artwork

Built-in image generation produced these project-local assets:

- `assets/ui/sky_dial/frame.png`: transparent copper/iron frame and blank plaques.
- `assets/ui/sky_dial/landscapes.png`: four seasons × day/night, two columns/four rows.
- `assets/ui/sky_dial/symbols.png`: nine transparent weather/celestial/season symbols.

The original files retain their alpha and resolution. Godot atlas regions and
runtime geometry place the art, cycle track and live labels; text is not baked
into images. Exact prompts are in [141 — Art prompts](concepts/141_sky_dial_prompts.md).

## Verification

`SkyDialTest.gd` exercises all four seasons/weather types, shared rise/set anchors,
pause/speed, dawn/dusk, midnight/year rollover and restoration. Native captures
cover 960×540, 1280×720 and 2560×1440, including focused details, the food warning
and window clearance. `RemainingMenusTest`, `DwarfInspectorTest` and the native
`NavigationPreview` check surrounding menu/window/input behavior.

Logs and captures: `tmp/sky_dial_20261012/`. The fixture's existing empty-Environment
warning is unrelated to the HUD. Restart Play to see it; no project reload,
new world, save migration or rebuilding placed items is needed.
