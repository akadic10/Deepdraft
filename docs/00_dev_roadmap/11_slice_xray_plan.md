# 11 - Slice & X-Ray: Deepdraft Implementation Plan

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = decided / ready to build</span> |
> <span style="color:#d29922;">Yellow = decision needed or tune-in-engine</span> |
> <span style="color:#f85149;">Red = explicitly out of scope for this pass</span>

Status: plan, written 2026-06-03 against the verified Stonehearth findings in
[`10_slice_xray_stonehearth_reference.md`](./10_slice_xray_stonehearth_reference.md) (rules
S1–S7, X1–X5, H1–H3 referenced throughout). Read that document first.

**Why this matters more for us than for Stonehearth:** Stonehearth is a surface game where
slicing is an occasional inspection tool. Deepdraft's core loop is *Dig → Brew → Trade* — the
player lives at the slice plane. Slice is not a vision mode here; it is **the primary camera of
the underground game** and must be rock solid: instant response, no global rebuilds, correct at
every depth, and visually honest (Hard Rule 9: block identity from data, never renderer tricks).

---

## 1. Where Deepdraft stands today (gap analysis)

What already exists and what is missing, from the current code:

| Piece | State today | Gap |
|---|---|---|
| `WorldRenderer.slice_y` | Exported property; culls **whole 16-block chunk layers** via `_chunk_y_is_visible()`; drives overview-vs-streamed mode switch at `overview_slice_threshold = 96` | **No per-block clip.** Moving the slice by 1–15 blocks inside a chunk layer changes nothing visually. A real slice needs block-granular clipping in the mesher. |
| `ChunkMesher.build_mesh()` | Already takes `visual_cut_blocks` and treats cut neighbours as transparent | The identical mechanism extends naturally to a `slice_y` parameter — blocks above the plane are skipped and treated as transparent so **cut-plane top faces emit** (the floor of the slice view). |
| `Camera.slice_y_changed` | Signal emitted (AUTO follow formula from `21_camera.md`) | **Nothing connects to it.** AUTO mode is currently dead wiring. |
| Dock `Slice` / `X-Ray` buttons | Present in `dock.json` as `toggle_window` stubs | No tool behind them. |
| Mining designation overlays | `MiningDesignationController` already reads `slice_y` for raycasts and grid (`_current_slice_y`) | Overlay meshes (zone fills, terrain grid, previews) do not clip to the slice volume → they draw inside hidden rock. Needs the visible-volume contract (S5). |
| Mining execution | Not implemented — zones are renderer-state visual cuts only | X-ray's data source (the interior region, X2) has **no producer yet**. The visual-cut set is the interim stand-in. |
| Entities (dwarves, items) | Not implemented | Entity visibility rules (S6) are forward hooks only. |
| Overview mode | Surface-only, active when `slice_y >= 96` | Correct interplay already exists: slicing below the threshold streams chunks. The slice tool must manage this transition deliberately (§3.4). |

**Terminology lock:** Deepdraft `slice_y` = **highest visible block layer, inclusive**
(`wy > slice_y` is hidden). Stonehearth's `clip_height` has the same meaning. All math below
uses this convention.

**Cell constant:** all snapping uses Deepdraft's mining cell height **4**
(`data/terrain/mining_config.json` → `dig_tool.y_cell_size`), not Stonehearth's 5. A *cell top*
is `n*4 - 1` (Y3, Y7, Y11, … — though Y3 is bedrock top and the floor clamp keeps the slice
above it, §3.2).

---

## 2. Architecture decision — how we replace Stonehearth's native layer

Stonehearth's zero-hiccup model = Lua state + native per-tile re-tessellation (ref doc §2.8,
§3.5). Our equivalents, reusing machinery that already ships in `WorldRenderer`:

| Stonehearth | Deepdraft equivalent |
|---|---|
| `_radiant.renderer.set_clip_height(h)` | `slice_y` passed into `ChunkMesher.build_mesh()` (block-granular skip + transparent-above test), plus chunk-layer node visibility for whole hidden layers |
| Native per-render-tile re-tessellation | Our existing **region rebuild queue** (`_dirty_region_queue`, per-frame budget) + the **threaded overview tile build** pattern (`WorkerThreadPool` batch, main thread assigns meshes) |
| `mark_dirty_index` | `_enqueue_region(key)` / `_enqueue_overview_tile(key)` — already deduplicated and budgeted |
| `xray_tiles` (tiled Region3 store) | A per-chunk **interior set** (`Dictionary[Vector3i chunk] -> Dictionary[Vector3i block]`) owned by a new `VisibleVolume` helper on the renderer |
| `visible_volume_changed` (1/frame max) | Same: a dirty flag flushed once in `_process` |
| `intersect_region_with_visible_volume()` | `VisibleVolume.filter_blocks(blocks)` / `clip_aabb(aabb)` — consumed by mining overlays first |

### <span style="color:#d29922;">2.1 Considered and rejected: shader clip plane</span>

A Godot global shader parameter discarding fragments above `slice_y` would make slice motion
free — but our mesher **skips buried faces**, so discarding the crust exposes a hollow shell:
the player would see through the world. The interior faces only exist if the mesher emits them,
which means geometry rebuild is unavoidable — same conclusion Stonehearth reached (hard clip via
re-tessellation, ref §2.1).

<span style="color:#d29922;">**Optional polish, deferred:** a shader clip *on top of* the
mesher clip could hide the one-frame latency while the slice-row remesh drains (instant
fragment cut, then real geometry replaces it). Only attempt if Phase 1 measurement shows
visible latency; one variable at a time, per the doc-08 fog lesson.</span>

### 2.2 The cost shape that makes slice cheap (the key insight)

A slice move from `old_y` to `new_y` requires re-meshing **only chunks whose 16-block layer
contains either plane** — every other chunk's geometry is unchanged:

- Chunks entirely **below** both planes: identical mesh. No work.
- Chunks entirely **above** `new_y`: hide node (visibility flip, free).
- Chunks whose layer contains `old_y` or `new_y`: re-mesh with the new clip (these are the only
  chunks whose block-skip set changed).

At `view_radius_chunks = 5` that is ~81 chunk columns × at most 2 chunk layers = **≤ ~162 chunk
meshes worst case, usually ~81** (one layer, when both planes share a chunk row), built through
the existing region queue. A single-block slice step inside one chunk row touches only that row.
This is the budget Phase 0 must verify.

---

## 3. SLICE — implementation phases

### <span style="color:#3fb950;">Phase 0 — Instrument before building</span>

Measured in a **release build** (doc-07 lesson), deep slice into the NW mountain at default
zoom:

- Time to re-mesh the slice row after a 4-block step (region queue drain time, per-frame stall).
- Mesh/vertex counts per sliced region vs unsliced.
- Worst case: slice from Y96 (overview threshold) down to Y20 in one drag — total time, frame
  spikes.

Acceptance: a numbers row in this doc to compare every later phase against.

#### <span style="color:#3fb950;">Phase 0 RESULTS — 2026-06-04 (editor/debug build, camera at world centre)</span>

Instrumentation: `WorldRenderer.slice_debug_timing` (default on; silent unless `slice_y` changes).
Measured by Alen via inspector pokes; seeds 1330346877 / 1699453172.

| Case | Result |
|---|---|
| Cold slice-on, 127 → 60 (from overview, zero streamed chunks) | 12.6–23.8 s to fully settled, dominated by background **column generation** (81 columns, 3.85 s gen-thread). 50 region rebuilds collapsing to 7 final nodes — regions rebuild repeatedly as their 16 columns stream in. Worst single frame **964–1821 ms** (initial budget builds up to 12 regions in one frame at 86–294 ms per region rebuild). |
| Warm step 60 → 59 (in chunk row) | **0 regions, 0 ms** — and 0 visual change (culling is chunk-layer-granular). |
| Warm step 59 → 60 | **0 regions, 0 ms.** |

**Findings that correct this plan's assumptions:**

1. The current `slice_y` setter does NOT globally rebuild. `_enqueue_visible_existing_chunks()`
   only enqueues regions **without existing nodes**, so warm steps are free today — because they
   also do nothing. §1's gap analysis stands: no per-block clip, and additionally:
2. **Latent bug:** a slice step crossing a 16-block chunk boundary re-enqueues nothing for
   regions with live nodes — their meshes go stale. Unobserved only because nothing moves
   `slice_y` at runtime yet. Phase 1b's dirty math fixes this.
3. The Phase-1 risk is therefore *new* per-step work, not removing old global work: each
   plane-row region rebuild costs ~86–294 ms (debug; ÷~2.3 for release). If stepping feels
   hitchy after Phase 1, thread the region mesh build (the proven `_ovt_` WorkerThreadPool
   pattern) as a Phase 1c — do not pre-emptively combine the two changes.
4. Cold-transition polish (region rebuilt up to 16× while its columns stream in) is a separate
   pre-existing cost amplifier; out of scope for this pass, noted for a future streaming pass.

#### <span style="color:#3fb950;">Phase 1 RESULTS — 2026-06-04 (editor/debug, after mesher clip + localized dirty math)</span>

| Case | Result |
|---|---|
| Cold 127 → 60 (camera at world centre) | 5.2 s settled, 49 region rebuilds, worst frame **587 ms** (was 964–1821 ms at baseline). |
| Warm ±1 step, plane ABOVE all local terrain | **0 regions, 0 ms** — dirty rule correctly identifies a non-intersecting plane as free. |
| Warm ±1 step over the NW mountain (plane cuts rock) | **9 of 10 live regions rebuilt** (the mountain subset), ~1.8 s total, worst frame **~900 ms** — budget builds 4 serial region rebuilds (~200–300 ms each) per frame on the main thread. |

Visual acceptance passed: cut floor renders at the plane, walls below, void above; non-intersected
terrain renders normally; both step directions produce symmetric rebuild counts (determinism).

**Phase 1c trigger met:** ~900 ms/step debug (~390 ms release) is far above the ≤16 ms/frame
target. Next lever per §5 guardrail 4: build region mesh arrays on a WorkerThreadPool (the proven
`_ovt_` batch pattern) so a frame's cost is the MAX single region build, not the SUM. If still
hitchy after threading, split region nodes per chunk-row (cy) so a slice step rebuilds only the
plane row — measure between the two changes, one variable at a time.

#### <span style="color:#3fb950;">Phase 1c RESULTS — 2026-06-04 (editor/debug, threaded region batch)</span>

`ChunkMesher.build_arrays` (pure, worker-safe) + `WorldRenderer` batch dispatch
(`region_threaded`, default on; serial fallback kept).

| Case | Before 1c | After 1c |
|---|---|---|
| Warm ±1 step over the mountain (9 regions) | 1.74–1.82 s total, worst frame ~900 ms | **0.73–0.78 s total, worst frame ~485 ms** |
| Cold 127 → 60 | worst frame 587–964 ms | **worst frame 444 ms** |

**Analysis:** with `vertical_context_chunks = 0` a region rebuild is already only the plane-row
chunks (~16), so the row-split idea is moot — the cost is **~27 ms per single 16³ chunk mesh**,
dominated by GDScript inner-loop waste: `BlockRegistry.get_color()` string-splits per solid block
(~3k/chunk), `is_transparent()` dict lookups per neighbour check (~6/block), and a WorldData mutex
acquisition per cross-chunk neighbour read (thousands/chunk, contended across workers). Phase 1d
= LUT caches (colour, transparency) + a 6-neighbour chunk snapshot per build, all inside
ChunkMesher. Greedy face merging is explicitly deferred (bigger rewrite, separate pass).

#### <span style="color:#3fb950;">Phase 1d RESULTS — 2026-06-04 (editor/debug, mesher fast path) — PHASE 1 BANKED</span>

BlockRegistry eager LUTs (per-season colour `PackedColorArray`, transparency `PackedByteArray`,
built in `_ready`, immutable → lock-free for workers) + ChunkMesher 6-neighbour chunk snapshot
(6 mutex ops per chunk instead of thousands) + cut-dict short-circuit when no mining cuts exist.

| Case | 1b (serial) | 1c (threaded) | **1d (fast path)** |
|---|---|---|---|
| Warm ±1 step over the mountain (9 regions) | ~1.8 s / ~900 ms worst frame | 0.73 s / ~485 ms | **0.47 s / ~240 ms** |
| Cold 127 → 60, worst frame | 587–964 ms | 444 ms | **211 ms** |

Per-chunk mesh cost ~27 ms → **~14 ms** (debug). Release estimate ÷~2.3 → ~105 ms worst frame
per step. Visual output verified identical (cut floor, walls, colours, water).

**Decision: Phase 1 banked here.** Remaining inner-loop cost is `_add_quad` call overhead and
per-face Vector3 construction — the next meaningful lever is **greedy face merging** (fewer,
larger quads), a dedicated future pass that also shrinks upload sizes. Not worth blocking the
Slice tool on. Committed as slice Phase 1 (a: mesher clip, b: localized dirty math, c: threaded
region batch, d: mesher fast path).

#### <span style="color:#3fb950;">Phase 1e RESULTS — 2026-06-04 (region rebuild defer during streaming)</span>

`WorldGenerator.is_column_pending()` + renderer drain-time defer: regions whose chunk columns are
still queued/in-flight are requeued (never dropped — each completing column re-dirties its region,
and the bounded one-pass queue scan prevents pending regions starving ready ones).

| Metric | Before 1e | After 1e |
|---|---|---|
| Cold 127 → 60: region rebuilds | 125 for ~10 final nodes (up to ~16× redundancy) | **24** |
| Cold settle time | ~10.6 s | ~10.5 s — now purely **generator-thread bound** (~130 ms/column, serial); renderer redundancy eliminated |
| Streamed-mode panning | noticeable churn/stutter | verified improved in-engine (Alen) |

Known remaining limits, by design for this pass: slice view shows only the streamed radius
(`view_radius_chunks`) — a "sliced overview" for full-map context would be a new render mode;
cold-transition time is generation throughput, a future streaming-pass concern (parallel column
fill is the obvious lever). Slice steps over settled terrain: ~240 ms worst frame debug
(~105 ms release), greedy meshing is the next lever.

**Refinement (same day):** the first defer implementation was all-or-nothing — a region showed
NOTHING until every column generated, producing swiss-cheese holes inside the streamed area
while the generator drained its queue. Fixed: defer applies to REbuilds only (`_region_nodes.has`
guard). First build happens immediately from whatever columns exist (progressive fill); the
final rebuild waits for the region to settle. ~2 builds per region, no holes.

### <span style="color:#3fb950;">Phase 1 — Block-granular clip in the mesher (the core)</span>

1. `ChunkMesher.build_mesh(chunk, cx, cy, cz, visual_cut_blocks, slice_y)`:
   - Skip blocks with `wy > slice_y` (same pattern as the `visual_cut_blocks` skip).
   - `_neighbor_transparent()` returns `true` for neighbours with `wy > slice_y` → blocks at
     `wy == slice_y` emit **top faces** (the cut floor) and side faces at the boundary emit
     normally. The black void above reads as rock (`24_world_rendering.md` §slice).
2. `WorldRenderer._rebuild_region()` passes its current `slice_y`.
3. `slice_y` setter computes the dirty set per §2.2: visibility flips for whole layers,
   `_enqueue_region` only for regions intersecting the old/new plane rows. **Never**
   `_enqueue_visible_existing_chunks()` wholesale (the current setter behaviour — replace it).
4. `_chunk_y_is_visible()` keeps culling whole layers above the slice (unchanged); the mesher
   clip handles the partial row.
5. Cut-face readability (`24_world_rendering.md`): vertical faces *at the slice boundary*
   slightly brighter than buried faces. Implementation: when emitting a side face whose
   neighbour is air-because-of-slice (not air-in-data), lighten the vertex colour by a small
   fixed factor. <span style="color:#d29922;">Tune the factor in-engine; it must not repaint
   block identity (Hard Rule 9 — brightness shading is presentation, colour hue stays the
   block's own).</span>

Acceptance criteria:

- Moving the slice 1 block inside a chunk row updates geometry within the per-frame budget; no
  global queue flush.
- A sliced room shows: floor top faces at `slice_y`, exposed wall faces below, black void above.
- Determinism: slicing and restoring produces the identical mesh (no state leaks).
- Mining visual cuts and slice compose correctly (a cut block above the plane stays gone when
  the plane rises past it).

### <span style="color:#3fb950;">Phase 2 — The Slice tool (UX, parity with S2/S3/S7/H1/H2)</span>

1. **Dock:** repurpose the existing `slice` dock entry from `toggle_window` stub to a real
   tool: button toggles slice mode; while active a small palette window (same visual language
   as the Clock window) shows: cell up, single up, **live `slice_y` readout**, single down,
   cell down. (H2)
2. **Stepping (S2, cell = 4):**
   - cell up: `slice_y = slice_y - ((slice_y + 1) % 4) + 4`
   - cell down: `delta = (slice_y + 1) % 4; if delta == 0: delta = 4; slice_y -= delta`
   - singles: ±1.
   - Floor clamp: `slice_y >= 4` (bedrock top Y3 must never become the only visible layer of
     nothing; Y4 keeps one mineable layer visible — Bedrock Protocol stays inviolate).
   - Ceiling clamp: `slice_y <= 127` = slice off (see §3.4).
3. **Hotkeys (H1):** `\` toggle, `]`/`[` cell, `Ctrl+]`/`Ctrl+[` single. Registered as input
   actions in `project.godot` `[input]` <span style="color:#d29922;">(needs a one-line addition
   to the AGENT.md project.godot ownership note — currently only `[autoload]` + main scene are
   agent-editable; flag to Alen before editing)</span>.
4. **Seeding (S3):** first activation seeds `slice_y` from the camera's hovered surface column:
   `cell_top(get_visible_surface_y(center))`. When mining execution lands, the first dig-down
   designation seeds it once (`initialized` flag), exactly like Stonehearth.
5. **Mutual exclusion (S7):** activating Slice deactivates X-Ray and vice versa — enforced in
   the tool layer (DockUI dispatch), not in the renderer.
6. **AUTO mode reconciliation:** `Camera.slice_y_changed` (AUTO follow) remains **opt-out
   dead** by default — Stonehearth has no auto-follow and manual control proved right (ref
   §2.3). Keep the signal; add a settings flag later if AUTO is wanted.
   <span style="color:#d29922;">Decision recorded: manual-first; AUTO behind a toggle, later.</span>
7. State persists with the future save system (S4); until then, session-only.

Acceptance criteria:

- Full keyboard + mouse parity with the table in ref doc §4 (H1/H2), adjusted to cell 4.
- Toggling slice off restores the full view without a global rebuild (off = `slice_y = 127`,
  S1 — one code path, no special "off" state).

#### <span style="color:#3fb950;">Phase 2 RESULTS — 2026-06-05, verified in-engine by Alen — PHASE 2 BANKED</span>

**Shipped:**

- `scripts/systems/SliceController.gd` (new) — tool state, cell-4 stepping snapped to cell
  tops, clamps [4, 127], one-time camera-column seeding (S3, retries until maps_ready),
  last-height restore across toggles, hotkey handling, `deactivate_if_active()` exclusion
  hook for the future X-Ray tool (S7), and the palette window (Clock-window visual language:
  ▲▲ cell / ▲ block / live `Y = N` readout / ▼ block / ▼▼ cell).
- `project.godot` `[input]` — `slice_toggle` (\), `slice_cell_up` (]), `slice_cell_down` ([),
  `slice_single_up` (Ctrl+]), `slice_single_down` (Ctrl+[); physical keycodes. AGENT.md
  ownership note extended to cover `[input]` (approved 2026-06-05).
- `DockUI.gd` — `slice` target routes to the controller (no more stub window); button
  pressed-state tracks `slice_active_changed`; controller self-registers via its
  `dock_ui_path` export.
- `scenes/main/debug_world.tscn` — SliceController node, all three paths wired.
- `data/ui/dock.json` — slice tooltip documents the hotkeys.

**Verified (in-engine, editor/debug):** Y4 floor clamp holds; ] / [ step ±4 (cell), Ctrl+] /
Ctrl+[ step ±1 with exact-match (no double-fire); Y126 is the last displayed height and 127
reads "Off"; toggle off/on restores the full view and the last manual height; dock button
state and live readout track correctly. Stepping cost matches SO-1 FINAL behaviour
(per-tile invalidation, center-first); release-build re-measure still pending (§5
guardrail 6).

**Deviations from the plan as written:** the palette window is owned by SliceController
itself (one CanvasLayer, like MiningDesignationController's zone window) rather than built
inside DockUI; registration is push-style (`register_slice_controller`) from the controller's
`dock_ui_path` export. Persistence is session-only (S4 waits for the save system). Seeding
from the first dig-down designation (S3's second path) waits for mining execution.

**Surfaced during verification, recorded as follow-ups:** floating zone overlays above the
plane → Phase 3 decision note (clip, Stonehearth's choice); missing alignment grid on
plane-cut floors → Phase 2b below.

#### <span style="color:#d29922;">Open performance note — slice-step stutter (observed 2026-06-05, deferred)</span>

**Observation (Alen, editor/debug, ±1 steps at Y64–65 over the mountain):** a minor but
feelable hitch per step — 283 tiles, ~1.5 s sweep, **worst frame 58–64 ms** — present with
and without mining zones, mining tool active or not. Slowest tile is always the world corner
`(0, 0)` at 34–39 ms, with `sides_us` ≈ 27–30k of it (deep world-edge walls).

**Diagnosis:** this is the accepted SO-1 FINAL cost, now felt interactively. Two compounding
facts: (1) the threaded tile batch **blocks the main thread** until the whole batch
completes, so the worst frame ≈ the slowest single tile, not the batch average; (2) side
faces are **50% of the sweep's total CPU** (profile: sides 50%, surface_loop 44%, merge 6%,
mesh ~0%) — the exact hotspot doc 07 named and deferred ("side-face greedy merge"). Against
the §5 target (no frame > 16 ms per step) we sit at 64 ms debug ≈ **~28 ms release** —
above target.

**Secondary, stacking cost:** with the mining tool active, `_rebuild_terrain_grid` runs
synchronously on the same frame as a slice step (unthrottled full-radius column loop,
main-thread; predates Phase 2b — 2b only added cheap per-column lookups). SliceTiming does
not measure it.

**RELEASE MEASUREMENT — 2026-06-05 (export, console wrapper, second run):** ±1 steps at
Y54–56: worst frame **24–27 ms**, slowest tile 14–16 ms, sweep 0.72–0.83 s (294–345 tiles);
toggle off (54 → 127) worst frame 36 ms (corner tile back to 25.8 ms — full-depth edge
walls). The 2.3× debug→release rule held (64 → 27 ms). Verdict: still above the §5 16 ms
target (1 dropped frame at 60 Hz). Notably the worst frame is ~2× the slowest tile — the
8-tile batch doesn't fit the core count in one wave — which strengthens lever 2. Startup
re-confirmed the doc-07 baseline (5.3 s interactive, 8.9 s full overview).

**DECISION (Alen, 2026-06-05): performance accepted — levers SHELVED.** 24–27 ms release
feels fine in play; per the doc-07 rule ("do this only if the hitch is actually noticeable
in a release playtest") no optimization work is taken. The §5 16 ms target row stands as
aspiration, not a blocker. Revisit only if a future change makes slice stepping feel worse
in release; the levers below are the pre-ranked starting points for that day.

**Levers, in recommended order (shelved):**

1. **Side-face greedy merge** (doc 07's named lever) — merging coplanar same-colour cliff
   quads attacks the 50% directly and shrinks the corner tile's 39 ms.
2. **Non-blocking batch collection** — dispatch the group task, poll
   `is_group_task_completed()` and assign finished meshes next frame instead of
   `wait_for_group_task_completion()`. Worst frame becomes assignment-only; sweep latency
   unchanged. Removes the slowest-tile bound entirely.
3. **Mining-grid debounce + threading** — defer the grid rebuild until the plane settles
   (~0.15 s), and/or build its line geometry on a worker (all reads are thread-safe).
   Fixes the stacking cost only.
4. **World-edge presentation slab** (Second Milestone, doc 24) — eventually removes the
   corner-tile edge-wall pathology at the source.

### <span style="color:#3fb950;">Phase 2b — Mining grid on the cut floor (added 2026-06-05)</span>

**Observed during Phase 2 verification (Alen):** sliced to Y64 with the precision mining tool
active, the black alignment grid is not painted on the plane-cut interior blocks — the cut
floor where the player most wants to lay out mining queues has no grid at all. Cause, in
`MiningDesignationController._rebuild_terrain_grid()`:

```gdscript
var top_y := int(WorldGenerator.get_visible_surface_y(x, z))
if top_y < 0 or top_y > slice_y:
    continue          # ← any column whose NATURAL surface is above the plane is skipped
```

The grid derives from the *natural* terrain surface, so a column cut by the plane is dropped
entirely instead of gridded at its cut top; the side-face grid inherits the same blindness via
`neighbor_top`. Designation itself already works there (the DDA raycast is slice-aware and
reads generated block ids) — the gap is the grid overlay only, which makes laying out queues
on a cut floor needlessly hard.

**Plan (mirror the overview's visible-surface math):**

1. Effective top per column = `min(get_visible_surface_y(x, z), slice_y)` — the same rule
   `_overview_visible_surface_after_cut()` applies, including stepping down past visual-cut
   blocks (existing zone cuts lower the effective top exactly as they do for the overview).
2. Emit the top-face grid at the effective top — cut floors at `slice_y` get gridded like any
   natural surface.
3. Side-face grid spans between *effective* neighbour tops (both clamped by the plane), so cut
   walls grid correctly from the cut lip down.
4. Concealment-safe by construction: the grid is line geometry only; it paints no block
   identity (Hard Rule 11 untouched).
5. Cost: same column loop, one extra `mini()` + cut-set lookup per column; the existing
   rebuild-cell / radius throttle already bounds it.

**Sequencing:** can ship before Phase 3 as a local fix (the controller already reads
`slice_y` every rebuild). When Phase 3 lands, the grid simply swaps its per-frame `slice_y`
read for the `visible_volume_changed` rebuild trigger — the effective-top math is identical.

Acceptance criteria:

- With the slice active, the alignment grid covers plane-cut floors at `slice_y` and the side
  grid hangs from cut tops; nothing grids above the plane.
- Grid respects existing visual-cut zones (no grid floating over already-designated cavities).
- No change to selection/raycast behaviour; no block identity revealed.
- Grid rebuild cost stays within the current per-cell throttle (no per-frame full rebuilds).

#### <span style="color:#3fb950;">Phase 2b RESULTS — 2026-06-05, verified in-engine by Alen — PHASE 2b BANKED</span>

Implemented same-day, in `MiningDesignationController.gd` only:

- `_effective_grid_top(x, z, slice_y)` — natural visible surface clamped to the plane, then
  stepped down past designated cut blocks via `_zone_by_block` (the controller's own
  designation set; no renderer query needed — it is the same data the renderer's
  `_visual_cut_blocks` mirrors).
- Column loop and `_append_visible_side_grid` neighbour math both use it; the old
  `top_y > slice_y → skip` is gone. Equal cut tops (flat cut floor) emit no side faces.
- Zone confirm / remove / Ctrl-subtract force a grid rebuild (guarded to active-tool state),
  so cavities re-grid immediately in both directions.

**Verified:** grid covers plane-cut floors at `slice_y`, side grid hangs from cut lips,
nothing grids above the plane, grid re-flows around confirmed zones and restores on removal;
selection/raycast unchanged.

**Noted, by design:** the designation ray still hits visually-cut blocks (confirmed zones
must stay clickable), so the gridded cavity floor cannot be designated where a zone occupies
the blocks above. Revisit when real mining execution replaces visual cuts.

**Performance:** the slice-step grid rebuild remains synchronous/unthrottled (predates 2b;
2b added only cheap per-column lookups) — tracked with the overview-step cost in the open
performance note above (lever 3: debounce + thread).

### <span style="color:#3fb950;">Phase 3 — The VisibleVolume contract (S5)</span>

New lightweight helper owned by `WorldRenderer` (no new autoload — render concern):

```gdscript
# Conceptual API
func is_block_visible(pos: Vector3i) -> bool        # slice plane + (later) xray set
func filter_blocks(blocks: Array[Vector3i]) -> Array[Vector3i]
func clip_aabb(aabb: AABB) -> AABB                   # slice plane only (cheap path)
signal visible_volume_changed                        # emitted at most once per frame
```

Consumers, in order:

1. **MiningDesignationController** — zone fills, exterior lines, previews, and the terrain grid
   clip to the visible volume and rebuild on `visible_volume_changed` (instead of every slice
   change individually). The grid already reads `slice_y`; this unifies it.

   > <span style="color:#3fb950;">**Decision (Alen, 2026-06-05, during Phase 2 verification):**</span>
   > a mining zone above the slice plane currently keeps drawing its yellow overlay, floating
   > over the cut (the block-inspector outline does the same). Cosmetic only — the designation
   > raycast already respects `slice_y`, so hidden rock cannot be *selected*. When this phase
   > lands, resolve it by clipping: **zones fully above the plane disappear (Stonehearth's
   > choice — the overlay never paints inside hidden rock)**, rather than rendering a faint
   > ghost. If a reminder of off-slice designations turns out to be wanted, fold it into the
   > doc-05 layered-overlay readability pass (low-alpha no-depth full volume + stronger
   > depth-tested exposed subset), not into this contract.
2. **Water rendering** (future CA work, doc 33) — lake/tarn surfaces clip the same way
   Stonehearth's water renderer does.
3. **Entities** (future) — §3.5.

The one-per-frame rule is mandatory: any state change sets a dirty flag; `_process` flushes it
once. No consumer may poll.

#### <span style="color:#3fb950;">Phase 3 RESULTS — 2026-06-05, verified in-engine by Alen — PHASE 3 BANKED</span>

Implemented as API on `WorldRenderer` directly (no separate class — consumers already hold a
renderer reference): `is_block_visible()`, `filter_blocks()` (slice-off fast path),
`clip_aabb()`, and `visible_volume_changed` — dirty flag set in the `slice_y` setter, flushed
at most once per frame at the top of `_process`, before either render branch.

First consumer, `MiningDesignationController`:

- `_visible_in_slice()` routes through `is_block_visible` — the raycast became
  contract-correct for free; the future x-ray set composes in with zero controller changes.
- Zone fills + exterior lines clip per zone; a zone fully above the plane **disappears**
  (per the Phase 3 decision note — data untouched, restores when the plane rises); a
  partially-cut zone closes its outline at the plane.
- **Designation is clipped, not just display (WYSIWYG):** `_filter_mineable_blocks` excludes
  above-plane blocks, so confirm designates exactly what the preview shows — Stonehearth's
  marquee behaviour (ref doc §2.5). The preview meshes clip identically.
- Zones, grid, and hover preview rebuild on `visible_volume_changed` (zones even while the
  tool is inactive); existing rebuild-cache keys prevent same-frame duplicates.

**Verified:** zone above plane vanishes/restores across steps with data intact; mid-zone cut
closes flat at the plane; preview never paints above the plane and confirm matches it;
inactive-tool zones still re-clip; slice off (Y127) identical to pre-Phase-3 behaviour.

**Decision (Alen):** a hidden zone's info window staying open is acceptable — left as-is.

**Surfaced during verification:** lateral cavities are invisible until top-exposed — a
pre-existing renderer property, recorded with disposition in the Phase SO section above.

### <span style="color:#3fb950;">Phase SO — SLICED OVERVIEW (added 2026-06-04, supersedes the old Phase 4)</span>

**Why (Alen's verdict on Phase 1):** Stonehearth never changes *what world you see* — the whole
map stays present and the plane removes geometry above it. Deepdraft's slice swapped to a local
streamed bubble because the full-map representation (block-face overview) was surface-only. The
mode swap, not the bubble's quality, is the parity gap. Decision: make the overview slice-aware
BEFORE building the Phase-2 tool.

**Design:**

1. **Slice-aware overview columns (SO-1).** A column whose visible surface is above the plane
   renders its cut floor at `slice_y`, coloured by `get_overview_strata_block_id` (thread-safe,
   vein-concealed, cave-less — the approximation stays geometric per doc 24 mode 2; exact caves
   and veins appear in the near streamed terrain). Neighbour-top math clamps the same way so
   boundary walls hang from the cut, not from the world bottom. Existing greedy top-merge makes
   deep-cut tiles nearly free geometry (one strata colour per Y band merges into large plates).
2. **Per-tile invalidation (SO-1).** WorldGenerator precomputes per-32×32-tile min/max visible
   height on the generator thread (gated like the grass bands; conservative all-tiles fallback
   until ready). A slice change rebuilds only tiles with `max_h > min(old, new)` plus their
   4-neighbours (border walls read neighbour tops). Lowland tiles never rebuild.
3. ~~**Compositing (SO-2).**~~ <span style="color:#f85149;">**BUILT, THEN REVERTED (2026-06-04).**</span>
   The "exact streamed bubble near the camera" showed real veins/caves on the cut floor —
   violating the design rule below. It also produced two hole-punching bugs (full-tile coverage
   over circularly-clipped partial region meshes) before the design conflict was recognised.
   Consolidated outcome: **the sliced overview IS the slice view at every depth.** The streamed
   chunk path is dormant (`set_overview_enabled(false)` only), reserved for a future
   true-3D-interior need (side views into roofed tunnels). The waterline-aware neighbour-top fix
   from this detour is kept — it removed a pre-existing ~127k-vert / 843 ms water-wall pathology
   per water tile.

   > <span style="color:#3fb950;">**DESIGN RULE (Alen): slicing must never reveal undiscovered
   > resources.** Cut floors show authored strata only — everywhere, at every zoom. Veins, gems,
   > and caves become visible exclusively through mining. Candidate for AGENT.md Hard Rules when
   > this ships.</span>

#### <span style="color:#3fb950;">CONSOLIDATED STATE — 2026-06-04, verified in-engine ("back to good")</span>

**The sliced overview is THE slice view.** `WorldRenderer.slice_y` cuts the whole map at any
depth with no mode switch, no streamed bubble, no resource reveal. Verified numbers (editor/debug,
seed 1956482717):

| Metric | Value |
|---|---|
| Slice 127 → 60 (278 tiles) | 1.54 s, worst frame **61 ms** |
| Step 59 → 60 | 1.55 s, worst frame 60 ms |
| Full overview build | 22.5 s (was 26.5 s — waterline fix cut total side faces 587k → **98.6k**) |
| Pure-overview slice steps | center-first sweep; lowland tiles untouched by mountain-depth planes |

**What ships from this arc:** Phase 1a–e (mesher slice clip — dormant with the streamed path but
correct and future-needed; localized invalidation; threaded region batches; ChunkMesher LUT fast
path; streaming rebuild defer), SO-1 (slice-aware overview + per-tile invalidation + tile-range
cache + strata-only floors + center-first ordering), the waterline neighbour-top fix, and the
slice timing instrumentation. The streamed chunk path is dormant behind `set_overview_enabled`.

**Phase 2 (the Slice tool) is now simpler than planned:** the dock window's ▲ / `Y = N` / ▼
just steps `WorldRenderer.slice_y` — no mode management, no streaming pre-warm, no
`set_overview_enabled` calls. §3 Phase 2's streamed-mode choreography and §Phase 4 are obsolete.
Seeding, clamps [4, 127], and mutual exclusion with the future X-Ray tool still apply.

#### <span style="color:#d29922;">Known renderer property — lateral cavities are invisible until top-exposed (observed 2026-06-05, accepted)</span>

**Observation (Alen, during Phase 3 verification; present since the Phase SO consolidation,
not a 2b/3 regression):** a designated block visually deducts from the terrain ONLY when it
is its column's visible top — exposed naturally at the surface, or made the top block by the
slice plane. A zone cut sideways into a vertical wall face shows its overlay box, but the
rock face stays solid; step the plane down so the designated blocks become the cut top and
the cavity appears. (Reproduced with a 2-block zone in a shelf wall at Y81: intact at
slice 81, deducted at slice 80.)

**Cause — representational, not a bug:** the block-face overview is a per-column top
renderer. `_overview_visible_surface_after_cut()` lowers a column's top through cut blocks,
and walls are side bands hung between neighbouring tops. A cavity that changes no column top
produces zero geometry — lateral holes and tunnel mouths *cannot exist* in this
representation. This is precisely the "true-3D-interior need (side views into roofed
tunnels)" the dormant streamed-chunk path is reserved for (`set_overview_enabled(false)`;
`ChunkMesher` already meshes cut cavities correctly in 3D — `24_world_rendering.md` mode 2).

**Forward note:** real mining execution will hit the same property — an actually-mined
lateral tunnel will not render in the overview either. When tunnels become diggable, the
interior view needs the streamed path composited near the camera, X-Ray, or both.
<span style="color:#3fb950;">**Superseded same day:** the DEV instant-mine tool (doc 03)
created a real producer of mined holes, which unblocked the targeted fix — see
Phase SO-2b below.</span>

### <span style="color:#3fb950;">Phase SO-2b — Mined-cavity rendering in the overview (planned 2026-06-05)</span>

**Why now:** the plan deferred cavity rendering because X-Ray's data source — *mined interior
space* (X2) — had no producer. The DEV instant-mine tool is now a producer: it creates
genuinely mined holes, not designation plans. With the sequencing blocker gone, the lateral
invisibility above becomes targetable without the failed SO-2 compositing: the overview keeps
its per-column-top representation, and mined cavities are expressed by two additive
mechanisms.

**Design decision (foundational):** **designations and mined blocks become separate sets in
the renderer.** Designations are plans, not holes — they keep exactly the current behaviour
(top-deduction only; no wall punching, no shell, no vein reveal). Only MINED blocks get the
new treatment. Mined ⊂ cuts: every mined block stays in the visual-cut set (top-walk
deduction unchanged); the new `_mined_blocks` set additionally drives the two mechanisms
below. Concealment (Hard Rule 11) is honoured by construction: faces exposed by the shell
were *mined open* — "veins, gems, and caves become visible exclusively through mining" is
this exact case.

**Mechanism 1 — cut-aware side bands (the hole mouth).** The overview's wall faces are
colour-run bands emitted per column Y-walk (`_add_overview_side_column`). The wall face at
height y belongs to block `(sample_x, y, sample_z)`; if that block is mined, the run ends
before it and restarts after — punching an exact block-sized hole in the cliff face. Cost
lands only on tiles containing mined wall blocks; the existing mining-edit tile invalidation
(changed blocks + XZ neighbours) already dirties the right tiles. The no-mined fast path is a
single empty-dict check.

**Mechanism 2 — the cavity shell (the tunnel interior).** A dedicated mesh renders, for each
mined block, the faces of its adjacent SOLID blocks (floor, ceiling, back walls), coloured by
their TRUE generated block ids — veins show, legitimately. Skips: mined neighbours (open
continuation), out-of-bounds (world edge), neighbours above the slice plane (the black void
reads as rock), and generated-void neighbours (natural cave adjacency — the cave interior
stays unrendered for now; discovery rendering is its own future decision). This builder is
X-Ray full-mode's geometry (X1: interior inflated +1 XZ, floor −1 Y) built early against the
DEV mined set — Phase X1 inherits a field-tested mesher, and real mining execution later
plugs into a renderer that already works.

**Implementation shape:** single `MeshInstance3D` shell node, full rebuild on mined-set
changes, the once-per-frame visible-volume flush (slice clipping), and season change —
trivially cheap at DEV scale (mined count × ≤6 faces). Scale path when real mining lands:
per-chunk shell nodes fed by X0's 3×3×3 dirty rule.

**Out of scope, recorded:** designation cut floors keep today's exact-block lookup when a
designation lowers a column top below the plane (pre-existing behaviour); whether they should
become strata-only under the set split is a separate decision for the mining-execution pass.

Acceptance criteria:

- A laterally DEV-mined block opens a visible hole in the cliff face; the cavity interior
  (floor/ceiling/back walls) renders in true block colours; tunnels deepen visibly block by
  block.
- Designations are visually unchanged from today (no punch, no shell, no reveal).
- Slice composes: cavities above the plane vanish; the shell never draws faces above it.
- Season changes recolour the shell with everything else.
- No-mined-blocks worlds pay one dictionary check per side column; tile rebuild cost
  otherwise unchanged.

#### <span style="color:#f85149;">Defect 1 — first build, 2026-06-05: z-fighting noise on open-pit walls</span>

**Observed (Alen):** camera movement over a dug-out open trench shows shifting mottled noise
on the trench walls; the opposite wall is clean.

**Diagnosis:** duplicate coplanar geometry. An open-from-above excavation is ALREADY fully
expressed by the overview (cut-walk lowers the column tops; the trench walls are ordinary
side bands, strata-only). The first shell build also emitted faces for those same walls in
EXACT colours — two quads on one plane, strata vs vein-speckled, z-fighting. The speckles
ARE the ore veins flickering through.

**Fix rule:** the shell renders ONLY enclosed cavities — mined blocks *below* their column's
cut-aware effective top (a solid roof above). Open-from-above mined blocks are the overview's
job exclusively; the shell skips every face around them. Side-band punching is unaffected
(it is a natural no-op on open walls and only bites at genuine tunnel mouths).

**Recorded design wrinkle (interim, deliberate):** with the fix, open-pit walls render
strata-only — concealed — even though mining exposed them. Concealment-SAFE but
under-revealing versus the rule's spirit. The honest future fix is an exposure-aware side
colour path (the band knows which faces were mined open); separate decision, not this pass.

#### <span style="color:#f85149;">Defect 2 — first build, 2026-06-05: designations still don't deduct laterally</span>

**Observed (Alen):** a zone designated into a cliff face (64 blocks, side-exposed) does not
visually deduct, while the same designation on a plateau top would. Not new behaviour — it is
the original lateral-invisibility property applied to designations, which the SO-2b set split
deliberately excluded from punch/shell ("plans ≠ holes"). SO-2b made the asymmetry
conspicuous: mined holes now render laterally, plans don't.

**Resolution options:**

- **A — extend cut visuals to designations, strata-only (recommended):** designated blocks
  also punch side bands and render shell interiors, coloured via
  `get_overview_strata_block_id` (never exact — a plan reveals nothing). Reads as a ghost
  preview of the dig under the yellow overlay; mined interiors keep exact colours. Composes
  with Defect 1's enclosed-only rule into ONE shell pass over cuts ∪ mined with per-source
  colouring (each shell face borders exactly one cavity block: mined → exact, designated →
  strata).
- **B — accept:** plans deduct from the top only; overlay-only from the side.

**Uniform rule if A is taken:** *a designated or mined block never renders as rock* —
top-walk, side punch, and shell all derive from the cut set; only the shell's colour source
distinguishes plan from hole.

> <span style="color:#3fb950;">**Decision: Option A taken (Alen, 2026-06-05).** Implemented
> same day together with Defect 1's enclosed-only rule — one shell pass over the cut set,
> per-source colouring.</span>

#### <span style="color:#f85149;">Defect 3 — 2026-06-05: designation cut floor reveals exact resources (CONCEALMENT)</span>

**Observed (Alen):** designating a 1-layer zone on a plateau top immediately renders the cut
floor beneath it in EXACT generated colours — a copper vein glows under what is only a plan.

**Mechanism:** `_overview_visible_surface_after_cut()` knows only two cases — slice-cut top
(strata) vs cut-lowered top (`get_generated_block_id`, exact). It cannot tell whether the
blocks removed above were MINED or merely DESIGNATED, so a plan earns mining's reveal. This
was parked in the SO-2b plan as "out of scope, recorded"; under Option A's uniform rule it is
a concealment bug (Hard Rule 11 violated in spirit through the floor path, exactly as the
old SO-1 vein-speckled cut floors violated it through the slice path).

**Fix rule (agreed, not yet implemented):** the cut-floor colour source depends on the
SOURCE of the removed blocks above — walk lowered by mined blocks only → exact (mining
reveals what it exposes); walk containing ANY designated-only block → strata (plans reveal
nothing; conservative on mixed runs until fully mined). Self-healing: DEV-mining the zone
later flips its floor from strata to exact at that moment — the reveal working as intended.

#### <span style="color:#f85149;">Defect 4 — 2026-06-05: designation as free prospecting scanner (CONCEALMENT, exploit framing)</span>

**Observed (Alen):** dug a real tunnel first — it legitimately showed only rock. One fresh
1-layer designation beside it instantly painted the entire copper field below: information
the honest dig had rightly NOT granted. Designate → read the floor → remove the zone →
designate elsewhere = full vein prospecting with zero mining.

**Root:** identical to Defect 3 — this entry records the gameplay consequence so the fix is
judged against it: after the Defect-3 rule, a designation must show a strata floor
indistinguishable from undisturbed rock, and discovery must require actual mining
(adjacent honest reveals — like the tunnel's own exact floor strip — remain correct).

> <span style="color:#3fb950;">**Defects 3/4 fix implemented 2026-06-05** (source-aware
> cut-floor colouring: exact only when the entire cut run above was mined; `_ovt_mined`
> snapshot restored for worker threads). Verified by Alen: designation floors conceal; mined
> floors reveal.</span>

#### <span style="color:#f85149;">Defect 5 — 2026-06-05: mined-open WALLS under-reveal (they lie)</span>

**Observed (Alen):** mined a pocket inside the mountain — pit walls rendered plain strata.
Mined one more layer off a wall: copper appeared exactly where that wall face had been —
the wall had been copper-bearing rock painted as plain stone. Mining exposed those faces;
they should have told the truth.

**Mechanism:** pit walls are overview side bands, and `_overview_side_color_at()` is
strata-only BY DESIGN (vein concealment for natural cliffs, `24_world_rendering.md`). It
cannot distinguish a mined-open face from a virgin cliff face. This was recorded as the
deliberate interim wrinkle in Defect 1's fix; these screenshots show it is not acceptable —
discovery feedback is the point of digging. (The defect-1 z-fight speckles were this truth
leaking through the old duplicate shell face: the duplicate was removed, the lying band kept.)

**Fix rule — exposure-source-aware wall colouring (symmetric twin of the Defect-3 floor
rule):** per wall-block face in the side walk, if the adjacent air block in the FACING
neighbour column at that Y is in the MINED set → exact generated colour (mining reveals what
it exposes); otherwise → strata (natural, slice, and designation exposure all stay
concealed). Side walk gains the facing-neighbour column; cost is one dict lookup per Y only
while mined blocks exist.

**Unified principle (write into doc 24 when this lands):** *a face renders exact colours iff
the air it faces was created by mining; every other face renders authored data* — floors
(Defect 3), walls (this defect), and the cavity shell all derive from this one rule.

#### <span style="color:#3fb950;">Phase SO-2b RESULTS — 2026-06-05, verified in-engine by Alen — SO-2b BANKED</span>

**Shipped (WorldRenderer + MiningDesignationController):**

- Designation/mined set split: `_mined_blocks` ⊂ `_visual_cut_blocks`, `_ovt_mined` worker
  snapshot, `add_mined_blocks()` API fed by the DEV instant-mine tool.
- Side-band punching for ALL cut blocks (Option A — plans and holes both open wall faces;
  run-splitting in `_add_overview_side_column`).
- Cavity shell (`_rebuild_cavity_shell`): enclosed-only cavity interiors, per-source
  colouring, slice-clipped, season-aware; single node, full rebuild (scale path: per-chunk
  nodes with X0's 3×3×3 dirty rule when real mining lands).
- Source-aware cut floors (exact only when the whole cut run above was mined).
- Exposure-aware walls (exact only where the facing air block was mined open) — the side
  walk gained its facing-neighbour column; strata fast path intact for clean worlds.

**Defect arc, all closed same day:** 1 (z-fighting → enclosed-only shell), 2 (lateral plan
deduction → Option A), 3/4 (designation floor reveal / prospecting exploit → source-aware
floors), 5 (mined walls lying → exposure-aware walls). Each entry above carries its own
diagnosis and fix rule; the **unified exposure principle** is now normative in
`24_world_rendering.md` §Slice concealment rule.

**Verified in-engine:** lateral tunnels render with mouth, interior, floor/ceiling; trench
walls clean (no z-fighting); designations conceal everywhere (floor strata, ghost interior,
no vein reveal — prospecting exploit dead); mined floors and walls tell the truth (jade/
cave-soil visible on honestly-exposed faces); natural cliffs unchanged.

**Known limits, recorded:** lateral cavities in the overview render via punch+shell — the
representation is still per-column-top, so fully roofed interiors are visible only where
punched mouths or the slice expose them (X-Ray remains the interior *vision* answer);
exposure state is session-only until the save system; shell is one full-rebuild node
(fine at DEV scale).

### <span style="color:#3fb950;">Phase SO-2c — Slice-cut face dimming (planned 2026-06-05, Stonehearth-verified)</span>

**Feature request (Alen, from Stonehearth screenshot):** sliced surfaces should read clearly
darker than real surfaces, so the cut plane is never mistaken for walkable ground.

**Stonehearth source findings (read from `P:\stonehearth` 2026-06-05):** their darkening is
NOT a slice feature — it is the fog-of-war/visibility system, which the slice merely exposes:

- A global `FogOfWarRT` is written from the visibility regions each frame: the VISIBLE
  region via `data/horde/materials/fow_visible.material.json` (flat-colour shader), the
  EXPLORED region via `fow_explored.material.json`, over a dark base — the RT's alpha
  encodes seen-state (visible 1.0, explored mid, unexplored near-black).
- Every terrain lighting shader multiplies it in:
  `lightColor *= texture2D(fowRT, projFowPos.xy).a` (`dir_lighting_f.shader` family), bound
  in `forward.pipeline.xml`'s Light stage. The screenshot's brightness follows hearthling
  SIGHT RADIUS, not the slice plane.
- Precedent factor: the `*_darkened` shader variants (building vision mode) use a flat
  `albedo = color.rgb * 0.5` — Stonehearth's number for de-emphasized geometry is 50%.

**Deepdraft plan (pre-FOW interim, honest about it):** the full equivalent is visibility
regions + fog of war (doc 06, Later Phase 1 — needs sight sources, i.e. dwarves). Until
then, a cheap presentation rule delivers the readability win:

1. Dim SLICE-CUT strata floors by a fixed luminance factor (start at Stonehearth's 0.5;
   tune in-engine). Applied at colour-bake time in `_overview_visible_surface_after_cut`'s
   slice-cut path — zero per-frame cost, re-baked by the existing slice invalidation.
2. <span style="color:#d29922;">Tune-in-engine decisions: do designation ghost floors and
   the cavity shell's strata faces share the dim (consistent "not really open" language),
   or stay full-bright? Do slice-clamped wall bands above the cut dim too? Decide by look.</span>
3. Luminance-only — block identity untouched (Hard Rule 9; same argument as Phase 1's
   cut-face brightening note, inverted).
4. **Forward note:** when FOW lands (post-dwarves), this constant folds into the visibility
   multiply exactly as Stonehearth does it (their slice has no dimming of its own), and the
   interim rule is deleted.

Acceptance: a slice-cut plateau is instantly distinguishable from natural ground at any
zoom; toggling slice off restores full brightness; no identity/colour-hue change, only
luminance; no measurable cost on the slice-step budget.

#### <span style="color:#3fb950;">Phase SO-2c RESULTS — 2026-06-05, verified in-engine by Alen — SO-2c BANKED</span>

Implemented same day: `SLICE_CUT_DIM = 0.5` applied at colour-bake time in the overview tile
build (the `slice_cut` flag rides out of `_overview_visible_surface_after_cut`); greedy
top-merge gained a sliced-flag guard so dimmed cut plates never fuse with natural plates of
the same block at the same height. **Pass at 0.5** — cut planes read as "inside the
mountain" at any zoom; slice off restores full brightness; zero budget impact (bake-time
multiply, re-baked by the existing slice invalidation).

Defaults shipped for the open look-decisions: designation ghost floors and cavity-shell
strata faces stay FULL-BRIGHT (only the plane's own cut floors dim). Revisit only if they
read wrong in play. Forward note stands: this constant folds into the fog-of-war multiply
when visibility regions land (doc 06), exactly as Stonehearth does it.
4. **Measure (SO-3).** Phase-0-style: slice-step tile rebuild counts + worst frame, full-map
   plane drag, verify lowland tiles stay untouched. Known risk: a deep plane step touches every
   mountain tile (~300); if the threaded 8-tile/frame budget janks, add the flat-plate fast path
   (tiles fully below the plane emit one merged plate + edge walls without per-column sampling).

#### <span style="color:#3fb950;">SO-1 RESULTS — 2026-06-04 (exact-vein cut floors, first iteration)</span>

Verified working in-engine via `overview_slice_threshold = 0` — full map present and cut at any
depth ("a huge step in the right direction" — Alen). Measured (editor/debug):

| Step | Tiles | Total | Worst frame |
|---|---|---|---|
| 127 → 60 | 291 | 3.0 s | 700 ms |
| 60 ↔ 59 | 291 | 3.3 s | 705 ms |
| 60 → 30 | 601 | 5.3 s | 405 ms |
| 30 → 15 | 1024 | 10.6 s | 462 ms |

**Cost driver identified:** vein/gem speckles on cut floors fragment the greedy top-merge
(hundreds of small rects per tile instead of a few plates) and balloon mesh uploads.

**Decision (Alen):** STRATA-ONLY far-field cut floors — veins/gems/caves appear only in the
exact streamed terrain near the camera (SO-2). Doubles as the design answer to instant full-map
prospecting: discovery requires going there. Plus center-first sweep ordering (fills outward
from the camera). Re-measure before SO-2.

#### <span style="color:#3fb950;">SO-1 FINAL — 2026-06-04 (strata-only floors + center-first + fixed frame stamps)</span>

| Step | Tiles | Total | Worst frame |
|---|---|---|---|
| 127 → 60 | 295 | **1.61 s** | **57 ms** |
| 60 → 59 | 295 | **1.65 s** | **56 ms** |

Profile (295 tiles): surface_loop 46%, sides 48%, top_merge 6%, **mesh_create ~0%** — the earlier
~650 ms worst frames were the vein-speckled mesh uploads; with strata plates, uploads vanish.
Slowest tile 34 ms (world-corner tile, deep edge walls). Release estimate: ~25 ms worst frame,
~0.7 s sweep. Flat-plate fast path stays in the back pocket; not currently needed. Visuals
verified in-engine: terraces, soil bands, tarn water plane in the cut — the Stonehearth model.

### <span style="color:#d29922;">Phase 4 (old) — Overview interplay — superseded by Phase SO</span>

Current behaviour (slice ≥ 96 → block-face overview; below → streamed chunks) is kept, with two
deliberate adjustments:

1. Activating the Slice tool while in overview mode **drops to streamed mode** by definition
   (slice below threshold). The first activation therefore pays the stream-in cost for the
   camera radius. Budget it: center-first column requests already exist; measure in Phase 0
   whether a one-time "stream before slice descends" pre-warm is needed.
2. Hide overview tile nodes instantly on slice activation (visibility flip), never free them —
   returning to surface view must be free (nodes re-shown, no rebuild).

### Phase 5 — Entities & forward hooks <span style="color:#f85149;">(deferred until dwarves exist)</span>

Record the rules now, implement with `DwarfAgent`:

- Entity visible iff `grid_pos.y <= slice_y` (S6), with the standing-on-visible-support
  exception once placed entities/furniture exist.
- Implementation: `visible` flag on the agent's render root, recomputed on
  `visible_volume_changed` + on the agent's own grid-cell change *only while a mode is active*.
- `clip_mode: custom` escape hatch for special entities (S6 exception), as entity data.

---

## 4. X-RAY — implementation phases

<span style="color:#f85149;">**Sequencing reality:** X-ray's data source is mined interior
space (X2). Real mining execution does not exist yet. Build slice first; build the interior
tracker INTO mining execution when that system lands; x-ray rendering then consumes it. An
interim x-ray over designation cuts is explicitly rejected — designations are *plans*, not
holes; an x-ray of plans would lie to the player.</span>

### <span style="color:#3fb950;">Phase X0 — Interior region tracker (build with mining execution)</span>

Owned by the future mining system (the producer), exposed read-only to the renderer:

- `INTERIOR_HEIGHT = 4` — one dig cell, matches our Y cell and covers the 3-block nav
  clearance envelope + floor (Stonehearth's 5 maps to their cell of 5; ours is 4).
- On block removed: compute the interior column above the removed block (air upward until
  terrain, capped at 4); add to the per-chunk interior set; mark the chunk + its 3×3×3 chunk
  neighbourhood x-ray-dirty (X3 — shell inflation crosses chunk borders).
- On block placed: subtract the placed region extruded up 4; recompute interior columns for
  remaining mined points in the dirtied volume (X2).
- Natural caves: when cave voids become reachable/mined-into, their air joins the interior set
  through the same column rule — no special path.
  <span style="color:#d29922;">Open question: should *unbreached* natural caves show in x-ray?
  Stonehearth's ore-vein caves do. Recommendation: NO for Deepdraft — undiscovered caves are
  exploration content; x-ray must not be a prospecting tool. Revisit with the discovery
  system.</span>
- Deterministic and save-friendly: the interior set is derivable from the mined set; persist
  the mined region only, rebuild interiors on load.

### <span style="color:#3fb950;">Phase X1 — X-ray render mode</span>

A third render path in `WorldRenderer`, alongside streamed regions and the overview:

1. When x-ray is active: hide region/chunk/overview nodes (visibility flips), show per-chunk
   **x-ray meshes** built from the interior shell:
   - **`full` (X1):** emit every solid block face adjacent to interior air, plus the floor
     block under each interior column — i.e. interior cubes inflated +1 X/Z, floor −1 Y; render
     those *solid blocks'* faces with their true block colours (ore veins in your walls show —
     they are exposed, this is data-honest).
   - **`flat` (X1):** floor blocks only, where headroom ≥ 3 (our nav clearance, not
     Stonehearth's 4) — the readable floor-plan view.
2. **Floor anchor (X4):** always render a flat slab at bedrock top (Y3 top faces, the world
   footprint) so the map silhouette and orientation survive. Cheap: one greedy-merged quad set,
   built once. <span style="color:#d29922;">Alternative if the full-map slab reads badly at
   navigation zoom: reuse the overview tiles dimmed/desaturated as the backdrop. Decide
   in-engine.</span>
3. Mesh build: same threaded worker batch as overview tiles (`_ovt_*` pattern); per-frame
   budget; chunk-granular dirty queue fed by X0's 3×3×3 dirtying.
4. Mode toggle = mark all interior chunks dirty once (X5), drain on budget — the only full
   rebuild, and it scales with *carved volume*, not world volume.

Acceptance criteria:

- Toggling x-ray on a colony with N carved chunks rebuilds exactly those chunks + neighbours;
  zero work for the untouched world.
- Mining one block while x-ray is active updates ≤ 27 chunks' x-ray meshes within one frame's
  budget.
- Slice and x-ray never run simultaneously (S7).

### <span style="color:#3fb950;">Phase X2 — UX</span>

- Dock `xray` entry becomes the tool toggle; palette window offers `Full` / `Flat` (H2);
  hotkey `X` toggles, remembering the last mode (terrain_vision.js behaviour: re-toggle restores
  `_lastMode || 'full'`).
- Activating x-ray force-disables slice and vice versa (S7).
- Camera "home"/reset (if/when added) disables both (H3).

### Phase X3 — Consumers <span style="color:#f85149;">(with their systems)</span>

`VisibleVolume.is_block_visible` gains the interior-set test when x-ray is active (clip first,
then x-ray — same composition order as ref §1). Mining overlays, water, entities then respect
x-ray with zero additional code (they already consume the contract from Phase 3).

---

## 5. Performance guardrails (the "rock solid" checklist)

Non-negotiables, distilled from ref §2.8 / §3.5 and our own doc-04/07 lessons:

1. **No global invalidation on any slice/x-ray state change.** The only allowed full pass is
   x-ray mode toggle, and it is bounded by carved volume. (Doc-04's 15-second freeze came from
   exactly this mistake in mining cuts — do not repeat it.)
2. **Dirty sets are chunk/region-granular with explicit neighbourhood rules** (slice: old+new
   plane rows; x-ray: 3×3×3 chunks), deduplicated, drained on the existing per-frame budgets.
3. **One `visible_volume_changed` per frame, max.** Overlays rebuild reactively; nothing polls.
4. **Mesh builds off the main thread** where batch size > 1 (reuse the proven `_ovt_*`
   WorkerThreadPool pattern); main thread only assigns `ArrayMesh`es.
5. **Visibility flips are the first resort** (whole layers, overview nodes, x-ray mode swap);
   geometry rebuild is the last.
6. **Measure in release builds, before and after every phase** (doc-07 lesson — debug numbers
   lie by ~2.3×). Add slice-step timing to the `StartupPerformance`-style report behind a debug
   flag.
7. **Determinism:** sliced meshes are a pure function of (chunk data, cut set, slice_y, season).
   No randomness, no accumulated state.
8. **Hard rules honoured:** bedrock never exposed as void (floor clamp Y4); block colours always
   the block's own (cut-face brightening is luminance-only); terrain identity from data.

### Targets (validate in Phase 0, confirm at each phase)

| Action | Target |
|---|---|
| Single/cell slice step (streamed view, default radius) | New geometry visible ≤ 2 frames; no frame > 16 ms attributable to the step |
| Slice toggle on (from overview, cold streams) | First sliced view ≤ 1 s; camera interactive throughout |
| Slice toggle off | ≤ 2 frames (visibility flips + one row re-mesh) |
| X-ray toggle (mid-game colony) | Full carved-volume rebuild ≤ 0.5 s, budgeted across frames, no single-frame stall |
| Mining 1 block under x-ray | Update ≤ 1 frame budget |

---

## 6. Build order & file touch list

| Step | Files | Depends on |
|---|---|---|
| 0. Instrument slice-row rebuild timing | `WorldRenderer.gd` (debug flag) | — |
| 1. Mesher slice clip + dirty-row math | `ChunkMesher.gd`, `WorldRenderer.gd` | 0 |
| 2. Slice tool + palette + hotkeys + seeding | `DockUI.gd`, new `scripts/systems/SliceController.gd` (or fold into renderer), `data/ui/dock.json`, `project.godot` `[input]` <span style="color:#d29922;">(ownership note)</span> | 1 |
| 2b. Mining grid on the cut floor (effective-top math) | `MiningDesignationController.gd` | 2 |
| SO-2b. Mined-cavity rendering (set split, side punch, shell) | `WorldRenderer.gd`, `MiningDesignationController.gd` | DEV mine tool (doc 03) |
| SO-2c. Slice-cut face dimming (luminance, pre-FOW interim) | `WorldRenderer.gd` | SO-2b |
| 3. VisibleVolume contract + mining overlay clipping | `WorldRenderer.gd`, `MiningDesignationController.gd` | 1 |
| 4. Overview interplay polish | `WorldRenderer.gd` | 2 |
| X0. Interior tracker | future mining-execution system | mining execution |
| X1. X-ray render mode | `WorldRenderer.gd` (+ possible `XrayMesher` helper) | X0, 3 |
| X2. X-ray UX | `DockUI.gd`, `dock.json` | X1 |

Docs to update on completion: `21_camera.md` (slice section — manual-first, AUTO behind a
flag), `24_world_rendering.md` (slice render modes — block-granular clip note), `23_user_interface.md`
(dock entries become tools), `43_mining_materials.md` (interior region contract), `AGENT.md`
hard-rule cross-references if the `[input]` ownership note is accepted.

---

*Prev: [10_slice_xray_stonehearth_reference.md](./10_slice_xray_stonehearth_reference.md)*
