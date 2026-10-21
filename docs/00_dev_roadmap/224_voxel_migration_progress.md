# 224 — Voxel migration execution checkpoints

**2026-10-18 — complete.** The full migration authorized in
[223](223_full_voxel_visual_migration_plan.md) is installed in normal Play:
403 production models, complete defined variants and 113 refreshed thumbnails.
Family tests, deterministic regeneration, repeated whole-world benchmarks and
both copied player saves pass. Checkpoint 9 records final costs and limitations.
Original saves are unchanged. No Windows export, commit or gameplay expansion.

## Recovery and baseline

- Recovery: `tmp/voxel_migration_20261018/recovery/workspace_before.zip` contains
  5,799 files (481,869,351 uncompressed bytes): tracked/untracked source, assets,
  documentation, current pilot work and unrelated existing VoxelFeed files.
  Generated tmp outputs, Git internals and ignored caches are excluded. Do not
  bulk-restore unrelated files; use the accompanying hashed manifest selectively.
- Original quicksave/autosave were copied to `recovery/player_saves/`; original
  paths and SHA-256 fingerprints are recorded there. Originals must remain untouched.
- Full native baseline: `tmp/settlement_art_20261013/voxel_before/`, isolated
  APPDATA and LOCALAPPDATA, 1600×1000, fixed simulation delta 60 Hz, VSync disabled.
  Existing settlement harness exercises live workers/wildlife, lights, slicing,
  terrain edits and a save round trip. Results pending at checkpoint creation.
- Initial inventory: 386 production GLBs and 14 missing defined crop models,
  recorded in 223. Production art has not yet changed at this checkpoint.

## Checkpoints

| Phase | State | Next / evidence |
|---|---|---|
| 0: baseline/recovery | Complete | Native matched settlement + save/reload passed; recovery and copies secured |
| 1: production builder/integration | Complete | 108 native consumer checks, 403-model audit and byte-identical rebuild |
| 2: 94 trees | Complete | Reproducible exports and native world/state checks; trunk close-up confirms intact step ledges |
| 3: plants/crops/rocks | Complete | All 96 installed/tested; crops explicitly art/data only; measured cost below |
| 4: dwarf roster | Complete | 43 parts + 3 presentation models, 800 appearances, live poses/lighting, full-world and copied-save checks |
| 5: wildlife | Complete | 21 parts, rigid knees/folded wings, 60 production views; geometry, live species/navigation/restore checks pass |
| 6: furniture/items/construction | Complete | All 146 exports; quantities, contacts, carrying, construction and lifecycle tests pass |
| 7: effects/secondary views | Complete | Native views plus 42 furniture/71 inventory PNGs regenerated and UI checks passed |
| 8: whole-project acceptance | Complete | 403-model audit/rebuild, both copied saves, two full native world runs and recovered-baseline comparisons pass |

## Handoff

Restart Play in the source project to review the complete migration. All families
are installed; no migration phase remains queued. The current authoring standard
is [63](../60_asset_creation/63_shared_art_standard.md), and generators/manifests
live in `tools/voxel_assets/` and `data/art/voxel_manifests/`. Keep the initial
recovery and final delta archive. Earlier checkpoints below describe intermediate
states; checkpoint 9 supersedes their pending-work notes. Do not rerun historical
faceted generators or resume unrelated gameplay/performance backlogs automatically.

### Checkpoint 0 — Recovery secured

Snapshot and original-save copies complete. Building production tools without
altering runtime files while the original-art baseline benchmark is running.

### Checkpoint 1 — Baseline and production integration

- Successful full baseline: `tmp/settlement_art_20261013/voxel_before_complete/`.
  Its report and matched close/overview captures are preserved in
  `concepts/224_voxel_migration/baseline/`. 24 dwarves, 48 furniture pieces,
  2,953 trees, live wildlife, hauling, seating, sleeping and door motion observed.
  Save/reload checks all passed, including identities, appearances, terrain,
  clock, furniture, wildlife and goods conservation. Original saves untouched.
- Earlier `voxel_before` stopped after the historical arbitrary-cliff edit;
  `voxel_before_bounded` completed all camera samples but stalled because the
  old harness disabled SaveManager processing during its asynchronous write.
  `WorldBenchmark.gd` now bounds renderer waits, enables the writer, and excludes
  that cliff loop equally before/after. Focused terrain fixtures remain required.
- `VoxelPipelineTest`: **80 checks passed** through actual item/furniture/dwarf
  consumers, animated hinges, portrait cloning, ghost/light no-casting policy,
  picking and construction floor collection. No duplicate proxy geometry in
  visible floor batches. Expected minimal-fixture sky/weather warnings only.
- Shared setup handles unique part-suffixed names: Godot uniquifies names across
  a GLB, so articulated pairs use `VoxelVisual__part` / `VoxelShadowProxy__part`
  beneath the original named pivot. Single meshes retain the pilot names.
- Production builder emits greedy meshes, adaptive inscribed shadow proxies,
  deterministic reports and staged files. Whole-family coverage is checked
  against 223; historical faceted writers reject manifest-owned production paths.
- Tree staging in `tmp/voxel_migration_20261018/staged/` is not activated.
  Approved raw pine anchor stays byte-identical; production trims its low root
  flare to the existing walkable footprint. Early oak gallery inspected; all
  seasons share scaffold/identity. Sparse winter shadow fallback needs tuning.
- Next: finish tree cost/geometry checks, all 94 native gallery/import/state tests,
  activate only the complete passing family, run live regression/performance and
  save the family checkpoint. Other families remain pending.

### Checkpoint 2 — Complete surface plants installed

- All **76** young/mature/seasonal/picked/packed exports installed from a complete
  staged manifest after source geometry audit and native gallery review. All
  seven contact sheets inspected. Sources: `tools/voxel_assets/plants.py` and
  `data/art/voxel_plants.json`; production ownership ledger:
  `data/art/voxel_manifests/plants.json`.
- Source tests verify full path coverage, grounding, crop-only removal, younger
  forms and exact grid-aligned packed-plant translation. Shared exporter tests:
  12 greedy/proxy tests plus four pipeline tests; three plant tests passed.
- Native `SurfaceVegetationArtTest`: **2,163 checks / 76 models passed**.
  `ShrubCuttingTest`, `ShrubRegrowthTest`, `ShrubTransplantTest`,
  `ShrubPlantingAnimationTest`, `PlantHabitatTransplantTest` and
  `ShrubMoveHandoffTest` passed. Regrowth/transplant initially printed success
  with terrain lookup errors: their synthetic worlds omitted `_cache_block_ids`.
  The fixtures now initialize that lookup, and clean reruns pass. No runtime
  terrain behavior was changed to hide those errors.
- Source totals: 60,862 visual / 37,974 shadow triangles across all variants
  (37.6% caster reduction), 9,243,936 bytes. Thin stems retain fine proxies when
  a coarse density would erase them. These are asset totals, not a frame-time
  or low-end hardware claim. Whole-world cost measurement remains required.
- Native review/logs: `tmp/settlement_art_20261013/plants_gallery/` and
  `plants_native`, `plants_cutting`, `plants_regrowth`, `plants_transplant`,
  `plants_animation`, `plants_habitat`, `plants_move`. Durable evidence copied to
  `concepts/224_voxel_migration/plants/`.
- All 94 trees completed their first staged export and gallery. Broad timber
  steps reduce mature winter oak from 32,112 to 8,646 triangles and ancient oak
  from 78,994 to 6,132. Pine anchor unchanged except production footprint trim.
  Apple blossom/fruit placement is being refined after native review showed
  accents hidden inside crowns; juniper twig tips are being tucked under foliage.
  Trees are not yet installed. Next: finish those previews, review matching
  hashes, run production tree suites, then matched full-world performance.

### Checkpoint 3 — All flora and ground rocks installed

- All **94 trees**, **6 rocks** and **14 defined crop models** installed after
  exact-hash native review and full source audit. Trees retain stable seasonal
  scaffolds, growth stages and positional variants; apple blossoms/fruit are
  exposed on the crowns and juniper picked forms retain their foliage.
- Native `TreePilotTest`: **2,440 checks / 94 models**. `TreeFellingTest`,
  `JuniperHarvestTest` and `SeasonalRefreshTest` (**243 checks**) pass. Felling's
  synthetic terrain fixture now initializes height and waterline maps for its
  edit-baseline queries; clean rerun has no script errors. Runtime terrain rules
  were not altered.
- `GroundStoneArtTest`: **530 checks / 6 models**; all installed manifests:
  **2,091 checks / 190 models**. Source tests verify full crop state coverage,
  smaller young forms, grounding and disconnected scree with ground contact.
  Crop models are art/data-ready only; no farming behavior was introduced.
- Asset totals (visual / shadow triangles): trees **786,526 / 307,966** (60.8%
  reduction), rocks **10,862 / 2,040** (81.2%), crops **10,494 / 9,298** (11.4%).
  Sparse crop stems require fine fallback. These totals do not establish frame
  time. Plant rebuild verification passed earlier; tree/rock/crop verification
  is running, followed by a matched native settlement performance check.
- Exact native reviews: `trees_gallery_final`, `rocks_gallery`,
  `crops_gallery_final` under `tmp/settlement_art_20261013/`. Durable evidence:
  `concepts/224_voxel_migration/flora_checkpoint/`.
- Dwarf staging now covers all **43** paths using integer-cell authoring data in
  `data/art/voxel_dwarves.json`. Three source tests pass: complete/distinct
  appearance variants, accepted pilot solid anchors, bounds and tool contacts.
  Production dwarves remain unchanged until assembled review and native checks.

### Checkpoint 3b — Flora world acceptance and reproducibility

- Tree, rock and crop `--check` rebuilds pass byte-for-byte (plants verified at
  checkpoint 2). Native `voxel_flora_complete` and `voxel_flora_repeat` full
  settlement runs pass, including all eight save/reload invariants, 24 dwarves,
  48 furniture pieces, 2,953 trees, physical hauling, wildlife, sleep and doors.
- The fixture hash differs only in `counts.mesh_instances` (7,493 → 12,560),
  as separate proxy nodes require. `compare_world.py` removes only that measured
  rendering count and requires every logical fixture field to match exactly;
  terrain fingerprints, entity identities, cameras and sample lengths match.
- A sequential old-art rerun under the same runtime (`voxel_flora_oldart_repeat`)
  separates art cost from the initial run's timing difference. It restores 176
  recovered flora/rock GLBs **only in that process's resource cache**, using
  imported study copies under `assets/models/studies/voxel_migration_baseline/`.
  Production assets and original saves are not restored or overwritten.
- Current-runtime old → voxel: paused overview GPU p50 **2.467 → 2.797 ms**;
  active overview **2.894 → 3.276 ms**. Active overview frame p95 **25.414 →
  26.397 ms**; other active-view p95 changes range **−0.207 to +0.357 ms**.
  Paused draw counts are unchanged; overview primitives increase from 1,765,418
  to 3,767,452. Original-baseline paused static memory increases about 31 MB and
  GPU allocation about 12 MB. The recovered-art replay retains extra resources,
  so its memory totals are not the memory baseline.
- The initial baseline's active p95 values were about 3 ms lower even than the
  old-art rerun. This broader timing/runtime difference remains documented;
  it cannot be attributed to voxel art. Final whole-project acceptance will
  repeat the matched checks. These results cover this RX 9070 XT machine only.
- Reports, matched captures, logs and comparison JSON are preserved under the
  flora checkpoint evidence directory. Trees/plants/rocks are now accepted;
  missing crops are gallery/data-ready. Continue with the complete dwarf batch.

### Checkpoint 4 — Complete dwarf roster installed

- All **43 dwarf parts** installed, including 14 hairstyles, seven beards,
  eight brows, four ages, four scars and both work tools. Width factors are now
  unit scale; final proportions are authored in the 1:16 geometry. Tool grip
  and contact coordinates, identifiers and logical occupation are preserved.
- Three additional tiny noncasting presentation assets replace procedural
  eyelids and apple/berry servings. Food meshes/materials are cached by shape
  and food color; no runtime voxel meshing or nutrition changes. Scope is now
  the planned 400 models plus these three explicit presentation models.
- Modular overlays are separated from coplanar head faces on the integer grid.
  Closed voxel surfaces use backface culling through a shared-body variant of
  the world shader. Original lighting equations are unchanged. Mirrored dwarf
  limbs continue to use baked reflected meshes and corrected winding.
- Native geometry suite: **7,710 checks**, 41 appearance/body models,
  **800 appearance combinations and 22 pose cases**. Presentation: **935 checks**.
  All installed manifests: **2,588 checks / 236 models**. Shared consumer suite:
  **92 checks**. Four source dwarf tests and byte-identical 43-part rebuild pass.
- Rest, dining, roster, inspector, readability, native slice movement, mining,
  hauling, felling, native construction and ladder checks pass without script
  errors. Ladder's synthetic terrain now initializes noise generators before
  its edit-baseline query. No runtime terrain change was needed.
- Native limb lighting: **32 paired samples**, four skin tones under daylight
  and torch light. Production roster/portraits/rear/poses gallery passed and
  was reviewed at 1600×1000. Evidence and exact staged hash review are saved in
  `concepts/224_voxel_migration/dwarves/`.
- Dwarf totals: **11,336 visual / 5,626 proxy triangles**, 1,645,140 bytes.
  These are source totals, not whole-world timing. Final acceptance remains.
- Reviewing full-world flora captures exposed dark triangular marks on some
  trunks. Tree visual acceptance is reopened while a matched diagnostic checks
  automatic LOD, shadows and culling. `Gallery.gd --production` now instantiates
  the actual imported PackedScenes instead of bypassing editor processing.
  Earlier source/import/state/performance results remain valid within those
  limits; the visual defect is not accepted merely because tests passed.

### Checkpoint 4b — Tree diagnosis; wildlife activation

- Identical full-world camera diagnostics compare actual imported scenes with
  LOD off, sun shadows off, closed culling, zero normal bias and proxies hidden.
  A close trunk view confirms the apparent marks are **intact horizontal voxel
  ledges**, bright without shadow and dark under the cool ambient lighting.
  There are no triangular holes, missing faces or LOD corruption. Existing
  geometry and global lighting remain unchanged; tree acceptance is restored.
  Evidence: `tmp/settlement_art_20261013/trees_trunk_diagnostic/`.
- Wildlife's **21 GLBs** are now installed after complete exact-hash part review,
  five assembled species/sex pages (60 views), three source tests and **48,859**
  sampled rigid-pose checks. Wolf proportions are baked into its vertices with
  unit root scale; presentation pivots preserve intended final placement.
- Deer/wolf legs now have closed upper/lower segments at real knee pivots,
  folding at rest instead of shrinking. Duck wings fold against the body with
  rigid transforms; reflected meshes use the same immutable, cached reflection
  utility as dwarves. Rabbit rest uses head/ear pose without body compression.
- Production imports are clean. Live rabbit/deer/wolf/duck/navigation and native
  production gallery checks are running; do not mark the family accepted yet.

### Checkpoint 5 — Complete wildlife installed and validated

- Production geometry: **48,859 checks / 21 GLBs**. Rabbit, deer, wolf, duck
  and animal navigation cache suites pass without script errors. The deer
  regression caught outward-pointing folded knees exceeding its existing
  footprint; front/rear legs now fold inward and the unchanged clearance test
  passes. No navigation limits or test tolerances were relaxed.
- Native production gallery: **60 views**, all four species and both duck
  sexes, front/side/rear, walking, feeding, rest and duck flight. Three source
  tests and byte-identical regeneration pass. Shared reflection regression:
  **7,710 dwarf checks / 800 appearances / 22 pose cases** still pass.
- All installed manifest checks: **2,831 checks / 257 models**. Wildlife source
  totals: **7,434 visual / 4,062 shadow triangles** (45.4% reduction),
  **1,102,464 bytes**. Paired proxies follow every rigid upper/lower leg segment.
- Durable native captures/logs/repro results: `concepts/224_voxel_migration/wildlife/`.
  Tree diagnostic evidence is also preserved under
  `concepts/224_voxel_migration/flora_checkpoint/trunk_diagnostic/`.
- Next: 50 furniture/support/frame-library exports, then loose goods,
  construction and final secondary-view/world/copied-save acceptance. Native
  analytic solid helpers are being added for joinery, profiles and hollow forms.

### Checkpoint 6 — Furniture, access structures and flames

- All **50 exports** installed: complete furniture catalogue, packed kits,
  legacy chair, four ladders, five bridges, fence rails and five animation libraries.
  Native solids retain original logical footprints, IDs, hinges and contact planes.
  The game table's .78 top rounds to .75 on the grid; gameplay height is unchanged.
- **864 geometry/contact/material checks**, **249 flame checks**, 57 paired native
  catalogue/interaction views and 42 unique timed flame frames pass. Day/night
  captures cover all six installed fire sources. Explicit GLB noncasting metadata
  keeps flames and tiny presentation pieces off the shadow pass automatically.
- Placement, moving, grid fences, bridge, ladder, hearth seasons/temperature,
  torch reach, native room lighting and all 12 rotated door cases pass. The bridge
  fixture now initializes its terrain baseline before underground edits. Hearth's
  fixture locates the visual child within the paired node. Door illumination uses
  the same neutral surface for actual/reference samples so bark darkness does not
  invalidate an illumination-only threshold; leakage/rotation assertions remain.
- Reviewed source game counters were widened one grid cell after the first gallery
  exposed empty corner-trimmed pieces. Corrected exact-hash gallery is preserved.
- Evidence: `concepts/224_voxel_migration/furniture/`. Items (92) and construction
  (4) have passed source/staged review and are now installed; imported runtime
  tests and final previews are running. Whole-world acceptance is still pending.

### Checkpoint 7 — Goods, construction and secondary views

- **92 item forms** cover all 62 definitions, 45 quantity-state crates, every wood,
  ore/gem/soil/stone, tool, crop product, drink and premium drink. Native review:
  **1,644 checks**, 41 views including all forms, four tool wood options, carrying
  and work poses. Produce-crate packing/refill/split/hauling/storage/save tests pass.
  Source review corrected merged fruit rows and preserved crate joinery around
  contents. No fallback models were used.
- **Four construction exports** installed. Floors remain complete unit solids;
  their greedy boundary faces feed the existing exposed-terrain batch, excluding
  proxies. Floor construction, staging, continuity and native hammer/crate
  presentation pass. Crate/material checks now distinguish visual surfaces from
  shadow-only instances; exact tool contact checks account for merged triangles.
- Final loader audit added explicit persistent shadow policy to bridge and ladder
  previews, construction crates, flag and water-stone loaders. Materials skip proxy
  nodes. **108 shared consumer checks** pass, including partial ladder ghosts after
  rebinding; water-stone/flag lifecycle tests and construction shadow checks pass.
- Four seasons: **243 refresh checks** pass. Crafting browser/category/details and
  responsive UI checks pass. Existing noncasting dust/chip and water/wake cube
  effects are deliberately retained; exceptions are listed in final coverage.
- Source tests: **24 family/pipeline + 12 mesher/proxy tests** pass. Complete
  **403-file byte-identical regeneration** passes. All native manifests:
  **4,620 checks / 403 models**. Final audit resolves **398 literal GLB references**,
  accounts for every production export and confirms original saves are unchanged.
  Only wolf visual scale/pose and dwarf baked-width presentation data changed
  outside art data; project settings and other gameplay JSON are unchanged.
- Source totals: furniture **52,942 visual / 10,620 shadow triangles**, items
  **33,214 / 20,286**, construction **316 / 128**. Fine proxies deliberately remain
  on tiny/thin shapes when coarsening would lose their silhouette. These counts
  describe source geometry, not a whole-game speedup.
- Fresh seeded-world `SaveManagerRoundTripTest` and **19 save-worker checks** pass.
  Durable evidence: `concepts/224_voxel_migration/goods_construction/` and
  `concepts/224_voxel_migration/final/coverage.json`. Copied player-save replay and
  matched final native settlement performance remain in progress.

### Checkpoint 8 — Existing saves and UI refresh

- Both recovery copies pass native load → save → reload checks. Quicksave:
  **five dwarves / 82 installed furniture**; autosave: **five / 80**. Exact tested
  terrain, furniture, construction, ladder/bridge/mining/crafting state, identities,
  appearance, clock and per-item/material goods totals are preserved. Four seasonal
  dawn/day/dusk/night views and three slice heights were captured for each copy.
  These checks write only isolated test profiles. Original fingerprints are intact.
- Native X-ray Full/Flat/slice/cache/UI fixture passes. Native construction review
  also checks the imported hammer surface itself: its cosmetic impact anchor now
  matches the nearest grid face (.375, .25, .25), preserving the world target and
  actual contact instead of checking only an abstract rig constant.
- Refreshed **42 furniture and 71 inventory transparent PNG thumbnails** from the
  current models, imported them and reran inventory/crafting browser checks.
  World/portrait/carrying and static menu images now use the same current art.
  The inventory total includes the retained flag image path used by storage
  inspectors; the generator now explicitly refreshes existing furniture aliases.
- Full matched settlement run is in progress. Do not claim full performance
  acceptance until its reports and any necessary repeat have been reviewed.

### Checkpoint 9 — Complete migration accepted

- Final inventory: **94 trees, 76 surface plants, 6 rocks, 14 crop models, 43
  dwarf parts, 3 presentation models, 21 wildlife parts, 50 furniture/support/
  flame-library exports, 92 item forms and 4 construction models**. All **403**
  installed exports reproduce byte-for-byte. The 14 crop models fill existing
  missing art definitions; farming gameplay is not introduced.
- **24 family/pipeline and 12 mesher/proxy source tests**, **4,620 native manifest
  checks** and **108 shared consumer checks** pass. Each family's geometry,
  interaction, pose, lighting and variant results are recorded above. Final
  construction-contact, inventory/crafting at three resolutions and X-ray tests
  pass. **113** transparent catalogue thumbnails are refreshed. No final accepted
  run has script errors; copied-save fixtures retain only the known pre-scene
  SkyController warning.
- Both complete native settlement runs (`voxel_complete_world`,
  `voxel_complete_repeat`) pass with **24 dwarves, 48 furniture pieces and 2,953
  trees**, active wildlife, carrying, seating, sleeping and moving doors. All eight
  save/reload invariants pass. Both copied player saves pass their detailed
  preservation checks and seasonal/slice views. Original quicksave/autosave
  fingerprints were checked again after the final runs and remain unchanged.
- Coverage resolves **398 literal model references** and every manifest-owned
  production GLB. Project settings and gameplay JSON retain the recovery versions
  apart from the explicitly allowlisted wolf pose/scale and dwarf baked-width
  presentation data. Noncasting dust/foam/wakes, uniform cargo fitting and the
  existing uniform construction-hammer scale are explicit retained exceptions.
  Illustrated HUD/menu artwork keeps its established style; model previews are
  migrated. Historical study assets are outside production coverage.

#### Matched performance and loading

Same **1600×1000**, Ryzen 7 9800X3D / Radeon RX 9070 XT, Godot 4.7.2, fixed 60 Hz
simulation delta and VSync-off benchmark. Cameras, terrain fingerprints, initial
logical entities and sample lengths match. The original project's source and art
were recovered into a separate ignored test project, with only the same test
harness copied in. It never replaces live production files or player saves.

| Measure | Recovered original | Complete voxel run | Voxel repeat |
|---|---:|---:|---:|
| Paused overview GPU p50 | 2.434 ms | 2.704 ms | 2.675 ms |
| Active overview GPU p50 | 2.881 ms | 3.189 ms | 3.358 ms |
| Active overview frame p95 | 26.760 ms | 27.855 ms | 26.846 ms |
| Active close frame p95 | 25.489 ms | 25.794 ms | 24.991 ms |
| Paused overview frame p95 | 9.328 ms | 9.224 ms | 9.133 ms |
| Paused overview draws | 653 | 713 | 713 |
| Paused overview primitives | 1,765,418 | 3,817,770 | 3,817,588 |
| Initial startup-ready time | 8.987 s | 9.434 s | 9.073 s |
| Initial complete overview | 13.350 s | 13.830 s | 13.440 s |

The repeat's active-view frame p95 deltas range **−0.498 to +0.365 ms**. The first
voxel run's largest active-view delta is **+1.095 ms** in the overview. Wide-view
GPU cost grows about **0.24–0.48 ms**. Paused overview static memory grows
**40.3–43.9 MiB**, GPU allocation **20.4 MiB**. Initial mesh instances increase
**7,493 → 13,750** because parts now have separate proxy instances. These measured
costs are accepted for the complete art conversion; this is not a whole-game
speedup or a low-end hardware certification.

The original early-session active timings were 4–6 ms lower than the final runs.
Running the entire recovered original project again reproduced most of that
difference, so it is not attributed wholly to the migration. Both original
comparisons and the repeated final data are retained. Active simulation has
wall-budgeted scheduling; identical starting fixtures do not guarantee identical
later worker timing.

Copied quicksave seasonal settle/capture, recovered original → voxel:
spring **9.024 → 9.909 s**, summer **8.975 → 9.171 s**, autumn **9.002 → 9.179 s**,
winter **8.822 → 9.262 s**. This is the complete terrain/season refresh queue plus
capture encoding, not an isolated object-mesh generation cost. It is one run per
revision. Original data, camera/time sequence and restored contents match.

Across all source variants there are **974,118 visual / 398,000 proxy triangles**
and **127,076,904 GLB bytes**. This catalogue total includes noncasting flames and
presentation assets; it is not a count of triangles drawn in a single frame.
Thin branches and tiny objects retain fine proxies where downsampling would
erase their silhouette. Detailed casting remains off; proxies are shadows-only.

#### Saved evidence and recovery

- [Final coverage](concepts/224_voxel_migration/final/coverage.json),
  [repeat comparison](concepts/224_voxel_migration/final/recovered_repeat_comparison.json),
  [loading comparison](concepts/224_voxel_migration/final/loading_comparison.json),
  [thumbnail fingerprints](concepts/224_voxel_migration/final/thumbnails.json) and
  [evidence manifest](concepts/224_voxel_migration/final/evidence_manifest.json).
  The final evidence folder contains full reports, samples, clean logs and native
  captures, including the recovered-source benchmark and copied-save comparison.
- Initial recovery remains `tmp/voxel_migration_20261018/recovery/workspace_before.zip`.
  Final selective delta and per-file hashes:
  `tmp/voxel_migration_20261018/checkpoints/final_voxel_migration.zip` and `.json`.
  Restore selectively over the initial recovery; unrelated pre-existing work was
  not staged, committed, deleted or bulk-restored. Family evidence/checkpoints
  remain alongside this report.
- Reproduction: `python tools/voxel_assets/build.py all --check` verifies installed
  bytes. `python tools/voxel_assets/final_audit.py` checks coverage, geometry,
  allowlisted data changes and the preserved original-save fingerprints against
  this local recovery. Native fixtures use `tools/voxel_assets/Run.ps1` with isolated
  profiles. Normal Play uses the migrated production assets directly.
