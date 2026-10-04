# 43 — Wall Torch Asset, Placement and Lighting

Status: **INSTALLED AND VERIFIED — 2026-10-02.**

The Wall Torch adds the colony's first independently buildable wall light.
It has a stepped iron backplate and cradle, charred oak handle, basket prongs
and a layered amber flame. It remains at eight voxels/block and 1.5 blocks tall.

## Model and light

`assets/models/furniture/wall_torch.glb` contains two named meshes, `torch_body`
and `torch_flame`. Combined: 122 voxels, 604 triangles, one connected component.
Bounds: X [-0.375,0.25], Y [0,1.5], Z [0,0.75]. Scale 0.125 is baked into
positions, and authored colors export as linear `COLOR_0`. Import/runtime scale
remains 1. The wall touches local Z=0; the handle/flame project toward +Z.

`FurnitureLighting.gd` adds an installed-only warm `OmniLight3D` and an emissive
material only to the named flame. Energy 1.6, range 7 blocks, attenuation 1.2,
color #FFC078 and local position [0,1.1875,0.8125] live in the furniture JSON.
The light casts shadows from terrain and other objects. Its own tiny body/flame
meshes do not cast shadows: a single point emitter otherwise creates an oversized
black fan from its bracket. Packed items and ghosts emit neither light nor heat.

The live terrain renderer previously disabled shadow casting. `TerrainLighting.gd`
now configures all four terrain mesh paths on reserved render layer 20 with shadows
enabled. `SkyController` excludes that layer only from the sun's shadow-caster mask,
preserving the prior daylight appearance and avoiding a new map-wide sun-shadow pass.
Local lights include it, so actual rock walls block torchlight. Normal camera and
light cull masks include this layer. No rendering settings in `project.godot` change.

The torch is always lit when installed. Fuel, ignition/extinguishing and burn-out
are not implemented. Heat is the existing room simulation,
not radiative outdoor or dwarf-comfort behavior.

### Flame animation — 2026-10-02 follow-up

Alen requested fire animation after the initial static version. Installed torches
now cycle eight sculpted voxel silhouettes: tongues rise, split and collapse while
the hot core drifts through the amber body. The iron/wood mesh stays still. The
animation uses the same eight-voxel grid and remains inside the original bounds,
so mounting height, wall clearance and selection do not change.

`assets/models/furniture/animations/wall_torch_flame.glb` holds the eight named
meshes (1,152 triangles across the whole library). `FurnitureFlameAnimation.gd`
loads and caches those meshes once, then swaps the existing flame mesh; it does
not instantiate eight overlapping meshes per torch. Frame durations total 0.8s,
with position-derived phase offsets and up to ±12% speed variation. A mixture of
unequal sine frequencies gently modulates local-light energy by at most ±10% and
flame emission by at most ±8%, updated at 30Hz. Settings live under
`light_source.flame_animation` in the furniture definition.

Animation is cosmetic real time, independent of calendar speed and room heat.
Hidden slices suspend its process loop and reveal resumes it. Ghosts/packed items
remain static and unlit. Save/restore reconstructs animation from the model and
definition, without additional saved fields. Each torch owns its emissive material
and timing but shares the clip meshes; no global script class/autoload is added.

The integration fixture observes all eight frames and over 100 distinct bounded
light/emission samples, checks static hardware, original bounds, independent
neighbor phases, shared mesh resources, hidden/revealed behavior and unchanged
heat/save state. Existing placement, support mining, fetch/build, uninstall and
save/restore checks pass. `renders/torch_animation.mp4` is an eight-second native
Godot recording showing the close-up and furnished-room views. All 152 pre-animation
GLBs, including the approved static torch, remain byte-identical.

## Placement and lifecycle

- **Build → Wall Torch**. Aim at a vertical terrain face for automatic orientation,
  or at the neighboring floor and press R. Four quarter-turns match the rendered
  model. The legacy `floor_wall` rotation helper now uses the same Godot Y rotation.
- `placement: wall` uses a separate wall-face index. Saved origin remains a FLOOR
  cell used for work targets and room membership. Floor footprint is 0×0 and
  collision regions are empty; no navigation or stockpile floor reservation.
- The model base is 2.5 blocks above the floor surface, with the flame at head
  height and above. Its top reaches 4 blocks. **Four-block room height is required.**
  The two terrain cells behind the bracket must be solid and its visual volume air.
- Low furniture and zones may occupy the floor below. Model bounds prevent overlap
  with tall pieces in either placement order, including walkable doors that have
  no navigation collision. A dwarf needs a walkable work cell beneath or beside it.
- Selection tests the mounted model before the terrain behind it, respecting
  intervening rock and slice visibility. A slice below the flame hides the torch and
  light, preventing the emitter from shining over clipped-away wall geometry.
  The placement hint now uses a CanvasLayer, removing the old 3D UI label.
- Terrain changes recheck live wall mounts. Removing a support or its floor anchor
  cancels a ghost or uninstalls the piece and refunds one packed torch. A final
  support check before the dwarf consumes the item closes the same-frame mining
  race; failed completion releases the intact carried crate at the worker's feet.
- Ordinary fetch/build, uninstall toggle, packed-item refund, ghost persistence
  and installed persistence all work. A restored torch reconstructs its light.
  No new global script class, autoload, save schema or main scene change.

`base:resources:furniture:wall_torch` uses the same packed crate as the other
twelve furniture types (thirteen total including this torch), heavy carry and
stack limit 5. Trade value 4 is provisional. **Storage Zone → DEV: Spawn Furniture**
now includes four packed torches per batch. Restart a running game to load the
new menu entry and definition.

## Heat

Each installed torch supplies **200 heat units** through `RoomManager`. Wall
pieces pass their floor work anchor for room membership, independently of their
empty floor footprint. Contributions now add/subtract at a shared anchor so a
torch and hearth can coexist without replacing or erasing each other's heat.

The actual room flood fill and temperature formula were exercised in a sealed
5×5×4 room: two torches plus one hearth produce **800 heat units / 100 blocks =
+8°C**. Removing one torch leaves **600 units / +6°C**, including the hearth's
400-unit contribution at the removed torch's floor anchor.

## Verification

`tools/VerifyWallTorch.gd` exercises all four directions, real camera wall hits,
model selection/occlusion, transparent unlit ghosts, nonblocking floor behavior,
native mesh bounds, emission/light properties, fetch reservation release/reclaim,
real dwarf pickup/build, uninstall/refund, support removal, the completion race,
ghost and installed serialization/restoration, and a restored uninstall flag.

It also checks low-furniture coexistence, tall-piece overlap prevention, room
heat and actual Build-button dispatch. All 14 buttons (13 pieces + Cancel) fit
in the existing 869×224 three-row panel at 1280×800 and 2560×1440. Bed, vat and
shelf regression fixtures pass. Tests use in-memory worlds and do not access
player saves or UI-layout preferences. They are direct integration checks, not
a full autonomous scheduler/main-world playthrough. Minimal fixtures produce
the known missing-sky and unseeded-weather warnings, with no final errors.

The fixture exercises all four live terrain mesh factories. A separate GPU check,
`tools/VerifyTorchShadows.gd`, uses the same terrain-shadow helper on the AMD RX9070XT:
the floor behind a wall receives **0.0 luminance** with terrain shadows enabled,
versus **0.574** with them disabled or excluded from the local light's caster mask.
It also confirms that the sun's illumination mask remains unchanged.

Six native Godot 4.7.2 Forward+ / D3D12 captures show three torch angles, native
dwarf scale, and the same furnished room with its torch lights on/off. Review
project and reports: `tmp/wall_torch_preview/`. The previous 151 GLBs, twelve
furniture definitions and all prior item definitions are preserved.

`tools/generate_wall_torch.py` owns the art. The canonical
`tools/generate_furniture_glbs.py` delegates its named-mesh export; the complete
set now has thirteen placed models, one shared packed crate and one flame-animation
library. `tools/audit_wall_torch.py` verifies all fifteen canonical exports.

## Reproduction

```powershell
python -B tools/generate_wall_torch.py --install
$torchEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $torchEngine -ArgumentList '--headless --editor --path P:\Deepdraft\tmp\wall_torch_preview --import --quit' -WindowStyle Hidden -Wait
Start-Process -FilePath $torchEngine -ArgumentList '--path P:\Deepdraft\tmp\wall_torch_preview -- --capture' -WindowStyle Hidden -Wait
Start-Process -FilePath $torchEngine -ArgumentList '--headless --editor --path P:\Deepdraft --import --quit' -WindowStyle Hidden -Wait
Start-Process -FilePath $torchEngine -ArgumentList '--headless --path P:\Deepdraft --script res://tools/VerifyWallTorch.gd' -WindowStyle Hidden -Wait
```

Omit `--install` to export only to the isolated review directory; omit
`-- --capture` for its interactive art review.
