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
2. **Water rendering** (future CA work, doc 33) — lake/tarn surfaces clip the same way
   Stonehearth's water renderer does.
3. **Entities** (future) — §3.5.

The one-per-frame rule is mandatory: any state change sets a dirty flag; `_process` flushes it
once. No consumer may poll.

### <span style="color:#3fb950;">Phase 4 — Overview interplay</span>

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
