# 310 — The anvil stone

**Status (2026-11-14):** built the same day from the owner's pick, B, and not yet seen in play.
The rules now live in doc 44 ("The anvil stone", at its top, and "The Forge"), doc 41 (the
path's table), doc 62 (the piece) and doc 64; what is left is in `00_todo.md` ("The Blacksmith
left for later"). This doc stays until the owner has looked: "accepted" retires it.

## What the owner asked

> How does the Blacksmith make a copper saw now, I think the smelter should not be that
> workstation, does the blacksmith need another workstation?

I recommended a second station for the Blacksmith, an anvil stone, and asked two things. The
owner's answer: "1 yes, 2 draw a sheet of looks first". So the station is agreed, and its look
is picked from a sheet before anything is built.

## How it works today

- All four copper tools (pick, saw, chisel, hoe) are made at the basic smelter: one copper bar
  and a log for the haft, hammered with the stone maul on the casting stone, 12 to 14 seconds,
  no wait (`recipes.json`, each recipe's `workshop`).
- That was part of my plan for the profession path (doc 306), not one of the owner's six picks.
  Copper fittings had been hammered on the casting stone, so the tools went there.
- A melting charge, and a set bar until it is taken off, claims the smelter
  (`CraftingManager.hang_batch`, `bench_valid`), so no tool can be hammered meanwhile. With one
  smelter, bars and tools take turns.

## The looks

The sheet is `tmp/anvil_20261114/anvil_stone_sheet.png`: today's casting stone and three ideas,
in studio light and in the game at two of the owner's cameras, at the sky's midday and by torch,
with nobody at each and with a Blacksmith hammering a bar on it, and each idea beside a smelter.
Each keeps its hammering face 15 cells up, the casting stone's height, so the Blacksmith's swing
stays as it is.

| | The idea | Size | It needs |
|---|---|---|---|
| A | A stone on a stump: one hard stone on the stump of a felled tree | 1 × 1 | A log and a Rough Stone (my proposal). The stump would take its log's wood. Under a dwarf it is a stool's size, and a bar covers its whole face. |
| B | One great stone: a boulder two cells broad, its top split off level, no wood | 2 × 1 | Three Rough Stones (my proposal). |
| C | The stone and the hafting block: an anvil stone, and beside it a stump with a saddle hewn across its top and the rope hung on it | 2 × 1 | A log and two Rough Stones (my proposal). The Blacksmith works only at the stone; the block is for show unless a binding motion is drawn. |

My pick is B: it holds its own under a dwarf and beside the smelter, it is one more boulder
knocked into use, as the smelter and the hearth are, and its face has room for the bar and the
blows.

Checked by script: every cell of each idea is inside its footprint and none stands above 15
cells. Not checked: no furniture test has run, because nothing is installed.

The concept models, the scene and the sheet's script are in `tmp/proposals_20261111/anvil/`
(`art.mjs`, `World.gd`, `sheet.py`), made with the proposal rig beside them.

## The owner's pick

> B, perhaps this work station can work for copper, bronze, etc... until the iron anvil arrives
> later

So B, the one great stone, was built. The second half is a rule for later, recorded in doc 44:
the anvil stone is where copper is hammered and whatever else comes before iron, and the Forge's
forged anvil replaces it. Nothing was built for bronze, which the game does not have.

## What was built

| What | Where |
|---|---|
| The piece: `base:furniture:anvil_stone`, 2 × 1, worked at its left cell at the casting stone's height | `data/furniture/anvil_stone.json`; its packed good in `items.json`; Place → Workshops in `place_catalog.json` |
| Its model, cell for cell the concept the owner picked (`tmp/anvil_20261114/equal.mjs` proves it) | `anvilStone()` in `tools/hearthblock/art/tier1.mjs`; `assets/models/furniture/anvil_stone.glb`; menu picture `assets/ui/furniture/anvil_stone.png` |
| Its recipe: three Rough Stones, 18 s, Blacksmiths at the crude workbench, Workshops | `recipes.json` |
| The four copper tools' `workshop` is the anvil stone; their words say so | `recipes.json`, `items.json`, `professions.json` |
| The smelter only melts and casts; its words say so | `data/furniture/basic_smelter.json`, `recipes.json` |
| "Needs an anvil stone": a bench is named with its own article | `CraftingManager.with_article`, `WorkerCraftingPanel` |
| Tests: `AnvilStoneTest` (new, in the crafting area): made by a Blacksmith alone, its stands and window, a pick hammered at the middle of its left cell while copper melts | `scripts/tests/` |

Checked: gate 55 of 55, lint clean; the crafting area 25 of 25 and the art area 10 of 10; the
pipeline's 76 tests and `build.py furniture --check`; the installed piece beside a smelter in a
new world (`tmp/anvil_20261114/installed_in_game.png`); a copy of the owner's quicksave of
2026-11-14 loads with the piece in the game.

## Decisions I took while building

They hold unless the owner says otherwise.

1. **The name:** Anvil Stone.
2. **Its cost:** three Rough Stones and 18 seconds, as the sheet proposed.
3. **The bar lies at the middle of the stone's left cell,** whichever side the Blacksmith stands
   on, where the face is pitted (`crafting_surface_radius` 0). On the casting stone it lay a
   quarter block toward the worker.
4. **The casting stone is as it was drawn,** peck marks included.
5. **Its window's button is "Hammer tools"** and opens the Blacksmith's page at the copper pick.
6. **It adds no appeal to a room** (`appeal.design` 0), as the smelter adds none.
7. **The smelter's purpose line was shortened** ("Blacksmiths melt copper ore in it and cast it
   into bars."), so its recipe's board still fits a 1080p screen.
8. **A colony with a smelter and no anvil stone can make no tool** until it has one: three Rough
   Stones away. No tool order is moved or cancelled.

## The plan the build followed

- **The piece:** a new furniture definition and its model (moved into `tier1.mjs` unchanged),
  made by Blacksmiths at the crude workbench from raw goods, under Crafters → Blacksmith →
  Workshops, and installed through Place → Workshops.
- **The tools move:** the four copper tool recipes name the anvil stone as their workshop. The
  smelter makes only bars and keeps its casting stone, where the bar sets and is taken off.
- **Words:** the smelter's and the recipes' descriptions, "Needs an anvil stone" on an order
  with none, and the career map's line for who makes a tool.
- **Tests and pictures:** the piece's furniture test, the crafting area, the menu pictures.
- **Docs:** 44 and 41 for the rule, 62 for the piece, `00_todo.md` (the note that a set bar
  holds the smelter no longer matters for tools).

## Settled with the pick

The owner answered "B" and nothing on the name, the cost or the casting stone's peck marks, so
the defaults I had stated stand; they are decisions 1, 2 and 4 above.
