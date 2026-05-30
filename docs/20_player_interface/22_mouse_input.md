# 22 — Mouse Input

## Overview

All player interaction with the voxel world is mouse-driven. The two primary mechanisms are **voxel raycasting** (single-block selection) and **click-and-drag box selection** (multi-block region).

## Voxel Viewport Raycasting

### Method

Each frame (on mouse move or on demand), a ray is cast from the camera through the mouse cursor into the 3D world. The hit voxel is identified by stepping through the DDA (Digital Differential Analysis) voxel traversal algorithm.

```gdscript
func raycast_voxel(camera: Camera3D, mouse_pos: Vector2) -> Dictionary:
    var origin    := camera.project_ray_origin(mouse_pos)
    var direction := camera.project_ray_normal(mouse_pos)
    # DDA step loop — returns { "hit": bool, "block_pos": Vector3i, "face_normal": Vector3i }
```

### DDA Parameters

| Parameter | Value |
|---|---|
| Max ray distance | 80 m |
| Step precision | 0.5 m (matches block size) |
| Layer mask | Terrain only (Layer 1) |

### Hit Result

```gdscript
{
  "hit":        true,
  "block_pos":  Vector3i(x, y, z),   # world block coordinates of the hit block
  "face_normal": Vector3i(0, 1, 0),  # face the ray entered through
  "place_pos":  Vector3i(x, y+1, z)  # adjacent block position for placement
}
```

## Multi-Block Click-and-Drag Selection

Players can drag to select a rectangular region of blocks for batch mining or designation orders.

### Drag State Machine

```
IDLE
  → [Left mouse down on voxel hit]
DRAG_START (record anchor_pos: Vector3i)
  → [Mouse moves > DRAG_THRESHOLD px]
DRAGGING (update live selection box each frame)
  → [Left mouse up]
DRAG_CONFIRM (emit signal with AABB selection)
  → IDLE
```

`DRAG_THRESHOLD` = 6 pixels. Clicks shorter than this threshold are treated as single-block selections.

### Selection AABB

The dragged selection is computed from the **anchor block** and the **current raycast block** each frame:

```gdscript
var selection_aabb := AABB(
    anchor_pos.min(current_pos),
    (current_pos - anchor_pos).abs() + Vector3i.ONE
)
```

All blocks within `selection_aabb` receive the pending action (mine, designate, etc.) on mouse-up.

## Visual Indicators

### Single-Block Hover Outline

- A **wireframe cube** (`ImmediateMesh` or thin `BoxMesh`) is rendered at the hovered block position each frame.
- Colour: `Color(1, 1, 1, 0.8)` white by default; red if the action is invalid (e.g. mining bedrock).
- The outline must be rendered in the **unshaded** pass to always appear visible regardless of layer slicing.

### Drag Selection Box

- A translucent `BoxMesh` (colour: `Color(0.2, 0.6, 1.0, 0.25)` blue) fills the selected AABB volume during dragging.
- Wireframe edges of the same colour are drawn at full opacity on top.
- Both the fill and edges snap to the **block grid** — no sub-block interpolation.

> **Agent note:** Never interpolate the wireframe cursor to the mouse position in world space — always snap it to `Vector3i` block coordinates multiplied by `BLOCK_SIZE`. Sub-block positions will misalign with the grid visually.

---

*Prev: [21_rts_camera.md](21_rts_camera.md) | Next: [23_user_interface.md](23_user_interface.md)*
