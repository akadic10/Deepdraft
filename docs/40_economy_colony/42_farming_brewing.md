# 42 — Farming & Brewing

**Gradual seasonal art, 2026-10-15:** trees, shrubs, flowers and reeds update
their appearance across the first night of a season. Harvest eligibility and
crop cycles still change at midnight; harvest/removal actions use current
logical state. Tree bodies, occupancy and chopping work survive visual swaps.
Saving preserves gameplay state; a paused load rebuilds target art through
bounded frames. The owner asked for this gradual overnight change rather than the
world swapping in one frame (doc 194); the old path despawned and respawned every
tree, so the forest briefly vanished. `SurfaceFloraSpawner` swaps only a tree's art
node and skips trees whose model path does not change. `SurfaceDetailManager` keeps
a separate seasonal queue; spawning, harvesting, growth and transplanting stay
immediate, so a new or just-picked plant can show the new season before its
neighbours. The night schedule and queue rules are in doc 13 (`WorldClock`).

**Zones navigation, 2026-10-12 (doc 137):** Zones reserves visible Farming and Animal
pasture entries beside live Storage (doc 23, "Navigation Groups"). Both
are explicitly planned and only explain their status; no farm or pasture zones,
worker jobs, livestock ownership or crop cultivation are enabled by this UI pass.

**Food foundation, 2026-10-12 (doc 131):** dwarves eat fresh fruit, and berry bushes
give repeat crops. Dwarves prefer reachable stored food, then allowed loose portions.
Famished dwarves may pick a ripe, unclaimed bush within 24 blocks of routed travel when
harvested food is unavailable. Normal crop work, yield and regrowth still apply: one
portion is carried for eating, surplus berries remain haulable, and interrupted work
saves on the plant. The picker never clears or uproots the bush or skips its regrowth.
Dining and hunger penalties are live; the eating and dining rules are in doc 41.
Edibility/nutrition are explicit item data, so later cooked food and edible meats can
share the same behavior.

## Overview

The colony's food and drink supply draws from two distinct farming environments: **surface plots** on outdoor dirt for crops that need open air, and **cave soil patches** underground for fungi and plants adapted to darkness. Both feed into the same brewery and kitchen chain.

**Water foundation — live 2026-10-10; farm/brewery jobs remain planned:**
[33 — Water, rivers & flooding](../30_simulation_systems/33_water_simulation.md)
defines a high rock spring feeding a river and the lowland lake. Water storage
is finite and spring replenishment is limited. Players can divert channels into
farms/cisterns; blocking waterways or breaching reservoirs can flood terrain.
Filled ditches gradually hydrate nearby soil, which dries gradually after supply
stops. A perimeter ditch supports nearby crops; larger fields can use internal
channels. Damp-soil visuals and a moisture overlay explain coverage.
Moisture reach, crop requirements and rates need balancing; the older saturation
numbers below are provisional. Flood-related crop damage remains a separate decision.

Dwarves will draw and transport measured water for brewing, making access,
hauling and storage meaningful. Reconcile recipe inputs and container handling
when implementing production: the current planned Longbeard Ale recipe has no
water input. Water simulation and measured withdrawal are live; production jobs and recipe
changes remain planned. Gravity-fed supply is possible only below the source; higher farms
and breweries require hauling or a later, separately designed lifting system.

## Wild berry harvest — live 2026-10-08

**Habitat, spacing and flower relocation — live 2026-10-09 (doc 85):** wild berry
bushes root on grass/dirt/soil at Y4–43, below the mountain boundary Y44; wild
flowers keep Y4–70 (`placement` in the JSON). These bands limit generation only:
player cultivation may use suitable soil (`transplant.ground_kinds`) at any
height. Bushes, cuttings and flowers reserve exclusive 3×3 planting areas,
including queued orders, while keeping single-cell roots and no collision (rules
under Surface details). Flowers now support Move/Uproot and variant-specific
Place → Plants entries: 1.5 seconds to uproot, 1.25 to replant, and each shape is
its own unstackable packed item (one heavy carry load, one Seeds & cuttings
slot). Seasonal packed art, identity and dormant/blooming state survive
relocation and storage; moving or clearing a flower yields nothing. JSON
`bloom.seasons` and `SurfaceDetailManager.flower_blooming(id)` /
`flowering_clumps(center, radius)` are the future hive forage boundary: only
living, planted clumps in bloom count, at their current locations, so packed,
stored and cleared flowers never do and Move or reload never resets bloom. Honey
is not yet playable.

**Flower follow-up:** the shared clearing tool is now **Clear plants**. Decorative
wildflowers have four seasonal appearances, no harvest action or resource yield,
and take 1.5 seconds to clear by hand. Clearing, construction and excavation
remove them permanently.

Generated blueberry, elderberry and wild-strawberry plants can now be harvested
or permanently cleared. Harvest takes three seconds and keeps the plant; clearing
takes two seconds and yields one cutting on completion (100% for all three
species, configured in `wild.clearing.yields[].chance`). Berry harvest yields
blueberry 3 in summer, elderberry 4 in autumn, and strawberry 3 in spring/summer.
As of milestone 131, berries regrow after two planted days in eligible seasons;
off-season and packed intervals pause progress. Picked visuals, crop progress,
separate partial work and removals save. Moving a bush cannot refresh its crop.
Fruit enters the existing loose produce-crate and hauling pipeline. All four
seasons have dedicated voxel art, including berry-free picked variants.

Use the individual inspector or **Orders → Harvest plants / Clear shrubs**.
Cuttings use existing crates and the **Seeds & cuttings** stockpile filter. Each
completed clearing grants its cutting only once; cancellation and reload cannot
repeat the reward. Construction/excavation displacement grants no cutting.
Farm plots and brewing remain future work. Fruit consumption is live (doc 41).

**Mature shrub relocation — live 2026-10-08:** inspector **Move** replants the
selected whole bush at chosen open ground; **Uproot** packs it for storage and
later **Place → Plants**. Each takes three seconds of uprooting, with another
1.25 seconds to replant (`wild.transplant.uproot_seconds` / `plant_seconds`).
Replanting starts animating on arrival and includes the set-down in that
duration (doc 83). These actions preserve identity and the seasonal crop
without yielding fruit or cuttings. Whole shrubs use seasonal wrapped-root art,
one heavy carry load and one storage slot in Seeds & cuttings. Player placement
uses suitable dry ground and a clear 3×3 envelope under open sky, independently
of world-generation habitat bands.

**Cutting growth — live 2026-10-08 (doc 80):** **Place → Plants** also plants one
cutting per young shrub, with three seconds of worker planting. Each planting
takes one cutting from its crate (pickup, cancelling and the final site check are
in doc 31, "Cutting planting"). Cuttings use the mature transplant's placement rules, with clearance
checked for the mature plant. Blueberry/strawberry need 3 growth days and
elderberry 4 (`stages.shrub.growth_duration_days`). JSON seasonal multipliers
(`wild.planting.seasonal_growth`) are spring 1.2, summer 1.0, autumn 0.8 and
winter 0.0. Age is the plant's `growth_credit` plus
`WorldClock.seasonal_days_between()` since its `planted_at` day: one growth day
is one in-game day at rate 1, pausing freezes it, and there is no wall-clock or
offline growth. Twelve young seasonal models show their growth stage without
fruit. WorldClock-derived age survives save/load; maturity enables ordinary
seasonal harvest and mature Move/Uproot. Until then a young plant can only be
cleared, which returns one cutting; construction or support loss removes it
without a drop. Inspector **DEV: Grow to maturity** adds growth credit to that
plant only, leaving the calendar and other crops unchanged.

## Agricultural Cycles

**Apple harvesting — live 2026-10-19 (doc 252):** inspector **Gather apples** and
**Orders → Harvest plants** gather fruit without felling. Mature trees yield 4–6
apples in four seconds; ancient trees yield 7–10 in six seconds, once each autumn.
Saplings are too young. The fruit disappears after picking and returns next
autumn; partial work and picked state survive saving. Gathered apples enter normal
hauling and hungry dwarves can eat them. These are player-designated jobs, with
no automatic annual orders. Crop rules are under Fruit Trees below.

**Juniper harvesting — live 2026-10-09 (doc 84):** standing mature and ancient
junipers yield 2 and 4 berries respectively once each autumn, after three seconds
of hand picking. Saplings are too young. Inspector **Harvest berries** and
**Orders → Harvest plants** share the same player-designated task; no recurring
orders are posted. Felling now grants wood and possible seeds only. JSON stage
`fruit_harvest` defines season, work and yield. Picked state, partial picking and
felling work save separately, and eight berry-free models show depleted or
out-of-season trees.

**Cave generation status (2026-10-07):** generated caves now expose existing
soil deposits and can add a rough patch of `base:terrain:soil:cave` on a chamber
floor. This supplies a material and location for later underground agriculture.
It does **not** implement farming, saturation, irrigation, or naturally growing
cave crops. The requirements below remain the design target; dry cave soil alone
does not promise a working farm. The deferred cave water and fungi
work is tracked in `00_todo.md` (World / caves).

### Underground Crops (cave soil — `base:terrain:soil:cave`)

These crops require no light and cannot survive on surface dirt. Dwarves expose cave soil patches during normal mining operations and designate them as farm plots.

| Crop Key | Grow Time | Yield | Notes |
|---|---|---|---|
| `base:flora:plump_helmet` | 6 in-game days  | 4 food units    | Bulbous mushroom; primary underground food staple. Auto-reseeds from mycelium — no seed item needed. See `data/entities/flora/plump_helmet.json` |

### Surface Crops (surface dirt — `base:terrain:surface:dirt`)

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

Live irrigation uses three-cell Manhattan reach, weaker at distance, two game hours to wet and 24 to dry (doc 33). The old `−0.005 / hour` proposal is superseded. A farm plot with saturation `< 0.1` cannot support new crop growth.

### Surface Dirt Farming Requirements

A surface dirt block is eligible for farming designation only if:

1. The block type is `base:terrain:surface:dirt`.
2. There is **open sky** — no solid block within 10 blocks directly above (checked at designation time).
3. There are **at least 3 clear air blocks** above for dwarf access.

### Growth State Machine

```
FALLOW → SEEDED → SPROUTING → MATURE → HARVESTABLE → (harvested → FALLOW or PERSIST)
```

Each transition triggers a visual mesh swap on the farm block (see Single-Tile Asset Overflow Rule below).

- Annual crops return to FALLOW after harvest.
- Perennial crops stay in their current growth stage and re-enter HARVESTABLE the following harvest season.

**Planned, not implemented.** The crop files in `data/entities/flora/` hold the
stages, models and yields the art tools read; the farming rules below are design
only. Stages advance in the order the crop file lists them.

| Crop | Stages | After harvest |
|---|---|---|
| Plump helmet | sprouting (6 days) → mature | FALLOW, then automatically re-seeds to sprouting with no dwarf and no seed item; needs no light |
| Pig tail | seedling (8 days) → mature | FALLOW; re-seed from pig tail seed |
| Hops | seedling → climbing → mature | FALLOW; re-seed from hops cuttings |
| Grape vine | cutting → fruiting | Persists |

---

## Beehives

Beehives (`base:workshop:beehive`) are outdoor structures that produce honey passively over time.

**Planned, not implemented;** there is no beehive data file yet. Its one recipe,
`base:recipe:beehive:collect_honey`, takes no inputs, yields 2 honey, is 1 hour of
work and needs no skill. The placement and production values below are the design.

### Required future connection: wildflower forage

**User requirement, 2026-10-08:** the generated wildflowers must have a meaningful
role in honey production when beekeeping is implemented. They currently remain
decorative; this connection is planned, not live.

The proposed design is to measure nearby **blooming flower clumps** as bee forage
and use that supply to influence hive productivity. Preserving a flower patch
should give the player a reason to place a hive nearby. Bees visit living
flowers; flowers are not harvested or consumed as recipe ingredients.

- Count persistent flower records and their actual seasonal bloom state, never
  visible meshes or camera distance. Current wildflowers bloom in spring and
  summer; autumn seedheads and winter remnants supply no floral forage.
- Clearing, construction and excavation remove that clump's contribution.
  Season changes and loading must refresh the same result without restoring
  removed plants. Retain the planned winter dormancy and stored honey.
- Show the local forage supply and its production effect in the hive inspector
  and placement preview so the relationship is understandable.
- Define bloom contributions, forage radius and production response in owning
  JSON data when implementing the system. Tune the radius, rate versus yield
  effect, caps and overlapping-hive behavior at that milestone; do not assume
  unlimited throughput from stacking hives around one patch.

Other forage sources (such as flowering shrubs/trees), production with no local
flowers, and autumn production need an explicit balance decision. The production
table below remains a planned baseline, to be reconciled with this requirement.

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

**Brewing vat:** a placeable brewing vat is planned with the brewery. There is no
vat furniture definition or placed model in the game yet.

Brewing converts raw crops into drinks and refined goods inside a `base:workshop:brewery` block.

**Planned, not implemented;** there is no brewery data file yet. Each recipe has an
id, inputs and outputs, a work time in in-game hours, a skill bonus, a minimum
Brewer level (Min Skill, 0 = always available) and a UI category (`ale`, `stout`,
`mead`, `cider`, `wine`, `spirit`, `processed_goods`). Each Brewer level above 1
cuts the work time by the recipe's skill bonus: 5% for ale, stout and cider, 6% for
mead and wine, 7% for gin and 4% for cloth. The recipes are:

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

The Aging Cellar (`base:workshop:aging_cellar`) is an underground workshop that produces premium aged drinks from base brewed drinks and oak staves. It is **planned, not implemented;** there is no aging cellar data file yet.

**Carpentry decision (2026-10-04):** oak felling supplies raw logs and possible
acorns. A carpenter makes oak staves from those logs, then uses the staves for
oak aging casks. Staves never drop from trees. The planned aging recipes below
still consume staves directly; those inputs are provisional until cask crafting
and use are implemented. Carpentry quantities and work times remain to be defined.

**Aging rack:** an oak-cask aging rack is planned with the aging cellar. There is
no rack furniture definition or placed model in the game yet; the recipes and
temperature-dependent batch behavior described below are planned too.

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

**Seasonal variation:** rooms above Y 30 experience a gentle seasonal and daily temperature curve — up to ±2°C total swing at Y 75, fading to zero at Y 30 and below. The baseline aging depths in the table therefore retain some seasonal influence; only rooms at Y ≤ 30 are unaffected. A wine cellar at mid-depth with torches may briefly pause in peak summer as the seasonal warmth nudges it above 10°C; removing a torch in early summer prevents this. See `34_temperature.md` for the full formula.

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

Planned recipe values. Loading takes 1 hour, cut by 4% per Brewer level above 1;
Min Skill is the minimum Brewer level. When the room is out of range the batch
shows a tooltip: stout "Too warm for stout — lower temperature or build deeper.",
wine "Temperature out of range for wine — adjust heat sources or depth.", gin
"Too warm for gin — this recipe needs deep cold stone." UI categories are
`aged_ale`, `aged_wine` and `aged_spirit`.

| Recipe ID | Inputs | Output | Aging Time | Temp Range | Min Skill |
|---|---|---|---|---|---|
| `base:recipe:age:aged_stout`   | 3× stout + 2× oak stave | 2× aged stout   | 36 h | 3–7°C  | 3 |
| `base:recipe:age:vintage_wine` | 3× wine + 2× oak stave  | 2× vintage wine | 48 h | 6–10°C | 5 |
| `base:recipe:age:reserve_gin`  | 3× gin + 2× oak stave   | 2× reserve gin  | 40 h | 1–4°C  | 4 |

### Frozen Vault and Food Preservation

A sealed room whose computed temperature is ≤ 0°C becomes a **Frozen Vault** — approximately Y ≤ 35 on the unheated baseline, with the actual result depending on heat and seasonal variation. Planned food preservation will prevent spoilage in its food stockpiles. The Frozen Vault zone is too cold for any aging recipe (minimum 1°C required), so planned aging progress pauses until the room is warmed into range.

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

**Runtime status (2026-10-19):** tree inspection and single/batch tree felling are live via
**Orders → Chop trees** and explorer actions. Per-stage work durations,
partial progress, designations and felled records persist; authored felling drops
enter the normal hauling system. Manual annual apple and juniper picking is live
through **Orders → Harvest plants** and explorer actions (rules under Fruit Trees
below). Growth timers and forestry zones remain planned.

### Collision Rule

A mature or ancient tree gets one `StaticBody3D` with a `BoxShape3D`: XZ = the stage's
footprint (see the table below), height = the stage's `clearance_height` from the species
JSON, resting on the ground. The canopy is visual overhang only and carries no collision
(Hard Rule 5). Saplings have no body. `SurfaceFloraSpawner.enable_collision` can turn tree
bodies off globally.

**Physics layers — never put trees on Layer 1.** The RTS camera's `SpringArm3D` collides
with Layer 1 only, which is reserved for terrain (`Camera.gd`). A tree body on Layer 1 makes
the spring arm treat it as ground and snap the camera down onto the canopy on a quick pan.
Trees and surface details (boulders) use **Layer 2** (`tree_collision_layer`); dwarves use
Layer 3 (`DwarfAgent.COLLISION_LAYER_DWARF`). All three use `collision_mask = 0`.

### Placed Tree Rendering

Tree GLBs are Hearthblock models built by `tools/voxel_assets/trees.py`, exported in world
units (1 block = 1 Godot unit, root scale 1; see `63_shared_art_standard.md`). A tree's origin
is its trunk base, placed on the top face of the surface block (`get_surface_y + 1`).
`SurfaceFloraSpawner` overrides every mesh with the terrain material: vertex colour as albedo,
**lit** (`SHADING_MODE_PER_PIXEL`) and **double-sided** (`CULL_DISABLED`). Double-siding
stops the stepped canopy showing see-through back faces; lighting makes the facets read
as 3D like the ground. Trees bake their colours and use no runtime tint.

### Growth Stages

All trees share the same three-stage pattern:

- **Sapling** — `collision: "clutter"`, no `CollisionShape3D`. Appears via planting or world-gen.
- **Mature** — primary harvest target; full canopy collision. First harvestable stage.
- **Ancient** — world-gen only, never planted; largest visual and collision footprint.

### Footprint Table

| Species | Sapling | Mature | Ancient | Primary yield |
|---|---|---|---|---|
| Oak (`base:flora:oak_tree`) | clutter | 3×3 | 5×5 (world-gen) | Oak log |
| Juniper (`base:flora:juniper_tree`) | clutter | 1×1 | 2×2 (world-gen) | Juniper berry |
| Apple (`base:flora:apple_tree`) | clutter | 3×3 | 5×5 (world-gen) | Apple (fruit harvest) |
| Pine (`base:flora:pine_tree`) | clutter | 2×2 | 3×3 (world-gen) | Pine log |

**Oak** is a spreading broadleaf. Mature oaks (3×3) are the primary surface obstacle and supply oak logs, which a carpenter will turn into staves for aging casks. Felling can also yield acorns, but never finished staves. Full schema: `data/entities/flora/oak_tree.json`.

**Juniper** is a columnar evergreen. It stays 1×1 through maturity — dwarves can stand directly adjacent to fell it. Only the rare ancient juniper spreads to 2×2. Full schema: `data/entities/flora/juniper_tree.json`.

**Apple** is a spreading deciduous fruit tree with a canopy matching the oak (3×3 mature). Mature and ancient trees support perennial autumn picking, described above, with distinct ripe and picked visuals. Full apple schema: `data/entities/flora/apple_tree.json`.

**Pine** is a tall conical evergreen — the primary source of basic construction lumber. Its cone is narrower than the oak's spreading crown (mature 2×2, ancient 3×3) but it grows fast and dense. Pine is the **elevation tree**: world-gen scatters it across the **foothill shelves and mountain slopes only — never the lowland shelf or settlement plain**, thinning to a bare-rock treeline near the peaks. Placement parameters are data-driven in the `placement` block of `data/entities/flora/pine_tree.json`; the scatter and streaming logic lives in `SurfaceFloraSpawner`; placement across species is described under World placement below. Full schema: `data/entities/flora/pine_tree.json`.

### World placement

The settlement plain is fully forested: trees grow everywhere suitable, and the player clears land to build. There is no special forest belt at the map edge; the normal rules run to the border. Apples grow wild in groves; player planting of apple saplings is planned (no tree-planting work exists yet).

Each species has an elevation, domain and moisture niche, and all species share one scatter grid (`SurfaceFloraSpawner.scatter_cell_size`). Each cell holds at most one tree: every species is scored for suitability there, and one is chosen by a seeded weighted pick, or the cell is left open. This blends species across the gradients and prevents overlapping trunks. Placement is a pure function of `world_seed` and column position, so it needs no save data; saves store only changed trees (felled, designated, harvested). Moisture is a seeded noise map that reads drier with altitude and wetter beside water (`WorldGenerator.get_moisture`). Per-species keys (domains, height band, moisture band, `base_density`, slope and edge limits, footprints, stage weights) live in the `placement` block of each `data/entities/flora/*_tree.json`. Apple suitability is also gated by a grove mask, so wild apples cluster into groves.

The planned trade road (doc 51) must exclude flora from its road strip.

### Fruit Trees

**Implementation boundary:** player-designated annual picking is live for
juniper (84) and apple (252). Neither species automatically queues harvest orders.

A fruit tree has two independent harvest mechanisms:

**1. Fruit harvest (non-destructive, annual):** Defined by a `fruit_harvest` block
on the stage. Each autumn, eligible trees become ready to harvest. The player
designates picking through the inspector or Harvest plants click/drag tool. A
dwarf gathers fruit by hand at a reachable side of the trunk and leaves the
crop there for ordinary hauling or eating. The tree persists.
Cancel/Undo releases the worker without losing the
current crop's partial work. The same tree cannot be picked twice that autumn;
the next year's crop starts with fresh work. No automatic annual orders are posted.
Only stages whose `fruit_harvest` has `work_seconds` post a job
(`SurfaceFloraSpawner.can_harvest_tree`). A marked tree carries one action at a
time, so felling and picking never run together: cancel one before ordering the
other. Each keeps its own saved progress (`fell_work_seconds`,
`harvest_work_seconds`), which never transfers. A crop is one year and season;
completion stamps `harvested_cycle` before any fruit spawns, so cancellation,
reload, streaming or a stale completion cannot repeat it, and leaving autumn
cancels pending and active picking. The crop lands on the picker's own cell, the
reachable side of the solid trunk.

`SurfaceFloraSpawner.resolve_tree_model_for_season()` takes a `picked` flag from
the saved `harvested_cycle`. Stages with `picked_models` (juniper) use them after
picking or outside `harvest_season`, so berries show only on an unpicked autumn
crop. Apples select `autumn_fruiting` only while that autumn's crop is unpicked;
after picking they use the matching ordinary autumn model without fruit. Saved
crop state drives the choice after reload or streaming, and season reconciliation
also runs when a restore changes only the year. A crop change replaces only the
visual child (`_refresh_tree_crop_visual`); the trunk body, occupancy and
reservations stay.

**2. Chop harvest (destructive):** Works the same as any other tree — dwarf fells the tree, yielding wood and a seed drop. Apples come exclusively from the non-destructive fruit harvest, not the fell.

| Species | Fruit item | Season | Mature yield | Ancient yield |
|---|---|---|---|---|
| Apple | `base:resources:flora:apple` | Autumn | 4–6 | 7–10 |
| Juniper | `base:resources:flora:juniper_berry` | Autumn | 2 | 4 |

A yield is either a fixed `yield_count` (juniper) or an inclusive
`yield_min`/`yield_max` (apple) picked by a deterministic tree/year hash, so
interruption and reload cannot reroll it. Picking takes four seconds for mature
apples and six for ancient apples; juniper picking takes three seconds at either
adult stage. These values live in JSON, as do `action_label` and `yield_label`,
which name the panel action and the worker's activity (apples: **Gather apples**,
"Harvesting apples"; without them, **Harvest berries** and "berries"). Hungry
dwarves eat gathered fruit through the normal food system; emergency
self-foraging of standing plants still targets nearby ripe berry shrubs.

> **Agent note**: Trees are the **only** surface entities with real collision shapes. Giving a `CollisionShape3D` to any farm crop violates the Single-Tile Asset Overflow Rule above.

---

## Surface details

Boulders, scree, wild berry shrubs, wildflowers and reeds are surface details:
placed entities, never terrain blocks. `SurfaceDetailRegistry` loads their
definitions from `data/entities/surface_details.json` and the flora
`*_bush.json` files; `SurfaceDetailPlacement` scores candidates and
`SurfaceDetailManager` owns the layout, removals and saved changes. They sit
beside the tree layer described under World placement and never change it.

- **Placement comes from seed and category only.** A candidate derives from
  `world_seed`, the definition's own hash salt and its scatter cell, sampled
  against generated terrain and water. Loaded visuals, streaming order, camera
  position and current occupancy never decide where a detail goes. Untouched
  details regenerate on load; saves store only changes (removal, moves, partial
  work, crop state).
- **Precedence.** Generated tree candidates come first: a detail whose area,
  plus its `tree_margin`, meets a tree candidate is rejected, even where that
  tree has not streamed in. Remaining candidates are arbitrated by JSON
  `placement_priority`, highest first, with ties broken by id: boulder 100,
  scree 50, blueberry 20, elderberry 19, wild strawberry 18, flowers 10,
  reeds 5.
- **Conflicts resolve before saved removals apply.** Arbitration runs on the
  immutable candidate set, so clearing a detail never lets a previously rejected
  one appear on reload.
- **Terrain is never flattened to fit a detail.** An unsupported footprint is
  rejected, not levelled.
- **Removal is committed before any reward.** The detail is tombstoned first and
  the drop spawned after, so cancelling, season changes or reloading cannot
  repeat a yield.
- **Construction or loss of supporting ground removes a detail with no reward.**
  Placed structures and terrain edits under a detail remove it permanently;
  season changes, camera movement and loading never bring it back.
- **Only boulders block.** A boulder registers its 2×2 footprint (2 high) in
  `PlacedEntityRegistry` and gets a `StaticBody3D` on physics Layer 2 with
  `collision_mask = 0`. Every other detail is non-blocking: no occupancy and no
  collider (Hard Rule 5 for plant overhangs).
- **Plants keep exclusive planting areas.** Bushes and flowers have
  `planting_radius` 1: `SurfaceDetailPlacement.planting_area()` covers the 3×3
  columns around the root, from the ground's top up three blocks (or the plant's
  height). Areas may touch but never overlap, so centres in a row stand at least
  three blocks apart and two-block diagonal offsets are rejected; plants on
  different terrain levels never collide just because their X/Z match.
  Generation, moved and stored plants, cuttings (given the mature area from
  planting) and queued Place destinations all use it. A queued plan reserves its
  area at once, cancelling releases it, restore rebuilds it from the saved plan,
  and a completing plan ignores only its own reservation. The areas carry no
  occupancy, so dwarves walk through them.
- **Reeds use actual nearby water.** A reed roots on a dry bank within
  `shore_radius` (4, Manhattan) of a generated water cell, 0–2 blocks above
  that body's local waterline (`min_bank_height` / `max_bank_height`). The
  water-bank mask is only a cheap prefilter; never place from the mask alone or
  assume the waterline is Y18.
- **Densities change only with measurement.** Before raising any category's
  population, repeat a paired comparison of the same seeds and camera paths with
  and without details (counts, frame time, draw calls, memory).

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

Place this as a `static func` on whichever system owns tree entity placement. It currently lives on `SurfaceFloraSpawner` (the surface-flora scene node, `scripts/systems/SurfaceFloraSpawner.gd`), which all tree spawners call. Do **not** scatter the hash logic across multiple callers — there must be exactly one resolution point.

### Season Fallback Order

When the current season key is absent from a stage's `models` dict, fall back in this order:

```
requested_season → "summer" → push_error and return ""
```

Pine and Juniper omit `spring` and `autumn` deliberately — `"summer"` is their defined fallback for those seasons. The resolver must handle a missing key gracefully before attempting variant resolution.

```gdscript
static func resolve_tree_model_for_season(
        stage_data: Dictionary, season: String, world_pos: Vector3i, picked := false) -> String:
    var models: Dictionary = stage_data.get("models", {})
    var fruit: Dictionary = stage_data.get("fruit_harvest", {})
    # Berry-free art after picking or out of season (juniper; see Fruit Trees).
    if stage_data.has("picked_models") and (picked or season != String(fruit.get("harvest_season", ""))):
        models = stage_data.picked_models
    if not picked and season == "autumn" and stage_data.has("fruit_harvest") and models.has("autumn_fruiting"):
        return resolve_tree_model(models["autumn_fruiting"], world_pos)
    var value = models.get(season, models.get("summer", ""))
    if value is String and value == "":
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
