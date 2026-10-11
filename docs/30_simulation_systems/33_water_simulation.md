# 33 — Water, Rivers & Flooding

Status: **Water simulation, river generation, voxel presentation and soil moisture
implemented 2026-10-10.** Physical brewing-water hauling and production remain
planned. This supersedes the earlier permanent-water-block and no-flood rules.

## Current implementation

Duck navigation reads live water levels and excludes unsafe waterfall approaches
and cave water. Ducks do not add/extract volume, irrigate soil or change terrain;
their wakes/splashes are cosmetic. See [45 — Wildlife](../40_economy_colony/45_wildlife.md)
for swimming, shore access, drainage escape and flights.

`WorldGenerator` loads `data/world_gen/water.json` and carves a guaranteed downhill
river from a high rock face to the main lake, after validating the macro shelves
and before placing caves. The Y115 summit and bedrock stay protected. Channels
vary with the seed and include collection pools, quiet reaches and cascades.
Normal reaches have a two-cell carving radius (about five voxels across), with
short one-cell-radius narrows and a small spring mouth. Pools remain wider.
The first four cells outside the cave continue its three-cell stream straight
ahead before joining the seeded bends. The cliff lip has real air clearance
across that opening; dry ledges cannot pinch the outlet with an immediate turn.
Existing optional tarn basins remain finite stores; they are not required sources.
River beds also account for the actual dry perimeter after cliff detailing,
carrying lower cuts downstream to retain banks and downhill exits.

`WaterManager` seeds finite volume once, then uses `WaterFlow` to exchange integer
millionths of a block cubed between solid-separated vertical spaces. Open basins
rise, equalize and spill at terrain sills. Mining can connect surface water to
underground pools. Solid placement retains displaced water rather than deleting it.
A bounded active queue sleeps quiet lakes; simulation time follows clock pause/speed.
Free waterfalls prefer the lowest receiving surface; they do not distribute flow
equally onto higher neighboring terraces while the lower channel is open.

The spring's wet stone adds at most 2 blocks³ per simulation second,
inside a real cave with a pool and dry access ledges. It stops at the existing
maximum discharge level. A loose dry stone rests on the lakebed at the existing
intake, replacing the decorative shoreline arch/fissure. It removes at most
8 blocks³/s, only above surface level 19
(the top of old water-block Y18), so its depth cannot empty the lake.
Both stones use the exact authored
ore-drop silhouette and scale, with turquoise wet-stone flecks and muted dry-stone
flecks. The wet stone rests on the ledge beside the pool; the dry stone sits on
the lakebed. `WaterStones` renders and inspects these two models with normal
underground lighting and slice/discovery visibility. Opaque water conceals a fully
submerged stone. Natural stones start disallowed: inspection and their water
effects continue, while colony interaction is blocked. Allow alone does not
auto-haul a placed stone. Deliberate Pack/Move/Place uses real worker jobs and
individually identified items. Packed, carried and stored stones are inactive.
Relocated wet stones supply their new base up to their top; relocated dry stones
retain the receiving surface at placement (at least their top). Removing support
settles both a placed stone and its effect. Models add no water displacement or
navigation occupancy. Extra scenario stones can use the same grant/lifecycle API;
the acquisition scenario remains future work. See [109](../00_dev_roadmap/109_loose_water_stones.md)
for artwork and [110](../00_dev_roadmap/110_item_permissions_and_water_stones.md)
for permissions, physical ownership, persistence and relocation.
The `base:terrain:water:source` key is an occupancy identity, never an inexhaustible
block. `WorldData.get_live_block` overlays current water on authoritative terrain.

Soil irrigation reaches up to three cells by Manhattan distance, with weaker
coverage farther away. Water must intersect the nearby root elevation; it cannot
irrigate through an entire rock shelf. Nearby soil wets gradually (two game hours
for full saturation) and dries over 24 game hours. The sparse analytic moisture
history is saved separately from liquid volume. No crop damage is applied.
These are initial balancing values, not final crop requirements.

Water uses opaque, fractional-height voxel surfaces and separately batched falls,
cube splashes, restrained square highlights and local water ambience. Damp soil
and a soil-only moisture overlay explain irrigation. Cave discovery, slicing,
underground lighting and the shared sound bus still apply.
Rivers, lakes and pools share one blue-green surface color and animation; depth
darkens that same color by at most 12%, instead of changing to a separate hue.
Depths below 1/16 block are conserved surface films: damp ground rather than blue
standing water, without blocking navigation/placement or producing waterfall effects.

Menu → Development → **DEV: Water** offers feature locations, spring stop/start,
a test dam/removal, a measured lake withdrawal and the moisture overlay. The dam
uses real terrain edits and survives saving. It is a developer control; ordinary
construction jobs and brewery/container hauling are separate planned systems.
`WaterManager.extract(cell, requested)` supplies measured finite withdrawals for
those future jobs; callers must handle access, transport and container ownership.

Current saves require the `water` owner (restore priority 11, after mining). Its
volume deltas, active queue, displacement, source/outlet switches, simulation time,
soil history and solid terrain edits survive JSON exactly using integer units.
Stone identity, permissions, placed state, effect location/head and packing progress
are also saved here. Physical inactive items save with their loose/cargo/storage
owners, and Move destinations with furniture plans. Validation enforces one
physical owner for each stone identity.
Water layout version 5 identifies the aligned spring outlet, real cave and wider, bank-aware terrain;
saves using the earlier river bed are rejected rather than applying incompatible deltas.
There are no migrations for older development saves. Tests and captures are in
[105 — Rivers and water](../00_dev_roadmap/105_rivers_and_water.md).

[106 — Spring caves and water edges](../00_dev_roadmap/106_spring_caves_and_water_edges.md)
records the source chamber and exposed-cave discovery; its original embedded
wet-stone blocks are superseded by the loose model in 109.
The cave reserves terrain separately from enclosed cave systems. Fractional water
interfaces are closed even below 0.002 block; steps below 1/8 block use surface
lighting, while real drops retain vertical faces. Sky access follows solid terrain,
so water cannot leave black cells by masquerading as an opaque voxel roof.

## Agreed water supply and geography

**High rock spring → stream/cascades → optional pools or tarn → lowland lake → outlet**

- Guarantee a natural spring on an upper mountain face, emerging from a visible
  crack or small cave. Its seeded position and elevation follow the terrain;
  the old Y54 tarn is not the required origin. Place it high enough to supply
  useful mountain terraces without promising gravity-fed water above the source.
- Guarantee a descending river connection to the main lake. Vary the route,
  channel widths and drops by seed. Preserve the world's voxel shelves and
  protected summit/bedrock constraints when planning the route.
- Include useful quiet stretches between waterfalls. These provide sites for
  collection points, farms, reservoirs and future workshops.
- A tarn is optional: a natural basin along the route can retain water before
  spilling over its lip. Other seeds may have several small pools and cascades.
- Springs and outlets begin as disallowed natural stones. Following milestone
  110, players may deliberately allow, pack and relocate them through dwarf work.
  Later scenarios may award additional stones without changing the water model.

## Finite storage, renewable flow

Ordinary water has finite volume. Lakes, pools, reservoirs, channels and cisterns
store water; transferring it does not create more water. Only an explicit source
adds water, at a configured, limited rate. Demand can exceed replenishment and
lower stored reserves, but the colony does not face inevitable exhaustion of a
fixed world-generation supply.

The spring's elevation defines its maximum discharge level. Submerging its mouth
with backed-up water stops further discharge until the level drops. It does not
keep creating water above its own maximum level. This still permits extensive
flooding below the spring.

The lowland lake has a dry stone on its bed with a defined retained surface level.
It drains excess above that level, rather than constantly deleting stored water.
The user chose an ore-shaped loose stone instead of a decorative shoreline opening.
Interrupting upstream supply must not cause the outlet to empty the lake below
its threshold. Water drawn by dwarves or released through a lower excavation
can still lower the lake.

Source rates, outlet capacities, elevations and storage volumes need later
balancing. Do not use matching constant source/sink rates as a substitute for
water levels and available volume.

## Channels, dams and real flooding

Water follows terrain and connected openings. Players may divert part of the
river into farm channels or storage while allowing the main course to continue.

| Terrain change | Required behavior |
|---|---|
| Block a channel | Incoming water accumulates upstream and raises the surface. |
| Water reaches a low bank | It spills over and seeks another downhill route. |
| Excavate into a reservoir | Stored water escapes through the opening and can flood excavations. |
| Build a suitable dam | A reservoir forms; the lowest spillway controls overflow. |
| Open a drainage route | Water leaves the flooded area according to available volume and elevation. |

Flooding must develop at a readable rate. Rising waterlines, stronger flow at
constrictions, wet banks and changing waterfall sound should give players time
to respond. Natural source limits must not prevent ordinary bank overflow.

Drowning, crop damage and floating goods are separate decisions. Terrain flooding
is approved; those additional consequences are not implicitly included. Pumps,
pressurized pipe networks, rainfall replenishment and drought
events are also outside the agreed first version.

Gravity and water levels drive this system. No mechanism should move water above
its supplying head without a separately designed lifting system. The old
"downward then sideways per cell" pseudocode is not a settled implementation:
the implemented conservative column-space solver is tested for backed-up water,
rising reservoirs and spillways. It does not implement a pressurized pipe network;
Stonehearth's pressure-channel implementation was not copied.

## Farming and brewing connection

The primary challenge is obtaining, storing and delivering enough water for
agriculture and alcohol production.

- Soil moisture is separate from standing-water volume. Filled ditches gradually
  hydrate nearby suitable soil over a short, visible distance; moisture fades
  gradually when the ditch dries. Larger fields can benefit from internal channels.
- Damp-soil visuals and a moisture overlay should explain coverage. Exact reach,
  crop requirements, consumption and drying rates remain balance decisions.
- Dwarves draw and transport measured water to brewing storage/workplaces. Hauling
  distance, access, source throughput and storage capacity should matter.
- Gravity cannot supply a farm or brewery above the source. Settlement elevation
  and hauling remain meaningful choices, including on the Y115 summit.
- Reconcile planned brewing recipes with water's agreed role before implementing
  production. Longbeard Ale currently lacks a water input; quantities and container
  handling are still to be designed. This agreement does not edit recipe data.

## Voxel presentation

**Live appearance pass (2026-10-10):** [107](../00_dev_roadmap/107_water_appearance.md)
uses measured transfer directions, including wet-reach equalization, to animate
sparse voxel highlights. Quiet water shimmers in place. Waterfall streaks fall
downward; foam and cube splashes stay near active lips/landings. Detail fades at
distance. This transient current field is indexed by water space (including its
floor), respects pause/speed, and never changes mass or saved solver state.

[108 — Water ambience](../00_dev_roadmap/108_water_ambience.md) adds procedurally
synthesized waterfall rush and gentler river burbling. Two bounded spatial voices
follow visible measured currents, fade with camera focus/zoom, and use the shared
Work volume/mute controls. Quiet lakes, hidden or drained water stay silent;
pause/loading stops playback. Sound generation and playback are transient.

Retain flat voxel surfaces and blocky shorelines, with readable depth, restrained
surface movement and visible changing water levels. Falling water gets separate
block-shaped splash, ripple and sparkle effects responding to actual flow.
The high spring should read as a landmark: dark rock opening, bright moving water
at the mouth, and a small splash pool where appropriate.

Use batched geometry, never a scene node per water cell. Separate water materials
or effects may be needed alongside the chunk pipeline. Normal lighting, slicing
and undiscovered-resource concealment must remain correct. Effects display the
simulation; they do not create water or determine authoritative terrain state.

## Simulation and persistence requirements

- Conserve transferred volume. Account explicitly for spring input, outlet loss,
  extraction and any later consumption; do not refill every wet cell as a source.
- Work on affected regions/bodies and active flow, not the entire world grid.
  Quiet stored water can sleep; a flowing river still requires bounded work even
  when its overall level is steady.
- Respect WorldClock pause/speed. Tick frequency, cell precision and threading
  are implementation choices requiring profiling, not locked values from the old spec.
- React to terrain edits and actual water levels independently of visible or
  streamed meshes. Audit consumers of today's immutable `waterline_map`.
- Persist authoritative water changes, source/outlet state and future stored water
  or soil moisture. Loading must not regenerate drained lakes or erase diversions.
  Update SaveManager's owner contract and validation when adding saved state.

Before shipping, verify several seeded source-to-lake routes, steady flow without
volume creation, reservoir drawdown/refill, an interrupted inflow with a retained
lake, blocked-channel bank overflow, an excavation breach, drainage, submerged
source shutoff, pause/speed behavior, and exact save/load restoration. Review the
spring, calm channels, falls and rising floodwater in the native renderer.

## Stonehearth reference reviewed

The local `P:\stonehearth` base-game source was inspected on 2026-10-10:

- `components/water/water_component.lua` models regions, volume and water height.
- `services/server/hydrology/hydrology_service.lua` responds to terrain edits and
  transfers water; `channel_manager.lua` uses level differences and cross-sections.
- `components/wet_stone/wet_stone_component.lua` explicitly adds or removes water
  at configured rates. Ordinary water bodies are separate from these generators.
- `components/growing/growing_component.lua` advances crops using timers and
  seasonal/town modifiers. No channel-based irrigation was found in this base-game
  farming implementation; old soil-moisture references are migration remnants.
- `renderers/water/water_renderer.lua` follows fractional surface height;
  `renderers/waterfall/waterfall_renderer.lua` supplies flow-responsive voxel effects.

This review informs the design; no Stonehearth code or assets were copied.

---

*Prev: [32_navigation_3d.md](./32_navigation_3d.md) | Next: [34_temperature.md](./34_temperature.md)*
