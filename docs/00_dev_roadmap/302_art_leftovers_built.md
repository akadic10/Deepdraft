# 302 — The art review's leftovers, built

**Status:** built 2026-11-11 from the owner's eleven picks; not yet seen in play.

## What the owner asked

On 2026-11-11 the owner asked for every leftover of the art review (doc 301, retired) to be
proposed ("Propose them all so I can review the three options and pick one"), and then picked
one option on each of the eleven sheets in `tmp/proposals_20261111/sheets/`:

> log bench, C / good pallet, B / food shelf, B / tool rack, B / pine log colors, 2 / hearth, C /
> campfire, B / career kits, C / tool icons, A / fence, A / midday light, 2

The picks differ from the ones marked on the sheets in three places: the log bench (C, the
sitting log, over B), the hearth (C, a split boulder, over B) and the fence (A, the same fence
drawn bolder, over B). Each package folder beside the sheets keeps its concept models and the
options passed over.

## What was built

| Pick | What changed for the player | Where |
|---|---|---|
| Log bench, C | The bench is one whole log lying on the ground, wedged so it cannot roll, with a seat hewn flat along its top | `logBench()` in `tier1.mjs`; `bench.json` and its recipe's words |
| Goods pallet, B | The same log skids, the deck laid as four broad split halves | `finishedGoodsPallet()`; `finished_goods_pallet.json` and its recipe's words |
| Food shelf, B | The same lean-to rack, its decks broad split halves, its posts' bark in ridges | `foodShelf()`; `food_shelf.json` and its recipe's words |
| Tool rack, B | The same pegged log, hung bark side out | `toolRack()`; `tool_rack.json` and its recipe's words |
| Pine's log colours, 2 | Pine beds, doors, ladders and torches take honey: their cut ends, slab faces, grain, rungs and sticks | six of pine's `colors` in `craft_materials.json` |
| Hearth, C | The fire-back is one split boulder in worked stone, the piece split from it its hearthstone | `hearth()`; `hearth.json` and its recipe's words |
| Campfire, B | The ring is five great stones in worked stone on ground burnt black | `campfire()`, new in `tier1.mjs`; `export.mjs` and `write_data.py` point at it |
| Fence, A | The post's top is chopped in two steps, its knot and check show, and the rails are lashed on with rope; the gate follows | `fencePost()`, `fenceRails()`, `gateLeaf()` |
| Career kits, C | Each kit is its two tools crossed and lashed where they cross, with the heads the dwarves now hold | `starter()` in `hearthblock_goods.py`; the kits' words in `items.json` |
| Tool icons, A | The nine icons that drew iron show stone tools, and the Blacksmith's shows his boulder smelter | `icons.mjs` |
| Midday light, 2 | The sun's path leans 30°, so at the sky's midday it stands 60° up: sides are lit and shadows fall beside things | `SkyController.gd`; `sky_settings.json` |

Each production model equals its picked concept cell for cell (`tmp/build_20261111/equal.mjs`
for the furniture; `port/check_goods.py` and `port/check_icons.mjs` under
`tmp/proposals_20261111/kits_icons/` for the kits and the icons), and the nine icons came out of
the game's own renderer pixel for pixel as on the sheet. Re-rendered: the menu pictures of the
eight changed pieces (the gate has its own), the three kits' item pictures, the nine icons and
the Animal pasture icon, which replays the fence.

Also re-rendered: the Build menu's two pine log pictures (`log_upright_pine`,
`log_horizontal_pine`). They are drawn in pine's hewn colours and had kept the paler pine
from before the honey of 2026-11-10, while pine walls in the world have been honey since.
The pine log colours sheet said no menu picture needed redrawing; that holds for the pick
itself (beds, doors, ladders and torches have oak-coloured pictures), and these two were a
leftover of 2026-11-10 found on the way.

Other things that moved with them:
- The campfire's model is `campfire()` in `tier1.mjs`; `proposal.mjs` keeps the proposal's
  eight-stone ring. The hearth and the campfire take the `hewn` palette, which holds the worked
  stone's colours.
- The four plank colours left the icon palette: the Carpenter's saw on a plank was their only
  user.
- The masonry kit's recipe says "crossed and lashed together", as its item does.
- The sun's lean is `sun.path_lean_degrees` (30). Only the sun leans; the ends of its path keep
  their directions, and `DioramaSkyTest` checks the midday height, the side, a rebind and the
  moon (doc 24, "Sky").

## Checked

- The job gate: 55 of 55, lint clean (211 known).
- The art pipeline: 66 Python tests; `build.py --check` for furniture and items.
- The art tests (10 of 10) and the fence, storage, fire, bench, item and sky tests.
- One look in a copy of the owner's colony, every piece installed by the game's own code, at
  the sky's midday and at nine: `tmp/proposals_20261111/build/world/`.
- Every menu picture against a fresh render, on every colour channel: the 36 furniture
  pictures and the 73 item pictures match (one item picture differs in one pixel), and of the
  100 icons 81 match, the two pine log pictures were stale and are replaced, and 17 older
  ones differ in 1 to 23 pixels by at most 6 colour steps in 255 and were left as they are.
  The first pass of this check compared only the pictures' outlines (a Pillow `getbbox()`
  on a picture with alpha), which is how the two pine pictures were put back unnoticed; doc
  61, "Running a script that draws", has the right comparison.

## Checks that changed

- **The bench's shape check** (`test_bench_seat_contacts` in `test_hearthblock.py`) asked for
  air under the middle of the seat, between two feet. A log has none: it now asks that the log
  is solid from the ground to the seat at three places. The seat's height, its flat support
  under the sitter and the bench's size are checked as before.
- **The hearth's flame check** (`HearthRoomTest`) asked for the stone back to stand 0.4 blocks
  over the flame's top, which fitted the stacked slabs (7 cells). The boulder's crown stands 5
  cells over it, so the check asks for 0.3. The flame still burns below the top of the back.

## For the owner's look in play

- The eleven changes above, at your own camera, by day and by fire.
- A bench beside a table: the sitting log is mostly bark, darker than the half log it replaces.
- A kit in a dwarf's hands on its way to a stockpile or the rack: crossed kits were looked at
  on the ground and on the rack, not carried.
- Build → Wood with pine chosen: the Upright log and Horizontal log pictures are now pine's
  honey, as the walls are.
- The colony at the sky's midday (14:00 by the clock in the 2026-11-10 save): shadows now fall
  beside things, and the mountain's shadow moves with them. At sunrise and sunset the sun
  stands about 2° lower than it did.

## Left open

- Nothing from the art review's list. Options passed over stay in
  `tmp/proposals_20261111/` beside the sheets.
