# 32 — Storage barrel visual redesign

**Status (2026-10-01): installed and verified.** The storage barrel now uses
the warm oak and dark iron palette of the [tavern set](31_tavern_visual_redesign.md).
Its 1×1 footprint, one-block height, collision and eight-item capacity are
unchanged. This is an art replacement; no gameplay definitions or runtime
scripts changed.

## Design and export

The cask has a fuller middle, narrower ends, broad vertical staves and two
continuous dark iron hoops with restrained rivets. A raised wooden rim
surrounds a recessed plank lid and an inset dark bung. Quiet stave seams
replace the old per-cell color noise. The silhouette and detail all use
the existing eight voxels per block; no fractional or enlarged voxels.

| Property | Installed asset |
|---|---|
| File | `assets/models/furniture/barrel.glb` |
| Authoring envelope | 8×8×8 cells |
| World bounds | X/Z −0.5 to +0.5; Y 0 to 1 |
| Occupied voxels | 343 |
| Triangles | 728 |
| Connected voxel components | 1 |
| Collision region (unchanged) | min [0,0,0], max [1,1,1] |
| Storage (unchanged) | capacity 8, render_contents false |

`tools/generate_barrel_redesign.py` owns the barrel geometry and uses the
tavern builder's shared oak/iron palette and linear `COLOR_0` export.
Scale 0.125 is baked into positions; import/root scale stays 1. The existing
lit, double-sided furniture material keeps `vertex_color_is_srgb = false`.
The canonical furniture generator delegates to this builder and conversion.
Its former builder remains available as `build_legacy_barrel`.

## Review and validation

The isolated project is `tmp/barrel_redesign_preview/project.godot`.
Seven native Godot 4.7.2 Forward+ / D3D12 captures include before/after,
three views of the model, actual dwarf/bar scale and the full tavern set.
Original references retain their actual in-game color interpretation.

Godot imported both the review and live asset without errors. The actual
placement controller instantiated the new GLB as a ghost and completed
build at all four rotations. Model bounds, material, collision alignment,
navigation blocking and the eight-item storage component passed checks.
The isolated fixture does not load or write player saves; it emits the
existing missing-sky and unseeded-weather warnings because it does not
create the main world scene.

All seven canonical exports match shipping bytes. The other six furniture
models, shared packed item and barrel JSON definition match the pre-install
snapshot. `validation.json`, `runtime_checks.json` and `integration.json`
record the results. The old GLB is preserved in `reference/barrel.glb`,
alongside the hash/definition snapshot in `pre_import.json`.

## Reproduction

```powershell
python -B tools/generate_barrel_redesign.py --install
$barrelEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $barrelEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\barrel_redesign_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $barrelEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\barrel_redesign_preview', '--resolution', '1600x1000', '--', '--capture') -WindowStyle Hidden -Wait
Start-Process -FilePath $barrelEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $barrelEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tmp/barrel_redesign_preview/LiveBarrelCheck.gd') -WindowStyle Hidden -Wait
```

Omit `--install` for a review-only export. Omit `-- --capture` for interactive
camera/comparison controls. Restart a running game to reload the cached GLB.
