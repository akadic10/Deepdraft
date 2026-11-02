# 276 — One project per blueprint placement

From the owner, 2026-10-27, placing their Blueprint 7, an 11 × 11 × 11 oak log cabin with a
grass roof: "it feels like it spawns two collection boxes and splits the work". It does. The
owner's decision, the same day: one placement should be one project.

Phases 1 and 2 are built (2026-10-27) with the owner's picks: see "Phases 1 and 2, built".
So is the fix for boxed-in blocks the owner added the same day, for every plan: see "Boxed-in
blocks, built". The owner's look in game is next.

## Before this milestone

- **A click plans one plan a material** (`BlueprintController.place_here`). The blueprint's
  blocks are grouped by construction kind and wood, and each group goes to
  `ConstructionController.create_order` on its own.
- **A plan holds one material:** one kind, one wood, and a crate that takes that material's
  good (`ConstructionWork.item_keys`). So each plan has:
  - its own materials crate (`ConstructionMaterials`), sited on its own;
  - up to two haulers and one builder;
  - its own panel, titled after the material ("Horizontal oak log area", "Grass area");
  - its own start: no block is built until every good the plan needs is in its crate
    (`ConstructionWork.ready_for_staged_work`).
- **Cancel construction** on a panel removes only that material and leaves the rest of the
  building planned. Undo takes the whole placement back.
- **Two starters split already.** The Log cabin plans its horizontal and upright pine logs as
  two plans, two crates of the same logs. The Garden terrace plans its dirt and grass as two
  crates of soil.
- **The bug the owner hit.** A crate is sited near its plan's lowest block: up to 6 blocks
  across, but only 2 up or down (`ConstructionController.place_materials_crate`). Blueprint
  7's grass starts on its sixth layer, so the roof's crate never finds the ground, and its
  panel stays on "No delivery access".

## Decisions (owner, 2026-10-27)

One placement is one project:
- one plan holding every block of the placement, whatever its material;
- one materials crate, on the ground by the footprint;
- one panel named after the blueprint, with each good's delivery;
- one Cancel, and one Undo as today.

Every block is still planned, built and mined on its own, and nothing becomes a building
object (doc 23).

## The project

**The plan** keeps each block's material: its construction kind and, for a log, its wood and
the way it lies, as it already keeps each log's direction. Build and Shapes make plans of one
material through the same code and behave as today.

**The crate** stages every good the plan needs: oak logs and soil for Blueprint 7.
- It takes each good only up to what that good's unbuilt blocks still need, less what is
  delivered or on the way.
- It already keeps goods by item, then material, so the stock count, the refunds and the
  goods it shows need no new shape.
- It is sited from the plan's lowest block, which for a placement is its base, so the
  missing roof crate goes away with the split.

**When building starts:** a good's blocks are built once all of that good is in (the owner's
pick).

**The order.** Every block needs a solid neighbour, so a building still goes up from the
ground: the builder takes reachable, supported blocks whose good is in.

**The panel** (`ConstructionController.get_explorer_data`):
- It is titled with the blueprint's name ("Blueprint 7") and shows the Blueprints picture.
- The status names the stage as today (Waiting for…, Delivering materials, No delivery
  access, Waiting for builder, Building, Needs attention) and the goods still short:
  "Waiting for oak logs and soil · 0 / 367 delivered".
- A row for each good: "Oak logs · 0 / 247 delivered", "Soil · 0 / 120 delivered". On the way
  lists each good.

Build and Shapes plans keep their "… area" panel.

**Cancel, Undo and taking blocks out.**
- Cancel construction takes back the whole placement and drops its unused goods at the crate.
- Undo is unchanged.
- Ctrl + drag still takes blocks out one by one, and the crate gives back what each good no
  longer needs.

**Copy** reads each planned block's own material, so a copy of a half-built placement keeps
its roof and its logs.

**Saves.**
- A plan saves its name and its main material (kind and wood) as before. With more than one
  good, it also saves each good's total blocks for the panel.
- A block names its own kind and wood beside its direction, only where they differ from the
  plan's.
- Plans from Build and Shapes save as they do now, so saves from before this load unchanged.
- `SaveSnapshotValidator` checks each block's material, and the staged goods against each
  good's blocks.

## The owner's picks (2026-10-27)

The owner took both recommendations ("Take the recommended picks").
1. **When building starts.** A good's blocks can be built once all of that good is in.
   - The cabin's walls go up while its soil is still arriving.
   - The roof waits for its soil, and for the walls to hold it.

   Not taken: the old rule for the whole plan, all 367 goods in before the first log. Plans
   of one good behave the same either way.
2. **The crew.** Before, a placement of two materials got up to four haulers and two builders.
   - The haulers stay: up to two for each good still short.
   - One builder for each project, as for any plan.

   In a building the second material mostly waits on the first, so a second builder would
   rarely have work. More builders for big plans can follow if play shows them slow.

## Phases 1 and 2, built (2026-10-27)

Built together, with the owner's picks.
- **`ConstructionWork`:**
  - `own` holds each block whose kind and wood are not the plan's. `kind_of`, `wood_of` and
    `good_of` read a block's own, and `project_name` is the blueprint's name.
  - `needs()` counts each good the unbuilt blocks still need, kept until the plan shrinks.
  - `ready_goods()` gives the goods that are all in. They gate `work_stands`,
    `continue_staged_build`, `can_complete_build`, `reserve_fetch` and the FETCH_BUILD lease.
  - `totals` keeps each good's blocks, built ones included, for the panel. Taking blocks out
    lowers it.
  - A block's work seconds and the block it becomes come from its own kind
    (`work_seconds_of`, `ConstructionController.block_key_for`).
- **`ConstructionMaterials`:**
  - `room_for(item)` drives `has_any_room`, `_has_room_for_key` and `_reserve_deposit`, so a
    crate never takes more of a good than its blocks need.
  - `consume(item)` replaces `consume_one()`, and `refund_excess()` gives back each good's
    extra.
  - `update_leases` asks for up to two haulers for each good still short and in supply.
  - A stored bundle skips a good with no room and fills its budget with the others. Its carry
    speed comes from the goods picked; it used to read the first good the crate takes.
  - The haul quote looks only for goods the crate still has room for.
- **`ConstructionController`:**
  - `create_order` takes `own` and `project_name`, and skips repeated cells with a dictionary
    rather than a list search.
  - The panel is as in "The project".
  - DEV finish and taking blocks out work block by block.
  - Saves are as in "Saves".
- **`BlueprintController`:** `place_here` makes one plan, its own material the one with the
  most blocks; `capture` reads each planned block's material.
- **Saves:**
  - The `SaveManager` catalogs give each construction kind's good, a log's by its wood.
  - `SaveSnapshotValidator` checks each block's kind, wood and direction, and the plan's
    `totals` and `name`.
  - It checks each good's staged count against that good's own blocks; before, it checked the
    total against the plan's blocks.
- **Tests:**
  - `BlueprintTest`: lying and upright logs plan as one plan. A "Turf wall" of 15 oak logs with
    3 grass blocks on top, five blocks up:
    - is one plan named for it, with its one crate on the ground;
    - has a panel that waits for "oak logs and soil" and gives a row for each good;
    - keeps each block's material through Copy and a save;
    - has its logs ready while its soil is short, then finishes with DEV;
    - is taken back whole by Cancel, crate included.

    A test message that formatted badly (`% turned.keys()`) is fixed too.
  - `BuildMaterialsTest`: a plan of two pine logs and a dirt block, with real haulers and a
    real builder. The logs are built while the soil is short and the panel then waits for
    soil; when soil comes the dirt is built, each block taking its own good.
  - `SaveManagerRoundTripTest`: its unfinished order is now a plan of stone and grass. Its
    name, totals and the grass block's kind round-trip. Three new malformed cases are
    refused: a block of an unknown kind, an unknown good in `totals`, and a name that is not
    text.
  - The construction tests and the save round trip pass (18/18). The job gate passes
    (55/55), and the lint finds nothing new.
- **Not checked in the running game.** The owner's look is next.
- **Enclosed blocks, found after building** (2026-10-27, by the builder-reach investigation,
  `tmp/builder_reach_20261027/README.md`, "Three gaps"):
  - A builder could not stand under any unfinished block of its own plan. A placement is now
    one plan, so that covered all its materials.
  - The Garden terrace's inside and the Log cabin's four crossing corners then never got built,
    in any order. With one plan a material, the terrace's inner grass had already stayed
    unbuilt, and only a lucky order built some corners.
  - Fixed the same day: see "Boxed-in blocks, built".

## Boxed-in blocks, built (2026-10-27)

The owner gave option D to this milestone, for every plan (Build, Shapes and blueprints):
"enclosed blocks first, middle outward for solid shapes, with regression tests for the two
starters and a thick Build platform".
- **Depth** (`ConstructionWork.depths`): each unbuilt block's depth at its own layer.
  - It is 1 beside open space, and 2 when its four sides are its plan's unbuilt blocks or
    solid; it grows by one each ring inward.
  - It is -1 when no path of unbuilt blocks leads out.
  - An undiscovered cave counts as rock.
  - It is kept until the plan shrinks, like `needs()`.
- **Middle outward:**
  - `work_stands` keeps each floor for the deepest block it serves, and the floors of each
    depth, deepest first.
  - `advance_fetch_plan` searches the deepest depth's floors first and moves to the next when
    none can be reached, so an unreachable middle never stalls the rest.
  - `continue_staged_build` keeps on from the same floor only at the depth being built.
- **Floors under the plan** (`_stand_allowed`):
  - Beside a boxed-in block, a builder may stand under the plan's own unbuilt blocks, if every
    one of them is nearer the edge than the block being built.
  - Built middle outward, those blocks are still unbuilt, so the builder always has a way out
    and nothing deeper is closed off.
  - Nothing is built into a dwarf, as before.
- **Holding back** (`_keeps_access`): a block waits while it may be the way in to a deeper
  boxed-in block that can't be built just now but soon can, so it is never closed off. That is
  when the block's good is not all in, as in stone walls round a dirt core, or when a dwarf or
  a loose item is in it. A block too high to reach holds nothing back.
- **Tests:** `ConstructionEnclosedTest`, new, in the construction tests.
  - A real builder hauls and hammers a two-layer plus, the shape of a log corner. It finishes
    all ten blocks, the centre first.
  - The scheduler's own choices (route search, floors and keeping on, each block placed at once,
    as the reach probe's oracle did) finish three plans middle outward, never a block before a
    deeper one:
    - the starter Log cabin, placed as one plan: 106 blocks, its 16 corner blocks first;
    - the starter Garden terrace: 48 blocks, its 16 inside blocks first;
    - a thick Build platform, 6 × 6 and two layers: 72 blocks, 32 of them boxed in.
  - The holding back, by the same oracle on two pluses. With an idle dwarf in the centre, or
    with a dirt centre whose soil isn't in, nothing is built. Once the dwarf leaves or the soil
    is in, the centre goes first.
  - The construction tests and the save round trip pass (19/19). The job gate passes (55/55),
    and the lint finds nothing new.
- **The builder-reach session's edge-case notes**, checked against this build:
  - Handled:
    - floors under the plan only outward of the target, with the same rule when keeping on
      (`ConstructionContinuityTest` still passes);
    - holding back regardless of goods, including a middle held up for a while;
    - middle-first as a preference that gives way when the middle can't be reached;
    - the depths cached.
  - Open, both from before this milestone, run by the builder-reach session after this build
    (`tmp/builder_reach_20261027/after_d/`):
    - **Builders can wall themselves in.** A real builder that starts inside a doorless 6 × 6 × 2
      room, its crate inside too, builds 32 of 40 blocks and then can't walk out. The oracle
      does the same in 5 × 5 × 2 and 6 × 6 × 3 rooms (`trap_results.json`). The walls are
      depth 1, so this fix never applies; it needs a way-out check before a block is
      committed. The builder-reach session offered it to the owner as its own task, "Stop
      builders walling themselves in".
    - **Long stairs:** a 12-step Shapes flight still leaves its 10 holes at layers 6 and up,
      68 of 78 built (`after_d_results.json`, `stairs_12_steps`).
- **Blueprint 7,** run by the builder-reach session's oracle after this build:
  - On flat ground its four crossed corners (20 logs) now get built, so the whole log box up
    to layer 5 is finished: 188 of 367 blocks. Everything left is on layers 6–11.
  - With Shapes stairs up to the eaves it reaches 349 of 367. The 18 left are the middle
    logs of both gables, under the roof.
- **Not helped:**
  - a block walled in by finished blocks;
  - a block boxed in by another plan's blocks, which still depends on that plan's order;
  - blocks more than 5 above every floor a builder can reach ("Not in this milestone").

## The Materials card, built (2026-10-27)

From the owner, looking at Blueprint 7's panel ("Delivering materials · 6 / 367 delivered"):
"we might need some way to see what materials need to be delivered by type", following the
Hearthblock layout.
- **Concepts:** three options of different formats, drawn over the owner's Kolvik autosave at
  1920 × 1080 and 7680 × 2160 (150%) from the game's own tiles, chips, tags and hover cards
  (`tmp/goods_panel_20261027/`, `GoodsConcepts.gd`, sheets `goods_*.png`):
  - A: a tile per good under the status, its count on the corner;
  - B: the total on the band's badge, split on hover;
  - C: a Materials tile opening a card.

  The owner picked C.
- **What the concepts showed:** in the owner's colony, Blueprint 7 had 28 of 247 oak logs and
  none of its 120 soil, with neither in stock. The status line was cut short ("Waiting for
  oak logs and soil · 28 / 36…").
- **Built:**
  - `CompactObjectPanel` gained a card an action opens: the action carries `card`, its
    content comes under `cards`, and the open card is filled again when it changes. It is
    drawn like the owner list, above the panel, and its tile stays lit.
  - `ConstructionController._materials_card` gives every plan's card. `ColonyInventory.available`
    and `ItemDropManager.free_loose_count` count one good's unclaimed stock.
  - `data/ui/compact_panel.json` gives the tile its picture and hover text.
  - A plan of several goods names the goods still short in its status, without the count, so
    the line no longer runs out of room.
- **Tests:** in `ConstructionInputTest`, with real clicks:
  - the tile opens the card above the panel, lit, with the good's row;
  - a refresh keeps it open;
  - the tile closes it, and so does clearing the selection;
  - it fits at 960 × 540 and 1280 × 720.

  `BlueprintTest` checks a mixed plan's card rows, order, tags and footer.
  `ConstructionDevTest` now finds DEV finish by its id, since Materials comes first. The job
  gate passes (55/55), the construction tests pass (18/18), and the lint finds nothing new.
- **Checked in game:** a real click on Blueprint 7's tile in a copy of the autosave
  (`GoodsCheck.gd`, `built_card_*.png`) draws the card as the concept, at both sizes.

## Phases

1. **Mixed plans.** A plan holds several materials, with staging, start, building, refunds and
   saves per good. Build and Shapes are unchanged. Built on 2026-10-27.
2. **One project a placement.** Placing makes one plan; the panel, Cancel and Copy as above.
   Built on 2026-10-27. Done when:
   - the owner places the Log cabin and the Garden terrace and sees one crate and one panel
     for each;
   - the dwarves build them, corners and inside included (see "Boxed-in blocks, built");
   - Blueprint 7 shows one crate on the ground.
3. **Close.**
   - The rules move into docs 23 ("Copy and Blueprints" and the panel), 31 ("Stone
     construction") and 13 (saved orders).
   - Open items go to `00_todo.md`.
   - This doc goes.

## Not in this milestone

- **Builders' reach.** A builder works at most 5 blocks above the floor it stands on
  (`ConstructionController.stands_for`, `reach_up` in `blocks.json`), and nothing lifts it
  higher. From flat ground that leaves Blueprint 7's grass (120 blocks) and its logs above
  the fifth layer (59) out of reach, so even as one project its roof needs DEV: Finish
  construction. This is a separate question, raised with the owner on 2026-10-27.
- **A Build or Shapes plan that starts high,** such as a slab off a ledge, keeps today's crate
  search, 2 blocks up or down.
- More than one builder for each project (see "The owner's picks").
- Choosing the wood when placing a blueprint (doc 275, "Later").
- **The Blueprints card and the placing tag** still list each kind against the stock, so the
  Garden terrace shows "24 soil" twice against the same soil. The crate is right, but the card
  and tag can miss a shortage; they could count each good once.
