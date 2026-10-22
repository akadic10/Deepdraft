# 00 — Changelog

Dated summaries of finished work, newest first. Each entry links to its milestone doc
when there is one. These entries lived at the top of AGENT.md until 2026-10-21; AGENT.md
now holds rules only.

To add an entry, put it at the top: the date, what changed for the player, the
milestone doc link, and whether the owner should restart Play or reload the project.

---

**Mining stutter fixed; mining drag capped at 32 (2026-10-21):** review item 6, at the
owner's request ([254 §4.3, §4.5](254_full_project_review_2026_10_20.md)).
- **Stutter.** Every mined or built block made the renderer rebuild three whole-world
  structures on the main thread: the cavity shell, the built-block mesh and the overview
  snapshot. The cost grew with the colony.
  - On a copy of the owner's save (49k edits, 5 dwarves), a frame with a mined block took
    284 ms against 6.9 ms idle. It now takes about 19 ms.
  - The cavity shell and the built blocks are now one mesh per 16×16 column. An edit
    rebuilds its own column, plus the next column when the edit sits on the edge.
  - The overview snapshot is patched per changed cell instead of copied (26–38 ms →
    0.01 ms).
  - Slice moves, season turns and loads still rebuild everything, as before.
  - Checked against the old code on the same save copy: identical triangles and snapshots
    after mining, building, designating and slice moves.
  - Not changed: the first mined block after a load still hitches once (~0.5 s), as it did
    before. Most of it falls outside the renderer; logged in [00 — To do](00_todo.md).
- **Drag cap.** The mining drag limit is now 32 blocks (was 40). The old limit was never
  enforced: a long drag only lost one brush step.
  - Each horizontal axis now stops at the most whole brush steps that fit in 32 blocks;
    the anchor side stays put.
  - New gate test `MiningDragLimitTest`; the gate has 46 tests.
- **Shader slots.** The 8,192-object cap is logged as a to-do in
  [00 — To do](00_todo.md). `buffer_size` is unchanged.
  - `tools/performance/RunShaderSlots.ps1` counts the slots on a copy of a save, in a
    throwaway profile; `-Mining` also times mined blocks.

Restart Play to pick up the changes.

**AGENT.md is rules only; git cleaned (2026-10-21):** at the owner's request.
- **AGENT.md.** It went from 1,852 lines to 317. Its 146 dated entries moved here.
  - It no longer tells agents to read every doc first; they read the docs for the area
    they're changing.
  - A new "Standing Decisions" section collects the owner's decisions that were buried in
    old entries: Hearthblock only, builds only when asked, performance paused,
    30 dwarves, no save backward compatibility, no Jeweller, and the honey connection.
    It also holds today's rules for tests and scratch output.
  - A "Recording Changes" section points new entries here.
- **CLAUDE.md.** A new `CLAUDE.md` imports AGENT.md, so Claude Code sessions load the rules
  automatically.
- **Git.** `.git` went from 1.6 GB to 1.2 GB. 382 MB of temp files from interrupted git
  operations were removed and the objects repacked. History is unchanged.

No restart needed.

**Milestone evidence removed (2026-10-21):** at the owner's request,
`docs/00_dev_roadmap/concepts/` went from 269 MB (2,428 files) to 856 KB.
- **Deleted:** milestone screenshots, reports, logs and old harness scripts. Some of those
  scripts swapped production sources in place while running.
- **Kept:** the 32 frozen `*.before.txt` source copies, in 10 folders. Nine tests read
  them, including the gate's `SaveManagerRoundTripTest` through `SaveWorkerChecks`, and so
  do two benchmark tools. All nine tests pass.
- **`docs/.gdignore` added:** Godot no longer imports images saved under `docs/`.
- **Broken links:** about 70 older milestone docs link to deleted evidence. Those links are
  now broken; the files can be recovered from git history if needed.

**`tmp/` cleared (2026-10-21):** at the owner's request, `tmp/` went from 8.6 GB (43,032 files)
to 56 MB.
- **Kept:**
  - `tmp/.gdignore`, which stops Godot importing scratch;
  - `tmp/hearthblock_studies/`, the chibi deer study, which isn't adopted yet;
  - `tmp/hearthblock_lighting_20261020/recovery/`, the save copy that the lighting review
    loads;
  - `tmp/hearthblock_pilot_20261020/`, the renders that doc 256 points to.
- **Git.** The 4,647 tracked tmp files leave the repo with the next commit; only
  `tmp/.gdignore` stays tracked.
- **Old evidence links.** Evidence paths under `tmp/` in older entries and docs no longer
  exist; the durable record is in `docs/`.
- **Tests.** The five world-generation tests now create their report folders.

**Test suite pruned (2026-10-21):** at the owner's request, 34 non-gate tests were deleted. The
owner's rule: write new tests as features need them.
- **What was deleted:**
  - tests that could not fail, or duplicated another test;
  - replays of old saves;
  - real-speaker audio checks;
  - pre-Hearthblock lighting and visual measurements;
  - tests broken by retired furniture, a half-built test world or the new art.
- **Four broken tests stay only as bases for kept tests:** `BoulderPilotTest`,
  `DwarfInspectorTest`, `FurniturePlaceTest`, `ToolPromotionTest`. Run on their own, they
  fail.
- **Tools removed with them:**
  - `tools/TunnelLightingStudy.gd`;
  - the atmosphere and autosave evidence collectors in `tools/performance/`.

  The two `Verify.ps1` runners no longer list the deleted tests.
- **Checks.** All 45 gate tests pass, as do the six kept tests built on the four bases.

**Test gate works in Windows PowerShell 5.1 (2026-10-21):**
`tools/run_job_reliability.ps1` now holds the Godot process handle, so exit codes read
correctly in the stock `powershell.exe`. Before this, every test showed FAIL with a blank
exit code. `tools/windows_playtest/Export.ps1` was deleted at the owner's request; export
from the editor instead.

**Mining hidden-air crash fixed (2026-10-21):** [254 §4.1](254_full_project_review_2026_10_20.md)
- **Bug.** A worker whose mining zone held a cell that was not solid in the live world
  re-pulled that cell from its own stand forever, until the stack overflowed. The cell
  was either undiscovered cave air, or a cave the previous dig had just revealed.
- **Fix.**
  - An open planned cell is now skipped for the rest of that lease.
  - A still-hidden cave cell is worked as the strata the slice shows. The commit breaks
    into the cave, reveals it, and gives no goods.
- **Checks.** `MiningHiddenAirTest` is new and in the job gate. It reproduced the
  overflow before the fix and passes after. The mining, ladder, job, support,
  navigation and construction checks pass.

Restart Play.

**Old art directions removed (2026-10-21):** only Hearthblock remains. Deleted:
- the faceted, 1:16 study, hand-hewn and chibi-refinement roadmap docs and their
  concept images (54 docs, 38 concept folders) and the old reference concept;
- 219 legacy tool scripts: generators, previews, audits, captures, study viewers,
  and the superseded timber, log and mined-resource builders in
  `tools/voxel_assets` with their data;
- the nine study launchers and eight study scenes;
- the old study models and the generated VoxelFeed exports.

Tests:
- the five `*FacetedArtTest` files are now `DwarfArtTest`, `WildlifeArtTest`,
  `ItemArtTest`, `FurnitureArtTest` and `FireArtTest`;
- the retired pilot checks (`DwarfPilotArtTest`, `DeerPilotArtTest`,
  `FurniturePilotArtTest`, `ProportionIntegrationTest`, `HandHewnProductionTest`)
  are deleted;
- the eight pilot wrapper tests (`DwarfPilot*`, `DeerPilotWildlifeTest`,
  `FurniturePilot*`) are deleted, along with their model installers (`tools/dwarf_pilot`,
  `tools/animal_pilot`, `tools/furniture_pilot`) and the world benchmark's `--pilot`
  mode. Each wrapper only reran a production test with the old pilot model set.
  `FurnitureCapture.gd` now carries the stage it used to inherit from
  `FurniturePilot.gd`;
- `GemDropArtTest` checks the Hearthblock gem shape.

Kept:
- the Tier 1 and Tier 2 study layouts in `data/art/studies/hearthblock_furniture_tiers.json`
  (the owner later deleted the whole `VoxelFeed/` folder, including the `.vox` copies);
- the six surface `*PilotTest` files (Boulder, Scree, Flower, Reed, Shrub, Tree): they
  test the current models and their gameplay, and "pilot" there means the first
  playable version, not an art style;
- tools that the galleries and benchmarks build on: `BenchmarkSettlement.gd`,
  `CaptureTerrain.gd` and `DwarfRedesignPreview.gd`.

Code moves:
- `solid()` moved to `tools/voxel_assets/solid_shapes.py`;
- the mesher and shadow tests moved into `tools/voxel_assets/`;
- coverage reads `data/art/voxel_baseline.json`.

All 384 production models are byte-identical. Everything removed is in git history
up to commit 1238cfa1. No commit.

**Hearthblock art (2026-10-20/21), the only art direction:**
[64 — Hearthblock art direction](../60_asset_creation/64_hearthblock_art_direction.md)
defines the look and the gameplay contracts, and
[256 — Hearthblock art](256_hearthblock_art_pilot.md) records the
conversion. Everything the game can show is Hearthblock:
- Tier 1 · Axe-Hewn furniture, plus the hearth, kits and flag;
- every dwarf appearance: square heads, bead eyes, cuffed mittens and boots, and six
  tunic colours (`DwarfAssets.CLOTHING`);
- all animals, with chibi rigs in each animal's `visual_pose` and squash and stretch;
- trees, wild plants, and the 25 stored goods the game produces;
- boulders, scree, the plank floor and the materials crate;
- the work tools, the "dressed" stone/grass/earth terrain
  (`terrain_appearance.gdshaderinc`, `appearance_profiles.json` → `dressing`) and the
  menu pictures.

Where to work:
- Author in `tools/hearthblock/art/*.mjs` and regenerate
  `data/art/voxel_hearthblock.json` with `write_data.py`. Or edit the Python family
  builders in `tools/voxel_assets/`.
- Install through `build.py`. The workflow is in
  [61](../60_asset_creation/61_voxel_art_guide.md), and the technical rules are in
  [63](../60_asset_creation/63_shared_art_standard.md).
- After model changes, re-render the menu pictures with
  `FurnitureCatalogThumbnails.gd`, `InventoryCatalogThumbnails.gd` and
  `GenerateFloorIcons.gd`.

Owner rules:
- Old joints, pivots, envelopes and shape pins must not constrain the art (2026-10-21).
  Change the rig data and the tests, but keep the real gameplay contracts.
- Content the game cannot produce yet (crops, the stone floor, drinks, staves,
  cloth, honey and so on) keeps its placeholder models. Author it in Hearthblock when
  its feature arrives, not before.
- Never delete the Tier 2 · Carpenter designs: `data/art/studies/hearthblock_furniture_tiers.json` (cell layouts for both tiers) and `diningTable()` / `bed()` in `tools/hearthblock/art/proposal.mjs`.

**Hearthblock lighting (2026-10-20):** [255 — Lighting pass](255_hearthblock_lighting_pass.md)
is part of the Hearthblock look. It applies in the main world only:
- ACES tone mapping and glow that only fire reaches;
- a dim cool fill for sealed air and a camera-facing fill on actors and props
  underground;
- warmer fire lights, darker warm slice caps and burlap stockpile overlays.

**Development → Hearthblock lighting** flips it at runtime, and switching it off
restores the previous look exactly. All values are in `data/sky/sky_settings.json`.
The cost is GPU +0.43 ms at 3840×1080, mostly the glow.

**Fruit hauling (2026-10-19):** [253 — Fruit consolidation](253_fruit_hauling.md)
lets a worker fill one carried basket with matching allowed fruit along a proven
delivery route, up to its normal 24-unit capacity and eight extra walking steps.
Exact source and destination claims survive partial pickups, cancellation and
saves. Harvest/haul priorities and the four-point carry budget stay unchanged.
The three-tree reproduction falls from three deliveries to two; a route with
three nearby baskets delivers all 22 apples together. Power-loss recovery found
and fixed the missing cached-route fallback. Checks and evidence are recorded
in 253 and `tmp/fruit_hauling_fix_20261019/`. Restart Play.

**Apple picking (2026-10-19):** [252 — Apple harvesting](252_apple_harvesting.md)
connects the existing apple fruit definitions to standing-tree harvest jobs.
Inspector **Gather apples** and **Orders → Harvest plants** pick 4–6 mature or
7–10 ancient apples once each autumn, in four/six seconds. Trees remain standing;
picked fruit disappears and returns next autumn. Hungry dwarves eat the real
gathered fruit through normal food behavior. Partial work and picked crops use
the existing save fields. Worker, food, UI, tree art, juniper, felling and full
save checks pass; a copy of the player's save shows the new action. Evidence and
backups: `tmp/apple_harvest_20261019/`. Original saves unchanged. Restart Play.

**Unused stone types removed (2026-10-19):** [251 — Stone retirement](251_retired_stone_types.md)
removes granite, basalt, limestone and marble, their four GLBs, thumbnails,
generated VOXs and active art definitions. Rough Stone is the ordinary stone
item; terrain, recipes and all 382 surviving production GLBs remain unchanged.
Explicit save retirement cleans old item/filter references while preserving
other goods. All four player-save copies validate unchanged; injected legacy
items are removed correctly on read/write. Asset, save, inventory and arrival
checks pass. Evidence/backups: `tmp/retired_stones_20261019/`. Restart Play.

**Famished dining range (2026-10-19):** [250 — Dining range](250_famished_dining_range.md)
keeps the normal 16-block route limit after food is collected, even when famished.
The obsolete six-block exception is removed; bounded search and all claims remain.
In the copied player save Birna carries food to stool 97 at table 94, sits with
the torso resting on the seat and completes a proper meal without the −8 penalty.
Dining, food and idle regressions pass, including real meals beyond six blocks
and fallback beyond sixteen. Native evidence and backups are in
`tmp/dining_fix_20261019/`. Original saves are unchanged. Restart Play.

**Solo games and partner search (2026-10-19):** [249 — Recreation](249_solo_games_and_partner_search.md)
reproduces Sollin's partner wait in a copy of the player save. Eligible companions
and reachable 29–31-block routes were excluded by the 24-block search limit.
An occupied table now recruits within 48 routed blocks under the same bounded
search budget. One dwarf starts playing immediately with one stool: a completed
solo game gives +4 happiness; a full shared game gives +8, each for 12 game hours.
Only the stronger thought contributes. Late partners, cooldown, interruption,
legacy/current saves and worker release pass focused and full save checks. The
copied colony completes a Sollin/Guntris game. Evidence is in
`tmp/recreation_fix_20261019/`. Original saves are unchanged. Restart Play.

**Saved-world loading (2026-10-19):** [247 — Loading performance](247_saved_world_loading.md)
adds a synchronous terrain/water restore boundary, immutable overview snapshot
reuse and a larger underground-lighting budget behind the loading cover. The
copied player save loads in 26.943 s versus 71.510 s with the original code; the
matching fresh world takes 15.596 s. Colony state, continued water simulation,
all terrain meshes and lighting bytes match. Focused save/water/rendering checks
pass; test limitations and evidence are in 247 and `tmp/load_fix_20261019/`.
Original player saves are unchanged. Restart Play. No export or commit.

**Mining planning stall (2026-10-19):** [246 — Mining planning holds](246_mining_planning_hold.md)
extends mining's temporary leisure hold while a bounded route search advances,
preventing strolling from repeatedly discarding its starting position. The mixed
scenario now clears all seven job families; idle and hauling regressions pass.
Three fixtures use current log furniture and test-only storage. Idle planning is
included in the default reliability gate. Evidence and task-start backups are in
`tmp/mining_stall_fix_20261019/`. Restart Play to use the scheduler correction.

**Resume latest save / New Game (2026-10-18):** [240 — Testing startup](240_startup_resume_and_new_game.md)
automatically restores the newest valid quick save/autosave or backup before
world generation. The gear menu now offers New Game, which resets the world,
calendar and seeded weather without writing save files. Normal autosaving
continues afterward. Native startup/menu/fresh-world/manual-load checks, save
selection/recovery, dock lifecycle and the full save/worker suite pass. Recovery
and completion checkpoints are in `tmp/startup_resume_20261018/`. Restart Play.
No player-save writes, export or commit.

**Unavailable furniture removed (2026-10-18):** [234 — Furniture retirement](234_retired_uncraftable_furniture.md)
removes fifteen uncraftable designs, their packed items, Place/DEV entries,
production art and generation paths. Settlement flag and wet/dry stones remain,
along with all sixteen craftable furniture designs. The log torch owns its
unchanged flame under a new filename. Validated save migration removes retired
pieces and preserves surviving container goods. All four real save slots are
cleaned; original saves and before/after source checkpoints are retained in
`tmp/retired_furniture_20261018/`. Native migration, art/fire, placement, dining,
recreation, full save/worker recovery and copied player-save roundtrips pass.
There are 33 furniture GLBs and 386 production models. Restart Play and load.
No export or commit. Await the player's next design priority.

**Closer dining stools (2026-10-18):** [232 — Compact dining layout](232_compact_log_dining.md)
moves each of the four log-table stool guides inward exactly one world voxel.
The unchanged 3×3 table and four separate one-tile stools now occupy 5×5 in total.
Table-local resting hands clear the slab; ordinary stool poses remain available
elsewhere. Four rotations, snapping, simultaneous dining, Move/save and seating
regressions pass. Native preview and checkpoint saved. Restart Play, then Move
previously placed stools onto the closer guides.

**Player log dining table (2026-10-18):** [231 — Log dining table](231_log_dining_table.md)
adds the Log Dining Table:
- a 3×3 footprint with four separate stool guides;
- two-log crafting, Move and save/restore.

Its model is now the Tier 1 split-slab table
([256](256_hearthblock_art_pilot.md)).

**Voxel shadows (2026-10-18):** [222 — Shadow proxies](222_voxel_shadow_proxies.md)
gives every voxel model a coarser shadow-only sibling and keeps every visual payload.
Godot setup turns off detailed casting and binds each proxy to its part's pivot.
The first pine cast 79% fewer shadow triangles. No save change.

**Windows playtest policy (2026-10-16):** The user explicitly requested removal
of the generated Windows playtest folder and does not want unsolicited exports.
Do not create, rebuild, update or package a Windows playtest unless the user
explicitly asks for it. Ordinary feature work and validation use the source
project. Generated `build/windows/` outputs were moved to the Recycle Bin; older
build links and export notes below are historical, not instructions to recreate
them. This policy takes precedence over earlier export guidance.

**End-of-day handoff (2026-10-17):** [220 — Session handoff](220_session_handoff_2026_10_17.md)
is the gameplay resume point: completed gameplay/save/worker changes, final X-ray
measurements and cache checks, reproduction limits, and parked work. Restart Play
and review the final slice toggles in the existing save. Await the player's next
priority; do not automatically resume the broader performance/water backlog.
This closeout changes documentation only; no export, commit or overnight task.

**X-ray slice reuse (2026-10-17):** [219 — X-ray slice cache](219_xray_slice_cache.md)
keeps unaffected chunks visible and restores cached meshes immediately when
toggling slices or returning to a recent height. Three variants per chunk bound
memory; terrain/season changes invalidate geometry and water refreshes lazily.
Same-height notifications and unchanged X-ray Off/On no longer rebuild the view.
Native cache/lifecycle tests and copied-save checks are recorded in 219.
Restart Play; saves are unchanged and no Windows export was produced.

**X-ray performance (2026-10-17):** [218 — X-ray performance](218_xray_performance.md)
removes physical-terrain rebuilds triggered by inspection chunk uploads,
reuses Full/Flat meshes, and updates only water for water changes. In the copied
save at 7680×2160, worst first-build frames fall from 319 to 25 ms; the active
sample falls from 310 to 35 ms. Appearance and original saves are preserved.
See 218 for measurement limits and native regressions. Restart Play; no export.

**Moving dwarves and slices (2026-10-17):** [217 — Dwarf slice visibility](217_dwarf_slice_visibility.md)
fixes workers staying invisible after walking downstairs into the selected slice.
The player's queued torch Move physically uses the stairs and lower-room work
positions, but previously ran with the worker hidden. Transform notifications
now update visibility before rendering, including ascent and paused restoration.
Reach/occlusion rules and saves are unchanged. Restart Play; no Windows export.

**Idle planning interruption (2026-10-17):** [216 — Idle planning](216_idle_planning_interruption.md)
preserves stationary idle timers and chair poses when considering work. Repeated
unsuccessful checks no longer restart leisure forever; real assignments still
interrupt immediately. The reported Sollin freeze does not reproduce on a fresh
load: the copied save has usable routes and both lights can be installed.
See 216 for the reproduced idle bug and the limits of the save observation.
Original saves are untouched. Restart Play and reload; no Windows export.

**Shared hauling routes (2026-10-17):** [215 — Shared hauling routes](215_shared_hauling_routes.md)
fixes the newer saved colony's repeated idle delay. Storage leases share bounded
route searches and planning quanta; inventory changes retain valid geometry.
Four awake dwarves receive jobs within 6.5 seconds in the copied-save check,
with ongoing deliveries, exact goods conservation and ten native regressions.
Navigation edits invalidate proofs; claims, needs and CPU limits remain intact.
Original saves are unchanged. Restart Play and load the save; no Windows export.

**Dwarf need indicators (2026-10-17):** [214 — Need indicators](214_dwarf_need_indicators.md)
adds one projected plate, exhaustion or unhappy-face badge above troubled dwarves.
The inspector and Colony detail card explain the same issue and how to help.
Serious/unresolved needs drive the display; normal meals and sleep retain their
existing behavior. Badges respect zoom, terrain, slices, loading and pause.
Native UI/needs tests, three aspect captures and a copied-save check are recorded
in 214. Existing saves need no migration. Restart Play; no Windows export.

**Hauling route fairness (2026-10-17):** [213 — Hauling route fairness](213_hauling_route_fairness.md)
addresses the player's multilevel-save stall. Difficult lower-level pickups now
yield to alternative reachable loads, including for a lone worker; unchanged route searches survive
availability churn from personal needs. Matching still respects proximity,
filters, claims and the existing CPU/probe budgets. The saved colony also has
no edible stored/loose food, a separate cause of work interruptions. Validation
and copied-save evidence are in 213. Restart Play; no Windows export.

**Final terrain state (2026-10-17):** [212 — Final terrain state](212_final_terrain_state.md)
removes completed stone/floor provenance. Schema 2 stores each current terrain
override once, with exploration separate; unchanged cells regenerate from the
seed. Valid schema-1 saves migrate in memory. Copied player quicksave/autosave
load, re-save and reload with exact terrain/exploration preservation; original
files are unchanged. Floor art/appeal and construction plans remain. Ordinary
stone shares the natural 5% mining return. Restart Play; no Windows export.

**Large-save load crash (2026-10-17):** [211 — Terrain restore batching](211_large_save_terrain_restore.md)
fixes the native crash reproduced with the player's larger settlement. SaveManager
now coalesces repeated terrain invalidations per chunk during synchronous restore;
every exact block edit and discovery update still occurs. Copied quicksave and
autosave loads pass, with original save files preserved. A 65,536-edit regression,
save/load round trips and X-ray checks pass. Large restores still take time behind
the loading screen. Its original format is superseded by 212; batching remains.
No Windows export.

**Underground X-ray (2026-10-17):** [210 — X-ray and level reference](210_underground_xray_and_level_reference.md)
adds Full/Flat underground inspection beside the slice tower. Pin the lower
level before raising the slice to retain dashed room/stair references. Working
tools restore real terrain and current-slice picking, while keeping the guide;
closing them resumes inspection. Only discovered interiors appear, construction
updates the shell, and floods retain discovery. Native stacked-room/input/aspect,
terrain-selection, construction, bedroom-lighting and save/load tests pass.
View preferences are transient; the saved slice contract remains unchanged.
Restart Play; no new autoload/global class and no Windows export.

**Torch reach and larger construction (2026-10-17):** [209 — Torch reach and construction](209_torch_reach_and_construction_size.md)
extends wall/log torch radii from 12 to 20 voxels, spreading the existing smooth
falloff over a longer distance. Native rendered profiles confirm a gentler outer
gradient and preserved wall shadows; the full bedroom lighting regression passes.
Stone and both floor tools now allow 32×32 drags, verified through actual input
in both directions with oversized endpoints. Restart Play; no Windows export.

**Optional mining guide (2026-10-17):** [208 — Mining guide](208_optional_mining_area_guide.md)
removes automatic per-voxel terrain outlines. Mine blocks now offers an
off-by-default **32×32 mining guide** toggle. Thick world-aligned ribbons follow
visible terrain, cliffs, slicing and mined/planned cuts; they hide outside mining
and retain the toggle choice when reopening the tool. Sparse geometry expands
coverage for ultrawide displays. Native input, geometry and 16:9/21:9/32:9 layout
checks plus construction/mining feedback regressions are recorded in 208.
Restart Play; no Windows playtest was created or updated.

**DEV construction and bushes (2026-10-17):** [207 — DEV actions](207_construction_and_bush_dev_actions.md)
adds **DEV: Finish construction** to selected stone blueprints/materials crates
and **Spawn Bushes** to Development. Instant completion uses staged stone and
supplies missing materials, safely releasing active workers; obstructed blocks
stay pending. Spawned blueberry, elderberry and strawberry bushes use real
packed art and persistent identities for hauling, Place → Plants and save/load.
Native lifecycle, planting, menu-layout and regression checks are recorded in
207. Restart Play; no Windows playtest was created or updated.

**Loading screen (2026-10-17):** [206 — Panoramic loading screen](206_panorama_loading_screen.md)
covers the world and HUD with a random choice of mountain or underground-settlement
concept art and a beer-filling progress indicator. Each startup/save reload chooses
once; the original mountain art is preserved. 16:9, 21:9 and 32:9 use the same vertical framing;
wider displays reveal more landscape on either side. Reveal waits for all 1,024
overview tiles, water/lighting/scenery queues and save restoration. A transient
clock hold freezes simulation without changing saved pause/speed preferences.
Input, native aspect captures, first-frame coverage and save/reload are tested.
Restart Play. No Windows playtest was created or updated.

**Staged construction (2026-10-17):** [205 — Construction materials crates](205_construction_materials_crates.md)
implements the approved project workflow. Dwarves deliver normal-capacity bundles
to an automatic temporary crate, then one builder hammers each voxel for three
seconds at normal labor speed. Up to two delivery workers use the existing carry
budget (currently four stones). Staged stock and partial work survive interruption
and save/load; cancellation returns unused stone. Inspector progress, crate art,
hammer poses and fifteen native source fixtures are covered. The hammer follow-up
aligns the striking end to each face, adjusts its held scale/stance, and adds six
contact-timed stone knocks through Effects audio. Five targeted native pose,
construction, crafting and recorded-audio checks pass. The continuity follow-up
keeps the same assignment and planted stance across reachable blocks, completing
a four-block column without intermediate idle frames, steps or pose resets.
Blocked targets still replan, and partial work survives interruption. Restart Play.
No Windows playtest was created or updated.

**Terrain sun shadows (2026-10-17):** [204 — Terrain sun shadows](204_terrain_sun_shadows.md)
fixes strawberry/prop shadows projecting through solid cliffs onto lower ground.
The sun now includes the existing terrain render layer in its caster mask.
Plants retain their shadows; visible cliffs and walls now block sunlight too.
Native shadow, room-lighting, sky-lifecycle and terrain slice/save/reload checks
pass, with a copied-save rendering comparison. Restart Play. No Windows export.

**Dining and game partners (2026-10-17):** [203 — Dining rest and game partners](203_dining_rest_and_game_partners.md)
keeps a diner seated after a successful meal, handing the chair to interruptible
idle rest with no standing frame or second sit-down. Empty hands lower smoothly.
Board-game eligibility now uses the six-hour cooldown, not the twelve-hour
happiness thought, so available recent players can join. Five native source
fixtures pass. Restart Play; no Windows playtest was created or updated.

**Room selection (2026-10-17):** [202 — Selected room highlight](202_selected_room_highlight.md)
gives the clicked room a gold outline, a clear floor perimeter and a subtle floor
tint. Only the selected room changes; switching rooms or closing the inspector
updates immediately. Slice visibility, room rebuilds and seal loss retain the
selection lifecycle. The highlight leaves room darkness readable. Restart Play.

**Grid-corner fences (2026-10-17):** [201 — Grid-corner fences](201_grid_corner_fences.md)
replaces the old two-post panel with one Log Fence Post placed at a voxel corner.
Two rails appear between adjacent same-height posts; corners and junctions share
posts. Gates span two grid edges and share their end posts. Thin barriers block
crossings without reserving neighboring floor cells, including route smoothing
and ground-animal movement. Plans preview connections; installed posts make them
physical. Crafting, Move, uninstall and current save/restore are covered by native
checks. Posts are now 1.3 voxels high, with rails at 0.45 and 1.0; gate geometry
and collision heights match the approved lower fence. Old panel layouts adopt
the current post definition and may need moving.
Restart Play. No Windows playtest was created or updated.

**Rudimentary log game (2026-10-16):** [200 — Game on a log](200_game_on_a_log.md)
replaces the fitted board-game table with a squat bark-covered log, rough cut rim,
end grain, charcoal grid and loose stone counters. Its game area is now 3×3;
two independently placed stools sit immediately outside opposite sides (3×5
including the stool tiles, plus dwarf clearance). Native surface-relative hand
reaches, current save/restore and placement labels follow the new geometry.
Existing tables use the current layout on reload under the development-save
policy; reposition their stools onto the new guides if needed. Restart Play.

**Hearth room heater (2026-10-16):** [199 — Campfire and room hearth](199_campfire_and_room_hearth.md)
keeps the campfire's outdoor ring and 3×3 camp area, while the hearth becomes a
2×2 open-front fieldstone heater with lower flames and glowing coals. Place
labels explain both footprints. The hearth inspector reports its enclosed room,
live temperature/comfort and individual heat contribution, or why no room is
heated. Output is now 1600 heat units: one heats a small bedroom without tiny-room
overheating; larger winter rooms may need more. Existing furniture keys, physical
footprints, crafting costs and save format are retained. Restart Play to load the
new model, thumbnail and balance. No Windows playtest was created.

**Fullscreen startup (2026-10-16):** Player-requested display change sets
`window/size/mode=3` (borderless fullscreen). The viewport renders at the display
resolution; 2560×1440 remains only the windowed fallback. Native source and
exported-package checks confirm 7680×2160 window, viewport and render texture
with stretch disabled. Details are recorded in
[198's fullscreen follow-up](198_rudimentary_recreation.md#fullscreen-follow-up).
Restart Play. Screenshot fixtures that need a
fixed window size should launch with `--windowed`.

**Rudimentary recreation shipped (2026-10-16):**
[198 — Rudimentary fences, gates and board games](198_rudimentary_recreation.md)
adds Worker-crafted log fences, automatic log gates and a board-game table with
two independently placed log stools. Two-dwarf games provide +8 happiness for
12 game hours; transient games release safely for needs, movement, furniture
changes and scene teardown. Mood memory/cooldown save with backward-compatible
optional fields. Place has a Recreation category and opposite stool guides.
The scene owns matchmaking; no global class or autoload was added. Native art,
job/needs/furniture regressions and save/reload validation are recorded in 198,
along with the screenshot. Restart Play to use it.
Construction staging subsequently shipped in 205. Performance targets, water
and findings in 177 remain parked as described below.

**Performance work paused (2026-10-15) — current direction:**
Camera panning and slicing feel substantially better, and several major hitches
have been reduced. Pause proactive performance targets and retain the existing
measurements as the baseline. The latest duck change reduces CPU work without
establishing a reliable overall FPS gain; do not automatically continue through
the older performance follow-up lists below.

Current focus: gameplay and usability. The construction workflow discussed in
[193](193_arrival_preparation_performance.md) was approved and
implemented in [205](205_construction_materials_crates.md):
temporary crates, existing carry capacity, one builder and progressive completion
with three seconds of work per voxel. Continue from fresh player feedback.

Keep routine performance awareness during ordinary play. Revisit profiling for
a repeatable hitch or clear regression. The longer normal-speed 30-dwarf soak
through saves, arrivals and seasons remains a later checkpoint; ordinary duck
flight-planning spikes remain recorded for later investigation. Water appearance
and performance, and review findings in 177, stay parked. The intended population
target remains 30 dwarves. The current Windows build and evidence are linked in
[197](197_duck_update_performance.md).

**Duck updates optimized (2026-10-15) — retained baseline:**
[197 — Duck update performance](197_duck_update_performance.md)
retains raw-solid/placed-obstacle body clearance through AnimalNavigation's
bounded, edit-invalidated cache. Normal-speed 30-dwarf profiling with 11 ducks
reduces total duck CPU 17–18% and total wildlife CPU about 8%. Whole-frame
controls are mixed; no reliable overall FPS or worst-frame improvement is claimed.
Ordinary flight planning can still spike to ~17 ms. Duck movement, reactions,
feeding, animation and offscreen updates keep their existing cadence; live water
and canopy checks retain their observation rules. All 1,200 differential updates,
1,017 new clearance assertions, 12 fixtures and 26 final native packaged checks
pass. The package check compares at existing JSON save precision; its initial
over-strict assertion and tiny numeric differences are documented in 197.
Windows build/ZIP refreshed and actual EXE startup passes; restart Play or launch
the release linked in 197. Only two existing runtime files changed; the original
save and all water code remain unchanged. Further performance work is paused
as recorded above; the longer normal-speed 30-dwarf soak is a later checkpoint.
Construction workflow design is the next discussion, before revisiting its
waiting/eligibility implementation. Water appearance/performance and findings
in 177 remain parked. No fog of war or population cap is introduced.

**Shared atmosphere shipped (2026-10-15) — resume here:**
[196 — Shared atmosphere performance](196_shared_atmosphere_performance.md)
replaces fog/sky broadcasts to ~1,300 materials with one scene-owned 320-byte
texture update at the existing maximum 20 Hz. Two normal-speed 30-dwarf controls
reduce first-pan means 20.08–21.36→16.16–16.40 ms and later pans
16.44–17.20→13.04–14.16 ms. First-pan render setup drops ~88%; GPU stays near
3 ms. Repeating the old path confirms a 20.20 ms first pan. P95 remains above
the 60 FPS budget, so further spikes remain. Eight old/new shader image pairs
are pixel-identical. All ten final fixtures, 3,494 native packaged save/reload
checks and release startup pass. Texture ownership stays local to each scene;
day/night, weather, camera overrides, room darkness and save schema are preserved.
Windows build/ZIP refreshed; restart Play or launch the release linked in 196.
Water work is deferred to a later session (user direction, 2026-10-15): the
player is unhappy with its current appearance. Revisit the visual direction
alongside water performance; do not treat today's appearance as an approved target.
The proposed water-focused 30-dwarf profile is parked too. A longer general
normal-speed soak through autosaves, arrivals and seasons remains a follow-up.
Construction/eligibility stays parked for the drop-box and timed-building design
discussion in 193; findings in 177 remain parked. No fog of war or population cap
is introduced. Original save and unrelated existing scripts are unchanged.

**Normal-speed rendering profiled (2026-10-15) — resume here:**
[195 — Normal speed rendering profile](195_normal_speed_rendering_profile.md)
uses copied 30-dwarf settlements at x1 calendar speed. First-pan controls average
20–21 ms/frame; later pans 16–17 ms, with P95 still 31–38 ms. GPU averages about
3 ms; reducing resolution to 720p barely changes whole-frame time. The broad
renderer timer includes water and lighting; its own callback is about 0.2 ms
after mining settles. Shared fog/sky broadcasts to ~1,300 materials are the next
rendering target: direct calls peak at 6.7 ms and cause extra render setup.
A controlled, deliberately stale-fog diagnostic lowers mean frames 18.60→15.98 ms
and render setup 1.15→0.18 ms. This is evidence for sharing live atmosphere data,
not a shipped optimization or promised gain. Actor-light checks cost ~0.6 ms;
cavity-shell rebuilds reach 9.6 ms during mining. Six native runs pass; all 337
production GDScripts and the player save are unchanged after instrumentation.
The release from 194 remains current. Next: shared scene-owned fog/sky data,
then the longer soak. Construction/eligibility and findings in 177 stay parked.

**Gradual overnight season changes (2026-10-15) — resume here:**
[194 — Gradual season transition](194_gradual_season_transition.md)
spreads tree/ground-plant art and existing terrain recolours from midnight to
sunrise. Tree bodies stay alive; logical season/crop rules still turn at midnight.
Queues share a soft 2 ms art/admission budget; terrain uses normal worker batches
and existing upload budgets. Pause/speed follow the calendar; paused loads rebuild
target art within frame budgets. No save schema change or new global class.
At 5/20/30 dwarves, clock peaks fall from 19–20 to 6–7 ms; all 2,925 trees stay
present, versus a baseline dip to 14. The 30-dwarf maximum falls 114→82 ms.
Accelerated-night mean frame times are 3–9% higher: this is a smoother transition,
not an average-FPS improvement. All 14 fixtures and native packaged mid-night
save/load, final art and slice checks pass; Windows build/ZIP refreshed.
Restart Play or launch the new release. Next: profile steady CPU within the
30-dwarf target, then a longer soak. Construction stays deferred for the later
drop-box/material-staging and timed-building discussion in 193. Findings in 177
stay parked; no fog of war or population-cap change is introduced.

**Wildlife arrival hitch reduced (2026-10-15) — resume here:**
[193 — Arrival preparation performance](193_arrival_preparation_performance.md)
identifies duck habitat/flight planning as the main stall. It now resumes across
main-thread frames under a shared soft 2 ms preparation budget. Peak event CPU
falls from 254–260 to 13–14 ms at 5/20/30 dwarves; whole-frame peaks fall from
297–322 to 71–88 ms. Average timings are mixed; this is a hitch improvement.
The same animals enter, with ducks about 3–4.4 seconds later. Attempts, safety
checks and save format remain intact. Pending searches restart from saved seeds.
All 12 fixtures, 45 exact planner comparisons, packaged pending-save recovery
and release startup pass. Windows build/ZIP refreshed; restart Play or launch it.
Construction waiting/access and repeated eligibility probes from 191 are deferred
for a fresh design discussion later (user direction, 2026-10-15; see 193): stage
all project materials in a drop box, then hammer for a duration possibly scaled
by block count. Discuss batch deliveries to address one-stone trips before
optimizing the current workflow. No construction implementation is authorized
by this handoff. Seasonal hitches and a longer soak remain performance follow-ups.
The known baseline dwarf teardown error is retained in 193's evidence; final
runs are clean. Findings in 177 stay parked, and no fog of war or population-cap
change is introduced.

**Autosave freeze reduced (2026-10-15):**
[192 — Autosave performance](192_autosave_performance.md)
moves formatting, JSON, validated file transactions and private-data cleanup to
one worker. Capture stays on the main thread; requests fall from 0.77–1.41 s
to 14.7–17.6 ms. Consecutive 30-dwarf peak frames fall from 1,415 to 80 ms.
The transaction still takes about 1–2 s; ordinary frame variability remains.
Eight fixtures, shutdown joining, native packaged saves/backup recovery and
release startup pass. Windows build/ZIP refreshed; restart Play or launch it.
Save request booleans now mean accepted; completion signals mean committed.
Busy saves/loads reject overlapping requests. Snapshot capture is observational.
Next: wildlife arrival route preparation (up to 348 ms in 191), followed by
construction waits and post-season drift. Use 5/20/30 dwarves. Findings in 177
stay parked; no fog of war or population-cap change is introduced.

**First work effect hitch reduced; event review complete (2026-10-15):**
[191 — Event hitch review](191_event_hitch_review.md)
traces the remaining first-mining stall to dust rendering pipeline preparation.
Shared dust resources and one hidden loading instance remove that compilation
from the first live impact. Standard 30-dwarf first-pan peaks fall from 215.05
to 59.64 ms; later pan timings are essentially unchanged. Ten fixtures, three
native effect checks, packaged copied-save checks and release startup pass.
Windows build/ZIP refreshed; restart Play or launch the new release.
Copied 5/20/30-dwarf event runs identify **autosave as the next priority**:
natural autosave frames reach 1.43–1.54 seconds. Then profile arrival route
preparation (up to 348 ms in WorldEventDirector), construction waits and the
modest post-season frame-time drift. The few-minute runs are not a leak proof
or an hours-long soak. Baseline shutdown errors from 190 recur after sampling
and remain documented; the final run exits cleanly. Findings in 177 stay parked.

**Lighting cleanup hitch reduced (2026-10-15):**
[190 — Lighting buffer disposal](190_lighting_buffer_disposal_performance.md)
identifies the large hitch as clearing the previous calculation's CPU buffers.
One worker now disposes of those private buffers while published lighting stays
available. Native 30-dwarf lighting peaks fall from 231.49 to 5.78 ms; a separate
168.18 ms frame stall remains. The five-dwarf copied settlement runs essentially
unchanged. Eight exact lighting comparisons, all 13 fixtures, native packaged-save
checks and release startup pass. Windows build/ZIP refreshed; restart Play or
launch the new release. Cleanup still consumes CPU and teardown joins it.
Next: [189's](189_session_handoff_2026_10_14.md) long-session/event
review at 5/20/30 dwarves, tracking completed work and waits alongside frame times.
The diagnostic run's dwarf shutdown errors are recorded in 190 for later review.
Findings in 177 remain parked; no fog of war or population cap is introduced.

**Colony size direction (2026-10-14):** The intended maximum is **30 dwarves**.
Use 5/20/30 dwarves for routine performance reviews, with a busy mature
30-dwarf settlement as the main target. The 50/100-dwarf results in 187 are
optional stress evidence, not shipping requirements. Prioritize camera/slice
smoothness, reliable job progress, accumulated items/rooms and long-session
events within the intended population. Thirty dwarves are now measured in
[188](188_job_scheduling_performance.md). This records design direction; runtime population
enforcement is not part of the performance changes.

**30-dwarf job preparation improved (2026-10-14):**
[188 — Job scheduling performance](188_job_scheduling_performance.md)
shares hauling eligibility work across workers and retains prepared construction
stands between route-search slices, with fresh validation before assignment.
Controlled hauling-query CPU falls 88%. Two native 30-dwarf runs build 10–12
blocks and store 12–38 items, versus 1/0 before; the final 20-dwarf run also
progresses in all three jobs. Later 30-dwarf frame times are 11–21% higher as
the world does more work; this is not an FPS win or a complete waiting fix.
All 34 fixtures, native packaged-save checks and release startup pass.
Windows build/ZIP refreshed; restart Play or launch the new release.
Next: long-session/event hitches, including an identified 250 ms lighting
update. Findings in 177 remain parked; no population cap is implemented.

**Colony scaling measured; construction scans reduced (2026-10-14):**
[187 — Colony scaling performance](187_colony_scaling_performance.md)
adds a reproducible 5/20/50/100-dwarf mining/building/hauling yard. A synchronous
construction call now shares obstacle checks across candidate blocks; controlled
query CPU falls 89%, with 35 exact comparisons. Yard mean frame time falls
35–38% at 5 dwarves and 11–17% at 20; 50/100-dwarf tail performance is mixed.
Heavy-colony hauling still stalls, and dwarf updates/renderer CPU dominate at
100. This is not a complete scaling fix. Twelve fixtures, native PCK copied-save
checks and release startup pass. Windows build/ZIP refreshed; restart Play or
launch the new release. Opportunity 3 is long-session/event hitches; the report
also records remaining scheduling, dwarf-update and actor-lighting targets.
Findings in 177 remain parked.

**Duck navigation work reduced (2026-10-14):**
[186 — Duck query performance](186_duck_query_performance.md)
reuses water and clearance queries within one synchronous wildlife update,
then discards them. Saved-game duck CPU falls 19–20%, total wildlife CPU 13%,
and active-pan mean frame time 10–11%; frame P95 falls 6–9%. Isolated stalls
remain. All 1,200 differential updates and 882 navigation comparisons match;
11 fixtures, native packaged-save checks and release startup pass. Offscreen
activity, flight/animation, water and saves retain their behavior. Windows
build/ZIP refreshed; restart Play or launch the new release. Larger-colony
scaling and long-session/event hitches remain opportunities 2 and 3. Findings
in 177 remain parked.

**Room rebuild hitches reduced (2026-10-14):**
[185 — Room rebuild performance](185_room_rebuild_performance.md)
spreads detection and room metadata across frames with a soft 1.5 ms budget.
Saved-game repeated-rebuild peaks fall from 35–42 ms to 1.8–2.1 ms; active-pan
whole-frame maxima fall from 59/64 to 43/47 ms. Average FPS is mixed: total
detector CPU increases 35–43%, and complete room metadata arrives later.
15 exact scheduling scenarios, 36 controlled comparisons, 12 fixtures, native
lighting/inspector checks, copied-save export checks and release startup pass.
Door lighting boundaries remain immediate; saves and water/wildlife are unchanged.
Windows build/ZIP refreshed. Restart Play or launch the new release. Findings in
177 remain parked; later natural pans still have non-room camera spikes.

**Water flow loop improved (2026-10-14):**
[184 — Water flow loop performance](184_water_flow_loop_performance.md)
reuses transfer quantities and receiving ceilings, and avoids temporary reach
arrays. Matched uninterrupted camera runs show 15–22% cheaper water updates
and 8–12% lower whole-frame P95. Controlled full-world water CPU falls 21%.
All 3,200 differential ticks match the prior solver; 16 final-source fixtures,
12,000 stability ticks, native views, packaged-save checks and release startup
pass. Simulation cadence, water behavior and saves remain unchanged. Windows
build/ZIP are refreshed; restart Play or launch the new release. Isolated stalls
remain, including a 37 ms room rebuild. Findings in 177 stay parked.

**Water current-animation spikes reduced (2026-10-14):**
[183 — Water current animation performance](183_water_current_performance.md)
captures compact current inputs and processes them across frames with a soft
1 ms budget. Saved-game current-update peaks fall from 13–14 ms to about 2.3 ms;
first/later pan P99 falls from 35.3/34.5 to 26.5/25.5 ms. Average frame times
change little; the benefit is shorter stalls. Nine fixtures, 103 scheduling
checks, native water views, packaged conservation/slicing and release startup
pass. Simulation, geometry and saves remain unchanged. Windows build and ZIP
are refreshed; restart Play or launch the new release. Findings in 177 stay parked.

**Periodic damp-ground hitch removed (2026-10-14):**
[182 — Moisture rendering performance](182_moisture_rendering_performance.md)
replaces whole-mesh moisture rebuilds with 16×16 tiles, incremental notifications
and a soft 1 ms frame budget. Worst measured moisture update falls from about
37 ms to 1.4 ms. Both fresh/saved pan samples have zero frames above 50 ms;
saved-pan P95 improves from 35.3/31.6 to 24.5/21.9 ms. Fresh averages are slightly
slower: this trades some steady CPU work for shorter stalls. Nine fixtures and
12 exact geometry comparisons pass. Slice/discovery concealment remains immediate;
simulation and saves are unchanged. Findings in 177 remain parked.
Native visuals, packaged-save conservation/slicing and release startup pass;
Windows build and ZIP are refreshed. Restart Play or launch the new release.

**Water simulation performance improved (2026-10-14):**
[181 — Water simulation performance](181_water_simulation_performance.md)
reuses unchanged space ceilings/reach geometry and avoids redundant neighbor
wakes. Native fresh-world average water-update cost falls by about one third;
first/later pan P95 improves from 26.5/33.7 to 21.0/25.8 ms. The original and final
solvers match across 1,400 differential ticks; all 13 regression fixtures pass.
Water behavior, simulation schedule, saves and offscreen activity are unchanged.
Saved-pan first/later P95 improves from 41.8/39.7 to 35.3/31.6 ms. Native water
views, packed-save conservation/slicing and release startup pass; Windows build
and ZIP are refreshed. Restart Play or launch the new release. Renderer spikes
remain a profiling target; this is not steady 60 FPS. Findings in 177 remain parked.

**Wildlife navigation performance improved (2026-10-14):**
[180 — Wildlife navigation performance](180_wildlife_navigation_performance.md)
reuses terrain, clearance and support checks with immediate edit/occupancy/water
invalidation and bounded storage. Wildlife still simulates every frame offscreen.
Saved-pan mean improves from 29.3 to 16.5 ms; P95 from 59.0 to 41.8 ms. Later
fresh-world wildlife P95 falls from 29.4 to 5.9 ms. Ten fixtures, 392 navigation
comparisons and native packaged-save checks pass. Windows build/ZIP refreshed;
restart Play or launch the new release. Water simulation/presentation remain the
next CPU targets; this is not steady 60 FPS. Findings in 177 remain parked.

**Water mesh rebuild performance improved (2026-10-14):**
[179 — Water mesh rebuild performance](179_water_mesh_rebuild_performance.md)
moves geometry construction to snapshot-only workers, coalesces dirty requests,
prioritizes nearby water and budgets main-thread preparation/uploads. Final saved
pan P95 improves from 82.6 to 59.0 ms; fresh-world initial pan from 65.6 to 30.8 ms.
Seven relevant fixtures, 36 exact geometry comparisons and native water views
pass. The refreshed Windows ZIP passes packaged save/slice and native release
startup checks. Simulation, visual detail and saves are unchanged; further CPU
work is needed for steady 60 FPS. Earlier findings in 177 remain parked.

**Performance baseline measured (2026-10-14):**
[178 — Performance baseline and camera stutter](178_performance_baseline_and_camera_stutter.md)
records three native runs, reproducible profiling tools, and the measured water
and wildlife CPU costs behind camera stalls. Production behavior is unchanged;
optimization priorities and validation targets are proposed there. The unrelated
review findings in [177](177_project_review_deferred_2026_10_14.md)
remain parked at the user's request.

**Temporary build exclusion corrected (2026-10-13):**
The root `.gitignore` now excludes all new `tmp/` output, including extracted
playtest executables. Earlier rules covered only selected logs/profiles and let
a 104 MiB test EXE appear in GitHub Desktop's commit list. Keep durable review
evidence under `docs/00_dev_roadmap/concepts/`; do not force-add scratch builds.
Existing tracked review files and local test/build files are preserved.

**Session closed (2026-10-13) — resume here:**
[176 — Session handoff](176_session_handoff_2026_10_13.md)
records the completed art, scale, sky/audio/weather and friends-playtest work,
the latest mining/limb fixes, validation boundaries and current Windows build.
Balanced dwarves and Large wolf are approved and live. Latest fixes have native
verification; player review after restart remains pending. Grass caps, cave/crop
art and broader performance work remain deferred or future work. No new feature
is assigned by this documentation-only closeout.

**Mismatched dwarf limb lighting fixed (2026-10-13):**
[175 — Dwarf limb lighting](175_dwarf_limb_lighting.md)
fixes the dark blue/grey right hand and boot caused by rendering reflected
double-sided meshes. Cached reflected geometry preserves the existing signed
rig transforms and work anchors while presenting positive transforms to the
renderer. All four skin tones match across hands/boots in daylight and torchlight;
six art/gameplay fixtures and a copied-save Ulvrek review pass. Restart Play or
use the refreshed Windows release and ZIP. Existing appearance saves are unchanged.

**Mining resumes after furniture moves (2026-10-13):**
[174 — Mining furniture access](174_mining_furniture_access.md)
fixes cached zero-face mining zones after a bed or other obstruction moves.
Nearby occupancy changes refresh work positions and re-arm pending leases;
rapid changes coalesce without losing removals. Seven fixtures pass. A native
copy of the player's save completes the real bed Move and both remaining wall
blocks. Existing saves need no migration or redesignation. The Windows ZIP
and a new isolated release directory include the fix.

**Ledge pickup and Windows export lifetime fixed (2026-10-13):**
[173 — Ledge pickup and safe exports](173_ledge_pickup_and_safe_exports.md)
lets dwarves collect reachable drops two blocks above the adjacent floor, with
live obstruction checks and unchanged navigation clearance. Ten gameplay/UI
fixtures pass. All three door widths and all 41 packed furniture models load;
the missing door preview came from overwriting a running game's PCK. Exports
now use unique `build/windows/releases/` folders. Close the old game and launch
the freshly exported EXE, or extract the refreshed playtest ZIP into a new folder.
Existing saves work without migration.

**Rudimentary bridge corrected (2026-10-13):**
[172 — Rudimentary log bridge](172_rudimentary_log_bridge.md)
replaces pale flat boards with four bark-covered trunks on rough cross logs across
all five spans. The catalogue icon is refreshed; bank anchors, walking surface,
palettes, placement and saves remain intact. Four fixtures and native comparisons
pass; all other 376 GLBs are unchanged. The Windows playtest ZIP is refreshed.
Restart Play or relaunch the exported game to see the new bridge.

**Windows friends playtest prepared (2026-10-13):**
[171 — Windows playtest](171_windows_playtest.md) fixes all ten
main-scene GDScript warnings without disabling diagnostics. Seven affected
regression fixtures pass, including full save/load and backup recovery. The
Windows x86-64 release includes all 102 runtime JSON definitions and excludes
development files. Share `build/windows/Deepdraft-Windows-Playtest.zip`; keep
its EXE and PCK together. Native DirectX 12 startup/world generation passes.
Player data stays separate. (`tools/windows_playtest/Export.ps1` was deleted on
2026-10-21 at the owner's request; until a new exporter is written, export from the
editor: Project → Export → Windows Desktop.)

**Environmental sound details and rain/storm weather added (2026-10-13):**
[170 — Environment sound details](170_environment_sound_details.md)
completes daytime insects, individual chirps, dry leaves, winter wind, tree
creaks, shoreline laps, warm-night frogs, discovered wet-cave drips and actual
wolf howls. Rain/Storm are scheduled and saved weather types with roof-clipped
rain, muted roof patter, thunder and sky-dial symbols. Cosmetic precipitation
does not add simulated water. Audio follows fractional water surfaces as well
as terrain. Eleven regression fixtures, all 12 new sound families in the native
mixer, and five generated-world reviews pass. Restart Play; existing saves and
audio preferences work. Final listening balance is ready for player review.

**Room sound perspective fixed (2026-10-13):**
[169 — Room audio perspective](169_room_audio_perspective.md)
anchors listening to the terrain at screen centre, using the visible slice and live
mined cells. An elevated orbit pivot had silenced bedroom torches and weakened
nearby snoring. One cached ray supplies all sound owners. Focused camera/audio
fixtures and native playback from a copied player save pass. Restart Play and
load normally; the original save and audio preferences remain unchanged.

**Environmental ambience added (2026-10-13):**
[168 — Environmental ambience](168_environment_ambience.md)
adds wind, nearby foliage, daytime birds, warm-night insects and sparse owls.
Seasonal sunrise, weather, physical shelter and overview zoom shape the mix.
Menu → Audio controls Ambience and Effects independently; preferences survive
scene changes. Native mixer/UI checks, existing fire/water/menu tests, full
save/load regression and generated-world day/night captures pass. Reload the
current project once for the new AmbientAudio autoload, then restart Play.
Existing saves work; listening balance is ready for player review.

**Sky save-load lifetime fixed (2026-10-13):**
[167 — Sky scene lifetime](167_sky_scene_lifetime.md)
fixes sun/moon global-transform errors during the gap in scene reload. The sky
autoload clears scene references on Environment exit and resumes on rebind.
The exact reproducer, sky state checks and full dock-driven save round trip pass.
A native copy of the player's latest quicksave restores five dwarves and 19
furniture pieces; original saves remain byte-identical. Restart Play and load
normally. No migration, new world or art change is required.

**Full-sphere diorama sky implemented (2026-10-13):**
[166 — Diorama sky](166_diorama_sky.md) replaces grey clear
nights with a blue atmosphere, stable stars and a crescent moon. The backdrop
continues below the horizon; day/dawn/dusk and weather drive color, clouds and
haze. Roof-aware fog shares the sky gradient and enclosed rooms remain dark.
Existing celestial light curves, terrain, actors, streaming and saves stay intact.
Six fixtures pass, including 85 native sky checks; 18 final production captures
and before/after evidence are recorded. Restart Play for player review.

**Save-menu reload fixed (2026-10-13):**
[161 — Save menu scene teardown](161_save_menu_scene_teardown.md)
fixes the null viewport error when loading from the dock. Persistence commands
close the menu before emitting signals, and queued layout callbacks ignore
detached docks. Three fixtures pass, including real menu-driven scene reloads.
A copy of the player's pre-fire quicksave restores five dwarves and 14 furniture
pieces with current art; all four original save files remain byte-identical.
Restart Play and load normally; no save migration is needed.

**Production asset structure unified (2026-10-13):**
[158 — Asset structure](158_asset_structure.md) places all
381 models under `assets/models/`, grouped into animals, characters, flora,
rocks, construction, furniture and items. Dwarves belong to
`characters/dwarves/`; trees, bushes, flowers and reeds are peers under flora.
All 146 moved files retain their bytes and importer settings. Definitions,
registry paths, generators, audits, viewers and fixtures use the new locations.
Ten authoring checks, 16 fixtures, native family galleries and pre-change
settlement restoration pass. [61](../60_asset_creation/61_voxel_art_guide.md) lists the current folders. Restart
Play; no new world or save migration is needed. Notes below retain dated layouts.

**Production asset folders flattened (2026-10-13):**
[157 — Asset folder layout](157_asset_folder_layout.md)
removes the seven redundant style folders and moves 297 models directly
under their family/species/part categories. All 381 model files retain their
exact bytes; moved import settings are preserved. Definitions, registry paths,
generators, audits, review tools and tests use the new layout. All 16 affected fixtures pass, and a pre-change settlement
save restores its actors, furniture, trees, wildlife and terrain. Restart Play;
no new world or save migration is needed.

**Shoreline colour correction (2026-10-13):** The reported moving pale shoreline
band came from `MoistureRenderer` covering the new linear terrain palette with
old sRGB vertex colours. Damp grass/dirt now share terrain profiles and shading,
with gradual darkening and paused-season refresh. Explicit moisture coverage
remains a separate debug palette. Five focused fixtures pass, including 314
overlay checks. Matched native 0/30/90-second captures preserve identical water
and moisture states. Evidence: `tmp/shoreline_art_20261013/` and roadmap 145.
Restart Play; no new world or save migration is needed.

**Base world terrain art implemented (2026-10-13):**
[145 — Base world terrain art plan](145_base_world_terrain_art_plan.md)
records all five completed phases. The base terrain uses one
coherent grey rock palette with subtle local variation, full grass voxels,
and restrained dirt. Height-driven rock colour bands and generated grass edge
rings are retired. Turf-over-dirt caps remain deferred. Production uses soft
terrain-only edge shading on merged faces. Overview jobs finish asynchronously with stale-result rejection and
a 4 ms soft upload budget. All 41 distinct regression fixtures pass, including
564 appearance checks, generation, concealment, construction and current save/load.
Native 1600×1000/2560×1440 comparisons and limits are recorded in 145: existing
large mining-command and active-simulation spikes remain. Restart Play.

**Fixed time/Slice controls (2026-10-12):** [142 — Utility HUD](142_fixed_time_slice_hud.md)
adds illustrated Pause, 1×, 2× and Slice at the bottom right. A permanent tower
above Slice has exact ±1/±4 arrows and a live level; off reads Full world and
retains the last height. Wheel over the tower steps height; world scrolling
still zooms. The old upper-left controls, Slice window and Menu shortcut are
removed. The main dock makes room, with a stacked fallback at narrow widths;
menus avoid the utility controls. Native input/layout, saved state, Sky Dial and
navigation checks pass. Logs: `tmp/time_slice_20261012/`. Restart Play.

**Sky Dial (2026-10-12):** [141 — Clock/weather HUD](141_sky_dial.md)
replaces the Clock window, Menu shortcut and upper-left calendar button with a
permanent illustrated upper-right dial. Live time, season/day, seasonal lighting
anchors and current Clear/Foggy/Overcast/Snow drive its original art. Hover/focus
shows year, phase and rise/set. Pause/speed/Slice remain separate; food warnings
sit below and ordinary windows make room. UIRegistry owns the art definitions;
there are no simulation/save changes or new autoloads. Restart Play.

**Remaining illustrated menus (2026-10-12):** [140 — Delivery](140_remaining_illustrated_menus.md)
implements approved plan 139: Craft, Place, Colony, Menu/Development, Inventory
and Rooms. Shared original art, hover/focus names and planned catalog badges
retain direct browser/room flows. World Build and time/weather tests now live in
Development; save/test dispatch uses stable IDs. Colony's flag entry inspects
the actual flag/order or opens its packed Place flow without founding again.
Native layouts, browser stability, worker flag moves and menu checks pass.
Logs: `tmp/remaining_menus_20261012/`. Restart Play; dwarf-screen work stays separate.

**Illustrated Construction (2026-10-12):** [138 — Construction menus](138_illustrated_construction.md)
adds stone-block and Floors icons, then plank/stone floor icons with a Back arrow.
The two floor tools stay usable DEV previews, with flask badges and hover/focus
explanations. Stone costs, floor worker locks and DEV Build are unchanged. Menus
anchor above Construction, which stays highlighted during building. Checks and
native captures: `tmp/construction_art_20261012/`. Restart Play.

**Illustrated Zones (2026-10-12):** [137 — Zones submenu](137_illustrated_zones.md)
adds Storage, Farming and Animal pasture art above Zones. Storage remains live;
the latter two are dimmed, locked planned entries with mouse/keyboard explanations
and no tool dispatch. The shared shelf now uses illustrated controls for both
groups. Native layouts and input checks: `tmp/zones_art_20261012/`. Restart Play.

**Illustrated Orders (2026-10-12):** [136 — Orders submenu](136_illustrated_orders_plan.md)
delivers six approved illustrated icons anchored above Orders, with hover/focus
names, a separated Cancel command and compact live tool feedback. Icons wrap
beside moved inspectors; Zones subsequently gained matching art in 137. Shared icon setup,
real input/cancel/undo and native 960/1280/2560 layouts pass. Captures and checks:
`tmp/orders_art_20261012/`. No simulation/save changes; restart Play.

**Illustrated dock (2026-10-12):** [135 — Command dock](135_illustrated_command_dock.md)
uses the approved Hearth & iron art for all ten bottom commands, with hover/focus
names, square responsive buttons and a copper active notch. UIRegistry owns atlas
regions in dock.json; DockIconButton owns presentation; existing dispatch remains.
Native button/menu/tooltip checks cover 960/1280/2560. Dwarf-screen redesign is
still separate. Captures: `tmp/dock_art_20261012/`.

**Food stage 2 (2026-10-12):** [131 — Food and dining](131_dwarf_food_and_dining.md)
now includes emergency berry picking, dining, hunger/dining penalties and serving
presentation. Stored/loose food wins; only famished dwarves forage within 24 routed
blocks. SurfaceDetailManager owns crop claims/progress/commit. Seats share leisure
claims; tables claim access spots. Dining thoughts replace rather than stack.
Hungry/famished work speed is 90%/75%, mood −5/−15; no starvation damage/death.
Overview shows effects; Details shows last meal/thoughts; failed food searches
drive a quiet HUD warning. Current saves preserve meals, mood and crop work.
The job gate now has 32 fixtures, including DwarfDiningTest. Stage 3's character
screen reorganization remains deferred. Logs/captures: `tmp/dining_20261012/`.

**Distant shrub Moves (2026-10-12):** [134 — Distant Move planning](134_distant_shrub_move_planning.md)
fixes idle wandering repeatedly discarding long uprooting route searches.
Surface work and exact-item Move searches renew their leisure hold while making
measured progress. Surface assignments prove/cache the exact work stand.
Search budgets and normal need/priority interruptions remain unchanged; the
handoff regression includes slow distant routes with live leisure/supervision.

**Settlement flag furniture (2026-10-12):** [133 — Settlement flag](133_settlement_flag_furniture.md)
makes the banner clickable in Object explorer with normal Move/Uninstall and
worker transport. Place → Rooms recovers a packed flag. The founding controller
grants the first flag/squad once and retains the last anchor during transit;
reinstallation updates it. Furniture owns the physical flag and occupancy.
Current saves use required settlement `founded` state; restoration never creates
a second physical flag. The shared job gate now has 31 fixtures.

**Furniture Move (2026-10-12):** [132 — Furniture Move](132_furniture_move.md)
adds Move to installed furniture/workbench and container inspectors. Confirm a
normal placement preview, then workers pack, carry and install that exact piece.
Material, bed ownership and container filters persist; contents empty through
normal uninstall. Cancelling before packing keeps the original; afterwards the
packed item remains recoverable. Current saves include required furniture move
records and destination identities; old development saves need no migration.
The shared job gate now includes FurnitureMoveTest (30 fixtures).

**Dwarf food foundation (2026-10-12):**
[131 — Food, dining and character screen](131_dwarf_food_and_dining.md)
records the agreed plan. Stage 1 adds general edible-item data (five fruits now),
game-hour hunger, reachable storage-first portions, allowed loose-food fallback,
safe interruption/current saves and a Food bar in the shared dwarf inspector.
Berry bushes regrow after two planted days in eligible seasons; packing and
off-season time pause growth. Development → Dwarf tools can make a dwarf hungry
for testing. Stage 2 is now live as described above; only the character-screen
redesign remains stage 3. No starvation damage/death.
The shared job gate includes food/regrowth and now has 29 fixtures.

**Clickable terrain (2026-10-12):**
[130 — Terrain inspection](130_terrain_inspection.md)
adds player material names and facts to Object explorer for exposed walls,
floors and ceilings. Slice/planned faces conceal resources; object and zone
selection retain priority. Block Inspector now lives in Development and honors
mined AIR when reading live chunks. Terrain metadata is owned by BlockRegistry.

**Wall-light mounting heights (2026-10-12):**
[129 — Wall mount heights](129_wall_mount_heights.md)
lets the player aim at a wall cell or use Alt + wheel for either torch. Install
and uninstall share five-block bracket reach from a clear, reachable work floor.
Saved positions stay fixed when floors change; pending lights wait for renewed
access. Actual bracket loss still removes them. Room heat samples the mount's
air cell. Automatic access ladders remain deferred. The job gate has 27 fixtures.

**Permanent floors — development preview (2026-10-12):**
[128 — Permanent floors](128_permanent_floor_preview.md)
adds Construction → Floors → Simple plank/stone floor. Mine a supporting layer,
then plan full blocks; click a blue plan for DEV Build. Carpenter/Stonemason
construction stays locked, with no jobs or inventory claims. Original 8×8×8 voxel
art repeats across the grid and uses live terrain lighting. Completed interior
floor coverage adds +5 flooring appeal in Rooms; mixed materials and tiles under
furniture count. Floor kinds, built terrain and pending plans save. The job gate
included 26 fixtures at this milestone. Rugs, pelts and fitted carpets remain deferred.

**Floor excavation recovery (2026-10-12):** Installed wall torches now depend on
their bracket supports, preserving their height/light/heat when the floor below
is dug out. Milestone 129 also preserves pending plans while access is missing.
Idle dwarves can step
up out of shallow unfinished floor tiles, and footing recovery lifts embedded
feet onto a clear raised floor, including current saved positions. See
[115](115_dwarf_support_recovery.md) and
[128](128_permanent_floor_preview.md).

**Development navigation (2026-10-12):** Development is a standalone dock entry
at the far right, after Menu. Its tools cover spawning, dwarf tools, block
inspection, water, cave inspection and arrival status. The 15 cycling object/arrival commands,
their dispatch, locator methods and cursor state have been removed. QA previews
select explicit fixtures through normal inspection. Current documentation and
playtest instructions use the new menu and ordinary click selection.

**Frameless log doors (2026-10-12):** [117 — Log furniture](117_log_furniture_and_fire_audio.md)
now uses only rough swinging log leaves at all three widths. Fixed frames are
reserved for later door tiers. The live generator, placed icons, hinge positions
and art/catalogue notes agree. Native art, door lighting, passage, sealing and
restoration checks pass. Restart Play/load a current save to refresh existing art.

**Structural stone construction — live (2026-10-12):**
[127 — Structural stone](127_structural_stone_construction.md)
adds Construction → Stone block. Each full voxel costs one physically delivered
rough stone and uses the existing natural rock layer at its height. Mining and
building are separate actions. Constructed slice caps now match natural cut-face
shading; genuine exposed tops keep their normal color. Native comparisons and
construction regressions pass. Real terrain supports navigation and room sealing;
unfinished areas, partial work and built provenance save. Normal mining recovers
one stone. BlockRegistry owns construction definitions; ConstructionController
owns orders and provenance. Wall coverings, combined replacement and floor/rug/pelt
features are outside this milestone. Roadmap 23 is historical and superseded.
Blue plans are clickable during and after construction mode: Object explorer
shows remaining blocks, stone, worker and progress, with safe cancellation.
Additional wall types are deferred and wall finishes remain excluded. Permanent
wood and stone floor previews follow in milestone 128 above. Fitted carpets are
grouped with rugs and pelts for later work.

**Shared job lifecycle and recovery — live (2026-10-11):**
[126 — Lifecycle and recovery](126_job_lifecycle_and_recovery.md)
implements the four steps from [125 — Architecture review](125_jobs_and_dwarves_architecture_review.md):
saved order identity, attempt fencing, progress supervision, complete furniture
fetch planning, shared work execution and fair retained searches. Dwarf development
has a Job inspector with waiting reasons and retry. Run the 25-fixture gate in
`tools/run_job_reliability.ps1`; source/inventory owners remain authoritative.
Receipts are runtime guards, not durable event replay. Current saves include jobs
diagnostics and craft order IDs; no legacy save migration was added.

**Earlier gameplay session handoff:** [124 — Starter colony, 2026-10-11](124_session_handoff_2026_10_11.md)
collects today's bridges, furniture/materials, bedrooms, warmth/privacy, mining
progression, placement timing and grouped storage. It records final verification,
next-session playtests, current save policy and issue status. On 2026-10-12, Alen
provisionally closed issues 001 and 002 as presumed resolved. Neither is active
work; reopen only if the player reports it again.

**Ladder extension dispatch (2026-10-11):** [88 — Ladder task reachability](88_ladder_task_reachability.md)
records the late-session saved-game fix: repeated mining searches above an
unfinished ladder starved its construction job. Budget yields now give other
job types a turn while preserving each type's search progress. The copied save
completes its two remaining sections; no replacement order or new world is needed.

**Grouped storage contents (2026-10-11):** [59 — Storage filters](59_storage_filters.md)
now shows alphabetical totals by item/material across ground zones and containers.
Allow/Disallow is outside-storage only, including Object explorer. Stored goods
remain available colony stock; acceptance filters and relocation keep their roles.

**Immediate furniture placement (2026-10-11):** [123 — Placement timing](123_furniture_placement_timing.md)
removes the hidden two-second build wait for ordinary furniture. All 25 designs
install during one 0.65-second set-down, aimed at their actual floor footprint or
wall mount. Bridges/ladders and plants retain their animated work durations.
Native/headless timing, rotated placement, interruption, cargo and task-family
regression checks pass.

**Privacy, heating and mining progression — live (2026-10-11):**
[122 — Bedroom comfort and mining progression](122_bedroom_comfort_and_mining_progression.md)
adds bedroom leisure privacy with normal visitor exits and filtered sleep routes,
rudimentary hearth crafting (two logs/four stones), sheltered 10°C rock baseline and
actual cold/chilly/hot sleep thoughts. RoomManager owns temperature.json. Ore/gem
progression now requires immutable cover from the natural exterior, including
cliffs, with descent gates for precious resources. Eight fresh-seed samples and
the copied player save are verified; existing mined goods are untouched.

**Development save policy (2026-10-09, user decision):** Backward compatibility
with older development saves is not required. Do not add legacy definitions,
migrations or compatibility branches just to preserve old saves unless the user
explicitly requests them. Keep current-version save/load working; development
changes may invalidate older saves. Use current definitions when loading rather
than retaining obsolete layouts that require players to rebuild items manually.

**Bed ownership and comfort — live (2026-10-11):** [121 — Personal bedrooms](121_personal_bedrooms.md)
adds bed assignments through Object explorer, exclusive use and one assigned bed
per colonist. A single assigned bed makes a personal bedroom; multiple beds make
a barracks. Completed sleep with at least three hours in one's personal bedroom
grants +10 happiness for 24 game hours. Assignments and thought timers save.
Torch range/falloff now light a furnished 4×7 room while doors retain shadows.

**Log beds and bedrooms — live (2026-10-11):** [120 — Beds and bedrooms](120_log_beds_and_bedrooms.md)
adds Worker-crafted 4×3 log beds with wood variants, real reachable/exclusive bed
sleep and ground fallback. Bedrooms require a whole bed, door, enclosure and light;
classification is derived on edits and load. Firelight energy is doubled. A faint
silhouette preserves dwarf readability behind nearby walls/ladders without changing
navigation. Native art/UI, sleep, lighting, cover and save checks are documented.

**Dwarf movement and ground rest — live (2026-10-11):** [119 — Walking and ground rest](119_dwarf_walking_and_ground_rest.md)
raises walking speed to 3.4 blocks/second with a longer planted stride. Sleepers
seek a nearby wall or tree, sit or recline with closed eyes and breathing, then
stand up before returning to work. Quiet spatial snores replace the old emoji.
Bed use followed in milestone 120; no new save fields. Rest search, poses, audio
and lifecycle are tested.

**Crafted materials and appeal — live (2026-10-11):** [118 — Crafted materials and appeal](118_crafted_materials_and_appeal.md)
preserves pine/oak/juniper/applewood through crafting, hauling, storage, equipment,
installation, recovery and saves. Shared wood palettes and a material selector
keep one catalog entry per design. Object appeal combines design and material;
copper/gold profiles prepare future recipes. Appeal-driven room scores/moods and
craftsmanship quality remain later work; bedroom/temperature thoughts are live.
Reload Current Project for the new CraftMaterials registry autoload.

**Log furniture and fire audio — live (2026-10-11):** [117 — Log furniture and fire ambience](117_log_furniture_and_fire_audio.md)
adds single log doors at two/three blocks wide and a double at four, with
approach-driven hinges and full room sealing. The bench and starter torch now
use simpler log art and names. Worker recipes and icons cover the new doors and
bench. Campfires and both torches have quiet spatial crackles on the Work bus;
pause, slices, visibility and source removal silence them. Current saves retain
installed items. Art, crafting, movement, audio and save/backup checks pass.
Door faces now sample their own side of the room seal, fixing black outdoor wood
and light leaking from jambs onto open leaves. All widths/rotations and restore
are covered by `DoorLightingTest`; see [24 — World rendering](../20_player_interface/24_world_rendering.md).

**Full packed furniture crates — live (2026-10-11):** [116 — Full furniture crates](116_full_furniture_crates.md)
enlarges the shared packed furniture model to an 8×8×8-voxel wooden shipping
crate, one full world block, with recessed planks and stepped braces. The 22
shared furniture items use it at native loose/carry size and fit existing shelf
slots. Native art, actual hauling and camp furniture installation are verified.

**Dwarf footing — fixed (2026-10-11):** [115 — Dwarf support recovery](115_dwarf_support_recovery.md)
checks every dwarf before work, leisure or sleep. If another miner removes its
floor, the dwarf settles onto the first physical support below, releases obsolete
routes/claims and drops cargo intact. Current saves with hovering dwarves recover
when resumed. Normal steps, ladders and bridge supports retain their behavior.

**Crafting browser — live (2026-10-11):** [114 — Crafting browser](114_crafting_browser.md)
replaces the tall recipe tiles and permanent queue column with compact icons
under category headings, recipe/category search, and Recipes / Orders tabs.
The selected item's illustration, materials and crafting actions share one
detail card. Queue and Place stay visible on compact screens; live updates
preserve keyboard focus, order controls and scroll positions.

**Log bridges — live (2026-10-11):** [113 — Log bridges](113_log_bridges.md)
adds Worker-crafted kits, Place → Access previews, two-block decks spanning up
to five water blocks between equal-height banks, and installation from one bank.
Completed decks support walking/hauling while water flows underneath. Closing,
evacuation, kit recovery, interrupted work and current saves are verified.
Placement now snaps bank faces/riverbed hits to landings and auto-aligns across
the river; real mouse clicks and the playtest seed are covered by the input fix.
Workers can build from either landing regardless of the preview's anchor bank,
fixing saved plans that demanded a route across the unbuilt crossing. Opposite-bank
mouse placement, real delivery and builder facing are regression-tested.
Bogorn's bridge-corner fall is fixed: moving shortcuts now check the actual actor
position, with safe recentering after interruption. See doc 32 and
`BridgeCornerWalkingTest`; already submerged saved actors require recovery.
Start a fresh development world; older saves lack the required bridges section.

**Previous session:** [112 — Water and wildlife, 2026-10-10](112_session_handoff_2026_10_10.md)
retains the finite-water, finished-gem, movable-stone and duck implementation history.
Use handoff 124 above for the current starting point and remaining work.

**Ducks — live (2026-10-10):** [111 — Duck wildlife](111_duck_wildlife.md)
adds seeded calm-water flocks, male/female voxel art, swimming, shore activity,
short obstacle-checked flights and scheduled aerial arrivals. Quacks/splashes
use Work audio; picking, Follow, slices, live levels and current saves are covered.
Click ducks near water to inspect or Follow them. Start a fresh development world;
old saves without duck fields are not migrated. Egg/breeding/domestication and
duck predation remain future work. Doc 45 owns wildlife behavior.

**Spring-fed rivers and flooding — live (2026-10-10):**
[105 — Rivers and water](105_rivers_and_water.md) implements the
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
shading. [106 — Spring caves and water edges](106_spring_caves_and_water_edges.md)
replaces the decorative spring mouth with real terrain air, a dry ledge and a
wet stone feeding a small pool. Hairline water gaps are closed and tiny
steps share surface lighting. The spring outlet stays aligned for four cells before
its first bend; rough cliff lips are opened through real cave air. Water layout
version 5 requires a fresh development world.
[107 — Water appearance](107_water_appearance.md) replaces fixed
scrolling/bands with sparse glints following measured local currents, quiet lake
shimmer, localized fall foam/splashes and distance fading. Presentation telemetry
does not change water volumes or saves. Whole-world startup coverage is verified.
[108 — Water ambience](108_water_ambience.md) adds procedural
waterfall rush and gentler river burbling, following visible measured currents,
camera focus/zoom and the shared Work volume/mute controls. Still lakes stay quiet.
[109 — Loose water stones](109_loose_water_stones.md) uses the
exact ore-drop shape for both stones: turquoise flecks beside the cave pool and
muted flecks on the lakebed. The old terrain patches and shoreline arch are gone.
Source/drain positions, rates, discharge cap and retained lake level are unchanged.
[110 — Permissions and movable stones](110_item_permissions_and_water_stones.md)
adds outside-storage Allow/Disallow and real Pack/Move/Place work. Natural stones
start disallowed and keep working; Allow alone never auto-hauls placed stones.
Packed/carried/stored stones are inactive; placing restarts their effect at the
new position. Permissions, exact identities, packing progress and move plans save.
Extra stone pairs share the same lifecycle through a grant API; scenario acquisition
remains future work. Initial hydrology is unchanged. Existing development saves
without these fields are rejected, with no migration required.
Development → DEV: Water locates features and provides a reversible test dam.
Ordinary dam construction jobs and physical brewery hauling/recipes remain planned;
flood damage, drowning, floating goods, pumps and pressurized pipes are not enabled.
Reload Current Project after pulling this new autoload. Older development saves
need no migration, per the policy above. Doc 33 owns the water contract.

**User decision: no Jeweller profession/workshop or cutting/polishing stage.**
The old deferred Jeweller proposal is superseded. Stable `_raw` identifiers stay;
display names omit "Raw". Gem-only gloss respects sky access and local lights,
including carried/shelved goods. Native art/lighting, item lifecycle, inventory,
loose support and full save/backup regressions pass; see 104 for captures.
The user rejected the initial angled polygon faces: gems now use only cube
faces on the standard eight-voxels/block grid, with square highlights.

**Equipment view and promotion feedback — live (2026-10-09):** [102 — Equipment feedback](102_equipment_view_promotion_feedback.md)
adds a shared Equipment tab to the Colony detail column and standalone inspector.
It shows the actual owned kit, thumbnail, materials and benefit, plus clearly
planned Iron saw / Iron pickaxe upgrade paths. No upgrade goods or bonuses are
invented. A short original chime plays on completed promotion, including paused
Miner appointments; requests, cancellation, demotion and restoration are silent.
Native UI at three resolutions, completion/restore checks, audio PCM/volume/mute
and existing promotion/inspector/roster/profession/work/wildlife tests pass.

**Carpenter tool promotion — live (2026-10-09):** [101 — Tool promotion](101_tool_based_promotion.md)
requires an available crude carpentry kit. A dwarf reserves and physically picks
it up before becoming a Carpenter. The inspector shows equipped tools; inventory
counts them separately from cargo. Cancellation/sleep and changing professions
release real goods without loss. Equipped and pending promotions survive current
save/load and backup recovery. Miner keeps free promotion/default pickaxe;
Carpenter specialist workshop/recipes and other starter-tool careers remain planned.

**Profession crafting and camp furniture — live (2026-10-09):** [100 — Camp crafting](100_profession_crafting_camp.md)
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

**Dwarf idle activity — live (2026-10-09):** [99 — Idle activity](99_dwarf_idle_activity.md)
adds staggered local strolls, looking around and exclusive use of nearby wooden
chairs after work. Leisure stays interruptible and in the scheduler's available
pool. Same-level local movement, seat removal/sleep cleanup, save-safe poses,
inspection and native seated views are covered; needs and dining are separate.

**Crafting worker selection — fixed (2026-10-09):** [98 — Crafting selection](98_crafting_worker_selection.md)
extends pickup proximity to every Worker recipe. All eligible idle dwarves are
compared at the first material, with bounded pickup/workbench route checks and
exact material reservation. Loose, stockpiled and container ingredients compete;
failed nearby routes cannot hide other workers, materials or workbenches.

**Starter profession tools — live (2026-10-09):** [97 — Starter tools](97_starter_profession_tools.md)
adds Worker-crafted stone hoes, hunting spears, carpentry kits and stone hammers
at the crude workbench, each from one allowed log plus one Rough Stone. Physical
material trips, safe interruption, storage, save/load, Tools inventory and native
menus are covered. Profession cards show tool stock; Carpenter pickup/equipping
followed in milestone 101. Other specialist promotions remain planned.
A forged saw is a Carpenter upgrade, not its entry gate.

**Professions and Miner — live (2026-10-09):** [96 — Professions](96_professions_and_miner.md)
adds the career map and appointment card, usable Worker/Miner changes, and planned
Farmer/Hunter/Carpenter/Stonemason/Blacksmith careers. Colony Labor opens real Work
permissions. Miners receive mining preference and levels 1–5 from completed blocks;
Workers retain normal mining. Safe release, retained XP, permission saves, native
compact layouts and gameplay/save regressions are covered in the milestone.
The agreed equipment follow-up is planned: Miner keeps its default pickaxe/free
promotion; crafted iron and later advanced-metal picks add bounded multi-voxel
mining. Selected careers will need starter tools. See the equipment sections in
[41 — Dwarves](../40_economy_colony/41_dwarf_agents.md) and
[43 — Mining](../40_economy_colony/43_mining_materials.md). Starter tools are now
craftable (97); Carpenter equipping is live (101), while equipment bonuses remain planned.

**Deer and wolf arrivals — live (2026-10-09):** [95 — Deer/wolf arrivals](95_deer_wolf_arrivals.md)
extends shared events with 2–4 deer every 4–7 days and 1–2 wolves every 7–12
days, capped at 18 deer / 4 wolves. Full-footprint routes, separate herd homes,
prey-surplus/local-food gates and saved group progress preserve gentle balance.
Wolves settle before hunting; kills never accelerate or enlarge events.
Startup planning waits for tree occupancy. **DEV: Arrival status** covers all
species; entered animals use ordinary click inspection and Follow.
Four-seed routes, mixed save/backup restoration and wildlife regressions pass.

**Rabbit arrival events — live (2026-10-09):** [94 — Rabbit arrivals](94_rabbit_arrival_events.md)
adds the shared WorldEventDirector scene owner and rabbit provider: scheduled
1–4-member opportunities every 2–4 days, validated edge-to-inland routes,
staggered entry, population caps and expiry. Kills never accelerate or enlarge
arrivals. Saved local hunting pressure is wired for future player hunting;
predation does not add it. Mid-group/mid-stride saves, backup restoration,
four-seed routes, native inspection/Follow and wildlife regressions pass.
**Development → DEV: Arrival status** reviews opportunities and their outcomes.
Deer/wolf support followed in milestone 95; visitor/raid providers remain future work.

**Rabbit wildlife — live (2026-10-09):** [90 — Rabbit wildlife](90_rabbit_wildlife.md)
adds seeded rabbits, gentle grazing and sleep, dwarf avoidance, voxel animation,
shared inspection/Follow and persistence. Click a rabbit to inspect it.
Behavior, native picking/art and full save/backup checks pass.
[45 — Wildlife](../40_economy_colony/45_wildlife.md) records ownership, tuning
and deferred berries and farm theft.

[91 — Rabbit audio](91_rabbit_audio.md) adds three quiet
selection and three grazing variations using the existing Work audio bus/pool.
Click cooldown, nearby/zoom attenuation, pause-aware eating, slice/source cleanup
and native PCM checks pass; audio never changes wildlife needs, RNG or saves.

**Deer wildlife — live (2026-10-09):** [92 — Deer wildlife](92_deer_wildlife.md)
adds up to eighteen deer in six loose groups, articulated grazing/rest/walking,
faster escape and quiet selection/eating sounds. Click deer to inspect them.
Shared GrazerAgent preserves rabbit behavior; species-specific navigation uses
the full deer footprint. Herd identity and mixed populations persist in current
saves. Native, behavior, audio and save checks pass.

**Wolves — live (2026-10-09):** [93 — Wolf wildlife](93_wolf_wildlife.md)
adds four sparse predators with hunger-gated, bounded hunts, prey escape,
atomic captures, long meal satisfaction and protected prey reserves. Wolves
avoid dwarves. Art, soft selection/eating sounds, inspection and saved pursuits
are included. Click wolves to inspect them. Behavior,
four-seed population, native, audio, save/backup and grazer regression checks pass.

**Previous session handoff:** [103 — Evening 2026-10-09](103_session_handoff_2026_10_09_evening.md)
records wildlife/arrivals, professions, starter tools, crafting selection, camp
furniture/leisure, physical Carpenter promotion and Equipment/promotion feedback.
Its recommended next milestone was Carpenter's workbench and first specialist
recipes; promotion is live but specialist production and tool upgrades are not.
It preserves naming/save decisions, final verification and outstanding work.
[89 — Earlier handoff](89_session_handoff_2026_10_09.md) retains
the world, caves, plants and ladder history. Read the relevant system docs as well.

**Seeded world layout — live (2026-10-07):** [66 — Seeded world layout](66_seeded_world_layout.md)
replaces fixed compass geography with seeded ridges, a guaranteed ≥32×32 Y115
summit, substantial mountains, one lowland lake and an optional tarn. Players
choose and clear their own location: no starting plateau or tree exclusion is
generated. All natural cliffs and shores receive rough ledges; summit interiors
stay intact. Full column checks, gameplay,
rendering and save/load verification are recorded there. The user confirmed no
existing saves: no legacy generator or migration path is retained.

**World diagnostics and tin (2026-10-07):** [67 — World generation diagnostics](67_world_generation_diagnostics.md)
records the actual-block surface census, current layout debug measurements, and
tin's 0.66 → 0.64 threshold correction. Four-seed before/after resource samples,
eight-seed gameplay checks and a native debug capture pass. Broader resource
balance remains a separate decision.

**Caves and discovery (2026-10-07):** [68 — Caves and discovery](68_caves_and_discovery.md)
adds connected dry chambers, existing exposed veins and occasional floor-soil
patches. Mining into a cave reveals its connected system; ordinary slicing keeps
it concealed. **Development → DEV: Cave explorer** provides outlines,
camera/slice focus and temporary interior lighting without changing discovery.
The document records playtest steps, verification and deferred cave content.

**Resource review (2026-10-08):** [69 — Resource distribution review](69_resource_distribution_review.md)
records resource measurements with caves, full-resolution deep-gem counts and
the diamond threshold correction (0.90 → 0.91) that restores emerald at Y5–12.
Eight-seed checks pass. Large connected metal deposits motivated the subsequent
prototype and integration passes below; this audit preserved ore noise, depth
bands and temporary testing drop rates.
The user deferred the additional manual cave checks to proceed with this review.

**Ore shape prototypes — offline only (2026-10-08):** [70 — Ore vein prototypes](70_ore_vein_prototypes.md)
compares current deposits, a finer shared field, and separate metal fields with
broader coal on the same eight seeds. Separate fields were the recommended
direction for smaller metal patches, with gold/tin abundance flagged for review.
Tools and measured sections are available for comparison. Live generation,
resource rules and drops were not changed by this prototype study.

**Independent ore fields — live (2026-10-08):** [71 — Independent ore fields](71_independent_ore_fields.md)
integrates smaller separate metal patches with broad coal. All field settings
and fitted cutoffs live in BlockRegistry's `block_resources.json`; gem/soil
selection, depths, drops and terrain shape remain unchanged. Eight seeds set
the cutoffs and eight additional seeds check abundance. This supersedes the
shared-metal-field tuning rules above; final economy balance remains open.

**Surface details — stones and seasonal plants live (2026-10-08):** [72 — Surface details plan](72_surface_details_plan.md)
records the numbered asset, placement, clearing and verification sequence for
boulders, scree, shrubs, flowers and lakeside reeds. [73 — Boulder pilot](73_boulder_pilot.md)
implements three boulder variants, deterministic placement, worker clearing and
persistent removal. Click a visible boulder for inspection. Eight-seed layout,
clearing, forestry regression and save/load checks pass.
**Orders → Clear stones** supports boulders and gatherable scree with click/rectangle
designation and live counts; Cancel orders, Undo and View order keep partial work.
[74 — Gatherable scree](74_gatherable_scree.md) adds three low,
walkable clumps at cliff bases. Three seconds of hand gathering yields one rough
stone, with persistent removal and automatic construction/support displacement.
Click loose-stone clumps to inspect them. Worker, eight-seed, Orders and save checks pass.
[75 — Seasonal wild shrubs](75_seasonal_shrubs.md) adds blueberry,
elderberry and wild strawberry with four-season voxel art, picked-crop variants,
deterministic habitats and nonblocking single-tile support. **Harvest plants**
keeps plants for one crop per eligible season; **Clear shrubs** permanently removes
them and yields one cutting (100% for all three species, configured in JSON).
Cutting growth subsequently shipped in milestone 80 below. Separate partial work, harvested cycles and removals persist.
Click shrubs to inspect them. Worker, native Orders, eight-seed and full
save/load checks pass.
[76 — Seasonal wildflowers](76_seasonal_wildflowers.md) adds three
small clump variants with four seasonal appearances and deterministic grassy
habitats. **Clear plants** now covers shrubs and flowers; flower clearing takes
1.5 seconds, yields no items and persists through seasons/load. Building and
support loss also remove flowers. Click flower clumps to inspect them.
Worker, mixed Orders, eight-seed and full save/load checks pass.
[77 — Seasonal reeds](77_seasonal_reeds.md) adds short/tall clumps
with four-season voxel art on dry lake/tarn banks near the actual local waterline.
**Clear plants** includes reeds: 1.5-second hand clearing, no yield, persistent
removal and partial work. Click reed clumps to inspect them. Native lake/tarn,
worker, mixed Orders, eight-seed, regression and full save/load checks pass.
[78 — Combined surface-detail review](78_surface_detail_review.md)
records twelve-seed placement/persistence checks and four-seed native comparisons
against worlds with details disabled. Current density and art scales are retained.
Seasonal refresh enqueue work drops from about 9.8 to 3.2 ms with the same plant
identities and pending order. Broader season-rebuild spikes, also present with
details disabled, remain documented performance follow-up. This completes the
five-category surface-detail plan; larger populations need a fresh review.
[79 — Move and uproot mature shrubs](79_shrub_transplanting.md)
adds inspector **Move / Uproot** and **Place → Plants** for the three mature berry
shrubs. Exact plant identity, crop state, seasonal packed art and unfinished work
survive carrying, storage and save/load. Moving grants no fruit or cutting;
Clear plants still yields its guaranteed cutting. Native worker/UI, storage,
inventory and complete save/backup checks pass.
[80 — Shrub cutting growth](80_shrub_cutting_growth.md):
**Place → Plants** consumes one cutting per young shrub;
JSON defines 3/4/3 growth days and seasonal rates, with winter dormancy. Twelve
young seasonal GLBs, saved player-created identities and **DEV: Grow to maturity**
are live. Native worker/UI, split-crate, storage, seasonal growth and full
save/backup checks pass. Farm plots and honey remain later milestones.
[81 — Surface worker selection](81_surface_worker_selection.md)
fixes distant idle dwarves winning shrub, tree and surface-clearing jobs by queue
order. New work compares eligible idle workers at reachable adjacent work cells,
with resumable ranking/probes, priorities and existing assignments preserved.
Multi-worker and hauling/planting/crafting/mining regressions pass.
[82 — Shrub Move handoff](82_shrub_move_handoff.md) closes the
remaining gap between uprooting and the separate pickup/carry/replant lease.
An available uprooter already beside the packed plant continues the Move;
reachable nearby replacements handle interruption or unavailability. Two-worker
full-Move, equal-distance, budget, cancellation and blocked-route checks pass.
[83 — Shrub planting animation](83_shrub_planting_animation.md)
replaces stationary planting work followed by set-down with one immediate
reach/lower/release action. Mature shrubs take 1.25 seconds, configured in JSON;
cuttings retain three seconds with continuous animation. Native captures and
timing, interruption, planting, hauling, furniture and crafting checks pass.
[84 — Juniper berry harvesting](84_juniper_berry_harvesting.md)
adds one autumn crop from standing mature/ancient junipers (2/4 berries; three
seconds, all in JSON). Inspector and Harvest plants support picking, with mixed
shrub/tree rectangles, cancellation and Undo. Saved crop cycles, separate work,
eight berry-free GLBs and nearby-worker selection pass focused/native/save tests.
[85 — Plant habitats, spacing and flower relocation](85_plant_habitats_spacing_flowers.md)
restricts wild berries to soil below Y44, allows cultivation on soil at any height,
and reserves nonoverlapping 3×3 areas for bushes, flowers and pending/cutting
plants. Flowers now support Move/Uproot/storage/Place with exact variant and
seasonal packed art. JSON bloom seasons and planted-clump queries prepare the
future honey connection; native, eight-seed and full save checks are recorded.
[86 — Rudimentary ladders](86_rudimentary_ladders.md)
adds Worker-crafted wooden sections at the crude workbench: one raw log per
exactly four blocks of height, with no extra top cap. Place → Access previews
the full route/cost; workers
carry and install from below. Explicit rung navigation supports climbing and
hauling, safe interruption, section recovery, and saved partial construction.
The document records native, gameplay, storage, UI and save/backup checks.
The player confirmed the final ladder correction and a staircase made by mining.

[87 — Placement over storage hauling](87_placement_over_storage_hauling.md)
keeps owned furniture available in Place while reserved for storage or being
hauled. Confirmed placement takes priority; a dwarf already carrying the packed
item continues directly to installation. Paused UI, ownership, cancellation,
storage relocation, plant/ladder regressions and save checks are recorded there.

[88 — Ladder task reachability](88_ladder_task_reachability.md)
fixes tall ladder routes passing DEV Walk but failing mining assignment. Shared
reachability searches resume within scheduler budgets; unfinished searches do
not trigger unreachable backoff. The follow-up handles isolated natural cliff
shelves by searching all exact mining stands and handing the proven route to
the worker. The reported seed's 32-block zone now completes automatically.
Native climbing/mining, route invalidation,
worker-selection, hauling, placement and save checks are recorded there.

**Required later connection:** wildflowers must support honey production through
nearby seasonal forage; beekeeping must account for bloom state and clearing.
The proposed design and unresolved tuning are recorded in [42 — Beehives](../40_economy_colony/42_farming_brewing.md#required-future-connection-wildflower-forage).
This honey connection is not implemented yet.
Resource placement remains depth-based for now, as agreed with the user.

**Worker crafting (2026-10-07):** [64 — Worker crafting](64_worker_crafting.md)
records the timber → crude workbench/stump → wooden torch loop, Craft menu,
batch/maintain orders, Pine-default wood choices, four-side access and axe sounds.
First benches are crafted at the timber pickup spot; inspector destinations use
the actual work position. Physical cargo and partial work survive interruptions/load.

**Loose items and explorer correction (2026-10-07):** [63 — Loose item support and explorer](63_loose_item_support_and_explorer.md)
records settling after mining removes support, repair of hovering loose goods on
load, safe pickup interruption, and the shared cabinet styling for Object explorer.

**Entrance lighting follow-up (2026-10-07):** [24 — World rendering](../20_player_interface/24_world_rendering.md)
records the longer entrance fade and actor lighting across solid cells. Movement
clipping was separately recorded as [Issue 002](00_open_issues.md),
provisionally closed by Alen on 2026-10-12; reopen only if reported again.

**Storage follow-up (2026-10-06):** [59 — Storage filters](59_storage_filters.md)
records the shared storage inspector, exact/category rules, relocation ownership,
save compatibility, and runtime/native UI verification.

**Hauling follow-up (2026-10-06):** [60 — Hauling worker selection](60_hauling_worker_selection.md)
fixes newly idle cutters losing nearby lumber to older idle entries or returning
haulers that bypassed worker selection after depositing.

**Colony overview follow-up (2026-10-06):** [61 — Colony overview](61_colony_overview.md)
combines the compact dwarf roster and shared personal details in one window.

**Separate zones navigation (2026-10-06):** [53 — Navigation](53_hearth_iron_navigation.md)
records the navigation foundation, dedicated Rooms button, Orders/Zones split and
lower active-tool banner.

**Tunnel lighting (2026-10-06):** [24 — World rendering](../20_player_interface/24_world_rendering.md)
records live roof-aware skylight, placed lights, entity shading, slice invariance,
door occlusion and the accepted fog/darkness correction, with native/save-load
verification. Visibility only; dwarf work is unchanged.

