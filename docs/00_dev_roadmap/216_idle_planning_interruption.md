# 216 — Preserve idle activity during work planning

The player reported Sollin standing indefinitely beside the lower staircase,
with two wall torches still awaiting installation. The October 17 19:18 quicksave
contains an awake, fed, empty-handed Sollin at floor cell `(244,36,519)`, two
pending wall torches, and two matching kits in storage. The current route up
the stairs is usable.

## Save observation and its limits

Loading an isolated copy with the existing code did **not** reproduce the
reported live-session stall. At normal speed, Sollin received a torch job after
0.63 seconds and completed the installation at `(251,37,525)` after 23.38 seconds.
Guntris completed the other torch after 35.85 seconds. Sollin subsequently moved
around; task ownership checks were clean. The original save was paused, so the
observation deliberately resumed it after normal loading finished.

This establishes that the saved layout, supplies and work permissions permit
the work. It does not identify the exact temporary runtime state behind the
original freeze. Save/load reconstructs pending jobs and transient planning
state. The follow-up copied-save observation with the correction below also
completes both installations without lifecycle errors.

## Reproduced idle bug and correction

`TaskManager.hold_for_planning()` cancelled all leisure whenever a new planning
hold began. That erased a stationary dwarf's home and timer, or released their
chair. The default four-second hold and two-second gap could repeat indefinitely:
each gap restarted a 2.5–5 second delay, which could never finish before the next
hold. This explains one way an available dwarf can remain Looking around even
when planning never yields an assignment.

A planning hold now cancels only a walk owned by leisure, retaining the existing
privacy-exit exception. Waiting timers, chair-search progress and seated poses
survive a hold, so they continue between unsuccessful checks. Actual assignments
still cancel leisure and release chairs through `receive_task`. Route searches
still stabilize their start position and extend holds while making progress.
Seat validity is checked before the hold, so uninstall, lost support or changed
access can still release a retained chair immediately.
Needs, work permissions, priorities, navigation clearance and probe/CPU budgets
are unchanged. There is no save-format change or position repair.

## Validation

`DwarfIdlePlanningTest` uses default idle timing and repeatedly asks the real
planning-hold API to consider an available dwarf for 40 simulated seconds. Before
the correction, displacement was zero and merely considering work also unseated
a resting dwarf. Afterwards the dwarf moves 3.16 voxels, stays available, retains
a chair during planning, and immediately releases leisure/chair ownership when
reachable work is actually assigned.

Eight native source fixtures pass: idle planning, idle behavior, shrub Move
handoff, furniture assignment, job planning, shared hauling routes, hauling
route fairness, and dining. The Move fixture retains its long outbound/return
searches, live leisure, and one-probe budget. Its synthetic generator needed the
waterline and block-ID caches initialized for the existing final-state terrain
writer; its initial run emitted script errors, and the repaired fixture passes
cleanly. Production terrain generation was not changed.

The final chair-availability safeguard was added after the copied-save check.
Uninstall-during-hold first failed, then passed after moving seat validation
ahead of the hold. Idle planning, idle behavior and dining were rerun successfully
with this safeguard. Native editor import also passed.

Both copied-save observations run for 60 seconds with normal needs and scheduler
processing. SHA-256 checks preserve the quicksave, autosave and both backups.
Evidence: [observations, regression results and save hashes](concepts/sollin_idle_20261017/summary.json).

Restart Play and load the existing save to use the correction. No Windows
playtest or export was created or updated.
