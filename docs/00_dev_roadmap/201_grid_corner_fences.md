# Grid-corner fences

2026-10-17. The player requested a repeatable fence pattern along voxel edges,
then chose individual posts at grid corners with rails between neighboring posts.

## Placement and appearance

Craft **Log Fence Post** at Rudimentary crafting → Access, then place it from
Place → Access. One post costs one timber and ten seconds of Worker crafting.
Click a grid intersection: the post snaps to that corner, rather than the centre
of a floor tile. Place the next post one grid edge away on level ground. Two
level rails connect adjacent posts at the same elevation. Diagonal and more
distant posts do not connect. The translucent preview shows upcoming connections;
the rails become physical after both endpoints have been installed.

Straight runs, right-angle corners and T/four-way junctions share a single post.
The old alternating panel braces and doubled end posts are gone. The rough
faceted post is 1.3 blocks high, with rails centred at 0.45 and 1.0 blocks. The
post is 128 triangles; the separate pair of rails is 256 triangles. Timber
identity colours both posts and rails through the existing wood palette.

The **Log Gate** spans two grid edges. Leave the middle corner empty. It can
reuse separately built end posts and connects to neighboring fence posts.
Its 896-triangle model matches the rail heights; R rotates the gate. It opens
near dwarves and retains the existing passable-door convention. Neither fences
nor gates seal a room. Gates do not yet have locks or animal permissions.

## Geometry, work and persistence

`GridFence.gd` is a scene-owned helper of FurniturePlacementController, with
cached post/edge indexes rebuilt when plans or installed pieces change. Links
are derived from endpoint positions; they are not extra inventory items or
independent saved furniture. Moving/removing a post updates only its incident
connections. Gate endpoint meshes are hidden when an existing post owns that
corner. Plans reserve geometry against other furniture without blocking routes.

Posts require solid, level ground around the corner and reachable adjacent
Worker stands. Removing support returns the real post item and removes its
connections. Crafting, installation, Move and uninstall use existing physical
items, material identity and job leases; no new autoload or global class exists.

PlacedEntityRegistry holds thin barrier AABBs separately from voxel occupancy.
Both neighboring floor tiles stay usable. A* edges, diagonal transitions,
string pulling and actual dwarf movement check swept body clearance against
posts and rails. Ground-animal clearance and hops use these barriers too.
Normal occupancy signals invalidate navigation caches when connections change.

Current installed pieces, plans, rotations, materials and move identities use
the existing save format. Connections are rebuilt once after restore. Per the
development-save policy, older fence panels adopt the new single-post definition;
their layouts may need repositioning. No legacy panel layout is retained.
Restart Play to load the new definitions, models and icons.

## Validation

`GridFenceTest` checks shared posts and spans, corners and junctions, gate joins
in four orientations, duplicate/opening rejection, camera-to-corner snapping,
preview and cancellation, support removal, pathfinding and actual dwarf movement,
ground animals, real crafting/hauling/installation, Move/uninstall, timber
conservation, and installed/pending save restoration. Native captures show the
same models used in play.

The recreation, faceted-art, navigation, animal cache/body bounds, bridge corner,
ladder, furniture Move/Place, crafting browser and full save round-trip fixtures
provide regression coverage. The Place fixture now initializes its waterline map
alongside its test heightmap, so cursor rays outside its loaded floor do not read
an empty terrain array. Generator reproducibility and whitespace checks are also
recorded in the [evidence summary](concepts/grid_fence_20261017/summary.json).

No Windows playtest was created or updated.

## Lower fence follow-up

Later on 2026-10-17, the player approved reducing posts from 1.8 to 1.3 voxels
and moving the rail centres from 0.62/1.30 to 0.45/1.0 voxels. Gate posts and rails
match, with shorter stiles and a refitted diagonal brace. Posts are now about
39% of the roughly 3.3-voxel visible dwarf height. The post collision height is
1.3; rail barriers end at 1.1, just above the upper rail's surface. The gate's
span, hinges and opening behavior are retained. Models and thumbnails were
regenerated; native grid-fence and furniture-art checks cover the revised assets.
The original evidence above records the initial height; the updated captures
and logs are in [lower_fence_20261017](concepts/lower_fence_20261017/summary.json).
