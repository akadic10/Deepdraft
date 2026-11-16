# 300 — The boulder smelter

**2026-11-14:** nothing is hammered at the smelter any more. The trades' copper tools are made on
the anvil stone (doc 310); the casting stone keeps the bar's mould and its old peck marks.

**Status:** step 1 built 2026-11-09. Its model was rebuilt in worked stone at 3 × 1 on 2026-11-10
(in the art review's stone pass, doc 301, since retired; see "Rebuilt in worked stone" below).
The owner's first look in play, 2026-11-10: "the new furniture looks good". On 2026-11-12 the
owner looked at the Blacksmith's work at it: "the blacksmith just moves in a weird way when
adding the ingredients", and asked for step 2. Step 2 and a reworked charge were built the same
day (below). The owner's look at it, the same day: "The animation looks better." The six
decisions below were not answered one by one, and the Soil in the recipe is still open.

## What the owner asked

- "The blacksmith animation looks weird and the smelter might be too small. First, the
  blacksmith is hammering on the copper ore, then it smelts." (2026-11-09). The basic smelter
  (doc 297) had one crafting motion, the Blacksmith's maul, so the copper charge was hammered,
  on a casting stone 0.375 blocks high.
- Round 1 of concepts (A tall stone stack, B clay dome, C smelting yard;
  `tmp/smelter_concepts_20261109/world/smelter.png`) was turned down: "I don't like B because
  we don't have clay. I don't like the visuals on any of them … the dwarves have basic tools for
  now, keep it rudimentary".
- Round 2 (`tmp/smelter_concepts_20261109/world/smelter_round2.png`: D stone cairn, E boulder,
  F stone oven), built only from Rough Stones and a log: the owner picked **E, the boulder**
  ("proceed with E"). It keeps the 2 × 1 footprint; the question of a 2 × 2 smelter was left
  open.

## What was built (step 1)

- **Model:** `basicSmelter()` and `basicSmelterCharge()` in `tools/hearthblock/art/tier1.mjs`, from
  concept E (`tmp/smelter_concepts_20261109/concept_art.mjs`). Left cell: one great Rough Stone,
  broad and rounded (`boulder()`), knocked hollow, 19 cells (1.19 blocks): a stone pot stands in
  the hole in its top, a fire hole is knocked in its foot at the front, both smoke-black, with
  lumps and a crack. Right cell: the casting stone, a rough slab on two log rounds (the mason's
  bench in small), its top at 15 cells (0.9375, bench height), with two bar moulds. No clay, daub,
  hide, planks or iron. The charge part shows copper melting in the pot, coals glowing round it
  and in the fire hole, and the bar cast in the front mould, each in a cell the smelter leaves
  empty. Installed through the furniture family (gallery `tmp/smelter_boulder_20261109/gallery/`);
  its menu picture `assets/ui/furniture/basic_smelter.png` was re-rendered. No item picture or
  UI icon replays it.
- **Work spots** (doc 44, "A workshop's work spots"): a workshop may name the footprint cell each
  kind of craft is worked at. The smelter's `batch_cell` is the boulder and its `crafting_cell`
  the casting stone, so the Blacksmith stands beside the boulder to charge it and beside the
  casting stone to hammer fittings or take a bar off. `InstalledFurnitureComponent.work_cells`
  turns the cell with the piece; stands (`nearest_stand_target`, `CraftingManager.bench_target`,
  the trip planners) and the reach (`CraftingManager.bench_surface`) follow it. A workshop that
  names no spot works as before.
- **The charge is tipped in by hand.** `batch_crafting_motion: "hands"` gives a batch the drying
  rack's hand motion (no tool, no knock): both hands reach over the boulder's hole
  (`batch_surface_height` 1.1875, `batch_surface_radius` 0.25) with the ore at the feet. The
  fittings keep the Blacksmith's maul (`craft_motion: "blow"`), now at bench height.
- **Data:** `data/furniture/basic_smelter.json` (heights, collision 1.1875 and 0.9375, the new
  fields, the description), and the smelter's and the copper bar's recipe text in
  `data/recipes/recipes.json` (no clay crucible: a stone pot).
- **Test:** `BasicSmelterTest` now checks that the charge is worked with the hands from beside the
  boulder at its crown, and the fittings with the maul from beside the casting stone at bench
  height. Without the new fields it fails as the owner saw it: motion `hew`, standing at the
  casting stone's far end.

## Rebuilt in worked stone (2026-11-10)

The owner: "proceed with the smelters stone", then of three sizes shown beside a dwarf (2 × 1,
3 × 1 and a 3 × 2 great boulder; `tmp/smelter_stone_20261110/proposal_smelter.png`), "B".
- **The idea is unchanged:** one great stone knocked hollow, a pot in its top, a fire hole in its
  foot, a casting stone on two log rounds beside it.
- **The model** is worked stone (doc 64, "Stone is drawn as wood is"): tiers with square-cut
  corners out of line with each other, a dark skin, a fresh lip round the pot, soot at the fire.
  The boulder is two cells broad and 24 cells high, with a low shoulder toward the casting stone.
  The casting stone is a thick worked slab with one bar mould and peck marks where fittings are
  hammered; two slots read as a toaster.
- **Data:** footprint 3 × 1; `batch_cell` [0, 0] and `crafting_cell` [2, 0];
  `batch_surface_height` 1.5 (the drying rack's hands already reach 1.6); collision 1.5625,
  1.1875 and 0.9375. A smelter already placed grows by one cell on its boulder's side.
- **Test:** `BasicSmelterTest` reads the charge's height from the definition, no longer 1.1875.
- Where step 1 below gives sizes, heights or two moulds, this section replaces them.

## Step 2 and the charge, reworked (2026-11-12)

The owner: "proceed with smelter step 2 and also review the animation for step 1, the blacksmith
just moves in a weird way when adding the ingredients".

**What was wrong in step 1,** seen frame by frame (`tmp/smelter_anim_20261112/sheets/before_*.png`):
- The charge borrowed the drying rack's hand motion. The Blacksmith raised two empty hands to
  the boulder and lowered them, once a second for the whole twelve seconds.
- The ore and the coal lay at its feet throughout and never went in.
- It stood on its cell's centre, so its body and its load cut into the boulder, which stands
  higher than a load is carried.
- The copper bar lay in its mould from the first second of charging, and through the melt.

**What was built** (the rules are in doc 44, "Charging the basic smelter" and "Its batch on show"):
- **Where it stands.** The Blacksmith charges from the floor cell before the fire hole, and
  stops a long step (1.3 blocks) back from it. The charge is set down there, before it.
- **Each lump goes in.** It takes up the lump in hand, then bends for each lump on the ground,
  lifts it, swings and throws it into the pot: two ore and a coal, about 1.6 s each.
- **Then it blows on the fire.** It crouches, a hand on its knee, and blows through a hollow
  stick held from its mouth to the fire hole, three breaths, about 7 s. The stick is
  `tools/blow_stick` in `dwarves.mjs`: a peeled green stick, bark where it is held, its far end
  burnt black.
- **What the smelter shows.** Coals and melting copper once the whole charge is in the pot,
  through the blowing and the melt. When the copper has set the coals go out and the bar shows
  in the mould (`parts/basic_smelter_bar`, split from the charge part), until it is taken off.
- **Given up half way,** the whole charge lies beside the smelter again.
- **The status line** reads "Charging the smelter", then "Blowing on the smelter's fire".
- **Code:** `scripts/components/DwarfSmeltPose.gd` is new. `InstalledFurnitureComponent`
  (`fire_hole`, `fire_stand`, `work_stands`), `WorkerCraftOrder`, `CraftingManager`,
  `CraftIngredientPlanner`, `FurniturePlacementController.show_batch`, `DwarfCarryWork`,
  `DwarfWorkExecution`, `DwarfBodyRig`, `DwarfAssets` and `DwarfInspection` changed.
  `basic_smelter.json` gained `batch_fire_hole` and `batch_done_model`.

**Decisions taken while building, for the owner to confirm:**
1. **The lumps are thrown, not tipped.** Concept E's caption said "tip the charge in at the
   top". The goods are set down in the cell the Blacksmith would have to step into, and the
   order forbids moving them, so stepping in walked its boots through the ore. A throw from
   where it stands also reads better from above.
2. **One hand holds the stick.** With both hands on it the hands hid the stick and it read as
   an arm reaching into the fire.
3. **It stands a long step back,** in effect in the second cell from the boulder. A dwarf's
   head is a block and a half across: any nearer and it cannot bend to the fire hole.
4. **A lump shrinks as it falls into the pot.** An ore lump is twice as broad as the pot's
   mouth.
5. **The bar shows only once the copper has set,** and the coals go out then. This follows the
   heat rule: the smelter warms its room only while it melts.
6. **A cramped smelter still works.** With no free cell before the fire hole it is charged
   from another side and the stick goes to the boulder's foot; with a wall right behind the
   Blacksmith it stoops and holds the stick steep. Both look plainer than the open case.

**Checked:**
- `BasicSmelterTest`: the stand before the fire hole, the lumps thrown before any fire or stick
  shows, the crouch and the stick at the fire, the bar once set, a bare smelter after, and a
  charge given up half way lying there again with every lump drawn. It fails when a given-up
  charge is not drawn again.
- Frame sheets of the real job in the crafting tests' world, from the owner's camera pitch and
  in profile: `tmp/smelter_anim_20261112/sheets/after_*.png`, with a cramped smelter
  (`tight_profile.png`) and a charge paused at a fifth (`stop_profile.png`).
- The owner's own smelter (a copy of the 2026-11-12 colony): the cell before its fire hole,
  (492, 43, 247), is free, and so is the one behind it.

**For the owner's look in play:**
- A copper bar order from start to end at their own camera: the throw, the crouch, the stick.
- The same from behind the Blacksmith, where its body hides the stick.
- The status line's two readings.

## Open points

- The recipe still takes a Soil (for the old daub). The boulder shows none; dropping it from the
  recipe is the owner's call.
- The smelter has its sounds since 2026-11-13 (doc 307; not listened to). The coals do not
  answer the breath (`00_todo.md`, "The Blacksmith left for later").
- Size: answered on 2026-11-10. The owner chose 3 × 1 over 2 × 1 and over a 3 × 2 great boulder.
