# 45 — Wildlife

**2026-10-15 — Duck body clearance:** [197](../00_dev_roadmap/197_duck_update_performance.md)
reuses inclusive raw-solid/placed-obstacle bounds across duck updates through
AnimalNavigation's existing bounded main-thread cache. Terrain edits, placed
occupancy changes, streamed chunks and world/registry resets invalidate affected
results, including footprints crossing tile seams. These entries share the
existing 128-tile/1,024-entry-per-tile limit with terrestrial navigation. They
remain separate from terrestrial air/support checks: swimming water is passable
and flight above terrain height still checks placed obstacles. Duck water levels,
hydraulic safety, surface results and canopy intersections keep their existing
live observation rules. Every duck continues to update and animate each active
frame, including offscreen. No behavior, population, save-schema or art changes.

**2026-10-15 — Arrival preparation:** [193](../00_dev_roadmap/193_arrival_preparation_performance.md)
spreads duck habitat and flight preparation across main-thread frames. The event
director shares a soft 2 ms preparation budget; pending work does not consume a
candidate attempt. Transient work is discarded on load/expiry; saved seeds and
ordinals restart it. The final member entry still checks the live landing and
complete flight. Population caps, chance rolls, member spacing, clearances,
ordinary animal updates and the save format remain unchanged. Duck query reuse
is enabled only inside a synchronous preparation slice and cleared afterward.
Terrestrial searches and final entry checks remain synchronous.

**2026-10-14 — Duck water/clearance query reuse:** [186](../00_dev_roadmap/186_duck_query_performance.md)
adds bounded reuse only within one synchronous WildlifeManager update. Its
query maps are discarded at the end, so fractional water levels remain live
next update; population/arrival queries stay live. Raw solid bounds now also
use the edit-invalidated cache described in 197 above. Saved-game duck CPU
fell 19–20% and total wildlife CPU 13% in 186. All 1,200
differential updates, 882 query comparisons, 11 fixtures and packaged checks
pass. Decisions, flight, animation, offscreen activity and saves are unchanged.

**2026-10-14 — Navigation query reuse:** [180](../00_dev_roadmap/180_wildlife_navigation_performance.md)
adds bounded terrain/clearance/support caches with live edit, occupancy, water
and reload invalidation. Wildlife still advances every frame everywhere; needs,
travel, hunting, animation and saves keep their existing behavior. Later fresh-world
wildlife P95 falls from 29.4 to 5.9 ms. Ten fixtures, 392 navigation comparisons
and native packaged-save checks pass. Restart Play or use the refreshed Windows build.

**Wolf size:** the chibi Hearthblock wolf is about 2.4 blocks to the ear tips
([256](../00_dev_roadmap/256_hearthblock_art_pilot.md)). Its definition owns the visual
scale and the four-wide, three-high navigation clearance. Flat strides remain two
cells; terrace transitions span four cells with twice the duration. Capture reach,
needs and population rules are unchanged.

**Current scope — 2026-10-10:** rabbits, deer, wolves and ducks are live, including
scheduled terrestrial/aerial arrivals. Current saves require all four species'
arrays and initialization flags. Older development saves are not migrated; the
historical milestone notes describe earlier formats, not compatibility promises.

**Art — Hearthblock (2026-10-21):** all four species are chibi Hearthblock animals
([256](../00_dev_roadmap/256_hearthblock_art_pilot.md)), authored in
`tools/hearthblock/art/wildlife.mjs` and built by `tools/voxel_assets/wildlife.py`:
23 parts (rabbit 3, deer 6, wolf 5 and duck 9). The duck has two folded-wing meshes
that show whenever it isn't flying. Each animal's joints are in its definition's
`visual_pose`, and its visual root squashes and stretches (`GrazerAgent._squash_stretch`,
amount in `visual_pose.squash`). Needs, predation, navigation, arrivals and saves keep
the contracts below.

## Rabbit pilot — live 2026-10-09

The player approved rabbits first, with gentle animal hunger and sleep, then
deer and wolves. Needs create visible behavior without starvation damage. Wolf
captures now remove prey, with protected minimum populations. Scheduled rabbit
arrivals shipped subsequently in milestone 94; the reserve floors remain intact.

- Up to 48 rabbits start on seeded, dry grassy lowlands (ground below Y44),
  at least 24 blocks apart, with at least two legal exits. Small scheduled edge
  arrivals can later settle up to that cap. No breeding, domestication, player
  hunting or loot yet. Wolves can hunt prey above
  the protected population minimum described below.
- Rabbits explore near their starting area, hop over one-block terraces and
  graze ground vegetation. Surface grass and surface dirt provide forage in all
  seasons. Grazing neither edits blocks nor harvests shrubs, flowers or crops.
- Appetite increases by 0.055 per game hour. At 0.48 a rabbit seeks food;
  six seconds of uninterrupted grazing relieves 0.55. Interrupted meals give
  no benefit. Feeding is occasional, not a constant food emergency.
- Fatigue also increases by 0.055 per game hour. Rabbits prefer naps during
  10:00–16:00 and 23:00–04:00, offset by up to an hour per animal. A tired rabbit
  prefers adjacent cover before settling; exhaustion can trigger sleep outside
  those windows. Sleep restores 0.36 per game hour until fatigue reaches 0.08.
- A dwarf within seven blocks interrupts feeding or sleep. Rabbits hop away at
  twice their ordinary speed, with an eleven-block safe distance and four calm
  seconds before normal behavior resumes. Dwarves do not chase them.
- WorldClock pause and speed apply to movement, needs and animation. All animals
  continue to simulate off screen; slicing only changes visibility.

## Ownership and navigation

`WildlifeManager` is a scene owner alongside DwarfDirector and CraftingManager.
It alone loads `data/entities/animals/rabbit.json`, `deer.json`, `wolf.json` and `duck.json`, loads their
shared model parts, and owns generation, inspection and the `wildlife` save
section. `GrazerAgent` owns common needs, decisions, terrain support and saved
state; `RabbitAgent` supplies the original rabbit model/poses, while `DeerAgent`
supplies articulated deer poses and herd steering. WolfAgent reuses common
movement/rest but replaces grazing decisions with bounded pursuit. The manager
owns prey claims and commits capture and meal together. DuckAgent supplies
water/land/air motion through DuckNavigation; DuckPopulation plans safe flocks
and aerial arrivals. Flight checks query nearby tree canopies from
SurfaceFloraSpawner as well as terrain and placed obstacles. No additional
global classes or autoloads are registered.

`AnimalNavigation` reads live WorldData chunks with generated-data fallback and
PlacedEntityRegistry occupancy. Rabbits require a 1×1 footprint with two empty
cells, use cardinal local hops and cannot use ladders, water or cliffs. Step-up
movement rises before crossing the edge; descent crosses before dropping.
Every active hop is revalidated. Removed support causes a visible vertical fall;
new construction can displace a rabbit into an immediately open adjacent cell.
Dwarf NavGrid retains its three-cell clearance and existing route behavior.

Deer require a complete 2×2 supported footprint and four empty cells above it.
Cardinal strides move two cells; both endpoint footprints cover the full sweep,
including overhead space when stepping up. This conservative rule keeps deer
away from narrow ledges, gaps and low ceilings. Deer check other deer positions
and reserved stride destinations before moving. They do not reserve dwarf work
cells or use dwarf navigation.
Grazing also checks the extra row reached by the lowered muzzle and stops if
that space becomes obstructed or loses support.

Ordinary movement uses local wandering and escape steering. Arrivals follow a
prevalidated edge-to-inland route before beginning ordinary wandering.
A boxed-in rabbit may wait; it receives no starvation damage. Wolf pursuit uses
bounded best-first searches of at most 64 nodes per stride. Dens and long-range
food searches remain future work.

## Presentation and persistence

Three Hearthblock voxel GLBs (body, head, ears), authored in
`tools/hearthblock/art/wildlife.mjs`, use world units and root scale 1. The chibi
rabbit fits one block front to back and side to side and stands 1.5 blocks tall,
with a cream muzzle, paws and tail, a brown coat and pink inner ears. Head bobbing,
ear movement, a crouched sleeping pose and hopping animate without a skeleton.
Existing world lighting shades the models.

Click a rabbit for activity, appetite and rest in Object explorer, with Locate
and Follow actions. Concealed caves and hidden slice levels never expose rabbit
selection. Wildlife does not discover caves.

Quiet rabbit audio shipped in [91 — Rabbit audio](../00_dev_roadmap/91_rabbit_audio.md).
Explicit selection plays a short breath/tooth-tick cue even while paused, with
three variations and a shared 0.75-second click cooldown. Grazing emits two soft
leaf/nibble phrases, at 8% and 52% of the existing meal animation. It has three
variations, a fourteen-block audible radius, zoom attenuation and a two-voice
cap. Sleeping has no ambient sound. Grazing playback pauses with simulation and
stops if the rabbit flees, becomes hidden, is removed or the scene changes.
These rabbit cues consume only cosmetic RNG, never animal RNG, and create no
save fields. Ducks instead save their behavior's quack timer; playback variation
still uses cosmetic RNG.

Save priority 65 restores the entire population after dwarves and before the
camera/slice. Identity, current/home/target cells, position, yaw, appetite,
fatigue, activity, timers, hop progress and pose phase survive. Each rabbit's
64-bit RNG state is stored as text to avoid JSON numeric precision loss. Saving
is observational. An initialized empty population is not reseeded on load;
it can receive future scheduled arrivals. The `wildlife` owner and all current
species fields are required by SaveSnapshotValidator before restoration.

## Deer — live 2026-10-09

- Up to eighteen deer spawn as six groups of three on connected dry grass below
  Y44. Group origins are at least 96 blocks apart; members start four blocks
  apart within an eight-block patch. Seeded identity and membership are stable.
- Gentle local steering brings wandering members toward their group beyond a
  six-block cohesion radius. Escape takes priority over cohesion. This is loose
  grouping, not coordinated migration or long-distance herd pathfinding.
- Appetite rises by 0.045 per hour; threshold 0.48 triggers eight seconds of
  ground grazing, relieving 0.55. Fatigue rises by 0.05 per hour, with the same
  preferred rest windows as rabbits and recovery of 0.34 per hour. Ground
  vegetation remains unlimited; berries and farms are untouched.
- Dwarves within ten blocks interrupt meals/rest. Deer flee at roughly 5.9
  blocks/second versus ordinary strides at 1.9, seeking sixteen blocks of
  separation and five calm seconds. Wolves also trigger escape and can capture
  deer; deer do not attack.
- Six voxel parts form an antlered deer, with four animated instances of the
  leg mesh. Neck and head joints lower the muzzle for grazing; rest lowers the
  body and folds legs. The first model has no sex, age or seasonal coat variants.
- Three selection and three leafy eating sounds share WorkFeedback's existing
  bus/pool. Selection has a 0.85-second cooldown; two graze cues occur at 10% and
  55% of the meal, with an eighteen-block radius and two-voice cap. Pause, zoom,
  visibility and source cleanup follow the rabbit rules. Sleeping is silent.
- Object explorer includes herd size and the existing Locate/Follow controls.
- The required `deer` array and `deer_initialized` flag share the `wildlife` save
  section with unchanged rabbit records. Each deer saves its herd ID in addition
  to the common state. Explicitly saved empty deer populations are not reseeded but can
  receive future scheduled arrivals.

Art generators, checks and playtest notes: [92 — Deer wildlife](../00_dev_roadmap/92_deer_wildlife.md).

## Wolves — live 2026-10-09

- Four wolves start on dry supported lowland grass, at least 128 blocks apart
  and 18–36 blocks from original seed-derived prey habitats. Their initial
  appetite ranges from 0.45 to 0.72, allowing some early hunts.
- Appetite rises by 0.012 per game hour. A wolf can acquire prey only at 0.6 or
  above, outside its satisfaction/retry period and while awake and calm. It
  chooses nearby unclaimed rabbits/deer within forty blocks and line of sight.
- Pursuit uses a 4×4 footprint with three-cell clearance, cardinal strides and
  bounded local routing. Two-cell flat hunting strides take 0.28 seconds;
  four-cell terrace strides take 0.56 seconds. After twelve seconds,
  a lost/distant target, fatigue, or a blocked route, the wolf gives up and waits
  a game hour before another attempt. A dwarf within eight blocks interrupts
  hunting/eating; wolves retreat and never attack colonists.
- All rabbits/deer treat nearby wolves as threats, including during feeding and
  sleep. A capture requires close contact (1.6 blocks), nearly equal elevation,
  clear intervening voxels and continuous floor support. Every intersected
  contact voxel is checked, including narrow corner intersections.
- Captures are non-graphic: the prey disappears and the wolf pauses to eat for
  nine seconds. The owner removes the prey and credits that one meal atomically.
  Rabbit meals relieve 0.75 appetite and prevent another hunt for 36 game hours;
  deer relieve 1.0 and prevent hunting for 72 hours. Interrupting the eating pose
  keeps this credit, avoiding replacement kills. No corpse items or loot spawn.
- Predation stops at 32 rabbits or 12 deer. These configurable reserve floors
  are deliberate pilot balance, not a breeding or replenishment simulation.
  Scarce prey causes a search delay; wolves never take starvation damage.
- Fatigue rises by 0.04 per hour, sleep restores 0.3 per hour, and wolves prefer
  rest between 08:00 and 17:00 with the common per-animal time offset. Exhaustion
  can end a hunt and trigger rest outside that window.
- Original grey voxel art animates walking/running, head/ears/tail, eating and
  folded rest. Three soft selection chuffs and three eating phrases reuse the
  Work bus. Eating cues occur at 12% and 58%, audible nearby with an eighteen-
  block range. Sleep has no ambient audio; selection can play while paused.
- The inspector shows activity, needs, diet and hunting/satisfaction status.
- `wolves` and `wolf_initialized` are required in the `wildlife` save section.
  Target ID, pursuit time, retry/satisfaction hours and common state persist.
  Target nodes are rebound by ID; stale targets are abandoned without a meal.
  Consumed prey remains absent on load. Explicitly empty wolf populations are not
  reseeded but can receive future eligible arrivals.

Generators, checks and playtest notes: [93 — Wolf wildlife](../00_dev_roadmap/93_wolf_wildlife.md).

## Planned food connections

Berry nibbling and crop theft remain separate work. Existing shrubs represent a
whole seasonal crop; a future nibble needs partial-yield accounting, a small
per-plant loss cap, reservation handling and saved seasonal consumption. The
plant should survive and ordinary vegetation should remain reliable food.

## Scheduled rabbit arrivals — live 2026-10-09

WorldEventDirector schedules 1–4-member opportunities every 2–4 game days,
independent of kills and population. Seasonal chance, the 48-rabbit cap, local
recent hunting pressure, nearby dwarves and suitable connected habitat can
prevent entry. Opportunities expire rather than accumulate. Rabbits enter one
at a time through a live validated boundary route and travel at least 32 blocks
inland, retaining fleeing, feeding and sleep. Inspector and Follow expose the
journey; its progress and pending group members survive saves without duplicates.

WildlifeManager.remove_animal with cause
player_hunt records local pressure for future player hunting; wolf predation
does not. The existing wolf prey floors remain unchanged. Settings, provider
contract, persistence, checks and DEV controls are documented in
[94 — Rabbit arrival events](../00_dev_roadmap/94_rabbit_arrival_events.md).

## Deer and wolf arrivals — live 2026-10-09

Deer opportunities bring 2–4 members every 4–7 days, capped at 18. Each group
has one saved herd identity and separate connected homes at least four blocks
apart, at least 40 blocks inland. Wolf opportunities bring 1–2 every 7–12 days,
capped at four, with destinations at least 48 blocks inland. Both retain seasonal
chance, local hunting-pressure avoidance, expiry and the no-compensation rule.

All wide routes and entry spacing use full species footprints and clearance.
Wolves require five surplus prey per total living wolf above the existing
32-rabbit/12-deer reserve floors, plus two eligible prey within 64 blocks of
each destination. Food is rechecked before each entry. New wolves enter content
and finish settling before hunting. Pending routes, members, herd identity and
movement survive current saves. Newly configured event definitions receive delayed
opportunities; this does not bypass validation of the current wildlife format.

Full settings, native captures and checks:
[95 — Deer and wolf arrivals](../00_dev_roadmap/95_deer_wolf_arrivals.md).

Pack coordination, breeding, corpse resources,
player hunting, domestication and wolf/colonist combat remain separate decisions.

## Ducks — live 2026-10-10

Three seeded flocks of 2–4 ducks occupy calm water near grass/dirt shores.
They swim at the live water level, walk onto reachable banks, forage, preen,
rest and flee dwarves/wolves. Short flights allow escape and relocation, including
to dry shores when tired. Waterfall approaches and cave water are excluded.
Air routes check real terrain, occupied cells and tree canopy bounds both when
planned and while moving. This does not change dwarf or terrestrial-animal paths.
Streamed trees retain their scatter-origin column ownership even when jitter
places them across a chunk boundary. Felling removes them from that owning list;
flight queries skip freed or queued-for-deletion nodes before typed access.
`DuckWildlifeTest` covers both boundary-crossing felling and a stale freed entry.

Male/female voxel art has articulated wings, heads and feet; wakes, splashes and
quiet procedural quacks use existing water/world presentation and Work audio.
The inspector and Follow work while walking, swimming or flying. Airborne state,
needs, group identity and RNG survive current saves, including pending arrivals.
New 2–5-member aerial opportunities every 4–7 days share the event director's
seasonal/habitat/pressure gates and a population cap of 16.

No eggs, breeding, domestication or duck predation is added. Wildlife water
interaction is observational: ducks never create/remove water or vegetation.
Settings, implementation, tests and playtest controls:
[111 — Duck wildlife](../00_dev_roadmap/111_duck_wildlife.md).

Verification and playtest steps: [90 — Rabbit wildlife](../00_dev_roadmap/90_rabbit_wildlife.md).
