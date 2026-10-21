# 237 — Accepted interim timber installed

2026-10-18. The player accepted the native preview for now and asked to install
it, while keeping the original, more detailed concept as the ongoing art target.
Dining tables, game tables, log stools, workbenches and chopped timber now use
the accepted models in normal Play. Their visual quality still falls short of
the concept; this milestone records integration, not artistic parity.

## Visual authority

The exact original concept is permanently saved at
`docs/60_asset_creation/reference/hand_hewn_timber_direction.png`.
[64 — Hand-hewn art direction](../60_asset_creation/64_hand_hewn_art_direction.md)
records the decision and the remaining shape, bark, grain and material goals.
The shared art standard and agent navigation index link to it. The simplified
235 concept and the 236 Godot screenshots are historical references, not a
replacement for the original concept's quality.

This request implements the accepted timber family. The illustration's paving,
dwarf, workbench feet and axe do not change terrain, characters or the approved
solid-stump workbench in this milestone.

## Installed assets and source ownership

Eight production GLBs change: `log_chair`, `log_table`, `board_game_table`,
`crude_workbench`, and the four wood resource models. The remaining **378 of
386** production GLBs are byte-identical to the before checkpoint. Eight native
thumbnails are refreshed. Existing objects adopt the models on reload; newly
crafted and placed objects use the same paths and saved identities.

`data/art/voxel_hand_hewn_timber.json` owns the accepted shapes and four palettes.
`tools/voxel_assets/hand_hewn_timber.py` is the shared shape generator used by
the furniture and item builders and the isolated study. `author_furniture.py`
also retains this routing when regenerating recipes. Current editable VOXs are
in `VoxelFeed/colored/hand_hewn_timber/`: five designs in four woods, 20 files.
Original player VOXs and historical source copies are preserved.

Only these four furniture definitions select the new `hand_hewn_timber` source
palette. Its ten namespaced `hewn_*` roles map to oak, pine, juniper and applewood
through the existing cached CraftMaterials owner. Other wood palettes retain
their colors. Game counters stay red and teal in every species. The loose wood
items bake the matching species palette.

The 1:16 grid, unit roots and ground contact remain unchanged:

| Design | Occupied cells, X × Y × Z | Placement |
|---|---|---|
| Dining table | 46 × 20 × 46 | 3×3; centered 16-cell pedestal and 4-cell slab |
| Game table | 46 × 21 × 46 | Same table body; board marks and six counters |
| Log stool | 14 × 14 × 14 | Four close stools and the table fit within 5×5 |
| Workbench | 46 × 16 × 46 | 3×3; existing four-sided work contacts |
| Chopped timber | 14 × 14 × 14 | Exact colored stool turned onto its side |

The game-counter clearance box grows by one micro voxel at its positive X/Z
edges to contain the accepted square counters completely. Table footprints,
chair guides, contact profiles, recipes and save IDs are unchanged.

Each asset retains one greedy visible surface and a separate shadow-only proxy.
The detailed visual has casting Off; the proxy has Shadows Only.

| Model | Visible triangles | Shadow triangles | GLB bytes |
|---|---:|---:|---:|
| Dining table | 2,492 | 126 | 242,836 |
| Game table | 2,566 | 142 | 251,128 |
| Stool | 548 | 92 | 60,856 |
| Workbench | 2,502 | 150 | 245,968 |
| Each timber species | 542 | 98 | 60,856–60,860 |

## Verification

- All 52 Python voxel-asset tests pass, including exact production routing,
  contacts, connected shapes, shared table geometry, supported counters,
  sideways rotation, palettes and all 20 editable VOX roundtrips.
- `HandHewnProductionTest.gd` passes 124 checks on actual furniture and item
  loader output. Every wood variant matches the accepted imported study's
  positions, indices and colors, with the required casting flags.
- Native furniture and item art suites pass 658 and 1,656 checks. Manifest
  suites pass 480 checks across 33 furniture models and 1,013 across 92 items.
- Dining, recreation, worker crafting and log stool suites pass: four rotations,
  four simultaneous diners, two-player games, sixteen directional workbench
  batches, seated poses, clearance, interruptions, Move and save/restore.
- Complete staged galleries were reviewed before exact-hash activation. Both
  full family builders regenerate all 125 installed GLBs byte-for-byte. The
  study's 20 GLBs also remain byte-identical, with source-grid and VOX checks.
- Godot reimport and both thumbnail jobs finish successfully. Native gallery
  and full-world captures show the installed assets; there are no new terrain
  textures or character meshes.

Evidence is under `tmp/settlement_art_20261013/hewn_*`. The completion checkpoint
records exact run labels, logs, output hashes and source files.
Isolated fixtures print the existing missing-scene/environment or world-seed
startup warnings; there are no script errors. The full-world runs have empty
stderr and no reported failures.

## Full-world measurements and limits

Matched `hewn_world_before` / `hewn_world_after` runs pass on seed 1234 at
1600×1000, using the production world, 24 dwarves, 48 furniture pieces, wildlife,
hauling, day/night lighting and slice transitions. Fixture hashes and world
fingerprints match. Both runs save and reload in isolated profiles, preserving
the tested clock, identities, furniture, wildlife, terrain edits and goods.

| View | GPU median before → after, ms | Frame p95 before → after, ms |
|---|---:|---:|
| Paused close | 0.913 → 0.905 | 9.300 → 8.368 |
| Paused overview | 2.639 → 3.011 | 9.473 → 8.775 |
| Active close | 1.483 → 1.386 | 27.159 → 24.505 |
| Active overview | 3.160 → 3.366 | 27.905 → 27.391 |
| Active night | 1.253 → 1.453 | 27.116 → 26.138 |
| Active slice | 1.579 → 1.616 | 27.170 → 26.890 |

Draw counts match in every sampled view. This is one paired run on a Ryzen 7
9800X3D and Radeon RX 9070 XT; GPU results vary in both directions and do not
establish a speedup or low-end performance. The full-world fixture includes
stools and timber but not every revised table design; targeted imported-art and
interaction suites cover the complete family. Renderer cost, simulation timing
and artistic quality are separate acceptance questions.

## Checkpoint and handoff

`tmp/hand_hewn_activation_20261018/before.zip` preserves the previous source,
data, GLBs and thumbnails. `production_before.json` fingerprints all 386 models.
`complete.zip` and `completion.json` retain the final source, exact assets,
canonical concept, test evidence and a verified archive manifest. No failures
remain in these checks. The documented artistic gap remains open.

Restart Play and load the existing save to see the installed models. No global
class or autoload was added, and no project reload is required. Actual player
save files were not written, and no Windows export or commit was created.
