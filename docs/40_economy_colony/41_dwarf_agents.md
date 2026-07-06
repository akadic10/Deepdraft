# 41 — Dwarf Agents

> **IMPLEMENTATION STATUS (First Dwarf Milestone, doc 16 — banked 2026-06-10 → 2026-07-02).**
> Shipped: `DwarfAgent` (`scripts/entities/DwarfAgent.gd`) with the four-part mesh hierarchy,
> runtime tint split (head/hands tinted, body/feet baked — doc 17 §1), procedural
> **distance-driven walk gait** (plant/lift foot phases, counter-swinging hands, body lean;
> `walk_speed` 2.2, `stride_length` 0.7 — all exports, doc 17 §2), zone-lease mining execution
> with the vertical reach envelope, and **sleep-lite** — the single `sleep` stat below, draining
> per the table, with in-place sleeping (no beds yet) and the §2.8 release protocol
> (`16_first_dwarf_milestone.md` step 7). Procedural generation (names/appearance/traits,
> seed-deterministic per `world_seed + birth_index`) runs through `DwarfFactory` +
> `DwarfAssets`; dwarves spawn at the player-placed Settlement Flag. NOT yet implemented:
> hunger/thirst/alcohol/mood/health, thoughts, beds, professions at runtime, portraits, the
> full needs-interrupt priority ladder — the tables below remain their design source.

## Overview

Each dwarf is an autonomous agent (`DwarfAgent`, extends `CharacterBody3D`) driven by the Task System. Dwarves have physiological stats that degrade over time and must be replenished through colony resources.

## Physiological Stats

All stats are floats in the range `0.0 – 1.0` unless otherwise noted.

| Stat | Drain Rate | Critical Threshold | Consequence |
|---|---|---|---|
| `hunger` | −0.005 / s | < 0.15 | Work speed ×0.5; < 0.0 → death |
| `thirst` | −0.008 / s | < 0.15 | Mood penalty; < 0.0 → death |
| `sleep` | −0.003 / s | < 0.20 | Work speed ×0.6, pathfinding errors increase |
| `alcohol` | +varies on drink | > 0.80 | Mood bonus but pathfinding accuracy −30% |
| `mood` | ±event-driven | < 0.10 | Tantrum trigger; < 0.0 → berserk |
| `health` | injury-driven | < 0.10 | Forced bed rest |

### Biological Limits

- **Sustenance**: A dwarf must eat food at least once every **8 in-game hours** or hunger hits critical.
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

### Mesh Anatomy — Stonehearth-Inspired Silhouette

Dwarf character meshes follow a **Stonehearth-style blocky silhouette**: deliberately simplified anatomy that keeps MagicaVoxel asset authoring fast and consistent across the whole roster.

A dwarf mesh is composed of exactly **four parts**:

| Part | Description | Notes |
|---|---|---|
| **Head** | Oversized relative to the body — the dominant visual element | Carries the face, hair, beard, and all headwear (helmets, hats) |
| **Body** | Compact torso block below the head | Carries chest armour, clothing, and profession colour/markings |
| **Hands** | Two small floating blocks at body-side height | Float at the sides of the body with no connecting arm geometry |
| **Feet** | Two small floating blocks below the body | Float below the body with no connecting leg geometry |

**Dwarves have no arms and no legs.** The hands and feet are detached, floating parts — connected to the body only by animation transforms, not by any mesh geometry. This is intentional and must be preserved:

- It dramatically simplifies mesh authoring in MagicaVoxel. Each dwarf variant is four small voxel objects rather than a complex articulated rig.
- It matches the aesthetic reference of Stonehearth, where the charm comes from the contrast between the large expressive head and the minimal, bobbing limb stubs.
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
  ├─ MeshHead   (MeshInstance3D)  ← .glb imported from MagicaVoxel
  ├─ MeshBody   (MeshInstance3D)
  ├─ MeshHandL  (MeshInstance3D)
  ├─ MeshHandR  (MeshInstance3D)
  ├─ MeshFootL  (MeshInstance3D)
  └─ MeshFootR  (MeshInstance3D)
```

Equipment meshes (helmets, chest armour, boots, weapons) are **child nodes** of the relevant part — a helmet is a child of `MeshHead`, chest armour a child of `MeshBody`, and so on. Equipping or unequipping gear is simply adding or removing those child nodes.

> **Agent note:** Never merge dwarf part meshes into a single combined mesh. The four-part separation is required for equipment attachment and procedural animation. Keep each part as an independently addressable `MeshInstance3D`.

## Agent State Machine

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
- **Portrait** — detailed close-up rendered in the labour UI and dwarf inspect panel. All appearance components are visible here.

### Trait Assignment

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

Every dwarf has exactly **one active profession** at a time. All dwarves start as `base:profession:worker`. The player promotes a dwarf to a specialised profession via the labour UI. Switching professions never resets accumulated experience — task counts are retained per profession key so a dwarf can be reassigned and resume from where they left off.

Full profession definitions, task type lists, room assignments, and level descriptions: `data/professions/professions.json`.

### Agent Fields

```gdscript
var profession: String = "base:profession:worker"   # current active profession key

var profession_experience: Dictionary = {           # raw task counts per profession key
    "base:profession:worker":      randi_range(0, 9),
    "base:profession:miner":       0,
    "base:profession:farmer":      0,
    "base:profession:brewer":      0,
    "base:profession:builder":     0,
    "base:profession:merchant":    0,
    "base:profession:innkeeper":   0,
    "base:profession:blacksmith":  0,
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
| 3 | 100 | 110 |
| 4 | 500 | 610 |
| 5 | 2,500 | 3,110 |
| 6 | 10,000 | 13,110 |

Level 6 requires both the cumulative task count **and** a qualifying trait (trait system not yet designed).

### Work Speed Bonus

Each profession defines a `work_speed_bonus_per_level` (see professions.json). The formula for primary task duration:

```
task_duration × (1.0 - (experience_level - 1) × work_speed_bonus_per_level)
```

At `work_speed_bonus_per_level: 0.05`, a level 5 dwarf completes primary tasks 20% faster than level 1. Level 6 adds a further 5% (25% total). The bonus applies only to the dwarf's **active profession** task types. Fallback Worker tasks (hauling while off-duty from a specialist role) always use the Worker experience level.

### Recipe Gates (Brewer)

The `required_skill` field in `brewery.json` and `aging_cellar.json` maps directly to the Brewer's experience level. A Brewer at experience level N can perform any recipe with `required_skill ≤ N`. The field name is kept as `required_skill` in recipe files for brevity.

---

*Prev: [33_water_simulation.md](../30_simulation_systems/33_water_simulation.md) | Next: [42_farming_brewing.md](./42_farming_brewing.md)*
