# 47 — Brazier asset and heating

Status: **INSTALLED AND VERIFIED — 2026-10-03.**

The independently buildable brazier adds a compact floor light and stronger
room heating. A beveled stone foot and squat pedestal carry a faceted iron fire
bowl with a riveted rim and four corner prongs. Glowing coals and eight sculpted
flame frames sit inside the bowl; the pedestal and hardware remain static.

## Asset and placement

- Models: `assets/models/furniture/brazier.glb` and
  `assets/models/furniture/animations/brazier_flame.glb`.
- Eight voxels per block; 8×16×8-cell envelope, .125 baked scale.
- Bounds: X/Z [−0.5,0.5], Y [0,2]; runtime/import scale 1, linear `COLOR_0`.
- Default pose: 324 occupied voxels, 1,128 triangles, one connected component.
- Clip library: eight distinct frames, 2,080 triangles across the library;
  only one flame mesh is drawn per installed brazier.
- Footprint 1×1, four rotations, collision `[0,0,0]` to `[1,2,1]`.
- The existing floor tool still requires three clear air cells for dwarf access.

**Build → Brazier** uses `base:furniture:brazier`. The packed item uses the shared
crate, heavy weight, stack limit 5, provisional trade value 20 and furniture
stockpile tag. **Storage Zone → DEV: Spawn Furniture** includes one. Normal dwarf
fetch/build consumes the crate; uninstall refunds the same item. Existing save
reconstruction handles both pending ghosts and installed braziers.

## Light, animation and heat

Named meshes separate `brazier_body` from `brazier_flame`. The shared
`FurnitureLighting.gd` / `FurnitureFlameAnimation.gd` components attach warm,
shadowed light only after installation. Its point source sits in the upper flame,
above the prongs to keep their shadows local. An opt-in light size of .35 softens
the bowl's shadow; previous furniture keeps the default point source. Emissive fire is unshaded and does
not cast shadows; the stone and metal retain ordinary lighting and shadows.

Frame durations total one second, with per-instance phase and speed offsets.
Light varies within ±8% of energy 2.2; emission within ±7% of .85. The clip meshes
are shared, while timing and materials are per instance. Hidden slices suspend
updates; uninstall hides the model and stops its animation immediately.

The installed definition supplies **600 heat units** to `RoomManager`. This is
steady simulation heat, independent of cosmetic flicker. A sealed 100-block room
gains 6°C from one brazier or 12°C from two. Ghosts/packed items have no light or
heat. Uninstall removes the contribution; reconstruction in a fresh scene restores
it once. The brazier is always lit in v1; fuel, ignition and burn-out remain future
work. The old planned `base:item:brazier` reference is replaced by the furniture
and packed-item keys above. No previous shipped item used that planned key.

## Verification and reproduction

`tools/generate_brazier.py` owns the art, clip and isolated native Godot review.
The canonical furniture generator delegates both GLB exports to it. Native views
cover close-up, RTS, rear, dwarf scale and a dark stone hall; an eight-second
movie demonstrates the flame and light animation.

`tools/VerifyBrazier.gd` exercises real placement, occupancy, the item manager,
dwarf fetch/build, reservation release/reclaim, uninstall and ghost/installed
save reconstruction. All four orientations, missing-floor rejection, three-block
clearance and neighboring navigation are checked. Eight visible animation frames,
bounded flicker, shared meshes, independent timing and slice suspension pass.
An actual sealed-room flood fill verifies single/double heat, restoration without
duplication, no ghost heat and removal back to baseline temperature. The real
Build button dispatches at 1280×800 and 2560×1440; 18 buttons fit three rows.
The fixture does not touch player saves. Its minimal scene emits existing
missing-sky-environment and unset-weather-seed warnings.

`tools/audit_brazier.py` compares the pre-import snapshot: all 158 previous GLBs,
16 existing furniture definitions and previous item entries remain unchanged.
All 22 canonical model/library exports reproduce shipping bytes. Native captures,
movie, validation reports and the scoped diff are in `tmp/brazier_preview/`.

```powershell
python -B tools/generate_brazier.py --install
$brazierEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process $brazierEngine -ArgumentList @('--headless','--editor','--path','P:\Deepdraft\tmp\brazier_preview','--import') -WindowStyle Hidden -Wait
Start-Process $brazierEngine -ArgumentList @('--path','P:\Deepdraft\tmp\brazier_preview','--resolution','1600x1000','--','--capture') -WindowStyle Hidden -Wait
Start-Process $brazierEngine -ArgumentList @('--headless','--editor','--path','P:\Deepdraft','--import') -WindowStyle Hidden -Wait
Start-Process $brazierEngine -ArgumentList @('--headless','--path','P:\Deepdraft','--script','res://tools/VerifyBrazier.gd') -WindowStyle Hidden -Wait
python -B tools/audit_brazier.py
```

Omit `--install` for review-only exports. Omit `-- --capture` for interactive
review controls. Restart play mode to load the model, definition and menu entry.
No new global script class or autoload was needed. The shared light helper adds
only the optional source-size field, defaulting to zero for existing definitions.
