# 128 — Permanent floor preview

**2026-10-17:** [212](212_final_terrain_state.md) removes completed-floor ownership.
The current block type preserves appearance, support and room appeal; both floors
save only in the unified final terrain map. Construction retains pending plans.

Implemented 2026-10-12. The player approved permanent floors that replace a full
supporting voxel: mine an extra layer, then fill it to restore the original
walking height. Mining and construction stay separate. Wall finishes remain
excluded; other wall types are deferred. Rugs, pelts and fitted carpets remain a
separate future category.

## Player controls

**Construction → Floors** contains Simple plank floor and Simple stone floor.
[138 — Illustrated Construction](138_illustrated_construction.md) replaces the
original voxel thumbnails with matching Hearth & iron illustrations, preview
flask badges and hover/focus descriptions. Click or drag across cleared space to
plan one layer, up to 32×32 cells after [209](209_torch_reach_and_construction_size.md).
The tiles require solid ground immediately
below them; they cannot bridge a gap. Escape ends the tool. Existing terrain
must be mined separately, and floors cannot overwrite it.

Click a blue floor plan to inspect it. It reports the required Carpenter or
Stonemason, the remaining tiles, and the whole-room appeal bonus. Those
professions/workshops are not implemented, so floor plans create no worker
leases, source registrations or material claims. No recipes or production costs
are invented for them.

**DEV Build** in that inspector instantly completes the selected area's visible,
clear, supported cells, without consuming materials. It rechecks water, bedrock,
discovery, actors, loose goods, furniture, storage, other structures and support
at commit. Blocked cells remain pending with a reason; retry or cancel them.
Normal mining removes finished floors. These free preview floors return no
materials, avoiding a free-resource loop. Normal stone-block construction still
requires one delivered rough stone; mining it now uses the same 5% rough-stone
chance as natural stone.

**2026-10-12 playtest fixes:** idle dwarves can take a normal adjacent step up
out of a shallow unfinished floor tile; retry DEV Build once they move clear.
Already embedded feet recover onto the floor if the three-block standing space
above is clear, including after loading a current save. See [115](115_dwarf_support_recovery.md).
Excavating the floor beneath an installed wall torch now preserves its original
mounting height, light and heat. Only its actual wall bracket supports determine
whether it stays attached. Pending installation still requires its work floor.
These fixes pass the 26-fixture job/save gate and five rest/bedroom/bridge
regressions. Both torch types retain their mounts in all four directions;
removing the bracket support still refunds exactly one torch. Evidence:
`tmp/floor_recovery_20261012/`.

## Geometry and appearance

Each floor occupies one **full 1×1×1 world block** (0.5 m per side), authored as
**8×8×8 art voxels**. A detail voxel is 1/8 of a block on each axis; the installed
floor is not a 1/8-block-thick overlay. Tops stay exactly on the grid walking
surface. Color joints preserve a solid physical surface, without holes or
z-fighting overlays.

`tools/generate_permanent_floors.py` exports original flat-shaded GLBs with linear
vertex colors, baked .125 scale and unit roots. The models use a cell-minimum
origin at (0,0,0), unlike centered furniture, so they fill [0,1] on all three axes.
Planks alternate two tiles along world Z to form longer staggered boards; laid
stone uses a repeating staggered slab pattern. Pattern phase is anchored to the
world grid, so separately built areas join consistently after saving or repair.
`tools/GenerateFloorIcons.gd` renders their menu icons through Godot.

`ConstructionFloorArt` caches the six boundary faces from each GLB. WorldRenderer
batches exposed faces into the shared terrain mesh, excluding internal faces.
There are no per-tile scene nodes or physics colliders. Floors share live terrain
lighting, shadow layers and slice clipping; artificial slice caps remain dimmed.

## Room appeal

RoomManager owns `data/rooms/appeal.json`. A sealed room receives one **+5 flooring
appeal** bonus when all its interior walking surfaces have finished floor blocks.
Both materials count equally and can be mixed. Natural rock and blue plans do
not count; unfinished excavation does not count. Furniture above a tile does not
exclude it. Doorway seal columns are outside the interior and are not required.

The room inspector displays finished/total floor tiles and the bonus. Mining one
tile removes the bonus; finishing a repair restores it without stacking. Room
geometry and this score are derived again on terrain changes and loading, not
saved as a second authority. This introduces the flooring contribution only;
aggregate furniture appeal and appeal-based happiness remain later systems.

## Data and saves

BlockRegistry owns the construction definitions and two constructed-floor block
identities. They are never generated in natural terrain. ConstructionController
keeps each pending order's construction kind. Completed floors save once in
`scene.terrain.edits`, with no provenance.
Restoration writes actual solid terrain before furniture and dwarves, preserving
navigation, room sealing and pattern phase. SaveSnapshotValidator accepts only
known construction types and registered rock/floor block identities. Development
saves now require the construction-kind field on pending orders; no old-save
migration is supplied under the project's development save policy.

## Verification

`FloorConstructionTest` covers real menu/mouse input, locked workers, physical
support, partial DEV completion, real mining, mixed 9×9 coverage, furniture,
bonus removal/repair, saved plan kinds, water/bedrock/slice guards and room UI at
960×540 and 1280×720, plus occupied-tile escape and a subsequent DEV Build retry.
It joins the 26-fixture job reliability gate.
`SaveManagerRoundTripTest` includes both finished floors and a locked floor plan
through full scene replacement, autosave and backup recovery.
`tools/PermanentFloorWorldReview.gd` checks a generated mountain room with live
underground lighting. Logs and native captures: `tmp/permanent_floors_20261012/`.

Verified 2026-10-12: all 26 job/save fixtures and BedroomTest,
BedroomComfortTest and BedroomPrivacyTest pass. Native FloorConstructionTest
passes, including both compact room layouts. The generated mountain review
passes with 81 tiles, +5 appeal and the production underground shader; torchlit
captures show the joined patterns and inspector. First-pass icon material and
test-only water fixture issues were corrected before these final runs.

Restart Play to load the new definitions/assets. No new global class or autoload
requires an editor reload. An older development save containing pending orders
without construction kinds is rejected; use a fresh world in that case.
