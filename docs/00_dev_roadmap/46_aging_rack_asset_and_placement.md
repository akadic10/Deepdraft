# 46 — Aging rack asset and placement

Status: **INSTALLED AND VERIFIED — 2026-10-03.**

The aging rack extends the brewing furniture set with two horizontal oak casks
in a stout timber cradle. Iron hoops wrap their tapered staves, raised chimes
frame recessed plank heads, and small draw-off taps face forward. Long runners,
diagonal braces and wooden wedges support the casks; a dark batch plaque with
two chalk marks identifies the cellar role at colony zoom.

## Asset and placement

- Model: `assets/models/furniture/aging_rack.glb`.
- Eight voxels per block; 16×16×16-cell envelope.
- World bounds: X/Z [−1,1], Y [0,2].
- 1,230 occupied voxels, 3,604 triangles, one connected component.
- Scale .125 baked into positions; runtime/import scale 1, linear `COLOR_0`.
- Footprint 2×2, four quarter-turn rotations; collision `[0,0,0]` to `[2,2,2]`.

**Build → Aging Rack** places `base:furniture:aging_rack`. Its heavy packed
item uses the shared furniture crate, stack limit 5, provisional trade value
28 and the furniture stockpile tag. **Storage Zone → DEV: Spawn Furniture**
includes one crate. A dwarf fetches it to build the rack; uninstall returns the
same item. Pending ghosts and installed racks use existing save reconstruction.

This pass provides art and placement. Casks, taps and batch marks are static;
the rack does not store items, produce drinks, change temperature or act as a
room anchor. Aging recipes, autonomous batch progress, temperature gating and
collection tasks remain future integration with `base:workshop:aging_cellar`.
The existing workshop recipe data is unchanged. No frost is painted onto the
world asset; the future inspect icon can communicate temperature separately.

## Verification and reproduction

`tools/generate_aging_rack.py` owns the art and isolated Godot review. The
canonical furniture generator calls the same builder and color exporter.
Native views cover three-quarter, RTS, rear, full-size dwarf comparison and
the rack alongside the brewing vat and ordinary storage barrel.

`tools/VerifyAgingRack.gd` checks the real furniture controller, item manager,
dwarf fetch/build executor and occupancy registry: all four rotations, all four
floor cells, nonblocking ghosts, overlapping placement rejection, reservation
release/reclaim, crate consumption, uninstall refunds, and ghost/installed
save reconstruction. Neighboring navigation and terrain stay unchanged.
The real Build button dispatches correctly at 1280×800 and 2560×1440; all 17
buttons including Cancel fit in three rows. The fixture does not touch player
saves. Its minimal scene emits the existing missing-sky-environment and unset
weather-seed warnings; neither affects furniture checks.

`tools/audit_aging_rack.py` verifies all 157 prior GLBs and 15 prior furniture
definitions against the pre-import snapshot, preserves existing item entries,
and compares all 20 canonical model/library exports against shipping bytes.
Captures, validation reports and the scoped source diff are in
`tmp/aging_rack_preview/`.

```powershell
python -B tools/generate_aging_rack.py --install
$agingEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process $agingEngine -ArgumentList @('--headless','--editor','--path','P:\Deepdraft\tmp\aging_rack_preview','--import') -WindowStyle Hidden -Wait
Start-Process $agingEngine -ArgumentList @('--path','P:\Deepdraft\tmp\aging_rack_preview','--resolution','1600x1000','--','--capture') -WindowStyle Hidden -Wait
Start-Process $agingEngine -ArgumentList @('--headless','--editor','--path','P:\Deepdraft','--import') -WindowStyle Hidden -Wait
Start-Process $agingEngine -ArgumentList @('--headless','--path','P:\Deepdraft','--script','res://tools/VerifyAgingRack.gd') -WindowStyle Hidden -Wait
python -B tools/audit_aging_rack.py
```

Omit `--install` for review-only exports. Omit `-- --capture` for interactive
review controls. Restart play mode to load the model, definition and menu entry.
No new global script class or autoload was added.
