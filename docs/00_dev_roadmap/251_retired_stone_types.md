# 251 — Remove unused stone types

Completed 2026-10-19 at the player's request. Granite, basalt, limestone and
marble are removed from the game, including their GLBs. Rough Stone remains
the only ordinary stone item. This supersedes their inclusion in the resource
art catalogues of milestones 225 and 238 and the proposed marble merchant trade.

## Removed content

- Four `base:resources:stone:*` definitions and their item descriptions/tags.
  Storage filters derive their choices from this catalogue, so the four choices
  disappear without a UI-specific blacklist.
- Four production GLBs, four inventory thumbnails and their eight import
  sidecars, plus eight generated editable VOXs across the old spherical and
  current chunky resource folders: 24 files total.
- Current faceted/voxel palettes, material-specific coloring, unused stone
  patch volumes, manifest entries and asset revision entries.

The item art family now contains **58 item definitions with 88 GLB forms**;
the complete runtime item catalogue has **83 definitions**. There are **382
production GLBs**, all retained files byte-identical to the before checkpoint.
The mined-resource family has ten variants: Rough Stone, six ores and three
soils. Terrain rock01–rock11, their appearance and yields, construction costs,
recipes, gems, scenery boulders, wet/dry stones and original shared VOX source
remain unchanged.

`data/content_retirements.json` retains exact obsolete IDs and asset paths only
to clean saves and prevent regeneration. Complete item builds prune retired
GLBs and import sidecars from reused staging directories. Coverage and legacy
write guards reject their reintroduction. Historical milestone images and
recovery archives are evidence, not runtime content.

## Save compatibility

SaveManager captures the new `items` retirement policy alongside furniture.
SaveFileStore passes both to the existing pure retirement migration. It removes
matching loose, stockpiled, carried and furniture-stored items, including
aggregate/instance inventories and item-filter exceptions on storage and Move
records. Items are removed, not converted to another material. Unknown/modded
keys and all other state remain intact; repeated migration has no further effect.

Validation still precedes migration and changed reads are validated again.
Writes normalize private copies of only the four affected owners. The caller's
snapshot, terrain/water sections and schema version remain unchanged. The legacy
report counter `packed_units` includes all retired item units, including stone.

All four current player-save copies validate and require **zero changes**. Tests
also inject all four retired types into each copied slot and verify real read
migration and transactional write/re-read restore exactly the original data.
Malformed retired entries are rejected before they can be concealed by cleanup.
No original player save was written; all four original hashes still match.

## Verification

- All **70 Python asset tests** pass, including exact production manifest
  coverage, retired-file absence and blocked historical generator writes.
- All **88 retained item GLBs rebuild byte-for-byte**. A complete staged build
  removes eight deliberately stale retired GLB/import files.
- Native item-art validation passes with zero fallback models; item manifest
  validation passes **969 checks over 88 models**.
- `RetiredStoneMigrationTest` passes **86 checks** with the optional four-slot
  copied-save integration. It covers all item owners, aggregate/instance count
  conservation, filters, retained/modded goods, caller isolation, idempotence,
  real save encoding, transactions and malformed data.
- Existing furniture retirement, full SaveManager roundtrip, colony inventory,
  rabbit arrival and herd arrival regressions pass. Three stale granite terrain
  references in the two arrival fixtures now use `rock01`; their obstruction
  assertions continue to exercise actual solid blocks.

The first stone test run exposed a fixture comparison between GDScript integer
values and JSON-decoded floats. Both expected and encoded results now pass
through JSON consistently, and caller isolation compares the actual input's
serialization. The corrected native run supersedes that failed fixture run.

Recovery source/assets are in `tmp/retired_stones_20261019/before.zip`; copied
saves, logs, fingerprints and the completion record are beside it. Current
design and art documentation reflects the removal; earlier art milestones
carry explicit supersession notices.

Restart Play to reload the item catalogue. No new global class, save schema,
Windows export or commit is introduced.
