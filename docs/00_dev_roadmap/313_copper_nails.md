# 313 — Copper nails

**Status (2026-11-16):** built the same day on the owner's ask, and not yet seen in play. All
245 tests and the lint pass, and so do the art pipeline's own 76. The rules now live in doc 44 ("Copper nails", at its top), doc 62 ("Copper nails
are kept 24 to a crate") and doc 64 ("Nailed in words, pegged in the drawing"). This doc stays
until the owner has looked: "accepted" retires it, and "What is left" moves to `00_todo.md`
then.

## What the owner asked

> I want to introduce copper nails that are made from a copper bar. Copper nails should be
> needed for carpenter or other recipes where it makes sense. 1 copper bar perhaps makes 12
> nails. nails should follow the crate approach just like most food.

## What was built

**The good.** `base:item:copper_nail`, "Copper nail". It is kept 24 to a crate, with low, half
and full crates of its own, and is stored as Metal: in ground storage that takes Metal and on
the finished goods pallet, where a crate takes one quarter. A crate of nails is one heavy
carrying load, whatever it holds, as a crate of log torches is.

**The recipe.** Crafters → Blacksmith → Metal → Copper nails: a Blacksmith hammers one copper
bar into twelve nails on the anvil stone, in 12 seconds. A batch lands as one crate and the
next batch joins it, so two bars fill a crate. Each batch is one Blacksmith experience.

**What takes them.** The Carpenter's seven plank pieces, a nail to each plank:

| Piece | Planks | Nails |
|---|---|---|
| Tool rack | 2 | 2 |
| Plank bench | 2 | 2 |
| Raw materials crate | 4 | 4 |
| Finished goods pallet | 4 | 4 |
| Food shelf | 4 | 4 |
| Plank dining table | 4 | 4 |
| Board-game table | 4 (and its rough stone) | 4 |

One bar's nails make three tables, or six benches. A piece takes its nails one by one out of a
crate, on the ground or in storage, and the crate stays where it is with the rest. Its nails
come in a trip of their own, before the planks: a crate's load is all a dwarf carries.

**Words.**
- The seven pieces' descriptions say "nailed" where they said "pegged", and name their nails:
  "Made from four matching planks and four copper nails."
- A fixed ingredient a recipe takes several of is counted in the good's own words: the board
  heads "INGREDIENTS · 4 planks · 4 copper nails" and lists "4 copper nails · 12 available",
  and an order without them reads "Waiting for 4 copper nails".
- The Blacksmith's page, career card, menu tooltip and anvil stone say nails beside tools.

**The crate's look.** A shadowed heap of copper under loose square nails with pale hammered
heads, lying both ways; a half crate crosses two more over the heap and a full one lays one on
top. Drawn in `hearthblock_goods.nails`, installed through `build.py`, with its menu picture.
The review sheet, beside the copper bar and four other crates at the game's camera pitch, is
`tmp/copper_nails_20261116/review.png` (scratch, not in git).

**Tests.** `CopperNailTest` (new, in the crafting area) covers the good, the recipe, the seven
pieces, a bench that waits for its nails and then takes exactly two from a crate of twelve, two
batches joining into one full crate, and a crate carried onto the pallet and used from there.
Eight older tests that make a plank piece now put nails down first.

## What the player will notice

- **Plank furniture waits for nails.** In a colony from before, a queued plank piece reads
  "Waiting for 4 copper nails" until a Blacksmith has made some. Saves from before keep
  loading: no id changed.
- **Storage that takes Metal takes nails** without being told. A store narrowed to copper bars
  alone does not.
- **While a piece is made, each nail waits beside the bench as its own small crate,** as each
  fish does at the drying rack.
- **Counts read in lower case** on the crafting board: "1 rough stone", "4 rough stones".

## Three slips found on the way

- **A later ingredient in a fuller crate stalled its order.** The board-game table takes its
  stone first and its nails second. The step that plans a later trip
  (`CraftIngredientPlanner`) saw only single goods, so nails in a crate holding more than one
  read as unreachable: the order said "Waiting for a reachable route" and waited out a retry
  before it went on. It is older than the nails: a second fish out of reach of the first did
  the same at the drying rack. The step now counts a fuller crate, as the first trip's does.
  `CopperNailTest` makes a game table from a crate of twelve and fails on the old line.
- **"Waiting for 1 copper bars".** An order for a copper tool, with no bar in the colony, named
  one bar in the plural, and the nails' order would have too. It reads "Waiting for 1 copper
  bar" now (`CraftingManager`, checked in `CopperNailTest`).
- **Two boards were a line too tall at 1080p.** The nails' own line under INGREDIENTS pushed
  the pallet's and the food shelf's boards past the window. Their descriptions were not the
  cause (four lines at any length tried), so their purposes were shortened to two lines.
  `CraftingBrowserTest` now says how many lines a board's words and ingredients take when one
  does not fit.

## Decisions of mine

For the owner's look; each is easy to change.

1. **A nail to each plank,** so two or four a piece. The numbers are in `recipes.json`.
2. **Only the seven plank pieces take nails.** A Worker's camp goods, the doors, the ladder
   and the torch are made before any copper. The carpenter's bench, the fence and the gate
   stay logs and take none. No stone piece and no tool takes any.
3. **The Blacksmith makes them on the anvil stone,** under Metal beside the copper bar, in 12
   seconds, and a batch counts as experience.
4. **Nails are Metal.** They share the copper bar's storage category instead of getting one of
   their own.
5. **The descriptions say "nailed".** The tool rack's board is "nailed to a wall"; its three
   pegs are still pegs.
6. **The models were not redrawn.** The plank pieces' knot-dark pegs now stand where the nails
   are. Drawing the nail heads in copper would be seven models and their pictures.
7. **The crate's look,** above.
8. **Rough stone has a plural,** "rough stones", so the hearth's board reads "4 rough stones".
   A stone piece's order now waits for "3 rough stones" where it said "3 stone".
9. **Two purposes were shortened** to fit the board:
   - the pallet: "Holds a packed piece, three copper bars, a crate of nails or four planks in
     each quarter. It is filled before ground storage." It names planks now, which it had left
     out;
   - the food shelf: "Holds six crates of food, three to a deck. It is filled before ground
     storage, and food keeps as it would on the floor."
10. **The recipe stands last on the Blacksmith's list,** so the anvil stone's window still opens
    at the copper pick.
11. **A new colony starts with no nails,** as it starts with no bars.

## What is left

- **Not seen in play.** The crates were drawn and checked on the review sheet only; a dwarf
  carrying one, nails on the pallet's deck and nails beside a bench have not been looked at.
- **One crate for a piece's nails.** An order could set its nails down as one crate holding
  the count, in place of a small crate for each. It needs staged goods to count by quantity
  (`WorkerCraftOrder`), which fish at the drying rack would share.
- **Iron nails.** Doc 44's Forge table still plans an iron nail, six from an ingot, for Build's
  wooden blocks. Whether it replaces the copper nail or stands beside it is for when iron
  arrives.
- **Build takes no nails.** Wooden blocks and walls cost what they did.
