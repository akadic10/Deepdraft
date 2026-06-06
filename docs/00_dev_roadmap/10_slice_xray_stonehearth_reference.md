# 10 - Slice & X-Ray: Stonehearth Reference (Verified Source Findings)

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = keep / verified</span> |
> <span style="color:#d29922;">Yellow = inferred (native C++ side, not directly readable)</span> |
> <span style="color:#f85149;">Red = do not copy into Deepdraft as-is</span>

Status: research record, written 2026-06-03. Every claim below was read from `P:\stonehearth`
source, not inferred from gameplay, except where marked yellow. This is the reference document
for `11_slice_xray_plan.md` (the Deepdraft implementation plan).

Primary sources:

- `P:\stonehearth\services\client\subterranean_view\subterranean_view_service.lua` — the whole feature
- `P:\stonehearth\ui\game\widgets\terrain_vision\terrain_vision.js` / `.html` — UI + mutual exclusion
- `P:\stonehearth\services\server\mining\mining_service.lua` — interior-region bookkeeping (x-ray's data source)
- `P:\stonehearth\call_handlers\mining_call_handler.lua`, `new_game_call_handler.lua` — clip-height initialization
- `P:\stonehearth\services\server\client_state\client_state.lua` — persistence
- `P:\stonehearth\data\hotkeys.json`, `data\constants.json` — bindings and cell sizes
- `P:\stonehearth\renderers\water\water_renderer.lua`, `waterfall_renderer.lua`, `mining_zone\mining_zone_renderer.lua`, `pathfinder\pathfinder_renderer.lua` — consumers of the visible volume

---

## 1. <span style="color:#3fb950;">Architecture overview — one service, two tools</span>

Both Slice and X-Ray are owned by a single **client-side** service, `SubterraneanViewService`.
It holds three pieces of state (`initialize()`, lines 34–54):

```lua
self.xray_mode    = nil      -- nil | 'full' | 'flat'
self.clip_enabled = false    -- slice on/off
self.clip_height  = 24      -- slice plane Y (blocks with y <= clip_height are visible)
```

The split of responsibilities is the key architectural fact:

| Layer | Responsibility |
|---|---|
| **Lua service** | State, stepping rules, the *x-ray visible-region computation*, entity show/hide, dirty-tile batching, persistence, a public clip API for other renderers |
| **Native renderer (C++)** | The actual terrain geometry. Two entry points only: `_radiant.renderer.set_clip_height(h)` and `_radiant.renderer.enable_xray_mode(bool)` + a writable tiled region (`_radiant.renderer.get_xray_tiles()`) + per-tile invalidation (`_radiant.renderer.mark_dirty_index(index)`) |

<span style="color:#d29922;">**Inferred (native side):** the engine re-tessellates terrain
*render tiles* against the clip plane / x-ray region — the same native CSG → tessellation path
described in `07_performance_tuning.md` ("Lua never builds terrain vertices"). The Lua service
only tells the renderer *which tiles changed*; the rebuild itself is C++ and per-tile, which is
why neither tool hitches.</span>

The two tools are **mutually exclusive in the UI** (not in the service): every slice button
handler calls `setXRayMode(null)` first, and the x-ray button calls `setClip(false)` first
(`terrain_vision.js` lines 47–115). The service itself can technically run both — see
`intersect_region_with_visible_volume`, which applies clip *then* x-ray (lines 222–250) — but
the UI never lets the player combine them.

---

## 2. <span style="color:#3fb950;">Slice ("terrain slice vision" / clip mode)</span>

### 2.1 What it does

A **hard horizontal clip**: terrain at `y <= clip_height` renders; everything above is removed
entirely (no fade, no ghost — matches what `24_world_rendering.md` already records). When
disabled, the service does not flip a render path — it sets the clip plane to
`MAX_CLIP_HEIGHT = 1000000000` (lines 13, 702–708). **The renderer therefore has exactly one
code path; "off" is just a clip plane above the world.**

```lua
function SubterraneanViewService:_update_clip_height()
   if self.clip_enabled then
      _radiant.renderer.set_clip_height(self.clip_height)
   else
      _radiant.renderer.set_clip_height(MAX_CLIP_HEIGHT)
   end
end
```

### 2.2 Stepping rules — slice moves in *mining cells*, not blocks

`constants.mining.Y_CELL_SIZE = 5` (`data/constants.json:499`). The slice plane always lands on
a **cell top** so a freshly sliced view exposes a full dig layer with its ceiling removed:

```lua
function SubterraneanViewService:move_clip_height_up()
   self:set_clip_height(self.clip_height - (self.clip_height + 1) % Y_CELL_SIZE + Y_CELL_SIZE)
end
function SubterraneanViewService:move_clip_height_down()
   local delta = (self.clip_height + 1) % Y_CELL_SIZE
   if delta == 0 then delta = Y_CELL_SIZE end
   local new_height = self.clip_height - delta
   if new_height > 0 then self:set_clip_height(new_height) end   -- never reaches 0
end
```

Plus single-block variants (`move_clip_height_up_single` / `down_single`, ±1, also floored at
`> 0`). So the palette offers **four motions**: cell up, cell down, single up, single down.

### 2.3 Initialization — the slice height is *seeded by gameplay*, not a constant

Two seeding paths, both snapping to the cell grid:

1. **At embark** (`new_game_call_handler.lua:92–97`): clip height = top of the Y-cell containing
   the chosen camp location, minus the ceiling:
   ```lua
   local quantized_height = math.floor(starting_location.y / step_size) * step_size
   local clip_height = quantized_height + step_size - 1   -- -1 to remove the ceiling
   ```
2. **On the first dig-down designation** (`mining_call_handler.lua:306–309`): if the player has
   never adjusted the slice, the first mining zone initializes it to the top of the mined cell
   (`get_cell_max(box.min.y, Y_CELL_SIZE)`), so the view "follows the player underground"
   exactly once, then respects manual control forever (`_clip_height_initialized` flag).

There is **no camera-follow auto mode** — slice height is fully manual after seeding.
(Deepdraft's `21_camera.md` AUTO mode is our own invention; see plan doc.)

### 2.4 Persistence

Clip state is **saved server-side per client** (`client_state.lua:29–151`: `_clip_enabled`,
`_clip_height`, `_clip_height_initialized`) and restored on load via
`get_subterranean_state_command` (`on_server_ready`, service lines 56–76). Default
`clip_height = 24` if never set.

### 2.5 What else reacts to the slice — the *visible volume* contract

The service exposes one query and one event that every overlay system uses:

```lua
-- clips a Region3 against slice plane, then against the x-ray region if active
function SubterraneanViewService:intersect_region_with_visible_volume(region)
```

- Event: `'stonehearth:visible_volume_changed'` — fired **at most once per render frame**
  (a `_visible_volume_dirty` flag is set by any state change; a render-frame trace flushes it,
  lines 279–285, 742–751).
- Consumers found: **water** bodies and **waterfalls** (clip their render regions), **mining
  zone overlays** (clip the selection boxes to the visible volume so they don't paint inside
  hidden rock — `mining_zone_renderer.lua:112–118`), **pathfinder path display**, and the
  mining call handler's custom-block marquee.

This is the contract that makes the whole game respect the slice with no special cases in the
terrain renderer.

### 2.6 Entity visibility under slice

Entities are hidden by per-entity **visibility override handles**
(`render_entity:get_visibility_override_handle()`), not by moving/deleting nodes. Rules
(`_calculate_visible`, lines 570–647):

1. Entity visible iff its world grid location `y <= clip_height`.
2. **Exception — standing on a visible support:** if the entity's own block is hidden but it
   stands on a SOLID/PLATFORM `region_collision_shape` entity that *is* visible, it stays
   visible (recursive check with an ignore set; early exit if standing directly on terrain).
3. Entities flagged `clip_mode == 'custom'` in entity data are left alone (they clip themselves).

Visibility is recomputed for **all** entities on any clip/x-ray state change, and per-entity on
location/parent changes — but the per-entity traces only do work **when a mode is active**
(lines 338–351), so normal play pays nothing.

### 2.7 Misc verified behaviours

- **Camera "home" key** (`player_camera_controller.lua:82–83`) force-disables both tools before
  resetting to town center.
- **Hotkeys** (`data/hotkeys.json`): `\` toggle slice, `]` cell up, `[` cell down,
  `Ctrl+]` / `Ctrl+[` single block, `X` toggle x-ray, `V` building vision (separate system).
- **UI** (`terrain_vision.html`): one slice button + a fold-out palette with the four motion
  buttons and a live `{{clip_height}}m` readout; one x-ray button + a palette with
  `full` / `flat` mode buttons.
- Water renderer caps clipped water cubes to the water surface height and rebuilds its outline
  node only on `visible_volume_changed` — overlays rebuild **reactively, never per frame**.

### 2.8 <span style="color:#3fb950;">Why slice has zero performance hiccups</span>

1. **One native clip-plane value.** Changing the slice is one renderer call; no Lua geometry.
2. <span style="color:#d29922;">Per-render-tile re-tessellation in C++ — only tiles crossing the
   plane produce different geometry.</span>
3. **Overlays are event-driven** (one event per frame max) and intersect *their own small
   regions*, never the terrain.
4. **Entity work is gated** behind "mode active" and uses cheap visibility overrides.
5. **No state bifurcation:** "slice off" = clip plane at +1e9, so there is no mode-switch
   rebuild cost for the common case.

---

## 3. <span style="color:#3fb950;">X-Ray ("terrain x-ray vision")</span>

### 3.1 What it does

Replaces normal terrain rendering with **only the shell of player-carved interior spaces** —
you see your tunnels and rooms as glowing negatives through the mountain. Two modes:

- **`full`** — for each interior (mined air) volume, show the surrounding shell: the interior
  cubes inflated by **+1 in X and Z**, with `min.y` lowered by 1 (the floor). So walls + floor
  of every tunnel render; the rock body does not.
- **`flat`** — an "RPG top-down" view: only the **floor blocks** of interiors render — and only
  floor cells with at least `rpg_min_height = 4` blocks of headroom (so shafts and crawl gaps
  drop out, keeping the floor plan readable).

```lua
function SubterraneanViewService:_get_visible_cube(interior_cube)
   local visible_cube = interior_cube:inflated(Point3(1, 0, 1))
   visible_cube.min.y = interior_cube.min.y - 1
   return visible_cube
end
```

Plus a **world floor slab** (`_get_world_floor`: terrain bounds, y in [-2, 0]) is always added
to the x-ray region so the map silhouette/ground plane stays for orientation (lines 436–437,
710–715).

### 3.2 The data source: the server-side *interior region*

X-ray does not scan terrain. It consumes an **incrementally maintained "interior region"**
owned by the terrain component and updated by `MiningService` (server):

- `INTERIOR_HEIGHT = 5` (`mining_service.lua:17`).
- When a block is mined (`mine_point` → `_update_interior_region`): compute the **interior
  column** above the mined point — air upward from the point until terrain is hit, capped at
  `INTERIOR_HEIGHT` (`_get_interior_column`, lines 853–874). Add that column to
  `terrain_component:get_interior_tiles()` (a tiled `Region3` store), then
  `optimize_changed_tiles` (with a TODO admitting it shouldn't run every time).
- When terrain is **restored** (`restore_terrain`): subtract the added region extruded up by
  `INTERIOR_HEIGHT` from the interior tiles, then recompute interior columns for every mined
  point inside the dirtied volume (lines 841–851).

Natural caves get the same treatment via the ore-vein scenario. The interior tiles replicate
to the client automatically (they live on the terrain component).

### 3.3 Client-side incremental update pipeline (the performance core)

The service never rebuilds the whole x-ray region except on **mode toggle**. The pipeline:

1. **Tile traces** (`_create_interior_region_traces`, lines 294–314): a trace on the interior
   tile *map* attaches a change-trace per interior tile. A changed tile calls
   `_mark_dirty(index)`.
2. **Dirty marking** (`_mark_dirty`, lines 401–409): a changed interior tile dirties its full
   **3×3×3 tile neighbourhood** (diagonals included) — because shell inflation (+1 XZ, −1 Y)
   can cross tile borders.
3. **Frame batching** (`_create_render_frame_trace`, lines 279–285): dirty tiles are processed
   **once per render frame, at frame start** (`_update_dirty_tiles`), never inline with the
   mining event.
4. **Per-tile rebuild** (`_update_dirty_tiles`, lines 417–469): for each dirty tile —
   `xray_tiles:clear_tile(index)`, re-add the world floor, then run the `full` or `flat`
   builder over that tile's interior region (which is kept *optimized*, so the builders iterate
   merged cubes, not points). Then:
   ```lua
   for index in self._xray_tiles:each_changed_index() do
      _radiant.renderer.mark_dirty_index(index:to_float())   -- native re-tessellation, per tile
   end
   self._xray_tiles:optimize_changed_tiles(...)
   self._xray_tiles:clear_changed_set()
   ```
5. **Mode toggle** is the only expensive path: `_mark_all_dirty()` dirties every interior tile
   once, and the comment at line 199 confirms toggling nil→nil is special-cased *because the
   computation below is expensive*.

### 3.4 Entity visibility under x-ray

Entity visible iff its grid location is **inside the interior region**
(`_is_xray_visible`: `self._interior_tiles:contains(location)`) — i.e. dwarves inside tunnels
show, anything inside solid rock or on the unexcavated surface hides, with the same
standing-on-support exception as slice (§2.6).

### 3.5 <span style="color:#3fb950;">Why x-ray has zero performance hiccups</span>

1. **The expensive question — "what is interior?" — is answered incrementally at mining time**
   (one column test per mined block), never by scanning terrain at toggle time.
2. **Tile-granular dirty sets with a 3×3×3 neighbourhood rule**, processed once per frame.
3. **Optimized (cube-merged) regions** everywhere: builders iterate a handful of merged cubes
   per tile, not voxels. `flat` mode does iterate the bottom-face *points* of each cube and
   runs a 4-high terrain probe per point — affordable because it only runs on dirty tiles.
4. <span style="color:#d29922;">The actual mesh rebuild is native, per render tile, driven by
   `mark_dirty_index`.</span>
5. **All consumers reuse the same `intersect_region_with_visible_volume` + one-per-frame
   event** as slice — no system polls the x-ray state.

---

## 4. <span style="color:#3fb950;">Behavioural spec extracted (engine-agnostic)</span>

The distilled rules a faithful port must reproduce:

| # | Rule | Source |
|---|---|---|
| S1 | Slice is a hard clip at a single Y; off = clip at infinity (one render path) | service 702–708 |
| S2 | Slice steps snap to mining-cell tops (`cell_top = n*CELL - 1`); plus ±1 fine steps; floor at y=1 | service 125–149 |
| S3 | Slice height seeds from embark location, or from the first dig-down designation, once | new_game 92–97, mining_ch 306–309 |
| S4 | Slice state persists per save | client_state 29–151 |
| S5 | One `visible_volume_changed` event per frame max; overlays clip their own regions through one shared intersect API | service 222–250, 742–751 |
| S6 | Entities hide above the plane unless standing on a visible support; per-entity work only while a mode is active | service 538–647 |
| S7 | Slice and x-ray are mutually exclusive at the UI layer | terrain_vision.js 47–115 |
| X1 | X-ray renders the *shell* of interior space: interior air inflated +1 XZ, floor −1 Y (`full`), or floors-with-headroom only (`flat`, headroom 4) | service 482–536 |
| X2 | Interior space is tracked incrementally at mining time as capped air columns (height cap 5) above each mined block; block placement subtracts and locally recomputes | mining_service 829–874 |
| X3 | X-ray updates are tile-granular: a changed interior tile dirties its 3×3×3 neighbourhood; dirty tiles rebuild once per frame | service 401–469 |
| X4 | A world-floor slab is always part of the x-ray region (orientation anchor) | service 436–437, 710–715 |
| X5 | Full rebuild happens only on mode toggle | service 196–215 |
| H1 | Hotkeys: `\` slice toggle, `]`/`[` cell, `Ctrl+]`/`Ctrl+[` single, `X` x-ray toggle | hotkeys.json 195–236 |
| H2 | UI: button + fold-out palette (4 motions + live height readout; full/flat selector) | terrain_vision.html |
| H3 | Camera "home" disables both modes | player_camera_controller 82–83 |

## 5. <span style="color:#f85149;">What NOT to copy</span>

- <span style="color:#f85149;">**The Lua/C++ split itself.**</span> We have no native terrain
  tessellator; Deepdraft's equivalent of "native re-tessellation" is our threaded, budgeted
  GDScript mesh build (see `07_performance_tuning.md`). The plan must restate every
  `mark_dirty_index` as a chunk/region/tile re-mesh with a per-frame budget.
- <span style="color:#f85149;">**Y_CELL_SIZE = 5.**</span> Deepdraft's mining cell is **4**
  (`data/terrain/mining_config.json`, `43_mining_materials.md`) and our nav clearance is 3.
  All cell-snap math must use 4.
- <span style="color:#f85149;">**Server/client state round-trips.**</span> Single-process game;
  persistence is just the future save file.
- <span style="color:#f85149;">**`INTERIOR_HEIGHT = 5`.**</span> Ours should match our own
  metrics: mining cell height 4 (one dig layer) — see plan doc for the chosen value.
- <span style="color:#f85149;">**The world floor at y ∈ [-2, 0].**</span> Deepdraft has a 4-deep
  bedrock slab at Y0–3; the x-ray floor anchor must respect the Bedrock Protocol and sit at the
  bedrock top instead.

---

*Prev: [08_sky_plan.md](./08_sky_plan.md) | Next: [11_slice_xray_plan.md](./11_slice_xray_plan.md)*
