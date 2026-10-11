# 112 — Session handoff: water and wildlife, 2026-10-10

Current starting point, superseding [103 — Previous evening](103_session_handoff_2026_10_09_evening.md).
The previous handoff retains professions, equipment, camp crafting and earlier
wildlife history. This session added finished gems, save fixes, finite water,
real spring caves, water presentation/audio, movable stones and ducks. This
wrap-up changes documentation only; verification below records the implementation
runs already completed, not a new gameplay test run during documentation cleanup.

## Where we stopped

The user accepted the water features and approved ducks with flight. Ducks now
swim in small flocks, visit banks, flee danger and make short checked flights.
They have male/female voxel art, occasional quacks, wakes, landing splashes,
inspection/Follow, aerial arrivals and current-save support. Native preview,
audio capture, four-seed population and full save/backup checks passed. The user
has not yet reported a playtest of the completed duck implementation.

Start a fresh development world: the current river layout is **version 5**, and
current saves require water, permissions, stone identities and duck fields.
Older development saves require **no migration or compatibility work**, by user
decision. After first picking up this session's new WaterManager autoload, use
**Project → Reload Current Project** before Play.

## Completed work and decisions

| Area | Current result | Detail |
|---|---|---|
| Gem drops | Six finished, shiny gems made from stepped cube voxels; matching thumbnails. No Jeweller, cutting or polishing stage. Stable `_raw` IDs retain finished display names. | [104 — Gems](104_gem_drop_artwork.md) |
| Weather and saves | Weather's 64-bit RNG state saves as decimal text. Shared validation rejects empty scene state and missing/wrongly typed owner data before restoration; valid backups remain recoverable. | [20 — Save/load](20_save_load.md) |
| Hydrology | A high rock spring feeds a wider downhill river, pools, waterfalls and the main lake. Water stores are finite; optional tarns are not required sources. Blocked channels and breached reservoirs can flood. | [105 — Rivers](105_rivers_and_water.md), [33 — Water contract](../30_simulation_systems/33_water_simulation.md) |
| Spring cave and terrain | Real carved air, roof, dry access ledge and wet-stone pool replace the decorative mouth. Shared water edges close hairline gaps. Whole-world terrain startup and the reported spring-outlet gap are fixed. | [106 — Caves and edges](106_spring_caves_and_water_edges.md) |
| Water appearance | One palette for lakes/rivers, restrained depth shading, local-current glints, quiet lake shimmer and localized falling-water foam/square splashes. No fixed diagonal scrolling or repeating cone-like bands. | [107 — Appearance](107_water_appearance.md) |
| Water sound | Original procedural waterfall rush and gentler river burbling follow visible flow and camera proximity/zoom, using Work volume/mute. Still lakes stay quiet. | [108 — Ambience](108_water_ambience.md) |
| Water stones | Both use the ore-drop silhouette, loosely placed on the cave ledge/lakebed. Initial intake, rates and retained lake level are preserved. | [109 — Stone artwork](109_loose_water_stones.md) |
| Permissions and relocation | Per-item/per-stack Allow/Disallow; natural stones default disallowed but operate. Allow alone never auto-hauls a placed stone. Real Pack/Move/Place work transfers its identity and effect. | [110 — Permissions/stones](110_item_permissions_and_water_stones.md) |
| Ducks | Three seeded flocks of 2–4; swimming, shore activity and short obstacle-checked flights. Scheduled aerial opportunities bring 2–5, subject to habitat/season and a 16-duck cap. | [111 — Ducks](111_duck_wildlife.md), [45 — Wildlife](../40_economy_colony/45_wildlife.md) |

Day/night was already implemented; its outdated overview statement was corrected.
The water design was informed by inspecting local `P:\stonehearth` source;
no Stonehearth code or assets were copied. All new art follows the project's
eight-voxels-per-block approach, with baked 0.125 scale and unit roots.

## Contracts to preserve

- `WaterManager` owns finite volumes, source/drain behavior, soil moisture and
  stone identities. Rendered currents, splashes and sound do not change water
  accounting. Use live water for navigation/placement, not the initial water map.
- Untouched rivers must remain within their channels. Intentional blockage can
  flood; fixes must preserve that behavior and volume conservation. The source
  shuts off at its head limit. The initial dry stone retains lake surface Y19.
- A placed stone works while disallowed. Packing completion stops its effect;
  packed/carried/stored stones are inactive. Placement activates it at its new
  position. Support loss settles the stone and effect together. Each identity
  has one physical owner, including after interruption or save/load.
- `WaterManager.grant_stone(kind, cell, disallowed=true)` supports future extra
  stones through the same lifecycle. No extra starting pair or acquisition
  scenario has been added. The player explicitly left that scenario for later.
- `WildlifeManager` owns animal definitions, actors and saves; `WorldEventDirector`
  owns arrival schedules and pending members. Ducks read live water and check
  terrain, placed obstacles and tree canopies. They do not change water/plants or
  dwarf navigation. Wolves still hunt rabbits/deer, not ducks.
- Duck quack timing is saved behavior; playback variations use cosmetic RNG.
  Water ambience has private cosmetic randomness. Keep weather/animal RNG exact
  across JSON save/load, and keep snapshot creation observational.
- Local renderer rebuilds cannot replace the initial whole-world overview build.
  Always verify surrounding and distant terrain when changing cave visibility.

## Verification at handoff

The milestone documents retain exact harnesses, capture paths and the scope of
each pass. Earlier failed diagnostic logs remain alongside final passing runs.
Do not treat a milestone's earlier save-case count as the current total.

- Final duck checks: `tmp/duck_review/behavior.log` (`DUCK_WILDLIFE_OK`),
  `population_final.log` (`DUCK_POPULATION_OK`, seeds 42, 1234, 1675083273,
  20261010), `native.log` (`DUCK_LIVE_PREVIEW_OK`) and `audio.log`
  (`DUCK_AUDIO_PLAYBACK_OK`). Native checks cover full-world art, forest flight
  clearance, public inspection/Follow, completed landing and Work-bus PCM.
- Final full-colony save/autosave/backup run: `tmp/duck_review/save_final.log`
  reports `SAVE_MANAGER_ROUND_TRIP_OK` and **156 malformed snapshots rejected**.
  It includes mid-flight ducks and a partly entered aerial flock. Existing
  rabbit/deer/wolf behavior, audio and arrival regressions also passed.
- Latest spring fix: `tmp/water_review/spring_gap_*.log` covers nine detailed
  cave layouts, ordinary/fallback routes, four five-game-hour no-spill controls,
  sealing/reopening, real dam flooding, conservation and all 1,024 terrain tiles
  through startup, slicing, save/reload and local/global rebuilds.
- Stone/permission checks cover real hauling/packing/placement, interruption,
  stored-stack flags, exact identities, extra sources and native compact UI.
  Water appearance and ambience checks cover local/reversed flow, pause/zoom,
  hidden water, volume invariance and native lighting/audio. See 107–110.
- Gem checks cover cube topology, game-scale readability, thumbnails and actual
  sky/torch lighting. The voxel revision's targeted reruns and the earlier broader
  inventory/hauling/save tests are distinguished in 104.

## Next playtest

1. In a fresh world, use **Menu → Development → DEV: Water** to inspect the
   cave, river, falls and lake. Review distant terrain as well as close features.
   Its reversible test dam should cause flooding and resume drainage on removal.
2. Inspect a visible stone: it should start disallowed and still work. Allow,
   Pack/Move and Place should use a dwarf and preserve the exact item. A submerged
   dry stone remains concealed by opaque water and needs reachable dry access.
3. Use **DEV: Next duck**, inspect and Follow a bird near water. Watch swimming,
   bank activity and flight; approach with a dwarf to startle it. Listen nearby
   for occasional quacks and waterfall/river ambience. **DEV: Next duck arrival**
   locates members after a later flock has entered.
4. Save/load the current world during activity and confirm the colony, moved
   stones and wildlife continue. Do not use old development saves for this check.

## Remaining work

Physical water collection, hauling, storage and brewery recipe consumption remain
planned. The finite-water withdrawal API and soil moisture are foundations, not
completed farming/brewing jobs. The planned Longbeard Ale recipe still needs its
water input reconciled when production is implemented. See [42 — Farming/brewing](../40_economy_colony/42_farming_brewing.md).

Ordinary dam construction jobs, flood damage/drowning, floating goods, pumps and
pressurized pipes remain separate work. Duck hunting/loot, eggs, breeding,
domestication and seasonal departures are not implemented.

Carpenter's workbench and first specialist recipes remain the prior handoff's
recommended production follow-up; equipment upgrades are still planned. No next
implementation milestone is selected by this wrap-up. [Open issues](00_open_issues.md)
001 (original mining-face stall) remains open and 002 (dwarf/terrain overlap)
remains parked; today's water/duck work does not close them.
