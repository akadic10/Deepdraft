# 132 — Move furniture and crafting stations

Implemented 2026-10-12. Object explorer offers **Move** for installed furniture,
including workbenches, storage containers, beds, seating, doors and wall lights.
This follows the existing shrub destination-preview workflow.

## Player controls

1. Inspect a piece and choose **Move**.
2. Aim at a clear, valid destination; **R** rotates using normal placement rules.
   Wall lights retain normal wall-height controls and worker reach requirements.
3. Click to confirm. A blue destination plan appears and the source is marked
   **Waiting to move**. Escape before confirmation leaves it untouched.
4. A worker packs the source, carries that exact item and installs it at the
   destination. No spare item or construction material is consumed.

Both the source and destination offer **Cancel move**. Before packing, cancellation
leaves the original installed. After packing, the intact item remains available
for hauling or ordinary placement. Cancellation while carrying drops it safely.
A Move plan has no DEV Instant Build action because it needs its real source item.

## Preserved state

- Material and its appeal contribution follow the actual packed item.
- Bed assignment follows the moved bed unless the player assigned its resident
  another bed while it was in transit.
- Containers keep acceptance filters. Packing empties their contents as real
  loose goods at the old location, using normal uninstall behavior. Haulers can
  store those goods again after the container is installed.
- Crafting orders retain their ingredients and progress when a station becomes
  unavailable. Workers resume at a suitable installed station.
- Lighting, heat, door boundaries, occupancy and room membership update through
  the existing uninstall/install paths.

Destinations must satisfy normal placement rules, including clearance, support,
seating access and wall mounting. The source remains occupied until packed;
overlapping moves and rotation in place are not part of this milestone.

## Ownership and persistence

`FurniturePlacementController` owns `FurnitureMoves`, a small settings/identity
ledger. Confirming a destination allocates an exact `furniture_move:<serial>` ID,
reserves its future packed item and posts the source's normal UNINSTALL job.
After packing, `FurnitureMovePlan` reuses FETCH_BUILD and the ordinary physical
inventory pipeline. As with shrub Move, the packer is preferred for the next
stage when eligible; interrupted work releases that preference.

The ledger is not inventory. Only the installed piece or its real loose, stored
or carried item owns the object. The ledger retains storage filters and bed
ownership even if the destination is cancelled after packing, then retires when
that item is installed normally. A blocked destination keeps the plan and item.

Current saves require `furniture.moves` (next ID and records); destination ghosts
save `move_id`. Claims rebuild before items/dwarf cargo restore. Carried items
load intact at the dwarf's feet using existing recovery, then workers resume.
Validation rejects missing/duplicate sources, items and destination identities.
Older development saves need no migration under the project save policy.

## Verification

`FurnitureMoveTest` exercises the real inspector button, preview cancellation,
exact-piece selection despite matching spare stock, worker transport/rotation,
interruption and cancellation while carrying, blocked-destination recovery,
container filters/contents, bed ownership, active crafting, wall mounting and
pending-owner restoration. Native captures cover the workbench, destination and
container inspectors in `tmp/furniture_move_20261012/`.

`SaveManagerRoundTripTest` includes pending and packed moves in full autosave,
manual/backup reload comparisons, malformed move state and carried-item recovery.
`tools/run_job_reliability.ps1` includes the new fixture (30 total). Bridge,
ladder and water-stone callbacks also accept the uninstalling worker ID.

Final verification: all 30 job-gate fixtures passed, plus WaterStoneLifecycleTest,
LogBridgeTest, DwarfRestTest, StorageFilterTest and ItemPermissionTest. Native
FurnitureMoveTest passes with captures at 1280×720 and 960×540; the compact
container scroll area contracts to keep the added action and footer on-screen.
Headless editor import and whitespace checks pass. Logs are under
`tmp/furniture_move_20261012/{gate,related,storage}/`.
