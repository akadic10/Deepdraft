# 212 — Final terrain state

Implemented 2026-10-17. Completed stone, plank floors and stone floors have no
player-built ownership record. Construction retains unfinished orders, staged
materials and partial work. Floor block types still determine their authored
appearance, walking support and the existing +5 completed-room flooring bonus.

## Terrain and mining

WorldData holds one current block value per changed position. A write replaces
the previous value; returning to the deterministic generated block removes the
override. There is no mining/building event history and no origin label in the
terrain inspector. The same mechanism accepts dirt and grass when their build
tools are introduced; those tools are not part of this change.

Ordinary placed stone now uses the same mining definition as natural stone:
a 5% chance of one rough stone, without a guaranteed construction refund.
Both preview floor types still yield nothing when mined because they currently
consume no materials and have no drops in their block definitions.

WorldRenderer draws solid overrides, including the existing floor art, from
WorldData. It coalesces edited cells per frame, updates generated-terrain masks
and removes stale excavation holes when a position returns to its original
state. ConstructionController renders only unfinished plans and previews.

## Save format and compatibility

Schema 2 stores `scene.terrain.edits` as unique `{cell, block}` records using
permanent string keys, including air. Unchanged terrain regenerates from the
saved seed. It saves the final world without allocating all 134 million voxels.

`scene.exploration` separately stores known cells and discovered cave IDs.
Filling a known room does not erase the player's knowledge. Exploration never
writes terrain. Mining saves only outstanding zones; water saves its own flow,
moisture and stone state; construction saves only unfinished orders and IDs.
The removed fields are `mining.mined_blocks`, `water.terrain` and
`construction.built`.

Existing valid schema-1 saves are validated before in-memory migration. The
converter resolves overlaps with the original restore precedence: mined air,
then water's solid terrain, then completed construction. It writes each final
voxel once. Legacy mined cells seed exploration only. The synchronous chunk
notification batching from [211](211_large_save_terrain_restore.md) remains.

Loading does not rewrite the original file. The next successful save writes
schema 2 and retains the previous valid file through normal backup rotation.
This migration supports the player's current schema-1 saves, not arbitrary
older development formats with missing unrelated required sections.

## Verification

Native source-project checks passed for save/load and transactional faults,
final-state migration and override removal, batched terrain notifications,
construction, input, staging, continuity, DEV completion, hammer audio, floor
construction, terrain inspection and X-ray.

Copied player quicksave and autosave each passed the full sequence: schema-1
load, comparison against all 56,777 legacy terrain positions, schema-2 save,
reload, exact final terrain/exploration comparison and rendered X-ray inspection.
The resulting terrain maps contain 44,958 and 45,008 current overrides,
respectively. Original save and backup SHA-256 hashes are unchanged.

Floor captures retain both patterns and the 81/81 completed-room bonus.
Evidence: [final_terrain_20261017](concepts/final_terrain_20261017/summary.json).
Restart Play to use the updated source. No Windows playtest/export was produced.
