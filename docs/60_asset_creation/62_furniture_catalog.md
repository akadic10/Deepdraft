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
| Trade Counter | `base:furniture:trade_counter` | **SHIPPED (2026-10-01, [art doc 37](../00_dev_roadmap/37_trade_counter_asset_and_placement.md))** — 2×1 stone/iron counter, 2 blocks tall; packed item and placement live | Shop room anchor and automated trade remain future work (doc 51) |
| Barrel | `base:furniture:barrel` | **SHIPPED; oak/iron redesign (art doc 32, 2026-10-01)** — 1×1×1 envelope, recessed lid and dark hoops | Storage container, capacity 8 (doc 19) |
| Chest / Crate | `base:furniture:storage_chest` (model: `storage_crate.glb`) | **SHIPPED; oak/iron redesign (art doc 33, 2026-10-01)** — 1×1×1 envelope, strapped lid and front clasp | Storage container, capacity 24 (doc 19) |
| Storage Shelf | `base:furniture:storage_shelf` | **REDESIGNED (2026-10-01, [art doc 41](../00_dev_roadmap/41_storage_shelf_visual_redesign.md))** — open oak/iron frame, 1×1 footprint, 2 blocks tall | Eight visible item slots, fitted to avoid overlap (doc 19; art doc 41) |
| Brewing Vat | `base:furniture:brewing_vat` | **SHIPPED (2026-10-02, [art doc 42](../00_dev_roadmap/42_brewing_vat_asset_and_placement.md))** — 2×2 oak/iron vessel, 2 blocks tall, open rim and copper tap | Placement live; ingredient handling, brewing queues and workshop integration remain future work |
| Dwarven Bed | `base:furniture:dwarf_bunk` | **SHIPPED (2026-10-01, [art doc 40](../00_dev_roadmap/40_bed_asset_and_placement.md))** — independent 4×2 oak/iron bed, 1-block mattress and 2-block headboard | Placement live; bed assignment, walking to bed, sleep animation and `slept_in_bed` thought remain future work (doc 41; sleep-lite remains in-place) |
| Wooden Chair | `base:furniture:wooden_chair` | **REDESIGNED (2026-10-05, [doc 50](../00_dev_roadmap/50_seated_dining_study.md))** — separate 2×2 oak chair, .875 seat and 1.375 low back/arms | Table snapping and seated head clearance live; old saved 1×1 chairs preserved. Sitting/eating AI remains future work |
| Personal Dining Table | `base:furniture:wooden_table` | **REDESIGNED (2026-10-05, [doc 50](../00_dev_roadmap/50_seated_dining_study.md))** — 2×2 oak table, 1.75 tall | Four alternative snap sides with a one-chair total limit, including queued chairs; chairs remain separate build items |
| Communal Dining Table | `base:furniture:communal_table` | **SHIPPED (2026-10-05, [doc 50](../00_dev_roadmap/50_seated_dining_study.md))** — 8×4 oak table, 1.75 tall | Eight optional snapped chairs: three per side and one per end; dining AI remains future work |
| Wall Torch | `base:furniture:wall_torch` | **SHIPPED (2026-10-02, [art doc 43](../00_dev_roadmap/43_wall_torch_asset_and_lighting.md))** — iron/wood mount, 1.5 blocks tall; wall placement with a walkable floor | Warm local light and **200 heat units**, real room-temperature contribution; no fuel consumption yet |
| Brazier | `base:furniture:brazier` | **SHIPPED (2026-10-03, [art doc 47](../00_dev_roadmap/47_brazier_asset_and_heating.md))** — 1×1 iron fire bowl on a stone pedestal, 2 blocks tall with animated flames | Warm local light and **600 heat units**, real room heating; fuel and ignition remain future work |
| Anvil | `base:furniture:anvil` | **SHIPPED (2026-10-02, [art doc 44](../00_dev_roadmap/44_anvil_asset_and_placement.md))** — 2×1 iron anvil on a stone pedestal, 1.5-block working height | Independent placement live; smithing recipes, operator animations and forge integration remain future work |
| Rune Shelf | `base:furniture:rune_shelf` | SPEC (61 §5.4) | Decorative / future room appeal |
| Stockpile Marker | `base:furniture:stockpile_marker` | SPEC (61 §5.4) | Zone decoration only |
| Wall Display | `base:furniture:wall_display` | PLAN (doc 52) | Armory — holds one weapon/shield |
| Armor Stand | `base:furniture:armor_stand` | PLAN (doc 52) | Armory — holds one armour set |
| Tavern Bar | `base:furniture:tavern_bar` | **SHIPPED; oak/iron redesign (doc 31, 2026-10-01)** — 2×1 footprint, 2-block height including taps; room_anchor/room_type remain future integration data | Tavern room anchor (future); traveler income (doc 51, still unbuilt) |
| Bench | `base:furniture:bench` | **SHIPPED; oak/iron redesign (doc 31, 2026-10-01)** — 2×1 footprint, 1-block seat height | Tavern seating; sit-down behaviour depends on doc 41 (not yet implemented) |
| Hearth | `base:furniture:hearth` | **SHIPPED; redesigned 2×2 (doc 30, 2026-10-01)** — 1-block stone rim, 2-block flame height; 400 heat units read once by `RoomManager` | Tavern social anchor; real heat source (doc 34, live); `warm_tavern` thought still depends on doc 41 |
| Door | `base:furniture:door` | **REDESIGNED (2026-10-01, [art doc 34](../00_dev_roadmap/34_door_visual_redesign.md))** — 2×1 framed oak double door, iron straps and ring pulls | Walkable; both tiles seal rooms for `RoomManager` (temperature doc 34) |

### Workshops (placeable, but a separate category — doc 61 §5.5)

Brewery (1×1×2) · Beehive (1×1×1) · Forge (1×1×2):
workshop production remains planned under doc 44.

**Aging Rack / Aging Cellar: visual and placement shipped, 2026-10-03 ([art doc 46](../00_dev_roadmap/46_aging_rack_asset_and_placement.md)).**
2×2 footprint, 2 blocks tall; twin horizontal oak casks, iron hoops, recessed
heads, taps, batch plaque and braced timber cradle. `base:furniture:aging_rack`
uses packed-item/build/uninstall/save handling. Recipes, batch progress,
storage and temperature gating remain future Aging Cellar integration (doc 42).

**Smelter: visual and placement shipped, 2026-10-03 ([art doc 45](../00_dev_roadmap/45_smelter_asset_and_placement.md)).**
2×2 footprint, 3 blocks tall; dressed-stone firebox, iron hood/grate, hollow
chimney and animated firelight. `base:furniture:smelter` uses the existing
packed-item/build/uninstall/save pipeline. Ore processing, fuel, jobs and
800 heat units while operating remain future workshop integration.

### Decoratives / world objects (doc 61 §5.6 — world-gen scatter, not player furniture yet)

Stone Boulder · Mining Cart · Water Barrel · Fence Post / Palisade · Runic Standing Stone ·
Mushroom Lantern (the underground torch alternative — `glow_blue` palette).

**Totals: 20 furniture pieces (15 shipped — 3 from doc 19, 3 from doc 21,
1 from doc 22, 1 each from art docs 37–40, 42–44 and 47; remaining pieces specced or planned),
5 workshops (Smelter and Aging Cellar have placeable visuals; production is pending), 6 decoratives.
The Build menu has 17 entries including the Smelter, Aging Rack and Brazier.**

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
- **Contents-rendering shelf** — ATTITEM-style anchors; maximum scale 0.5, with rotated bounds fitted to each slot (art doc 41).
- **Room-anchor furniture** — Trade Counter ≙ SH market/stall function; Tavern Bar,
  Armor Stand, Wall Display follow the same "furniture defines the room" pattern SH uses.
- **Heat-bearing furniture** — torch/brazier feed doc 34; SH lighting is cosmetic-first,
  so Deepdraft's temperature hook is a genuine differentiator, not a gap.

### What SH has that Deepdraft has no analogue for (candidate archetypes, in rough value order)

| SH archetype | Why it would earn its place in Deepdraft | Natural home |
|---|---|---|
| **Firepit / hearth** — **built, doc 21** | SH's social anchor. A tavern hearth = heat source (doc 34) + `warm_tavern` thought (doc 41) in one piece — highest synergy per asset | Tavern milestone (doc 51) |
| **Bench** — **built, doc 21** | Cheap mass seating for the tavern hall; dwarven long-bench fits the aesthetic brief perfectly | Tavern milestone |
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
real system pull was **tavern furniture** (bar, bench, hearth) — **built 2026-08-03,
see doc 21**. Placing these three pieces today gets working, fetchable, installable
furniture with no attached gameplay yet; they activate docs 34, 41, and 51 the moment
those systems are actually implemented, not before.

---

*Prev: [61_voxel_art_guide.md](./61_voxel_art_guide.md)*
