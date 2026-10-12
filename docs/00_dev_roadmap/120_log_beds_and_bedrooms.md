# 120 — Log beds, bedrooms and dwarf readability

Implemented 2026-10-11 following the first underground settlement playtest.

- **Log bed:** Workers craft one at a crude workbench under Rudimentary → Camp
  furnishings, using four logs of the same wood and 16 seconds. It uses the full packed crate,
  then installs as a four-by-three-block bed. Rough bark rails and cross logs
  support loose hay, dried leaves and an extra hay mound at the head. The native
  eight-voxel art has no upholstered mattress, sewn pillow or folded cloth. Wood identity,
  palette and appeal survive crafting, hauling, installation and saves.
- **Bed use:** Tired dwarves try reachable beds within 48 blocks, preferring
  bedrooms. One sleeper claims each bed for that sleep period. Normal navigation
  reaches a clear mattress-side access cell; only the visual pose moves onto the
  bed. Lying, breathing, closed eyes, snoring and wake transitions are shared with
  ground rest. Existing Dwarven Beds also work. No free reachable bed means the
  existing sheltered ground-rest fallback.
- **Lifecycle:** Claims are transient. Wake, removal, an uninstall designation,
  support loss or actor teardown releases them. Load reconstructs a claim from
  the saved access floor without resetting the remaining sleep duration. Search
  advances one bed approach per tick to bound pathfinding work.
- **Bedrooms:** RoomManager derives `room_type`, `bed_count` and `light_count`
  from the sealed air volume and installed furniture. A bedroom requires at
  least one whole bed footprint inside, a door, complete enclosure and an inside
  light. Outside lights and unfinished furniture do not count. Removing any
  requirement revokes the classification. The Rooms inspector explains what is
  missing; temperature remains a separate property.
- **Firelight:** Campfire and wall torch energy are now 3.2, log torch 2.6:
  twice their previous energy. Ranges, heat units, shadows and sound are unchanged.
- **Readability:** Dwarves retain the logical 1×1×3 navigation footprint and
  their oversized appearance. A faint warm silhouette continues the body where
  nearby terrain or ladder rails hide it. A bounded local cover query excludes
  self-occlusion; the shader uses actual scene depth and fades before 2.5 blocks
  of cover. Clear ground, deep rock, portraits and sliced-out dwarves get no
  silhouette. This addresses visual readability, not physical body collision.

Owners: FurniturePlacementController loads furniture definitions; TaskManager
loads rest/readability tuning; RoomManager owns derived room classification;
DwarfBedRest owns bed selection/claims; DwarfRestBehavior owns poses;
DwarfReadability owns the optional cover pass. No new autoload or save fields.
Permanent bedroom ownership and a sleep happiness thought followed in
[121 — Personal bedrooms](121_personal_bedrooms.md). Bedding production remains
future work; this starter recipe does not require an unavailable textile chain.

The rudimentary art revision (2026-10-11) removes the finished headboard and
replaces the tidy bedding with ragged stalk edges and loose tufts. Its collision
envelope is now one block high; the 4×3 footprint and .75-block sleep surface
remain. Material palettes affect timber only. The placed-model catalog icon is
regenerated with `FurnitureCatalogThumbnails -- --only=log_bed`. Native renders
from `tools/LogBedPreview.gd` are in `tmp/rudimentary_bed_20261011`; BedroomTest
checks real crafting, delivery, rotated sleep poses and restoration.

The four-log cost was increased after playtesting. Workers collect each physical
log before crafting; cancellation and loading preserve staged and carried goods.
Only a complete matching-wood batch starts, and active workers' remaining timber
needs prevent other crafting orders from claiming the same supply. The cost and
matching-wood requirement appear on the recipe card. `TimberBatchTest` covers
partial/mixed stock, deliveries, interruption, save reconstruction, storage,
maintain targets, competing workers and compact menu layouts.

Verification: BedroomTest exercises actual crafting/delivery, wood identity,
each room requirement, all four rotations, exclusive sleepers, bedroom preference,
unreachable-bed fallback, wake/removal and restore. Native captures inspect the
bed and bedroom UI at 1280×720 and 960×540. DwarfReadabilityTest compares native
pixels with/without wall, ladder, open ground and deep rock, plus slice/navigation
guards. RoomLightingTest checks real generated-mine darkness, firelight, doors,
fog and slices. Ground sleep, hauling, dwarf inspector and full save/backup
regressions also pass. Review captures live in `tmp/bedroom_20261011`.
