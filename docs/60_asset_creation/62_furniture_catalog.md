# 62 — Furniture Catalogue & Stonehearth Comparison

**Current furniture direction (2026-10-18): 1:16 chibi voxel art.** Furniture
uses sixteen native cells per world-block edge, with chunky timber/stone forms,
readable joinery and a few large signs of wear. Follow
[64 — Art direction and original concept](64_hand_hewn_art_direction.md) and
[63 — Technical standard](63_shared_art_standard.md). The current timber family
is recorded in [244](../00_dev_roadmap/244_chibi_timber_refinement.md); beds, doors,
fences, gates, bridges and fires are recorded in
[245](../00_dev_roadmap/245_chibi_buildable_furniture.md). Retain approved footprints,
contacts, wood variants and shadow proxies. Dated entries below describe earlier
revisions; their triangle counts and old generators are historical. The unavailable
designs removed in [234](../00_dev_roadmap/234_retired_uncraftable_furniture.md)
remain retired.

**Grid-corner fences (2026-10-17):** [201](../00_dev_roadmap/201_grid_corner_fences.md)
replaces the rudimentary fence panel with one rough post (128 triangles).
Separate two-rail spans (256 triangles) connect neighboring voxel corners at
consistent heights, with no doubled posts at joins. The 896-triangle gate spans
two grid edges and shares end posts. Posts are 1.3 voxels high; rails at 0.45/1.0
voxels match the lower gate. Models and actual-model thumbnails come from the
existing rudimentary furniture generator and thumbnail tool. The same
wood palettes apply; no whole floor cells are reserved by fences.

**Log game (2026-10-16):** [200 — Game on a log](../00_dev_roadmap/200_game_on_a_log.md)
gives the rudimentary Board-game Table a 3×3 game area and a squat bark-covered
log with end grain, uneven cut edges, a charcoal grid and loose stone counters.
Two separate log stools snap directly outside opposite sides. The playing
surface is 0.78 blocks high; dwarf hand reaches follow it. The actual-model
thumbnail and placement description match. Author with
`tools/generate_rudimentary_furniture.py`; the two-player happiness rules and
2-timber/1-stone recipe are unchanged.

**Complete catalogue converted (2026-10-13):**
[154 — Family conversion](../00_dev_roadmap/154_complete_family_conversion.md)
integrates 41 faceted GLBs covering all 30 furniture/water-stone definitions,
the legacy chair, ladder heights 1–4, bridge spans 1–5 and three packed forms.
The approved stool, hay bed and two-wide door are byte-identical to
[152](../00_dev_roadmap/152_furniture_art_pilot.md). Footprints, collision, seats,
sleeping surfaces, hinges, recipes, heat and saves are unchanged. Existing flame
meshes and flipbook libraries remain. Campfire wood now uses the once-linear
`oak_log` source palette; selectable material identity is preserved. Catalogue
and water-stone inventory thumbnails match the new models.
Author with `tools/generate_furniture_faceted.py`, `data/art/furniture_catalog.json`,
the pilot profile and CraftMaterials palettes, under [63](63_shared_art_standard.md).
The old voxel construction descriptions below are historical; retain their
gameplay bounds and tier roles. `tools/furniture_art/RunReview.ps1` records the
complete production review from opposing angles, including sitting/sleeping/hinge poses.
[156 — Cleanup](../00_dev_roadmap/156_legacy_art_cleanup.md) removes old exports
and duplicate pilots. Retained flame source data lives in `data/art/furniture_flames.json`;
static furniture and flame-animation GLBs retain their exact approved bytes.

**Dining (2026-10-12, 131 stage 2):** wooden chairs, log stools and log benches
now support meals as well as leisure. A log bench supplies one broad dwarf seat
with authored access/headroom. Diners prefer a correctly facing nearby tabletop;
the personal and communal dining tables retain separately built seating.

> Compiled 2026-07-11 (Alen's ask, during doc 19 planning). Deepdraft side gathered from
> doc 61 §5.4–5.6, doc 19, doc 34 (heat sources), doc 51 (tavern/trade), doc 52 (Armory),
> and `data/furniture/`. Stonehearth side enumerated directly from `P:\stonehearth`
> `entities/furniture/` (47 entries), `entities/containers/` (51), `entities/decoration/`
> (60+). Use this when planning furniture milestones or asset batches.

**Bed behavior and heating checked 2026-10-12:** current behavior follows
[120 — Beds and bedrooms](../00_dev_roadmap/120_log_beds_and_bedrooms.md),
[121 — Personal bedrooms](../00_dev_roadmap/121_personal_bedrooms.md) and
[122 — Bedroom comfort](../00_dev_roadmap/122_bedroom_comfort_and_mining_progression.md).
Installed heat values come from each definition's `heat_source.heat_units` in
`data/furniture/`; the Stonehearth comparison below retains its original date.

**Floor categories, 2026-10-12:** simple plank and stone permanent floors now have
full-block voxel art and DEV Build previews. **Rugs, pelts and fitted carpets**
form a separate future category; room-wide fitted carpet is not part of the
wood/stone-floor milestone. Floors fill an excavated support layer. Normal
construction awaits Carpenter/Stonemason; production recipes/costs remain undecided.
Other wall types are deferred, and wall finishes are excluded. See
[128 — Permanent floor preview](../00_dev_roadmap/128_permanent_floor_preview.md).

---

## 1. Deepdraft furniture — everything specced or planned today

**Status legend:** `DATA` = JSON def exists · `SPEC` = doc 61 authored spec, no asset ·
`PLAN` = designed in a system doc, no spec · `v1` = in the doc 19 build

### Functional furniture

| Piece | Key | Status | System it serves |
|---|---|---|---|
| Campfire | `base:furniture:campfire` | **SHIPPED (2026-10-09, [100](../00_dev_roadmap/100_profession_crafting_camp.md))** — roughly 2×2 stone ring centered in a 3×3 placement area, eight flame frames | Rudimentary crafting, warm local light, 900 heat units; no fuel upkeep |
| Log Stool | `base:furniture:log_chair` | **SHIPPED (2026-10-09, [100](../00_dev_roadmap/100_profession_crafting_camp.md))** — 1×1 bark stump with a flat cut top, 0.75 blocks high | Rudimentary crafting, placement and interruptible idle sitting |
| Trade Counter | `base:furniture:trade_counter` | **SHIPPED (2026-10-01, [art doc 37](../00_dev_roadmap/37_trade_counter_asset_and_placement.md))** — 2×1 stone/iron counter, 2 blocks tall; packed item and placement live | Shop room anchor and automated trade remain future work (doc 51) |
| Barrel | `base:furniture:barrel` | **SHIPPED; oak/iron redesign (art doc 32, 2026-10-01)** — 1×1×1 envelope, recessed lid and dark hoops | Storage container, capacity 8 (doc 19) |
| Chest / Crate | `base:furniture:storage_chest` (model: `storage_crate.glb`) | **SHIPPED; oak/iron redesign (art doc 33, 2026-10-01)** — 1×1×1 envelope, strapped lid and front clasp | Storage container, capacity 24 (doc 19) |
| Storage Shelf | `base:furniture:storage_shelf` | **REDESIGNED (2026-10-01, [art doc 41](../00_dev_roadmap/41_storage_shelf_visual_redesign.md))** — open oak/iron frame, 1×1 footprint, 2 blocks tall | Eight visible item slots, fitted to avoid overlap (doc 19; art doc 41) |
| Brewing Vat | `base:furniture:brewing_vat` | **SHIPPED (2026-10-02, [art doc 42](../00_dev_roadmap/42_brewing_vat_asset_and_placement.md))** — 2×2 oak/iron vessel, 2 blocks tall, open rim and copper tap | Placement live; ingredient handling, brewing queues and workshop integration remain future work |
| Dwarven Bed | `base:furniture:dwarf_bunk` | **SHIPPED (2026-10-01, [art doc 40](../00_dev_roadmap/40_bed_asset_and_placement.md))** — independent 4×2 oak/iron bed, 1-block mattress and 2-block headboard | Reachable, exclusive bed sleep with lying/waking animation; persistent assignments, bedroom classification and sleep comfort thoughts live (docs 120–122; details below) |
| Log bed | `base:furniture:log_bed` | **SHIPPED (2026-10-11, [120](../00_dev_roadmap/120_log_beds_and_bedrooms.md))** — 4×3 rough-log frame, loose hay and leaves, 0.75-block sleep surface | Four matching logs at a crude workbench; retains wood material and uses the same bed assignment, sleep and bedroom systems |
| Wooden Chair | `base:furniture:wooden_chair` | **REDESIGNED (2026-10-05, [doc 50](../00_dev_roadmap/50_seated_dining_study.md))** — separate 2×2 oak chair, .875 seat and 1.375 low back/arms | Table snapping and seated head clearance live; old saved 1×1 chairs preserved. Sitting/eating AI remains future work |
| Personal Dining Table | `base:furniture:wooden_table` | **REDESIGNED (2026-10-05, [doc 50](../00_dev_roadmap/50_seated_dining_study.md))** — 2×2 oak table, 1.75 tall | Four alternative snap sides with a one-chair total limit, including queued chairs; chairs remain separate build items |
| Communal Dining Table | `base:furniture:communal_table` | **SHIPPED (2026-10-05, [doc 50](../00_dev_roadmap/50_seated_dining_study.md))** — 8×4 oak table, 1.75 tall | Eight optional snapped chairs: three per side and one per end; dining AI remains future work |
| Log torch | `base:furniture:wooden_torch` | **SHIPPED; log redesign (2026-10-11, [117](../00_dev_roadmap/117_log_furniture_and_fire_audio.md))** — charred branch on a wooden peg; player-selected wall height, five-block worker reach ([129](../00_dev_roadmap/129_wall_mount_heights.md)) | Worker-crafted light and **75 heat units**; always lit when installed, no fuel upkeep |
| Wall Torch | `base:furniture:wall_torch` | **SHIPPED (2026-10-02, [art doc 43](../00_dev_roadmap/43_wall_torch_asset_and_lighting.md))** — iron/wood mount, 1.5 blocks tall; same selectable heights/reach as the log torch | Warm local light and **100 heat units**, real room-temperature contribution; no fuel consumption yet |
| Brazier | `base:furniture:brazier` | **SHIPPED (2026-10-03, [art doc 47](../00_dev_roadmap/47_brazier_asset_and_heating.md))** — 1×1 iron fire bowl on a stone pedestal, 2 blocks tall with animated flames | Warm local light and **3200 heat units**, real room heating; no starter recipe; fuel and ignition remain future work |
| Anvil | `base:furniture:anvil` | **SHIPPED (2026-10-02, [art doc 44](../00_dev_roadmap/44_anvil_asset_and_placement.md))** — 2×1 iron anvil on a stone pedestal, 1.5-block working height | Independent placement live; smithing recipes, operator animations and forge integration remain future work |
| Rune Shelf | `base:furniture:rune_shelf` | SPEC (61 §5.4) | Decorative / future room appeal |
| Stockpile Marker | `base:furniture:stockpile_marker` | SPEC (61 §5.4) | Zone decoration only |
| Wall Display | `base:furniture:wall_display` | PLAN (doc 52) | Armory — holds one weapon/shield |
| Armor Stand | `base:furniture:armor_stand` | PLAN (doc 52) | Armory — holds one armour set |
| Tavern Bar | `base:furniture:tavern_bar` | **SHIPPED; oak/iron redesign (doc 31, 2026-10-01)** — 2×1 footprint, 2-block height including taps; room_anchor/room_type remain future integration data | Tavern room anchor (future); traveler income (doc 51, still unbuilt) |
| Bench | `base:furniture:bench` | **SHIPPED; oak/iron redesign (doc 31, 2026-10-01)** — 2×1 footprint, 1-block seat height | Tavern seating; sit-down behaviour depends on doc 41 (not yet implemented) |
| Rudimentary hearth | `base:furniture:hearth` | **SHIPPED; [room heater redesign](../00_dev_roadmap/199_campfire_and_room_hearth.md), 2026-10-16** — 2×2 open-front stone firebox, 1.68-block back, low flames and glowing coals; 1600 heat units counted once | Small-room heater with live room/temperature feedback; two logs + four rough stones at crude workbench |
| Log door (2 wide) | `base:furniture:door` | **SHIPPED; frameless revision 2026-10-12 ([doc 117](../00_dev_roadmap/117_log_furniture_and_fire_audio.md))** — 2×1; one rough log leaf, wooden battens/pegs/pull, uneven 30–31-voxel top | Opens on approach; walkable; both columns seal rooms |
| Log door (3 wide) | `base:furniture:log_door_3` | **SHIPPED; frameless** — 3×1; one rough log leaf with wooden fittings | Opens on approach; walkable; all three columns seal rooms |
| Double log door (4 wide) | `base:furniture:log_door_4` | **SHIPPED; frameless** — 4×1; two rough log leaves with wooden fittings | Leaves swing apart on approach; walkable; all four columns seal rooms |

Starter log doors have no fixed jambs or top beams. Frames are reserved for better
door tiers later. Existing doors and their placed-form icons share the new art;
each still costs one selected log at the crude workbench (12/18/24 seconds).

### Bed use and heating (live, 2026-10-12)

Both bed designs support **Assign bed…** in Object explorer, with one assigned
bed per colonist. Tired dwarves try their assigned bed first, then reachable
unassigned beds, then sheltered ground rest. Each bed admits one sleeper; other
colonists cannot use an assigned bed. Assignments save, while temporary sleeper
claims are rebuilt on load.

A sealed room with a door, installed light and complete bed footprints becomes
a Bedroom (one unassigned bed), Personal bedroom (one assigned bed), or Barracks
(multiple beds). Completing rest with at least three game hours asleep in one's
personal bedroom grants **Slept in my own bedroom**, +10 happiness for 24 game
hours. Unassigned beds and barracks do not grant this bonus. Cold, chilly and hot
sleep can separately produce temperature penalties (doc 122).

`RoomManager` counts each installed heat source once, including multi-cell fires.
The heating contribution is `total heat units / max(room volume, 128)` °C, added
to ambient temperature. Packed items do not heat rooms. These five installed
sources require no fuel or ignition; planned workshop heating below is separate.

### Workshops (placeable, but a separate category — doc 61 §5.5)

**Crude Workbench (2026-10-07):** playable Worker crafting, now represented by
a rough 1×1 chopping stump usable from all four sides. Workers make it without
a workshop and use it to craft wooden torches. See
[doc 64](../00_dev_roadmap/64_worker_crafting.md).

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

The earlier snapshot counted 20 furniture pieces (15 shipped), 5 workshops,
6 decoratives and 17 Build entries. Those historical counts predate the starter
furniture additions and are not current catalogue or Place-menu totals.

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
| **Pet beds** | Wild rabbits/deer/wolves added in milestones 90–93; domestication and pet furniture remain unplanned | Deferred until domestication is approved |

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
see doc 21**. All three use the fetch/install/uninstall pipeline. The hearth now
provides live room heating and a starter crafting recipe (doc 122); tavern room
integration, traveler income and the proposed `warm_tavern` thought remain future
work under doc 51.

---

*Prev: [61_voxel_art_guide.md](./61_voxel_art_guide.md)*
