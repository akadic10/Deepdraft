# 220 — Session handoff · 2026-10-17

Current resume point after the October 16–17 gameplay, save and X-ray work.
The latest completed changes are [218 — X-ray performance](218_xray_performance.md)
and [219 — X-ray slice cache](219_xray_slice_cache.md). Source validation and
copied-save checks are complete; the final slice-cache change still awaits the
player's review after restarting Play. This end-of-day update is documentation
only. No further implementation, export, commit, push or overnight work was requested.

## Current playable state

Later linked revisions supersede the original layouts and behavior.

| Area | Current behavior and reference |
|---|---|
| Rudimentary recreation | The board game is a rough log with a charcoal grid and stone counters, occupying 3×3. Two separate 1×1 log stools go outside opposite sides, making a 3×5 arrangement. Find it in Rudimentary crafting → Recreation and Place → Recreation. Two eligible dwarves play; replay eligibility uses a six-hour cooldown. See [198](198_rudimentary_recreation.md), [200](200_game_on_a_log.md), [203](203_dining_rest_and_game_partners.md). |
| Campfire and hearth | The outdoor campfire has a 3×3 camp area. The distinct 2×2 stone hearth heats an enclosed room and reports its room/temperature state. See [199](199_campfire_and_room_hearth.md). |
| Fences and gates | Place individual posts at grid corners; rails connect neighboring posts at the same height, sharing junctions. Posts are 1.3 voxels high, with rails at 0.45 and 1.0. Matching gates span two grid edges. See [201](201_grid_corner_fences.md). |
| Room and dwarf feedback | Clicking a room highlights its perimeter and floor. Dwarves show a single relevant unresolved food, exhaustion or unhappiness badge, with matching inspector guidance. See [202](202_selected_room_highlight.md), [214](214_dwarf_need_indicators.md). |
| Dining transitions | Successful seated eating can hand off to seated leisure without the one-frame standing/sitting pop. See [203](203_dining_rest_and_game_partners.md). |
| Construction | Temporary materials crates stage resources beside structural projects. Existing carrying capacity remains four points: six rough stones require loads of four and two. Up to two haulers supply a project, then one builder uses a correctly oriented hammer with contact audio. Work costs one stone and three productive seconds per voxel at normal speed, plus delivery/travel. Reachable consecutive blocks preserve the builder's stance. Staged resources and partial work survive interruption/save. Construction selections allow 32×32. See [205](205_construction_materials_crates.md), [209](209_torch_reach_and_construction_size.md). |
| DEV tools | Finish the selected structural construction instantly and spawn bushes in transport states. See [207](207_construction_and_bush_dev_actions.md). |
| Lighting and shadows | Terrain casts sunlight shadows, preventing props such as strawberries from projecting through solid cliffs. Torch reach increased from 12 to 20 with smooth falloff. See [204](204_terrain_sun_shadows.md), [209](209_torch_reach_and_construction_size.md). |
| Mining guides | Automatic lines between individual voxels are removed. An optional, initially disabled 32×32 mining guide draws thicker area boundaries. See [208](208_optional_mining_area_guide.md). |
| Fullscreen and loading | Fullscreen supports the native display; 2560×1440 remains the nominal viewport size, not a window cap. Loading randomly selects the retained mountain panorama or underground panorama. Equal vertical framing at 16:9, 21:9 and 32:9 reveals more scenery at the sides on wider screens. A beer-fill indicator covers world/HUD/input until readiness, including all 1,024 overview tiles and save restoration. See [206](206_panorama_loading_screen.md). |
| Save state | Large terrain restores coalesce chunk invalidation. Schema 2 stores the current terrain override at each changed position and exploration separately, without completed stone/floor provenance. Returning a voxel to its generated state removes the override. Schema 1 migrates in memory; loading alone does not rewrite the original. Stone uses the same natural mining return rule; preview floors have no material drop. See [211](211_large_save_terrain_restore.md), [212](212_final_terrain_state.md). |
| Hauling and idle behavior | Bounded route searches yield to other candidates and share reusable route/planning results. Inventory changes retain valid geometry work. Unsuccessful work consideration no longer continually restarts stationary idle timers or chair poses. See [213](213_hauling_route_fairness.md), [215](215_shared_hauling_routes.md), [216](216_idle_planning_interruption.md). |
| Dwarves crossing slices | Movement now refreshes visibility as a dwarf descends into or ascends out of the selected slice. The reproduced torch Move used the stairs physically; the worker was previously hidden during the move. See [217](217_dwarf_slice_visibility.md). |
| X-ray | Full/Flat inspection shows discovered underground interiors, with a pinned lower-level reference. Working tools restore ordinary terrain and targeting. Inspection uploads no longer trigger physical cavity rebuilds; water-only changes update water, Full/Flat shares meshes, and recent slice variants are cached. See [210](210_underground_xray_and_level_reference.md), [218](218_xray_performance.md), [219](219_xray_slice_cache.md). |

## Latest validation and evidence

The copied-save X-ray measurements used native **7680×2160**, a Ryzen 7 9800X3D
and RX 9070 XT. These are measured samples, not a universal FPS guarantee.

- In [218](218_xray_performance.md), the worst first-build frame fell from
  **318.757 to 25.011 ms**, with p95 **298.770 to 11.392 ms**. The following
  paused sample's worst frame fell from 300.397 to 11.316 ms; the baseline was
  still finishing initial construction, so these were not two settled views.
  The active-colony sample's worst frame fell from **310.155 to 34.988 ms**;
  median/p95 changed much less. Production budgets, visual quality and simulation
  rate were not reduced. See the [measurement summary](concepts/xray_performance_20261017/summary.json).
- In [219](219_xray_slice_cache.md), the copied save had **56 chunks** at slice
  53 with reference 47. The first transition to the full-height cutoff retained
  **42 chunks** and queued only **14** missing variants. Four subsequent off/on
  cycles, plus X-ray off/on, queued **zero** mesh rebuilds and restored the same
  mesh instances, with all 56 chunks visible before the next frame. The cache
  held 70 variants, bounded to three recent variants per chunk. See the
  [cache summary](concepts/xray_slice_cache_20261017/summary.json).
- The final cache change passed native **XrayViewTest, TimeSliceHUDTest,
  TerrainExplorerTest and ConstructionInputTest**. The preceding performance
  change also passed BedroomLightingTest. These were targeted regressions,
  not a new whole-project suite or long-duration colony soak.
- Original quicksave/autosave and backup hashes remained unchanged during the
  copied-save checks. Earlier schema migration checks preserved exact terrain
  and exploration through schema 1 load → schema 2 save/reload.

## Findings to keep distinct

- **Sollin's persistent freeze:** the exact reported freeze did not reproduce
  after a fresh load. The nearby lights had valid routes and were installed.
  A separate reproducible idle-timer/pose interruption bug was fixed in
  [216](216_idle_planning_interruption.md). Do not claim that this established
  the cause of every stationary dwarf in the player's running session.
- **Torch reached from upstairs:** the exact queued Move in the copied save
  showed Ildgra descending from floor 43 to floor 37 and making valid contact.
  The demonstrated problem was stale slice visibility, fixed in
  [217](217_dwarf_slice_visibility.md), not a reproduced through-floor reach.
  Reach and occlusion rules were not changed by that fix.
- **Hauling and needs:** route starvation was reproduced and corrected, but
  one investigated save also lacked edible stored/loose food. Legitimate need
  interruptions and food shortage must remain distinct from route failures.

## Next session and remaining boundaries

1. Restart Play, load the existing save, and review the final X-ray Slice off/on
   behavior. Previously visited heights should return immediately when still
   cached and valid. This player check is the immediate resume point.
2. Let the player choose the next priority. No unattended work is scheduled.
   A first uncached height still builds affected chunks, and actual terrain,
   season and water changes still refresh relevant data. Ordinary physical
   terrain slice changes have their own cost; the cache does not promise that
   every slice transition requires zero work.
3. Broader performance work, a longer normal-speed 30-dwarf soak, and the water
   appearance/profiling investigation remain parked under
   [197](197_duck_update_performance.md). The construction discussion that was
   pending in the older handoffs is now implemented in
   [205](205_construction_materials_crates.md).
4. Findings in [177 — Deferred project review](177_project_review_deferred_2026_10_14.md)
   remain parked without a new review. Historical issues 001/002 in the
   [issue index](00_open_issues.md) remain presumed closed by the player's
   earlier instruction; do not reopen them without fresh evidence.
5. Thirty dwarves remains the design/performance target, not an implemented
   population cap. No fog-of-war or reduced offscreen simulation was added.
   Decorative floors remain preview construction, without paid worker building;
   construction of natural dirt/grass is future work.

## Workspace and testing precautions

- Work from `P:\Deepdraft` on the existing `master` checkout. It contains many
  accumulated modified/untracked files. Preserve them; this closeout did not
  commit, reset, clean or package the project.
- **Do not create, rebuild, update or package a Windows playtest unless the
  player explicitly asks.** Old release/export links are historical. Ordinary
  feature validation uses the source project.
- Original saves live under
  `C:\Users\akadi\AppData\Roaming\Godot\app_userdata\Deepdraft\saves`.
  Reproduce with copies and isolated `APPDATA`/`LOCALAPPDATA`; verify original
  hashes and avoid rewriting the player's save during diagnostics.
- Native Godot is
  `S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`.
  Run performance comparisons sequentially, without competing tests or exports.
  Temporary X-ray timing wrappers were removed; durable evidence is linked
  above, with scratch diagnostics under the corresponding `tmp` directories.
- Preserve body clearance, terrain identity, discovery, item conservation and
  job cancellation/release behavior when changing routes or rendering.

No game tests were rerun solely for this documentation closeout.
