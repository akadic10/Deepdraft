# 44 — Crafting Workshops

**Drying rack (2026-10-31, doc 289):** Crafters → Ranger → Workshops offers a Drying Rack
for two matching logs and 12 seconds at a crude workbench: a 2×1 Tier 1 piece installed
through Place → Food. It is the Ranger's own workbench, so Rangers make it (owner,
2026-11-01: "the drying rack should move under the rangers menu as a workbench, the ranger
may have more workbenches later such as drying leather"); with no Ranger its order waits as
"Needs a Ranger". Place still files it with food (owner, 2026-10-31: "the drying rack is not
a workshop"). To the code it is the bench of its one recipe (`workshop` in the recipe, a
bench claim while drying). Crafters → Ranger → Food → Dried fish (doc 292; Rudimentary until
then) takes two fresh fish of one kind (perch, trout, char or cave fish) to an installed rack.
Hanging them takes 12 seconds, and then they dry there by themselves (owner, 2026-11-01: "the
fish dried instantly, I don't think we want it to work that way"):
- **A day on the rack.** The recipe's `dry_hours` (24) pass on the world clock while the
  batch hangs, on show (the rack's `batch_model`). The order's batch counts as done once hung,
  so an order moves on to another free rack. A rack holds one batch: an order whose every rack
  is drying says "Waiting for a free drying rack · about 14 hours".
- **Taken down.** Once dry, the rack posts a COLLECT lease (`WorkshopBatch`, a surface work
  source like a fishing spot). A Ranger takes the batch down by hand in `collect_seconds` (4);
  two dried fish land beside the rack, the Ranger's log counts them, and the rack is free.
  With no Ranger, the dry fish wait on the rack.
- **Fish on a rack** don't spoil and count toward a Keep target (`CraftingManager.batch_output`).
  The rack's window shows a Drying row ("2 trout · about 14 hours left"), and the crafting
  window lists each batch under the queue (DRYING).
- **Saves** keep each batch: its rack, fish and the hour it was hung. A rack removed or marked
  for uninstall before its batch comes down drops the fish beside it, dried if they were.

Dried fish keep 30 days at 20°C (doc 42, "Spoilage") and are never an ingredient again. Only Rangers dry fish: a recipe's `section` names the page
it sits on, and the career whose `craft_section` it is makes its orders (doc 41). With no
Ranger in the colony the order waits as "Needs a Ranger". The recipe's `catch_log` adds each
batch to the Ranger's log of fish dried.
- **Ingredient words.** A recipe names its goods with `ingredient_words` (the dried fish's:
  "fish"), so its orders wait "for 2 matching fish" or "for 2 perch", never for wood.
  Wooden recipes keep timber's words.
- **A workshop's motion.** The furniture's `crafting_motion`: "hands" hangs the goods by
  hand, with the goods at the dwarf's feet and no axe or chop. Without it a Worker hews, as
  at the workbench.
- **Its window's action.** `crafting_recipe` and `crafting_action` give a workshop its
  action: the workbench's Craft items and the rack's Dry fish.
- **Its batch on show.** A workshop's `batch_model` is laid over it only while a dwarf works
  a batch there (`CraftingManager._show_batches`, `FurniturePlacementController.show_batch`):
  the fish hang on the drying rack while they dry, and an idle rack is bare (owner: "the
  drying rack should not display fish if no fish are drying").

**Log dining table (2026-10-18):** Craft → Rudimentary → Dining now offers a
Log Dining Table for two matching logs and 16 seconds at a crude workbench.
Its 3×3 footprint is a split-slab top over a one-block central base (the Tier 1
design in doc 62). Pine, Oak, Juniper and Applewood follow normal material selection,
packed delivery, installation, Move and saving. Four separate stools fit
the displayed guides, one against the middle of each side, so table and four
stools together occupy 5×5. Stools are crafted independently (docs 231, 232); the
guides take log and stone stools alike (doc 293).

**Recipe categories (2026-10-13):** Rudimentary groups items by their use, matching
the Place catalogue: Rooms contains the log bed, hearth and three doors; Dining
contains the log stool and bench; Lighting contains the log torch and campfire.
These replace the mixed Camp furnishings group. Workshops, Access and Starter
tools retain their existing recipes. Categories affect browsing and search only.
Recreation holds the Board-game Table: two matching logs and one rough stone, 18
seconds; Access also holds the Log Fence Post and Log Gate, one log and 10 seconds each
(doc 198).

**Rudimentary hearth (2026-10-11):** Rudimentary → Rooms now offers a
rough fieldstone hearth: two matching logs and four rough stones, physically delivered to
a crude workbench before 18 seconds of work. It emits 9600 heat units, tended so a room
never goes past 18°C (1600 until 2026-10-30, 2400 until doc 199; doc 34), and quiet fire
audio while lit. Unlike the other wooden
starter pieces it keeps no wood identity, whichever logs it used (its definition has no
`material_group`). Repeated ingredients appear as one quantity in the recipe detail. Fuel upkeep remains
future work (doc 122).

**Log bed cost (2026-10-11):** One bed requires four matching logs at the crude
workbench, under Rudimentary → Rooms. Every log is physically delivered
before the 16 seconds of work. Mixed species cannot substitute for a complete
batch; the finished bed retains its wood identity. Cancelled work releases all
unconsumed timber (doc 120).

**Material identity and appeal (2026-10-11):** Starter recipes inherit the actual
selected timber. Wood follows packed goods, storage, carried/equipped items,
installation and saves. Maintain counts only outputs made from allowed wood;
Place selects a wood within its existing design card. Appeal is design plus a
scaled material bonus, with future copper/gold tuning separate from recipes (doc 118).
- A recipe opts in with `material_group`. The batch's first log fixes its wood, and the
  material of the last log is read just before that log is consumed, so interrupted
  work keeps the original goods. Names read "Oak log stool"
  (`CraftMaterials.product_name`).
- `material_id` is an item property, not a new item key. It survives splitting, storage,
  relocation, equipment, saves, installation and recovery, and different materials never
  share a stack or a storage slot. A ladder keeps one material per built section and gives
  them back in order. Packed crates keep their neutral art.
- A placement plan's chosen wood (`required_material_id`, saved with the plan) binds its
  claim, storage withdrawal and redirected hauls; Any takes the nearest.
- Appeal (`design`, `material_factor`) lives only in the furniture definitions
  (`data/furniture/*.json`); a packed item finds its piece through
  `FurniturePlacementController.def_for_item()`, which the crafting screen and the item
  inspector use. Keeping a second copy in the item data let the build menu and crafting
  disagree (doc 258; `PackedAppealTest`, gate). Furniture and item definitions both carry
  `material_palette`; `data/materials/craft_materials.json` holds each material's bonus
  (pine 0, oak 1, juniper 1.5, applewood 2; iron 1, copper 4 and gold 25 wait for
  refined-metal recipes). Torches and campfires take a quarter of it
  (`material_factor` 0.25). Raw ore never becomes furniture.
- Goods without a `material_id` stay unspecified: original artwork and the design's
  appeal alone. Nothing guesses their wood.

**Log furniture (2026-10-11):** Rudimentary → Rooms offers 2/3-wide single log
doors and a 4-wide double log door. Dining offers a log bench. Each uses
one allowed timber at a crude workbench, taking 12/18/24 seconds for doors and
10 for the bench. Finished crates use normal haul/install work. The starter
wooden torch is renamed Log torch; its four-per-log recipe is unchanged (doc 117).

**Crafting menu (2026-10-11):** the profession cabinet uses compact category
icon groups, name/category search, and separate Recipes / Orders tabs. A single
selected-item card shows the illustration, real materials/stock, batch or stock
target controls, and Place. Pause, priority, cancellation and per-order wood
selection stay in Orders. Recipe costs, reservations and work are unchanged (doc 114).
The window was rebuilt on 2026-10-24; its current layout is "The crafting window" in
`23_user_interface.md`.

**No bridge kits (2026-10-27):** the Log bridge kit recipe was retired with the log
bridge; rivers are crossed on logs built from Build (doc 32, "River crossings").

**Carpenter promotion (2026-10-09):** A crafted crude carpentry kit now enables
promotion after the selected dwarf reserves, collects and equips it. Changing
profession returns the kit. The Carpenter's own page and bench followed in doc 293
(Specialist workbenches, below); general work remains available. The old profession stays until the kit is picked up;
the appointment rules are in `41_dwarf_agents.md`, Agreed equipment progression
(doc 101).

The shared **Equipment** tab shows the owned kit, materials and current benefit.
The Blacksmith-made iron saw is an explicit planned upgrade, not a craftable
item. Completed promotions play a chime (doc 102).

**Profession menu and camp furniture (2026-10-09):** Craft opens a submenu of
profession icon buttons above the dock. Choosing **Rudimentary** opens Worker
recipes; specialists open planned menus and Miner opens an equipment preview.
Since 2026-10-24 the crafting window's own Crafters row switches professions (doc 23).
Each menu shows its own section's orders. Browsing preserves live production;
previews cannot queue unavailable crafts. Workers can now make a campfire from
one allowed log plus one Rough Stone (10 seconds), or a log stool from one allowed
log (8 seconds), at the crude workbench. Both use normal physical crafting and
placement; idle dwarves use stump stools. Installed campfires and hearths are lit at
dusk with a log and burn until dawn (doc 34). No specialist jobs are enabled (doc 100).
- **Sections** (`sections` in `worker_crafting.json`: name, `planned`, preview and
  requirement text) only present the menu. They never enable a specialist job or change
  who may craft; a recipe without `section` belongs to Rudimentary.
- **Every placeable recipe needs a Place tile.** A recipe that makes furniture needs its
  design in `data/ui/place_catalog.json`, or its goods can never be placed: the first
  campfires and stools shipped that way. `ProfessionCraftingTest` checks every one.

**Implemented starter crafting:** Workers can make a crude workbench without an
existing workshop, install it, then craft batches of log torches (four per log).
The bench is a rough **3×3 stump** usable from any open side. Its 1-unit top
has a worker-facing crafting contact 0.625 units from the center. Its first
packed form is crafted at the timber pickup spot; the settlement flag is not a
workshop. Recipes live in `data/workshops/worker_crafting.json`, loaded only by
`CraftingManager`. The Craft cabinet supports finite batches and spare-stock
(maintain) targets. The specialist metalworking and carpentry chains below
remain design specifications, not live conversion systems.

- **Allowed wood.** Each order keeps its own allowed-wood list, defaulting to the
  recipe's `default_ingredients` (Pine for every current recipe). An empty list
  leaves the order waiting; excluded species are never substituted.
- **Choosing a log.** Workers take the nearest allowed unit by Manhattan
  distance, comparing loose logs and units stored in stockpiles; a loose log wins
  a tie. The checklist is not a species priority.
- **Matching wood.** A recipe that takes several logs (the bed, the tables, the
  hearth) takes them all from one species: a batch starts only when one allowed
  species can supply all of them. Logs a working order still needs are not
  available to other orders (`CraftingManager.batch_ingredient_keys`). Every log is
  delivered to the bench before work starts. Logs set down there stay with the order
  through an interruption ("Interruption" below); cancelling the order leaves staged
  and carried logs as ordinary goods (doc 120).
- **Changing wood mid-order.** Excluding the species of the log already being
  used returns that log and keeps the order's partial progress.
- **Maintain orders** refill in full batches, so the last batch may overshoot a
  target that is not a multiple of the batch size. Installed, reserved and
  carried goods do not count as spares. Queuing a duplicate maintain order
  updates the existing order's target and wood list.
- **One worker per bench.** A worker claims a bench while collecting and
  working; an order never fans out into parallel batches.
- **The queue.** Orders are made from the top down. An order that could start but finds
  every bench of its kind claimed keeps its turn: its status says "Next in line", "2nd in
  line" and so on, and its recipe stays ready to queue. Only a missing bench is a
  requirement ("Needs a crude workbench"): none installed, or none kept, standing on solid
  ground and open on a side. The next free bench goes to the top-most order that can start
  (doc 31, "Craft queue order"). An order that can't start yet (wood, materials, a met
  stock target, paused) is passed over, so later orders may go ahead of it. An
  interrupted order with goods beside a bench waits for that bench only.
- **Fixed ingredients.** `additional_ingredients` lists exact item keys, one unit each
  (Rough Stone for the starter tools, campfire, hearth and board-game table). The worker
  fetches them first, then the logs. Every ingredient but the last is set down beside the
  bench as an ordinary loose item claimed by the order (`WorkerCraftOrder.claim_owner_id`),
  not an abstract credit, and the bench stays claimed between trips. Counts, claims,
  positions, the wood rule, the work cell and the bench are checked again before work and
  at the commit; only a finished batch consumes them. There is no material ledger
  (doc 97).
- **Trips.** A Worker carries as many ingredients a trip as hauling would: the hauling
  `carry_capacity` by each good's `carry_cost`, so four stones or logs (owner report
  2026-10-30: Tekak brought a Log bed's logs one at a time).
  - The first ingredient is chosen, and its routes proven, as before. After each pickup
    the Worker also takes the next ingredient the batch needs if it lies within the
    hauling `pouch_bundle_radius` (8 blocks), loose or stored, then sets the whole load
    down beside the bench together (`WorkerCraftOrder.reserve_trip_extra`).
  - A load that completes the batch keeps its last log in hand, and work starts.
  - An extra that is gone or out of reach is left where it lies; the trip goes on to
    the bench with the rest.
  - Goods in a loose crate, such as a fisher's catch at the shore, are used where they
    lie: the crate is reserved whole until pickup, which takes out one unit
    (`WorkerCraftOrder.take_planting_item`), and the rest stay in it (doc 289).
  - Units of one kind that travel in crates share one crate's load, as a hauler carries
    a crate (`WorkerCraftOrder._load_with`), so both fish of a drying batch go in one
    trip. A log or a stone is one to a crate, so they still go four at a time.
  - A Log bed takes one trip; a hearth two, four stones and then two logs.
- **Interruption.** Sleep, a meal, lost access or a broken route stop the Worker, not
  the order (owner report 2026-10-30: a hauler stored a hearth's stones and logs while
  the next Worker gathered them all again).
  - The goods beside the bench stay there, claimed by the order, so no hauler stores
    them and no other order takes them. So does the stone or log in the Worker's hands
    if it lands beside the bench, as when they were working or setting it down.
  - Partial work stays with the order. The bench goes to the next order in turn; the
    interrupted order waits for that bench, "Next in line" while another order uses it.
  - When its turn comes, a Worker brings only what is missing, or lifts the last log
    when everything is there, and finishes the work at that bench.
  - The goods become ordinary loose goods again, which hauling stores, when the order
    is paused or cancelled, its bench is removed or flagged for uninstall, its stock
    target is met, its staged logs' wood is excluded, or a staged good is moved,
    forbidden or falls. Partial work survives all of these but cancelling, and moving
    the workbench keeps it too (doc 132).
  - A save keeps the goods with the order, which records each one's item and cell and
    the bench; the Worker's ingredient is recorded at their feet, where it lands on
    load. A load claims them again in order, stopping at the first one no longer there.
- **Sound.** The craft sound fires when the axe crosses contact, driven by saved
  work progress, so resuming never replays earlier strikes. Clock speed changes
  the cadence, not the pitch.

**Starter tools implemented (2026-10-09):** Workers craft stone hoes, Ranger's
kits, crude carpentry kits, crude masonry kits (doc 293) and stone hammers at the crude
workbench. Each uses one allowed log and one Rough Stone, collected physically before
crafting. Tools support normal hauling, storage and saving. The recipe card and profession
preview show current availability: the Carpenter, the Stonemason and the Ranger equip their
kits; other careers remain planned (doc 97). Tools are
ordinary goods in the Other goods storage category (`stockpile_misc`, with exact-item
filters) and Inventory's Tools group, never placeable. The Ranger's kit, a stone-tipped
spear bound to a peeled fishing rod, replaced the hunting spear on 2026-11-01 (owner,
doc 292). Its line is drawn, not an ingredient, so it needs no cord or leather; bows
are later equipment.

**Agreed equipment direction (2026-10-09, planned):** crafted tools will support
selected profession requirements and later upgrades. Miner keeps its default
pickaxe and free promotion; the iron pickaxe is the first planned mining-tool upgrade.
Workers must be able to craft the crude tools needed to establish the first
specialists without circular recipe dependencies. The starter recipes above
are live; Carpenter kit pickup/equipping followed in milestone 101, and the Stonemason's
kit and both careers' own benches in doc 293. Other tool careers remain future work. Equipment ownership and UI:
[41 — Equipment progression](41_dwarf_agents.md#agreed-equipment-progression--planned-2026-10-09).
Iron/advanced-metal multi-voxel benefits and limits:
[43 — Pickaxe upgrades](43_mining_materials.md#pickaxe-upgrades--planned-2026-10-09).
Durability and repairs are deferred beyond the first equipment version.

## Overview

The colony's metalworking chain converts raw ore into the tools, weapons, and armour that keep the settlement alive and defended. It operates in two stages: the **Smelter** refines ore into ingots, and the **Forge** turns ingots into finished goods. Both buildings are operated by the **Blacksmith**, the colony's one metalworking profession. There is no Weaponsmith or Armorsmith (owner decision, 2026-10-31): the Blacksmith forges weapons and armour too.

This system closes the two open placeholders in prior design docs:

- `52_combat_military.md` acquires military gear through trade until the Forge exists. The Blacksmith's weapon and armour recipes here remove that constraint.
- `51_visitors.md` lists crafted goods as merchant buy priority 5. Forged items are the first entries in that tier; mined gems are already finished valuables in tier 2.

---

## Professions

### Planned carpentry chain (2026-10-04)

Oak trees yield raw logs and possible acorns. The carpenter will process **oak
logs → oak staves → oak aging casks**; finished staves are not felling drops.
Keep the existing oak-stave item definition for this future crafting output.
Recipe quantities, work times and workshop behavior are not implemented yet.
This carpentry work is separate from the tree-felling milestone.

### Specialist workbenches (2026-11-01)

From the owner: each specialist crafts its own starting workbench, and better tools later let
it craft more advanced ones. A career's first workbench is made by that career alone at the
crude workbench from raw goods, as Rangers make the drying rack. Built for the Carpenter and
the Stonemason (doc [293](../00_dev_roadmap/293_stonemason_and_carpenter.md), step 2):
- **The pages.** Crafters → Carpenter and Crafters → Stonemason are live sections
  (`worker_crafting.json`), laid out as the Rudimentary page with no `later` box. A recipe's
  `section` names the career that makes it; with none in the colony its order reads "Needs a
  Carpenter" or "Needs a Stonemason".
- **The carpenter's bench:** three matching logs, 16 s, Workshops. A thick slab hewn flat on
  top on four peeled log legs braced low with log rails, from the owner's picture (peeled,
  A), 3 × 1 with its work top at 1.125. Its wood recolours it like other log furniture.
- **The mason's bench:** a log and three Rough Stones, 18 s, Workshops. A split stone slab on
  two log stumps, 3 × 1 with its work top at 0.9375; the slab keeps the Rough Stone's own
  greys and the bench takes no wood (no `material_group`).
- Both install through Place → Workshops. Goods worked on either lie on the slab where it is
  nearest the worker, `crafting_surface_inset` (0.4375) inside its edges, so even a Rough Stone
  never overhangs it (`CraftingManager.bench_surface`); the round stump keeps
  `crafting_surface_radius`.
- **The stone stool** (step 3): Stonemasons make it at the mason's bench from one Rough Stone
  (10 s, Dining; the recipe's `ingredient_tag` is `stockpile_stone`, the Rough Stone alone, with
  stone's `ingredient_words`). Without a mason's bench its order reads "Needs a mason's bench".
  The Rough Stone itself lies on the slab while the maul knocks it square.
- **The tool rack** (doc [294](../00_dev_roadmap/294_storage_furniture.md), step 3): the
  Carpenter's first goods. Carpenters make it at the carpenter's bench from one log (12 s,
  Storage); without a carpenter's bench its order reads "Needs a carpenter's bench". It keeps
  three of the colony's tools (doc 31, "Storage priority and storage furniture").
- The benches' Craft items now open what is made at them: the tool rack at the carpenter's
  bench, the stone stool at the mason's bench.
- Planks, dressed stone and the advanced benches wait for iron tools.

### Carpenter entry tools — dependency review (2026-10-09)

The player flagged that requiring a saw for Carpenter promotion could require
Blacksmith first. The chosen starter tool is a crude carpentry kit; a metal saw
is a later equipment upgrade.
If the first smithing workshop also needs Carpenter products, that would create
a circular dependency. Current Worker crafting already starts with an implicit
axe and crude workbench; milestone 97 extends it with the carpentry kit.

**Starter recipe implemented in milestone 97:** a Worker makes a crude carpentry kit
at the crude workbench from timber and rough stone, represented by a wooden
mallet and stone adze. Milestone 101 makes it the Carpenter's collected/equipped
promotion requirement without metalworking; the Carpenter's own bench followed in doc 293.
A later Blacksmith-made iron saw will upgrade the Carpenter's equipment,
with faster work and/or finer recipes to be balanced with the profession.
Do not invent a wooden saw to satisfy the entry requirement.

The first Blacksmith must likewise be establishable with basic tools and a
starter workshop that requires neither refined Carpenter goods nor its own
forged output. The stone hammer is now Worker-crafted; the specialist workshop,
promotion gates and upgrade benefits remain to be implemented.

### Blacksmith — `base:profession:blacksmith`

The Blacksmith is a permanent, long-term colony role. They are the only profession that operates the Smelter and the Forge: they make the basic metal goods the colony consumes continuously (pickaxe heads, torch brackets, door hardware and nails) and every weapon, piece of armour and shield its military uses. A colony that arms itself needs enough Blacksmiths to keep both buildings busy.

**Primary task types:** `SMELT`, `FORGE`
**Work speed bonus per level:** `0.05` (matches Brewer — 5% per level, 25% total at level 5)

---

## The Smelter

`base:workshop:smelter`

The Smelter converts raw ore into metal ingots. It is a standalone workshop block — no sealed room required. Place it underground or on the surface; it functions identically in both locations. Only **Blacksmiths** operate the Smelter.

Full schema: `data/workshops/smelter.json` *(to be created)*.

**Status:** the smelter is planned. There is no smelter furniture definition or
placed model in the game yet, and none of the production behavior in this
section is live.

### Placement

- Footprint: **2×2 floor cells, 3 blocks tall**, including the chimney (approved art design, 2026-10-03).
- Requires three clear air blocks above each of its four floor cells. The adjacent operator position also needs the standard 3-block dwarf clearance (see `32_navigation_3d.md`); no outdoor chimney/exhaust rule is implemented.
- Produces heat: a Smelter in operation counts as **800 heat units** for the temperature system in its enclosing room (see `34_temperature.md`). A Smelter left running in a shallow aging cellar will ruin the temperature balance — keep it in a dedicated room.

### Smelting Recipes

Coal is consumed as fuel in every smelting recipe. It is never a product and cannot be smelted itself.

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:smelt:iron_ingot`   | 2× iron ore + 1× coal   | 2× iron ingot   | 1 h | 1 |
| `base:recipe:smelt:copper_ingot` | 2× copper ore + 1× coal | 2× copper ingot | 1 h | 1 |
| `base:recipe:smelt:tin_ingot`    | 2× tin ore + 1× coal    | 2× tin ingot    | 1 h | 1 |
| `base:recipe:smelt:silver_ingot` | 2× silver ore + 1× coal | 1× silver ingot | 1 h | 2 |
| `base:recipe:smelt:gold_ingot`   | 2× gold ore + 1× coal   | 1× gold ingot   | 2 h | 3 |

> **Design note:** Gold and silver ingots have no combat application — they are luxury goods. Gold ingots are the highest-value item a merchant will buy (above gems, by unit weight). The Blacksmith who can smelt gold is a direct economic asset.

Silver and gold ingots need base trade values (see the planned price table in `51_visitors.md` § Pricing). Exact values TBD in the trade balance pass.

---

## The Forge

`base:workshop:forge`

The Forge turns ingots and other materials into finished goods. Blacksmiths work every Forge recipe: general goods, weapons and armour. A single Forge serves the whole colony — build additional Forges only when throughput is a bottleneck.

Full schema: `data/workshops/forge.json` *(to be created)*.

### Placement

- Footprint: **1×1×2 blocks** (floor block + anvil block above).
- No sealed room required.
- Does **not** produce heat units — unlike the Smelter, the Forge is cold-worked for game design purposes (simplicity; the Smelter is the heat-producing step).

---

## Forge Recipes — General Goods

General metal goods. Any Blacksmith accepts these tasks.

| Recipe ID | Inputs | Output | Work Time | Min Skill | Notes |
|---|---|---|---|---|---|
| `base:recipe:forge:pickaxe_head`    | 1× iron ingot   | 2× pickaxe head    | 1 h   | 1 | Used in mining tool construction (future) |
| `base:recipe:forge:torch_bracket`   | 1× iron ingot   | 4× torch bracket   | 0.5 h | 1 | Required to place wall torches |
| `base:recipe:forge:door_hinge`      | 1× iron ingot   | 4× door hinge      | 0.5 h | 1 | Required to place constructed doors |
| `base:recipe:forge:iron_nail_bundle`| 1× iron ingot   | 6× iron nail       | 0.5 h | 1 | Used in BUILD tasks for wood construction |
| `base:recipe:forge:copper_fitting`  | 1× copper ingot | 4× copper fitting  | 0.5 h | 1 | Used in brewery/aging cellar construction |

---

## Forge Recipes — Weapons

Only Blacksmiths accept `FORGE` tasks for these recipes. If no Blacksmith exists, these recipes are never queued.

### Melee Weapons

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:forge:sword_iron`     | 2× iron ingot | 1× iron sword     | 2 h | 2 |
| `base:recipe:forge:axe_iron`       | 2× iron ingot | 1× iron axe       | 2 h | 2 |
| `base:recipe:forge:maul_iron`      | 3× iron ingot | 1× iron maul      | 3 h | 3 |
| `base:recipe:forge:greataxe_iron`  | 3× iron ingot | 1× iron greataxe  | 3 h | 3 |

### Ranged Weapons

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:forge:crossbow_iron` | 2× iron ingot + 1× cloth | 1× iron crossbow | 3 h | 3 |

> **Cloth requirement:** Crossbow limbs require a cloth-wrapped grip. Cloth is produced from pig tail at the Brewery (`base:recipe:brew:pig_tail_cloth`). This creates a soft dependency between the farming/brewing chain and military production.

---

## Forge Recipes — Armour

As with weapons, only Blacksmiths accept `FORGE` tasks for these recipes.

### Leather Armour

Leather armour uses **leather strips** as its primary input. Leather strips are not produced in the colony — they must be acquired through merchant buy orders at the Trade Counter. This makes leather armour the early-game, trade-dependent tier; chainmail and plate are the self-sufficient tiers.

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:forge:helmet_leather` | 2× leather strip | 1× leather helmet | 1 h | 1 |
| `base:recipe:forge:chest_leather`  | 4× leather strip | 1× leather chest  | 1.5 h | 1 |
| `base:recipe:forge:boots_leather`  | 2× leather strip | 1× leather boots  | 1 h | 1 |

### Chainmail

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:forge:helmet_chain` | 2× iron ingot | 1× chainmail helmet | 2 h | 2 |
| `base:recipe:forge:chest_chain`  | 4× iron ingot | 1× chainmail chest  | 3 h | 2 |
| `base:recipe:forge:boots_chain`  | 2× iron ingot | 1× chainmail boots  | 2 h | 2 |
| `base:recipe:forge:shield_iron`  | 3× iron ingot | 1× iron shield      | 2 h | 2 |

### Plate Armour

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:forge:helmet_plate` | 4× iron ingot | 1× plate helmet | 3 h | 4 |
| `base:recipe:forge:chest_plate`  | 8× iron ingot | 1× plate chest  | 5 h | 4 |
| `base:recipe:forge:boots_plate`  | 4× iron ingot | 1× plate boots  | 3 h | 4 |

> **Plate cost:** A fully equipped Stoneclad costs 16 iron ingots in armour alone (8 chest + 4 helmet + 4 boots), plus 3 for the maul or greataxe — 19 ingots total per soldier, requiring 38 iron ore and 10 coal. Plate is a meaningful late-game investment that makes iron ore veins strategically valuable.

---

## Task Types

Two new task types are added to `Task.Type` in `31_task_system.md`:

```gdscript
enum Type { MINE, HAUL, FARM, BREW, BUILD, IDLE, PATROL, SMELT, FORGE }
```

### Default Priorities

| Task Type | Default Priority | Rationale |
|---|---|---|
| `SMELT` | 45 | On par with BUILD — ingots must stay ahead of Forge demand |
| `FORGE` | 40 | Same as HAUL — keeps military stocked without pre-empting core production |

Priority bonuses:

```
+20  if bolt stockpile < 20 and task type == FORGE and recipe == bolt_bundle
+15  if no iron ingots in any stockpile and task type == SMELT
```

### Skill Compatibility

| Task Type | Preferred Skill |
|---|---|
| `SMELT` | `base:profession:blacksmith` |
| `FORGE` | `base:profession:blacksmith` |

A dwarf without the preferred profession can attempt a `SMELT` or `FORGE` task at ×0.7 speed — but only general-goods recipes. Weapon and armour recipes need a Blacksmith: a Farmer cannot forge a sword regardless of speed penalty.

---

## Stockpile Integration

### New Stockpile Filter Tags

The Stockpile filter panel (see `23_user_interface.md`) gains two new filter categories:

| Filter Tag | Covers |
|---|---|
| `stockpile_ingots` | All metal ingots (iron, copper, tin, silver, gold) |
| `stockpile_metalwork` | All forged items (tools, weapon components, armour pieces, weapons) |

Leather strips use the existing `stockpile_general` category until a dedicated tag is warranted.

---

## Integration with Existing Systems

| System | Integration Point |
|---|---|
| `TaskManager` | `SMELT` and `FORGE` added to `Task.Type`. Priority table in `31_task_system.md` updated. |
| `DwarfAgent` | Blacksmith experience counts in `profession_experience` like every profession's (see `41_dwarf_agents.md`). |
| `StockpileManager` | New filter tags `stockpile_ingots` and `stockpile_metalwork`. Bolt stockpile tag `stockpile_ammo` already scaffolded in `52_combat_military.md`. |
| `RoomData` / temperature | Smelter emits 800 heat units into its enclosing sealed room while active. Handled the same way as torches — see `34_temperature.md`. |
| `VisitorManager` / trade | Gold and silver ingots, forged weapons (if surplus), and armour pieces get base trade values (`51_visitors.md` § Pricing) and appear in the merchant buy priority 5 tier. |
| `52_combat_military.md` | The `ARMING` task now resolves via Forge output — military gear no longer depends exclusively on trade. The placeholder note in that doc is satisfied by this system. |

---

## Hard Rules

1. **Only Blacksmiths operate the Smelter.** If no Blacksmith exists, the Smelter idles regardless of ore supply.
2. **Weapon and armour recipes need a Blacksmith.** The Task System must check the assigned dwarf's profession before issuing a weapon or armour `FORGE` task.
3. **One metalworking profession.** There is no Weaponsmith or Armorsmith, and no specialisation beyond Blacksmith: the same Blacksmith forges nails, swords and plate (owner decision, 2026-10-31).
4. **The Smelter heat output applies at all times while a batch is in progress.** It does not matter whether a dwarf is currently standing at the Smelter — a running batch heats the room.
5. **Leather strips are never produced in the colony.** They are a trade-only input. Do not add a tanning or hide-processing recipe without a new design doc covering that system.

---

## Forward Compatibility Notes

- **Gems are finished drops (user decision, 2026-10-10)** — Jade, Amethyst, Ruby, Sapphire, Emerald and Diamond are beautiful and trade-ready immediately after mining. No Jeweller profession, workshop, cutting or polishing stage is planned. This replaces the earlier deferred Jeweller proposal. Their stable `_raw` identifiers do not imply unfinished goods.
- **Steel tier** — `52_combat_military.md` notes steel as a future equipment quality tier above iron. When steel ore or a steel-making recipe is added, it slots into the existing smelting/forging pipeline with higher `min_skill` requirements and better damage/reduction values. No structural changes to this system are needed.
- **Forged weapons and champions** — the champion invader AI (`52_combat_military.md` Forward Compatibility) may loot forged weapons on colony breach. The item drop pipeline already handles this; no new code needed.
- **Copper and tin uses** — copper and tin ingots have no forge recipes yet. They are placeholder outputs for future systems: copper fittings for water/brewing infrastructure upgrades, tin for food preservation vessels. Do not delete them from the smelting table.
- **Support pillars** — `43_mining_materials.md` notes a future support pillar mechanic. Iron or copper ingots are the likely material input when that system is designed.

---

*Prev: [43_mining_materials.md](./43_mining_materials.md) | Next: [51_visitors.md](../50_world_events/51_visitors.md)*
