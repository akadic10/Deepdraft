# 113 — Early log bridges

Implemented 2026-10-11, following the requested starter river crossing.

## Player flow

- Craft → Rudimentary → Access → **Log bridge kit**. An ordinary Worker uses
  one allowed raw log at an installed crude workbench (12 seconds).
- Place → Access → **Log bridge**. Aim at either tile of a two-block riverbank
  landing; the preview automatically aligns across the water. Bank-face hits
  snap to the lip, and submerged riverbed hits search the nearest bank within
  one possible span. R prefers another direction where a valid crossing exists.
  The preview scans forward and quotes
  the gap and one-kit cost. Click to reserve the kit and designate the crossing.
- A Worker physically collects the kit, stands on the bank nearest them, and
  installs the complete deck (8 seconds). No route across the water is required.
  Either landing can be used, regardless of which bank anchored the preview.
- Inspect a pending bridge to cancel it; Place's Undo also releases its claim.
  Inspect an installed bridge to dismantle it and recover the kit (4 seconds).
  Cancelling dismantling reopens the existing deck without generating an item.

## Placement and traversal contract

Width is two terrain blocks. Clear spans are 1–5 blocks, plus one solid landing
row on each end: a maximum reservation of 2×7. Both lanes must first encounter
the opposite bank at the same distance and elevation. Diagonal, sloping, wider,
and unsupported crossings are rejected with a placement hint. Each gap column
must contain standing water at placement; subsequent drying does not erase the
structure. Three blocks of head clearance, clear landings, world/slice bounds,
and conflicts with furniture, ladders, plants, stones, zones and other bridge
plans are checked. No new dam/terrain blocks are written.

Only completed decks register floor supports with NavGrid. Those supports use
ordinary walking, diagonal corner checks, route invalidation and hauling.
Placed-entity boxes occupy the deck slab below the walking surface, preventing
actors underneath from clipping through it; water simulation ignores these
structure supports and continues unchanged. Loose or interrupted cargo can rest
on the deck, including after loading. Removing a deck settles loose goods using
the same support-loss rule as excavated terrain.

Closing removes entry permission without removing physical support. Dwarves on
the deck safely release tasks/cargo and walk to a surviving landing, including
idle or sleeping occupants. Removal waits for their bodies to clear. Terrain or
clearance damage cancels unpaid plans; paid decks close, retain occupied support,
then recover one kit when empty. If no safe exit remains, support stays until the
occupants can leave. Ghosts never provide traversal. Release keeps one pending
lease and accumulated installation/removal work, with no duplicated kit or job.

## Ownership, art and saves

`BridgeSystem` is a scene-owned child of FurniturePlacementController; that
controller remains the sole reader of furniture JSON. The bridge uses the
existing FETCH_BUILD/UNINSTALL pipelines through BridgeBuildComponent and
BridgeRemovalComponent. Recipe, item, Place catalog and timing definitions are
JSON. No new autoload or global script class is required.

`tools/generate_log_bridge.py` exports five span models and one compact timber
kit. Four split logs, dark seams, end grain and underside cross ties use the
existing oak palette at eight voxels per terrain block. Baked scale is 0.125,
root scale is one, and there are no mesh colliders. The deck top matches the nav
floor; landing tails are buried slightly to avoid coplanar terrain flicker.
The Place/Craft/Inventory thumbnail is generated from the actual model.

Current saves require the `bridges` owner at restore priority 42, before loose
goods and dwarves. Namespaced identity, bank, yaw, span, completed state, mode,
partial work and next ID round-trip. Claims and jobs are reconstructed. Older
development saves without this section are not migrated, per project policy.

## Verification

- Opposite-bank delivery fix (2026-10-11): the saved plan at (503,43,276)
  required its anchor bank even though all five colonists and the stored pine kit
  were across the river. Both landing rows now enter the existing dwarf-relative
  stand selection; builders face into the span from their actual work cell.
  BridgePlacementInputTest now clicks the opposite bank and verifies real pickup,
  work from the colony bank, facing, exact kit consumption and traversal. The
  same test failed before the fix. Existing plans use the corrected stands when
  loaded; no replacement order or save migration is needed.
  An isolated copy of the player's save completed that unchanged order, consumed
  its single stored pine kit and opened the crossing. LogBridgeTest and LadderTest
  also pass; reproduction logs are in `tmp/bridge_delivery_20261011`.
- BridgePlacementInputTest (2026-10-11 follow-up): actual terrain raycasts and
  mouse clicks on both banks, a vertical bank face and submerged riverbed now
  resolve to a valid landing without hand-setting yaw. The resulting plan is
  fetched/built by a real worker. Stationary obstruction changes, slice limits,
  preview/click agreement, Undo and exact kit consumption pass. The original
  test injected coordinates and yaw and therefore missed the picker problem.
- The current playtest seed 3495149338 was regenerated in an isolated profile:
  16 natural sites near the spring auto-align, and a real mouse click places a
  bridge plan. This does not load, change or overwrite the player's game/save.
- LogBridgeTest: all four rotations and 1–5-block spans, oversized/uneven gaps,
  clearance, permission, real crafting and delivery, preview/catalog/Undo,
  interrupted work with exactly one lease, navigation/hauling, cargo support,
  JSON round-trip, closing/evacuation, cancellation and damaged-bank recovery.
- SaveManagerRoundTripTest: three natural river sites with unfinished, complete
  and dismantling bridges survive full save/load, autosave and backup recovery.
- LadderTest, LadderMiningTest, NavigationRegressionTest,
  FurnitureAssignmentTest, WorkerCraftingTest, PlacementHaulPriorityTest,
  ItemPermissionTest and LooseItemSupportTest pass.
- Native placement-menu/ghost and finished-deck captures reviewed in
  `tmp/log_bridge_20261011/`; 120 production scripts have zero LSP diagnostics.
  The input follow-up's native captures/logs are in
  `tmp/bridge_placement_20261011/`; all rotations also exercise automatic bank
  alignment while retaining the five-block limit.

Start a fresh development world to playtest this save-format addition. Longer
bridges, sloped landings, piers, stone bridges and construction over dry chasms
remain outside this starter bridge milestone.
