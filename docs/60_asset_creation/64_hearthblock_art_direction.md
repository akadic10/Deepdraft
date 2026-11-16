# 64 — Hearthblock art direction

**Hearthblock is Deepdraft's only art direction.** It means cozy, warm, friendly chibi
voxels built from squares and rectangles on the 1:16 grid. Models are designed for the
gameplay camera and lit like a hearth. The owner chose it on 2026-10-20. By 2026-10-21
everything the game can show had been converted and the owner signed off the result.

- [Lighting](#lighting) below holds the lighting pass (doc 255).
- [What is Hearthblock today](#what-is-hearthblock-today) below lists every converted family
  and where it is authored (doc 256); [62](62_furniture_catalog.md) gives each furniture
  piece's Tier 1 design.
- [61 — Voxel art authoring guide](61_voxel_art_guide.md) explains how to build a model.
- [63 — Technical art standard](63_shared_art_standard.md) gives the renderer, pipeline
  and acceptance rules.
- The approved proposal models are kept verbatim in `tools/hearthblock/art/proposal.mjs`.
  They come from the owner's proposal page, "Deepdraft Hearthblock Style".

Earlier art directions were retired on 2026-10-21 and their documents removed:
faceted low-poly (2026-10-12/13), the first 1:16 voxel look and the hand-hewn timber
concept with its chibi refinements (2026-10-18/19). Git history before that cleanup
still holds them. Do not revive them as targets.

## Scope and grid

Hearthblock covers every solid non-terrain asset:
- dwarves and their work tools;
- animals, trees and wild plants;
- furniture, construction pieces and stored goods.

It also covers the dressing drawn on terrain blocks.

- One cell is **1/16 of a world block on each axis**: 0.0625 Godot units. Sixteen cells
  span one block edge, and a block is one Godot unit. Objects may span several blocks
  at the same cell size.
- World blocks stay one unit with simple voxels. Hearthblock only dresses the stone,
  grass, earth and coal faces in the shader (`terrain_appearance.gdshaderinc`, values in
  `data/terrain/appearance_profiles.json` → `dressing`). Coal's edge is lit instead of
  dark, because a darker edge cannot show on the darkest block. Every mark is a whole
  cell, like the models. Built logs are the exception: each is drawn as a Hearthblock
  piece, the loose log stretched to fill its block with its bark drawn off (docs 275 and
  278; doc 24, "Built logs").

## Shape language

- **Squares and rectangles.** Build from boxes, notched boxes (clipped corners) and
  steps. Suggest curves with steps and notches; never use round or spherical geometry.
- **Chibi proportions.** Characters and animals have big square heads, compact bodies
  and short limbs. Hands, boots and paws are chunky. Eyes are beads with a glint.
- **Light tops, dark undersides.** Give each mass a lit top layer and a darker skirt or
  underside. Baked corner occlusion adds the soft contact shade.
- **Big shapes first, then a few one-cell details.** Seams, growth rings, cracks, pegs,
  knots, rope bands and moss patches explain the object. Never add random per-cell
  colour noise.
- **Deliberate wear.** One or two chosen marks per object, such as a drying split, a
  chipped corner or an axe chop. Place them on purpose; don't scatter them.
- **Readable at colony distance.** Each object must read at gameplay zoom first. Detail
  is for the close view.

## Colour and materials

- Warm, readable palettes with semantic roles (wood, bark, grain, rope, hay, stone,
  iron, leather and so on).
- Wood roles map to the existing source palettes, so every wood still recolours for
  pine, oak, juniper and apple through `CraftMaterials`. Stone, rope, hay, char and the
  game counters are fixed colours.
- Baked shade is stored per vertex in UV2, so recolouring matches the unshaded swatch
  at that shade.
- Dwarves wear one of six tunic colours (`DwarfAssets.CLOTHING`): teal, rust, moss,
  slate, ochre and plum. In the world, bead eyes are untinted. Portraits show the eye
  colour on the glint.

## Lighting

The Hearthblock lighting pass (doc 255, 2026-10-20) is part of the look:
- ACES tone mapping, with glow that only fire reaches. Flames are unshaded, and a flame
  gain above 1 lifts only them past the glow threshold, so lit walls and faces never
  bloom;
- a cool fill for sealed air and a camera-facing fill on actors and props underground.
  Both fade with sky access and stay subtle: they lift faces and shadows without
  flattening the torch pools;
- warmer fire lights and darker, warmer slice caps;
- burlap stockpile overlays.

**The sun's path leans 30° (owner, 2026-11-11).** A sun that climbed straight overhead gave every
top all of its light at the sky's midday and every side face none: bark, legs and a dwarf's face
dropped into shade together. With the lean it stands 60° up at midday, so sides toward it are
lit and shadows fall beside things all day (`sun.path_lean_degrees` in `sky_settings.json`;
doc 24, "Sky"). It was the owner's pick of three light changes; the other two, a weaker midday
sun and a plainer tone curve, dimmed the day or changed torchlit rooms and night.

The values are in `data/sky/sky_settings.json` → `hearthblock_lighting`. The main world
always uses this lighting; the old on/off toggle was removed on 2026-10-22. Judge new art
in the game under this lighting at gameplay and colony zoom, not in studio light alone.

Who applies it:
- `SkyController.hearthblock_active()` is true only in the main world scene
  (`debug_world.tscn`). Galleries, previews, thumbnails, portraits and test scenes keep
  their own Environment and materials. `SkyController` sets the world Environment's tone
  mapping and glow, and emits `hearthblock_lighting_changed` after every scene bind.
- `UndergroundLighting` sets the sealed-air floor and tint, the view fill (closed actor
  and prop materials only) and the cap tint on every material it makes. The shader
  defaults (`readability_tint`, `view_fill`, `slice_cap_tint`) leave a material unchanged.
- `FurnitureLighting` warms each fire light by furniture key (`light_colors`) and sets
  the flame gain.
- `StockpileDesignationController` draws confirmed zones in burlap, authored in sRGB and
  converted for the linear vertex overlay. The preview while drawing keeps its own valid
  and invalid colours, and the X-ray inspection shell keeps its neutral look.

## Furniture tiers

- **Tier 1 · Axe-Hewn Era** is the furniture in the game now. Pieces are split slabs,
  bark, chopped stepped ends, notches, rope lashings and loose hay, with no iron and no
  wool.
- **Peeled logs (owner, 2026-10-28, doc 278).** Log builders strip the bark before a log
  goes into a wall or a fence, and the dwarves do too. Built logs, fence posts, rails and
  gates are peeled. Their surface is each wood's peeled swatch (`hewn_peel`), with knots
  trimmed flush and drying checks instead of bark plates, and fresh-cut ends and notches.
  Furniture made from stumps and slabs keeps its bark, and so does the stockpile log, which
  is the log as felled.
  Knots and checks never sit on a lying log's top, which the play camera sees most. Barked
  walls were the tree trunks' brown, so a cabin sank into the forest at the default camera
  distance, and their bark plates repeated as a grid; peeled walls read as built. Fences and
  gates recolour from the built logs' source palette (`hand_hewn_timber`), so a pine fence
  matches a pine cabin. The approved study is in `tmp/peeled_logs_20261028/`.
  Since 2026-11-11 (the owner's pick of three) a fence post's top is chopped in two steps and
  its rails are lashed on with rope: from the play camera a flat top and plain rails read as
  a row of dots and two thin lines.
- **Fires hold no drawn wood (owner, 2026-10-28, doc 279).** The campfire and the hearth
  are stone and ash; the night's log is the real stockpile log a worker sets in them, shown
  in its own wood (`nightly_fire` places and scales it). Soot darkens the stone that faces
  the flame, which also keeps the fire's own light from washing that stone out. Their menu
  pictures show them burning a pine log. The hearth is a fire-back (owner's pick of four
  rudimentary concepts, 2026-10-29): an open fire against a stone back that throws its heat
  into the room. Since 2026-11-11 (the owner's picks) the back is one split boulder and the
  campfire's ring is five great stones, both in worked stone (below).
  `tmp/hearth_concepts_20261029/` holds the four concepts and their renders.
- **Tier 2 · Carpenter Era** is the look of what a Carpenter makes (owner, 2026-11-13,
  doc 308: "the carpenter starts with a saw, therefore I think the initial set of items the
  carpenter can make don't need to be rudimentary anymore").
  - **Sawn, but plain.** Thick boards, pegs and saw-cut ends: a clear step up from the camp's
    hewn logs, and as plain and thick as the copper tools. No carving, no turned legs, no iron
    and no cloth. Fine joinery waits for the iron saw.
  - **Made from planks,** which a Carpenter saws from logs (doc 44). Everything a Worker makes
    at camp stays Tier 1.
  - **Nailed in words, pegged in the drawing** (doc 313, 2026-11-16). A plank piece takes a
    copper nail to each plank and its description says nailed. The models were not redrawn: a
    knot-dark peg stands where a nail is, and no nail head is drawn in copper.
  - **Piece by piece.** A Carpenter's piece keeps its Tier 1 look until its plank look is
    drawn and picked; doc 308 has the list and the order. The first (the owner's picks,
    2026-11-13) are the Plank Dining Table, the Plank bench, the Tool Rack, the Finished Goods
    Pallet, the Board-game Table, the Raw Materials Crate and the Food Shelf, in `tier2.mjs`
    with the helpers every plank piece shares. That is every piece on the list.
  - **Field work stays hewn.** The fence and the gate are split rails on peeled posts, not
    planks: the owner found both plank fences "too busy" (2026-11-13), and a rail fence is
    split, not sawn. A Carpenter's furniture is sawn; what it puts up in a field is not.
  - **Nothing crosses the inside of a crate** (owner, 2026-11-13: "I don't think it needs
    connecting pieces through the middle"). A store's places are rules, not parts: the goods
    mark them.
  - **A sawn face is drawn one way** on every plank piece and on the plank good: as pale as a
    log's cut end on top, a step darker on a board's sides and dark underneath; the saw's
    strokes run across the board and stop short of its edges (a split face's lines run along
    it); pegs are as dark as a knot.
  - **What tells plank pieces apart at midday** is not their colour: every pale sawn face comes
    out the same cream. It is the strokes, the pegs, the gaps between boards and a step of tone
    from board to board, so draw those boldly, and give a piece legs or ends that show.
  - Its first designs, a plank dining table and a blanket bed, are in
    `tools/art_data/studies/hearthblock_furniture_tiers.json`, next to the Tier 1 studies, and
    as `diningTable()` and `bed()` in `tools/hearthblock/art/proposal.mjs`.
  **Never delete either tier's designs.**
- **Stone tools make rough work (owner, 2026-11-01).** "Dwarves have very basic tools and
  they can't quite make the things you're presenting with a chisel." A Worker's wood is hewn
  and split, never sawn, and stone is still split or knocked square, never dressed or tooled
  smooth: the mason's bench has a split slab, and the stone stool is a Rough Stone knocked
  square. Planks came with the Carpenter's copper saw on 2026-11-13 (doc 308; until then they
  waited for an iron one). The Stonemason's turn comes later (owner, the same day).
  - **Copper tools (owner, 2026-11-13, doc 306).** The Carpenter and the Stonemason now start
    with a copper saw and a copper chisel that a Blacksmith makes. The saw brings planks and
    the Carpenter's plank look (above); the Stonemason's pieces stay knocked for now. The
    copper tools themselves are a first copper age,
    hammered and cast in a stone mould: plain and thick, the copper bar's own colours, hafts in
    the wood they were made from, bound with rope. The saw is a Japanese pull saw (the owner's
    words): a long straight handle in line with a thin blade.
    - **Copper is drawn dark.** At the sky's midday the bar's pale top (`E09A5C`) reaches the
      screen as pale as pine, and a saw blade drawn in it read as wood ("Noon lifts every light
      colour", below). A copper tool is the bar's body colour over its shade, and the pale
      colour marks only what was ground or filed: edges, points and teeth. By torch the body
      colour is the reddest thing in the room.
    - **No tool holds more copper than the bar it is made from** (256 cells), and none is
      longer than a rack's hook is high (39 cells); `tools/voxel_assets/test_items.py` checks both.
- **Stone is drawn as wood is (owner, 2026-11-10, doc 301).** A log has bark outside and a
  pale cut face inside a bark rim. Stone furniture has a dark weathered skin outside and pale
  fresh stone where it was split or knocked, the fresh face one cell inside a ledge of skin.
  The owner picked this over the Rough Stone's own greys and over the mountain's own colour,
  which vanishes into a rock floor.
  - Marks are cut in, never stuck on: a crack is a slot, a knocked corner leaves a fresh scar,
    spalls lie on the ground. A lighter rectangle raised on a face reads as a label, and one
    let into it as a window.
  - Corners are cut square, as the world's boulders are. The diamond that `cut` clips gives
    one-cell stairs, which read as ribbing on a stone.
  - Stone is thick. The mason's slab is 8 cells on short stumps; at 4 cells it read as a board.
  - A boulder is tiers out of line with each other, with a lump against one flank. Tiers that
    match on every side read as a stove.
  - Colour alone cannot stop stone looking pale, because noon light lifts every light grey.
    The dark skin and the shape do. The skin is a neutral, slightly cool grey: a warm one
    turns wood-brown by torch.
  - The mason's bench, the stone stool, the basic smelter, since 2026-11-11 the hearth and
    the campfire, and since 2026-11-14 the anvil stone (doc 310) are built this way.
  - A fire's bed is burnt black out to its stones: grey ash merged with the stones' skin, which
    noon lifts to a middle grey.

  The approved sheets are in `tmp/stone_concepts_20261110/` and `tmp/smelter_stone_20261110/`.
- **A top is a split log's face (the owner's picks, 2026-11-10, doc 301).** The play camera
  looks down, so a top is most of what shows, and one flat colour reads as a blank. A riven
  face shows bark on both edges, pale sapwood inside it, a darker band of heartwood down the
  middle with the pith as a broken line, a knot or two, an axe's bites and a drying split
  (`rivenX`, `heartX` in `tier1.mjs`). The dining table, the board-game table and the
  carpenter's bench are drawn this way. Legs show: the dining table stands on a stump at each
  corner, and a bench says whose it is when nobody is at it (the Carpenter's chopping block).
  A deck is laid the same way: the finished goods pallet is four broad halves and the food
  shelf's decks are broad halves (the owner's picks, 2026-11-11), because narrow poles read
  as stripes however their faces are drawn.
  The approved sheets, with the concepts passed over, are in `tmp/bulk_concepts_20261110/`.
- **Bark is drawn in ridges, not plates (doc 301).** A raised plate of lighter bark reads as a
  panel stuck on, and on a broad stump as a drawer. Bark splits into upright ridges, painted
  flush and uneven in length (`stump`, `logStool`, `workbench` in `tier1.mjs`). A great stump is
  not a squared slab either: the crude workbench is the stump of a felled tree, with roots that
  give it an outline of its own and the felling cut along one side. A lying log's bark runs in
  ridges along it: the tool rack hangs bark side out, and the log bench was one whole log with
  a seat hewn along its top (the owner's picks, 2026-11-11; the bench is a plank piece since
  2026-11-13, doc 308, and the sitting log's design is kept).
- **Noon lifts every light colour (doc 301).** Pine's split face, stored `#CBA45B`, reaches the
  screen at noon as about `#DAC588`; made as dark as oak it would still render `#D3B775`. No
  recolour holds a light colour at noon, so shape and marks carry a pale piece. Pine was
  deepened one step on 2026-11-10 (the owner's pick of three): it stays the palest wood and the
  yellowest, and must not meet oak. Those values were measured at 12:00, under a sun that still
  climbed straight overhead. The sky's midday is its own event, not 12:00 (14:00 by the clock in
  the 2026-11-10 save). Since 2026-11-11 the sun's path leans (see Lighting), and at the sky's
  midday pine's face reaches the screen as about `#D6C083`. No change of light makes a pale top
  dark: a weaker sun, the lean and a plainer tone curve were measured on
  `tmp/proposals_20261111/sheets/E_midday_light.png`. Judge a piece at the sky's midday, not at
  noon by the clock.

## Art over rigs (owner rule, 2026-10-21)

From the owner (2026-10-21), adopting the re-proportioned deer: "we should not be
constraining the new art direction due to old joints".

Old joints, pivots, envelopes and pinned shapes must not constrain the art. When the
art needs new proportions:
- move the joints into data (`visual_pose` in the animal definitions,
  `data/dwarves/proportions.json`);
- change the rig;
- update tests that only pin old shapes.

Real gameplay contracts still hold. When one blocks the art, propose a change to the
owner instead of working around it. The current contracts:

- **Furniture** keeps its footprint, collision, seat and sleep heights, door openings
  and hinges, and walking surfaces. The heights, from the definitions in
  `data/furniture/`, are:
  - stool top 0.875 blocks;
  - bench seat 1.0;
  - log bed sleep surface 0.75, with the bed no taller than 15 cells;
  - table tops 1.5;
  - workbench top 1.0.

  The dining and game tables are 3 × 3; the dining table takes four stools in a 5 × 5
  layout and the game table two opposite stools (3 × 5). A seated
  dwarf sits 3 cells back on the stool, and no head cell may enter the tabletop
  (`test_dining_table`). Every table cell stays inside the definition's
  `seating_obstacles`, so seated legs stay clear (`test_hearthblock`). A diner's posed
  boots must clear those boxes too (`LogDiningTableTest`), so a table seat keeps the boots
  beside the stool (`rest_pose` feet at -0.125) and a table may have legs at its corners. The
  board-game nod pivots at the neck, so a long beard swings back from the table edge.
  The bench is 2 × 1 with one seat. Door leaves are `leaf_left` and `leaf_right`,
  hinged at the outer edges.
- **Dwarves** grip tools at the palm, cell (17, 20, 3). The support grip is 10 cells up
  the haft. Strike points are axe (0, 17, 11), pickaxe (0, 22, 15) and the Farmer's hoe
  (0, 22, 10). Hand tools are stone bound with rope until the Blacksmith's iron (doc 41b);
  the hoe is copper, as the Farmer's tool is (doc 309). The head obeys
  these layout rules:
  - fringes start at y 45 and brows sit at y 40–44;
  - nothing goes above y 54;
  - beards end at y ≥ 12 so a striding boot passes under them;
  - below y 18, anything on the head stays within z 11.

  A lying head rests on its lowest cell, measured once per dwarf (`DwarfRestBehavior`),
  so a back bun lifts the head instead of sinking into the bed.

  A trade's hat (owner, 2026-11-12; doc 41b, "Trade hats") sits on any head and any hair, so
  it keeps rules of its own:
  - it is solid from the hat line, y 45, up, and covers the head of every age; hair under it is
    the style's own cut at that line;
  - below y 50 nothing goes past z 12, three cells proud of the face. A peak or a brim hides the
    brows and eyes from the play camera, so trades differ on top, at the sides and behind;
  - its back stands at z -13, where a bun's cut meets it;
  - it shares no face with any head, brow, beard or hairstyle;
  - a hat ends at y 54 as hair does; a feather or a candle may rise above it. In a tunnel three
    blocks high they stand in the ceiling's rock, as hair tops do.

  A hat's colour is never its only mark: torchlight turned teal into the Ranger's green and
  pulls ochre and rust together. The mark on top carries it (a candle, a feather, a button, a
  dusted top, folds and a scorch).
- **Animals** keep their navigation footprints and clearances. Deer need four blocks of
  headroom, and the rabbit fits one block. Squash and stretch keeps volume and feet,
  and no foot dips below ground.
- **Trees and plants** keep heights, clearance under the canopy, felling, variants and
  every growth, season, picked and packed state. Trunk footprints come from each tree
  definition. Saplings and wild plants never block movement.
- **Rocks:** boulders are 2 × 2 × 2 and block movement. Scree is 3 × 3 and stays low
  enough to walk over, at most half a block high.
- **Goods** keep their footprints, so carrying, crates and stockpile tiles are
  unchanged.
- **Terrain** blocks stay one unit; the dressing is shader-only.

## What is Hearthblock today

| Family | Authored in |
| --- | --- |
| Dwarves, hair, beards, brows, trade hats, work tools | `tools/hearthblock/art/dwarves.mjs` |
| Tier 1 furniture, hearth, campfire, kits, flag | `tools/hearthblock/art/tier1.mjs` |
| Animals | `tools/hearthblock/art/wildlife.mjs`, rigs in each animal's `visual_pose` |
| Trees | `tools/voxel_assets/trees.py` (square crowns, `square_pine`) |
| Bushes, wildflowers, reeds | `tools/voxel_assets/plants.py` (notched square clumps) |
| Field vegetables and the bare tilled tile (doc 309) | `tools/voxel_assets/crops.py`, beside the brewing crops' placeholders |
| Stored goods the game can produce | `tools/voxel_assets/hearthblock_goods.py` |
| Boulders and scree | `tools/voxel_assets/rocks.py` |
| Materials crate | `tools/voxel_assets/construction.py` |
| Terrain dressing | `terrain_appearance.gdshaderinc`, `appearance_profiles.json` |
| Menu pictures | `FurnitureCatalogThumbnails.gd`, `InventoryCatalogThumbnails.gd` |
| UI icons (doc 259) | `tools/hearthblock/art/icons.mjs`, rendered by `tools/GenerateUiIcons.gd` |
| The Sky Dial (doc 23) | `tools/hearthblock/art/sky.mjs`, rendered to layers by `tools/GenerateUiIcons.gd` |

Placeholders that are not Hearthblock yet, because the game cannot produce them yet:
the brewing and weaving crops (hops, grape vine, pig tail, plump helmet); drinks, staves, cloth,
honey, the water bucket, grapes, hops, plump helmet, pig tail and their cuttings and seeds; the fossil
and the gold coin. Author each one in Hearthblock when its feature arrives. Don't
convert content ahead of its feature.

UI icons are Hearthblock too (owner, 2026-10-23):
each is a small Hearthblock model rendered with a dark outline and drawn on a tile in its
command family's colour. Since 2026-10-27 every UI icon is one, the badges over dwarves'
heads and the DEV-only Development menu included; no painted sheet is left.
The Sky Dial is Hearthblock too: a stone window onto the sky, built from models and
rendered to layers (owner, 2026-10-26).
The painted loading screens stay a separate medium.

## Making new art

1. Prove the idea with real cells. Use the proposal's box and notched-box vocabulary,
   not a painted concept that cannot be built at 1:16.
2. Show the owner before anything is installed (owner, 2026-11-10: "will you propose the new
   art first?"). Put two or three concepts on one sheet beside today's piece, in studio light
   and in a copy of the colony at the owner's camera, at noon and by torch, and say which you
   would pick. In the 2026-11-09 save that camera is pitch 45 and zoom 20, where a cell is
   about 8 px on the owner's screen, so one-cell detail shows. The camera differs from save to
   save: 64° down at zoom 30 on 2026-11-06 and 60° at zoom 29 on 2026-11-10, where a cell is
   about 5.5 px and a top is nearly all that shows. Show the newest save's view beside the close
   one.
3. Build it through the normal pipeline ([61](61_voxel_art_guide.md)) and review the
   gallery.
4. Look at it in the game under Hearthblock lighting, close up and at colony zoom, with a dwarf
   standing beside it. A dwarf is 3.3 blocks tall with a head as big as a stool, so a piece that
   looks right alone can look like a toy at its feet (the first boulder smelter did).
5. Keep the gameplay contracts above, or propose a change to them. Check a concept against a
   contract with the piece's own Godot test, not by hand: the dining table's sheet called corner
   legs safe from the seats' clearance boxes, and the diners' posed boots clipped the stumps.
6. Re-render the menu pictures that show the model.
