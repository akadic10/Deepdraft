# 289 — Fishing

2026-10-31. All three steps built: the lake, every water (with seasons, Wisdom and sounds)
and the drying rack. The owner's look in Play is next. Concepts drawn and picked (below).
Since 2026-11-01 only Rangers fish and dry, and Dried fish is on the Ranger's page
([292](292_ranger.md), step 2); where this doc says Workers fish or dry, read Rangers.

From the owner: "when Stonehearth was abandoned by its developers, an ACE mod introduced
things like fishing, does that fit our game". Shown an approach, the owner took every
recommended pick: "Write it up".

Workers fish the lake, the river, the tarn and the spring cave from a Fishing zone. Each
water holds a limited stock of fish that grows back slowly. Fish are a second food after
fruit, they spoil quickly, and they give a colony a way to stock up for winter.

## What is there

- **The waters are known.** `WorldGenerator` keeps the lowland lake and tarn footprints
  (`lake_columns`, `tarn_columns`, and `water_bodies` with each body's floor and waterline),
  the river (`river_layout`: route, columns and pools) and the spring cave's water
  (`spring_cave.water`). `WaterManager.depth_at` gives any cell's live depth. Water is
  finite, and only the spring adds more (doc 33). Ducks swim on it (doc 45); nothing else
  uses it.
- **Food is data.** An item's `food` block (`edible`, `nutrition`, `keeps_days`, `serving`)
  makes it a meal. Fruit is the only food: every kind fills 0.6, so one is a portion, and
  five dwarves eat 15 portions a day (doc 41, doc 282).
- **Spoilage follows temperature** (doc 42, "Spoilage"). Food that keeps 2 days at 20°C,
  as elderberries do, keeps about 5 in a valley larder and 10 in the cellar under the summit.
- **Winter food is open** (doc 282, "Open"). A start has about a twentieth of the food a
  winter needs. The owner (2026-10-29): dwarves stock up for winter, and hunting comes later.
- **The pieces it reuses:** Labor's permissions (`work_permissions` in professions.json),
  work sources and leases (doc 31), Storage zones (`StockpileDesignationController`),
  crafting's Keep in stock, hauling, and log decks built over water (doc 32, "River
  crossings"), so a jetty needs nothing new.
- **Wisdom does nothing yet.** Doc 41 plans it for yields.

## Where the idea comes from

- [Stonehearth ACE](https://steamcommunity.com/games/253250/announcements/detail/1700570870642830419),
  the Authorized Community Expansion, carried Stonehearth on with Team Radiant's blessing.
  Its fishing came from a companion mod,
  [Fisher Job + Archipelago Biome](https://catalogue.smods.ru/archives/20069): a Fisher works
  from zones drawn at the water's edge, or from docks, with traps, lures, crabs and oysters.
- RimWorld's Odyssey ([Fishing zone](https://rimworldwiki.com/wiki/Fishing_zone)) keeps one
  fish population per body of water. Each catch lowers it, it regrows 2.5% of its maximum a
  day, and a low population fishes worse. Fishing later got its own work type.
- Not taken: a Fisher profession, lures, traps and rare catches.

## Decisions (owner, 2026-10-31)

1. **A Fishing zone** in Zones, beside Storage, painted on shore cells beside water. Not a
   placed jetty piece, and not an Orders tool with a count.
2. **Any dwarf may fish,** under a new **Fish** permission in Labor, not under Gather.
3. **Keep N fish.** Each zone has a target, 20 by default, as crafting has Keep in stock.
   Fishing pauses once the colony stores that many fish.
4. **A stock for each water,** set by its size: about 200 in the lake, 80 in the river, 60
   in the tarn and 20 in the spring cave on a typical map. Each regrows 3% of its maximum a
   day, and bites slow as it falls. Water the player makes holds no fish. Drained water
   can't be fished until it fills again.
5. **One fish for each water:** perch in the lake, trout in the river, char in the tarn and a
   pale cave fish in the spring cave. A fish is one portion (0.6, like fruit) and keeps 2 days
   at 20°C. Dwarves eat it raw until there is cooking.
6. **Seasons:** bites come quickest in spring and autumn, and at half speed in winter. Water
   doesn't freeze.
7. **Wisdom speeds fishing,** 6% a step as Strength and Wits speed their work. It becomes
   Wisdom's first live work: "Fishes 6% faster".
8. **A drying rack** (Tier 1) turns fresh fish into dried fish that keeps a season.

## Concepts (2026-10-31)

Drawn over a copy of the owner's colony (scratch in `tmp/fishing_concepts_20261031/`):
three formats for the zone's card, two looks for the fish, the fish in crates, and the rod
with four frames at the lake.
- **The card: A · Zone window** (owner: "A · Zone window"). The zone opens its own window,
  as Storage does. B (a compact card, as a deer shows) and C (the lake's own window) were
  not taken.
- **The fish: A · Chunky,** the recommendation, which matches the chibi wildlife: a big
  head, a bead eye, a short deep body and a fan tail. B · True to life was the other look.
- **The rod and pose:** a peeled sapling rod with rope lashings and a red-tipped float, Tier
  1 with no iron; the frames are cast, wait, bite and land.

## How it plays

- **Zones → Fishing.** Drag along a shore. A cell takes if a dwarf can stand on it (dry ground
  or a built deck, with three blocks of headroom, Hard Rule 4) and fishable water lies in
  front of it: at least half a block deep, in one of the generated waters. Each cell is a
  spot for one fisher. Cells over water, under it, or beside water no one has found are
  refused with the reason on the tool's tag.
- **The zone's card** names its water ("Lowland lake"), shows the stock as a word (Plenty,
  Some, Few, Fished out) with the count on hover, as hit points show theirs, and has the
  Keep N stepper and the fishers at work.
- **Fishing.** A dwarf allowed to fish walks to a free spot, faces the water and casts. The
  rod is held as the axe and the pick are, with a line and a float on the water. A bite
  tugs the float, the dwarf lands the fish, it drops at their feet, and they cast again.
  Haulers carry the catch to storage as they do fruit.
- **Stopping.** The zone posts no work while the colony stores Keep N fish or more, or while
  its water is Fished out: below a tenth of its maximum. Fished from a tenth, a water is full
  again in about 30 days, so a lake fished hard in autumn is back by the end of spring.
- **Eating and keeping.** Hungry dwarves eat fish from storage as they eat fruit, served
  whole on the table. A cool larder or cellar keeps them longer, as it does fruit. Dried fish
  (step 3) last the winter.
- **The cave fish** live only in the spring cave's water, so a colony fishes them once it has
  dug into the cave. The zone tool can't mark what the colony hasn't found (Hard Rule 11).

## The numbers (to tune in play)

- **Stocks** come from each water's surface area, tuned so a typical map gives the figures in
  decision 4. Together they regrow about 10 fish a day: two thirds of five dwarves' 15
  portions, a side dish for thirty.
- **A catch** takes about an hour of game time for an Average dwarf on a full water in spring
  or autumn, with a small seeded spread. Summer is a little slower, winter half speed, and a
  water near Fished out takes about three times as long.
- **Wisdom:** each step from Average is 6% (`per_step`), so Excellent fishes at ×1.12.

## How it will be built

- **`FishingSystem`** (a scene system, like the Storage controller) owns the zones and the
  stocks. It is the zones' work source: it posts one FISH lease for each free spot while its
  zone wants fish. It saves and restores both.
- **The waters** take ids from generation: `lake`, `tarn`, `river` (its pools included) and
  `spring_cave`. A cast cell belongs to the water whose footprint holds it (the lake wins
  where the river meets it) and must be deep enough right now.
- **`Task.Type.FISH`**, appended, with its own priority in `task_config.json`; the `fish`
  permission lists it. `DwarfWorkExecution` times the catch as a new `fishing` kind, sped by
  `work_rate`. Landing spawns the fish at the dwarf's feet and takes it from the stock.
  Releasing ends the cast and loses nothing (Hard Rule 12).
- **Data:** a `fishing` section in `task_config.json` (stock per surface cell, regrowth,
  the Fished-out share, catch times, season factors, the Keep N default); the fish and dried
  fish in `resources.json` (food, `stockpile_food`); the permission in `professions.json`;
  Wisdom's `work` and `does` in `stats.json`; the Zones entry in `dock.json`.
- **Saves:** each water's stock and the day it last regrew, and each zone's cells and Keep N.
  Fish are ordinary items and spoil as fruit does. A dwarf mid-cast at a save casts again
  after loading. Saves from before step 1 won't load: start a new world.

## Art and sound

Hearthblock, through the usual pipeline (doc 61), concepts first:
- the four fish, as goods and as a serving (`serving_fish`), and later dried fish;
- the rod in the hand, its line and float, and the pose: cast, wait, bite, land;
- pictures for the Fishing zone and the Fish permission;
- the drying rack (step 3), a Tier 1 log frame, designed with doc 62's rules.

Sounds: the cast, the float's plop, the bite and the landing, recorded and free to use,
like the other work sounds (doc 13, WorkFeedback).

## Built: step 1 (2026-10-31)

- **In play.** Zones → Fishing paints teal spots along a shore. The tool bar names the tool
  with its keys; while dragging, its tag counts the spots, and over a cell it refuses it says
  why ("No fishable water in front", "Fishers stand on the shore, not in the water", ...).
  View and Undo work as for Storage. A click on a zone, with the tool on or off, opens its
  window (concept A): the lake and its perch, the stock as a word, a count and a bar
  ("Plenty · 153 of 154" in the capture), how fast it regrows and where Fished out starts, Keep with − and + and how many perch the colony keeps,
  who is fishing, and Remove zone. Labor has a Fish column. A dwarf allowed to fish walks to a
  free spot, casts, waits, feels the bite and lands a perch at its feet; haulers store it
  and dwarves eat it raw.
- **Code.**
  - `FishingSystem` (a scene node in `debug_world.tscn`, among the object explorer's click
    tools): the tool, zones and their overlay, the lake's stock, the leases, the catch, the
    `fishing` save section (priority 35) and the window.
  - `FishingSpot` (one per spot): a surface work source, so the surface matcher and the
    felling executor run it.
  - `FishingZonePanel`: the window.
  - `DwarfFishingPose`: the rod, line, float and caught perch across one catch;
    `DwarfWorkExecution` makes one catch one pose cycle and resumes a released cast where
    it was.
  - `Task.Type.FISH` joins `SURFACE_WORK`; the dwarf inspector says "Fishing".
  - Storage zones and furniture refuse fishing spots, and the fishing tool refuses theirs.
  - `SaveSnapshotValidator` checks the new section.
- **Data:** task_config's `fishing` section and FISH at priority 42 (above hauling, below
  player-marked gathering); perch in `resources.json`, crated 24 to a crate like fruit; the
  Fish permission; the Zones entry and the tool bar's keys.
- **Art (Hearthblock, look A):** perch crates at three fills, the fish serving, the rod, float
  and caught perch, the Fishing zone picture and the perch's inventory picture.
- **As built in the owner's world:** the lake's 12,844 columns hold 154 perch, regrowing about
  5 a day and Fished out below 16. A catch takes about 25–35 seconds at ×1 (an hour of game
  time, give or take a fifth).
- **Tests:** `FishingTest` (new `fishing` area): the spot rules, a zone's leases, a real
  dwarf's catch landing at its feet and coming off the stock, the rod in the hand, a release
  mid-cast, Keep, Fished out, regrowth, the window, Undo and saves. `DwarfFoodTest` and
  `ItemArtTest` count perch among the goods. Gate 55/55, the lint clean; `ShrubPilotTest`
  fails as it did before this work.
- **Seen in the game:** a capture over a copy of the owner's colony (`tmp/fishing_step1/`): the
  dock's tool and a real drag made a five-spot zone, Runbrin fished a catch through all four
  frames, the perch landed, the lake went from 154 to 153, and the window showed it.
- **Saves:** saves from before step 1 have no `fishing` section and won't load.
- **Not yet:** seasons, Wisdom and sounds (step 2), any water but the lake.

## Built: step 2 (2026-10-31)

From the owner, after a playtest at a river: "how do we fix this?", then "proceed with the next
step then".
- **Every generated water has fish.** The lake gives perch, the river trout, a mountain tarn
  char and the spring cave's pool pale cave fish, the pool once the cave is found (Hard Rule
  11: a hidden cave's water is rock to the tool). A cast cell belongs to the lake, then the
  tarn, then the pool at its own depth, then the river, so where two meet the first wins. A
  zone keeps to one water; its window names that water and its fish.
- **Banks:** a spot reaches water from its feet down to four blocks below them
  (`bank_drop`), since rivers run in channels, but never through ground.
- **Honest refusals:** "No water in front", or "This water has no fish" for water the colony
  dug or flooded, in place of step 1's "No fishable water in front".
- **Seasons:** bites come at full speed in spring and autumn, ×0.85 in summer and ×0.5 in
  winter (`season_speed`).
- **Wisdom** is fishing's stat: 6% a step, "Fishes 6% faster" on the sheet. It is Wisdom's
  first live work.
- **Sounds:** the float's plop, the bite and the landing (`fish_plop`, `fish_bite`,
  `fish_land`), each its own name so one never silences the next. They reuse the recorded
  duck splashes, so nothing new was downloaded. A cast's whoosh would need a recording.
- **As built:** in the owner's earlier world the river's 4,029 columns hold 121 trout. Tarns
  run about 900 columns (60 char at 0.067) and the spring cave's pool 31–37 cells (about 20
  cave fish at 0.6).
- **Code:** `FishingSystem.water_of_cell`, `_cast_cell` and `_wet_cell`, each water's size,
  `season_speed`; `FishingSpot.item`; the pose hangs the catch's own fish
  (`DwarfFishingPose.catch_item`, `DwarfAssets.caught_fish`); `DwarfWorkExecution` names the
  work "fishing" for Wisdom and plays the three cues; `WorkFeedback.play_fishing`.
- **Art (look A):** trout, char and cave fish crates at three fills, each fish on the line and
  each one's inventory picture.
- **Tests:** `FishingTest` adds a river channel under a high bank, water the colony dug, each
  water's fish and their order, the three sounds, seasons and Wisdom. `DwarfFoodTest` counts
  nine edible goods and `ItemArtTest` 60 / 98. Gate 55/55, the lint clean; the fishing, ui,
  flora, saves, art, dwarves, storage, furniture, rooms, audio and wildlife areas pass but for
  `ShrubPilotTest`, which failed before this work.
- **Seen in the game** (`tmp/fishing_step1/river_*.png`, over a copy of the owner's earlier
  colony): a real drag made a zone on a bank two blocks above the river, Runbrin fished a
  trout, and the river went from 121 to 120. The tarn and the cave pool are covered by the
  test only.
- **Saves:** the `fishing` section is unchanged, so step 1 saves load.

## Built: step 3 (2026-10-31)

From the owner: "Build step 3".
- **The rack.** Craft → Rudimentary → Food → Drying Rack: two matching logs and 12 seconds
  at a crude workbench. Place → Food → Drying rack puts it down, 2×1, worked from either long
  side. Both menus first filed it under Workshops; after a look in Play the owner moved it:
  "the drying rack is not a workshop, can we move it into some kind of food category". The
  rack stands bare; its three dried fish hang on it only while a Worker dries a batch there
  (owner: "the drying rack should not display fish if no fish are drying"; the
  `parts/drying_rack_fish` part, doc 44 "Its batch on show"). Its Tier 1 design is in doc 62: two forked bark posts with a peeled pole
  lashed into the forks and three dried fish hanging from it. Its window's action is Dry
  fish, which opens the recipe.
- **Dried fish.** Rudimentary → Food → Dried fish: two fresh fish of one kind (perch, trout,
  char or cave fish) make two dried fish in 12 seconds at a rack. A dried fish is a portion,
  keeps 30 days at 20°C (longer kept cool) and is stored as food. The Worker hangs the fish
  by hand, with no axe and no chop.
- **The goods' own words.** The order waits "for 2 matching fish" or "for 2 perch", never for
  wood. The board shows the four fish, "A batch is two fish of one kind" and "Click a fish to
  allow it"; a Worker on the way is "Carrying fish to the rack".
- **The catch dries where it lies.** A fisher's catch lands in one crate at their feet. A
  Worker takes the fish out one at a time, as a cutting leaves its crate, and both fish of a
  batch go in one trip, as a hauler carries a crate. Before this, crafting took only single
  loose goods, so an order beside a crate of fish said "Waiting for a reachable route", and
  each fish cost a whole trip (its carry cost is a crate's). Both rules hold for any good in
  crates (doc 44, "Trips").
- **Code:** `CraftingManager.ingredient_words` and the goods' words in its waiting reasons
  and statuses, which `WorkerCraftingPanel` reads; craft quotes and reservations take loose
  crates; `WorkerCraftOrder.take_planting_item` (one unit out of a crate), `_load_with` (a
  crate's load a kind) and `work_motion`; for "hands", `DwarfWorkExecution` skips the axe and
  the chop and `DwarfCarryWork` holds the goods at the crossbar; `FurnitureWindow` takes a
  workshop's action from `crafting_recipe` and `crafting_action`, the workbench's included.
- **Data:** `drying_rack.json`; the rack's and the dried fish's recipes in
  `worker_crafting.json` (dried fish: `ingredient_tag` "fish", `ingredient_words`, the Food
  group); the packed rack and dried fish in `resources.json`; the Place entry; the
  workbench's `crafting_recipe`.
- **Art (Hearthblock):** the rack and its Place picture; dried fish crates at three fills, the
  dried fish serving and its inventory picture.
- **Tests:** new `FishDryingTest` (fishing area): the rack's recipe and window, the fish words,
  a batch of one kind, hands with no axe, two dried fish, and a crate's fish taken out one at
  a time and carried in one trip. `CraftingSelectionTest` gives the dried fish recipe fish and
  a rack; `DwarfFoodTest` counts ten edible goods, `FurnitureArtTest` 24 forms and 19
  definitions, `ItemArtTest` 61 / 101 and `CraftingBrowserTest` eight groups with Food. Gate
  55/55, the lint clean; the crafting, fishing, furniture, dwarves, hauling, storage,
  construction, ui, saves, art, rooms and flora areas pass but for `ShrubPilotTest`, which has
  failed since 2026-10-29.
- **Seen in the game** (`tmp/fishing_step1/drying_*.png`, over a copy of the owner's earlier
  colony, the view sliced above a roofed hall): a rack installed in a hall beside Runbrin, two
  perch at its foot, haulers storing them first, then Runbrin fetching both from storage,
  working at the rack with no axe, and a crate of dried fish at the rack; the rack's window
  with Dry fish, and the crafting window's Dried fish board.
- **Saves:** nothing new is saved; step 1 and 2 saves load.

## Steps

1. **The lake.** Built (above).
2. **Every water.** Built (above).
3. **The drying rack.** Built (above).

Each step: a focused `FishingTest` (the zone's rules, stocks and regrowth, a real dwarf's
catch, a release mid-cast, Keep N, Fished out, saves), the job gate, a capture over a colony,
then the owner's look in Play.

## Not in this milestone

- Ice on the lake and tarn, and fishing through it (doc 282's later list).
- Cooking, which waits for a Cook; fish in trade. Dwarves grill fresh fish on a burning
  campfire themselves (doc 290).
- Lures, nets and traps. Fishing as a career's work is built in [292](292_ranger.md), the
  Ranger (step 2); rare catches are planned there (step 4).
- Stocking a pond the player made; fish in caves other than the spring cave (cave water is
  deferred in `00_todo.md`).
- Ducks reacting to fishers.

## Open

- The Keep N default (20), the Fished-out share (a tenth) and the catch time: tuning in Play.
- Whether the Hunter gets better at fishing: answered 2026-11-01. The Hunter takes fishing and
  becomes the Ranger ([292](292_ranger.md)).
