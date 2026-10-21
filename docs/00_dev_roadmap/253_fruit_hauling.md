# 253 — Consolidate fruit during hauling

Implemented and recovered after a power interruption, 2026-10-19.

## Finding and behavior

Harvesting produced several small fruit baskets. Every basket consumed the
entire four-point carry budget, and a haul's pickup list never expanded along
the delivery route. A controlled three-tree harvest produced 16 apples and
required three deliveries; the first worker carried six apples past another
six-apple basket only one block away. Harvest priority 50 also precedes haul
priority 40, explaining why picking a batch can leave fruit on the ground first.

A worker now combines matching edible produce into one carried basket, up to
the item's capacity (24 for current fruit). Item key and material must match;
forbidden, already claimed, unique-instance and unreachable goods are excluded.
The original four-point carry budget, non-food crate behavior and job priorities
remain unchanged. This is an optional haul optimization, not a harvest-to-haul
continuation or a promise that every nearby basket will be collected immediately.

## Ownership and routing

`TaskManager` passes its successful pickup/delivery proofs to `DwarfAgent`.
`StorageComponent` and `FruitHaulPlanner` reserve compatible sources along that
route, using legal ground-handling stands and proven short out-and-back spurs.
Planning runs at assignment and completed-pickup boundaries, never every walking
frame. A missing proof or expired budget leaves ordinary pathfinding/delivery
available. Paths still use the normal worker navigation validation.

The hauling JSON sets eight total extra walking steps per load, a 750-microsecond
optional planning budget, 128 nodes per side-route probe, a 512-cell route prefix
and up to 16 candidate probes. Distant or costly pickups can be left for another
trip. This avoids expanding every route cell into a large spatial corridor.

Each source retains an exclusive claim and exact destination quantity tokens.
Tokens can span partially occupied and empty storage slots. At hand contact,
only the reserved portion leaves the source; its count joins the same carried
node. One hand supports the basket while the other gathers. Leftover source
fruit stays on the ground. Delivery validates all constituent tokens before
distributing the basket across its reserved slots. Cancellation releases all
claims and drops actual carried contents once.

No save-format change is needed. Sources and the one carried basket serialize
their actual counts on either side of contact; existing restoration puts cargo
at the carrier's feet. Routes, top-up animation and reservation groups are
transient. No player-save files or GLB assets were changed.

## Verification and power-loss recovery

The first four regression results survived the interruption. Recovery completed
the remaining checks and found a real missed fallback: `Dictionary.get` returned
an untyped empty array from `fruit_pickup_path`, whose return requires
`Array[Vector3i]`. A missing cached path now explicitly returns a typed empty
result, allowing ordinary routing. The regression includes a direct fruit pull
without a scheduler proof. A subsequent copied-save replay exits without script
errors.

`FruitHaulingTest` uses real workers, storage, scheduler, navigation and handling:

- Three sources with 6 + 7 + 9 apples deliver 22 apples in one physical basket.
  Quantities are checked on every simulated frame and both top-up contacts occur.
- A 20 + 10 load collects exactly 24 and leaves six; another worker cannot steal
  the claimed source. Matching fruit fills partial and empty destination slots
  in both ground stockpiles and container storage.
- Different fruit, forbidden goods, blocked approaches and excessive detours
  are skipped. Cancellation before/after contact, JSON snapshots, storage-filter
  changes and unrelated permission edits preserve all goods and clear claims.
- An expired planning deadline returns immediately; an uncached pickup returns
  safely. Native before/after-contact captures show the single supported basket.

The original three-tree reproduction now delivers all 16 apples in **two trips**;
the first carries 12. The farther four apples remain outside the allowed detour.

A copy of the player's quicksave was loaded in an isolated profile and replayed
for 600 simulated seconds. All four initial loose/restored fruit baskets were
cleared; five deliveries brought stored berries to 12, then normal food behavior
withdrew a portion, leaving 11 stored. No loose fruit remained. That save's
spread-out sources and concurrent claims did not produce a combined load (largest
observed basket: four); consolidation is demonstrated by the controlled worker
fixtures, not inferred from this older save. The four original save hashes match
the pre-change checkpoint, as do all 382 surviving production GLBs.

Eleven relevant fixtures passed: FruitHaulingTest, HaulingCapacityTest,
HaulingSelectionTest, HaulingAnimationTest, ProduceCrateTest, StorageFilterTest,
ItemPermissionTest, HaulingSharedRoutesTest, HaulingRouteFairnessTest,
PlacementHaulPriorityTest and SaveManagerRoundTripTest. StorageFilterTest was run
with its required isolated native profile; its first ordinary headless invocation
correctly rejected the missing isolation. ProduceCrateTest and StorageFilterTest
now use synthetic test storage instead of retired furniture definitions. Fruit
and capacity tests join the default reliability gate.

Evidence: `tmp/fruit_hauling_review_20261019/review.json` preserves the baseline;
`tmp/fruit_hauling_fix_20261019/` holds source backups, recovery logs, controlled
report, saved replay, native captures and the completion checkpoint. Storage
inspector evidence is `tmp/storage_filter_review/fruit_recovery.*`. Earlier failed
fixture/replay logs are retained and superseded by the final passing results.

Restart Play to load the corrected scripts. No export or commit was made.
