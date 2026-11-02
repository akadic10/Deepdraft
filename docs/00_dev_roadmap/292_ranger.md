# 292 — The Ranger

2026-11-01. Step 2 built: the Ranger fishes, dries and levels up (below). The owner chose the
career and its name, took every recommended pick and the four recommended concepts. Steps 3
(fish that differ) and 4 (rare fish) are next, after the owner's look in Play.

From the owner: "let's evaluate fishing, the drying rack and its orders. Right now fishing is
not a profession and that may be the best option but I just want to evaluate it. The pine
rack is also a crafting station so it feels weird being nested under the rudimentary
workbench. Fishing should feel fun and rewarding for the player and it feels like a skill the
dwarves should gain experience on." Shown four ways to go: "I actually like the hunter idea,
is there a better name for this profession for someone who will hunt and fish?" Offered the
Ranger: "Yes, as Ranger". Shown the plan's recommended picks: "Take them all". Shown the
concepts' four recommendations: "Take them all". Then: "Build the Ranger".

The Hunter becomes the Ranger, who brings the colony food from the wild. Rangers fish now
and will hunt once hunting is built. They own fishing and the drying rack, and get better
with every catch. Their levels make catches bigger, not faster, because each water's stock
limits fishing, not the fisher's time. Dried fish moves from the workbench's page to the
Ranger's own.

## What is there

- **Fishing** (doc 289). A Fishing zone along a shore posts work for each of its spots.
  - Any dwarf with Fish ticked in Labor fishes, in any profession, and Fish starts ticked for
    everyone.
  - A catch is one fish of the water's kind and takes about a game hour (30 seconds at ×1).
    Each Wisdom step above or below Average makes it 6% quicker or slower.
  - Each water holds a stock that regrows 3% of its maximum a day. In the owner's earlier
    world the lake held 154, the river 121, the tarn about 60 and the cave pool about 20, so
    together they regrow about 10 fish a day.
  - Each zone keeps 20 of its fish (Keep) and pauses while the colony has them.
- **What limits it.** One dwarf fishing all day lands 12–15 fish at a full lake, and about 5
  near Fished out, while the lake regrows about 5 a day. So one fisher keeps up with a whole
  lake, and more fishers only empty it sooner. A water gives about the same food however
  many dwarves fish it; only what each fish is worth can grow.
- **The fish.** Perch, trout, char and cave fish differ only in looks. Each is a portion
  (0.6), keeps two days at 20°C and can be grilled (doc 290).
- **Drying** (doc 289, step 3).
  - Workers make the rack at the workbench (Rudimentary → Food).
  - Dried fish is a Worker craft at the rack: two fresh fish of one kind become two dried
    fish in 12 seconds. Dried fish keep 30 days.
  - Its order sits on the Rudimentary · Worker page, beside the rack's own recipe, and queues
    with the torches and beds. The rack's Dry fish button opens that page.
- **Professions** (doc 41). Each dwarf has one profession; Worker, Miner and Carpenter are
  live.
  - The Hunter is planned on the career map, with Agility, then Wisdom. Its starter tool is
    the hunting spear: a log and a stone at the workbench (Rudimentary → Starter tools).
  - Only the Miner earns experience: one a block, with levels at 10, 100, 500 and 2,500 and 5%
    less digging time a level. That code serves the Miner alone: `DwarfAssets.profession_level`,
    `mining_duration_multiplier`, `DwarfInspection.experience`, the roster's "Mining focus" and
    the Miners' first refusal in `TaskScheduler._assign_bucket`.
  - Doc 41 plans that specialists fall back to hauling when they have no primary work. The
    live Miner instead helps with all the general work it is allowed to do.
- **Crafting** (docs 23 and 44).
  - The window's Crafters row has a tile for each profession.
  - Each recipe names its `section` (Rudimentary by default), and the window shows only that
    section's recipes and orders.
  - Only Workers craft (`TaskScheduler.types_for`), and Labor's Craft box is Worker-only.
  - A Hunter section already exists as a planned preview, in the Crafters menu and the window.
- **Hunting** (doc 45).
  - Rabbits, deer, wolves and ducks live in the world and have hit points.
  - Player hunting is the Hunter's planned work, at about 15 hit points a spear blow.
  - There are no trapping grounds (owner, 2026-10-23).

## The review (2026-11-01)

Four ways to go were weighed:
- **A fishing skill for every dwarf.** Keeps "any dwarf may fish", but adds a second kind of
  progress beside professions. Labor has no priorities, so the catches would spread over
  whoever is idle.
- **A Fisher profession.** Fits promotion, experience and tools, but adds a new career for one
  job.
- **The Hunter fishes too** (chosen). One career for food from the wild. Until hunting is
  built, it only fishes.
- **No change.** Fish feed only three or four dwarves, and the core loop is Dig → Brew → Trade.

For the rack, three ways were weighed:
- its own window;
- its orders under the career that dries the fish;
- real drying, where fish hang for a day.

The career choice puts Dried fish under the Ranger. Real drying waits.

Names weighed for a career that hunts and fishes:
- **Ranger** (chosen).
- **Provisioner:** exact, but it sounds like a clerk.
- **Hunter** kept as it is: it leaves out half the job.
- **Forager:** clashes with the game's emergency foraging and the bees' forage.
- **Trapper:** the owner turned it down for the Hunter on 2026-10-09.
- **Huntsman, Woodsman and Fisherman:** read as men only.

## Decisions (owner, 2026-11-01)

1. **The Hunter takes fishing.** Not a Fisher, a fishing skill for everyone, or no change.
2. **It is called the Ranger:** someone who lives off the wild, hunting and fishing.
3. **What it is for:** fishing that feels fun and rewarding, experience for the dwarves who
   fish, and the rack's orders off the workbench's page.

## Picks (owner, 2026-11-01)

My recommendations, all taken ("Take them all").

1. **Fishing is the Ranger's work.** Only Rangers fish, as only Workers craft, and Labor's
   Fish box applies to them alone.
   - A water feeds the same however many dwarves fish it, so every catch should go to a dwarf
     who learns from it.
   - A colony fishes once it has a Ranger, which takes one spear.
   - *Not taken:* Workers keep fishing without experience, as Workers mine. Then Rangers need
     first pick of the spots, and Workers take fish a Ranger would land bigger.
2. **Rangers do Ranger work first.** They dry the catch and fish, and haul when neither is
   wanted, as doc 41 plans for specialists.
   - They don't mine, fell trees or build, so they stay at the water. Mining, felling and
     building outrank fishing today.
   - *Not taken:* they help with all the work they are allowed, as the Miner does. Fishing would
     then have to come first for them.
3. **Only Rangers dry fish.** Dried fish moves to Crafters → Ranger, and the rack's Dry fish
   opens that page. Workers still make the rack (until the owner moved it to the Ranger's
   page, below).
   - *Not taken:* Workers may take the Ranger's drying orders too.
4. **Rangers promote with the hunting spear,** already the Hunter's starter tool. The Ranger
   keeps it for hunting. They fish with the rod every fisher holds today, as a Miner digs
   with the default pickaxe.
5. **Wisdom, then Agility** (the Hunter had Agility, then Wisdom). Fishing comes first and
   Wisdom is its stat. Agility still counts for hunting, and this order sets the Ranger apart
   from the planned Marksman, who has Agility, then Wisdom.
6. **One experience a catch, on its own scale:** levels at 10, 50, 150 and 400 catches.
   - A Ranger who fishes every day reaches level 2 on the first day, level 3 in the first
     week, level 4 within the first season and level 5 near the end of the first year.
   - At the Miner's thresholds, level 5 (2,500) would take a Ranger three years.
7. **Levels make catches bigger, not faster.** This replaces the planned 5% speed a level,
   as the Merchant's levels raise prices instead (doc 41).
   - Level 1: Fishing focus.
   - Level 2: one catch in six is a big fish: two fish land, and the water loses one.
   - Level 3: patient: winter slows them half as much.
   - Level 4: one catch in three is big, and rare fish start to bite (step 4).
   - Level 5: almost every other catch is big (45%), and rare fish bite twice as often.

   At level 5 a water gives nearly half as much food again.
8. **Each fish has a trait of its own,** so the choice of water matters:
   - perch come from the lake, which holds the most fish;
   - trout are often big (10 points more);
   - char keep three days instead of two;
   - cave fish bite at full speed all year, since the spring cave has no seasons.
9. **A calm job.** Each catch gives the Ranger the thought "A quiet hour by the water", +3 for
   8 game hours. Fishing becomes the first work that lifts a dwarf's mood.
10. **Rare fish** (step 4), one for each water: perhaps pike in the lake, salmon in the river,
    golden trout in the tarn and a cave eel in the spring cave.
    - A rare fish lands as three portions.
    - The journal names it: "Runbrin landed a pike at the lowland lake".
    - The Ranger gets the thought "Landed a rare fish", +4 for 12 game hours.

## Concepts (2026-11-01)

From the owner: "Draw concepts", then, shown them, "Take them all": the four recommendations
are taken. They were drawn over a copy of the owner's colony, with the Hunter made the Ranger
in memory only. Grunbur, the colony's one dwarf allowed to fish, stands in as the Ranger.
Scratch is in `tmp/ranger_concepts_20261101/`; the window sheets are at 1920×1080 and
7680×2160.
- **The picture** (`icon_review.png`, `ui/career_sheet_*.png`): drawn in the icons' cells and
  shown on the career map's tile.
  - A · Both tools: the Hunter's spear crossed over the dwarves' peeled rod, the float hanging
    past the turf.
  - B · The catch: the spear planted upright, with a big perch hung from it.
  - C · The creel: a woven basket with a perch's and a trout's tail out of it, the spear behind.
  - Taken: A, as recommended. It reads as hunting and fishing at every size, as the Worker's
    axe and pick read as its work. B reads as a fish first, and C as a basket.
- **The crafting page** (`ui/craft_sheet_*.png`):
  - A · The Ranger's page: Crafters → Ranger is a page like every career's. Dried fish is its
    one recipe, the board's tags name the rack and the Ranger, and a line says what joins it
    with hunting.
  - B · The rack's page: opened from the rack, the page leads with the rack, lists the colony's
    racks and what each is doing, and shows the fish waiting.
  - C · Orders on the rack: the rack's own card holds Keep dried fish, what is on the rack and
    who works it.
  - Taken: A, as recommended and as the plan has it. Each career keeps its recipes in one
    place, as the Carpenter and the Blacksmith will. B gives one window two headings, and C
    puts the same order in two places.
- **The sheet** (`ui/sheet_sheet_*.png`):
  - A · The Miner's list: the five rewards as words, earned ones lit.
  - B · Odds you can see: each big-catch reward drawn as six catches with the big fish among
    them.
  - C · The catch log: fish caught by kind, big and rare fish, the best day, and the next
    reward.
  - Taken: C, as recommended. A record of the Ranger's own catches is what makes a fisher
    worth caring about. It needs a few counts saved for each Ranger (catches by kind, big and
    rare fish, the best day and the fish dried); A needs nothing new.
- **The big catch** (`fish/big_fish_sheet.png`), at the colony's river zone with the game's own
  landing pose:
  - A · The same fish, bigger: the trout at 1.4 times. No new art, but its cells come out
    bigger than every other model's, against the 1:16 grid (doc 63).
  - B · A big fish of its own: a heavier trout, longer and deeper, with a bigger eye and jaw.
    One more model for each fish.
  - C · Two on the line: two trout, matching the two that land. At a distance they read as a
    tangle.
  - Taken: B, as recommended. It reads as big at gameplay zoom and keeps the grid.

## How it plays

- **Promoting.** Workers make a Ranger's kit at the workbench (the hunting spear until
  the owner's change below). Choosing Ranger in Change profession sends the dwarf to
  collect the kit, as a Carpenter collects theirs, and the promotion chime plays when they
  have it.
  - The career map's tile stands where the Hunter's was and reads "Fishes the colony's
    waters and dries the catch. Hunting comes later."
  - The tile shows the dwarf's fit for Wisdom, then Agility.
- **Fishing.** A zone posts work for its spots as it does now, and the nearest idle Ranger
  takes a spot.
  - With no Ranger the zone waits, and its window says "No Ranger yet: promote one to fish
    here".
  - Each catch gives the Ranger one experience. It counts even when that catch fills the
    zone's Keep and stops the work, as a Miner's last block counts.
- **A big catch** shows a bigger fish on the line. Two fish land at the Ranger's feet, and the
  water loses one.
- **Drying.** Crafting outranks fishing (priority 46 against 42). With a Keep in stock order
  for dried fish, a Ranger dries each pair as it lands, then casts again, so a rack by the
  shore saves walking.
  - Crafters → Ranger is a page like every career's (concept A): Dried fish, its tags for the
    rack and the Ranger, and a note of what joins the page once hunting is built.
  - The board's tag says "✓ A Ranger" or "Needs a Ranger". With no Ranger, the order waits
    "for a Ranger".
  - With nothing to fish or dry, the Ranger hauls. With nothing to haul either, they rest
    like any idle dwarf.
- **The sheet** (concept C). The Profession tab shows the level, the bar ("40% to level 4 ·
  112 fish caught") and the Ranger's catch log, which takes the place of the Miner's list of
  rewards:
  - each kind of fish with its picture and count, with the kinds not caught yet dimmed;
  - big fish, rare fish, the best day ("14 fish · day 18 of spring") and the fish dried;
  - the next reward and the catches to go ("One catch in three is big, and rare fish bite ·
    38 catches to go"). It is gone at level 5, where the bar reads "Master Ranger · 412 fish
    caught".

  The compact panel reads "Ranger · Lv 3", as it does for the Miner.
- **The zone's window** shows the fish's trait under its name (step 3).

## The numbers (to tune in play)

- **Levels:** 10, 50, 150 and 400 catches.
- **Big fish:** 15% at levels 2 and 3, 30% at level 4 and 45% at level 5. Trout add 10 points.
- **Patience:** from level 3, winter's ×0.5 speed becomes ×0.75.
- **Rare fish:** 3% of catches at level 4 and 6% at level 5, three portions each.
- **Thoughts:** the calm one is +3 for 8 game hours and renews with each catch; a rare catch is
  +4 for 12.
- **Food:** at level 5 each fish taken from a water feeds 1.45 portions (trout 1.55). The
  waters that now feed about three and a half dwarves would then feed about five.

## How it will be built

- **The career** (`professions.json`). `base:profession:hunter` becomes
  `base:profession:ranger`, with:
  - its name, icon, summary and availability text;
  - `promotion_enabled`, the hunting spear as `required_tool`, and an `equipment_preview`;
  - `stats` (Wisdom, Agility);
  - its own `experience_thresholds`;
  - its level rewards: the big-fish chances, patience and the rare odds.

  The Crafters entry in `dock.json` and the `hunter` section in `worker_crafting.json`
  become the Ranger's, and the section goes live.
- **Levels for any career.**
  - `DwarfAssets.profession_level` reads a career's own thresholds and works for every
    career that earns experience. The Miner keeps its digging time.
  - `DwarfInspection.experience`, the career map and the roster's work note show the
    Ranger's rewards and catches, and the Profession tab shows a Ranger's catch log.
- **Ranger work.**
  - `TaskScheduler.types_for` offers FISH only to Rangers. It offers Rangers FISH, CRAFT for
    their section's recipes and HAUL.
  - The surface matcher already picks the nearest dwarf allowed the work.
  - Labor shows a Ranger's Fish, Craft and Haul boxes and keeps the others for a return to
    Worker, as it keeps Craft today.
- **The catch.**
  - `FishingSystem._land` gives the Ranger one experience before the lease can end. It rolls
    for a big fish, seeded as the catch time is, and lands two fish for one off the stock.
    It writes the catch in the Ranger's log; drying a pair adds to the fish dried.
  - Patience joins Wisdom in the fishing work rate (`DwarfWorkExecution`, kind "fishing").
  - `DwarfFishingPose` hangs the fish's big model on the line.
  - The zone's window says when no Ranger can fish.
- **The Ranger's recipes.**
  - Dried fish takes `section: "ranger"`.
  - A craft order goes to the career that owns its section: Rudimentary orders to Workers,
    Ranger orders to Rangers (`types_for`, `CraftingManager`).
  - `recipe_waiting_reason` gains "Needs a Ranger", and the board's tag names who makes it.
  - The rack's `crafting_recipe` already opens its recipe's section.
- **Fish that differ** (step 3): char's `keeps_days` becomes 3, trout get a `big_chance`, the
  spring cave pool ignores `season_speed`, and the zone's window gets the trait line.
- **The thoughts and rare fish** (steps 3 and 4):
  - the calm and rare-catch memories in `DwarfMood`, and their journal lines;
  - the rare fish in `resources.json`, with each water's rare fish and odds in
    `fishing.waters`.
- **Saves.**
  - Experience already saves per career, and every dwarf's saved experience lists each
    career. Older saves carry a Hunter count of 0, which the save check accepts and nothing
    reads.
  - No compatibility code (standing rule). The build confirms the owner's quicksave still
    loads.
  - The calm and rare-catch memories save with the mood while they last, as the grill
    memories do.
  - A Ranger's catch log saves with the dwarf. A dwarf who has never landed a fish has none,
    so the owner's quicksave needs nothing new to load.
- **In the owner's colony** the fishers stop when step 2 lands, until a Ranger is promoted.
  Any Dried fish order waits for one too.
- **Tests.**
  - A new `RangerTest` (fishing area) covers:
    - promotion with the spear;
    - Workers no longer fishing, and Rangers fishing;
    - experience per catch and the levels;
    - a big catch landing two fish for one;
    - winter patience;
    - Dried fish made by Rangers only, "Needs a Ranger" with none, and the rack opening the
      Ranger's page;
    - the sheet's line, and saves.
  - `FishingTest`, `FishDryingTest` and `CraftingSelectionTest` make their fishers and dryers
    Rangers.
  - The Crafters and career-map tests, and `DwarfStatsTest`'s Hunter fit, move to the Ranger.

## Art and sound

Hearthblock, through the usual pipeline (doc 61), concepts first:
- the Ranger's icon (concept A): the hunting spear crossed over the peeled rod on the turf,
  the float hanging past its edge. It replaces `hunter.png`; the old `.import` is left for
  the owner, as with other retired pictures;
- a big fish of its own for each fish, hung on the line (concept B). The concepts drew the
  perch and the trout; the char and the cave fish follow. Two ordinary fish still land;
- the concepts' models (`tmp/ranger_concepts_20261101/ranger_art.mjs`) move into
  `tools/hearthblock/art/`;
- step 4: the four rare fish in crates at three fills, on the line, raw and grilled on the
  stick, and their inventory pictures.

No new sounds. The cast's whoosh is still missing (doc 289).

## Built: step 2 (2026-11-01)

From the owner: "Build the Ranger".
- **The career.** The Hunter is the Ranger (`base:profession:ranger`): Wisdom, then Agility;
  promotion collects a hunting spear, as a Carpenter collects a kit; the career map's tile
  reads "Fishes the colony's waters and dries the catch on the rack. Hunting comes later."
  Its icon is concept A, the spear crossed over the rod.
- **Ranger work.** Only Rangers fish: fishing left the common work (`Task.COMMON_WORK`), and a
  career that names its own `work` does only that, so Rangers fish, dry and haul and never
  mine, fell or build. Labor greys out the boxes a career can't use and keeps their setting.
  The zone's window says "No Ranger yet: promote one to fish here" while the colony has none.
- **The Ranger's page.** Dried fish moved to Crafters → Ranger, a live page like
  Rudimentary (concept A): its one recipe, the tags "✓ A drying rack" and "✓ A Ranger ·
  Grunbur" (or "Needs a Ranger"), and a WITH HUNTING box under the recipes. Each craft order
  goes to the career that makes its section; with no Ranger the order waits as "Needs a
  Ranger", and one no idle Ranger can take is skipped, so the Workers' orders below it go
  on. The rack's Dry fish opens the page.
- **Levels.** One experience a catch, awarded before the lease can end, with levels at 10,
  50, 150 and 400 catches. A big fish one catch in six at levels 2 and 3, one in three at 4
  and 45% at 5: it lands as two fish for one off the stock and hangs as its own model on the
  line (concept B; each catch's roll is seeded and kept on its spot, so the cast shows what
  lands). Patience from level 3: winter's half speed becomes three quarters.
- **The sheet.** The bar reads "62% to level 4 · 112 fish caught" and the compact panel
  "Ranger · Lv 3". The Profession tab shows the catch log in place of the rewards (concept C):
  each fish with its catches, the Ranger's own first and the rest dimmed, big fish, the best
  day and the fish dried, then the next reward with the catches to go.
- **Not as planned, or drawn:**
  - no rare-fish row in the log and no "rare fish bite" in level 4's reward: rare fish
    arrive with step 4;
  - the career map keeps its words for every career: "Retained level 1 · 0 fish caught" and
    "10 more catches to level 2";
  - the career map warns when the career's own work is unticked in Labor (Fish for the
    Ranger, Mine for the Miner). Four of the colony's five dwarves have Fish unticked, so a
    Ranger promoted from one of them waits for the tick;
  - drying by Rangers is tested in `FishDryingTest`, beside the rack, rather than in
    `RangerTest`.
- **Code:** `DwarfAssets` (`profession_task_types`, `profession_allows`, `craft_section`,
  `section_profession`, `earns_experience`, `earns_by`, levels from a career's own
  thresholds, `level_rewards`, `level_reward`, `big_fish`); `TaskScheduler.types_for`,
  `crafts` and `has_idle_crafter`; `CraftingManager` ("Needs a Ranger", `crafters`,
  `crafter_name`); `FishingSystem` (the big catch, experience, the log, `patience`,
  `has_fisher`); `FishingSpot` (`roll`, `big_for`, `rate_for`); `DwarfFishingPose.catch_big`;
  `DwarfWorkExecution` (the Miner's award by `earns_by`, the big flag, patience's rate);
  new `CatchLog.gd` and `CatchLogView.gd`; `DwarfInspection.experience` for any career;
  `DwarfProfessionPanel`, `DwarfRosterPanel`, `WorkerCraftingPanel`, `FishingZonePanel`,
  `DwarfInspectorPanel`; `WorkerCraftOrder` counts fish dried; `TaskSupervision`.
- **Data:** `professions.json` (the Ranger, `work`, `craft_section`, `experience` for the
  Miner and the Ranger, the Craft and Fish boxes' words); `worker_crafting.json` (the
  `ranger` section, Dried fish's `section` and `catch_log`, the spear's and the rack's
  words); `dock.json` (Crafters → Ranger); the spear's description; the animals' notes.
- **Art (Hearthblock):** the Ranger icon (`icon/ranger` in `icons.mjs`, `ranger.png`);
  `tools/big_perch`, `big_trout`, `big_char` and `big_cave_fish` in `dwarves.mjs`, installed
  with the dwarf family. `hunter.png` is deleted; its `.import` is left for the owner.
- **Tests:** new `RangerTest` (fishing area): Labor by career, a Worker beside a zone never
  fishing, the spear's promotion, experience and levels, a big catch on the line, patience,
  the roster's note, the sheet and saves. `FishDryingTest` checks the Ranger's page, "Needs
  a Ranger", the tags, the fish dried and a drying order not holding up a Worker's torches.
  `FishingTest` fishes with a Ranger; `CraftingSelectionTest` races each recipe between its
  own career; `CraftingBrowserTest` and `ProfessionCraftingTest` count the Rudimentary page
  and skip live pages; `DwarfStatsTest` checks the Ranger's fit.
- **Seen in the game** (`tmp/ranger_build_20261101/shots/`, over a copy of the owner's
  colony with Grunbur as a level 3 Ranger and a sample log): the career map, the Ranger's
  page, the character sheet, Labor, and each fish's big model on the line at the river zone.
- **Saves:** a dwarf saves `catch_log` while it holds anything; nothing else is new, and the
  owner's quicksave loads. Its Workers stop fishing until a Ranger is promoted, and its Keep
  2 dried fish order waits for one.

## The Ranger's tool (2026-11-01)

From the owner: "the promotion tool is still a spear, while the rangers new icon is a
combination of a spear and a fishing pole, we should update the hunting spear I think".

The tool is hidden once a Ranger collects it. It shows in the crafting list, Inventory,
storage and the career map, and lies loose until collected. Three concepts in the starter
tools' own vocabulary and colours (`tmp/ranger_tool_20261101/`, `tool_review.png`; the wood
takes its log's colours as the spear's does):
- **A · Ranger's kit, bound** (recommended): the spear and a peeled rod bound side by side
  with two rope bands, as the carpentry kit binds its mallet and adze. The line is wound on
  the rod and the float is tied on at its tip. It is the icon's two tools, and the rod is the
  one a Ranger fishes with.
- **B · Ranger's kit, crossed:** the icon in the round, the spear laid over the rod and lashed
  where they cross. It is the most literal, but lying flat it sprawls and reads as a twig at
  tile size.
- **C · Ranger's spear:** one spear for both, with barbs on the point, the line wound on the
  haft and the float tied on. It is the cleanest picture, but Rangers fish with a rod, not a
  spear.

A build of A or B would add `base:resources:tools:ranger_kit` in place of the spear, with
the same recipe (a log and a Rough Stone at the workbench, Starter tools). It would update
the career's `required_tool` and preview, the texts, the model and its menu picture, and the
tests that name the spear. The spear's model and picture would be deleted, their `.import`
files left for the owner.

**Built: A (2026-11-01).** From the owner: "Build A".
- **The item.** `base:resources:tools:ranger_kit`, "Ranger's Kit", in place of the hunting
  spear, with an `equipment` block like the carpentry kit's: Crude, "Stone-tipped spear ·
  Peeled rod", and "They fish with its rod; the spear waits for hunting". Same recipe
  (`base:recipe:worker:ranger_kit`, Starter tools), with the line "A rod for the river, a
  spear for the woods." The career's `required_tool`, the career map's line and the Ranger
  page's hint name the kit.
- **The art.** `hearthblock_goods.starter('ranger_kit')` (concept A; the rod's line and
  float colours as `ROD`), installed through the items gallery, and its menu picture from
  `InventoryCatalogThumbnails.gd`. `hunting_spear.glb` and its picture are deleted; their
  `.import` files are left for the owner. The unused pre-Hearthblock `starter()` in
  `items.py` went with them.
- **Tests.** `RangerTest` promotes with the kit and checks the Equipment view;
  `SaveManagerRoundTripTest` and `ItemArtTest` (its wood colours) cover the new model.
- **Seen in the game** (`tmp/ranger_tool_20261101/shots/`, over the colony copy): the
  crafting window on the kit and the career map on the Ranger.
- **Saves.** None of the owner's saves held a hunting spear, so they all still load.

## The rack as the Ranger's workbench (2026-11-01)

From the owner: "I think the drying rack should move under the rangers menu as a workbench,
the ranger may have more workbenches later such as drying leather".
- **Built.** The rack's recipe moved from Rudimentary → Food to Crafters → Ranger →
  Workshops (`section` ranger, `category` Workshops), above Dried fish under Food. Rangers
  make it, still for two matching logs at the crude workbench. With no Ranger its order
  waits as "Needs a Ranger", and Rudimentary has no Food group now. Place still files the
  rack under Food (owner, 2026-10-31).
- **Texts.** The page's line reads "Food from the wild, and the Ranger's own workbench: the
  drying rack now, more with hunting". Its WITH HUNTING box names more workbenches, such as
  a rack for drying hides into leather.
- **Tests.** `FishDryingTest` checks that the rack waits for a Ranger with only a Worker,
  that the page lists the rack above Dried fish, and that the Ranger makes it at the
  workbench. `CraftingBrowserTest` counts Rudimentary's seven groups.
- **Seen in the game:** `tmp/ranger_tool_20261101/shots/rack_page.png`, over the colony
  copy.

## Rangers dry before they fish (2026-11-01)

From the owner, with Durrek fishing beside a Keep 5 Dried fish order that read "Waiting for a
Ranger": "Durek, our ranger keeps fishing and not making the dried fish, can we review his
priorities".
- **Why.** Crafting (46) outranks fishing (42), but a drying search spans several scheduler
  wakes, finding two fish of one kind and a route to the rack. Between wakes the next
  bucket gets a turn, and the fishing spot at the Ranger's feet won them within two frames,
  after every catch. A replay of the owner's quicksave showed it.
- **Built.** A career that names its `work` does it in that order: the Ranger's is now Craft,
  Fish, Haul, and `TaskScheduler.takes` keeps an idle Ranger from fishing or hauling while an
  available drying order waits for them. The current catch always finishes first. A drying
  search that fails backs its order off and frees the Ranger meanwhile. Workers and Miners,
  who take the common work, are unchanged.
- **Tests.** `FishDryingTest` puts a fishing spot at the Ranger's feet and allows one route
  probe a wake: the Ranger dries first. It failed before the fix. In the replay Durrek takes
  the order three frames after a catch, dries two trout and goes back to fishing.

## Real drying (2026-11-01)

From the owner, after Durrek dried his first batch: "the fish dried instantly, I don't think we
want it to work that way". I proposed the planned aging cellar's shape (doc 42: load, age by
itself, collect) and the owner said "Build it".
- **Hang.** The Ranger brings two fish of one kind and hangs them, the same 12 seconds. The
  order counts the batch done and can move to another free rack.
- **Dry.** The batch hangs on the rack, on show, for the recipe's `dry_hours` (24) of game time.
  One batch a rack; more racks dry more at once. An order with every rack busy waits "for a free
  drying rack · about 14 hours". Fish on the rack don't spoil and count toward Keep.
- **Take down.** Once dry, the rack posts a COLLECT lease, a new surface task type done by hand
  (priority 47, the Craft box in Labor). A Ranger takes the batch down in `collect_seconds` (4):
  two dried fish beside the rack, counted in their catch log. With no Ranger they wait on the
  rack. The Ranger's work order is now COLLECT, CRAFT, FISH, HAUL.
- **Code.** `WorkshopBatch.gd` holds a batch and is its take-down's work source.
  `CraftingManager` keeps `hanging` (a batch per rack, the rack claimed meanwhile), ticks it with
  its half-second refresh, takes batches down, drops a batch whose rack goes, and saves them
  (`worker_crafting.batches`). `WorkerCraftOrder.complete_build` hangs a `dry_hours` recipe's
  batch instead of making its goods.
- **Shown.** The rack's window: "Any Ranger" and a Drying row; its compact line "Drying 2 trout ·
  about 14 hours left", then "2 dried fish · waiting for a Ranger". The crafting window lists
  DRYING batches under the queue.
- **Tests.** `FishDryingTest`: no dried fish when hung; the rack's line and window; the batch
  counted to come; a save keeping it; half a day halving the time; one batch a rack; the
  take-down by a Ranger with the log; the crate batch on the freed rack; and the Workers' orders
  still not held up.
- **Seen in the game** (`tmp/ranger_tool_20261101/shots/rack_world.png`,
  `ranger_page_drying.png`): two trout on the colony's rack with 14 hours left.

## Steps

1. **Concepts** (drawn; the owner took the four recommendations):
   - the Ranger's icon and tile;
   - the Ranger's crafting page, with one live recipe and what comes later;
   - the sheet's level line and rewards;
   - a big fish on the line.
2. **The Ranger** (built, above):
   - the career and promotion, with its icon;
   - fishing and drying as Ranger work;
   - experience and levels, with big catches (their own models) and patience;
   - the catch log on the sheet;
   - the rack's page.
3. **Fish that differ and the calm job.** Mostly data.
4. **Rare fish.** Art first, then the odds, the journal line and the thought.

Each step gets focused tests, the job gate, a capture over a copy of the owner's colony, then
the owner's look in Play.

## Not in this milestone

- **Hunting,** its own milestone:
  - the spear against animal hit points (doc 45);
  - what an animal gives;
  - experience for each animal brought down, worth more than a catch since animals are fewer;
  - Agility in the aim.
- Smoked fish. Real drying is built (above).
- Ice fishing.
- Better rods made by other careers.
- More Ranger workbenches with hunting, such as a rack for drying hides into leather (owner).
- The calling trait and level 6, as for every career.
- Fish in trade, and cooking.

## Open

- The thresholds and the odds for big and rare fish: tuning in Play.
- Whether Rangers also pick wild berries and fruit, which is Gather work for everyone today.
- Whether rare fish should be worth more than food, through trade or a trophy on the wall.
- How the Crafters page shows a career with one live recipe and more to come: answered
  2026-11-01 by concept A, with a note on the page of what joins it with hunting.
