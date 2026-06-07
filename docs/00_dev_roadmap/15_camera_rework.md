# 15 - Camera Rework (Stonehearth-parity zoom, pan & orbit)

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = decided / ready to build</span> |
> <span style="color:#d29922;">Yellow = decision needed or tune-in-engine</span> |
> <span style="color:#f85149;">Red = explicitly out of scope for this pass</span>

Status: **Phases 1–3 shipped & verified in-engine 2026-06-07.** Zoom, pan, orbit, the surface
floor, cursor-targeted zoom, the emoji cursor and the §8a close-zoom fix are all live and confirmed.
Only the **optional dynamic orbit pivot** remains (deferred — see §6/§8). Created 2026-06-07.
Triggered by the camera feeling wrong in testing — chiefly that **a single mouse-wheel notch jumped
from a normal overview straight through the surface**. This doc audits the rig against Stonehearth's
real camera source (mounted at `P:\stonehearth`, verified — not inferred) and records the rework.
It supersedes the original tuning in `data/camera/camera_settings.json` and the `21_camera.md`
"Navigation Parameters" table.

Touch before working on `Camera.gd`, `camera_settings.json`, or `21_camera.md`.

---

## 0. Current state (what shipped) — read this first

The rework is implemented in `scripts/systems/Camera.gd` (spring-arm rig kept) and tuned entirely in
`data/camera/camera_settings.json`. Behaviour now:

- **Zoom** — geometric per-notch step (`zoom_step_fraction`), **cursor-targeted**: scrolls toward the
  ground point under the mouse (`mode: cursor_target`), which it finds by marching the cursor ray
  against the terrain **height field** (`get_visible_surface_y`) so it works map-wide even on
  un-streamed overview columns. `spring_fraction` is the no-hit fallback.
- **Surface floor** — `_enforce_camera_floor` keeps the camera above the terrain everywhere (no
  physics colliders exist). Margin is **ruggedness-scaled**: flat ground → `surface_floor_min_clear`
  (close to the ground); a wall/notch within 1 block → up to `surface_floor_margin`. Sampled around
  the **look point** (pivot), so an edge behind the camera doesn't hold you back.
- **Pan** — speed tracks camera **height** (`pan_reference_height`); **fast by default**, Shift is a
  precision/slow modifier (`shift_multiplier` < 1). Plus **middle-mouse grab-the-ground** drag.
- **Orbit** — **right-mouse** drag with a movement **dead zone** (`dead_zone_pixels`); rotation is
  snap (un-smoothed) in our rig.
- **Cursor feedback** — ✋ while grab-dragging, 🔄 while orbiting (CanvasLayer Label overlay).

### Final tunables (`camera_settings.json`)

| Block | Key | Value | Meaning |
|---|---|---|---|
| camera_settings | `surface_floor_margin` | 8 | wall clearance in rugged terrain |
| camera_settings | `surface_floor_min_clear` | 1.5 | clearance on flat ground (close-up limit) |
| camera_settings | `surface_floor_ruggedness` | 12 | local height delta for full margin |
| movement | `move_speed` | 126 | base pan speed (fast) at default framing |
| movement | `shift_multiplier` | 0.286 | Shift = precision/slow |
| movement | `pan_reference_height` | 135 | camera Y where move_speed reads face value |
| rotation | `dead_zone_pixels` | 6 | mouse motion before orbit engages |
| zoom | `zoom_step_fraction` | 0.18 | fraction of distance per notch |
| zoom | `cursor_min_gap` | 1.5 | nearest the camera sits to the cursor point |
| zoom | `min_distance` / `max_distance` | 2 / 180 | spring length range |
| zoom | `mode` | cursor_target | `cursor_target` \| `spring_fraction` |
| input_mappings | `rotate_action` / `drag_action` | RMB / MMB | orbit / grab-pan buttons |
| cursors | `orbit` / `drag` | 🔄 / ✋ | overlay glyphs |

> Closeness ladder (closest→furthest limiter): `surface_floor_min_clear` → `min_distance` →
> `cursor_min_gap`. Lower any to zoom tighter; the floor still prevents sinking into terrain.

### Known follow-ups

- **Dynamic orbit pivot** — orbit still rotates around the rig origin; cursor-zoom moves the pivot to
  the point of interest so it's usually fine. Deferred (§6).
- **`_axis_t_max` is dead code** — orphaned when the zoom raycast moved to the height-field march;
  safe to delete.
- At close range, props (trees) have no collision, so zooming into a canopy sees through it
  (cosmetic).

---

## 1. The complaint, stated precisely

From the default start position (high overview, pitch ≈ −50°, looking down at the lowland
plateaus), **one wheel-up lands the camera below the surface.** Zoom has effectively two useful
stops — "far" and "underground" — with nothing in between. Panning and orbit are secondary but
also feel off: pan speed doesn't track height the way Stonehearth's does, and orbit pivots around
the rig origin rather than what you're looking at.

The root cause is arithmetic, not engine limits. See §4.

---

## 2. Stonehearth's camera model (verified from source)

Files: `services/client/camera/player_camera_controller.lua`,
`services/client/camera/camera_service.lua`. Constants inline in those files (Stonehearth reads a
few from `radiant.util.get_config`, defaults shown).

### 2.1 Rig shape — *there is no rig*

Stonehearth does **not** use a spring-arm / orbit-pivot hierarchy. The camera is a **free point in
world space** (`self.position`, a `Point3`) plus a **look direction** (`self.lookat`, a normalized
vector). Every frame:

```lua
-- player_camera_controller.lua : update(frame_time)
self.position = self.position + scaled_continuous_delta + self._impulse_delta
local lerp_pos = camera:get_position():lerp(self.position, smoothness * frame_time)  -- smoothness = 0.0175
local rot = Quat(); rot:look_at(Point3(0,0,0), self.lookat)
return lerp_pos, rot
```

So *position is authoritative and free*; orientation is derived from a look vector. There is no
"spring length." Distance-to-subject is an emergent property of where the point sits, not a tracked
scalar. **This is the single biggest structural difference from Deepdraft** and the reason their
zoom behaves and ours doesn't.

Initial state: `position = (0, 120, 190)`, `lookat = (0, −125, −340)` normalized → a steep-ish
downward gaze. Home/reset (`reset_camera_to_town_center`) puts the camera at
`(target.x, target.y + 30, target.z + 70)` and looks at the town banner — i.e. **30 up, 70 back,
aimed at the centre of town.**

### 2.2 Zoom — cursor-targeted, distance-proportional (the important one)

`_calculate_zoom(e)`:

1. **Raycast from the mouse cursor** into the scene: `cast_screen_ray(e.x, e.y)`. If it hits
   nothing, **do nothing** (no zoom in empty sky). The hit point is `target`.
2. `distance_to_target = position:distance_to(target)`.
3. Hard clamp by **distance to that point**: refuse to zoom in past `_min_zoom = 15`, refuse to
   zoom out past `_max_zoom = 300`.
4. Pick a **factor by distance band**:
   - `< 100` units → `0.20`
   - `< 500` units → `0.30`
   - else → `0.40`
5. `input_scale = |wheel|` (or `0.2` for the key-repeat path).
6. `distance_to_cover = distance_to_target * factor * input_scale`, then clamped so the move never
   crosses `_min_zoom` / `_max_zoom`.
7. Move the camera **along the line between the camera and the cursor's world point**
   (`dir = position − target`, normalized, scaled by `distance_to_cover`, sign flipped for zoom-in).
   Applied as `self._impulse_delta`.

Two consequences that matter:

- **The step is a fraction (20–40%) of how far the cursor target is** — never a fixed unit count
  and never referenced to the *minimum*. From 85 units out, one notch covers ~17–34 units, so a
  full far→near traverse is several notches with a smooth geometric feel.
- **You zoom toward the thing under the cursor**, and the move *stops 15 units short of that
  surface point*. You physically cannot punch through the surface by scrolling, because the wall
  you're aiming at is the clamp.

### 2.3 Pan — speed equals camera height

`_calculate_keyboard_pan()`:

```lua
local speed = stonehearth.camera:get_position().y  -- "surprisingly this feels good with no modifiers!"
```

Pan speed **is the camera's Y**. High overview → fast sweep; low/zoomed-in → fine nudges, with no
separate zoom-scale constant. Movement is along the camera's flattened `forward` (y zeroed) and
`left` vectors, plus a world-up component for vertical move keys. The continuous delta is scaled by
`frame_time/1000`.

`_drag` (middle-mouse / `cam:drag`): ray-cast the cursor to the terrain on press, then on each move
re-intersect the **horizontal plane through the grab point** and translate so the grabbed world
point stays under the cursor — true "grab the ground and drag it." Bounded to within 900 units of
the map.

### 2.4 Orbit — around what you're looking at, with a dead zone

- Bound to **right mouse button** (`MOUSE_BUTTON_2`) drag, or keyboard orbit keys.
- **Dead zone:** the mouse must accumulate `dead_zone_size` of motion before orbit engages
  (`_calculate_mouse_dead_zone`) — a click with a tiny wobble won't spin the world.
- **Pivot is dynamic:** `_get_orbit_target()` ray-casts forward from the camera and orbits around
  the hit point (or a synthesized point ~20 units above the `y=0` plane at the cursor). You orbit
  around *the subject*, not a fixed origin.
- `_orbit()` rotates `position − target` around world-Y (`y_deg`) and the camera's `left` axis
  (`x_deg`), clamping the vertical angle via `acos(origin_vec.y)` to **`MIN_X_ANGLE = 5°` …
  `MAX_X_ANGLE = 80°` above horizon.** Orbit is applied **snap, no smoothing** ("just go there!").
- Sensitivity: `mouse_orbit_sensitivity = 0.26`, `keyboard_orbit_sensitivity = 0.18`.

### 2.5 Smoothing

One global position lerp toward the free target: `lerp(target, 0.0175 * frame_time)`. Orbit bypasses
it (snaps). There is a `min_height = 10` floor constant in the controller.

### 2.6 Constant summary (Stonehearth)

| Constant | Value | Meaning |
|---|---|---|
| `_min_zoom` | 15 | nearest the camera may sit to the cursor's surface point |
| `_max_zoom` | 300 | farthest |
| zoom factor | 0.20 / 0.30 / 0.40 | fraction of distance per notch, by `<100 / <500 / else` band |
| `MIN_X_ANGLE` / `MAX_X_ANGLE` | 5° / 80° | pitch above horizon |
| `mouse_orbit_sensitivity` | 0.26 | deg per mouse pixel (×−1) |
| `keyboard_orbit_sensitivity` | 0.18 | deg per frame-ms |
| pan speed | `position.y` | height-proportional, no constant |
| `smoothness` | 0.0175 | position lerp rate × frame_time |
| `min_height` | 10 | controller height floor |
| reset offset | +30 up, +70 back | home-to-town framing |

---

## 3. Deepdraft's current model

File: `scripts/systems/Camera.gd`, data: `data/camera/camera_settings.json`.

### 3.1 Rig shape — a spring-arm hierarchy

```
CameraRig (Node3D)         ← pans in XZ only (world_dir.y is forced 0)
  └─ CameraArm (Node3D)    ← Y-axis orbit
       └─ SpringArm3D      ← pitch (X rot) + spring_length = zoom, collides with Layer 1
            └─ Camera3D
```

The rig **pivot moves in the XZ plane at a fixed Y** (`default_position.y = 70`; pan never changes
Y). Zoom = `SpringArm3D.spring_length`. Orbit = `CameraArm.rotation.y` around the rig pivot. Pitch =
`SpringArm3D.rotation.x`. The camera always points at the rig pivot from `spring_length` away.

This is a clean, conventional RTS rig — but it is structurally *opposite* to Stonehearth on the two
axes the complaint is about: **zoom collapses toward a fixed ground pivot, not the cursor**, and
**the pivot's height is constant**, so framing depends entirely on `spring_length`.

### 3.2 Current tuning (`camera_settings.json`)

| Field | Value |
|---|---|
| `fov` | 45 |
| `default_position` | (512, **70**, 512) |
| `default_rotation.x` (pitch) | −50° |
| `move_speed` / `shift_multiplier` / `smoothing` | 36 / 3.5 / 0.22 |
| `rotation_speed` | 0.6, pitch clamp **−80° … −5°** |
| `zoom_speed` | **8.0** |
| `min_distance` / `max_distance` / `default_distance` | **6 / 180 / 85** |
| `proportional` | true |
| `zoom smoothing` | 0.15 |

Pan already scales with zoom (`speed *= spring_length / zoom_default`), which is the right idea but
referenced to the default distance rather than to height.

> Note: `21_camera.md`'s "Navigation Parameters" table is stale (it lists zoom 50–340, default 110,
> pitch −5…−80 — partly Stonehearth's numbers, partly old). Fix it as part of this rework so the
> doc matches the JSON.

---

## 4. Root cause of the "one notch → underground" jump

The proportional zoom step in `Camera._handle_orbit_and_zoom`:

```gdscript
step = _zoom_speed * (_target_zoom / _zoom_min)      # = 8.0 * (85 / 6) ≈ 113.3
```

With `zoom_speed = 8`, `zoom_min = 6`, at the default distance `85`, **one wheel notch is ~113
units** — larger than the entire 6→180 range is wide on the near side. `85 − 113` clamps straight to
`min_distance = 6`. So a single wheel-up teleports the spring from 85 to 6 — fully zoomed in. The
pivot sits at a fixed `y = 70` over lowland terrain whose surface is ~Y12–43, so slamming the spring
to its minimum drops the camera onto/through the surface lip in one motion. **Exactly the reported
behaviour.**

The bug is that the proportional multiplier divides by `_zoom_min` (a small constant) instead of
being a modest fraction of the *current* distance. Stonehearth's equivalent multiplier is `0.2–0.4`;
ours is effectively `_target_zoom / _zoom_min ≈ 14×` at default. We are ~35–70× too aggressive per
notch.

A second, subtler problem: because Deepdraft zooms toward the **fixed ground pivot** rather than the
**cursor's surface point**, even a correctly-sized step has no surface to clamp against — nothing
stops the camera descending below terrain except the spring-arm's own collision, which is aimed at
the pivot, not at the ground under the mouse.

---

## 5. Side-by-side

| Aspect | Stonehearth | Deepdraft (now) | Gap |
|---|---|---|---|
| Camera representation | Free `position` + `lookat` | Spring-arm rig, fixed-Y pivot | Structural |
| Zoom step size | 20–40% of distance-to-cursor | `8 × dist/6` ≈ 14× distance-ish | **Bug — far too large** |
| Zoom direction | Toward cursor's world point | Toward fixed ground pivot | Behavioural |
| Zoom floor | Stops 15 u from the surface you aim at | Spring clamps at 6 u from pivot | No surface-relative clamp |
| Zoom feel | Geometric, several notches across range | Two stops (far / underground) | **Primary complaint** |
| Pan speed | = camera height (`position.y`) | `36 × spring_length/85` | Close idea, wrong reference |
| Pan drag | Grab-the-ground (cursor-locked plane drag) | None (keys/edge only) | Missing feature |
| Orbit button | RMB (MOUSE_BUTTON_2) | MMB | Mapping choice |
| Orbit pivot | Raycast subject under view | Fixed rig origin | Behavioural |
| Orbit dead zone | Yes (`dead_zone_size`) | No | Missing |
| Pitch clamp | 5–80° above horizon | −5…−80° (same range, neg. convention) | Equivalent |
| Orbit smoothing | Snap (no lerp) | Smoothed | Feel choice |
| Position smoothing | `lerp(0.0175 × frame_time)` | `1 − exp(−smooth×60×dt)` | Both frame-rate-safe |

---

## 6. Proposed rework

Two routes. They are not mutually exclusive — Route A is a subset of Route B and should ship first
regardless.

### Route A — <span style="color:#3fb950;">Fix the rig we have (do this now)</span>

Keep the spring-arm hierarchy; correct the math and tuning so zoom is graduated and surface-safe.

1. **Replace the proportional step formula** so a notch is a *fraction of the current distance*,
   matching Stonehearth's geometric feel:

   ```gdscript
   # was: step = _zoom_speed * (_target_zoom / _zoom_min)
   var factor := _zoom_step_fraction        # new JSON field, default ~0.18 (one notch ≈ 18%)
   _target_zoom = clampf(_target_zoom * (1.0 - factor if zoom_in else 1.0 + factor),
                         _zoom_min, _zoom_max)
   ```

   Multiplicative zoom gives constant *perceived* speed at every distance and is impossible to make
   teleport in one notch. From 85 at 18%: 85 → 70 → 57 → 47 … ~8 notches to `min`. Tune `factor`
   (0.12–0.25) in-engine.

2. **Retire `zoom_speed` as a unit count** (or keep only for a key-repeat path) and add
   `zoom_step_fraction`. Document both in the JSON `__comment`.

3. **Raise the effective zoom floor relative to the surface, not the pivot.** Cheapest version:
   keep the pivot at fixed Y but raise `min_distance` so the closest framing still clears terrain
   (tune; ~12–20). Better version is Route B's cursor target.

4. **Re-tune pan toward height-proportionality:** reference pan speed to the camera's *world Y*
   (or the spring length) rather than the default distance, mirroring `speed = position.y`. Keep
   the shift multiplier as an explicit "fast" override.

5. **Fix `21_camera.md`** Navigation Parameters to match the new JSON; mark the old table superseded.

Route A alone resolves the reported bug. Estimated change: ~30 lines in `Camera.gd`, a few JSON
fields, one doc table.

### Route B — <span style="color:#d29922;">Adopt Stonehearth's cursor-targeted zoom (decision needed)</span>

For true parity ("zoom to where I'm pointing, never through the ground"), move zoom from
"shrink spring length toward pivot" to "move toward the cursor's surface point":

1. On wheel, raycast from the mouse through the viewport to the terrain (reuse the mining/selection
   raycast in `22_mouse_input.md` / `MiningDesignationController`). No hit → ignore the notch.
2. Move the **rig** along the camera→hit line by `dist_to_hit × factor`, clamped to stop `min_zoom`
   short of the hit. This makes the framing follow the cursor and gives the surface itself as the
   zoom clamp — structurally why Stonehearth can't punch through.
3. Because our rig pans at fixed Y, this needs the **pivot Y to become free** (let zoom adjust rig
   Y, or collapse the rig toward a free camera position as Stonehearth does). This is the real work
   and the open decision: *do we keep the @export spring-arm rig and drive its position from the
   raycast, or refactor to a free-position camera?*
   - **Keep-rig variant:** least disruptive; `SpringArm3D` stays for terrain collision; we drive
     rig position + spring length from the raycast result. Recommended.
   - **Free-camera variant:** closest to Stonehearth, but discards the rig and the collision spring;
     more rewrite, more risk. <span style="color:#f85149;">Out of scope unless the keep-rig variant
     proves insufficient.</span>

4. Optional parity extras (each independently toggleable): grab-the-ground drag pan (§2.3), dynamic
   orbit pivot (§2.4), orbit dead zone, snap-during-orbit.

> **Open questions for the user before Route B:**
> 1. Keep the spring-arm rig (drive it from the raycast) or refactor to a free-position camera?
> 2. Move orbit to RMB (Stonehearth) or keep MMB? Does RMB conflict with planned context actions?
> 3. Do we want grab-the-ground drag pan, or are keyboard + edge-scroll enough?
> 4. Orbit dead zone + snap (Stonehearth feel) vs. our current smoothed orbit — which do you prefer?

---

## 7. Data schema (proposed `camera_settings.json` zoom block)

```jsonc
"zoom": {
  "mode": "spring_fraction",      // "spring_fraction" (Route A) | "cursor_target" (Route B)
  "zoom_step_fraction": 0.18,     // fraction of current distance per notch (Route A)
  "min_distance": 14,             // raised so closest framing clears terrain
  "max_distance": 180,
  "default_distance": 85,
  "cursor_min_gap": 15,           // Route B: stop this far short of the cursor surface point
  "smoothing": 0.15,
  "zoom_speed": 8.0               // legacy / key-repeat fallback only
}
```

All feel lives in JSON per the Registry/data rules — no magic numbers back in `Camera.gd`.

---

## 8. Phasing

1. **Route A** — ✅ shipped 2026-06-07. Fraction-based zoom (`zoom_step_fraction`) + raised floor
   (min_distance 6→14) + pan-by-height (`pan_reference_height`) + Shift-as-precision (fast default,
   `shift_multiplier` 0.286) + doc fix. Resolves the bug. Confirmed in-engine: zoom now takes ~10
   notches to the ground and pan/shift feel right.
2. **Route B keep-rig** — ✅ cursor-zoom shipped & verified 2026-06-07.
   `mode: cursor_target` in `Camera._zoom_cursor`: a DDA voxel ray (`_zoom_target_point`) finds the
   surface point under the mouse; the rig pivot **and** spring length scale toward it by one factor
   `s`, holding view direction fixed so the point stays put on screen, clamped to stop
   `cursor_min_gap` (14) short of the surface. Pivot Y is now free (set by zoom). `spring_fraction`
   remains as a fallback/no-hit path. Verify: zoom homes to the cursor and clamps at the surface;
   orbit after zoom pivots near the zoomed-in point.
   - **Surface floor (closes Phase 2, 2026-06-07).** The terrain has **no physics colliders**
     (picking is a voxel data-ray, not physics), so the SpringArm cannot push the camera out of
     rock and `cursor_min_gap` only clears the *targeted* point — deep zoom in rugged terrain still
     clipped between neighbouring columns. `Camera._enforce_camera_floor()` now runs every frame in
     both modes: it samples `WorldGenerator.get_visible_surface_y` over a 3×3 neighbourhood under
     the camera and lifts the whole rig so the camera stays `surface_floor_margin` (8) above the
     surface everywhere. Verify: deepest zoom into a mountain notch no longer goes behind blocks.
3. **Parity extras** — ✅ shipped & verified 2026-06-07, per §6 answers
   (full Stonehearth parity): **orbit moved to right-mouse** (`rotate_action`) with a **dead zone**
   (`dead_zone_pixels` 6) before rotation engages — orbit was already snap/un-smoothed in our rig;
   **grab-the-ground drag pan on middle-mouse** (`drag_action`, `Camera._start_drag`/`_handle_drag`)
   keeps the grabbed world point locked under the cursor. Still open: **dynamic orbit pivot**
   (raycast-forward target instead of the rig origin) — deferred; cursor-zoom already moves the
   pivot to the point of interest, so orbiting after a zoom pivots near it in practice.
   - **Cursor feedback (2026-06-07).** Like Stonehearth's cursor swap, an emoji cursor shows the
     active mode: **✋ while grab-dragging, 🔄 while orbiting** (only after the dead zone engages).
     Implemented as a CanvasLayer + Label overlay (`Camera._build_cursor_overlay` /
     `_update_cursor_overlay`) that follows the mouse and hides the OS cursor under it; the dock
     already proves emoji glyphs render. Data-driven in the `cursors` JSON block
     (`enabled`, `orbit`, `drag`, `size`, `hide_system_cursor`).
4. **Reconcile** `21_camera.md` — ✅ table updated as we went.

---

## 8a. Known issues / follow-ups

- **Surface floor over-restricts close zoom on open ground (logged 2026-06-07; ✅ fixed
  2026-06-07).** <span style="color:#3fb950;">Resolved with a **ruggedness-scaled margin**:
  `_enforce_camera_floor` now samples the local surface min/max (radius 2) and lerps the clearance
  from `surface_floor_min_clear` (1.5, flat ground → full ground-level zoom) up to
  `surface_floor_margin` (8, a wall/notch nearby → camera pushed clear), keyed to
  `surface_floor_ruggedness` (8-block delta = full margin). Paired with lowering `min_distance`
  14→4 and `cursor_min_gap` 14→3 so the spring/cursor knobs no longer cap closeness on flats.
  Flora doesn't inflate the floor (surface sample is terrain-only).</span>

  <span style="color:#8b949e;">Original report: after the Phase 2 surface floor shipped, you could
  no longer fully zoom in on lowland/foothill ground; the floor should only stop the camera passing
  *through or behind* terrain, not cap how close it gets on clear ground.</span>

- **Cursor zoom targeted the pivot height, not the ground (fixed 2026-06-07).** <span
  style="color:#3fb950;">The bigger reason close zoom failed: `_zoom_target_point` used a WorldData
  voxel DDA, but distant *overview* columns aren't streamed into WorldData, so the ray hit nothing
  and fell back to a plane at the pivot's Y (~70). Cursor zoom then homed toward a point floating in
  the air, bottoming out ~40 u above ground regardless of `min_distance`. Now it marches the ray
  against the terrain **height field** (`get_visible_surface_y`, the overview's own source), which
  works map-wide regardless of streaming and returns the real ground point. Also fixes the
  grab-pan grab point. `min_distance` lowered 4→2, `cursor_min_gap` 3→1.5 for close-up.</span>

  *Cause.* Two things cap closeness, both deliberately conservative:
  1. `surface_floor_margin` (8) holds the camera ≥ 8 units above the surface **everywhere**,
     including flat ground where there's nothing to clip.
  2. `cursor_min_gap` (14) stops cursor-zoom 14 units short of the targeted point.

  Additionally, the floor samples a **3×3 neighbourhood max**, so a nearby tree trunk column or a
  1-block rise can inflate the local "surface" and push the floor up even on otherwise flat ground.

  *Why it's hard.* The mountain-notch clip is a **lateral** problem (a wall beside the camera),
  but the current guard is a **vertical** height cap — so the only knob that fixes clipping also
  blocks legitimate close zoom on flats. They need to be separated.

  *Candidate fixes (pick later):*
  - Make the floor guard only the camera's **own column** (true "camera Y below the surface
    directly beneath it") so open ground allows a full descent; handle lateral walls separately
    (e.g. a near-plane push-out, or only lift when the camera column itself is solid).
  - Drop `surface_floor_margin` toward ~2–3 and `cursor_min_gap` toward ~3–4, and lean on a small
    `near_clip` so extreme close-ups don't z-clip — accept that rugged notches need a small margin.
  - Exclude flora/prop columns from the surface sample so trunks don't inflate the floor.
  - Scale the margin by local ruggedness: ~0 on flat shelves, full margin only where neighbouring
    columns differ a lot (a wall is present).

  Out of scope for the Phase 2 close; revisit before Phase 3 sign-off.

---

## 9. Verification

- **Zoom granularity:** from the default start, count notches far→near; must be ≥ ~6 and never
  cross the surface in one step (the original failure case).
- **Surface safety:** at every orbit angle and over lowland/foothill/peak, full zoom-in keeps the
  camera above terrain (Route B: clamps at the cursor surface).
- **Pan feel:** pan sweep at high overview vs. zoomed-in — fast vs. fine, no constant retuning.
- **Determinism N/A** (camera is presentation only; no save state, no worldgen interaction).
- **Regression:** slice hotkeys, mining designation raycast, and dock interaction still work with
  the new input handling. Orbit-button change (if adopted) must not collide with existing tools.
- **Screenshots:** fixed-seed before/after at the default position for review.

---

## 10. Out of scope

Follow-camera (Stonehearth's `follow_camera_controller` — locking onto a unit; revisit once dwarves
exist), `move_to_camera_controller` cinematic lerps, edge-scroll retuning beyond what Route A
touches, and any change to the slice system (`11_slice_xray_plan.md` owns that; the dormant
auto-slice in `21_camera.md` §Horizontal Layer Slicing stays dormant).

---

*Prev: [14_flora_distribution_plan.md](./14_flora_distribution_plan.md) · Related:
[21_camera.md](../20_player_interface/21_camera.md),
[10_slice_xray_stonehearth_reference.md](./10_slice_xray_stonehearth_reference.md)*
