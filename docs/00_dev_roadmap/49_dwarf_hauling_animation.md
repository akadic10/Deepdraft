# 49 — Dwarf pickup, carry and stockpile delivery

Implemented 2026-10-05; adjacent-cell handling approved in player visual review.

## Motion

The previous hauling visual attached items instantly in a vertical stack while
the hands kept their walking swing. `DwarfCarryPose.gd` now gives the existing
floating fists a reach, contact, lift, supported carry, lower and release.
Body/head motion accompanies the reach; the logical navigation root and
1×1×3 footprint stay fixed. No new GLBs, skeleton or equipment.

The rig measures each item's local mesh bounds once per pickup. Both fists
bracket the visible item, with the load in front of the beard. Walking bounce
moves the fists and cargo together. A four-item load uses two columns and
up to two rows at native scale; existing items ease into their new positions as
the next item is lifted. One fist supports the load during additional pickups.
The same motion covers loose items, produce crates, timber, stone and packed
furniture fetched from a stockpile for construction.

Pickup and ground delivery use a reachable cardinal cell beside the goods;
the dwarf turns toward the item before contact and keeps both boots planted.
The reserved item/destination cell is never used as the handling stand. The
approach checks normal navigation clearance, allows neighbouring one-block
steps, and tries another side if the closest side cannot be reached.
For a multi-item delivery, all of that bundle's reserved destination cells
are excluded from the possible standing cells.

Ground delivery lowers the bundle forward onto the reserved first cell. Container
delivery turns toward the furniture and hands over at container height.
The existing atomic bundle commit still distributes goods among their reserved
cells/shelf slots or absorbs them into container inventory; this is one bundle
handoff, not a separate physical placement animation for every destination slot.

## Carry capacity

`data/tasks/task_config.json` sets `hauling.carry_capacity` to **4 points**.
Every item definition in `data/entities/items/resources.json` has a `carry_cost`:

| Physical object | Cost | Maximum per trip |
|---|---:|---:|
| Rock or ore | 1 | 4 |
| Raw log (oak, pine, juniper, apple wood) | 2 | 2 |
| Produce crate or packed furniture crate | 4 | 1 |
| Other items, including processed oak staves | 1 | 4 |

Mixed loads share the budget: two rocks and one log use all four points.
A produce crate pays once regardless of its fill, including a split pickup
for refilling stored produce. `weight_class` independently retains the existing
heavy-load walking multiplier; carry points describe handling bulk.

`StockpileManager` injects the budget into both ground and furniture storage.
`StorageComponent` selects the nearest accepted, storable item that fits, then
nearby extras within `pouch_bundle_radius`. It skips extras that exceed the
remaining budget and continues searching for cheaper ones. Only successfully
paired source/deposit claims spend points. Oversized items do not post impossible
leases or block another fitting main item. Missing item costs default to 1;
costs and configured capacity are clamped to at least 1. This replaces the old
`pouch_capacity` physical-object count; no save schema changes are needed.

## Timing and ownership

- `data/tasks/task_config.json`, `hauling.pickup_time_s`: 0.75 seconds.
- `hauling.deposit_time_s`: 0.65 seconds.
- The source stays reserved and visually untouched until 36% of the pickup.
  Contact calls the existing quantity-aware take operation exactly once.
- Carried entries own cargo throughout lift, travel and lowering. Final storage
  or construction consumption occurs after lowering. Failed commits use the
  normal drop-at-feet release path.
- Handling and construction timers follow clock speed. Pausing freezes the
  hauling/fetch phases, including travel; gait remains distance-driven.
- Cancellation, source removal, sleep and path failure restore the neutral
  pose and preserve goods. Signed right-hand/foot scales use the existing safe
  restoration helper shared with chopping/mining.
- Saves retain the existing loose-versus-carried boundary. No animation fields
  or new save schema; in-transit goods restore at the saved carrier's feet.

## Review and checks

`scripts/tests/HaulingAnimationTest.gd` exercises real scheduler dispatch,
contact ownership, fitted grips, pause/speed, slice visibility, snapshots before
and after contact, cancellation across all handling phases, sleep during lift,
four-item delivery, partial crate refills, stockpile withdrawal for construction,
container delivery and destination deletion during reach.

`tools/DwarfHaulingPreview.gd` captures an actual assigned job in Godot. Run
without `--headless`; `-- --log` selects a log and `-- --bundle` selects four rocks.
Review GIFs are in `tmp/hauling_animation_review/`.

Regression checks: HaulingAnimationTest, ProduceCrateTest, MiningAnimationTest,
TreeFellingTest and SaveManagerRoundTripTest. Run these with
`--headless --path . --script res://scripts/tests/<name>.gd`.
All five passed on 2026-10-05. Native crate and four-log bundle captures were
also reviewed; logs and GIFs are retained in the review directory.

Player feedback on 2026-10-05 rejected the original between-the-feet handoff.
The adjacent-cell correction above replaces that stance. HaulingAnimationTest
now checks distinct stand/item cells, forward-facing contact, planted boots,
storage withdrawal and blocked-side fallback. HaulingAnimationTest,
ProduceCrateTest and TreeFellingTest passed again after the correction.
The updated native previews are `crate_forward.gif` and `bundle_forward.gif`.
Those retained bundle GIFs show the earlier four-log policy; new bundle captures
use four rocks under the carry-point rules above.

`HaulingCapacityTest.gd` checks rock/ore/log/crate limits, partial/full crates,
unchanged light/heavy speed, mixed loads and subsequent trips, skipping bulky
nearby candidates, claims, configurable budgets/costs, oversized goods,
container delivery and cancellation of an actual two-log load.
After the capacity change, HaulingCapacityTest, HaulingAnimationTest,
ProduceCrateTest, TreeFellingTest, VerifyShelf and SaveManagerRoundTripTest
all passed on 2026-10-05. The headless editor check also passed. VerifyShelf
now uses a fully built dwarf and advances contact/set-down before asserting
ownership, matching the new handling phases.

The new rig is preloaded without `class_name` and registers no autoload.
