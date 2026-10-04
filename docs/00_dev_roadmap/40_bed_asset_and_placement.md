# 40 — Dwarven Bed Asset and Placement

Status: **INSTALLED AND VERIFIED — 2026-10-01.**

The Dwarven Bed is an independent buildable furniture item with its own model,
packed-item identity, Build-menu entry and placement definition. Alen approved
revising the old 2×1 specification to **4×2** to fit the current 3.375-block
visual dwarf. Bed assignment, walking to bed, sleeping animation and the
`slept_in_bed` thought remain future gameplay work.

## Model

`assets/models/furniture/dwarf_bunk.glb` has a heavy oak frame, stout corner
posts, iron shoes and brackets, slatted support, a linen-covered straw mattress,
a broad pillow and a folded wool blanket. The headboard has recessed panels
and a small iron rune; the foot end stays open. Oak and iron match the existing
furniture. Linen colors derive from `cloth_undyed`; the muted teal blanket
repeats the existing dwarf tunic palette.

Length is on X, with the headboard at -X. Mattress height is **1 block**,
pillow/blanket height **1.25**, and headboard height **2**. The model uses
**eight voxels/block** in a **32×16×16-cell** envelope: **2,572 occupied voxels**,
one connected component, **4,936 triangles**. Local bounds are X [-2,2],
Y [0,2], Z [-1,1]. Scale 0.125 is baked into positions; import/runtime scale
remain 1. Vertex colors are exported as linear `COLOR_0` for the existing
lit, double-sided furniture material.

`tools/generate_bed.py` owns the geometry and isolated review export.
`tools/generate_furniture_glbs.py` delegates to it, bringing the canonical
set to eleven placed models and one shared packed crate.

## Integration

- `base:furniture:dwarf_bunk` uses floor placement, a 4×2 footprint and four
  yaw steps. Four collision regions cover the body, headboard, pillow and
  folded blanket. It adds no room-anchor, storage, heat or door behavior.
- `base:resources:furniture:dwarf_bunk` uses the shared packed crate, heavy
  weight class and stack limit 5. Trade value 18 is provisional data.
- **Build → Dwarven Bed** selects the bed. **Storage Zone → DEV: Spawn
  Furniture** provides one packed bed per batch. Restart a running game
  to load the new definition and menu entry.
- Existing fetch/build, independent removal/refund and persistence paths
  handle the new piece. No autoload or global script class is added.

The placement controller now rotates both bounds of footprint-local collision
regions before rounding outward to grid cells on every axis. Previously it
only swapped X/Z sizes and truncated their fractional values, which would
lose the quarter-block headboard and leave offset bedding in the wrong place.
Explicit quarter-turn formulas match positive Godot Y rotation and avoid
floating-point drift at cell edges. Existing furniture coverage is preserved.

The Build panel now uses six columns and two rows for its eleven pieces plus
Cancel. It stays horizontally centered and grows upward above the dock.
Smaller action panels remain on one row. No user window-layout preferences
are changed.

## Review and verification

The isolated review is `tmp/bed_preview/project.godot`. Seven native Godot
4.7.2 Forward+ / D3D12 captures cover the bed at multiple angles, standing
and reclining dwarf scale, and a bedroom example. The reclining pose uses
full-size shipping parts with relaxed hand/body placement. It confirms length
and pillow fit; ear tips slightly overhang the frame. This is a static visual
study, not a gameplay sleep animation. The bedroom's chest and chair are
separate build items.

`tools/VerifyBed.gd` checks actual controller, item-manager and dwarf
pickup/build methods on an in-memory floor fixture:

- Nonblocking ghosts, overlap prevention, four rotations, native scale,
  imported bounds/material flags and correct eight-cell footprints.
- Rotated headboard/bedding occupancy, including empty space above the
  exposed mattress and above the headboard.
- Releasing/reclaiming fetch reservations, carrying and consuming one packed
  bed, uninstalling/refunding the same item, and restoring saved state into
  a cleared fixture.
- Unchanged terrain, walkable neighbors and no heat or door side effects.
- Actual Build-panel rectangles at 1280×800 and 2560×1440: all twelve buttons
  visible in two rows within an 869×170 panel. The bed button activates the
  real placement controller. Reopening a smaller menu preserves one-row layout.

`tools/BedBuildPanelFixture.gd` loads after autoload initialization and builds
only the real action panel; it avoids player UI preferences and save callbacks.
The existing dining-table and chair fixtures also pass, covering all ten
previous pieces, fractional table height and independent chair/table removal.
These direct integration checks do not constitute a full autonomous scheduler
or main-world playthrough. No player saves are used. Minimal fixtures emit
the existing missing-sky and unseeded-weather warnings; final logs have no errors.

The audit confirms all **149 prior GLBs**, all **ten prior furniture
definitions** and all prior item definitions are preserved. All twelve
canonical exports match shipping bytes. Every occupied bed voxel is covered
by its collision regions. Snapshot, geometry report, runtime checks and audit
are `pre_import.json`, `validation.json`, `runtime_checks.json` and
`integration.json` under `tmp/bed_preview/`.

## Reproduction

```powershell
python -B tools/generate_bed.py --install
$bedEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $bedEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\bed_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $bedEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\bed_preview', '--resolution', '1600x1000', '--', '--capture') -WindowStyle Hidden -Wait
Start-Process -FilePath $bedEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $bedEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tools/VerifyBed.gd') -WindowStyle Hidden -Wait
Start-Process -FilePath $bedEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tools/VerifyDiningTable.gd') -WindowStyle Hidden -Wait
Start-Process -FilePath $bedEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tools/VerifyChair.gd') -WindowStyle Hidden -Wait
```

Omit `--install` for review-only export, or `-- --capture` for interactive review.
