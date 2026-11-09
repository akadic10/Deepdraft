# 296 — The finished goods pallet

**Status:** built 2026-11-02, waiting for the owner's look in play.

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
- **Item and recipe:** `base:resources:furniture:finished_goods_pallet` (packed, carry cost 4),
  and Crafters → Carpenter → Storage: two matching logs, 16 s, at the carpenter's bench.
- **Place:** Storage, beside the crate (38 entries).
- **Test:** `FinishedGoodsPalletTest` (areas furniture, crafting, storage): Carpenters make it;
  it keeps packed furniture only; four packed stools go to it one per quarter and stand on the
  deck; placing a stool takes one from it; a save keeps its pieces. Furniture counts in
  `FurnitureArtTest` and `tools/voxel_assets/test_coverage.py` went up by one.

## Left for later

- Planks, dressed stone and metal bars join its `accepts` when they exist, under their own
  storage category. Doc 62's plan of three to a quarter was for those; with packed furniture it
  is one to a quarter. Revisit the capacity then.
- A packed pallet can itself be stored on a pallet (it is packed furniture). Harmless; noted.
