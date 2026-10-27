# 275 — Build's Stone and Wood menus, and logs

From the owner, 2026-10-26, looking at Build's tool bar. Clicking Stone or Wood should open
a menu:
- **Stone** lists native stone, with other stones to follow.
- **Wood** starts with logs that fill a whole block, laid upright or horizontal (two menu
  items), so the colony can build log cabins like the owner's Pokopia reference.

Where horizontal logs cross in a + they should look as if the dwarves cut them to overlap.
The player picks the wood, apple included, and a built log closely matches the loose log
the colony stores.

Phases 1 to 3 are built (2026-10-26): see "Phase 2, built". The owner's look in game is next.

## Today

- **Build's tool bar** shows MATERIAL as four pictures: Stone, Dirt, Grass and Wood.
  - A click, or Q and E, picks one, and Build opens on the last one used. There are no
    menus.
  - The code: `ConstructionController.tool_bar_state` and `ToolBar._choice`, over the kinds
    whose `tool` is `build` in `data/construction/blocks.json`.
- **Stone** costs 1 rough stone and becomes the natural rock of its layer.
- **Wood** costs 1 log of oak, pine or juniper, whichever reaches the crate.
  - It becomes `base:construction:wood:<log>`, and mining gives that log back.
  - The three woods share one look: a cube with planks painted on by the terrain shader
    (the `timber` profile).
  - Apple wood can't be used.
- **Every built block is a cube** and has no direction; its neighbours never change its look.
  - `WorldRenderer` draws built blocks as one mesh of cube faces per column and skips every
    face a solid block touches.
  - The cave shell also skips faces next to a built block.
- **Shapes, Copy and Blueprints** use the same materials. The Wooden shed starter is 30
  wood blocks.
- **The loose log** (`log()` in `tools/voxel_assets/hearthblock_goods.py`) is the Tier 1
  log stool on its side, without the root flare, in its wood's own colours:
  - a 12 × 12 bark body with clipped corners;
  - four bark plates raised one cell, one on each side and off centre;
  - at both ends, a bark rim, a lighter cut face, one square growth ring off centre, the
    pith and a drying split.

  It measures 14 cells each way. Oak, pine, juniper and apple ("Apple Wood") each have one.

## Decisions (owner, 2026-10-26)

- Stone and Wood open menus. Dirt and Grass stay as they are.
- Stone's menu holds native stone only, for now.
- Wood's menu holds Upright log and Horizontal log. The player picks the wood: oak, pine,
  juniper or apple ("picking the wood type is important").
- A built log closely matches the loose log.
- The owner took the recommended answers to four questions:
  1. **The planked wood block goes; logs replace it.** Planks can return as a Carpenter
     texture (`00_todo.md`, "Build textures by progression"). The Wooden shed starter is
     rebuilt in logs.
  2. **A horizontal log lies along the drag's longer side.** R turns it for a click or a
     square drag.
  3. **Joints:** the +, L corners and T junctions are all notched. The log on top
     alternates layer by layer, as on a real cabin corner.
  4. **Logs in a row join into one long log**, with end grain only where the row stops.
     Stacked upright logs join into one post.

## The log

**The loose log, stretched to fill its block** (owner, 2026-10-26: "the existing log needs
to be stretched just a little to hit the edges"):
- **Body:** 16 × 16 cells of bark, reaching every face of the block.
  - Its clipped corners scale with it: 3 cells deep, where the loose log's are 2.
  - They are the only open part of the block.
- **Bark plates:** the loose log's plates stand one cell proud, and a full block has no room
  for that.
  - They stay as lighter bark plates, flush with the face, each with a one-cell groove cut
    round it so it still stands out as a plate. A dark painted seam was tried first and
    read as panels on a long log.
  - They sit as on the loose log, one to a side and off centre.
  - A long log changes its plates from block to block, picked by position, so a wall never
    repeats.
- **Ends:** the loose log's end, scaled up: bark rim, cut face, one square growth ring off
  centre, the pith, and the drying split down one side.
- **Length:** 16 cells, one block.
- **Colours:** each wood's own, from the palettes its loose log uses (`craft_materials.json`):
  oak warm brown, pine pale and yellow, juniper grey-brown, apple pinkish.

**Solid walls.** Logs side by side or stacked touch along their flat faces, and nothing shows
through. A groove runs where their clipped corners meet, like the line between courses on a
real log wall.

**Pieces.** A log's look comes from the logs around it in its layer, or in its column for an
upright log. The look never changes what the block is.

| Piece | When | Look |
|---|---|---|
| Single | nothing joins it | the stretched loose log, end grain at both ends |
| End | a log joins one end | end grain on the open end |
| Middle | logs join both ends | bark all along |
| Crossing (+) | two rows cross here, both carrying on | both logs pass; the upper sits in a notch chopped in the lower, and the chopped faces show fresh-cut wood |
| Tee (T) | one row carries on, the other ends in it | the through log is notched; the other row's end sits in the notch |
| Corner (L) | both rows end here | the two ends notched into each other, each showing its end grain on its own face |

- **The top log in a joint alternates by layer:** the log along X lies on top on even
  layers, the log along Z on odd ones.
- **Joints form only between horizontal logs.** A horizontal log against an upright one
  just ends (see Later).
- **Logs join only logs of the same wood,** in rows and joints. An oak wall meeting a pine
  wall shows two ends.
- **An upright log is the same piece stood up.** Stacked upright logs make one post, with
  end grain at its top and foot.

Phase 1 draws all of this for the owner before anything changes in the game.

## Blocks and gameplay

- **Twelve blocks:** `base:construction:log:<wood>:<direction>`. The wood is oak, pine,
  juniper or apple; the direction is `up`, `x` or `z`.
  - Each block's entry in `terrain_blocks.json` names its wood and direction, so no code
    reads the key's text.
  - Saves keep the names, as today (Hard Rule 3).
  - The block is what the data says. The joint look is only how it is drawn (Hard Rule 9).
- **Cost and mining:** 1 log of the chosen wood a block, and mining gives it back
  (`block_resources.json`). The crate takes only that wood. Apple's good is Apple Wood.
- **A log is a whole solid block** for walking, support, sealing rooms, water and picking,
  like every built block. The open corners only change how it looks.
- **The planked wood block goes,** with its three keys and the `timber` profile's boards.
  - Saves and blueprint files that hold it no longer load (no backward compatibility
    during development).
  - The Blueprints window lists such files at the bottom with the reason, as it does now.
- **Orders keep each cell's direction** and save it, since one rectangle can hold both
  directions. An order's wood is the one chosen when it was planned.

## The menus

- **The pictures:** Stone's and Wood's show the chosen type. Wood's is the chosen log in
  the chosen wood.
- **Opening:** clicking Stone or Wood opens its menu above the bar. Dirt and Grass are
  picked at once, as now.
- **Stone:** Native stone, 1 rough stone, which becomes the natural rock of its layer. New
  stones join the list as they come (`00_todo.md`, "Other stones and thinner walls").
- **Wood:** Upright log and Horizontal log, and the four woods with their stock ("Pine · 23
  logs"). A wood with none in stock can still be picked; the cost on the tag shows rust, as
  now.
- **Keys:**
  - Q and E still step through the four materials, and each one remembers its type.
  - R turns a horizontal log.
  - A click in the world or Esc closes the menu. Esc closes the menu before it ends the tool.
- **Two formats,** drawn in phase 1 over the real game at 1920 × 1080 and 7680 × 2160:
  - **A (recommended):** a small menu rising above the picture, as the dock's menus rise
    above their buttons. The two logs are in one row, with the four woods below them.
  - **B:** a grid of the eight logs, one row per wood with its stock and one column per
    log, so one click picks both.
- **The tag** names the wood: "18 blocks · 18 oak logs · 6 in stock".
- **The preview** shows which way the logs will lie. It could be green ghost logs instead
  of cubes, or a stripe along each cell; the owner picks from the phase 1 pictures.

## Drawing logs

- **Models, not painted cubes.**
  - The pieces are Hearthblock models made from the loose log's recipe, beside `log()` in
    `tools/voxel_assets/`, in the four woods.
  - The pieces vary with their neighbours (joints, the top log and the plates). So they
    are generated from the recipe and kept once made, not authored one by one.
  - `WorldRenderer` draws each log cell with the piece its neighbours call for, inside its
    column's built-block mesh. Instanced meshes are the alternative if they measure better.
- **Faces behind a log are still drawn.**
  - A log's clipped corners leave its block's long edges open. Today a solid block hides
    every face it touches, and both the built-block mesh and the cave shell skip those
    faces.
  - Logs are the first solid block that doesn't fill its cell. Block kinds get a flag for
    that, and those two places draw the faces next to a log: a stone wall or a cliff behind
    a cabin, for example.
- **The slice** hides logs above the cut, as it hides blocks. A log on the cut layer is
  drawn whole.
- **Shadows** come from a coarse shadow proxy, as doc 63 requires for models.
- **Cost:** one check for a hitch or a clear regression, with a village of cabins (about
  1,500 logs) at 30 dwarves.

## Shapes, Copy and Blueprints

- **Shapes** use Wood's chosen log and wood.
  - In a hollow rectangle, horizontal logs lie along each side, so its corners become L
    joints.
  - A filled rectangle lays them along its longer side, a circle along the ring, and stairs
    across the flight.
  - Upright logs need no direction.
- **Copy** keeps each log's wood and direction.
- **Blueprint files** store logs by wood and direction. R turns them with the blueprint, so
  X becomes Z. Placing a blueprint uses the wood each block was copied in.
- **The Wooden shed starter** becomes a small log cabin: horizontal pine logs, + corners,
  three courses and a door gap.

## Phase 1 pictures (2026-10-26)

In `tmp/log_building_20261026/`:

| Picture | Shows |
|---|---|
| `pieces.png` | Each wood in a row: the loose log beside a built log and an upright log, then a row, a wall four courses high, stacked upright logs, a + crossing, a T and an L, each three layers |
| `joints.png` | The three joints in pine, close from outside and from the play camera's height |
| `cabins.png` | A small cabin in each wood: + corners running one block past, a door between upright logs |
| `menus_1920x1080.png`, `menus_7680x2160.png` | Format A and format B of Wood's menu, and A for Stone's, on the game's own tool bar over the owner's colony, with a pine cabin of study logs in the world |
| `previews_1920x1080.png`, `previews_7680x2160.png` | The two previews of five horizontal logs being dragged |

- **How they were made:**
  - `log_pieces.py` builds study models from the loose log's recipe and the woods' palettes,
    with the production exporter (greedy mesh, baked corner occlusion, shadow proxy).
  - `LogStudio.gd` renders them under the menu pictures' light, with shadows.
  - `LogMenus.gd` loads a copy of the owner's quicksave in an isolated profile. It uses the
    game's own tool bar, tiles and hover cards; the menus are stand-ins built from them.
- **The joints in the pictures:**
  - The lower log shows fresh-cut wood where the top log's corners meet it.
  - At a T, the branch log's end shows through the through wall on every other layer.
  - At an L, the end showing on each face alternates layer by layer.
- **Stock numbers in the menus are samples.** The copied colony is a day old and has no logs.
- **Cost:** a study log is about 320 triangles; the 106-log cabin is 34,000.

**The owner's picks (2026-10-26):** format A, the ghost-log preview, and the log's look as
drawn ("The log look is approved; start phase 2").

## Phase 2, built (2026-10-26)

Phase 2 and the work planned for phase 3 were built together: with the planked block gone,
the Wooden shed starter and Copy needed logs at once.

- **Data:** `data/construction/materials.json` holds Build's materials, with Stone's and
  Wood's menus, and the four woods, each with its craft material, good, words and blocks by
  direction (read by `BlockRegistry`). `blocks.json` has `log_upright` and `log_horizontal`
  in place of `wood`. The twelve log blocks and their drops are in `terrain_blocks.json` and
  `block_resources.json`. The planked blocks, the `timber` profile and the shader's boards are
  gone, and mining sounds count `log` as wood.
- **The pieces:** `tools/voxel_assets/built_logs.py` makes the 80 pieces from the approved
  recipe. They ship as one `construction/logs.glb` in the hand-hewn source palette, which
  CraftMaterials recolours for each wood, as it does furniture: one 5.9 MB model instead of
  four. Each piece is about 560 visual triangles, more than the study's 320 a log, since each
  block keeps all its own faces.
- **The menu pictures:** the eight logs, each wood's horizontal and upright log, are made by
  `icons.py` from the same recipe and rendered by `GenerateUiIcons.gd`. The woods' tiles use
  the loose logs' pictures. The planked block's picture (`block_wood`) is gone.
- **Drawing:** `BuiltLogs` (doc 24, "Built logs"). `BlockRegistry.fills_cell` keeps the faces
  behind a log, both in built blocks and in the cave shell.
- **Building:** the controller keeps each material's type, the chosen wood (at first the one
  in most stock) and R's direction. Orders and saves keep the wood and each log's direction.
  Shapes lay logs as planned. The tool bar's choices can carry a menu, and Build's keys add
  "R · turns a log".
- **Blueprints:** a log is `log:<wood>:<direction>`. Copy keeps it, turning swaps x and z,
  and placing plans one order a kind and wood. The Log cabin starter replaces the Wooden
  shed: 8 × 4 × 8 of pine, with + corners and a door between upright logs.
- **Not changed:** pending plans still show as blue cubes, and a blueprint's placing ghost as
  green cubes; only a Build or Shapes drag shows ghost logs.
- **Old saves:** saves holding a planked wood block no longer load (no backward
  compatibility during development). The owner's quicksave of 2026-10-26 (Gunberg) holds one.
- **Tests:** `LogJointsTest` (new: pieces by neighbours, the faces beside a log, every piece in
  every wood); `BuildMaterialsTest`, `BlueprintTest` and `ToolBarTest` reworked for logs and
  menus; `SaveManagerRoundTripTest`, `DwarfSupportTest`, `FinalTerrainStateTest` and
  `OverviewSnapshotTest` moved to log blocks. The job gate passes (55/55), and the lint finds
  nothing new.
- **Checked in game** on a fresh world (`tmp/log_building_20261026/phase2/`, `LogPhase2Check.gd`):
  the menu from Wood's picture, a dragged row as ghost logs then one long log, and the Log
  cabin starter placed and DEV-finished, 106 logs drawn.

## Phases

1. **The look, pictures only.** Drawn on 2026-10-26; see "Phase 1 pictures".
   - The pieces in all four woods: a single log beside the loose log, a row, a wall four
     courses high, an upright post, a stack of + crossings, an L, a T and a cabin corner.
   - The two menu formats and the preview over the real game.
   - Rendered from the real pieces, as the menu pictures are, into
     `tmp/log_building_20261026/`. The owner picks before phase 2 starts.
2. **Logs in Build.** The Stone and Wood menus, the twelve blocks, directions, the crate per
   wood, mining, saves, and drawing with rows and joints. The planked block goes. Done when
   the owner builds a small log cabin with Build and it reads like the pictures. Built on
   2026-10-26; the owner's look is next.
3. **Shapes, Copy and Blueprints.** Directions in shapes and files, turning blueprints, and
   the log cabin starter. Built with phase 2.
4. **Close.**
   - The rules move into docs 12, 23, 24, 43 and 63.
   - The menu pictures are rendered again (`GenerateUiIcons.gd`).
   - The job gate is green.

**Tests:** as built, in "Phase 2, built". Building, mining and saving logs went into the
reworked `BuildMaterialsTest` rather than a new `LogBuildTest`.

## Later

- More stones in Stone's menu, and planks and other woodwork in Wood's (`00_todo.md`).
- Joints between horizontal logs and upright posts.
- A Crossed corners switch for a hollow rectangle of logs. It runs each side one block past
  the corner, so every corner is a +, as on the reference cabin.
- Choosing the wood when placing a blueprint.
- Ghost logs for pending plans and for a blueprint's placing ghost, which show cubes today.
