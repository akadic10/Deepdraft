# 223 — Full 1:16 voxel visual migration plan

**2026-10-18 — requested plan; production conversion has not started.**

**Execution authorized later the same day:** the player requested full migration
while away, including each family's variants/tests and saved checkpoints.
[224 — Execution checkpoints](224_voxel_migration_progress.md) records completed
phases 0–8, all 403 models and final validation/performance evidence.
The original planning status and sequence below are retained for context.

The player likes the detailed voxel pilot and its coarse shadow proxies and now
wants a plan to convert the complete visual roster, including growth stages,
seasons, dwarves and furniture. This plan extends the approved examples in
[221](221_micro_voxel_art_study.md) and [222](222_voxel_shadow_proxies.md) into a
complete production migration. Those studies are the visual reference.

The intended result is a playable Deepdraft with consistent **1:16 authored solid
art, greedy visual meshes and separate cheap shadow casters**, including the
models shown in catalogues and portraits. The existing editable world remains
on its world-block grid. This is a visual migration: identifiers, saves,
navigation, occupancy, recipes, growth rules and worker behavior retain their
current meaning.

## Scope and verified inventory

The [baseline inventory](concepts/223_voxel_migration_plan/inventory.json) records
every existing production GLB's path, hash, bytes, triangle count, named nodes
and direct gameplay-JSON references, plus the defined flora states. It excludes
the 18 study GLBs, which remain comparison references.

| Family | Existing GLB files | Coverage required |
|---|---:|---|
| Trees | 94 | Pine 14, oak 28, apple 34, juniper 18; all stages, positional variants, seasons, fruit and picked states |
| Surface plants | 76 | Blueberry 14, elderberry 14, strawberry 16, flowers 24, reeds 8; young/mature, seasonal, picked and packed forms |
| Dwarves and equipped work tools | 43 | 41 appearance parts plus axe/pickaxe; all ages, hair, beards, brows and portrait scars |
| Wildlife | 21 | Rabbit 3, deer 6, wolf 5, duck 7, including sex variants and articulated parts |
| Furniture and its effects | 50 | All 33 definitions and supporting exports; installed/packed/legacy forms, ladder heights, bridge spans, fence rails and five flame libraries |
| Items | 92 | Resource drops, produce crates, seeds/cuttings, logs, ores, gems, goods and inventory tools |
| Ground rocks | 6 | Three boulders and three scree variants |
| Construction | 4 | Materials crate, stone floor, two plank-floor forms |
| **Existing production models** | **386** | File count, not number of entities or rendered mesh instances |
| Defined but missing crop models | **14** | Grapes 5, hops 4, pig tail 3, plump helmet 2 |
| **Initial asset-file scope** | **400** | Existing replacements plus the known missing art |

The 14 crop paths were already missing before this request. Author their defined
forms and show them in the review gallery. Validate live integration only where
the current game actually supports that crop; supplying models must not silently
become a farming-system implementation. Likewise, apple fruit visuals do not
authorize new apple-harvesting mechanics or automatic tree growth.

This file count is the initial coverage floor. It does not count individual flame
frames, thumbnails, runtime meshes, or dynamically constructed resource paths.
Phase 1 closes those gaps in the manifest. Assets already compatible with the
new style can be retained after inspection; every entry still needs a disposition.

Additional presentation coverage:

- Dwarf portraits, sleeping eyelids, eating servings, carried items, work tools,
  appearance changes and occlusion silhouettes.
- Furniture/item thumbnails, inventory and crafting images, placement previews,
  moving/uninstalled objects, construction ghosts and staged materials.
- Animated door/gate leaves, flags, flames, embers, work dust, duck wakes and
  other existing procedural effects.
- Constructed-floor surface appearance, respecting its terrain-chunk assembly.

Keep the existing sky, water simulation/surfaces, weather systems, terrain,
camera, UI layout, icons, typography and loading illustrations. Audit their
appearance next to the new art, but do not turn translucent effects into opaque
voxel piles or redesign the interface. Water/fire retain appropriate emission,
transparency and animation; solid objects and effect geometry get a coherent
blocky treatment. Floor blocks keep their full support volume and chunk meshing.

## Art and technical rules for every batch

1. **Match the accepted pilot.** Author readable forms in voxel space. Use broad
   tree crowns, deliberate branch clusters and selective surface detail. Preserve
   the distinctions between species, materials and growth stages. Avoid a blanket
   triangle-to-voxel conversion that merely stair-steps every old bevel.
2. **Sixteen cells per world block.** Export world-unit positions, correct local
   pivots and unit roots. Source solid geometry is grid-aligned; rigid animation
   can rotate/translate it freely. Do not snap motion or alter logical footprints.
   Resolve inherited nonuniform presentation scaling before claiming cubic cells.
3. **Bake meshes offline.** Cull internal faces and greedily merge compatible
   coplanar faces. No cube nodes, per-frame meshing or model baking when furniture
   completes construction. Load the prepared GLB through the existing owner.
4. **Pair opaque visuals and shadow proxies.** Use `VoxelVisual` and
   `VoxelShadowProxy` within each rigid component. Visual casting is Off, proxy
   Shadows Only. Start at shadow stride four with the existing coverage/span
   fallback. Preserve thin limbs, leafless branches and ground contacts; tune
   per-family proxies if automatic erosion loses an important silhouette.
5. **Use shadows where appropriate.** Flames, transparent effects, UI ghosts and
   tiny overlays may remain non-casting. Do not manufacture a proxy for every
   particle or eyelid. Record these deliberate exceptions in the manifest.
6. **Share resources.** Retain linear vertex colors, semantic CraftMaterials
   swatches, runtime dwarf tints and reusable meshes/materials. Do not create a
   material per micro-voxel. Material sharing alone does not promise one draw call.
7. **Preserve runtime structure.** Keep named hinges, attachment points and flame
   nodes, immutable imported meshes, mirrored-limb correction and existing
   animation timing. Place each visual/proxy pair inside its moving part.
8. **Preserve state identity.** Maintain seasonal array ordering, deterministic
   variant selection and saved appearance identifiers. Picked variants remove
   fruit without changing the underlying plant; packed versions preserve it
   above the root bundle. Summer fallback remains valid where already defined.
9. **Keep gameplay independent.** No canopy colliders or micro-voxel collision.
   Keep walkability, dwarf clearance, interaction surfaces, capacities, quantities,
   planting rules, yields, growth durations and save schemas intact.

## Execution sequence

### Phase 0 — Baseline and recovery

**Inventory done in this planning turn.** Before implementation, preserve a
recoverable snapshot of the current working tree, including uncommitted pilot
work and asset sources. Git HEAD alone is not the current baseline. Keep backups
outside imported asset directories and preserve unrelated user changes.

Capture matched baseline views and a representative saved settlement using
copied saves and isolated APPDATA/LOCALAPPDATA. Record current frame-time
distributions, rendering costs, object counts, memory and import/load times.
Retain an executable way to compare the old art under the same conditions.

**Exit:** reproducible baseline, copied-save fixture and recoverable family files.

### Phase 1 — Production pipeline and integration contracts

Promote the reusable work in `tools/micro_voxel_study/generate.py`,
`tools/voxel_glb.py` and `tools/voxel_shadow.py` into a family-based production
builder. Put offline authored shapes/palettes in `data/art/`; use explicit output
manifests and temporary staging until a batch passes. Keep the accepted 18 pilot
visual payloads as anchors. Do not rerun retired generators into production or
allow old faceted builders to overwrite migrated families accidentally.

Required builder operations: one family, all families, verify-only `--check`,
geometry report and coverage audit. Deterministic hashes should reproduce both
visual and proxy meshes. Record visual/shadow triangles separately, surfaces,
file size, bounds and required named nodes. Update generator ownership and art
standards as each family migrates; retain historical evidence unchanged.

Audit every mesh consumer, extending the current `VoxelShadowSetup.gd` contract:

- World loaders, seasonal replacement, carried and packed items, editor instances
  and reloaded saves configure the pair before its first rendered frame.
- DwarfPortrait and catalogue renderers either configure or omit proxies, even
  without UndergroundLighting. Cloning/material substitution preserves the roles.
- Selection bounds, outlines, ghost previews, tinting, reflection and readability
  handle proxy nodes deliberately. Add a shared visual-mesh traversal helper
  where repeated filters would otherwise diverge.
- `ConstructionFloorArt._collect()` currently collects every mesh recursively.
  Its visible chunk bake must exclude proxies. Keep floor boundary meshing and
  the existing terrain shadow path; do not add one shadow node per floor voxel.
- Preserve named `leaf_left` / other moving roots and flame names by putting
  visual/proxy siblings beneath those roots, not replacing the names with a
  flat list. Explicitly exempt non-casting flame/effect nodes.
- Dwarf current body/head width factors (.8/.93) and the wolf's nonuniform
  `visual_scale` (1.65/1.30/1.75) would stretch cubic cells. Bake their intended
  final proportions into authored grids and remove duplicate render scaling.
  Update presentation pivots/offset conversions consistently, including portraits,
  rests and all poses. Do not change navigation dimensions or behavioral reach.

**Exit:** one static asset, one dwarf pair and one hinged fixture work through
actual production loaders, thumbnails, picking and shadow toggling. No visible
proxy contribution or duplicate floor geometry; pilot appearance retained.

### Phase 2 — Complete trees

Convert **pine, oak, apple and juniper**, one species at a time, including every
sapling/mature/ancient form and variant. Use a stable wood scaffold across
seasons, species-specific foliage, bare deciduous winter forms, evergreen snow,
spring blossoms, autumn fruit and juniper picked states. Snow should read as
clusters on upper surfaces rather than uniformly recolored foliage.

Test every stage/season combination actually defined, deterministic variant
identity across season changes, felling, picking, streaming, slice hiding,
grounding, overhang clearance and saved partial work. Check winter branch proxies
particularly carefully: a sparse canopy cannot use the mature pine's dense proxy
settings blindly. Capture all seasons in the gallery and a real forest at normal
zoom, including low sun and torchlight.

**Exit:** all 94 paths covered and existing tree/season/harvest fixtures pass.

### Phase 3 — Bushes, flowers, reeds, crops and ground rocks

Complete all 76 surface-plant exports, including young cuttings, mature forms,
four-season presentation, picked berries, root wraps and packed flower mats.
Young plants must remain visibly younger; harvested plants must retain leaves
and stems. Preserve berry visibility, carried scale and planting contacts.

Author the 14 missing defined crop forms:

| Crop | Required forms |
|---|---|
| Plump helmet | Sprouting, mature; existing season fallback |
| Hops | Seedling, climbing, mature summer, mature autumn |
| Pig tail | Seedling, mature summer, mature autumn |
| Grape | Cutting, spring budding, summer fruiting, autumn harvest, winter dormant |

Convert three boulders and three scree forms with distinct silhouettes, proper
ground contact and restrained mineral variation. Retain the distinction between
blocking boulders and walkable scree.

**Exit:** all defined art resolves; shrub growth/regrowth, harvest, move, uproot,
packing, seasonal refresh, habitat selection and quantity conservation pass.
Crop art with no live gameplay owner is explicitly marked gallery/data-ready,
not described as a working farming feature.

### Phase 4 — Complete dwarf roster

Extend the accepted adult into all four ages, shared body/eyes/hands/feet,
14 hair styles, seven beards, eight brows and four portrait scars. Preserve
bald/no-beard choices, male/female appearance pools, skin/hair/eye tints and
saved identities. Do not use the study adapter's substitution of one hairstyle
for every style as the production solution.

Adapt sleeping eyelids to the authored eye positions and create voxel servings
for existing eating visuals. Preserve working/carrying grip anchors, mirrored
hands/feet, proportions, chair/bed surfaces, tools and occlusion behavior.
Render roster and portrait contact sheets under daylight and torchlight.

**Exit:** live walk, turn, climb, mine, fell, carry, construct, eat, sit and sleep
poses pass at multiple phases. Portraits and scars match the same appearance;
proxies follow parts, paired limb lighting matches, and slices hide the whole actor.

### Phase 5 — Complete wildlife

Complete rabbit, deer, wolf and duck, including male/female duck bodies, heads
and wings. Preserve species scale, palette, pivots and distinctive silhouettes.
Treat the wolf scale migration as a presentation change with matched contacts,
not a resize of its support footprint or movement rules.

**Exit:** standing, locomotion, grazing/foraging, sleep, swimming, flight and
hunting/capture behavior where implemented pass their existing fixtures. Feet,
bellies and shadows stay attached; thin antlers/ears remain readable. Population,
navigation and save identities are unchanged.

### Phase 6 — Furniture, construction, goods and tools

Convert all 33 furniture definitions and supporting exports as functional groups:

- Seating, tables, beds/bunks, game table, storage and brewing furniture.
- Workbench, anvil, smelter, trade/tavern furniture, aging rack and settlement flag.
- Torches, campfire, hearth, brazier and wet/dry stones.
- Doors/gates, fence post and connecting rails, ladder heights 1–4, bridge spans
  1–5, access kits, packed furniture and saved legacy chair forms.

Keep semantic wood palettes and all selectable material combinations. Preserve
hinges, mount heights, seating/sleep/work surfaces, access from usable sides,
storage positions, flame anchors and room sealing.

Complete all 92 loose-item exports and the two equipped work tools, including
low/half/full produce crates, species logs/seeds/cuttings, ores, gems, soil/stone,
food, drink and crafted goods. Inventory tools and equipped tools may have
different orientations; retain the correct anchor for each. Check hauled bundles,
ground rotations, storage slots and construction hand contacts.

Update staged materials crate and construction floor art. Floor top/boundary
geometry must work through the existing chunk pipeline, with neither duplicate
proxy triangles nor new per-tile nodes. Construction ghosts stay readable and
must not cast an extra proxy shadow.

**Exit:** placement, rotate/move/uninstall/reinstall, building, hauling, storage,
door motion, bridges/ladders/fences, wet/dry lifecycle, seating and sleeping pass.
Quantities, capacities, recipes, collision and room behavior remain unchanged.

### Phase 7 — Effects and every secondary view

Rebuild solid flame geometry/static first frames and the five existing animation
libraries as coherent voxel flames. Preserve emission, named nodes, frame/clip
timing, heat, light and sound. Reuse cached baked frames; do not mesh volumes each
frame. Check the flame controller's replacement meshes and shadow flags.

Review work dust, embers, wake foam and small procedural geometry. Keep them
pooled/shared and low cost; no unnecessary shadow proxies. Render fresh furniture
and item thumbnails, invalidate stale preview caches and check inspector and
profession portraits. Verify ghosts, outlines, move previews and saved legacy
presentations use the new visuals without leaking proxy geometry.

**Exit:** world, inventory, crafting, placement and portrait views agree, and
non-solid effects remain readable in daylight, night and underground rooms.

### Phase 8 — Whole-project acceptance and handoff

Run an exhaustive manifest audit: every original asset is converted or explicitly
retained with a reason; all 14 missing crop models exist; every runtime model
reference, defined state and dynamic variant resolves. No old faceted presentation
is silently left active. Separately verify that unrelated non-art data and save
semantics are unchanged. Treat intentional presentation scale updates as explicit
allowlisted changes, not a reason to weaken the gameplay audit.

Load copied existing saves and a fresh seeded world. Check all four seasons,
multiple slice heights and X-ray, dawn/noon/night, dense woodland and lit rooms.
Exercise simultaneous workers, wildlife, staged construction and physical items.
Save/reload the converted presentation and verify identities, terrain edits,
stock counts, appearances and partial tasks. Original player saves stay untouched.

Compare performance against the matched baseline: CPU/frame distributions, GPU
render time, draw calls, visible/shadow triangles, resource counts, memory and
startup/season-switch costs. Use repeated matched runs when a difference is near
noise. If a family materially worsens performance, simplify/reuse its geometry
and retest before marking it complete. Do not extrapolate the 504-object static
pilot result to the full game, or claim low-end support from the current GPU.

Deliver a normal-Play source project, reproducible family builders, completed
coverage manifest, native gallery, test/performance report and clear remaining
exceptions. Retain recovery until the full pass is accepted. No unsolicited
Windows export, publication, commit or cleanup of unrelated files.

## Verification matrix

Use existing behavior fixtures and add focused missing contracts. Historical
`*FacetedArtTest` geometry/hash assumptions need new voxel-specific equivalents;
do not disable behavior checks merely to make the new art pass.

| Area | Existing fixtures / checks to retain or extend |
|---|---|
| Mesh/export | Current 12 greedy/proxy tests; deterministic family rebuilds, palette validity, finite/nondegenerate faces, exact source grid, import quantization tolerance, named pivots, proxy containment/roles |
| Trees/season | `TreePilotTest`, `TreeFellingTest`, `JuniperHarvestTest`, `SeasonalRefreshTest` |
| Plants | `SurfaceVegetationArtTest`, `ShrubCuttingTest`, `ShrubRegrowthTest`, `ShrubTransplantTest`, `ShrubPlantingAnimationTest`, `PlantHabitatTransplantTest` |
| Dwarves | `DwarfRosterTest`, `DwarfLimbLightingTest`, `DwarfReadabilityTest`, `DwarfInspectorTest`, mining/hauling/rest/dining and slice-movement fixtures |
| Wildlife | Rabbit/deer/wolf/duck wildlife fixtures; species navigation and imported-part checks |
| Furniture/items | Material/door/seating/bedroom fixtures, `FurnitureMoveTest`, `GridFenceTest`, `LogBridgeTest`, `ProduceCrateTest`, `WaterStoneLifecycleTest`, worker crafting |
| Construction | Floor construction, staging/presentation/continuity, input, access and materials-conservation fixtures |
| Effects/UI | Flame frame/anchor test, daylight/torch captures, generated thumbnail completeness, portrait refresh, ghost/proxy exclusion |
| Whole world | `SaveManagerRoundTripTest` plus copied-save replay, terrain/discovery invariants, seasonal reload, live-settlement performance |

Each family needs: reproducible exports, complete state coverage, native import
checks, inspected close/gameplay-scale captures, relevant interaction regressions
and measured cost. An attractive gallery alone does not complete a family.

## Work checkpoints and time expectations

This is approximately 400 asset files plus integration and previews. Generators
make variants scalable, but a fully polished and validated migration should not
be promised within a few hours. Plan a sustained sequence of resumable batches.

For an initial implementation run, prioritize the production pipeline, complete
trees and surface plants, then the dwarf roster; proceed through the remaining
phases as time allows. A completed batch means its variants and tests pass, not
that only its mature summer example looks correct. Complete each family before
activating it in production, and keep the project loadable at every checkpoint.

Once execution is requested, use the accepted pilot and this plan to resolve
routine choices autonomously; family boundaries are validation checkpoints, not
repeated requests for permission. Record progress, touched paths, outstanding
failures and the next action in the roadmap after each batch. Do not silently
mark the whole migration done if time ends partway through. This planning turn
does not schedule work or start the conversion.

## Planning completion

- [x] Inspect current production roster and direct JSON state/model references.
- [x] Record 386 existing assets and 14 known missing crop models with baseline hashes.
- [x] Identify proxy, scale, floor-baking, portrait and procedural-geometry integration risks.
- [x] Define family sequence, state coverage, recovery and acceptance criteria.
- [x] Execute production conversion phases 0–8; completion and recovery in 224.
