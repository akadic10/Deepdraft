# 62 — Furniture Catalogue & Stonehearth Comparison

> Compiled 2026-07-11 (Alen's ask, during doc 19 planning). Deepdraft side gathered from
> doc 61 §5.4–5.6, doc 19, doc 34 (heat sources), doc 51 (tavern/trade), doc 52 (Armory),
> and `data/furniture/`. Stonehearth side enumerated directly from `P:\stonehearth`
> `entities/furniture/` (47 entries), `entities/containers/` (51), `entities/decoration/`
> (60+). Use this when planning furniture milestones or asset batches.

---

## 1. Deepdraft furniture — everything specced or planned today

**Status legend:** `DATA` = JSON def exists · `SPEC` = doc 61 authored spec, no asset ·
`PLAN` = designed in a system doc, no spec · `v1` = in the doc 19 build

### Functional furniture

| Piece | Key | Status | System it serves |
|---|---|---|---|
| Trade Counter | `base:furniture:trade_counter` | DATA + SPEC (61 §5.4) | Shop room anchor, automated trade (doc 51) |
| Barrel | `base:furniture:barrel` | **SHIPPED (doc 19)** | Storage container, capacity 8 (doc 19) |
| Chest / Crate | `base:furniture:storage_crate` → `storage_chest` | **SHIPPED (doc 19)** | Storage container, capacity 24 (doc 19) |
| Storage Shelf | `base:furniture:storage_shelf` | **SHIPPED (doc 19)** — Alen's hand-authored model pending | Contents-rendering storage, capacity 8 (doc 19) |
| Brewing Vat | `base:furniture:brewing_vat` | SPEC (61 §5.4) | Brewery chain (doc 42) |
| Bed (Dwarf Bunk) | `base:furniture:dwarf_bunk` | SPEC (61 §5.4) | Sleep + `slept_in_bed` thought (doc 41 — beds NOT yet implemented; sleep-lite is in-place) |
| Wooden Chair | `base:furniture:wooden_chair` | SPEC (61 §5.4 — respecced wood, 2026-07-11) | Future eating/idle comfort |
| Wooden Table | `base:furniture:wooden_table` | SPEC (61 §5.4 — respecced wood, 2026-07-11) | Future eating/idle comfort |
| Wall Torch | `base:furniture:wall_torch` | SPEC (61 §5.4) | Light + **200 heat units** (doc 34) |
| Brazier | `base:item:brazier` | PLAN (doc 34 — "future item") | **600 heat units**; large-room heating |
| Anvil | `base:furniture:anvil` | SPEC (61 §5.4) | Forge visual anchor (doc 44) |
| Rune Shelf | `base:furniture:rune_shelf` | SPEC (61 §5.4) | Decorative / future room appeal |
| Stockpile Marker | `base:furniture:stockpile_marker` | SPEC (61 §5.4) | Zone decoration only |
| Wall Display | `base:furniture:wall_display` | PLAN (doc 52) | Armory — holds one weapon/shield |
| Armor Stand | `base:furniture:armor_stand` | PLAN (doc 52) | Armory — holds one armour set |
| Tavern Bar | `base:furniture:tavern_bar` | PLAN (doc 51 — "not yet implemented") | Tavern room anchor; traveler income |

### Workshops (placeable, but a separate category — doc 61 §5.5)

Brewery (1×1×2) · Aging Cellar (2×2×2) · Beehive (1×1×1) · Smelter (2×1×2, 800 heat) ·
Forge (1×1×2). These will ride the doc 19 placement pipeline when doc 44 lands.

### Decoratives / world objects (doc 61 §5.6 — world-gen scatter, not player furniture yet)

Stone Boulder · Mining Cart · Water Barrel · Fence Post / Palisade · Runic Standing Stone ·
Mushroom Lantern (the underground torch alternative — `glow_blue` palette).

**Totals: 16 furniture pieces (3 in the doc 19 build, ~10 specced, 4 plan-only),
5 workshops, 6 decoratives.**

---

## 2. Stonehearth's catalogue (enumerated from source, 2026-07-11)

SH reaches its volume by multiplying a small archetype set by **material**
(wood / clay / stone / amberstone / iron / woven / leather) and **quality**
(base / fine / ornate):

| Category | Count | Archetypes behind it |
|---|---|---|
| Beds | 10 | comfy bed, stone/clay beds, "not much of a bed" (starter), 3 pet beds |
| Chairs | 13 | simple/arch-backed/comfy/ornate × materials |
| Tables | 10 | dining table, table-for-one × materials/quality |
| Benches | 6 | bench, stone/ornate/park variants |
| Dressers & desks | 6 | dresser, writing desk × quality |
| Tombstone | 1 | burial |
| **furniture/ total** | **47** | ~15 archetypes |
| General containers | ~20 | barrel, small/large crate (+fine), urns, chests (leather/stone/amberstone), **vault** |
| Input bins/shelves/corners/tables | ~25 | single-filter workshop feeders × materials — **contents rendered** on shelves |
| Market shelves | 3 | trade display |
| Output boxes | 4 | crafter deposit targets |
| Resource piles | 5 | log/stone/clay/wheat piles (bulk storage look) |
| **containers/ total** | **51** | ~8 archetypes |
| Lighting | ~18 | lanterns, wall/floor candles, braziers, torches, lamps × materials |
| Firepits | 4 | **functional** — the evening gathering point |
| Rugs / mats / curtains / banners / tapestries | ~10 | room appeal |
| Statues / shrines / fountains / misc | ~25 | appeal + faction flavour |
| Market stalls | 3 | trade events |
| **decoration/ total** | **60+** | — |

---

## 3. Comparison & takeaways

### Where Deepdraft already matches the SH shape

- **The storage ladder** — barrel 8 → chest 24 → (future vault-class): doc 19 tracks SH's
  crate 8 → 32 → vault 256 deliberately.
- **Contents-rendering shelf** — direct SH parity (ATTITEM anchors, sca 0.5).
- **Room-anchor furniture** — Trade Counter ≙ SH market/stall function; Tavern Bar,
  Armor Stand, Wall Display follow the same "furniture defines the room" pattern SH uses.
- **Heat-bearing furniture** — torch/brazier feed doc 34; SH lighting is cosmetic-first,
  so Deepdraft's temperature hook is a genuine differentiator, not a gap.

### What SH has that Deepdraft has no analogue for (candidate archetypes, in rough value order)

| SH archetype | Why it would earn its place in Deepdraft | Natural home |
|---|---|---|
| **Firepit / hearth** | SH's social anchor. A tavern hearth = heat source (doc 34) + `warm_tavern` thought (doc 41) in one piece — highest synergy per asset | Tavern milestone (doc 51) |
| **Bench** | Cheap mass seating for the tavern hall; dwarven long-bench fits the aesthetic brief perfectly | Tavern milestone |
| **Tombstone** | Doc 52 already forward-notes burial + `honored_dead` thought — the asset is the easy half | Combat/burial follow-on |
| **Resource piles** (log/stone piles) | Bulk visual storage for exactly the rough-stone flood doc 18 flagged; reads as industry | Storage follow-on (doc 19+) |
| **Input bins / output boxes** | Already adopted — doc 44's workshop feeding model (doc 18 §2.5) | Workshops (doc 44) |
| **Rugs / banners / wall décor** | Needs a room-appeal system first; cheap assets, no logic | After room detection (doc 34/51) |
| **Dresser** | Only meaningful with per-dwarf belongings — no system planned | Far future |
| **Pet beds** | No animals in Deepdraft's design | Never (out of vision) |

### The variant strategy (the real structural difference)

SH ships ~25 archetypes and multiplies them to 150+ items via **material × quality**.
Deepdraft's doc 61 aesthetic is deliberately singular (dwarven stone-and-iron), so the
multiplier isn't materials — the natural Deepdraft multipliers are:

1. **Quality tiers** tied to crafter experience levels (doc 41's level curve already
   exists; `fine`/`masterwork` variants would feed trade value, doc 51), and
2. **The function split** (material rule, Alen 2026-07-11): **furniture is woodwork** —
   beds, chairs, benches, tables, shelves, anything dwarves USE — while stone/iron is
   reserved for industrial anchors (anvil, trade counter, workshop bodies) and monuments
   (rune shelf, standing stones). Wood is plentiful (forested map), so this is identity,
   not scarcity. Lighting keeps its own split: wall torch (surface warmth) vs mushroom
   lantern (underground glow).

Recommendation: keep the archetype list tight (SH proves ~25 is enough for a full game)
and defer any variant multiplication until crafting quality exists.

### Asset-batch implication for doc 19+

The doc 19 batch (barrel, chest, shelf + item forms) plus the already-specced doc 61 set
covers Deepdraft's equivalent of SH's starter town. The first post-19 asset batch with
real system pull is **tavern furniture** (bar, bench, hearth) — it activates docs 34, 41,
and 51 simultaneously.

---

*Prev: [61_voxel_art_guide.md](./61_voxel_art_guide.md)*
