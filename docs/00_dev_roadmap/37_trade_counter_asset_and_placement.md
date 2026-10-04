# 37 — Trade Counter Asset and Placement

Status: **INSTALLED AND VERIFIED — 2026-10-01.**

The trade counter had a furniture definition and an art specification, but no
shipping model or placement registration. This milestone supplies its stone/iron
model and connects it to the existing packed-furniture installation pipeline.
Shop designation, merchant visits, buying/selling and reputation remain future
work; their existing data fields are preserved.

## Model

`assets/models/furniture/trade_counter.glb` has a **2×1 footprint and 2-block
height**, at the established eight voxels per block. Two stout stone piers on
stepped plinths support a thick dressed-stone slab. A pale beveled top, dark
iron belt, quiet rivets and recessed angular front carving give it a distinct
industrial identity beside the wooden tavern bar. The shopkeeper side has a
shallow work recess. Customer front is +Z; shopkeeper rear is -Z.

The 16×16×8-cell envelope contains 1,378 occupied voxels in one connected
component and exports 2,224 triangles. Local bounds are X [-1, 1], Y [0, 2],
Z [-0.5, 0.5], fitting the existing full-footprint collision box. Scale 0.125
is baked into vertex positions; import and runtime scale remain 1. Stone
colors come from the hearth and iron from the tavern set, converted locally
to linear `COLOR_0` for the existing lit, double-sided furniture material.

`tools/generate_trade_counter.py` owns the geometry and isolated preview.
`tools/generate_furniture_glbs.py` delegates the new placed form to it, so
the canonical export now produces eight placed models and one shared item.

## Placement and item data

- `trade_counter.json` now includes its packed `item_key`, floor placement
  and four yaw steps. Its footprint, collision and future shop fields remain.
- `base:resources:furniture:trade_counter` uses the shared packed crate, a
  heavy weight class and stack limit 5. Trade value 20 is provisional data
  for the future trading system.
- **Build → Trade Counter** starts placement. The **Storage Zone → DEV:
  Spawn Furniture** mix includes one packed counter for the existing test flow.
- Ghosts, claims, dwarf fetch/build, occupancy, uninstall refunds and save
  restoration use the existing implementations. No new autoload or global
  script class was added, and no terrain/navigation rules were changed.

Restart a running game to load the new definitions and menu entry. The shelf
remains reserved for Alen's hand-authored replacement.

## Verification

The isolated review project is `tmp/trade_counter_preview/project.godot`.
Seven native Godot 4.7.2 Forward+ / D3D12 captures cover the front, rear,
RTS view, dwarf scale, tavern comparison and storage context. Review and
live-project imports completed without errors.

`LiveTradeCounterCheck.gd` exercises the actual furniture controller, item
manager and dwarf pickup/build methods on an in-memory floor fixture. All
four rotations pass model-bound/collision alignment and two-cell occupancy
checks. Ghosts remain nonblocking; fetch reservations can be released and
reclaimed; dwarf pickup consumes the packed item and completion installs
the counter; uninstall refunds the same item and clears occupancy. An
installed serialize/restore round trip preserves placement. The fixture
also checks the actual Build mapping and DEV-spawner registration and that
the counter introduces no heat or door-sealing entries.

These are direct runtime integration checks, not a full autonomous scheduler
or main-world UI playthrough. No player saves were read or written. The minimal
fixture emits the existing missing-sky and unseeded-weather warnings because
it omits the main world environment; the final run has no errors.

The audit confirms all nine canonical exports match their shipping GLBs and
all 105 pre-existing model files retain their prior hashes. Existing item
definitions are unchanged. Furniture changes are limited to the new trade
placement metadata, its description/comments and the tavern-bar status comment.
`pre_import.json`, `validation.json`, `runtime_checks.json` and `integration.json`
record the snapshot and results in the review directory.

## Reproduction

```powershell
python -B tools/generate_trade_counter.py --install
$tradeEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $tradeEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\trade_counter_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $tradeEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\trade_counter_preview', '--resolution', '1600x1000', '--', '--capture') -WindowStyle Hidden -Wait
Start-Process -FilePath $tradeEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $tradeEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tmp/trade_counter_preview/LiveTradeCounterCheck.gd') -WindowStyle Hidden -Wait
```

Omit `--install` for review-only export, or `-- --capture` for interactive
review controls.
