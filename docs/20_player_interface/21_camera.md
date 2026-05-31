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

| Parameter | Value | Notes |
|---|---|---|
| Pan speed | 36 units/s (keyboard), ×3.5 with shift | Scales with zoom distance |
| Zoom range | 50–340 units (default 110) | Min/max spring length |
| Pitch clamp | −5° to −80° (look-down) | Stored as negative degrees; −5° ≈ shallow, −80° ≈ steep. Prevents gimbal flip and under-ground views |
| Orbit | Middle-mouse drag | Horizontal only by default |
| Edge scroll | Screen-edge mouse | Optional; toggle in settings |

## Horizontal Layer Slicing

A defining feature: the player can slice the world horizontally to see underground.

- The slice plane hides all chunks above a chosen Y level.
- Controlled by scroll-modifier or dedicated hotkeys.
- The `slice_y` value is read by `WorldRenderer` to cull chunk meshes above it.
- AUTO mode: as the camera descends, the slice follows automatically.

## Slice Visual Treatment

When a slice is active, the topmost visible layer should have a subtle highlight or edge fade (`slice_fade_bands`) so the cut reads clearly. See `24_world_rendering.md`.

## Implementation Notes

- All tuning values live in `data/camera/camera_settings.json`.
- The camera script is `Camera.gd`, attached to the `CameraRig` root.
- Never hardcode node paths; wire child nodes via `@export` (see `13_architecture.md`).
- `BLOCK_SIZE` is 1 m; slice math uses it to convert camera Y to a block layer.

*Prev: [20_player_interface](.) | Next: [22_mouse_input.md](22_mouse_input.md)*
