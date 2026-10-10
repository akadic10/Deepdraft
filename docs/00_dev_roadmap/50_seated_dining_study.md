# 50 — Seated dining and table-size study

Status: **FURNITURE AND CHAIR SNAPPING IMPLEMENTED — 2026-10-05.**
The approved personal 2×2 table, communal 8×4 table and separate 2×2 chair are
live build items. Table seat slots, chair head clearance and approach offsets
are JSON data. Walking navigation remains 1×1×3. Autonomous idle sitting and
exclusive transient chair reservations now ship in [99 — Idle activity](99_dwarf_idle_activity.md).
Eating and tavern gatherings remain future gameplay work. The historical study
and implementation notes below describe the original furniture/placement pass.

Player review: **personal table/chair/dwarf approved; communal 8×4 eight-seat
layout visually approved** ("I like this look").
The chosen communal layout seats **eight**: three along each long side and one
at each end. Both end chairs should snap like the side chairs. The narrower
8×2 and 8×3 alternatives remain in the study for comparison only.

## Finding

Native head meshes are 2.125 blocks wide; the side-braid hairstyle reaches
2.375 blocks. The body is 1.375 blocks wide. Two occupied original 1×1 chairs
on adjacent cells cannot fit these silhouettes. A seated rendering of that
arrangement reproduces the head overlap. Standing-dwarf scale images in the
earlier furniture reviews did not validate occupied seating.

## Two table candidates

| Candidate | Table footprint | Seats in this study | Furniture arrangement |
|---|---|---|---|
| Personal dining | 2×2 | 1 | One independently placed chair; suitable for a private room |
| Communal dining, original study | 8×2 | 6 | Rejected as too narrow; retained for comparison |
| Communal dining, compact alternative | 8×3 | 6 | Three independent chairs on each long side, centers 3 blocks apart |
| Communal dining, selected | 8×4 | 8 | Three chairs per long side plus one at each end, all facing inward |

Both tables use a 1.75-block tabletop, raised from the previous 1.5-block
height to meet the seated fists. Oak planks, iron fittings and trestles retain
the project's existing palette and eight-voxels-per-block construction.

The separate chair prototype is 2×2, with a .875-block seat and 1.375-block
low back/arms. The wider seat accommodates the torso. The low back leaves
clearance for hanging rear hair. Its footprint occupies two cells in each
direction; three-block center spacing leaves one tile between neighboring
chairs. The personal arrangement uses a 2×4 furniture area and the communal
arrangements 8×6, 8×7 or **12×8** respectively, before allowing access space or
visual overhang. The 8×3 preview offsets the table center by half a block so
both its edges and the 2×2 chair origins remain aligned to whole grid cells.

These previews do not establish room-size requirements. Entry/exit, route
availability, walls, multi-dwarf traffic and seat reservations need a later
gameplay pass. Chairs remain separately built furniture, as requested in docs
38 and 39; neither table auto-spawns seating. A communal bench is a possible
later variant, not included in this study.

## Pose and assets

`tools/generate_seating_study.py` builds prototype GLBs and copies the shipping
dwarf parts into the isolated `tmp/seating_study/` Godot project. Original
source hashes are recorded in `validation.json`. There is no install option.

`tools/SeatingStudy.gd` assembles the original head, hair, eyebrows, beard,
body, floating fists and floating feet at native scale. Signed hand/foot
mirroring matches the live dwarf assembly. It positions the torso on the seat,
moves the feet forward beneath it and places both fists above the tabletop.
Small head turns, breathing and foot movement provide an idle pose preview;
this is not an implemented enter-seat/eating/exit animation.

The eight diners include side braids, loose hair, twin braids, a bun, long/full/forked
beards and several ages/skin/hair colors. The personal image uses a long-bearded
elder to expose the table clearance. The game character meshes are not resized.

## Review evidence

Native Godot Forward+ captures were rendered and visually inspected:

- `renders/personal.png`, `personal_side.png`, `personal_rts.png`.
- `renders/communal.png`, `communal_rts.png`, `communal_top.png`.
- `renders/current_crowding.png` reproduces the original tight arrangement.
- `renders/chair_fit.png` compares the original and prototype chairs.
- `renders/communal_8x3.png` and `communal_8x3_rts.png` show the compact revision.
- `renders/communal_8x4.png`, `communal_8x4_rts.png` and `communal_8x4_top.png`
  show the broad revision.
- `renders/seat_guides.png` illustrates proposed chair-position guides on the
  8×4 table: one solid placed chair and seven translucent available positions,
  including the two end seats.

`clearance_checks.json` records 180 samples over twelve seconds of idle at
each of four quarter-turn rotations. For all eight tested diners, no head/hair/
beard bounds intersect another head or the table in the communal arrangement;
the minimum separating axis gap is **.562 blocks**. The personal table also
clears the tested elder's hair/beard. Torso support height and palm height are
checked. These are conservative mesh-bound checks for the shown styles and
pose, not complete collision or navigation certification for every variant.
Both wider communal variants pass the same four-rotation checks and retain
the .562-block minimum head gap along each row. The selected 8×4 arrangement
includes every end-to-corner pair in that check and confirms exactly eight
diners. The two end diners include a long braided beard and a rear bun.

The original one-block spacing produces overlapping head bounds. It is a
diagnostic preview of future seating, not a claim that live sitting already
exists. Chair fit was inspected visually from three-quarter and side views.

## Implemented placement behavior

The furniture registry owns `data/furniture/*.json`. `wooden_table.json` has
four alternative personal seat positions with `max_chairs: 1`;
`communal_table.json` has eight slots with `max_chairs: 8`. Each slot
specifies a chair key, footprint-local origin and inward quarter-turn rotation.
The communal origins are `(0,-2)`, `(3,-2)`, `(6,-2)` and `(0,4)`, `(3,4)`,
`(6,4)`, with `(-2,1)` and `(8,1)` at the ends. All four table rotations transform
the complete chair rectangle, preserving integer grid alignment.

Selecting Wooden Chair near an installed or planned table shows its suggested
positions. Hovering within the JSON snap radius snaps the cursor ghost and
sets its inward facing; R continues to rotate standalone placements. Green
guides are available; red guides are obstructed. A correctly placed/planned
chair occupies its guide. Clicking queues exactly one independently built chair.
The two end chairs follow the same rules as the six side chairs. Any slot can
remain empty, and chairs away from tables can still be built independently.

Personal tables offer one inward-facing position on each side: `(0,2)`,
`(0,-2)`, `(-2,0)` and `(2,0)`. The original south slot retains its `personal`
ID. Planned and installed chairs both count toward the one-chair limit. Once
a chair is planned, the unused guides disappear; pointing at another side
shows a red cursor and a capacity explanation. Cancelling or removing the chair
reopens all four choices. Marking a chair for uninstall reserves its place
until removal finishes. The limit also applies when a table is placed around
existing chairs. Occupancy derives from saved furniture positions, so no new
save fields or persistent capacity claims are needed. Older saves keep their
pieces; if they already contain excess chair plans, installed chairs take
priority and the earliest remaining plan can finish.

The wide chair's `seating_chair` data supplies a seated head/hair clearance box
and six side/back approach tiles. Placement checks terrain, other furniture,
external entity occupancy, neighboring seated clearance and at least one
open three-air-high approach tile. New furniture also respects existing chair
head space. These are local space/access checks; colony-wide reachability,
dining reservations and multi-dwarf traffic are not implemented here. Planned
chairs reserve placement space without becoming solid navigation obstacles.
Before a dwarf consumes a crate to build a chair, clearance, floor and local
access are checked again. Tool cancellation and slice changes clear the guides.

`FurnitureSeating.gd` derives installed table/chair associations from exact
origin, key and facing; `FurniturePlacementController.get_dining_seats()` exposes
them. No cross-object IDs are persisted. Uninstalling a table leaves its chairs;
uninstalling a chair frees only that position and refunds its own packed item.

The old table item/key becomes Personal Dining Table; Communal Dining Table
has its own item/key, Build entry and DEV furniture-batch entry. Both use the
normal packed-item fetch/build/uninstall pipeline (carry cost 4).

Chair layout version 2 saves the new 2×2 footprint. Unversioned/version-1 chair
saves and ghosts retain their old 1×1 footprint and `wooden_chair_legacy.glb`;
loading an older room does not expand its chairs. Uninstall/rebuild upgrades the
refunded chair item. Saved table footprints remain compatible.

### Validation

`DiningPlacementTest.gd` checks all 32 seats across four table rotations, inward
facing, floor reservations, camera hover/click snapping, head clearance, blocked
local access, terrain/external obstacles, ghost tables, slice/tool cleanup,
old/new saved layouts and independently removing table/chair items. Personal
tables are checked at all four sides and rotations, including queued and built
capacity, cancellation, uninstall, restore and table-after-chair placement. It also
runs a communal crate through real dwarf hand-contact pickup and build/refund.
`VerifyChair.gd` and `VerifyDiningTable.gd` verify real fetching, all rotations,
model bounds/occupancy, independent uninstall and restore. SaveManager's disk
round trip runs with isolated test saves. The live guide capture is
`tmp/seating_study/live_dining_guides.png`; the earlier seated-dwarf images
remain visual studies, not live dining AI.

## Reproduce and interact

```powershell
python -B tools/generate_seating_study.py
$seatingEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $seatingEngine -ArgumentList @('--headless','--editor','--path','P:\Deepdraft\tmp\seating_study','--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $seatingEngine -ArgumentList @('--path','P:\Deepdraft\tmp\seating_study','--resolution','1600x1000','--','--capture') -WindowStyle Hidden -Wait
```

Open `tmp/seating_study/project.godot` in Godot and run it without `--capture`
for layout/angle buttons, an idle toggle and initial-pose head-bound overlays.
The review project has no colony autoloads or player save access.

Future work is autonomous approach/sitting, seat reservations, eating and
social behavior using the installed seat associations.
The current 1×1×3 navigation contract remains the baseline for walking.
