# 306 — The profession path

**Status:** step 1 built 2026-11-13 from the owner's picks of the same day. The owner's play
that day brought two fixes: the crafting screen, not yet seen in play, and the career map, of
which the owner said "this makes more sense now".
The tools' look is the owner's pick of the same day, from one sheet (`tmp/profession_path_20261113/tools_sheet.png`). Nine decisions of mine,
below, wait for the owner's word. Steps 2 and 3 are not built.

**2026-11-14:** the four copper tools are hammered on the anvil stone, a station of its own, no
longer on the basic smelter's casting stone (doc 310; doc 44, "The anvil stone").

## What the owner asked

> Can we review the current available professions? I am not sure it feels great that all of them
> can start right away, I think we cane easily have the Miner, Ranger, Carpenter, Stonemason and
> Blacksmith. But it doesn't feel rewarding at all I think. Can you help me plan a better
> profession path, perhaps the Miner, Carpenter and Stonemason have to be gated behind the
> blacksmith and instead of getting rudimentary tools they get a copper saw, copper chisel and
> copper mining pick? This means that some recipes may need to be adjusted or moved back to
> rudimentary?

The review found why it felt flat: every trade's tool cost a Worker one log and one Rough Stone
(the Miner's nothing), no trade opened another, nothing from under the ground mattered to any of
them, and copper had no use at all. Six decisions were put to the owner, who answered:

> 1 - move the log bed and all log doors back to rudimentary / 2 - agree, and I do want the saw
> to look like a japanese pull saw / 3 - agree / 4 - I think I want to remove copper fittings,
> we'll just simplify this scenario and use copper bars / 5 - agree / 6 - agree, but we should
> probably do the same with the stone hoe and make a copper hoe instead

| | The question | The owner's pick |
|---|---|---|
| 1 | What goes back to Rudimentary | The log bed and all three log doors |
| 2 | What the copper Carpenter and Stonemason make | Today's goods for now; the saw is a Japanese pull saw |
| 3 | The basic smelter also burns logs, two in place of the coal | Yes |
| 4 | Copper fittings | Removed for good; what would take fittings takes bars |
| 5 | The copper pick digs 20% faster | Yes |
| 6 | The crude carpentry and masonry kits are retired | Yes, and the stone hoe too: a copper hoe instead |

## The path

| Stage | Trade | Its tool | Made by |
|---|---|---|---|
| Camp | Ranger | Ranger's kit | a Worker, a log and a Rough Stone |
| Camp | Blacksmith | Stone hammer | a Worker, a log and a Rough Stone |
| Copper | Miner | Copper pick | a Blacksmith, a copper bar and a log |
| Copper | Carpenter | Copper saw | a Blacksmith, a copper bar and a log |
| Copper | Stonemason | Copper chisel, with its maul | a Blacksmith, a copper bar and a log |
| Copper, planned | Farmer | Copper hoe | a Blacksmith, a copper bar and a log |
| Iron, planned | the copper trades | Iron pick, saw, chisels | as doc 44 already plans |

## What step 1 built

| | For the player | Where |
|---|---|---|
| The copper tools | Crafters → Blacksmith → Tools: copper pick, copper saw, copper chisel and copper hoe, each from one copper bar and a log, hammered on the basic smelter's casting stone in 12 to 14 seconds. A tool keeps its haft's wood ("Oak copper pick"). | `recipes.json`, `items.json`; `WorkerCraftOrder.capture_item_properties` |
| The gate | A Miner needs a copper pick, a Carpenter a copper saw, a Stonemason a copper chisel, each collected by hand as the Ranger's kit is. The crude carpentry kit, the crude masonry kit and the stone hoe are gone. | `required_tool` in `professions.json` |
| The pick | A Miner digs in a fifth less time than a Worker, before its levels: 80% of the time at level 1, 64% at level 5. Workers keep the stone pick and still mine. | `equipment.dig_time`; `DwarfAssets.mining_duration_multiplier` |
| Rudimentary | The log bed and the 2-wide, 3-wide and double 4-wide log doors are made by Workers at the crude workbench again, under Rooms. | `recipes.json` |
| Fuel | A copper bar melts over a coal, or over two logs of one wood when the colony has no coal. An order with neither reads "Waiting for a coal or two logs". | a recipe's `one_of`; `CraftingManager.choice_keys`, `WorkerCraftOrder.settle_choice` |
| The charge | Logs are pushed into the fire hole; the ore, and a coal, still go into the pot. | `DwarfSmeltPose`, `WorkerCraftOrder.fire_goods` |
| No fittings | The copper fittings recipe, good and model are removed. | |
| The career map | Every trade in one row under the Worker, with who makes its tool said under the tiles: "A Worker makes their tools" under the Ranger and the Blacksmith, "A Blacksmith makes their tools" under the Miner, the Carpenter, the Stonemason and the Farmer. (First built as a tree with the copper trades under the Blacksmith; see "After the owner's look at the career map".) A trade the colony has no free tool for reads "Needs tool", and its card says who makes the tool. A Worker's map opens on the Blacksmith. | `promotion_screen` in `professions.json`; `DwarfProfessionPanel` |
| Words | A refused promotion says "No spare copper saw. A Blacksmith makes it at the basic smelter." | `DwarfEquipment.blocked_reason`, `DwarfAssets.tool_source_text` |

## The tools' look

One sheet, `tmp/profession_path_20261113/tools_sheet.png`: two ideas for each tool, drawn in real
cells and rendered as the game draws a loose item, from the play camera and from above, in the
game at the owner's two camera distances and by torch, lined up beside a dwarf, hung on a tool
rack and in each wood. The owner's pick:

> Miner's pick, A / Carpenters saw, A / Chisel and hammerstone maul, A / Farmers hoe, B

So the pick, the saw and the chisel are their A, and the hoe is its B, the bent-knee hoe on its
side. All four are installed with their menu pictures.

| Tool | A | B |
|---|---|---|
| Pick | The stone pick's outline cast in copper: one bar pointed at both ends, across the haft | One point and a flat hammer poll |
| Saw, a Japanese pull saw | A ryoba: a long corded handle in line with a blade that widens to its end, fine teeth on one edge and coarse on the other | A blade let into a long split stick that is its handle and its back, teeth on one edge |
| Chisel | The copper chisel crossed with the hammerstone maul the Stonemason swings, lashed where they cross | The same chisel with a wooden mallet |
| Hoe | A broad flat blade lashed under the haft's end | A bent-knee hoe lying on its side |

- **Changed from what was briefed.** The hoe's B was to be a narrow blade square across the haft's
  end; from above that is the pick's T, so B became the bent-knee hoe. The chisel lies aslant, in
  steps, because it is crossed with the maul.
- **Copper is drawn dark** (doc 64, "Copper tools"): at midday the bar's pale colour comes out as
  pale as pine, so the tools are the bar's body colour with the pale only on ground edges.
- **Checked by the art tests:** no tool is longer than a rack's hook is high (27 to 37 cells
  against 39), none holds more copper than one bar, and no fixed colour can pass for a wood when
  the haft is recoloured. The Ranger's kit, the stone hammer and the copper bar are unchanged
  byte for byte.
- **Not checked:** how each tool sits in a dwarf's hands when carried. Tools hung on neighbouring
  hooks can touch by a few cells (at most 7 among the A options; two of the old masonry kits met
  in 29). The hoe the owner picked is broader and taller than its A (15 by 7 cells against 12 by
  3); how far it meets a neighbour on the rack was not measured.
- **The hoe from above** shows little copper and can read as a hatchet from some sides; the owner
  picked it over the flat blade, which read as a spade.
- **Retired art:** the models and menu pictures of the crude carpentry kit, the crude masonry kit,
  the stone hoe and the copper fitting are deleted. Their eight `.import` files were deleted on
  the owner's word on 2026-11-15.
  The old drawings are kept in `tmp/profession_path_20261113/tools/before/`.
- **Also looked at:** the career map (`tmp/profession_path_20261113/career_map_miner.png`), the
  seven tool pictures (`menu_pictures.png`, same folder) and the log-fuelled charge frame by frame
  (`tmp/smelter_anim_20261112/sheets/logs_profilelogs_toss.png`).

## After the owner's first new game

> I started a new game, when pressing the crafting screen, carpenter for example is lit up even
> though I cannot build it, same with others.

The crafting screen lit every live page whether or not anyone could craft from it; with the
trades gated, that was every trade at the start. Fixed the same day: a page's button is lit only
while the colony has a dwarf of its career, on the dock's Craft menu and in the crafting window's
Crafters row. The others are dimmed and locked, say "No Carpenter yet" and the way to one, and
still open (doc 23, "Craft"). `ProfessionPathTest` covers it. A decision of mine: the pages stay
open, and orders can still be queued on them ahead of the trade.

## After the owner's look at the career map

> When promoting dwarves, this page is confusing and it would seem as if the Dwarf has to be a
> blacksmith first before becoming a farmer.

Step 1 drew the map as a tree and hung the copper trades under the Blacksmith, joined by lines,
because the Blacksmith makes their tools. On a page about one dwarf those lines read as that
dwarf's way through the trades, which it is not: every trade is promoted from the Worker.
Changed the same day (doc 23, "The map"):

- **Every trade stands in one row under the Worker,** as the map was before step 1. A line is
  what a dwarf is promoted from, and nothing else.
- **Who makes the tool is said under the tiles.** The Ranger and the Blacksmith stand over a
  bracket named "A Worker makes their tools"; the Miner, the Carpenter, the Stonemason and the
  Farmer over "A Blacksmith makes their tools". The groups are read from the tools' recipes.
- **The chosen trade** has its line, its group's bracket and the bracket's name in copper.
- Pictures: `tmp/career_map_20261113/` (`before_tree_blacksmith.png`, `after_career_map_blacksmith.png`,
  `after_career_map_miner_map_zoom.png`). `ProfessionPathTest` holds the rule: no trade under
  another, the groups and their names, and the tiles, brackets and names clear of each other at
  1280 x 720 and at 960 x 540.

Decisions of mine in it: the names' words; the bracket under the tiles and not a heading above
them; the Worker's two trades first in the row; no bench in the name (the card gives it).

The owner's look the same day:

> this makes more sense now

Taken as the map now reading rightly. It was not an answer to the nine decisions below; a
Worker's map still opens on the Blacksmith (decision 5).

## The rules, and where they now live

- **Doc 41, "The profession path":** the table, who makes which tool, the pick's bonus, the map.
- **Doc 44, at the top and under "Specialist workbenches":** the Blacksmith's tools, Rudimentary
  as the first camp, the fuel and haft choices (`one_of`), the ladder with copper as its first rung.
- **Doc 43, "Pickaxe upgrades":** the stone pick, the copper pick, then iron.
- **Doc 23:** the career map. **Doc 64:** the copper tools' look.
- **`00_todo.md`, "The profession path left for later":** steps 2 and 3 and the leftovers.

## Decisions of mine, for the owner to confirm

1. **A coal is burnt before logs.** While coal has no other use it saves timber. When iron needs
   coal this wants turning round, or a switch on the order.
2. **A haft takes pine first,** then oak, juniper and applewood, with no picker. The plainest wood
   goes first so applewood is not spent on a pick.
3. **One bar and one log make one tool,** in 14 seconds for the pick and the saw and 12 for the
   chisel and the hoe.
4. **The Stonemason's good is the "Copper chisel",** drawn with the maul that drives it, as the
   kits were two tools bound together.
5. **A trade whose tool is missing reads "Needs tool"** on the map, and a Worker's map opens on
   the Blacksmith instead of the Miner.
6. **The pick's bonus came with step 1,** not step 2 as planned: without it a Miner in step 1
   would have been gated and no better than a Worker.
7. **A Miner loaded from a save without a pick stays a Miner** and digs at a Worker's pace.
   Nothing demotes it or sends it for a pick.
8. **The Carpenter still swings the stone adze at the bench** until step 2 draws the saw in its
   hands, and the careers' icons still show stone tools.
9. **The Farmer's tile stands with the copper trades,** over "A Blacksmith makes their tools",
   still planned.

## Not built

- **Step 2, the tools in hand:** the copper pick in the mining pose, the pull saw and a sawing
  motion at the carpenter's bench, the chisel under the maul, the careers' icons.
- **Step 3, what copper tools make:** planks and dressed stone, if the owner lifts the hold of
  2026-11-01 for copper.
- No surface signs of copper. (A log going into the fire hole has its sound since doc 307.)

## Saves

A save that names a retired good (a crude kit, a stone hoe, copper fittings) is refused at
startup, as any save naming unknown content is. Skarberg has a masonry kit on a tool rack, so it
no longer loads; the owner agreed to start a new colony. Copies of its quick save and autosave
from before the change are in `tmp/profession_path_20261113/saves_before/`.

## Measured for the plan

61 starting digs in 8 worlds, the owner's among them (`tmp/profession_path_20261113/copper_reach.json`;
2 × 3 tunnels, an ore counting once it shows in a wall, floor or roof):

| Dig | Copper within 32 steps | Coal within 64 | Both within 64 |
|---|---|---|---|
| A stair 12 down, then level | 75% | 72% | 66% |
| A level tunnel into a cliff foot | 18% | 36% | 26% |

Ore is 0.6% of rock in the outer ten blocks and about 5% deeper, and stays hidden until a tunnel
touches it (Hard Rule 11). So copper is found by digging down, coal was the bottleneck, and the
log fuel takes coal off the path to the first tools.

## Tests

- New: `ProfessionPathTest` (who needs which tool and who makes it, the pages, a Worker's bed and
  door, fuel and haft choices, the career map with every trade under the Worker).
- Reworked: `BasicSmelterTest` (a copper pick from a bar and an oak log, a bar melted over logs
  with a late coal left alone), `ToolPromotionTest`, `EquipmentFeedbackTest`, `MinerProfessionTest`
  (no Miner without a pick; the pick's fifth), `StonemasonTest`, `CarpenterTest`, and the tests
  that used the stone hoe, the kits or fittings as their example goods.

Results, 2026-11-13: every test, 238 of 238, the gate's 55 among them; lint clean (209 known).
The art pipeline's own 68 tests pass. Nothing was played.
