# 133 — Settlement flag inspection and relocation

Implemented 2026-10-12. The settlement flag was outside Object explorer because
the founding controller created a standalone visual and occupancy box. It now
installs `base:furniture:settlement_flag` through the ordinary furniture owner.

## Player behavior

- Clicking the banner opens Object explorer with **Move** and **Uninstall**.
  Picking respects actual geometry, terrain occlusion and slice visibility.
- Move uses the same preview, rotation, exact-item reservation and worker
  pack/carry/install workflow as [132 — Furniture Move](132_furniture_move.md).
- Cancelling before packing keeps the installed flag. Cancelling after packing
  leaves its real item for storage or **Place → Room furnishings → Settlement flag**.
- The colony remains founded while the flag is packed or carried. Its last
  installed location remains the settlement anchor until installation at the
  new location. Only the initial founding action spawns the starting squad.
- Ordinary Uninstall packs the flag for storage. It does not allow another free
  founding flag. The packed item uses the standard furniture crate and storage
  category; it has no crafting recipe.

## Ownership

`data/furniture/settlement_flag.json` defines the existing banner model and
1×1×3 occupancy. `FurniturePlacementController` owns all installed flag visuals,
collision, inspection, rotation, uninstall sources and Move plans.

`FlagPlacementController` retains the first surface-placement preview and the
once-only founding action. It observes furniture installation to update its
last anchor and `DwarfDirector.settlement_anchor`. Uninstall never erases founding.
No second flag model, duplicate occupancy, separate relocation job or autoload
is introduced.

## Current saves

`settlement_flag` now stores required `founded` and the last installed `cell`.
This historical state restores at priority 20 without creating a physical flag.
Installed flags and pending plans restore through furniture at priority 40;
packed flags restore through normal loose/stored/dwarf-cargo owners. This avoids
creating a second flag when loading during a move. Older development saves
without the new ownership layout are rejected under the current save policy.

## Verification

`SettlementFlagMoveTest` exercises native banner clicks, Move button input,
terrain/slice exclusion, three-block occupancy, physical worker relocation,
before/after-packing cancellation, ordinary Place and Uninstall, retained anchor,
once-only squad creation and reconstruction from an in-transit save.

`SaveManagerRoundTripTest` now includes the installed furniture flag in complete
scene replacement and checks agreement with both saved settlement anchors.
The shared job gate includes SettlementFlagMoveTest (31 fixtures). Native
captures and focused regression logs are in `tmp/settlement_flag_move_20261012/`.

Verification passed: SettlementFlagMoveTest, FurnitureMoveTest,
FurniturePlacementAnimationTest, FurniturePlaceTest, ObjectExplorerTest,
ColonyInventoryTest and SaveManagerRoundTripTest. Native flag inspection/worker
relocation, headless editor import and whitespace checks also pass.
