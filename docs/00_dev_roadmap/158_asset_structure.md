# 158 — Asset structure

**2026-10-13:** Group assets by media type, then organize 3D models by subject.
This follows the legacy cleanup in [156](156_legacy_art_cleanup.md) and removal
of style folders in [157](157_asset_folder_layout.md).

```text
assets/
  audio/
  models/
    animals/                  # species
    characters/
      dwarves/                # appearance parts and rig-specific tools
    flora/
      trees/                  # species
      bushes/                 # species
      flowers/
      reeds/
    rocks/
      boulders/
      scree/
    construction/
    furniture/
      animations/
    items/                    # resource and inventory categories
  ui/
```

| Previous location | Current location | Models moved |
|---|---|---:|
| `assets/animals/` | `assets/models/animals/` | 21 |
| `assets/dwarves/` | `assets/models/characters/dwarves/` | 43 |
| `assets/models/flora/vegetation/` | `assets/models/flora/` (existing child categories) | 76 |
| `assets/models/details/` | `assets/models/rocks/` | 6 |

All **146 moved models** retain their exact bytes and import settings. The
complete inventory is **381 GLBs**, now entirely under `assets/models/`.
The four old folder locations are removed. Animals remain distinct from
characters; trees, bushes, flowers and reeds are peers within flora. Keep
species and modular part categories where useful, and add future folders when
real assets require them. Joint-local axe and pickaxe models stay with the
dwarf rig; independently dropped tools stay in `items/tools/`.

Nine JSON definitions change only resource paths. Registry preloads, fallback
paths, authoring destinations, review tools and fixtures use the new structure.
IDs, recipes, statistics, palettes, geometry, animation anchors and save schemas
are preserved. Retired export commands remain guarded. Historical evidence
keeps its original paths; `tools/art_asset_paths.py` resolves those paths for
offline audits without introducing runtime path aliases.

Verification covers all model hashes and current Godot import hashes, all 146
moved importer parameter sets, ten generator reproduction checks, both retained
art audits and 16 art/gameplay/save fixtures. Native dwarf, wildlife, vegetation
and stone galleries load successfully. A pre-change settlement save restores
24 dwarves, 48 furniture pieces, eight lights, 2,953 trees and all four wildlife
species, with all save-restoration checks passing. No new missing model
references are introduced; 14 already-deferred growing-crop references remain
future art work.

Evidence: [inventory and recovery archive](concepts/158_asset_structure/inventory.json),
[validation](concepts/158_asset_structure/validation.json),
[family audit](concepts/158_asset_structure/family_audit.json), and
[existing-save restoration](concepts/158_asset_structure/save_restore.json).
[Standard 63](../60_asset_creation/63_shared_art_standard.md) is the current
authoring guide; older milestones retain their dated layouts.

Restart Play to refresh resources already loaded from previous paths. No new
world or save migration is needed.
