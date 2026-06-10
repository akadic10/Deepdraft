# 21 — Camera

## Overview

The camera is a top-down god-view with **no direct character control**. All navigation is panning,
rotating, and zooming the camera rig. The player never embodies a single unit.

Feel is modeled on Stonehearth's `player_camera_controller.lua` (cursor-targeted zoom, height-scaled
pan, orbit-around-what-you-look-at), built in the 2026-06-07 camera rework and consolidated here as
the permanent reference. All tuning values live in `data/camera/camera_settings.json` (the source of
truth) and are hot-editable without touching GDScript. Logic is in `Camera.gd`, attached to the
`CameraRig` root.

## Camera Rig Structure

```
CameraRig (Node3D)          ← panning pivot, moves in XZ (and Y, via zoom/floor)
  └─ CameraArm (Node3D)     ← horizontal orbital rotation (Y-axis)
       └─ SpringArm3D       ← pitch + zoom distance (spring_length); collision mask = Layer 1
            └─ Camera3D      ← actual viewport camera
```

The rig is kept (not a free-flying camera): the spring arm gives terrain-collision headroom and a
clean pitch/zoom pivot. Terrain has **no physics colliders** (picking is a height-field/voxel
data-ray, not physics), so the spring arm cannot push the camera out of rock — the **surface floor**
below does that job instead.

## Controls

| Input | Action |
|---|---|
| WASD / arrows | Pan (screen-relative, rotated by orbit) |
| Shift (held) | Precision/slow modifier while panning |
| Middle-mouse drag | Grab-the-ground pan — the grabbed point stays locked under the cursor |
| Right-mouse drag | Orbit (yaw + pitch); engages after a small dead zone |
| Mouse wheel | Zoom toward the point under the cursor |
| Screen edge | Optional edge-scroll (off by default) |

While dragging, an emoji cursor shows the mode (✋ grab-pan, 🔄 orbit) and the OS cursor hides.

## Navigation Parameters

All values track `data/camera/camera_settings.json`. Defaults as shipped:

### `camera_settings`
| Key | Value | Meaning |
|---|---|---|
| `fov` | 45 | vertical FOV |
| `near_clip` / `far_clip` | 0.1 / 1024 | clip planes |
| `default_position` | (512, 70, 512) | rig start (pivot) |
| `default_rotation` | (−50, 0, 0) | start pitch −50° (look-down) |
| `surface_floor_margin` | 8 | camera clearance above terrain at a **wall/notch** |
| `surface_floor_min_clear` | 1.5 | clearance on **flat** ground (the close-up limit) |
| `surface_floor_ruggedness` | 12 | local height delta (blocks) at which full margin applies |

### `movement`
| Key | Value | Meaning |
|---|---|---|
| `move_speed` | 126 | base pan speed at the default framing height (**fast by default**) |
| `shift_multiplier` | 0.286 | Shift = precision/slow (< 1) |
| `pan_reference_height` | 135 | camera world-Y where `move_speed` reads at face value |
| `smoothing` | 0.22 | pan position lerp |
| `edge_scroll_enabled` / `edge_scroll_threshold_pixels` | false / 10 | edge scroll |

### `rotation`
| Key | Value | Meaning |
|---|---|---|
| `rotation_speed` | 0.6 | degrees per mouse pixel |
| `min_pitch` / `max_pitch` | −80 / −5 | look-down clamp (negative degrees; −5 shallow, −80 steep) |
| `dead_zone_pixels` | 6 | mouse motion before orbit engages |
| `dynamic_pivot` | true | re-anchor the orbit pivot to the look point on engage |

### `zoom`
| Key | Value | Meaning |
|---|---|---|
| `mode` | `cursor_target` | `cursor_target` (zoom to mouse) \| `spring_fraction` (zoom to pivot) |
| `zoom_step_fraction` | 0.18 | geometric step = this fraction of current distance per notch |
| `cursor_min_gap` | 1.5 | nearest the camera sits to the cursor's surface point |
| `min_distance` / `max_distance` | 2 / 180 | spring length range |
| `default_distance` | 85 | start zoom |
| `smoothing` | 0.15 | zoom lerp |
| `zoom_speed` | 8 | non-proportional fixed-step fallback only |

### `input_mappings` / `cursors`
`rotate_action` = right-mouse, `drag_action` = middle-mouse, move keys = WASD + arrows, zoom = wheel.
`cursors`: `enabled` true, `orbit` 🔄, `drag` ✋, `size` 28, `hide_system_cursor` true.

## Zoom (cursor-targeted)

Each wheel notch moves a **fixed fraction** (`zoom_step_fraction`) of the current distance — geometric
zoom, constant perceived speed at any distance, so one notch can never collapse the whole range.

In `cursor_target` mode the zoom homes toward the **ground point under the mouse**: a ray is marched
against the terrain **height field** (`WorldGenerator.get_visible_surface_y`) — the same source the
overview renderer uses, so it works map-wide even on columns not yet streamed into `WorldData`. The
rig pivot **and** spring length scale toward that point by one factor with the view direction held
fixed, so the point stays put on screen (true zoom-to-cursor). If the ray finds no ground (e.g. the
pointer is off-world), it falls back to the `spring_fraction` step toward the pivot.

**Closeness ladder** (closest → furthest limiter): `surface_floor_min_clear` (1.5) →
`min_distance` (2) → `cursor_min_gap` (1.5). Lower any to zoom tighter; the surface floor still
prevents sinking into terrain.

## Surface floor

Because terrain has no colliders, `Camera._enforce_camera_floor()` keeps the camera above the ground
every frame, in both zoom modes. It samples the surface height in a small neighbourhood around the
**look point** (so an edge behind the camera doesn't hold you back) and lifts the rig if the camera
would drop below it. The clearance is **ruggedness-scaled**: on flat ground it shrinks to
`surface_floor_min_clear` (you can zoom to ground level); near a wall/notch (large local height
delta) it ramps up to `surface_floor_margin` to keep the camera clear of rock. Terrain-only sampling
means placed flora/props never inflate the floor.

## Orbit & pan details

- **Orbit** is right-mouse drag, snap (un-smoothed) in this rig, clamped to the pitch range. A
  movement **dead zone** (`dead_zone_pixels`) means a quick right-click doesn't spin the view.
- **Dynamic orbit pivot** (`dynamic_pivot`): when orbit engages, the pivot re-anchors to the ground
  point straight ahead of the camera (recomputing spring length so the camera doesn't jump), so
  rotation spins around what you're looking at — not the rig origin. Skips if that point is outside
  the zoom range (would force a jump).
- **Pan speed tracks camera height** (Stonehearth `speed = position.y`): high overview sweeps fast,
  low/zoomed-in nudges finely, referenced to `pan_reference_height`. Fast by default; Shift slows.
- **Grab-the-ground drag** (middle-mouse) shifts the rig each frame so the world point grabbed on
  press stays locked under the cursor, tracking 1:1.

## Tool input contract (mining, and future tools)

Right-mouse and the wheel are shared with tools; the resolved contract (see `MiningDesignationController`):

- **Tool cancel is ESC-only.** Right-mouse is reserved for camera orbit (Stonehearth model: RMB =
  orbit, ESC = cancel mode). Tools must **not** consume RMB.
- **An active tool may claim the wheel.** The camera exposes `Camera.set_zoom_suppressed(bool)`; a
  tool calls it `true` on activate and `false` on deactivate. While suppressed the camera ignores the
  wheel (e.g. the mining brush resize wins); orbit and pan still work.
- Middle-mouse (grab-pan) is camera-only — tools should avoid it.

## Horizontal Layer Slicing

A defining feature: the player can slice the world horizontally to see underground.

- The slice plane hides all geometry above a chosen Y — the slice-aware block-face overview: the
  whole map stays present at any depth, cut floors show authored strata only (slice-concealment rule,
  `24_world_rendering.md`).
- Driven by `WorldRenderer.slice_y`; the Slice tool (`SliceController`, dock palette + `\` `]` `[`
  `Ctrl+]` `Ctrl+[` hotkeys, doc 11 Phase 2) steps it. `SliceController.slice_changed(new_slice_y)`
  fires on every move (`slice_y = 127` = off).
- **Placed flora obey the slice:** `SurfaceFloraSpawner` connects to `slice_changed` and hides trees
  whose base is above the cut (coarse per-instance toggle; doc 11 Phase 5). The same hook will serve
  furniture, items, and dwarves.
- **AUTO mode** (slice follows the camera): **dormant by decision** — manual control proved right
  (doc 10 §2.3, doc 11 Phase 2.6). `Camera.slice_y_changed` still emits but nothing connects to it;
  revisit only behind a settings toggle.

## Slice Visual Treatment

When a slice is active, the topmost visible layer should have a subtle highlight or edge fade
(`slice_fade_bands`) so the cut reads clearly. See `24_world_rendering.md`.

## Known limitations

- **Props see-through at extreme close-up:** flora/props have no collision, so at the closest zoom
  the camera passes through a tree canopy (cosmetic).
- **Coarse flora slice-culling:** a tree straddling the cut shows whole (canopy can poke above the
  plane). Accepted as-is; a per-prop clip-plane shader is the optional clean follow-up (doc 11
  Phase 5).

## Implementation Notes

- All tuning values live in `data/camera/camera_settings.json`.
- The camera script is `Camera.gd`, attached to the `CameraRig` root.
- Prefer `@export` for child-node references and signals for cross-node wiring (see
  `13_architecture.md`); the spawner↔slice link uses a `NodePath` export + the `slice_changed` signal.
- `BLOCK_SIZE` is 1 m; slice math uses it to convert camera Y to a block layer.

*Prev: [20_player_interface](.) | Next: [22_mouse_input.md](22_mouse_input.md)*
