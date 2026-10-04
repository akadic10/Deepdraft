# 34 — Double door visual redesign

**Status (2026-10-01): installed and verified.** The door now matches the
warm oak and dark iron of the upgraded tavern and storage furniture. Its
2×1 footprint, 3.875-block height and walkable, room-sealing behavior are
unchanged. No gameplay definitions or runtime scripts changed.

## Design and asset contract

Heavy stiles and rails surround two recessed panels on each leaf. Three
tapered iron straps, projecting hinge knuckles and a ring pull give each
leaf readable hardware. A recessed dark centre line separates the leaves.
Both faces receive the same detailing so every placement rotation reads
well. The door remains a static closed mesh; this pass adds no animation.

| Property | Installed asset |
|---|---|
| Furniture key | `base:furniture:door` |
| Model | `assets/models/furniture/door.glb` |
| Authoring envelope | 16×31×6 cells at 8 voxels/block |
| World bounds | X −1 to +1; Y 0 to 3.875; Z −0.375 to +0.375 |
| Occupied voxels | 1,688 |
| Triangles | 3,944 |
| Connected voxel components | 1 |
| Footprint (unchanged) | 2×1, four yaw rotations |
| Collision (unchanged) | empty; `blocks_movement: false` |
| Room boundary (unchanged) | two columns, each floor + four air cells; one door identity |

`tools/generate_door_redesign.py` owns the geometry and reuses the tavern
palette and linear `COLOR_0` conversion. Scale 0.125 is baked into positions;
import/root scale stays 1. The existing lit, double-sided furniture material
keeps `vertex_color_is_srgb = false`. The canonical furniture generator
delegates the door to this builder; the previous builder remains available
as `build_legacy_door`.

The shared packed-furniture box, other six furniture models and door JSON
are preserved. Existing placements use the same model path and require no
save migration. The shelf remains reserved for Alen's hand-authored asset.

## Review and verification

The isolated project is `tmp/door_redesign_preview/project.godot`.
Seven native Godot 4.7.2 Forward+ / D3D12 renders cover before/after at two
camera elevations, three model views, dwarf scale and a mock stone doorway.
The stone surround is review geometry, not part of the installed door.
Original references retain their actual in-game color interpretation.

Review and live imports completed without errors. The actual placement
controller instantiated the replacement ghost and completed construction at
all four rotations. Imported bounds, footprint alignment and material passed
checks. Both tiles remain walkable, with actual navigation paths crossing
each tile. A fixture with a room on either side produced two separate rooms
of 64 air cells each, each counting one door. Removing the door clears the
sealing registration. The fixture reads/writes no player saves; it emits
the existing missing-sky and unseeded-weather warnings because it does not
create the main world scene.

All seven canonical exports match shipping bytes. The other six models,
shared packed item and door definition match the pre-install snapshot.
`validation.json`, `runtime_checks.json` and `integration.json` record the
results. The original GLB is retained in `reference/door.glb`;
`pre_import.json` holds the pre-install hashes and definition.

## Reproduction

```powershell
python -B tools/generate_door_redesign.py --install
$doorEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $doorEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\door_redesign_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $doorEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\door_redesign_preview', '--resolution', '1600x1000', '--', '--capture') -WindowStyle Hidden -Wait
Start-Process -FilePath $doorEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $doorEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tmp/door_redesign_preview/LiveDoorCheck.gd') -WindowStyle Hidden -Wait
```

Omit `--install` for review-only export, or `-- --capture` for interactive
review controls. Restart a running game to reload its cached model.
