# 36 — Shared packed furniture visual redesign

**Status (2026-10-01): installed and verified.** The common furniture item
is now a compact framed-oak crate with recessed side panels, two rope loops
and a raised knot. It retains the exact original bounds and carrying scale.
The one-box rule remains in force for all seven packed furniture types.

## Design and asset contract

Four broad wooden corners and top/bottom rails surround a recessed plank
core. Pale rope crosses the lid and continues down all four sides and under
the base; the crossing and tucked end project above the lid. The body uses
the upgraded furniture's oak palette, with quiet broad colors rather than
per-voxel noise. At this small size the framing and rope do most of the
visual work. The model contains no iron clasps or hinges.

| Property | Installed asset |
|---|---|
| Model | `assets/models/items/furniture/packed_furniture.glb` |
| Shared by | barrel, storage chest, storage shelf, tavern bar, bench, hearth, door |
| Authoring envelope | 5×4×5 cells at 8 voxels/block, including knot |
| World bounds (unchanged) | X/Z −0.25 to +0.375; Y 0 to 0.5 |
| World size (unchanged) | 0.625 × 0.5 × 0.625 |
| Occupied voxels | 69 |
| Triangles | 296 |
| Connected voxel components | 1 |
| Runtime/import scale | 1.0; existing shelf anchor scale 0.5 |

The original odd-width mesh has a +0.0625-block X/Z centre offset. This
replacement preserves that local frame as well as the original envelope.
The crate body is three cells high and the knot occupies the fourth, so
the added relief does not increase its carrying height.

`tools/generate_packed_furniture_redesign.py` owns the geometry and reuses
the tavern palette and local sRGB-to-linear `COLOR_0` conversion. Scale
0.125 is baked into positions. `tools/generate_furniture_glbs.py` delegates
`build_packed_box()` and the packed-item mesh export to the new builder;
the previous geometry remains available as `build_legacy_packed_box()`.

All item keys, stack limits, weight classes, furniture definitions, carry
offsets, stockpile behavior and shelf anchors remain unchanged. The seven
installed furniture models are preserved, including the shelf reserved for
Alen's hand-authored replacement.

## Review and verification

The isolated project is `tmp/packed_furniture_redesign_preview/project.godot`.
Seven native Godot 4.7.2 Forward+ / D3D12 captures show the old/new crate at
two elevations, three new-model views, the existing dwarf carry attachment
at native scale, and one crate per stockpile cell beside installed storage.
The carry image is a static scale study using the current attachment; it
does not introduce a new holding pose or animation.

Review and live imports passed without errors. The actual `ItemDropManager`
loaded all seven item types and confirmed they share the same imported
mesh, expected bounds, native scale and lit vertex-color material. Its
spawn, reserve, pickup, stockpile deposit, withdrawal and loose-drop APIs
passed, followed by an in-memory loose-item serialize/restore round trip.
The existing `ContainerStorageComponent` also placed the crate on a shelf
anchor at half scale. These are asset and API integration checks, not a
full autonomous hauling/building playthrough. No player saves were used.

The minimal fixture emits the existing missing-sky and unseeded-weather
warnings because it omits the main world scene. An initial fixture run
loaded gameplay classes before the autoloads were available; deferring
those loads fixed the fixture, and the final run completed without errors.

All eight canonical furniture/item exports match the shipping GLBs. Every
other model under `assets/models`, all furniture/item definitions and the
relevant runtime scripts match their pre-install hashes. The original
packed GLB remains in `reference/packed_furniture.glb`; `pre_import.json`,
`validation.json`, `runtime_checks.json` and `integration.json` record the
snapshot and results.

## Reproduction

```powershell
python -B tools/generate_packed_furniture_redesign.py --install
$packedEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $packedEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\packed_furniture_redesign_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $packedEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\packed_furniture_redesign_preview', '--resolution', '1600x1000', '--', '--capture') -WindowStyle Hidden -Wait
Start-Process -FilePath $packedEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $packedEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tmp/packed_furniture_redesign_preview/LivePackedFurnitureCheck.gd') -WindowStyle Hidden -Wait
```

Omit `--install` for review-only export, or `-- --capture` for interactive
review controls. Restart a running game to reload the cached model.
