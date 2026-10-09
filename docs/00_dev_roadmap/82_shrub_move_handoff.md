# 82 — Keep shrub Move work with its nearby worker

2026-10-09. Follow-up to milestone 81 after the player showed Furlok finishing
uprooting a strawberry and becoming idle while Rogan walked over to collect it.

## Cause and result

Milestone 81 fixed selection for the UPROOT_SHRUB stage, but Move's subsequent
FETCH_BUILD lease still used the ordinary per-worker queue scan. Completing
uprooting appended Furlok behind Rogan in the idle queue. The next lease chose
Rogan without comparing their positions at the packed plant.

For an exact-plant Move, the fetch stage now compares available workers at the
plant's actual, walkable pickup sides. The uprooter has a continuation preference
when already at a pickup side, including ties with another adjacent worker.
This keeps the ordinary sequence with one worker: uproot, pick up, carry, replant.
The preference does not pull a worker away from existing or higher-priority work,
wake sleepers, or choose a distant former worker after interruption. A nearby
reachable replacement can finish when needed.

This applies to the three mature shrub species through their shared Move source.
Ordinary species-based Place requests, cuttings, furniture and stored-item fetches
retain their existing contracts. Uproot without Move still produces a plant for
ordinary hauling/storage.

## Implementation

- `SurfaceDetailManager` reports the completing uprooter to the existing Move
  plan. `ShrubPlantingComponent.continuation_worker` is transient and clears when
  the fetch is assigned or released. It is not a saved worker reservation.
- `move_worker_quote()` supplies the existing exact-item claim's valid pickup
  sides without changing ownership. A claim/position/stand/preference signature
  and idle membership version invalidate stale comparisons.
- `TaskManager` compares eligible idle workers inside the normal FETCH_BUILD
  priority bucket. It checks worker-to-pickup and pickup-to-destination routes
  before assigning; ranking and the two probe stages resume under the existing
  time/probe limits. Other workers and pickup sides are tried before backoff.
- A worker chosen later in the idle snapshot is skipped by subsequent visits,
  preventing a second assignment from replacing the Move. Earlier idle workers
  remain available for other jobs.
- After an interrupted carry, release routing immediately reclaims the dropped
  exact plant for its Move. This closes the gap before the controller's throttled
  lease refresh and allows the next wake to compare the real dropped pickup.
  Cancelling the plan still releases its claim and identity promise.
- Navigation changes and scene reset clear the new comparison. Save formats,
  priorities, yields, growth and work durations are unchanged; no new global
  classes or autoloads were introduced.

## Verification

`ShrubMoveHandoffTest` first reproduced the reported older-idle-worker handoff
with two real dwarves and a real strawberry Move (`before.log`). It now verifies:

1. The same worker completes uprooting, pickup, carrying and replanting, with
   one exact plant at the destination and no duplicate or bonus drop.
2. Equal-distance adjacent workers keep the uprooter; pickup and delivery checks
   can span separate one-probe wakes without prematurely transferring the claim.
3. Sleep during comparison and higher-priority work permit a replacement, which
   completes the Move without stealing an active job.
4. Cancellation during comparison leaves one recoverable packed plant, while
   scene reset discards the transient comparison.
5. Interrupted carrying preserves plant identity, clears the old preference,
   immediately reclaims the dropped plant and selects a nearby replacement.
6. An unreachable nearby worker does not hide another worker; an unreachable
   destination backs off safely and resumes after its route is opened.

SurfaceWorkSelectionTest, ShrubTransplantTest, ShrubCuttingTest,
HaulingSelectionTest and FurniturePlaceTest pass. SaveManagerRoundTripTest also
passes manual save/load, autosave and backup recovery. Evidence is recorded
under `tmp/move_handoff_review/`.

Manual check: restart the game, leave one dwarf beside a mature shrub and another
farther away, then choose Move and place its destination. Watch the nearby dwarf
through replanting. Repeat while interrupting or putting that dwarf to sleep to
check safe takeover.
