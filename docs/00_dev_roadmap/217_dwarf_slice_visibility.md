# 217 — Dwarf visibility while crossing slices

The player reproduced a wall-torch Move that appeared to be performed from the
room upstairs and saved the pending order at 19:50 on October 17. Unlike the
earlier reconstruction, this observation loads that exact saved order without
changing source/destination mounts, actor positions, terrain or job parameters.
The original save and its three companion save files remain untouched.

## Finding

The order moves installed torch 91 from `(245,37,525)` to `(254,37,528)`.
Its actual mount cell is `(245,40,525)`. All four valid removal stands are on
floor 37; floor 43 upstairs is not an accepted work position.

In the unmodified-source observation, Ildgra starts on floor 43, takes the
staircase down through floors 42, 41, 40, 39 and 38, and reaches floor 37.
Removal begins at `(244,37,525)` after 12.43 seconds, completes after 14.90
seconds, and installation completes downstairs after 20.32 seconds. The actor's
logical position and body transform agree. The recorded route does not reach
through the separating floor.

However, Ildgra stays **invisible** in the selected slice (41). Visibility was
updated on spawn/load, slice-control changes and lost-footing recovery, but
ordinary staircase movement never refreshed it. An upstairs worker therefore
continued into the lower room and moved the torch with no visible worker there.
The native removal capture and the movement regression reproduce this defect.

## Correction

`DwarfAgent` enables global transform notifications when entering the tree and
refreshes the existing feet-height slice test when its transform changes.
Visibility updates before rendering; the setter runs only when the result
changes. `apply_slice()` uses the same helper. This covers ordinary stairs,
ladders, parent transforms and paused position restoration, without relying on
simulation ticks or a second click of the slice controls.

No reach, obstruction, navigation, job-priority, carrying or saved-data rules
were changed. The fix also conceals a dwarf climbing above the active slice.

## Validation

The new `DwarfSliceMovementTest` uses real staircase paths and rendered frames,
with an unchanged slice. Before the correction, the first test recorded 27
incorrect-visibility samples in each walk and failed downstairs visibility and
paused restoration. Afterward it reports zero mismatches. The final fixture
independently resets the initial visible state for its ascent check and passes.

Six native fixtures pass: dwarf slice movement, dwarf support (including steps,
ladders and decks), wall-mount heights/obstruction, real furniture Move,
overhead need indicators, and X-ray view. The exact pending-save replay also
checks the removal and installation positions, actor visibility, completion,
and task ownership. Ildgra is visibly present for both contacts in the corrected
run. Native editor import passes. Original save hashes are recorded with the
evidence.

Evidence: [trace, checks and original-save hashes](concepts/torch_slice_visibility_20261017/summary.json),
[before removal](concepts/torch_slice_visibility_20261017/before.png),
[after removal](concepts/torch_slice_visibility_20261017/after.png).

Restart Play and reload the existing save. No Windows playtest or export was
created or updated.
