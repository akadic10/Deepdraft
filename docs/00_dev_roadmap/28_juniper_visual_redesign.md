# 28 — Juniper visual redesign

> **Full-roster follow-up:** [doc 29](29_complete_tree_roster.md) completes
> every sapling, ancient tree, seasonal model and structural variant. The
> approved baseline GLBs below are unchanged. Single-model selections and
> remaining-work notes below describe this earlier integration phase.

**Status (2026-10-01):** the approved mature summer/winter models are imported
into the live game. Both existing baseline GLBs were replaced, and the mature
summer array now selects only the approved model. The isolated review remains
in `tmp/juniper_redesign_preview`.

## Direction

The previous juniper hides its trunk inside a narrow foliage column. Its
random per-cell color variation competes with the berries, and separate
seasonal seeds change its geometry in winter.

The redesign retains the 12-block height and one-block trunk footprint. A
crooked woody stem splits into four uneven upright foliage clusters, with
openings that expose the fork. The cooler blue-green palette distinguishes
juniper from the warmer broadleaf trees and the taller pine. Six deliberate
slate-blue berry cells sit on exposed foliage shoulders. They are visual
accents, not a literal count of harvested items.

Winter recolors 36 cells as joined snow patches on upward-facing foliage
and short snow lips. All occupied cells, mesh positions, normals and indices
match summer. Visible bark and berry colors remain identical across seasons.

## Scale and export contract

| Model | Bounds X × Y × Z | Occupied cells | Triangles |
|---|---:|---:|---:|
| `juniper_mature.glb` | 9 × 12 × 6 | 129 | 568 |
| `juniper_mature_winter.glb` | 9 × 12 × 6 | 129 | 568 |

The previous baseline meshes had 620 summer / 664 winter triangles. These
are geometry counts; no frame-rate claim is implied.

- Trees remain one voxel per world block, baked scale 1.0.
- The single root cell is centered on X=Z=0; its bottom is Y=0.
- All overhangs begin at Y=4 or higher outside the one-block trunk footprint,
  clearing the approved dwarf's 3.375-block visual height.
- The existing 1×6×1 trunk collider and occupancy remain unchanged.
  Foliage carries no collision or navigation occupancy.
- Export uses the approved tree helper's sRGB-to-linear `COLOR_0` conversion.
  Runtime `vertex_color_is_srgb` stays false; dwarf and legacy tree color
  interpretation remains local to those assets.

## Verification

The canonical generator `tools/generate_juniper_glbs.py` reuses the approved
builder and exporter in `tools/generate_juniper_redesign.py`. The preview
script, `tools/JuniperRedesignPreview.gd`, reuses the oak/pine studio's actual
Godot lighting, vertex-color material and dwarf assembly.

- Both models form one face-connected occupied-cell component.
- Root centering, outside-footprint clearance, stable wood/berries and
  identical seasonal geometry pass.
- Exported positions, normals, colors and indices match their authored
  arrays. Coordinates are finite, indices valid, and face normals axis-aligned.
- Repeated exports are byte-identical.
- Both live replacements match their approved preview hashes. The other 56
  tree GLBs retain their pre-import hashes, including the nine approved
  oak/pine/apple replacements. Historical juniper references are regenerated
  from the legacy builder to preserve the before/after comparison.
- The canonical generator reproduces all eight shipping juniper GLBs
  byte-for-byte. Placement, growth, collision and harvest data are unchanged.
- Godot 4.7.2 Forward+ / D3D12 imported the isolated project and rendered eight
  captures, ending with `JUNIPER_REDESIGN_REVIEW_OK`.
- Live integration checked 768 model resolutions across three stages and
  four seasons, including spring/autumn fallback to summer. Both mature
  models instantiate through `SurfaceFloraSpawner._instance_tree` at scale
  1.0 with correct grounding, default linear vertex-color material, one
  1×6×1 trunk collider and one-block-wide occupancy.
- World generation using seed 1388941899 produced 462 mature junipers; all
  loaded the approved summer GLB with 9×12×6 bounds. The actual debug-world
  noon lighting capture is `renders/live_world.png`.

`validation.json` records bounds, mesh counts and hashes. `checks.json`
records original prototype export/isolation checks; `integration.json`
records the subsequent live replacement checks. Captures cover front, rear,
three-quarter, RTS, before/after, all four mature species at matching scale,
and summer/winter groves at FOV 45°, elevation 50°, distance 65 blocks.

## Reproduction

```powershell
# Reproduce the shipping set, including the approved mature baseline:
python tools/generate_juniper_glbs.py

# Rebuild the isolated review and its historical references:
python tools/generate_juniper_redesign.py

$juniperEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $juniperEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\juniper_redesign_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $juniperEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\juniper_redesign_preview', '--resolution', '1600x1000', '--', '--capture') -WindowStyle Hidden -Wait
```

Run without `-- --capture` for interactive comparison controls.

## Live integration

Both baseline filenames are retained. The mature summer array selects only
the approved model; the older alternate file remains dormant. Spring/autumn
continue to fall back to summer, and winter selects the matching snowy GLB.
The review's historical references come from the legacy builder, matching
the oak/pine/apple review workflow.

Sapling, ancient and additional structural variants are now complete in
[doc 29](29_complete_tree_roster.md), including matching winter variants.
