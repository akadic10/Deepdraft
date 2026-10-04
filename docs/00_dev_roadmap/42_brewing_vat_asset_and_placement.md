# 42 — Brewing Vat Asset and Placement

Status: **INSTALLED AND VERIFIED — 2026-10-02.**

The Brewing Vat is now an independently buildable furniture piece. Alen approved
expanding its original 1×1 specification to a **2×2 footprint**, **2 blocks tall**,
at **eight voxels/block**. Ingredient handling, recipe queues, drink storage and
brewery workshop integration remain future gameplay work; the recessed liquid
is static artwork.

## Model

`assets/models/furniture/brewing_vat.glb` has broad oak staves, two heavy iron
hoops, a deep open rim and reinforced timber skids. The liquid surface is three
voxels below the lip. A copper mounting plate, short draw-off nozzle and
T-handle face +Z. Offsetting the vessel one voxel toward -Z keeps its front
fittings inside the declared footprint. It reads as a larger production vessel
beside the existing storage barrel.

Oak and iron reuse the tavern/barrel palette. Copper starts from doc 61's
`copper_body` (#B05828), with derived shadows/highlights and one restrained
`copper_patina` (#4A7858) accent. Liquid uses the specified #2A1808 with sparse
reflections. No light source, shader animation or simulated fluid is added.

The **16×16×16-cell** envelope contains **1,200 occupied voxels**, one connected
component and **4,300 triangles**. Local bounds are X/Z [-1,1], Y [0,2]. Scale
0.125 is baked into positions, leaving import/runtime scale at 1. Authored
colors export as linear `COLOR_0` for the existing lit, double-sided material.

`tools/generate_brewing_vat.py` owns the geometry and isolated review export.
The canonical furniture generator delegates to it, producing twelve placed
models and one shared packed crate.

## Integration

- `base:furniture:brewing_vat` uses floor placement, four yaw steps and one
  full 2×2×2 collision region. It adds no storage, heat, door or room-anchor
  behavior. The production category reserves its future role.
- `base:resources:furniture:brewing_vat` uses the shared crate model, heavy
  weight class and stack limit 5. Trade value 24 is provisional data.
- **Build → Brewing Vat** selects the piece. **Storage Zone → DEV: Spawn
  Furniture** includes one packed vat per batch. Restart a running game
  to load the new model, definition and menu entry.
- Existing fetch/build, uninstall/refund and save/restore implementations
  handle the piece. No registry, autoload, global script class or save-schema
  change is needed. Brewery recipes and workshop data are unchanged.

The existing six-column Build grid accommodates twelve pieces on two rows
and Cancel on a third. Its growth/positioning code is unchanged. The previous
bed UI fixture now calculates its expected button/row counts from the current
roster, while still testing screen bounds, actual bed dispatch and smaller menus.

## Review and verification

The isolated project is `tmp/brewing_vat_preview/project.godot`. Seven native
Godot 4.7.2 Forward+ / D3D12 captures show four asset angles, native dwarf scale,
comparison with the barrel/packed crate and an example brewing area. All
surrounding furniture remains independently buildable.

`tools/VerifyBrewingVat.gd` checks actual placement, item-manager and dwarf
pickup/build methods on an in-memory floor:

- Nonblocking ghosts, overlap prevention, four rotations, native model
  bounds/material flags, two-layer occupancy and neighboring walkability.
- Fetch reservation release/reclaim, carrying and consuming one packed vat,
  uninstall/refund of the same item, and installed save/restore.
- Unchanged terrain and no storage, heat or door side effects.
- Actual Build-panel rectangles and vat-button dispatch at 1280×800 and
  2560×1440. All thirteen buttons fit in an 869×224 panel with three rows.

The updated bed fixture also passes. These are direct integration checks,
not a full autonomous scheduler or main-world playthrough. No player saves
or UI-layout preferences are used. Minimal fixtures emit the existing
missing-sky/unseeded-weather warnings; final logs contain no errors.

The audit preserves all **150 prior GLBs**, all **eleven prior furniture
definitions** and all prior item definitions. All thirteen canonical exports
match shipping bytes; every vat voxel fits the collision envelope. Snapshot,
geometry validation, runtime checks and final audit are under
`tmp/brewing_vat_preview/`.

## Reproduction

```powershell
python -B tools/generate_brewing_vat.py --install
$vatEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $vatEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\brewing_vat_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $vatEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\brewing_vat_preview', '--resolution', '1600x1000', '--', '--capture') -WindowStyle Hidden -Wait
Start-Process -FilePath $vatEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $vatEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tools/VerifyBrewingVat.gd') -WindowStyle Hidden -Wait
Start-Process -FilePath $vatEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tools/VerifyBed.gd') -WindowStyle Hidden -Wait
```

Omit `--install` for review-only export, or `-- --capture` for interactive review.
