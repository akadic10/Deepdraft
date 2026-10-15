# Scheduling evidence, 2026-10-14

See [report 188](../../188_job_scheduling_performance.md) for interpretation,
limits, reproduction and the Windows build.

`jobs30_before` is uninstrumented. `jobs30_after_v1` and
`jobs30_after_repeat` run the same final production code; the repeat adds
benchmark-only assignment signals and extra source hashes. `jobs20_after`
is a final-source functional/performance observation, without a matched
20-second pre-change baseline. Do not compare its totals directly with the
12-second runs from 187.

`jobs30_trace_before` adds temporary counters to the original implementation.
Its timing must not be used for FPS claims. `.trace.txt` contains the exact
instrumented TaskManager/FurnitureFetchPlanner. To reproduce it in a disposable
checkout, restore the frozen StorageComponent and ItemDropManager too, install
the two trace sources, copy `Jobs30Trace.gd.txt` to
`tools/performance/Jobs30Trace.gd` and adapt `RunTrace.ps1.txt` to that checkout.
Restore all four production files afterwards. `Instrument.py.txt` records
how the original counters were inserted; it expects the frozen pre-change
sources and should not be run against the final implementation.

Full native frame rows are gzip-compressed JSON. Reports retain phase
distributions, work counts, frame-sampled worker activity and navigation data.
The original player save is never edited. Test/export application data lives
under `tmp/jobs30_20261014`, outside player profiles.

The initial preparation-test attempts had fixture initialization and typed
array errors. They are excluded; `job_gate_*` is the final clean 34-fixture
run. Production source was unchanged during the gate and both final 30-dwarf
runs. `CollectJobs30.py` copies final evidence and records source/build hashes.
