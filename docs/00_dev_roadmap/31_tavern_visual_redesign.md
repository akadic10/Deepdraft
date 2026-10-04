# 31 — Tavern bar and bench visual redesign

**Status (2026-10-01): installed and verified.** The bar and bench now match
the richer oak, iron and substantial construction of the upgraded dwarves
and [2×2 hearth](30_hearth_visual_redesign.md). Both retain their existing
2×1 placement footprints. No gameplay definitions or scripts changed.

## Art direction

The old bar was a striped solid box with single-cell tap knobs. Its slab
extended past the declared footprint to 2.25×1.25 blocks. The replacement
insets the body under a thick, chamfered slab, keeping the entire model
inside 2×1. Recessed front panels, stout posts, iron shoes, a customer-facing
footrail and shaped taps make its purpose clearer. The countertop stands
1.5 blocks high; the oak tap handles reach 2 blocks. The +Z face has the
footrail; the −Z serving face has framed recesses. These are visual details,
not functional storage or serving behavior.

The bench has a two-cell-thick plank seat over four heavy legs, end trestles
and a longitudinal brace. Short iron brackets and exposed tenon ends echo
the bar. The seat reaches 1 block, fitting its existing collision height.
Both pieces use broad oak tones and sparse grain marks rather than random
per-cell color noise.

## Asset contract

| Property | Tavern bar | Bench |
|---|---|---|
| Authoring resolution | 8 voxels/block | 8 voxels/block |
| Footprint / base grid | 2×1 / 16×8 cells | 2×1 / 16×8 cells |
| World bounds | X ±1, Z ±0.5, Y 0–2 | X ±1, Z ±0.5, Y 0–1 |
| Occupied voxels | 1,016 | 472 |
| Triangles | 1,756 | 1,248 |
| Connected voxel components | 1 | 1 |
| Collision max (unchanged) | [2,2,1] | [2,1,1] |

Scale 0.125 is baked into vertex positions; import/root scale stays 1.
Authored sRGB palette values are converted to linear `COLOR_0` by the local
tavern exporter. This matches the existing lit, double-sided furniture
material's default `vertex_color_is_srgb = false`, as with the hearth.
Other furniture exports retain their existing color interpretation.

`tools/generate_tavern_redesign.py` owns both builders and their color
conversion. The canonical `tools/generate_furniture_glbs.py` delegates to
them so rebuilding the furniture set preserves the new art. The old
builders remain available under `build_legacy_tavern_bar` and
`build_legacy_bench` for historical comparisons.

Only the two shipping GLBs are replaced. Furniture keys, packed item,
definitions, footprints, collisions and save fields are unchanged. The
storage shelf remains outside this pass, preserving the planned
hand-authored replacement.

## Verification and review

Review project: `tmp/tavern_redesign_preview/project.godot`.
`tools/TavernRedesignPreview.gd` reuses the existing studio and approved
dwarf assembly. Ten native Godot 4.7.2 Forward+ / D3D12 renders cover both
before/after comparisons, close views, rear construction, dwarf scale and
the pair beside the installed hearth. Original assets keep their actual
runtime color interpretation in comparisons.

Godot imported the review and live assets without errors. An isolated
runtime fixture exercised both models through the real placement
controller, ghosts and build completion at all four rotations. Imported
mesh bounds align with the rotated collision boxes; the existing material
and navigation behavior pass. No player saves were loaded or written.
The minimal fixture emits the existing missing-sky and unseeded-weather
warnings because it does not create the main world scene.

All seven canonical furniture exports were compared in a temporary
directory and match the shipping files byte for byte. The other five
models, shared packed item and both furniture JSON definitions match the
pre-install snapshot. `validation.json`, `runtime_checks.json` and
`integration.json` record the results. `reference/` and `pre_import.json`
retain the originals and pre-install hashes.

## Reproduction

```powershell
python -B tools/generate_tavern_redesign.py --install
$tavernEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $tavernEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\tavern_redesign_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $tavernEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\tavern_redesign_preview', '--resolution', '1600x1000', '--', '--capture') -WindowStyle Hidden -Wait
Start-Process -FilePath $tavernEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $tavernEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tmp/tavern_redesign_preview/LiveTavernCheck.gd') -WindowStyle Hidden -Wait
```

Omit `--install` for a review-only export. Omit `-- --capture` for the
interactive camera and comparison controls. Restart a running game to
reload cached GLBs.
