# 42 — Farming & Brewing

## Overview

The colony's food and drink supply draws from two distinct farming environments: **surface plots** on outdoor dirt for crops that need open air, and **cave soil patches** underground for fungi and plants adapted to darkness. Both feed into the same brewery and kitchen chain.

## Agricultural Cycles

### Underground Crops (cave soil — `base:terrain:soil:cave`)

These crops require no light and cannot survive on surface dirt. Dwarves expose cave soil patches during normal mining operations and designate them as farm plots.

| Crop Key | Grow Time | Yield | Notes |
|---|---|---|---|
| `base:flora:plump_helmet` | 6 in-game days  | 4 food units    | Bulbous mushroom; primary underground food staple. Auto-reseeds from mycelium — no seed item needed. See `data/entities/flora/plump_helmet.json` |

### Surface Crops (surface dirt — `base:terrain:surface:dirt_NN`)

These crops require open sky above the farm block (no ceiling within 10 blocks) and grow on the surface dirt exposed around the mountain entrance. Dwarves must venture outside to tend and harvest them.

| Crop Key | Grow Time | Harvest Season | Yield | Notes |
|---|---|---|---|---|
| `base:flora:pig_tail`    | 8 in-game days  | Any (annual — re-seed each spring) | 4× pig tail fiber + seed (40%) | Annual fibrous plant; source of cloth. See `data/entities/flora/pig_tail_plant.json` |
| `base:flora:hops_plant`  | 11 in-game days | Any (dies in winter) | 5 hops + 2× cutting (60%) | Annual bine; re-seed each spring. See `data/entities/flora/hops_plant.json` |
| `base:flora:grape_vine`  | 6 in-game days  | Summer / Autumn | 5 grapes + 1× cutting (25%) | Perennial vine; survives winter dormant. See `data/entities/flora/grape_vine.json` |

#### Hops — Annual Crop

Hops (`base:flora:hops_plant`) grow through three stages: `seedling → climbing → mature`. The plant only yields at the mature stage. After harvest the farm plot returns to **FALLOW** and must be re-seeded from hops cuttings the following spring. Any plant still in the `seedling` or `climbing` stage when winter arrives is lost — the farm plot returns to FALLOW at the season change. Dwarves should prioritise harvesting all mature hops before the end of autumn.

#### Grape Vine — Perennial Crop

Grape vines (`base:flora:grape_vine`) grow through two stages: `cutting → fruiting`. Once fruiting, the vine **persists across seasons** and yields grapes each summer and autumn without replanting. The vine displays a dormant bare-cane model in winter but does not reset. A single planting effort provides a permanent supply — prioritise establishing vines early.

### Cave-Floor Soil Saturation Requirements

A cave soil block is eligible for farming designation only if:

1. The block type is `base:terrain:soil:cave`.
2. Water saturation of the block is `> 0.3` (tracked as a per-block float, separate from fluid CA mass).
3. There are **at least 3 clear air blocks** above (matches dwarf clearance envelope — crops must be harvestable).

Soil saturation drains at `−0.005 / in-game hour` and is replenished by adjacent water blocks or irrigation channels (future feature). A farm plot with saturation `< 0.1` cannot support new crop growth.

### Surface Dirt Farming Requirements

A surface dirt block is eligible for farming designation only if:

1. The block type is any `base:terrain:surface:dirt_NN` variant.
2. There is **open sky** — no solid block within 10 blocks directly above (checked at designation time).
3. There are **at least 3 clear air blocks** above for dwarf access.

### Growth State Machine

```
FALLOW → SEEDED → SPROUTING → MATURE → HARVESTABLE → (harvested → FALLOW or PERSIST)
```

Each transition triggers a visual mesh swap on the farm block (see Single-Tile Asset Overflow Rule below).

- Annual crops (`post_harvest: "fallow"`) return to FALLOW after harvest.
- Perennial crops (`post_harvest: "persist"`) stay in their current growth stage and re-enter HARVESTABLE the following harvest season.

---

## Beehives

Beehives (`base:workshop:beehive`) are outdoor structures that produce honey passively over time. Full schema: `data/workshops/beehive.json`.

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

Brewing converts raw crops into drinks and refined goods inside a `base:workshop:brewery` block.

Recipes are defined in `data/workshops/brewery.json` (see that file for the full schema). The recipes are:

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

The Aging Cellar (`base:workshop:aging_cellar`) is an underground workshop that produces premium aged drinks from base brewed drinks and oak staves. Full schema: `data/workshops/aging_cellar.json`.

For the full temperature system — sealed rooms, heat sources, the depth-temperature gradient, and the Frozen Vault — see [`34_temperature.md`](../30_simulation_systems/34_temperature.md).

### Temperature Requirement

The aging cellar block must be placed inside a **sealed room** whose computed temperature falls within the recipe's required range. Temperature is derived from the room's mean floor Y (deeper = colder) plus any heat bonus from torches or braziers placed inside the sealed room.

There is no hard Y placement constraint on the block itself — temperature is the gating factor. A cellar placed in a room that is too warm or too cold simply shows its affected recipes as unavailable until temperature is corrected.

| Aged Drink | Required Temp | Baseline Depth | Notes |
|---|---|---|---|
| Aged Dark Stout | 3–7°C | Y 47–64 | Cold Cave zone; accessible without extreme depth |
| Vintage Wine | 6–10°C | Y 57–75 | Cool Cave zone; the shallowest aging recipe |
| Reserve Gin | 1–4°C | Y 37–56 | Deep Cold zone; a torch converts a near-frozen room into a gin cellar |

**Warming a room:** place torches or braziers inside the sealed room to raise its temperature. The heat bonus scales inversely with room volume — compact aging rooms (4×4×4 to 8×8×4) respond strongly to a single torch; large caverns need several.

**Cooling a room:** there is no cooling mechanic. If a room is too warm for a recipe, build a new aging cellar at greater depth.

**Seasonal variation:** shallow rooms (above Y 30) experience a gentle seasonal and daily temperature curve — up to ±2°C total swing at the shallowest caves, fading to zero below Y 30. Deep aging cellars are completely unaffected. A wine cellar at mid-depth with torches may briefly pause in peak summer as the seasonal warmth nudges it above 10°C; removing a torch in early summer prevents this. See `34_temperature.md` for the full formula.

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

| Recipe ID | Inputs | Output | Aging Time | Temp Range | Min Skill |
|---|---|---|---|---|---|
| `base:recipe:age:aged_stout`   | 3× stout + 2× oak stave | 2× aged stout   | 36 h | 4–8°C  | 3 |
| `base:recipe:age:vintage_wine` | 3× wine + 2× oak stave  | 2× vintage wine | 48 h | 8–12°C | 5 |
| `base:recipe:age:reserve_gin`  | 3× gin + 2× oak stave   | 2× reserve gin  | 40 h | 1–5°C  | 4 |

### Frozen Vault and Food Preservation

A sealed room at Y ≤ 14 (temperature ≤ 0°C) becomes a **Frozen Vault**. Food stockpiles inside do not spoil. The Frozen Vault zone is too cold for any aging recipe (minimum 1°C required). Placing an aging cellar inside a frozen vault disables its recipe queue entirely.

A heavily torched frozen vault can be warmed above 0°C, converting it from a freezer into a potential Reserve Gin cellar — but the freezing benefit is lost. The tradeoff is intentional.

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

### Collision Rule

The `CollisionShape3D` XZ extents must match the visual canopy spread of the mesh. The harvestable destination region mirrors those same XZ extents at Y height = 1 (ground level, where the dwarf stands to chop). Collision runs full height from Y = 0 to the top of the mesh.

### Growth Stages

All trees share the same three-stage pattern:

- **Sapling** — `collision: "clutter"`, no `CollisionShape3D`. Appears via planting or world-gen.
- **Mature** — primary harvest target; full canopy collision. First harvestable stage.
- **Ancient** — world-gen only, never planted; largest visual and collision footprint.

### Footprint Table

| Species | Sapling | Mature | Ancient | Primary yield |
|---|---|---|---|---|
| Oak (`base:flora:oak_tree`) | clutter | 3×3 | 5×5 (world-gen) | Oak stave |
| Juniper (`base:flora:juniper_tree`) | clutter | 1×1 | 2×2 (world-gen) | Juniper berry |
| Apple (`base:flora:apple_tree`) | clutter | 3×3 | 5×5 (world-gen) | Apple (fruit harvest) |

**Oak** is a spreading broadleaf. Mature oaks (3×3) are the primary surface obstacle and the only source of oak staves for the aging cellar. Full schema: `data/entities/flora/oak_tree.json`.

**Juniper** is a columnar evergreen. It stays 1×1 through maturity — dwarves can stand directly adjacent to fell it. Only the rare ancient juniper spreads to 2×2. Full schema: `data/entities/flora/juniper_tree.json`.

**Apple** is a spreading deciduous fruit tree with a canopy matching the oak (3×3 mature). Unlike oak and juniper, apple trees are **perennial fruit producers** — see Fruit Trees below. Full schema: `data/entities/flora/apple_tree.json`.

### Fruit Trees

A fruit tree has two independent harvest mechanisms:

**1. Fruit harvest (non-destructive, annual):** Defined by a `fruit_harvest` block on the stage. Each autumn, the tree auto-enters a FRUITING state and a harvest task is queued. A dwarf picks the fruit and deposits it in the nearest food stockpile. The tree persists (`post_harvest: "persist"`). No player action needed beyond having idle dwarves.

**2. Chop harvest (destructive):** Works the same as any other tree — dwarf fells the tree, yielding wood and a seed drop. Apples come exclusively from the non-destructive fruit harvest, not the fell.

| Species | Fruit item | Season | Mature yield | Ancient yield |
|---|---|---|---|---|
| Apple | `base:resources:flora:apple` | Autumn | 4–6 | 7–10 |

> **Agent note**: Trees are the **only** surface entities with real collision shapes. Giving a `CollisionShape3D` to any farm crop violates the Single-Tile Asset Overflow Rule above.

---

## Model Variant Resolution

Tree species JSON (`data/entities/flora/*.json`) supports two formats for each season key inside a stage's `models` block:

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

Place this as a `static func` on whichever Autoload owns tree entity placement (world-gen system or surface environment manager). Do **not** scatter the hash logic across multiple callers — there must be exactly one resolution point.

### Season Fallback Order

When the current season key is absent from a stage's `models` dict, fall back in this order:

```
requested_season → "summer" → push_error and return ""
```

Pine and Juniper omit `spring` and `autumn` deliberately — `"summer"` is their defined fallback for those seasons. The resolver must handle a missing key gracefully before attempting variant resolution.

```gdscript
static func resolve_tree_model_for_season(stage_data: Dictionary, season: String, world_pos: Vector3i) -> String:
    var models: Dictionary = stage_data.get("models", {})
    var value = models.get(season, models.get("summer", ""))
    if value == "":
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
