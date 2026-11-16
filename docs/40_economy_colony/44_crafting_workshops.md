# 44 — Crafting Workshops

**Copper nails (2026-11-16, doc 313):** the Carpenter's plank furniture is nailed (owner: "I want
to introduce copper nails that are made from a copper bar. Copper nails should be needed for
carpenter or other recipes where it makes sense. 1 copper bar perhaps makes 12 nails. nails
should follow the crate approach just like most food.").
- **Who makes them.** A Blacksmith hammers one copper bar into twelve copper nails on the anvil
  stone, in 12 s, under Crafters → Blacksmith → Metal. The recipe stands after the four tools,
  so the anvil stone's window still opens at the copper pick. A batch is one Blacksmith
  experience, as a bar or a tool is.
- **What takes them.** The seven plank pieces, a nail to each plank, as
  `additional_ingredients`: the Tool Rack and the Plank bench two; the Raw Materials Crate, the
  Finished Goods Pallet, the Food Shelf, the Plank Dining Table and the Board-game Table four.
  Nothing else does: a Worker's camp goods, the carpenter's bench, the fence and the gate, the
  stone pieces and the tools are all made before a nail can be, or without a board to fix.
  `CopperNailTest` fails when a plank recipe takes no nails or another recipe takes some.
- **A crate good.** `base:item:copper_nail` is kept 24 to a crate with low, half and full crates
  of its own, as produce and log torches are (doc 62, "Copper nails are kept 24 to a crate"): a
  batch lands as one crate, the
  next batch joins it, and a crate is one stockpile cell, one carry and one quarter of the
  finished goods pallet. It is stored as Metal. A crate of nails is a heavy load of 4 points,
  whatever it holds.
- **How a piece takes them.** One nail leaves its crate for each the piece needs, from the
  ground or from storage (`WorkerCraftOrder.take_planting_item`, `StorageComponent.withdraw_stack`);
  the crate stays where it is with the rest. A piece's nails are one load, so they come in a
  trip of their own, before the planks ("Trips", below, which also has the fix that lets a
  later trip find a fuller crate).
- **Words.** A fixed ingredient a recipe takes several of is counted in the item's own words
  (`CraftingManager.goods_words`, from the item's `plural_name`): the board heads
  "INGREDIENTS · 4 planks · 4 copper nails" and lists "4 copper nails · 12 available", and an
  order reads "Waiting for 4 copper nails". One of a good keeps its name alone ("Waiting for
  Rough stone"). A recipe's own good is worded the same way where the item names its plural:
  "Waiting for 1 copper bar", "Waiting for 3 rough stones".
- **The board at 1080p.** The nails' line made the pallet's and the food shelf's boards a line
  too tall, so their `purpose` is two lines now. `CraftingBrowserTest` says how many lines a
  board's words and ingredients take when one does not fit.
- **The models are unchanged.** The plank pieces' descriptions say nailed; their knot-dark pegs
  stand where the nails are (doc 64).

**The anvil stone (2026-11-14, doc 310):** the Blacksmith's second station, where a bar is
hammered into a tool (owner: "I think the smelter should not be that workstation, does the
blacksmith need another workstation?").
- **What it is.** One great stone, two cells broad, with its top split off level and nothing
  else done to it; no wood (the owner's pick of three ideas, B). 2 × 1, worked stone, its
  hammering face at the casting stone's height (0.9375).
- **Who makes it.** Blacksmiths, at the crude workbench from three Rough Stones (18 s), under
  Crafters → Blacksmith → Workshops; installed through Place → Workshops. So the Blacksmith has
  two stations made from raw goods: the basic smelter melts, the anvil stone shapes.
- **What is made on it.** All four copper tools (pick, saw, chisel, hoe): one bar and a log
  each, 12 to 14 s, no wait. Since doc 313, copper nails too: one bar into twelve. Nothing is
  hammered at the basic smelter any more: an order with a smelter but no anvil stone reads
  "Needs an anvil stone".
- **Why two stations.** A melting charge, and a set bar until it is taken off, holds the
  smelter (one batch a smelter). On the casting stone, tools and bars took turns; on the anvil
  stone a tool is hammered while the next bar melts.
- **Where the bar lies.** At the middle of the stone's left cell (`crafting_cell` [0, 0],
  `crafting_surface_radius` 0), where its face is pitted; the right end is a flank lump and is
  not worked. The Blacksmith stands in a free cell beside the left cell
  (`InstalledFurnitureComponent.work_stands`).
- **Until iron (owner, 2026-11-14:** "perhaps this work station can work for copper, bronze,
  etc... until the iron anvil arrives later"**).** The anvil stone is the hammering station for
  copper and for whatever else comes before iron; the Forge's forged anvil replaces it then.
  There is no bronze in the game yet.
- **Words.** A bench is named with its own article (`CraftingManager.with_article`): "Needs a
  mason's bench", "Needs an anvil stone". A tool's card says "A Blacksmith makes it at the anvil
  stone." (`DwarfAssets.tool_source_text`, from the recipe's workshop).

**The profession path (2026-11-13, doc 306):** the trades no longer all start from a Worker's
log and stone (owner: "it doesn't feel rewarding at all"). The rules are in doc 41, "The
profession path"; what changed at the benches:
- **The Blacksmith makes the other trades' tools** on the anvil stone (doc 310; at the basic
  smelter until 2026-11-14), under Crafters →
  Blacksmith → Tools: the copper pick (Miner), the copper saw (Carpenter), the copper chisel
  (Stonemason) and the copper hoe (Farmer, doc 309). Each is one copper bar and a log for its
  haft, hammered with the maul (14 s the pick and the saw, 12 s the chisel and the hoe).
  The crude carpentry kit, the crude masonry kit and the stone hoe are gone.
- **Rudimentary is the first camp.** The log bed and every log door are a Worker's again, at the
  crude workbench under Rooms (owner: "move the log bed and all log doors back to rudimentary").
  See "Rudimentary is the first camp" under Specialist workbenches.
- **Copper melts over a coal, or over two logs of one wood** when the colony has no coal, so a
  colony needs to find only copper. Copper fittings are gone (owner: "we'll just simplify this
  scenario and use copper bars"): what brewing was to take as fittings takes bars.
- **A choice of goods** is a recipe's `one_of` (`recipes.json`): `choices` lists them best
  first, each a list of exact item keys, and a batch takes the first the colony can supply whole
  (`CraftingManager.choice_keys`). The bar's fuel is a coal, then two pine, oak, juniper or
  applewood logs; a tool's haft is one log, pine first. They are fetched after the recipe's fixed
  ingredients and before its own goods, set down beside the bench like them, and used up with the
  batch.
  - **A batch keeps its choice.** A waiting order chooses again at every refresh; from the moment
    a dwarf takes the order or goods lie beside its bench the choice stays
    (`WorkerCraftOrder.settle_choice`), so a coal that turns up later is left alone. A save needs
    no new field: on load the staged goods say which choice was made
    (`CraftingManager.choice_matching`).
  - **Words.** An order with nothing to choose from reads "Waiting for a coal or two logs" or
    "Waiting for a log" (`one_of.words`); the recipe's card heads the goods "Fuel" or "Haft"
    (`one_of.label`), shows each with its stock and ticks the one the next batch takes.
  - **A tool keeps its haft's wood** ("Oak copper pick"): its own good is the bar, so the wood is
    read from the log beside the bench (`WorkerCraftOrder.capture_item_properties`).
  - **Logs feed the fire, not the pot.** In the charge, a log is turned end on, swung low and sent
    into the fire hole (`DwarfSmeltPose`, `WorkerCraftOrder.fire_goods`); a coal still goes into
    the pot with the ore.

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
- **A day on the rack.** The recipe's `batch_hours` (24) pass on the world clock while the
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
  at the workbench. A batch (a recipe with `batch_hours`) takes the workshop's
  `batch_crafting_motion` instead if it has one: the basic smelter's is "charge", while the
  tools hammered there keep the Blacksmith's maul (doc 300).
- **Charging the basic smelter** ("charge"; owner, 2026-11-12: "the blacksmith just moves in a
  weird way when adding the ingredients"). Until then the charge borrowed the rack's "hands":
  the Blacksmith stood in the boulder and raised empty hands to it twelve times, the ore at its
  feet.
  - **Where it stands.** `batch_fire_hole` is the fire hole's mouth, a point of the model in
    blocks. The charge is worked from the floor cell before it whenever a dwarf can stand there
    (`InstalledFurnitureComponent.fire_stand`, `work_stands`; the first-trip quote and the trip
    planner take their stands from `work_stands` too). With that cell taken or walled, any free
    side of the boulder serves, and the stick goes to the boulder's foot.
  - **A long step back.** The walk stops 1.3 blocks short of the stand's centre
    (`DwarfSmeltPose.STAND_REACH`, through `stop_short_of`): the boulder stands higher than a
    load is carried, and a crouch at its foot needs the room. With no walkable cell behind the
    stand the dwarf stops at the cell's edge and stoops, holding the stick steep. The trip's
    goods are set down at the stand, before the dwarf (`WorkerCraftOrder.placement_contact`).
  - **The work.** Each lump takes 13% of the work: the lump in hand first, then those set
    down. The Blacksmith bends to it, lifts it, swings and throws it into the pot. A log that
    feeds the fire (doc 306) is turned end on, swung back beside the knee and sent low into
    the fire hole instead. For the
    rest it crouches and blows on the fire through a hollow stick held to the fire hole, three
    breaths. Nothing is set down at the end: the work finishes as the last breath does.
  - **Goods never move.** The order checks where its goods lie, so a real lump stays put: it
    stops being drawn (its meshes' layers, never its `visible`, which is the item manager's
    for the slice) and a copy of it is thrown. A charge given up puts every lump on show again
    where it lay (`DwarfSmeltPose.release`, from the fetch teardown; Hard Rule 12).
  - **The words.** The dwarf's status reads "Charging the smelter", then "Blowing on the
    smelter's fire"; its explanation names the logs when the charge burns them.
  - **What is heard** (owner, 2026-11-13: "The basic smelter could use some audio as well when it
    is in action"). Each lump is heard landing in the pot (`smelt_toss`), each log going into the
    fire hole (`smelt_log`) and each breath as its blow starts (`smelt_blow`).
    `DwarfSmeltPose.cues` gives the work's marks from the numbers the pose draws by, so a sound
    comes as it is seen; `DwarfWorkExecution` plays each mark the work passes, once
    (`WorkFeedback.play_smelting`), and work taken up again replays none. The recordings are in
    doc 13 ("WorkFeedback").
  - The pose is cosmetic (`DwarfSmeltPose`): the order owns the 12 seconds.
- **A workshop's work spots.** A workshop of more than one cell may name where each kind of craft
  is worked, each a footprint-local `[x, z]` cell that turns with the piece: `batch_cell` for a
  batch, `crafting_cell` for everything else (and for taking a batch down). The dwarf stands
  beside that cell and reaches from its centre: `crafting_surface_height` and
  `crafting_surface_radius`, or `batch_surface_height` and `batch_surface_radius` for a batch
  (`InstalledFurnitureComponent.work_cells`, `CraftingManager.bench_surface`). A workshop that
  names no spot is worked from any side, as before.
- **Its window's action.** A piece is a workshop when a recipe names it as its `workshop`
  (`ContentRegistry.recipes_at`). Nothing in the piece's own file says what is made at it:
  the `crafting_recipe` line each workshop had named one recipe, the torch for the crude
  workbench, and the owner read it as all the bench made ("it can make more things",
  2026-11-15). It is gone.
  - **The action** is Craft items, or the piece's `crafting_action` (the rack's Dry fish, the
    smelter's Smelt copper, the anvil's Hammer tools). It opens crafting at the first recipe
    made there, on that recipe's page.
  - **Who crafts there** comes from the careers of all those recipes
    (`FurnitureWindow.get_explorer_data`). One career is named: "Any Ranger crafts here". The
    crude workbench serves five, Workers and the four trades that make their first station on
    it. The panel's tag has room for one short line, so its line counts them, "Workers and 4
    trades craft here", and its description ends with all five by name, which the panel shows
    on hover (its Crafter row names them too).
- **Its batch on show.** A workshop's `batch_model` is laid over it only while a dwarf works
  a batch there or a batch dries on it (`CraftingManager._show_batches`,
  `FurniturePlacementController.show_batch`):
  the fish hang on the drying rack while they dry, and an idle rack is bare (owner: "the
  drying rack should not display fish if no fish are drying").
  - **From when.** The order says (`WorkerCraftOrder.batch_showing`): fish hang from the first
    moment, and the basic smelter's coals and melt show once its whole charge is in the pot.
  - **Once finished.** A workshop with a `batch_done_model` shows that in place of its batch
    from the moment the batch is done until it is taken off: the basic smelter's coals go out
    and the bar shows in its mould (2026-11-12; until then the bar lay in the mould from the
    first second of charging). A workshop without one keeps its batch on show, as the rack
    keeps its fish.
  - **The smelter's fire is heard while its coals show** (2026-11-13). Its `fire_sound` is
    `smelter`, and a workshop with a `batch_model` burns only while that part is shown
    (`InstalledFurnitureComponent.batch_showing`, `FurnitureFires.burning`). So the fire starts
    as the last lump goes in, burns through the blowing and the four hours of melting, and stops
    when the copper sets. An idle smelter is silent.
  - **A batch taken off is heard as its recipe says** (`collect_sound`): the copper bar's is
    `smelt_bar`, played as the take-down ends and the bar lands beside the smelter
    (`WorkshopBatch.collect_sound`, `WorkFeedback.play_collect`). The drying rack names none.

**The dining table (2026-10-18; a plank table since 2026-11-13, doc 308):** Crafters →
Carpenter → Dining offers a Plank Dining Table for four matching planks, four copper nails
(doc 313) and 16 seconds at a carpenter's bench. Until 2026-11-13 it was the Log Dining Table, two matching logs (and
Rudimentary, at the crude workbench, until 2026-11-02; see "Specialist workbenches").
Its 3×3 footprint, its top a block and a half up and its stools' places are as they were
(doc 62 has its look). Pine, Oak, Juniper and Applewood follow normal material selection,
packed delivery, installation, Move and saving. Four separate stools fit
the displayed guides, one against the middle of each side, so table and four
stools together occupy 5×5. Stools are crafted independently (docs 231, 232); the
guides take log and stone stools alike (doc 293).

**Recipe categories (2026-10-13):** Each page groups items by their use, matching
the Place catalogue. Rudimentary: Workshops (the crude workbench), Lighting (log torch,
campfire), Access (ladder section), Dining (log stool), Rooms (log bed, the 2-wide, 3-wide and
double 4-wide doors; back from the Carpenter's page on 2026-11-13) and Starter tools (the
Ranger's kit and the stone hammer). The Carpenter's
page: Workshops, Timber (the four woods' planks, doc 308), Storage, Dining (plank dining table,
plank bench), Access (Log Fence Post and Log
Gate, one log and 10 seconds each, doc 198) and Recreation (the Board-game Table: four matching
planks, four copper nails and one rough stone, 18 seconds; two matching logs until 2026-11-13, doc 308). The Stonemason's page: Workshops, Dining (stone stool)
and Rooms (the hearth). The Blacksmith's page: Workshops (the basic smelter and the anvil stone), Metal (the copper
bar and copper nails) and Tools (the copper pick, saw, chisel and hoe).
Categories affect browsing and search only; a page lists them in the order its recipes first
name them.

**Rudimentary hearth (2026-10-11):** Crafters → Stonemason → Rooms offers a
rough fieldstone hearth (Rudimentary until 2026-11-02): two matching logs and four rough
stones, physically delivered to a mason's bench before 18 seconds of work. It emits 9600 heat units, tended so a room
never goes past 18°C (1600 until 2026-10-30, 2400 until doc 199; doc 34), and quiet fire
audio while lit. Unlike the other wooden
starter pieces it keeps no wood identity, whichever logs it used (its definition has no
`material_group`). Repeated ingredients appear as one quantity in the recipe detail. Fuel upkeep remains
future work (doc 122).

**Log bed cost (2026-10-11):** One bed requires four matching logs at the crude
workbench, under Crafters → Rudimentary → Rooms (the Carpenter's from 2026-11-02 to 2026-11-13). Every log is physically delivered
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
  them back in order. Packed crates keep their neutral art; a crate of log torches shows
  its wood (doc 62).
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

**Log furniture (2026-10-11):** Crafters → Rudimentary → Rooms offers 2/3-wide single log
doors and a 4-wide double log door (the Carpenter's from 2026-11-02 to 2026-11-13), and Crafters
→ Carpenter → Dining a bench (a log bench of one log until 2026-11-13; since then a plank
bench of two matching planks, doc 308, and two copper nails, doc 313). Each door uses one allowed timber at the crude
workbench, taking 12/18/24 seconds; the bench takes 10 at a carpenter's bench. Finished crates use normal haul/install work. The starter
wooden torch is renamed Log torch; its four-per-log recipe is unchanged (doc 117). Since
2026-11-15 its torches are kept 24 to a crate, and a batch lands as one crate (doc 62).

**Crafting menu (2026-10-11):** the profession cabinet uses compact category
icon groups, name/category search, and separate Recipes / Orders tabs. A single
selected-item card shows the illustration, real materials/stock, batch or stock
target controls, and Place. Pause, priority, cancellation and per-order wood
selection stay in Orders. Recipe costs, reservations and work are unchanged (doc 114).
The window was rebuilt on 2026-10-24; its current layout is "The crafting window" in
`23_user_interface.md`.

**No bridge kits (2026-10-27):** the Log bridge kit recipe was retired with the log
bridge; rivers are crossed on logs built from Build (doc 32, "River crossings").

**Carpenter promotion (2026-10-09):** A crafted crude carpentry kit (since 2026-11-13 a copper
saw from the Blacksmith, doc 306) enables
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
- **Sections** (`sections` in `recipes.json`: `display_name`, `planned`, preview and
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
workshop. Recipes live in `data/recipes/recipes.json`, loaded only by
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
  (Rough Stone for the starter tools, campfire, hearth and board-game table). A recipe's
  `one_of` goods, its fuel or its haft, follow them and are handled the same way (doc 306, at
  the top). The worker
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
    That holds for every trip of a batch. Until doc 313 the step that plans a later trip
    (`CraftIngredientPlanner`) saw only single goods, so an ingredient fetched second from a
    crate holding more than one (the game table's nails after its stone, a second fish out
    of reach of the first) read as unreachable and waited out a retry before the scheduler
    planned it again. All three quotes for a craft's goods now count a fuller crate.
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

**Starter tools implemented (2026-10-09):** Workers craft Ranger's kits and stone hammers at
the crude workbench. Each uses one allowed log and one Rough Stone, collected physically before
crafting. Until 2026-11-13 Workers also made stone hoes and the crude carpentry and masonry
kits; the other trades' tools are now copper and a Blacksmith's (doc 306, at the top). Tools
support normal hauling, storage and saving. The recipe card and profession
preview show current availability; the Farmer collects its hoe as the others do (doc 309). Tools are
ordinary goods in the Other goods storage category (`stockpile_misc`, with exact-item
filters) and Inventory's Tools group, never placeable. The Ranger's kit, a stone-tipped
spear bound to a peeled fishing rod, replaced the hunting spear on 2026-11-01 (owner,
doc 292). Its line is drawn, not an ingredient, so it needs no cord or leather; bows
are later equipment.

**Agreed equipment direction (2026-10-09, planned):** crafted tools will support
selected profession requirements and later upgrades. The Miner promoted freely with the
default pickaxe until 2026-11-13 and now takes a copper pick (doc 306); the iron pickaxe is
the next planned mining-tool upgrade.
Workers must be able to craft the crude tools needed to establish the first
specialists (the Ranger and the Blacksmith) without circular recipe dependencies. The starter recipes above
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

From the owner (2026-11-01): "each will have to craft their starting workbench, later as better
tools become available they will be able to craft more advanced workbenches". A career's first
workbench is made by that career alone at the crude workbench from raw goods, as Rangers make
the drying rack. The same holds for every career to come (the Farmer, the Brewer): no bench
waits on another career, though better benches may take other careers' goods (iron tools,
planks, dressed stone). Since 2026-11-13 a career's *tool* may wait on another: the Miner's,
the Carpenter's and the Stonemason's come from the Blacksmith (doc 306; doc 41, "The profession
path"). Built for the Carpenter and the Stonemason (doc 293):
- **The pages.** Crafters → Carpenter and Crafters → Stonemason are live sections
  (`recipes.json`), laid out as the Rudimentary page with no `later` box (owner,
  2026-11-01: "I can't think of a reason why it would not look the same as the rudimentary
  crafting page"). Each career makes only its own page. A recipe's
  `section` names the career that makes it; with none in the colony its order reads "Needs a
  Carpenter" or "Needs a Stonemason".
- **Rudimentary is the first camp (owner, 2026-11-02:** "Rudimentary was supposed to be
  initial surviving"**; 2026-11-13:** "move the log bed and all log doors back to
  rudimentary"**).** Workers with an axe make what a camp lives on before it has a trade: the
  crude workbench, light (log torch, campfire), a way down (the ladder), a seat (the log
  stool), a bed (the log bed), every log door (2-wide, 3-wide and double 4-wide), and the two
  tools no trade can make for itself, the Ranger's kit and the Blacksmith's stone hammer.
  - **Why the bed and the doors came back.** From 2026-11-02 they were the Carpenter's, when
    a Carpenter cost a log and a stone. A Carpenter now waits for copper, which can take a long
    dig to find, so a bedroom (bed, door, light) is a Worker's work again.
  - **The Carpenter** makes the rest of the wooden furniture at the carpenter's bench: storage
    (the tool rack, the raw materials crate, the finished goods pallet, the food shelf), the
    dining table, the bench, the fence post, the gate and the board-game table. The dining
    table and the bench are plank pieces made from planks since 2026-11-13; the others follow
    as their plank looks are picked (doc 308).
  - **The Stonemason** makes the stone stool and the hearth at the mason's bench: the hearth's
    fire-back is one split boulder, and the piece split from it is the hearthstone. So a warm
    bedroom still needs a trade, and a colony's first nights are spent by the campfire or in a
    cold room.
- **The carpenter's bench:** three matching logs, 16 s, Workshops. A thick slab hewn flat on
  top and peeled, one end let into a stump with its bark on, the chopping block, the other on
  two peeled legs (doc 62; the owner's pick, 2026-11-10), 3 × 1 with its work top at 1.125. Its
  wood recolours it like other log furniture.
- **The mason's bench:** a log and three Rough Stones, 18 s, Workshops. A split stone slab on
  two log stumps, 3 × 1 with its work top at 0.9375; the slab is worked stone (doc 64, "Stone
  is drawn as wood is") and the bench takes no wood (no `material_group`).
- Both install through Place → Workshops. Goods worked on either lie on the slab where it is
  nearest the worker, `crafting_surface_inset` (0.4375) inside its edges, so even a Rough Stone
  never overhangs it (`CraftingManager.bench_surface`); the round stump keeps
  `crafting_surface_radius`, 0.5 since its top narrowed (doc 301).
- **The stone stool** (step 3): Stonemasons make it at the mason's bench from one Rough Stone
  (10 s, Dining; the recipe's `ingredient_tag` is `stockpile_stone`, the Rough Stone alone, with
  stone's `ingredient_words`). Without a mason's bench its order reads "Needs a mason's bench".
  The Rough Stone itself lies on the slab while the maul knocks it square.
- **The tool rack** (doc 294): the Carpenter's first goods. Carpenters make it at the
  carpenter's bench from two matching planks and two copper nails (12 s, Storage; one log until
  2026-11-13, doc 308; nails since doc 313);
  without a carpenter's bench its order reads
  "Needs a carpenter's bench". It keeps three of the colony's tools (doc 31, "Storage priority
  and storage furniture").
- **The raw materials crate** (doc 294): Carpenters make it there from four matching planks and
  four copper nails (16 s, Storage; two logs until 2026-11-13, doc 308), and it keeps their wood. It holds twelve raw goods: Rough Stone, the ores and coal,
  and soil (doc 62).
- **The finished goods pallet** (doc 296): Carpenters make it there from four matching planks and
  four copper nails (16 s, Storage; two logs until 2026-11-13, doc 308), and it keeps their wood.
  Each of its four quarters holds one piece of packed furniture, three copper bars (owner,
  2026-11-12), a crate of up to 24 copper nails (doc 313) or four planks (doc 62). A crate of up
  to 24 log torches is one such piece (2026-11-15).
- **The food shelf** (doc 299): Carpenters make it there from four matching planks and four
  copper nails (16 s, Storage; two logs until 2026-11-13, doc 308), and it keeps their wood. It holds six crates of food on two decks (doc 62; doc 42, "Spoilage").
- The benches' Craft items open what is made at them, at the first recipe on the page: a plank
  at the carpenter's bench, the stone stool at the mason's bench ("Its window's action").
- **The basic smelter** (doc 297; reworked in doc 300): the Blacksmith's starter bench, made by
  Blacksmiths at the crude workbench from a log, four Rough Stones and a Soil (20 s, Workshops;
  one Soil, not two, so the recipe's board still fits a 1080p screen). It is one great stone,
  two cells broad, knocked hollow, a stone pot in its top and a fire hole in its foot (1.5
  blocks), beside a casting stone on two log rounds at bench height (0.9375), 3 × 1 in all and
  built as worked stone (doc 301); no clay (owner: "we don't have
  clay … keep it rudimentary"). Crafters →
  Blacksmith holds it, copper bars and the trades' copper tools (doc 306); the page's `later`
  box says the Smelter and the Forge come with iron.
  - **Copper bar:** two copper ore (the recipe's `ingredient_tag` is `copper_ore`, so no other
    ore) over a coal, or over two logs of one wood when the colony has no coal (the recipe's
    `one_of`; owner, 2026-11-13). The ore, and the coal with it, are thrown lump by lump into
    the boulder's pot, logs are pushed into the fire hole, and the fire is blown on through a
    hollow stick, 12 s in all, from before the fire hole (never hammered: owner, 2026-11-09; see
    "Charging the basic smelter" above). The charge then melts for `batch_hours` (4) on the world
    clock, as fish dry on the rack, heating the room meanwhile; then a Blacksmith takes one bar
    off the casting stone in `collect_seconds` (4). One batch a smelter; the window's row and
    the crafting list say Melting, from the recipe's `batch_words`.
  - **The trades' tools** (doc 306): one bar and a log hammered into a copper pick, saw,
    chisel or hoe, 12 to 14 s, no wait. Since 2026-11-14 that is done on the anvil stone (doc
    310, at the top of this doc), not on the smelter's casting stone. The
    bar is the good worked on the stone; the log is its haft and gives the tool its wood.
    Copper fittings, which a bar was hammered into until 2026-11-13, are gone: the brewery and
    the aging cellar will take bars.
  - **Practice:** each batch is one Blacksmith experience, a tool as much as a bar; iron will
    need level 2 (10 batches).
  - **Storage:** bars are `stockpile_metal`, the Metal category under Materials.
    The finished goods pallet takes them, three to a quarter, ahead of a Metal zone on the
    ground (owner, 2026-11-12: "the copper bars, a finished good, is not able to be stored on
    the finished goods pallet"). The tools are tools: the tool rack takes them.
  - **The Blacksmith** is promoted with a stone hammer, crafts and collects before the common
    work, and swings the stone maul at the anvil stone with a hammer's knock. Blowing on the
    fire through a hollow stick after the charge is planned (doc 300, step 2).
- **Planks** (owner, 2026-11-13, doc 308: "the carpenter starts with a saw, therefore I think
  the initial set of items the carpenter can make don't need to be rudimentary anymore").
  - **A Carpenter saws one log into two planks of its wood** at the carpenter's bench, in 10 s.
    Each wood has its own recipe under Crafters → Carpenter → Timber (pine, oak, juniper and
    applewood planks), so an order always gives that wood's planks and "keep 8 oak planks" counts
    oak alone. A sawing recipe's `ingredient_tag` is its log's own tag (`oak_log`), which only
    that log carries.
  - **A plank is a good of its own:** `base:item:<wood>_plank`, tagged `plank`. It is
    never `timber`, so no fire burns it and no log recipe takes it. It gives what is made from
    it its wood (`CraftMaterials`, each wood's `ingredients`), as its log does.
  - **Storage:** Planks is a storage category (`stockpile_plank`, Materials). Ground storage
    takes it, and the finished goods pallet takes planks four to a quarter, ahead of the ground.
    New ground storage accepts every category in `storage_filters.json`
    (`StockpileZoneComponent.DEFAULT_FILTER_TAGS`; Metal had been left out of that list until
    2026-11-13, so a new zone refused copper bars).
  - **Plank furniture** takes planks of one wood (`ingredient_tag` `plank`, worded by the
    recipe's `ingredient_words`) and wears the Tier 2 look (doc 64). Since doc 313 it also takes
    a copper nail to each plank ("Copper nails", at the top of this doc). It costs the planks of
    the logs its log form cost, carries one more point of appeal than that form did, and keeps
    its key, so a colony's pieces change look and its save keeps loading. The first two
    (owner's pick, 2026-11-13): the Plank Dining Table, four planks, and the Plank bench, two.
    Then, from the second sheets the same day: the Tool Rack (two planks), the Finished Goods
    Pallet (four), the Board-game Table (four and its Rough Stone), the Raw Materials Crate
    (four) and the Food Shelf (four). The fence and the gate stay logs, a log each: a rail
    fence is split, not sawn (doc 64, "Field work stays hewn").
    A piece changes over when its plank look is picked; doc 308 has the list. The carpenter's
    bench stays hewn: it is made from logs before any plank exists, and planks are sawn on it.
- Dressed stone waits for the Stonemason's turn (owner, 2026-11-13: "Stonemason later"), and
  the advanced benches for iron tools.

**The ladder.** Both careers climb the same rungs. The upper two are planned, and the advanced
benches' names are suggestions:

| Rung | Carpenter | Stonemason |
|---|---|---|
| Tool (a Blacksmith makes it on the anvil stone; docs 306, 310) | Copper saw, a pull saw | Copper chisel, with its hammerstone maul |
| Starter bench (the career makes it at the crude workbench, from raw goods) | Carpenter's bench | Mason's bench |
| Better tool (from the Blacksmith) | Iron saw | Iron chisels |
| Advanced bench (made with that tool) | Joiner's bench: fine joinery and carving, chests and barrels, framed doors on iron hinges (planks and the plank look came with the copper saw, doc 308) | Carver's bench: dressed stone, Build's dressed blocks, carved stone and finer doors |

- **The first rung was a Worker's kit until 2026-11-13:** a crude carpentry kit (a wooden mallet
  and a stone adze) and a crude masonry kit (a hammerstone maul and a stone point).
- **Rough work still** (doc 64, "Furniture tiers"). With copper tools the two trades make the
  same hewn and knocked goods as before; planks and dressed stone stay held (owner, 2026-11-13,
  agreeing to "today's goods for now"). Whether copper or iron brings them is open
  (`00_todo.md`, "The profession path left for later").
- **The tool gates the finer work.** A recipe will name the tool its maker must hold, the
  advanced bench and that bench's own recipes alike, so their orders wait "Needs a Carpenter
  with an iron saw".
- What is left to build is in `00_todo.md` ("The Stonemason and the Carpenter left for later").

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

**Reversed on 2026-11-13 (doc 306).** The owner chose the dependency this review avoided: the
Carpenter does start with a saw, a copper one, and it does need a Blacksmith first. No circle
results, because the Blacksmith's hammer and smelter need no Carpenter goods (the paragraph
below still holds), and the bed and the doors went back to Workers so a camp does not wait on
copper to sleep indoors.

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

Full schema: `data/furniture/smelter.json` *(to be created; a workshop is a furniture piece)*.

**Status:** the smelter is planned. There is no smelter furniture definition or
placed model in the game yet, and none of the production behavior in this
section is live.

**The basic smelter comes first (owner, 2026-11-02; built, doc 297).** The Blacksmith's starter bench is a
**basic smelter** made from raw goods at the crude workbench (see "Specialist workbenches").
It smelts copper ore with coal into copper bars, and the Blacksmith practises on copper before
iron (owner: "the blacksmith might have to practice first on copper bars"). This Smelter
becomes the advanced bench for iron, which needs Blacksmith level 2. Tin waits for it. No
bronze yet. The planned tables below still say "ingot"; these goods are bars.

### Placement

- Footprint: **2×2 floor cells, 3 blocks tall**, including the chimney (approved art design, 2026-10-03).
- Requires three clear air blocks above each of its four floor cells. The adjacent operator position also needs the standard 3-block dwarf clearance (see `32_navigation_3d.md`); no outdoor chimney/exhaust rule is implemented.
- Produces heat: a Smelter in operation counts as **800 heat units** for the temperature system in its enclosing room (see `34_temperature.md`). A Smelter left running in a shallow aging cellar will ruin the temperature balance — keep it in a dedicated room.

### Smelting Recipes

Coal is consumed as fuel in every smelting recipe. It is never a product and cannot be smelted itself.

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:smelt:iron_ingot`   | 2× iron ore + 1× coal   | 2× iron ingot   | 1 h | 1 |
| `base:recipe:smelt:copper_ingot` | Moved to the basic smelter (doc 297): 2× copper ore + 1× fuel → 1× copper bar | | | 0 |
| `base:recipe:smelt:tin_ingot`    | 2× tin ore + 1× coal    | 2× tin ingot    | 1 h | 1 |
| `base:recipe:smelt:silver_ingot` | 2× silver ore + 1× coal | 1× silver ingot | 1 h | 2 |
| `base:recipe:smelt:gold_ingot`   | 2× gold ore + 1× coal   | 1× gold ingot   | 2 h | 3 |

> **Design note:** Gold and silver ingots have no combat application — they are luxury goods. Gold ingots are the highest-value item a merchant will buy (above gems, by unit weight). The Blacksmith who can smelt gold is a direct economic asset.

Silver and gold ingots need base trade values (see the planned price table in `51_visitors.md` § Pricing). Exact values TBD in the trade balance pass.

---

## The Forge

`base:workshop:forge`

The Forge turns ingots and other materials into finished goods. Blacksmiths work every Forge recipe: general goods, weapons and armour. A single Forge serves the whole colony — build additional Forges only when throughput is a bottleneck.

Full schema: `data/furniture/forge.json` *(to be created; a workshop is a furniture piece)*.

**Before the Forge: the anvil stone (doc 310).** Until iron, bars are hammered on the anvil stone
(at the top of this doc), into tools and into copper nails (doc 313): copper today, and whatever else comes before iron (owner, 2026-11-14:
"perhaps this work station can work for copper, bronze, etc... until the iron anvil arrives
later"). The Forge's forged anvil is the better bench that replaces it.

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

Copper nails are in the game already (doc 313, at the top of this doc): twelve from a copper bar
on the anvil stone, taken by the Carpenter's plank furniture. This table's iron nail is still a
plan; when iron arrives, decide whether it replaces the copper nail or stands beside it.

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
- **Copper and tin uses** — copper bars make the trades' tools and the Carpenter's nails on the anvil stone (docs 306, 310, 313) and are what brewing and water infrastructure will take (there are no copper fittings: owner, 2026-11-13); tin ingots have no recipes yet and are a placeholder for future systems such as food preservation vessels. Do not delete them from the smelting table.
- **Support pillars** — `43_mining_materials.md` notes a future support pillar mechanic. Iron or copper ingots are the likely material input when that system is designed.

---

*Prev: [43_mining_materials.md](./43_mining_materials.md) | Next: [51_visitors.md](../50_world_events/51_visitors.md)*

## Bench motions

Each crafting career has its own motion at the bench, named by `craft_motion` in `professions.json` and
shaped in `DwarfFellingPose.BENCH_MOTIONS`: the Carpenter's adze stroke, the Stonemason's tap and the
Blacksmith's hammer blow. All share the Worker's swing timing, so work time and sound are unaffected.
