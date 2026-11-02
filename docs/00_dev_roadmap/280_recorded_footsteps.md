# 280 — Recorded dwarf footsteps

2026-10-28. Implemented; owner listening acceptance pending.

The project had no footstep WAVs or playback hooks. Walking dwarves now use 22
recorded boot-step variations: six each for stone, wood and grass, plus four for
earth. The actual supporting terrain selects the bank, including built logs.
Earth uses filtered gravel foley; grass is the uploader's recorded thud/grass
composite. All four sources are Fission9's CC0 recordings, downloaded as public
HQ MP3 previews, with full decoded masters, credits and edit regions retained in
`tools/audio_sources/footsteps/`.

`DwarfMovement` emits at the two landing phases of its distance-driven gait.
Short arrival segments also advance the gait before its pose resets. Stalled
frames coalesce missed contacts; suppressed contacts do not replay. Stationary
posing, ladders and unsupported feet stay quiet. Movement routes and saves have
no new fields. `WorkFeedback` applies the existing camera, slice, pause and Work
bus rules, with a shared three-voice footstep limit, −15 dB source gain, 18-block
range and maximum zoom 48. Existing random pitch variation is independent of
game speed.

The review is `tmp/audio_audit_20261028/footsteps/review.html`. It provides source
recordings, individual steps, walking sequences and an offline preview at the
configured source/Work bus levels. There is no old footstep recording to compare.
Signal checks cannot replace the owner's listening review, and the preview is
not an in-game mixer capture.

All 22 WAVs rebuild identically, all 94 existing WAVs are unchanged, and Godot has
imported the new non-looping assets. Seven focused audio tests pass; lint has no
new violations. The gate passed 54/55 with `SaveManagerRoundTripTest` failing its
autosave-state comparison. A diagnostic retry passed that comparison, then failed
the installed light/heat reload assertion. `AudioListeningPointTest` also hit a
`FurnitureFires.burning` type error from its Dictionary fixture. Concurrent
nightly-fire and save-test edits are outside this change; exact results and
diagnostic snapshots are retained under the review directory.

Validation results are recorded in the review's `checks.json`. `FootstepAudioTest`
covers real route contact timing, final-waypoint contacts, skipped contacts,
surface selection, shared voice limits and source lifecycle. Existing hammer
and crafting tests now count their own sound families, so walking to work does
not masquerade as a tool impact. No hand-edited import files or new autoloads are
needed. Let Godot finish importing the new WAVs, then restart Play; no project
reload or save migration is needed.
