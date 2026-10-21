# 234 — Remove unavailable furniture and clean player saves

Completed 2026-10-18 at the player's request. The following fifteen designs are
removed from the production game until they can be redesigned with actual
player crafting:

| Removed design | Identity suffix |
|---|---|
| Aging rack | `aging_rack` |
| Anvil | `anvil` |
| Storage barrel | `barrel` |
| Brazier | `brazier` |
| Brewing vat | `brewing_vat` |
| Communal dining table | `communal_table` |
| Dwarven bed | `dwarf_bunk` |
| Smelter | `smelter` |
| Storage chest | `storage_chest` |
| Storage shelf | `storage_shelf` |
| Tavern bar | `tavern_bar` |
| Trade counter | `trade_counter` |
| Wall torch | `wall_torch` |
| Wooden chair | `wooden_chair` |
| Personal dining table | `wooden_table` |

The settlement flag, wet stone and dry stone are explicitly retained. All
sixteen craftable furniture designs remain, including the organic log stool,
dining/game tables, workbench, bed, bench, doors, fences and log torch. Their
twenty recipes (sixteen furniture and four tools) remain intact. Other goods,
beverages, crops, floors, original VOXs and historical art studies are outside
this furniture removal.

## Production cleanup

Removed the fifteen definitions, packed-item identities, Place cards,
thumbnails, DEV spawns, fallback UI labels and production meshes. The alternate
legacy chair and the brazier/smelter flame clips were also retired. The log
torch now owns `wooden_torch_flame.glb`; its geometry, palette and animation are
identical to the former shared wall-torch clip. Every other retained furniture
GLB is byte-identical to the recovery snapshot. Shadow proxies and native 1:16
geometry are unchanged.

There are now **19 furniture definitions**, **28 Place entries** including
plants, **33 furniture GLBs** and **386 production GLBs** overall. Current voxel
authoring and coverage omit the removed designs. Complete furniture builds
prune their obsolete staged files. Legacy generators reject writes to retired
production paths. Historical roadmap evidence remains historical.

`data/content_retirements.json` owns the explicit removal policy. SaveManager
loads it and passes a private dictionary to SaveFileStore. The pure
`RetiredFurnitureMigration` component removes matching installed pieces,
plans, Move records, loose/stockpiled/carried packed items and obsolete filter
entries. Unknown/modded keys remain untouched. Surviving contents of removed
containers become loose goods at the old floor position, preserving counts,
materials, instance identities and permissions without counting aggregate
inventory and instances twice. The migration is idempotent.

Reads validate before migration and validate changed results again. Writes
normalize a copy of the four affected owners, preserving caller-owned state
and avoiding copies of the large terrain/water sections. Ordinary cleaned
reads do not pay for a second full validation. Save schema remains version 2.

## Player saves

All four real slots were replaced only after native validation and copied-save
roundtrips. Independent comparison confirmed that these particular files
changed only the retired installed furniture and stockpile stacks:

| Slot | Installed pieces removed | Packed units removed |
|---|---:|---:|
| Quicksave | 15 | 14 |
| Quicksave backup | 15 | 14 |
| Autosave | 13 | 16 |
| Autosave backup | 11 | 18 |

The quicksave retains 73 installed furniture pieces; the autosave retains 67.
Both retain all five dwarves. Flag, water stones, terrain, clock, camera,
wildlife, construction, ongoing work and unrelated goods are preserved.
The autosave's older workbench layout follows the already-existing v1→v2
upgrade from milestone 229 when loaded; the retirement does not rewrite that
layout field in the player file.

Original slots and source assets are recoverable under
`tmp/retired_furniture_20261018/`. Installation uses a hash guard against
intervening player writes, flushed temporary files and atomic replacement.
`player_saves_installed.json` records before/after hashes and original recovery
locations. `workspace_before.zip` and `workspace_after.zip` retain the source
checkpoints; `completion.json` records their hashes and verification evidence.

## Verification

- Four furniture generation tests and four retirement/coverage tests pass.
  All 33 furniture assets rebuild byte-identically; all 386 production models
  have exact manifest coverage and matching hashes.
- Native migration: 183 checks, including both Move phases, aggregate/instance
  inventory, identity-bearing water stones, permissions, malformed input,
  copy isolation, idempotence and all four save candidates.
- Native imported art: 658 checks; retained fire animation: 129 checks.
- Real crafting/placement: 27 placement cases plus interruptions and wall
  support; log dining and two-player recreation suites pass.
- Full SaveManager roundtrip passes, including 210 malformed snapshots,
  backup recovery, 19 validator comparisons, worker snapshot isolation,
  busy-operation guards and three injected transaction-failure stages.
- Cleaned quicksave and autosave each pass actual world load, save and reload
  in isolated profiles. Retained furniture, goods and residents roundtrip.

Native logs are under `tmp/settlement_art_20261013/retired_furniture_*`.
The save regression now uses a synthetic, test-only storage definition to
exercise container persistence without restoring unavailable production
furniture. Older tests/previews specifically demonstrating retired designs
remain historical fixtures; this was a targeted regression run, not a run of
every historical test script.

Restart Play and load the quicksave or autosave. No Windows export or Git commit
was requested or created.
