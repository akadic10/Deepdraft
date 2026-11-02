# 293 — The Stonemason and the Carpenter

2026-11-01. Step 2 and step 3's stone stool are built and await the owner's look in Play
("Built: step 2" and "Built: step 3", below); the Carpenter's first goods are still to choose.
The owner took
the picks, with a stone stool in place of the stone door. Then, shown the concepts, the owner
chose the kit and both benches and put the refined goods on hold until better tools exist
("Concept picks", below). After the redraws the owner settled the pieces: a carpenter's bench
like the owner's picture, peeled (A), the slab on stumps at 3 × 1 and the stone stool B
("Settled", below). The Carpenter's first goods are still to choose.

From the owner: "Review the professions in the game, I think I am ready to start the
Stonemason and the carpenter and each will have to craft their starting workbench, later as
better tools become available they will be able to craft more advanced workbenches".

## The professions today

| Career | In the game | Promotes with | Does | Its crafting page | Levels |
|---|---|---|---|---|---|
| Worker | Live | — | The common work, and Rudimentary at the crude workbench | Rudimentary | None |
| Miner | Live | Nothing | Mines first, then the common work | A preview of pickaxes | One a block; 5% less digging time a level |
| Ranger | Live (doc 292) | The Ranger's kit | Dries and fishes, then hauls | Ranger: the drying rack and dried fish | One a catch; big fish |
| Carpenter | Half live | The crude carpentry kit | The common work, and no crafting | Planned preview | None |
| Stonemason | Preview | Nothing yet; it can't be chosen | — | Planned preview | — |
| Blacksmith | Preview | The stone hammer (planned) | — | Planned preview | — |
| Farmer | Preview | The stone hoe (planned) | — | Planned preview | — |

The Brewer, Builder, Merchant, Innkeeper and the military careers are off the career map
(doc 41).

What matters for this plan:
- **A Carpenter today is a Worker who can't craft.** The kit is collected and equipped, but
  the career has no crafting page (`craft_section`), and Rudimentary belongs to Workers. A
  Carpenter mines, fells, builds, gathers and hauls. Promotion costs a kit and gains nothing.
- **The Stonemason has nothing yet:** no kit, no recipes, and Change profession can't choose
  it. Its page says its "promotion requirements are still being designed".
- **The Ranger set the pattern** (doc 292). A career names its crafting page and its work in
  `professions.json`, and its orders wait "Needs a Ranger" without one. Its own workbench, the
  drying rack, is made by Rangers at the crude workbench and sits on its page under Workshops.
- **Stone is one good.** All eleven rock bands drop the same Rough Stone, a quarter of the time
  (`block_resources.json`). Wood comes in four kinds, each with its own colours, appeal and
  toughness. Dressed stone would be one grey stone.
- **Rooms feel only what they hold.** Appeal adds up furniture, loose piles and stocked cells
  (`data/rooms/appeal.json`); walls and floors add nothing. A dressed hall would look better
  and feel the same.
- **Bench work is Wits work** (doc 41, "Stats"). The Carpenter's main stat (Wits) speeds it;
  the Stonemason's (Strength) does not.
- **Crafting ranks below mining and felling** (46 against 50, `task_config.json`). A career
  that crafts and also does the common work would mine and fell first.
- **Tier 2 · Carpenter Era is designed and waiting.** The plank dining table (three hewn
  planks with a butterfly key, on a square post with a cross foot) and the blanket bed (a wool
  blanket and a linen pillow) are in `proposal.mjs` and the tier studies. Hewn planks and pegs
  need no iron, so a Carpenter with the mallet and stone adze can make them.
- **Build already plans for both careers.** The owner's "Build textures by progression"
  (`00_todo.md`, 2026-10-26) recommends textures that cost the good that makes them:
  - dressed stone from the Stonemason, in Stone's menu;
  - planks from the Carpenter, in Wood's menu;
  - rough stone and logs stay the cheap default;
  - finished blocks add room appeal.

  Replace (doc 285) can swap a dug room's walls and floor for them in one drag.
- **Better tools mean the Blacksmith,** who is a preview too: no smelter, forge or ingots.
  - The iron saw is the Carpenter's planned upgrade. Doc 44 says: "Do not invent a wooden saw
    to satisfy the entry requirement."
  - Doc 44 also says the first Blacksmith needs a starter workshop "that requires neither
    refined Carpenter goods nor its own forged output".
- **The icons show the upgrades.** The Carpenter's icon is a handsaw on a plank, and the
  Stonemason's a steel chisel in a dressed block. Both careers start with stone tools.

## Decisions (owner, 2026-11-01)

1. Start the Stonemason and the Carpenter.
2. Each crafts its own starting workbench.
3. Better tools, when they arrive, let them craft more advanced workbenches.

## The ladder

Both careers climb the same rungs:

| Rung | Carpenter | Stonemason |
|---|---|---|
| **Kit** (Workers, at the crude workbench) | Crude carpentry kit: a wooden mallet and a stone adze (in the game) | Crude masonry kit: a hammerstone and a stone point (new) |
| **Starter workbench** (the career, at the crude workbench, from raw goods) | Carpenter's bench | Mason's bench |
| What it makes | Rough work only, without a saw: still to choose (see Open) | The stone stool: a rough squared stone |
| **Better tool** (the Blacksmith, later) | Iron saw | Iron chisels |
| **Advanced workbench** (later) | Joiner's bench: planks, Tier 2 · Carpenter Era pieces, chests and barrels, framed doors on iron hinges | Carver's bench: dressed stone, Build's dressed blocks, carved stone and finer doors |

This makes a rule for every career after these two (the Blacksmith, the Farmer, the Brewer):
**a career's first workbench is made by that career, at the crude workbench, from raw goods.**
No career waits on another to start. Better benches may need other careers' goods: iron tools,
planks or dressed stone. The Ranger's rack already follows the rule.

## Picks (owner, 2026-11-01)

My recommendations, taken with one change. From the owner: "all good except the stone door,
let's make a stone stool instead for now".

1. **Each starter bench is made by its own career at the crude workbench,** as Rangers make
   the rack.
   - A Carpenter makes the carpenter's bench from three matching logs. A Stonemason makes the
     mason's bench from a log and three Rough Stones.
   - Each sits on its career's page under Workshops, and in Place under Workshops.
   - With no Carpenter, its order waits "Needs a Carpenter", as the rack waits for a Ranger.
   - The career's other recipes need its bench: "Needs a carpenter's bench".
   - *Not taken:* the career makes its bench on clear ground, with no bench, as Workers make the
     crude workbench. The crude workbench is always there, since the kits are made at it.
2. **The Stonemason promotes with a crude masonry kit** of its own. Workers make it at the
   crude workbench (Starter tools) from a log and a Rough Stone, like the other kits. A dwarf
   promoted to Stonemason collects it. The stone hammer stays the Blacksmith's starter tool.
   - *Not taken:* no tool, as for the Miner. Promotion would be free, but the iron chisels
     would have no first tool to replace.
   - *Not taken:* the stone hammer, shared with the Blacksmith. Builders already swing it, and
     one tool would promote two careers.
3. **Each career makes only its own page,** as Rangers make only theirs. Workers keep
   Rudimentary, log furniture included, so a colony with no Carpenter keeps its log bed.
4. **Their own crafting first, then a Worker's work.** Carpenters and Stonemasons take their
   page's orders before anything else. Then they mine, fell, build, gather and haul as Workers
   do.
   - Nothing ties them to one place, as the water ties the Ranger, and a colony of five can't
     spare idle hands. A Carpenter with nothing to make fells the trees that feed the bench; a
     Stonemason mines the stone.
   - Crafting ranks below mining and felling, so "first" uses the Ranger's work order,
     followed by the common work at its usual priorities.
   - *Not taken:* craft, then haul only, as the Ranger does.
5. **On hold (owner, 2026-11-01): planks and dressed stone.** "I don't know how the dwarves can
   make these without a saw yet, hold off on this"; "not yet, dwarves lack fancy tools for
   now". They wait for the iron tools and the advanced benches. As planned:
   - The Carpenter splits and adzes a log into two planks of its wood. The Stonemason dresses
     a Rough Stone into a block of dressed stone.
   - Tier 2 pieces take planks, the Stonemason's pieces take dressed stone, and Build takes
     both.
   - They are hauled and stored like logs and stones.
   - *Not taken:* Tier 2 pieces straight from logs. That is one step fewer, but leaves no plank
     for Build.
6. **On hold (owner, 2026-11-01): Build's dressed stone and planked blocks** ("they look too
   advanced"), with the goods that make them. As planned, from the owner's "Build textures by
   progression":
   - Dressed stone joins Stone's menu beside native stone. The planked block joins Wood's
     menu beside the logs, in each wood.
   - Each costs one of its good and gives it back when mined.
   - Both work with Replace, so a dug room's walls and floor can be dressed in one drag.
   - Native stone and logs stay the cheap default.
7. **On hold, with the blocks: finished blocks add room appeal.** As planned, each face of
   dressed stone or planks that a room shows adds a little, on the floor, the walls and the
   ceiling alike.
   - A 7 × 7 bedroom dressed on its floor and walls shows about 160 faces and gains about 5,
     most of the way from Plain to Pleasant.
   - Native rock, dirt and logs add nothing.
   - *Not taken:* looks only, as Build is today.
8. **One experience a batch, and levels make them faster.**
   - A batch made at the career's own benches counts one. Levels come at 10, 50, 150 and 400
     batches, the Ranger's scale.
   - Each level gives 5% less work time at those benches, as the Miner digs faster and as doc 41
     plans for every career.
   - *Not taken:* more from the same, such as three planks a log at level 3. That suits scarce
     goods; wood isn't scarce, and dressing a stone gives one block.
   - *Not taken:* finer pieces at higher levels ("Fine", with more appeal). Doc 62 waits for a
     quality system.
9. **Stone benches count as Strength work.** Work at the mason's bench goes at Strength's
   speed, so the Stonemason's fit (Strength, then Wits) means what it says. Carpenters keep
   Wits.
   - *Not taken:* swap the Stonemason's stats to Wits, then Strength, the Carpenter's pair.
10. **Better tools come from the Blacksmith, and the advanced benches wait for them.**
    - The iron saw lets a Carpenter make the joiner's bench. Iron chisels let a Stonemason make
      the carver's bench.
    - A recipe names the tool its maker must hold. The advanced bench's own recipes need that
      tool too: finer work wants the finer tool.
    - Each page looks the same as the Rudimentary page, with no box or strip for what comes
      later (owner, 2026-11-01: "I can't think of a reason why it would not look the same as the
      rudimentary crafting page"). This replaces the WITH IRON TOOLS box first planned.
    - *Not taken:* the tool gates only the bench, and any Carpenter may then use it.
    - *Not taken:* a stone-age middle rung, where each career improves the other's tools before
      iron (a ground-stone adze from the Stonemason, for one). It comes sooner, but it is a tier
      that neither the art nor the economy needs yet.
11. **A small first set, the rest later.**
    - **Carpenter:** the carpenter's bench. Its first goods are still to choose, as nothing on
      the first list can be made without a saw: planks, the plank dining table and the plank
      stool are on hold (owner, 2026-11-01: "Plank stool - remove this for now").
    - **Stonemason:** the mason's bench and a stone stool (owner: "let's make a stone stool
      instead for now"). It is a stool like the log stool, made from a Rough Stone, a stone the
      log stool's size but more square (owner, 2026-11-01). Dwarves rest, eat and play on it,
      it fits a table's guides, and it turns to a nearby fire.
      - It is the first stone piece that dwarves use. Until now the owner's material rule
        (doc 62, 2026-07-11) kept such furniture to wood.
    - **Later,** as the owner wants: the stone door, recommended first and set aside for now
      (two wide, with the jambs and lintel that doc 62 kept for better doors); the plank bed
      (see Open); a standing stone for appeal; and a great hearth that can warm a hall.

## Concepts (2026-11-01)

From the owner: "Draw concepts". Each piece is a Hearthblock model in the shared vocabulary
(`proposal.mjs`), rendered as the game renders its menu pictures, then laid in a copy of the
owner's colony (the 17:19 quicksave; nothing saved). In the colony the wooden pieces are pine,
as the colony's furniture is; the menu pictures show the woods' source colours, as every menu
picture does. The scratch is in `tmp/mason_carpenter_concepts_20261101/`, with the sheets in
`sheets/`, `world/`, `pages/` and `poses/`. My recommendation comes first in each list.

- **The crude masonry kit** (`sheets/kit.png`):
  - **A · Maul and point, bound** (recommended): a hammerstone maul and a long stone point on two
    hafts, bound side by side as the carpentry kit binds its mallet and adze. It reads as a
    mason's pair at tile size and doesn't look like the stone hammer.
  - B · Hammerstone and points: no hafts. A round hammerstone in a rope cradle, with two points
    bound beside it. At tile size it reads as a rock.
  - C · The mason's pick: one tool, with a hammer face on one side and a point on the other. Its
    outline is close to the Blacksmith's stone hammer.
- **The carpenter's bench, 3 × 1** (`sheets/carpenter_bench.png`, `world/benches.png`):
  - **A · The split-log bench** (recommended): a thick half log adzed flat, on four splayed legs
    pegged through it, with a planing stop, a holdfast hole and shavings underneath. It reads as
    a workbench at the game's zoom and looks nothing like the Workers' stump.
  - B · Trestles and a plank: a long plank lashed across two log trestles, with a log
    underneath. It reads as a table.
  - C · The hewing cradle: two notched bolsters holding the log being hewn. When idle, only the
    bolsters stand.
- **The mason's bench, 2 × 1** (`sheets/mason_bench.png`, `world/benches.png`):
  - **A · The dry-stone banker** (recommended): two courses of squared stones laid dry, under a
    slab dressed flat. It is built from the stones it takes ("banker" is the masons' word for
    it), so its recipe can drop the log: four Rough Stones.
  - B · The slab on stumps: a stone slab across two log stumps.
  - C · The boulder banker: one great boulder, rough all round, with its top dressed flat and a
    bed of grit.
- **The plank stool** (`sheets/plank_stool.png`, `world/stools.png`):
  - **B · Board ends** (recommended): a seat plank on two board ends cut into feet, with a
    wedged stretcher between them. It is chunky enough to read as a seat beside log stools.
  - A · Three legs: two planks on three splayed legs. Beside the table's log stools it looks
    thin.
  - C · The table's twin: the Tier 2 table in small. It reads as a little table.
- **The stone stool** (`sheets/stone_stool.png`, `world/stools.png`):
  - **A · The dressed block** (recommended): a squared stone on a wider footing, its faces
    drafted round their edges and the seat dressed smooth.
  - B · The drum: two stepped round stones. It reads as a barrel.
  - C · The slab on a pillar. It reads as a small table.
- **Planks** (`sheets/planks.png`, `world/goods_world.png`):
  - **C · A waney board** (recommended): one broad board with the bark still on its edges. A log
    makes two planks, so a plank is one board.
  - A · A bound bundle of three boards: three boards for one plank, and busy at the game's zoom.
  - B · A crossed stack. It reads as a pallet.
- **Dressed stone** (`sheets/dressed_stone.png`, `world/goods_world.png`):
  - **B · The drafted block** (recommended): a smooth margin round each face, with the chisel's
    lines down the middle. It reads as worked stone at a glance, unlike the Rough Stone.
  - A · The ashlar block: a plain dressed cube. It reads as a box.
  - C · Two slabs.
- **Build's blocks** (`world/blocks_world.png`), each drawn as a wall corner with a floor in front:
  - Dressed stone: **B · Coursed** (recommended) has two courses a block, the upper joint
    halfway along, so walls bond like brickwork and a hall looks built of many stones. A ·
    Ashlar is one big stone a block with a light mortar joint. C · Drafted is one stone a block
    with its margin.
  - Planked: **A · Boards** (recommended) has four boards up each face, with seams and pegs.
    B · Upright boards reads as a palisade. C · Wide planks has two boards a face.
  - All are drawn as whole-block Hearthblock pieces, as built logs are. One of them could be a
    terrain appearance profile instead, since one id is free.
- **The pages** (`pages/pages_carpenter.png`, `pages/pages_stonemason.png`): the game's own
  crafting window, with the plan made real in memory. Ralin stands in as the Carpenter and
  Ingvin as the Stonemason.
  - **A · A WITH IRON TOOLS box** (recommended): the recipes, with the bench first under
    Workshops and the rest waiting for it, then a box naming what the Blacksmith's tools open.
    This is the Ranger's page as built.
  - B · The joiner's bench, locked: already on the page as a dark shape, tagged "Needs an iron
    saw · from the Blacksmith".
  - C · The ladder across the top: the kit, the bench and the iron saw. It makes the window a
    fifth wider.
  - The career map on the Stonemason for Ingvin: available, a Good fit (Strength, then Wits),
    and the masonry kit to collect.
- **At work** (`poses/poses.png`): Ralin hews the board with the stone adze and Ingvin dresses
  the stone with the maul. Both use the motion every bench uses today, with the new tool in hand.
  This is recommended for the first build, since it needs no new motion. Short adze strokes, or
  a point held to the stone and struck with the maul, can follow once the benches are in Play.
- **Colour.** Dressed faces are a warm grey, like the hearth's stones; in the Rough Stone's own
  cool grey a sunlit wall read as ice. Rough parts, such as the banker's courses, keep the Rough
  Stone's grey.
- **At the table.** The colony's dining table stands under the owner's shelter, so its shot uses
  the slice cut just above the floor, as the owner plays.

## Concept picks (owner, 2026-11-01)

From the owner: "Your design approach is good, but we have to remember that Dwarves have very
basic tools and they can't quite make the things you're presenting with a chisel." Piece by
piece:
- **Masonry kit: A,** the maul and point, bound.
- **Carpenter's bench: C,** the hewing cradle, "but it might need some refinement to look more
  rudimentary". Redrawn below.
- **Mason's bench: B,** the slab on stumps. Redrawn below with a split slab, not a dressed one.
- **Plank stool:** "remove this for now".
- **Stone stool:** "these are too advanced, I am thinking a stone that has the dimensions of the
  log stool but more square". Redrawn below.
- **Planks:** "I don't know how the dwarves can make these without a saw yet, hold off on this".
- **Dressed stone:** "not yet, dwarves lack fancy tools for now".
- **Build blocks:** "let's hold off on these, they look too advanced".
- **Crafting page:** "I can't think of a reason why it would not look the same as the rudimentary
  crafting page". A career's page takes the Rudimentary page's layout: its recipes and nothing
  more.
- The work poses drew no comment, so the Worker's swing with the new tool stands.

What follows for the plan:
- **Basic tools make rough work.** A stone adze, a mallet, a hammerstone and a stone point hew
  timber and knock stone square; nothing is dressed or tooled smooth. Planks, dressed stone,
  Build's blocks and their appeal wait for the iron tools and the advanced benches (picks 5 to
  7), as do the Tier 2 table and the plank stool.
- **The Carpenter's page holds only its bench for now.** Its first goods are still to choose
  (see Open).

## Redrawn (2026-11-01)

The rough pieces, drawn again in the same way. The scratch is in the same folder: `sheets2/`,
`world/benches2.png`, `world/stools2.png` and `poses/poses2.png`. My recommendation comes first.
- **The carpenter's bench, more rudimentary** (`sheets2/carpenter_bench2.png`). Round 1's cradle
  had neat bolsters, a smooth light flat and regular score cuts, which read as finished work. Both
  takes have rough bark bolsters with V notches chopped in steps and the axe's marks, and chips
  and bark scraps round them. The log being hewn is the batch: bark on its underside, a rough
  flat taken off the top in axe strokes, still round at the far end, and V notches along its
  edge. It costs two logs.
  - **C2 · The cradle on a sill** (recommended): the bolsters are joined by a log sill on the
    ground, so the station stands as one piece when idle and in its menu picture.
  - C1 · The rough cradle: two bolsters of different sizes and nothing between them. It is the
    plainest, but when idle it reads as two loose logs.
- **The mason's bench, rough** (`sheets2/mason_bench2.png`): the owner's B, with its slab split
  rather than dressed. The top is uneven, the corners chipped and a crack runs across it, all in
  the Rough Stone's own colours. Its batch is a Rough Stone being knocked square: the stone stool
  in the making.
- **The stone stool** (`sheets2/stone_stool2.png`, `world/stools2.png`): a Rough Stone knocked
  square with the maul, the log stool's size (1 × 1, the seat at 0.875).
  - **A · The squared stone** (recommended): the log stool's shape in stone, with a wider foot
    like its root flare, straight sides, a flat top, a chipped corner and a crack.
  - B · The rough block: knocked square all the way down, its top a little uneven, with lumps
    left on its sides.
  - C · The squared boulder: bulging at its middle, flat top and bottom. It reads as a barrel.
- **At work** (`poses/poses2.png`): Ralin hews the log in the cradle with the stone adze, and
  Ingvin knocks the stone square on the slab with the maul, by the Worker's swing.

## Settled (owner, 2026-11-01)

From the owner, with a picture of a log workbench in a wood (kept as
`tmp/mason_carpenter_concepts_20261101/reference_workbench.webp`): "Wooden workbench, try
something like this image. The masons bench B looks good but make it 1x3. The Stone stool looks
good in B".
- **The carpenter's bench, from the owner's picture** (`sheets3/carpenter_bench3.png`,
  `world/benches3.png`). It replaces the cradle. A thick slab, half of a great log with its round
  side down, hewn flat on top, stands on four thick log legs braced low with log rails: rails
  across both ends, and long rails a little higher along both sides. The slab runs past the legs
  at both ends, and every cut shows its end grain. It is 3 × 1, with its top at 1.125 blocks, and
  costs three matching logs. At work, half a log lies on the slab, being hewn.
  - **A · Peeled, as in the picture** (the owner's pick: "Peeled, A"): the legs, rails and slab
    are peeled, as built logs and fences are (doc 278), with knots trimmed flush and a drying
    check. It is the picture, and it sets the Carpenter's work apart from the Workers' bark
    furniture.
  - B · Bark left on: the same bench with the bark kept on its legs, rails and the slab's
    underside, as the Workers' stump furniture keeps it.
- **The mason's bench, B at 3 × 1** (`sheets3/mason_bench3.png`): the split slab on two log
  stumps, stretched to three blocks with the stumps set in from the ends. It costs a log and three
  Rough Stones, and the stone being knocked square sits in the middle.
- **The stone stool: B,** the rough block (`sheets2/stone_stool2.png`). It is knocked square all
  the way down, its top a little uneven, with lumps left on its sides.
- **At work** (`poses/poses3.png`): Ralin hews half a log on the new bench with the stone adze,
  and Ingvin knocks a stone square on the long slab with the maul.

## How it plays

- **Promoting.** Workers make a crude masonry kit at the crude workbench. Choosing Stonemason
  sends the dwarf to collect it, as a Carpenter collects a carpentry kit, and the chime plays
  when they have it. The career map's tiles read:
  - Carpenter: "Works timber with basic tools at the carpenter's bench, which they make first."
  - Stonemason: "Shapes rough stone at the mason's bench, which they make first."
- **The first bench.** Crafters → Carpenter becomes a live page, laid out as the Rudimentary
  page.
  - Its first recipe, under Workshops, is the carpenter's bench. The board's tags read
    "✓ A crude workbench" and "✓ A Carpenter" with the Carpenter's name, or "Needs a
    Carpenter".
  - Every other recipe on the page reads "Needs a carpenter's bench" until one is installed
    through Place → Workshops.
  - The Stonemason's page works the same way, with the mason's bench and the stone stool.
- **Working.** A Carpenter lays half a log on the bench and hews it with the adze. A
  Stonemason knocks a Rough Stone square on the slab with the maul. With no orders they mine, fell, build,
  gather and haul.
- **The stone stool** serves wherever a log stool does: by a fire, at a table's guides and at
  the board.
- **The sheet.** The Profession tab shows the level, the bar ("40% to level 3 · 32 batches
  made") and the rewards. The compact panel reads "Stonemason · Lv 2".

## The numbers (to tune in play)

| Recipe | Made by, where | Takes | Work |
|---|---|---|---|
| Crude masonry kit | Workers, crude workbench | A log and a Rough Stone | 12 s |
| Carpenter's bench | Carpenters, crude workbench | Three matching logs | 16 s |
| Mason's bench | Stonemasons, crude workbench | A log and three Rough Stones | 18 s |
| Stone stool | Stonemasons, mason's bench | A Rough Stone | 10 s |

- **Appeal:** the stone stool 1, the log stool's design; stone takes no wood bonus.
- **Levels:** 10, 50, 150 and 400 batches, with 5% less work time a level.

## How it will be built

- **The careers** (`professions.json`).
  - The Stonemason gains `promotion_enabled`, the masonry kit as `required_tool`, an
    `equipment_preview`, a description, a `craft_section` and `experience`.
  - The Carpenter gains a `craft_section` and `experience`.
  - Both get a work order that puts their crafting first and then the common work. Today a
    career that names its `work` does only that. "Then the common work" is a small addition to
    `DwarfAssets.profession_task_types` and `TaskScheduler.takes`.
  - The career map's texts change for both, and its hard-coded Carpenter line ("Specialist
    crafting and experience are planned", `DwarfProfessionPanel`) goes.
- **Their pages** (`worker_crafting.json`).
  - The `carpenter` and `stonemason` sections go live with hints, laid out as the Rudimentary
    page, with no `later` box.
  - New recipes name their `section` and their bench as `workshop`.
  - The masonry kit joins Rudimentary → Starter tools.
  - The stone stool's recipe gets stone's `ingredient_words`.
- **Goods** (`resources.json`): the masonry kit, with an `equipment` block like the carpentry
  kit's.
- **Benches and pieces** (`data/furniture/`).
  - The two benches, both 3 × 1, with their `crafting_motion`, the stat their work uses and
    each one's batch on show (`batch_model`): half a log on the bench, the stone on the slab.
  - The stone stool, with a `seating_chair` like the log stool's.
  - Place tiles in `place_catalog.json` (every placeable recipe needs one), and a taste for the
    stone stool in `tastes.json`.
- **Any stool at a table.** A table's guides name one seat today (`seating.chair_key`: the log
  stool in `log_table.json` and `board_game_table.json`). Snapping, the seat's posture at the
  table and the board's game seats all match that key (`FurnitureSeating`).
  - The guides take any stool instead, so the stone stool snaps to a dining table's guides and
    is a game seat at the board.
  - The Place card's "Snaps to tables" (today keyed to the log stool) and the board's "separate
    log stools" go with them.
- **Experience:** `earned_by` CRAFT for both, awarded when a batch finishes
  (`WorkerCraftOrder`), as a catch counts for the Ranger before the lease ends.
- **Strength at stone benches:** the bench names the stat its work uses, read in
  `DwarfWorkExecution` with the kind of work (`_timed_kind`).
- **The tools in hand:** the crafting swing (`DwarfCarryWork._craft_pose`) holds the
  career's tool, the stone adze or the maul, in place of the axe.
- **Later, with the Blacksmith:** the advanced benches, a recipe's `tool`, and orders that wait
  "Needs a Carpenter with an iron saw"; then planks, dressed stone and Build's blocks (picks 5
  to 7).
- **Saves.** New goods and furniture save by key, with nothing to migrate (standing rule). A
  Carpenter already in a save keeps the kit.
- **Tests.**
  - New `CarpenterTest` and `StonemasonTest` (crafting area) cover:
    - promotion with each kit;
    - the starter bench, made only by its career at the crude workbench;
    - "Needs a Carpenter" and "Needs a mason's bench";
    - experience and levels, and Strength at the mason's bench;
    - crafting first, then the common work;
    - the stone stool on a dining table's guides and at the board;
    - saves.
  - `ToolPromotionTest`, `ProfessionCraftingTest`, `CraftingBrowserTest`, `DwarfStatsTest`,
    `SaveManagerRoundTripTest`, `FurnitureArtTest` and `ItemArtTest` change with them.

## Art and sound

Hearthblock, through the usual pipeline (doc 61):
- the crude masonry kit, as goods and as its menu picture;
- the carpenter's bench (the log workbench from the owner's picture) and the mason's bench (the
  slab on stumps at 3 × 1), with the batch each shows at work (`batch_model`);
- the stone stool (B, the rough block);
- the tools in hand, the stone adze and the maul, swung as the Worker swings the axe;
- menu pictures from `FurnitureCatalogThumbnails.gd`, `InventoryCatalogThumbnails.gd` and
  `GenerateUiIcons.gd`.

Sound: real recordings, by the sound workflow, of an adze on wood and of stone struck with
stone. The Worker's chop stays for Rudimentary.

## Steps

1. **Concepts** (drawn and settled, above).
2. **The careers and their benches** (built 2026-11-01, below). The masonry kit and the
   Stonemason's promotion, both pages live, the benches, crafting first, experience and
   levels, the sheet and the career map.
3. **The first pieces:** the stone stool (built 2026-11-01, below), and the Carpenter's first
   goods once chosen.

Each step gets focused tests, the job gate, captures over a copy of the owner's colony, then the
owner's look in Play.

## Built: step 2 (2026-11-01)

What is in the game now:
- **The Stonemason is a career.** Workers make a crude masonry kit at the crude workbench
  (Rudimentary → Starter tools: a log and a Rough Stone, 12 s). Choosing Stonemason sends the
  dwarf to collect it, as the Carpenter's kit is collected. The kit carries its wood's name
  ("Pine crude masonry kit"), as the carpentry kit does.
- **Both pages are live** (Crafters → Carpenter, Crafters → Stonemason), laid out as
  Rudimentary. Each holds its career's bench under Workshops:
  - the carpenter's bench: three matching logs, 16 s;
  - the mason's bench: a log and three Rough Stones, 18 s;
  - each made only by its career, at the crude workbench. With no such dwarf the order reads
    "Needs a Carpenter" or "Needs a Stonemason". Place → Workshops installs them.
- **Crafting first.** A Carpenter or Stonemason takes an order from their own page before any
  other work, then mines, fells, builds, gathers and hauls as a Worker does. Orders on other
  pages never hold them (`work_first`, `TaskScheduler.takes`).
- **Experience:** one per batch made on their own page. Levels come at 10, 50, 150 and 400
  batches, each taking 5% off the work time.
  - The sheet's bar reads "5% to level 3 · 12 batches made"; one batch reads "1 batch made"
    (`noun_one`, for every career).
  - The roster's note reads "Carpentry focus" or "Masonry focus", or "Crafting disabled" with
    Craft unticked.
- **Stats:** a Carpenter crafts by Wits, as a Worker does. A Stonemason's crafting is
  "stonework", which Strength speeds; the sheet's Strength line now reads "Digs, fells, clears
  and shapes stone".
- **In hand:** in the Worker's crafting swing, the Carpenter holds a stone adze and the
  Stonemason a maul, each striking where the axe's edge does. The maul knocks like the builder's
  hammer; the adze keeps the axe's chop.
- **Art:**
  - the carpenter's bench, peeled (A), from the owner's picture;
  - the mason's bench, the split slab on two stumps at 3 × 1. Its slab keeps the Rough Stone's
    own greys and no wood recolours it;
  - the masonry kit, the adze and the maul;
  - menu pictures for the two benches and the kit.

Not as planned:
- **Strength goes by the career, not the bench** (pick 9 said the bench names its stat). Every
  Stonemason craft is stonework, wherever it is made; so far all of them are made at the crude
  workbench.
- **No batch on show at the new benches yet** (`batch_model`). Nothing is made at them until
  step 3's goods, so the half log and the stone come with those.
- **No new recordings.** The maul reuses the construction hammer's knock and the adze the axe's
  chop. Recordings of an adze on wood and stone on stone can come with step 3.
- **No other recipes yet**, so no recipe reads "Needs a carpenter's bench".

Tests:
- New `CarpenterTest` and `StonemasonTest` (crafting area).
- `CraftingBrowserTest` and `RangerTest` now use the Blacksmith's page as the planned one, and
  `EquipmentFeedbackTest` expects Crafting on a Carpenter's card.
- `FurnitureArtTest` and `ItemArtTest` count the new pieces and check the benches' work tops
  and the tools' strike points. `DwarfStatsTest` reads the new Strength line.
- Results: the job gate passes (55/55), lint is clean, and the crafting, fishing, dwarves, art,
  furniture and UI areas pass (89/89).

Checked over a copy of the owner's colony (`tmp/mason_carpenter_build_20261101/colony/`):
- Ralin and Ingvin, made Carpenter and Stonemason, each made their bench from a real order at
  a crude workbench, adze or maul in hand, and earned one experience;
- the two benches installed in the camp;
- both pages, and the career map on the Stonemason.

## Built: step 3, the stone stool (2026-11-01)

From the owner: "Build the stool". What is in the game now:
- **The stone stool:** Crafters → Stonemason → Dining. A Stonemason makes it at the mason's
  bench from one Rough Stone (10 s). With no mason's bench the order reads "Needs a mason's
  bench". Place → Dining installs it.
- **At the bench** the Rough Stone itself lies on the slab in front of the Stonemason while the
  maul knocks it square.
- **It seats as the log stool does,** with the same seat height, posture and clearance. Dwarves
  rest on it, turn it to a nearby fire, eat at a table on it and play at the board.
- **Any stool at a table.** Tables now list the stools their guides take
  (`seating.chair_keys`), so the dining table and the board take log and stone stools, mixed.
  - The guides show the stool being placed.
  - Both stools' Place cards say "Snaps to tables".
  - The board's card reads "2 separate stools", and its window "Needs a stool".
- **Appeal and taste:** its appeal is its design alone (1, with no wood bonus). A dwarf may love,
  like or dislike it as any other design (`tastes.json`).
- **Art:** the rough block (B) in the Rough Stone's own greys, and its menu picture.

Not as planned:
- **No `batch_model` at the mason's bench.** The stone being worked is the real Rough Stone,
  already on the slab, so a separate model would show it twice.
- **The benches' work point.** A fixed reach from the slab's centre left a Rough Stone hanging
  off the mason's bench. Long slabs now put their goods where the top is nearest the worker,
  inside its edges (`crafting_surface_inset`), for the carpenter's bench too. The crude
  workbench and the drying rack keep their reach (`CraftingManager.bench_surface`).
- **New dwarves' tastes.** They are dealt from the longer list, so a seed can give a different
  hand than before. Dwarves in saves keep theirs.
- **No new recordings,** as in step 2.

Tests:
- New `StoneStoolTest` (crafting and furniture areas).
- `FurnitureArtTest` counts the stool and checks its seat at 0.875.
- `CraftingSelectionTest` installs a mason's bench, as it does a drying rack, so every recipe
  has its workshop.
- Results: the job gate passes (55/55), lint is clean, and the crafting, furniture, dwarves,
  UI, art, rooms, fishing and saves areas pass.

Checked over a copy of the owner's colony (`tmp/mason_carpenter_build_20261101/stool/`):
- Ingvin, made a Stonemason, made a stool from a real order at a new mason's bench, the Rough
  Stone on the slab in front of him and the maul in hand;
- the stool installed at the colony's dining table in place of one log stool;
- its Place card.

Ralin, made hungry, ate a few blocks away instead of at the table. A diner checks the nearest
seats first within a time budget, and at triple speed in a busy colony he chose before
reaching it. `StoneStoolTest` covers a meal at a table on the stone stool.

## Not in this milestone

- The Blacksmith, iron tools and the advanced benches. They come with the Blacksmith, whose own
  first workbench follows the rule above.
- With the iron tools (owner, 2026-11-01): planks, dressed stone, Build's dressed and planked
  blocks with their appeal, the Tier 2 table and the plank stool.
- Stone kinds (granite, slate, marble and so on), carried from each rock band as logs carry their
  wood. That is its own milestone if wanted.
- Storage furniture (the barrel and chest), with the storage milestone (doc 62).
- Oak staves and aging casks, with brewing (docs 42 and 44).
- Quality ("Fine" pieces), level 6 and the calling traits.
- The stone door, set aside for the stone stool for now (owner).
- Other stone furniture that dwarves use. The stone stool is the owner's exception; the rest of
  doc 62's material rule (furniture is woodwork) stands.

## Open

- **The Carpenter's first goods: a wall-mounted tool hanger** (owner, 2026-11-01: "A wall
  mounted tool hanger could be a good start for the carpenter").
  - Carpenters make it at the carpenter's bench, the first recipe made there. It mounts on a wall
    as the log torch does (`placement: wall`).
  - It is built from what stone tools can make: hewn and split wood, pegs and rope, with no saw
    and no iron.
  - It holds the colony's tools (owner: "Hold tools"), so it is the first storage furniture. The
    owner added two more containers, a raw materials crate and a finished goods pallet. All three
    are planned, with concepts, in doc [294](294_storage_furniture.md).
  - Not taken for now: hewn timber, riven boards, an adzed trough.
- **The icons.** Keep the Carpenter's saw and the Stonemason's steel chisel as the careers'
  emblems, or redraw them with the stone tools they start with? The Ranger's kit was changed to
  match its icon.
- **The names** are suggestions: crude masonry kit, carpenter's bench, mason's bench, joiner's
  bench, carver's bench.
- **The numbers:** tuning in Play.
