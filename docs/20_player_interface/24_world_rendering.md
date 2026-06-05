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

> **Implemented (2026-06-04):** `WorldRenderer.slice_y` hard-clips the whole map via the
> slice-aware block-face overview (per-column cut tops, strata-only floors, per-tile
> invalidation). Verified: ~1.5 s center-first sweep, ~60 ms worst frame for a mountain-depth
> step (editor/debug). See `00_dev_roadmap/11_slice_xray_plan.md` for the full record.

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

> **Unified exposure principle (2026-06-05, shipped with Phase SO-2b):** *a face renders
> exact block colours iff the air it faces was created by MINING; every other face renders
> authored data.* Concretely: cut floors are exact only when the entire cut run above was
> mined (designation floors stay strata — a plan is not a prospecting tool); wall side-bands
> are exact only where the facing air block was mined open (natural cliffs, slice cuts, and
> designation ghosts stay strata); the cavity-shell mesh colours per cavity-block source
> (mined → exact, designated → strata). Derivation and defect history:
> `00_dev_roadmap/11_slice_xray_plan.md` §Phase SO-2b, Defects 1–5.

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
- **Open polish (tracked in `00_dev_roadmap/05_mining_tech_debt.md`):** the yellow zone
  overlay (`_rebuild_zones_mesh()`) still rebuilds all zones into one mesh per edit.

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
