# 75 — Seasonal wild shrubs

Implemented 2026-10-08 after approval of the shrub milestone and four-season
voxel art. This is step 6 of [72 — Surface details](72_surface_details_plan.md).
Flowers and lakeside reeds remain the next separate steps.

## Player behavior

| Plant | Habitat | Harvest seasons | Crop |
|---|---|---|---:|
| Blueberry | Foothill/mountain pockets, Y36–115; rock, grass or dirt; moisture 0.10–0.85 | Summer | 3 blueberries |
| Elderberry | Moist lowlands and foothills, Y4–70; grass or dirt; moisture ≥0.50 | Autumn | 4 elderberries |
| Wild strawberry | Lower grassy/dirt openings, Y4–40; moisture ≥0.25; wider tree spacing | Spring and summer | 3 strawberries per season |

These are initial placement/yield settings, not a balanced food economy. Broad
seeded masks form patches with open gaps. Elderberry's moist habitat and tree
spacing approximate sheltered woodland edges; no wind/sunlight simulation exists.

**Harvest berries** takes three seconds of worker hand gathering at normal speed.
It grants the existing berry item through the loose-item/crate/hauling system,
removes visible berries and leaves the plant. There is one crop per eligible
season, identified by calendar year and season. Strawberries can produce once
in spring and again in summer. Skipped crops do not accumulate. New crops need
a new player designation; plants never post automatic recurring jobs.

**Clear plant** takes two seconds and permanently removes the plant, in any
season. Completed worker clearing recovers **one cutting** for all three species,
with `wild.clearing.yields[].chance` set to **1.0 (100%)** at the user's request;
ordinary berry harvest grants fruit only. The inspector shows the cutting name
and chance. Cuttings use their existing crate assets, inventory entries and
**Seeds & cuttings** stockpile filter; growing from cuttings subsequently shipped
in [80 — Shrub cutting growth](80_shrub_cutting_growth.md).
Mature **Move / Uproot / Place → Plants** subsequently shipped in
[79 — Shrub transplanting](79_shrub_transplanting.md), preserving the existing crop.

The yield does not change with season, previous berry harvest, cancellation or
reload. Permanent removal is committed before drops, preventing repeated rewards.
Construction and support excavation still remove plants without a cutting.

Harvest and clear are separate actions; an active action
must be cancelled before switching. Each keeps its own partial work. Pause,
interruption, sleep and cancellation use the existing worker release contract.
When harvest season ends, queued/active harvests are cancelled safely; partial
work is retained for a future eligible crop. Clearing continues across seasons.

The ordinary Object explorer offers these actions and shows crop state, seasons,
yield, work progress and access/retry state. **Orders → Harvest plants** selects
only ripe shrubs; **Orders → Clear shrubs** selects all remaining shrubs.
**Clear stones** still selects only boulders/scree. All share actual mesh picking,
ground rectangles, live counts, Cancel orders, source-safe Undo and View order.
Six Orders tiles use one row on larger screens and two rows below 1100px.

## Art and placement

`tools/generate_shrubs.py` produces **19 GLBs**: twelve seasonal mature models,
four picked-crop models and three smaller shrub-stage models for the existing
future planting definitions. All use baked 0.125 scale, root scale 1, ground Y0,
linear vertex colors and the normal lit world material. Godot creates imports.
One world block is one Godot unit and eight small-asset voxels.

| Mature species | Maximum X / Y / Z bounds, blocks | Clearance height |
|---|---|---:|
| Blueberry | 1.625 / 1.625 / 1.5 | 2 |
| Elderberry | 2.25 / 2.5 / 1.875 | 3 |
| Wild strawberry | 1.5 / 0.625 / 1.75 | 1 |

Blueberries have a compact crown, pale spring blooms, blue summer berries, rust
autumn leaves and bare winter twigs. Elderberries have an open branching crown,
small spring foliage, fuller summer flower umbels, purple autumn clusters and
bare winter stems. Strawberries have connected low rosettes, spring flowers and
red fruit, summer fruit, reduced autumn foliage and dormant winter runners.
Picked variants keep leaves/stems and remove fruit accents.

Each plant has one logical support tile and no collider or navigation occupancy.
Visual overhangs are nonblocking. A flat dry 3×3 placement envelope, tree margins
and spacing from other details prevent edge/trunk intersections. Committed
construction on the support tile or excavation of its support removes the plant
and cancels work without loot. Neither season changes nor rebuilding support
resurrects a removed plant. Generation never flattens or clears terrain.

Each species has independent salts on a 14-block candidate grid. Existing trees,
boulders and scree take precedence, followed by stable shrub priorities/IDs.
Acceptance occurs before applying player removals, so clearing a boulder never
creates a newly eligible shrub on reload. Terrain, lakes, rough cliffs, caves,
ore placement and tree identities are unchanged.

## Ownership and persistence

`SurfaceDetailRegistry` solely loads the three existing bush JSON files and
normalizes their mature models, fruit yields and new `wild` settings. Runtime
owners, workers and previews never open those definitions themselves. Berry
harvest and cutting recovery use separate yield lists. Growth from
cuttings, farm jobs, berry consumption and brewing remain separate work.

`SurfaceDetailManager` owns permanent records and deltas. `ShrubSeason` provides
crop-cycle/model rules. Appended priority-50 task types `HARVEST_SHRUB` and
`CLEAR_SHRUB` share the adjacent work source and hand-gathering pose. A successful
crop stamps its harvested cycle and retires its source before creating rewards.

The existing `surface_details` save section additionally stores plant action,
harvested cycle and separate partial harvest/clear progress. Node, mesh, task
and source identities remain transient. Clock restoration happens after scene
owners: restoring a plant must not reject its saved harvest against the old
clock. The final `season_changed` signal reconciles jobs and queues visual swaps.
Duplicate signals/load cannot replenish the current crop or replay rewards.

Visual creation and seasonal swaps use the existing twelve-per-frame queue.
Meshes are shared by species/season/state; plants have no per-instance process.

## Verification

- **ShrubPilotTest, headless and native:** all seasonal imported bounds, grounded
  models, nonblocking support, inspector actions, actual scheduler/worker harvest
  and clearing, pause/interruption, separate action progress, active/cancelled
  restore, clock restore ordering, season-end cancellation, exact yields, annual
  regrowth, two strawberry crops, picked visuals, permanent removal, construction
  displacement and support excavation. Native scale/worker image includes a dwarf
  and a one-block cube: `tmp/shrub_review/worker_scale.png`.
- **Initial cutting follow-up, ShrubPilotTest native:** fixed successful/unsuccessful rolls
  for every species, actual worker clearing, partial cancellation/restore,
  seasonal changes, duplicate completion guards, no cuttings from berry picking
  or construction/support displacement, exact item quantities after item restore,
  valid crate models and actual hauling into Seeds & cuttings storage. The updated
  inspector was visually reviewed. `tmp/shrub_review/cuttings.log` and native
  `cutting_orders.log` pass without script errors.
- **100% cutting update, ShrubPilotTest headless:** all six clearing fixtures now
  yield exactly one cutting, including the previously unsuccessful positions.
  Inspector percentages, cancellation/restore, duplicate completion guards,
  displacement exclusions, item persistence and hauling pass.
  Log: `tmp/shrub_review/guaranteed_cuttings.log`.
- **SurfaceDetailLayoutTest:** eight seeds, forward/reverse enumeration and fresh
  owner restore; habitat/ground/support checks; unchanged terrain/tree fingerprints
  and exact existing boulder/scree populations. All three species occur on each
  sampled seed, without a forced population guarantee.
- **OrdersShelfTest, native:** actual click/drag selection, ripe/category filters,
  mixed stone exclusion, cancellation, separate modes and stale receipt safety.
  Layout captures cover 960×540, 1280×720 and 2560×1440, with/without inspectors.
- **SaveManagerRoundTripTest:** full scene, autosave, manual save and corrupt-file
  backup recovery. Fixtures include removed shrubs, active/partial elderberry
  harvesting and an already-picked autumn crop; final saved clock wins over a
  transient winter. Full owner snapshots compare equal after reload.
- **BoulderPilotTest, ScreePilotTest and TreeFellingTest:** existing stone and
  forestry work paths pass, including established hauling behavior.
- **ShrubLivePreview:** real generated map, developer menu for all three species,
  ordinary picking/Orders harvest/cancel and live summer→winter replacement.
  Close/native captures reviewed beside existing trees and terrain.

| Seed | Blueberry | Elderberry | Strawberry | All detail layout/registration, ms |
|---|---:|---:|---:|---:|
| 0 | 269 | 318 | 416 | 313.5 |
| 1 | 281 | 301 | 502 | 329.0 |
| 2 | 290 | 294 | 419 | 351.6 |
| 7 | 180 | 400 | 520 | 357.9 |
| 42 | 337 | 345 | 403 | 349.8 |
| 1234 | 275 | 368 | 430 | 345.7 |
| 65535 | 247 | 398 | 514 | 335.9 |
| 20261007 | 226 | 385 | 510 | 341.9 |

These are development-machine startup samples excluding visual creation, not
frame-rate promises. Detailed results: `tmp/shrub_review/layout_report.json` and
`asset_manifest.json`. Native seasonal contact sheet: `seasonal_art.png`.
Tests use isolated APPDATA/LOCALAPPDATA beneath `tmp/shrub_review/`.

## Easy in-game review

1. Start a world; use **Menu → Development → DEV: Next blueberry**, **Next
   elderberry**, or **Next strawberry** to locate and inspect a plant.
2. In an eligible season, use **Harvest berries** or **Orders → Harvest plants**.
   Let a dwarf finish: the plant remains, berries disappear, and a berry crate is
   created. A second order that season is unavailable.
3. Cancel/reissue partway through work; use **Clear plant** separately to verify
   permanent removal without berries and one cutting per plant. Inspect the
   plant first to see its chance. Use a Seeds & cuttings stockpile to collect
   them. Save/load preserves quantities and removal without repeating drops.
4. Advance seasons with the existing development time controls. Check spring,
   summer, autumn and winter models, then the next eligible crop. The locator
   changes only the camera/selection; it never harvests or changes crop state.

Next: review density/readability in play, then **flowers**, followed by **lakeside
reeds**. Additional shape variants and food-economy balance remain later tuning.
