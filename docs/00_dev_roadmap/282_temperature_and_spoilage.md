# 282 — Temperature and food spoilage

2026-10-29. The plan, with the owner's picks. All three phases are built and wait on the
owner's look in Play: the climate and the Temperature view (phase 1), spoilage (phase 2)
and heat spreading (phase 3).

From the owner: temperature only works inside rooms and seems to affect only how dwarves
sleep. Food should spoil: berries stored outside in the weather should be penalised, kept
indoors they should last longer, and the cooler the store the slower they should spoil. The
owner also asked for a review of where a colony can start, dig into the mountain and keep
its first food; whether higher in the mountain or deeper underground should be colder; and
whether heat and cold can spread between rooms that aren't sealed. After the review below,
the owner accepted the recommended choices.

## Decisions (owner, 2026-10-29)

1. **Higher is colder; deeper is steadier.** One height rule for air and rock: 1°C colder
   per 12 blocks, one mountain shelf. Rock damps the seasons, so deep places barely change
   through the year, and the deepest are a little warmer.
2. **A wider climate.** Winter nights freeze and summer days are warm: over a year the
   valley runs from about −8 to 26°C, the summit from about −16 to 18°C.
3. **Food spoils** faster the warmer it is, nearly stops when frozen under a roof, and
   spoils faster under the open sky, more in rain or snow. Rotten food is simply gone, with
   an Events line; there is no rotten item for now.
4. **Heat and cold travel a short way through open air:** outside air about 12 blocks into a
   tunnel, a fire's warmth a few blocks. Doors and rock stop them, and a closed door leaks a
   little. Temperatures settle at once: no warm-up time and nothing new to save.
5. **A Temperature view** (asked the same day): a heat map the player turns on with T. It
   must stay cheap; nothing in it runs every frame. See "The Temperature view".
6. **Warm rooms keep their fires unlit** (answering "Hearths on warm nights", the same day):
   a fire in a sealed room is lit only while the room is below Comfortable without it.
   Built with phase 1; the rule is in doc 34.

Still open: see "Open" at the end.

## The review: what is built

### Temperature

- **One formula.** RoomManager owns temperature and `data/world_gen/temperature.json`. Rock
  is 10°C; the season adds up to ±6°C and the time of day ±2°C, both multiplied by an
  exposure, `exp(−cover / 16)`, where cover is the natural surface height above minus the
  cell's height. A sealed room takes a quarter of its floor columns' mean exposure.
- **Outdoors stays between 2 and 18°C all year.** It snows in winter but never freezes, and
  summer never gets warm. Weather doesn't change the temperature.
- **A room exists only behind doors.** RoomRebuild's flood fill starts beside door cells and
  gives up past 4,096 cells. An unheated sealed room is always 8–12°C: Chilly.
- **Heat counts only in a sealed room:** heat units ÷ max(volume, 128). Log torch 75,
  campfire 900, rudimentary hearth 1,600; the campfire and hearth count only while they
  burn, dusk to dawn (doc 279). A fire anywhere else warms nothing, so the campfire warms no
  one sitting round it.
- **Unsealed places use the cover alone** (`RoomManager.temperature_at`). A tunnel one block
  into a cliff under a tall shelf counts as half shielded although the wind blows straight
  in: outside air never travels into tunnels.
- **Rooms don't share heat.** A hearth never warms the corridor or the room next door; doors
  and rock insulate perfectly.
- **One effect on play:** the sleep thought (Cold −20, Chilly −5, Hot −15; doc 34). The Rooms
  tool, the room inspector, the DEV block inspector and the hearth's panel show temperatures.
- **Dead ends.** The Frozen vault label (0°C or below) can't appear, because the coldest
  sealed room is 8°C. Doc 42's Aging Cellar and "Frozen Vault and Food Preservation" still
  describe the depth model doc 34 replaced on 2026-10-11: lower was colder, frozen at about
  Y35 and below, warmed by braziers.

### Food and storage

- **Five fruits are edible,** each worth 0.6 Food: wild strawberry, blueberry, elderberry,
  juniper berry and apple. None spoils.
- **Storage.** Harvested fruit drops in loose produce crates (24 units) and is hauled to
  ground storage zones, which can go anywhere, outdoors included. Storage furniture left on
  2026-10-22 and returns with its own milestone (`00_todo.md`, Storage).
- **The fruit calendar.** Strawberries in spring and summer, blueberries in summer;
  elderberries, juniper berries and apples in autumn; nothing in winter. A dwarf eats about
  three fruit a day (Food drains 0.075 a game hour), so five dwarves need about 315 for a
  21-day winter.
- **Spoilage on today's temperatures wouldn't help.** The best and worst places would differ
  only two to four times in speed; a winter yard (2–6°C) would be the best larder in the
  game and a hearth bedroom (19–25°C) the worst.

### The start

- The flag can go on any dry, standable ground, the summit included, and the five dwarves
  bring nothing. A new game starts on summer's first day, the warmest of the year.
- Food grows low down: berry bushes at Y4–43 and apple trees up to Y30; juniper grows in
  every domain. The natural start is the valley at the foot of a cliff: forage outside and
  tunnel in.
- Today it makes no difference where food is stored, so nothing asks for a larder.

### Height or depth

- In reality air cools with height, about 6.5°C per kilometre. A few metres down, rock sits
  at the year's average temperature of the air above it; deeper still it warms, roughly
  2.5–3°C per 100 m. A cellar feels cold in summer because it is shielded, not because depth
  is cold.
- The summit stands 96 blocks, about 48 m, above the valley floor: real air would cool by a
  third of a degree. The game exaggerates on purpose, as it already fits a year into 84 days.
- The old "lower is colder" model fought the world: the valley floor itself is at Y19, the
  best ores lie deepest, and it reads wrong beside snowy peaks.
- Other games: RimWorld rots food by temperature, stops it when frozen and has a separate
  deterioration for things left under the open sky, the same split as here. Oxygen Not
  Included simulates heat tile by tile, which would be far too heavy for a 1024 × 128 × 1024
  world.

## The model

What a player can learn: higher is colder, rock damps the seasons, day and night reach only
as far as open air, doors and rock stop air, and fires add heat.

```
T       = mean(y) + season × e_season + (day + weather) × e_air + heat

mean(y) = 9°C − (y − 19) / 12        1°C per 12 blocks; the valley floor is Y19
season  = 12°C × WorldClock.solstice_cosine(day_of_year)
day     = 5°C × sin((hour − 8) / 24 × TAU) × the weather's daily scale
weather = the weather's offset
```

| Place | e_air | e_season |
|---|---|---|
| Open sky: no solid block anywhere above, built roofs included | 1 | 1 |
| Under a roof, not sealed | a | max(a, rock) |
| Sealed room | 0 | mean of rock over its floor columns |

- **a**, the outside-air reach: 1 at an open-sky cell, falling evenly to 0 at 12 blocks of
  walking distance through air. Doors stop it. It is the same reach daylight uses at
  entrances (`UndergroundLighting`, 12 blocks), worked out separately for play, since the
  lighting is presentation only.
- **rock** = `exp(−cover / 8)`. Cover counts the solid blocks over the spot in its column
  as they are now: built blocks are included, and caves the colony has not found count as
  rock. For a room it is measured over each column's lowest air. Rock damps the seasons
  within a few blocks, and day and night don't get through rock at all. This replaced the
  16-block damping and the sealed room's quarter.
- **Changed while building:** the plan counted cover from the natural heightmap, as before.
  Counting real blocks lets built roofs and stone stacked on a hut insulate, and mining
  above a room thins its cover.
- A room's height is its mean floor height.
- A roof keeps the weather off, not the cold: a roofed spot next to open air still follows
  the outside temperature.

Each weather gets a `temperature` block in its JSON. WeatherManager owns those files; the
climate reads them through `WeatherManager.current_definition()`.

| Weather | Offset | Daily scale | Wet |
|---|---|---|---|
| Clear | 0 | 1 | no |
| Overcast | 0 | 0.5 | no |
| Foggy | 0 | 0.4 | no |
| Rain | −1°C | 0.4 | yes |
| Storm | −2°C | 0.4 | yes |
| Snow | −2°C | 0.4 | yes |

### Targets

The numbers above are a starting point. Phase 1 tunes them until these hold to about 1°C.
Built: `ClimateTest` measures each at the year's extremes, and all hold with the starting
numbers (2026-10-29).

| Place | Over a year |
|---|---|
| Valley, open sky | −8 to 26°C; days average ~21°C at the height of summer, ~−3°C in winter |
| Summit, open sky | −16 to 18°C |
| Tunnel from the valley floor into a Y35 shelf, 6 blocks from open air | about 0 to 17°C |
| The same tunnel 12 or more blocks in | 7–11°C |
| Sealed valley larder under 12 solid blocks | 6–12°C; 5–13°C since phase 3, its door onto the valley letting in 9% of its swing |
| Sealed cellar just under the summit (floor Y100) | −1 to 5°C; frozen about two weeks around the coldest day, winter's first |
| Deep under the mountain at the valley's height | 9°C, steady |
| Near bedrock under the valley (Y6) | 7–13°C |
| One-hearth 6 × 6 × 4 bedroom in the valley | 17–23°C, Comfortable all year; since phase 3, 15–23°C with its door onto the valley (Chilly on the coldest nights), about 16–22°C behind an entry room |
| The same bedroom just under the summit | 10–16°C with one hearth; 21–28°C with two (its door into rock, so phase 3 leaves it) |

Sleep comfort keeps its thresholds (Cold below 8°C, Comfortable 16–26°C). An unheated valley
bedroom becomes Cold in winter instead of Chilly all year; living high costs more firewood.

## The Temperature view

From the owner: the player needs to see temperature, as a heat map, without it being
taxing; it needn't refresh every frame. Doc 23 already says later views, "temperature or
light, say", follow the Appeal view: dim the world, colour what counts, give every number a
word, and take a line in the banner. So this is the dock's second view, between Appeal and
X-ray.

- **Toggle:** a button with the existing thermometer icon (`assets/ui/icons/thermometer.png`)
  and the key T, a new `view_temperature` input action (T is free). It is a view, not a
  tool: other tools work while it is on. It starts off in each session and is never saved.
- **What it shows:** the world dims as in the Appeal view, and every floor in view takes
  its temperature's colour: open ground, tunnels, the caves the colony has found and sealed
  rooms. Slice and X-ray work as they do for Appeal, so rooms below the surface show once
  sliced. Hidden caves count as rock (Hard Rule 11).
- **Words:** a scale above its button names five bands with their ranges: Hot above 26°C,
  Comfortable 16–26°C, Chilly 8–16°C, Cold below 8°C, Frozen 0°C and below. These are the
  sleep thought's words from `temperature.json`, plus Frozen.
- **Hover:** a card gives the temperature and its word ("9°C · Chilly"), what sets it
  ("Sealed room: Larder", "Tunnel, 6 blocks from open air", "Open sky, raining") and its
  range over a year ("Over a year: 6–12°C"), which is what a player choosing a larder needs.
  Phase 2 adds how long food keeps there. Clicking a room opens its window, as in the Appeal
  view.
- **Banner:** "Temperature view" and a line, for example "How warm each place is".

**Cost.** The view does nothing while off, and while on nothing in it runs every frame:
- It builds floors in tiles of 16 × 16 columns around the view, nearest the camera first,
  within 2 ms a frame (built at 2 ms rather than the 1 ms first planned, so the range fills
  in about three seconds).
- Each floor quad carries three numbers: its base temperature (height and heat), how much
  it feels the season, and how much it feels the day and the weather. A small shader works
  out the colour from two values set once per game hour, so the clock moving rebuilds
  nothing.
- A tile is rebuilt only when it comes into view, when the slice moves, or when its blocks,
  doors or a room's heat change. Changes are gathered for half a second, as room rebuilds
  are. Neighbouring quads with the same numbers merge, so a flat shelf is a few big quads.
- Hovering works out one spot with the same rules; nothing is scanned.

**Concepts first.** As with any new UI, the owner picks from options that differ in format,
drawn in real cells over the real game at both sizes, for example:
- A, a banded wash over every floor, the Appeal view's treatment;
- B, isotherm lines at the band edges with their numbers, the floors lightly tinted, like a
  weather map;
- C, a probe: only a radius round the cursor takes colour, and the rest stays dim.

The colours are part of the pick: temperature reads naturally from icy blue to red, which
bends doc 23's "cool for bad, warm for good", since hot is bad too. So is whether the cut
rock shows what a room dug there would be.

## Spoilage

- **Freshness.** Each stack carries `spoil` from 0 (fresh) to 1 (rotten): a crate in storage,
  a loose crate or a portion in hand. Merging stacks averages their spoil by count; taking
  units out copies it. Fruit on the bush never spoils, and carried fruit spoils where its
  carrier is.
- **Speed**, worked out each game hour from the place's temperature (the model above):

```
speed  = 2.5 ^ ((T − 20) / 10)           1 at 20°C; ×2.5 for every 10°C warmer
speed  = 0.05 when T ≤ 0°C under a roof  frozen nearly stops
speed += 1.0 under the open sky          1.5 in rain, storm or snow, frozen or not
spoil += speed / (24 × keeps_days) each game hour
```

- **Keeping time** is item data: `food.keeps_days` in `resources.json` (ContentRegistry), the
  days a fruit lasts at 20°C under a roof. Wild strawberry 2, elderberry 2, blueberry 4,
  apple 15, juniper berry 40. The rest is `food.spoilage` in `task_config.json` (TaskManager).
- **Rotting.** At 1, the stack's unclaimed units are gone and Events says so ("12 blueberries
  rotted in Storage zone 2"). Units already claimed for a meal or a haul stay until used. A
  worker who lets go of a carried portion drops it as usual, with its spoil, and it rots at
  its next hour if due; Hard Rule 12 holds.
- **Eating order.** The food search prefers the source closest to rotting among those nearly
  as close as the nearest one (a route margin in `food.spoilage`).
- **Warnings and readouts.**
  - Events warns once when a stack passes 75%.
  - The storage window shows the zone's temperature, whether it lies under open sky, and how
    long its most perishable food keeps there (blueberries when it is empty).
  - The item and crate inspectors show "Fresh", "Spoiling: about N days left" or "Frozen".
  - The layout needs the owner's concept pick, as for any new UI.
- **Saves.** `spoil` saves with zone stacks (`StockpileZoneComponent.cell_stacks`), loose
  items and carried items (ItemDropManager's item metadata and the carried-item save). Older
  saves aren't supported.

What it gives, with blueberries keeping 4 days and apples 15 days at 20°C:

| Place | Temperature | Blueberries keep | Apples keep |
|---|---|---|---|
| Valley yard, summer | ~21°C | ~2 days | ~7 days |
| The same in rain | ~20°C | ~1.6 days | ~6 days |
| Valley yard, winter | ~−3°C | ~3.5 days | ~13 days |
| Tunnel, 6 blocks in, summer | ~15°C | ~6 days | ~24 days |
| Valley larder, or a tunnel 12+ blocks in | ~9°C | ~11 days | ~41 days, two seasons |
| Cellar just under the summit | ~2°C | ~21 days, a season | ~78 days, most of a year |

Elderberries keep about 5 days in a valley larder and 10 in the cellar under the summit,
longer while it is frozen: not a whole winter, which leaves room for brewing them into wine
later. Kept cool, apples and juniper berries (about 110 days in a valley larder) carry a
colony through winter.

**Balance target.** A five-dwarf colony that keeps its autumn harvest in a cool cellar gets
through its first winter with at most a few hungry days; one that leaves it in the yard goes
hungry for most of the winter. Hunger never kills (doc 41): famished dwarves lose 15
happiness and work 25% slower. Phase 2 checks this against the apple, juniper and elderberry
counts near a few real starts before the keeping times are accepted.

## Heat and cold spreading

- **Fires warm open air.** A burning fire outside a sealed room warms the air within its
  radius by walking distance, fading to nothing at the edge: heat units ÷ 150 at the fire
  (campfire 6°C, hearth about 11°C, torch 0.5°C), over 5 blocks for the campfire, 4 for the
  hearth and 2 for a torch. The radius goes in each fire's `heat_source` data. Doors and
  solid blocks stop it. In a sealed room heat works as today.
- **Doors leak a little.** Each door moves a sealed room about 10% of the way toward the
  temperature on its other side, another room or the open place beyond, scaled down for big
  rooms (× 128 ÷ volume). Two passes settle a chain of rooms. A hearth room then warms the
  larder or corridor next to it by a degree or two and loses about as much.
- **No warm-up time.** All of this settles at once, each hour and on changes, with nothing to
  save. Thermal mass can come later if a feature needs it, such as an ice house.
- **Big halls.** Space past 4,096 cells stays unsealed as today. Far from open air it sits at
  rock temperature anyway, and fires warm it locally, so the cap needn't change.

## Phases

### Phase 1 — Climate and the Temperature view

**Progress (2026-10-29):** phase 1 is built: steps 1 and 2, then the view (step 3) after
the owner picked A, the wash, with C's details on its hover card. It waits on the owner's
look in Play.
- **Code:** `scripts/components/Climate.gd`, owned by RoomManager (`RoomManager.climate`).
  RoomManager gains `temperature_at` for every spot, `climate_at` and `temperature_word`;
  RoomRebuild works out the seasonal share. `temperature.json` has the new keys, and the
  weather files have their `temperature` blocks.
- **The `weather_changed` signal** came with step 3: the view's colours follow it.
- **Tests:**
  - `ClimateTest` (rooms area) measures every target.
  - HearthRoomTest, BedroomComfortTest and BedOwnershipTest stack 11 blocks of stone on their
    rooms (`BedroomTest._bury`), so the rooms stand for cellars. HearthRoomTest also breaches a
    wall instead of the buried roof.
  - RoomRebuildSchedulingTest compares geometry with its frozen detector and checks the
    climate fields against the rule.
- **Docs:** 34, 42 and 24 describe the climate.
- **Warm rooms keep their fires unlit** (decision 6): `FurnitureFires.needed` re-checks on
  room changes, and FireLightingTest covers a hut's two hearths through summer, spring and
  winter. Before it, a 6 × 6 × 4 hut under a one-block roof ran 9 to 30°C with its hearth
  burning every night.
- **Step 3, the view, is built** (2026-10-29): `TemperatureViewController` (a scene node
  beside the Appeal view's), `temperature_view.gdshader`, its button, scale, banner line
  and T key (`view_temperature`), and the Controls list. The Appeal view and it take turns.
  Doc 23 "The Temperature view" has the rules, and doc 24 the drawing.
  - **The pick:** A, the wash, with C's details on its card: steps from open air, blocks
    overhead and the year's range. A heated room's card gives its year without its fires,
    which burn only while it is cold ("Over a year: 24 to 34°C" read as if the fires burned
    all summer).
  - **Cost, measured** in the copy of the owner's colony: 81 tiles in 3.0 s at 2.01 ms a
    frame (worst 2.59 ms); moving the slice builds them again in 1.1 s, keeping the
    floors' numbers. Reading columns a chunk at a time made the climate's column profile
    18 times cheaper (0.21 to 0.012 ms), with the same profiles on 3,072 columns; without
    that the view would have taken minutes to fill.
  - **Tests:** `TemperatureViewTest` (rooms and ui areas) covers the button, the scale,
    nothing built while off, the budget, each floor's numbers against `temperature_at` at
    the year's extremes and in rain, an hour and the weather building nothing, an edit
    building only the tiles within reach, the slice, a hidden cave as rock until found, the
    card, the click and taking turns with Appeal. TimeSliceHUDTest and GameMenuTest know the
    new button and key.
  - **Pictures:** `tmp/temperature_view_20261029/*_built_*.png`.
  - **Runs:** gate 55/55, the rooms and ui areas 40/40, the lint nothing new.
- **Step 3's concepts** (2026-10-29), from which the owner picked A:
  - **Where:** the three formats over a copy of the owner's colony, at 7680 × 2160 (150%)
    and 1920 × 1080, in `tmp/temperature_view_20261029/` (`sheet_*.png` put today, A, B and
    C side by side).
  - **For the pictures only:** a tunnel, a larder and a two-hearth bedroom dug into the Y55
    shelf east of the flag, never saved.
  - **Two moments:** a spring morning, when outdoors is Chilly and the tunnel and the cellars
    Cold; and a winter night, when outdoors is Frozen and the bedroom Comfortable with both
    hearths lit.
  - **What they show:** every colour is the live climate's. The dim, the floor quads, the
    card, the scale and the banner are the Appeal view's own pieces.

The work, in order:
1. **Rules and data.**
   - The model above lives in a component owned by RoomManager, as RoomRebuild is.
     RoomManager keeps the temperature data, the API and the signals.
   - `temperature_at(cell)` stays the one call for every reader. A new `climate_at(cell)`
     also gives the word, what sets the temperature and its range over a year, for the view
     and the DEV block inspector.
   - `temperature.json` gets the new keys and drops `sealed_exposure` and the 16-block
     damping (the lint fails on unused keys).
   - RoomRebuild works out each room's new seasonal exposure.
   - `ClimateTest` comes first, and the numbers are tuned to the targets.
2. **Open sky, outside air and weather.**
   - Open sky: a test per column against current blocks (built roofs count; furniture and
     water don't), cached and cleared on `WorldData.block_changed`.
   - Outside-air reach: one bounded search per 16 × 16-column tile, spreading from the
     open-sky cells into roofed air for 12 steps with doors blocking. It is cached per tile
     and cleared by block and door changes within 12 blocks. Game calls and the view share
     it, and nothing is worked out until something asks.
   - Weather: the six weather files get their `temperature` blocks.
3. **The Temperature view:** concepts, the owner's pick, then the build (see "The
   Temperature view"). WeatherManager gets a `weather_changed` signal (it has none today),
   so the view's colours follow a weather change as they follow the hour. The DEV block
   inspector also shows any spot's `climate_at`.
4. **Docs and handover.**
   - 34 rewritten for the model.
   - 42's Aging Cellar and Frozen Vault sections rewritten to the height rule: gin high in
     the mountain, stout in the middle, wine in valley cellars.
   - 24 gets the weather effects; 23 gets the view and its key.
   - Then the owner looks in Play.

- **Saves:** nothing new; the climate is worked out, never stored.
- **Tests:**
  - `ClimateTest` checks the targets, weather, roofs, doors stopping outside air and the
    height rule, and writes its table to `tmp/` for tuning.
  - `TemperatureViewTest` checks that the view:
    - costs nothing while off;
    - builds its tiles within budget;
    - rebuilds nothing when an hour passes;
    - rebuilds only the tiles within reach of an edit;
    - shows hidden caves as rock;
    - fills its hover card.
  - `BedroomComfortTest`, `HearthRoomTest` and `BedOwnershipTest` move to the new numbers.
- **Done when** the targets hold, the job gate is green and the owner has looked in Play.

### Phase 2 — Spoilage

**Progress (2026-10-29):** the rules are built; the freshness readouts wait on concepts.
- **Built:** `scripts/components/FoodSpoilage.gd`, owned by StockpileManager
  (`StockpileManager.spoilage`), with the rule, rotting and Events lines exactly as in
  "Spoilage" above. Doc 42 "Spoilage" now holds the rules.
  - **Data:** `keeps_days` and `plural_name` for the five fruits; `food.spoilage` in
    `task_config.json`.
  - **Bookkeeping:** spoil follows food through every split, merge, deposit and withdrawal
    (`ItemDropManager.spoil_of`, `blend_spoil`), and saves with zone stacks, loose and
    carried goods.
  - **Eating order:** the food quote ranks distance less 12 blocks times spoil (doc 41).
  - **The Temperature view's card** says how long blueberries keep at the spot.
- **Found while building:** a rotten crate left in the tree for the rest of its frame could
  still be found as a zone's stored crate; `ItemDropManager.discard` takes it out at once.
- **Tests:** `FoodSpoilageTest` (storage and dwarves areas) covers speeds, frozen, open sky
  and rain, the hours' gain on stored, loose and carried food, splits and merges, rotting with
  its Events lines, the 75% warning, claimed portions and food in hand kept, saves, eating
  order and the hourly pass over frames. `SaveManagerRoundTripTest` saves a part-spoiled
  crate; `TemperatureViewTest` checks the card's new line.
- **The winter balance check fails on supply, not on keeping.** Counted in the copy of the
  owner's colony (`tmp/temperature_view_20261029/FoodCount.gd`): within 48–64 blocks of the
  flag and of three other spots there are 0–2 apple trees, 2–8 junipers and 0–7 elderberry
  bushes, so 10–25 apples and juniper berries an autumn. Five dwarves eat 15 portions a
  day, 315 a winter. A day-by-day model of the rule (scratch `winter_model.py`) leaves every
  start hungry for 15–21 of winter's 21 days, cellar or yard. Given 300 apples and juniper
  berries and six elderberry bushes, a valley cellar feeds the whole winter and the yard
  leaves 12 hungry days, so the keeping times give the intended difference. The keeping
  times stay; winter food supply is an open question for the owner (see "Open").
- **Runs:** gate 55/55 with the lint clean; the storage, dwarves, rooms, saves and hauling
  areas 48/48; crafting, furniture and construction 42/42. The gate caught one slip on the
  way, fixed: crafting and equipment compare the quotes' `distance`, which the food quote
  keeps alongside its new `score`. FruitHaulingTest fails about two runs in five even alone,
  at "blocked side basket": the optional fruit route planner (`FruitHaulPlanner`) claims a
  walled-in basket, which no spoilage code touches.
- **The readouts are built** (2026-10-29) from the owner's pick, "A tag + B list": A's status
  tag on the crate panel and B's Keeping list in the storage window (`StorageKeeping.gd`).
  Doc 23 has the rules. They refresh after each spoilage pass (`FoodSpoilage.passed`).
  `FoodSpoilageTest` covers the tags, Frozen, the list's order and rows, an empty store's
  blueberry line, and a store taking no food. Pictures: `tmp/freshness_20261029/built_*.png`.
- **The readouts' concepts** (2026-10-29), from which the owner picked. They're in
  `tmp/freshness_20261029/` at 7680 × 2160 (150%) and 1920 × 1080; `sheet_*.png` puts today,
  A, B and C side by side.
  - **The scene:** the copy of the owner's colony on a spring morning, with the temperature
    concepts' larder (7°C, a sealed room). A stockpile on its floor holds six crates at
    different freshness. The storage window is on Contents, and the panel shows the
    blueberry crate, half spoilt.
  - **A · words:** the crate's status tag says its freshness in its tone ("Spoiling · about
    6 days left"). Under the window's hint a line gives the store and how long blueberries
    keep there, and a rust line names food going bad.
  - **B · bars:** a bar of the crate's remaining life under its tag. Above the window's
    pictures, a Keeping block has one bar for each food, the soonest to rot first.
  - **C · chips:** a tone tag with the days left on the crate's band, beside its count.
    Temperature and room chips sit in the window's footer, and a tone tag with days left
    sits on each food picture.
  - All three use the panel's tag tones: moss Fresh, hay Spoiling (from half its life),
    rust Going bad (from three quarters).
- **Phase 2 is built,** waiting on the owner's look in Play.

- As in "Spoilage" above. A spoilage component owned by StockpileManager works hourly over
  stored, loose and carried food. The eating order goes into the food search's quote, and
  the warnings into Events, the storage window and the inspectors. The Temperature view's
  hover card adds how long food keeps at the spot.
- **Tests:** a new `FoodSpoilageTest` (speeds, frozen, open sky and rain, merging, rotting with
  its Events line, claimed portions kept, save and load, eating order).
  `SaveManagerRoundTripTest` saves a part-spoiled crate.
- **Docs:** 42 (spoilage), 41 (eating order), 23 (storage window, inspectors, Events).
- **Done when** blueberries left in a summer yard rot in about two days, keep about 11 in a
  valley larder and about a season under the summit, Events warns before they go, the
  winter balance check passes and the job gate stays green.

### Phase 3 — Spreading

- Fire warmth through open air and leaking doors, as above. Dwarves sleeping or eating round
  a lit campfire are warmer; a hearth room warms its neighbour through the door.
- **Tests:** `ClimateTest` and `HearthRoomTest` grow to cover both.
- **Docs:** 34.

**Progress (2026-10-29): phase 3 is built,** waiting on the owner's look in Play. Doc 34
"Heat and cold spreading" has the rules.
- **Code:** a `HeatSpread` component owned by RoomManager (`RoomManager.heat`) walks each
  open-air fire's warmth and leaks the doors. A room carries `own_form` and `temp_form`;
  `climate_at` gains `fire_c`, `heat_c` and `door_c`, and RoomManager gains `heat_kept`,
  `heat_sources` and the `warmth_changed` signal. Rooms also recompute when the weather
  changes, since a door to the open air lets some in. `temperature.json` has
  `open_air_heat_per_degree`, `door_leak` and `door_leak_passes`; the campfire, hearth and
  log torch have a `radius`.
- **Readouts:** the Temperature view's floors carry a room's leaked numbers and a fire's
  warmth; its card adds "Its doors make it 1.1°C warmer." and "A fire nearby adds 4.8°C.",
  and gives the year without a nearby fire. "Its fires add" and the hearth panel's "This
  hearth" now give what the room keeps of the heat past its doors, which the fire-lighting
  rule also uses.
- **Tests:** `ClimateTest` (a campfire's warmth by steps and stopped by a wall, a three-room
  chain, the tunnel door letting in a tenth of the day), `HearthRoomTest` (a door straight
  outside, an entry room, the hearth warming it), `TemperatureViewTest` (the card's lines, a
  campfire on the plain, rain through a door) and `RoomRebuildSchedulingTest` (a room's own
  and leaked forms).
- **What moved:** doors to the open air widen the rooms behind them, so two phase 1 targets
  changed (see "Targets"). The one that matters: one hearth no longer keeps a 6 × 6 × 4
  bedroom Comfortable on the coldest nights if its door opens straight outside (15.0°C, a
  Chilly sleep, −5 happiness). Behind an entry room it stays Comfortable, if only just
  (16.3°C). The owner kept it (2026-10-29, "Keep it"; see "Open").

### Later, not in this milestone

- The aging cellar's temperature ranges and the frozen vault's food benefit, with brewing.
- Brewing and drying as ways to keep food.
- Ice cut in winter to keep a cellar frozen all year.
- Thoughts about cold and heat while working, including the planned `weather_cold` thought
  (doc 24).
- Snow cover; ice on the tarn and lake.
- Barrels and chests that slow spoiling, with the storage furniture milestone.
- Wildlife raiding food left outside; frost and crops.

## Open

- **A natural freezer.** With these numbers only cellars just under the summit freeze, and
  only for about two weeks around the coldest day. A freezer all year would need ice
  (later) or a steeper height rule.
- **The view's look in Play.** The format is picked (A, the wash); the colours are the
  concepts' physical ramp. On a winter night the whole open ground is Frozen, so the view
  turns the surface pale; the owner judges whether that reads well.
- **The gate.** Whether `ClimateTest`, `TemperatureViewTest` and `FoodSpoilageTest` join the
  job gate.
- **Winter food supply.** Starts have about a twentieth of the food a winter needs (phase 2
  "Progress"), so spoilage can't decide whether a colony eats in winter yet. The owner
  (2026-10-29): dwarves stock up for winter, and hunting comes later in the game. The keeping
  times stay; meat will carry its own `keeps_days`.
- **Crates of different freshness: decided and built** (owner, 2026-10-29, "Separate
  them"). Crates further apart in spoil than 0.25 stay apart; doc 42 "Spoilage" has the
  rule. One change from the first proposal: a stockpile with no empty cell tops up the crate
  closest in freshness instead of refusing the fruit. Hauling decides "is there room?" by
  item alone, so a strict refusal would have left haulers picking fruit they could not
  store, over and over. Tested in `FoodSpoilageTest`.
- **Rotten food** stays gone until farming wants compost.
- **Bedrooms with a door straight outside: decided** (owner, 2026-10-29, "Keep it"). One
  hearth leaves them Chilly on the coldest winter nights, so entry rooms and second hearths
  are worth building. Doors to the open air keep the same 10% leak as any other door.
