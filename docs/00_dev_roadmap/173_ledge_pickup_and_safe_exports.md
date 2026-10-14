# 173 — Ledge pickup and safe Windows exports

The player reported three copper drops left on a mined wall ledge and a missing
three-wide log-door placement preview in the Windows playtest.

## Copper reach

The copied settlement has a room floor at Y43 and ore resting at Y46, on the
Y45 wall. Pickup candidates previously considered only same-level and one-step
neighbours. A dwarf standing below the ledge therefore never received a haul.

`StorageComponent.ground_access_cells()` now includes the cardinal neighbour
two floor levels below when the item space and the space over the lip are clear.
Live terrain and placed occupancy supply those checks. Navigation still proves
the route and normal three-block standing clearance; step height is unchanged.
Haul and furniture/ingredient fetch contact rechecks the raised reach before
transferring ownership. A blocked reach releases its claim without moving ore.
Food and equipment reuse the shared access candidates.

A second restriction appeared in the copied room: the route probe rejected the
ore's own cell for insufficient standing headroom before considering its explicit
pickup stands. `NavGrid` now validates the actual stands for multi-target work
probes. Ordinary walking still requires a navigable destination. A ceiling added
to the regression reproduced this failure before the route-probe correction.

This also applies to existing loose items restored from saves. No item IDs,
saved positions, inventory quantities, terrain, or schemas are migrated.

## Door preview and export lifetime

The player's log reports `ResourceFormatImporter::load` failures for
`log_door_3.glb.import` and other furniture. The previous bridge export replaced
the same PCK used by an already running game. Godot reads that pack lazily;
its old resource offsets no longer described the replacement bytes.

The source imports and door definitions were intact. No door dimensions or
placement rules needed changing. `tools/windows_playtest/Export.ps1` now creates
a unique timestamp/GUID release directory on every run and keeps export logs
beside that release. It refreshes the shareable ZIP without replacing any prior
EXE/PCK directory. The editor preset points to a separate manual-export location.
The packaged README explains safe updating. Manual exports still require the
user to close any game running from the destination before overwriting it.

Save and close the old game, then launch the fresh release and load normally.
Existing saves live outside the installation and carry across builds.

## Verification

- `LedgePickupTest`: real scheduling, contact, carrying and storage of three
  elevated copper chunks under a low ceiling; rejects a higher ledge, diagonal reach, blocked lip
  and placed occupancy; a new blocker at contact preserves ore and frees claims.
- `HaulingAnimationTest`, `WorkerCraftingTest`, `DwarfFoodTest`:
  ordinary hauling, containers, crafting fetch, food and conservation regressions.
- `NavigationRegressionTest`: destination/route blocking, live terrain and
  occupancy changes, water, cached corners and route costs.
- `LadderMiningTest`, `LadderSchedulingTest`, `MiningLedgeAccessTest`:
  resumable work probes, distant ladder routes and alternate ledge approaches.
- `LogFurnitureTest`, `FurniturePlaceTest`: all three door widths, crafting,
  preview loading, installation, hinges, traversal, room boundaries, rotations,
  save restoration and catalogue input.
- `tools/windows_playtest/AuditPack.gd`, run using the editor with `--main-pack`
  and an absolute external script path, loads and instantiates all 41 furniture
  models directly from the exported PCK, including all three doors.
- Native Windows release startup/world generation exits without diagnostics.
- Native review of the player's copied autosave (seed 3324557759): all three
  door previews resolve valid floor cells through screen picking; the three-wide
  preview fits the reported opening. The real scheduler picks up all three
  original copper drops from `(584,43,591..593)` and stores exactly three units.
  Only review actor position/needs/work permissions and storage filters were
  adjusted to focus the check; saved terrain and ore positions were unchanged.

Reproduction tooling and temporary evidence are under
`tools/windows_playtest/ReviewLedgeDoor.gd` and `tmp/ledge_door_20261013/`.
All runtime checks use isolated APPDATA; the source player saves are only read.

Preserved [copied-save results](concepts/173_ledge_pickup/copied_save_review.json),
[three-wide preview](concepts/173_ledge_pickup/log_door_3.png) and
[raised pickup](concepts/173_ledge_pickup/reach_1.png) record the final native review.

Final release: `build/windows/releases/20261013-205942-799-1e2206c3/Deepdraft/`.
Share `build/windows/Deepdraft-Windows-Playtest.zip`, SHA256
`2CE8B51D1EABAB65B5DB59FC05900C5A3107D8B63FC9C4C9DC4B75FD296AFD8C`.
The preceding release's PCK remains byte-identical after this export.
