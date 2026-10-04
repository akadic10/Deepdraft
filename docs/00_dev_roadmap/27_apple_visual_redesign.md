# 27 — Apple visual redesign

> **Full-roster follow-up:** [doc 29](29_complete_tree_roster.md) completes
> every sapling, ancient tree, seasonal model and structural variant. The
> approved baseline GLBs below are unchanged. Single-model selections and
> remaining-work notes below describe this earlier integration phase.

**Status (2026-10-01):** all five approved mature apple models are imported
into the live game, replacing the existing baseline GLBs for spring blossom,
summer leaf, autumn, autumn with fruit, and winter branches. The mature
registry now selects only these approved models. The review project remains
in `tmp/apple_redesign_preview`; growth, placement and harvest behavior are
unchanged.

## Art direction

The apple has a lower, wider orchard silhouette than the imported oak and
pine. A crooked trunk divides into spreading arms before they rise into six
uneven foliage masses. The summer crown stays 12 blocks tall, compared with
the approved oak's 17 and pine's 20. The root remains centered in the mature
apple's existing 3x3 trunk footprint.

Spring adds connected cream and pink blossom patches to the canopy surface.
Summer uses warm green leaves. Autumn shifts to gold and ochre, with a
separate fruit-bearing model that adds seven staggered pairs of red cubes on
outer shoulders and one upper shoulder. They are placed for readability from
several directions at the RTS camera's elevation, rather than hidden beneath
the canopy. These are visual clusters, not a literal count of harvest items.

All seasons contain exactly the same 113 wood cells and bark colors. Spring,
summer and unfruited autumn share the same occupied cells and exported
geometry. The fruit-bearing model adds 14 attached fruit cells; removing
them changes no branch, leaf position, or leaf color. Winter removes the
foliage and reveals the existing scaffold. Overhangs start at Y=4 or above,
clearing the updated dwarf's 3.375-block visual height outside the trunk.

## Asset contract and measurements

Trees stay at **one voxel per world block**, baked scale 1.0. The exporter
reuses the approved oak/pine tree helpers for face-connected branches, solid
leaf lobes, exposed-face meshing, and sRGB-to-linear `COLOR_0` conversion.
The game material can retain `vertex_color_is_srgb = false`. Dwarfs retain
their existing eight-voxels-per-block scale and color interpretation.

| File | Dimensions (X x Y x Z) | Triangles |
|---|---:|---:|
| `apple_mature_spring.glb` | 15 x 12 x 11 | 1,324 |
| `apple_mature.glb` | 15 x 12 x 11 | 1,324 |
| `apple_mature_autumn.glb` | 15 x 12 x 11 | 1,324 |
| `apple_mature_autumn_fruiting.glb` | 15 x 12 x 13 | 1,396 |
| `apple_mature_winter.glb` | 12 x 10 x 9 | 776 |

The summer baseline is effectively the same geometry budget as the old
1,320-triangle model. This is an exported mesh count, not an FPS measurement.

## Review and validation

- All five models are single face-connected occupied-cell components.
- Every fruit cube attaches directly to the canopy. No flowers or fruit are
  painted onto the trunk, and no foliage grows down its sides.
- Exported positions, normals and colors match their authored meshes; all
  cube edges are one world unit and all normals are flat axis normals.
- Root centering, shared seasonal wood, exact fruit removal, and byte-identical
  regeneration pass. The five live replacements match their approved preview
  hashes; the other 53 tree GLBs retain their pre-import hashes, including
  the four approved oak/pine replacements.
- Godot 4.7.2 Forward+ / D3D12 imported all models and rendered 15 captures,
  ending with `APPLE_REDESIGN_REVIEW_OK`.
- The canonical apple generator reproduces all 20 shipping apple GLBs exactly,
  including the five replacements and the preserved legacy stages/alternates.
- Live integration passed 832 model resolutions across all apple stages and
  seasons, including the separate unfruited autumn model selector. All five
  mature models instantiate through `SurfaceFloraSpawner._instance_tree` at
  scale 1.0, grounded at Y=0 locally, with the default linear vertex-color
  material, one 3x5x3 trunk collider and the existing 3x3 occupancy footprint.
  The check ended with `LIVE_APPLE_IMPORT_OK`.
- A separate debug-world capture uses the real noon sky/light setup and
  approved dwarfs for scale. `renders/live_world.png` shows all five models;
  the run ended with `LIVE_APPLE_WORLD_ART_OK` without script errors. The
  harness emits the existing sky/weather startup warnings before creating
  the world scene, then binds the scene for capture.

`validation.json` contains bounds, mesh counts and hashes; `checks.json`
records the original prototype geometry and isolation checks.
`integration.json` records the subsequent live replacement checks.
Captures include three-quarter,
rear and RTS views, old/new comparisons, a side-by-side species scale view,
and a five-tree orchard at 45-degree FOV, 50-degree elevation and 85-block
camera distance. Lighting matches the earlier oak/pine studio review.

## Reproduction

```powershell
# Regenerate the shipping set, retaining the approved mature baseline:
python tools/generate_apple_glbs.py

# Rebuild the isolated review with historical before/after references:
python tools/generate_apple_redesign.py

$appleEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $appleEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\apple_redesign_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $appleEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\apple_redesign_preview', '--resolution', '1600x1000', '--', '--capture') -WindowStyle Hidden -Wait
```

Open the generated `project.godot` in Godot for interactive inspection, or
launch it without `-- --capture`. The preview has seasonal, harvest-state,
species-scale and orchard views. `tools/AppleRedesignPreview.gd` reuses
`TreeRedesignPreview.gd` for studio setup and dwarf assembly. Captures are
written to the preview's `renders` directory.

## Live integration

All five existing baseline filenames are retained. The shipping apple
generator reuses `generate_apple_redesign.py` for approved mature geometry and
linear colors. The isolated review regenerates its historical references
from the legacy builder so its before/after view remains useful after import.
The mature summer and autumn model arrays select only the approved baseline;
older alternate files remain available but are no longer selected. Trunk
collision, harvest amounts, placement and growth data remain intact.

The existing world spawner selects `autumn_fruiting` for apple throughout
autumn when the stage has a fruit-harvest definition. This art study supplies
both visual states; it does not implement per-tree harvested-state persistence.
Sapling, ancient and additional structural variants are now complete in [doc 29](29_complete_tree_roster.md).
