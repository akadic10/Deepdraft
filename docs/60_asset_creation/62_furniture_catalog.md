# 62 — Furniture catalogue and Stonehearth comparison

All furniture in the game is **Tier 1 · Axe-Hewn** Hearthblock art: split slabs, bark,
chopped stepped ends, notches, rope lashings and loose hay, with no iron. See
[64 — Hearthblock art direction](64_hearthblock_art_direction.md) for the look and the
tier rules, and [63](63_shared_art_standard.md) for the pipeline. The models are
authored in `tools/hearthblock/art/tier1.mjs` and `proposal.mjs`. Wooden pieces
recolour for pine, oak, juniper and apple.

**Tier 2 · Carpenter Era** (a plank dining table and a blanket bed) waits for its
progression step. Its designs are kept in
`tools/art_data/studies/hearthblock_furniture_tiers.json` and as `diningTable()` and `bed()` in
`tools/hearthblock/art/proposal.mjs`. They must never be deleted.

## 1. Furniture in the game

Footprints are width × depth in blocks. Heat values come from each definition's
`heat_source.heat_units` in `data/furniture/`.

| Piece | Key | Footprint | Tier 1 design | What it does |
|---|---|---|---|---|
| Log Stool | `log_chair` | 1×1 | Bark stump with raised bark plates, a square growth ring and a drying split | Seat for resting, dining and games |
| Log bench | `bench` | 2×1 | Half a split log dropped into notches in two short logs | One broad seat for meals and leisure |
| Log Dining Table | `log_table` | 3×3 | Two riven halves on two short logs crossed in a notch | Four separate stools in a 5 × 5 dining layout |
| Board-game Table | `board_game_table` | 3×3 | The same table with a board scratched into the top and six counters | Solo or two-player games for happiness |
| Crude Workbench | `crude_workbench` | 3×3 | One great squared stump with root flare, bark, growth rings, a crack and a chopping notch | Worker crafting from any open side |
| Log bed | `log_bed` | 4×3 | Notched log frame with flat hay under the sleeper | One sleeper; counts toward bedrooms |
| Log door (2, 3 wide) | `door`, `log_door_3` | 2×1, 3×1 | Vertical split slabs with stepped chopped tops, pegged battens, rope lashing and a rope pull | Opens on approach; seals rooms |
| Double log door | `log_door_4` | 4×1 | Two such leaves | Leaves swing apart; seals rooms |
| Log Fence Post | `log_fence` | grid corner | Squared pole with a chopped point and rope bands; split-pole rails | Posts at neighbouring grid corners join with two rails |
| Log Gate | `log_gate` | 2 edges | Chopped stiles, split rails and a stepped brace | Opens on approach; shares posts with fences |
| Rough wooden ladder | `crude_ladder` | 1×1 | Bark poles with chopped tops, lashed stick rungs every 8 cells | Each crafted section installs four blocks of ladder |
| Log bridge | `log_bridge` | 2 wide | Four split logs, riven face up, lashed near each bank | Spans one to five water blocks between level banks |
| Log torch | `wooden_torch` | wall | The proposal's wooden peg torch | Light and 75 heat units; no fuel |
| Campfire | `campfire` | 3×3 area | The proposal's eight-stone campfire | Rudimentary crafting, light and 900 heat units |
| Rudimentary hearth | `hearth` | 2×2 | Squared stones in uneven courses on a hearthstone, a lintel, crossed logs and embers | Small-room heater, 1600 heat units counted once |
| Settlement flag | `settlement_flag` | 1×1 | A rough pole in a stone cairn with a lashed crossbar | Marks the settlement; can be packed and moved |
| Wet stone, dry stone | `wet_stone`, `dry_stone` | 1×1 | Rocks (unchanged) | Supply or absorb water while placed |

Ladder and bridge kits, packed furniture and the materials crate are rope-bound
bundles of poles and split logs, or a crate of split slats on bark corner posts.

### Bed use and heating

Each bed design supports **Assign bed…** in Object explorer, with one assigned bed
per colonist. A tired dwarf tries its assigned bed first, then reachable unassigned
beds, then sheltered ground rest. Each bed admits one sleeper. Assignments save, and
temporary sleeper claims are rebuilt on load.

A sealed room with a door, an installed light and complete bed footprints becomes a
Bedroom (one unassigned bed), a Personal bedroom (one assigned bed) or Barracks
(several beds). A dwarf who sleeps at least three game hours in its own personal
bedroom gets **Slept in my own bedroom**: +10 happiness for 24 game hours. Cold,
chilly and hot sleep can separately cause temperature penalties (doc 122).

`RoomManager` counts each installed heat source once, including multi-cell fires.
Heating adds `total heat units / max(room volume, 128)` °C to the ambient
temperature. Packed items don't heat rooms, and no installed source needs fuel or
ignition yet.

## Retired and planned furniture

[234](../00_dev_roadmap/234_retired_uncraftable_furniture.md) removed fifteen designs
until players can craft them:
- the aging rack, anvil, storage barrel, brazier, brewing vat and smelter;
- the communal dining table, personal dining table, wooden chair and dwarven bed;
- the storage chest, storage shelf, tavern bar, trade counter and wall torch.

When one returns, design it fresh in Hearthblock, in the tier that its progression
step calls for. Planned pieces without a design yet include:
- the rune shelf, stockpile marker, wall display and armor stand (doc 52);
- workshops such as the brewery, beehive and forge (doc 44);
- world objects such as the mining cart and runic standing stone;
- the mushroom lantern, an underground light.

Rugs, pelts and fitted carpets are a separate future category.

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

## 3. Comparison and takeaways

This comparison was written on 2026-07-11. Several Deepdraft pieces it mentions (the
barrel, chest, shelf, trade counter, tavern bar and brazier) were retired in 234 and
will return with player crafting.

### Where Deepdraft matches the SH shape

- **The storage ladder:** barrel 8 → chest 24 → a future vault class. Doc 19 tracks
  SH's crate 8 → 32 → vault 256 deliberately. The container code was deleted on
  2026-10-22 because no furniture used it (doc 258); build it fresh with the barrel
  and chest milestone.
- **Room-anchor furniture:** the trade counter matches SH's market and stall function.
  The tavern bar, armor stand and wall display follow the same "furniture defines the
  room" pattern.
- **Heat-bearing furniture:** torches, the campfire and the hearth feed room temperature
  (doc 34). SH lighting is cosmetic first, so this is a genuine differentiator.

### What SH has that Deepdraft has no analogue for (candidate archetypes, in rough value order)

| SH archetype | Why it would earn its place in Deepdraft | Natural home |
|---|---|---|
| **Firepit / hearth** (built) | SH's social anchor; a hearth is a heat source plus a warm-room thought in one piece | Tavern milestone (doc 51) |
| **Bench** (built) | Cheap mass seating for a hall | Tavern milestone |
| **Tombstone** | Doc 52 already forward-notes burial and an `honored_dead` thought | Combat/burial follow-on |
| **Resource piles** (log/stone piles) | Bulk visual storage for the rough-stone flood doc 18 flagged; reads as industry | Storage follow-on (doc 19+) |
| **Input bins / output boxes** | Already adopted in doc 44's workshop feeding model (doc 18 §2.5) | Workshops (doc 44) |
| **Rugs / banners / wall décor** | Needs a room-appeal system first; cheap assets, no logic | After room detection (doc 34/51) |
| **Dresser** | Only meaningful with per-dwarf belongings; no system planned | Far future |
| **Pet beds** | Domestication and pet furniture are unplanned | Deferred until domestication is approved |

### The variant strategy (the real structural difference)

SH ships ~25 archetypes and multiplies them to 150+ items via **material × quality**.
Deepdraft's multipliers are different:

1. **Furniture tiers** ([64](64_hearthblock_art_direction.md)): Tier 1 · Axe-Hewn now,
   Tier 2 · Carpenter later. Each archetype gets one model per tier, recoloured for the
   four woods.
2. **Quality tiers** tied to crafter experience levels. Doc 41's level curve exists, and
   `fine`/`masterwork` variants would feed trade value (doc 51).
3. **The function split** (material rule, Alen 2026-07-11): **furniture is woodwork**.
   Beds, chairs, benches, tables, shelves and anything else dwarves *use* are wood.
   Stone and iron are for industrial anchors (anvil, trade counter, workshop bodies) and
   monuments (rune shelf, standing stones). Wood is plentiful on the forested map, so
   this is identity, not scarcity.

Recommendation: keep the archetype list tight (SH proves ~25 is enough for a full
game) and defer quality variants until crafting quality exists.

---

*Prev: [61_voxel_art_guide.md](./61_voxel_art_guide.md)*
