# 236 — Native hand-hewn timber preview

**Subsequent decision:** [237](237_hand_hewn_timber_activation.md) installs this
preview in normal Play after the player accepted it provisionally. The original
concept remains the higher [art-direction target](../60_asset_creation/64_hand_hewn_art_direction.md).
The shared authoring owner is now `tools/voxel_assets/hand_hewn_timber.py` with
`data/art/voxel_hand_hewn_timber.json`; this study's generator delegates to it.
The viewer's Current Production comparison now shows the installed design.
The isolated-preview description below records the state at this milestone.

2026-10-18. The player asked how confidently the timber concept could become
real voxel art they can see. This is an isolated first implementation for review,
with actual Godot renders and an interactive source-project viewer.

## Review

Run **`Launch Hand-Hewn Timber Study.cmd`** from the project root. Choose Family,
Dining, Games, Workbench, Stools + timber, or Compare. Compare shows the current
production dining set and the study under identical lighting. Select Oak, Pine,
Juniper or Applewood; use Close / Colony / Top and Neutral / warm. Arrow keys
orbit, the mouse wheel zooms, and Escape closes the viewer.

The launcher uses an isolated user-data directory under `tmp/hand_hewn_study/`.
It does not load or write the player's savegame. Normal Play still uses the
previous approved assets. No Windows export, production activation, new global
class or autoload was created.

Native captures and validation are saved in
`concepts/236_hand_hewn_native/`. The overview is `family_oak.png`; `compare.png`
shows the design difference. These are engine screenshots, not generated images.

## Design

Five designs in four woods produce 20 greedy GLBs and 20 editable VOX files:

- Dining table: an irregular, broad outline, darker bark rim, broken angular grain,
  a knot and a carved drying split. The centered pedestal remains 16×16×16 cells;
  the slab remains four cells thick, with a 46×46 occupied envelope.
- Log stool: 14×14×14 cells with broad bark plates and a small drying check. Four
  separate stools remain at cardinal offsets of two world blocks, inside the
  approved total 5×5 dining area.
- Game table: the identical dining body plus an inscribed board and six supported
  colored counters. Their height stays one micro voxel above the slab.
- Workbench: the approved 46×16×46-cell stump, with a squarer outline and shallow
  tool scars. This prototype keeps the existing stump construction rather than
  adopting the illustration's separate feet; it has no decorative axe.
- Timber: the exact colored stool occupancy rigidly rotated onto its side, still
  14 cells in each dimension. Oak, pine, juniper and applewood are all shown.

One occupied cell is exactly 1/16 world unit; root scale is one. Color variation
uses a small semantic palette and broad patches rather than per-cell randomness.
The study palette is independently editable and does not change CraftMaterials.
The dwarf is the existing production dwarf used for scale, not new character art.

The floor uses the existing rock block ID, live ChunkMesher and existing terrain
appearance shader. There is no new paving texture. Neutral and warm light are
controlled review setups; full underground gameplay lighting remains a separate
integration review if the player adopts this direction.

## Geometry and shadows

Each object has one visible mesh surface and one shadow-only proxy. The viewer
uses a shared vertex-color StandardMaterial3D and VoxelShadowSetup. Detailed
geometry has casting Off; the proxy has Shadows Only and GI disabled.

| Oak asset | Visible triangles | Shadow triangles |
|---|---:|---:|
| Dining table | 2,492 | 126 |
| Stool | 548 | 92 |
| Game table | 2,566 | 142 |
| Workbench | 2,502 | 150 |
| Sideways timber | 542 | 98 |

The dining proxy submits about 95% fewer triangles than the full visible mesh.
This is a geometry count, not an FPS claim. The coarser proxy intentionally
omits fine bark/crack self-shadow detail; native screenshots show its footprint.

## Sources and verification

- Design profiles: `data/art/studies/hand_hewn_timber.json`.
- Generator and viewer: `tools/hand_hewn_study/`.
- GLBs and geometry manifest: `assets/models/studies/hand_hewn_timber/`.
- Editable VOXs: `VoxelFeed/studies/hand_hewn_timber/`.
- Run evidence: `tmp/settlement_art_20261013/hand_hewn_final_review/`.
- Recovery snapshot: `tmp/hand_hewn_study/checkpoint/`.

`generate.py --check` regenerates all 20 GLBs byte-for-byte, reads their actual
position buffers to verify the exact source 1:16 grid, and roundtrips every
editable VOX's occupied cells and palette. It also checks connected solids,
approved envelopes, support, shared game/dining geometry, six counter contacts,
exact sideways log rotation and the 5×5 stool arrangement.

The native viewer passes 260 checks across the imported models: unit roots,
dimensions, floor contact, single surfaces, retained color palettes, shared
materials, visual/proxy policy and lower proxy triangle counts. Godot's default
vertex compression introduces at most roughly 0.001 micro voxel of position
error; the source GLBs are exact. Twelve views cover all woods, close details,
comparison, top, colony distance and warm lighting. Native logs are clean.

The checkpoint records source/output hashes and verifies that all 386 installed
production GLBs still match their existing family manifests. This first preview
is ready for visual feedback before any production replacement.
