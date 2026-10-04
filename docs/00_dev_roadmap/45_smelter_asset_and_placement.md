# 45 — Smelter asset, placement and animated fire

Status: **INSTALLED AND VERIFIED — 2026-10-03.**

The smelter pairs with the new anvil: thick dressed-stone walls, an arched
firebox, bolted iron belt, faceted iron hood and a soot-darkened hollow chimney.
A low projecting grate frames bright coals and moving flames. The approved
2×2 footprint and three-block height replace the earlier 2×1×2 sketch.

## Asset contract

| Property | Installed asset |
|---|---|
| Model | `assets/models/furniture/smelter.glb` |
| Clip | `assets/models/furniture/animations/smelter_flame.glb` |
| Resolution | 8 voxels per block; 16×24×16-cell envelope |
| World bounds | X/Z [−1,1], Y [0,3] |
| Static geometry | 2,740 occupied cells, 4,588 triangles, one connected component |
| Named meshes | `smelter_body`, `smelter_flame` |
| Animation | Eight frames, 3,312 triangles across the library, 1-second cycle |
| Export | .125 baked into positions; linear `COLOR_0`; import/runtime scale 1 |
| Collision | `[0,0,0]` to `[2,3,2]`; four floor cells, three vertical cells |

The working face points +Z. The grate stays within the reserved footprint,
and the firebox and flue are hollow geometry. Masonry colors match the hearth;
iron colors match the anvil. The furnace body, grate and chimney remain static.
Native Godot captures check the asset at RTS zoom and beside the shipping dwarf,
anvil and storage furniture.

## Fire and light

The existing `FurnitureLighting` / `FurnitureFlameAnimation` helpers attach only
to installed models. A shared eight-frame library reshapes the fire tips while
preserving the ember bed, and gives each smelter independent position-derived
timing. Only one fire mesh is rendered per instance. Frames remain inside the
recessed chamber and never intersect the body or grate.

The flame material is unshaded and emissive; the stone and iron use the normal
lit material. A warm shadowed point light sits at `[0,1.125,0.5]`, with energy
1.9, range 6.5 and at most 9% light variation. The raised light position reduces
the long shadows from the grate. The furnace shell blocks rearward light and
the opening directs a warm pool onto the working area. Flame meshes do not
cast shadows. Hidden slices suspend animation; removal immediately hides the
light. Ghosts and packed items remain static and unlit.

## Placement and gameplay scope

**Build → Smelter** uses `base:furniture:smelter` in the existing furniture
pipeline. Its heavy packed item uses the shared crate, stack limit 5 and a
provisional trade value of 32. **Storage Zone → DEV: Spawn Furniture** includes
one packed smelter. Dwarves fetch/install the crate; uninstall refunds it.
Four quarter-turn orientations and installed/ghost save reconstruction work
through the existing owners, with no new save fields, global classes or autoloads.

All four floor cells require three clear air cells above them. A ceiling at
floor Y+3 rejects placement; a ceiling at Y+4 permits the three-block model.

This pass adds the visual, placement and cosmetic firelight. Ore conversion,
fuel, recipe queues, smith jobs and the planned **800 heat units while operating**
remain future workshop integration under `docs/40_economy_colony/44_crafting_workshops.md`.
The current piece contributes no simulated heat and creates no production tasks.

## Verification and reproduction

`tools/VerifySmelter.gd` uses the actual furniture controller, dwarf fetch/build
executor, item manager, occupancy registry and save owner. It checks all four
rotations, sixteen missing-floor rejections, ceiling clearance, ghost and
installed save restoration, release/reclaim, crate consumption, uninstall
refunds and absence of heat/door side effects. It observes all eight flame
frames and bounded light/emission changes, static hardware, shared meshes with
independent phases, and visibility suspension. The real menu button is tested
at 1280×800 and 2560×1440; all sixteen buttons fit in three rows. Fixtures do
not load or write player saves.

`tools/audit_smelter.py` checks all 155 prior GLBs, fourteen prior furniture
definitions and previous item definitions are unchanged. It validates the
connected model, contained flame frames and open flue, then reproduces all
nineteen canonical furniture/library exports in isolation and compares their
bytes with shipping assets. Reports, the baseline snapshot, scoped diff and
native renders are under `tmp/smelter_preview/`.

```powershell
python -B tools/generate_smelter.py --install
$smelterEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process $smelterEngine -ArgumentList @('--headless','--editor','--path','P:\Deepdraft\tmp\smelter_preview','--import') -WindowStyle Hidden -Wait
Start-Process $smelterEngine -ArgumentList @('--path','P:\Deepdraft\tmp\smelter_preview','--resolution','1600x1000','--','--capture') -WindowStyle Hidden -Wait
Start-Process $smelterEngine -ArgumentList @('--headless','--editor','--path','P:\Deepdraft','--import') -WindowStyle Hidden -Wait
Start-Process $smelterEngine -ArgumentList @('--headless','--path','P:\Deepdraft','--script','res://tools/VerifySmelter.gd') -WindowStyle Hidden -Wait
python -B tools/audit_smelter.py
```

Omit `--install` for review-only export. The isolated preview supports model,
camera, dwarf-scale and workshop controls. `--write-movie <path>.avi --fixed-fps 30
-- --movie` captures eight seconds of close-up and dark-workshop animation.
The delivered preview is `tmp/smelter_preview/renders/smelter_animation.mp4`.
Restart play mode to load the new model, definition and menu entry.
