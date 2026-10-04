# 25 — Dwarf visual redesign

Status: **approved and integrated into the live roster**, 2026-10-01.

Alen retained **8 voxels per block** and agreed to the proposed art redesign:
a 15-wide skull, stronger torso, shorter boots, sculpted hair and beard volume,
and more deliberate color placement. The first milestone was one adult base,
reviewed unbearded and with a short beard, plus cropped and longer hair, before
expanding the whole appearance roster in this integration pass.

## Live deliverable

Alen approved the prototype and requested replacement of the old models.
All **41 GLBs in `assets/dwarves/`** have been overwritten and imported into
Godot. Every existing appearance ID and filename remains valid, so new and
saved dwarves both use the redesign. No save migration or pool changes.

- `tools/generate_dwarf_glb.py`: canonical command, validates then exports.
- `tools/dwarf_roster.py`: all four ages, fourteen hair styles, seven beards,
  eight brow files, four scars, and shared body/eyes/hands/feet.
- `tools/generate_dwarf_redesign.py`: approved base shapes and isolated study.
  Adult head/body/hands/boots/eyes, cropped hair, side braid and short beard
  retain the approved geometry and colors.
- `tools/voxel_glb.py`: extracted shared mesher/writer, re-exported by the
  original generator for compatibility with furniture, tree and item tools.
  Those generators retain their corner-based coordinates and scale rules.
- `tools/render_dwarf_roster.py`: actual exported GLB contact sheets.
- `tools/DwarfRosterPreview.gd` and `tools/dwarf_roster_review.tscn`: live
  DwarfAssets/DwarfAgent review, all-combination assembly check, actual gait
  and carry previews. Uses studio light and does not write a game save.
- `tmp/dwarf_roster/geometry_report.json`: counts and reproducible hashes.
- `tmp/dwarf_roster/renders/`: hair, beard, age, brow, scar and Godot captures.

The original nine-part study and saved old-asset references remain under
`tmp/dwarf_redesign_preview/`. Re-running the study preserves any existing
reference copies. A fresh study folder copies the currently installed assets,
so it does not recreate a historical before/after comparison by itself.

## Art and scale contract

| Feature | Live roster |
|---|---|
| Density | 8 voxels/block, scale 0.125 baked into GLB vertices |
| Base skull | 15 cells wide; 17 including ears |
| Total height | 25 bare / 26 shaved / 27 most hair; maximum 3.375 blocks |
| Nose | Central narrow bridge, three-wide bulb, projecting tip |
| Body | Broad 11-cell chest/shoulder envelope; collar, belt, work pouch |
| Boots | 5 wide × 4 high × 7 long; shaped sole and toe |
| Head attachments | Eyes and eyebrows sit in carved slots; shared hair cap |
| Hair | Continuous scalp coverage; asymmetric swept crest; optional side braid |
| Beard | Short jaw volume, projecting moustache, mouth opening, tapered chin |
| Palette | Tint-compatible head/hands/eyes/hair/beard/brows; baked muted teal tunic, linen collar, leather boots/pouch |
| Anatomy | Detached hands and feet; no arms, legs, skeleton, or fused appendages |
| Logical footprint | Existing 1×1×3 gameplay footprint remains unchanged |

The odd-width authoring frame uses integer **cell centres** on X/Z. The writer
subtracts 0.5 from legacy mesh X/Z vertex coordinates before applying the 0.125
scale. Thus the skull is centred on world X=0, facial parts share the same
origin, and the current runtime negative-X mirror still works for hands/feet.
Y=0 remains the sole plane. No runtime import-scale adjustment is needed.

The crown is filled as an outer mass before subtracting the head. This covers
both the tops and vertical risers of skull steps and avoids the old bare scalp
bands. Tone clusters follow the sweep/parting and braid segments; no random
single-voxel highlights are used.

## Audit of the old assets

All 41 shipped GLBs matched the original generator at review time. The old
bare head reaches Y=28 authored voxels (3.5 blocks), ordinary hair Y=29
(3.625), and the tallest style Y=31 (3.875), exceeding the documented ~3.3
target. The redesign restores that approximate target instead of increasing
overall character height along with the extra skull column.

The old drawer-hair note in doc 17 proposed age-dependent crown differences
as a possible cause. The current four head tiers have identical geometry in
their upper crowns. That hypothesis does not explain the present files. The
planar hair sides, boxed outer volumes, and scalp-only top coverage were
addressed directly in this prototype.

## Reproduction

Generate or validate the live roster, then render its exported GLBs:

```powershell
python tools/generate_dwarf_glb.py --check
python tools/generate_dwarf_glb.py
python tools/render_dwarf_roster.py
```

`--out tmp/dwarf_roster/assets` stages the complete set outside live assets.
The live Godot review scene is `res://tools/dwarf_roster_review.tscn`: launch
it with `-- --capture` for nine captures or `-- --check` for headless assembly
validation. Omit both for interactive inspection. The older flat QA tool
`render_dwarf_qa.py` also uses the new source and corrected centre mirroring.

Original isolated study commands:

From the repository root, using Python with numpy and Pillow installed:

```powershell
python tools/generate_dwarf_redesign.py
python tools/render_dwarf_redesign.py
```

Import and capture with the configured engine:

```powershell
& 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --editor --path 'P:\Deepdraft\tmp\dwarf_redesign_preview' --import
& 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --path 'P:\Deepdraft\tmp\dwarf_redesign_preview' -- --capture
```

Omit `-- --capture` to use the interactive preview. It has front,
three-quarter, side, RTS, rear, and gameplay-distance views, a current/prototype
comparison, and an in-place walk preview using the existing gait timing and
offset formulas. The preview uses its own studio lighting, not the generated
world's sky/weather. The Gameplay view uses the project's 45° FOV, 50° pitch,
and 85-block default zoom; the enlarged RTS view evaluates the same elevation.

The Godot GUI executable does not block PowerShell by default. Automation
should use `Start-Process -WindowStyle Hidden -Wait -PassThru` with a log file
and check for `DWARF_REDESIGN_PREVIEW_OK`, as was done for this review.

## Integration validation

- All **800 map shape combinations** from the actual appearance pools: four
  ages × (five male hair choices × four brows × eight beard choices, plus ten
  female hair choices × four brows). No occupied-cell overlaps; exactly five
  face-connected groups per assembly (body/head, two hands, two boots).
- Solid parts are connected; paired eyes/brows and separated facial hair are
  intentional. Scars are shallow, baked-color, portrait-only relief overlays.
- All exported heights are 25–27 cells. The 15-cell skull remains centered;
  negative-X mirroring and import Root Scale 1.0 are unchanged.
- The live manifest matches all 41 original paths. Re-exported files match
  byte-for-byte; the nine approved prototype parts match the live position,
  normal and color arrays exactly. Shared mesher/writer definitions are
  unchanged from the old utility code.
- Every imported combination instantiated through the actual DwarfAgent and
  DwarfAssets registry, including optional bald/no-beard paths and the logical
  1×1×3 collision box: `DWARF_ROSTER_ASSEMBLY_OK: 800`.
- Godot 4.7.2 Forward+ / D3D12 rendered the live assets, side/rear/RTS views,
  additional styles, actual walk poses, and carried items:
  `DWARF_ROSTER_PREVIEW_OK`.
- The carry preview exposed stones intersecting the old face anchor. The
  item origin is now `(0, 1.05, 1.55)`, clearing the longest beard and walking
  lean while keeping the first item below the eyes. Stack spacing and all
  haul/fetch behavior are retained.
- Full game scene save/autosave/backup and carried-item restoration regression:
  `SAVE_MANAGER_ROUND_TRIP_OK`.
- A temporary review platform in the generated game world confirmed the live
  materials under the game's noon sky/light setup (`live_world.png`,
  `DWARF_WORLD_ART_OK`). This QA platform is not saved or added to the game scene.

Existing procedural animation and shared-origin pivots are retained. Equipment
that is not yet implemented will need its own fit review when it is added.
