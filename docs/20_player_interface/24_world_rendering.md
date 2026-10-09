# 24 — World Rendering & Atmosphere

## Reference

All visual design decisions in this document are derived from analysis of **Stonehearth** (Radiant Entertainment) as the primary reference, specifically its fog system, sky settings, terrain slice view, and world-edge treatment.

---

## Fog & Sky System

### Core Principle: Sky and Fog Must Match

The single most impactful atmospheric decision is that **the sky color and the fog color must be nearly identical**. Stonehearth achieves a seamless world-edge dissolve entirely through this color match — there is no special boundary shader, no fog wall, no edge culling. The terrain simply fades into the sky.

### Daytime Fog Parameters (Target)

| Condition | Fog start distance | Density | Max distance |
|---|---|---|---|
| Clear midday | 0 units | 0.3 | ~500 units |
| Overcast / autumn | 50 units | 0.4 | ~150 units |
| Night / winter | 100 units | 0.5 | ~100 units |

These values are derived from Stonehearth's `sky_settings.json` `height_fog` params at corresponding times of day. The clear daytime setting is the most important — it must feel open, airy, and deep, not claustrophobic.

### Sky

Use Godot's `WorldEnvironment` with a `ProceduralSkyMaterial` or a gradient sky texture. The horizon color must match the daytime fog color. Even a simple two-stop gradient (sky blue top → hazy blue-grey horizon) is sufficient.

> **Current implementation:** `SkyController` drives the sky gradient and Sun/Moon
> lights from calendar-keyed data. The scene's authored Environment still supplies
> fog settings; the separate world-edge fog redesign remains deferred. See
> [08 — Sky plan](../00_dev_roadmap/08_sky_plan.md) and the live underground-lighting
> section below for the current division of responsibilities.

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

---

## Terrain Slice View

### Hard Clip, Not Fade

Stonehearth uses a **hard horizontal clip** at `slice_y` — geometry above the slice is completely removed from rendering, leaving a black void. It does not fade or dim.

> **Implemented (2026-06-04):** `WorldRenderer.slice_y` hard-clips the whole map via the
> slice-aware block-face overview (per-column cut tops, strata-only floors, per-tile
> invalidation). Verified: ~1.5 s center-first sweep, ~60 ms worst frame for a mountain-depth
> step (editor/debug). See `00_dev_roadmap/11_slice_xray_plan.md` for the full record.

DwarfVoxel's `slice_fade_bands` (see `21_rts_camera.md`) should apply only at or near the **surface** where transitioning from aboveground to underground view. For slices **deep underground**, default to a hard clip. The black void above reads as solid rock ceiling, which is narratively correct.

### The Black Ceiling Reads as Rock

When the player is working inside a carved underground chamber and the slice removes geometry above them, the black void is not perceived as a missing sky — it reads as the solid mountain above. This effect is free and correct. Do not add ambient fill light or particle effects to the overhead void.

### Underground Lighting Model

**Wall torch lighting shipped 2026-10-02** ([art doc 43](../00_dev_roadmap/43_wall_torch_asset_and_lighting.md)).
Installed torches add bounded warm omni lights and 200 heat units. All four terrain
mesh paths (chunk, region, overview and cavity shell) now cast local-light shadows,
so rock blocks torchlight. `TerrainLighting.gd` reserves render layer 20 for terrain;
the sun excludes that layer from its **shadow-caster** mask while retaining its
normal light mask. Thus terrain still receives daylight and the existing sun-shadow
behavior is preserved. Camera cull masks include layer 20. A torch is hidden with
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
`readability_floor: 0.008` (reduced after the room-darkness follow-up below).

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

**Room darkness / fog follow-up (2026-10-06):** scene fog was still blending sky
colour into sealed rooms after the lighting shader ran. The earlier native room
fixture disabled fog, so its passing lighting checks did not cover the actual
gameplay appearance. With fog enabled, an unlit room measured 0.150 luminance;
even with the readability glow set to zero, fog alone contributed 0.131.

The shared lighting shader now supplies `FOG` explicitly and scales its opacity
by physical sky access. It reads the active scene (or camera override)
Environment at 20 Hz, updating only changed material parameters. Depth / density
and height falloff, the ProceduralSky gradient in the view direction, and sun
scattering remain available outdoors. The gradient is evaluated analytically;
this does not reproduce the engine's blurred sky-radiance sampling or volumetric
fog. The current scene uses depth fog and a ProceduralSky. No additional render
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

The navigation symptom is **not fixed by shading**. The current path follower
moves positions directly with collision mask zero. Its smoothing checks from
cell centers and uses a smaller margin than the logical footprint. These are
plausible contributors, not a reproduced root cause of the player's route.
[Issue 002](../00_dev_roadmap/00_open_issues.md) records the parked investigation.

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

> Migrated from the original `00_dev_roadmap/01_world_gen_plan.md` (retired 2026-06-05; live
> remainder in `00_dev_roadmap/12_worldgen_second_milestone.md`). The renderer may simplify geometry, but
> it must simplify **exposed block faces** — never invent a painted surface that disagrees with
> the generated blocks. `WorldRenderer` implements the first two modes today.

### Accepted modes

1. **Block-face overview mesh — THE renderer (since 2026-06-04), including all sliced views.**
   Uses deterministic generated column data; emits top faces plus vertical faces at height
   drops; greedily merges same-material, same-plane faces. **Side-face colours are per-block
   exact** (since 2026-06-03): every wall block face shows that block's *own* colour — the
   1-block grass cap renders grass on its sides, and the 2-block soil bands and rock shelves
   render true. Banding may merge only **identical adjacent colours**; the "approximation" is
   geometric simplification, never colour.
   **Slice-aware (doc 11 Phase SO):** a column whose surface is above `slice_y` renders its cut
   floor at the plane. Cut floors are **authored strata only** — see the slice-concealment rule
   below. Neighbour tops are waterline-aware, so water bodies read as calm planes in the cut.
   Slice changes invalidate only tiles whose terrain reaches above the lower plane (+1-tile wall
   margin), center-first from the camera.
2. **Near streamed chunk mesh — DORMANT.** Built from generated chunks (`ChunkMesher`, which
   supports block-granular slice clipping); reachable only via
   `WorldRenderer.set_overview_enabled(false)`. Reserved for a future true-3D-interior need
   (side views into roofed tunnels). It must never run during normal sliced play: exact chunk
   data on a cut floor reveals veins/caves, violating the concealment rule.
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
> follows the same rule. Derivation and defect history:
> `00_dev_roadmap/11_slice_xray_plan.md` §Phase SO-2b, Defects 1–5.

Mining into a generated cave reveals its whole connected system. Its air joins
the renderer's cut/exposure sets independently of executed mining and planned
cuts. Removing a mining plan must not erase discovered space. Newly discovered
air is initialized to underground darkness throughout the cave; the usual light
solver then propagates entrance daylight and placed lights. Merely moving the
slice does not discover a cave or light its interior.

**Explicit developer inspection exception:** at the user's request, **Menu →
Development → DEV: Cave explorer** can outline hidden caves and temporarily
preview their actual interiors. The preview uses a separate cut set and temporary
readability lighting. Closing it restores normal lighting and the previous view,
preserving real discoveries and mining plans. Preview air never becomes a mined
or discovered save delta. See [68 — Caves and discovery](../00_dev_roadmap/68_caves_and_discovery.md).

### Rejected modes

Never use these as the main validation view: a top-only painted heightmap; fake grass/dirt/rock
side bands; screen-space or fog-dependent material choices; one vertical wall stripe per terrain
sample at the world boundary; **coarse side-colour sampling steps or top-colour overrides that
repaint a block's face with a different block's colour** (a 4-block Y sampling step plus a
top-colour override did exactly this — swallowing the grass cap so grass blocks showed dirt
sides — removed 2026-06-03; a block's faces must always show that block's colour).

## Mining-Edit Invalidation Contract

> Migrated from the original `00_dev_roadmap/04_mining_performance.md` (retired 2026-06-05;
> the performance pass it planned shipped 2026-06-01 and killed the 15-second mining-edit
> freeze). Verified against `WorldRenderer.gd` / `MiningDesignationController.gd` on
> retirement day. Slice-change invalidation has its own rules — see
> `00_dev_roadmap/11_slice_xray_plan.md` Phase SO.

Mining cuts are **renderer state** (Stonehearth's model — designation never mutates
`WorldData`; only DEV/real mining does). Edits must invalidate locally, never globally:

- **Delta APIs are the normal path:** `add_visual_cut_blocks()` / `remove_visual_cut_blocks()`
  (and `add_mined_blocks()` for executed mining). The mining controller sends only changed
  blocks on confirm / remove / Ctrl-subtract.
- **Dirty rule:** changed blocks dirty their own overview tiles **plus X/Z neighbour columns'
  tiles** (side faces compare neighbouring column heights); streamed regions dirty only
  regions containing changed blocks and their direct neighbours. Deduplicated, drained on the
  existing per-frame budgets.
- **`set_visual_cut_blocks()` (full replacement) is fallback/global-sync only.** Risk to
  guard in review: a controller edit path quietly reverting to it reintroduces global
  invalidation.
- **`_invalidate_overview_global()` is reserved for genuinely global events:** initial build
  after worldgen, season/colour changes, render-mode resets, wholesale world-data swaps.
  Ordinary mining edits must never reach it.
- **Resolved 2026-06-05:** the yellow zone overlay no longer rebuilds all zones into one mesh
  per edit — it was split into per-zone overlay nodes with localized rebuilds (see
  `43_mining_materials.md` §Mining Zone Entity).

## Debug Overlay & Block Inspector

The debug overlay (`DebugLoadingOverlay`) exposes generation/render state: map readiness, active
render mode, overview step, overview sampled/merged face counts, overview validation mismatch
count, domain percentages, surface material percentages, height min/max/average, water-body
stats, settlement-candidate count, generated column count, and mesh count / queue count.

The block inspector reports, per hovered block: render mode, hit source, face direction, hit
block key, **generated block key**, agreement (yes/no), coordinate, domain, surface Y, visible
top Y, water/bank flags, kind, and colour. The agreement check is the core validation that the
overview/inspector and the generated blocks never disagree.

---

*Prev: [23_user_interface.md](./23_user_interface.md)*
