# 21 — Camera

**Underground inspection (2026-10-17, 210):** adds
Full/Flat X-ray beside the slice tower (doc 23, "Underground X-ray"; its rendering is in
doc 24). The plane and ±1/±4 controls remain
available. Pin a lower level, then raise the plane for projected room/stair
references. Working tools restore normal terrain and picking automatically;
closing them resumes inspection. The original camera mask and environment
restore on exit. RTS movement and saved slice state are unchanged.

## Overview

The camera is a top-down god-view with **no direct character control**. All navigation is panning,
rotating, and zooming the camera rig. The player never embodies a single unit.

Feel is modeled on Stonehearth's `player_camera_controller.lua` (cursor-targeted zoom, height-scaled
pan, orbit-around-what-you-look-at), built in the 2026-06-07 camera rework and consolidated here as
the permanent reference. All tuning values live in `data/camera/camera_settings.json` (the source of
truth) and are hot-editable without touching GDScript. Logic is in `Camera.gd`, attached to the
`CameraRig` root.

Keyboard pan and edge scrolling pause while a LineEdit or TextEdit has focus,
so typing in the Colony roster search or moving its caret cannot move the world.
Normal camera movement resumes when text entry loses focus.

The loading screen also suspends keyboard/edge pan and drag polling while its
transient WorldClock hold is active. Camera settling, floor enforcement and slice
initialization continue so the final frame is ready before reveal (206).

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

## World sound perspective (updated 2026-10-13)

The camera publishes the centre-screen terrain hit and actual camera-to-hit distance
through `get_work_audio_context()`. A shared slice-aware voxel ray follows live
mined terrain and standing water and is cached once per process frame for work,
fire, water and ambience. Water uses its fractional surface level; listening
must not sink to the hidden lake bed (doc 170), where a terrain-only ray once made a
shore view sound enclosed.
Missing terrain uses the orbit pivot; detached cameras return no context. This keeps
room sounds near the viewed floor when cursor zoom or the terrain-floor guard lifts
the orbit pivot above it: listening at the pivot once left a sliced bedroom's
torches out of hearing range (doc 169).

Nearby chopping and mining are strongest around the looked-at X/Z area,
fade smoothly between 6 and 65 blocks from it, and become quieter when zooming
out beyond 24 units. Camera altitude alone does not suppress nearby work.
Native positional playback supplies restrained left/right panning. Active sound
tails also update while panning; distant hits are discarded rather than queued.
Both work families share the same attenuation and voice budget. Tuning lives in
`data/audio/work_feedback.json`; camera controls are unchanged. 

## Controls

| Input | Action |
|---|---|
| WASD / arrows | Pan (screen-relative, rotated by orbit) |
| Shift (held) | Precision/slow modifier while panning |
| Middle-mouse drag | Grab-the-ground pan — the grabbed point stays locked under the cursor |
| Right-mouse drag | Orbit (yaw + pitch); engages after a small dead zone |
| Mouse wheel | Zoom toward the point under the cursor |
| Screen edge | Optional edge-scroll (off by default) |

While dragging, a glyph cursor shows the mode (✋ grab-pan, 🗘 orbit) and the OS cursor hides. The glyphs come from the symbol font shipped with the game, in light ink with a dark outline (doc 23, "Type").

### Dwarf inspection: Locate and Follow (2026-10-05)

The dwarf inspector can center the camera on a dwarf or follow their position,
preserving zoom, pitch and orbit. This changes only the camera, never the dwarf's
orders. Keyboard/edge pan, middle-mouse pan, orbit past its dead zone, and world
zoom return control to the player. UI-consumed wheel events retain follow.
Closing or clearing selection, switching objects, slice concealment and actor
removal also end follow. Following is transient and is cleared on camera restore;
the existing saved camera framing is unchanged.

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

**Frame pacing (2026-10-22).** With vsync, a frame that misses a refresh stays on
screen for one refresh or two, unpredictably, and panning judders even at a high
average frame rate. `Engine.max_fps` is therefore capped at an even share of the
display's refresh rate, so every frame is held equally long.
- **The cap is a video setting** (2026-10-24): Frame rate in the game menu's Settings,
  owned by `VideoSettings` (doc 23, doc 13). Its choices are the even shares of the
  refresh rate down to 24 fps (120, 60, 40 and 30 fps at 120 Hz).
- **The default**, 75 in `data/video/video_settings.json`, gives the largest share not
  above it: 120 Hz → 60, 144 Hz → 72, 60 Hz → 60.
- **Rounded choices.** The rates on offer are rounded (165 Hz offers 41 fps for 41.25), so
  the cap adds half a frame to the chosen rate before finding its share, and each choice
  caps at itself.
- **The rig starts the cap** in `_ready` (`VideoSettings.pace_frames()`), so tools that
  never start the camera stay uncapped.

Measured on the owner's 7680×2160 120 Hz display: uncapped, 94% of running frames
missed a 120 Hz refresh; capped at 60, most frames land on the 16.7 ms beat. The
camera benchmark (`tools/performance/Run.ps1`) stays uncapped unless run with
`-Paced`.

Stutter while panning is frame time, not camera cost: the controller measured about
0.02 ms a frame (doc 178), and panning only makes uneven frames visible. Look for the
world update or render stall behind a long frame (doc 13, "Measuring performance").

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

Every notch is geometric in both modes; the old fixed-step fallback and its `zoom_speed`
key were removed in doc 258.

### `input_mappings` / `cursors`
`rotate_action` = right-mouse, `drag_action` = middle-mouse, move keys = WASD + arrows, zoom = wheel.
`cursors`: `enabled` true, `orbit` 🗘, `drag` ✋, `size` 28, `hide_system_cursor` true.

## Zoom (cursor-targeted)

Each wheel notch moves a **fixed fraction** (`zoom_step_fraction`) of the current distance — geometric
zoom, constant perceived speed at any distance, so one notch can never collapse the whole range.

In `cursor_target` mode the zoom homes toward the **ground point under the mouse**: a ray is marched
against the camera's ground (`ObjectPicking.surface_hit` over the height field clamped to the slice;
see "The camera's ground") — the rule the overview draws by, so it works map-wide even on columns
never materialised in `WorldData`, and under a deep slice it heads for the cut floor. The
rig pivot **and** spring length scale toward that point by one factor with the view direction held
fixed, so the point stays put on screen (true zoom-to-cursor). If the ray finds no ground (e.g. the
pointer is off-world), it falls back to the `spring_fraction` step toward the pivot.

**Closeness ladder** (closest → furthest limiter): `surface_floor_min_clear` (1.5) →
`min_distance` (2) → `cursor_min_gap` (1.5). Lower any to zoom tighter; the surface floor still
prevents sinking into terrain.

## Surface floor

Because terrain has no colliders, `Camera._enforce_camera_floor()` keeps the camera above the ground
every frame, in both zoom modes. It samples the camera's ground (below) in a small neighbourhood
around the **look point** (so an edge behind the camera doesn't hold you back) and lifts the rig if
the camera would drop below it. The clearance is **ruggedness-scaled**: on flat ground it shrinks to
`surface_floor_min_clear` (you can zoom to ground level); near a wall/notch (large local height
delta) it ramps up to `surface_floor_margin` to keep the camera clear of rock. Terrain-only sampling
means placed flora/props never inflate the floor.

## The camera's ground (2026-10-26)

Zoom, the middle-drag grab, the orbit pivot and the surface floor all use one ground,
`Camera._ground`. For each column it is the terrain height field
(`WorldGenerator.get_visible_surface_y`, water surfaces included) clamped to the slice plane,
then stepped down past mined cells and caves the colony has found: `WorldData.visible_top_y`,
the rule the overview draws by (doc 12). The plane and the found caves come from the
WorldRenderer (group `terrain_overview_renderer`); without one nothing is sliced.

- **Under a deep slice the cut floor is the ground.** The camera comes down to a cut floor under
  a mountain as closely as to open ground. The hidden top above the plane no longer holds the
  camera up, draws the zoom, or catches the grab and the orbit pivot.
- **A room mined under the cut, or a found cave the slice opens,** is open to the camera, so it
  can come down into it. The ruggedness margin applies at its edges as at any wall. Water
  standing in it is its ground, as a lake's surface is (`WaterManager.has_standing_water`).
- **A cave not yet found is rock** (Hard Rule 11; doc 24, "Slice concealment rule"). The ground
  never steps into it, so the camera cannot give it away by sinking below the cut.
- **A mining plan does not lower the ground.** The overview draws a plan's cut, but the rock is
  still there, so over a plan the camera keeps above the rock until it is mined.
- **Raising the slice lifts the camera** at once when the terrain it shows again stands above
  the camera.
- `CameraDeepSliceTest` checks zoom, drag and orbit with real input, and the floor in a mined
  room, dry and flooded, and in a hidden and a found cave.

## Orbit & pan details

- **Orbit** is right-mouse drag, snap (un-smoothed) in this rig, clamped to the pitch range. A
  movement **dead zone** (`dead_zone_pixels`) means a quick right-click doesn't spin the view.
- **Dynamic orbit pivot** (`dynamic_pivot`): when orbit engages, the pivot re-anchors to the ground
  point (the camera's ground, so the cut floor under a slice) straight ahead of the camera
  (recomputing spring length so the camera doesn't jump), so
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
- **Plain wheel always zooms over the world**, including with Mine blocks selected
  or during a designation drag. **Shift + wheel** adjusts mining width and
  **Alt + wheel** adjusts mining depth, without also zooming. The camera checks
  these modifiers itself so scene input order cannot cause both actions.
- Wheel input over UI panels is consumed by the GUI before reaching either tool
  or camera; scrolling a panel must not resize the brush or zoom the world.
- Middle-mouse (grab-pan) is camera-only — tools should avoid it.

**2026-10-06 fix:** removed the old tool-wide zoom-suppression flag/API. Mining
was setting it throughout activation even though brush resizing already required
Shift/Alt, which unintentionally blocked plain-wheel zoom. `OrdersShelfTest`
reproduces the original failure and verifies both zoom directions, modifier
resizing, UI isolation, zoom during a drag and after exit, in both node input orders.

## Horizontal Layer Slicing

A defining feature: the player can slice the world horizontally to see underground.

- The slice plane hides all geometry above a chosen Y — the slice-aware block-face overview: the
  whole map stays present at any depth, cut floors show authored strata only (slice-concealment rule,
  `24_world_rendering.md`).
- Driven by `WorldRenderer.slice_y`; the Slice tool (`SliceController`, dock palette + `\` `]` `[`
  `Ctrl+]` `Ctrl+[` hotkeys) steps it. `SliceController.slice_changed(new_slice_y)`
  fires on every move (`slice_y = 127` = off).
- **The camera follows the slice:** zoom, drag, orbit and the surface floor use the floor the
  slice shows (see "The camera's ground").
- **Placed flora obey the slice:** `SurfaceFloraSpawner` connects to `slice_changed` and hides trees
  whose base is above the cut (coarse per-instance toggle). Dwarves (`DwarfDirector`), loose items
  (`ItemDropManager`), furniture and room overlays use the same hook.
- **AUTO mode** (slice follows the camera): **dormant by decision** — manual control proved right.
  `Camera.slice_y_changed` still emits but nothing connects to it; revisit only behind a
  settings toggle.

## Slice Visual Treatment

When a slice is active, the topmost visible layer should have a subtle highlight or edge fade
(`slice_fade_bands`) so the cut reads clearly. See `24_world_rendering.md`.

## Known limitations

- **Props see-through at extreme close-up:** flora/props have no collision, so at the closest zoom
  the camera passes through a tree canopy (cosmetic).
- **Coarse flora slice-culling:** a tree straddling the cut shows whole (canopy can poke above the
  plane). Accepted as-is; a per-prop clip-plane shader is the optional clean follow-up.
- **Entity slice visibility is one height test.** An entity hides when its base is above
  `slice_y`: trees use the ground block they stand on, dwarves and loose items their feet
  height, furniture its placed origin (wall pieces their top cell). These read raw `slice_y`
  from `slice_changed`, not the VisibleVolume contract (`24_world_rendering.md`), so cut
  cavities do not cull them. X-ray filters them separately, by camera layer, in
  `XrayController`.
  A dwarf also reruns its test whenever its transform changes (`DwarfAgent` turns on
  transform notifications when it enters the tree), before the frame draws, and sets
  `visible` only when the answer changes. Walking stairs, climbing a ladder or a position
  restored while paused therefore shows or hides it at the plane without a slice change:
  a worker that walked down into the sliced room once stayed hidden there (doc 217).

## Implementation Notes

- All tuning values live in `data/camera/camera_settings.json`.
- The camera script is `Camera.gd`, attached to the `CameraRig` root.
- Prefer `@export` for child-node references and signals for cross-node wiring (see
  `13_architecture.md`); the spawner↔slice link uses a `NodePath` export + the `slice_changed` signal.
- `BLOCK_SIZE` is 1 m; slice math uses it to convert camera Y to a block layer.

*Prev: [20_player_interface](.) | Next: [22_mouse_input.md](22_mouse_input.md)*
