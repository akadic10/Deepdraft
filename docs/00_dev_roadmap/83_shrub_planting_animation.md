# 83 — Immediate shrub planting animation

Implemented 2026-10-09 after the player reported a dwarf standing at a shrub's
destination before beginning the planting animation.

## Cause and result

Planting accumulated three seconds of work while displaying the stationary carry
pose, then played the ordinary 0.65-second deposit animation. Replanting therefore
took about 3.65 seconds at the destination, with movement only at the end.

Mature blueberry, elderberry and wild-strawberry replanting now takes **1.25 seconds
total at normal speed**. Arrival immediately begins one reach/lower/release
animation. `wild.transplant.plant_seconds` in each species JSON defines its full
duration. Uprooting remains three seconds. Cutting planting retains its configured
three seconds, with animation throughout that work instead of the stationary wait.

## Implementation

- `DwarfAgent` begins the planting pose when it reaches the work stand, whether
  arrival finishes a route or the dwarf is already there. Plant work progress
  drives the existing bounds-aware carry lowering pose.
- The packed plant's bottom center reaches the actual destination ground. Both
  feet remain planted while the hands follow the cargo and release it.
- Planting completes directly from its work phase, without adding a separate
  `FETCH_DEPOSIT`. Ordinary hauling, furniture installation and crafting retain
  their existing execution paths.
- Pausing and clock speed affect work and pose together. Interruptions preserve
  accumulated work; returning starts a fresh reach over the remaining duration.
- The worker owns the physical cargo throughout the animation. The final site
  check still precedes consumption. Cancellation leaves the intact packed plant,
  and saving still records its exact identity as carried goods until completion.
- No new global classes, autoloads or save format changes were introduced.

## Verification

`ShrubPlantingAnimationTest` exercises real Move tasks for all three species. It
checks visible lowering within 150 ms, fixed feet, cargo identity in saved worker
state, pause/speed, exact ground contact, completion within the configured duration,
no second deposit phase, interruption/resumption and cancellation without copies.

The test passes headless and in the native D3D12 renderer. Start, middle and release
captures were generated for each shrub, with representative captures visually
inspected. ShrubMoveHandoffTest, ShrubTransplantTest, ShrubCuttingTest,
HaulingAnimationTest, FurniturePlaceTest and WorkerCraftingTest also pass. Logs
and captures are under `tmp/shrub_planting_review/`.

Manual check: restart the game, Move a mature shrub nearby and watch arrival at
its ghost. The dwarf should immediately lower the shrub and finish in about
1.25 seconds at 1×. Repeat using a stored whole shrub through Place → Plants.
