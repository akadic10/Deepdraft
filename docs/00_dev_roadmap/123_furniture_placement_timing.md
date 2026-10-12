# 123 — Furniture placement follows its animation

Implemented 2026-10-11 after the log-bench playtest report.

Ordinary finished furniture used to wait for a generic two-second build timer,
showing the stationary carry pose, then play a 0.65-second set-down. It now starts
that set-down as soon as the dwarf reaches the placement stand and installs at
the animation's end. Destination time at 1× changes from 2.65 to 0.65 seconds.
Pickup and travel retain their existing timing.

## Placement review

| Placement family | Arrival behavior |
|---|---|
| All 25 ordinary furniture designs | One 0.65-second set-down, using `hauling.deposit_time_s` |
| Wall furniture | Same duration, raised handoff at its mounted position |
| Log bridge | Existing eight-second animated assembly and saved work progress |
| Ladder section | Existing two-second animated assembly per section |
| Mature shrubs | Existing 1.25-second continuous planting motion |
| Cuttings | Existing three-second continuous planting motion |
| Water stones | Same immediate set-down for placement; packing retains its work step |
| Crafting inputs/results | Existing ingredient delivery and actual recipe work |

`DwarfAgent._begin_fetch_work` sends ordinary sources straight to the shared
deposit phase. Only sources that own `remaining_work` enter the timed work phase;
bridge/ladder, crafting and planting progress already drive their own animation.
The obsolete global `furniture.build_time_s` setting and fallback are removed.
Ordinary uninstall timing is unchanged.

`FurnitureGhostComponent.placement_contact` targets the closest floor cell of
the rotated designation, or the front of a wall mount at its installed height.
The dwarf turns to that contact rather than lowering the crate along its last
walking direction. Large furniture can be reached from its nearest edge. The
worker stays at the existing safe stand outside floor furniture occupancy.

The physical packed item remains carried through lowering/release. Only the
final valid-site commit consumes it and creates installed furniture. Pause and
clock speed affect pose and completion together. Cancellation, interruptions and
lost support return the intact item; current save ownership and material identity
are preserved, with no save-format additions.

## Verification

`FurniturePlacementAnimationTest` covers all 25 ordinary designs and extra
rotations of benches, beds, double doors and wall torches: 37 placements. It uses
actual pickup, task dispatch and installation. Checks cover immediate movement,
single-animation timing, planted boots, correct contact, pause/2×, saved cargo,
final consumption, safe builder position, cancellation, invalid final support,
interruption/resume and an already-at-stand handoff. It passes headless and in
Godot's native renderer. Bench and wall-torch captures plus `checks.json` are in
`tmp/furniture_placement_animation_20261011/`.

Related passing suites: HaulingAnimationTest, WorkerCraftingTest, LogBridgeTest,
LadderTest, ShrubPlantingAnimationTest, WaterStoneLifecycleTest,
PlacementHaulPriorityTest, CraftMaterialTest and SaveManagerRoundTripTest
(including 169 malformed snapshots and backup recovery). The save fixture now
waits for wildlife initialization as well as terrain; otherwise it could inspect
ducks before their first water-dependent population tick. Six changed scripts
have clean editor diagnostics. The runs use isolated profiles and never modify
the player's saves.
