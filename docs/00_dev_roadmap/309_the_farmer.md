# 309 — The Farmer and its crops

**Status (2026-11-14):** built the same day, all five steps, and not yet seen in play. The owner's
answer to the plan and its five questions: "proceed with the full plan", which I took as every
proposal accepted (my reading). The rules now live in doc 42 ("Fields"), doc 41 ("Profession
System"), doc 23 ("Fields"), doc 31 (FARM), doc 13 and doc 33; what is left is in `00_todo.md`,
"Farming left for later". This doc stays until the owner has looked: "accepted" retires it.

From the owner (2026-11-14): "plan the farmer next and we need to plan several vegetables the
farmer can grow, some low level that he can farm during a specific season and then later more
complicated crops as the farmer levels up".

## What was built

| Step | What the player gets |
|---|---|
| 1 · The first field | The Farmer on the career map (a copper hoe); Zones → Farming and the field's window; tilled soil; radish, carrot and turnip; pulling into crates; bushes and fruit trees in a field picked with no order; levels |
| 2 · The Farmer's look | A straw hat; the copper hoe in hand with a chop-and-draw motion; sowing and pulling by hand |
| 3 · Water, cabbage, onion | Damp soil grows a crop a quarter faster; rain makes every open field damp; the first crop free of the calendar and the first that takes two seasons |
| 4 · Pumpkin and kale | A crop that grows only in damp soil; a crop picked again and again through winter |
| 5 · Sounds | The hoe in earth, a tile sown, a ripe tile pulled |

**Where it differs from the plan below:**
- **A new field plans the starter crops** (radish, carrot, turnip, rest in winter), so a Farmer
  starts at once and the window is only for changing it.
- **Plants are drawn a node a tile,** as bushes are, not in batches: it lights and slices them
  as every other plant with no new code. Batching is in the to-do list.
- **The two sheets step 1 was to open with were not drawn first.** The crops have one look
  each, and the field's window follows the Fishing zone's format, which the owner picked. The
  pictures are for the owner's look now: `tmp/farmer_20261114/`.
- **Pumpkins grow at their plain speed in damp soil,** not a quarter faster: the water is what
  lets them grow at all.
- **Level 4 is at 250 tiles,** so a Farmer who starts in the first summer has it in time for
  the next year's pumpkins.

**Decisions I took while building** (they hold unless the owner says otherwise):
1. A Farmer's order of work in a field: pull what is ripe, hoe under what the plan has moved on
   from, sow, then hoe new ground. So each tile is sown as soon as it is hoed.
2. Two Farmers a field at most (`max_farmers_per_field`).
3. The pulls fill one crate after another where the Farmer stood, not a crate a tile.
4. Picking a bush or a tree in a field takes only a Farmer while the colony has one. With no
   Farmer a field picks nothing by itself, and an order given there is open to anyone.
5. A tree stands in a field when its trunk's centre is inside the field's rectangle.
6. Tiles under furniture, a trunk or a stone, within a bush's or a flower's planting area, or
   under water are left alone, and the window counts them ("4 left alone").
7. Tilled soil keeps one colour all year, so the ridges drawn on every tile always match it.
8. The field on the ground is its soil and its plants; the zone is a thin green edge.
9. Events says what was not ripe when a season turned, one line a crop a field.
10. The Farmer's page under Crafters stays a preview: it has nothing to craft.
11. `FarmingTest` is in its own area (`--area farming`), not in the gate of 55.
12. **Saves from before today do not load:** the save gained a `farming` section, and the
    standing decision is no backward compatibility.
13. **The art, one look each** (two artists drew it from briefs while the rules were built):
    - the straw hat's band is slate blue, the tunics' slate; it is the broadest of the six hats
      and hides the shoulders from above;
    - the hoe in hand has a haft two cells shorter than the pickaxe's and a blade two cells
      broader than the hoe good's, so it shows from above;
    - a vegetable's serving sits above the mitten's cuff, not inside the fist as the apple
      does, so it shows while a dwarf eats. At the top of a bite it is at eye level for a
      moment; lowering the meal pose by two cells would bring it to the mouth;
    - carrot and pumpkin crates are both orange, told apart by green tops against ribs and
      stems; the onion's gold is close to the crate's own wood.
    - every tile's model carries two soil ridges, so rows join from tile to tile and a tilled
      tile with nothing sown shows its furrows; cabbage and pumpkin, one plant a tile, stand on
      a small hill across the middle trough;
    - roots stand out of the soil under small leaves, so the vegetable's own colour shows from
      above; a ripe onion is only 5 cells high because its tops lie over the bulbs;
    - colours were chosen by how the game's midday renders them, so kale is stored greener
      than the blue-green it shows.

**The sounds** (the sound workflow in CLAUDE.md; a second helper sourced them). **Nobody has
listened to them:** I cannot hear audio, so the choices and the levels wait on the owner's ear,
at `tmp/farmer_20261114/sounds/review.html`.
- Three kinds, thirteen recordings, all CC0 from Freesound, all decoded from public HQ MP3
  previews because the lossless originals need a login (`tools/audio_sources/farming/`,
  rebuilt by `tools/generate_farming_audio.py`).
- **The hoe** (`farm_hoe`, six): strokes of a mattock digging a garden, which stands in for a
  hoe. The one plain hoe recording found was a long scrape with no bite. Each cue is the chop
  and the soil crumbling; the draw back through the soil is not heard.
- **The pull** (`farm_pull`, four): one plant pulled up with its roots snapping, and three
  tears of a weed, which stand in for a crop pulled.
- **The sowing** (`farm_sow`, three): a hand brushing the ground, which stands in for sowing;
  no seed is heard.
- **Levels** against the yardstick of doc 13: the hoe at −28 (a pick in soil is −23, the axe
  −26), the pull at −34, the sowing at −40, which is under the Farmer's own footsteps on
  earth (−37) and may not be heard. They carry 26 blocks, as a catch does.
- Until today the hoe had no sound of its own; in this build it never borrowed the pick's.

**The winter model, run again with a field** (`tmp/farmer_20261114/winter_model.py`; a model,
not a game run; the numbers are in `00_todo.md`, "Winter food"). With one Ranger and one 6 × 6
field no start goes hungry in its first winter, the flag and the mountain included, which had
21 hungry days of 21. But the yard is then fed as well as the cellar: turnips pulled late in
autumn last half the winter in the open, and fresh fish carry the rest. The cellar decides it
only when the field is the colony's one food (0 hungry days against 11). The owner's bar was
that a colony keeping its harvest in the yard goes hungry for most of the winter; whether to
hold fields to it is theirs to say, after a game run.

**For the owner to look at** (all under `tmp/farmer_20261114/`):
- `crops_sheet.png`: the seven crops at every stage, from both of the owner's cameras;
- `goods_sheet.png`: the crates, the inventory pictures, the servings, the straw hat beside
  the other five and the hoe in hand;
- `preview/`: the real game, a fresh world. `field_stages_close.png`, `_far.png` and
  `_near.png` show every crop at every stage on one field, and `field_stages_slice_later.png`
  the same under a slice one level above the grass; `farmer_till_0` to `_5`, `farmer_sow_*`
  and `farmer_harvest_*` are frames of the Farmer's three motions; `field_window.png`,
  `field_window_spring.png` and `field_window_in_spring.png` are the field's window;
  `after_load.png` is the world after a save and a load;
- `sounds/review.html`: the three cues, which nobody has listened to;
- and the numbers, in play.

The plan as it was agreed follows.

## What stands already

- **The tool.** The Farmer's tool is the copper hoe a Blacksmith hammers from a bar and a log
  (doc 306; the owner picked its look, the bent-knee hoe). The good exists; the career is
  still "Planned" on the career map, and Zones → Farming is a reserved entry.
- **Zoned bushes.** From the owner (2026-11-06): "when we start with the farmer, bushes in a
  farming zone should get picked by the farmer." Left open then: whether fruit trees count,
  and what happens to fruit the colony cannot eat (doc 42).
- **The calendar.** A season is 21 days and a year 84. A new colony starts on summer's first
  day, so its first Farmer arrives in the first summer or autumn. A day is 12 minutes at ×1.
- **Food.** A dwarf eats three portions a day; five dwarves eat 315 in a season. Every food
  is one portion (`nutrition` 0.6) and keeps by its `keeps_days`, the cellar's cold and the
  open sky (doc 42, "Spoilage").
- **Winter.** Too little grows near a start to feed a winter (`00_todo.md`, "Winter food").
  The owner's rule: dwarves stock up, all food counts, tune the supply and not the keeping
  times. That plan waits on the Farmer.
- **Water.** Soil within three cells of water turns damp in two hours and dries in a day, and
  the damp-soil look and the moisture overlay show it (doc 33). Nothing uses it yet. Doc 33
  names water as farming's main challenge.
- **Ground.** Dwarves build dirt and grass blocks from Soil, so a player can make ground.
- **Art.** The hops, grape, pig tail and plump helmet models on disk are placeholders for
  brewing and weaving. They stay untouched until those features come.

## The plan in short

A Farmer works **fields**: farming zones the player drags on open ground. The Farmer hoes the
ground into tilled soil, sows the crop the field's plan names for the season, and pulls it when
ripe. A new Farmer knows three vegetables, one for each growing season. Each level teaches one
more, and each new crop brings one new idea: a crop free of the calendar, a crop that spends
two seasons in the ground, a crop that needs water, a crop picked through the snow.

## The Farmer

- **Becoming one.** A Worker collects a copper hoe, as the other copper trades collect theirs.
  So a colony farms only once it has a Blacksmith and copper.
- **Only Farmers work fields,** as only Rangers fish, so every harvest goes to a dwarf who
  learns from it. Workers still pick wild bushes and trees by order, as today.
- **Its work.** The fields come first: pulling what is ripe, then sowing, then hoeing new
  ground. With nothing due in the fields a Farmer takes the common work, as a Carpenter does,
  and so carries its own harvest to the store.
- **Experience** is one for each tile harvested, and one for each bush or tree picked in a
  field. Levels at 25, 100, 250 and 800.
- **Wisdom** speeds field work by 6% a step, as it speeds fishing. Toughness, the second stat,
  gives hit points only.
- **The look.** A straw hat (kept for the Farmer since doc 304), the hoe in its hands with a
  chop-and-pull motion for tilling, and hand motions for sowing and pulling.
- **Labor** gains a Farm box, as Fish has.

## The field

- **Zones → Farming.** A drag paints a flat rectangle, at most 16 × 16, on grass or dirt under
  the open sky, at any height. Built dirt counts, so terraces can be farmed.
- **What is already there stays.** A berry bush inside the field keeps its 3 × 3 planting
  area, and the Farmer picks it as it ripens with no order. A tile holding a wildflower, a
  boulder or a tree's trunk ground is left alone.
- **Tilling.** The Farmer hoes each tile once, three seconds a tile. The grass or dirt becomes
  **tilled soil**, a furrowed block of its own, so a field reads as a field when empty.
  Removing the zone leaves the tilled soil.
- **The season plan.** The field's window holds one crop for each season, or Rest. The Farmer
  follows it year after year with no further orders. A crop can be put only in a season it
  grows in, and a crop no Farmer in the colony may sow yet shows the level it needs.
- **Sowing** takes 1.5 seconds a tile and no goods. A tile is sown only if the crop will be
  ripe two days before the plan moves on to another crop. The window says so: "Sown until
  Summer 13."
- **Growing.** A crop shows three stages: sprout, half grown and ripe. Nothing grows in winter.
- **Pulling** takes two seconds a tile. The vegetables land on the tile as fruit does, and
  haulers store them. The tile is then sown again if another round can still ripen.
- **When the season turns** the field changes over. Ripe plants of the old crop are pulled,
  unripe ones are hoed under, and Events says how many. Since the Farmer never sows what
  cannot ripen, only a field left without a Farmer loses plants.
- **No collision** (Hard Rule 5): dwarves and animals walk through a crop.
- **An orchard** is a field whose plan is Rest in every season: nothing is tilled, and the
  Farmer only picks what stands in it.

## The crops

"A tile gives" is the portions one tile yields at one harvest. All are eaten raw, as fruit is.

| Level | Crop | In the ground | Days | A tile gives | Keeps at 20°C | The new idea |
|---|---|---|---|---|---|---|
| 1 | Radish | Spring | 4 | 2 | 5 days | A season's crop. Quick: up to four rounds a spring, the first fresh food after winter |
| 1 | Carrot | Summer | 6 | 3 | 12 days | A season's crop. Up to three rounds a summer |
| 1 | Turnip | Autumn | 8 | 4 | 15 days | A season's crop. Two rounds an autumn; it keeps like apples, so it is the winter root |
| 2 | Cabbage | Spring, summer or autumn | 9 | 6 | 8 days | Free of the calendar. Slow and big: the most fresh food a tile, but it does not keep |
| 3 | Onion | Sown in spring, pulled in summer | 28 | 14 | 40 days | Two seasons in the ground. It keeps longest, so a summer field can feed the winter |
| 4 | Pumpkin | Sown in summer, cut in autumn | 30 | 24 | 30 days | Two seasons and thirsty: it grows only in damp soil. The biggest harvest of the year |
| 5 | Kale | Sown in autumn, picked until spring | 10, then a picking every 3 days | 1 a picking, about 10 in all | 6 days | Picked through the snow: the only field food in winter |

```
            Spring         Summer         Autumn         Winter
Radish  L1  ████████████
Carrot  L1                 ████████████
Turnip  L1                                ████████████
Cabbage L2  ████████████   ████████████   ████████████
Onion   L3  ██ sown ████████ pulled ███
Pumpkin L4                 ██ sown ████████ cut ██████
Kale    L5                                ██ sown ████████ picked ███
```

- **Sowing windows** follow from the days: onions until Spring 13, pumpkins until Summer 11,
  kale until Autumn 10.
- **A two-season crop takes both seasons in the plan.** Choosing onions for spring fills
  summer too.
- **What a tile gives in a year.** The three starters: 8 + 9 + 8 = 25. Cabbage in spring and
  pumpkins after it: 12 + 24 = 36.
- **A rule of thumb to hold the numbers to:** a 6 × 6 field of a starter crop feeds five
  dwarves through its season (about 300 portions against 315).
- **Alternates,** if the owner wants a swap: beetroot, peas, leek, parsnip and garlic fit the
  same rules. Potatoes and beans want cooking first.

## Water

- **Damp soil grows every crop a quarter faster.** Soil is damp within three cells of water,
  as today, so a ditch from the river or the lake pays from the first field.
- **Pumpkins grow only in damp soil.** In dry soil they wait.
- **Rain is water.** On a day of rain or storm every open field is damp.
- **The window says it:** "24 of 36 tiles damp", and the moisture overlay shows where.
- Water runs downhill only (doc 33), so a field above the spring gets its water from rain.

## Levels

| Level | Tiles harvested | It learns |
|---|---|---|
| 1 | 0 | Radish, carrot and turnip |
| 2 | 25 | Cabbage |
| 3 | 100 | Onion |
| 4 | 250 | Pumpkin |
| 5 | 800 | Kale; Master Farmer |

- **A crop is sown only by a Farmer of its level.** Any Farmer pulls it.
- **A level gives its crop and nothing else:** no speed and no extra yield. This replaces the
  older note in doc 41 ("Yields improve at levels 2 and 4").
- **The pace** with one 6 × 6 field: level 2 at the first harvest, level 3 within two seasons,
  level 4 by the next spring, in time to sow pumpkins that summer. More fields are faster.

## Steps

Each is one session. The owner looks before the next begins.

1. **The first field.** The Farmer on the career map, the Farming zone and its window, tilled
   soil, the three starter crops, pulling and storing, zoned bushes, experience and levels.
   It opens with two sheets for the owner's pick: the crops' looks in a field, and the field
   window in formats that differ.
2. **The Farmer's look.** The straw hat, the hoe in hand and the three motions.
3. **Water, cabbage and onion.** Damp soil, rain, the first two-season crop.
4. **Pumpkin and kale.**
5. **Sounds,** by the sound guide: the hoe in earth, a plant pulled, leaves.

Before step 1's numbers are final, the winter model is run again with turnips; after step 1,
the game run that `00_todo.md` ("Winter food") asks for.

## For the owner to decide

1. **The roster.** The seven vegetables above, their levels and seasons. Strike, swap or add.
2. **Seeds.** Proposed: none. A Farmer's level is the only gate, and sowing costs work alone.
   The other way: each crop has a seed good found on wild plants, which adds seven goods,
   their storage and a search for each crop. Tree seeds and bush cuttings stay as they are.
3. **The field's plan.** Proposed: one crop for each season, set once. The other way: one crop
   a field, changed by hand each season.
4. **Water.** Proposed: damp soil helps every crop, rain counts, and only pumpkins need it.
   The other ways: every crop needs damp soil, so a field is always waterworks; or no water
   rule until later.
5. **Trees and surplus.** Proposed: apple and juniper trees inside a field are picked by the
   Farmer each autumn, as bushes are. And everything ripe is picked and stored, with no Keep
   number: what the store cannot keep rots, as today, and the player sizes the field.

## Decisions I took

They hold unless the owner says otherwise.

- Only Farmers work fields, and they keep the common work between field jobs.
- Fields go on open ground at any height. Height and temperature do not slow a crop.
- Tilled soil is a real block, not a mark on the ground.
- Nothing ripe is lost to the calendar, and a Farmer does not sow what cannot ripen.
- A crop is sown only by a Farmer of its level; levels give crops and nothing else.
- Experience is counted in tiles harvested, with levels at 25, 100, 250 and 800.
- Every vegetable is eaten raw and is one portion, as fruit is.
- Wildflowers inside a field are left standing, for the bees to come.
- Rabbits and deer leave crops alone for now.
- Kale gives winter food from the field. The owner's rule is that dwarves stock up for
  winter, so it is the last crop a Farmer learns, and it can be struck.

## Not in this plan

- **Underground crops.** Mushrooms in the dark, all year, are the dwarves' own crop and want
  their own design: soil underground, water there, and their place beside brewing.
- **Brewing and weaving crops** (hops, grapes, pig tail): with the Brewer.
- **Cooking.** A pot of stew, and the crops that want it (potatoes, beans).
- **Seeds from traders,** bees and honey, fodder and pastures.
- **Wildlife raiding fields,** and fences against it.
- **Soil that tires,** compost from rot, frost by height.

## Build notes

- **Owner and shape.** A scene node like `FishingSystem`: the zone tool, the window, a save
  section. One FARM lease a field, as a mining zone's lease, with the work done on each tile
  kept on the tile (Hard Rule 12).
- **Data.** Crops are content a save names, so their definitions belong to a registry
  autoload (CLAUDE.md, "Registry Pattern"). Tilled soil is a block in `terrain_blocks.json`
  that counts as soil for moisture and drops Soil.
- **Drawing.** Bushes are a node each; a field can hold 256 plants, so crops were to be drawn
  in batches by crop and stage. Built a node a tile instead (see "What was built").
- **The slice.** The owner plays with the cut just above the grass. A crop shows when its soil
  is at or under the cut, as a bush does.
- **Growth** is credit kept on each tile and added each game hour over frames, as spoilage is.
- **Menus.** Who may do a thing shows in the career map, the dock's Craft menu, the crafting
  window and Labor: change all four (doc 306's lesson).
- **Tests that say the Farmer is planned:** `ProfessionPathTest`, `RangerTest`,
  `MinerProfessionTest`, `ToolPromotionTest`, `CraftingBrowserTest`, `TreeFellingTest`.
- **Docs to change with step 1:** 42 (the planned farming sections), 41 (the Farmer's row and
  the profession path), 31 (the FARM type), 23 (the zone and its window), 13 (the save
  section), 33 (what crops need) and `00_todo.md`.
