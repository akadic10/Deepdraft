# 30 — Hearth visual redesign

**Status (2026-10-02): installed at 2×2 with animated fire.** The shipping GLB,
furniture definition and canonical generator use separate body/flame meshes
and a ten-frame fire library. Current review project:
`tmp/hearth_animation_preview/project.godot`. The original size review remains
under `tmp/hearth_redesign_preview/`.

## Design

The original shipping hearth was a thin 1×1 stone ring, only 0.25 blocks tall.
The first redesign added a dressed-stone bowl and rising flame within a 1×1
footprint. Its appearance was approved, but it still looked small beside the
3.375-block-tall dwarves. The final version is rebuilt on a 16×16-cell base at
the same eight voxels per block, rather than enlarging individual voxels.

A cut-corner plinth supports staggered stone courses and broad capstones.
Four iron shoulder clamps frame recessed grate rails, charred logs and an
ember bed. The main curved flame has two lower shoulders. Broad stone colors
and restrained joints keep the masonry readable at gameplay scale.

The stone rim reaches 1 block; the highest flame reaches 2 blocks. This is a
freestanding communal fire bowl, with enough presence to anchor a tavern.

## Export and gameplay contract

| Property | Installed model |
|---|---|
| Authoring grid | 8 voxels per block |
| Base grid | 16×16 voxels |
| Export scale | 0.125, baked into positions; import/root scale 1 |
| World bounds | X/Z −1 to +1; Y 0 to 2 |
| Occupied voxels | 1,431 |
| Triangles | 2,888 in static body/flame model; 6,816 across ten library frames |
| Connected occupied-cell components | 1 |
| Placement footprint | 2×2 floor cells |
| Collision region | min [0,0,0], max [2,2,2] |
| Heat output | 400 units per hearth |
| Live filename | `assets/models/furniture/hearth.glb` |

Authored sRGB palette colors convert to linear `COLOR_0`, matching the existing
furniture material's default `vertex_color_is_srgb = false`. This conversion
is local to the hearth; other furniture exports retain their existing colors.
The body retains its lit, double-sided material and masonry shadows. The
named `hearth_flame` mesh uses an unshaded emissive material so fire stays
bright from every direction in a dark room. A warm point light sits above the
rim, with range 8, energy 2 and at most 8% brightness variation. The hearth
opts into body shadows; the wall torch retains its existing lighting settings.

Ten connected voxel frames curl and vary the height of the three flame tongues
above the rim, with a fixed broad base and untouched masonry, grate and logs.
Their 1.38-second cycle is slower than the wall torch's 0.8-second cycle.
`FurnitureFlameAnimation` shares mesh resources and gives each hearth a
position-derived phase and small speed variation. Only one flame frame is drawn
at a time; all frames fit the original 2×2×2 bounds. The effect runs in cosmetic
real time, independent of calendar speed, without changing the 400-unit heat
output. Hidden slices suspend updates. Build ghosts and packed items are unlit;
save restoration rebuilds the light and animation without new save fields.

The model is centered on the full footprint. All four floor cells must be
valid for placement. Built hearths block those cells through the existing
occupancy system; pending build ghosts reserve them without blocking walking.
`RoomManager` registers 400 heat units once at the origin, so the wider
footprint does not multiply the heat output. The furniture key, item key,
shared packed-furniture model and floor-placement behavior are unchanged.

Saved hearth origins and rotations are retained on restoration, and the
current definition supplies the new dimensions. Existing hearths in cramped
layouts may need repositioning: an old 1×1 placement now occupies the origin
and its +X/+Z neighbors. No save-file migration or automatic relocation is
part of this art update.

## Review and verification

`tools/generate_hearth_redesign.py` creates the isolated review and, with
`--install`, copies the model and flame library into the game.
`tools/generate_furniture_glbs.py` delegates the hearth builder and color
conversion to it, preserving the design when the full furniture set is rebuilt.

`tools/HearthRedesignPreview.gd` reuses the tree studio and approved dwarf
assembly. Nine Godot 4.7.2 Forward+ / D3D12 captures cover the 1×1/2×2 scale
comparison, dwarf scale, three model angles, tavern context and original
shipping model comparison. These are native GLB renders under studio lighting.

QA artifacts live under `tmp/hearth_redesign_preview/`:

- `validation.json`: voxel count, bounds, connectivity and export hash.
- `checks.json`: exported arrays, winding, deterministic bytes, canonical
  generator output and preservation of the other furniture assets.
- `runtime_checks.json`: real placement controller, occupancy/navigation,
  all four rotations, missing-floor rejection, translucent ghosts, build
  completion, room heat, removal and installed/ghost save restoration.
- `integration.json`: installed model identity and combined verification.

The runtime check uses an in-memory sealed room with 64 air cells. One hearth
adds 400 heat units and 6.25°C; removing it clears the contribution. It does
not load or write player saves. The harness awaits deferred terrain-to-nav
invalidation before checking floor edits.

The legacy shipping mesh is retained in `reference/hearth.glb`; the approved
small prototype and its original captures are in `reference/prototype_1x1/`.
`pre_import.json` records pre-install hashes and the original definition.

## Animated-fire verification (2026-10-02)

`tools/HearthAnimationPreview.gd` shows the live fire close up, beside a dwarf
and in a dark tavern with the approved furniture. The native Godot movie is
`tmp/hearth_animation_preview/renders/hearth_animation.mp4`.

`tools/VerifyHearthAnimation.gd` checks all ten imported frames, static body,
bounded light/emission flicker, shared clips with independent timing, hidden
slice suspension, four placement rotations, collision/navigation, unlit
ghosts, teardown, and installed/ghost save restoration. A sealed 64-cell room
still receives exactly 400 heat units and 6.25°C. `tools/VerifyWallTorch.gd`
also passes with both light sources present. Fixtures never read/write player saves.

`tools/audit_hearth_animation.py` compares with the pre-animation snapshot,
checks that every original hearth voxel and color is preserved in the split
static model, validates the frame library, and reproduces the full canonical
furniture export in isolation. The other 152 existing GLBs remain unchanged.
Reports and the scoped source diff live under `tmp/hearth_animation_preview/`.

## Reproduction

```powershell
python -B tools/generate_hearth_redesign.py --install
$hearthEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $hearthEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft\tmp\hearth_animation_preview', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $hearthEngine -ArgumentList @('--path', 'P:\Deepdraft\tmp\hearth_animation_preview', '--resolution', '1600x1000', '--', '--capture') -WindowStyle Hidden -Wait
Start-Process -FilePath $hearthEngine -ArgumentList @('--headless', '--editor', '--path', 'P:\Deepdraft', '--import') -WindowStyle Hidden -Wait
Start-Process -FilePath $hearthEngine -ArgumentList @('--headless', '--path', 'P:\Deepdraft', '--script', 'res://tools/VerifyHearthAnimation.gd') -WindowStyle Hidden -Wait
python -B tools/audit_hearth_animation.py
```

Omit `--install` to export only the review. Omit `-- --capture` to use the
interactive model, camera and comparison controls. Restart a running game
after replacing an already loaded GLB.
