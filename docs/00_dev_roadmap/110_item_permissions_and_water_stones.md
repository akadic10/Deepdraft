# 110 — Item permissions and movable water stones

Implemented 2026-10-10 after the user approved per-object Disallow and deliberate
stone relocation. A later scenario may award another pair; no scenario is added now.

## Player behavior

- Loose goods and individual stored stacks have Allow/Disallow. Ordinary goods
  start allowed. The natural wet and dry stones start disallowed.
- Disallowed goods remain visible in inventory totals and inspection, but cannot
  be hauled, reserved for crafting/placement, withdrawn, or collected for promotion.
  Stored stacks have their own toggle in Contents; storage acceptance filters
  remain separate. Crates with different permissions never merge on restoration.
- Placed water stones keep working regardless of permission. Allow alone does
  not turn a functioning stone into an automatic storage-hauling target.
- An allowed placed stone offers **Move** and **Pack for storage**. A dwarf
  reaches it, packs it, then carries the real item. Move reserves that exact stone
  for its destination. Packed stones can be hauled normally; **Place → Water**
  uses an available allowed packed stone. Their inventory artwork matches the ore models.
- Packing stops the water effect. Packed, carried and stored stones remain
  inactive. Completed placement restarts the effect at the new location. A
  reachable dry working position is required; dwarves cannot collect an
  inaccessible submerged stone through deep water.
- Disallow cancels conflicting pickup/work and a stone's packing/move order.
  Carried goods return to the worker's feet with the flag intact. Interrupted
  packing retains progress and leaves the source active until packing completes.

## Ownership and water

`WaterManager.stones` owns persistent identity, kind, placed state, base/intake,
head limit and packing progress. `WaterStones` owns the placed models and
`WaterStonePacking` work sources. Packing reuses UNINSTALL; placement reuses
FETCH_BUILD and exact-instance promises. Loose nodes, cargo and storage stacks
own the physical packed form. One identity always has one physical owner.

The initial pair keeps the existing source/intake coordinates, rates and head
limits. The wet stone adds at most 2 blocks³/s; the dry stone removes at most
8 blocks³/s while retaining the natural lake's Y19 surface. Untouched hydrology
is unchanged. Relocated wet stones supply their base cell up to their top;
relocated dry stones retain the receiving surface at placement, or their top in
a dry basin. Removing support settles a placed stone and its effect together.
Models do not add terrain, water displacement, colliders or navigation occupancy.

`WaterManager.grant_stone(kind, cell, disallowed=true)` creates a uniquely named,
inactive physical item for a future reward/scenario. Extra pairs use all the same
work, permission and save paths; effects are evaluated in deterministic ID order.
No extra starting stones, recipes, acquisition event or reward balance are introduced.

`ItemPermission` is a small shared predicate, not a new global inventory owner.
The permission is carried by node metadata or its owning storage stack and saved
with that owner. Container save entries now preserve every physical stack, so
same-type crates can retain different permissions. Stone identity/progress lives
in the existing water section; destinations live in furniture plans. Carried
stones restore loose at dwarf feet and are reclaimed by their standing Move plan.
Validation rejects malformed permission fields, missing/duplicate stone owners,
invalid stone kinds/locations, and conflicting identity-specific move plans.
Older development saves need no migration and may be rejected.

## Verification

- `ItemPermissionTest`: real haul before/after contact, safe cargo release,
  selection gates, ground/chest/shelf withdrawal, blocked crate preservation,
  independent stack flags and native Contents toggles at 960×540 and 2560×1440.
- `CraftingPermissionTest`, `ToolPromotionTest`: forbidden inputs/tools,
  interruption during approach/work/pickup, conservation and successful reuse.
- `WaterStoneLifecycleTest`: real packing, Move, cancellation, inactive cargo,
  relocated supply, independent extra sources and JSON restoration. Native
  Allow/Disallow/Pack/Move inspection at both resolutions and compact Water catalog.
- `SaveManagerRoundTripTest`: full scene replacement and manual/autosave backup
  recovery, permissions in loose/ground/container state, five stone identities,
  active packing progress/destination, and inactive carried-stone restoration.
- `StorageFilterTest`, `ProduceCrateTest`, `PlacementHaulPriorityTest`: existing
  storage, quantities, physical slots, handoff and cancellation behavior.
- `WaterStoneHydrologyBaseline --compare`: identical initial water and exact
  continuation over 100 steps; presentation/identity metadata excluded from hash.
- `WorldTerrainStartupTest`: visible geometry across all 1,024 tiles at startup,
  local update, slice/save/reload and full invalidation.

Logs and native captures are under `tmp/water_review/`. Restart Play for the new
scene behavior. No new autoload or global class was added by this milestone.
