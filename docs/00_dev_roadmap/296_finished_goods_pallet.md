# 296 — The finished goods pallet

**Status:** built 2026-11-02 and in use in the owner's colony (five stand there on 2026-11-12,
holding packed furniture). The owner has not said it is accepted. On 2026-11-12 metal goods
joined it at the owner's word (below); that part is not yet seen in play.

## What the owner asked

- "There was supposed to be a finished goods pallet as well, what happened to that dev item"
  (2026-11-02). It had been held in `00_todo.md` because the goods it was planned for (metal
  bars, dressed stone, planks) need iron tools.
- Of three options (keep waiting, build it empty, build it with today's goods) the owner chose to
  build it with today's goods, and picked **packed furniture**, **one piece to each quarter**.

## What was built

- **Model:** concept A, log skids (the owner's pick of three, 2026-11-02;
  `tmp/storage_concepts_20261102/world/pallet_a_skids.png`), ported from
  `tmp/storage_concepts_20261102/concept_art.mjs` to `finishedGoodsPallet()` in
  `tools/hearthblock/art/tier1.mjs`: split poles, split face up, across two dark log runners,
  lashed at the ends, deck top at 7 cells. The concept's runners ran one cell past each side;
  they now keep inside the 2 × 2 footprint, as the raw materials crate does. Installed through
  the furniture family (gallery `tmp/pallet_gallery/`); its menu picture is
  `assets/ui/furniture/finished_goods_pallet.png`.
- **Furniture:** `data/furniture/finished_goods_pallet.json`. Floor, 2 × 2, four yaws, collision
  up to the deck (0.4375). `storage` accepts `stockpile_furniture`, capacity 4, one to a quarter,
  priority 4; its anchors are the quarters' centres on the deck, so a packed piece stands on it.
  It keeps its wood (`hand_hewn_timber`), appeal as the crate.
- **Item and recipe:** `base:item:finished_goods_pallet` (packed, carry cost 4),
  and Crafters → Carpenter → Storage: two matching logs, 16 s, at the carpenter's bench.
- **Place:** Storage, beside the crate (38 entries).
- **Test:** `FinishedGoodsPalletTest` (areas furniture, crafting, storage): Carpenters make it;
  it keeps packed furniture only; four packed stools go to it one per quarter and stand on the
  deck; placing a stool takes one from it; a save keeps its pieces. Furniture counts in
  `FurnitureArtTest` and `tools/voxel_assets/test_coverage.py` went up by one.

## Metal goods (2026-11-12)

The owner: "the copper bars, a finished good, is not able to be stored on the finished goods
pallet". Its first plan (2026-11-02) had been "a Finished Goods pallets for metal bars, refined
stones, planks, etc..."; copper bars came the same day with the basic smelter and were left to
Metal zones on the ground.
- **What it takes now:** packed furniture, one piece to a quarter, and metal goods
  (`stockpile_metal`: copper bars and fittings), three to a quarter. A quarter keeps one kind
  of good and shows one of them on the deck. Ore, coal and everything else stay off it.
- **How:** `accepts` gained `stockpile_metal`, and `per_slot_of` gives a tag's goods their
  number to a slot (`ContainerStorageComponent._slot_capacity`). Its window counts "Used 3 / 4
  quarters · 5 goods", and its bar says "One packed piece or three metal goods to each of its
  quarters."
- **Pallets already placed** keep the choice of goods their save holds, which is furniture
  only: press **All** in the pallet's storage window, or place a new one. No save is rewritten
  for it (CLAUDE.md, "Saves").
- **Decisions taken, for the owner to confirm:** three to a quarter, as doc 62's first plan
  had it; fittings go on it with the bars, as both are the Metal category; a quarter shows one
  bar however many it holds, as the raw materials crate's quarters do.
- **Test:** `FinishedGoodsPalletTest`: four bars and a fitting on a second pallet (3, 1 and 1),
  ore left off, the count and the bar's words, one good shown to a quarter, and a save.

## Left for later

- Planks and dressed stone join its `accepts` when they exist, under their own storage
  category, with their number to a quarter in `per_slot_of` (`00_todo.md`, "The finished goods
  pallet's later goods").
- A packed pallet can itself be stored on a pallet (it is packed furniture). Harmless; noted.
