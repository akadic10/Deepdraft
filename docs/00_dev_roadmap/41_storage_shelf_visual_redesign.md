# 41 — Storage Shelf Visual Redesign

Status: **INSTALLED AND VERIFIED — 2026-10-01.**

Alen selected the storage shelf ahead of the brewing vat. This requested
replacement supersedes the earlier plan to reserve the shelf for hand-authoring.
The existing shelf now matches the upgraded oak/iron furniture and keeps its
1×1 footprint, two-block height, eight-item capacity and independent placement.

## Asset

`assets/models/furniture/storage_shelf.glb` has four oak uprights, two plank
decks, iron corner shoes/collars and small under-deck brackets. A deep open
top frame replaces the solid cap, exposing upper contents from the gameplay
camera. All four sides remain open; there is no back panel or wall requirement.
Colors use the shared tavern oak/iron palette with restrained wear highlights.

The model uses **eight voxels/block**, an **8×16×8** envelope, **264 occupied
voxels** and **1,456 triangles** in one connected component. Local bounds are
X/Z [-0.5,0.5], Y [0,2], exactly matching the existing collision. Scale 0.125
is baked into positions; import/runtime scale stay 1. Vertex colors are linear
`COLOR_0` for the existing lit, double-sided material.

`tools/generate_shelf_redesign.py` owns the mesh and isolated review export.
The canonical furniture generator delegates to it; the old builder remains
as `build_legacy_storage_shelf`. All twelve canonical exports reproduce the
shipping models, including this replacement.

## Stored-item display

The old fixed 0.5 display scale crowded large ores and rotated crates into
adjacent slots; tall items could extend through the upper deck. The new JSON
layout keeps four anchors per level, at X/Z 0.3125 and 0.6875. Support heights
remain Y 0.125 and 1.0. Each anchor has a clear **0.3125×0.625×0.3125** envelope.

`anchor_scale: 0.5` remains the maximum. The optional `anchor_max_size` field
lets `StorageItemLayout.gd` uniformly shrink rotated item bounds to fit,
center their visible X/Z extents, and align their bottom with the plank.
`ContainerStorageComponent` applies it when depositing or restoring visuals.
Pieces without the field retain their existing sizing. Inventory quantities,
filters, hauling, carried/loose models, withdrawal and refunds are unchanged.
The preview uses the same helper as gameplay.

Stored contents still come from actual inventory. The shelf is empty when
built; the stocked review shows example contents, not bundled props. Existing
saved shelves keep their identities and inventories and use the new model and
layout when loaded. No save-schema change, global script class or autoload
is added. Restart a running game to reload the model and definition.

## Verification

Nine native Godot 4.7.2 Forward+ / D3D12 captures under
`tmp/shelf_redesign_preview/renders/` show the original/new comparison, empty
views, mixed contents, packed crates, dwarf scale and the storage furniture set.
The original GLB is preserved under `reference/` in the isolated review project.

`tools/VerifyShelf.gd` checks the real placement, item and storage components
on an in-memory floor at all four rotations:

- Ghosts, overlap prevention, imported model bounds/material, occupancy and
  navigation; dwarf fetch reservation release/reclaim and build consumption.
- Haul reservation, pickup and deposit of eight items, with a ninth rejected.
- Fitted ores, stone, asymmetric crates and a tall flag: bounds lie inside
  their slots, rest on the decks and do not intersect neighboring items.
- Withdrawal returns a native-scale item, which can be deposited again.
- Stocked furniture serializes/restores its eight contents; uninstalling
  returns every stored item and the shelf's own packed item at native scale.
- Barrel/chest remain absorbing containers; terrain is unchanged.

The dining-table fixture also passes, including all eight earlier furniture
pieces at all rotations. These are direct integration checks, not a complete
autonomous hauling or main-world playthrough. No player saves are used. The
minimal fixtures emit the existing missing-sky/unseeded-weather warnings;
final import, capture and runtime logs contain no errors.

The audit preserves all **149 other GLBs**, all **ten other furniture
definitions** and all item definitions. Every shelf voxel lies within the
existing collision, all eight display envelopes are clear of the frame, and
all twelve canonical exports match shipping bytes. Reports and the original
snapshot live under `tmp/shelf_redesign_preview/`.

## Reproduction

```powershell
python -B tools/generate_shelf_redesign.py --install
$shelfEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $shelfEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\shelf_redesign_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $shelfEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\shelf_redesign_preview', '--resolution', '1600x1000', '--', '--capture') -WindowStyle Hidden -Wait
Start-Process -FilePath $shelfEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $shelfEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tools/VerifyShelf.gd') -WindowStyle Hidden -Wait
```

Omit `--install` for review-only export, or `-- --capture` for interactive review.
