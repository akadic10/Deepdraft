# 05 - Mining Tech Debt

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = keep</span> |
> <span style="color:#d29922;">Yellow = review / move to a more specific plan</span> |
> <span style="color:#f85149;">Red = safe to delete or archive once you are comfortable</span>

## Document Review - 2026-06-01

This file is still useful as a focused mining cleanup backlog. Both current items are yellow:
real enough to keep visible, but small enough that they may move into implementation tasks once
the next mining pass begins.

---

This file tracks small cleanup items discovered while reviewing the mining implementation. It is for debt that is real but not urgent enough to interrupt the current feature pass.

## <span style="color:#d29922;">REVIEW - Restore Audit - 2026-06-01</span>

Both debt items below are still valid in the restored project.

- `Config Source Of Truth` is still open: `MiningDesignationController.gd` loads
  `data/terrain/mining_config.json`, but the same numbers are still initialized inline as unnamed
  fallback values.
- `Foreground vs Background Mining Overlay Readability` is still open: preview and zone overlays use
  no-depth fill/line materials for full regions, and there is no separate stronger depth-tested
  exposed/floating subset yet.

No additional small mining cleanup item was found during this restore audit. Performance-specific
work is tracked in `04_mining_performance.md`, and first-slice UX backlog is tracked in
`03_mining_plan.md`.

## <span style="color:#d29922;">REVIEW / MOVE - Config Source Of Truth</span>

**Status:** <span style="color:#d29922;">Open / review</span>

**Context:** `data/terrain/mining_config.json` is the source of truth for mining tool tuning, but `scripts/systems/MiningDesignationController.gd` currently initializes the same values inline:

```gdscript
var _horizontal_size: int = 1
var _vertical_size: int = 1
var _max_horizontal: int = 8
var _max_vertical: int = 8
var _max_drag_length: int = 40
```

The controller does load and override these from JSON in `_load_config()`, so behavior is correct. The issue is readability: the inline values look like a second configuration source.

**Desired cleanup:** Make the code values explicit fallbacks, not apparent config.

```gdscript
const FALLBACK_DEFAULT_SIZE := 1
const FALLBACK_MAX_HORIZONTAL := 8
const FALLBACK_MAX_VERTICAL := 8
const FALLBACK_MAX_DRAG_LENGTH := 40

var _horizontal_size: int = FALLBACK_DEFAULT_SIZE
var _vertical_size: int = FALLBACK_DEFAULT_SIZE
var _max_horizontal: int = FALLBACK_MAX_HORIZONTAL
var _max_vertical: int = FALLBACK_MAX_VERTICAL
var _max_drag_length: int = FALLBACK_MAX_DRAG_LENGTH
```

Then keep `_load_config()` as the only path that applies real tuning from `mining_config.json`.

**Rule:** JSON wins. Code constants exist only so the tool can fail gracefully if the config file is missing or malformed.

**Acceptance criteria:**

- `MiningDesignationController.gd` names these values as fallback defaults.
- `data/terrain/mining_config.json` remains the only intended tuning surface.
- No behavior changes to precision mining controls.

## <span style="color:#d29922;">REVIEW / MOVE - Foreground vs Background Mining Overlay Readability</span>

**Status:** <span style="color:#d29922;">Open / review</span>

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

---

*Prev: [04_mining_performance.md](./04_mining_performance.md)*
