# 33 — Storage chest visual redesign

**Status (2026-10-01): installed and verified.** The chest now matches the
oak and iron palette of the upgraded barrel and tavern furniture. Its
1×1 footprint, one-block collision envelope and 24-item capacity are
unchanged. No gameplay definitions or runtime scripts changed.

## Design and asset contract

A stout oak body stands on four broad feet, reinforced with iron corner
straps. A thick, slightly crowned lid has two iron bands that continue into
rear hinges. Its recessed opening seam and projecting front clasp make the
chest recognizable from the gameplay camera. Broad plank colors and sparse
grain match the existing upgraded furniture. The lid is static geometry;
this pass adds no opening animation or visible stored contents.

| Property | Installed asset |
|---|---|
| Furniture key | `base:furniture:storage_chest` |
| Historical model filename | `assets/models/furniture/storage_crate.glb` |
| Authoring envelope | 8×8×8 cells at 8 voxels/block |
| World bounds | X/Z −0.5 to +0.5; Y 0 to 1 |
| Occupied voxels | 334 |
| Triangles | 820 |
| Connected voxel components | 1 |
| Collision (unchanged) | min [0,0,0], max [1,1,1] |
| Storage (unchanged) | capacity 24, render_contents false |

`tools/generate_chest_redesign.py` owns the geometry and reuses the tavern
palette and linear `COLOR_0` conversion. Scale 0.125 is baked into positions;
import/root scale stays 1. The existing lit, double-sided furniture material
keeps `vertex_color_is_srgb = false`. The canonical furniture generator
delegates the chest to this builder; the previous builder remains available
as `build_legacy_storage_chest`.

The shared packed-furniture box and all other furniture models are preserved.
The live JSON remains `data/furniture/storage_chest.json`; no crate/chest key
rename or save migration is needed.

## Review and verification

The isolated project is `tmp/chest_redesign_preview/project.godot`.
Seven native Godot 4.7.2 Forward+ / D3D12 renders cover before/after at two
camera elevations, three model views, dwarf/barrel scale and a storage set.
Original references retain their actual in-game color interpretation.

Review and live imports completed without errors. The actual placement
controller instantiated the new model as a ghost and completed build at all
four rotations. Imported bounds, material, collision alignment, navigation
blocking and the 24-item storage component passed checks. The isolated
fixture reads/writes no player saves and emits the existing missing-sky and
unseeded-weather warnings because it does not create the main world scene.

All seven canonical exports match shipping bytes. The other six models,
shared packed item and chest definition match the pre-install snapshot.
`validation.json`, `runtime_checks.json` and `integration.json` record the
results. The original GLB is retained in `reference/storage_crate.glb`;
`pre_import.json` holds the pre-install hashes and definition.

## Reproduction

```powershell
python -B tools/generate_chest_redesign.py --install
$chestEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $chestEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\chest_redesign_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $chestEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\chest_redesign_preview', '--resolution', '1600x1000', '--', '--capture') -WindowStyle Hidden -Wait
Start-Process -FilePath $chestEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $chestEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tmp/chest_redesign_preview/LiveChestCheck.gd') -WindowStyle Hidden -Wait
```

Omit `--install` for review-only export, or `-- --capture` for interactive
review controls. Restart a running game to reload its cached model.
