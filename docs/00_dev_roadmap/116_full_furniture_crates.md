# 116 — Full furniture crates

Implemented 2026-10-11 at the user's request to make packed furniture bigger
and use the full 8×8×8 voxel envelope, as boxed goods.

## Artwork

The shared `assets/models/items/furniture/packed_furniture.glb` now occupies one
whole world block. It is a closed oak shipping crate with inset plank panels,
square corner posts, perimeter rails and stepped diagonal wooden braces with
dark fixing pegs. Warm wood shades match the existing furniture palette.

The model has 362 occupied voxels and 1,168 triangles in one connected component.
Only exposed cube faces are meshed. Bounds are X/Z −0.5 to +0.5 and Y 0 to 1;
0.125 scale is baked into vertices, root scale stays 1, and vertex colors use
linear `COLOR_0`. No texture, collider, lights or runtime scaling were added.

All 22 furniture definitions referencing the shared box receive the design,
including campfires, log stools, tables, chairs and workshop kits. Dedicated
bridge/ladder timber kits and rooted plants keep their existing artwork.
Place and Craft icons continue to identify the furniture the crate becomes.

`tools/generate_packed_furniture_redesign.py` is the authoring source;
`tools/generate_furniture_glbs.py` delegates to it. The isolated preview tool
shows the old/new size comparison, all sides and a stockpile arrangement.

## Verification

- Native Godot renders reviewed for shape, colors and dwarf scale under
  `tmp/packed_crate_20261011/art/renders/`.
- `tmp/packed_crate_20261011/RuntimeReview.gd` verifies the real campfire hauling
  job: pickup, both grips, face/body clearance, full native carry size and
  deposit into an exact one-block ground storage cell.
- All eight shelf display slots hold the enlarged crate without overlap;
  withdrawal returns a full-size model. Native captures `game_scale.png` and
  `carried.png` show the real hauling pose and actual shelf contents.
- ProfessionCraftingTest and HaulingAnimationTest pass, including campfire
  crafting/installation, quantities, interruption, stockpile fetch and save state.
- Editor import succeeds. Runtime fixtures retain the existing missing
  SkyController Environment warning; no gameplay scripts were changed.

Existing current-version saves use the new asset after restarting the game.
Item identities, costs, capacities, carry weights and placement rules are unchanged.
