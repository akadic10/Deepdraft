# 62 — Furniture catalogue and Stonehearth comparison

All furniture in the game is **Tier 1 · Axe-Hewn** Hearthblock art: split slabs, bark,
chopped stepped ends, notches, rope lashings and loose hay, with no iron. The fence posts,
rails and gate and the carpenter's bench are peeled, as built logs are (doc 278). See
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
| Stone Stool | `stone_stool` | 1×1 | A Rough Stone knocked square all the way down (doc 293, B), in the Rough Stone's own greys: its top a little uneven with one corner a cell lower, lumps left on its sides | Seats as the log stool does: resting, dining at a table's guides and games at the board. Stonemasons make it at the mason's bench from one Rough Stone; appeal is its design alone |
| Log bench | `bench` | 2×1 | Half a split log dropped into notches in two short logs | One broad seat for meals and leisure |
| Log Dining Table | `log_table` | 3×3 | Two riven halves on two short logs crossed in a notch | Four separate stools in a 5 × 5 dining layout |
| Board-game Table | `board_game_table` | 3×3 | The same table with a board scratched into the top and six counters | Solo or two-player games for happiness |
| Crude Workbench | `crude_workbench` | 3×3 | One great squared stump with root flare, bark, growth rings, a crack and a chopping notch | Worker crafting from any open side |
| Drying Rack | `drying_rack` | 2×1 | Two forked bark posts on root flares with a peeled pole lashed into the forks, bare when idle; while a batch dries, three dried fish (look A, split along the belly) hang head down from cords (`parts/drying_rack_fish`) | The Ranger's workbench: Rangers make it and hang two fresh fish of one kind on it, by hand, from either long side; they dry for a day, then a Ranger takes them down as two dried fish (docs 289, 292) |
| Carpenter's Bench | `carpenter_bench` | 3×1 | The owner's picture, peeled (doc 293, A): a thick slab, half a great log hewn flat on top, on four peeled log legs braced low with round log rails across both ends and a little higher along both sides; knots trimmed flush, end grain at every cut | The Carpenter's workbench, work top at 1.125: Carpenters make it from three matching logs at the crude workbench (doc 293) |
| Tool Rack | `tool_rack` | 3×1, on a wall | Half a split log, its round back to the wall and its split face out, lashed with rope to two wall pegs, with three stout pegs driven in and angled up (doc 294, B); it hangs 2 blocks up over its three floor cells | Holds three tools, one hung upright on each peg, at storage priority 4 (ahead of ground storage). Carpenters make it at the carpenter's bench from one log; it needs a wall behind it as high as it is (3 blocks), and falls with its tools when that wall is mined |
| Raw Materials Crate | `raw_materials_crate` | 2×2 | A log crib (doc 294, A): two courses of notched bark logs crossing at the corners, open on top, inside its footprint | Holds twelve raw goods (Rough Stone, the ores and coal, soil), three to each quarter, at storage priority 4; each filled quarter shows one of its goods over the rim. Carpenters make it at the carpenter's bench from two matching logs |
| Mason's Bench | `mason_bench` | 3×1 | A split stone slab in the Rough Stone's own greys across two bark log stumps set in from the ends, with stone chips at their feet | The Stonemason's workbench, work top at 0.9375: Stonemasons make it from a log and three Rough Stones at the crude workbench; no wood recolours it (doc 293) |
| Log bed | `log_bed` | 4×3 | Notched log frame with flat hay under the sleeper | One sleeper; counts toward bedrooms |
| Log door (2, 3 wide) | `door`, `log_door_3` | 2×1, 3×1 | Vertical split slabs with stepped chopped tops, pegged battens, rope lashing and a rope pull | Opens on approach; seals rooms |
| Double log door | `log_door_4` | 4×1 | Two such leaves | Leaves swing apart; seals rooms |
| Log Fence Post | `log_fence` | 1×1 | Peeled 6 × 6 pole with an earth-dark foot, a knot, a drying check and a flat top showing its rings; peeled split rails, split face up, set into the posts | Posts on neighbouring tiles join with two rails |
| Log Gate | `log_gate` | 3×1 | Peeled stiles with chopped tops, two split rails and one brace laid over the front from the hinge's foot to the latch's head; rope ties at the hinge, a rope loop at the latch, a one-cell gap at the latch | One open tile between two posts; opens on approach; shares posts with fences |
| Rough wooden ladder | `crude_ladder` | 1×1 | Bark poles with chopped tops, lashed stick rungs every 8 cells | Each crafted section installs four blocks of ladder |
| Log torch | `wooden_torch` | wall | The proposal's wooden peg torch | Light and 75 heat units; no fuel |
| Campfire | `campfire` | 3×3 area | The proposal's eight-stone ring with no wood: grey ash, a charred centre, soot on each stone's face toward the fire; the night's log is the real good | Rudimentary crafting; lit at dusk with a log until dawn: light and 900 heat units while it burns (doc 279); dwarves grill fresh fish at it while it burns (doc 290) |
| Rudimentary hearth | `hearth` | 2×2 | Fire-back (the owner's pick of four concepts, doc 279): an open fire on four flagstones, scorched round the ash, against three stacked slabs with soot fading up them, and low wing stones at the back corners; no wood, the night's log is the real good | Room heater for up to about 600 cells; lit at dusk with a log until dawn, or at bedtime by a dwarf sleeping in its room (doc 34), 9600 heat units counted once while it burns, tended so its room never passes 18°C (doc 34) |
| Settlement flag | `settlement_flag` | 1×1 | A rough pole in a stone cairn with a lashed crossbar | Marks the settlement; can be packed and moved |
| Wet stone, dry stone | `wet_stone`, `dry_stone` | 1×1 | Rocks (unchanged) | Supply or absorb water while placed |

Ladder kits, packed furniture and the materials crate are rope-bound
bundles of poles and split logs, or a crate of split slats on bark corner posts.
All packed furniture, the settlement flag included, shares one crate
(`assets/models/furniture/packed_furniture.glb`, the `model` of each packed item in
`resources.json`), one world block in size and carried and stored at that size. Only
ladder kits, the water stones and uprooted plants keep models of their
own when packed. Menus never show the crate: Place, crafting, Inventory, storage and the
compact panel picture a packed piece by its placed form
(`assets/ui/furniture/<key>.png`, from `FurnitureCatalogThumbnails.gd`; doc 116).

### Bed use and heating

Each bed design supports **Assign owner** in the compact panel (a list of the
colonists' portraits, [23](../20_player_interface/23_user_interface.md#object-selection-implemented-2026-10-04)), with one assigned bed
per colonist. A tired dwarf tries its assigned bed first, then reachable unassigned
beds, then sheltered ground rest. Each bed admits one sleeper. Assignments save, and
temporary sleeper claims are rebuilt on load.

A sealed room with a door, an installed light and complete bed footprints becomes a
Bedroom (one unassigned bed), a Personal bedroom (one assigned bed) or Barracks
(several beds). A dwarf who sleeps at least three game hours in its own personal
bedroom gets **Slept in my own bedroom**: +10 happiness for 24 game hours. Cold,
chilly and hot sleep can separately cause temperature penalties (doc 34).

`RoomManager` counts each installed heat source once, including multi-cell fires.
Heating adds `total heat units / max(room volume, 128)` °C to the ambient
temperature. Packed items don't heat rooms. The campfire and the hearth are nightly
fires: a worker lights each at dusk with a log, and it heats only until dawn (doc 34).

### Doors, fences and gates

**Doors** (doc 117). The three log doors are frameless: the leaves fill the opening
and hinge at its outer edges (`door_animation.hinge_inset: 0`). Fixed jambs and lintels
are kept for better doors in later tiers (owner, 2026-10-12).
- A dwarf within `approach_distance` (2.8 blocks) in front of or behind the doorway
  opens the leaves away from its side. The side is chosen only while they are shut, so
  passing traffic can't flip them. They shut `hold_seconds` after the last dwarf has
  gone, and pause freezes them (`FurnitureDoorAnimation`, tuned by each definition's
  `door_animation`; the gate swings the same way).
- The hinges are looks only: navigation, the room seal and door lighting never follow
  the pose, and doors load shut with nothing saved. Doors stay walkable, and each
  footprint column of a door seals rooms at any pose (doc 34).
- **Hit points** (owner, 2026-10-31): the design's `hit_points` times the material's
  `toughness` (`CraftMaterials.hit_points`), the way appeal is design plus material, in the
  one health model dwarves and animals share (doc 41, "Health"). Log doors have 150 in pine
  or applewood, 165 in juniper and 180 in oak, and the gate 100 in pine; iron's toughness
  is 5, for a later iron door of about 750. The Place card shows them on a shield chip
  under appeal ("150–180" across the woods), and an installed door's panel says "Intact ·
  180 hit points". Nothing damages a door yet: invaders will break doors instead of
  opening them, and a broken door will unseal its room (doc 52, "Invader Behaviour").
- **Better doors, planned:** an iron door with the Smelter and Forge (doc 44), and perhaps a
  stone door with the Stonemason, both using the fixed jambs and lintels kept for them.

**Fences and gates** (doc 277; `placement: grid_fence`, `GridFence.gd`, a helper of
`FurniturePlacementController`):
- A Log Fence Post stands in the middle of the tile under the pointer and blocks that
  tile, like a stool; the tiles beside it stay walkable. Its tile takes the
  floor-furniture tile rule (solid floor, three blocks of headroom, no zone, furniture or
  hidden cave), and the worker needs a walkable tile beside it.
- Posts on neighbouring tiles at the same height join with two rails, from tile centre
  to tile centre; diagonal and more distant posts don't. Runs, corners and T or
  four-way junctions share one post. A plan previews its rails, and rails turn solid
  once both of their posts are installed.
- Diagonal posts get no rail, but dwarves never cut corners, so the gap between them is
  closed all the same. So is the gap between neighbouring posts at different heights.
- The Log Gate covers three tiles in a line: an end post, one open tile and another end
  post. The pointer aims at the open tile, and R turns the gate. Its ends reuse posts
  already there (hiding its own) and join neighbouring posts. The leaf hinges at its
  post's face (`door_animation.hinge_inset` 0.1875, doc 278).
- Each fence tile has one role: a post, which a post and gate ends may share, or a gate
  opening, which nothing else may use (so two gates can't cross).
- The opening is one tile wide: dwarves, rabbits and ducks pass, but deer (2 wide) and
  wolves (4 wide) don't fit. Gates have no locks or animal permissions.
- Rails are worked out from the posts' positions; they are neither items nor saved.
  They are rebuilt when plans or pieces change and once after a load, and moving or
  removing a post changes only its own rails. Rails lie inside post tiles, so they are
  looks only.
- An installed post's tile is ordinary occupancy in `PlacedEntityRegistry`: one box per
  post tile, `ceil(grid_fence.height)` blocks high, registered by `GridFence.sync` so a
  shared post counts once. A plan reserves its tiles against furniture, storage zones
  and construction but blocks no route. Neither fences nor gates seal a room.
- A post or gate that loses its floor drops its packed item, and its rails go with it;
  a plan there is cancelled.
- A piece saves its first tile as its origin: the post's tile, or a gate's first end.

## Retired and planned furniture

Doc 234 (2026-10-18) removed fifteen designs until players can craft them (the
settlement flag and the wet and dry stones stayed, though no recipe makes them):
- the aging rack, anvil, storage barrel, brazier, brewing vat and smelter;
- the communal dining table, personal dining table, wooden chair and dwarven bed;
- the storage chest, storage shelf, tavern bar, trade counter and wall torch.

The log bridge and its kit were retired on 2026-10-27: rivers are crossed on logs built
from Build, which make crossings of any width and length (doc 32, "River crossings").

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
   this is identity, not scarcity. One exception (owner, 2026-11-01): the Stonemason's first
   piece is a stone stool, in place of a stone door "for now" (doc 293).

Recommendation: keep the archetype list tight (SH proves ~25 is enough for a full
game) and defer quality variants until crafting quality exists.

---

*Prev: [61_voxel_art_guide.md](./61_voxel_art_guide.md)*
