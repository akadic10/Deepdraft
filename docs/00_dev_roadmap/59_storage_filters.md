# 59 — Storage filters

Implemented 2026-10-06 after approval of the interactive storage study. Stonehearth
provided the interaction reference; the native implementation uses Deepdraft's
shared Hearth & iron theme and existing item thumbnails.

Presentation updated 2026-10-12: ground zones now use the same framed window,
wood-toned title bar, inset identity card, serif object name and body spacing as
Object explorer. The zone window is titled Storage inspector; its card identifies
the selected zone. Containers use that same identity card inside Object explorer.
Actions stack below the controls, and Contents contracts for short lists while
long lists and Filters remain scrollable. Selection, hauling and saved window
positions retain their existing owners.

## Player behavior

- Installed containers offer **Move**, using the furniture destination preview.
  Filters follow the exact packed container; contents empty as loose goods at
  its old location and can be hauled again. Cancelling before packing leaves it
  installed. See [132 — Furniture Move](132_furniture_move.md).
- Ground zones, chests, barrels and shelves share `StorageInspectorPanel`.
- Filters and Contents are separate tabs. Capacity always shows occupied
  cells/slots separately from goods inside crates.
- Whole categories and exact item identities combine: All stone + Oak Log is a
  valid rule. Oak Log does not imply Oak Stave, acorns or other wood.
- Individual exceptions to a category persist. A dash identifies a partially
  selected category. Clicking that category selects all; clicking a fully
  selected category clears it. Selecting a category includes future items
  with that category's tag.
- Accept all goods and Clear all filters apply immediately. Closing the panel
  does not confirm or revert anything. New storage accepts all existing categories.
- Contents groups actual goods by item and material, sorted by displayed name.
  Separate crates contribute their full unit counts; wood variants remain distinct.
  Rejected goods stay visible with one Awaiting relocation note per group and
  still count toward capacity. This is a derived view, not merged physical stock.
- Allow/Disallow applies only outside storage. Contents and stored-item inspection
  have no permission controls; stored goods are available colony stock. Storage
  filters continue to control what belongs here and what should relocate.
- The scroll area contracts on smaller displays; actions and acceptance summary
  stay outside it. Native title dragging, saved placement, tool-input isolation,
  zone removal, and furniture uninstall keep their existing behavior.

## Ownership and hauling

`StorageComponent` owns category tags, exact inclusions and exclusions. Item
definitions still belong to `ItemDropManager`. `UIRegistry` alone reads
`data/ui/storage_filters.json`, which supplies presentation categories.
The inspector holds no second inventory or pending copy of the rules.

Acceptance is checked when seeking cargo, reserving incoming space, picking up,
and committing a delivery. A filter edit cancels incompatible HAUL bundles
through `TaskManager`; a worker carrying goods drops them safely at its feet.
Deliveries that still match continue. Ordinary loose-item bundling keeps its
existing carry-cost budget.

When a destination cannot find compatible loose goods, it may pull a rejected
stack from another registered storage. This uses the existing HAUL lease and
pickup/deposit animation. One outgoing claim protects each physical source
stack; an incoming token reserves the destination quantity first. A produce
crate can split to fill remaining space. Unclaimed quantities remain available
to ordinary fetches.

Before pickup contact, all goods remain in the source and are saved there. A
hidden visual supplies the reach pose bounds, but never joins loose/stored/
carried inventory or saves. At contact, the source withdraws the real quantity
and the dwarf becomes its owner. Shelf visuals update with the source counts.
The usual carried-item save and interruption paths then apply. Relocations
currently move one physical stack per trip; ordinary loose hauling still bundles.

Claims are released on cancellation, failed paths, storage removal, and missing
workers. Source registration, current acceptance and quantity are rechecked at
pickup, so reversing a source filter or removing it cannot duplicate a withdrawal.
Suspended containers do not supply relocations. Removing a destination releases
its outgoing source claim even if its assigned worker no longer exists.

`StockpileManager` wakes on rule edits, claims, withdrawals, deposits, registration
and task events. Candidate scans run during these throttled wakes or HAUL pulls,
not every frame. Colony inventory and Place availability subtract outgoing claims
without subtracting them from physical ownership totals.

## Persistence

Both zone and installed-furniture records save `storage_filter` with `tags`,
`items`, and `excluded_items` arrays of stable strings. Old zones migrate their
`filter_tags`; missing rules on old containers mean all default categories.
Explicit empty arrays mean accept nothing. Existing incompatible contents are
restored intact, and tasks/claims are rebuilt rather than serialized.

No new global script class or autoload was added, so this feature does not
require a project reload for global-class registration.

## Verification and handoff

- `StorageFilterTest`: exact/mixed/excluded rules; legacy defaults; actual native
  clicks; compatible and incompatible delivery edits; real dwarf relocation in
  both directions; partial crates; concurrent claims; source reversal/removal;
  orphaned destination cleanup; shelf visuals; zone/container save restoration;
  shared container selection; dragging and world-input isolation.
- `ItemPermissionTest`: grouped material variants and produce quantities, live
  withdrawals, occupied-slot totals, relocation notes, ground/chest/shelf contents,
  outside-only permission controls and available stored goods after restoration.
  Updated native captures: `tmp/storage_contents_20261011/` at 960×540 and 2560×1440.
- Native renders inspected at 960×540, 1280×720 and 2560×1440. Captures are under
  `tmp/storage_filter_review/`. Smaller displays preserve a full tile row.
- Regression coverage: `ProduceCrateTest`, `HaulingAnimationTest`,
  `HaulingCapacityTest`, `ColonyInventoryTest`, `FurniturePlaceTest`,
  `DwarfInspectorTest`, `ZoneWindowTest`, and `SaveManagerRoundTripTest`.
  The save test includes mixed rules and an exclusion through actual scene reload
  and backup recovery, alongside unchanged physical contents.

Run the new test with APPDATA/LOCALAPPDATA isolated under
`tmp/storage_filter_review/`; append `-- --capture` without `--headless` for native
screenshots. Test saves and UI preferences must not use the player's directory.

Playtest by clicking two storage areas, clearing both, and assigning Stone to one
and only Oak Log to the other. Change a filled storage's filters and watch a dwarf
move the rejected goods when another storage accepts them. With no destination,
the original storage should retain the goods and show Awaiting relocation.
