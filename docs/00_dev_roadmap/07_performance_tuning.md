# 07 - Startup Performance Tuning

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = keep</span> |
> <span style="color:#d29922;">Yellow = review / move to a more specific plan</span> |
> <span style="color:#f85149;">Red = safe to delete or archive once you are comfortable</span>

## Document Review - 2026-06-01

This is the live startup-performance worklog. It records what has been measured, what has
been changed and why, and the outstanding bottleneck that still blocks a Stonehearth-class
startup. It complements, and should not duplicate:

- `06_initial_world_load_sky_fog_view_distance_plan.md` - the architectural plan (local
  generation, fog/camera budget, visibility regions). Still the source of truth for the
  long-term direction.
- `04_mining_performance.md` - the tiled block-face overview and delta visual-cut work that
  this document builds on.

---

## <span style="color:#3fb950;">KEEP - North Star</span>

Stonehearth reaches a fully playable 3D world (terrain, trees, wildlife, plants, actions) in
about 6 seconds on the same machine, and the camera can immediately scroll to any edge of the
map with no jitter. Deepdraft must match that *feel*: the whole map navigable, smooth, fast.

The target is not "generate less world." The whole world should remain navigable. The target
is "stop doing redundant, full-resolution, main-thread work to present it."

---

## <span style="color:#3fb950;">KEEP - Measured Progression</span>

All numbers from the in-engine `StartupPerformance` report on the same machine, random seed per
run (`generate(0)` -> `randi()`), 1024 x 128 x 1024 world.

| Stage | total_to_initial_load | first_visible_terrain | map precompute | full overview build |
|---|---:|---:|---:|---:|
| Pre-work baseline (interim overview gating, doc 06) | ~19.8 s | ~15.4 s | ~15.5 s | (not stamped) |
| After map-pass parallelization | 17.79 s | 13.02 s | 12.98 s | (not stamped) |
| After grass-band deferral | 15.90 s | 10.38 s | 10.33 s | (not stamped) |
| Latest measured | 15.49 s | 10.16 s | 10.11 s | **44.13 s** |

> **Important measurement correction:** `total_to_initial_load` / `startup_ready` (~15.5 s) only
> marks when the **121-tile center radius** is built, not when the world is playable. The
> renderer keeps meshing the remaining ~900 tiles afterward. A stopwatch to "actually playable"
> measured **~47.8 s**, which matches the newly added full-overview timestamp (`built ... 1024
> tiles ... in 44.13 s since startup`). Always compare against the full-overview line, not
> startup_ready.

### Latest map-phase breakdown (precompute, gen thread)

| Phase | Time | Parallelized? |
|---|---:|---|
| domain_map | 1.91 s | yes (WorkerThreadPool, per-X column) |
| heightmap | 3.88 s | partial - main fill parallel; macro precompute + 4 shaping post-passes still serial |
| lakes | 1.76 s | no |
| edge_detail | 2.55 s | no (cross-column max-merge, order dependent) |
| lowland_grass_band | ~2.1 s | no (BFS) - now deferred past maps_ready |
| foothill_grass_band | ~1.6 s | no (BFS) - now deferred past maps_ready |

---

## <span style="color:#3fb950;">KEEP - Changes Already Made</span>

### 1. Parallelized the two heaviest map passes

`WorldGenerator._compute_domain_map` and `_compute_heightmap` main fills now run through
`WorkerThreadPool.add_group_task` over `WORLD_SIZE_X`, one worker per X column. Each worker
writes a disjoint Z slice and calls only read-only helpers (noise sampling is a const read),
so output is bit-identical to the serial version; debug tallies use per-column scratch arrays
summed afterward.

- Measured: domain 2.83 -> 1.91 s, heightmap 5.48 -> 3.88 s. Net precompute -2.5 s.
- Speedup is only ~1.4-1.5x, far below core count. Two reasons: a large serial remainder still
  lives in `_compute_heightmap` (the `macro_heights` precompute calls `_macro_cell_terrain_profile`,
  which loops `TERRAIN_MACRO_CELL_SIZE^2` = ~1M ops total before threading; plus four serial
  shaping post-passes that currently change nothing - `shaping: terraced 0, plateau-adjusted 0`),
  and likely copy-on-write contention from many threads writing one packed array.

### 2. Deferred the grass-band passes past `maps_ready`

The two grass-band passes are cosmetic surface-variant overrides (they pick grass tiers near
lowland/foothill cap edges; they do not change terrain shape). They were moved to run **after**
the `maps_ready` emit so first-visible terrain no longer waits on them (-2.6 s).

Race safety: a `_grass_bands_ready` gate flag (flipped on the main thread by
`_deferred_finalize_grass_bands`) keeps every main-thread reader of the band/distance maps from
touching them while the generator thread is still writing. While the gate is closed, the
overview renders a procedural fallback grass. When it opens, a `grass_bands_ready` signal asks
`WorldRenderer` to re-mesh the already-built overview tiles **in place** (no node free -> no
flicker).

### 3. Stamped the full-overview completion time

`WorldRenderer` now appends `... in %.2f s since startup` to the "built block-face overview
tiles (1024 tiles ...)" log so the true time-to-playable is visible, not just startup_ready.

### 4. Fixed a shadowing warning

Renamed `_set_overview_nodes_visible(is_visible)` -> `(make_visible)` to stop shadowing
`Node3D.is_visible()`.

---

## <span style="color:#f85149;">CRITICAL - The Real Bottleneck (overview build)</span>

The dominant cost is no longer map generation. It is the **block-face overview being meshed on
the main thread, at per-block resolution, with redundant generation per column.** This is what
keeps the game at a crawl for ~44 s and prevents jitter-free scrolling.

### <span style="color:#f85149;">Finding 1 - All overview meshing runs on the main thread</span>

`_process` -> `_update_block_face_overview` -> `_drain_overview_tile_queue` builds
`overview_tiles_per_frame = 8` tiles per frame, each ~43 ms. That is **~344 ms of main-thread
work every frame -> ~3 FPS for the full ~44 s build.** Scrolling to an unbuilt edge triggers
those 43 ms builds inside the frame loop, which is the jitter.

Stonehearth builds terrain up front off the main thread (engine-native tessellation), so its
main thread stays smooth and the finished static mesh scrolls freely. Same "whole world is
there," different threading model.

### <span style="color:#f85149;">Finding 2 - A redundant full-world validation pass</span>

In `WorldRenderer._rebuild_overview_tile`, each column's surface block is computed once
(`_overview_visible_surface_after_cut`, line ~1238) and then the **entire surface-generation
pipeline is run again** on the same column (`WorldGenerator.get_generated_block_id`, line ~1243)
only to assert the two match (`validation_mismatches`). That counter is `0/1048576` - it has
never failed. This doubles the top-face generation cost across all 1,048,576 columns purely for
a debug check.

### <span style="color:#f85149;">Finding 3 - `OVERVIEW_STEP = 1` (one quad per block)</span>

The overview samples and meshes every single block of the 1024 x 1024 surface. At the zoom used
to navigate the whole map, per-block detail is not resolvable. A coarse step (4 or 8) would cut
whole-map sampling and face count by 16-64x while looking identical at navigation zoom.

### <span style="color:#f85149;">Finding 4 - Generation pipeline invoked several times per column</span>

Beyond the validation double-call, side faces re-invoke `get_generated_block_id` per exposed
side band via `_overview_side_color_at`. So the per-column generation pipeline runs several
times, not once.

---

## <span style="color:#d29922;">REVIEW - Candidate Fixes (ranked by leverage)</span>

Not yet implemented. Listed so we can decide order and confirm none regress the working visual.

1. <span style="color:#f85149;">**Remove the per-column validation re-generation**</span> in
   `_rebuild_overview_tile`. Keep it only behind an explicit debug flag, run on a sparse sample,
   not every column. Expected: roughly halves top-face cost. Lowest risk, highest certainty.
2. <span style="color:#d29922;">**Move overview meshing off the main thread.**</span> Generate
   tile geometry (vertex/normal/color/index arrays) in a worker; only the final
   `ArrayMesh`/`MeshInstance3D` assignment must touch the main thread. Removes the ~3 FPS stall
   and the scroll jitter. Biggest feel improvement.
3. <span style="color:#d29922;">**Coarsen `OVERVIEW_STEP` to 4-8 for the navigation view.**</span>
   16-64x fewer samples/faces for the whole map. Pairs with a higher-detail step only when zoomed
   in. Confirm the look at navigation zoom first.
4. <span style="color:#d29922;">**Cache the surface block id during precompute.**</span> The
   surface skin is recomputed on demand (`_pick_surface_block` re-runs slope/region/grass-variant
   noise) every time the overview asks for a column. A cheap per-column `surface_block_id` array
   filled during the (already running) map passes would make overview/streaming surface lookups
   O(1) instead of re-deriving them.
5. <span style="color:#d29922;">**Scope the grass-band re-mesh to cap tiles only.**</span>
   `_on_grass_bands_ready` currently re-meshes all built tiles; only cap columns actually change
   between fallback and final. Also make the fallback a single flat grass variant so the interim
   is clean instead of a checkerboard.
6. <span style="color:#d29922;">**Finish parallelizing / pruning the heightmap serial remainder.**</span>
   Parallelize the `macro_heights` precompute loop; drop or gate the four shaping post-passes
   that currently produce zero changes.

---

## <span style="color:#3fb950;">KEEP - Stonehearth Reference: Camera Far Clip, Background & Distance Fog</span>

Read from `P:\stonehearth` on 2026-06-01. This is how Stonehearth keeps the whole map present
and navigable without a hard terrain edge - and why it does not need a large fixed far clip.

### Camera / far clip

- `services/client/camera/player_camera_controller.lua` clamps zoom only: `_min_zoom = 15`,
  `_max_zoom = 300` (lines 144-145). Zoom step scales with distance (short/med/far factors
  0.2/0.3/0.4 at <100 / <500 / beyond).
- There is **no scripted hard far-clip plane** that culls distant terrain. Distant geometry is
  hidden by **fog that fades into the sky**, not by clipping. The far plane is left to the engine
  and the horizon is dissolved visually.
- Contrast - Deepdraft (`data/camera/camera_settings.json`): `far_clip = 1200`, `max_distance
  = 180`, plus a fixed Godot Environment fog with `fog_depth_end = 170` in `debug_world.tscn`.
  This is a static, non-time, non-weather approximation.

### Background = time-of-day sky gradient, cross-faded by weather

- `services/client/sky_renderer/sky_renderer_service.lua` sets a **sky gradient texture**
  (`set_sky_texture('skyGradient', ...)`, e.g. `data/texture_gradient/skybox/sunny/sky_gradient.png`)
  and samples it by **normalized game time**: `set_sky_parameter('parameters',
  normalized_game_time, transition_factor, ...)`. The background is a gradient, not a flat color.
- Weather changes call `transition_sky(new_sky_settings_json_path, transition_interval)`, which
  cross-fades `skyGradient` -> `targetSkyGradient` and interpolates every sky/light/fog param
  over the interval. Each weather has its own `data/weather/<name>/<name>_sky_settings.json`.

### Distance fog = shader height-fog, colored by sun and weather

- Fog is a **shader effect** (`data/horde/shaders/fullscreen_quad_height_fog.shader`,
  `data/horde/shaders/utilityLib/atmosphere.glsl`), driven each frame by
  `SkyRenderer:_update_height_fog` through global uniforms:
  - `heightFogParams = (fog_height, fog_thickness_factor, fog_noise_factor, 1.0 / fog_distance_factor)`
  - `heightFogParams2 = (fogNoiseScaleX, fogNoiseScaleZ, fogNoiseSpeed, 1)`
  - `heightFogColorMult` = fog tint.
- Shader distance term: `fFar = clamp(length(pos - camViewerPos) * heightFogParams.w, 0, 1)`,
  and fog color is `celestialLightColor * heightFogColorMult`. So **fog takes the sun's current
  color times the weather tint** - the horizon fog matches the sky gradient, and the terrain edge
  dissolves into the background instead of ending at a visible line.
- All fog params are **time-of-day interpolated and weather cross-faded**. Concrete values:

| Sky setting | time | height_fog = (height, thickness, noise, distance) | color mult |
|---|---|---|---|
| default/sunny | midday | (0, 0.3, 1, **500**) | (1,1,1,1) |
| default/sunny | dawn/dusk | (50, 0.4, 1, 150) | (1,1,1,1) |
| default/sunny | midnight | (100, 0.5, 1, 100) | (1,1,1,1) |
| foggy | midday | (70, 0.8, **5**, 250) | (0.152, 0.16, 0.144, 1) |

  (Source: `data/calendar/sky_settings.json` = `stonehearth:sky_settings:default`,
  `data/weather/foggy/foggy_sky_settings.json`.)

### <span style="color:#d29922;">REVIEW - Why this matters for performance</span>

The fog is not only cosmetic - it is what lets the renderer **stop drawing far terrain crisply
without showing a hard edge**. Because the horizon fades to a sky-matched color well before any
boundary, the effective draw distance can be much smaller than `far_clip`, and the build budget
can match it (doc 06, Phase 6). Deepdraft currently promises a 1200-unit far clip with fixed
170-unit fog that neither matches a sky gradient nor tracks time/weather, so it both over-draws
(no honest distance cap) and shows a flatter horizon. A weather/time-driven height fog whose
color matches a sky gradient would let us cap drawn/built tiles to the fog distance cleanly.

This is a presentation lever that compounds with the overview-build fixes above: smaller honest
draw distance -> fewer far tiles that must be built and drawn at all.

---

## <span style="color:#3fb950;">KEEP - Stonehearth Reference: How Terrain Is Built (and why there is no jitter)</span>

Read from `P:\stonehearth` on 2026-06-01. The "smooth, whole map present, no jitter" behavior is
three mechanisms working together. Critically, **Lua never builds terrain vertices** - it only
describes terrain as boxes and lets the native engine tessellate.

### 1. Lua produces compact region data; native C++ does the meshing

`services/server/world_generation/height_map_renderer.lua`:

- `render_height_map_to_region` builds a **`Region3`** (a set of axis-aligned cubes) for surface,
  underground, and bedrock, then calls **`region3:optimize(...)`** - a native CSG pass that merges
  the cubes into a minimal box set.
- `add_region_to_terrain` then does the geometry:
  ```lua
  local ring_tesselator = self._terrain_component:get_terrain_ring_tesselator()
  local tesselated_region = ring_tesselator:tesselate(region3, clipper)
  self._terrain_component:add_tile(tesselated_region)
  ```
  `Region3`, `optimize`, and `tesselate` are all `_radiant.csg` / native C++. Lua hands over
  *what the terrain is* (boxes); the engine builds the mesh. No per-face vertex work in script.

This is the core contrast with Deepdraft. Our block-face overview builds
`PackedVector3Array`/normals/colors/indices **per column, per face, in GDScript**
(`_rebuild_overview_tile`, `_add_overview_sides`, `_add_greedy_overview_tops`). We do in an
interpreted language, on the main thread, what Stonehearth does in compiled C++.

### 2. Generation is a yielding coroutine, tile by tile

`services/server/world_generation/world_generation_service.lua`:

- `_run_async(fn)` runs generation in a coroutine; `_yield()` is `coroutine.yield()` (line ~485).
- The per-tile body (`_generate_tile_internal`, ~line 330-377) calls `self:_yield()` **after every
  phase**: terrain gen, render-to-region, water, add-to-terrain, flora, scenarios - and the outer
  loop yields between tiles. So generation is time-sliced across game ticks and never blocks for a
  long stretch.
- Only a bounded local tile radius is materialized first (`DEFAULT_WORLD_GENERATION_RADIUS = 2`,
  i.e. 5x5 tiles around the chosen spot), the rest stream in later.

### 3. The client renderer only installs visibility regions

`services/client/renderer/renderer_service.lua` does **not** build terrain. It calls
`_radiant.renderer.visibility.set_visible_region(uri)` / `set_explored_region(uri)`. The native
engine owns terrain meshing *and* visibility culling. The Lua client never touches terrain
geometry at all.

### <span style="color:#f85149;">What this means for Deepdraft</span>

We cannot get C++ tessellation in GDScript, but the jitter cause is squarely #1 + the main thread:
we build mesh arrays on the main thread. The actionable equivalents:

1. **Build the mesh arrays off the main thread.** A `WorkerThreadPool` task can fill the
   `PackedVector3Array`/normal/color/index arrays for a tile; only `ArrayMesh.add_surface_from_arrays`
   and the `MeshInstance3D` assignment must run on the main thread. This is the GDScript analog of
   Stonehearth freeing its main thread via native tessellation, and it directly removes the ~3 FPS
   stall and scroll jitter (candidate fix #2 above).
2. **Reduce the geometry the way `region3:optimize()` does.** We already greedy-merge top faces;
   merging side faces and coarsening `OVERVIEW_STEP` shrink the array sizes the worker must build.
3. **Keep generation time-sliced.** Map generation already runs on a `Thread`; the gap is that the
   *mesh build* is the part still on the main thread. Fixing #1 closes that gap.

The lesson is not "rewrite in C++." It is: **stop building vertices on the main thread, and feed
the GPU fewer, larger faces.**

---

## <span style="color:#3fb950;">KEEP - Constraints (do not regress)</span>

- The whole 1024 x 1024 map must remain navigable; do not silently shrink the world or gate the
  camera to a local patch as a substitute for fixing the build cost.
- Deterministic generation from `world_seed`: parallel or cached paths must produce identical
  output. Verify by pinning a fixed seed and diffing two runs (seed-independent macro values -
  `basin 146524, southeast foothill 131583, edge belt 111552` - are a quick integrity check).
- Bedrock at Y0-3, namespaced block IDs, 3-block nav clearance, terrain identity in data.
- The finished grass look must match the working result (uniform cap grass with edge-ring tiers).

---

## <span style="color:#d29922;">REVIEW - Open Questions</span>

- Is the block-face overview the right long-term representation for the navigation view, or
  should distant terrain use an engine-native / LOD mesh as Stonehearth does?
- Should the surface block id be a first-class generated map (like `heightmap`/`domain_map`)
  rather than an on-demand recomputation?
- After threading the overview build, is `view_radius` / fog tuning (doc 06, Phase 6) still
  needed, or does smooth full-map meshing make it moot?
- Should Deepdraft replace fixed Environment fog + `far_clip = 1200` with a Stonehearth-style
  time/weather-driven height-fog whose color matches a sky-gradient background, so the draw
  distance can be honestly capped to the fog distance (see reference section above)? Godot
  supports a custom `sky` shader and height/depth fog; the sky-gradient + fog-color-matches-sky
  trick is reproducible without Horde3D.

---

*Prev: [06_initial_world_load_sky_fog_view_distance_plan.md](./06_initial_world_load_sky_fog_view_distance_plan.md)*
