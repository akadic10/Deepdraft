# Deepdraft — Agent Navigation Index

This file is the **entry point** for any AI agent working on this codebase. Read it first. It maps every design document to its purpose and tells you which file to consult before touching any system.

**Development save policy (2026-10-09, user decision):** Backward compatibility
with older development saves is not required. Do not add legacy definitions,
migrations or compatibility branches just to preserve old saves unless the user
explicitly requests them. Keep current-version save/load working; development
changes may invalidate older saves. Use current definitions when loading rather
than retaining obsolete layouts that require players to rebuild items manually.

**Latest session handoff:** [112 — Water and wildlife, 2026-10-10](docs/00_dev_roadmap/112_session_handoff_2026_10_10.md)
records finished voxel gems, weather/save validation fixes, finite rivers and real
spring caves, water appearance/audio, movable stones and permissions, and ducks
with short flights. It lists current verification, fresh-world playtest steps
and deferred work. Read the relevant system docs alongside the handoff.

**Ducks — live (2026-10-10):** [111 — Duck wildlife](docs/00_dev_roadmap/111_duck_wildlife.md)
adds seeded calm-water flocks, male/female voxel art, swimming, shore activity,
short obstacle-checked flights and scheduled aerial arrivals. Quacks/splashes
use Work audio; picking, Follow, slices, live levels and current saves are covered.
Menu → Development → DEV: Next duck locates one. Start a fresh development world;
old saves without duck fields are not migrated. Egg/breeding/domestication and
duck predation remain future work. Doc 45 owns wildlife behavior.

**Spring-fed rivers and flooding — live (2026-10-10):**
[105 — Rivers and water](docs/00_dev_roadmap/105_rivers_and_water.md) implements the
agreed high rock spring, downhill river/pools/waterfalls and protected lake outlet.
`WaterManager` owns finite water in integer millionths of a block cubed, active
flow, measured extraction, gradually wetting/drying soil, and current-save state.
Terrain edits can flood banks and excavations; submerged sources stop. Separate
voxel water meshes, square sparkles/splashes, local waterfall audio, damp soil and
a moisture overlay follow live levels. Navigation and placement use live water.
The terrace-spill fix routes free waterfalls into the lower channel, checks
detailed river banks and adds plunge pools. Films below 1/16 block look damp and
remain walkable. Normal river reaches are now about five voxels across, with
short narrows and wider pools; all water shares one palette with subtle depth
shading. [106 — Spring caves and water edges](docs/00_dev_roadmap/106_spring_caves_and_water_edges.md)
replaces the decorative spring mouth with real terrain air, a dry ledge and a
wet stone feeding a small pool. Hairline water gaps are closed and tiny
steps share surface lighting. The spring outlet stays aligned for four cells before
its first bend; rough cliff lips are opened through real cave air. Water layout
version 5 requires a fresh development world.
[107 — Water appearance](docs/00_dev_roadmap/107_water_appearance.md) replaces fixed
scrolling/bands with sparse glints following measured local currents, quiet lake
shimmer, localized fall foam/splashes and distance fading. Presentation telemetry
does not change water volumes or saves. Whole-world startup coverage is verified.
[108 — Water ambience](docs/00_dev_roadmap/108_water_ambience.md) adds procedural
waterfall rush and gentler river burbling, following visible measured currents,
camera focus/zoom and the shared Work volume/mute controls. Still lakes stay quiet.
[109 — Loose water stones](docs/00_dev_roadmap/109_loose_water_stones.md) uses the
exact ore-drop shape for both stones: turquoise flecks beside the cave pool and
muted flecks on the lakebed. The old terrain patches and shoreline arch are gone.
Source/drain positions, rates, discharge cap and retained lake level are unchanged.
[110 — Permissions and movable stones](docs/00_dev_roadmap/110_item_permissions_and_water_stones.md)
adds per-item/per-stack Allow/Disallow and real Pack/Move/Place work. Natural stones
start disallowed and keep working; Allow alone never auto-hauls placed stones.
Packed/carried/stored stones are inactive; placing restarts their effect at the
new position. Permissions, exact identities, packing progress and move plans save.
Extra stone pairs share the same lifecycle through a grant API; scenario acquisition
remains future work. Initial hydrology is unchanged. Existing development saves
without these fields are rejected, with no migration required.
Menu → Development → DEV: Water locates features and provides a reversible test dam.
Ordinary dam construction jobs and physical brewery hauling/recipes remain planned;
flood damage, drowning, floating goods, pumps and pressurized pipes are not enabled.
Reload Current Project after pulling this new autoload. Older development saves
need no migration, per the policy above. Doc 33 owns the water contract.

**Finished gem artwork — live (2026-10-10):** [104 — Gem drops](docs/00_dev_roadmap/104_gem_drop_artwork.md)
adds six stepped voxel gem models and matching inventory thumbnails. Jade, Amethyst,
Ruby, Sapphire, Emerald and Diamond are shiny and finished immediately when mined.
**User decision: no Jeweller profession/workshop or cutting/polishing stage.**
The old deferred Jeweller proposal is superseded. Stable `_raw` identifiers stay;
display names omit "Raw". Gem-only gloss respects sky access and local lights,
including carried/shelved goods. Native art/lighting, item lifecycle, inventory,
loose support and full save/backup regressions pass; see 104 for captures.
The user rejected the initial angled polygon faces: gems now use only cube
faces on the standard eight-voxels/block grid, with square highlights.

**Equipment view and promotion feedback — live (2026-10-09):** [102 — Equipment feedback](docs/00_dev_roadmap/102_equipment_view_promotion_feedback.md)
adds a shared Equipment tab to the Colony detail column and standalone inspector.
It shows the actual owned kit, thumbnail, materials and benefit, plus clearly
planned Iron saw / Iron pickaxe upgrade paths. No upgrade goods or bonuses are
invented. A short original chime plays on completed promotion, including paused
Miner appointments; requests, cancellation, demotion and restoration are silent.
Native UI at three resolutions, completion/restore checks, audio PCM/volume/mute
and existing promotion/inspector/roster/profession/work/wildlife tests pass.

**Carpenter tool promotion — live (2026-10-09):** [101 — Tool promotion](docs/00_dev_roadmap/101_tool_based_promotion.md)
requires an available crude carpentry kit. A dwarf reserves and physically picks
it up before becoming a Carpenter. The inspector shows equipped tools; inventory
counts them separately from cargo. Cancellation/sleep and changing professions
release real goods without loss. Equipped and pending promotions survive current
save/load and backup recovery. Miner keeps free promotion/default pickaxe;
Carpenter specialist workshop/recipes and other starter-tool careers remain planned.

**Profession crafting and camp furniture — live (2026-10-09):** [100 — Camp crafting](docs/00_dev_roadmap/100_profession_crafting_camp.md)
opens Craft's profession-button submenu above the dock, then the selected
profession's recipes/orders or planned preview. The old dropdown is removed;
Rudimentary contains the live Worker recipes and a Crafters button returns to
the submenu. Profession buttons wrap into two rows on compact screens.
Campfires and compact 1×1 stump stools are craftable at the crude workbench,
physically hauled and installed. Campfires center on a tile in a 3×3 placement
area and animate/light; idle dwarves use stools directly beside all four sides.
Stool occupants rest their hands in front and independently face a nearby clear
campfire, with a small head turn for off-axis fires. Rounded head/beard clearance
and separate low body/fire regions permit this spacing. Preview
gating, save/load, compact layouts and existing crafting regressions pass.

**Dwarf idle activity — live (2026-10-09):** [99 — Idle activity](docs/00_dev_roadmap/99_dwarf_idle_activity.md)
adds staggered local strolls, looking around and exclusive use of nearby wooden
chairs after work. Leisure stays interruptible and in the scheduler's available
pool. Same-level local movement, seat removal/sleep cleanup, save-safe poses,
inspection and native seated views are covered; needs and dining are separate.

**Crafting worker selection — fixed (2026-10-09):** [98 — Crafting selection](docs/00_dev_roadmap/98_crafting_worker_selection.md)
extends pickup proximity to every Worker recipe. All eligible idle dwarves are
compared at the first material, with bounded pickup/workbench route checks and
exact material reservation. Loose, stockpiled and container ingredients compete;
failed nearby routes cannot hide other workers, materials or workbenches.

**Starter profession tools — live (2026-10-09):** [97 — Starter tools](docs/00_dev_roadmap/97_starter_profession_tools.md)
adds Worker-crafted stone hoes, hunting spears, carpentry kits and stone hammers
at the crude workbench, each from one allowed log plus one Rough Stone. Physical
material trips, safe interruption, storage, save/load, Tools inventory and native
menus are covered. Profession cards show tool stock; Carpenter pickup/equipping
followed in milestone 101. Other specialist promotions remain planned.
A forged saw is a Carpenter upgrade, not its entry gate.

**Professions and Miner — live (2026-10-09):** [96 — Professions](docs/00_dev_roadmap/96_professions_and_miner.md)
adds the career map and appointment card, usable Worker/Miner changes, and planned
Farmer/Hunter/Carpenter/Stonemason/Blacksmith careers. Colony Labor opens real Work
permissions. Miners receive mining preference and levels 1–5 from completed blocks;
Workers retain normal mining. Safe release, retained XP, permission saves, native
compact layouts and gameplay/save regressions are covered in the milestone.
The agreed equipment follow-up is planned: Miner keeps its default pickaxe/free
promotion; crafted iron and later advanced-metal picks add bounded multi-voxel
mining. Selected careers will need starter tools. See the equipment sections in
[41 — Dwarves](docs/40_economy_colony/41_dwarf_agents.md) and
[43 — Mining](docs/40_economy_colony/43_mining_materials.md). Starter tools are now
craftable (97); Carpenter equipping is live (101), while equipment bonuses remain planned.

**Deer and wolf arrivals — live (2026-10-09):** [95 — Deer/wolf arrivals](docs/00_dev_roadmap/95_deer_wolf_arrivals.md)
extends shared events with 2–4 deer every 4–7 days and 1–2 wolves every 7–12
days, capped at 18 deer / 4 wolves. Full-footprint routes, separate herd homes,
prey-surplus/local-food gates and saved group progress preserve gentle balance.
Wolves settle before hunting; kills never accelerate or enlarge events.
Startup planning waits for tree occupancy. **DEV: Arrival status** covers all
species; **DEV: Next deer arrival / Next wolf arrival** locates new entrants.
Four-seed routes, mixed save/backup restoration and wildlife regressions pass.

**Rabbit arrival events — live (2026-10-09):** [94 — Rabbit arrivals](docs/00_dev_roadmap/94_rabbit_arrival_events.md)
adds the shared WorldEventDirector scene owner and rabbit provider: scheduled
1–4-member opportunities every 2–4 days, validated edge-to-inland routes,
staggered entry, population caps and expiry. Kills never accelerate or enlarge
arrivals. Saved local hunting pressure is wired for future player hunting;
predation does not add it. Mid-group/mid-stride saves, backup restoration,
four-seed routes, native inspection/Follow and wildlife regressions pass.
**DEV: Arrival status / Next arrival** reviews opportunities and entered rabbits.
Deer/wolf support followed in milestone 95; visitor/raid providers remain future work.

**Rabbit wildlife — live (2026-10-09):** [90 — Rabbit wildlife](docs/00_dev_roadmap/90_rabbit_wildlife.md)
adds seeded rabbits, gentle grazing and sleep, dwarf avoidance, voxel animation,
shared inspection/Follow and persistence. **Menu → Development → DEV: Next rabbit**
locates one. Behavior, native picking/art and full save/backup checks pass.
[45 — Wildlife](docs/40_economy_colony/45_wildlife.md) records ownership, tuning
and deferred berries and farm theft.

[91 — Rabbit audio](docs/00_dev_roadmap/91_rabbit_audio.md) adds three quiet
selection and three grazing variations using the existing Work audio bus/pool.
Click cooldown, nearby/zoom attenuation, pause-aware eating, slice/source cleanup
and native PCM checks pass; audio never changes wildlife needs, RNG or saves.

**Deer wildlife — live (2026-10-09):** [92 — Deer wildlife](docs/00_dev_roadmap/92_deer_wildlife.md)
adds up to eighteen deer in six loose groups, articulated grazing/rest/walking,
faster escape and quiet selection/eating sounds. **DEV: Next deer** locates one.
Shared GrazerAgent preserves rabbit behavior; species-specific navigation uses
the full deer footprint. Herd identity and mixed populations persist in current
saves. Native, behavior, audio and save checks pass.

**Wolves — live (2026-10-09):** [93 — Wolf wildlife](docs/00_dev_roadmap/93_wolf_wildlife.md)
adds four sparse predators with hunger-gated, bounded hunts, prey escape,
atomic captures, long meal satisfaction and protected prey reserves. Wolves
avoid dwarves. Art, soft selection/eating sounds, inspection and saved pursuits
are included. **DEV: Next wolf** locates one. Behavior,
four-seed population, native, audio, save/backup and grazer regression checks pass.

**Previous session handoff:** [103 — Evening 2026-10-09](docs/00_dev_roadmap/103_session_handoff_2026_10_09_evening.md)
records wildlife/arrivals, professions, starter tools, crafting selection, camp
furniture/leisure, physical Carpenter promotion and Equipment/promotion feedback.
Its recommended next milestone was Carpenter's workbench and first specialist
recipes; promotion is live but specialist production and tool upgrades are not.
It preserves naming/save decisions, final verification and outstanding work.
[89 — Earlier handoff](docs/00_dev_roadmap/89_session_handoff_2026_10_09.md) retains
the world, caves, plants and ladder history. Read the relevant system docs as well.

**Seeded world layout — live (2026-10-07):** [66 — Seeded world layout](docs/00_dev_roadmap/66_seeded_world_layout.md)
replaces fixed compass geography with seeded ridges, a guaranteed ≥32×32 Y115
summit, substantial mountains, one lowland lake and an optional tarn. Players
choose and clear their own location: no starting plateau or tree exclusion is
generated. All natural cliffs and shores receive rough ledges; summit interiors
stay intact. Full column checks, gameplay,
rendering and save/load verification are recorded there. The user confirmed no
existing saves: no legacy generator or migration path is retained.

**World diagnostics and tin (2026-10-07):** [67 — World generation diagnostics](docs/00_dev_roadmap/67_world_generation_diagnostics.md)
records the actual-block surface census, current layout debug measurements, and
tin's 0.66 → 0.64 threshold correction. Four-seed before/after resource samples,
eight-seed gameplay checks and a native debug capture pass. Broader resource
balance remains a separate decision.

**Caves and discovery (2026-10-07):** [68 — Caves and discovery](docs/00_dev_roadmap/68_caves_and_discovery.md)
adds connected dry chambers, existing exposed veins and occasional floor-soil
patches. Mining into a cave reveals its connected system; ordinary slicing keeps
it concealed. **Menu → Development → DEV: Cave explorer** provides outlines,
camera/slice focus and temporary interior lighting without changing discovery.
The document records playtest steps, verification and deferred cave content.

**Resource review (2026-10-08):** [69 — Resource distribution review](docs/00_dev_roadmap/69_resource_distribution_review.md)
records resource measurements with caves, full-resolution deep-gem counts and
the diamond threshold correction (0.90 → 0.91) that restores emerald at Y5–12.
Eight-seed checks pass. Large connected metal deposits motivated the subsequent
prototype and integration passes below; this audit preserved ore noise, depth
bands and temporary testing drop rates.
The user deferred the additional manual cave checks to proceed with this review.

**Ore shape prototypes — offline only (2026-10-08):** [70 — Ore vein prototypes](docs/00_dev_roadmap/70_ore_vein_prototypes.md)
compares current deposits, a finer shared field, and separate metal fields with
broader coal on the same eight seeds. Separate fields were the recommended
direction for smaller metal patches, with gold/tin abundance flagged for review.
Tools and measured sections are available for comparison. Live generation,
resource rules and drops were not changed by this prototype study.

**Independent ore fields — live (2026-10-08):** [71 — Independent ore fields](docs/00_dev_roadmap/71_independent_ore_fields.md)
integrates smaller separate metal patches with broad coal. All field settings
and fitted cutoffs live in BlockRegistry's `block_resources.json`; gem/soil
selection, depths, drops and terrain shape remain unchanged. Eight seeds set
the cutoffs and eight additional seeds check abundance. This supersedes the
shared-metal-field tuning rules above; final economy balance remains open.

**Surface details — stones and seasonal plants live (2026-10-08):** [72 — Surface details plan](docs/00_dev_roadmap/72_surface_details_plan.md)
records the numbered asset, placement, clearing and verification sequence for
boulders, scree, shrubs, flowers and lakeside reeds. [73 — Boulder pilot](docs/00_dev_roadmap/73_boulder_pilot.md)
implements three boulder variants, deterministic placement, worker clearing and
persistent removal. **Menu → Development → DEV: Next boulder** locates one for
review. Eight-seed layout, clearing, forestry regression and save/load checks pass.
**Orders → Clear stones** supports boulders and gatherable scree with click/rectangle
designation and live counts; Cancel orders, Undo and View order keep partial work.
[74 — Gatherable scree](docs/00_dev_roadmap/74_gatherable_scree.md) adds three low,
walkable clumps at cliff bases. Three seconds of hand gathering yields one rough
stone, with persistent removal and automatic construction/support displacement.
**DEV: Next scree** locates examples. Worker, eight-seed, Orders and save checks pass.
[75 — Seasonal wild shrubs](docs/00_dev_roadmap/75_seasonal_shrubs.md) adds blueberry,
elderberry and wild strawberry with four-season voxel art, picked-crop variants,
deterministic habitats and nonblocking single-tile support. **Harvest plants**
keeps plants for one crop per eligible season; **Clear shrubs** permanently removes
them and yields one cutting (100% for all three species, configured in JSON).
Cutting growth subsequently shipped in milestone 80 below. Separate partial work, harvested cycles and removals persist.
**DEV: Next blueberry / elderberry / strawberry** locates examples. Worker, native
Orders, eight-seed and full save/load checks pass.
[76 — Seasonal wildflowers](docs/00_dev_roadmap/76_seasonal_wildflowers.md) adds three
small clump variants with four seasonal appearances and deterministic grassy
habitats. **Clear plants** now covers shrubs and flowers; flower clearing takes
1.5 seconds, yields no items and persists through seasons/load. Building and
support loss also remove flowers. **DEV: Next flowers** locates examples.
Worker, mixed Orders, eight-seed and full save/load checks pass.
[77 — Seasonal reeds](docs/00_dev_roadmap/77_seasonal_reeds.md) adds short/tall clumps
with four-season voxel art on dry lake/tarn banks near the actual local waterline.
**Clear plants** includes reeds: 1.5-second hand clearing, no yield, persistent
removal and partial work. **DEV: Next reeds** locates examples. Native lake/tarn,
worker, mixed Orders, eight-seed, regression and full save/load checks pass.
[78 — Combined surface-detail review](docs/00_dev_roadmap/78_surface_detail_review.md)
records twelve-seed placement/persistence checks and four-seed native comparisons
against worlds with details disabled. Current density and art scales are retained.
Seasonal refresh enqueue work drops from about 9.8 to 3.2 ms with the same plant
identities and pending order. Broader season-rebuild spikes, also present with
details disabled, remain documented performance follow-up. This completes the
five-category surface-detail plan; larger populations need a fresh review.
[79 — Move and uproot mature shrubs](docs/00_dev_roadmap/79_shrub_transplanting.md)
adds inspector **Move / Uproot** and **Place → Plants** for the three mature berry
shrubs. Exact plant identity, crop state, seasonal packed art and unfinished work
survive carrying, storage and save/load. Moving grants no fruit or cutting;
Clear plants still yields its guaranteed cutting. Native worker/UI, storage,
inventory and complete save/backup checks pass.
[80 — Shrub cutting growth](docs/00_dev_roadmap/80_shrub_cutting_growth.md):
**Place → Plants** consumes one cutting per young shrub;
JSON defines 3/4/3 growth days and seasonal rates, with winter dormancy. Twelve
young seasonal GLBs, saved player-created identities and **DEV: Grow to maturity**
are live. Native worker/UI, split-crate, storage, seasonal growth and full
save/backup checks pass. Farm plots and honey remain later milestones.
[81 — Surface worker selection](docs/00_dev_roadmap/81_surface_worker_selection.md)
fixes distant idle dwarves winning shrub, tree and surface-clearing jobs by queue
order. New work compares eligible idle workers at reachable adjacent work cells,
with resumable ranking/probes, priorities and existing assignments preserved.
Multi-worker and hauling/planting/crafting/mining regressions pass.
[82 — Shrub Move handoff](docs/00_dev_roadmap/82_shrub_move_handoff.md) closes the
remaining gap between uprooting and the separate pickup/carry/replant lease.
An available uprooter already beside the packed plant continues the Move;
reachable nearby replacements handle interruption or unavailability. Two-worker
full-Move, equal-distance, budget, cancellation and blocked-route checks pass.
[83 — Shrub planting animation](docs/00_dev_roadmap/83_shrub_planting_animation.md)
replaces stationary planting work followed by set-down with one immediate
reach/lower/release action. Mature shrubs take 1.25 seconds, configured in JSON;
cuttings retain three seconds with continuous animation. Native captures and
timing, interruption, planting, hauling, furniture and crafting checks pass.
[84 — Juniper berry harvesting](docs/00_dev_roadmap/84_juniper_berry_harvesting.md)
adds one autumn crop from standing mature/ancient junipers (2/4 berries; three
seconds, all in JSON). Inspector and Harvest plants support picking, with mixed
shrub/tree rectangles, cancellation and Undo. Saved crop cycles, separate work,
eight berry-free GLBs and nearby-worker selection pass focused/native/save tests.
[85 — Plant habitats, spacing and flower relocation](docs/00_dev_roadmap/85_plant_habitats_spacing_flowers.md)
restricts wild berries to soil below Y44, allows cultivation on soil at any height,
and reserves nonoverlapping 3×3 areas for bushes, flowers and pending/cutting
plants. Flowers now support Move/Uproot/storage/Place with exact variant and
seasonal packed art. JSON bloom seasons and planted-clump queries prepare the
future honey connection; native, eight-seed and full save checks are recorded.
[86 — Rudimentary ladders](docs/00_dev_roadmap/86_rudimentary_ladders.md)
adds Worker-crafted wooden sections at the crude workbench: one raw log per
exactly four blocks of height, with no extra top cap. Place → Access previews
the full route/cost; workers
carry and install from below. Explicit rung navigation supports climbing and
hauling, safe interruption, section recovery, and saved partial construction.
The document records native, gameplay, storage, UI and save/backup checks.
The player confirmed the final ladder correction and a staircase made by mining.

[87 — Placement over storage hauling](docs/00_dev_roadmap/87_placement_over_storage_hauling.md)
keeps owned furniture available in Place while reserved for storage or being
hauled. Confirmed placement takes priority; a dwarf already carrying the packed
item continues directly to installation. Paused UI, ownership, cancellation,
storage relocation, plant/ladder regressions and save checks are recorded there.

[88 — Ladder task reachability](docs/00_dev_roadmap/88_ladder_task_reachability.md)
fixes tall ladder routes passing DEV Walk but failing mining assignment. Shared
reachability searches resume within scheduler budgets; unfinished searches do
not trigger unreachable backoff. The follow-up handles isolated natural cliff
shelves by searching all exact mining stands and handing the proven route to
the worker. The reported seed's 32-block zone now completes automatically.
Native climbing/mining, route invalidation,
worker-selection, hauling, placement and save checks are recorded there.

**Required later connection:** wildflowers must support honey production through
nearby seasonal forage; beekeeping must account for bloom state and clearing.
The proposed design and unresolved tuning are recorded in [42 — Beehives](docs/40_economy_colony/42_farming_brewing.md#required-future-connection-wildflower-forage).
This honey connection is not implemented yet.
Resource placement remains depth-based for now, as agreed with the user.

**Worker crafting (2026-10-07):** [64 — Worker crafting](docs/00_dev_roadmap/64_worker_crafting.md)
records the timber → crude workbench/stump → wooden torch loop, Craft menu,
batch/maintain orders, Pine-default wood choices, four-side access and axe sounds.
First benches are crafted at the timber pickup spot; inspector destinations use
the actual work position. Physical cargo and partial work survive interruptions/load.

**Loose items and explorer correction (2026-10-07):** [63 — Loose item support and explorer](docs/00_dev_roadmap/63_loose_item_support_and_explorer.md)
records settling after mining removes support, repair of hovering loose goods on
load, safe pickup interruption, and the shared cabinet styling for Object explorer.

**Entrance lighting follow-up (2026-10-07):** [24 — World rendering](docs/20_player_interface/24_world_rendering.md)
records the longer entrance fade and actor lighting across solid cells. Movement
clipping is separately parked as [Issue 002](docs/00_dev_roadmap/00_open_issues.md).

**Storage follow-up (2026-10-06):** [59 — Storage filters](docs/00_dev_roadmap/59_storage_filters.md)
records the shared storage inspector, exact/category rules, relocation ownership,
save compatibility, and runtime/native UI verification.

**Hauling follow-up (2026-10-06):** [60 — Hauling worker selection](docs/00_dev_roadmap/60_hauling_worker_selection.md)
fixes newly idle cutters losing nearby lumber to older idle entries or returning
haulers that bypassed worker selection after depositing.

**Colony overview follow-up (2026-10-06):** [61 — Colony overview](docs/00_dev_roadmap/61_colony_overview.md)
combines the compact dwarf roster and shared personal details in one window.

**Separate zones navigation (2026-10-06):** [53 — Navigation](docs/00_dev_roadmap/53_hearth_iron_navigation.md)
records the navigation foundation, dedicated Rooms button, Orders/Zones split and
lower active-tool banner.

**Tunnel lighting (2026-10-06):** [24 — World rendering](docs/20_player_interface/24_world_rendering.md)
records live roof-aware skylight, placed lights, entity shading, slice invariance,
door occlusion and the accepted fog/darkness correction, with native/save-load
verification. Visibility only; dwarf work is unchanged.

---

## Project Identity

| Field | Value |
|---|---|
| Engine | Godot 4.x |
| Language | GDScript |
| Genre | Subterranean colony-builder RTS |
| Core loop | Dig → Brew → Trade |
| Perspective | Top-down RTS only (no WASD direct control) |
| Godot install path | `S:\STEAM\steamapps\common\Godot Engine` |

---

## Document Map

### 📁 Core Foundation — `docs/10_core_foundation/`

| File | Read before you… |
|---|---|
| [`11_overview.md`](docs/10_core_foundation/11_overview.md) | Start any work at all. Contains the invariant design boundaries. |
| [`12_world_grid.md`](docs/10_core_foundation/12_world_grid.md) | Touch block storage, chunk loading, JSON static data registries, registry lookups, or save files. |
| [`13_architecture.md`](docs/10_core_foundation/13_architecture.md) | Add or modify Autoloads, Autoload registration, boot sequence, JSON file-loading systems, or serialisation logic. |

### 📁 Player Interface — `docs/20_player_interface/`

| File | Read before you… |
|---|---|
| [`21_camera.md`](docs/20_player_interface/21_camera.md) | Work on the camera rig, orbital controls, or layer slicing. |
| [`22_mouse_input.md`](docs/20_player_interface/22_mouse_input.md) | Implement raycasting, voxel selection, or drag-to-select. |
| [`23_user_interface.md`](docs/20_player_interface/23_user_interface.md) | Build or modify any UI panel, counter, toast, or labor window. |
| [`24_world_rendering.md`](docs/20_player_interface/24_world_rendering.md) | Work on fog, sky, atmosphere, world-edge treatment, or the slice view's visual behaviour. |

### 📁 Simulation & Systems — `docs/30_simulation_systems/`

| File | Read before you… |
|---|---|
| [`31_task_system.md`](docs/30_simulation_systems/31_task_system.md) | Add task types, change priorities, or modify the worker polling loop. |
| [`32_navigation_3d.md`](docs/30_simulation_systems/32_navigation_3d.md) | Modify pathfinding, walkability rules, or step-assist logic. |
| [`33_water_simulation.md`](docs/30_simulation_systems/33_water_simulation.md) | Touch springs, rivers, water volume/levels, flooding, irrigation or water rendering. |
| [`34_temperature.md`](docs/30_simulation_systems/34_temperature.md) | Work on room sealing, heat sources, the aging cellar temperature check, or food preservation. |

### 📁 Economy & Colony Content — `docs/40_economy_colony/`

| File | Read before you… |
|---|---|
| [`41_dwarf_agents.md`](docs/40_economy_colony/41_dwarf_agents.md) | Work on dwarf stats, needs, state machine, or skill system. |
| [`42_farming_brewing.md`](docs/40_economy_colony/42_farming_brewing.md) | Add crops, recipes, farm logic, or plant visual meshes. |
| [`43_mining_materials.md`](docs/40_economy_colony/43_mining_materials.md) | Add block types, change noise generation, or touch collapse logic. |
| [`44_crafting_workshops.md`](docs/40_economy_colony/44_crafting_workshops.md) | Work on the Smelter or Forge workshops, Blacksmith/Weaponsmith/Armorsmith professions, metalworking recipes, or ingot stockpile logic. |
| [`45_wildlife.md`](docs/40_economy_colony/45_wildlife.md) | Work on rabbits/deer/wolves/ducks, wildlife needs, ground/swim/flight navigation, flocks, hunting, spawning, inspection or future food connections. |

### 📁 World Events — `docs/50_world_events/`

| File | Read before you… |
|---|---|
| [`51_visitors.md`](docs/50_world_events/51_visitors.md) | Work on live wildlife arrival events and `WorldEventDirector`, or planned merchants, travelers, invaders, taverns and combat triggers. |
| [`52_combat_military.md`](docs/50_world_events/52_combat_military.md) | Work on military professions, the Armory room, enlistment/arming flow, patrol routes, invader waves, or combat resolution. |

### 📁 Asset Creation — `docs/60_asset_creation/`

| File | Read before you… |
|---|---|
| [`61_voxel_art_guide.md`](docs/60_asset_creation/61_voxel_art_guide.md) | Author or review any GLB asset — trees, bushes, cave flora, farm crops, furniture, workshop props, or world decoratives. Contains the master colour palette, MagicaVoxel scale rules, per-asset bounding boxes, naming conventions, and the Dwarven fantasy aesthetic brief. |
| [`62_furniture_catalog.md`](docs/60_asset_creation/62_furniture_catalog.md) | Plan a furniture or decoration milestone, or pick the next asset batch. Full Deepdraft furniture inventory (status per piece) compared against Stonehearth's catalogue (enumerated from source 2026-07-11), with the variant strategy and archetype gap list. |


---

## Session Start Protocol

> **On every new session, read ALL files listed in the Document Map below using the `Read` tool before performing any work. Do not rely on shell directory listings to discover files — use the paths listed here directly.**

---

## Hard Rules (Never Violate)

These constraints appear in individual documents but are listed here for quick reference:

1. **Bedrock Protocol**: Never allow any action to modify or mine `Y = 0`. (`12_world_grid.md`)
2. **RTS-only camera**: No first-person, no WASD direct control. (`11_overview.md`)
3. **Block ID format**: Save files store namespaced strings, never runtime integers. (`12_world_grid.md`, `13_architecture.md`)
4. **3-block dwarf nav clearance**: Dwarf pathfinding requires 3 empty air blocks above every floor node. (`32_navigation_3d.md`) Wildlife uses separate species clearance; never relax dwarf NavGrid for animals. (`45_wildlife.md`)
5. **Single-tile plant footprint**: Plant visual overhangs must never have collision shapes. (`42_farming_brewing.md`)
6. **Visual vs logical dwarf height**: Use 3-block logical height for nav/collision, not the 3.3-block visual mesh. (`41_dwarf_agents.md`)
7. **No 3D UI elements**: All UI lives on a `CanvasLayer`. (`23_user_interface.md`)
8. **Deterministic world generation**: Generation must be fully deterministic from `world_seed`; use position-derived hashes or seeded noise, never `randi()` / `randf()` for streamed terrain identity. (`43_mining_materials.md`)
9. **Terrain identity lives in data**: Block identity must come from generated block data and JSON registries, not renderer tricks, fog, camera distance, or painted heightmaps. (`24_world_rendering.md`, `43_mining_materials.md`)
10. **Scene Decoupling Contract (recommended default)**: Prefer `@export` variables for scene references and signals for cross-node communication over explicit node paths (`$Node` / `get_node()`). The agent MAY now create and edit `.tscn` files and register autoloads / set the main scene / register `[input]` actions in `project.godot` — but keep logic scene-agnostic by default and only hardcode node paths when there is a clear reason. Never edit `.tres` or `.import` files. (`13_architecture.md`, File Ownership Rules)
11. **Slice concealment**: The normal slice view must never reveal undiscovered resources. Plane-cut floors render authored strata only; mining into a cave reveals its connected air and facing resources. The explicitly requested DEV Cave explorer is a temporary inspection exception, never saved discovery. (`24_world_rendering.md`, `43_mining_materials.md`, roadmap `68_caves_and_discovery.md`)
12. **Releasing a task is always cheap and always legal**: No task type may be designed such that abandoning it mid-way corrupts state. Release returns the task to PENDING, frees reservations, and never loses source-level progress; a future carried item is dropped at the dwarf's feet. (`16_first_dwarf_milestone.md` §2.8, `31_task_system.md`)

---

## Godot Project Structure (expected)

```
DwarfVoxel/
├── AGENT.md                  ← you are here
├── docs/
│   ├── 10_core_foundation/
│   │   ├── 11_overview.md
│   │   ├── 12_world_grid.md
│   │   └── 13_architecture.md
│   ├── 20_player_interface/
│   │   ├── 21_camera.md
│   │   ├── 22_mouse_input.md
│   │   ├── 23_user_interface.md
│   │   └── 24_world_rendering.md
│   ├── 30_simulation_systems/
│   │   ├── 31_task_system.md
│   │   ├── 32_navigation_3d.md
│   │   ├── 33_water_simulation.md
│   │   └── 34_temperature.md
│   ├── 40_economy_colony/
│   │   ├── 41_dwarf_agents.md
│   │   ├── 42_farming_brewing.md
│   │   ├── 43_mining_materials.md
│   │   └── 44_crafting_workshops.md
│   └── 50_world_events/
│       ├── 51_visitors.md
│       └── 52_combat_military.md
├── project.godot             ← agent may edit [autoload], main scene, and [input] only; leave other config to human
├── data/                     ← agent-owned JSON definitions
│   ├── biome/
│   ├── entities/
│   ├── furniture/
│   ├── professions/
│   ├── terrain/
│   ├── visitors/
│   ├── workshops/
│   └── world_gen/
├── scripts/                  ← agent-owned GDScript
│   ├── registries/           ← registry autoloads (BlockRegistry, PlacedEntityRegistry,
│   │                            DwarfAssets, UIRegistry)
│   ├── systems/              ← simulation autoloads (WorldClock, WorldData, WorldGenerator,
│   │                            NavGrid, TaskManager, InteriorTracker, RoomManager,
│   │                            SkyController, WeatherManager) + scene-node systems
│   │                            (WorldRenderer, Camera, SliceController,
│   │                            MiningDesignationController, FurniturePlacementController,
│   │                            FlagPlacementController, SurfaceFloraSpawner, ItemDropManager…)
│   │                            — authoritative autoload list + load order: docs/10_core_foundation/13_architecture.md
│   ├── components/           ← reusable logic components, no autoload (MiningZoneComponent)
│   ├── entities/             ← agent scripts (DwarfAgent, DwarfFactory, DwarfDirector,
│   │                            DwarfAppearanceData)
│   └── ui/                   ← UI logic scripts (DockUI, DebugLoadingOverlay)
└── scenes/                   ← agent may create and edit scenes (git-tracked)
    ├── main/
    ├── ui/
    └── entities/
        └── resources/
```

---

## File Naming Conventions

When creating any new file, follow the convention for its type:

| File type | Convention | Examples |
|---|---|---|
| `.gd` scripts | `PascalCase` | `MiningSystem.gd`, `BlockRegistry.gd` |
| `.json` data | `snake_case` | `terrain_blocks.json`, `aging_cellar.json` |
| `.md` docs | `NN_snake_case` (numbered prefix) | `43_mining_materials.md` |
| `.glb` assets | `snake_case` | `apple_mature_autumn.glb` |

GDScript filenames must match their `class_name` declaration exactly — this is a Godot requirement, not a style choice.

---

## File Ownership Rules

### Agent MAY read and write:
- `data/**/*.json` — all static definitions and content tables
- `scripts/**/*.gd` — all GDScript logic and autoloads
- `docs/**/*.md` — design documents
- `scenes/**/*.tscn` — create and edit scenes freely (see Scene Editing Protocol below)

### Agent MAY edit, but only for specific purposes:
- `project.godot` — the `[autoload]` section (register/reorder autoloads), the main scene setting (`run/main_scene`), and the `[input]` section (register input actions for tools/hotkeys — approved 2026-06-05; first use: the Slice tool, `11_slice_xray_plan.md` Phase 2). Do not change rendering, physics, display, or other config unless explicitly asked.

### Agent MUST NEVER touch:
- Any `.tres` file
- Any `.import` file (editor-generated on asset import; hand-editing desyncs the asset)

---

## JSON vs GDScript: The Decision Rule

> **JSON = what things are. GDScript = what things do.**

| Use JSON for… | Use GDScript for… |
|---|---|
| Block definitions and stats | Block registry loader |
| Item and material definitions | Task scheduler |
| Recipe tables | Pathfinding logic |
| Dwarf trait and skill definitions | State machines |
| Biome and noise parameters | Combat resolver |
| Visitor and invader spawn tables | Water CA simulation |
| Temperature thresholds | Signal handlers and events |
| Crafting costs and unlock conditions | Runtime behavior and AI |

If a designer could edit it in a spreadsheet → **JSON**.
If it contains logic, conditionals, or runtime state → **GDScript**.

**No custom Resource instances as data stores.** All static definitions live in JSON, loaded by a registry Autoload. Never use `.tres` files to store game data.

---

## Registry Pattern (Mandatory)

All JSON loading goes through a dedicated registry Autoload. Raw JSON file I/O is never scattered across scripts.

```
scripts/registries/
└── BlockRegistry.gd     ← loads data/terrain/terrain_blocks.json
                            and data/terrain/block_resources.json
```

Workshop, recipe, flora, and visitor data is loaded by the Autoload that owns that system (e.g. `VisitorManager` loads `data/visitors/merchant_catalog.json`). No separate registry Autoload is created for these — each system owns its own data loading.

**Rule:** No script may call `FileAccess.open()` on a JSON file directly. All data access goes through the owning registry or system Autoload:

```gdscript
# Correct
var block = BlockRegistry.get("dwarf:stone_granite")

# Never do this in a non-registry script
var f = FileAccess.open("res://data/terrain/terrain_blocks.json", FileAccess.READ)
```

---

## Script-to-Scene Contract

The agent may now author scenes, but the decoupling discipline below is still the **recommended default** — it keeps logic testable and resilient to scene reorganisation. Deviate only with a clear reason.

1. **Prefer `@export` over hardcoded node paths.** Avoid `get_node("UI/HealthBar")` / `$NavigationAgent3D` in logic scripts where an `@export` reference would do.
2. **Declare node dependencies as `@export` variables** at the top of each script. The wiring can now be done by the agent directly in the scene — it is no longer a human-only step.
3. **Signals are the preferred interface** between scene structure and script logic.
4. **Keep scripts scene-agnostic** where practical — logic should not break if a script is moved in the tree.

### Scene Editing Protocol

`.tscn` is a structured text format with fragile internal references. When creating or editing a scene:

- **Read before edit.** Always read the existing `.tscn` before modifying it.
- **Preserve UIDs.** Keep existing `uid://…` ext_resource IDs and the scene's own UID intact. Scripts are referenced by the UID stored in their `.gd.uid` file.
- **Commit first.** Prefer committing pending work to git before a large scene edit, so the change lands as an isolated, revertible diff.
- **Verify it loads.** After editing, sanity-check that every referenced resource path/UID exists and that node and `[connection]` blocks are well-formed.

```gdscript
# Correct — human wires this in the editor
@export var health_bar: ProgressBar
@export var nav_agent: NavigationAgent3D

# Never do this
func _ready():
    var health_bar = get_node("UI/HealthBar")
```

### Playtest Handoff Note

Godot caches global script classes. After any work session that **adds a new `class_name`
script or registers an autoload**, tell the human to run **Project → Reload Current
Project** before playtesting — a stale cache half-loads the changes and produces ghost
bugs (first hit: doc 16 autoloads; second: doc 19 Phase 3, where pending tasks were
silently never assigned until the reload). Sessions that only edit existing scripts don't
need it.
