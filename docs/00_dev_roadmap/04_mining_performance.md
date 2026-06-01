# 04 - Mining Performance Plan

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = keep</span> |
> <span style="color:#d29922;">Yellow = review / move to a more specific plan</span> |
> <span style="color:#f85149;">Red = safe to delete or archive once you are comfortable</span>

## Document Review - 2026-06-01

This plan contains both completed mining performance work and remaining validation/polish items.
Keep the current architecture notes while they help explain the delta-rendering model. Review or
archive historical restore-state sections once the implementation has been fully validated in-game.

---

## <span style="color:#3fb950;">KEEP - Goal</span>

Keep the current Stonehearth-like mining designation behavior intact while making single-block
add/remove operations feel instant. The working behavior from `03_mining_plan` is now the baseline:
confirmed mining zones visually cut terrain, remain yellow/selectable, and can be removed.

The next step is performance only. Do not change mining UX, zone semantics, colors, or the current
visual deduction result while doing this pass.

## <span style="color:#d29922;">REVIEW / ARCHIVE LATER - Implementation Audit - 2026-06-01</span>

This document was re-audited after restoring a project backup, before the performance pass below was
re-implemented. At that restore point, the code was still mostly at the pre-performance state
described below. Some renderer infrastructure existed, but ordinary mining add/remove still used a
full visual-cut replacement and broad terrain invalidation.

### <span style="color:#3fb950;">KEEP / CONFIRMED - Implemented In Current Code</span>

- `ChunkMesher.build_mesh(chunk, cx, cy, cz, visual_cut_blocks)` accepts a cut-block mask.
- `ChunkMesher` skips mesh emission for blocks present in `visual_cut_blocks`.
- `ChunkMesher._neighbor_transparent()` treats cut neighbors as transparent, so cut cavities expose
  adjacent faces correctly.
- `MiningDesignationController` stores confirmed mining zones, supports zone removal and Ctrl
  subtract, rebuilds the yellow zone overlay, and calls the renderer after edits.
- `WorldRenderer` stores `_visual_cut_blocks` and passes that mask into `ChunkMesher`.
- `WorldRenderer` already has region mesh nodes, a dirty region queue, deduplication, per-frame
  rebuild budgets, and `_region_key(cx, cz)` / `_rebuild_region()` infrastructure for streamed
  rendering.
- `WorldRenderer` has a global block-face overview renderer that accounts for visual cuts through
  `_overview_visible_surface_after_cut()`.

### <span style="color:#d29922;">REVIEW - Outstanding / Not Implemented At Restore Point</span>

- No delta visual-cut APIs exist in `WorldRenderer`: `add_visual_cut_blocks()` and
  `remove_visual_cut_blocks()` are absent.
- `MiningDesignationController` still calls `_sync_visual_cut_blocks()` after add/remove/subtract.
  That method rebuilds a full dictionary by iterating every zone and every zone block, then calls
  `WorldRenderer.set_visual_cut_blocks()`.
- `WorldRenderer.set_visual_cut_blocks()` still replaces the whole mask and calls
  `_invalidate_visual_cut_meshes()`.
- `_invalidate_visual_cut_meshes()` still invalidates globally:
  - overview mode sets `_overview_built = false` and clears the single overview mesh;
  - streamed mode enqueues every existing region and then calls `_enqueue_visible_existing_chunks()`.
- The block-face overview is still one global `MeshInstance3D` (`_overview_node`), not tiled.
- No `_overview_tile_nodes`, `_dirty_overview_tiles`, or `_dirty_overview_tile_set` structures exist.
- Mining edits do not dirty only affected overview tiles or affected streamed regions.
- The old full overview rebuild path exists only implicitly through `_overview_built = false`; there
  is no clearly named global invalidation API.
- Lightweight mining-performance timing logs and before/after measurements are not present.
- `_rebuild_zones_mesh()` still rebuilds all confirmed zone geometry on each add/remove/select,
  which was acceptable for the first terrain pass but remains future work.

### <span style="color:#d29922;">REVIEW / ARCHIVE LATER - Restore-Point Current Status</span>

At the restore point, the visual-cut rendering behavior was present, but the performance work from
this plan was not complete. The likely freeze path still existed for overview-mode edits because a
single mining change could force `_build_block_face_overview()` to rescan the full `1024 x 1024`
surface grid.

## <span style="color:#3fb950;">KEEP - Performance Pass Update - 2026-06-01</span>

The code-level performance pass from this plan has now been implemented.

Implemented changes:

- `WorldRenderer` now exposes `add_visual_cut_blocks()` and `remove_visual_cut_blocks()` delta APIs.
- `MiningDesignationController` uses those delta APIs for normal zone confirm, zone removal, and
  Ctrl-subtract. `_sync_visual_cut_blocks()` remains only as a fallback/global sync path.
- Ordinary mining edits no longer call the broad `set_visual_cut_blocks()` replacement path.
- Streamed rendering invalidates only regions touched by changed cut blocks and their direct
  neighbor blocks, instead of enqueueing all existing/visible regions.
- Block-face overview rendering is split into `32 x 32` world-tile mesh nodes.
- Overview tiles are queued and rebuilt with a per-frame budget (`overview_tiles_per_frame`).
- Ordinary mining edits dirty only the overview tiles touched by changed columns plus the immediate
  X/Z neighbor columns needed for side-face correctness.
- The old full overview rebuild remains as `_invalidate_overview_global()` /
  `_queue_full_overview_rebuild()` for global events and fallback full sync.

Still outstanding:

- No explicit timing-log instrumentation was added.
- The `1x1x1`, `3x3x1`, and `4x4x4` cases still need interactive timing/feel validation in the
  running game.
- `_rebuild_zones_mesh()` still rebuilds all confirmed mining-zone overlay geometry. This is not the
  original terrain-freeze path, but remains future polish for very large numbers of zones.

## <span style="color:#d29922;">REVIEW / ARCHIVE LATER - Original Current Problem</span>

Designating or removing even a `1x1x1` mining zone can freeze the game for roughly 15 seconds.
The freeze is not caused by the one-block zone mesh itself. It comes from invalidating renderer
work at world scale.

Current flow:

1. `MiningDesignationController._sync_visual_cut_blocks()` rebuilds a full dictionary of all mining
   zone blocks.
2. `WorldRenderer.set_visual_cut_blocks()` replaces the renderer mask.
3. `WorldRenderer._invalidate_visual_cut_meshes()` invalidates too much:
   - In block-face overview mode, it marks the whole overview mesh dirty.
   - In streamed region mode, it enqueues every existing rendered region.
4. The next renderer update rebuilds large terrain meshes even when only one block changed.

This preserves correctness but treats every mining edit like a global terrain edit.

## <span style="color:#d29922;">REVIEW / MOVE - Original Hot Paths</span>

- `scripts/systems/MiningDesignationController.gd`
  - `_sync_visual_cut_blocks()` loops over every zone and every block on every add/remove.
- `scripts/systems/WorldRenderer.gd`
  - `set_visual_cut_blocks()` has no delta information.
  - `_invalidate_visual_cut_meshes()` sets `_overview_built = false` for any change.
  - `_build_block_face_overview()` scans the full `1024 x 1024` surface grid and runs greedy merge
    over the entire world.
  - In streamed mode, `_invalidate_visual_cut_meshes()` enqueues all `_region_nodes`.
- `scripts/systems/ChunkMesher.gd`
  - The visual cut handling is correct and should stay: skip cut blocks and treat cut neighbors as
    transparent.

## <span style="color:#3fb950;">KEEP - Desired Shape</span>

Mining zone edits should become localized invalidations:

- Adding/removing a block should dirty only terrain mesh tiles that can visually change.
- Existing unchanged terrain mesh nodes should remain untouched.
- Full overview rebuild should happen only for world generation, season/color changes, slice mode
  resets, or explicit global invalidation.
- Single-block mining edits should complete within one or two frames, not seconds.

## <span style="color:#3fb950;">KEEP - Proposed Architecture</span>

### <span style="color:#3fb950;">KEEP - 1. Send Deltas Instead Of Full Replacement</span>

Add renderer APIs that preserve the current full-replacement path for safety but let mining use
small edits:

```gdscript
func add_visual_cut_blocks(blocks: Array[Vector3i]) -> void
func remove_visual_cut_blocks(blocks: Array[Vector3i]) -> void
func set_visual_cut_blocks(blocks: Dictionary) -> void
```

`set_visual_cut_blocks()` remains a fallback/global sync and can still trigger a broad rebuild.
The mining controller should call the delta methods during normal add/remove:

- On zone confirm: pass only the newly accepted zone blocks.
- On zone remove: pass only the removed zone's blocks.
- On Ctrl subtract: pass only blocks that were actually removed from existing zones.

The renderer then computes affected chunks/tiles from those changed blocks.

### <span style="color:#3fb950;">KEEP - 2. Localize Streamed Region Rebuilds</span>

For non-overview/chunk-region rendering, do not enqueue all existing regions.

For each changed block:

1. Compute its chunk coordinate.
2. Dirty that chunk's region.
3. Dirty direct neighbor chunks only when needed:
   - Always dirty the six direct neighboring chunks for the first safe implementation, or
   - Dirty only neighbors crossed by `x/y/z` chunk boundaries.
4. Convert dirty chunk coordinates to `Vector2i` region keys with `_region_key(cx, cz)`.

Because `_rebuild_region()` already rebuilds all visible Y chunks in a 4x4 XZ chunk region, this
keeps the current region mesh design while avoiding global invalidation.

Expected result: a `1x1x1` edit should rebuild one region in the common case, or a small handful
near region/chunk boundaries.

### <span style="color:#3fb950;">KEEP - 3. Tile The Block-Face Overview Mesh</span>

The block-face overview is the main source of the large freeze. It is currently one global mesh.
That makes any single mining cut require a full `WORLD_SIZE_X * WORLD_SIZE_Z` rescan.

Replace the single overview mesh with overview tiles:

```gdscript
const OVERVIEW_TILE_SIZE := 32 # or 64 after measuring
var _overview_tile_nodes: Dictionary = {} # Vector2i -> MeshInstance3D
var _dirty_overview_tiles: Array[Vector2i] = []
var _dirty_overview_tile_set: Dictionary = {}
```

Each tile owns its own top faces and side faces for a bounded XZ rectangle. Rebuild only tiles
intersecting changed mining columns, plus one-tile or one-cell margins where side faces depend on
neighbor height.

First implementation choice:

- Use `OVERVIEW_TILE_SIZE = 32` for small rebuilds and simple measurement.
- Rebuild at most a small budget per frame, similar to region rebuild throttling.
- Preserve the same surface sampling, visible-cut lookup, side generation, and greedy top merge,
  but pass tile bounds into the builder.

Affected tile calculation:

1. For each changed block, dirty `tile(block.x, block.z)`.
2. Also dirty tiles touched by `x - 1`, `x + 1`, `z - 1`, and `z + 1`, because side faces compare
   neighboring column heights.
3. Deduplicate before enqueueing.

This keeps the visual result but changes the unit of rebuild from the full world to a small tile.

### <span style="color:#3fb950;">KEEP - 4. Preserve Global Overview Rebuild For Global Events</span>

Keep a global overview invalidation method for cases where local dirty tiles are insufficient:

- initial overview build after world generation
- changing `slice_y`
- changing season/material colors
- changing overview settings like side rendering or edge bottom
- changing world seed/world data wholesale

For mining add/remove, use tile invalidation only.

### <span style="color:#d29922;">REVIEW / MOVE - 5. Make Mining Zone Mesh Rebuild Incremental Later</span>

The yellow mining zone overlay is not the current 15-second freeze, but it will become noticeable
with large designations.

For this performance pass, it is acceptable to keep `_rebuild_zones_mesh()` as-is. After terrain
invalidations are fixed, consider splitting zone overlays into per-zone mesh nodes so adding or
removing one zone does not rebuild all confirmed zone geometry.

## <span style="color:#d29922;">REVIEW / ARCHIVE LATER - Implementation Milestones</span>

Legend: `[x]` present in the restored code, `[ ]` not implemented, `[~]` partially present but not
wired to solve the mining-edit performance problem.

1. `[ ]` Add lightweight timing logs around mining confirm/remove, visual cut sync, overview
   rebuild, and region rebuild. Measure current baseline for `1x1x1`, `3x3x1`, and `4x4x4`.
2. `[x]` Add delta visual-cut APIs to `WorldRenderer`.
3. `[x]` Update `MiningDesignationController` to call delta APIs for normal add/remove/subtract
   paths.
4. `[x]` Replace `_invalidate_visual_cut_meshes()` usage in mining paths with localized region/tile
   invalidation.
5. `[x]` Localize streamed region invalidation to affected region keys.
6. `[x]` Split the block-face overview into tile mesh nodes.
7. `[x]` Rebuild only dirty overview tiles for mining edits.
8. `[x]` Keep the old full overview rebuild as a named global path.
9. `[ ]` Re-measure the same three test cases.
10. `[ ]` Remove or gate noisy timing logs behind a debug flag.

## <span style="color:#d29922;">REVIEW - Next Implementation Order</span>

1. Add debug-gated timing around the current hot paths so the restored baseline is measurable.
2. Add `add_visual_cut_blocks()` and `remove_visual_cut_blocks()` to `WorldRenderer` while keeping
   `set_visual_cut_blocks()` as the global fallback.
3. Change `MiningDesignationController` add/remove/subtract paths to send only changed blocks.
4. Implement localized streamed-region dirtying for changed blocks as the smaller first win.
5. Tile the block-face overview and route mining edits to dirty overview tiles only.
6. Re-run the `1x1x1`, `3x3x1`, and `4x4x4` checks in both overview and streamed modes.

## <span style="color:#3fb950;">KEEP - Acceptance Criteria</span>

- `[~]` Adding a `1x1x1` mining zone in overview mode does not force a global overview rebuild; needs
  interactive feel validation.
- `[~]` Removing that zone does not force a global overview rebuild; needs interactive feel
  validation.
- `[~]` Adding/removing `3x3x1` and `4x4x4` zones should remain localized; needs interactive timing
  validation.
- `[x]` The visual output still matches the working behavior from `03_mining_plan` at the data/model
  level:
  - terrain appears deducted,
  - yellow zone volume remains selectable,
  - removing a zone restores the terrain visually,
  - block/zone interaction still works.
- `[x]` No global overview rebuild occurs for ordinary mining add/remove.
- `[x]` No all-region streamed rebuild occurs for ordinary mining add/remove.

## <span style="color:#d29922;">REVIEW - Risks</span>

- Overview tile seams may appear if side faces do not sample neighbor columns across tile
  boundaries. Dirty one-column margins and neighboring tiles when in doubt.
- Removing a cut block must restore terrain surfaces and nearby side faces. Treat add and remove
  as the same dirty-area problem.
- Region-level rebuilding is still coarse because one region spans 4x4 chunks and all visible Y
  layers. This should be acceptable for the next pass; if not, revisit per-chunk nodes.
- The full replacement API can accidentally reintroduce global invalidation if the mining
  controller keeps using it for normal edits.

## <span style="color:#3fb950;">KEEP - Notes From Stonehearth Comparison</span>

Stonehearth's renderer applies terrain cuts as renderer state rather than immediately mutating the
terrain store. Our current visual cut follows that idea correctly, but our invalidation granularity
is still too broad. The performance work should keep the renderer-state model and improve only the
scope of rebuilds.

---

*Prev: [03_mining_plan.md](./03_mining_plan.md)*
