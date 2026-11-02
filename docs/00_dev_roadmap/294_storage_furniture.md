# 294 — Storage furniture: the tool rack, the raw materials crate and the finished goods pallet

2026-11-02. Steps 2 to 4 are built: the storage priority, the tool rack and the raw materials
crate ("Built", below); they await the owner's look in Play. The pallet is next. The owner picked
the designs (tool rack B, crate A, pallet A) and added a 1 to 5 storage priority ("Picks",
below).

From the owner:
- On the Carpenter's first piece: "A wall mounted tool hanger could be a good start for the
  carpenter"; then, asked whether it holds the colony's tools or is for looks: "Hold tools".
- Then: "the carpenter can build the tool rack and also let's plan two more. A Raw materials crate
  for ores, stones, dirt, etc... and a Finished Goods pallets for metal bars, refined stones,
  planks, etc...".

These are the first storage furniture since barrels, chests and shelves were removed on
2026-10-22 (`00_todo.md`, "Storage furniture"). The owner's rule for containers, from 2026-10-23,
stands:
- each container type accepts only certain goods, and its filter lists only those;
- it may hold one chosen item type, named in its title;
- it shows its capacity ("Used 9 / 12");
- the reference is Stonehearth's supply shelf (`tmp/ui_review_20261023/stonehearth/15_supply_shelf*`).

## Storage today

- **Only ground zones.** A zone stores one stack per floor cell. Most goods fill a cell with one
  unit (`ItemDropManager.item_capacity`); produce crates take 24.
- **Hauling.** A zone posts HAUL jobs for the loose goods it accepts, at priority 40, below crafts,
  building, mining and fishing. Storages compete only by distance. Goods move out of a store only
  when that store stops accepting them, so a new container would never pull tools out of a zone
  that still takes them.
- **Taking goods out.** Crafting, promotions (a kit) and meals find stored goods as readily as
  loose ones. Their pickups assume the goods lie on a floor cell, except meals, which ask the
  storage where to stand.
- **The parts are there.** All storage shares one hauling contract (`StorageComponent`), meant for
  ground zones and furniture alike. Its one furniture user today is the construction-materials
  crate. The removed barrels, chests and shelves (`ContainerStorageComponent`, commit `b3a95478`)
  are a close template: capacity slots, goods shown on anchors, contents dropped loose when
  uninstalled, saves.
- **Storage categories.** Eleven `stockpile_*` tags file the goods: stone (Rough Stone), ore (the
  six ores and coal), soil, gem, wood, food, drink, seed, furniture, currency and misc. The five
  tools are misc, marked by their own `tool` tag.
- **Finished goods do not exist yet.** Metal bars, dressed stone and planks wait for iron tools
  (doc 293). No item or storage category exists for them.

## The three containers

| | Tool rack | Raw materials crate | Finished goods pallet |
|---|---|---|---|
| Where | On a wall, 3 blocks wide | On the floor, 2 × 2 | On the floor, 2 × 2 |
| Holds | Tools (`tool`): the carpentry, masonry and Ranger's kits, the stone hoe and the stone hammer today; iron tools later | Rough Stone, the ores and coal, soil (`stockpile_stone`, `stockpile_ore`, `stockpile_soil`) | Metal bars, dressed stone and planks, once they exist |
| Capacity | 3 tools, one to a hook | 12 units, 3 to each quarter | 12 units, 3 to each quarter |
| Shows | Each tool hung on its hook, the game's own model upright | Each filled quarter's goods, over the rim | Each filled quarter's stack on the deck |
| Made by | Carpenters at the carpenter's bench, 1 log | Carpenters there, 2 matching logs | Carpenters there, 2 matching logs |
| Place | Storage (a new category) | Storage | Storage |

The capacities are a start, to tune in play. A 2 × 2 zone holds 4 Rough Stones; the crate holds 12
on the same ground.

## How they work

- **Filling.** A container posts HAUL jobs for the goods it accepts, as a zone does. At priority
  4 it ranks ahead of ground zones at 5, so it fills first and draws its goods out of them while it
  has room ("Storage priority", below). That way, tools end up on the rack.
- **Taking out.** Crafting, promotions and Build take goods from containers as from zones. A
  dwarf stands in front of the rack's wall, or beside a crate or a pallet, to take them.
- **The window.** Each container opens the storage window, for its own goods only, with its
  priority:
  - the title names it, and the item it keeps when the player chooses one ("Raw materials crate ·
    Iron ore");
  - "Used 2 / 3" counts hooks or units;
  - the filter lists only its kind of goods (tools for the rack, raw goods for the crate).
- **Moving and removing.** A move keeps its settings. Uninstalling drops its contents loose,
  where haulers pick them up. A rack whose wall is mined away drops its tools.
- **Saves.** The contents, the filter and the priority save with the furniture.

## Concepts (2026-11-02)

All Tier 1 (doc 64): hewn, split and peeled wood, pegs, rope and bark, with no saw, planks or
iron. They are photographed in a copy of the owner's colony with the game's own tools and raw
goods; the pallet's stacks are stand-ins, since its goods don't exist yet. The pictures are in
`tmp/storage_concepts_20261102/world/`: one sheet each (`rack.png`, `crate.png`, `pallet.png`),
the close shots, and a wide shot of each row.
- **The tool rack**, on a short rock wall raised in the copy, as a hall's walls are rock:
  - A · The stub pole: a peeled branch with its side branches cut short as hooks, hung level by
    rope from two pegs driven into the wall.
  - B · The pegged board: half a split log, its round back to the wall and its split face out,
    lashed to two wall pegs, with three stout pegs driven in, angled up.
  - C · The forked sticks: three forked branches driven into the wall with their bark on, each
    fork holding one tool. No board and no rope.
- **The raw materials crate**, low enough that its goods show over the rim:
  - A · The log crib: two courses of notched logs crossing at the corners, open on top.
  - B · The wattle bin: eight stakes driven in, with split withies woven between them.
  - C · The slab box: four split slabs stood on edge, split faces inward, lashed at the corners.
- **The finished goods pallet:**
  - A · Log skids: split poles laid across two log runners, split face up, lashed at the ends.
  - B · The lipped pallet: the same on three runners, with a peeled pole along each side to keep
    stacks tidy.
  - C · On stumps: split poles on two bearers and four short stumps, off the damp ground.

## Picks (owner, 2026-11-02)

From the owner: "tool rack - B // Crate - C // Pallet A - Also, we should add a ranking for
storage zones. The ground storage should start out with the lowest value, let's say we implement a
1-5 priority system, the ground zone starts as 5 and these more specific storages start as 4,
players can then change them later".
- **The designs:**
  - the tool rack is B, the pegged board;
  - the raw materials crate is A, the log crib. The owner first picked C, the slab box, then, as
    step 4 began: "I want to change my mind and use Option A";
  - the finished goods pallet is A, log skids.
- **Storage priority, 1 to 5,** for ground zones and containers alike. It replaces my "containers
  before ground storage" ("Storage priority", below).
- **Not commented on, so kept as recommended** until the owner says otherwise:
  - the sizes and capacities in the table;
  - the crate takes Rough Stone, ores and coal, and soil, with raw gems left for a valuables chest;
  - the pallet is built with its first goods;
  - a container may be set to one chosen item;
  - the Carpenter makes all three at the carpenter's bench, filed under Storage.

## Storage priority

- **Every store has a priority from 1 (first) to 5 (last).** Ground zones start at 5 and
  containers at 4. The player changes either in its window.
- **Where loose goods go:** to the store of the best priority that accepts them and has room;
  among stores of the same priority, the nearest, as today.
- **Moving up.** Stored goods move to a store of better priority (a lower number) that accepts
  them and has room. They never move between stores of the same priority, so goods don't shuttle
  back and forth. Goods a store stops accepting still move out, as today.
- **Taking goods out** still takes the nearest, whatever the store's priority. Crafts and
  promotions don't walk past a near zone to a far rack.
- **On its own it changes nothing:** with every zone at 5, storage works as it does now. A player
  who sets a zone near a workshop to 1 gets it filled first, before any container exists.
- **Saves:** each zone and container saves its priority.
- **Edge case:** a better store that the hauler can't reach is skipped, so its goods still go to
  the stores they can reach.

## How it will be built

- **The container.** A `StorageComponent` for furniture, after the removed
  `ContainerStorageComponent`. A furniture JSON `storage` block gives the goods it accepts, its
  capacity, and where its goods show (the rack's hooks, the crate's quarters).
- **The registry.** StockpileManager registers containers beside zones, counts them in its totals
  and quotes, and routes their tasks. Containers stay out of `get_zones()`, whose callers expect
  zones.
- **Storage priority.** A `priority` on `StorageComponent`, saved with zones and containers:
  - zones start at 5 and containers at 4;
  - a haul quote skips loose goods that a store of better priority accepts and has room for;
  - relocation also moves stored goods up to a better store, never between equal ones;
  - the storage window has a 1 to 5 setting.
- **Taking out.** Pickups of stored goods ask the store where to stand (`withdrawal_stands`), as
  meals do:
  - `CraftIngredientPlanner`, `FurnitureFetchPlanner`, `DwarfEquipment` and the haul matcher in
    `TaskScheduler`;
  - the rack's stands are the floor in front of its wall (`WallFurnitureMount`), since wall pieces
    have no footprint cells.
- **Furniture.** `FurniturePlacementController`:
  - creates and registers the container on install;
  - drops its contents on teardown, which also runs when a wall is mined;
  - saves its contents and filter, with the save validator updated;
  - moves keep the filter;
  - flagging it for uninstall stops deposits.
- **The window.** The storage window (`StorageInspectorPanel`) for containers: their own goods in
  the filter, "Used x / y", and the chosen item in the title. Inventory counts container goods as
  stored, and Locate finds them.
- **Data.** The recipes on the Carpenter's page, the items and furniture definitions, and a Storage
  category in Place.
- **The art.** The picked designs in `tier1.mjs`, through the usual pipeline. The rack hangs each
  tool's own model upright from its top.
- **Tests.** For each built container:
  - filling, including from a zone;
  - taking out for a craft and for a promotion;
  - the window, uninstall and saves;
  - for the rack, also its wall being mined.

## Steps

1. **Concepts and picks** (done, above).
2. **Storage priority,** for ground zones: the 1 to 5 setting, hauling and moving up, saves.
3. **The container and the tool rack (B),** the Carpenter's first piece, at priority 4.
4. **The raw materials crate (A).**
5. **The finished goods pallet (A),** with its first goods.

Each step gets focused tests, the job gate, then the owner's look in Play. A colony check runs
only when the owner asks for one.

## Built: step 2, the storage priority (2026-11-02)

- **Every store ranks 1 to 5** (`StorageComponent.priority`). Ground zones start at 5, storage
  furniture at its JSON `storage.priority` (the tool rack 4). A project's materials crate
  (`ConstructionMaterials`) ranks 0, so no store takes a project's goods ahead of it.
- **Loose goods go to the best store with room.** A store's hauls skip goods that a better store
  accepts and has room for (`StockpileManager.better_store_takes`). A better store whose haul jobs
  are all waiting out failures to reach goods (`hauling_blocked`) doesn't count, so a walled-off
  store never holds goods back. The answer is kept for a hauling revision, and at most a second.
- **Moving up** (`StockpileManager.moves_to`): stored goods leave a store that stops taking them,
  or move to a store of better priority; never between equal ones.
- **Taking out** stays nearest-first.
- **The window:** a Priority row under the filter, five buttons with the store's own pressed and
  "1 is filled first"; each says on hover what it means.
- **Saves:** zones save `priority`; a zone saved without one is a 5.
- **Test:** `StoragePriorityTest` (storage area).

## Built: step 3, the container and the tool rack (B) (2026-11-02)

- **The rack.** Carpenters make it at the carpenter's bench from one log in 12 s (Crafters →
  Carpenter → Storage); it keeps its wood. Place → Storage hangs it over three floor cells against
  a wall, which must stand behind every cell as high as the rack (3 blocks). It holds three tools,
  one on each peg, each hung upright from its top with its back to the rack's split face.
- **The container** (`ContainerStorageComponent`, after the removed one). A furniture JSON
  `storage` block gives what it accepts (material tags), its `capacity`, its `slot_word`
  ("hooks"), its `priority`, its `anchors` (footprint-local blocks from the back-left floor
  corner) and `hang`. Its filter lists only its own kind of goods, and the player may narrow it.
- **The furniture side** (`FurnitureStorage`, the controller's helper):
  - it creates and registers the container on install;
  - it drops the goods loose in front of it when the piece goes: uninstalled, packed for a move,
    or its wall mined;
  - it saves `storage` (contents, filter, priority) with the installed piece;
  - a move's record carries the filter and the priority;
  - marked for uninstall, the rack takes nothing more.
- **Its wall.** A `floor_wall` piece now falls when its wall is mined
  (`_revalidate_wall_mounts`, which drops its packed item and its goods), and
  `has_wall_behind` checks the wall to the piece's full height. A planned rack is checked again
  when a dwarf comes to build it, so it is never built against a wall mined away meanwhile.
- **Taking out.** A withdrawn good is set down, reserved, on the stand nearest its hook
  (`withdrawal_item_cell`), and the existing pickups plan from there: crafts, promotions and
  relocations. Relocation quotes now plan from that cell too (for zones it is the zone's own
  cell, as before). A relocation's hidden handoff marker keeps that cell as its floor
  (`floor_cell` meta), while the dwarf's hands reach for the hook.
- **Differences from the plan above:**
  - the rack is a `floor_wall` piece over three floor cells, not a wall-mounted one, so its
    stands are the floor around those cells;
  - pickups didn't need `withdrawal_stands` in every planner: the goods are set down on a stand
    cell, and each planner's own floor rules apply.
- **The windows.**
  - The rack's own window says "Holding 2 / 3 hooks" and has a Storage button; its details list
    the hooks in use and the priority.
  - Storage opens the storage window on the rack: its tools as one grid of pictures, "Used 2 / 3
    hooks", the priority. Inventory's Locate in storage opens it too.
  - Inventory and the settlement's storage counts include the rack's goods.
- **Art.** `toolRack()` in `tier1.mjs` (concept B), occlusion `{'wall': -8}`: `tool_rack.glb`
  and its Place picture.
- **Tests:**
  - `ToolRackTest` (storage, furniture and crafting areas): Carpenters make it, its wall, tools
    only, three hooks at priority 4 ahead of the ground, moving up, the windows, Locate, a
    promotion, uninstall, saves, a move and its wall mined;
  - `FurnitureArtTest` (28 forms, 23 definitions; the rack's model starts 33 cells up),
    `FurniturePlacementAnimationTest` (a wall for `floor_wall` pieces) and
    `CraftingSelectionTest` (a carpenter's bench).
- **Checked in a copy of the owner's colony** (`tmp/storage_build_20261102/colony/`): on a rock
  wall raised by the camp, a dwarf hung the rack and haulers filled it with three spare tools
  ahead of the colony's zone, all within seven seconds at triple speed. Once the hoe was no
  longer kept, a dwarf reached up to its hook and took it to the zone.

## Built: step 4, the raw materials crate (A) (2026-11-02)

- **The crate.** Carpenters make it at the carpenter's bench from two matching logs in 16 s
  (Crafters → Carpenter → Storage); it keeps their wood. Place → Storage sets it on the floor over
  2 × 2 cells, and dwarves reach into it from any side. It holds Rough Stone, the ores and coal,
  and soil (`stockpile_stone`, `stockpile_ore`, `stockpile_soil`) at priority 4.
- **Quarters of three.** The storage block's new `per_slot` gives the goods one slot holds: the
  crate's four quarters (`capacity` 4, `slot_word` "quarters") hold three of one good each, twelve
  in all. A new good tops up its own quarter before it takes another, as zone crates do, so a
  fifth kind finds no room while four kinds fill the quarters.
- **What it shows.** Each filled quarter shows one of its goods on the ground inside the crib,
  rising over the rim. A quarter looks the same holding one good or three; its window has the
  count.
- **Counting goods.** Its window and its details count goods, not slots: "Used 8 / 12 goods",
  "Holds 8 / 12 goods", and the bar's hover says "3 goods to each of its quarters." The tool rack
  still counts hooks ("Used 2 / 3 hooks"), without the "· 2 goods" that repeated it.
  `storage_used()` gives what `storage_capacity()` counts: a zone's cells, a container's goods.
- **One good at a time.** A quarter of three gives up one good per trip: relocations take one good,
  or one crate of produce (`StockpileManager.relocation_candidates`), and `withdraw_stack` refuses
  more. Crafts and builds already took one.
- **Uninstalled,** each quarter's goods drop at the stand nearest it, not all at one.
- **Art.** `rawMaterialsCrate()` in `tier1.mjs` (concept A). Floor furniture must stay inside its
  footprint, so both courses sit 2 cells further in than in the concept, keeping their 2-cell
  crossing ends, and the goods sit 6 cells out from the centre instead of 8. It is 4 cells
  smaller than the concept in each direction. `raw_materials_crate.glb` and its Place picture.
- **Tests:** `CrateTest` (storage, furniture and crafting areas): Carpenters make it, moving up
  from the ground, quarters of three, what each quarter shows, the windows, a craft taking a
  stone, one chosen good and the goods moving out, saves and uninstall. `FurnitureArtTest` now
  expects 29 forms and 24 definitions.

## Not in this milestone

- Barrels and chests for food and drink, shelves, and a vault: storage furniture's own later
  steps (`00_todo.md`).
- Stored goods reacting to mining under them (`00_todo.md`).

## Open

- **The numbers:** capacities and costs, to tune in Play.
- **The storage window's height.** It keeps the zones' body height, so the rack's five tools sit
  at the top of a mostly empty grid. Furniture may want a shorter body.
- **A crate's quarter shows one good,** whether it holds one or three. A heap would need smaller
  goods or a pile model: a good is 12 cells wide, a quarter 12 inside.
- **The settlement's storage meter** says "cells used", and now counts a crate's goods among them.
