# 62 — Furniture catalogue and Stonehearth comparison

Furniture is **Tier 1 · Axe-Hewn** Hearthblock art, apart from the Carpenter's plank pieces
(Tier 2, below): split slabs, bark,
chopped stepped ends, notches, rope lashings and loose hay, with no iron. The fence posts,
rails and gate and the carpenter's bench are peeled, as built logs are (doc 278). See
[64 — Hearthblock art direction](64_hearthblock_art_direction.md) for the look and the
tier rules, and [63](63_shared_art_standard.md) for the pipeline. The models are
authored in `tools/hearthblock/art/tier1.mjs`, `tier2.mjs` and `proposal.mjs`. Wooden pieces
recolour for pine, oak, juniper and apple.

**Tier 2 · Carpenter Era** is the plank look of what a Carpenter makes (owner, 2026-11-13,
doc 308). The pieces below change over one by one as each plank look is picked; until then
they are as this table has them. The Plank Dining Table and the Plank bench were the first
(2026-11-13), then the Tool Rack, the Finished Goods Pallet, the Board-game Table, the Raw
Materials Crate and the Food Shelf the same day. The fence and the gate stay logs, and the
carpenter's bench stays hewn (doc 308). Its first designs (a plank dining table and a blanket bed)
are kept in
`tools/art_data/studies/hearthblock_furniture_tiers.json` and as `diningTable()` and `bed()` in
`tools/hearthblock/art/proposal.mjs`. They must never be deleted.

## 1. Furniture in the game

Footprints are width × depth in blocks. Heat values come from each definition's
`heat_source.heat_units` in `data/furniture/`.

| Piece | Key | Footprint | Tier 1 design | What it does |
|---|---|---|---|---|
| Log stool | `log_stool` | 1×1 | Bark stump with its bark in upright ridges, painted flush (doc 301; raised plates read as panels stuck on), a square growth ring and a drying split | Seat for resting, dining and games |
| Stone stool | `stone_stool` | 1×1 | A Rough Stone knocked square all the way down (doc 293, B), built as worked stone (doc 301, A): a dark weathered skin, a fresh seat inside a ledge of skin, one top corner knocked off, a crack from the seat down the back, a chip gone from its foot | Seats as the log stool does: resting, dining at a table's guides and games at the board. Stonemasons make it at the mason's bench from one Rough Stone; appeal is its design alone |
| Plank bench | `bench` | 2×1 | **Tier 2** (doc 308; the owner's pick A of two, 2026-11-13): a seat of two boards pegged onto two notched plank ends, with a stretcher through both ends held by a peg outside each; saw strokes across the boards. Its size and its seat a block up are the log bench's. Its Tier 1 form, the sitting log (the owner's pick of three, 2026-11-11), is kept in `tier1.mjs`, uninstalled | One broad seat for meals and leisure |
| Plank dining table | `dining_table` | 3×3 | **Tier 2** (doc 308; the owner's pick B of two, 2026-11-13): four broad boards laid across two plank ends with gaps between them, each board pegged onto both ends, and a pegged board under each long side tying the ends; every cell stands inside the boxes the log table's stumps, bearers and top had. Its Tier 1 form, the four stumps (doc 301), is kept in `tier1.mjs`, uninstalled | Four separate stools in a 5 × 5 dining layout |
| Board-game table | `board_game_table` | 3×3 | **Tier 2** (doc 308; the owner's pick A of two, 2026-11-13): the plank dining table's own frame and four boards, a board of four squares by four scratched across its two middle boards in knot-dark lines (three of its lines are the gaps between the boards), with six counters. Its Tier 1 form, the log table's stumps and bearers under two riven halves, is kept in `tier1.mjs`, uninstalled | Solo or two-player games for happiness |
| Crude workbench | `crude_workbench` | 3×3 | The stump of a felled tree (doc 301, A, the owner's pick): buttress roots running out over its ground, bark in upright ridges, the felling cut and its splintered hinge along one side, rings off centre, a drying crack | Worker crafting from any open side |
| Drying rack | `drying_rack` | 2×1 | Two forked bark posts on root flares with a peeled pole lashed into the forks, bare when idle; while a batch dries, two dried fish, as many as a batch holds (look A, split along the belly) hang head down from cords (`parts/drying_rack_fish`) | The Ranger's workbench: Rangers make it and hang two fresh fish of one kind on it, by hand, from either long side; they dry for a day, then a Ranger takes them down as two dried fish (docs 289, 292) |
| Carpenter's bench | `carpenter_bench` | 3×1 | The chopping block (doc 301, B, the owner's pick): a thick slab, half a great log hewn flat on top and peeled, one end let into a stump with its bark on, level with the slab and scarred by the axe, the other on two peeled legs with a rail and one stretcher back to the block; chips at its feet. It replaced the bench on four legs after the owner's picture of a log workbench (`tmp/mason_carpenter_concepts_20261101/reference_workbench.webp`, doc 293, A) | The Carpenter's workbench, work top at 1.125: Carpenters make it from three matching logs at the crude workbench (doc 293) |
| Tool rack | `tool_rack` | 3×1, on a wall | **Tier 2** (doc 308; the owner's pick A of two, 2026-11-13): the peg rail, one broad sawn board flat on the wall, pegged to it, with three knot-dark pegs under the hooks. Its Tier 1 form, half a split log pegged to the wall bark side out (doc 294, B; the owner's pick of three ways to draw it, 2026-11-11), is kept in `tier1.mjs`, uninstalled | Holds three tools, one hung upright on each peg, at storage priority 4 (ahead of ground storage). Carpenters make it at the carpenter's bench from two matching planks; it needs a wall behind it as high as it is (3 blocks), and falls with its tools when that wall is mined |
| Raw materials crate | `raw_materials_crate` | 2×2 | **Tier 2** (doc 308; the owner's pick of 2026-11-13, the open bin, after asking for nothing through its middle): a sawn post at each corner, two boards a side with a gap between them, pegged through the posts, open on top and with no floor; its sides 12 cells high, its posts 13, inside its footprint. Its Tier 1 form, the log crib (doc 294, A; doc 301, A), is kept in `tier1.mjs`, uninstalled | Holds twelve raw goods (Rough Stone, the ores and coal, soil), three to each quarter, at storage priority 4; each filled quarter shows one of its goods inside the bin. Carpenters make it at the carpenter's bench from four matching planks |
| Finished goods pallet | `finished_goods_pallet` | 2×2 | **Tier 2** (doc 308; the owner's pick A of two, 2026-11-13): the plain pallet, four sawn deck boards across three runners with two-cell gaps between the boards, every board pegged to every runner; the gaps keep the deck readable under pale goods. Its Tier 1 form, four split halves across two log runners (the owner's picks of 2026-11-02 and 2026-11-11), is kept in `tier1.mjs`, uninstalled | Holds the colony's finished goods at storage priority 4: one piece of packed furniture to a quarter, three metal goods (copper bars, since 2026-11-12) or four planks (since 2026-11-13). A filled quarter shows one of its goods on the deck. Carpenters make it at the carpenter's bench from four matching planks (doc 296) |
| Food shelf | `food_shelf` | 3×1 | **Tier 2** (doc 308; the owner's pick A of two, 2026-11-13): two shelves between two plank ends; each end is one board on edge with a notch sawn out of its foot and its front corner sawn out above the upper shelf; the lower shelf is two boards and the upper one board, six cells shallower, each pegged through the ends. Its Tier 1 form, the lean-to rack (the owner's picks of 2026-11-06 and 2026-11-11), is kept in `tier1.mjs`, uninstalled | Holds six crates of food, three to a deck, at storage priority 4; food keeps there as on the floor beside it. Carpenters make it at the carpenter's bench from four matching planks (doc 299) |
| Mason's bench | `mason_bench` | 3×1 | A slab split from a bigger stone, eight cells thick, across two short stout bark stumps (doc 293, B), built as worked stone (doc 301, A): a fresh cleft top inside a ledge of weathered skin, its two ends out of line, one end left unworked, one corner broken away, a crack in from the front, peck marks, spalls at one foot | The Stonemason's workbench, work top at 0.9375: Stonemasons make it from a log and three Rough Stones at the crude workbench; no wood recolours it (doc 293) |
| Basic smelter | `basic_smelter` | 3×1 | One great stone, two cells broad and 24 cells high, with a low shoulder and a lump at its front, knocked hollow with the maul: a stone pot stands in the hole in its crown, its lip fresh stone, and a fire hole is knocked in its foot, both smoke-black. Beside it the casting stone, a thick slab on two log rounds with their root flares, one bar mould in its top and peck marks from the days when tools were hammered beside it. Built as worked stone (doc 301, B). While copper melts, it shows in the pot with glowing coals round it and in the fire hole (`parts/basic_smelter_charge`); once it has set, the bar shows in the mould instead (`parts/basic_smelter_bar`). The owner's pick E of round 2 (doc 300): rudimentary, no clay | The Blacksmith's workbench: the charge is thrown into the boulder's pot at 1.5 and blown on at the fire hole, from the cell before it; the cast bar is taken off the casting stone at 0.9375 (doc 44, "A workshop's work spots"), and nothing is hammered there since the anvil stone (doc 310). Blacksmiths make it from a log, four Rough Stones and a Soil at the crude workbench; two copper ore and a coal melt in it into one copper bar, and it heats its room only while it melts (docs 297, 300) |
| Anvil stone | `anvil_stone` | 2×1 | One great stone, two cells broad, with its top split off level and nothing else done to it; no wood (doc 310, the owner's pick B of three ideas, 2026-11-14). A broad foot, a lump against its right flank, and the upper stone set back from the front and hanging over the back, in worked stone. The hammering face is fresh stone inside a ledge of weathered skin, over the left cell and half the right, stopping where the split ran out a cell lower; it is pitted where the maul falls, with copper beaten into it; a corner broken away, a crack in from the back, spalls and a scrap of copper on the foot's ledge | The Blacksmith's anvil, its face at 0.9375, the casting stone's height: the four copper tools are hammered on it, a bar and a log each, at the middle of its left cell (doc 44, "The anvil stone"). Blacksmiths make it from three Rough Stones at the crude workbench. It serves until iron brings a forged anvil |
| Log bed | `log_bed` | 4×3 | Notched log frame with flat hay under the sleeper | One sleeper; counts toward bedrooms |
| Log door (2, 3 wide) | `door`, `door_3` | 2×1, 3×1 | Vertical split slabs with stepped chopped tops, pegged battens, rope lashing and a rope pull | Opens on approach; seals rooms |
| Double log door | `door_4` | 4×1 | Two such leaves | Leaves swing apart; seals rooms |
| Log fence post | `log_fence` | 1×1 | Peeled 6 × 6 pole, drawn bolder since 2026-11-11 (the owner's pick of three): its top chopped in two steps, its foot dark three cells up, a knot three cells across and a drying check that runs out of the top; two peeled split rails, split face up with the heart line showing, lashed to the posts with rope | Posts on neighbouring tiles join with two rails |
| Log gate | `log_gate` | 3×1 | Peeled stiles with chopped tops, two split rails and one brace laid over the front from the hinge's foot to the latch's head; rope ties at the hinge, a rope loop at the latch, a one-cell gap at the latch | One open tile between two posts; opens on approach; shares posts with fences |
| Ladder section | `crude_ladder` | 1×1 | Bark poles with chopped tops, lashed stick rungs every 8 cells | Each crafted section installs four blocks of ladder |
| Log torch | `torch` | wall | The proposal's wooden peg torch | Light and 75 heat units; no fuel. Kept 24 to a crate ("Log torches are kept 24 to a crate", below) |
| Campfire | `campfire` | 3×3 area | Five great stones in worked stone (the owner's pick of three, 2026-11-11), out of line with each other, one knocked flat on top, with no wood: the ground burnt black out to the stones, grey ash in the middle of it, a charred heart, soot on each stone's face toward the fire; the night's log is the real good | Rudimentary crafting; lit at dusk with a log until dawn: light and 900 heat units while it burns (doc 279); dwarves grill fresh fish at it while it burns (doc 290) |
| Rudimentary hearth | `hearth` | 2×2 | Fire-back (the owner's pick of four concepts, doc 279), since 2026-11-11 a split boulder in worked stone (the owner's pick of three): one boulder with a great lump against its left flank, its front split away flat for the fire to burn against, smoke-black behind the flame; the piece that came away lies before it as the hearthstone, scorched round the ash; no wood, the night's log is the real good | Room heater for up to about 600 cells; lit at dusk with a log until dawn, or at bedtime by a dwarf sleeping in its room (doc 34), 9600 heat units counted once while it burns, tended so its room never passes 18°C (doc 34) |
| Settlement flag | `settlement_flag` | 1×1 | A rough pole in a stone cairn with a lashed crossbar | Marks the settlement; can be packed and moved |
| Wet stone, dry stone | `wet_stone`, `dry_stone` | 1×1 | Rocks (unchanged) | Supply or absorb water while placed |

Ladder kits, packed furniture and the materials crate are rope-bound
bundles of poles and split logs, or a crate of split slats on bark corner posts.
All packed furniture, the settlement flag included, shares one crate
(`assets/models/furniture/packed_furniture.glb`, the `model` of each packed item in
`items.json`), one world block in size and carried and stored at that size. Only
ladder kits, the water stones and uprooted plants keep models of their
own when packed. Menus never show the crate: Place, crafting, Inventory, storage and the
compact panel picture a packed piece by its placed form
(`assets/ui/furniture/<key>.png`, from `FurnitureCatalogThumbnails.gd`; doc 116).

**Log torches are kept 24 to a crate** (owner, 2026-11-15: "The torch in our game takes too
much space up as a furniture shipping container, can we make the torch behave similar to fruit
where 24 of them fit in a crate?"). The torch is the one piece of furniture stored as produce is:
- **Its item** (`base:item:torch`, named "Log torch") has `crate_capacity`
  24 and low, half and full crates of its own (`assets/models/items/crates/torch_*.glb`,
  `hearthblock_goods.torches`): unlit torches lying head to tail, three abreast, each a stick, a
  fibre binding and a charred tip. A half crate shows a second layer and a full one two more on top.
- **A crate is one of everything**: one stockpile cell, one quarter of the finished goods pallet
  and one carrying load (4 points, heavy), whatever it holds. A bench's batch of four lands as one
  crate and later batches join it while it lies there unclaimed.
- **A crate holds one wood.** Its sticks are the tool hafts' wood (`material_palette`
  `starter_tool`), so pine torches show pine; torches of another wood keep a crate of their own.
- **A plan takes one torch** out of a crate, loose or stored (doc 31, "A plan claims one unit").
  A torch taken down joins a free crate of its wood on the cell it lands on, else starts one.
- Menus still picture the hung torch. `TorchCrateTest` covers the rules, `ItemArtTest` the crates.

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
- **Tiles, not corners.** Fences first stood on grid corners, between voxels (doc 201). On
  2026-10-27 the owner called that a mistake and chose posts centred on tiles, with a gate of
  one open tile between two posts.
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

**The finished goods pallet** is built (doc 296, in the table above). The owner chose to build
it with today's finished goods, packed furniture, one to each quarter (2026-11-02). Metal goods
joined it on 2026-11-12, three to a quarter as its first plan had them (the owner: "the copper
bars, a finished good, is not able to be stored on the finished goods pallet"). Planks joined
it on 2026-11-13, four to a quarter (doc 308). Dressed stone joins it when it exists
(`00_todo.md`, "The finished goods pallet's later goods").

**The food shelf** is built (doc 299, in the table above), from three concepts of 2026-11-06: A the lean-to
rack, B two half logs on wall pegs, C log rounds with half logs across. **A piece with decks sets the upper
one back.** From the owner's camera (64° down in their save, zoom 30) a deck straight above another hid
every crate on it in the first round. The lean makes the upper deck 10 cells deep against the lower's 16,
so both rows show from the front. It fills the upper deck first, the one the camera sees from every side.
From behind, the upper row hides the lower, so the player turns it to face the room with R when placing it.

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
  SH's crate 8 → 32 → vault 256 deliberately. The container code, deleted on
  2026-10-22 (doc 258), came back with the tool rack and the raw materials crate
  (`ContainerStorageComponent`, doc 294); barrels and chests build on it.
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
