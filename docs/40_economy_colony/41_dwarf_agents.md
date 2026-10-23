# 41 — Dwarf Agents

**2026-10-19 — Dining while famished:** [250](../00_dev_roadmap/250_famished_dining_range.md)
retains the normal 16-block dining range after a dwarf collects food, including
when famished. The two-second bounded search and existing route/seat claims
remain. The former six-block exception skipped Birna's nearby free dining stool
in the player save. Stored food, emergency foraging and need thresholds retain
their existing priorities.

**2026-10-19 — Solo and shared recreation:** [249](../00_dev_roadmap/249_solo_games_and_partner_search.md)
lets a dwarf play immediately at one game stool for +4 happiness after a full
game. A partner can join; both must play a fresh full game for +8 each. The
thoughts last 12 game hours and contribute only the stronger bonus. An occupied
table searches up to 48 routed blocks for a companion under the existing bounded
probe budget. The six-hour cooldown and needs/work/privacy rules still apply.
Separate optional solo memory persists without changing old social memories.

**2026-10-17 — Moving between slices:** Dwarves refresh slice visibility on
global transform changes, before rendering. Ordinary stairs/ladder travel now
shows a worker entering the selected level and conceals one leaving it, without
another slice-button click. Paused restoration also refreshes. This corrects
invisible downstairs torch work in the player's save; navigation and wall reach
are unchanged. See [217](../00_dev_roadmap/217_dwarf_slice_visibility.md).

**2026-10-17 — Visible needs:** [214](../00_dev_roadmap/214_dwarf_need_indicators.md)
adds overhead food, exhaustion and unhappy-face badges for serious or unresolved
needs. `DwarfConcern` supplies one read-only reason/action to both the projected
2D display and shared inspector. Normal food/rest/mood simulation and save fields
are unchanged; low happiness names the strongest active negative thought.

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
access returns to planning. Supervision tracks each block as a separate work unit.
`DwarfWorkExecution` applies the existing labor-speed factor to three seconds per
voxel. Carry capacity and item carry costs are unchanged. See
[205](../00_dev_roadmap/205_construction_materials_crates.md).

**2026-10-14 — Colony size:** The intended maximum is **30 dwarves**.
Use 5/20/30 as the routine performance cases and test mature-colony work and
needs at 30. Larger development populations are stress tests. This is design
direction; runtime population enforcement has not been added. See
[11 — Overview](../10_core_foundation/11_overview.md) and
[187 — Scaling measurements](../00_dev_roadmap/187_colony_scaling_performance.md).

**Proportions:** `DwarfAssets` owns `data/entities/dwarves/proportions.json`. Body and
head widths are 1 because the Hearthblock parts carry their own shape; the file sets
the relaxed hand and foot stance. Standing height and the logical 1×1×3 body stay
fixed. Assembly, work/rest resets and static portraits use those values. Tool/carry
grips and appearance IDs remain current; existing saves receive the new shape.

**2026-10-12 — Food and dining:** [131 — Food and dining](../00_dev_roadmap/131_dwarf_food_and_dining.md)
implements stages 1 and 2 of the agreed plan: game-hour Food, physical fruit
portions from reachable storage before allowed loose food, bounded retries,
safe work interruption and current saves. Famished dwarves can pick a nearby
ripe bush only after harvested food fails. Diners prefer seat/table, seat alone,
table alone, then neither; penalties are 0/−3/−3/−8 for up to eight game hours.
Hungry/famished dwarves lose 5/15 happiness and work 10%/25% slower. No damage or
death. Serving art, last-meal details and shortage warnings are live; stage 3's
character-screen reorganization remains planned.
Fresh fruit is the first edible content; future meals/meats use the same metadata.

**2026-10-11 — Privacy and thermal sleep comfort:** Idle visitors leave bedrooms;
owners may relax in their own, and unassigned bedrooms are for sleep. Work access
remains open. Cold/chilly/hot sleep creates a −20/−5/−15 happiness thought after
one actual game hour asleep; strongest thermal penalty only, lasting 24 hours.
See [122](../00_dev_roadmap/122_bedroom_comfort_and_mining_progression.md).

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

2026-10-09 [96 — Professions and Miner](../00_dev_roadmap/96_professions_and_miner.md)
implements Worker/Miner changes through the shared inspector's Profession action,
planned career previews and saved per-dwarf work permissions. Only Miner progression
is live: completed blocks grant experience at cumulative 10/100/500/2500 thresholds,
with up to 20% less digging time. Workers keep normal mining and basic crafting.
Level 6 and all other career bonuses below remain future design.

2026-10-09 follow-ups: Carpenter promotion now requires collecting and equipping
a crude carpentry kit. The shared Equipment tab shows the real kit, materials,
benefit and planned upgrades; completed specialist promotions play a chime.
Carpenter's workshop/recipes and upgraded-tool bonuses remain planned. See
[101 — Tool promotion](../00_dev_roadmap/101_tool_based_promotion.md) and
[102 — Equipment feedback](../00_dev_roadmap/102_equipment_view_promotion_feedback.md).

2026-10-07 Worker crafting: current Workers can make the first crude workbench
beside collected timber, then craft torches at the installed stump from any open
side. They reuse physical pickup/carry/set-down, the two-handed axe pose and
contact-synchronized wood sounds. Partial recipe work belongs to the order;
interruptions return the unconsumed log. Inspection reports the actual crafting
destination. Miner progression followed in milestone 96 and Carpenter tool
promotion in milestone 101; specialist Carpenter production remains future work.

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

`DwarfBedRest` first tries the dwarf's assigned bed, then free, unassigned beds
within 48 blocks, preferring a classified sleeping room. It claims one sleeper per bed and follows normal navigation
to a mattress-side access cell. Visual parts recline on the mattress while the
actor remains on that supported floor. Claims release on wake, removal, unusable
support or actor teardown, and reconstruct from the saved access floor on load.
Both the new Worker-crafted Log bed and existing Dwarven Bed support sleep.

Without a usable bed, `DwarfRestBehavior` searches within eight blocks for reachable, level ground
beside a wall or unmarked tree. It checks the full resting footprint, excludes
stockpiles, furniture plans, bridges and ladder approaches, and keeps sleepers'
claims separate. Searches use short proven flat routes and a fixed candidate
budget per tick. Dwarves prefer either reclining or lazy sitting, try the other
pose when needed, then fall back to clear ground (compact sitting if boxed in).
Task cleanup and cargo release happen before searching; the six-hour sleep
clock begins after settling. Walking to shelter does not restore sleep.

Sleep uses eased settle/wake transitions, closed voxel eyelids, breathing and
slow head motion. The old emoji is removed. Three original quiet snores use
Work audio, camera distance/zoom, slice/visibility, pause and wake guards.
Spatial choices and claims are transient: saved sleepers rebuild a suitable
pose while retaining position and remaining rest. Lost floor support still
settles the real actor first, then reselects a spot without resetting the need.
Bed ownership and the first sleep comfort thought are implemented: a completed
rest with at least three game hours in one's personal bedroom gives +10 happiness
for 24 game hours, refreshing without stacking. Happiness starts at 50%. Both
qualifying sleep progress and thought duration save and honor pause/speed. Other
needs/thoughts remain planned. See [121 — Personal bedrooms](../00_dev_roadmap/121_personal_bedrooms.md).
See [119 — Dwarf walking and ground rest](../00_dev_roadmap/119_dwarf_walking_and_ground_rest.md).
Bed use, bedroom classification and the nearby-cover silhouette are detailed in
[120 — Log beds and bedrooms](../00_dev_roadmap/120_log_beds_and_bedrooms.md).

## Idle activity — implemented 2026-10-09

After a short staggered pause, available dwarves stroll on nearby clear ground,
look around, or use an unoccupied installed wooden chair. Their local anchor
stays at the last job/spawn position so successive walks do not become an
expedition. Leisure remains in the task scheduler's idle pool and yields to
work immediately. It does not restore sleep or create a mood/food requirement.
The 2026-10-12 flooring follow-up lets a dwarf with no flat stroll take an
adjacent one-block step up onto clear ground. This lets them leave shallow tiles
that DEV Build skipped while occupied. The inspector calls this **Stepping up**.

`DwarfIdleBehavior` owns transient activity and uses TaskManager's `idle` tuning.
Chair claims are exclusive and transient; entry uses authored access cells and
the seated pose uses existing body parts, preserving 1×1×3 walking clearance.
Inspection labels the actual activity while the roster retains idle availability.
Completed seated meals also continue into this rest without standing and sitting
again. Dining transfers its exclusive seat claim; its table claim is released.
The empty hands relax smoothly, and work or needs can interrupt normally.
Read-only job planning preserves stationary idle timers and chair poses; actual
assignment still interrupts them. This prevents repeated unsuccessful checks
from restarting the wait before wandering indefinitely. See
[216 — Idle planning](../00_dev_roadmap/216_idle_planning_interruption.md).
See [99 — Idle activity](../00_dev_roadmap/99_dwarf_idle_activity.md).

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
This is immediate settling, not a gravity or fall-injury simulation.
See [115 — Dwarf support recovery](../00_dev_roadmap/115_dwarf_support_recovery.md).

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
> The former hunger rate of −0.005/s is superseded by milestone 131's
> game-hour Food tuning. Thirst and the other unimplemented needs below remain
> future design, including their provisional rates and consequences.
| `alcohol` | +varies on drink | > 0.80 | Mood bonus but pathfinding accuracy −30% |
| `mood` | ±event-driven | < 0.10 | Tantrum trigger; < 0.0 → berserk |
| `health` | injury-driven | < 0.10 | Forced bed rest |

### Biological Limits

- **Sustenance**: Initial tuning targets one portion every **8 game hours**.
  Food ≤ 0.40 starts a search; Famished is ≤ 0.15, not an automatic eight-hour
  death/critical deadline. Sleep also drains Food. Pause freezes both needs.
- **Rest profiles**: Dwarves require a minimum of **6 in-game hours** of sleep per 24-hour cycle. Sleep is taken autonomously when `sleep < 0.25` and a claimed bed is reachable.
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

The broader table below remains design material. The first live thought is
`Slept in my own bedroom` (+0.10 for 24 game hours after completing a rest with
at least three hours in a personal bedroom). DwarfMood currently combines that
thought with a 0.5 baseline. It has no tantrum or work-speed side effects.

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

---

## Profession System

Every dwarf has exactly **one active profession** at a time. All dwarves start as `base:profession:worker`. The shared inspector's Profession action opens the career map. Worker and Miner are assignable immediately; Carpenter requires physical collection of a crude carpentry kit. Other careers are planned previews. Switching professions never resets accumulated experience. Miner experience counts successfully removed blocks, not zone leases. Per-dwarf work permissions are independent of the active profession.

`data/professions/professions.json` holds what the game uses: the career-map
entries, work permissions, Miner experience thresholds, display names, promotion
parents, required tools and equipment previews. The planned design for every
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
| Hunter, Stonemason | Not designed beyond the career-map preview | — | — |

Level 6 needs both 10,000 tasks and the profession's calling trait (see Planned
trait effects).

### Agreed equipment progression — planned (2026-10-09)

**Live follow-up:** [101 — Tool promotion](../00_dev_roadmap/101_tool_based_promotion.md)
implements Carpenter's kit requirement, physical collection, cancellation,
equipped-item ownership, inspector/inventory presentation and current saves.
Miner keeps its implicit pickaxe. Carpenter workshop gameplay and all equipment
bonuses/upgrades remain planned. The original progression agreement follows.

[102 — Equipment feedback](../00_dev_roadmap/102_equipment_view_promotion_feedback.md)
adds the shared Equipment view with the owned tool's thumbnail, tier, materials
and actual benefit. Iron saw/pickaxe are explicit planned previews; no upgrade
goods or bonuses exist yet. Completed specialist promotions emit a short chime;
collection requests, cancellation, demotion and load restoration are silent.

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
These are agreed future requirements; equipment inventory, promotion tool gates
and tool upgrades are not implemented by milestone 96.
Milestone [97 — Starter tools](../00_dev_roadmap/97_starter_profession_tools.md)
adds physical, craftable/storable starter goods and displays their available
stock in the profession screen. It does not implement equipped-item ownership,
activate planned professions or grant bonuses for owning tools.

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
