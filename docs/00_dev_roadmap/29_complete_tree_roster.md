# 29 — Complete tree roster replacement

**Status (2026-10-01):** installed and verified in the live game. Oak, pine,
apple and juniper now use the redesigned art at every growth stage, season
and variant. This completes the remaining work from docs 26–28.

## Installed roster

| Species | Sapling models | Mature models | Ancient models | Total |
|---|---:|---:|---:|---:|
| Oak | 4 | 12 | 12 | 28 |
| Pine | 2 | 6 | 6 | 14 |
| Apple | 4 | 15 | 15 | 34 |
| Juniper | 2 | 4 | 4 | 10 |
| **Total** | **12** | **37** | **37** | **86** |

All 58 existing filenames remain valid. The 47 remaining older GLBs were
overwritten; the 11 previously approved mature baseline GLBs are unchanged,
verified by SHA-256. Another 28 seasonal counterparts complete the variants.
No legacy tree model remains in the live asset folders or registry selections.

Saplings have one shape per season. Mature and ancient oak, pine and apple
have three shapes per season; juniper has two. Every season for a given
stage uses the same variant count and ordering. The existing position hash
therefore picks the same structural variant through all seasons, without
changing the resolver. Pine and juniper still use summer for spring/autumn.

Apple mature/ancient models include both ordinary autumn and autumn-fruiting
states, each with three matching variants. The existing spawner selects the
fruiting state throughout autumn. Per-tree harvested-state persistence
remains separate work; saplings do not have a fruiting model.

## Art and scale

The full roster shares the approved broad color regions, connected foliage
and exposed woody structures. Ancient trees have heavier bases and larger,
less regular crowns. Saplings use compact versions of their species' shapes.
Variants broaden a crown shoulder and rotate or mirror the complete seasonal
structure on the voxel grid, preserving root position and branch continuity.

- **Oak:** a forked sapling and a massive ancient tree with root flares,
  spreading branches and eleven connected canopy lobes. All stages now have
  fresh spring greens, warm autumn leaves and the same bare winter scaffold.
- **Pine:** small overlapping boughs on saplings; six uneven, overlapping
  bough levels on ancient trees. Branch tips stay inside the needle masses.
  Winter adds connected snow patches without changing occupied geometry.
- **Apple:** spreading orchard saplings with small spring blossom accents;
  ancient trees have broad low crowns, heavy crooked arms, blossom patches
  and 24 attached fruit cells. Removing fruit changes no leaf or branch.
- **Juniper:** compact cool foliage on saplings; ancient trees expose several
  crooked forks beneath six uneven sprays and ten berry accents. Snow leaves
  the wood and berry colors intact.

Summer baseline bounds, X × Y × Z in world blocks:

| Species | Sapling | Mature | Ancient |
|---|---:|---:|---:|
| Oak | 5 × 7 × 5 | 15 × 17 × 13 | 23 × 24 × 21 |
| Pine | 4 × 8 × 5 | 10 × 20 × 11 | 13 × 27 × 13 |
| Apple | 6 × 6 × 4 | 15 × 12 × 11 | 23 × 18 × 19 |
| Juniper | 4 × 5 × 3 | 9 × 12 × 6 | 12 × 16 × 8 |

Alternate silhouettes and fruit can extend these bounds. Exact per-model
bounds, voxel/triangle counts and hashes are in the review's `validation.json`.

Trees remain one voxel per world block, scale 1.0. Character resolution stays
at eight voxels per block. All tree colors now use the approved exporter’s
sRGB-to-linear `COLOR_0` conversion; the default runtime material continues
to use `vertex_color_is_srgb = false`.

Mature/ancient overhangs begin at Y=4 outside the existing trunk footprint.
Saplings remain nonblocking clutter. Placement, density, growth, harvest,
clearance heights, trunk collision and navigation occupancy are unchanged.

## Verification

- All 86 models are face-connected, grounded, deterministic and valid GLBs.
  Exported positions, normals, colors and indices match the authored arrays;
  winding, finite coordinates, valid indices and flat normals pass.
- Each canonical species generator reproduces its complete shipping set
  byte-for-byte. All live GLBs match the reviewed exports. Gameplay fields
  in all four JSON definitions match the pre-replacement snapshot.
- Godot 4.7.2 Forward+ / D3D12 imported the roster successfully. The isolated
  studio rendered 49 captures covering seasons, growth stages, mature and
  ancient variants, rear views and RTS views.
- The live spawner instantiated all 86 models at the expected bounds and
  scale with correct materials, grounding, trunk collision and occupancy.
  All 3,072 position/stage/season resolution checks passed.
- A generated debug world using seed **1388941899** contained **2,838 trees**.
  Summer, autumn, winter and spring each used all 26 available structural
  variants across all 12 species/stage combinations. Every tree retained
  its position and variant index through seasonal replacement.
- Four captures show that natural forest under the real noon sky/fog setup.
  No production scene, camera, weather or rendering settings were changed.
  Final import and runtime runs completed with no script errors. The test
  harness's two pre-scene sky/weather startup warnings are the same as the
  earlier mature-model checks; both systems bind after world creation.

Review files: `tmp/forest_redesign_preview/`. `pre_import.json` and `reference/`
preserve the pre-replacement roster; `export_checks.json`, `runtime_checks.json`
and `integration.json` record verification. Live captures are
`renders/live_forest_{summer,autumn,winter,spring}.png`.

## Reproduction

`tools/generate_forest_redesign.py` is the shared roster builder. The existing
four `generate_*_glbs.py` entry points call it for shipping geometry; their
legacy builders remain available for historical before/after previews.
`tools/ForestRedesignPreview.gd` reuses the earlier studio lighting/materials
and approved dwarf assembly at its actual 3.375-block visual height.

```powershell
# Build the isolated full-roster review:
python -B tools/generate_forest_redesign.py

# Regenerate shipping GLBs and update only model arrays and art comments:
python -B tools/generate_forest_redesign.py --install

# Import and render the isolated studio:
$forestEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $forestEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\forest_redesign_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $forestEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\forest_redesign_preview', '--resolution', '1800x1100', '--', '--capture') -WindowStyle Hidden -Wait
```

Launch the isolated project without `-- --capture` for interactive controls.
After replacing live GLBs, let Godot import them and restart a running game
to clear cached model resources.
