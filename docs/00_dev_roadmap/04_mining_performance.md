# Mining Performance Plan

## Goal

Keep the current Stonehearth-like mining designation behavior intact while making single-block
add/remove operations feel instant. The working behavior from `03_mining_plan` is now the baseline:
confirmed mining zones visually cut terrain, remain yellow/selectable, and can be removed.

The next step is performance only. Do not change mining UX, zone semantics, colors, or the current
visual deduction result while doing this pass.

## Current Problem

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

## Current Hot Paths

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

## Desired Shape

Mining zone edits should become localized invalidations:

- Adding/removing a block should dirty only terrain mesh tiles that can visually change.
- Existing unchanged terrain mesh nodes should remain untouched.
- Full overview rebuild should happen only for world generation, season/color changes, slice mode
  resets, or explicit global invalidation.
- Single-block mining edits should complete within one or two frames, not seconds.

## Proposed Architecture

### 1. Send Deltas Instead Of Full Replacement

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

### 2. Localize Streamed Region Rebuilds

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

### 3. Tile The Block-Face Overview Mesh

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

### 4. Preserve Global Overview Rebuild For Global Events

Keep a global overview invalidation method for cases where local dirty tiles are insufficient:

- initial overview build after world generation
- changing `slice_y`
- changing season/material colors
- changing overview settings like side rendering or edge bottom
- changing world seed/world data wholesale

For mining add/remove, use tile invalidation only.

### 5. Make Mining Zone Mesh Rebuild Incremental Later

The yellow mining zone overlay is not the current 15-second freeze, but it will become noticeable
with large designations.

For this performance pass, it is acceptable to keep `_rebuild_zones_mesh()` as-is. After terrain
invalidations are fixed, consider splitting zone overlays into per-zone mesh nodes so adding or
removing one zone does not rebuild all confirmed zone geometry.

## Implementation Milestones

1. Add lightweight timing logs around mining confirm/remove, visual cut sync, overview rebuild, and
   region rebuild. Measure current baseline for `1x1x1`, `3x3x1`, and `4x4x4`.
2. Add delta visual-cut APIs to `WorldRenderer`.
3. Update `MiningDesignationController` to call delta APIs for normal add/remove/subtract paths.
4. Replace `_invalidate_visual_cut_meshes()` usage in mining paths with localized region/tile
   invalidation.
5. Localize streamed region invalidation to affected region keys.
6. Split the block-face overview into tile mesh nodes.
7. Rebuild only dirty overview tiles for mining edits.
8. Keep the old full overview rebuild as a named global path.
9. Re-measure the same three test cases.
10. Remove or gate noisy timing logs behind a debug flag.

## Acceptance Criteria

- Adding a `1x1x1` mining zone in overview mode does not freeze the game.
- Removing that zone does not freeze the game.
- Adding/removing `3x3x1` and `4x4x4` zones remains responsive.
- The visual output still matches the working behavior from `03_mining_plan`:
  - terrain appears deducted,
  - yellow zone volume remains selectable,
  - removing a zone restores the terrain visually,
  - block/zone interaction still works.
- No global overview rebuild occurs for ordinary mining add/remove.
- No all-region streamed rebuild occurs for ordinary mining add/remove.

## Risks

- Overview tile seams may appear if side faces do not sample neighbor columns across tile
  boundaries. Dirty one-column margins and neighboring tiles when in doubt.
- Removing a cut block must restore terrain surfaces and nearby side faces. Treat add and remove
  as the same dirty-area problem.
- Region-level rebuilding is still coarse because one region spans 4x4 chunks and all visible Y
  layers. This should be acceptable for the next pass; if not, revisit per-chunk nodes.
- The full replacement API can accidentally reintroduce global invalidation if the mining
  controller keeps using it for normal edits.

## Notes From Stonehearth Comparison

Stonehearth's renderer applies terrain cuts as renderer state rather than immediately mutating the
terrain store. Our current visual cut follows that idea correctly, but our invalidation granularity
is still too broad. The performance work should keep the renderer-state model and improve only the
scope of rebuilds.

---

*Prev: [03_mining_plan.md](./03_mining_plan.md)*
