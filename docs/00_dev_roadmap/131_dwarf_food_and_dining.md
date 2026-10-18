# 131 — Dwarf food, dining and character screen

Agreed plan, 2026-10-12. Stages 1 and 2 are implemented. Stage 3, the larger
character-screen reorganization, remains planned.

## Decisions

- Food is a general item capability. Fresh fruit is the first enabled food;
  cooked meals, edible meats and other foods will use the same system later.
  A food-storage tag or cooking-ingredient tag alone does not imply edibility.
- Dwarves eat from reachable ground stockpiles and containers first, then allowed
  loose harvested food. Only desperate dwarves may automatically harvest a
  nearby ripe berry bush. Ordinary harvesting remains player-directed.
- Hunger uses game hours, including sleep, and stops on pause. It must behave
  identically over equal game time at every game speed.
- Hunger reduces mood and productive work speed, with no starvation damage or
  death. Health remains a separate future system.
- Bushes give several fruit units per harvest and regrow while in season.
  Current yields remain blueberry 3, elderberry 4 and strawberry 3. Blueberry
  fruits in summer, elderberry in autumn, strawberry in spring and summer.
  Two eligible game days between harvests is the initial tunable regrowth time.
  Regrowth pauses outside fruiting seasons and while uprooted/packed. Moving or
  saving a plant cannot reset its crop. This replaces one harvest per season.
- One berry inventory unit represents a small portion; one eating action never
  consumes a whole produce crate. Fruit initially shares a nutrition value.

## Stage 1 — Food foundation

Implemented general edible item metadata, hunger timing, storage-first physical
portion collection, loose-food fallback, eating completion, current save/load,
berry regrowth and a basic Food indicator in the shared dwarf inspector.

Initial tuning: Food ranges from 0 to 1, drains 0.075 per game hour, starts a
meal search at 0.40 and is labelled Famished at 0.15. A fruit portion restores
0.60. This targets about one portion per eight game hours (three per day), with
small deterministic differences in initial fullness. These are starting balance
values, not a claim that existing world food yields are already balanced.

Search must be bounded and resumable. Check the actual storage access cells,
try alternatives when a closer source is unreachable, and preserve the ordering
between stored and loose food. Failed searches retry after a short game-time
delay while the dwarf can resume useful work. Show the failure reason.

Food stays in storage until the dwarf physically collects it. Reserve one
portion per dwarf (several dwarves may claim different portions of one crate),
transfer it through the inventory owner, and remove it only when the
meal completes. Cancelled routes, removal of storage, changes of profession,
terrain recovery and player interruption must release claims and preserve cargo.
Save hunger and the last meal; unfinished food uses the existing carried-item
save contract and returns intact for collection after load. Runtime reservations
are rebuilt, not serialized. No legacy development-save migration is required.

Eating is personal self-care, not a public job another dwarf can claim. Active
eaters must be excluded from every scheduler assignment/reconciliation path.
Finish an active meal before starting sleep. If both needs trigger while awake,
famished food search takes precedence, but a failed search cannot prevent sleep.
Ordinary hunger does not wake a sleeper. Stage 2 extends the original standing
meal with seating, serving art and dining thoughts below.

Playtest: start a fresh development world, store harvested fruit, then open
Development → DEV: Dwarf tools →
**DEV: make a dwarf hungry**. The button lowers one awake dwarf to the ordinary
search threshold; it supplies no food. Inspect Food/current activity to follow
the trip. Overview shows hunger effects; Details shows the last food, elapsed
game hours and dining arrangement. The portion is visibly raised to the mouth.
Older development saves lack the required dwarf food state; current saves
preserve it, including the uneaten portion of an interrupted meal.

### Ownership

- `ItemDropManager` owns item definitions, explicit food metadata, loose portions
  and physical item transfers; it remains the sole resources.json loader.
- `StorageComponent`/`StockpileManager` own stored quantities and outgoing claims.
- A dwarf food behavior component owns hunger, search/meal state and last meal.
  `DwarfAgent` only integrates need priority, movement, interruption and save hooks.
- `TaskManager` owns worker availability; existing work release remains legal.
- `ShrubSeason` owns pure crop timing; `SurfaceDetailManager` owns crop commits,
  persisted plant state, relocation and visual refreshes.
- `DwarfInspection` supplies read-only presentation to the existing shared panel.

### Verification

Check clock speeds and pause; all enabled fruit and exclusion of non-food;
storage preference; unreachable and removed storage; exact portions from full
crates; two hungry dwarves competing for food; job interruption and resumed work;
meal cancellation and save/load conservation; hunger during sleep; empty-supply
retry; inspector layout. Exercise full saves and the shared job regression gate.
Check repeated in-season crops, off-season and packed pauses, relocation,
save/load, crop visuals and no duplicate reward after completion.

Verified 2026-10-12:

- All 29 fixtures in the shared job gate passed across the gate run and focused
  reruns, including full `SaveManagerRoundTripTest`. `ConstructionInputTest`
  now advances its refresh timer explicitly instead of assuming a fixed number
  of headless frames lasts long enough.
- `DwarfFoodTest` covers game speeds/pause/sleep, real stored and loose portions,
  simultaneous claims from one crate, the final-portion race, cancelled meals,
  removed workers/claims, inaccessible storage, permitted food, resumed crafting,
  containers, saved hunger/cargo and the shared inspector.
- `ShrubRegrowthTest` covers multiple normal harvests, seasonal and packed pauses,
  current saves, relocation, ripe visuals and duplicate completion. Existing
  shrub harvest, cutting and transplant fixtures also passed.
- Additional crate, storage-filter, hauling, rest and inspector checks passed.
  Native inspector captures at 1280×720 and 960×540 confirmed readable layout
  and scrolling. Test logs: `tmp/food_20261012/`.

Balance and prolonged colony play remain player playtests; the tests establish
inventory conservation and behavior, not final food availability across seasons.

## Stage 2 — Emergency foraging, dining and consequences

Implemented 2026-10-12. All four pieces below are live; this section records
the current rules and starting balance.

When no harvested food is available and the dwarf is famished, search known,
reachable ripe bushes within 24 blocks of routed travel. SurfaceDetailManager
owns exclusive personal crop claims and the same crop commit as normal harvest.
Pick the normal crop, eat one portion and leave the remainder for hauling. Do
not clear or uproot the plant, bypass regrowth or steal another worker's crop.

After collecting food, prefer a reachable free chair, stool or usable bench seat
at a properly positioned table. Claim the seat for the meal. If the complete
arrangement is unavailable, prefer a seat alone, then a table alone, then ground
eating. Bound travel/search time; a desperate dwarf should eat promptly. Dining
uses real furniture geometry and access, not simply a table somewhere nearby.
The initial limits are 16 blocks of travel, six when famished, and two simulation
seconds of incremental search. Backed chairs/benches must face the tabletop;
round stools may turn toward it. Headroom, access, bedroom privacy and furniture
removal are checked. A two-block log bench supplies one broad dwarf seat.
Leisure and dining share an exclusive seat claim; table access positions are
claimed separately. Removing a table preserves a usable chair; losing the seat
falls back without losing the carried meal. Cancel/load releases transient claims.

**2026-10-17 completion fix:** A successful seated meal transfers the same chair
claim and seated pose to ordinary idle rest, while releasing the dining-table
claim. Empty hands lower over the existing seat transition interval. The dwarf
stays available for work and later stands through the normal transition; needs,
movement, removal and load can still release the seat. See [203](203_dining_rest_and_game_partners.md).

Initial dining balance:

| Arrangement | Thought | Happiness |
|---|---|---:|
| Seat and table | No dining penalty | 0 |
| Seat only | Ate without a table | -3 |
| Table only | Ate standing up | -3 |
| Neither | Ate without a proper place | -8 |

Apply one outcome, not the combined penalty plus both individual penalties.
The next meal replaces the dining thought; each lasts at most eight game hours.
Repeated poor meals do not stack duplicates. A proper meal clears the previous
penalty. Numbers are tunable. Hungry dwarves lose five happiness points and work
10% slower; famished dwarves lose 15 and work 25% slower. The stronger tier
replaces the weaker one. Productive work and job pickup/deposit slow; walking,
pathfinding and eating do not. Supervisor time estimates include the multiplier.
Feeding removes hunger effects immediately. There is no damage/death or raw-fruit
penalty. TaskManager remains the sole owner of task_config.json tuning.

Fruit-in-hand artwork uses item-owned serving palettes and a repeated eating
motion, while the real one-unit cargo retains inventory ownership. The inspector
shows work/mood effects, last meal and dining thoughts. A persistent, quiet HUD
warning counts hungry dwarves whose searches found no reachable harvested food;
it suggests harvesting or restoring storage access and clears on successful
collection. Inventory totals alone do not prove food is accessible.

`DwarfForaging` and `DwarfDining` are per-dwarf helpers, not public work orders
or new autoloads. Foraging progress saves in the plant's existing harvest work;
meals save their last arrangement, and mood saves its one dining outcome/timer.
Uneaten portions remain recoverable through the existing cargo-save contract.

`DwarfDiningTest` covers all four arrangements, stool/bench use, incorrect chair
orientation, competing diners, cancellation/removal, storage before emergency
foraging, crop conservation/claims, saved crop progress, seasons, bounded travel,
mood replacement/expiry, work rates and inspector/warning data. It joins the
32-fixture job gate. Native eating/inspector captures and logs are under
`tmp/dining_20261012/`. All 32 checks pass, including the full save/autosave/backup
round trip with dining fields. Rest and bed-ownership fixtures also pass. Native
reviews cover eating, meal details and the shortage HUD at 1280×720 and 960×540;
the warning has an explicit viewport-bounds regression. `verification.json`
records the latest result/log for each gate fixture after targeted repairs.
Prolonged supply/demand balance remains a player playtest. Future meal quality,
preferences, dietary restrictions, spoilage, farming and cooking are separate extensions.

## Stage 3 — Dwarf character screen

Use Stonehearth's persistent identity header and focused tabs as information
hierarchy inspiration, keeping Deepdraft's Hearth & iron visuals. The standalone
inspector and Colony roster continue sharing one component.

Persistent header: portrait, name, profession, actual level/XP where supported,
current activity, compact Food/Rest/mood indicators. Keep Locate and Follow.

| Tab | Contents |
|---|---|
| Overview | Current action/reason, destination, last meal, cargo, assigned bed |
| Morale | Positive/negative thoughts, real effects and remaining duration |
| Traits | Existing traits and readable descriptions; identify inactive effects |
| Equipment | Actual equipped tools and equipment |
| Profession | Current role, implemented progression and promotion options |

Keep cargo in Overview until personal inventory warrants a Backpack tab.
Individual appeal tastes, Mind/Body/Spirit equivalents and health displays
must wait for supported gameplay, rather than inventing values for the screen.

## Reference and balance notes

Reviewed local Stonehearth `ai/actions/eat_action.lua`, food retrieval/serving
actions, `components/consumption/consumption_component.lua`, and
`ui/game/character_sheets/citizen_character_sheet/`. Its separate portions,
reachable food retrieval and seat/ground alternatives inform the design. Our
storage-first order and emergency bush fallback are Deepdraft decisions.

At three portions per dwarf daily, five dwarves need 420 portions in a 28-day
season. Compare real wild/cultivated yields, accessibility and starting supplies
before finalizing balance. In-season regrowth helps; winter storage still matters.
Tree fruit (including juniper) retains its existing seasonal harvesting rules;
this plan changes berry-bush regrowth only.
