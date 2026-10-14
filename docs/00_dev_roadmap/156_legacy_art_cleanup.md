# 156 — Legacy art cleanup

Completed **2026-10-13** after approval to purge the superseded voxel art.
The approved appearance is unchanged. The project now contains one production
export per converted model, with no obsolete tree to select by mistake.

## Removed and retained

- Removed **353 superseded voxel GLBs** and **17 duplicate pilot GLBs**.
- Moved **94 production trees** from `assets/models/flora/trees/pilot/` to
  `assets/models/flora/trees/faceted/`, updating all four species definitions,
  the exporter, tests and study scene references.
- Removed 464 orphan import sidecars accompanying the retired/moved sources and
  41 empty asset directories. Godot generated the new tree import metadata;
  current import settings were not hand-edited.
- Preserved all **373 approved production models** and the **eight still-live
  floor/effect models** byte for byte: 381 GLBs total, down from 751.

See [standard 63](../60_asset_creation/63_shared_art_standard.md) for the current
folder inventory. The production `wooden_chair_legacy` model remains because it
supports an existing furniture form. Cave flora, growing crops, floor art and
effects are outside this removal. The 14 already-missing planned crop-stage
references remain deferred; this cleanup introduces no new missing references.
Terrain remains editable voxels and grass remains a full voxel.

## Authoring and review tools

Dwarf, wildlife and furniture family generators now reproduce their approved
reference parts directly from source. They no longer copy duplicate pilot GLBs.
The pilot-named helper scripts remain usable and write to production paths.
Six exact named flame meshes now live in the offline authoring input
`data/art/furniture_flames.json`; rebuilding furniture no longer needs its old
voxel bodies. Existing flame animation libraries are unchanged.

The 59 retired voxel export commands and six historical snapshot audits stop
with a retirement message. Their source helpers remain importable for existing
flame authoring. Current family/item audits compare against the preserved
approval hashes and historical cost reports, rather than deleted binaries.

Review scenes now use the production asset set: dwarf appearance pairs,
opposing wildlife/furniture views, wood material comparisons, and current
resource/tool catalogues. Legacy environment capture switches explain that
historical comparisons are now in the dated reports. Earlier images and reports
remain unchanged; their source asset paths document historical states.

## Validation

- All seven production family generators and three reference generators pass
  byte reproduction checks; all 381 imported models match their source hashes.
- **16 fixtures pass**, covering every converted family, approved reference
  parts, mining, felling, hauling, produce crates, water-stone lifecycle and saves.
- Native item, furniture, wildlife, dwarf, vegetation and ground-stone review
  captures complete without asset-loading or script errors.
- A pre-cleanup settlement save restores **24 dwarves, 48 furniture pieces,
  eight lights, 2,953 trees and all four animal species**. Identity, appearance,
  furniture, terrain edits, stone conservation and clock checks pass.

Evidence: [inventory and fingerprints](concepts/156_art_cleanup/inventory.json),
[fixture results](concepts/156_art_cleanup/validation.json),
[family audit](concepts/156_art_cleanup/family_audit.json), and
[native save restoration](concepts/156_art_cleanup/save_restore.json).
Updated viewer examples: [dwarves](concepts/156_art_cleanup/dwarf_review.png),
[furniture](concepts/156_art_cleanup/furniture_review.png).

An external recovery ZIP contains every removed/moved GLB, its original import
metadata and pre-cleanup source files. Its local path is recorded in the inventory.
It is outside the project, so Godot cannot reimport the retired art from it.
Temporary QA snapshots remain in the already-ignored `tmp/` folder.

Restart Play to refresh loaded resources. If an old import preview remains open
in the editor, close it and browse the production folder. No new world or save
migration is required.
