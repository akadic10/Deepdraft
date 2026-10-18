# 199 — Campfire and room hearth

Implemented 2026-10-16 following the player's approved plan. The campfire remains
an outdoor gathering fire; the hearth is visibly a compact stone room heater.

## Appearance and placement

The campfire's model, animation, collision, seating behavior and heat output are
unchanged. Its roughly 2×2 ring remains centered in the existing 3×3 camp area.
The placement card, ghost hint and Object explorer now call that reservation
**3 × 3 camp area**, explaining that stools belong around its edges.

The hearth has a squared flagstone base, an uneven stacked fieldstone back and
cheeks, and an open front facing local +Z. Exposed logs, dark ash, glowing coals
and a lower animated flame distinguish it from the campfire. Its 2×2 footprint
and 2×2×2 collision envelope are unchanged; visible geometry stays inside them
and reaches 1.6825 blocks high. It can stand against a wall and rotate through
the existing four orientations. Placement shows the full base, labels it
**2 × 2 room heater**, and asks the player to face its opening into the room.

The named body and flame meshes, ten-frame animation library, item key and
furniture key remain intact. The thumbnail comes from the actual new model.
Only `hearth.glb`, `animations/hearth_flame.glb` and the hearth thumbnail change
among production art assets. Both existing art generators reproduce the results.
No import metadata was hand-edited. The old voxel generator remains retired.

## Heating and feedback

The existing RoomManager formula and ownership remain authoritative. Hearth
output changes from 2400 to 1600 heat units, counted once at its origin. The
minimum heated volume stays 128. The common `heating_contribution()` calculation
serves both room totals and the heater inspector, avoiding duplicated formulas.

The installed hearth's Object explorer identifies its room, actual temperature
and comfort label, and that hearth's own temperature contribution. Multiple
hearths do not each claim the room's combined contribution. Outdoors or after a
roof/door breach, it displays **No enclosed room** and explains **Not inside an
enclosed room. Walls, a roof and a door let this hearth heat a room.** The normal
inspector refresh reads the current room map and follows seasonal/hour changes.
Pending plans show their footprint without claiming installed heating.

Measured room cases (normal sheltered-rock climate, minimal overburden):

| Room | Heating | Temperature |
|---|---|---:|
| 6×6×4 bedroom, winter night | One hearth | 19.11°C |
| Same bedroom, summer afternoon | One hearth | 23.11°C |
| Tiny room below the 128-cell minimum, summer afternoon | One hearth and a log torch | 25.09°C |
| 8×8×4 barracks, winter night | One hearth | 14.25°C, Chilly |
| Same barracks | Two hearths | 20.50°C, Comfortable |

Heating still requires a detected enclosed room. Campfires retain their 900-unit
contribution if placed indoors; outdoor temperature does not simulate local fire
warmth. Existing comfortable-sleep behavior avoids thermal happiness penalties.
There is no new direct happiness bonus, fuel requirement, chimney simulation or
thermostat. Multiple heaters can still overheat a small room.

Crafting still costs two matching logs and four rough stones, taking 18 seconds
at the crude workbench under Rudimentary → Rooms. Existing installed, queued and
packed furniture continues using the same keys and save format; restored pieces
load the current definition. Restart Play to refresh loaded models and balance.

## Validation

`HearthRoomTest` exercises actual sealed rooms, four rotations, placement outlines,
blocked and adjacent walkable cells, flame/body bounds, all seasonal temperature
extremes, individual heat accounting, roof breach and repair, pending/packed
objects, inspector rows and JSON furniture restoration. Native captures additionally
check inspector fitting at 960×540 and 1280×720 and both placement cards.

The static hearth changes from 1002 to 2326 triangles and remains two named
meshes. The ten-frame library changes from 3500 to 5700 stored triangles; only
one flame frame is displayed at a time. This is an art cost report, not a claim
of improved game performance. Other furniture and fire exports are byte-identical.

All 11 focused fixtures pass: HearthRoom, BedroomComfort, BedOwnership,
CampfirePlacement, CampfireStool, FireFacetedArt, FurnitureFacetedArt,
FurnitureMove, FurniturePlace, RoomRebuildScheduling and CraftingBrowser.
Native HearthRoom and CraftingBrowser runs also pass, covering the refreshed
thumbnail, room feedback, daylight/night art and compact interface layouts.
The browser fixture's earlier six-category/two-Access-recipe expectations were
updated for the already-added Recreation category, log fence and gate. The new
hearth fixture corrected its float-format string and packing baseline during
development; these were test corrections, not deferred runtime failures.

Durable evidence: [validation summary](concepts/hearth_room_20261016/summary.json),
[comparison](concepts/hearth_room_20261016/fires_colony.png),
[hearth close view](concepts/hearth_room_20261016/hearth_close.png),
[heated bedroom](concepts/hearth_room_20261016/heated_bedroom.png),
[temperature measurements](concepts/hearth_room_20261016/temperatures.json), and
[art cost](concepts/hearth_room_20261016/art_cost.json). The same directory holds
compressed test logs and native menu/night captures. No Windows playtest was
created or updated. This milestone does not resume paused performance work.
