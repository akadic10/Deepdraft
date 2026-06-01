# 06 - Initial World Load, Sky, Fog, and View Distance Plan

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = keep</span> |
> <span style="color:#d29922;">Yellow = review / move to a more specific plan</span> |
> <span style="color:#f85149;">Red = safe to delete or archive once you are comfortable</span>

Status: plan updated after instrumentation and Stonehearth retest.
Research date: 2026-06-01.

## Document Review - 2026-06-01

This is the active startup-performance plan. Keep the Stonehearth findings, measured Deepdraft
baseline, and revised local-generation direction. Review implementation-order details as new
benchmarks replace the current numbers. Archive any failed local-generation experiment notes rather
than treating them as accepted design.

---

## <span style="color:#3fb950;">KEEP - Goal</span>

Reduce Deepdraft's initial load time and perceived load time by adopting the useful parts of Stonehearth's startup model: a small first playable terrain neighborhood, a bounded 3D flag-placement preview before the full world exists, camera limits that match the renderer budget, and fog/sky settings that hide the edge of generated terrain instead of requiring the renderer to build everything the camera could theoretically see.

The current target is no longer "make full-world startup cheaper." The target is "make only the first local world real, fast."

## <span style="color:#3fb950;">KEEP - Stonehearth Reference Findings</span>

Stonehearth does not appear to make the initial experience fast by rendering a complete world with heavier sky tricks. It splits world creation into stages and only turns a selected area into full terrain.

Retest note:

- On 2026-06-01, after picking a settlement location on Stonehearth's 2D map, the 3D game/banner-placement stage was ready in about 5.28 seconds.
- Camera movement was immediately responsive.
- This strongly suggests Stonehearth's fast path is bounded terrain generation plus renderer-level visibility, not simply faster full-world meshing.

Relevant files reviewed:

- `P:\stonehearth\stonehearth_client.lua`
- `P:\stonehearth\ui\shell\select_settlement\select_settlement.js`
- `P:\stonehearth\ui\shell\select_settlement\map.js`
- `P:\stonehearth\services\server\game_creation\game_creation_service.lua`
- `P:\stonehearth\services\server\world_generation\world_generation_service.lua`
- `P:\stonehearth\services\server\world_generation\terrain_generator.lua`
- `P:\stonehearth\services\client\renderer\renderer_service.lua`
- `P:\stonehearth\call_handlers\new_game_call_handler.lua`
- `P:\stonehearth\services\client\subterranean_view\subterranean_view_service.lua`
- `P:\stonehearth\services\client\sky_renderer\sky_renderer_service.lua`
- `P:\stonehearth\data\weather\sunny\sunny_sky_settings.json`
- `P:\stonehearth\services\client\camera\player_camera_controller.lua`

### <span style="color:#3fb950;">KEEP - What Stonehearth Does</span>

1. World preview is not full terrain.
   - `select_settlement.js` starts a new game by asking the server for map info.
   - `map.js` renders settlement selection as a 2D canvas map with colored cells, forest marks, and overlays.
   - `game_creation_service.lua` returns an overview map derived from world-generation metadata, not a fully instantiated voxel world.

2. Full terrain is generated only after the player picks a settlement area.
   - `DEFAULT_WORLD_GENERATION_RADIUS = 2` in `game_creation_service.lua`.
   - A default 12x8 requested map is expanded for overview, but `generate_start_location` calls `wgs:generate_tiles(i, j, radius)`.
   - Radius 2 means Stonehearth materializes a 5x5 tile area around the chosen settlement rather than the whole blueprint.
   - `world_generation_service.lua` shuffles and generates only those local tiles, yielding between tile phases.
   - Each generated tile runs terrain height generation, heightmap-to-region conversion, water placement, terrain-region insertion, flora placement, and scenario placement.

3. After that local terrain is generated, Stonehearth enters a 3D banner-placement stage.
   - The loading screen calls `stonehearth:embark_client`, then navigates into the game view.
   - `new_game_call_handler.lua` exposes `choose_camp_location`, which uses `stonehearth:camp_standard_ghost` as the placement cursor.
   - The player can move the camera around the generated local terrain, but the only meaningful startup action is placing the town banner.
   - This is the stage shown in the screenshot: real 3D terrain, fogged edges, active camera, and banner placement before the full settlement starts.
   - At this stage, the visible world is terrain plus static ecology such as trees and bushes. Animals, citizens, jobs, economy, and settlement simulation are not created yet.

4. Terrain generation is staged and yield-friendly.
   - `world_generation_service.lua` creates micro maps, height maps, overview maps, and tile data separately.
   - `_generate_tile_internal` generates one tile through terrain, water, flora, and scenarios, with explicit yields between phases when running asynchronously.
   - Heightmaps are converted through engine terrain-region/tessellation systems rather than many script-created mesh instances.
   - The expensive "real terrain" step is local to the chosen tile radius. The overview map is metadata for choosing a place, not the same thing as the generated 3D world.

5. Visibility is a renderer-level concept.
   - `renderer_service.lua` installs visible and explored regions into the renderer.
   - `new_game_call_handler.lua` passes terrain visible/explored region URIs to the client renderer during embark.
   - `create_camp_command` enables fog of war after camp placement.

6. After banner placement, Stonehearth switches from placement preview to early settlement state.
   - The placed banner creates a revealed area surrounded by fog of war.
   - Starter citizens and loadout items appear near the banner.
   - The wider world remains present but darkened/unrevealed outside the starting visibility region.
   - Deepdraft does not have citizens, food, loadouts, or full inventory yet, but it can mimic the handoff with placeholders and a revealed-radius effect.
   - Fog of war is primarily gameplay visibility. It is enabled after the camp is created, calculated from citizens/entities, and installed into the renderer as visible/explored regions. It can reduce what the renderer presents, but it is not the same thing as the earlier performance trick of generating only a bounded terrain area.

7. Vertical visibility is clipped.
   - `subterranean_view_service.lua` maintains a clip height and intersects entity/region visibility against the visible volume.
   - During camp placement, `new_game_call_handler.lua` computes a starting clip height from the terrain surface and applies it before camp creation.

8. Sky and fog are shader-driven and camera-aware.
   - `sky_renderer_service.lua` applies sky gradient textures and updates height-fog shader uniforms over time.
   - `sunny_sky_settings.json` defines time-varying height fog. Midday uses a longer value than dawn, dusk, or night.
   - Weather can reduce vision through `vision_multiplier` values, so visibility can be treated as part of weather/camera presentation.

9. The default camera is comparatively close to the settlement.
   - `player_camera_controller.lua` resets toward the banner or terrain bounds.
   - It uses an approximate camera height of 30 and target distance of 70 for town reset.
   - Zoom can go farther later, but the initial view is a controlled playable area, not an invitation to inspect the full world.

## <span style="color:#3fb950;">KEEP - Deepdraft Current State</span>

Relevant files reviewed:

- `P:\Deepdraft\scenes\main\debug_world.tscn`
- `P:\Deepdraft\data\camera\camera_settings.json`
- `P:\Deepdraft\scripts\systems\Camera.gd`
- `P:\Deepdraft\scripts\systems\WorldGenerator.gd`
- `P:\Deepdraft\scripts\systems\WorldRenderer.gd`
- `P:\Deepdraft\godot_streaming_test.log`

### <span style="color:#3fb950;">KEEP - Current Behavior</span>

1. The world is very large for a first render.
   - `WorldGenerator.gd` defines a 1024 x 128 x 1024 world.
   - That is 134,217,728 possible blocks and 32,768 32x16x32 chunks.
   - The generator precomputes full 1024x1024 world maps before chunk streaming.

2. The initial overview path can request a full-world surface.
   - `WorldRenderer.gd` has `use_block_face_overview = true`.
   - `overview_slice_threshold = 96`.
   - `OVERVIEW_STEP = 1` and `OVERVIEW_TILE_SIZE = 32`.
   - With `slice_y = 127` as the exported renderer default, overview mode is initially active and can build 1024 overview tiles for the entire 1024x1024 map.

3. The normal streaming path is also broad.
   - `view_radius_chunks = 5` means roughly 81 visible chunk columns around the camera.
   - Requesting a column asks the generator for generated chunks in that column.
   - Mesh rebuilding batches columns into regions, but generation still performs substantial work before the first stable scene.

4. Camera and fog currently allow a larger visual promise than the first-load budget.
   - `camera_settings.json` uses far clip 1200, default zoom 85, max zoom 180, and default camera rig y 70.
   - `debug_world.tscn` has fixed Environment fog enabled with `fog_depth_end = 170`.
   - The renderer may still build far more terrain than the fog makes useful.

5. The current measured load is far above the desired target.
   - `godot_streaming_test.log` reports initial load complete after 2068 meshes built.
   - The same log reports `WorldGenerator: stopped in 144.6 s`.
   - Instrumented baseline before center-first overview gating:
     - Total to initial load: about 48.7 seconds.
     - First visible terrain: about 21.6 seconds.
     - Full map precompute: about 21.6 seconds.
     - Full block-face overview: 1024 tiles, about 26.8 to 28.2 seconds.
     - Column generation and region meshes: 0 in overview mode.
   - After moving debug metrics out of maps-ready and gating startup overview to a camera-centered radius:
     - Total to initial load: about 19.8 seconds.
     - First visible terrain: about 15.4 seconds.
     - Startup overview: 128 built tiles for a 121-tile goal, with 896 tiles continuing in the background.
   - This is a useful diagnostic improvement, but it is still far slower than Stonehearth's measured 5.28-second post-map startup.

## <span style="color:#3fb950;">KEEP - Core Hypotheses</span>

1. The major startup cost is world data and terrain materialization, not sky rendering.

2. Fixed fog can hide distant terrain visually, but it does not reduce generation, overview, chunk requests, mesh creation, or node count.

3. Deepdraft's initial slice/overview state can accidentally turn first boot into a full-world surface render.

4. Stonehearth's key trick is a contract between world generation, camera, visibility, and fog: only a small local area becomes real terrain, and the presentation hides that boundary.

5. Deepdraft should not try to make a 1024x1024x128 world cheap on first load. It should make only the first playable patch necessary.

6. Center-first full-world overview is only an interim mitigation. It improves perceived startup by ending the loading state early, but it still depends on full-world precompute and a full overview queue. Stonehearth's 5.28-second behavior points to local terrain generation as the real target.

## <span style="color:#d29922;">REVIEW - Proposed Starting Point</span>

Start with a bounded, local 3D placement world based on Deepdraft's current authored world recipe.

Deepdraft should keep its current world identity: mountain mass in the northwest, lake in the southwest, valley/foothill transitions, and the existing deterministic terrain recipe. The world should start in a limited 3D placement view that looks like terrain and supports camera movement. The start anchor can be auto-picked or player-chosen with the Settlement Flag; either way, it becomes the center of the first playable terrain patch and later streaming rings.

The revised implementation direction should therefore be:

1. Measure startup and prove which stage is slow.
2. Treat the current center-first overview gating as a temporary benchmark aid, not the final architecture.
3. Stop requiring full-world map precompute before first visible 3D terrain.
4. Create a local world-generation path centered on a start anchor.
5. Generate only a bounded local 3D patch around that anchor.
6. Either auto-pick the anchor or let the player place the settlement flag in the local preview.
7. Tune startup camera, fog, far clip, and view radius around that local patch.
8. Add background rings later, still without requiring real settlement gameplay.
9. Add post-flag fog-of-war and starter placeholders later, when the handoff into settlement play matters.

The flag item is useful as a player-facing world-start anchor, but it is not required for raw startup performance. The performance mechanism is bounded terrain generation. The flag simply lets the player choose the patch center and gives future settlement systems a home location.

## <span style="color:#3fb950;">KEEP - Performance Plan By Game Stage</span>

### <span style="color:#3fb950;">KEEP - Pre-Settlement Plan</span>

This section applies now, before camp placement, settlement selection, citizens, or full embark flow are ready.

#### Pre-Settlement Goal

Make the current boot path fast, bounded, measurable, and visually honest.

The player or developer should see a coherent local world quickly, with the camera/fog preventing inspection beyond what has been generated.

The useful pre-settlement flow is:

1. Bounded 3D placement preview: inspect a limited generated surface with camera movement.
2. Start-point selection: choose the first terrain anchor, either by placing the flag or by auto-picking a recipe-valid point.
3. First playable patch: generate and reveal only the area promised by the camera/fog budget.
4. Later handoff: add fog-of-war reveal and starter placeholders when settlement play begins.

At this stage, the flag does not need population, buildings, ownership, storage, jobs, or economy. If used, its job is to choose the first terrain anchor for camera, fog, and streaming during world start. If skipped, the same systems should work from an auto-selected anchor.

#### Pre-Settlement Phase 0 - Measure The Current Startup

Before changing behavior, capture where the 144.6 seconds are going.

Add or collect timing for:

- Full world map generation.
- Overview tile build count and total build time.
- Chunk-column generation count and total generation time.
- Region mesh rebuild count and total rebuild time.
- Mesh instance count at first interactive frame.
- Triangle/vertex count at first interactive frame, if easy to collect.
- Initial camera position, zoom, `slice_y`, and whether overview mode is active.
- Time to first visible terrain.
- Time to first interactive camera input.

Acceptance criteria:

- A single benchmark log can explain startup time by stage.
- The log clearly says whether first boot used overview mode or normal chunk streaming.
- The baseline includes the current 2068-mesh / 144.6-second case for comparison.
- A Stonehearth comparison row is kept in the notes: post-2D-map to 3D banner-placement ready in about 5.28 seconds on the same machine.

#### Pre-Settlement Phase 1 - Disable Full-World Overview As A Boot Path

The current block-face overview is too expensive to be the real first boot solution at full resolution.

Options to evaluate:

- Disable full-world block-face overview during startup.
- Raise or gate `overview_slice_threshold` so startup never enters overview mode accidentally.
- Build overview only after the first playable patch is ready.
- Render overview at a coarse step such as 4 or 8 for map-scale use.
- Build overview only within the camera-visible radius.

Recommended first direction:

- Do not build `OVERVIEW_STEP = 1` full-world overview on boot.
- Treat overview as a later map/debug mode with its own performance budget.
- Keep center-first overview gating only as an interim diagnostic milestone. It reduced measured initial load to about 19.8 seconds, but it still does not match Stonehearth's 5.28-second startup.

Acceptance criteria:

- Startup never builds all 1024x1024 top faces before the developer can interact.
- Overview mode has an independent target for tile count and build time.
- Switching into overview after startup does not stall the game for many seconds.
- The production startup path does not depend on full-world overview completion or full-world map precompute.

#### Pre-Settlement Phase 1A - Replace Full-World Precompute With Local Startup Generation

This is now the most important phase.

Deepdraft currently waits about 15 seconds for full 1024x1024 map precompute before the first terrain can appear. Stonehearth avoids this by using broad metadata for selection and then generating only the chosen local tile radius.

Deepdraft needs a local generation entry point that can answer:

- Given `world_seed` and an anchor position, generate the terrain maps needed for a bounded patch only.
- Preserve the authored macro identity: northwest mountain, southwest lake, valley corridor, lowlands, and foothill transitions.
- Produce enough neighbor-margin data that terrain at the local patch edge is stable when later rings are generated.
- Generate surface blocks and visible vertical faces for the startup camera without filling the entire world.
- Defer deep underground, full metrics, full settlement-candidate scans, full overview, and distant ecology.

Initial implementation target:

- Anchor-centered patch, not whole world.
- Patch radius comparable in spirit to Stonehearth's 5x5 generated tile neighborhood.
- In Deepdraft terms, start with a small chunk-column radius such as 5x5 or 7x7 columns, plus one hidden margin ring for continuity.
- Generate center-first.
- Let the camera become interactive as soon as the central visible terrain is ready.

Acceptance criteria:

- First visible terrain does not wait for full 1024x1024 domain, height, lake, edge, grass-band, or metrics passes.
- First interactive camera target is under 8 seconds, with a stretch goal near Stonehearth's 5.28 seconds.
- Local patch terrain matches the deterministic full-world result for the same seed and coordinates, at least for surface and near-surface blocks.
- Later background rings can attach without visible seams or identity changes.
- Full-world debug metrics are available only after startup, or behind an explicit debug action.

#### Pre-Settlement Phase 2 - Add A Bounded 3D Settlement Placement Preview

Add a limited 3D game view before the full world starts.

This should borrow Stonehearth's post-selection banner-placement stage, while keeping Deepdraft's current world recipe:

- The screen shows a limited 3D terrain preview, not the full terrain world.
- The camera works during this stage.
- The northwest mountain, southwest lake, valley corridor, lowland shelf, and foothill transitions should be implied by the generated local preview and fogged horizon.
- Blocks, trees, and bushes may be present.
- Animals, dwarves, jobs, inventory simulation, economy, and settlement AI are not created yet.
- The only meaningful action, if player choice is enabled, is placing or previewing the settlement flag.

The preview should be derived from deterministic world-layout data:

- Domain class such as lowland, valley, foothill, mountain.
- Coarse height/elevation.
- Water hints.
- Forest/vegetation hints.
- Settlement suitability hints later.
- Fixed authored layout signals such as the northwest mountain and southwest basin/lake.

It should not:

- Start `WorldGenerator.generate()` for full terrain.
- Build all chunk meshes.
- Build the full block-face overview.
- Precompute all 1024x1024 domain/height/water/debug maps.
- Start animals, dwarves, settlement systems, jobs, inventory simulation, economy, or building systems.

Acceptance criteria:

- A limited 3D placement terrain appears before the full world exists.
- The camera can pan/orbit/zoom within the placement budget.
- The terrain preview reflects the current Deepdraft world shape, especially the northwest mountain and southwest lake.
- Static flora can be shown if it is cheap enough for the preview budget.
- No animals or dwarves exist during placement preview.
- No full-world block-face overview or broad streamed chunk generation starts on this screen.
- The preview can run with no action by auto-picking a start point, or with one action: placing the settlement flag.

#### Pre-Settlement Phase 3 - Choose A World Start Anchor

Choose the center of the first playable patch inside the world-start 3D preview before the heavy game view starts.

This can be player-driven with the Settlement Flag, or automatic. Internally it is a world-streaming anchor either way.

Current artifact:

- Item ID: `base:items:special:settlement_flag`
- Item data: `P:\Deepdraft\data\entities\items\resources.json`
- Placeholder model: `res://assets/models/items/misc/settlement_flag.glb`
- Intended dimensions: one-tile footprint, three blocks tall.

Responsibilities:

- Use the current 3D placement preview.
- Pick the center of the first generated terrain patch.
- Pick the initial camera target.
- Pick the initial fog/view-distance boundary.
- Pick the origin for center-first chunk generation.
- Provide a future handoff point for real settlement systems.

Non-responsibilities:

- It does not need to create citizens.
- It does not need to claim territory.
- It does not need to start economy, jobs, storage, or building systems.
- It does not need to be permanent save-game settlement state yet, unless that is cheap and clean.

Possible flow:

1. Show the current bounded 3D terrain preview.
2. Let the player place the flag on a valid standable surface, or auto-select a recipe-valid point.
3. Fade or transition into the bounded playable patch.
4. Generate the first patch around the chosen anchor.
5. Place the camera and fog profile around the anchor.

Acceptance criteria:

- Heavy terrain generation is delayed until after the start anchor is known.
- Flag placement, if enabled, is part of the world-start 3D preview flow.
- The first generated patch is centered on the chosen anchor.
- The player cannot move the camera outside the promised generated/fogged area during startup.
- Removing, replacing, or bypassing the temporary flag later will not require rewriting world generation.
- The anchor exists before expensive local terrain generation if we need the Stonehearth-like path. If using the current fixed world recipe, the anchor may be auto-selected from authored layout data.

#### Pre-Settlement Phase 4 - Add Post-Flag Handoff

After the start anchor is chosen, optionally mimic Stonehearth's transition into early settlement state without requiring full settlement systems. This is not required for the first performance milestone.

Immediate behavior:

- Keep the chosen anchor as the world anchor. If the flag exists, the flag marks it.
- Reveal a small circular or square area around the anchor.
- Darken or hide terrain outside that revealed area with fog of war.
- Spawn temporary starter placeholders near the anchor.
- Enable the normal game UI after placement.

Placeholders can be simple, non-simulated objects:

- Supply crates.
- Tool bundles.
- Bedrolls.
- Marker objects standing in for future dwarves.

Do not create yet:

- Real dwarves.
- Animal entities.
- Food systems.
- Loadout inventory logic.
- Jobs, hauling, economy, or settlement AI.

Acceptance criteria:

- The visual state changes clearly after anchor selection.
- A revealed local area appears around the anchor.
- Starter placeholders appear near the anchor without starting simulation.
- The rest of the generated preview remains fog-of-war darkened or hidden.
- Fog of war is treated as gameplay visibility state first, not as the only mechanism preventing expensive terrain generation.

#### Pre-Settlement Phase 5 - Define A Debug Playable Patch

If flag placement is not enabled, use a deterministic temporary patch center as a fallback.

Patch center options:

- The placed world anchor flag.
- World center, matching the current default camera intent.
- A recipe-derived favorable point near the world center.
- A manually configured debug spawn in data.

The patch should be large enough to test terrain, camera, slicing, and early systems, but not large enough to behave like the whole world.

Initial test sizes:

- Small: 3x3 chunk columns around the center.
- Medium: 5x5 chunk columns around the center.
- Large: 7x7 chunk columns around the center.

Acceptance criteria:

- Boot can generate and render only the debug patch.
- The rest of the world remains unloaded potential that can be derived later from the deterministic world recipe.
- The camera cannot reveal outside the generated patch during startup.

#### Pre-Settlement Phase 6 - Define A Startup Visual Budget

Create an explicit startup visual profile instead of letting camera, fog, renderer radius, and world size drift independently.

Initial target values to test:

- First interactive camera height: 30 to 45 world units above the target.
- First camera target distance or zoom: 60 to 90.
- Initial chunk view radius: 3 to 4, not 5.
- Far clip: 300 to 500 during startup.
- Fog should begin before the unload/edge boundary and reach near-sky color before the far clip.
- Sun shadows should be budgeted explicitly; if kept on, shadow distance should match the startup camera.

Acceptance criteria:

- At default camera and maximum allowed startup zoom, no hard generated-world boundary is visible.
- Fog hides distant slab edges before the camera can inspect them.
- The renderer is not asked to build terrain beyond what the visual profile can reveal.

#### Pre-Settlement Phase 7 - Add Renderer And Worldgen Backpressure

Deepdraft should be able to say "no more terrain this frame" in more places.

Plan items:

- Cap new column requests per frame.
- Cap mesh rebuilds per frame separately from column generation.
- Prioritize center-first visible terrain.
- Generate a surface shell first, then deeper chunks later.
- Avoid generating all vertical chunks in a column when only the current slice can be seen.

Acceptance criteria:

- The first playable patch appears center-first.
- New terrain generation does not cause long single-frame stalls.
- Changing slice height does not force unnecessary full-depth terrain generation.

#### Pre-Settlement Phase 8 - Validate Against Startup Targets

Track performance against the current baseline.

Baseline from current log:

- Initial load complete after 2068 meshes built.
- World generator stopped in 144.6 seconds.

Updated target:

- First visible terrain: under 5 seconds on the same machine if possible; under 8 seconds as the first milestone.
- First interactive debug camera: under 8 seconds; stretch target near Stonehearth's measured 5.28 seconds after leaving the 2D map.
- No visible hard world edge at default startup camera.
- No missing terrain inside the promised camera/fog boundary.
- Deterministic terrain remains stable by `world_seed`.

Current measured Deepdraft after interim overview gating:

- First visible terrain: about 15.4 seconds.
- Startup-ready: about 19.8 seconds.
- This is improved, but still not acceptable compared to Stonehearth.

Stretch target:

- Debug playable patch appears near 5 seconds.
- Background generation is invisible to normal playtesting.

### <span style="color:#d29922;">REVIEW / MOVE - Later Settlement Systems</span>

This section applies after the flag-placement preview can hand off to a real settlement/camp simulation.

#### Later Goal

Turn the bounded placement preview into the start of real settlement play.

The key change is that the chosen anchor stops being only a startup/rendering anchor and becomes the camp/settlement anchor for simulation systems. If the Settlement Flag remains part of the flow, the placed flag represents that anchor.

#### Later Phase 0 - Generate The Settlement-Centered Patch

After anchor selection, materialize only a local terrain patch:

- Start with a patch equivalent to Stonehearth's 5x5 tile idea.
- In Deepdraft terms, choose a radius in chunk columns or macro tiles.
- Generate nearby terrain synchronously enough for first play, then background-fill farther rings.
- Keep the rest of the world unloaded until needed, deriving it later from the deterministic world recipe.

Acceptance criteria:

- Camp/settlement placement only generates the local patch.
- Background generation can continue without blocking the first playable moment.
- The patch center comes from the chosen anchor. If the Settlement Flag is used, the flag supplies that anchor.

#### Later Phase 1 - Add Visibility Regions And Fog Of War

Stonehearth treats visibility as a renderer concept, not only as a camera distance.

Deepdraft should eventually add:

- Visible region.
- Explored region.
- Fog-of-war or equivalent hidden/unseen state.
- Optional vertical clip volume for mining/slicing.
- Entity visibility rules that respect the visible volume.

Acceptance criteria:

- The renderer can distinguish generated terrain from player-visible terrain.
- Hidden or unexplored areas do not need full visual detail.
- Vertical slicing does not expose unseen underground content accidentally.

#### Later Phase 2 - Expand Weather, Sky, And Height Fog

Once local terrain generation is bounded, deeper sky/fog work becomes more valuable.

Stonehearth-like presentation target:

- The player sees a confident local world, not the whole world.
- The horizon fades to sky before the generated boundary.
- Zooming out increases abstraction and fog, not terrain workload linearly.
- Weather can reduce view distance later through a multiplier.

Acceptance criteria:

- Camera max zoom and far clip cannot reveal terrain that the renderer is not prepared to draw.
- Fog starts early enough to make pop-in and edge hiding intentional.
- Weather can alter view distance without changing core world generation rules.

## <span style="color:#d29922;">REVIEW - Recommended Implementation Order</span>

This is the recommended order after the plan is accepted:

1. Keep startup instrumentation and benchmark against Stonehearth's measured 5.28-second post-map startup.
2. Treat the center-first overview gate as temporary. Keep it only while building the real local startup path.
3. Add a local world-generation path that does not precompute the entire 1024x1024 map.
4. Choose a start anchor, initially auto-picked or optionally selected with the Settlement Flag.
5. Create a debug playable patch centered on the chosen anchor.
6. Generate center-first visible terrain for that patch, then background-fill margin/rings.
7. Create a startup visual budget for camera, fog, far clip, shadows, and view radius.
8. Move full metrics, settlement-candidate scans, full overview, distant flora, animals, and settlement simulation after first interaction.
9. Add renderer/worldgen backpressure for background rings.
10. Later, add post-anchor fog-of-war reveal and starter placeholders.
11. Later, promote the temporary flag into the real settlement/camp anchor if player placement remains valuable.
12. Consider custom height/distance fog shaders if built-in Environment fog cannot hide patch boundaries cleanly.

## <span style="color:#d29922;">REVIEW - Risks And Open Questions</span>

- The old 144.6-second time has been partially attributed. Full overview and full map precompute were major contributors. The remaining unsolved problem is that full map precompute still blocks first visible terrain.
- Godot's built-in Environment fog may be enough for startup, but Stonehearth's height fog is more flexible.
- Lowering far clip and view radius without changing generation may improve rendering but will not solve total startup time.
- The placement preview/local patch must preserve deterministic world identity while remaining much smaller than the full world.
- Local generation must match eventual full-world generation at patch/ring boundaries. This likely requires margin sampling, deterministic coordinate-based noise, and avoiding world-global postpasses in the startup path.
- Terrain below the surface should remain lazy until mining/slicing requires it.
- A temporary flag should stay thin if we use it. If it grows real settlement responsibilities too early, it can slow down the performance work it is meant to unlock.
- The final design must preserve Deepdraft rules: bedrock at Y=0, namespaced block IDs, 3-block nav clearance, and deterministic generation from `world_seed`.

## <span style="color:#3fb950;">KEEP - Things Not To Do Yet</span>

- Do not rewrite gameplay systems before measuring startup stages.
- Do not permanently shrink the world as a substitute for lazy generation.
- Do not only increase fog density while still generating the full world.
- Do not build a full-resolution 1024x1024 overview as part of first boot.
- Do not make camera max zoom larger until the renderer and fog budget can support it.
