# 05 - Mining Tech Debt

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = keep</span> |
> <span style="color:#d29922;">Yellow = review / move to a more specific plan</span> |
> <span style="color:#f85149;">Red = safe to delete or archive once you are comfortable</span>

## Status - 2026-06-05

This file is **the consolidated mining backlog**: tech debt plus UX/perf polish. It absorbed
the live remainders of the retired `03_mining_plan.md` (parity polish) and
`04_mining_performance.md` (zone overlay rebuild) on 2026-06-05. Permanent specs live
elsewhere: tool spec in `43_mining_materials.md` §Mining Tools, invalidation contract in
`24_world_rendering.md` §Mining-Edit Invalidation Contract. Every item below was verified
still open against the code on 2026-06-05.

Open items: zone overlay whole-rebuild, parity polish 1–6. (Config source of truth and
overlay readability both resolved 2026-06-05.)

## <span style="color:#3fb950;">RESOLVED 2026-06-05 - Config Source Of Truth</span>

`MiningDesignationController.gd` now names its inline values as explicit
`FALLBACK_DEFAULT_SIZE` / `FALLBACK_MAX_HORIZONTAL` / `FALLBACK_MAX_VERTICAL` /
`FALLBACK_MAX_DRAG_LENGTH` constants, referenced from both the var initializers and the
`_load_config()` defaults (the numbers previously lived unnamed in three places).
`data/terrain/mining_config.json` remains the only intended tuning surface — JSON wins;
the constants exist solely so the tool fails gracefully if the config file is missing or
malformed. No behavior change.

## <span style="color:#3fb950;">RESOLVED 2026-06-05 - Foreground vs Background Mining Overlay Readability</span>

**Status:** <span style="color:#3fb950;">Shipped — verified in-engine by Alen 2026-06-05</span>

**Context:** Stonehearth makes mining selections easier to read by rendering two different overlay layers:

- A low-alpha no-depth outline/fill for the whole selected region, so the player can still perceive the full volume even where terrain occludes it.
- A stronger depth-tested "floating" outline/fill after subtracting visible terrain intersection, so foreground/exposed portions read brighter than the background/inside grid.

This creates the visual effect where hidden/internal selection lines are still visible, but lighter, while the exposed or foreground part of the selection is visually dominant.

**Stonehearth references:**

- `P:\stonehearth\call_handlers\mining_call_handler.lua:220-230`
  - Inflates the custom-block region by `Point3(0.001, 0.001, 0.001)`.
  - Draws the full region with `transparent_box_nodepth.material.json` / `debug_shape_nodepth.material.json` at low alpha.
  - Computes `floating_region` by subtracting `stonehearth.subterranean_view:intersect_region_with_visible_volume(radiant.terrain.clip_region(region))`.
  - Draws that floating region again with normal depth materials and stronger alpha.
- `P:\stonehearth\renderers\mining_zone\mining_zone_renderer.lua:118-135`
  - Intersects confirmed mining zones with the visible volume.
  - Subtracts completed terrain.
  - Inflates the result slightly.
  - Draws both no-depth low-alpha and depth-tested stronger-alpha outline nodes.

**Current Deepdraft issue:** The mining terrain grid and preview can make foreground/background relationships hard to read. Internal or behind-terrain grid lines can appear too similar to exposed selection edges, especially because some overlay material uses no-depth rendering.

**Desired cleanup:** Add a layered mining overlay treatment similar to Stonehearth:

1. Draw a low-alpha no-depth region/grid layer for the full selected volume.
2. Compute an exposed/floating region or visible-face subset.
3. Draw that exposed subset with stronger alpha and depth-aware materials.
4. Keep a tiny outward offset to avoid z-fighting.
5. Apply the same visual language to active previews and confirmed mining zones where practical.

**Acceptance criteria:**

- Foreground/exposed selection edges are visibly stronger than background/internal grid lines.
- Hidden or inside-region selection structure remains faintly readable.
- The player can distinguish selected volume depth without the overlay becoming noisy.
- The implementation does not change mining zone data or actual terrain blocks.

**Slice interaction (decided 2026-06-05):** zones above the slice plane are handled by the
VisibleVolume contract, not by this readability pass — they disappear entirely (Stonehearth's
choice — the overlay never paints inside hidden rock). See `11_slice_xray_plan.md` Phase 3.
The "faintly readable" rule above applies to structure hidden *behind terrain* within the
visible volume, not to structure above the slice plane.

**SHIPPED 2026-06-05, verified in-engine by Alen:** done in
`MiningDesignationController.gd` only, simpler than the Stonehearth recipe: no
exposed-region computation. Four new `*Exposed` MeshInstance3D nodes (preview fill/lines,
zones fill/lines) **share the ghost layer's meshes** but use depth-TESTED materials at the
original strengths — the overlay geometry already sits 0.008–0.018 outside the terrain
faces, so the depth buffer partitions exposed from hidden on the GPU, free, with zero
extra rebuild cost (item below unaffected). The original no-depth materials became the
faint ghost layer (alphas cut to ≈30%: preview fill 0.42→0.14, lines 1.0→0.30, remove fill
0.18→0.06, zones fill 0.26→0.08, zones lines 0.92→0.28).

**Verified:** preview dragged into a wall shows a bright exposed front and faint buried
interior; a confirmed zone behind a ridge ghosts through the hill instead of punching
over it; nothing broken in open view (exposed-only overlays read as before); slice
behaviour unchanged. Alphas accepted at first values — retune only if a future scene
makes the ghost read wrong.

## <span style="color:#d29922;">REVIEW - Zone Overlay Mesh Is Rebuilt Whole (moved from retired 04_mining_performance.md, 2026-06-05)</span>

**Status:** <span style="color:#d29922;">Open / polish — not the old freeze path</span>

`_rebuild_zones_mesh()` rebuilds ALL confirmed zone overlay geometry into one combined mesh
on every confirm / remove / select / DEV-mine, and (since doc 11 Phase 3) on every slice
change via `visible_volume_changed` — the per-block VisibleVolume clip runs inside the same
all-zones loop. Fine at current zone counts; will become noticeable with many large zones.
Fix shape when needed: per-zone mesh nodes so one edit touches one zone's mesh, and the
slice clip re-evaluates only zones intersecting the changed plane rows.

The terrain-side invalidation contract that pass established is now normative in
`24_world_rendering.md` §Mining-Edit Invalidation Contract.

**Timing validation (conditional, doc-07 rule):** the 04 plan's formal `1×1×1` / `3×3×1` /
`4×4×4` before/after measurements were never taken — the freeze was eliminated and daily
DEV-mine use has not surfaced hitches. Re-measure (release build) only if mining edits ever
feel hitchy in play.

## <span style="color:#d29922;">REVIEW - Stonehearth Parity Polish (moved from retired 03_mining_plan.md, 2026-06-05)</span>

Mining-UX polish items from the old parity review, all verified still open in
`MiningDesignationController.gd` on move day. The permanent tool spec now lives in
`43_mining_materials.md` §Mining Tools.

1. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Drag height locking.**
   During drag, intersect the mouse ray against an anchor-height plane instead of raycasting
   terrain every update (`_update_hover_preview` re-raycasts terrain each frame today). Keeps
   selection stable on slopes and terraces.
2. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Selection support offset /
   validity display.** Keep the preview visually rectangular, but make invalid or filtered
   blocks clearer before confirmation.
3. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Size labels and rulers.**
   `Label3D` size labels exist, but they are not full X/Z rulers and may still be hard to
   read.
4. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Modifier redraw.** Force
   preview rebuild on Ctrl press/release — today `_update_hover_preview` early-returns on an
   unchanged hit, so the removal colour only updates when the mouse hit changes.
5. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Cursor and user feedback.**
   Add a small mining-mode instruction callout; cursor assets can wait.
6. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Zone data model (worker
   prep).** The mined/designation set split shipped with slice Phase SO-2b; the remaining
   split — completed blocks, destination blocks, reserved blocks — lands with real mining
   execution (spec: `43_mining_materials.md` §Mining Zone Entity).

---

*Prev: [00_dev_roadmap](.) — docs 03 and 04 retired 2026-06-05; specs moved to `43_mining_materials.md` §Mining Tools and `24_world_rendering.md` §Mining-Edit Invalidation Contract*
