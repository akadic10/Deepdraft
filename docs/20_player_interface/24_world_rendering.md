# 24 — World Rendering & Atmosphere

**X-ray slice reuse (2026-10-17, 219):** `XrayController` retains three recent
variants per chunk (`CACHED_LEVELS_PER_CHUNK`), dropping the least recently used.
Slice toggles immediately reuse cached geometry and keep unaffected
chunks visible; only uncached or edited geometry is rebuilt. Cached water and
terrain correctly refresh after changes made in another view or while Off.
- A chunk wholly below or wholly above several slice heights shares one variant for
  them; one extra level over the chunk's top keeps water cut at its top edge apart from
  a live surface above it. A notification at the same height does nothing.
- Full and Flat share each variant. Interior edits retire a chunk's variants at every
  height, and a season change retires them all. Water changes, also while X-ray is off,
  mark cached water stale; it rebuilds alone when that variant is next shown.
- Turning X-ray back on takes up the pending changes instead of rebuilding unchanged
  chunks. The guide moves to the new plane at once while its outline refreshes, and
  picking uses the shown variant's faces. The cache is transient.

**X-ray update performance (2026-10-17, 218):** separates inspection visibility
notifications from physical cavity rebuilds. Actual slice/terrain edits still
update the physical shell; X-ray chunk uploads do not (see "VisibleVolume contract").
Full/Flat switches reuse meshes, and a water-only change rebuilds only the water
mesh, keeping terrain, picking sets and the guide. Copied-save
measurements at 7680×2160 remove the repeated approximately 300 ms stalls.

**Moving dwarf visibility (2026-10-17, 217):** refreshes actor slice
visibility on transform changes (doc 21, "Known limitations"). Moving down into a
cutaway no longer leaves the dwarf invisible until the player changes slices. Upward
crossings, paused restoration and whole-world view use the same existing feet-height
threshold.

**Underground X-ray (2026-10-17, 210):** adds a scene-owned discovered-interior shell
on camera layer 19 (`XrayController`, built through `XrayGeometry` from
`InteriorTracker`'s interior air). Full emits inward walls and supported floors, with no
ceilings; Flat retains floors with three blocks of headroom and their one-block wall
strips. Real terrain
continues supplying shadows and world data. The inspection camera uses a dark
background and a modest shell readability floor; normal lighting returns while
working or when X-ray is off. Interior water uses still surfaces at the live
solver height, clipped to discovered space. Normal water rendering is unchanged.
Pinned floor perimeters and stair boundaries project as dashed, non-interactive
cyan ribbons onto the active slice; no individual-voxel grid is added. Shell
updates are incremental, and construction removes occupied interior air.
- **The camera** sees only layer 19 while X-ray inspects. Its own mask and environment
  come back while a tool works, when X-ray turns off and at scene teardown.
- **What joins the view:** furniture, actors and props with a low or central point of
  their bounds in known interior air gain layer 19, keeping their own slice and animation
  visibility; moving actors are checked again every frame. Lights always gain it, so
  their light still reaches the shell. Terrain batches, outdoor water and damp ground
  never join (the shell draws its own pools); individual water stones still can.
- **Clicks** follow the shell's faces: never a floor's underside or a wall's hidden top,
  and in Flat only faces that open onto air with headroom, as Flat draws them. Terrain
  outside the shell never takes a click (`XrayController.is_terrain_face_visible`).
- **Budgets:** building chunk meshes and the guide share a soft 2.5 ms a frame, and
  sorting the scene's visuals 1.2 ms; one mesh upload is atomic. These and the look
  (background, readability floor, guide colour, width and radius) are the `xray`
  section of `data/ui/time_slice.json`, read through UIRegistry.

**Torch reach (2026-10-17, 209):** the log torch lights a 20-voxel radius (12
before). Its 0.6 attenuation spreads the smooth outer fade over that wider area;
there is no extra shader cutoff or room-wide fill (`light_source` in
`data/furniture/wooden_torch.json`: `range`, `attenuation`, `energy` 2.6). The wall
torch shared this reach until it was retired (doc 234). Energy, warm colour, flicker
and terrain/door shadowing are retained.

**Optional mining guide (2026-10-17, 208; dotted lines 2026-10-26):** no per-voxel
mining grid is drawn. The optional 32×32 guide (doc 23) uses warm, depth-tested ribbons
0.16 voxels wide, without shadows, only at world-aligned area boundaries (X/Z multiples
of 32). Halfway between them, on the other multiples of 16, dotted lines split each
square into 16×16 quarters: ribbons 0.1 wide and fainter, one dash 0.4 long centred on
each block, so a dotted line has a gap at every block edge and where it crosses a solid
line. Each side of a boundary follows its own visible top, and a perpendicular cliff
gets one continuous vertical stripe; a dotted line climbs it a dash per block of height.
Both kinds share one mesh and material. Only columns touching a boundary are sampled,
each column's top read once per line; coverage follows the camera's position and zoom,
widens for ultrawide aspects, and a still view reuses its mesh. A rebuild with the
dotted lines costs about 1.2× the 32-only guide's before them (2026-10-26, a fresh world
at slice 47: 36 ms at 7680×2160 at zoom 46 and 59 ms at zoom 110, against 31 and 48;
9 and 18 ms at 1920×1080). It shares the existing slice/cut invalidation (planned cuts
and mined floors move it) and has no mesh while disabled or outside mining. Tuning:
`area_guide` in `data/terrain/mining_config.json`; a `dotted_cell_size` that does not
divide `cell_size` (or 0) draws no dotted lines.

**Terrain sun shadows (2026-10-17, 204):** terrain is in the sun's
shadow-caster mask. Excluding it let plants on plateaus project isolated shadows
through solid cliffs onto lower ground. Visible terrain now blocks sunlight as
well as local lights; plants keep their normal shadows. Existing slice visibility
controls the rendered casters, while physical roof/door skylight remains derived
from world data. No mesh rebuild, material, sunlight intensity or save changes.

**Shared live atmosphere (2026-10-15, 196):** replaces repeated
fog/sky uniform broadcasts with one scene-owned 20×1 RGBA float texture
(`SceneAtmosphereData`). Every material made by that `UndergroundLighting`
owner binds the same stable texture; changed atmosphere uploads 320 bytes at
the existing maximum 20 Hz cadence. Colours retain the old `source_color`
conversion, sun colours remain linear, and camera environment overrides still
apply. Roof/door/actor exposure and water appearance use the same equations.
The packet is derived data, recreated on scene load, with independent ownership
for separate viewports. Eight native comparisons against the frozen prior
shader are pixel-identical. This changes data delivery, not atmospheric design.
Writing each changed value to every cached material (about 1,300 in a 30-dwarf
colony) cost main-thread time and render setup on every update. Unchanged values
upload nothing, and a material created later binds the same texture and sees its
current contents. The pixel layout is a contract between
`SceneAtmosphereData._pack()` and `atmosphere()` in
`underground_lighting_common.gdshaderinc`: change both together. Pixels are full
floats, so HDR colours keep their range.

**Work effect preparation (2026-10-15, 191):** first-use dust
pipeline compilation was a separate mining hitch. `WorkDustBurst` shares one
immutable box mesh/material while each burst retains its own MultiMesh colors
and transforms. `WorkFeedback` prepares the same format with one hidden
scene-lifetime instance during loading; headless runs skip it. Counts, RNG,
animation, sound and slice behavior are unchanged. The traced first impact's
rendering drops from 199.83 to 2.33 ms. Compilation work moves to loading.
A new effect that brings its own mesh/material combination needs the same
preparation, or its first appearance compiles a pipeline mid-game. Performance
diagnostics now include render setup CPU, which viewport-only render timing
omits (doc 13, Measuring performance). `WorkDustReuseTest` checks the shared
resources and the hidden instance against the frozen original burst.

**Lighting buffer disposal (2026-10-15, 190):** clearing the previous light
calculation's private CPU work buffers runs on a worker. One `clear()` of a large
solve's caches (over a million air and visited entries in the 30-dwarf work yard)
cannot yield to the 2.5 ms solver budget, so
`UndergroundLighting._retire_work_buffers()` swaps in fresh containers and hands the
old ones, which hold only coordinates, numbers and booleans, to `WorkerThreadPool`.
Only one retired set may await disposal; later edits coalesce until that slot
is available. Published light samples, images, textures and scene/world access
stay on the main thread. The solver, actor lighting and concealment rules are
unchanged. Native 30-dwarf lighting peaks fall from 231.49 to 5.78 ms; separate
frame stalls remain. Cleanup still consumes CPU and scene teardown joins it.
`LightingBufferDisposalTest` checks the published light data against the frozen
original solver.

**Water current scheduling (2026-10-14, 183):** snapshots only the
volumes needed for measured/decaying currents and processes animation updates
across frames within a soft 1 ms budget. Pending samples retain their captured
inputs while new telemetry accumulates separately. Shader animation continues
every frame; current changes appear progressively. Reload discards pending work.
Water simulation, geometry, shader detail and save formats remain unchanged.
The sampling rules are in doc 33.

**Damp-ground scheduling (2026-10-14, 182):** replaces the
whole-world moisture mesh with 16×16-column tiles, incremental soil/film
notifications and a soft 1 ms main-thread work budget. Partial tiles resume
across frames. Slice/discovery changes hide existing tiles immediately;
season/debug changes refresh while paused. Terrain colors, moisture simulation,
surface films and saves retain their existing behavior. The old renderer rebuilt
one whole-world mesh every simulated second, overlay closed or not, stalling a
frame each second. `MoistureRenderer` now keeps a disposable index of tracked soil and
surface films, fed by `SoilMoisture.cells_changed` and `WaterManager.surface_changed`;
neither signal changes the simulation, its schedule or saves. Tiles whose analytic
moisture is still changing refresh once per simulated second; settled tiles never
rebuild, and an identical rebuild keeps its mesh. Work runs in batches of 16 cells
against `rendering.moisture_budget_ms` (1.0, soft) in `data/world_gen/water.json`,
nearest tile first, with every eighth dispatch taking the oldest. Terrain edits hide
and requeue their tile. A new moisture owner or a reload discards the index and
disconnects the old owner.

**Water mesh rebuilds (2026-10-14, 179):** adds private
worker snapshots, coalesced dirty tiles, nearby priority with distant progress,
and a soft main-thread time budget for water mesh preparation/uploads. The
32×32 tile geometry, palette, waterfalls and concealment rules stay intact.
Simulation runs independently of presentation scheduling. The scheduling rules
are in doc 33.

**Rain and storms (2026-10-13, 170):** adds two scheduled and
saved weather IDs with cloud/haze overrides and one bounded local rain mesh.
Spring, summer and autumn can draw them (`data/calendar/weather_schedule.json`);
winter keeps snow. Actual roofs and the visible slice clip streaks, including
visually removed roofs over rooms. Rain presentation never adds simulated water or flooding.
The sky dial and environmental audio follow the same authoritative weather ID.
WeatherManager adds the scene's `WeatherPrecipitation` when the weather has a
`precipitation` profile (`data/weather/rain.json`, `storm.json`). It draws at most
`streaks` (180) around the listening focus, each starting on the physical roof
(`UndergroundLighting.roof_height`), and stops at the slice.

**Planned weather effects (not implemented):** snow cover would build at about
+0.0007 per minute while it snows and melt at −0.0007 per minute in clear, foggy or
overcast weather (−0.0009 in rain and storms). Foggy weather would give dwarves a
`weather_foggy` thought and snow a `weather_cold` thought. Weather never changes
gameplay sight or streaming.

**Sky scene lifetime (2026-10-13, 167):** the sky autoload clears its scene
references when the WorldEnvironment leaves the tree (`tree_exiting`). Save
loading leaves a gap between old scene detachment and replacement; no light
global transforms may be read in that gap. The existing SaveManager rebind
(`rebind_to_current_scene()`) resumes rendering. Each bind first disconnects the
previous exit listener, so a departing older scene cannot clear a newer binding.
A sun or moon that leaves the tree on its own is skipped and hidden in the backdrop. A null check is not enough: the
lights still exist during the gap, so check `is_inside_tree()` before reading a
transform. `SkySceneLifecycleTest` and the dock-driven save round trip cover this.

**Full-sphere sky (2026-10-13, 166):** replaces the plain procedural backdrop
with a continuous directional sky shader, stars and celestial discs. `SkyController` now owns time/weather haze as well as sky color;
clear-night fog no longer retains daytime grey. The same gradient is evaluated
by roof-aware materials, preserving sealed-room darkness. Cloud/star details
are excluded from the ambient cubemap. The lower hemisphere is atmosphere,
and orthographic views use a finite sky FOV. Six fixtures and native captures
pass. World-edge streaming/dissolve work remains separate. The rules are under
§Sky below.

**Settlement shader capacity (2026-10-13):**
a settlement benchmark exposed shader-instance allocation failures with the full forest, 24 dwarves,
wildlife and 48 furniture pieces. Some character parts rendered black with
the existing art. `project.godot` now sets
`rendering/limits/global_shader_variables/buffer_size=131072`, doubling the
default uniform-slot capacity. Both current and pilot benchmark runs use this
setting and reject renderer errors. This is buffer headroom, not a new population
or performance guarantee. Restart Play after changing it.

**Base terrain art (2026-10-13):** doc 145
unifies natural rock into one grey palette and keeps grass as a full seasonal
voxel (the owner's choice), with the brown in a separate dirt voxel below. Dirt uses a
restrained earth family. Every variant of a family shares one authored sRGB palette
(`terrain_blocks.json`, `surface_palettes.json`). Local variation and soft edge normals
run on the existing merged surfaces. Real chamfer geometry was measured and rejected:
it added about 75% more scene primitives, and its regular seams read as masonry. Real
world geometry, support and picking planes retain their cube boundaries. Grass
edge-distance maps and their deferred recolour pass are removed. Since 2026-10-21,
stone, grass and earth also carry the Hearthblock dressing in the same shader
([63](../60_asset_creation/63_shared_art_standard.md#world-and-effect-boundaries)).
Built logs take no profile: they are drawn as pieces (see "Built logs").

BlockRegistry loads `appearance_profiles.json` and builds immutable linear terrain
colour lookups. The existing opaque sRGB `get_color` API remains for UI and
definitions. Terrain vertices carry a profile in colour alpha (`id / 16`);
artificial cut faces add eight to the tag and use quieter detail. Alpha one opts
out, for imported art that keeps its own detail. Only the terrain material enables the shader
treatment; shared actor, prop and water materials retain their existing response.
Exposure/concealment chooses the permitted material before assigning any profile.
The detail is hashed in world space, so it stays stable across tiles, reloads and
camera moves. It fades with projected cell size, and with distance between
`detail_fade.near` and `far` in `appearance_profiles.json`.

The damp-soil overlay is part of this terrain colour contract too. It uses the
same linear palette and appearance tag, then darkens with moisture. Mixing its
former sRGB colours with linear terrain caused a pale band that advanced as the
shore became wet. Seasonal changes invalidate it even while time is paused.
The explicit moisture debug palette is linear and opts out of terrain variation.

Overview batches now complete asynchronously. The main thread polls completion
and uploads finished meshes within a 4 ms soft budget (one mesh upload is atomic).
Tile revisions, slice/season snapshots and a global rebuild epoch reject stale
results. Existing meshes stay visible until a current replacement is ready.
Scene teardown/save reload joins workers before generation maps are cleared.
Seasonal refresh also updates generic added-terrain meshes. Positive edits now batch their exposed
faces, cull shared faces and tag slice-only tops just like constructed stone.

**Gradual seasons (2026-10-15, 194):** existing terrain is admitted for seasonal
recolour in normal worker-sized batches across midnight to sunrise. Trees and
ground plants share the night schedule and a soft 2 ms admission/art budget;
tree root nodes and collision stay alive while only changed art is replaced.
The existing mesh build/upload budgets remain separate. Edits and slice
concealment still invalidate immediately. Pause holds the night schedule;
paused loads rebuild the target appearance within frame budgets. This is a
sequence of discrete replacements rather than a continuous colour crossfade.
Terrain is queued in batches of `overview_tiles_per_frame` tiles: admitting tiles
one at a time copied the edit snapshot and recomputed the whole-overview
statistics for every tile, which made the first trial slower. The cavity shell
and added terrain still rebuild at the boundary. The night schedule and queue
rules are in doc 13 (`WorldClock`).

**Constructed stone (2026-10-12):** built blocks are solid terrain overrides.
`WorldRenderer` draws every solid override from `WorldData` (the added terrain) with the
terrain material, the block's own palette and exposed cube faces, clipped by slice. Tops exposed only because the slice hides a solid
block above use the same `slice_cut_color` dimming as natural overview plates.
Real exposed tops and vertical faces retain ordinary stone color; slice and
terrain changes rebuild this distinction for existing construction too.
The overview masks every overridden cell. Edited cells flush once per frame, and a
cell set back to its generated block loses its mask and its stale excavation hole.
Nothing records who built a block; `ConstructionController` draws only previews and
unfinished plans (doc 212). Plans provide neither terrain nor navigation support
(roadmap 127).

**Floor art removed (2026-10-26):** the plank and stone floors' authored face art
(`ConstructionFloorArt`, which batched GLB boundary faces into the added terrain) left
with the floors. Every built block but a log is drawn as a coloured cube with its kind's
appearance profile; five of the seven profile ids are taken since the planked wood block and
its `timber` boards went (doc 275). The planned Build textures need more profile ids than
the vertex alpha holds, or authored art again (`00_todo.md`, "Build textures by progression").

**Built logs (2026-10-26, doc 275):** a built log is a whole solid block for every system, but
`BuiltLogs` (a WorldRenderer helper) draws it as a Hearthblock piece of
`assets/models/construction/logs.glb`, not as a cube: the loose log stretched to fill its
block (`tools/voxel_assets/built_logs.py`), recoloured for its wood by CraftMaterials and lit
with the goods' material.
- **Pieces by neighbours:** logs of one wood in a row join into one long log, with end grain
  only where the row stops, and upright logs into one post. Where lying logs meet across (+,
  T, L) the top log passes whole over the lower log's fresh-cut shoulders: along X on even
  layers, along Z on odd ones, so stacked corners alternate. Logs of another wood, and lying
  logs against upright ones, stay apart. Each block takes one of four plate variants by
  position. `BuiltLogs.piece_at` picks the piece (`LogJointsTest`).
- **Faces behind a log:** a log's clipped corners leave its block's long edges open, so
  `BlockRegistry.fills_cell` is false for a log. Built blocks keep the faces they turn to a
  log, and the cave shell draws the faces round a log as round the space it was built in.
- **The slice** hides logs above the cut, and a log at the cut shows its end grain.
- **Drawing:** one MultiMesh a piece and wood, and one a piece for the coarse shadow proxies,
  rebuilt when a log comes or goes or the slice moves. A piece is about 560 visual triangles.
- **The preview:** a log drag shows the same pieces in the preview's green.

**Water update (2026-10-10, 105):** terrain overview/chunks now render solid beds;
`WaterRenderer` renders live fractional voxel water in 32×32 tiles, with batched
cube splashes and a shared lighting/fog shader. It follows discovery and slice
changes without exposing hidden caves. `MoistureRenderer` shades damp soil and
provides a soil-only coverage overlay. Positive solid edits such as dams have a
batched terrain mesh. Static `waterline_map` remains generation data, not live
rendering authority. The water rules are in doc 33.

**Startup coverage fix (2026-10-10, 106):** full-world overview scheduling has its own
initialization state (`TerrainTileMesher._overview_initialized`): global invalidation
resets it, a local refresh keeps it. Local discovery/edit queues cannot stand in for
the initial 1,024-tile build: the spring cave's reveal once queued two local tiles
before the first build, startup took that queue as its whole job, and the rest of
the terrain stayed absent under floating trees and water. `WorldTerrainStartupTest`
covers fresh worlds, local updates, slice/save reloads and full invalidation.

**Flying wildlife (2026-10-10):** full-world visibility includes ducks above the
highest terrain layer. An actual slice still hides birds and their wake/splash
effects together. Cosmetic water effects remain outside animal picking bounds
(doc 111; duck rules in [45](../40_economy_colony/45_wildlife.md#ducks--live-2026-10-10)).

## Dwarf readability and firelight — updated 2026-10-11

`DwarfReadability` adds a faint depth-tested silhouette only to portions covered
by nearby actual terrain or the thin ladder slab. It samples bounded local cover
at 5 Hz and shares each animated part's mesh/transform. The pass is disabled on
open ground, omitted from portraits and inherits actor/slice visibility. Cover
beyond 2.5 blocks fades out; the actor's own body never creates a cover region.
Logical 1×1×3 navigation and physical terrain remain unchanged. Readability
color/opacity/reach/timing are loaded by TaskManager from task_config.json.
The depth reconstruction follows the native renderer's reverse-Z convention.

Campfire light energy is 3.2 and the log torch's 2.6 (both doubled in doc 120),
held in each definition's `light_source`.

## Reference

All visual design decisions in this document are derived from analysis of **Stonehearth** (Radiant Entertainment) as the primary reference, specifically its fog system, sky settings, terrain slice view, and world-edge treatment.

---

## Fog & Sky System

### Core Principle: Sky and Fog Must Match

The single most impactful atmospheric decision is that **the sky color and the fog color must be nearly identical**. Stonehearth achieves a seamless world-edge dissolve through this color match — no fog wall and no edge culling. The match is per pixel: their dissolve pass takes the fog colour from the sky behind each fragment (see §Future world-edge dissolve). The terrain simply fades into the sky.

### Daytime Fog Parameters (Target)

| Condition | Fog start distance | Density | Max distance |
|---|---|---|---|
| Clear midday | 0 units | 0.3 | ~500 units |
| Overcast / autumn | 50 units | 0.4 | ~150 units |
| Night / winter | 100 units | 0.5 | ~100 units |

These values are derived from Stonehearth's `sky_settings.json` `height_fog` params at corresponding times of day. The clear daytime setting is the most important — it must feel open, airy, and deep, not claustrophobic.

They are design targets. The live depth-fog values are data: `diorama.atmosphere` in
`data/sky/sky_settings.json` for clear weather, and each weather file's
`sky_overrides.atmosphere`. `SkyController` applies them with the fog colour taken from
the sky's horizon colour, so night fog is never daytime grey.

### Sky

Use the full-sphere `diorama_sky.gdshader` installed by `SkyController` on the
`WorldEnvironment`. Above and below the horizon are continuous atmosphere.
Sky and roof-aware fog share `sky_atmosphere.gdshaderinc`; the broad gradient
also supplies ambient light. Stars and clouds remain background detail.

> **Current implementation:** `SkyController` drives the sky gradient and Sun/Moon
> lights from calendar-keyed data. It also applies weather cloud/haze parameters
> from the owned sky/weather JSON. The world-edge fog redesign remains deferred; see
> §Future world-edge dissolve below, and the live underground-lighting section for the
> current division of responsibilities.

**Light hue is normalised.** `SkyController._apply_light()` divides each sun/moon colour by
its brightest channel: the hue goes to `light_color`, the brightness to `light_energy`. A
bluish curve value therefore becomes a fully blue light every frame. Never copy
Stonehearth's bluish light values (tuned for their renderer); keep sun colours near-white,
with the max channel setting the energy.

**Sky data.** In `data/sky/sky_settings.json`, `sky_gradient_colors` holds the top,
horizon and lower-hemisphere curves keyed to calendar events, and `starfield_brightness`
fades the stars. `diorama` holds the gradient shape, star brightness and scale, the sun
and moon disc radii, the cloud colours and the clear-weather `atmosphere` (cloud cover,
fog density, begin and end). A weather file's `sky_overrides.atmosphere` overrides only
those atmosphere values, and `SkyController` eases toward them.

**The sky depends on view direction only.** `diorama_sky.gdshader` reads `EYEDIR`, never
the camera position or shader `TIME`. Clouds turn with the game hour, so they stop while
the game is paused and wrap without a jump at midnight. Stars use three blended
direction-space projections, so there is no seam or pole. An orthographic camera's
angular FOV becomes `sky_custom_fov`, so world-unit zoom cannot stretch the stars.

**Only the broad gradient lights the world.** The radiance-cubemap pass
(`AT_CUBEMAP_PASS`) skips stars, discs and clouds, so they never sparkle on surfaces or
brighten interiors. There is no sky mesh, bitmap, seam or ground disc, and the crescent
moon is fixed art, not a lunar phase.

**One Moon per scene.** Each bind reuses the scene's `Moon` node or adds one that never
casts shadows (the sun is the only shadow caster), so repeated binds add no lights.
`DioramaSkyTest` covers these sky rules.

### Atmospheric Depth (Scattering)

Stonehearth keeps a constant light scattering pass active at all times of day. This causes distant objects to fade toward the sky/fog color, giving the scene atmospheric perspective — near trees are dark and saturated, far trees are lighter and desaturated. In Godot, this can be approximated via the `WorldEnvironment` fog with `fog_aerial_perspective` enabled.

---

## World Edge Treatment

### No Special Boundary Required

When the player pans to the map edge, **no special shader, fog wall, or boundary effect is needed**. The fog distance and sky color handle the edge dissolve naturally from the surface view. A dense belt of trees and foliage at the outermost 20–30 blocks of the XZ boundary provides an organic visual termination that works from any camera angle.

### Border Foliage Belt

- Pack flora entities at maximum density in the outermost **20–30 block ring** of the XZ map boundary.
- From the oblique RTS camera angle, this reads as a continuous wilderness wall, not a geometry edge.
- This is the primary edge-hider. Fog is the secondary backup.

### Underground Edge (Slice View Active)

When the terrain slice is active and the player pans to the map edge, they will see the **hollow dark interior of the world** exposed against the sky. Stonehearth demonstrates this works cleanly with no special handling:

- The underground void is near-black.
- The sky horizon is dark enough (especially with atmospheric haze) that the void bleeds into it naturally.
- The player sees a dramatic silhouette of the mountain hollowed against the sky — this is correct and desirable, not a bug.

**No world-edge boundary shader is required for the slice view.** The dark void + dark horizon color match solves it for free.

### Future world-edge dissolve

Not built. Today `SkyController` applies depth fog in the horizon colour (`fog_begin` /
`fog_end` in `data/sky/sky_settings.json`), and the camera's `far_clip` (1024,
`camera_settings.json`) runs well past the fog end, so there is no honest horizon.

**How Stonehearth does it.** A separate edge-dissolve pass redraws the far ~30% of the view
(`frustum_start = 0.7`). Its fog factor reaches fully opaque at the far plane, and its fog
colour is **the rendered sky sampled at that screen pixel**. That is why their terrain and
sky meet in one line. Their atmosphere height fog is a separate mood layer.

**Why a flat fog colour fails.** Terrain fades to one constant while the sky behind it is a
gradient, and the far cutoff does not sit on the sky's visual horizon. The result is always
two lines: where the blocks end and where the horizon band starts. Past attempts, so they
are not repeated blind:

| Attempt | Result |
|---|---|
| Environment depth fog pinned to the far clip | Invisible; the depth mode had no effect on this scene. |
| Exponential fog in the horizon colour | Washed out the whole scene; exponential fog tints everything. |
| Terrain shader fading albedo to a flat colour | Two lines: terrain cutoff and sky horizon. |

A red exponential-fog diagnostic was the one useful step: it proved the Environment fog
reaches terrain and that only the depth mode was dead.

**Rules for the next attempt.**

1. The fog colour must equal the sky behind the pixel: render the sky to a texture and sample
   it, or evaluate the analytic sky gradient for the fragment's view direction. The roof-aware
   lighting shader already evaluates that gradient per fragment (`atmosphere()` in
   `underground_lighting_common.gdshaderinc`), mixed with the flat fog colour by the aerial
   perspective setting.
2. Prove the mechanism with an obvious diagnostic (such as solid red) before tuning values.
3. Change one variable per screenshot, in-engine; headless maths cannot judge the look.
4. Once the dissolve is honest, cap the draw and build distance around the camera to the fog
   distance, so far tiles are neither built nor drawn. The whole map stays reachable.

---

## Terrain Slice View

### Hard Clip, Not Fade

Stonehearth uses a **hard horizontal clip** at `slice_y` — geometry above the slice is completely removed from rendering, leaving a black void. It does not fade or dim.

> **Implemented (2026-06-04):** `WorldRenderer.slice_y` hard-clips the whole map via the
> slice-aware block-face overview (per-column cut tops, strata-only floors, per-tile
> invalidation). See §Slice meshing rules and §Slice known limits under Terrain Render Modes.

### The Black Ceiling Reads as Rock

When the player is working inside a carved underground chamber and the slice removes geometry above them, the black void is not perceived as a missing sky — it reads as the solid mountain above. This effect is free and correct. Do not add ambient fill light or particle effects to the overhead void.

### VisibleVolume contract

`WorldRenderer` is the one visibility interface for overlays (no autoload):

- `is_block_visible(pos)` — inside the slice plane, then (while X-ray inspects) inside the
  discovered shell. The order is always clip first, then the interior set.
- `filter_blocks(blocks)` — the visible subset, order kept; returns the input unchanged when
  the slice is off and X-ray is not inspecting.
- `clip_aabb(aabb)` — slice plane only; a box wholly above the plane comes back zero-size.
- `visible_volume_changed` — any visibility change sets a dirty flag, flushed as at most one
  emission per frame in `_process`. Consumers (mining overlays, water, moisture, construction)
  rebuild on the signal; no consumer may poll.
- The signal is for overlays only and never rebuilds the physical cavity shell or terrain.
  Slice moves (`slice_y`'s setter) and terrain edits invalidate the shell on their own
  paths. X-ray marks the volume dirty with every chunk upload; when the signal also
  rebuilt the whole shell, each upload stalled a frame (doc 218).

Mining zone overlays and previews clip through this contract, so a zone wholly above the
plane disappears (its data is untouched) and designation is WYSIWYG — see
`43_mining_materials.md`. Entities do not use it yet; see `21_camera.md` §Known limitations.

### Underground Lighting Model

**Torch lighting:** each installed log torch (`data/furniture/wooden_torch.json`) adds a
bounded warm omni light and 75 heat units; packed torches are unlit. The terrain
meshes (overview tiles, cavity shell and added terrain) cast local-light shadows,
so rock blocks torchlight. `TerrainLighting.gd` reserves render layer 20 for terrain.
Since the 2026-10-17 fix (doc 204), the sun also
includes that layer in its **shadow-caster** mask, preventing plant/prop shadows
from passing through cliffs. `SkyController` applies `TerrainLighting.configure_sun()`
to the scene's sun on every bind; the terrain meshes get the layer through
`configure_mesh()`. Camera and normal light masks include layer 20. A torch is hidden with
its light when the slice cuts below its flame, preventing illumination over a
sliced-away wall. Terrain identity, material colors and discovery rules are unchanged.

The GPU occlusion check measured zero illumination behind a test wall, versus
0.574 luminance with its local-light shadows disabled. Roof-aware ambient and
directional lighting was added on 2026-10-06, as recorded below.

Stonehearth's slice view works on a surface world where ambient sunlight exists at all depths. **DwarfVoxel is primarily underground — the sunlight model does not reach deep slices.**

The approved model uses entrance skylight, installed local lights, and a small
readability floor. It affects visibility only; tasks, movement, work speed and
dwarf needs do not depend on illumination. Camera slicing never removes a roof
from the lighting calculation.

#### Tunnel lighting study — 2026-10-06 (historical prototype)

The player chose **visibility first** for the next lighting pass: darkness should
make placed lights useful without restricting dwarf work or changing task priority.
The current bright tunnel has two confirmed causes: terrain is excluded from the
sun's shadow-caster mask, and `SkyController` applies sky ambient light without
checking physical roof cover. Dimming the slice cut plates does not shade mined
air spaces, and enabling sun shadows alone would not remove ambient sky fill.

`tools/TunnelLightingStudy.gd` renders a representative covered passage with current
daylight fill, proposed unlit shading, and two existing wall torches. It uses actual
registry stone colours, dwarf models, and controller-owned torch definitions.
The proposed view keeps outside daylight, fades entrance light over seven blocks,
retains a small readability floor, and shades indoor props and dwarves too. Local
torch lights and shadows use their existing authored settings. These values are
study tuning, not accepted production settings.

The fixture's sky access follows a bounded flood through authored 2D air cells;
the hidden roof is treated as intact. Its shader and field are **not connected to
the live world renderer**. Native captures and GPU sample checks are written to
`tmp/tunnel_lighting_review/`; the final run passed with no script errors. Outdoor
luminance stayed identical, and sampled torchlit floor patches were more than 50%
brighter than their unlit equivalents.

A production implementation still needs incremental 3D sky access derived from
physical blocks and executed mining, independent of camera slicing. It must retain
local mining invalidation, undiscovered-resource concealment, outdoor day/night
behaviour, and consistent shading for terrain, dwarves and installed furniture.
Runtime roof removal, slice changes, save/load and mining performance have not
been validated by this study.

#### Live tunnel lighting — shipped 2026-10-06

`WorldRenderer` creates a scene-owned `UndergroundLighting` child. It consumes
`WorldData.block_changed` (exact edits, not mesh streaming signals) and derives
skylight from physical air and roof columns. Mining a skylight updates the air
column below it; closing a passage removes its daylight. Light propagates through
six-connected air with twelve-block falloff, independently on stacked floors
(extended from seven on 2026-10-07).
The affected air region includes a second reach of cells to supply correct
boundary conditions. CPU work drains on a 2.5 ms frame budget; no terrain meshes
are invalidated by lighting updates.

The field stores sparse 32-cubed tiles in four lazily populated texture-array
pages, covering all 4096 possible tiles in the world. A small indirection texture
lets the shared shader sample in world coordinates. Only changed layers upload;
ordinary movement and slice changes require no field rebuild. Untracked/solid
cells retain normal illumination, preserving cut plates and designation previews.
Tracked air attenuates sky ambient and directional light. Installed omni lights
retain their existing range, colour and shadow settings. Air-only interpolation
prevents solid rock from blending daylight into tunnel edges. SkyController owns
the tuning in `data/sky/sky_settings.json`: `entrance_reach_blocks: 12` and
`readability_floor: 0.008` (reduced after the room-darkness follow-up below). In the
main world the Hearthblock lighting replaces that floor with
`hearthblock_lighting.underground_fill` (0.035 of albedo, cool slate tint) and adds a
camera-facing `view_fill` on closed actor and prop materials. Both scale with
`1 − sky access`, so open ground is unchanged
([64 §Lighting](../60_asset_creation/64_hearthblock_art_direction.md#lighting)).

The same shader shades live dwarves, their subsequently attached tool meshes,
installed furniture and loose/carried items. Emissive flames and transparent
placement ghosts retain their own materials. Dwarf portraits explicitly restore
the original tint material and use their separate studio lighting. Lighting data
is derived on scene load from replayed mining; nothing is added to save files.

**Door/room follow-up (2026-10-06):** installed doors now stop the skylight flood
using `RoomManager.get_door_boundaries()`, the same four-block doorway columns
used for room sealing. `door_boundaries_changed` queues local updates on install
and uninstall, including changes during an in-progress lighting update. Doors
remain walkable air in navigation. Existing door meshes already block nearby
omni lights through their shadows. The room selection keeps a volume outline
and barely tinted floor rather than a bright unshaded shell. The Room inspector
counts actual installed `light_source` definitions separately from heat units.
SaveManager clears old room/door/heat/light registrations before furniture restore.

**Thin-door face lighting (2026-10-11):** log door wood sits inside the full-block
room seal. Sampling only 0.04 blocks along its normal incorrectly darkened both
faces, including the outdoor face. Installed doors now carry a fixed world-space
doorway plane and clear width as per-instance shader parameters. Faces within the
seal sample the air cell on their own side; open leaves use their physical depth.
Samples stay inside the clear width so nearby solid jambs cannot leak cut-plate
daylight onto an indoor leaf. The plane stays fixed when hinges swing, supports
all four placement rotations, and is recreated through normal furniture restore.
The skylight flood, room seal, local omni lights and other world materials retain
their existing rules. No lighting data is saved.

`DoorLightingTest` reproduces the black outdoor pine door with the actual models
and lighting field. Native pixel checks cover both faces of all three widths in
four rotations, leaves at 45/90 degrees opening both ways, restored furniture and
local firelight. The exterior matches a fully exposed reference; the unlit inner
face remains dark. `UndergroundLightingTest`, `RoomLightingTest` (including scene
fog and torch occlusion), and `LogFurnitureTest` also pass. Captures and reports:
`tmp/door_lighting_20261011/`.

**Room darkness / fog follow-up (2026-10-06):** scene fog was still blending sky
colour into sealed rooms after the lighting shader ran. The earlier native room
fixture disabled fog, so its passing lighting checks did not cover the actual
gameplay appearance. With fog enabled, an unlit room measured 0.150 luminance;
even with the readability glow set to zero, fog alone contributed 0.131.

The shared lighting shader now supplies `FOG` explicitly and scales its opacity
by physical sky access. It reads the active scene (or camera override)
Environment at a maximum 20 Hz, uploading changed values through the shared
scene atmosphere texture (196; originally individual material parameters). Depth / density
and height falloff, the ProceduralSky gradient in the view direction, and sun
scattering remain available outdoors. The gradient is evaluated analytically;
this does not reproduce the engine's blurred sky-radiance sampling or volumetric
fog. That baseline used depth fog and a ProceduralSky; milestone 166 now uses
the shared full-sphere gradient while preserving this roof gate. No additional render
pass, terrain rebuild, atmosphere JSON owner or simulation dependency is added.
The visibility glow is reduced from 0.05 to 0.008 so closed unlit spaces read as
near-black, with only a faint shape remaining.

Validation:

- `UndergroundLightingTest.gd`: native GPU comparison, entrance falloff, blocked
  passages/reopening, roof removal/replacement during an update, stacked floors,
  and replaying mined terrain into a fresh lighting field. Sampled deep floor
  luminance fell from 0.628 to 0.027 with the current tuning; the existing torch
  raised it to approximately 0.17.
- `tools/UndergroundWorldReview.gd`: full generated world, actual renderer and
  mining pipeline, slice invariance, installed torch visibility, dwarf/portrait
  material separation, and loose-item materials. The 272-block tunnel rebuilt
  two terrain tiles; lighting frame work peaked at 2.60 ms in that run.
- `SaveManagerRoundTripTest`, `MiningAnimationTest`, and `FurniturePlaceTest`
  passed. Native captures, reports and logs are in
  `tmp/underground_lighting_review/`.
- Door follow-up: `UndergroundLightingTest` also covers door installation,
  removal, replacement during an update, and a new field reading existing doors.
  `RoomLightingTest` uses the native renderer, mined 64-block room, real door and
  corridor torch, then an interior brazier. Closed-room floor luminance remains
  unchanged with the corridor torch; selection adds only a faint tint, and an
  interior brazier visibly raises illumination. Both panels fit 960×540 and
  1280×720; room dragging and Slice bounds/height memory pass. Captures are in
  `tmp/room_lighting_review/`. The save round-trip includes saved and unsaved doors
  and braziers to verify stale boundaries and duplicate light/heat are removed.
- Fog follow-up: `RoomLightingTest` keeps the native scene fog enabled and checks
  that the lighting materials receive it. The sealed floor measures 0.010, versus
  0.150 using the previous automatic fog and visibility glow. Doubling camera
  distance leaves the dark floor unchanged; an interior brazier raises it to
  0.154. Exposed terrain is compared against native automatic fog, at near/far
  camera distances and during day/night. `UndergroundLightingTest` retains the
  door, skylight, stacked-floor, torch and mining-replay regressions. Logs for
  this pass are under each review directory's `darkness_fix/` folder.

**Entrance and dwarf overlap follow-up (2026-10-07):** shallow mining became too
dark after the fog correction. Entrance reach is now twelve individual voxel
blocks (three four-block mining cells), with the existing squared falloff. At
four blocks from open sky the field retains 44% skylight instead of 18%; at
eight blocks it retains 11% instead of zero. These are field strengths, not
display luminance. Closed doors still stop the flood; the `0.008` readability
floor and the previous sealed-room darkness are unchanged.

The bright dwarf inside unmined terrain was a separate presentation defect:
solid/untracked texture cells intentionally return full daylight for slice cut
plates. Sampling each head/hand fragment used that same fallback when the mesh
overlapped rock. Bound dwarf meshes now share a body-center sky sample via a
per-instance shader parameter. A physical solid at that position returns zero
sky access; air uses the same interpolation as the terrain shader. Existing
local lights retain their normal attenuation and shadows. Late-attached tools
and carried goods inherit the actor sample, released goods revert to world
sampling, and portraits keep their studio materials. The lighting component
owns weak references and updates only changed instance values; it does not
change dwarf movement, tasks, material identity, saves, or terrain meshes.

The navigation symptom was **not fixed by shading**. At the time of this
follow-up, the path follower moved positions directly with collision mask zero;
smoothing checked from cell centers with a smaller margin than the logical
footprint. These were hypotheses, not a reproduced root cause of the player's
route. Later actual-position checks are documented in [32 — Navigation](../30_simulation_systems/32_navigation_3d.md).
[Issue 002](../00_dev_roadmap/00_open_issues.md) retains the historical report;
Alen provisionally closed it on 2026-10-12, to reopen only if reported again.

Validation for this follow-up:

- `TunnelEntranceTest`: native generated terrain and scene fog, previous/new
  reach at the same camera. Sampled floor luminance at four blocks increased
  from 0.109 to 0.175; at eight blocks, from 0.015 to 0.083. Deep floor (0.015)
  and the outdoor sample (0.856) were unchanged. The test also covers a dwarf
  deliberately inside a still-solid designation, smooth actor entrance fade,
  late mesh attachment, cargo detachment, portrait materials, freed references,
  slice invariance and no terrain rebuild for a light-only update.
- `UndergroundLightingTest`: passed entrance propagation, barriers and doors,
  opening/closing skylights during updates, stacked floors, existing torches
  and mining replay into a fresh lighting field. Its deep-floor sample now sits
  beyond the longer entrance reach.
- `RoomLightingTest`: passed with native fog; sealed-room floor remains 0.010,
  unchanged by the exterior torch or camera distance, and rises to 0.154 with
  an interior brazier. Outdoor day/night fog and room/slice controls still pass.

Reports, native captures and the named test logs are under
`tmp/underground_lighting_review/entrance_fix/` and
`tmp/room_lighting_review/entrance_fix/`. Test profiles are isolated. The generated
world tests retain the known autoload-before-scene sky/weather startup warnings;
there are no script/shader errors in the final runs. Restart play mode for the
new tuning and shader; no project reload or save migration is required.

This is a bounded skylight approximation, not bounced global illumination or
sun-angle ray tracing. The normal slice still controls local-light shadow
geometry and torch visibility. Natural-cave discovery and constructed room roofs
remain governed by their existing world/geometry systems; this pass does not add
either system or lighting-related work restrictions.

### Exposed Wall Faces Are the Core Visual Language

In underground slice view, the **vertical faces of rock blocks at the slice boundary** are the primary visual information. They tell the player how deep spaces are, where tunnels go, and what materials are present. Ensure:

- Side faces of blocks at `slice_y` boundary are rendered slightly brighter than buried faces.
- Ore veins on wall faces must be visually distinct from plain stone even in low ambient light.

---

## Surface Atmosphere — Tone

DwarfVoxel's surface is an **unforgiving wilderness** the dwarves are retreating from. The surface atmosphere should feel slightly heavier and more ominous than Stonehearth's bright daytime default:

- Fog can be slightly denser on the surface than Stonehearth's clear-day 0.3 — aim for 0.35–0.45.
- The wilderness feels threatening, not inviting. The player should want to go *underground*.
- Shadows from trees and rocks should be strong — Stonehearth demonstrates that a single directional sun light with shadows does more for world believability than any other single rendering feature.

---

## Terrain Render Modes

> Migrated from the original `00_dev_roadmap/01_world_gen_plan.md` (retired 2026-06-05). The renderer may simplify geometry, but
> it must simplify **exposed block faces** — never invent a painted surface that disagrees with
> the generated blocks. `WorldRenderer` implements the first mode today.

**Code layout (doc 258 step 8, 2026-10-22):** `WorldRenderer` owns the lifecycle, the
exports, `slice_y`, the cut sets, the added terrain, the VisibleVolume contract and the
material. `TerrainTileMesher` (`renderer.tiles`) owns the tile queue, the immutable
cut/mined snapshots read by workers, tile meshing, the startup and slice-timing reports
and the statistics behind `get_render_stats()`. `TerrainCavityShell` (`renderer.cavity_shell`) owns the mined-cavity
shell, its per-column cut index and the column-mesh helpers the added terrain shares.
`BlockInspector` is the DEV inspector. All three are plain preloaded scripts in
`scripts/components/`.

### Accepted modes

1. **Block-face overview mesh — THE renderer (since 2026-06-04), including all sliced views.**
   Uses deterministic generated column data; emits top faces plus vertical faces at height
   drops; greedily merges same-material, same-plane faces. **Side-face colours are per-block
   exact** (since 2026-06-03): every wall block face shows that block's *own* colour — the
   1-block grass cap renders grass on its sides, and the 2-block soil bands and rock shelves
   render true. Banding may merge only **identical adjacent colours**; the "approximation" is
   geometric simplification, never colour.
   **Slice-aware:** a column whose surface is above `slice_y` renders its cut
   floor at the plane. Cut floors are **authored strata only** — see the slice-concealment rule
   below. Neighbour tops are waterline-aware, so water bodies read as calm planes in the cut.
   Slice changes invalidate only tiles whose terrain reaches above the lower plane (+1-tile wall
   margin), center-first from the camera; see §Slice meshing rules.
2. **Near streamed chunk mesh — REMOVED (2026-10-22).** The dormant per-chunk mesher and its
   on-demand chunk-column generation were deleted (doc 258). A future true-3D-interior view
   (side views into roofed tunnels) would need a new path, and it must never show exact chunk
   data on a cut floor: that reveals veins/caves, violating the concealment rule.
3. **World-edge presentation slab** *(future — Second Milestone).* Large, calm boundary panels —
   not a per-block noisy side dump, and must not contradict the visible playable surface blocks.

### Slice concealment rule (HARD — Alen, 2026-06-04)

**Slicing must never reveal undiscovered resources.** Cut floors render authored strata only —
everywhere, at every zoom. Veins, gems, and caves become visible exclusively through mining.
This is a deliberate departure from "paint every block its own colour" for *interior* blocks
exposed by the plane: interior identity is undiscovered information, and the slice is a camera,
not a prospecting tool.

> **Unified exposure principle (2026-06-05, extended for caves 2026-10-07):** a face
> renders exact underground block colours when it faces mined air or natural cave
> air discovered through mining. Cut floors are exact only when the entire cut run
> above is revealed air. Designation floors, untouched cliffs and concealed slice
> cuts stay authored strata; a plan must not reveal resources. The cavity shell
> follows the same rule. The fix rules behind it are listed in §Slice meshing rules.

Mining into a generated cave reveals its whole connected system. Its air joins
the renderer's cut/exposure sets independently of executed mining and planned
cuts. Removing a mining plan must not erase discovered space. Newly discovered
air is initialized to underground darkness throughout the cave; the usual light
solver then propagates entrance daylight and placed lights. Merely moving the
slice does not discover a cave or light its interior.

**Placement tools (2026-10-26):** a cave not yet found, its air and its water, is rock to
every placement tool (`InteriorTracker.is_hidden_cave`). Furniture, storage, construction,
Copy and placing a
blueprint aim through `ObjectPicking.concealed_block` (doc 22), so with the slice through a
hidden cave the pointer stops on the cut, never on the cave floor. Construction refuses the
cave's air with rock's own reason, "Mine existing terrain before building", and its stairs
take it for rock in their headroom; furniture, wall pieces and storage refuse it as they
refuse a cell that is not open floor. Copy goes further: every block the colony has not
seen copies as its strata, so a copied chunk of mountain shows no cave, deposit or water
inside it (doc 23, "Copy and Blueprints"). Placing a blueprint needs nothing more, since
every unseen block in its way, rock, ore, deposit, water or hidden cave, is in the way for
the same reason. `HiddenCavePlacementTest`. The camera's ground (doc 21) also takes a hidden
cave for rock, so zoom, drag, orbit and the camera floor stop on the cut above it.

**Explicit developer inspection exception:** at the user's request, **Menu →
Development → DEV: Cave explorer** can outline hidden caves and temporarily
preview their actual interiors. The preview uses a separate cut set and temporary
readability lighting. Closing it restores normal lighting and the previous view,
preserving real discoveries and mining plans. Preview air never becomes a mined
or discovered save delta. See `43_mining_materials.md` §Cave discovery.

### Slice meshing rules

**Invalidation.** `WorldGenerator` precomputes a visible-height range for every 32×32 overview
tile (`get_tile_visible_range`). A slice move from `old` to `new` rebuilds only tiles whose
max height is above `min(old, new)`, plus their four neighbours (border walls read neighbour
tops), queued nearest-first from the camera's tile. Lowland tiles below both planes never
rebuild. A slice move also marks the cavity shell for one full rebuild.

**Cut dimming.** Floors cut by the plane itself are baked at `SLICE_CUT_DIM = 0.5` luminance
(`TerrainTileMesher.slice_cut_color`, shared by constructed stone and the added terrain).
The dimming leaves hue and block identity untouched. Designation floors and the cavity shell
stay full brightness. Greedy top-merge never fuses a dimmed cut plate with an undimmed natural
plate of the same block at the same height. In the main world the Hearthblock lighting also
tints these tagged cut faces toward darker, warmer rock (`slice_cap_tint`, applied in
`terrain_appearance.gdshaderinc`); block identity is still untouched.

**Cut cells and revealed air.** Designated, mined and discovered cave cells are all cut cells.
Revealed air (executed mining, discovered caves, terrain overrides) is the subset that earns
exact colours; a plan reveals nothing. Every cut block opens the overview:

- **Side-band punching.** A cliff band ends before any cut wall block and restarts after it,
  so plans and holes both open a block-sized mouth in the wall.
- **Cavity shell** (`TerrainCavityShell.gd`). For each **enclosed** cut cell (below its
  column's cut-aware top, under a solid roof) it draws the faces of solid neighbours: exact
  colour around revealed air, strata around plans. It skips cavity continuations, faces above
  the plane, the world edge and undiscovered cave air. It is split into 16×16-block columns.

Fix rules these mechanisms keep (each closed a real defect):

1. The shell draws only enclosed cavities; open-from-above cuts are the overview's job alone
   (a second coplanar face z-fought and flickered veins through).
2. Plans deduct laterally too: designations punch side bands and get strata shell faces.
3. A cut floor is exact only when every cut block above it is revealed air; any plan in the
   run makes it strata.
4. A designation must never act as a prospecting scanner: designate-read-remove shows only
   strata, indistinguishable from untouched rock.
5. A wall face is exact only when the air it faces is revealed air; natural, slice and
   designation exposure stay strata.

### Slice known limits

- **Slice-step stutter (accepted).** A ±1 step over the mountain cost about a 25 ms worst
  frame in a release build, measured before overview batches became non-blocking; it felt fine
  in play. Side faces were half the sweep's CPU, and the world-corner tile with its full-depth
  edge walls was the slowest. If stepping feels slow again, the ranked levers are: side-face
  greedy merge (coplanar same-colour cliff quads), then debouncing the optional mining guide's
  rebuild until the plane settles. Non-blocking batch collection, once the second lever, is
  already in place.
- **Lateral cavities.** The overview is a per-column-top representation, so roofed
  interiors show only where punched mouths, the shell or the slice expose them. X-ray is the
  interior view.

### Rejected modes

Never use these as the main validation view: a top-only painted heightmap; fake grass/dirt/rock
side bands; screen-space or fog-dependent material choices; one vertical wall stripe per terrain
sample at the world boundary; **coarse side-colour sampling steps or top-colour overrides that
repaint a block's face with a different block's colour** (a 4-block Y sampling step plus a
top-colour override did exactly this — swallowing the grass cap so grass blocks showed dirt
sides — removed 2026-06-03; a block's faces must always show that block's colour).

## The Appeal view's dim and tints (2026-10-25)

The Appeal view (doc 23) is presentation drawn over the normal render, never a change to
terrain or its materials:
- **The dim** is one full-screen quad (`appeal_dim.gdshader`, its vertex shader setting
  `POSITION` to cover the screen) that reads the screen texture and draws it greyed and
  darkened. Its render priority (−100) makes it the first of the see-through passes.
- **The room tints** are one multimesh of floor quads, 0.02 above each floor, unshaded and
  depth-tested, so furniture and walls hide them as they hide the floor (priority 10).
- **The glows** are overlay materials on the counted pieces' meshes (priority 20), given
  back when the view turns off.
- **Layers:** all three sit on the default layer, X-ray's layer and the terrain layer, so
  the normal and X-ray cameras both draw them and X-ray's own scan leaves them alone.

## Mining-Edit Invalidation Contract

> Migrated from the original `00_dev_roadmap/04_mining_performance.md` (retired 2026-06-05;
> the performance pass it planned shipped 2026-06-01 and killed the 15-second mining-edit
> freeze). Verified against `WorldRenderer.gd` / `MiningDesignationController.gd` on
> retirement day. Slice-change invalidation has its own rules — see §Slice meshing rules.

Mining cuts are **renderer state** (Stonehearth's model — designation never mutates
`WorldData`; only DEV/real mining does). Edits must invalidate locally, never globally:

- **Delta APIs are the normal path:** `add_visual_cut_blocks()` / `remove_visual_cut_blocks()`
  (and `add_mined_blocks()` for executed mining). The mining controller sends only changed
  blocks on confirm / remove / Ctrl-subtract. Which cut cells are mined holes comes from
  `WorldData.is_removed_terrain()`; the renderer keeps no mined set of its own. Column tops
  use `WorldData.visible_top_y()` (see `12_world_grid.md`).
- **Dirty rule:** changed blocks dirty their own overview tiles **plus X/Z neighbour columns'
  tiles** (side faces compare neighbouring column heights). Deduplicated, drained on the
  existing per-frame budget.
- **`set_visual_cut_blocks()` (full replacement) is fallback/global-sync only.** Risk to
  guard in review: a controller edit path quietly reverting to it reintroduces global
  invalidation.
- **`TerrainTileMesher.invalidate_global()` is reserved for genuinely global events:** initial build
  after worldgen, season/colour changes, wholesale world-data swaps.
  Ordinary mining edits must never reach it.
- **Resolved 2026-06-05:** the yellow zone overlay no longer rebuilds all zones into one mesh
  per edit — it was split into per-zone overlay nodes with localized rebuilds (see
  `43_mining_materials.md` §Mining Zone Entity).

## Loading and overview snapshots

Overview workers reuse immutable cut/mined/discovery/terrain dictionaries while
their inputs remain unchanged. Global invalidations replace these snapshots. Local
cut/terrain/discovery changes record their cells, and only those cells are patched.
Either happens only after the previous batch has been consumed; existing per-tile
revisions and global epochs still reject stale results. Slice/season values remain
captured per batch. Copying the large terrain dictionaries for every batch slowed
saved-world loads (doc 247).

**Edit cost (2026-10-21):** the cavity shell and the added-terrain mesh are split
into 16×16-block columns that cover every height. A mined, built or designated block
rebuilds only its own column, plus the neighbouring column when it sits on a column
edge. Slice moves, season turns and loads rebuild every column. Before this, every
commit rebuilt the whole shell, the added terrain and the overview snapshot on the main
thread, a cost that grew with the colony's age (doc 254).

Underground lighting uses a 12 ms work budget while WorldClock is held by the
loading cover, returning to 2.5 ms during play (`UndergroundLighting`
`LOADING_FRAME_BUDGET_USEC` and `FRAME_BUDGET_USEC`). The solver, published samples,
texture data and readiness gate are unchanged (doc 247).

## Debug Overlay & Block Inspector

Player terrain inspection uses the compact panel beside the dock
([23](23_user_interface.md#object-selection-implemented-2026-10-04)): click an exposed face for its material
name, the kind of face and its level, and its description. `TerrainExplorerProvider` follows live
terrain, constructed blocks and the renderer's visual cuts, keeping undiscovered
deposits concealed on slices and planned excavations (doc 130). It is a scene node with
a `renderer_path` export and keeps no visibility state of its own: it reads the
renderer's cut and revealed sets, X-ray's shown faces and `InteriorTracker`'s known
cells. The object explorer falls back to it only when no object or zone was hit.

The debug overlay (`DebugLoadingOverlay`) exposes generation/render state: map readiness, active
render mode, overview step, overview sampled/merged face counts, overview validation mismatch
count, domain percentages, surface material percentages, height min/max/average, water-body
stats, settlement-candidate count, generated column count, and mesh count / queue count.

**Development → Block Inspector** (`scripts/components/BlockInspector.gd`, built only when
`UIRegistry.dev_tools_enabled`) reports, per clicked block: render mode, hit source, face direction, hit
block key, **generated block key**, agreement (yes/no), coordinate, domain, surface Y, visible
top Y, water/bank flags, kind, and colour. The agreement check is the core validation that the
overview/inspector and generated blocks agree on unedited terrain. Edited chunk
AIR is authoritative, so the ray can pass through excavations instead of falling
back to their original generated rock. These technical details stay out of the
player terrain inspector.

---

*Prev: [23_user_interface.md](./23_user_interface.md)*
