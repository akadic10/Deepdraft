# 63 — Loose item support and Object explorer

Implemented 2026-10-07 following a playtest screenshot of hovering Rough Stone
and an Object explorer that still used the older window treatment.

## Loose goods

`ItemDropManager` already scanned down to bedrock when spawning mining loot, but
never reconsidered the floor after later mining. Removing that supporting block
left an existing item at its old height. Save restoration also retained that
unsupported height. This reproduces the reported symptom; the precise session
that first exposed it was not established.

The manager now listens to exact `WorldData.block_changed` removals. Changes are
coalesced into columns, then loose items in those columns settle onto the first
solid terrain below them. There is no continuous physics/polling loop, terrain
rebuild, or response to camera slicing. Bedrock remains the lower boundary.
Actual imported rough-stone mesh bounds are checked against the resulting floor.

Before moving a reserved item, `TaskManager.invalidate_dwarf_task()` aborts the
worker's stale pickup/path and releases its lease through the existing protocol.
Pickup and destination reservations are freed, any carried cargo is dropped
safely, and the goods can be matched again. Stored and carried items retain their
existing owners and do not participate in loose-item settling.

Loading an older save settles unsupported loose positions after mined terrain
has been restored. Horizontal position, yaw, item identity and crate quantity are
preserved. Interrupted cargo also checks its floor when returned to loose goods.
Fractional saved carrier positions are never lowered into a solid step. No save
schema or authoritative quantity fields changed.

Restart play mode to load the corrected scripts. Reloading a save repairs its
already-hovering loose goods; no manual save-file edit is needed.

## Object explorer

The shared window uses `UITheme.apply_catalog_window()`, matching Slice/Rooms:
gold edge, wood-toned title bar and larger serif title. Generic subjects have an
inset identity card with a copper kind label and prominent object name. Facts and
description scroll together, with actions remaining below the scroll. Selection
outlines share the copper accent. Dwarf/storage content, provider-owned actions,
remembered positions and world-input exclusion remain intact.

Native resource/tree captures cover 960×540, 1280×720 and 2560×1440 in
`tmp/object_explorer_review/cabinet_fix/`. The existing explorer fixture's container
assertions were updated to inspect the shared storage panel introduced in doc 59,
instead of its now-hidden legacy generic rows.

## Verification

- `LooseItemSupportTest`: reproduced the unsupported-height failures before the
  fix; covers removed ledges, actual mesh grounding, preserved quantities/XZ/yaw,
  deep bedrock fallback, slice visibility, old save positions, fractional steps,
  real reserved pickup interruption, freed claims, rehauling and carried ownership.
- `ObjectExplorerTest`: native rendering, all 12 tree stages, fixed rows, exact
  picking, terrain/slice/tool guards, live resource quantities, container actions,
  seasonal replacement and the three cabinet viewport sizes.
- Regression checks: `HaulingAnimationTest`, `HaulingCapacityTest`,
  `DwarfInspectorTest`, `StorageFilterTest`, `SaveManagerRoundTripTest`.

Tests use isolated APPDATA/LOCALAPPDATA under their review directories; player
saves and window preferences are untouched. Evidence is in
`tmp/loose_support_review/`, `tmp/object_explorer_review/cabinet_fix/`,
`tmp/dwarf_inspector_review/support_fix/` and
`tmp/storage_filter_review/support_fix/`. Some headless fixtures retain the
existing SkyController startup warning about the missing scene Environment.
No new global class or autoload was added.
