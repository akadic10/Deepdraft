# 21 — Camera

## Overview

The camera is a top-down god-view with **no direct character control**. All navigation is performed by panning, rotating, and zooming the camera rig. The player never embodies a single unit.

## Camera Rig Structure

```
CameraRig (Node3D)          ← panning pivot, moves in XZ plane
  └─ CameraArm (Node3D)    ← horizontal orbital rotation (Y-axis)
       └─ SpringArm3D       ← spring collision + zoom distance
            └─ Camera3D     ← actual viewport camera
```

## Navigation Parameters

Values below track `data/camera/camera_settings.json` (source of truth). See
`docs/00_dev_roadmap/15_camera_rework.md` for the Stonehearth comparison and the full rework
(§0 has the shipped behaviour and the complete tunables table).

| Parameter | Value | Notes |
|---|---|---|
| Pan speed | 126 units/s base (keyboard); Shift = ×0.286 precision/slow | Fast by default, Shift slows for fine work; scales with camera height (`world_y / pan_reference_height`) |
| Zoom range | 2–180 units (default 85) | Min/max spring length; min lowered to 2 for ground-level close-up (surface floor prevents clipping) |
| Zoom step | proportional: `zoom_step_fraction` (0.18) × current distance per notch | Geometric zoom (15_camera_rework.md §4/§6); `zoom_speed` is the fixed-step fallback only |
| Zoom targeting | `mode: cursor_target` — zoom toward the ground point under the mouse, stopping `cursor_min_gap` (1.5) short of it | Marches the cursor ray against the terrain height field (`get_visible_surface_y`), works map-wide; scales pivot+spring toward the hit. `spring_fraction` = zoom toward pivot (no-hit fallback). (15_camera_rework.md §6/§8a) |
| Surface floor | ruggedness-scaled, `surface_floor_min_clear` (1.5) on flats → `surface_floor_margin` (8) at walls | Keeps the camera above terrain without colliders; sampled around the look point (15_camera_rework.md §8a) |
| Pitch clamp | −5° to −80° (look-down) | Stored as negative degrees; −5° ≈ shallow, −80° ≈ steep. Prevents gimbal flip and under-ground views |
| Orbit | Right-mouse drag, `dead_zone_pixels` (6) before it engages | Horizontal + pitch, snap (un-smoothed). Stonehearth parity (15_camera_rework.md §6 Phase 3) |
| Drag pan | Middle-mouse drag | Grab-the-ground: the grabbed point stays locked under the cursor |
| Edge scroll | Screen-edge mouse | Optional; toggle in settings |

## Horizontal Layer Slicing

A defining feature: the player can slice the world horizontally to see underground.

- The slice plane hides all geometry above a chosen Y level — implemented (2026-06-04) as the
  slice-aware block-face overview: the whole map stays present at any depth, cut floors show
  authored strata only (slice-concealment rule, `24_world_rendering.md`).
- Driven by `WorldRenderer.slice_y`; the Slice tool (shipped 2026-06-05 — `SliceController`,
  dock palette + `\` `]` `[` `Ctrl+]` `Ctrl+[` hotkeys, doc 11 Phase 2) steps it.
- AUTO mode (slice follows the camera): **dormant by decision** — Stonehearth has no auto-follow
  and manual control proved right (doc 10 §2.3, doc 11 Phase 2.6). `Camera.slice_y_changed`
  still emits but nothing connects to it; revisit only behind a settings toggle.

## Slice Visual Treatment

When a slice is active, the topmost visible layer should have a subtle highlight or edge fade (`slice_fade_bands`) so the cut reads clearly. See `24_world_rendering.md`.

## Implementation Notes

- All tuning values live in `data/camera/camera_settings.json`.
- The camera script is `Camera.gd`, attached to the `CameraRig` root.
- Never hardcode node paths; wire child nodes via `@export` (see `13_architecture.md`).
- `BLOCK_SIZE` is 1 m; slice math uses it to convert camera Y to a block layer.

*Prev: [20_player_interface](.) | Next: [22_mouse_input.md](22_mouse_input.md)*
