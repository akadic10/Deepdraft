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

> **Note:** Full day/night sky cycling is not yet implemented. See `11_overview.md` § 5 for the planned cosine-curve day length system. Do not implement dynamic sky color until that section is marked complete. Use a static daytime sky in the interim.

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

DwarfVoxel's `slice_fade_bands` (see `21_rts_camera.md`) should apply only at or near the **surface** where transitioning from aboveground to underground view. For slices **deep underground**, default to a hard clip. The black void above reads as solid rock ceiling, which is narratively correct.

### The Black Ceiling Reads as Rock

When the player is working inside a carved underground chamber and the slice removes geometry above them, the black void is not perceived as a missing sky — it reads as the solid mountain above. This effect is free and correct. Do not add ambient fill light or particle effects to the overhead void.

### Underground Lighting Model

Stonehearth's slice view works on a surface world where ambient sunlight exists at all depths. **DwarfVoxel is primarily underground — the sunlight model does not reach deep slices.**

At depth, the current `slice_y` floor needs its own ambient illumination. Options (to be decided when implementing lighting):

- A "game camera light" — a weak ambient directional light that always points straight down and follows the camera, illuminating only the current slice floor.
- Torchlight / room-scoped light sources placed by dwarves.
- A flat ambient intensity floor so rooms never go completely black, even unlit.

> **Implementation note:** Do not implement underground lighting until the task system and room-carving loop are functional. Placeholder flat ambient is acceptable during early development.

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

> Migrated from `00_dev_roadmap/01_world_gen_plan.md`. The renderer may simplify geometry, but
> it must simplify **exposed block faces** — never invent a painted surface that disagrees with
> the generated blocks. `WorldRenderer` implements the first two modes today.

### Accepted modes

1. **Near streamed chunk mesh.** Built from generated chunks (`ChunkMesher`); emits real exposed
   block faces. Used for inspection, mining, selection, and close review.
2. **Block-face overview mesh.** For high-altitude / zoomed-out surface views. Uses deterministic
   generated column data; emits top faces plus vertical faces at sampled height drops; greedily
   merges same-material, same-plane faces; labels itself as an approximation in the debug UI.
3. **World-edge presentation slab** *(future — Second Milestone).* Large, calm boundary panels —
   not a per-block noisy side dump, and must not contradict the visible playable surface blocks.

### Rejected modes

Never use these as the main validation view: a top-only painted heightmap; fake grass/dirt/rock
side bands; screen-space or fog-dependent material choices; one vertical wall stripe per terrain
sample at the world boundary.

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
