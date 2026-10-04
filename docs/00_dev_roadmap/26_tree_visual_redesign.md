# 26 — Tree visual redesign

> **Full-roster follow-up:** [doc 29](29_complete_tree_roster.md) completes
> every sapling, ancient tree, seasonal model and structural variant. The
> approved baseline GLBs below are unchanged. Single-model selections and
> remaining-work notes below describe this earlier integration phase.

**Status (2026-10-01):** the approved mature oak and pine summer/winter models
are imported into the live game. Four existing GLB paths were overwritten.
The isolated review project remains in `tmp/tree_redesign_preview`.

Mature oak summer and mature pine summer/winter now select only their approved
baseline models. Older alternate files remain available but are no longer
selected for those seasons. Pine's spring/autumn fallback also uses the new
summer model. Mature apple has since been imported across all seasons and
both autumn fruit states ([doc 27](27_apple_visual_redesign.md)). Mature
juniper summer/winter is also imported ([doc 28](28_juniper_visual_redesign.md)).
Oak spring/autumn, saplings and ancient trees retain their earlier art
pending further review. Scatter, harvest, growth,
collision footprints and the seasonal resolver itself are unchanged.

## Approved direction

Retain **one voxel per block** for trees and **eight per block** for characters.
Increase visual quality through silhouette, supporting branches, coherent leaf
masses and color handling. Mature summer heights remain oak 17 and pine 20
blocks. The updated dwarfs accompany the models at their actual 3.375-block
maximum height.

- **Oak:** bent, flared trunk with multiple substantial forks. Offset crowns
  create a broad, uneven outline; small openings expose the supporting wood.
  The winter model is the summer model's existing wood with its leaves removed.
- **Pine:** overlapping, irregular boughs taper into a continuous leafy leader.
  Dark, cool greens distinguish it from the warmer oak. Winter snow recolors
  connected top patches; it does not reroll the tree or add another shell.
- **Color:** five leaf colors per species, broad value bands within each leaf
  mass, continuous bark accents, and three snow colors. No independent random
  color per cube.

## Source and asset contracts

`tools/generate_tree_redesign.py` authors the four models using the shared
`voxel_glb.py` container and writer. Its CLI exports to the review directory
only. The shipping `generate_oak_glbs.py` and `generate_pine_glbs.py` generators
reuse the approved builders and linear-color exporter for those four live
models, so regeneration cannot silently restore the earlier art. Their legacy
builders remain responsible for the other models and historical comparisons.
`tools/TreeRedesignPreview.gd` is copied into that standalone project. It has
no game autoloads and does not create saves or modify the generated world.

The palette is authored in sRGB and converted to **linear COLOR_0 at export**.
The new meshes therefore use the existing game material with
`vertex_color_is_srgb = false`. This conversion is local to the prototype
exporter: dwarf colors and the shared writer are unchanged. The review's
"Correct old colors" toggle interprets only the reference trees as sRGB so
shape can also be compared without their original washed-out color handling.
It does not modify the reference GLBs.

Cells are one-unit cubes, Y=0 at the ground, baked scale 1.0. The oak's odd
3x3 root is centered with a half-cell X/Z export offset; the pine's even 2x2
root already straddles the origin. Live logical trunk footprints remain 3x3
for mature oak and 2x2 for mature pine. Crowns are visual overhangs, not colliders.

Branches have face-connected spines, including one-block twig ends. Leaf
masses are solid. Meshing excludes faces bordering sealed internal air as
well as adjacent solid cells. This filtering is local to the tree exporter.

## Review measurements

Dimensions are X width x Y height x Z depth, in world blocks. Triangle counts
are exported mesh triangles, before any material or shadow rendering cost.

| Approved model | Dimensions | Triangles | Previous baseline triangles |
|---|---:|---:|---:|
| Oak summer | 15 x 17 x 13 | 1,660 | 1,648 |
| Oak winter | 12 x 16 x 11 | 1,000 | 780 |
| Pine summer | 10 x 20 x 11 | 960 | 1,368 |
| Pine winter | 10 x 20 x 11 | 960 | 1,448 |

The oak's visible crown is slightly wider than the old baseline, without a
height increase. Winter loses one block of leaf height. The pine's wider,
more complete silhouette uses about 30% fewer triangles than the current
summer baseline. These are geometry measurements, not a forest FPS benchmark.

Validation completed:

- All four models are a single face-connected occupied-cell component.
- Oak's 153 wood cells retain their positions and colors in both seasons.
- Pine's summer/winter occupied cells, exported positions and normals are
  identical; its exposed wood retains its colors.
- Exported arrays match the authored meshes, with finite colors and unit
  cube edges. Root bases are centered and remain 3x3 / 2x2.
- Regeneration produces byte-identical GLBs.
- Before import, all 58 live tree hashes matched the pre-prototype audit.
- Godot 4.7.2 imported the assets and rendered 11 review captures through
  Forward+ / D3D12, ending with `TREE_REDESIGN_REVIEW_OK` and no script errors.

`validation.json` records model bounds, counts and hashes; `checks.json`
records the export-array, regeneration and live-asset audit results.

Live integration validation completed after approval:

- All four live GLBs match their approved preview SHA-256 hashes exactly.
  The other 54 tree GLBs retain their original hashes.
- All 30 oak/pine generator outputs reproduce the live files byte-for-byte.
- The real `SurfaceFloraSpawner` resolves 3,072 species/stage/season/position
  combinations to imported PackedScenes. Approved mature seasons always pick
  their new model; pine spring/autumn correctly fall back to the new summer.
- All four approved models instantiate through `_instance_tree` at scale 1.0,
  with the existing linear vertex-color material, root alignment, one trunk
  collider, and unchanged occupancy bounds. No canopy occupancy is added.
- `LIVE_TREE_IMPORT_OK` and `LIVE_TREE_WORLD_ART_OK` pass in Godot 4.7.2.
  `renders/live_world.png` captures all four through the live spawner under
  the game's noon sky. The temporary review platform is not saved or added
  to the game scene. Autoload warnings before the check creates its scene
  are unrelated to the assets; the game then binds its sky normally.

`integration.json` records the live replacement hashes and check results.

## Reproduction and viewing

From the repository root:

```powershell
# Regenerate the shipping oak/pine sets, retaining the approved baseline art:
python tools/generate_oak_glbs.py
python tools/generate_pine_glbs.py

# Rebuild the isolated preview and historical before/after references:
python tools/generate_tree_redesign.py

$treeEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $treeEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\tree_redesign_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $treeEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\tree_redesign_preview', '--resolution', '1600x1000', '--', '--capture') -WindowStyle Hidden -Wait
```

For interactive review, open `tmp/tree_redesign_preview/project.godot` in
Godot and run it, or launch the same project without `-- --capture`. Buttons
select summer, winter, before/after, mixed grove, and three-quarter/RTS/rear
views. The old-color toggle affects only comparison references. Captures
hide the controls and save under `tmp/tree_redesign_preview/renders`.

The grove uses the project's configured 45-degree FOV, 50-degree elevation
and 85-block default camera distance. Its five trees use several authored
orientations to inspect the silhouette from different sides; these
are repeated prototypes, not five new variants. Studio lighting matches
the earlier dwarf review; this is not a test of live sky/weather lighting.

## Roster completion

The mature apple and juniper baselines were completed in docs 27 and 28.
[Doc 29](29_complete_tree_roster.md) now completes all saplings, ancient trees,
additional structural variants and oak spring/autumn. Matching variant
counts/order preserve seasonal identity with the existing position hash.
The complete 86-model roster has been checked in the natural forest at the
existing scatter density, with unchanged trunk collision and placement.
