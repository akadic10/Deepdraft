# 39 — Standalone Chair Asset and Placement

Status: **INSTALLED AND VERIFIED — 2026-10-01.**

The wooden chair is now an independent buildable furniture item, with its own
model, packed item, Build-menu entry and placement definition. It is never
bundled with a table or spawned automatically when building one. Sitting
animations, seat assignments and dining/comfort effects remain future work.

## Model

`assets/models/furniture/wooden_chair.glb` uses a **1×1 footprint**, a **2-block
backrest** and a **1-block seat rim**, at **eight voxels/block**. Its thick
seat has a one-voxel-deep worn hollow. Four stout posts, low stretchers, solid
arm rails, a recessed oak back panel and a clipped cap give it a clear chair
silhouette. Dark iron shoes and restrained back/arm fittings use the same
palette as the tavern table and benches. Front is +Z; back is -Z.

The 8×16×8-cell model contains **402 occupied voxels**, one connected component
and **1,472 triangles**. Local bounds are X/Z [-0.5, 0.5], Y [0, 2], matching
the full-footprint collision region. Scale 0.125 is baked into positions;
import and runtime scale remain 1. Authored colors are converted locally to
linear `COLOR_0` for the existing lit, double-sided furniture material.

`tools/generate_chair.py` owns the geometry and isolated review export.
`tools/generate_furniture_glbs.py` delegates the new chair to that builder.
The canonical output now contains ten placed models and one shared packed crate.

## Integration

- `base:furniture:wooden_chair` uses floor placement, four yaw steps,
  a 1×1 footprint and `collision_regions: [{min:[0,0,0], max:[1,2,1]}]`.
- `base:resources:furniture:wooden_chair` uses the shared packed crate,
  heavy weight class and stack limit 5. Trade value 8 is provisional data.
- **Build → Wooden Chair** places one chair. **Storage Zone → DEV: Spawn
  Furniture** includes one packed chair in each batch. Restart a running
  game to load the new definition and menu entry.
- Existing placement, occupancy, fetch/build, uninstall and persistence
  implementations are reused. No new autoload or global script class is added.

The table, bench and every other existing model/definition remain unchanged.
The storage shelf is still reserved for Alen's hand-authored model.

## Review and verification

The isolated Godot review is `tmp/chair_preview/project.godot`. Seven native
Godot 4.7.2 Forward+ / D3D12 captures cover the standalone chair at four angles,
standing dwarf scale, comparison with the table/bench, and an example dining
arrangement. The primary preview shows only the chair. Context images explicitly
label the table, benches and additional chairs as separate build items.

`tools/VerifyChair.gd` checks the actual furniture controller, item manager
and dwarf pickup/build methods on an in-memory floor fixture:

- Registration in the Build menu and DEV-spawner mix.
- Nonblocking ghosts, overlap prevention, four rotations, native model scale,
  material flags, full 1×2×1 bounds and two-layer occupancy.
- Releasing/reclaiming fetch reservations, carrying and consuming the packed
  chair on installation, correct uninstall refund, and save restoration.
- A chair and adjacent table saved/restored into a cleared fixture, followed
  by independent removal: the other piece remains installed and only the
  removed piece's packed item is refunded.
- Unchanged terrain, walkable neighbors, and no heat or door-sealing effects.

The existing dining-table fixture also passes, including its fractional-height
occupancy check and all eight earlier pieces at four rotations. Its registration
count assertion now permits later furniture additions while still requiring the
table and checking every Build-menu mapping.

These are direct integration checks, not a complete autonomous scheduler or
main-world UI playthrough. No player saves are used. The minimal fixture emits
the existing missing-sky and unseeded-weather warnings because it omits the world
environment; final review/import/runtime logs contain no errors. An initial
chair fixture tried restoring over existing instances; clearing its instances
first corrected the fixture to match the real SaveManager load contract.

All eleven canonical exports match shipping GLBs. The final audit confirms
all 148 earlier model files, all nine previous furniture definitions and all
previous item definitions remain unchanged. The snapshot, geometry report,
runtime results and audit are `pre_import.json`, `validation.json`,
`runtime_checks.json` and `integration.json` under `tmp/chair_preview/`.

## Reproduction

```powershell
python -B tools/generate_chair.py --install
$chairEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $chairEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\chair_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $chairEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\chair_preview', '--resolution', '1600x1000', '--', '--capture') -WindowStyle Hidden -Wait
Start-Process -FilePath $chairEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $chairEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tools/VerifyChair.gd') -WindowStyle Hidden -Wait
Start-Process -FilePath $chairEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tools/VerifyDiningTable.gd') -WindowStyle Hidden -Wait
```

Omit `--install` for review-only export, or `-- --capture` for interactive review.
