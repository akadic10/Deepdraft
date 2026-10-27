# 41 — Dwarf Agents

**2026-10-19 — Dining while famished (doc 250):** once a dwarf holds food, dining
keeps the normal 16-routed-block range (`food.dining_distance`), famished or not.
The two-second bounded search and existing route/seat claims remain. The former
six-block famished exception skipped Birna's nearby free dining stool in the player
save. Stored food, emergency foraging and need thresholds retain their existing
priorities.

**2026-10-19 — Solo and shared recreation (docs 198, 200, 203, 249):** a dwarf can
play immediately at one game stool for +4 happiness after a full game. A partner can
join; both must play a fresh full game for +8 each. The thoughts last 12 game hours
and contribute only the stronger bonus. An occupied table searches up to 48 routed
blocks for a companion under the existing bounded probe budget. The six-hour cooldown
and needs/work/privacy rules still apply. Separate optional solo memory persists
without changing old social memories.
- **The board.** The Board-game Table (Rudimentary → Recreation, Place → Recreation)
  keeps a 3 × 3 game area with two opposite Log Stool guides just outside it (3 × 5 with
  both stools). Stools on those guides are game seats: dining and idle sitting skip them,
  and they become ordinary seats when the table goes.
- **Who plays.** Idle dwarves, and a working dwarf whose happiness is below the 50
  baseline, if they carry nothing, are neither tired nor hungry, and are not collecting a
  profession tool or leaving a bridge or ladder. Explicit movement, food and sleep come
  first: when one of them claims a player, the game ends for both.
- **Matchmaking** (`BoardGameRecreation`, owned by FurniturePlacementController; no
  autoload): one candidate and one bounded route slice per frame, at most three seconds
  per candidate. A free table recruits within 24 routed blocks, an occupied one within 48,
  counting the route around the table and room. Players leave the idle pool until the
  game ends.
- **Play.** A seated dwarf starts playing alone. When a partner sits down, a fresh
  20-second shared game starts; solo and travel time never count toward it. While a
  recruited partner is on the way the solo game lasts up to 30 seconds (`wait_seconds`);
  if the partner never arrives, the seated dwarf earns the solo reward and the traveller
  nothing. A game nobody has started within 30 seconds is called off.
- **After.** A completed game sets the six-game-hour cooldown; the happiness memory never
  blocks another game (doc 203: it once kept recent players out for 12 hours). An
  interrupted or unfinished game earns nothing and retries after half a game hour; work
  returns through the normal cheap release.
- **Look.** The board and counters belong to the table. Players take turns reaching
  toward its `game_surface_height` with a detached hand (a solo player takes both turns);
  logical feet stay on the floor beside the stool while the visual parts sit.
- **Saves.** `recreation_memory_hours` (shared play), `solo_recreation_memory_hours`
  (written only while positive) and `recreation_retry_hours` (the cooldown or retry) save
  with the mood. Games, routes and seat claims are transient and start afresh after a
  load. Tuning is `recreation` and `mood.recreation` in `task_config.json`.

**2026-10-17 — Moving between slices (doc 217):** Dwarves refresh slice visibility on
global transform changes, before rendering. Ordinary stairs/ladder travel now
shows a worker entering the selected level and conceals one leaving it, without
another slice-button click. Paused restoration also refreshes. This corrects
invisible downstairs torch work in the player's save; navigation and wall reach
are unchanged. The rule is in doc 21, "Known limitations".

**2026-10-17 — Visible needs (doc 214):** overhead food, exhaustion and unhappy-face
badges show serious or unresolved needs. `DwarfConcern` supplies one read-only
reason/action to the projected 2D display, the compact panel and the character sheet;
it never plans routes, claims food or saves anything. Normal food/rest/mood simulation
and save fields are unchanged; an Unhappy or Miserable dwarf's face names the strongest
active negative thought. The conditions and their order are in doc 23 ("Dwarf concern
badges").

**2026-10-17 — Construction:** Workers deliver normal-capacity bundles to a
temporary project crate before building. `DwarfConstructionPose` uses the existing
stone-hammer model with two floating hands and a target-face contact point.
The striking end aligns squarely with the surface: low blocks are hit from above,
raised blocks on their near face. A smaller held scale and close-target stance
keep the swing readable. Hammer knocks follow actual contact crossings through
the existing Effects audio, including pause, speed, distance and slice rules;
project completion and interruption restore the ordinary pose and stow the hammer.
Finishing an individual block keeps the same assignment and stance when more
supported blocks are reachable from the current cell. The builder finishes the
current column before turning to other reachable work; only exhausted or blocked
access returns to planning. The stance is anchored once on arrival from the near
face's horizontal clearance, never from each target's height, so both feet stay put
while the hands reach up the column; ending the assignment per block made builders
step between stones (`ConstructionWork.continue_staged_build`). Supervision tracks each block as a separate work unit.
`DwarfWorkExecution` applies the existing labor-speed factor to three seconds per
voxel. Carry capacity and item carry costs are unchanged (doc 205).

**2026-10-14 — Colony size:** The intended maximum is **30 dwarves**.
Use 5/20/30 as the routine performance cases and test mature-colony work and
needs at 30. Larger development populations are stress tests. This is design
direction; runtime population enforcement has not been added. See
[11 — Overview](../10_core_foundation/11_overview.md); the scaling benchmark for
these cases is in [13 — Measuring performance](../10_core_foundation/13_architecture.md#measuring-performance).

**Proportions:** `DwarfAssets` owns `data/entities/dwarves/proportions.json`. Body and
head widths are 1 because the Hearthblock parts carry their own shape; the file sets
the relaxed hand and foot stance. Standing height and the logical 1×1×3 body stay
fixed. Assembly, work/rest resets and static portraits use those values. Tool/carry
grips and appearance IDs remain current; existing saves receive the new shape.

**2026-10-12 — Food and dining (doc 131):** game-hour Food, physical fruit
portions from reachable storage before allowed loose food, bounded retries,
safe work interruption and current saves (doc 31). Famished dwarves can pick a nearby
ripe bush only after harvested food fails (doc 42). Diners prefer seat/table, seat alone,
table alone, then neither; penalties are 0/−3/−3/−8 for up to eight game hours.
Hungry/famished dwarves lose 5/15 happiness and work 10%/25% slower. No damage or
death. Serving art, last-meal details and the Events food warning are live; the
character sheet (doc 23) replaced the planned stage 3 screen.
Fresh fruit is the first edible content; future meals/meats use the same metadata
(the item's `food` block in `resources.json`: `edible`, `nutrition`, `serving`). A
storage or cooking tag alone never makes an item edible, and one unit is one portion, so
a meal never empties a crate. Tuning is `food` in `task_config.json`.
- **Search and claims** (`DwarfFoodBehavior`): storage first, then allowed loose food, at
  each source's real withdrawal stands, moving on when a closer source is unreachable. A
  failed search gives its reason and retries after `retry_hours` while the dwarf works.
  Several dwarves can claim different portions of one crate. Hunger, the last meal and
  its arrangement save; a portion in hand uses the carried-item save, and claims are
  rebuilt, never saved.
- **Priority.** A meal in progress finishes before sleep. A famished search comes before
  sleep, while ordinary hunger waits until the dwarf wakes. A failed search never keeps a
  tired dwarf awake, and hunger never wakes a sleeper.
- **Dining** (`DwarfDining`): backed seats must face the tabletop; round stools
  (`face_nearby_fire`) may turn to it. Headroom, access, privacy and removal are checked;
  a two-block bench is one broad seat, and board-game stools are never dining seats.
  Seats share leisure's exclusive claim; table access spots are claimed separately.
  Losing the table keeps a usable seat; losing the seat falls back without losing the
  meal. A seated meal ends in idle rest on the same seat (see Idle activity).
- **Effects.** One dining outcome per meal: the next meal replaces it, and a proper meal
  clears it. Hunger effects end the moment the dwarf eats. The slowdown applies to
  productive work and pickup/deposit, not to walking, pathfinding or eating.
- **DEV.** Development → Dwarf tools → DEV: make a dwarf hungry sets one awake dwarf to the
  search threshold; it gives no food.

**2026-10-11 — Privacy and thermal sleep comfort (doc 122):** Idle visitors leave
bedrooms; owners may relax in their own, and unassigned bedrooms are for sleep. Work
access remains open. Cold/chilly/hot sleep creates a −20/−5/−15 happiness thought after
one actual game hour asleep; strongest thermal penalty only, lasting 24 hours (doc 34).
- **The rule** (`DwarfPrivacy`, from RoomManager's room kinds): a personal bedroom admits
  only its owner, an unassigned bedroom only sleepers, and barracks and every other room
  are shared. A room that is unsealed, or has lost its bed or light, follows ordinary
  rules.
- **What it covers.** Wandering, chair choice, dining and game seats, ground sleep and bed
  routes, including their string-pulled shortcuts; a bed search may take a public detour.
  Ordinary work routes and doors stay unrestricted (doc 32).
- **Leaving.** A dwarf idling or about to sleep in a room it may not use walks out first;
  it is never teleported or put to sleep there. Rest and work can interrupt the walk, and
  a bed reassignment displaces idle visitors the same way.

> **IMPLEMENTATION STATUS (First Dwarf Milestone, doc 16 — banked 2026-06-10 → 2026-07-02).**
> Shipped: `DwarfAgent` (`scripts/entities/DwarfAgent.gd`) with the four-part mesh hierarchy,
> runtime tint split (head/hands tinted, body/feet baked — doc 17 §1), procedural
> **distance-driven walk gait** (plant/lift foot phases, counter-swinging hands, body lean;
> `walk_speed` 3.4, `stride_length` 1.05 — TaskManager movement tuning), zone-lease mining execution
> with the vertical reach envelope, and **sleep-lite** — the single `sleep` stat below, draining
> per the table, with reachable bed use, sheltered ground sleeping and the release protocol
> (`31_task_system.md` §Release Protocol). Procedural generation (names/appearance/traits,
> seed-deterministic per `world_seed + birth_index`) runs through `DwarfFactory` +
> `DwarfAssets`; dwarves spawn at the player-placed Settlement Flag. NOT yet implemented:
> thirst/alcohol/health, the broader thought system, the full profession roster and the
> full needs-interrupt priority ladder — the tables below remain their design source.
>
> **Components (doc 258 step 8, 2026-10-22).** `DwarfAgent` keeps identity, needs,
> task dispatch (`receive_task`), interruption (`abort_task`, `force_interrupt`) and
> the read-only views. Preloaded components (no `class_name`) hold the rest:
> `DwarfBodyRig` builds and tints the parts, owns the work/carry rigs, the idle bob
> and the carried cargo (`carried_entries`); `DwarfMovement` follows paths, climbs
> ladders, drives the walk gait and keeps physical floor support (`snap_to_floor`,
> `lift_from_raised_floor`); `DwarfWorkExecution` (extending `DwarfCarryWork`) runs
> the job executors. `walk_to`/`walk_nearby` stay on the agent: they cancel
> leisure, meals and promotions, then hand the path to `DwarfMovement`.

## Overview

2026-10-09 Professions and Miner (doc 96)
implements Worker/Miner changes through the shared inspector's Profession action,
planned career previews and saved per-dwarf work permissions. Only Miner progression
is live: completed blocks grant experience at cumulative 10/100/500/2500 thresholds,
with up to 20% less digging time. Workers keep normal mining and basic crafting.
Level 6 and all other career bonuses below remain future design.

2026-10-09 follow-ups: Carpenter promotion now requires collecting and equipping
a crude carpentry kit. The shared Equipment tab shows the real kit, materials,
benefit and planned upgrades; completed specialist promotions play a chime.
Carpenter's workshop/recipes and upgraded-tool bonuses remain planned. The rules are
under Profession System below (docs 101 and 102).

2026-10-07 Worker crafting: current Workers can make the first crude workbench
beside collected timber, then craft torches at the installed stump from any open
side. They reuse physical pickup/carry/set-down, the two-handed axe pose and
contact-synchronized wood sounds. Partial recipe work belongs to the order;
interruptions return the unconsumed log. Inspection reports the actual crafting
destination. Miner progression followed in milestone 96 and Carpenter tool
promotion in milestone 101; specialist Carpenter production remains future work.

2026-10-23 compact dwarf panel ([23](../20_player_interface/23_user_interface.md#object-selection-implemented-2026-10-04)):
clicking a dwarf in the world opens the compact panel beside the dock. It shows the
portrait, the name, a mood badge (happiness beside its mood step's face, with the mood
and thoughts on hover), the profession on its tile, and the activity, with a concern icon
when one needs the player.
Its buttons are Follow (lit while following), Locate and Character sheet. Character
sheet opens the character sheet (Overview, Mood, Traits, Equipment, Profession; see
`23_user_interface.md`); closing it keeps the dwarf selected. Colony → Dwarves shows the dwarf on
its Details card instead, with the character sheet a click away, and each row shows the
dwarf's mood.

2026-10-05 inspection and roster: visible dwarves have a portrait, live work/rest
and cargo readouts in the shared inspector. **Colony → Dwarves** adds a stable
overview with name search, work/rest filters and Locate; selecting a row opens
that same inspector. Static portraits use existing visual parts and never create
simulation agents. Developer controls moved to Development.

2026-10-04 work tools: tree felling and mining have distinct two-handed procedural
swings and visible implicit axe/pick models. Both use shared grip and mirrored-part
reset handling; mining aims across its full existing vertical reach and underfoot.
Work poses stow on task transitions. Mining honors WorldClock pause/speed while
preserving authored hardness/durability work totals. Axe/pick contact crossings
trigger procedural positional sounds through `WorkFeedback`; mining also emits
small contact chips. Successful tree/block removal triggers completion dust from
the owning world system. Sounds follow camera focus/zoom; particles follow
simulation pause/speed. Dwarves implicitly carry both tools with no equipment
inventory or durability requirement.

Each dwarf is an autonomous agent (`DwarfAgent`, extends `CharacterBody3D`) driven by the Task System. Dwarves have physiological stats that degrade over time and must be replenished through colony resources.

## Movement and sleep — updated 2026-10-11

Walking now covers 3.4 blocks/second at normal speed (previously 2.2), with
1.05-block strides, eased foot lifts, planted stance, hand counter-swing and
gentle torso/head counter-motion. Movement honors clock speed; heavy carrying
and ladders retain their multipliers. The existing floating-part silhouette and
logical 1×1×3 navigation clearance are unchanged.

On a ladder a dwarf faces the wall and alternates hands and feet at the ladder's
`climb_speed_multiplier` (0.45 for the rough ladder), with the heavy-carry slowdown on
top; carried goods ride against its back so both hands hold the rungs
(`DwarfCarryPose.climb`). A dwarf interrupted on the rungs, falling asleep there or
loaded from a save there climbs down to a floor before it takes work or rests; the
inspector reads **Climbing down to safe ground** (roadmap 86).

`DwarfBedRest` first tries the dwarf's assigned bed, then free, unassigned beds
within 48 blocks, preferring a classified sleeping room. It claims one sleeper per bed and follows normal navigation
to a mattress-side access cell. Visual parts recline on the mattress while the
actor remains on that supported floor. Claims release on wake, removal, an
Uninstall or Move order, unusable support or actor teardown, and reconstruct from
the saved access floor on load without resetting the remaining sleep. Access cells
lie beside the mattress, never at its ends; each must be walkable floor off bridges
and ladders, with no other sleeper on it. The 48 blocks are `rest.bed_search_radius`
in `task_config.json`; the search tries one bed approach per tick to bound
pathfinding. Any installed piece with a `sleep_surface` is a bed; the log bed is the only one
today, as the Dwarven bed was retired (doc 234).

Without a usable bed, `DwarfRestBehavior` searches within eight blocks for reachable, level ground
beside a wall or unmarked tree. It checks the full resting footprint, excludes
stockpiles, furniture plans, bridges and ladder approaches, and keeps sleepers'
claims separate. Searches use short proven flat routes and a fixed candidate
budget per tick. Dwarves prefer either reclining or lazy sitting, try the other
pose when needed, then fall back to clear ground (compact sitting if boxed in).
Task cleanup and cargo release happen before searching; the six-hour sleep
clock begins after settling. Walking to shelter does not restore sleep.

Sleep uses eased settle/wake transitions, closed voxel eyelids, breathing and
slow head motion. The old emoji is removed. Three original quiet snores
(`tools/generate_snore_audio.py`) use Work audio, camera distance/zoom,
slice/visibility, pause and wake guards, at most two at once (`max_voices` in the
snore profile of `data/audio/work_feedback.json`). The ground search and poses use
`rest` in `task_config.json` (doc 119).
Spatial choices and claims are transient: saved sleepers rebuild a suitable
pose while retaining position and remaining rest. Lost floor support still
settles the real actor first, then reselects a spot without resetting the need.

**Bed ownership (doc 121).** Assign owner on a bed's compact panel (doc 23) gives it to
one colonist. Each colonist owns at most one bed, so choosing one who owns another moves
the assignment; unassigned beds are open to anyone, and no one else sleeps in an
assigned bed. Ownership is separate from the sleeper's claim: it survives waking, saves
on the bed, follows a Move and ends when the bed is uninstalled. Reassigning a bed
during sleep sends the affected sleepers to choose again without resetting their rest
(`BedAssignment`). A save naming a missing or duplicate owner is rejected. A completed
rest with at least three game hours asleep in one's personal bedroom gives +10
happiness for 24 game hours, refreshing without stacking; walking, settling, unassigned
beds and barracks earn nothing. Happiness starts at 50%. Qualifying sleep progress and
the thought's duration save and honor pause/speed (`mood.personal_bedroom` in
`task_config.json`).
Bed use came with doc 120; bedroom classification is in doc 34, and the
nearby-cover silhouette in doc 24.

## Idle activity — implemented 2026-10-09

After a short staggered pause, available dwarves stroll on nearby clear ground,
look around, or use an unoccupied installed seat (a log stool or bench; the wooden
chair was retired, doc 234). Their local anchor
stays at the last job/spawn position so successive walks do not become an
expedition. Leisure remains in the task scheduler's idle pool and yields to
work immediately. It does not restore sleep or create a mood/food requirement.
A dwarf with no flat stroll may take an adjacent one-block step up onto clear ground
(2026-10-12), so it can leave a shallow excavation. The inspector calls this
**Stepping up**.

Strolls stay on the anchor's level within `home_radius` and follow straight flat routes
with full dwarf clearance, rechecked while walking. Leisure never climbs a ladder or
roams to find a spot: a dwarf that finds no clear stop in `candidate_attempts` tries
steps up or waits. A stop avoids storage tiles, door cells, furniture plans, cells
beside installed furniture, ladders and their approach cells, and other dwarves and
their chosen stops (`spacing`). Each dwarf's timing comes from its own RNG, seeded from
the world seed and its id, so leisure takes nothing from generation or simulation RNG.
Leisure state, routes, timers and seat claims are never saved; a loaded dwarf starts
available where it stood.

`DwarfIdleBehavior` owns transient activity and uses TaskManager's `idle` tuning.
Chair claims are exclusive and transient; entry uses authored access cells and
the seated pose uses existing body parts, preserving 1×1×3 walking clearance.
Inspection labels the actual activity while the roster retains idle availability.
Completed seated meals also continue into this rest without standing and sitting
again. Dining transfers its exclusive seat claim; its table claim is released.
The empty hands relax smoothly, and work or needs can interrupt normally. The
hand-over (`DwarfDining.continue_seated()`) runs before the meal's cleanup: finishing
through the cancel path once freed the chair and stood the dwarf up for a frame (doc 203).
Read-only job planning preserves stationary idle timers and chair poses; actual
assignment still interrupts them. This prevents repeated unsuccessful checks
from restarting the wait before wandering indefinitely (doc 216). How long a
planning hold lasts, what renews it and why the chair is checked first are in
[31 — Task System](../30_simulation_systems/31_task_system.md#overview).

Seats are installed pieces whose `seating_chair` has a `rest_pose` (the log stool and
bench; never a board-game seat), checked one per frame within `seat_radius`.
`InstalledFurnitureComponent.idle_seat_owner` is the exclusive claim from the approach
until standing up, and `idle_seat_yaw_steps` the facing the sitter takes;
FurnitureSeating's clearance checks use that facing, so later furniture respects the
real head room. Both clear on every release and are never saved. The logical dwarf
stays on its proven access cell and `rest_pose` moves only its visual parts onto the
seat, so an interruption or a save never leaves a dwarf inside furniture. A seat with
`seating_chair.face_nearby_fire` (the stool) faces the nearest `seating_focus: "fire"`
piece on its level within `seat_focus_radius` when that seated pose fits and terrain
does not hide the flames: the body keeps a quarter turn, and the head turns toward an
off-axis fire. Otherwise the placed facing is used, if it fits. Work, walk commands,
sleep, abort, restore and teardown end the rest; so do the seat's removal, lost support
or access, and seated clearance newly blocked (rechecked with FurnitureSeating's
placement rules after navigation changes). Removing the fire only stops the head turn.
The activity reads Looking around, Strolling nearby, Stepping up, Leaving bedroom, Going
to sit, Sitting or Getting up (doc 99).

## Lost footing — fixed 2026-10-11

Every unpaused dwarf tick checks physical support before jobs, leisure and sleep.
When another miner removes the floor, the dwarf settles vertically onto the first
solid block or bridge deck below. This also repairs unsupported positions restored
from a current save and handles drops deeper than four blocks. It preserves XZ,
facing and sleep state, and refreshes slice visibility at the new height.
Since 2026-10-12, feet embedded in a raised floor also recover onto that block
when the full three-block standing space above is clear. This works for current
saved positions as well as live terrain edits and never searches through a roof.

Interrupted work follows the ordinary release protocol: clear the obsolete route,
release source, seating and tool reservations, drop carried goods at the landing,
and return awake dwarves to the available pool. The miner completing its own
underfoot block still settles immediately before pulling the next mining target.
Ladder rungs and supported step interpolation retain control of vertical movement.
This is immediate settling, not a gravity or fall-injury simulation. Settling never
makes an exit: an idle dwarf in a one-block hole climbs out by Stepping up (Idle
activity), but a deeper pit or a walled-in landing needs the player to dig a way out
(doc 115).

## Physiological Stats

All stats are floats in the range `0.0 – 1.0` unless otherwise noted.

| Stat | Drain Rate | Critical Threshold | Consequence |
|---|---|---|---|
| `food` (live, 131) | −0.075 / game hour | Hungry ≤ 0.40; Famished ≤ 0.15 | Seek a portion; +0.60 from fruit. Mood −5/−15; work speed −10%/−25%; no damage/death. |
| `thirst` | −0.008 / s | < 0.15 | Mood penalty; < 0.0 → death |
| `sleep` | −0.0007 / s | < 0.20 | Work speed ×0.6, pathfinding errors increase |

**Awake fatigue timing corrected 2026-10-12:** the sleep drain rate is per
simulation second. Awake fatigue now scales with WorldClock speed, so equal
game hours drain equal rest at ×1, ×2 and ×3, matching the existing six-game-hour
sleep duration. Pause and speed zero freeze the drain. The ×1 rate, per-dwarf
variation, sleep threshold and saved fields are unchanged. DwarfRestTest covers
equal-game-hour drain, pause/zero speed and the accelerated sleep interrupt.

> **Sleep drain retuned 2026-08-07** (was −0.003/s; first extended sleep-lite playtest).
> The old rate emptied full→threshold in ~4 in-game hours — a 4-hour waking day against a
> 6-hour nap, so dwarves slept 60% of the time and, with spawn-staggered schedules only
> ~2 minutes apart, the whole squad slept *simultaneously* for minutes in every session
> ("the dwarves are just stuck doing nothing"). −0.0007/s yields ~18 waking hours per
> 6-hour nap — the 24-hour cycle §Biological Limits specifies. `DwarfAgent` additionally
> jitters each dwarf's drain ±10% (deterministic per id) so schedules decohere over days
> rather than staying phase-locked. The original sleep billboard was replaced by
> ground poses, closed eyes, breathing and snoring on 2026-10-11 (see above).
> The former hunger rate of −0.005/s is superseded by the game-hour Food tuning
> (`food` in `task_config.json`; Biological Limits below; doc 131). Thirst and the other unimplemented needs below remain
> future design, including their provisional rates and consequences.
| `alcohol` | +varies on drink | > 0.80 | Mood bonus but pathfinding accuracy −30% |
| `mood` | ±event-driven | < 0.10 | Tantrum trigger; < 0.0 → berserk |
| `health` | injury-driven | < 0.10 | Forced bed rest |

### Biological Limits

- **Sustenance**: Initial tuning targets one portion every **8 game hours**.
  Food ≤ 0.40 starts a search; Famished is ≤ 0.15, not an automatic eight-hour
  death/critical deadline. Sleep also drains Food. Pause freezes both needs.
- **Rest profiles**: Dwarves require a minimum of **6 in-game hours** of sleep per 24-hour cycle. Sleep is taken autonomously at `sleep ≤ 0.25`, in a reachable bed when there is one and on sheltered ground otherwise (see Movement and sleep).
- **Alcohol levels**: Drinking one unit of ale raises `alcohol` by `+0.15`. Alcohol drains at `−0.02 / s`. Dwarves **will not** voluntarily drink above `0.80`.

### Need Resolution Priority

When multiple needs are critical simultaneously, dwarves resolve in this order:
1. Health (seek medic)
2. Thirst (find drink)
3. Hunger (find food)
4. Sleep (find bed)
5. Return to assigned tasks

## Visual Mesh Profile

| Measurement | Value | Notes |
|---|---|---|
| Visual mesh height | 3.3 blocks (1.65 m) | Includes helmet/hat |
| Logical grid footprint | 3 blocks tall (1.5 m) | Used for collision and pathfinding clearance |
| XZ footprint | 1 × 1 block | Single tile |

The **0.3 block visual overhang** above the logical footprint is purely cosmetic (head ornament, hat spike). It does not interact with collision or the navigation clearance envelope.

> **Agent note:** The navigation system (see `32_navigation_3d.md`) uses the **3-block logical height**, not the 3.3-block visual height. Never use the visual mesh AABB for pathfinding clearance calculations.

### Mesh Anatomy — Hearthblock Chibi Silhouette

Dwarf character meshes use the **Hearthblock chibi silhouette** ([64](../60_asset_creation/64_hearthblock_art_direction.md)): a big square head, a compact flared tunic, chunky mittens and square boots. The anatomy is deliberately simple, which keeps authoring fast and consistent across the whole roster.

A dwarf mesh is composed of exactly **four parts**:

| Part | Description | Notes |
|---|---|---|
| **Head** | Oversized relative to the body — the dominant visual element | Carries the face, hair, beard, and all headwear (helmets, hats) |
| **Body** | Compact torso block below the head | Carries chest armour, clothing, and profession colour/markings |
| **Hands** | Two small floating blocks at body-side height | Float at the sides of the body with no connecting arm geometry |
| **Feet** | Two small floating blocks below the body | Float below the body with no connecting leg geometry |

**Dwarves have no arms and no legs.** The hands and feet are detached, floating parts — connected to the body only by animation transforms, not by any mesh geometry. This is intentional and must be preserved:

- It keeps authoring simple. Each dwarf is a few small cell-built parts (`tools/hearthblock/art/dwarves.mjs`) rather than a complex articulated rig.
- The charm comes from the contrast between the big expressive head and the small, bobbing mittens and boots.
- Hands and feet bob and swing via simple procedural animation offsets. No skeletal rig or IK solver is needed — transform offsets on the four part nodes are sufficient.

```
Visual layout (front view, approximate):

     ┌──────────┐
     │          │   ← Head (large)
     │          │
     └──────────┘
        ┌────┐
   □    │    │   □  ← Hands (floating, no arms)
        │Body│
        └────┘
        □    □      ← Feet (floating, no legs)
```

### Part Hierarchy in Godot

Each dwarf scene is structured as four sibling `MeshInstance3D` nodes under the root `DwarfAgent`. Animation is driven by setting `position` and `rotation` offsets on these nodes each frame — no `AnimationPlayer` or skeleton is required.

```
DwarfAgent (CharacterBody3D)
  ├─ MeshHead   (MeshInstance3D)  ← .glb built by tools/voxel_assets
  ├─ MeshBody   (MeshInstance3D)
  ├─ MeshHandL  (MeshInstance3D)
  ├─ MeshHandR  (MeshInstance3D)
  ├─ MeshFootL  (MeshInstance3D)
  └─ MeshFootR  (MeshInstance3D)
```

Equipment meshes (helmets, chest armour, boots, weapons) are **child nodes** of the relevant part — a helmet is a child of `MeshHead`, chest armour a child of `MeshBody`, and so on. Equipping or unequipping gear is simply adding or removing those child nodes.

> **Agent note:** Never merge dwarf part meshes into a single combined mesh. The four-part separation is required for equipment attachment and procedural animation. Keep each part as an independently addressable `MeshInstance3D`.

## Agent State Machine

**2026-10-05 hauling animation:** stockpile hauling and furniture fetches now
stand beside an item, turn toward it, acquire it at fist contact, lift it, carry it with both
floating fists, and lower/release it in front of their planted feet at delivery. Item bounds drive the grip;
loads form a compact two-column bundle at native scale. The JSON carry budget is
4 points: rock/ore costs 1, raw timber 2, and produce/packed furniture crates 4.
Mixed loads share that budget; crate cost is independent of fill, while
`weight_class` separately controls walking speed. Pickup and
deposit take 0.75 s and 0.65 s at normal clock speed (task JSON tunables).
Reservations, carried-item saves and interruption drops remain authoritative;
animation state is transient.

The handling stand is a walkable cardinal cell beside the goods. The reserved
item cell, and every reserved destination cell of a bundle, is never used as the
stand. Stands are tried nearest first; if the nearest side cannot be reached, the
dwarf tries another side (`DwarfCarryWork._walk_to_handling_stand`). The item is
taken from its source exactly once, at hand contact (`DwarfCarryPose.CONTACT_PHASE`,
36% of the pickup); storage or construction consumes it only after it has been
lowered. An item without `carry_cost` costs 1, and costs and the configured capacity
are clamped to at least 1 (`StorageComponent`, `StockpileManager`), so an item
costing more than the budget is never offered and never posts an impossible lease.

Placing finished furniture is the 0.65 s set-down itself (doc 123). The worker
starts lowering the packed piece as soon as it reaches its stand outside the
footprint, turned toward the nearest footprint cell (a wall light: the front of its
mount, at its height; a fence post: its corner), and the piece is installed as the
set-down ends, with no separate build timer (`FurnitureGhostComponent.placement_contact`).
Only that final commit, after the site is checked again, consumes the carried item.
Pause and speed act on the pose and the commit together, and cancellation,
interruption or lost support returns the item intact. Sources with work of their own
(`remaining_work()`: bridges, ladders, crafting, planting, construction) run their
own timed work instead (`DwarfCarryWork._begin_fetch_work`).

```
IDLE
MOVING_TO_TASK   ← following A* path
EXECUTING_TASK   ← performing work animation at target block
NEEDS_INTERRUPT  ← hunger/thirst/sleep exceeded critical → drops task, resolves need
SLEEPING
EATING
DRINKING
TANTRUM          ← mood < 0.10, random destructive behaviour
DEAD
```

## Mood Events (Thought System)

The broader table below remains design material. The live thoughts
(`DwarfMood.thoughts()`), in happiness points:

| Thought | Points | Lasts |
|---|---|---|
| A board game with a friend / on one's own | +8 / +4 | 12 game hours |
| Hungry / Famished | −5 / −15 | until fed |
| Ate without a table, or standing up / without a proper place | −3 / −8 | 8 game hours |
| Slept in one's own bedroom | +10 | 24 game hours |
| Slept in the cold / chilly / in the heat | −20 / −5 / −15 | 24 game hours |
| Slept, ate or played in a horrid / pleasant / beautiful room | −6 / +4 / +8 | 24 / 8 / 12 game hours |

- Only the stronger board-game thought, and the strongest sleeping-temperature thought,
  count.
- **Room thoughts (2026-10-25):**
  - A full sleep, a meal or a board game in a sealed room leaves the room's appeal word
    (doc 23 "Room appeal").
  - A plain room, or no room, leaves none and ends the last memory of that activity. The
    next sleep, meal or game replaces it, so a dwarf holds at most one of each.
  - The points belong to the words in `data/rooms/appeal.json`; the hours are `room_appeal`
    in the mood section of `task_config.json`.
  - DwarfAgent passes the bed's room to `finish_sleep()`. DwarfFoodBehavior and
    BoardGameRecreation call `record_room()` at the end of a meal or an earned game.
  - The memories save with the mood as `slept_room`, `ate_room` and `played_room` (the
    word in lower case, or "") and their hours, with the taste each names. A save naming a
    word appeal.json lacks is rejected.
  - The word is the room as the dwarf feels it: their found tastes move it, and the
    thought names the strongest ("Tastes", below).
- Each thought carries a stable id: `recreation_together`, `recreation_alone`, `hungry`,
  `famished`, `dining_seat_only`, `dining_table_only`, `dining_neither`, `bedroom`, `cold`,
  `chilly` and `hot`, and for rooms the activity and the word (`slept_beautiful`,
  `ate_horrid`, `played_pleasant`…). The colony's journal (`ColonyJournal`, doc 23) keys its
  lines by it and notes a thought when it begins, or when its memory comes again.
- Happiness is the 50 baseline plus the thoughts, from 0 to 100.
- **Five words name it.** These are the `steps` in the `mood` section of
  `task_config.json`:

  | Step | Happiness |
  |---|---|
  | Miserable | up to 25 |
  | Unhappy | up to 40 |
  | Content | up to 54 |
  | Happy | up to 64 |
  | Joyful | above 64 |

- **When Unhappy or Miserable,** the face shows over the dwarf's head
  (`DwarfMood.unhappy()`), naming the strongest bad thought.
- The character sheet's Mood tab shows each thought with its hours left.
- Mood has no tantrum or work-speed side effects.

`mood` does not drain over time — it is the running sum of all active thought effects. Each thought has a **magnitude** (positive or negative delta applied instantly) and a **duration** after which the effect expires and mood recalculates.

```gdscript
class_name Thought extends RefCounted
var id:         String   # namespaced thought key, e.g. "base:thought:ate_fine_meal"
var magnitude:  float    # mood delta; positive = happy, negative = unhappy
var expires_at: float    # Time.get_ticks_msec() + duration_ms; 0 = permanent until cleared
```

`DwarfAgent.mood` is recomputed each time a thought is added or expires:
```gdscript
mood = clamp(thoughts.reduce(func(acc, t): return acc + t.magnitude, 0.0), 0.0, 1.0)
```

### Thought Table

| Thought ID                       | Trigger                                                          | Magnitude | Duration     |
| -------------------------------- | ---------------------------------------------------------------- | --------- | ------------ |
| `base:thought:ate_fine_meal`     | Ate a meal (food stockpile ≥ 2 types)                            | +0.08     | 8 h          |
| `base:thought:ate_plain_meal`    | Ate a meal (only 1 food type available)                          | +0.03     | 6 h          |
| `base:thought:drank_ale`         | Consumed one unit of ale                                         | +0.06     | 4 h          |
| `base:thought:drank_stout`       | Consumed one unit of dark stout                                  | +0.08     | 5 h          |
| `base:thought:drank_mead`        | Consumed one unit of mead                                        | +0.10     | 6 h          |
| `base:thought:drank_cider`       | Consumed one unit of mountain cider                              | +0.07     | 4 h          |
| `base:thought:drank_wine`        | Consumed one unit of grape wine                                  | +0.09     | 5 h          |
| `base:thought:drank_gin`         | Consumed one unit of juniper gin                                 | +0.08     | 4 h          |
| `base:thought:drank_aged_stout`  | Consumed one unit of aged dark stout                             | +0.13     | 8 h          |
| `base:thought:drank_vintage_wine`| Consumed one unit of vintage wine                                | +0.16     | 10 h         |
| `base:thought:drank_reserve_gin` | Consumed one unit of reserve gin                                 | +0.14     | 8 h          |
| `base:thought:slept_in_bed`      | Completed sleep cycle in a claimed bed                           | +0.06     | 12 h         |
| `base:thought:slept_on_floor`    | Completed sleep cycle without a bed                              | −0.05     | 16 h         |
| `base:thought:no_drink`          | Thirst hit critical (< 0.15)                                     | −0.08     | 4 h          |
| `base:thought:no_food`           | Hunger hit critical (< 0.15)                                     | −0.10     | 4 h          |
| `base:thought:saw_corpse`        | Walked within 3 tiles of a dead dwarf                            | −0.12     | 24 h         |
| `base:thought:injured`           | Health dropped below 0.50                                        | −0.08     | Until healed |
| `base:thought:tantrum_recovered` | Mood recovered above 0.30 after tantrum                          | +0.05     | 8 h          |
| `base:thought:completed_project` | Finished a BUILD task on a structure                             | +0.07     | 12 h         |
| `base:thought:warm_tavern`       | Idle within 5 tiles of a lit brewery                             | +0.04     | 2 h          |
| `base:thought:cave_in_nearby`    | A collapse event within 10 tiles                                 | −0.15     | 6 h          |
| `base:thought:legendary_gem`     | Walked within 5 tiles of a ruby/sapphire stockpile with ≥ 5 gems | +0.06     | 8 h          |

### Stacking Rules

- Multiple instances of the same thought **do not stack** — the most recent replaces the previous and resets the timer.
- Positive and negative thoughts coexist and sum freely.
- If `mood` would exceed `1.0`, it is clamped at `1.0`. If it would drop below `0.0`, the TANTRUM state is triggered.

## Dwarf Generation

Every dwarf is procedurally generated at creation time from three component pool files. The same world seed always produces the same sequence of dwarves in the same order, so saves are deterministic.

### Component Files

| File | Contents |
|---|---|
| `data/entities/dwarves/names.json` | Male and female prefix/suffix pools — 500 distinct names per gender |
| `data/entities/dwarves/appearance.json` | Shared and gender-specific visual component pools (skin, hair, eyes, etc.) |
| `data/entities/dwarves/traits.json` | Trait definitions, rarity weights, generation_config distribution, exclusion groups |

### Name Generation

A dwarf's name is a single word assembled as `prefix + suffix`. Each gender has 25 prefixes and 20 suffixes, giving 500 distinct names per gender. The generator tracks assigned names for the current world and re-rolls up to 10 times on collision before appending a Roman numeral birth-order index (e.g. `Bromin II`). This fallback requires generating ~500 same-gender dwarves and is not expected in normal play.

### Appearance Generation

Appearance components are selected by weighted random roll. All dwarves receive: `skin_tone`, `eye_color`, `hair_color`, `age_tier`, and an optional `scar` overlay. Males additionally receive `hair_style`, `beard` (85% probability; style selected from 7 options if present), and `eyebrow_style`. Females receive `hair_style` (10 options) and `eyebrow_style`. No beards on female dwarves.

All dwarves share the same logical height (**3 blocks / 1.5 m**) for collision and pathfinding. The visual mesh stands **3.3 blocks tall** (cosmetic overhang for headwear — does not affect clearance; see Visual Mesh Profile below).

Two visual representations are maintained per dwarf:

- **Map mesh** — the in-world character model. Only broad features render at game scale: skin tone, hair colour, and hair/beard silhouette.
- **Portrait** — a static copy of the actual head/body visual parts in the Colony
  roster and dwarf inspector. Portraits do not register or animate another agent.

### Trait Assignment

**Runtime status (2026-10-05):** generation, storage and inspection of trait IDs
are implemented; applying their `effects` is not. The inspector's Details tab
shows names/descriptions from DwarfAssets with an explicit inactive-effects note.
Light Sleeper is authored as +1 sleep hour (seven instead of six), and Deep
Sleeper as −1 (five instead of six), but all dwarves currently use the same
six-hour sleep-lite duration. The descriptions below and in JSON must not be
treated as evidence of active modifiers.

#### Planned trait effects (not implemented)

`traits.json` holds only what generation and the inspector use (name, description,
polarity, rarity weight, exclusion group). The effects below are design only.

| Trait | Planned effect |
|---|---|
| Born Miner, Brewmaster's Intuition, Green Thumb, Architect's Eye, Merchant's Tongue, Warm Host, Born Hauler | ×1.5 experience gain in Miner, Brewer, Farmer, Builder, Merchant, Innkeeper or Worker respectively, and unlock level 6 in that profession |
| Loves to Cook | Reserves a future Cook profession for this dwarf |
| Cheerful / Grumpy | Mood baseline +0.06 / −0.05 |
| Hardworking / Lazy | All task durations ×0.90 / ×1.12 |
| Iron Constitution / Frail | Incoming damage ×0.70 / ×1.45 |
| Deep Sleeper / Light Sleeper | −1 / +1 hour of sleep per cycle |
| Iron Stomach | Ignores food-variety thoughts |
| Brave | Ignores the invader flee trigger |
| Fearful | Flees invaders within 15 tiles |
| Hates the Outdoors | −0.05 mood during outdoor tasks (planting, tending, harvesting, beehives, honey, hauling, clearing rubble) |
| Cave Sick | −0.05 mood inside a sealed room with no sky |
| Glutton | Hunger drains ×1.5 |
| Alcohol Dependent | Must drink every 16 h; each missed window adds −0.06 mood, up to 4 stacks (−0.24). Alcohol thoughts are ×1.5 stronger |
| Loner | −0.04 mood with 4+ dwarves within 5 tiles |
| Social | +0.03 mood with 3+ dwarves within 5 tiles |
| Homesick | −0.08 mood on arrival, fading linearly over 56 days (two seasons) |

The generator rolls a **trait slot distribution** from `generation_config` in `traits.json`, then fills each slot from the positive or negative pool independently:

| Slot distribution | Weight | Notes |
|---|---|---|
| No traits | 35 | Most common — plain dwarves |
| One negative | 30 | Slight majority carry a flaw |
| One positive | 20 | — |
| One positive, one negative | 10 | — |
| Two positive | 4 | Valuable and uncommon |
| Two positive, one negative | 1 | Rarest; sought-after workers |

Traits in the same **exclusion group** (e.g. `mood_baseline`, `work_pace`) cannot be assigned to the same dwarf. The generator checks exclusions before finalising each slot. If a rolled trait conflicts, it re-rolls from the remaining eligible pool rather than skipping the slot.

### Tastes

Personal tastes (2026-10-25; `DwarfTastes`, `data/entities/dwarves/tastes.json`, read by
DwarfAssets). The owner chose furniture and woods the dwarves use over adding foods and
plants, or two broad leanings known from the start (2026-10-25).
- **What they name:** furniture designs a dwarf uses (log bed, log stool, bench, log
  table, board-game table) and woods (pine, oak, juniper, applewood), each with the picture
  its tile shows.
- **Given at birth, kept for life:** one love, two likes and one dislike (`counts`). They
  are dealt by DwarfFactory from the dwarf's own seed, after every other roll, so the
  same world gives each dwarf the same tastes.
- **Found by using:** a taste is "?" until the dwarf meets the thing:
  - the bed, after a full night in it (DwarfAgent, before the room's thought);
  - the seat and table of a meal (`DwarfDining.used_pieces()`);
  - the board and seat of an earned board game (BoardGameRecreation);
  - and the wood of any of those.

  `DwarfAgent.meet_pieces()` marks them found. The journal tells each found taste that day
  (`ColonyJournal.note_taste`): "Found a taste: loves the log bed", a praise for a love or a
  like and a complaint for a dislike, in lines from `found_love`, `found_like` and
  `found_dislike` (`{thing}` is its name).
- **What a found taste does:** in a room holding the thing (a design, or any piece of the
  wood) it moves the appeal that dwarf feels: a love +4, a like +2, a dislike −4 (`felt`),
  once a thing. The room's thought takes the word as the dwarf feels it and names the
  strongest taste ("Slept in a pleasant room · loves the log bed"). A taste not yet found
  does nothing, so the sheet never tells one early.
- **Saved** with the dwarf as `tastes` (thing id → love, like or dislike) and
  `found_tastes`. Each room memory saves the taste it names (`slept_room_taste`…). A save
  whose tastes name a thing the game lacks, use another word, mark one found that is not
  held, or name a room taste not found, is rejected.
  - A dwarf's tastes, like its mood and food, are made in `setup()`. A test that saves a
    dwarf builds it with `DwarfFactory.spawn`, as the game does; a bare `DwarfAgent.new()`
    has nothing to save them from (`ProduceCrateTest`, 2026-10-26).

---

## Profession System

Every dwarf has exactly **one active profession** at a time. All dwarves start as `base:profession:worker`. Change profession (on the character sheet's Profession tab or Colony Dwarves' Details card) opens the career map. Worker and Miner are assignable immediately; Carpenter requires physical collection of a crude carpentry kit. Other careers are planned previews. Switching professions never resets accumulated experience. Miner experience counts successfully removed blocks, not zone leases. Per-dwarf work permissions are independent of the active profession.

The live rules (doc 96):
- **Who can be assigned.** Only professions with `promotion_enabled`, from the career map
  or through `DwarfAgent.change_profession`; a starter tool in stock never enables a
  planned career.
- **Changing** releases the current job through the normal release (goods set down,
  claims freed, source progress kept). A sleeping dwarf takes the new role without
  rejoining the idle pool early.
- **Work permissions** (`work_permissions` in professions.json: Haul, Gather, Mine, Build
  and Craft, each listing its task types) are saved per dwarf and kept across careers; a
  category with no entry is allowed. Unticking one releases a current job of that kind.
  Carrying supplies for an allowed job is not Haul, and rest is automatic. Craft applies
  only while a Worker (`TaskScheduler.types_for`), so a Miner's Craft setting returns
  with the Worker role.
- **Miner experience** is one per block the Miner removes, awarded before that commit can
  end the zone lease, so a zone's last block counts. Partial swings, cancelled blocks,
  walking, hauling and Worker mining earn none.

`data/professions/professions.json` holds what the game uses: the career-map
entries, work permissions, Miner experience thresholds, display names, promotion
parents, required tools and equipment previews. Each profession also names its one
Hearthblock icon (`icon`, doc 259). The career map, the equipment view and the
Crafters menu all show it. The planned design for every
profession is recorded below.

#### Planned profession design (not implemented)

Every profession promotes from Worker unless noted. Specialists fall back to
Worker tasks (`HAUL`, `CLEAR_RUBBLE`) when they have no primary work; fallback
speed is unaffected by experience. Work-speed bonus is per level above 1 on the
profession's primary tasks (5% unless noted), so level 5 is 20% faster and level 6
25% faster.

| Profession | Primary tasks | Room | Notes |
|---|---|---|---|
| Worker | `HAUL`, `CLEAR_RUBBLE`, `COLLECT_FLOOR_ITEMS`, `CRAFT` | — | Base profession; cannot be removed. Planned: haul speed improves with level |
| Miner (live) | `MINE`, `CLEAR_RUBBLE`, `HAUL_ORE` | — | Live: digging speed. Planned: level 3 spots ore before it is fully exposed; level 6 small chance of bonus ore or gem fragments |
| Farmer | `PLANT_SEED`, `TEND_FARM`, `HARVEST_CROP`, `TEND_BEEHIVE`, `COLLECT_HONEY` | — | Yields improve at levels 2 and 4; level 6 occasional double harvests |
| Brewer | `BREW`, `LOAD_AGING_CELLAR`, `COLLECT_AGING_CELLAR`, `WEAVE_CLOTH` | — | Not on the career map. Level gates recipes (see Recipe Gates); level 6 gives a 10% chance of a bonus output unit |
| Builder | `BUILD_BLOCK`, `DEMOLISH_BLOCK`, `PLACE_FURNITURE`, `REMOVE_FURNITURE` | — | Not on the career map. Level 6 gives buildings a small structural-integrity bonus |
| Merchant | `STAFF_TRADE_COUNTER`, `COLLECT_SHOP_COINS`, `RESTOCK_SHOP_STORAGE` | Shop | Not on the career map. +2% sale price per level instead of speed; see `51_visitors.md` |
| Innkeeper | `SERVE_DRINK`, `SEAT_GUEST`, `COLLECT_NIGHT_STAND_COINS`, `RESTOCK_TAVERN_STORAGE` | Tavern | Not on the career map. +1 coin lodging fee per level; see `51_visitors.md` |
| Carpenter | Planned workshop recipes | — | Live: promotion with a carpentry kit |
| Blacksmith | Smelting and forging (doc 44) | — | Needs a Smelter and Forge |
| Weaponsmith, Armorsmith | Forge weapons / armour (doc 44) | — | Promote from Blacksmith level 3 |
| Hunter, Stonemason | Not designed beyond the career-map preview | — | The owner's names, not Trapper or Stonesmith (2026-10-09) |

Level 6 needs both 10,000 tasks and the profession's calling trait (see Planned
trait effects).

### Agreed equipment progression — planned (2026-10-09)

**Live follow-up (doc 101):** Carpenter's kit requirement (`required_tool`), physical
collection, cancellation, equipped-item ownership, inspector/inventory presentation and
current saves are implemented. Miner keeps its implicit pickaxe and promotes at once.
Carpenter workshop gameplay and all equipment bonuses/upgrades remain planned. The live
rules:
- **A personal appointment.** `DwarfEquipment` holds one pending appointment and one
  equipped item per dwarf; no other dwarf can take it as a job. Choosing a tool career
  releases the current job and takes the dwarf out of the idle pool (TaskManager ignores
  its idle notices, `TaskScheduler.types_for` offers it nothing, `receive_task` bounces a
  late lease). The old profession stays until the pickup ends. A sleeping dwarf, or one
  still leaving a ladder, cannot begin.
- **Finding the kit.** Read-only loose and storage quotes and a bounded reachability check
  pick the nearest reachable kit; an unreachable one is excluded and the next tried. Only
  that exact item is reserved or withdrawn, so another appointment or a hauler cannot
  take it.
- **Pickup** uses the ordinary carry pose. At hand contact the kit leaves ItemDropManager
  as cargo; when the motion ends the same node becomes a hidden equipped child of the
  dwarf and is no longer cargo.
- **Cancelling.** Cancel promotion, a walk command, sleep, a lost reservation, a
  disallowed kit or a changed route ends the appointment: an unlifted kit is unreserved,
  a lifted one drops intact at the dwarf's feet. Sleep never removes an equipped tool.
- **Leaving the profession** drops the kit at the dwarf's feet as available goods;
  experience is kept.
- **Inventory** counts an equipped tool in the total and as reserved, never available, so
  a Keep in stock order still makes a spare; Locate goes to its dwarf.
- **Saves.** The dwarf's `equipment` holds `tool`, its `material_id` and any
  `pending_role`. Loose and reserved kits stay ItemDropManager's, and a lifted kit is
  ordinary carried cargo that a load sets down; a pending appointment searches again
  after the load.
- **Feedback.** Only a completed change to a profession other than Worker plays the
  promotion chime (doc 13, WorkFeedback) and posts colony news. Requests, cancellation,
  returning to Worker and loading are silent.

The Equipment view (doc 102; the character sheet's Equipment tab, doc 23) shows the
owned tool's picture, tier, materials and actual benefit. Iron saw/pickaxe are explicit
planned previews; no upgrade goods or bonuses exist yet.

The player approved three connected forms of progression:

- **Promotion** selects a profession. Selected careers will require an available
  starting tool. Milestone 97 adds craftable stone hoes, hunting spears, carpentry
  kits and stone hammers for Farmer, Hunter, Carpenter and Blacksmith. Carpenter's
  requirement and physical equipping are live; other tool careers remain planned.
  Carpenter starts with a
  mallet/adze kit; its saw is a later upgrade. The dependency review is recorded in
  [44 — Carpenter entry tools](44_crafting_workshops.md#carpenter-entry-tools--dependency-review-2026-10-09).
- **Experience** improves the dwarf through practice. Existing Miner levels and
  digging-time bonuses remain independent of equipment.
- **Equipment** provides crafted upgrades with visible tools and meaningful
  benefits. Leveling up does not create a free upgraded tool or weapon.

Miner promotion remains free, with no crafted-tool or level requirement. The
existing implicit pickaxe is sufficient to begin mining and stays the baseline.
Carpenter already owns a physical kit; the **iron pickaxe is
the first planned equipment upgrade**, followed by steel or another advanced metal.
Mining benefits and limits are specified in
[43 — Pickaxe upgrades](43_mining_materials.md#pickaxe-upgrades--planned-2026-10-09).

The promotion screen shows the required starter tool, its availability and maker.
The dwarf inspector shows equipped tool, materials and actual benefit. Automatic
upgrades and manual allocation of scarce upgraded tools remain planned.
Equipment must represent owned goods, with one item assigned to one dwarf;
switching professions must preserve experience and account for the physical item.

Workers must have a route to craft the crude tools needed to establish the first
specialists, without a profession requiring its own exclusive product to start.
Tool durability and repairs are deferred beyond the first equipment version.
These are agreed requirements; beyond Carpenter's kit, tool gates and all tool upgrades
are not implemented. The four starter tools (doc 97) are ordinary goods (doc 44) and
grant no bonus; the career map shows each tool's stock and maker.

### Agent Fields

```gdscript
var profession: String = "base:profession:worker"   # current active profession key

var profession_experience: Dictionary = {           # raw task counts per profession key
    "base:profession:worker":      randi_range(0, 9),
    "base:profession:miner":       0,
    # ...one entry, starting at 0, for every profession in professions.json
    "base:profession:weaponsmith": 0,   # set to blacksmith count at specialisation
    "base:profession:armorsmith":  0,   # set to blacksmith count at specialisation
}
```

Workers are initialised with a small random task count (0–9) so new arrivals aren't all identical level-1 dwarves. All specialist professions start at 0 until the dwarf actually practices them.

### Specialisation Professions

`base:profession:weaponsmith` and `base:profession:armorsmith` are restricted professions — they cannot be assigned directly from the Labour window. A dwarf must first reach **Blacksmith Level 3** (100 cumulative tasks) before the specialisation options appear. On promotion, the target profession's experience entry is set to equal the current Blacksmith count. Full rules: `44_crafting_workshops.md`.

### Experience Level Derivation

Experience level is derived at runtime from the raw task count. Do not store the level — store only the count.

```gdscript
func get_experience_level(profession_key: String) -> int:
    var tasks := profession_experience.get(profession_key, 0)
    if tasks >= 10000: return 6   # also requires trait — check separately
    if tasks >= 2500:  return 5
    if tasks >= 500:   return 4
    if tasks >= 100:   return 3
    if tasks >= 10:    return 2
    return 1
```

### Experience Thresholds

| Level | Tasks Required (this level) | Cumulative Tasks |
|---|---|---|
| 1 | — (starting level) | 0 |
| 2 | 10 | 10 |
| 3 | 90 | 100 |
| 4 | 400 | 500 |
| 5 | 2,000 | 2,500 |
| 6 (planned) | 7,500 | 10,000 |

Level 6 remains planned and cannot be reached in the current Miner implementation.

### Work Speed Bonus

Miner's `work_speed_bonus_per_level` lives in professions.json; other professions use the planned 5% (see the planned profession table). The formula for primary task duration:

```
task_duration × (1.0 - (experience_level - 1) × work_speed_bonus_per_level)
```

At `work_speed_bonus_per_level: 0.05`, level 5 mining takes 20% less work time than level 1. The live bonus applies only to mining while the dwarf is a Miner. Fallback work and Workers keep normal speed; Worker progression and level 6 remain planned.

### Recipe Gates (Brewer)

The planned recipes' Min Skill (`42_farming_brewing.md`) is a Brewer experience level. A Brewer at level N can perform any recipe with Min Skill ≤ N: level 1 brews Longbeard Ale, Mountain Cider and Pig Tail Cloth; level 2 adds Dark Stout and Sweet Mead; level 3 Grape Wine and Aged Dark Stout; level 4 Juniper Gin and Reserve Gin; level 5 Vintage Wine.

---

*Prev: [33_water_simulation.md](../30_simulation_systems/33_water_simulation.md) | Next: [42_farming_brewing.md](./42_farming_brewing.md)*
