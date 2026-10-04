# 38 — Dining Table Asset and Placement

Status: **INSTALLED AND VERIFIED — 2026-10-01.**

The dining table now has a shipping model, furniture/item definitions and
Build-panel placement. Its approved **2×2 footprint and 1.5-block height**
replace the original 1-block-high specification, putting the tabletop half
a block above the existing bench seats. Resolution remains eight voxels/block.
Dining, seating assignments and comfort effects remain future gameplay work.

**Seating clarification (Alen, 2026-10-01):** the shipping table includes no
chairs or benches. The review's dining-set images arrange existing benches
beside it for context. Seating must remain independently built and placed;
future chairs will have their own model, packed item and placement definition.

## Model

`assets/models/furniture/wooden_table.glb` uses the tavern oak/iron palette:
four broad planks with sparse grain, worn edges and clipped corners, two
stout braced trestles, a through-tenoned stretcher, iron corner fittings and
short iron shoes on the feet. The supports leave readable gaps beneath the
slab while the full footprint remains blocked for navigation.

The 16×12×16-cell model contains **1,100 occupied voxels**, one connected
component and **2,536 triangles**. Local bounds are X/Z [-1, 1], Y [0, 1.5].
Scale 0.125 is baked into vertex positions; import and runtime scale remain 1.
Authored sRGB colors are converted locally to linear `COLOR_0` for the
existing lit, double-sided furniture material.

`tools/generate_dining_table.py` owns the geometry and review export.
`tools/generate_furniture_glbs.py` delegates the table to that builder;
its full output is now nine placed models plus the shared packed crate.

## Placement and occupancy

`base:furniture:wooden_table` uses floor placement, four yaw steps and
`collision_regions: [{min:[0,0,0], max:[2,1.5,2]}]`. The shared packed item
`base:resources:furniture:wooden_table` is heavy, stacks to 5, and has
provisional trade value 12. **Build → Dining Table** starts placement;
**Storage Zone → DEV: Spawn Furniture** supplies one packed table per batch.
Restart a running game to load the new menu entry and definitions.

The table exposed a truncation in `FurniturePlacementController._install()`:
converting the collision's Y maximum directly to an integer discarded its
upper half-block. Registration now floors the lower Y bound and ceils the
upper bound, covering every touched grid layer. The visual and declared
height stay 1.5; navigation occupancy is two whole layers. Existing integer
heights are unchanged. Terrain data, three-block clearance, X/Z registration
and the existing furniture lifecycle are unchanged.

There are no new autoloads or global script classes. All existing assets and
definitions are preserved, including the shelf awaiting Alen's authored model.

## Review and verification

`tmp/dining_table_preview/project.godot` is an isolated review project.
Seven native Godot 4.7.2 Forward+ / D3D12 captures show the table at three
angles, two views with benches on adjacent grid-aligned footprints, dwarf
scale and the broader tavern set. Review and live-project imports pass.

`tools/VerifyDiningTable.gd` uses the real furniture controller, item manager
and dwarf pickup/build methods on an in-memory floor fixture. It verifies:

- Build-menu and DEV-spawner registration for the ninth furniture piece.
- Nonblocking ghosts, prevention of overlapping placements, all four yaw
  settings, exact model bounds, native scale and the existing lit material.
- Fetch reservation release/reclaim, dwarf pickup and packed-item consumption
  on build completion, uninstall refunds, and installed save restoration.
- Four occupied footprint cells, both touched vertical layers, an empty
  third layer, walkable neighbors and unchanged air in the terrain grid.
- The previous cell coverage of all eight older pieces at all four rotations,
  including the door's empty occupancy, with no residual heat/door entries.

These are direct runtime integration checks, not an autonomous pathfinding/
scheduler or main-world UI playthrough. No player saves were read or written.
The minimal fixture reports the existing missing-sky and unseeded-weather
warnings because it omits the world environment; the final run has no errors.

The final audit compares all ten canonical exports with shipping GLBs and
all 147 pre-existing models (world assets plus dwarf parts) with their prior
hashes. The eight existing furniture definitions and existing item definitions
are unchanged. `pre_import.json`, `validation.json`, `runtime_checks.json`
and `integration.json` in the review directory record the results.

## Reproduction

```powershell
python -B tools/generate_dining_table.py --install
$tableEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $tableEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\dining_table_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $tableEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\dining_table_preview', '--resolution', '1600x1000', '--', '--capture') -WindowStyle Hidden -Wait
Start-Process -FilePath $tableEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $tableEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tools/VerifyDiningTable.gd') -WindowStyle Hidden -Wait
```

Omit `--install` for review-only export, or `-- --capture` for interactive
review controls.
