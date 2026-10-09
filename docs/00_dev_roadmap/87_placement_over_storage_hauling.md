# 87 — Placement takes priority over storage hauling

The Place catalog previously hid a packed crude workbench as soon as a
stockpile hauler reserved it. The player owned the item but had to wait for
storage delivery before requesting installation. Storage hauling is now a
reclaimable reservation for player placement.

## Player behavior

- Owned furniture stays available while awaiting collection, in a hauler's
  hands, or reserved for transfer between storage areas. This also applies to
  the shared plant and ladder placement stock.
- Opening the catalog or selecting a design does not interrupt hauling.
  Confirming a valid placement takes priority, including while paused.
- Before pickup, the haul releases its reservations and the placement claims
  the item. A worker then collects it through the normal fetch task.
- After pickup, the same dwarf keeps the single packed object and carries it
  directly to installation. There is no storage detour or second pickup.
- A carried multi-unit cutting crate returns loose so the existing fetch
  operation can split one cutting. Remaining units stay physical and available.
- Cancelling, sleeping, or losing a valid installation site preserves the item.
  Other placements, crafting reservations and promised plant identities remain
  protected. A second click cannot reserve the same unit twice.

## Ownership

StorageComponent exposes read-only offers from active haul pulls. TaskManager
accepts only active HAUL tasks, excluding exact identities promised to another
plan. Catalog counts add these offers to the normal loose/stored pool, with
stored outgoing claims counted once. ColonyInventory uses the same placement
availability.

FurnitureGhostComponent requests a handoff only after the designation exists.
TaskManager cancels the old lease, releasing deposit/outgoing tokens. For a
single carried object, DwarfAgent preserves that exact node across cancellation
and begins the fetch task at its travel-to-install phase. Other cargo follows
the normal safe-drop cleanup. No extra inventory store, save field, item
duplication, or global class is introduced; carried items use existing saves.

## Verification

`PlacementHaulPriorityTest.gd` covers the paused Place UI, read-only browsing,
waiting pickup, pickup before/after contact, carrying, deposit, same-carrier
ownership, rapid repeated placement, final installation, cancellation, sleep,
invalid final support, exact-instance protection, storage relocation and
splitting a cutting crate. It checks physical counts and carried save data.

Related suites: FurniturePlaceTest, WorkerCraftingTest, ColonyInventoryTest,
HaulingAnimationTest, ShrubMoveHandoffTest, LadderTest and SaveManagerRoundTripTest.
Logs and a native paused-catalog capture are in `tmp/placement_haul_review/`.

Manual check: craft a crude workbench with a stockpile active, pause after a
dwarf reserves or picks it up, then use Place → Workshops → Crude workbench.
It should remain available; confirming its location supersedes storage hauling.
