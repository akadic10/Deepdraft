# 157 — Asset folder layout

**2026-10-13:** Remove the redundant `faceted` directory layer now that the
superseded voxel exports and duplicate pilots have been removed in
156. Asset families and their meaningful categories
remain the organizing structure.

| Family | Production location | Models moved |
|---|---|---:|
| Trees | `assets/models/flora/trees/<species>/` | 94 |
| Ground stones | `assets/models/details/<category>/` | 6 |
| Dwarf appearance | `assets/dwarves/<part category>/` | 41 |
| Wildlife | `assets/animals/<species>/` | 21 |
| Furniture and packed forms | `assets/models/furniture/` | 41 |
| Loose goods | `assets/models/items/<category>/` | 92 |
| Animated work tools | `assets/dwarves/tools/` | 2 |

All **297 models** move up one level; all **seven `faceted` folders** are removed.
The 76 vegetation models, three construction-floor models and five flame
animation libraries keep their locations. All **381 model files** retain their
exact bytes. Godot regenerates import metadata at the new paths, preserving all
297 moved models' import settings.

Definitions, registry preloads, fallback paths, generators, review tools and
tests use the new locations. The 41 changed JSON definitions contain only path
changes. Gameplay identities, model geometry, palettes, bounds, recipes,
animation anchors and save data formats remain unchanged.

The generators keep their descriptive filenames such as
`generate_furniture_faceted.py`; they now export directly to the family folders.
Retired voxel generators remain guarded against overwriting production assets.
The family audit excludes separately owned dwarf tools and furniture flame
libraries when checking appearance and furniture inventories. Historical hashes
and reports retain their original path spelling, which the audits map to the
current locations. Earlier reports are dated evidence rather than current
asset directory instructions.

All seven production generators and three reference generators pass byte
reproduction checks. All 16 art, animation, hauling, water-stone and save
fixtures pass. Native resource/tool and furniture catalogues render successfully
at the new paths. A pre-change settlement save restores 24 dwarves, 48 furniture
pieces, eight lights, 2,953 trees and all four wildlife species, with identity,
appearance, clock, furniture, terrain and resource-conservation checks passing.

Current authoring locations are listed in
[standard 63](../60_asset_creation/63_shared_art_standard.md).
Verification evidence is stored in
[the inventory](concepts/157_asset_layout/inventory.json),
[validation results](concepts/157_asset_layout/validation.json),
[the family audit](concepts/157_asset_layout/family_audit.json) and
[existing-save restoration](concepts/157_asset_layout/save_restore.json).
The inventory also records the verified external recovery archive.

Restart Play to refresh already-loaded resource paths. No new world or save
migration is required.
