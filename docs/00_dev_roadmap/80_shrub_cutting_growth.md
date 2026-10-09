# 80 — Plant and grow berry cuttings

Status: **implemented 2026-10-08**, following mature shrub relocation in
[79](79_shrub_transplanting.md).

## Player flow

**Place → Plants** now includes three cutting entries alongside the whole
uprooted shrubs. Choose an available blueberry, elderberry or strawberry cutting,
then click suitable ground. A worker collects **one cutting**, carries it to the
site and spends three seconds planting it. A new, small shrub appears on completion.
The existing 100% cutting recovery from clearing remains unchanged.

Cuttings can come from loose crates or storage. A crate with several cuttings
supplies one unit per plant; the remainder stays at its pickup location. More
planting requests can be placed against those remaining units. Whole shrubs and
cuttings have separate catalog entries, counts and previews.

The new plants use the same dry, level 3×3 placement envelope and open-sky check
as mature transplants. Blueberries accept rock, dirt or grass; elderberries and
strawberries accept dirt or grass. Clearance is checked for the eventual mature
plant, even though the young art is smaller. The logical footprint remains one
tile and foliage has no collision shapes. Wild habitat bands do not limit planting.

## Growth and seasonal rules

Existing `stages.shrub.growth_duration_days` values are now active:

| Species | Growth days to maturity | Mature crop seasons |
|---|---:|---|
| Blueberry | 3 | Summer |
| Elderberry | 4 | Autumn |
| Wild strawberry | 3 | Spring and summer |

Each species' `wild.planting` JSON configures its cutting item, catalog key,
planting work time and seasonal growth multipliers: **spring 1.2, summer 1.0,
autumn 0.8, winter 0.0**. One growth day is one in-game day at multiplier 1.
For example, a summer blueberry takes 72 in-game hours after planting; spring
growth is faster. Winter preserves young shrubs and pauses their growth.

Growth derives from the authoritative WorldClock calendar, including fractional
days and boundaries between seasons/years. Pausing freezes it. Saving/loading
does not add time, reset age or mature plants against the previous world's clock.
There is no wall-clock/offline growth. Only young player plants are checked on
hour/season signals; their maturity queues the normal visual refresh.

Young plants have **Clear plant** and **DEV: Grow to maturity** in Object explorer,
with growth percentage and remaining growth days. They cannot yield berries or
use Move/Uproot until mature. Clearing returns one cutting; construction or loss
of support removes them without a drop. Removed plants never mature or regrow.

Maturity swaps to the normal full-size seasonal model and enables the existing
harvest, Move and Uproot rules. Fruit is available only in the species' harvest
seasons, once per eligible season. A player-grown mature bush retains its exact
identity and picked state when moved or packed for storage.

## Physical work and saves

Cutting requests share `ShrubPlantingComponent` and the existing `FETCH_BUILD`
worker flow. The pickup splits a single unit from a loose crate and redirects the
animation to that new cargo node; the remaining crate is never moved with it.
Stored withdrawals also take one unit. No cutting is consumed until the completed
planting passes its final destination check.

Cancellation before pickup preserves stock. Cancellation while carrying returns
the intact cutting at the worker's feet. An ordinary interruption retains work
on the destination plan for later resumption. Removing the plan abandons that
plan's work, without consuming a cutting or creating a plant.

`SurfaceDetailRegistry` remains the only bush-definition loader. It supplies
separate whole-plant and cutting adapters to Place. Completed planting registers
a player-created record with `SurfaceDetailManager`, using a monotonically
allocated `planted:<world_seed>:<serial>` identity. The `surface_details` save
section adds explicit planted descriptors and `next_plant_id`; individual edits
retain the planting calendar time and optional DEV growth credit alongside the
existing crop, removal and transplant fields. These records restore without a
generated candidate. Wild generation and its fingerprints are unchanged.

WorldClock's read-only `elapsed_days()` and `seasonal_days_between()` APIs supply
calendar calculations. Saving reads the existing state; it does not tick growth,
release workers, move items or change visual stage.

## Art and testing

`tools/generate_young_shrubs.py` creates **12 seasonal young models** at
`assets/models/flora/bushes/{species}/{species}_young_{season}.glb`. All use the
same baked 0.125 voxel scale, root scale 1, ground Y0 and linear vertex colors.
Blueberries have short branching shoots, elderberries taller open stems, and
strawberries a small rooted rosette. Spring growth, summer foliage, autumn color
and dormant winter stems are distinct; none has fruit. These supersede the
previous single-season young-model references. Three new catalog thumbnails use
the actual summer meshes.

For a quick playtest:

1. Clear a berry shrub to obtain its guaranteed cutting.
2. Open **Place → Plants**, select that species' cutting and place it on open ground.
3. Let a worker plant it, then select the young shrub to see growth progress.
4. Use **DEV: Grow to maturity** on that plant to avoid waiting several game days.
   This changes only the selected plant's growth credit, not the calendar or crops
   elsewhere. Out-of-season plants still have no harvest action.
5. Harvest in its eligible season, then Move it to verify its crop remains picked.

`ShrubCuttingTest` passes with real worker pickup, split-stack handling, crate
position preservation, multiple pending requests, cancellation before/after
pickup, interruption/resume, one-unit stored withdrawal, all three species,
fractional-day growth, pause, winter/year rollover, spring rates, natural maturity,
harvest/Move, young clearing and fresh-owner restoration. Native input checks
exercise the cutting catalog tile and DEV growth button, and verify that the DEV
action leaves the calendar unchanged.

`SaveManagerRoundTripTest` passes manual save, autosave and corrupt-primary backup
recovery with young, mature, cleared and packed player-grown shrubs plus an
unfinished cutting plan. Complete owner snapshots and terrain fingerprints match.
`ShrubTransplantTest`, `ShrubPilotTest`, `ProduceCrateTest`, `FurniturePlaceTest`
and `ColonyInventoryTest` pass as regressions.

Native captures under `tmp/cutting_review/` include `young_inspector.png`,
`place_cuttings.png` and `young_art.png`, all visually reviewed. Run the native
test with `--script res://scripts/tests/ShrubCuttingTest.gd -- --capture`, and the
art sheet with `--script res://tools/ShrubArtReview.gd -- --young`. Use isolated
APPDATA/LOCALAPPDATA below that review directory.

Farm plots, other crops, food processing, and the required seasonal flower/honey
connection remain separate milestones. This does not implement those systems.
