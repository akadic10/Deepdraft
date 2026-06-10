# 07 - Startup Performance Tuning

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = keep</span> |
> <span style="color:#d29922;">Yellow = review / move to a more specific plan</span> |
> <span style="color:#f85149;">Red = safe to delete or archive once you are comfortable</span>

## Document Review - 2026-06-01

**STATUS: TARGET MET.** In a release build the world is interactive in ~5.0 s with first terrain
at ~4.6 s - under Stonehearth's 5.28 s reference - and the full world overview finishes at
~9.7 s. The startup-performance effort is considered done; remaining items are optional polish
(see *Outcome* below). This file is the worklog of how we got there.

It complements, and should not duplicate:

- `06_world_start_placement.md` - now just the world-start placement backlog feature. (The
  local-generation / fog-camera-budget architecture this effort once leaned on was retired from
  that doc in its 2026-06-06 rewrite; the bounded-generation rewrite was **not needed** to hit
  the target and is recoverable in git only if the world grows.)
- the tiled block-face overview and delta visual-cut work this document builds on — from the
  retired `04_mining_performance.md`, now normative in `24_world_rendering.md` §Mining-Edit
  Invalidation Contract.

---

## <span style="color:#3fb950;">KEEP - Outcome (2026-06-01)</span>

Full-journey result, from the start of this effort to the shipped (release) build:

| Metric | Start (debug) | End, editor (debug) | End, **release** |
|---|---:|---:|---:|
| First visible terrain | ~15.5 s | 10.2 s | **4.57 s** |
| Startup -> interactive | ~20.2 s | 11.65 s | **5.01 s** |
| Map precompute | ~15.5 s | 10.1 s | **4.54 s** |
| Full world overview built | ~47.8 s (stopwatch) | 23.5 s | **9.71 s** |

Two compounding factors got us here:

1. **Algorithmic / architectural work** (this doc): parallelized map passes, deferred grass
   bands, removed redundant per-column generation in the overview, and threaded the overview
   tile build. This is what made the *editor* number drop ~20 s -> 11.6 s and the full build
   ~47 s -> 23.5 s.
2. **Release export** (~2.3-2.4x on top): stripping debug bounds/type checks and editor/debugger
   overhead from the million-iteration loops. This is what took 11.6 s -> 5.0 s. GDScript is
   still interpreted bytecode in release - export is not native compilation - so the speedup is
   from removed debug checks, not compilation.

**Key lesson: measure in a release build before optimizing.** We nearly committed to the big
bounded-generation rewrite to chase 6 s; a release export alone beat the target. Always compare
against release numbers (export with *Export With Debug* unchecked; set the console wrapper to
include Release to see the `StartupPerformance` prints), and run twice to skip first-launch
shader/asset warmup.

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

| Stage (all editor/debug unless noted) | total_to_initial_load | first_visible_terrain | map precompute | full overview build |
|---|---:|---:|---:|---:|
| Pre-work baseline (interim overview gating, doc 06) | ~19.8 s | ~15.4 s | ~15.5 s | (not stamped) |
| After map-pass parallelization | 17.79 s | 13.02 s | 12.98 s | (not stamped) |
| After grass-band deferral | 15.90 s | 10.38 s | 10.33 s | (not stamped) |
| After overview build stamp added | 15.49 s | 10.16 s | 10.11 s | **44.13 s** |
| After removing redundant overview generation (validation, surface-id neighbour, vein/cave-free sides) | 12.71 s | 10.16 s | 10.11 s | 29.84 s |
| After threading the overview tile build | 11.65 s | 10.30 s | 10.24 s | 23.53 s |
| **Release build (same code)** | **5.01 s** | **4.57 s** | **4.54 s** | **9.71 s** |

> **Two measurement corrections we learned the hard way:**
> 1. `total_to_initial_load` / `startup_ready` only marks when the **121-tile center radius** is
>    built, not when the whole map is meshed. Compare "feel of fully built" against the
>    full-overview timestamp line (`built ... 1024 tiles ... in N s`), not startup_ready.
> 2. Editor/debug numbers are ~2.3x slower than a release build for these script-heavy loops.
>    The numbers that matter are the **release** row above. Do not tune against debug numbers.

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

## <span style="color:#3fb950;">RESOLVED - The Overview-Build Bottleneck (kept for the record)</span>

> **Resolved.** Findings 1, 2 and 4 below were the real cost and have been fixed (redundant
> generation removed, build threaded). Finding 3 (`OVERVIEW_STEP`) was left as-is - the release
> build is fast enough that per-block resolution is fine. Kept here as the diagnosis trail.

The dominant cost was never map generation. It was the **block-face overview being meshed on
the main thread, at per-block resolution, with redundant generation per column** - which kept
the game at a crawl during the build and prevented jitter-free scrolling.

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

## <span style="color:#3fb950;">DONE / OPTIONAL - Fixes (was: ranked candidates)</span>

Implemented this session:

1. <span style="color:#3fb950;">**[DONE]** Removed the per-column validation re-generation</span>
   (now behind `overview_validate_block_ids`, off by default).
2. <span style="color:#3fb950;">**[DONE]** Threaded the overview tile build</span> - the geometry build
   (`_build_overview_tile_geometry`) is pure and runs on a `WorkerThreadPool` group task per
   frame batch; the main thread only assigns the finished `ArrayMesh`. Toggle: `overview_threaded`.
   A main-thread cut-block snapshot (`_ovt_cut`) keeps workers safe while mining mutates cuts.
3. <span style="color:#3fb950;">**[DONE]** Vein/cave-free side coloring + height-only neighbour
   lookup</span> - `get_overview_strata_block_id` and `get_overview_surface_height` removed the
   bulk of redundant per-column surface generation; side-color walk subsampled by
   `OVERVIEW_SIDE_COLOR_STEP`.
4. <span style="color:#3fb950;">**[DONE]** Dropped the dead `block_kind` per-column lookup.</span>
5. <span style="color:#3fb950;">**[DONE]** Parallelized `domain_map` + `heightmap` main fills</span>
   (`WorkerThreadPool`, per-X column); grass bands deferred past `maps_ready`.

Optional remaining (only if a specific problem shows up in a release playtest):

- <span style="color:#d29922;">**Side-face greedy merge.**</span> The only remaining hotspot is
  mountain tiles (~110 ms / ~127 k verts each in release). Merging adjacent coplanar same-colour
  cliff quads (as we already do for tops) would shrink them, fully smooth scrolling over the NW
  mountain *during* the background build, and improve thread load-balance. Do this **only if**
  that hitch is actually noticeable in a release playtest - it may already be fine.
- <span style="color:#d29922;">**Scope the grass-band re-mesh to cap tiles.**</span>
  `_on_grass_bands_ready` re-meshes all built tiles; only grass-cap columns change. Faster
  building means more tiles get redundantly re-meshed (~500). Low value unless profiling says so.
- <span style="color:#d29922;">**Bounded local generation.**</span> Not needed for the target
  (this architecture was retired from doc 06 in its 2026-06-06 rewrite; recoverable in git).
  Revisit only if the world size grows or precompute creeps back up.

---

## <span style="color:#3fb950;">Stonehearth fog & sky reference → moved to `08_sky_plan.md`</span>

The Stonehearth camera far-clip / sky-gradient background / height-fog research that used to live
here is consolidated in **`08_sky_plan.md` §3 (the two fog systems) and §4 (the fog post-mortem)** —
its proper home, and a more complete treatment. The one **performance** takeaway stays in scope here:
a correct sky-matched fog lets the **honest draw distance be capped to the fog distance**, so fewer
far tiles need to be built/drawn at all — a presentation lever that compounds with the overview-build
fixes above. That fog-distance → build-budget link is logged as an open item in `08_sky_plan.md` §5.

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
- After threading the overview build, is `view_radius` / fog tuning still needed, or does smooth
  full-map meshing make it moot? (The fog direction now lives in `08_sky_plan.md` §4–§5.)
- The fog-vs-far-clip direction (replace fixed Environment fog + `far_clip = 1200` with a
  time/weather height fog whose colour matches the sky, then cap draw/build distance to the fog
  distance) now lives in `08_sky_plan.md` §4–§5, with the Stonehearth fog reference.

---

*Prev: [06_world_start_placement.md](./06_world_start_placement.md)*
