# 256 — Hearthblock art: Tier 1 furniture, every dwarf, all animals, trees, wild plants and stored goods

Step 2 of the Hearthblock direction (see [255](255_hearthblock_lighting_pass.md) and
[64](../60_asset_creation/64_hearthblock_art_direction.md)), built in the game rather
than in a study viewer. The pilot (stool, dining table, torch, campfire, one dwarf)
was accepted on 2026-10-20; the owner then asked for the Tier 1 furniture pass and
the remaining dwarves overnight.

## What changed

**Furniture: Tier 1 · Axe-Hewn Era.** Split, chopped and notched with an axe: bark
stays on, ends step back like axe cuts with square end rings, joints are notches and
rope lashings, no iron. Every piece keeps its frame, footprint, collision, seat and
sleep heights, hinges and walking surfaces, and all four woods.

| Piece | Tier 1 design |
| --- | --- |
| Log Stool | Bark stump, raised bark plates, square growth ring, drying split (proposal). |
| Log Dining Table | Split-Slab table: two riven halves on two short logs crossed in a notch. The upper cross log is shortened to the centre block so seated legs stay clear. |
| Board-game Table | The same table with a knot-dark board scratched into the top and six 4 × 4 counters. |
| Log bench | Half of a split log dropped into notches in two short logs (feet centred at ±10 cells). |
| Crude Workbench | One great squared stump: root flare, bark plates and rim, growth rings, drying crack, chopping notch. |
| Log bed | The proposal's Notched Log Bed; hay under the sleeper's torso is flat and one leaf lowered to keep 15 cells. |
| Log doors (2, 3, double) | Vertical split slabs with bark edges and stepped chopped tops, pegged battens on both faces, rope lashed round the hinge end, a rope pull loop. |
| Fence post, rails, gate | Squared pole with a chopped point and rope bands at rail height; split-pole rails; gate of chopped stiles, split rails and a stepped brace. |
| Rough ladders (1–4) | Bark poles with chopped tops; stick rungs every 8 cells lashed with rope. |
| Log bridges (1–5) | Four split logs, riven face up; the deck ends short so both ends settle into the banks; rope lashings near each bank. |
| Ladder/bridge kits, packed furniture | Rope-bound bundles of poles and split logs; a crate of split slats on bark corner posts. |
| Hearth | Squared stones in uneven courses on a hearthstone, a lintel, crossed logs, embers, soot. |
| Torch, campfire | Proposal designs (wooden peg torch; eight-stone campfire); animated flames unchanged. |
| Settlement flag | A rough pole in a stone cairn, a lashed crossbar and the banner. |

The water stones are rocks and unchanged. Tier 2 · Carpenter Era designs remain in
`data/art/studies/hearthblock_furniture_tiers.json` and `proposal.mjs` (never delete).

**Dwarves: every appearance.** All dwarves now have the proposal's square head (four
ages: smaller nose for young, a forehead line for middle age, elder dome, wrinkles
and crow's feet), bead eyes with a glint, potato nose, rosy cheeks and smile, flared
tunic with brass buckle, chunky mitten hands and square boots. All 14 hairstyles, 7
beards, 8 brow styles and 4 portrait scars keep their IDs and pools and are redrawn
for the square head (twin braids, swept cut and the block and forked beards come
straight from the proposal). Saves, names, tints, tools and animations are unchanged.
The pilot switch is retired; sleeping eyelids are refitted to the bead eyes. In the
world the bead eyes are untinted; portraits show each dwarf's eye colour on the glint.

**Dwarves without the old rig limits** (2026-10-21; the owner: "you are not be
constrained by existing stuff"):

- **Hands:** the proposal's mitten with its tunic cuff. The cuff is a second, untinted
  mesh in `hand.glb`, so the skin tint never colours it.
- **Relaxed hands** hang under the sleeves as on the proposal page. `proportions.json`
  moves them 3 cells in, 5 down and 3 back. Every work pose still grips the palm at
  (17, 20, 3).
- **Boots:** the proposal's cuffed boot, 9 cells wide and 15 long, with a folded cuff
  one cell proud all round.
- **Long beards:** the spade, forked, braided and long-plait beards hang to the belt,
  as in the proposal.
- **Seating at tables:** a seated dwarf now sits 3 cells back on the stool, set in the
  `log_table` and `board_game_table` chair profiles. The beard hangs in front of the
  table edge instead of through the top.
- **Back bun:** the bun is a real knot at the back of the head. A lying head rests on
  its lowest cell, which `DwarfRestBehavior` measures once per dwarf. The bun lifts
  the head about 1.5 cells instead of sinking into the bed.

**Wildlife, trees and plants.** Every animal, tree and wild plant is Hearthblock. Crops
keep placeholder models until farming arrives.

- **Animals: all four species** (owner-approved 2026-10-21). All are chibi: square
  blocks, bead eyes with a glint, species palettes unchanged.
  - Rabbit: a big square head with front bead eyes and chubby cheeks on a small loaf,
    big hind feet, one tall and one floppy ear, a cotton tail. It still fits one block
    front to back and side to side, and stands 1.5 blocks tall.
  - Ducks: a big square head with a wide flat bill on a round little hull, a stub tail
    and big paddles. Both sexes share one shape (drake: green head and white ring;
    hen: browns).
  - The duck's folded wings are their own mesh on the flanks (two new parts), shown
    whenever it is not flying. The open wings appear only in flight.
- **Chibi deer and wolf.** The first pass squared both animals inside their old rigs
  and read as square versions of realistic animals. The owner compared a
  re-proportioned deer and adopted it: "we should not be constraining the new art
  direction due to old joints". Both now have big square heads, short legs and compact
  bodies. Deer: square barrel with a cream belly and white rump, short neck, big head
  and snout, antlers of squared tines with depth (brow tine forward); 2.9 blocks to
  the antler tips (was 3.75). Wolf: boxy body with a dark saddle, pale belly and chest
  ruff, big head with a long snout, cheek ruffs and amber eyes, tall stepped ears, a
  curled bushy tail, big paws; 2.4 blocks to the ear tips. Hoof and paw soles narrow
  so a striding corner never dips below ground.
- **Rigs follow the art.** The deer's joints moved from `DeerAgent.gd` into
  `visual_pose` in `data/entities/animals/deer.json`: neck, head, ears, hips, knee,
  sleeping rest, and a 2-cell forward shift that keeps the resting footprint. The
  wolf's existing `visual_pose` got new head, tail, hip, knee and rest values. The
  rabbit's head and ears and the duck's head, wing shoulders and feet moved into their
  own `visual_pose`. `wildlife.py` reads each knee split from the same data.
  Navigation footprints and clearances are unchanged; deer still need four blocks of
  headroom.
- **Squash and stretch.** Each animal's visual root squashes as it pushes off and
  lands, and stretches mid-step, keeping its volume and its feet
  (`GrazerAgent._squash_stretch`).
  - The amount is set per species in `visual_pose.squash`: rabbit .12, duck .06 (on
    land), wolf .045, deer .035.
  - Every voxel part stays rigid, and standing, grazing and sleeping animals are not
    scaled.
- **Trees: all four species** (oak first as the pilot; pine, apple and juniper on
  2026-10-21). Every tree keeps its seeded skeleton and gameplay:
  - heights, walking clearance under the canopy, felling, variants;
  - growth, season and picked states;
  - connected bare winter limbs.

  The shapes:
  - Timbers are squared and stepped.
  - Oak, apple and juniper crowns are square tiered clumps, dark below and light on
    top, with offset side clumps. Apple blossoms and fruit and juniper berries still
    sit on the real crown faces.
  - The pine (`square_pine`) is square bough plates, each lit on top with a dark
    underside, over a narrower core that the next plate overhangs. It is widest at
    the base and steps in to a chunky square spire. In winter, snow settles on every
    plate.

  Trees get no baked occlusion: on their large stepped faces it tripled the
  triangles, while the square geometry alone is lighter.
- **Bushes and small plants: all five** (2026-10-21), built in `plants.py` from
  notched square clumps (the trees' clean corner at plant scale), pads and stalks,
  with baked occlusion. Picking, packing, growth and seasons are unchanged.
  - Blueberry and elderberry (`_square_shrub`): canes under clumps with a dark skirt
    and a lit cap. Ripe berries sit on each clump's outward faces. Bare forked canes
    in winter.
  - Blueberry: white bells in spring, blue berries in summer.
  - Elderberry: flat cream umbels in spring and summer, heavy purple clusters in
    autumn.
  - Wild strawberry: rosettes of three square leaf pads on runners, plus-shaped white
    flowers, square red berries with a green cap.
  - Wildflowers: square stalks with L-shaped leaves and chunky square heads (a cream
    daisy, a two-tier purple aster, a yellow flower).
  - Reeds: square stalks and L-shaped blades with square cattails.

**Stockpile goods: the 25 the game has today** (2026-10-21; `hearthblock_goods.py`,
with baked occlusion). Goods the game cannot produce yet keep placeholder models in
`items.py`: drinks, staves, cloth, honey, the water bucket, grapes, hops, plump
helmet, pig tail and their cuttings and seeds, the fossil and the gold coin. Every
good keeps its old footprint, so carrying, crates and stockpile tiles are unchanged.
- **Mined:** rough stone, three soils and six ores as broken square chunks (a tall
  block and a lower one on a wide base, a crack, lit tops). Ores carry two-cell
  stepped seams and raised nuggets; soils are stepped mounds; coal glints.
- **Gems:** six raw gems as clusters of three square crystals with stepped points and
  lit facets.
- **Logs:** pine, oak, apple and juniper. Each is the Tier 1 stool on its side, cut
  end toward the front, with its root flare replaced by a second cut end. It is drawn
  in that wood's own colours.
- **Crates:** produce, tree seeds and cuttings (12 goods, 3 fill levels). The crate is
  axe-hewn: split slats on bark corner posts with a rope band. Inside sit square
  apples, berries, strawberries with green caps, acorns with caps, stepped cones,
  seeds and cuttings, on a bed of the same goods.
- **Starter tools:** square stone heads lashed to their hafts with rope. The wood
  still recolours for the crafted material.

**World rocks, construction and clothing** (2026-10-21):
- **Boulders** (`rocks.py`): broken square rocks of stacked notched blocks, with a
  crack, chipped corners, lit tops and a few square moss patches. They keep their
  2 × 2 footprint and 2-block height.
- **Scree:** a clutch of small notched stones, some with a smaller stone on top. It
  keeps its 3 × 3 footprint and stays low enough to walk over.
- **Plank floor** (`construction.py`): Tier 1 split planks, two eight-cell boards per
  tile over a dark joist layer, with dark seams, staggered ends, pegs, grain, a knot
  and an axe chop. The alternate tile flips the stagger. Both stay solid 16-cell
  blocks.
- **Materials crate:** the same axe-hewn crate as the stockpile goods.
- **Stone floor:** unchanged. It needs a Stonemason, who is not in the game yet.
- **Clothing colours:** each dwarf wears one of six tunic colours: teal, rust, moss,
  slate, ochre and plum (`DwarfAssets.CLOTHING`).
  - The baked teal torso and both mitten cuffs are recoloured with the same
    shade-aware recolour the woods use (`CraftMaterials.apply_colors`), one shared
    mesh per colour.
  - The colour is saved in the appearance as `clothing`. Dwarves without one, from
    new games or earlier saves, get it from their id, so neighbours differ and no
    other appearance roll changes.

**Work tools, terrain and menu pictures** (2026-10-21):
- **Work tools** (`dwarves.mjs`, the same iron, steel, haft wood and leather wraps as
  before): square hafts with a lit grain face.
  - The felling axe has a square socket collar, a heavy cheek and a flared bit with a
    bright edge.
  - The pickaxe has a square socket, two square arms stepping down to steel points.
  - The grip at (0, 0, 0), the support grip 10 cells up the haft and the strike
    points (axe 0, 17, 11; pickaxe 0, 22, 15) are unchanged.
- **Terrain dressing** (`terrain_appearance.gdshaderinc`, the proposal's "Dressed"
  world blocks), for the stone, grass and earth profiles only. Bedrock and ore blocks
  are unchanged.
  - Each block gets a one-cell darker edge ring, a fine seam, ±5% variation between
    blocks, and three quiet two-cell flecks.
  - About one block in eight is marked: a stepped one-cell crack on stone and earth,
    a paler worn patch on grass.
  - Every mark is a whole 1:16 cell, like the models. Marks fade before a cell drops
    below a pixel, and on slice caps they stay quiet.
  - The values live in `appearance_profiles.json` → `dressing`; zeroing them turns
    the dressing off. The fine seam replaces the old soft seam on those three
    profiles.
- **Menu pictures:** the build-menu furniture thumbnails, the in-game goods' item
  icons and the floor icons were re-rendered from the new models with their own
  tools (`FurnitureCatalogThumbnails.gd`, `InventoryCatalogThumbnails.gd`,
  `GenerateFloorIcons.gd`). Icons for goods not in the game were left as they were.
  `GenerateFloorIcons.gd` used to draw the coarse shadow proxy over the floor, which
  showed as a white cube. It now draws only the visual meshes, as the other two tools
  do.
- **Checks:** the dwarf tools pass `ItemFacetedArtTest` and `DwarfFacetedArtTest`
  (grips, strike points), plus `MiningAnimationTest` and `TreeFellingTest`.
  - The in-game review (`RunLightingReview.ps1`, label `terrain_dressed`) passes with
    no shader errors.
  - Hall-view GPU median with the Hearthblock lighting on went from 5.45 to 5.70 ms
    at 3840 × 1080. That covers the dressing and all of this day's model changes.
  - `TerrainAppearanceTest` still fails its old mineral-profile discovery check, as
    it did before this work.

## How it is built

- `tools/hearthblock/art/`: `proposal.mjs` (the approved proposal models, verbatim),
  `tier1.mjs` (furniture), `dwarves.mjs` (every dwarf part). `write_data.py` runs
  `export.mjs` and writes `data/art/voxel_hearthblock.json` with each model's
  operations, palettes and pilot edits. `tools/voxel_assets/hearthblock.py` replays
  them; the furniture and dwarves families use them through the normal
  `build.py --install` gate.
- Wood roles map to the existing `hand_hewn_timber` and `oak_log` source palettes,
  so every wood still recolors. Stone, rope, hay, char, banner and counters are fixed.
- Dwarf wearables: any hairstyle can meet any beard and brows, so `dwarves.py` clips
  wearables against the torso, beards against every man's hairstyle and brows against
  fringes and beards, then applies the existing head-overlay rule and culls against
  the cells all four heads share. A combination check finds no shared cells and no
  coincident faces. Layout rules: fringes from y 45, brows y 40–44, nothing above
  y 54, beards ending at y ≥ 12 so striding boots pass under them. Below y 18,
  anything on the head stays within z 11: seated at a table, the head sits 6 cells up
  and 3 back, and `test_log_table` checks every head cell against the tabletop.

## Baked occlusion

Opt-in in `greedy_mesh_from_voxels(..., occlusion=...)`; other families rebuild
byte-for-byte. Each face corner counts its two side cells and one diagonal cell:
curve `[0.5, 0.68, 0.85, 1.0]` from `data/art/voxel_occlusion.json`, as on the
proposal page. Floors (and the torch's wall) count as solid for shading only. Faces
merge only when color and all four corner levels agree; the diagonal follows the
brighter pair. Darkened wood ramps collide (oak bark equals oak wood_dark at the
second level), so each shaded vertex stores its shade in `TEXCOORD_1` (Godot UV2)
and `CraftMaterials._recolor` matches the unshaded swatch at that shade within one
8-bit step. `test_hearthblock` simulates that recolor on every shaded vertex.

## Verification

- Install galleries pass for furniture (33), dwarves (43) and presentation (3); all
  three installed through `build.py --install`; headless imports clean.
- Python: all 76 asset tests pass, including the new `test_hearthblock` (routes,
  wood swatches, exact shaded recolor, table seated-leg clearance, bench seat, rig
  anchors). Updated for the intended art change: production routes in
  `test_hand_hewn_timber`, `test_log_bench`, `test_game_table`; the eye contract in
  `test_dwarves` (eyelids must cover the bead eyes).
- Godot headless: `FurnitureFacetedArtTest`, `FurniturePilotMaterialTest`,
  `FurniturePilotDoorTest`, `FurniturePilotBedroomTest`, `LogFurnitureTest`,
  `LadderTest`, `LogBridgeTest`, `GridFenceTest`, `RudimentaryRecreationTest`,
  `DwarfFacetedArtTest` (800 combinations, grips, soles, rest clearance),
  `DwarfRosterTest`, `DwarfRestTest`, `DwarfReadabilityTest`, `DwarfPilotRestTest`,
  `DwarfDiningTest` pass.
- Already failing before this work (stale fixtures, not rerouted here):
  `CampfireStoolTest`/`FurniturePilotSeatingTest` (retired storage chest),
  `DiningPlacementTest` (retired wooden chair), `DwarfInspectorTest` (retired wooden
  table), `FurniturePilotArtTest`/`DwarfPilotArtTest`/`DeerPilotArtTest` (expect single
  meshes without shadow proxies or knee splits), `ProportionIntegrationTest` (expects 0.8/0.93 width factors; data is 1.0).
- Pilots: Python `test_wildlife` (deer now pinned to the Hearthblock deer, knee split
  read from `visual_pose`), `test_plants`, `test_trees` pass; Godot `WildlifeFacetedArtTest`,
  `RabbitWildlifeTest`, `DeerWildlifeTest`, `DeerPilotWildlifeTest`, `DeerPopulationTest`,
  `HerdArrivalTest`, `ArrivalEventTest`, `WolfWildlifeTest`, `DuckWildlifeTest`,
  `DuckSolidBoundsTest`, `SurfaceVegetationArtTest`,
  `ShrubPilotTest`, `ShrubRegrowthTest`, `ShrubCuttingTest`, `ShrubTransplantTest`,
  `TreeFellingTest` and `TreePilotTest` pass. Authoring: `wildlife.mjs`, `plants.mjs`
  (`tools/hearthblock/art/`); the oak lives in `trees.py` (`HEARTHBLOCK=('oak',)`).
  Updated for the chibi deer: `DeerWildlifeTest` now expects a standing deer taller
  than 2.5 blocks (was 3), and `DeerPilotArtTest` reads its anchors from `visual_pose`.
  It still fails for its older single-mesh expectation.
- Unbound pass (2026-10-21): the dwarves (43) and wildlife (23) galleries pass, both
  families are installed and the import is clean. Python passes all 76 tests. Godot
  passes the dwarf, seating, bed, hauling, board-game and all wildlife tests listed
  above, plus `HaulingAnimationTest`, `MiningAnimationTest`, `TreeFellingTest` and
  `LogDiningTableTest`. Tests changed to check
  gameplay contracts instead of old shapes:
  - `test_dwarves`: the palm grip, the sole on the ground, the boot gap and the
    eyelids, replacing the old hand and foot envelope.
  - `test_log_table`: no head cell may enter the tabletop, replacing the old
    "everything above y 20" rule.
  - `LogDiningTableTest` and `RudimentaryRecreationTest`: posed faces are checked
    against the table instead of the parts' combined bounding boxes (helper
    `VoxelFaceClearance.gd`).
  - `HaulingAnimationTest`, `MiningAnimationTest` and `TreeFellingTest`: read the
    relaxed hand pose from the agent.
  - `DwarfFacetedArtTest`: the hand has two meshes, the mitten and its cuff.
  - `WildlifeFacetedArtTest`: 23 parts; the root may squash while keeping its volume.
  - `test_wildlife`: covers the folded wings.
  - `test_retirements`: 384 models.
- Behaviour changes in the same pass:
  - The board-game nod now pivots at the neck, so a long beard swings back from the
    table edge.
  - A feeding duck dips its bill; it used to lift it.
  - Duck paddles lift by their reach while swinging, so the longer toes stay above
    ground.
- Trees, plants and goods (2026-10-21):
  - The trees (94), plants (76) and items (88) galleries pass, and all three families
    are installed and imported. Python passes all 77 tests.
  - Godot: `SurfaceVegetationArtTest`, `TreePilotTest`, `ShrubPilotTest`,
    `FlowerPilotTest`, `TreeFellingTest`, `JuniperHarvestTest`, `ShrubCuttingTest`,
    `ShrubTransplantTest`, `ItemFacetedArtTest`, `HaulingAnimationTest`,
    `LooseItemSupportTest`, `WorkerCraftingStumpTest` and `DwarfFoodTest` pass.
  - `test_items` checks the new shapes: the stool-on-its-side logs, the crate
    joinery, and mined goods as one solid at the carry size with visible ore.
  - `ItemFacetedArtTest` now matches each wood vertex to its swatch at the vertex's
    baked shade, like the furniture test.
  - Triangles for the 60 converted goods: 24,850 → 44,026. Baked occlusion roughly
    doubles a crate (about 556 → 1,050).
- Rocks, construction and clothing (2026-10-21):
  - The rocks (6) and construction (4) galleries pass, and both are installed and
    imported. Python passes all 77 tests.
  - Godot: `DwarfFacetedArtTest` passes, now also checking six tunic colours in a
    row, each saved. `DwarfRosterTest`, `GroundStoneArtTest`,
    `SurfaceDetailLayoutTest` and `FloorConstructionTest` pass.
  - `BoulderPilotTest` and `ScreePilotTest` pass their checks but log a world
    generator index error from their fixture (`WorldGenerator.gd:1614`). This is
    not the rocks.
  - `ToolPromotionTest` fails because the loose-tool search
    (`ItemDropManager.advance_material_quote`) skips the reachable kit in its
    "blocked nearest tool" step. The item code is unchanged since the last commit,
    so the failure is not from this art pass.
  - The scree's resting stones were limited to keep it walkable, at most half a
    block high.
  - `tools/DwarfRosterPreview.gd` cycles tunic colours, because its actors all
    share id 0.
- Native roster captures (every style, ages, brows, rear, torch light, colony view,
  portraits, walk/mine/fell/rest) in `tmp/hearthblock_pilot_20261020/roster/`.
- Triangles: furniture 49,540 → 55,800 in total (tables, workbench and bridges are
  lighter; the hearth rises 1,350 → 5,628 and the bed 1,452 → 3,716); a typical dwarf
  about 2,600 → 4,400. Unmeasured on low-end hardware.

Restart Play to see it. No Windows export was made.
