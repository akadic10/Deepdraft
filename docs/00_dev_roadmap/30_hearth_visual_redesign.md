# 30 — Rudimentary hearth

**Installed 2026-10-11.** The early hearth is a rough fire bed banked with
fieldstones. It replaces the dressed stone bowl and iron grate, retaining the
existing furniture, packed-item and recipe keys. Current saves load the current
model and definition. Restart the running game to refresh loaded assets.

## Appearance

Uneven dry-stacked stones form a taller back bank and a low open front. Exposed
unsawn logs rest on a soot/ember bed. Chipped shoulders, varied stone sizes,
muted earth/stone colors and blackened inner faces make it look improvised.
There is no cut plinth, dressed rim, iron clamp or grate. Three simple stepped
flame tongues animate above the logs; the fieldstones and logs stay static.

## Asset and gameplay contract

| Property | Current value |
|---|---|
| Authoring grid | Eight voxels per block; 16×16-cell footprint |
| Export | Baked 0.125 scale, root identity, flat faces, linear COLOR_0 |
| Static model bounds | X/Z −1 to +1; Y 0 to 1.625 |
| Maximum stone height | 0.75 blocks |
| Static geometry | 832 occupied cells, 2,148 triangles, one connected component |
| Animation | Ten distinct connected frames, 3,908 triangles across the library |
| Envelope | Every frame fits the existing 2×2×2 placement/collision envelope |
| Recipe | Two matching logs + four rough stones, 18 seconds at crude workbench |
| Heating | 2,400 units, registered once at the origin |
| Audio | Existing quiet campfire crackle |

`assets/models/furniture/hearth.glb` contains `hearth_body` and `hearth_flame`.
`assets/models/furniture/animations/hearth_flame.glb` supplies the ten frames.
Only the flame is emissive/unshaded; the body uses lit vertex colors and casts
shadows. The existing light sits at Y1.375, range 8 and energy 2, above the low
stone bank. Flicker and per-instance timing use `FurnitureFlameAnimation`.
Ghosts and packed items remain unlit. The shared packed furniture crate is used.
Craft, Place, installed and packed inspection all call it **Rudimentary hearth**.
The catalog thumbnail is rendered from the same shipping model.

## Authoring and verification

`tools/generate_hearth_redesign.py` owns the geometry and ten fire frames.
`tools/generate_furniture_glbs.py` delegates to it, so full exports preserve this
version. Generator validation checks connectivity, bounds, ten distinct frames,
no overlap between body/flame, and identical body cells/colors across frames.
Its isolated review reproduces the production lighting/component directory.

Native Godot Forward+ renders under `tmp/rudimentary_hearth_20261011/renders/`
cover three angles, actual dwarf scale and a firelit room. `validation.json`
records generated counts and hashes. `runtime_checks.json` records the live
placement/animation checks. The original bowl is retained only as an art-review
reference in that temporary review project, not as a gameplay variant.

Verified:

- `tools/VerifyHearthAnimation.gd`: four rotations, 16 missing-floor rejections,
  model scale/material/bounds, ten live animation frames, static body, independent
  timing, slice suspension, ghost/installed collision, heat, teardown and save/load.
- `BedroomComfortTest`: actual crafting consumes all six ingredients; installed
  heat makes a starter bedroom comfortable and removal clears it.
- `FurnitureCatalogThumbnails.gd -- --only=hearth`: refreshed current icon.
- `CraftingBrowserTest -- --capture`: current name/icon, grouped ingredients and
  crafting controls at 960, 1280 and 1920 pixels.

The runtime fixture's 64-cell room uses the current minimum heated volume of
128, so 2400 heat adds 18.75°C. This tiny fixture is a heat-accounting check;
normal starter bedrooms are larger. Player saves are never read or written by it.

```powershell
python -B tools/generate_hearth_redesign.py --install
powershell -File tmp/rudimentary_hearth_20261011/run.ps1 -Mode import-review
powershell -File tmp/rudimentary_hearth_20261011/run.ps1 -Mode preview
powershell -File tmp/rudimentary_hearth_20261011/run.ps1 -Mode import-game
powershell -File tmp/rudimentary_hearth_20261011/run.ps1 -Mode thumbnail
powershell -File tmp/rudimentary_hearth_20261011/run.ps1 -Mode verify
```

Omit `--install` for a review-only export. The earlier 2026-10-01 size study and
2026-10-02 animation study remain in `tmp/hearth_redesign_preview/` and
`tmp/hearth_animation_preview/`. `audit_hearth_animation.py` belongs to that
historical animation-only change: its preservation assertions intentionally do
not apply to this requested geometry replacement.
