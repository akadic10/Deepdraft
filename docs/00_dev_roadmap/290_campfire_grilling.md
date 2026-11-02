# 290 — Grilling fish on the campfire

2026-10-31. Built with concept A, the owner's pick (step 2, below). The owner's look in Play is next.

From the owner, after a playtest of fishing (doc 289): "dwarves may take a fresh fish and
grill it on the campfire, which should replenish their hunger, give them some rest and make
them happy". Shown a review with four picks, the owner took every recommendation: "Write it
up".

A hungry dwarf takes a fresh fish to a burning campfire, grills it on a stick and eats it by
the fire. The meal fills them as a raw fish does, rests them a little and leaves a good
memory. Fresh fish spoil in two days, so grilling eats them while they are fresh, and the
drying rack keeps the rest for winter. It makes the campfire the evening's meeting place.

## What is there

- **Meals** (doc 41, "Dining"; `DwarfFoodBehavior`). At 0.40 food a dwarf is Hungry and
  takes one portion, from storage first, then from the floor, older food first. It looks
  for a seat and a table within 32 walking blocks of where it took the food
  (`food.dining_distance`, `DwarfDining`), eats for 5 seconds (`eat_seconds`) and gains the
  food's nutrition: 0.6 for every fruit and fish. A meal without a seat at a table leaves a
  memory for 8 game hours: "Ate without a table" or "Ate standing up" (−3), "Ate without a
  proper place" (−8). A meal under way is not saved.
- **Rest** is the `sleep` meter. Awake it drains 0.042 a game hour, about 18 waking hours a
  day; asleep it fills evenly to full over six hours, about 0.125 an hour. Nothing else
  fills it.
- **Happiness** is 50 plus the thoughts (doc 41, "Mood Events"): a board game with a friend
  +8, alone +4, each for 12 game hours, of which only the stronger counts; the dining
  memories; room appeal; one's own bedroom +10; the cold −20. The colony journal notes a
  thought when it begins (`data/colony/journal_lines.json`).
- **The campfire** (doc 34, "Nightly fires"; doc 62). A Tier 1 stone ring, about 2 × 2, in
  the middle of a clear 3 × 3 camp area that dwarves walk around. A worker lights it at
  dusk with a log and it burns until dawn (`FurnitureFires.burning`), with light, its
  crackle and 900 heat units, which outdoors warm only the air a few steps around. Stools
  within 6 blocks turn to it, lit or cold (`seating_focus: "fire"`).
- **Fish** (doc 289). Perch, trout, char and cave fish carry the `fish` tag; each is a
  portion and keeps 2 days at 20°C. Dried fish keep 30 days and are not tagged `fish`.
  Dwarves eat fish raw, and doc 289 left cooking to a Cook who doesn't exist yet.

## Decisions (owner, 2026-10-31)

1. **A meal by the fire, not a craft.** There is no order, no profession and no stored
   grilled fish. The reward is the time by the fire.
2. **Only while the campfire burns,** from dusk to dawn. By day dwarves eat as now; no one
   lights a fire to cook, so each fire still takes one log a night.
3. **The numbers:** a grilled fish fills as a raw one does (0.6, one portion); the meal adds
   0.05 Rest; it leaves the thought "Grilled fish by the fire", +6 for 12 game hours, or
   +8 with company at the same fire. It takes the place of the dining memory, since the fire
   is a proper place to eat.
4. **The campfire first.** The hearth, also an open fire, can follow later.

## Concepts (2026-10-31)

From the owner: "Draw concepts". Drawn over a copy of the owner's colony at night, at its
campfire, with one dwarf on a stool and one standing at the camp area's edge (scratch in
`tmp/grill_concepts_20261031/`: `model_sheet.png`, `fire_sheet.png`). Three ways to grill a
perch, each raw and grilled, at the dwarf tools' scale:
- **A · On a stick** (the plan as written). A whole perch pushed onto a peeled green stick
  from the mouth, held out over the flames in both hands, then eaten off the stick. The perch
  browns, scorched along the belly where the flames reach, its eye turns white, and the
  stick's tip blackens.
- **B · Split.** The perch split along the belly and pinned flat on a forked stick by two
  cross twigs, flesh to the fire: pink flesh turns golden. It reads as cooking from further
  off, but a dwarf would split the fish first, a step A doesn't have.
- **C · Propped.** A's stick pushed into the ground at the fire's edge with a stone at its
  foot, leaning in over the flames. The dwarf sits with hands on knees and waits, then takes
  it up to eat. Hands free while it grills, and each grilling dwarf's stick stands in the
  ring.
- **The owner's pick: A** ("A · On a stick"), the recommendation. It reads as grilling a fish in every shot, near or across the fire,
  and its eating frame is the clearest. It needs only a held stick, the path the fishing rod
  already takes (`DwarfWorkToolPose`). C looks the most restful, but its fish sit low in the
  flames' glow and the stick becomes a prop in the world to clean up after; B needs a
  splitting step and reads as a flat square at a distance.

## How it plays

- **Choosing to grill.** At night, while a campfire within reach burns and has a free spot,
  a hungry dwarf looks for a fresh fish first, the oldest first, as long as the fire stands
  within 32 walking blocks of where the fish is taken (as a table must). With no fresh
  fish, no free spot, no burning fire or a fire too far away, they eat as they do now.
- **At the fire.** The dwarf sits on a free stool that faces the fire, or stands at the edge
  of the camp area, pushes the fish onto a peeled stick and holds it over the flames. The
  fish browns over about 20 game minutes, about 10 seconds at ×1, with a sizzle. Then they
  eat it there.
- **What it gives:** 0.6 food, as a raw fish; +0.05 Rest, shown on the sheet as "Rested by
  the fire"; and the thought. "Grilled fish with company" (+8) needs another dwarf grilling
  or seated at the same fire, as a board game needs a friend.
- **What it never does:** dried fish and fruit aren't grilled. Dawn doesn't stop a grill
  already under way. A fire with no free spot sends the next dwarf to eat as now. An
  interrupted grill drops the raw fish at the dwarf's feet, as any meal does (Hard Rule 12).
- **Seeing it:** the inspector says "Grilling a perch by the campfire"; the journal notes the
  thought as it does a board game.

## The numbers (to tune in play)

- **Grill time:** 20 game minutes (`grill_seconds` 10, real seconds at ×1 as `eat_seconds`
  is).
- **Rest +0.05** is about 1.2 hours awake, or 24 minutes asleep. Three grilled meals a day
  give back about a fifth of a day's tiredness. A larger amount would let dwarves skip sleep.
- **Happiness:** +6 alone, +8 with company, for 12 game hours; the stronger one counts.
- **Spots:** free stools within 6 blocks that face the fire, then the cells along the camp
  area's sides, three a side. A stick of about a block and a half reaches the flames from
  either.

## How it will be built

- **The meal.** `DwarfFoodBehavior` gains a grill branch. Before the search, a quick check
  for a burning campfire with a free spot near the dwarf narrows the search to the foods
  that can be grilled. After the pickup, a `CampfireGrill` helper, beside `DwarfDining`,
  claims a spot (a stool as seats are claimed, or a side cell), routes there, runs the
  grill and hands over to eating. The meal's dining outcome is "fire", which has no
  penalty.
- **The reward.** `DwarfMood.record_grill(together)` keeps two memories with their hours, as
  `record_recreation` does, with the thoughts `grilled_together` and `grilled_alone`. The
  finished meal adds the Rest to `DwarfAgent.sleep`, up to full.
- **The look.** A `DwarfGrillPose`, as `DwarfFishingPose` holds the rod: the stick, the fish
  on it browning from its raw colour, seated and standing, then held up to the mouth. The
  fish is eaten off the stick, so no serving is needed.
- **Data:** a `grill` block in each fresh fish's `food` in `resources.json` (its browned
  colour) marks what can be grilled; `food.grilling` in `task_config.json` (grill time, Rest,
  spots); `mood.grilled` (the two bonuses and their hours); journal lines for the two
  thoughts; a `fish_sizzle` sound bank in `work_feedback.json` if a recording is approved.
- **Saves:** the two grill memories save with the mood, as the board-game ones do, and the
  save check knows them. A grill under way is not saved, as no meal is. No compatibility
  work for older saves (standing rule).

## Art and sound

Hearthblock, Tier 1, through the usual pipeline (doc 61), concepts first:
- the stick: a peeled green stick with the fish pushed on lengthwise;
- the pose seated on a stool and standing at the fire's edge, the stick held over the flames;
- the fish on the stick, raw and browned, eaten off the stick.

Sound: the campfire's crackle is there already. A sizzle needs a new free recording, which
I'd download only with the owner's OK; without it, the crackle carries the moment.

## Steps

1. **Concepts.** Drawn; the owner picked A (above).
2. **The meal by the fire.** Built (below).

## Built: step 2 (2026-10-31)

From the owner: "A · On a stick".
- **In play.** At night, while a campfire burns within 32 blocks of a hungry dwarf, the meal
  looks for a fresh fish first (perch, trout, char or cave fish), the oldest first, then any
  food. With a fish the dwarf goes "Taking a fish to the campfire": to a free stool that faces
  it, else a place at its side. There they push the fish onto a peeled stick and hold it over
  the flames; it browns after about 6 seconds at ×1, is done at 10, and is eaten off the stick
  in 5. The meal gives 0.6 food, as the raw fish would, and 0.05 Rest (the sheet's Rest row
  says "Rested by the fire" for two game hours), and leaves "Grilled fish by the fire", +6 for
  12 game hours, or "Grilled fish with company", +8, when another dwarf grills or sits at the
  same fire. The sheet's meal line is "Ate grilled fish by the fire", with no dining memory.
  On a stool, the dwarf then sits on by the fire.
- **Ordinary meals.** By day or at a cold fire, with only dried fish or fruit, with no room
  at the fire or a fire beyond the meal's reach, the meal is as before. A release mid-grill
  drops the raw fish whole at the dwarf's feet.
- **Code.**
  - `DwarfFoodBehavior`: the search for fish to grill, the grilling state, the nearest
    burning fire, company and `grilling_fire_id`.
  - `DwarfDining` takes a fire: only stools facing it and the places at its sides (claimed
    as a table's), the outcome "fire" and `at_fire`.
  - `DwarfGrillPose` on the rig: carry, hold and bite, the stick swapped for the grilled one
    as the fish browns.
  - `DwarfMood.record_grill` and its two memories; `ItemDropManager.grill_keys`;
    `DwarfAgent.get_grill_pose` and `fire_watched` (`DwarfIdleBehavior.fire_watched`).
  - `SaveSnapshotValidator` knows the "fire" outcome and the memories;
    `DwarfInspectorPanel` shows Rested by the fire.
- **Data.** `food.grill` on the four fresh fish; `grilling` on the campfire; `food.grilling`
  (grill_seconds 10, browned_at 0.6, rest 0.05, rested_hours 2) and `mood.grilled` (0.06,
  together 0.08, 12 hours) in `task_config.json`; journal lines for the two thoughts.
- **Art (Hearthblock, concept A).** Each fresh fish on its stick, raw and grilled
  (`tools/grill_stick_<fish>` and `_grilled`): eight models in the dwarves family, in
  `DwarfAssets.grill_sticks`. Gallery: `tmp/grill_art_20261031/`.
- **Tests.** New `CampfireGrillTest` (fishing area): a perch grilled on the stool facing a
  burning fire, the stick raw then browned, food 0.3 → 0.9, Rest +0.05, +6 and no dining
  memory, Rested by the fire and sitting on; company +8; a cold fire, dried fish, a full fire
  and a far one as ordinary meals; a release; saves. `ColonyJournalTest` knows the two
  thoughts. Gate 55/55, the lint clean; the dwarves, fishing, furniture, ui, saves, art,
  crafting and rooms areas pass.
- **Seen in the game** (`tmp/grill_build_20261031/grill_sheet.png`, a copy of the owner's
  earlier colony at night, nothing posed): Tekak, made hungry, took a perch laid near the
  campfire to a stool facing it, grilled it and ate it off the stick, then sat on by the
  fire. Tekak's sheet read "Ate grilled fish by the fire" and Rested by the fire, with +6.
- **Not yet:** a sizzle (no recording) and the hearth.
- **Saves:** the grill memories are written only while they last, so step 3 saves load.

## Not in this milestone

- Grilling at the hearth.
- Lighting a fire by day to cook.
- A Cook and cooked meals; stored grilled fish.
- Grilling other foods, such as fruit or meat from hunting.
- Tastes for food (tastes name furniture and woods only, doc 41).

## Open

- The grill time, the Rest amount and the thought's points: tuning in Play.
- Whether a grilled fish should fill more than a raw one, once winter food is weighed.
- The sizzle recording.
