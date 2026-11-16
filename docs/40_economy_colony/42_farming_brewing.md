# 42 — Farming & Brewing

**Gradual seasonal art, 2026-10-15:** trees, shrubs, flowers and reeds update
their appearance across the first night of a season. Harvest eligibility and
crop cycles still change at midnight; harvest/removal actions use current
logical state. Tree bodies, occupancy and chopping work survive visual swaps.
Saving preserves gameplay state; a paused load rebuilds target art through
bounded frames. The owner asked for this gradual overnight change rather than the
world swapping in one frame (doc 194); the old path despawned and respawned every
tree, so the forest briefly vanished. `SurfaceFloraSpawner` swaps only a tree's art
node and skips trees whose model path does not change. `SurfaceDetailManager` keeps
a separate seasonal queue; spawning, harvesting, growth and transplanting stay
immediate, so a new or just-picked plant can show the new season before its
neighbours. The night schedule and queue rules are in doc 13 (`WorldClock`).

**Fields (2026-11-14, doc 309):** a Farmer with a copper hoe grows seven vegetables on fields,
farming zones laid out with Zones → Farming. See "Fields".

**Zones navigation, 2026-10-12 (doc 137):** Zones reserves a visible Animal pasture entry beside
live Storage, Fishing and Farming (doc 23, "Navigation Groups"). It is explicitly planned and
only explains its status; no pasture zones or livestock are enabled.

**Spoilage (2026-10-29, doc 282 phase 2):** stored, loose and carried fruit spoils by
temperature and open sky, and rots at the end; cool cellars keep it longest. See "Spoilage".

**Food shelf (2026-11-06, doc 299):** the Carpenter's food shelf keeps six crates of food off the
floor, and food keeps there as on the floor beside it. See "Spoilage".

**Tree planting (2026-10-29, doc 284):** tree seeds plant through Place → Plants and grow to
ancient. See Surface Trees, "Planting Seeds".

**Food foundation, 2026-10-12 (doc 131):** dwarves eat fresh fruit, and berry bushes
give repeat crops. Dwarves prefer reachable stored food, then allowed loose portions.
Famished dwarves may pick a ripe, unclaimed bush within 24 blocks of routed travel when
harvested food is unavailable. Normal crop work, yield and regrowth still apply: one
portion is carried for eating, surplus berries remain haulable, and interrupted work
saves on the plant. The picker never clears or uproots the bush or skips its regrowth.
Dining and hunger penalties are live; the eating and dining rules are in doc 41.
Edibility/nutrition are explicit item data, so later cooked food and edible meats can
share the same behavior. Fish are food the same way: perch, trout and cave fish keep 2
days at 20°C, char 3, and a drying rack turns two of a kind into two dried fish that keep 30 (doc 289).
At night a hungry dwarf grills a fresh fish on a burning campfire and eats it there, a meal by
the fire (doc 290, `food.grill` marks the fish that grill); dried fish and fruit are eaten as
they are.

## Overview

The colony's food and drink supply draws from two distinct farming environments: **surface plots** on outdoor dirt for crops that need open air, and **cave soil patches** underground for fungi and plants adapted to darkness. Both feed into the same brewery and kitchen chain.

**Water foundation — live 2026-10-10; farm/brewery jobs remain planned:**
[33 — Water, rivers & flooding](../30_simulation_systems/33_water_simulation.md)
defines a high rock spring feeding a river and the lowland lake. Water storage
is finite and spring replenishment is limited. Players can divert channels into
farms/cisterns; blocking waterways or breaching reservoirs can flood terrain.
Filled ditches gradually hydrate nearby soil, which dries gradually after supply
stops. A perimeter ditch supports nearby crops; larger fields can use internal
channels. Damp-soil visuals and a moisture overlay explain coverage.
Moisture reach, crop requirements and rates need balancing; the older saturation
numbers below are provisional. Flood-related crop damage remains a separate decision.

Dwarves will draw and transport measured water for brewing, making access,
hauling and storage meaningful. Reconcile recipe inputs and container handling
when implementing production: the current planned Longbeard Ale recipe has no
water input. Water simulation and measured withdrawal are live; production jobs and recipe
changes remain planned. Gravity-fed supply is possible only below the source; higher farms
and breweries require hauling or a later, separately designed lifting system.

## Wild berry harvest — live 2026-10-08

**Habitat, spacing and flower relocation — live 2026-10-09 (doc 85):** wild berry
bushes root on grass/dirt/soil at Y4–43, below the mountain boundary Y44; wild
flowers keep Y4–70 (`placement` in the JSON). These bands limit generation only:
player cultivation may use suitable soil (`transplant.ground_kinds`) at any
height. Bushes, cuttings and flowers reserve exclusive 3×3 planting areas,
including queued orders, while keeping single-cell roots and no collision (rules
under Surface details). Flowers now support Move/Uproot and variant-specific
Place → Plants entries: 1.5 seconds to uproot, 1.25 to replant, and each shape is
its own unstackable packed item (one heavy carry load, one Seeds & cuttings
slot). Seasonal packed art, identity and dormant/blooming state survive
relocation and storage; moving or clearing a flower yields nothing. JSON
`bloom.seasons` and `SurfaceDetailManager.flower_blooming(id)` /
`flowering_clumps(center, radius)` are the future hive forage boundary: only
living, planted clumps in bloom count, at their current locations, so packed,
stored and cleared flowers never do and Move or reload never resets bloom. Honey
is not yet playable.

**Flower follow-up:** the shared clearing tool is now **Clear plants**. Decorative
wildflowers have four seasonal appearances, no harvest action or resource yield,
and take 1.5 seconds to clear by hand. Clearing, construction and excavation
remove them permanently.

Generated blueberry, elderberry and wild-strawberry plants can now be harvested
or permanently cleared. Harvest takes three seconds and keeps the plant; clearing
takes two seconds and yields one cutting on completion (100% for all three
species, configured in `wild.clearing.yields[].chance`). Berry harvest yields
blueberry 3 in summer, elderberry 4 in autumn, and strawberry 3 in spring/summer.
As of milestone 131, berries regrow after 1.5 planted days in eligible seasons (two before the 21-day calendar, doc 281);
off-season and packed intervals pause progress. Picked visuals, crop progress,
separate partial work and removals save. Moving a bush cannot refresh its crop.
Fruit enters the existing loose produce-crate and hauling pipeline. All four
seasons have dedicated voxel art, including berry-free picked variants.

Use the individual inspector or **Orders → Harvest plants / Clear shrubs**.
Cuttings use existing crates and the **Seeds & cuttings** stockpile filter. Each
completed clearing grants its cutting only once; cancellation and reload cannot
repeat the reward. Construction/excavation displacement grants no cutting.
Farm plots and brewing remain future work. Fruit consumption is live (doc 41).

**Mature shrub relocation — live 2026-10-08:** inspector **Move** replants the
selected whole bush at chosen open ground; **Uproot** packs it for storage and
later **Place → Plants**. Each takes three seconds of uprooting, with another
1.25 seconds to replant (`wild.transplant.uproot_seconds` / `plant_seconds`).
Replanting starts animating on arrival and includes the set-down in that
duration (doc 83). These actions preserve identity and the seasonal crop
without yielding fruit or cuttings. Whole shrubs use seasonal wrapped-root art,
one heavy carry load and one storage slot in Seeds & cuttings. Player placement
uses suitable dry ground and a clear 3×3 envelope under open sky, independently
of world-generation habitat bands.

**Cutting growth — live 2026-10-08 (doc 80):** **Place → Plants** also plants one
cutting per young shrub, with three seconds of worker planting. Each planting
takes one cutting from its crate (pickup, cancelling and the final site check are
in doc 31, "Cutting planting"). Cuttings use the mature transplant's placement rules, with clearance
checked for the mature plant. Blueberry/strawberry need 2.25 growth days and
elderberry 3 (`stages.shrub.growth_duration_days`; ¾ of the values before the 21-day calendar, doc 281). JSON seasonal multipliers
(`wild.planting.seasonal_growth`) are spring 1.2, summer 1.0, autumn 0.8 and
winter 0.0. Age is the plant's `growth_credit` plus
`WorldClock.seasonal_days_between()` since its `planted_at` day: one growth day
is one in-game day at rate 1, pausing freezes it, and there is no wall-clock or
offline growth. Twelve young seasonal models show their growth stage without
fruit. WorldClock-derived age survives save/load; maturity enables ordinary
seasonal harvest and mature Move/Uproot. Until then a young plant can only be
cleared, which returns one cutting; construction or support loss removes it
without a drop. Inspector **DEV: Grow to maturity** adds growth credit to that
plant only, leaving the calendar and other crops unchanged.

### Bushes and fruit trees in a field

**From the owner, 2026-11-06:** "when we start with the farmer, bushes in a farming zone should
get picked by the farmer." Live since 2026-11-14 (doc 309).

- A bush that stands in a field needs no order. While the colony has a Farmer, each ripe one is
  marked for picking, as **Harvest plants** marks one, with the same crop work, yield and
  regrowth (`FarmingSystem._pick_standing`, on the game hour). Apple and juniper trees in a
  field are picked the same way each autumn (owner, 2026-11-14).
- **Picking in a field is its Farmers' work.** Every such lease takes only a Farmer
  (`TreeFellingComponent.worker_filter`), and the Farmer earns one experience for it. A field
  whose colony has no Farmer picks nothing by itself, and an order the player gives there is
  open to anyone.
- A bush keeps its 3 × 3 planting area in a field: those tiles are neither hoed nor sown.
- Outside a field nothing changes: **Harvest plants** and the inspector mark one crop, and the
  pick clears the mark.
- The owner declined a standing harvest order, where a marked bush stays marked while it regrows
  until cancelled. Repeat picking comes from the Farmer instead.
- **Surplus** (owner, 2026-11-14): everything ripe is picked and stored. What the store cannot
  keep rots, as Events says (see Spoilage), and the player sizes the field. There is no Keep.
- **An orchard** is a field whose plan rests in every season: nothing is hoed, and its Farmers
  only pick what stands in it.

## Fields

Live 2026-11-14 (doc 309). From the owner: "several vegetables the farmer can grow, some low
level that he can farm during a specific season and then later more complicated crops as the
farmer levels up." Vegetables are the colony's third food after fruit and fish, and the one it
sows. `FarmingSystem`, a scene node, owns the fields and their plants. The crops are
`data/flora/field_crops.json`, read by ContentRegistry, and the tuning is `farming` in
`task_config.json`, whose comment explains each value; the numbers are still to be settled in
Play. The tool and the field's window are in doc 23, "Fields".

- **Only Farmers work fields** (doc 41, Profession System), as only Rangers fish, so every
  harvest goes to a dwarf who learns from it. A Farmer needs a copper hoe, so a colony farms
  only once it has a Blacksmith and copper. With no Farmer a field waits.
- **A field** is a farming zone: floor cells of grass or dirt (`tillable_kinds`) on one level,
  under the open sky (nothing solid within `sky_clearance` blocks above), at any height, at
  most `max_zone_extent` a side. Dirt and grass the colony builds count, so terraces can be
  farmed. Storage, fishing spots and other fields refuse a field's cells, and it theirs.
  Height and temperature do not slow a crop: the calendar's autumn cools from 9°C to −3°C in
  the valley (doc 34), so a frost rule would take every autumn crop.
- **What stands there stays.** A cell that holds a bush, a wildflower, a stone, a tree or
  furniture may be part of a field and is left alone: a tile under furniture, a trunk or a stone,
  within a plant's planting area or under water is neither hoed nor sown. A field counts these
  afresh on the game hour and when something is placed (`FarmingSystem._survey`).
- **Tilled soil** is a block of its own, `base:terrain:soil:tilled`. Its kind is `dirt`, so it
  takes water from a ditch, shows damp and drops Soil as dirt does. A Farmer hoes grass or dirt
  into it, `till_seconds` a tile, once. Removing a field leaves the tilled soil; digging it or
  building over it takes the tile's plant.
- **The plan** names a crop for each season, or rest, and the Farmer follows it year after year.
  A new field plans the starter crops (radish, carrot, turnip) and rests in winter. A crop goes
  only in a season it is sown in (`sow_seasons`). A crop that takes two seasons (`plan_seasons`
  2: onion, pumpkin, kale) holds the season after its own; naming another crop for that second
  season puts the first to rest (`FarmingSystem.set_plan`).
- **Sowing** takes `sow_seconds` a tile and no goods: there are no seeds (owner, 2026-11-14),
  and a Farmer's level is the only gate. A tile is sown only if the crop will be ripe
  `sow_margin_days` before the plan moves on to another crop (`can_sow`), so a Farmer never
  sows what cannot ripen. From that follow the last sowing days the window shows: radish
  Spring 16, carrot Summer 14, turnip Autumn 12, onion Spring 13, pumpkin Summer 11 and kale
  Autumn 10; cabbage day 11, or any day while the next season names it too.
- **Growth** is credit kept on the tile and added on the game hour (`grow`): a day a day in
  spring, summer and autumn, nothing in winter. A tile shows a sprout until `growing_from` of
  its days, then the growing plant, then the ripe one.
- **Water** (doc 33). Soil is damp from `damp_from` of full moisture, within three cells of
  water, and on a day of rain or storm every open field is damp. Damp soil grows a crop
  `damp_growth` times as fast. A crop that `needs_damp` (pumpkin) is sown and grows only in
  damp soil, at its plain speed, and waits in dry soil. The sowing rule counts on dry soil, so
  water only ever brings a harvest sooner.
- **Pulling** takes `harvest_seconds` a tile and gives `tile_yield` of the crop's good. The
  pulls fill one crate after another where the Farmer stood, not a crate a tile, and haulers
  store them as they do fruit. The tile is then sown again if another round can still ripen.
- **A crop picked more than once** (`regrow_days`: kale) stays in the ground after a picking and
  is ripe again after those days, in winter too, until its seasons in the plan end.
- **When the season turns** the field changes over. Ripe plants of the old crop are still
  pulled, unripe ones are hoed under (`clear_seconds`), and Events says how many: "11 tiles of
  carrots in Field 1 were not ripe when autumn came." Nothing ripe is lost to the calendar.
- **A Farmer's order of work** in a field: pull what is ripe, hoe under what the plan has moved
  on from, sow, then hoe new ground. Among jobs of a kind it takes the nearest tile. A field
  takes `max_farmers_per_field` Farmers at once.
- **Levels** (doc 41). A crop is sown only by a Farmer of its `farmer_level`; any Farmer pulls
  it. A level gives its crop and nothing else.
- **No collision** (Hard Rule 5): dwarves and animals walk through a plant. Rabbits and deer
  leave crops alone (`00_todo.md`, "Farming left for later").
- **Saves:** the `farming` section keeps each field's tiles, its plan and its plants: the
  crop, the days grown, ripe or picked, and work begun on a tile (Hard Rule 12). Tilled soil
  saves with the terrain. A save that names a crop or a season the game lacks is rejected.

| Level | Crop | In the ground | Days | A tile gives | Keeps at 20°C | What sets it apart |
|---|---|---|---|---|---|---|
| 1 | Radish | Spring | 4 | 2 | 5 days | Quick: up to four rounds a spring, the first fresh food after winter |
| 1 | Carrot | Summer | 6 | 3 | 12 days | Up to three rounds a summer |
| 1 | Turnip | Autumn | 8 | 4 | 15 days | Two rounds an autumn; it keeps like apples, so it is the winter root |
| 2 | Cabbage | Spring, summer or autumn | 9 | 6 | 8 days | Free of the calendar. The most fresh food a tile, but it does not keep |
| 3 | Onion | Sown in spring, pulled in summer | 28 | 14 | 40 days | Two seasons in the ground. It keeps longest: a summer field can feed the winter |
| 4 | Pumpkin | Sown in summer, cut in autumn | 30 | 24 | 30 days | Two seasons, and it needs damp soil. The biggest harvest of the year |
| 5 | Kale | Sown in autumn, picked until spring | 10, then a picking every 3 | 1 a picking | 6 days | Picked through the snow: the only field food in winter |

- **What a tile gives in a year:** the three starters 8 + 9 + 8 = 25; cabbage in spring and
  pumpkins after it 12 + 24 = 36. A 6 × 6 field of a starter crop gives about 300 portions in
  its season, against the 315 five dwarves eat.
- **For agents:**
  - a Farmer's place in a field is a surface work source (`FarmFieldWork`, doc 31): a field
    posts one lease for each place it has work for, never one a tile, and the Farmer who takes
    it is given the nearest job it may do;
  - a field's plants are drawn a node a tile, as bushes are (`FarmFieldVisuals`), a few a frame.
    A tile's model carries its own soil ridges, and a tilled tile with nothing sown shows
    `bare_model`;
  - `grow()` reads dampness as it is at the hour; a test that sets the clock by hand resets
    `_grown_at` (`FarmingTest._clock`).

## Fishing

Live 2026-10-31 (doc 289; Rangers since doc 292). Fish are the colony's second food after
fruit: fresh fish spoil fast, and dried fish keep a month, a way to stock up for winter.
`FishingSystem`, a scene node, owns the zones and each water's stock. The tuning is `fishing`
in `task_config.json`, whose comment explains each value; its numbers are still to be settled
in Play. The zone's tool and window are in doc 23, "Fishing Zones".
- **Rangers fish,** one to a spot, and no other career does (doc 41, Profession System). A
  water gives about the same food however many dwarves fish it, so every catch goes to a dwarf
  who learns from it. From the owner (2026-11-01): "Fishing should feel fun and rewarding for
  the player and it feels like a skill the dwarves should gain experience on." With no Ranger
  in the colony a zone waits.
- **A spot** is a shore cell a dwarf can stand on (Hard Rule 4) with water straight out from it
  within `reach` blocks, at least `min_depth` deep, from the fisher's feet down to `bank_drop`
  blocks below them (rivers run in channels), and never through ground. A cell over the lake or
  a tarn, or with water on it, is refused, as are storage zones and furniture.
- **The waters** (`fishing.waters`): the lowland lake gives perch, the river trout, a mountain
  tarn char and the spring cave's pool pale cave fish. A cast cell belongs to the lake, then the
  tarn, the pool, then the river, so where two meet the first wins, and a zone keeps to one
  water. Water outside them, such as a pond the colony digs or floods, holds no fish. The cave
  pool can be fished only once the cave is found (Hard Rule 11). A spot whose water drains
  waits until it fills again, and a load keeps it: a zone whose water had drained at the save
  comes back whole, with its Keep (2026-11-09).
- **Stocks.** A water holds `stock_per_cell` fish for each of its cells and regrows
  `regrowth_per_day` of its maximum a day. Below `fished_out_share` of that maximum the water
  is Fished out and its zones post no work; from a tenth, it is full again in about 30 days.
- **Keep.** While the colony keeps fewer of a zone's fish than its Keep (`keep_default`),
  stored or loose, and its water isn't Fished out, each free spot posts one FISH lease (doc 31).
  A Ranger already casting when the Keep is met, or the water is Fished out, lands that catch
  and then stops (2026-11-09: the cast went on, sounds and all, with nothing to land).
- **A catch** takes about a game hour (`catch_hours`) on a full water, give or take a seeded
  `catch_spread`. Bites come at full speed in spring and autumn, slower in summer and at half
  speed in winter (`season_speed`; water doesn't freeze), and up to `low_stock_factor` times
  slower as the stock nears Fished out. Wisdom speeds the work (doc 41, "Stats"). The fish
  lands at the fisher's feet, and haulers store it as they do fruit. A release mid-cast loses
  nothing (Hard Rule 12), and a dwarf casting at a save casts again after loading.
- **Each water's fish differ** (`fishing.waters`, shown in the zone's window as `trait`): the lake
  holds the most fish, trout add 10 points to a Ranger's big-fish chance (`big_bonus`), char keep 3
  days instead of 2, and the spring cave's fish bite at full speed all year (`seasonless`), so a
  Ranger's winter patience adds nothing there.
- **A calm job.** Each catch leaves a Ranger "A quiet hour by the water" (`mood.quiet_hour`, +3 for
  8 game hours, renewed by the next catch), the first work that lifts a dwarf's mood. The journal
  speaks only when it begins, not at each renewal.
- **What limits it.** One fisher lands 12–15 fish a day at a full lake and about 5 near Fished
  out, where a lake regrows about 5 a day. So one fisher takes all a water gives, more fishers
  only empty it sooner, and only what each fish is worth can grow: a Ranger's levels make
  catches bigger, not faster (doc 41).
- **As food,** a fish is one portion and keeps 2 days at 20°C, or 3 for char (Spoilage). Dwarves eat it raw,
  served whole, or grill it at a burning campfire (doc 41, "Grilling"). Rangers hang two of a
  kind on a drying rack, where they dry for a day and don't spoil, then take them down as two
  dried fish that keep 30 days (doc 44).
- **The look.** Fish are look A, Chunky, to match the chibi wildlife: a big head, a bead eye, a
  short deep body and a fan tail (`tmp/fishing_concepts_20261031/art/fish_sheet.png`). The rod
  is a peeled sapling with rope lashings and a red-tipped float, Tier 1 with no iron, and a
  catch shows four frames: cast, wait, bite and land (`DwarfFishingPose`). A big fish is a
  heavier model of its own (concept B, `tmp/ranger_concepts_20261101/fish/big_fish_sheet.png`),
  never a scaled fish, which would break the 1:16 grid (doc 63).
- **The sound** (owner, 2026-11-12: "I think we could add some sounds"). A catch is heard as it
  is seen: the rod's swish, the float's plop, then nothing through the wait, which keeps it a
  calm job; a splash at the bite, a longer one as the fish comes out (heavier for a big fish),
  and two flops as it flaps on the line, its tail swinging with each. All are recordings; the
  cues, their sources and their levels are in doc 13, "WorkFeedback".
- **Saves:** the `fishing` section keeps each zone's spots and Keep, and each water's stock
  with the day it was counted (doc 13). Fish are ordinary items. Only a catch and a load
  write a stock; reading one (`FishingSystem.stock`) never does. A load reads stocks before
  the clock is restored, so a read that wrote would have moved the count's day, and the
  water would have refilled once the clock caught up.

## Spoilage

Live 2026-10-29 (doc 282 phase 2; `scripts/components/FoodSpoilage.gd`, owned by
StockpileManager). Fruit spoils once harvested; fruit on the bush never does.
- **Spoil.** Each food stack carries `spoil`, 0 fresh to 1 rotten: a stored stack in its
  storage entry (a zone's `cell_stacks` or a food shelf's slot, shown on its crate's node), a loose
  crate or a portion in hand on its node (`ItemDropManager.spoil_of`). Splitting a stack copies it; putting goods
  together (a deposit topping up a stack, fresh fruit landing on a loose crate, a basket
  collecting another) averages it by count.
- **Crates of different freshness stay apart** (owner, 2026-10-29): goods further apart in
  spoil than `merge_band` (0.25, a quarter of their life) never share a crate while room
  allows, so fresh fruit never takes on a rotting crate's clock.
  - A stockpile deposit tops up a crate of like freshness, else takes an empty cell. Only
    when the stockpile has no empty cell does it top up the crate closest in freshness,
    rather than leave the fruit outside (`StorageStackSlots.reserve`). Food already stored,
    moving up to a better store or out of one that no longer takes it, never uses that
    last step: it waits where it is for room (2026-11-09; `StoragePriorityTest`).
  - Fresh harvest landing on a loose crate spoilt past the band starts a crate of its own.
  - A hauler's basket collects only crates within the band of its first.
  - Hauling still asks only "is there room for apples?"; that answer never depends on
    freshness, so no hauler waits on fruit that has nowhere to go.
- **Speed**, worked out each game hour at the stack's place: where it is stored, where it
  lies, or where its carrier stands. T is that place's temperature now (doc 34):

```
speed  = 2.5 ^ ((T − 20) / 10)           1 at 20°C; ×2.5 for every 10°C warmer
speed  = 0.05 when T ≤ 0°C under a roof  frozen nearly stops
speed += 1.0 under the open sky          1.5 in rain, storm or snow, frozen or not
spoil += speed / (24 × keeps_days) each game hour
```

- **A food shelf changes nothing** (doc 299, accepted by the owner 2026-11-06): food on it keeps as on
  the floor beside it, by the same temperature, roof and rain, read over the floor cell under its place.
  An open rack has no reason to keep food better, the keeping times stay (owner, 2026-10-29), and
  slower spoiling is for barrels and chests (`00_todo.md`, "Food keeping left for later"). A number could
  be added later without other changes.
  - **What it holds:** six crates of 24, 144 portions, twice what its three cells hold on the ground.
    Five dwarves eat 15 portions a day, so a full shelf is about 10 days of food, and three hold a 21-day
    winter.
  - **A shelf in a warm place pulls food out of a cool one.** A shelf is at priority 4 and ground storage
    at 5 (doc 31), and a store's priority never looks at temperature, so a shelf in the yard takes food
    from a cellar floor and it spoils sooner. That is the player's to fix: put the shelf in the cellar,
    or lower its priority. Its window's Keeping line says how long food keeps there.
- **Keeping time** is item data: `food.keeps_days` in `items.json`, the days a food
  lasts at 20°C under a roof. Wild strawberry 2, elderberry 2, blueberry 4, apple 15,
  juniper berry 40; each fresh fish 2 and dried fish 30 (doc 289); radish 5, kale 6, cabbage 8,
  carrot 12, turnip 15, pumpkin 30 and onion 40 (doc 309). The rest is
  `food.spoilage` in `task_config.json`.
- **Rotting.** At 1 the units nobody has claimed are gone. Units claimed for a meal or a haul,
  and food in hand, stay until used; food put down rots at the next hour if due (Hard Rule
  12 holds). Events says so, one line for each food in each place: "24 blueberries rotted in
  Stockpile 1.", "5 apples rotted on the ground."
  On a food shelf: "24 apples rotted on the food shelf."
  Rotten food is simply gone: there is no rotten item (owner, 2026-10-29). A rotted crate
  leaves through `ItemDropManager.discard`, which takes it out of the tree at once, so no
  storage search finds it before it is freed.
- **Warning.** As a stack passes 75%, Events warns with the days it has left there:
  "Blueberries in Stockpile 1 are going bad: less than a day left."
- **Eating order** prefers older food (doc 41 "Eating").
- **The hourly pass** runs over frames, at most 0.5 ms a frame (`budget_usec`), and covers
  the hours since the last pass; after a load the hours start afresh.
- **Saves:** `spoil` saves with zone stacks, loose goods and carried goods.
- **Rooms that keep food** (2026-11-12; doc 34 "Room types"): a sealed room holding a food
  shelf is a Pantry above 0°C and below 16°C and a Freezer at 0°C or below. The types change
  nothing about spoiling, which goes by temperature alone; the room window shows how long
  blueberries keep there.
- **Seen** (doc 23):
  - a food crate's status tag: Fresh, Spoiling (from half its life), Going bad (from three
    quarters) or Frozen, with its days left there (`FoodSpoilage.freshness`);
  - the storage window's Keeping list: each food's stalest crate, the soonest to rot first;
  - the Temperature view's hover card: "Blueberries keep about 11 days here."

What it gives, with blueberries keeping 4 days and apples 15 days at 20°C:

| Place | Temperature | Blueberries keep | Apples keep |
|---|---|---|---|
| Valley yard, summer | ~21°C | ~2 days | ~7 days |
| The same in rain | ~20°C | ~1.6 days | ~6 days |
| Valley yard, winter | ~−3°C | ~3.5 days | ~13 days |
| Tunnel, 6 blocks in, summer | ~15°C | ~6 days | ~24 days |
| Valley larder, or a tunnel 12+ blocks in | ~9°C | ~11 days | ~41 days, two seasons |
| Cellar just under the summit | ~2°C | ~21 days, a season | ~78 days, most of a year |

Elderberries keep about 5 days in a valley larder and 10 in the cellar under the summit:
not a whole winter, which leaves room for brewing them into wine later. Kept cool, apples and
juniper berries (about 110 days in a valley larder) last the winter. Today too few grow near
a start to feed one: 10–25 apples and juniper berries an autumn within 48–64 blocks, against
the 315 portions five dwarves eat in a 21-day winter. From the owner (2026-10-29): dwarves
stock up for winter, and hunting comes later; the keeping times stay, and meat will carry its
own `keeps_days`. Fishing and the drying rack (doc 289) give a way to stock up; the winter
check is in `00_todo.md` (Food, "Winter food").

## Agricultural Cycles

**Apple harvesting — live 2026-10-19 (doc 252):** inspector **Gather apples** and
**Orders → Harvest plants** gather fruit without felling. Mature trees yield 4–6
apples in four seconds; ancient trees yield 7–10 in six seconds, once each autumn.
Saplings are too young. The fruit disappears after picking and returns next
autumn; partial work and picked state survive saving. Gathered apples enter normal
hauling and hungry dwarves can eat them. These are player-designated jobs, with
no automatic annual orders. Crop rules are under Fruit Trees below.

**Juniper harvesting — live 2026-10-09 (doc 84):** standing mature and ancient
junipers yield 2 and 4 berries respectively once each autumn, after three seconds
of hand picking. Saplings are too young. Inspector **Harvest berries** and
**Orders → Harvest plants** share the same player-designated task; no recurring
orders are posted. Felling now grants wood and possible seeds only. JSON stage
`fruit_harvest` defines season, work and yield. Picked state, partial picking and
felling work save separately, and eight berry-free models show depleted or
out-of-season trees.

**Cave generation status (2026-10-07):** generated caves now expose existing
soil deposits and can add a rough patch of `base:terrain:soil:cave` on a chamber
floor. This supplies a material and location for later underground agriculture.
It does **not** implement farming, saturation, irrigation, or naturally growing
cave crops. The requirements below remain the design target; dry cave soil alone
does not promise a working farm. The deferred cave water and fungi
work is tracked in `00_todo.md` (World / caves).

### Underground Crops (cave soil — `base:terrain:soil:cave`)

These crops require no light and cannot survive on surface dirt. Dwarves expose cave soil patches during normal mining operations and designate them as farm plots.

| Crop Key | Grow Time | Yield | Notes |
|---|---|---|---|
| `base:flora:plump_helmet` | 4.5 in-game days | 4 food units    | Bulbous mushroom; primary underground food staple. Auto-reseeds from mycelium — no seed item needed. See `data/flora/plump_helmet.json` |

### Surface Crops (surface dirt — `base:terrain:surface:dirt`)

These crops require open sky above the farm block (no ceiling within 10 blocks) and grow on the surface dirt exposed around the mountain entrance. Dwarves must venture outside to tend and harvest them.

| Crop Key | Grow Time | Harvest Season | Yield | Notes |
|---|---|---|---|---|
| `base:flora:pig_tail`    | 6 in-game days  | Any (annual — re-seed each spring) | 4× pig tail fiber + seed (40%) | Annual fibrous plant; source of cloth. See `data/flora/pig_tail_plant.json` |
| `base:flora:hops_plant`  | 8.25 in-game days | Any (dies in winter) | 5 hops + 2× cutting (60%) | Annual bine; re-seed each spring. See `data/flora/hops_plant.json` |
| `base:flora:grape_vine`  | 4.5 in-game days | Summer / Autumn | 5 grapes + 1× cutting (25%) | Perennial vine; survives winter dormant. See `data/flora/grape_vine.json` |

#### Hops — Annual Crop

Hops (`base:flora:hops_plant`) grow through three stages: `seedling → climbing → mature`. The plant only yields at the mature stage. After harvest the farm plot returns to **FALLOW** and must be re-seeded from hops cuttings the following spring. Any plant still in the `seedling` or `climbing` stage when winter arrives is lost — the farm plot returns to FALLOW at the season change. Dwarves should prioritise harvesting all mature hops before the end of autumn.

#### Grape Vine — Perennial Crop

Grape vines (`base:flora:grape_vine`) grow through two stages: `cutting → fruiting`. Once fruiting, the vine **persists across seasons** and yields grapes each summer and autumn without replanting. The vine displays a dormant bare-cane model in winter but does not reset. A single planting effort provides a permanent supply — prioritise establishing vines early.

### Cave-Floor Soil Saturation Requirements

A cave soil block is eligible for farming designation only if:

1. The block type is `base:terrain:soil:cave`.
2. Water saturation of the block is `> 0.3` (tracked as a per-block float, separate from fluid CA mass).
3. There are **at least 3 clear air blocks** above (matches dwarf clearance envelope — crops must be harvestable).

Live irrigation uses three-cell Manhattan reach, weaker at distance, two game hours to wet and 24 to dry (doc 33). The old `−0.005 / hour` proposal is superseded. A farm plot with saturation `< 0.1` cannot support new crop growth.

### Surface Dirt Farming Requirements

A surface dirt block is eligible for farming designation only if:

1. The block type is `base:terrain:surface:dirt`.
2. There is **open sky** — no solid block within 10 blocks directly above (checked at designation time).
3. There are **at least 3 clear air blocks** above for dwarf access.

### Growth State Machine

```
FALLOW → SEEDED → SPROUTING → MATURE → HARVESTABLE → (harvested → FALLOW or PERSIST)
```

Each transition triggers a visual mesh swap on the farm block (see Single-Tile Asset Overflow Rule below).

- Annual crops return to FALLOW after harvest.
- Perennial crops stay in their current growth stage and re-enter HARVESTABLE the following harvest season.

**Planned, not implemented.** These four are the brewing and weaving crops, and they wait
for the Brewer; the vegetables a Farmer grows today are under "Fields". Their files in
`data/flora/` hold the stages, models and yields the art tools read; the rules below
are design only, and the live rules of a field (the plan, sowing, growth) take the place of
this state machine when they are built. Stages advance in the order the crop file lists them.

| Crop | Stages | After harvest |
|---|---|---|
| Plump helmet | sprouting (4.5 days) → mature | FALLOW, then automatically re-seeds to sprouting with no dwarf and no seed item; needs no light |
| Pig tail | seedling (6 days) → mature | FALLOW; re-seed from pig tail seed |
| Hops | seedling → climbing → mature | FALLOW; re-seed from hops cuttings |
| Grape vine | cutting → fruiting | Persists |

---

## Beehives

Beehives (`base:workshop:beehive`) are outdoor structures that produce honey passively over time.

**Planned, not implemented;** there is no beehive data file yet. Its one recipe,
`base:recipe:beehive:collect_honey`, takes no inputs, yields 2 honey, is 1 hour of
work and needs no skill. The placement and production values below are the design.

### Required future connection: wildflower forage

**User requirement, 2026-10-08:** the generated wildflowers must have a meaningful
role in honey production when beekeeping is implemented. They currently remain
decorative; this connection is planned, not live.

The proposed design is to measure nearby **blooming flower clumps** as bee forage
and use that supply to influence hive productivity. Preserving a flower patch
should give the player a reason to place a hive nearby. Bees visit living
flowers; flowers are not harvested or consumed as recipe ingredients.

- Count persistent flower records and their actual seasonal bloom state, never
  visible meshes or camera distance. Current wildflowers bloom in spring and
  summer; autumn seedheads and winter remnants supply no floral forage.
- Clearing, construction and excavation remove that clump's contribution.
  Season changes and loading must refresh the same result without restoring
  removed plants. Retain the planned winter dormancy and stored honey.
- Show the local forage supply and its production effect in the hive inspector
  and placement preview so the relationship is understandable.
- Define bloom contributions, forage radius and production response in owning
  JSON data when implementing the system. Tune the radius, rate versus yield
  effect, caps and overlapping-hive behavior at that milestone; do not assume
  unlimited throughput from stacking hives around one patch.

Other forage sources (such as flowering shrubs/trees), production with no local
flowers, and autumn production need an explicit balance decision. The production
table below remains a planned baseline, to be reconciled with this requirement.

### Placement

- Must be placed on a **surface block** (`base:terrain:surface:*`).
- Requires **open sky** — no solid block within 10 blocks directly above (same check as surface farm plots).

### Production

A beehive produces **2 honey** every **48 in-game hours** at baseline. A dwarf is auto-dispatched to collect when the production interval elapses; no player action is required. If no dwarf is available, uncollected honey accumulates internally up to a cap of **6 units** before production pauses.

| Season | Production Interval | Notes |
|---|---|---|
| Spring | 48 h (baseline) | Bees active |
| Summer | 38 h (×0.8 — peak forage) | Fastest production |
| Autumn | 58 h (×1.2 — slowing) | Slower |
| Winter | **Dormant** | No production; uncollected honey is retained |

Build multiple beehives to increase honey throughput. Honey is required for **Sweet Mead** and **Mountain Cider**.

---

## Brewing Recipes

**Brewing vat:** a placeable brewing vat is planned with the brewery. There is no
vat furniture definition or placed model in the game yet.

Brewing converts raw crops into drinks and refined goods inside a `base:workshop:brewery` block.

**Planned, not implemented;** there is no brewery data file yet. Each recipe has an
id, inputs and outputs, a work time in in-game hours, a skill bonus, a minimum
Brewer level (Min Skill, 0 = always available) and a UI category (`ale`, `stout`,
`mead`, `cider`, `wine`, `spirit`, `processed_goods`). Each Brewer level above 1
cuts the work time by the recipe's skill bonus: 5% for ale, stout and cider, 6% for
mead and wine, 7% for gin and 4% for cloth. The recipes are:

### Ales & Stouts

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:brew:longbeard_ale` | 4× plump helmet + 2× hops | 5× ale | 2 h | 0 |
| `base:recipe:brew:dark_stout`    | 7× plump helmet + 3× hops + 1× water bucket | 4× stout | 4 h | 2 |

### Meads & Ciders

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:brew:sweet_mead`     | 3× honey + 1× water bucket | 4× mead   | 4 h | 2 |
| `base:recipe:brew:mountain_cider` | 6× apple + 1× honey + 1× water bucket     | 4× cider  | 3 h | 1 |

### Wines & Spirits

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:brew:grape_wine`   | 7× grape + 1× water bucket      | 3× wine | 5 h | 3 |
| `base:recipe:brew:juniper_gin`  | 6× juniper berry + 1× water bucket | 3× gin  | 5 h | 4 |

### Processed Goods

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:brew:pig_tail_cloth` | 2× pig tail | 1× cloth | 1 h | 0 |

Brewing tasks are issued by the Task System when a brewery workshop is idle and raw input materials are available in an accessible stockpile.

---

## Aging Cellar

The Aging Cellar (`base:workshop:aging_cellar`) is an underground workshop that produces premium aged drinks from base brewed drinks and oak staves. It is **planned, not implemented;** there is no aging cellar data file yet.

**Carpentry decision (2026-10-04):** oak felling supplies raw logs and possible
acorns. A carpenter makes oak staves from those logs, then uses the staves for
oak aging casks. Staves never drop from trees. The planned aging recipes below
still consume staves directly; those inputs are provisional until cask crafting
and use are implemented. Carpentry quantities and work times remain to be defined.

**Aging rack:** an oak-cask aging rack is planned with the aging cellar. There is
no rack furniture definition or placed model in the game yet; the recipes and
temperature-dependent batch behavior described below are planned too.

For the full temperature system — the climate, sealed rooms, heat sources and the Frozen Vault — see [`34_temperature.md`](../30_simulation_systems/34_temperature.md).

### Temperature Requirement

The aging cellar block must be placed inside a **sealed room** whose computed temperature
falls within the recipe's required range. The room's temperature is the climate's (doc 34):
higher is colder, a degree for every 12 blocks; the rock over the room damps the seasons; a
burning hearth adds heat.

There is no hard Y placement constraint on the block itself — temperature is the gating factor. A cellar placed in a room that is too warm or too cold simply shows its affected recipes as unavailable until temperature is corrected.

| Aged Drink | Required Temp | Baseline Height | Notes |
|---|---|---|---|
| Vintage wine | 6–10°C | Y 7–55 | Valley and foothill cellars; the most accessible aging recipe |
| Aged dark stout | 3–7°C | Y 43–91 | The mountain's middle shelves |
| Reserve gin | 1–4°C | Y 79–115 | Cold stone high in the mountain; a hearth warms a freezing summit cellar into range |

The baseline height is where a well-covered room's yearly mean falls in the range.

**Warming a room:** a burning hearth adds heat units ÷ room volume (doc 34), so compact aging rooms respond strongly to one hearth and large caverns need several. A log torch adds little.

**Cooling a room:** there is no cooling mechanic. If a room is too warm for a recipe, build a new aging cellar higher in the mountain.

**Seasonal variation:** rock damps the seasons. Under 12 solid blocks a room swings about
±2.7°C over the year, under 24 about ±0.6°C. A shallow wine cellar may pause at the height of
summer as the warmth nudges it above 10°C; dig further into the rock for a steadier one.

### Aging Progress and Temperature

Each active aging batch displays a **progress bar** in the workshop UI showing elapsed hours against the total `aging_time`. Temperature interacts with it directly:

- **In range** — progress advances at 1 in-game hour per in-game hour.
- **Out of range** — progress **pauses**. The bar shows a pulsing thermometer warning icon. The batch is not lost or reset.
- **Restored** — progress resumes from exactly where it paused. No hours are lost.

A batch can pause and resume any number of times — mismanaging heat costs time, never the batch itself.

### How Aging Works

Aging is a three-phase process:

1. **Load** — A dwarf hauls the required inputs (base drink + oak staves) to the cellar and spends **1 in-game hour** loading the batch.
2. **Age** — The cellar ages the batch autonomously for `aging_time` in-game hours (accumulated only while temperature is in range). No dwarf is needed during this phase.
3. **Collect** — When the accumulated aging time reaches `aging_time`, a COLLECT task is auto-queued. A dwarf retrieves the finished drink and deposits it in the nearest output stockpile.

Only **one batch per cellar block** can be in progress at a time. Build additional aging cellar blocks for parallel production.

> **Patience cannot be rushed.** Brewer skill applies only to the 1-hour loading task. `aging_time` is fixed and is never reduced by skill.

### Aging Recipes

Planned recipe values. Loading takes 1 hour, cut by 4% per Brewer level above 1;
Min Skill is the minimum Brewer level. When the room is out of range the batch
shows a tooltip: stout "Too warm for stout — lower the heat or build higher in the mountain.",
wine "Temperature out of range for wine — adjust heat sources or height.", gin
"Too warm for gin — this recipe needs cold stone high in the mountain." UI categories are
`aged_ale`, `aged_wine` and `aged_spirit`.

| Recipe ID | Inputs | Output | Aging Time | Temp Range | Min Skill |
|---|---|---|---|---|---|
| `base:recipe:age:aged_stout`   | 3× stout + 2× oak stave | 2× aged stout   | 36 h | 3–7°C  | 3 |
| `base:recipe:age:vintage_wine` | 3× wine + 2× oak stave  | 2× vintage wine | 48 h | 6–10°C | 5 |
| `base:recipe:age:reserve_gin`  | 3× gin + 2× oak stave   | 2× reserve gin  | 40 h | 1–4°C  | 4 |

### Frozen Vault and Food Preservation

A sealed room whose computed temperature is ≤ 0°C becomes a **Frozen Vault**. In today's
climate only cellars just under the summit freeze, for about two weeks around winter's first
day; nothing freezes all year (ice to keep a cellar frozen is a later idea, in `00_todo.md`). Food
there spoils at a twentieth of its 20°C speed while it stays frozen ("Spoilage"). The Frozen Vault is too
cold for any aging recipe (minimum 1°C required), so planned aging progress pauses until the
room is warmed into range.

A hearth can warm a frozen vault above 0°C, converting it from a freezer into a potential Reserve Gin cellar — but the freezing benefit is lost. The tradeoff is intentional.

---

## Single-Tile Asset Overflow Rule

> **INVARIANT — must be respected by all rendering and physics code.**

Multi-cell plant visual meshes (e.g. a tall mushroom tree that visually spans 2×1×2 blocks) **bleed past a strict 1×1×1 engine grid cell** in their visual representation while their **logical engine footprint remains exactly 1×1×1**.

### Consequences

- **Pathfinding**: The navigation system treats the farm block as a single 1×1×1 solid node. The visual overhang does not add collision or navigation cost.
- **Harvesting**: The task target is always the origin block of the plant (bottom-center). Workers path to that single block.
- **Collision**: Farm plants have no `CollisionShape3D`. Dwarves can walk through the visual mesh without obstruction.
- **Rendering**: Visual meshes are placed as `MeshInstance3D` children of the farm block node, with local offsets to centre the overflow. Do not use `Area3D` or physics bodies for plant meshes.

> **Agent note:** If you find yourself adding a `StaticBody3D` or `CollisionShape3D` to a plant mesh, you are violating this rule. Remove it.

---

## Surface Trees

Surface trees are **world objects, not farm crops**. They are the only surface entities that carry real `StaticBody3D` + `CollisionShape3D` collision. Dwarves path *around* them; they do not walk through.

**Runtime status (2026-10-19):** tree inspection and single/batch tree felling are live via
**Orders → Chop trees** and explorer actions. Per-stage work durations,
partial progress, designations and felled records persist; authored felling drops
enter the normal hauling system. Manual annual apple and juniper picking is live
through **Orders → Harvest plants** and explorer actions (rules under Fruit Trees
below). Tree seeds plant through Place → Plants and grow to ancient (2026-10-29, doc 284;
rules under Planting Seeds). Wild trees keep their seeded stage; forestry zones remain
planned.

### Collision Rule

A mature or ancient tree gets one `StaticBody3D` with a `BoxShape3D`: XZ = the stage's
footprint (see the table below), height = the stage's `clearance_height` from the species
JSON, resting on the ground. The canopy is visual overhang only and carries no collision
(Hard Rule 5). Saplings have no body. `SurfaceFloraSpawner.enable_collision` can turn tree
bodies off globally.

**Physics layers — never put trees on Layer 1.** The RTS camera's `SpringArm3D` collides
with Layer 1 only, which is reserved for terrain (`Camera.gd`). A tree body on Layer 1 makes
the spring arm treat it as ground and snap the camera down onto the canopy on a quick pan.
Trees and surface details (boulders) use **Layer 2** (`tree_collision_layer`); dwarves use
Layer 3 (`DwarfAgent.COLLISION_LAYER_DWARF`). All three use `collision_mask = 0`.

### Placed Tree Rendering

Tree GLBs are Hearthblock models built by `tools/voxel_assets/trees.py`, exported in world
units (1 block = 1 Godot unit, root scale 1; see `63_shared_art_standard.md`). A tree's origin
is its trunk base, placed on the top face of the surface block (`get_surface_y + 1`).
`SurfaceFloraSpawner` overrides every mesh with the terrain material: vertex colour as albedo,
**lit** (`SHADING_MODE_PER_PIXEL`) and **double-sided** (`CULL_DISABLED`). Double-siding
stops the stepped canopy showing see-through back faces; lighting makes the facets read
as 3D like the ground. Trees bake their colours and use no runtime tint.

### Growth Stages

All trees share the same three-stage pattern:

- **Sapling** — `collision: "clutter"`, no `CollisionShape3D`. Appears via planting or world-gen.
- **Mature** — primary harvest target; full canopy collision. First harvestable stage.
- **Ancient** — largest visual and collision footprint. Wild ancients come from world-gen;
  planted trees grow into it (Planting Seeds below).

### Footprint Table

| Species | Sapling | Mature | Ancient | Planting area | Primary yield |
|---|---|---|---|---|---|
| Oak (`base:flora:oak_tree`) | clutter | 3×3 | 5×5 | 13×13 | Oak log |
| Juniper (`base:flora:juniper_tree`) | clutter | 1×1 | 3×3 | 7×7 | Juniper berry |
| Apple (`base:flora:apple_tree`) | clutter | 3×3 | 5×5 | 13×13 | Apple (fruit harvest) |
| Pine (`base:flora:pine_tree`) | clutter | 2×2 | 3×3 | 7×7 | Pine log |

Crowns overhang their trunks (measured from the models, widest season and variant, in
blocks): oak mature 12 × 11 and ancient 18.5 × 17, 23.5 high; apple 12 × 11 and 18.5 × 17,
17.5 high; pine 6 × 6 and 8 × 8, 27 high; juniper 6 × 6 and 9 × 8, 16 high. Below four blocks
a mature or ancient tree is only its trunk.

**Oak** is a spreading broadleaf. Mature oaks (3×3) are the primary surface obstacle and supply oak logs, which a carpenter will turn into staves for aging casks. Felling can also yield acorns, but never finished staves. Full schema: `data/flora/oak_tree.json`.

**Juniper** is a columnar evergreen. It stays 1×1 through maturity — dwarves can stand directly adjacent to fell it. Only the rare ancient juniper spreads to 3×3: an odd trunk, so a planted juniper stays centred on its seed (owner, 2026-10-29; it was 2×2, and the models' root flare follows the footprint). Full schema: `data/flora/juniper_tree.json`.

**Apple** is a spreading deciduous fruit tree with a canopy matching the oak (3×3 mature). Mature and ancient trees support perennial autumn picking, described above, with distinct ripe and picked visuals. Full apple schema: `data/flora/apple_tree.json`.

**Pine** is a tall conical evergreen — the primary source of basic construction lumber. Its cone is narrower than the oak's spreading crown (mature 2×2, ancient 3×3) but it grows fast and dense. Pine is the **elevation tree**: world-gen scatters it across the **foothill shelves and mountain slopes only — never the lowland shelf or settlement plain**, thinning to a bare-rock treeline near the peaks. Placement parameters are data-driven in the `placement` block of `data/flora/pine_tree.json`; the scatter and streaming logic lives in `SurfaceFloraSpawner`; placement across species is described under World placement below. Full schema: `data/flora/pine_tree.json`.

### Felling Yields

A felled tree gives logs by its size (owner, 2026-10-28). Bigger trees give more, and an
ancient tree gives about 2.5× its mature stage. Apple gives less than its size: felling it
ends a fruit tree, and applewood is the most valuable wood. Saplings give nothing. Seeds
are a separate chance roll, and the counts live in each stage's `harvest.yields`.

| Species | Mature | Ancient |
|---|---|---|
| Oak | 6 | 16 |
| Pine | 4 | 10 |
| Apple | 3 | 8 |
| Juniper | 2 | 5 |

- **The logs lie one to a tile over the cleared footprint**, nearest its centre first
  (`ItemDropManager.spawn_spread`). A tile holding a solid block is passed over; logs beyond
  the open tiles share them. A seed crate drops on the open tile nearest the centre.
- **A dwarf carries four logs a trip**, as with stones (log `carry_cost` 1, doc 31).
- **Each log takes its own stockpile tile**, so 16 is the most one tree gives.

### Planting Seeds

Live 2026-10-29 (doc 284). Each species' `planting` block in its JSON makes a Place → Plants
entry: Oak acorn, Apple seed, Pine cone, Juniper seed. The plan runs like a cutting's (doc 31,
"Cutting planting"): one seed from its crate, `planting.work_seconds` of planting, and the
seed is kept if the plan is cancelled. `TreePlanting` holds the rules below;
`SurfaceFloraSpawner` owns the planted trees.

- **Two squares, both centred on the seed:**
  - *The trunk ground* is the ancient footprint (by its `clearance_height`), so the trunk
    never runs out of room. At planting it must be level, solid and open to the sky, with no
    plant, stone, furniture or stockpile, and no bush or flower may be planted on it later.
    The seed cell needs a `planting.ground_kinds` block (grass, dirt, soil).
  - *The planting area* (`planting.area`) is the mature crown (owner, 2026-10-29: the
    ancient crown, 19 × 19 for oak, was too big). No other tree may stand in it: a wild
    trunk, counted from the seeded candidates so trees not yet streamed in count too, or
    another planted or queued tree's area. Areas may touch but never overlap, so mature
    crowns never meet; ancient crowns may overlap by up to about 5½ blocks for oak and apple,
    2 for juniper and 1 for pine, about as much as the wild forest's. Below four blocks a tree
    is only its trunk (doc 63's walking clearance), so bushes, flowers, furniture and paths
    still go under the crown.
- **The trunk grows round the seed.** Odd footprints stay centred on it; the one even
  footprint, the pine's mature 2 × 2, takes the seed's +X/+Z side until the 3 × 3 ancient
  trunk centres again.
- **Growth** follows `stages.*.growth_duration_days` (sapling → mature, mature → ancient),
  weighted by `planting.seasonal_growth` (spring 1.2, summer 1, autumn 0.8, winter 0), as
  cuttings do: saved `growth_credit` plus `WorldClock.seasonal_days_between()` since
  `planted_at`, checked on the hour. A clock jump can take two stages at once.
- **Growth waits for room.** A new stage needs its footprint × `clearance_height` to be level
  ground and open air with no blocks, furniture or furniture plan, stockpile, ladder or other
  placed thing, loose items, dwarves or animals in it (`TreePlanting.room_reason`); the tree's
  own trunk doesn't count. The panel says what is in the way. Growth also
  waits while a felling or picking order is on the tree.
- **Planted trees are trees.** They fell, drop logs and seeds, pick fruit and block dwarves
  like wild ones. A planted tree's id is its seed's column; its saved change carries
  `planted`, `anchor` (the seed cell), `planted_at` and `growth_credit`. A seed may go where
  a felled tree stood, and the wild tree of that column never returns. Seed drops roll on the
  planting hour as well as the column, so a replanted spot rolls afresh.
- **Not built:** wild trees don't grow, and a sapling, wild or planted, floats if the ground
  under it is mined.

### World placement

The settlement plain is fully forested: trees grow everywhere suitable, and the player clears land to build. There is no special forest belt at the map edge; the normal rules run to the border. Apples grow wild in groves; players plant them from seeds (Planting Seeds above).

Each species has an elevation, domain and moisture niche, and all species share one scatter grid (`SurfaceFloraSpawner.scatter_cell_size`). Each cell holds at most one tree: every species is scored for suitability there, and one is chosen by a seeded weighted pick, or the cell is left open. This blends species across the gradients and prevents overlapping trunks. Placement is a pure function of `world_seed` and column position, so it needs no save data; saves store only changed trees (felled, designated, harvested). Moisture is a seeded noise map that reads drier with altitude and wetter beside water (`WorldGenerator.get_moisture`). Per-species keys (domains, height band, moisture band, `base_density`, slope and edge limits, footprints, stage weights) live in the `placement` block of each `data/flora/*_tree.json`. Apple suitability is also gated by a grove mask, so wild apples cluster into groves.

The planned trade road (doc 51) must exclude flora from its road strip.

### Fruit Trees

**Implementation boundary:** player-designated annual picking is live for
juniper (84) and apple (252). Neither species automatically queues harvest orders.

A fruit tree has two independent harvest mechanisms:

**1. Fruit harvest (non-destructive, annual):** Defined by a `fruit_harvest` block
on the stage. Each autumn, eligible trees become ready to harvest. The player
designates picking through the inspector or Harvest plants click/drag tool. A
dwarf gathers fruit by hand at a reachable side of the trunk and leaves the
crop there for ordinary hauling or eating. The tree persists.
Cancel/Undo releases the worker without losing the
current crop's partial work. The same tree cannot be picked twice that autumn;
the next year's crop starts with fresh work. No automatic annual orders are posted.
Only stages whose `fruit_harvest` has `work_seconds` post a job
(`SurfaceFloraSpawner.can_harvest_tree`). A marked tree carries one action at a
time, so felling and picking never run together: cancel one before ordering the
other. Each keeps its own saved progress (`fell_work_seconds`,
`harvest_work_seconds`), which never transfers. A crop is one year and season;
completion stamps `harvested_cycle` before any fruit spawns, so cancellation,
reload, streaming or a stale completion cannot repeat it, and leaving autumn
cancels pending and active picking. The crop lands on the picker's own cell, the
reachable side of the solid trunk.

`SurfaceFloraSpawner.resolve_tree_model_for_season()` takes a `picked` flag from
the saved `harvested_cycle`. Stages with `picked_models` (juniper) use them after
picking or outside `harvest_season`, so berries show only on an unpicked autumn
crop. Apples select `autumn_fruiting` only while that autumn's crop is unpicked;
after picking they use the matching ordinary autumn model without fruit. Saved
crop state drives the choice after reload or streaming, and season reconciliation
also runs when a restore changes only the year. A crop change replaces only the
visual child (`_refresh_tree_crop_visual`); the trunk body, occupancy and
reservations stay.

**2. Chop harvest (destructive):** Works the same as any other tree — dwarf fells the tree, yielding wood and a seed drop. Apples come exclusively from the non-destructive fruit harvest, not the fell.

| Species | Fruit item | Season | Mature yield | Ancient yield |
|---|---|---|---|---|
| Apple | `base:item:apple` | Autumn | 4–6 | 7–10 |
| Juniper | `base:item:juniper_berry` | Autumn | 2 | 4 |

A yield is either a fixed `yield_count` (juniper) or an inclusive
`yield_min`/`yield_max` (apple) picked by a deterministic tree/year hash, so
interruption and reload cannot reroll it. Picking takes four seconds for mature
apples and six for ancient apples; juniper picking takes three seconds at either
adult stage. These values live in JSON, as do `action_label` and `yield_label`,
which name the panel action and the worker's activity (apples: **Gather apples**,
"Harvesting apples"; without them, **Harvest berries** and "berries"). Hungry
dwarves eat gathered fruit through the normal food system; emergency
self-foraging of standing plants still targets nearby ripe berry shrubs.

> **Agent note**: Trees are the **only** surface entities with real collision shapes. Giving a `CollisionShape3D` to any farm crop violates the Single-Tile Asset Overflow Rule above.

---

## Surface details

Boulders, scree, wild berry shrubs, wildflowers and reeds are surface details:
placed entities, never terrain blocks. `SurfaceDetailRegistry` loads their
definitions from `data/terrain/surface_details.json` and the flora
`*_bush.json` files; `SurfaceDetailPlacement` scores candidates and
`SurfaceDetailManager` owns the layout, removals and saved changes. They sit
beside the tree layer described under World placement and never change it.

- **Placement comes from seed and category only.** A candidate derives from
  `world_seed`, the definition's own hash salt and its scatter cell, sampled
  against generated terrain and water. Loaded visuals, streaming order, camera
  position and current occupancy never decide where a detail goes. Untouched
  details regenerate on load; saves store only changes (removal, moves, partial
  work, crop state).
- **Precedence.** Generated tree candidates come first: a detail whose area,
  plus its `tree_margin`, meets a tree candidate is rejected, even where that
  tree has not streamed in. Remaining candidates are arbitrated by JSON
  `placement_priority`, highest first, with ties broken by id: boulder 100,
  scree 50, blueberry 20, elderberry 19, wild strawberry 18, flowers 10,
  reeds 5.
- **Conflicts resolve before saved removals apply.** Arbitration runs on the
  immutable candidate set, so clearing a detail never lets a previously rejected
  one appear on reload.
- **Terrain is never flattened to fit a detail.** An unsupported footprint is
  rejected, not levelled.
- **Removal is committed before any reward.** The detail is tombstoned first and
  the drop spawned after, so cancelling, season changes or reloading cannot
  repeat a yield.
- **Construction or loss of supporting ground removes a detail with no reward.**
  Placed structures and terrain edits under a detail remove it permanently;
  season changes, camera movement and loading never bring it back.
- **Only boulders block.** A boulder registers its 2×2 footprint (2 high) in
  `PlacedEntityRegistry` and gets a `StaticBody3D` on physics Layer 2 with
  `collision_mask = 0`. Every other detail is non-blocking: no occupancy and no
  collider (Hard Rule 5 for plant overhangs).
- **Plants keep exclusive planting areas.** Bushes and flowers have
  `planting_radius` 1: `SurfaceDetailPlacement.planting_area()` covers the 3×3
  columns around the root, from the ground's top up three blocks (or the plant's
  height). Areas may touch but never overlap, so centres in a row stand at least
  three blocks apart and two-block diagonal offsets are rejected; plants on
  different terrain levels never collide just because their X/Z match.
  Generation, moved and stored plants, cuttings (given the mature area from
  planting) and queued Place destinations all use it. A queued plan reserves its
  area at once, cancelling releases it, restore rebuilds it from the saved plan,
  and a completing plan ignores only its own reservation. The areas carry no
  occupancy, so dwarves walk through them.
- **Reeds use actual nearby water.** A reed roots on a dry bank within
  `shore_radius` (4, Manhattan) of a generated water cell, 0–2 blocks above
  that body's local waterline (`min_bank_height` / `max_bank_height`). The
  water-bank mask is only a cheap prefilter; never place from the mask alone or
  assume the waterline is Y18.
- **Densities change only with measurement.** Before raising any category's
  population, repeat a paired comparison of the same seeds and camera paths with
  and without details (counts, frame time, draw calls, memory).

---

## Model Variant Resolution

Tree species JSON (`data/flora/*.json`) supports two formats for each season key inside a stage's `models` block:

```json
"summer": "res://assets/models/flora/trees/oak/oak_mature.glb"       // single string — always this model
"summer": ["path_1.glb", "path_2.glb", "path_3.glb"]                // array — pick one at spawn
```

When the value is an array, the tree system picks one entry **once at spawn time** using a deterministic hash of the entity's world position. The same position always yields the same variant — no save data is needed and no runtime flickering occurs.

### Variant Picker Pattern

Any system that places a tree entity (world-gen, planting task) must resolve the model path before attaching the `MeshInstance3D`. Use this utility function:

```gdscript
# Resolves a tree stage's seasonal model to a single resource path.
# Call once at spawn; cache the result on the entity.
#
# models_value : the JSON value for a season key — either a String or Array[String]
# world_pos    : the entity's grid position (Vector3i) — used as the hash seed
#
static func resolve_tree_model(models_value, world_pos: Vector3i) -> String:
    if models_value is String:
        return models_value

    if models_value is Array and not models_value.is_empty():
        # Spatial hash — reproduces the same index for the same position every time.
        var h: int = (world_pos.x * 73856093) ^ (world_pos.z * 19349663) ^ (world_pos.y * 83492791)
        return models_value[abs(h) % models_value.size()]

    push_error("resolve_tree_model: invalid models_value at %s" % str(world_pos))
    return ""
```

Place this as a `static func` on whichever system owns tree entity placement. It currently lives on `SurfaceFloraSpawner` (the surface-flora scene node, `scripts/systems/SurfaceFloraSpawner.gd`), which all tree spawners call. Do **not** scatter the hash logic across multiple callers — there must be exactly one resolution point.

### Season Fallback Order

When the current season key is absent from a stage's `models` dict, fall back in this order:

```
requested_season → "summer" → push_error and return ""
```

Pine and Juniper omit `spring` and `autumn` deliberately — `"summer"` is their defined fallback for those seasons. The resolver must handle a missing key gracefully before attempting variant resolution.

```gdscript
static func resolve_tree_model_for_season(
        stage_data: Dictionary, season: String, world_pos: Vector3i, picked := false) -> String:
    var models: Dictionary = stage_data.get("models", {})
    var fruit: Dictionary = stage_data.get("fruit_harvest", {})
    # Berry-free art after picking or out of season (juniper; see Fruit Trees).
    if stage_data.has("picked_models") and (picked or season != String(fruit.get("harvest_season", ""))):
        models = stage_data.picked_models
    if not picked and season == "autumn" and stage_data.has("fruit_harvest") and models.has("autumn_fruiting"):
        return resolve_tree_model(models["autumn_fruiting"], world_pos)
    var value = models.get(season, models.get("summer", ""))
    if value is String and value == "":
        push_error("resolve_tree_model_for_season: no model for season '%s'" % season)
        return ""
    return resolve_tree_model(value, world_pos)
```

### Variant Counts by Species

| Species | summer | autumn | spring | winter | Notes |
|---|---|---|---|---|---|
| Oak | 3 | 2 | 1 | 1 | Deciduous; all four seasons |
| Apple | 3 | 2 | 1 | 1 | Same as oak; `autumn_fruiting` is a separate single-model key |
| Pine | 3 | — | — | 2 | Evergreen; spring/autumn fall back to summer |
| Juniper | 2 | — | — | 1 | Columnar; less shape variance than spreading species |

Sapling stages are always single-model strings. Variants are mature and ancient only.

---

*Prev: [41_dwarf_agents.md](./41_dwarf_agents.md) | Next: [43_mining_materials.md](./43_mining_materials.md)*
