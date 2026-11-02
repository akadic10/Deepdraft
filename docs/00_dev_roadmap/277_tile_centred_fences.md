# 277 — Fence posts and gates centred on tiles

From the owner, 2026-10-27, placing a Log Fence Post: doc 201 put posts on grid corners,
between voxels, and the owner now calls that a mistake. The post and the gate should sit
centred on a voxel. The owner took the recommended gate: one open tile between two posts.

Built 2026-10-27. The owner's look in Play is next.

## What changed for the player

- **A post stands in the middle of the tile you click** and blocks that tile, like a
  stool. The tiles beside it stay walkable. Posts on neighbouring tiles at the same height
  join with the same two rails, from tile centre to tile centre.
- **A fence line now uses a row of tiles.** A 5 × 5 pen needs a 7 × 7 ring of 24 posts;
  the corner ring took 20.
- **The Log Gate covers three tiles:** an end post, one open tile and another end post.
  The pointer aims at the open tile, and R turns the gate. It still reuses posts already
  at its ends, opens as dwarves approach and never seals a room.
  - The walkable gap is one tile; the corner gate had two lanes. Dwarves, rabbits and
    ducks pass. Deer (2 wide) and wolves (4 wide) no longer fit.
- **Diagonal posts** still get no rail, but the gap between them is now closed, because
  dwarves never cut corners. Neighbouring posts at different heights close the same way.
- Storage zones, furniture and construction stay off post tiles and gate openings.

## How it works

- `GridFence.gd` keeps its rules, with tiles in place of corners:
  - `ends` are the post tiles and `openings` a gate's walkable tiles. `aim_origin` turns
    the aimed tile into the saved origin, a gate's first end.
  - Each tile has one role: a post, which a post and gate ends may share, or a gate
    opening, which nothing else may use. Two gates can no longer cross at one opening.
  - New tiles take the floor-furniture tile rule (`FurniturePlacementRules.is_valid_cell`);
    a gate end on an existing post reuses that post's tile.
  - `sync` registers one occupancy box per installed post tile (`register_box`, 1 × 2 × 1).
    Rails register nothing: they lie inside post tiles.
  - `bounds_for` is the piece's own tiles, which is exact, so an L corner reserves nothing
    in its inner tile. `pick_bounds` adds the rails for picking (`FurnitureWindow`).
- `FurniturePlacementController.blocks_zone_cell` asks the fences, so zones stay off
  fence tiles.
- **The thin-barrier system is gone.** Fences were its only user. Removed:
  `PlacedEntityRegistry.register_barrier`, `barriers_overlap` and
  `barrier_blocks_segment`; `NavGrid.edge_clear` and the barrier check in
  `line_walkable_flat_from`; four checks in `AnimalNavigation`; one in
  `DwarfMovement.move_segment_clear`; and one in `ConstructionController._crate_site_clear`.
  Occupancy and no-corner-cutting cover all of them.
- **The models did not change.** Post, rails and gate are built around their own centres,
  and the 1- and 2-block spans still meet tile centres, so nothing was re-rendered.
- **Data:** new descriptions, `placement_label` and `placement_note` for both pieces (the
  descriptions also in `resources.json` and `worker_crafting.json`), and
  `grid_fence.post_radius` is gone.

## Saves

The saved origin is still a `Vector3i`, now a tile. Fences in older development saves load
half a tile off (+x, +z), with no migration (standing decision). Re-place them.

## Checks

- `GridFenceTest` (construction area) was rewritten for tiles. It covers:
  - posts blocking their own tile and nothing beside it;
  - routes and live walking going around, and diagonal gaps closing;
  - gate post sharing, one-role tiles and storage zones;
  - support loss;
  - real crafting, plan, install, Move and uninstall;
  - saves, picking, a real `push_input` click and gate aiming.
- `RudimentaryRecreationTest` and `FurniturePlacementAnimationTest` (job gate) check the
  post tile, the gate opening and the worker standing beside the fence tiles.
- The navigation, wildlife, furniture and construction areas pass (52/52). The job gate
  passes (55/55), and the lint finds nothing new; one private access fewer is recorded.
- Not checked: the look in Play.

Restart Play. No project reload is needed: there is no new `class_name` or autoload.
