# 35 — Settlement flag visual redesign

**Status (2026-10-01): installed and verified.** The settlement marker is
now a crimson hanging standard with a gold geometric emblem, an iron-bound
oak mast and a compact dressed-stone footing. The existing 1×1 footprint,
three-block height, founding behavior and save format are unchanged.

## Design and asset contract

A capped crossbar supports cloth with broad stepped folds and two hanging
tails. Gold edging follows the lower hem; a hollow angular emblem appears
on both faces. The oak and iron reuse the upgraded furniture palette, and
the stone uses the hearth palette. Cloth and hardware are static geometry.

| Property | Installed asset |
|---|---|
| Item key | `base:items:special:settlement_flag` |
| Model | `assets/models/items/misc/settlement_flag.glb` |
| Authoring resolution | 8 voxels/block; scale 0.125 baked into positions |
| World bounds | X −0.5 to +0.5; Y 0 to 3; Z −0.375 to +0.375 |
| Occupied voxels | 362 |
| Triangles | 1,168 |
| Connected voxel components | 1 |
| Registered occupancy (unchanged) | 1×3×1 above the selected floor cell |
| Runtime/import scale (unchanged) | 1.0 |

`tools/generate_flag_redesign.py` is the canonical source. It uses the shared
voxel exporter and the tavern's local sRGB-to-linear `COLOR_0` conversion.
The model keeps the existing lit, double-sided placement material with
`vertex_color_is_srgb = false`.

The old model stored oak, blue cloth and brass in three material factors,
with no vertex colors. `FlagPlacementController` overrides these materials
with a white vertex-color material, so the old flag renders white when
placed. The new asset bakes its colors into vertices and therefore works
with that existing controller. Before/after renders deliberately use the
actual placement material for both assets.

## Review and verification

The isolated project is `tmp/flag_redesign_preview/project.godot`. Seven
Godot 4.7.2 Forward+ / D3D12 renders cover before/after at two elevations,
three flag views, dwarf scale and a small camp with the upgraded furniture.

Review and live imports passed without errors. The actual placement
controller produced the ghost and placed the new model with the expected
bounds, vertex colors and material. The flag blocks exactly one column
for three blocks; neighboring floor cells remain walkable. A director probe
verified the settlement-anchor and initial-squad hooks. An in-memory
serialize/restore round trip restored the model and anchor without calling
the squad-spawn hook again. This is a controller integration check, not a
full world-start playthrough, and no player saves are read or written.
The minimal fixture emits the existing missing-sky and unseeded-weather
warnings because it omits the main world scene.

The export is deterministic and matches the installed GLB. Every other
model under `assets/models`, the item definitions and the placement
controller match the pre-install hashes. Godot regenerated the flag's
import metadata normally; no import settings were hand-edited.

`validation.json`, `runtime_checks.json` and `integration.json` record the
checks. `reference/settlement_flag.glb` preserves the original model, and
`pre_import.json` records the pre-install hashes.

## Reproduction

```powershell
python -B tools/generate_flag_redesign.py --install
$flagEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $flagEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\flag_redesign_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $flagEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\flag_redesign_preview', '--resolution', '1600x1000', '--', '--capture') -WindowStyle Hidden -Wait
Start-Process -FilePath $flagEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $flagEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tmp/flag_redesign_preview/LiveFlagCheck.gd') -WindowStyle Hidden -Wait
```

Omit `--install` for review-only export, or `-- --capture` for interactive
review controls. Restart the running game to reload its cached model.
