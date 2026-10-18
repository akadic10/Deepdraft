# Construction materials crates

2026-10-17. The user approved replacing repeated one-stone construction trips
with project staging in a temporary materials crate, retaining the existing
dwarf carrying capacity. This implements the construction discussion in 193
and supersedes the delivery/work loop in 127.

Each structural Stone block designation automatically places one open wooden
crate on nearby clear, supported ground outside the blueprint. It is temporary
packaging, requires no separate crafting order and disappears at completion or
cancellation. Its real one-voxel occupancy prevents overlapping construction.
Placement avoids plans, storage, furniture, barriers, stairs and narrow passages;
an open ring provides delivery access. If no suitable patch exists within six
voxels, the order reports no delivery access and retries. Losing support safely
releases haulers, returns staged stone and searches for another location.

Up to two workers deliver stone from loose goods or existing storage. They use
the existing `hauling.carry_capacity` and per-item `carry_cost`, currently four
points and one point per rough stone. Heavy-cargo movement and pickup/deposit
animations are unchanged. A six-block project can receive loads of four and two;
it does not give dwarves a new six-stone capacity. Reservations cap incoming
goods at the amount still needed. Storage supplies are reserved before pickup
and withdrawn only when the worker physically reaches their access point.

All required stone arrives before building starts. One builder then uses the
existing stone-hammer model with a new two-hand swing, contacting the actual
target face. Each voxel costs one stone and three seconds of productive work at
normal labor speed. Existing game speed and labor modifiers apply; walking and
delivery are additional time. Six voxels therefore require eighteen seconds of
hammering. Blocks complete individually and gain real terrain solidity/support
as before. Builders stand outside unfinished blueprint cells and revalidate
support, occupancy and contact before each commit.

Hunger, sleep, player interruption and job recovery retain delivered stock and
per-voxel work. Cancellation drops unused staged stone at the crate while normal
hauling cleanup preserves carried goods. Finished terrain remains. Saved orders
include optional total-block, crate-location and staged-material fields beside
their existing partial work; old current-schema orders without these fields start
with empty crates. Restore discards transient claims, rebuilds terrain first and
places crates after furniture/storage restore. Scene teardown never refunds into
a dying scene. Save validation rejects excess stock and unknown material IDs.

Clicking a blueprint or its crate opens the project inspector with delivered
and incoming stone, delivery workers, completed blocks, active builder, current
voxel progress and remaining hammer time. Cosmetic crate contents show up to six
stones; the inspector remains the exact count. Colony inventory includes staged
stock as reserved and unavailable to other jobs. Crates share existing world
materials and slice visibility.

`ConstructionMaterials` extends the existing storage contract; `ConstructionWork`
owns building progress. The scheduler's existing HAUL and FETCH_BUILD families
remain in use, with at most two delivery leases and one builder lease per order.
No new autoload, global class, profession or hammer-equipment requirement was
introduced. Worker construction of the separate decorative floor types remains
disabled as before. Data stays under BlockRegistry's construction JSON.

Fifteen native source fixtures pass with no script/runtime errors:
ConstructionStagingTest, ConstructionPresentationTest, ConstructionTest,
ConstructionInputTest, ConstructionObstacleReuseTest, FloorConstructionTest,
HaulingCapacityTest, HaulingAnimationTest, HaulingSelectionTest, JobLifecycleTest,
JobPlanningTest, LadderTest, WorkerCraftingTest, ColonyInventoryTest and
SaveManagerRoundTripTest. Coverage includes concurrent four/two deliveries,
ground and container storage bundles, conservation, pause/hunger interruption,
staged save/restore, partial funding, cancellation, lost support, exact hammer
contact, tool cleanup, crate picking and slicing. The full save fixture also
exercises autosave and corrupt-primary recovery. ConstructionStagingTest joins
the normal job reliability gate; the presentation fixture requires rendering.

Native screenshots were inspected and the initial missing crate vertex-color
material corrected. Fixture setup also needed a fresh mouse-enter event for the
construction tooltip and complete water/rock caches for the inventory scene.
An intermediate material edit had a variable-name typo, fixed before the final
runs; a subsequent unresponsive native process was stopped and rerun successfully.
Final fixture results and compressed logs are retained in
[the evidence summary](concepts/construction_staging_20261017/summary.json).
The longer 30-dwarf performance soak remains a separate checkpoint, not a claim
of this feature validation. Restart Play. No Windows playtest was created or
updated.

## Hammer orientation and impact audio follow-up

2026-10-17. Player feedback identified a sideways-facing hammer at contact and
missing construction audio. The old pose placed the head's +X end at the target
but used a fixed orientation, so its striking face was not parallel to the block.
`DwarfConstructionPose` now derives the impact basis from the struck face normal.
Low blocks receive a top-down strike; higher blocks receive a strike into their
near side. The contact point stays on that face through the contact hold. The
held model scale is 1.1 instead of 1.65, with a close-target stance adjustment
following the existing mining pose approach. The source GLB remains unchanged.

`DwarfWorkExecution` compares actual clamped work progress before and after each
tick and calls `WorkFeedback.play_hammer` when it crosses the 0.72 contact phase
of the one-second cycle. A stalled frame emits at most one hit; partial-work
resumption does not replay old hits. Six original procedural stone-hammer knocks
are authored by `tools/generate_hammer_audio.py`, with short, weighty resonances
distinct from the pick's bright ring. They use the existing Work/Effects bus,
variant avoidance, minor pitch variation, zoom/distance gain, slice suppression
and bounded voice pool. Game speed changes cadence without pitch-shifting samples.
Pausing stops new strikes and pauses the hammer's short remaining audio tail.

Five targeted native source checks pass: ConstructionPresentationTest verifies
all four approach directions at four heights, exact head contact, unreflected
tool transforms, grips above ground and interruption cleanup. Close-up captures
show the wind-up, downward strike and side strike. ConstructionAudioTest exercises
real deliveries/building, contact/hold, pause, speed, stalled frames, hidden/sliced
work, distance, interruption/resume, cancellation and completion clamping.
ConstructionStagingTest confirms supplies, partial work and conservation still
behave correctly; WorkerCraftingAudioTest retains the existing axe sound behavior.
WorkAudioPlaybackTest with `--kind=hammer` records the actual native mixer and
passes audible PCM, attenuation, stereo and eight-voice headroom checks (near
peak 0.297; eight simultaneous hits peak 0.527). It records only the game's Work
bus, not a microphone. Final runs have no script/runtime errors.

Initial regression runs exposed fixture-only native pointer issues: the staging
fixture now disables unused mining input, and the crafting audio fixture creates
its noise instances for hover rays outside its loaded test chunks. Both reruns
pass. No production input or world-generation behavior was changed for these.
Logs, captures, audio samples and results are retained in
[the hammer evidence](concepts/construction_hammer_20261017/summary.json).
Restart Play. No Windows export or playtest package was created or updated.

## Continuous work from one standing position

2026-10-17. Korur visibly stepped inward between the stones of a four-block
column. Two resets caused this: every block completed the FETCH_BUILD assignment,
stowed the hammer and returned to scheduling, while the hammer's close-target
stance also changed with target height.

`ConstructionWork` now retains its builder and delivery stand after each commit.
It selects the next supported, unoccupied block within reach of the same floor
cell, preferring the current column. `DwarfAgent` keeps FETCH_WORKING, the same
attempt generation and the equipped hammer; it does not reset the pose or plan
a route between reachable blocks. Once no valid work remains at that position,
the normal cleanup explicitly releases the builder claim before completing the
assignment. Later work can then choose another approach. The existing five-up /
one-down reach, three-air-block clearance, support, occupancy and materials rules
remain in force. No build order or save schema changed.

The hammer pose anchors its stance once on arrival, using horizontal near-face
clearance rather than each target's height. Both visible feet remain fixed while
the hands reach successive heights. Final completion and interruption release
that transient anchor. Work supervision identifies the current block, so a new
per-block timer is progress rather than an apparent stall in a long assignment.

`ConstructionContinuityTest` uses real deliveries and a real four-block column,
checking the same root position, both feet, horizontal body position, task and
attempt at every frame and all three internal transitions. It also exercises a
late obstacle, normal replanning, pause, interruption after the first commit,
resuming partial work and cancellation/refunds. It joins the job reliability gate.
Native ConstructionStagingTest, ConstructionAudioTest, ConstructionPresentationTest,
ConstructionTest and SaveManagerRoundTripTest cover the surrounding behavior.
Initial checks caught a builder claim that needed explicit cleanup when continuation
fails, and a resume assertion needed to include the scheduler's first productive
tick. Both were corrected before the final runs.

Results and the per-transition position trace are retained in
[the continuity evidence](concepts/construction_continuity_20261017/summary.json).
Restart Play. No Windows export or playtest package was created or updated.
