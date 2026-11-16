# 308 — Sawn timber: planks and the Carpenter's plank look

**Status:** built 2026-11-13: planks (a good, four sawing recipes, storage) and all seven plank
pieces in the looks the owner picked the same day: the dining table, the bench, the tool rack,
the finished goods pallet, the board-game table, the raw materials crate and the food shelf. The
fence and the gate stay logs, and the carpenter's bench stays hewn. The saw in the Carpenter's
hand is not built. Nothing here has been seen in play.

## What the owner asked

> Now, the carpenter starts with a saw, therefore I think the initial set of items the carpenter
> can make don't need to be rudimentary anymore, let me know what you think about that approach

This lifts the hold of 2026-11-01 on planks ("I don't know how the dwarves can make these without
a saw yet, hold off on this"): since doc 306 no Carpenter exists without a copper saw. Three
questions were put to the owner, who answered:

> 1, agree with planks / 2, let's make a list of what upgrades to a plank look vs what retires /
> Stonemason later

and, of the list and the plank's rules below, "proceed with your reocommendations".

## The shape of it

- **Sawn, but plain.** Thick boards, pegs and saw-cut ends: a clear step up from hewn logs, and as
  plain and thick as the copper tools. No carving, no turned legs, no iron, no cloth. Fine joinery
  waits for the iron saw, which keeps something for iron to give.
- **Planks are a real good.** A Carpenter saws a log into planks, and its furniture is made from
  them. The saw has a job that is seen, and planks are there for Build later.
- **The camp stays rough.** Everything a Worker makes (stool, bed, doors, ladder, torch, campfire,
  crude workbench) keeps its hewn look. Rough means camp; sawn means Carpenter.

## The list

Seven of the Carpenter's ten pieces take a plank look; none of their uses goes. Their rough looks
leave the game and stay in the art sources (doc 64: never delete either tier's designs). (The
list first had nine: the fence and the gate were to follow, and stay logs after the owner's look
at their plank options.)

| Piece | What happens | Its plank look, in a line | Step |
|---|---|---|---|
| Carpenter's Bench | Stays hewn | It is made from logs before any plank exists, and planks are sawn on it | |
| Log Dining Table | Plank look | A board top on a pegged frame (the Tier 2 design kept since October is one option) | 1 |
| Log bench | Plank look | A plank seat on two plank ends | 1 |
| Tool Rack | Plank look | A sawn board on the wall with a row of pegs | 2, built |
| Raw Materials Crate | Plank look | A plank bin on corner posts, open inside | 2, built |
| Finished Goods Pallet | Plank look | Sawn deck boards across runners | 2, built |
| Food Shelf | Plank look | Two plank shelves between uprights, the upper set back as now | 2, built |
| Board-game Table | Plank look | The dining table's frame, with the game board marked on its top | 3, built |
| Log Fence Post | Stays logs (the owner found both plank fences too busy, 2026-11-13) | | |
| Log Gate | Stays logs, with the fence | | |

Two of these were the owner's to overrule and were left as proposed: the bench (the sitting log is
only a log, and could have stayed at the camp) and the fence (a split-rail fence needs no saw).
A plank bed, a plank door and a plank stool could join the Carpenter's page later, beside the
camp's rough ones; they are not on this list.

## What step 1 has built: the plank

| | For the player | Where |
|---|---|---|
| The good | Pine, oak, juniper and applewood planks: thick boards, carried and stored one at a time like logs | `items.json`, tagged `plank` |
| Sawing | Crafters → Carpenter → Timber: one log is sawn into two planks of its wood at the carpenter's bench, in 10 s. Each wood has its own recipe, so "keep 8 oak planks" counts oak alone | `recipes.json`; each log's own tag is its recipe's `ingredient_tag` |
| Not fuel | No fire burns a plank, and no log recipe takes one: a plank is not `timber` | |
| Its wood | Furniture made from planks takes their wood, as from logs | `craft_materials.json`, each wood's `ingredients` |
| Storage | Planks is a storage category under Materials. Ground storage takes it; the finished goods pallet takes planks four to a quarter, ahead of the ground | `storage_filters.json`, `inventory_catalog.json`, the pallet's `storage` |
| Experience | Each batch sawn is one Carpenter experience, as any batch on its page is | |

- **Found on the way.** New ground storage is meant to accept every storage category, and Metal
  had been left out of its list since copper bars arrived, so a new zone refused bars until Metal
  was ticked. The list now holds every category (`StockpileZoneComponent.DEFAULT_FILTER_TAGS`),
  and `PlankTest` fails if a category is added without it.
- **A store placed before today keeps its saved choice of goods,** so it refuses planks until All
  is pressed in its storage window (the known rule in `00_todo.md`, "The finished goods pallet's
  later goods").

## The looks: one sheet, and the owner's pick

> Plank, A / Dining Table, B / Bench, A

`tmp/plank_look_20261113/plank_look_sheet.png`: two ideas each for the plank, the dining table
and the bench, drawn in real cells and rendered as the game draws them, beside what the game has
today: in studio light, at the owner's two cameras at the sky's midday, by torch, beside a
dwarf, and in each wood. A subagent drew it from a written brief while the plank's rules were
built. Its in-world pictures are from a new world, since the owner's older save no longer loads.

| | A | B |
|---|---|---|
| Plank | A squared board, every edge sawn, three saw strokes across its face, square ends showing the ring. **Installed,** so that the rules could be built and tested | A waney board: wider and thinner, bark left along one edge |
| Dining table | The Tier 2 design kept since October: three broad planks on a centre post with a cross foot, pegs and a butterfly key. Shown also plainer, without the key and in the planks' own colours | Four boards across two plank ends, tied by a pegged board under each long side |
| Bench | Two boards pegged onto two notched plank ends, with a stretcher: built as table B is, so they make a set | A staked bench: one thick board on four wedged stakes |

What the sheet's maker found, checked against today's definitions by script:
- **The Tier 2 table as drawn does not fit today's table.** Its centre post and cross foot stand
  outside the collision and the diners' leg room, which are made for four corner legs and two
  bearers: 4,287 cells outside, and 3,216 for the plainer one. Either needs new collision and
  seat boxes. Table B has none outside and needs only its model.
- **Both benches keep the seat, the size and the collision.** Each breaks one line of the art
  test, which says a bench is solid from the ground to its seat: that describes today's log.
- **Every pale sawn face comes out the same cream at midday.** What is left to read is the
  strokes, the pegs, the gaps between boards and a step of tone from board to board. Plank A on a
  pine pallet is pale on pale; B's bark edge marks it off, and brings the camp's look back.
- **From the far camera** the two benches look alike, and the plainer table A and table B differ
  by the way their boards run and B's corner legs.
- Its own picks: plank A, table B, bench A.
- **Not checked:** diners' boots against a new table, a dwarf seated on either bench; the
  planks on the pallet in its picture were set at the quarters by hand.

## What step 1 has built: the table and the bench

| | For the player | Where |
|---|---|---|
| Plank Dining Table | Four broad boards across two plank ends, pegged, a board under each long side. Four matching planks, 16 s at the carpenter's bench. Its footprint, top height, stools' places and diners' leg room are the log table's | `dining_table` (key unchanged); `plankTable()` in `tier2.mjs` |
| Plank bench | A seat of two boards on two notched plank ends with a stretcher. Two matching planks, 10 s. One broad seat a block up, as before | `bench`; `plankBench()` |
| Appeal | One point more than their log forms: the table's design 2, the bench's 3 | their definitions |
| Their wood | Each takes the wood of its planks; the recolour is the game's own, on the palette the log pieces used | `hand_hewn_timber` |
| Words | The recipe card and its waits name planks: "Waiting for 4 pine planks"; the allowed woods read Pine, Oak, as for logs | the recipes' `ingredient_words`; `CraftingManager.ingredient_label` |
| Kept | The log table's four stumps and the sitting log stay in `tier1.mjs`, uninstalled; the October table and bed are untouched | |

- **A colony's own tables and benches change look,** since the keys are the same, and gain their
  point of appeal. A room one point under Pleasant may cross into it.
- **The board-game table still stands on the log table's stumps and bearers,** so the two no
  longer match until step 3.
- A subagent installed both models and their menu pictures in ten minutes from its own sheet's
  builders, while the recipes, names and tests were changed over. Its one look in the game:
  `tmp/plank_look_20261113/world/installed_table.png` (two diners) and `installed_benches.png`
  (four woods, a dwarf seated).

## Steps 2 and 3: three sheets, for the owner's pick

The owner, after the table and the bench were installed: "I think we should review the tool rack,
raw materials crate, finished good pallet, food shelf, fences, and board game table now that the
carpenter starts with a saw". Three subagents drew two ideas for each piece the same day, in real
cells with `tier2.mjs`'s helpers, beside today's piece, loaded or in use, at the owner's two
cameras, by torch and in each wood. Nothing is installed. Each folder under
`tmp/plank_pieces_20261113/` holds its sheet (`sheet.png`) and the builders of every option
(`art.mjs`).

| Piece | A | B | Sheet |
|---|---|---|---|
| Tool Rack | A peg rail: one broad sawn board on the wall with three pegs | A peg shelf: the same rail under a narrow shelf board on two short plank ends | `rack_shelf` |
| Food Shelf | Two shelves between two plank ends, the upper shallower | Plank steps: two broad steps on stair-sawn sides | `rack_shelf` |
| Raw Materials Crate | A post-and-board bin: corner posts, two boards a side with a gap, crossing boards for the quarters | A low trough: one thick board on edge per side, one across the middle | `crate_pallet_game` |
| Finished Goods Pallet | A plain pallet: four deck boards across three runners, gaps between them | A plank platform: boards laid tight inside a board on edge all round | `crate_pallet_game` |
| Board-game Table | The plank dining table with the game scratched across its two middle boards | The same frame with a separate game board let into its top, two cells down | `crate_pallet_game` |
| Fence and gate | Post and board: a sawn post with a slanted top over two boards let into it; a boarded gate with a brace, wooden hinge blocks and a latch bar | Capped: posts cut level under one broad board laid flat along their tops, one board below; a gate with its own cap | `fence_gate` |

What the sheets' makers found, by script against today's definitions:
- **Every option keeps its piece's rules:** no cell outside today's footprint and collision, no
  storage place, hook, deck height or hinge moved. Each needs only its model and new words.
- **Two exceptions, neither a rule of the game.** The capped fence breaks two lines of the art
  test that describe today's rails. The let-in game board lies two cells under the height the
  game is played at.
- **The capped fence reads boldest from the far camera,** as one unbroken band, where post and
  board is today's row of squares joined by two lines, tidier and no bolder. But a board along
  the post tops is kin to the top pole of an option the owner passed over on 2026-11-11, and its
  lower board cannot be seen from far.
- **The peg rail is a pale band on a wall again;** on 2026-11-11 the owner took the log's bark
  over a pale face. The peg shelf shades its own pegs and the tools' heads at midday.
- **Pine planks on a pine pallet are pale on pale** on both pallets, as today; the plain
  pallet's gaps keep its deck readable under its goods.
- **A crate is told by its height:** from far the two crates differ little, and the low trough
  empty is a frame on the grass.
- Their own picks were A for every piece.
- **Not checked on any of them:** the pieces' own Godot tests (they need installed models), a
  dwarf at work at each, menu pictures. Goods and gates in the pictures were set by hand as the
  game sets them.
- **On install:** the Zones "Animal pasture" icon replays the fence post and rails and must be
  re-rendered; the game table's frame should become one helper shared with the dining table.

### The owner's picks from the three sheets

> Tool rack, A / Crate, let's rethink it, I don't think it needs connecting pieces through the
> middle / Pallet, A / Game Board, A / Fence, looks too busy, would they use planks here or
> should we leave it as logs

| Piece | The owner | What followed |
|---|---|---|
| Tool Rack | A, the peg rail | Installed the same day: two matching planks, design appeal 2 |
| Finished Goods Pallet | A, the plain pallet | Installed: four matching planks, design appeal 2 |
| Board-game Table | A, the dining table with the game marked on it | Installed: four matching planks and its Rough Stone, design appeal 3; it shares the dining table's frame |
| Raw Materials Crate | Rethink it: nothing through the middle | Drawn again, three ideas with an open inside: `tmp/plank_pieces_20261113/crate_pallet_game/crate_sheet.png`; then "Crate, A", the open bin, installed |
| Fence and gate | "looks too busy, would they use planks here or should we leave it as logs" | Left as logs, my answer to the owner's question; nothing changes unless the owner says otherwise |
| Food Shelf | Not named in the answer | Asked again: "Food Shelf, A", two shelves between plank ends, installed |

**Why the fence stays logs** (my answer): a rail fence is split, not sawn. Splitting rails needs
no saw, and sawing two planks from a log to fence a field spends the saw on rough outdoor work. A
peeled-log fence also matches the peeled-log walls it stands beside (they share a palette), and
its look is the owner's own pick of 2026-11-11, drawn bolder for the far camera. Both plank ideas
added boards, pegs and hinge blocks without reading bolder from far, the capped one apart. So
the rule reads: a Carpenter's furniture is sawn; its field work, the fence and the gate, stays
hewn. They stay on the Carpenter's page, made from a log each.

### What was built for the three picked pieces

| | For the player | Where |
|---|---|---|
| Tool Rack | The peg rail: one broad sawn board on the wall with three pegs. Two matching planks, 12 s. Its hooks are where they were | `tool_rack`; `plankToolRack()` in `tier2.mjs` |
| Finished Goods Pallet | The plain pallet: four deck boards across three runners with gaps between. Four matching planks, 16 s. Its quarters and deck height are as before | `finished_goods_pallet`; `plankPallet()` |
| Board-game Table | The plank dining table with the game scratched across its two middle boards and six counters. Four matching planks and a Rough Stone, 18 s. It matches the dining table again | `board_game_table`; `plankGameTable()`, on the shared `plankFrame()` |
| Appeal | One point more each: the rack and the pallet 2, the game table 3 | their definitions |

- A subagent installed the three models and their menu pictures in eight minutes from the
  sheets' builders. Its one look in the game: `tmp/plank_pieces_20261113/fence_gate/world/`
  (`installed_rack_pallet.png`, `installed_game_table.png`).
- Each quarter's middle on the pallet lies over a gap between two deck boards, as picked; a
  stored good rests on the boards either side, which the art test pins.

### The crate, drawn again

`tmp/plank_pieces_20261113/crate_pallet_game/crate_sheet.png`: three ideas with nothing crossing
the inside, beside today's log crib, empty and holding its goods.

| | The idea | Needs |
|---|---|---|
| A | The open bin: a post at each corner, two boards a side with a gap, no floor | Its model |
| B | A bin with a lower front: the same with one board on its front, so the front goods show nearly whole; turned with R when placed | Its model |
| C | A plank box on two runners: two boards a side laid tight, a floor of three planks | Its model, and the goods' places raised by 4 cells (a quarter of a block) to stand on the floor |

Empty, A and B read as a frame on the grass; C shows its floor and still reads as a box. Its
maker's pick, and mine, was C.

### The owner's last two picks

> Crate, A / Food Shelf, A

| | For the player | Where |
|---|---|---|
| Raw Materials Crate | The open bin: a sawn post at each corner, two boards a side with a gap, nothing inside but its goods. Four matching planks, 16 s. Its quarters and its goods' places are as before | `raw_materials_crate`; its builder in `tier2.mjs` |
| Food Shelf | Two shelves between two plank ends, the upper shallower so both rows show. Four matching planks, 16 s. Its six places are where they were | `food_shelf`; its builder in `tier2.mjs` |
| Appeal | One point more each: 2 | their definitions |

The owner took the open bin over the box with a floor, which was my pick: the plainer form again.

## Decisions of mine, for the owner to confirm

1. **One log makes two planks,** in 10 s, and a plank piece will cost the planks of the logs its
   rough form cost (a table two logs' worth: four planks).
2. **Four sawing recipes, one a wood,** instead of one "Planks" recipe that takes any log. The
   player says which wood to saw, and a standing order counts one wood.
3. **Planks are their own storage category,** not Wood: the pallet can then take planks and
   still refuse logs.
4. **Four planks to a pallet's quarter** (metal goods are three).
5. **A plank piece will carry one more point of appeal** than its rough form did (told to the
   owner with the list; applied as each piece changes over).
6. **The pieces kept their keys** (`log_table`, `bench`): a colony's rough tables and benches
   turned into plank ones, and its save kept loading. The owner's naming pass of 2026-11-15
   then renamed the table's key `dining_table`, an id by use (doc 13, "Naming ids and files"),
   and saves from before that day no longer load.
7. **Their names:** "Plank Dining Table" and "Plank bench".
8. **A table is four planks and a bench two,** the planks of the two logs and the one log they
   cost before.

## Not built

- The other seven pieces (steps 2 and 3 of the list).
- The saw in the Carpenter's hand: it still swings the stone adze and is heard as an axe.
- Everything in `00_todo.md`, "Sawn timber left for later".

## Tests

- New: `PlankTest` (the four recipes, a log into two planks of its wood and no other, never fuel,
  the storage category and the pallet's rule, the Carpenter's page, Carpenters only, experience,
  each plank's model and menu picture).
- Reworked: `FinishedGoodsPalletTest` (planks four to a quarter beside the bars, logs kept off, a
  save keeps both); `ItemArtTest` (a plank lies flat inside a log's stockpile slot; 68 goods).
- The art pipeline's own tests gained the plank (`tools/voxel_assets/test_items.py`).
- `ProfessionPathTest` lists the four sawing recipes on the Carpenter's page.
- For the two pieces: `PlankTest` (a table from four planks of one wood, never from logs; names
  and appeal), `LogDiningTableTest` and `LogFurnitureTest` (made from planks), `RoomAppealTest`,
  `AppealViewTest` and `TastesTest` (the rooms' sums with the extra point). The art pipeline's
  bench test no longer says a bench is solid to the ground: it asks for a whole, level seat and
  feet under both ends.
- `CraftingSelectionTest` (gate) stocks each recipe with the first good a new order allows; it
  had given the plank table applewood planks, which a new order does not take.

- For the tool rack, the pallet and the game table: `ToolRackTest`, `FinishedGoodsPalletTest` and
  `RudimentaryRecreationTest` make them from planks; `PlankTest` holds their plank counts and
  appeal, and that the crate, the food shelf, the fence, the gate and the carpenter's bench are
  still made from logs. The art pipeline gained a rack test and a pallet test, and its game
  table test now compares the frame with the plank dining table's.

- For the crate and the food shelf: `CrateTest` and `FoodShelfTest` make them from planks; the
  crate's test now says a shown good stands higher than the gap between a wall's two boards (it
  had said a good rises over the crib's rim); the art pipeline gained a crate test and a shelf
  test.

Results, 2026-11-13, after all seven pieces: the gate, 55 of 55, lint clean (209 known); the
crafting, storage, interface, art, furniture, saves, rooms and dwarves areas, 118 of 118; the art
pipeline's 73 tests. Nothing was played.
