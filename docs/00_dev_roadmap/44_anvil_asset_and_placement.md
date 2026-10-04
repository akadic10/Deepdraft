# 44 — Anvil asset and placement

Status: **INSTALLED AND VERIFIED — 2026-10-02.**

The independently buildable anvil establishes the metalworking furniture style:
a heavy iron head with a tapered horn, worn steel face and square hardy hole,
above a narrow waist and flared feet. Bolted iron hold-downs secure it to a
dressed-stone pedestal. The proposed 2×1 footprint and 1.5-block working height
were accepted by Alen; this supersedes the original 1×1 bare-anvil spec.

## Asset and placement

- Shipping model: `assets/models/furniture/anvil.glb`.
- Authoring grid: 8 voxels per block; 16×12×8-cell envelope.
- World bounds: X [−1,1], Y [0,1.5], Z [−0.5,0.5].
- 638 occupied voxels, 1,376 triangles, one connected component.
- Scale .125 baked into positions; runtime/import scale 1, linear `COLOR_0`.
- Footprint 2×1, four quarter-turn rotations, collision `[0,0,0]` to `[2,1.5,1]`.
- Grid occupancy conservatively covers the two vertical cells touched by the mesh.

The model uses the existing lit, double-sided furniture material. Broad cool
iron colors separate the working face, body and shadowed underside; the stone
uses the hearth palette. The head remains free of tools or loose workpieces,
and the horn projects within the reserved footprint. Native Godot renders check
the silhouette at close range, colony zoom, from behind and beside a full-size
3.375-block dwarf.

`data/furniture/anvil.json` adds **Build → Anvil**. Its heavy packed item uses
the common furniture crate, stack limit 5, provisional trade value 24 and
the furniture stockpile tag. **Storage Zone → DEV: Spawn Furniture** includes
one packed anvil. Dwarves fetch the crate to build it; uninstall returns the
same item. Existing save reconstruction handles both pending ghosts and built
anvils without a new save field.

This is a placeable anvil. It has no heat output or storage. Metalworking
recipes, smith animations, crafting queues and forge integration remain future
work under `docs/40_economy_colony/44_crafting_workshops.md`.

## Verification and reproduction

`tools/generate_anvil.py` generates the art and isolated review. The canonical
`tools/generate_furniture_glbs.py` delegates to the same builder and color export.
`tools/VerifyAnvil.gd` exercises the actual furniture controller, item manager,
dwarf fetch/build executor, occupancy registry and save reconstruction. Checks
cover four rotations, both required floor cells, nonblocking ghosts, release
and reclaim, crate consumption, uninstall refunds, and no heat/door side effects.
The real Anvil menu button is dispatched at 1280×800 and 2560×1440; all 15 buttons
fit in three rows. Fixtures do not read or write player saves.

`tools/audit_anvil.py` compares the pre-import snapshot, verifies that all 154
existing models and 13 existing furniture definitions are unchanged, and checks
all 17 canonical furniture/model-library exports against the shipping bytes.
Native captures, validation reports and the scoped diff are in `tmp/anvil_preview/`.

```powershell
python -B tools/generate_anvil.py --install
$anvilEngine = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process $anvilEngine -ArgumentList @('--headless','--editor','--path','P:\Deepdraft\tmp\anvil_preview','--import') -WindowStyle Hidden -Wait
Start-Process $anvilEngine -ArgumentList @('--path','P:\Deepdraft\tmp\anvil_preview','--resolution','1600x1000','--','--capture') -WindowStyle Hidden -Wait
Start-Process $anvilEngine -ArgumentList @('--headless','--editor','--path','P:\Deepdraft','--import') -WindowStyle Hidden -Wait
Start-Process $anvilEngine -ArgumentList @('--headless','--path','P:\Deepdraft','--script','res://tools/VerifyAnvil.gd') -WindowStyle Hidden -Wait
python -B tools/audit_anvil.py
```

Omit `--install` for review-only exports. Omit `-- --capture` for interactive
camera/context controls. Restart play mode after installation to load the model,
definition and menu entry. No global script class or autoload was added.
