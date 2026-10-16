# Lighting buffer disposal evidence, 2026-10-15

See [report 190](../../190_lighting_buffer_disposal_performance.md) for the
measured benefit, limits, validation and build.

`lighting_20261015_before_30` and `lighting_20261015_after_30` are the native
30-dwarf yard pair. `saved_before` and `saved_after` load the same isolated copy
of the player's newer five-dwarf settlement. Full frame rows are compressed
JSON; reports retain work completion and assignment data as well as timings.

`lighting_20261015_trace_30` is a diagnostic run of the original implementation.
It finished measurement phases but failed the strict runner on two dwarf
shutdown errors. Use it only to attribute the reset cost, never for FPS claims
or clean regression counts. Its exact source and instrumentation helper are
saved as text. No diagnostic counters are installed in production.

`UndergroundLighting.gd.before.txt` is the original source;
`UndergroundLighting.gd.after.txt` is the final source. The new controlled
fixture compiles the frozen original for exact comparisons. The yard pair
predates the benchmark's new lighting-hash metadata; the copied-save pair
contains that field. `audit.json` verifies final source and unchanged save
hashes and records the tested package.

Run `tools/performance/CollectLighting.py` after all named checks to refresh
this evidence. It collects reports, compressed frame rows, fixture logs and
native captures without launching the game. Saved PowerShell helpers use
isolated profiles; adapt absolute paths when reproducing on another machine.
Native visual fixtures with historical output paths contribute only files
written on this session's date. Player saves themselves are not copied here.
