# 100 — Profession crafting and camp furniture

Implemented 2026-10-09. **Craft → Crafters → profession** opens the selected
crafting menu. The original in-window profession dropdown was replaced after
the player clarified the intended Stonehearth-style submenu navigation.
Existing Worker recipes, physical production and wood rules are unchanged.

## Menu

- Rudimentary groups Workshops, Lighting, Access, Camp furnishings and Starter
  tools. Returning from a preview remembers the selected recipe.
- Carpenter, Stonemason, Blacksmith, Weaponsmith, Armorsmith, Farmer, Hunter and
  Brewer have marked planned sections. Miner has an equipment preview; its
  existing promotion and mining behavior remain available.
- Previews explain future output areas and known entry tools, with no fake
  recipes, costs, Queue or Place actions. Current starter tools stay Worker-made.
- Craft first opens icon buttons for all ten sections above the dock. Desktop
  uses one row; compact screens use balanced rows. Planned professions remain
  clickable and clearly marked. Choosing one closes the chooser and opens its
  titled recipe/preview window; **‹ Crafters** returns to the profession buttons.
  Clicking Craft again or pressing Escape closes the chooser.
- Orders shown in a profession menu belong to that section. Worker orders keep
  running while browsing planned professions and reappear on return to Rudimentary.
  Workbench/recipe links open the appropriate recipe directly. First-open layout settles after wrapped
  labels measure their widths. The window fits above the dock at 1280×720 and
  960×540 with Queue and Place visible.
- CraftingManager owns `sections` in `worker_crafting.json`. Presentation groups
  do not enable specialist jobs or change task eligibility.
- UIRegistry owns the profession-button labels, order, icons and `open_crafting`
  bindings in `data/ui/dock.json`. DockUI handles submenu navigation; the shared
  recipe-window component displays the selected section without a dropdown.

The navigation follow-up is verified through actual dock, profession and Back
button clicks for every section at 1280×720 and 960×540. It checks menu fit,
compact wrapping, Escape, highlight state, queue/recipe retention, planned-action
gating and direct recipe links. Native captures were reviewed for both submenu
layouts and the Rudimentary/Carpenter screens. WorkerCraftingTest and
WorkerCraftingWoodTest also pass. Evidence: `tmp/craft_submenu_review/` logs and
`tmp/profession_crafting_review/crafters_1280.png`, `crafters_960.png`,
`rudimentary_1280.png`, `rudimentary_960.png`, `carpenter_1280.png`, `carpenter_960.png`.

## New Worker recipes

| Recipe | Materials | Work | Workshop | Output |
|---|---|---|---|---|
| Campfire | 1 allowed log + 1 Rough Stone | 10 seconds | Crude workbench | 1 packed campfire |
| Log stool | 1 allowed log | 8 seconds | Crude workbench | 1 packed log stool |

Both use physical ingredient delivery, Worker proximity selection, spare stock
targets, hauling, installation, uninstall refunds and existing save owners.
Pine is the default wood; players can opt into other species.

The campfire has a 3×3 placement footprint with the original roughly 2×2 stone
ring centered on its middle tile, charred logs, eight voxel flame silhouettes
and warm local light. Its definition uses the existing
heat-source integration at 200 units. Installed fires stay lit without fuel
upkeep; packed goods have no light. Cooking and social gatherings remain future
work. Campfires appear in Place → Lighting.

The 1×1 log stool is a short bark-covered stump with a flat cut top, no back or
arms, and a height of 0.75 blocks. Its seat-specific rest pose puts the torso on
the cut surface and the boots on the ground beside the stump. Idle dwarves can sit,
reserve it exclusively and return to work immediately. This is ambient leisure,
with no new needs or bonuses. Place → Dining lets players arrange stools around
a campfire.

`tools/generate_camp_furniture.py` exports original models at eight voxels/block,
baked 0.125 scale, linear colors, root scale 1 and no GLB colliders. Separate body
and flame meshes use FurnitureLighting/FurnitureFlameAnimation. The generator
checks connected, bounded, distinct flame frames. Native thumbnails use placed
models; packed goods use the existing furniture carrying crate.

## Verification

- ProfessionCraftingTest: material/workbench gates, real crafting and exact costs,
  normal installation, animated/local lighting, idle sitting, furniture JSON
  restoration without duplicate goods, preview gating, retained orders, recipe
  navigation and responsive Queue/Place controls.
- Native captures reviewed: seated dwarf with camp furniture and Rudimentary/
  Carpenter panels at 1280×720 and 960×540.
- WorkerCraftingTest, WorkerCraftingWoodTest, StarterToolsTest,
  CraftingSelectionTest and DwarfIdleBehaviorTest pass. Selection tests include
  both new recipes automatically.
- Godot import/parse and native furniture thumbnail generation pass. Tests use
  isolated application-data directories, not player saves.

Evidence in `tmp/profession_crafting_review/`: `native_final.log`, `worker4.log`,
`wood.log`, `tools.log`, `selection.log`, `idle.log` and PNG captures. Earlier
failed logs record layout issues corrected before completion.

## Follow-up: packed campfire missing from Place

The player found a finished campfire but an empty Place menu. Both new furniture
definitions and recipes existed, but their presentation entries were missing
from `data/ui/place_catalog.json`. The first test installed through the placement
controller directly, so it missed the absent player-facing tiles.

Campfire is now registered under Lighting and Log chair under Dining. Existing
packed items are usable; no item, recipe, reservation or save migration is needed.
The strengthened ProfessionCraftingTest checks that every placeable Worker
recipe has a catalog tile, then exercises Craft → Place finished item and real
Place dock/category/tile clicks while paused before completing both installs.
It reproduces the two missing entries before the fix and passes afterward.
FurniturePlaceTest also passes; it scrolls to its unavailable test tile now that
the catalog has another row. Evidence: `tmp/campfire_catalog_fix/before.log`,
`after2.log`, `catalog2.log`, `native.log`, and the `place_campfire.png` /
`place_log_chair.png` captures in `tmp/profession_crafting_review/`.

## Follow-up: compact stump stool

The player found the original 2×2 chair too large. It is now a basic 1×1 stump
stool with a stepped round outline, bark furrows and visible cut wood. Menus and
packed goods use **Log stool**; the existing `log_chair` furniture, item and
recipe keys remain stable. Layout version 2 adopts the smaller footprint when
an older placed chair is loaded, preserving its anchor and avoiding duplicate
items. Existing packed chairs install as stools.

The data-defined rest pose lowers the hands and places the feet beside the
stump. Cardinal access remains open; the larger seated dwarf still reserves head
clearance around the small stool. No dwarf geometry or navigation dimensions
change. The native catalog thumbnail was regenerated from the new model.

LogStoolTest passes for all four rotations: exact 1×0.75×1 model bounds, one
blocked tile, cardinal access, torso support, ground-level boots outside the
stump, head clearance, interruptible sitting, a walkable saved dwarf position,
old-chair restoration and the unchanged packed-item refund. ProfessionCraftingTest
and DiningPlacementTest pass as regressions. Native captures of the unoccupied
stump and all four seated rotations were reviewed. Evidence is in
`tmp/log_stool_review/`: `behavior2.log`, `native2.log`, `crafting.log`,
`dining.log`, `thumbnail2.log`, `stump.png` and `occupied_0.png`–`occupied_3.png`.

## Follow-up: centered campfire area

The campfire reserves a 3×3 area, with the unchanged fire model
centered on the cursor's tile. This aligns the fire with single-tile stools.
The cursor and queued plan show a validity-tinted area outline, which disappears
after installation. Neighboring areas may touch but cannot overlap. Installed
occupancy rounds the centered stone-ring bounds outward to the nine touched
tiles, so dwarves walk around the fire; queued plans remain walkable.

FurniturePlacementController reads the optional `placement_anchor: "center"`
and `show_placement_area: true` fields. Other furniture keeps its existing
cursor anchor, and plant outlines retain their established 3×3 behavior. The
saved origin remains the minimum corner of the footprint. Installed campfires
and pending plans always use the current 3×3 definition when loaded. The user
explicitly rejected preserving older development layouts: the campfire's legacy
override and layout version were removed. Reloading applies the current layout
without an uninstall/rebuild step. Backward compatibility for development saves
is not a project requirement; current-version save/load still works normally.

CampfirePlacementTest covers actual screen-space cursor centering, all four
rotations, unchanged art scale, preview/queued outlines, overlap and cancellation,
installed navigation, JSON round trips, current definitions on restored plans, and
normal worker reinstallation of the returned item. ProfessionCraftingTest,
PlantHabitatTransplantTest and DiningPlacementTest pass. Native previews and a
fire with four aligned stools were reviewed. Evidence in
`tmp/campfire_area_review/`: `area3.log`, `native.log`, the three regression logs,
`preview.png` and `installed_with_stools.png`. Earlier focused-test failures
were corrected assertions for the intentionally irregular ring and JSON number
normalization, not changes to the campfire art or save format. The subsequent
current-definition loading check passes in `current_definition.log` after removal
of the obsolete layout override.

## Follow-up: stools directly beside the fire

The player could not place stools on the four tiles immediately outside the
campfire area. The single wide, seat-to-head clearance box intersected low fire
geometry and the empty corners of neighboring seats. The earlier camp preview
used stools a tile farther away and did not reproduce the requested arrangement.

Log stools now define separate torso, hand and beard boxes plus cylindrical
head/hair clearance. The 1.375-block head radius covers the current modular
meshes (largest measured horizontal radius 1.349), allowing diagonally adjacent
diners without allowing genuinely overlapping heads. Campfire `seating_obstacles`
describes its low stone ring separately from the narrower flames. Navigation and
the fire's 3×3 placement area are unchanged. Boots rest beside the stump, clearing
the stones when the dwarf faces the fire.

FurnitureSeating owns region intersection for placing stools, finishing their
plans and adding furniture around them. DwarfIdleBehavior reuses that same
validation after navigation changes, so rounded grid occupancy cannot reject a
seat that the actual furniture geometry permits. Terrain, other entities,
supported floors, open access, exclusive seat claims and work interruption remain
checked. Wooden dining chairs retain their existing box clearance.

CampfireStoolTest passes all four adjacent positions in every rotation, queued
neighbors, restored plans, both construction orders, real terrain/furniture
obstructions and four dwarves walking to and remaining in the seats. Native
`four_seated.png` was reviewed. LogStoolTest, DiningPlacementTest and
DwarfIdleBehaviorTest also pass. Evidence: `tmp/campfire_stool_review/`, including
the named test logs and `native.log`.

## Follow-up: relaxed pose and facing the fire

Stool sitters previously copied the furniture's placed rotation and held their
hands wide beside the torso. Their hands now rest inward in front, while the torso
remains supported by the cut top and boots stay on the ground beside the stump.
The existing dwarf meshes and proportions are unchanged.

Round stools opt in to choosing a facing toward the nearest same-level campfire
within six blocks. Each visit selects a clear quarter-turn pose after checking
terrain visibility and the shared seating clearance. An off-axis fire adds a
bounded head turn. Backed chairs keep their authored facing. No usable fire means
the placed facing is used if it remains clear; removing a fire during rest clears
the gaze without spinning or stranding the dwarf.

InstalledFurnitureComponent holds a transient occupant yaw alongside its seat
claim. FurnitureSeating uses it when checking nearby furniture, and idle seating
uses it when revalidating after world changes. Cancel, normal stand-up and failed
approach release both. Rounded beard clearance covers the turned head as well as
the broad hair volume. No new save fields or compatibility logic were added.

CampfireStoolTest now deliberately places all four stools with the same rotation,
then verifies four actual dwarves sit facing inward with their parts clear of the
stones/flames. It covers missing, hidden, distant, obstructed and uninstalling
fires, off-axis gaze, removal while seated, cleanup and backed-chair behavior.
LogStoolTest, DiningPlacementTest and DwarfIdleBehaviorTest pass. Native renders
were reviewed for the four-sitter layout and close views with/without a long beard.
Evidence: `tmp/stool_rest_review/behavior_final.log`, `native3.log`, the three
regression logs; `tmp/campfire_stool_review/four_seated.png`, `relaxed_stool.png`
and `bearded_stool.png`.
