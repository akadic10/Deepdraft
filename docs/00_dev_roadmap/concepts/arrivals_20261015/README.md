# Arrival preparation evidence · 2026-10-15

Interpretation and limitations: [193](../../193_arrival_preparation_performance.md).

- `summary.json`: 3 baseline, 1 trial and 3 final native runs at 5/20/30 dwarves.
- `arrivals_profile_before_*`: unchanged behavior with stage timers. The five-dwarf run reports the known dwarf teardown errors **after** complete measurements; retain its timings as diagnostic evidence, not a clean pass.
- `arrivals_after_trial_30`: initial result; final matrix uses `arrivals_after_5`, `arrivals_after_20`, `arrivals_after_30`.
- Each run has arguments/input hash/exit, raw logs, frame stream and arrival report. `arrival_frames.json` contains flat rows: seconds, wall ms, event CPU ms, process ms, draw ms.
- `*.before.txt` / `*.profile.txt`: original sources and temporary baseline timing wrappers. Ground planner and event tuning remain unchanged in final production.
- `final_sources`, `source_hashes.json`: final code identity, including the preserved earlier performance changes.
- `initial`: existing duck and terrestrial arrival fixtures.
- `differential_v3`: successful independent planner comparisons, duck population and query-reuse fixtures. `differential` / `differential_v2` retain the failed harness attempts and are not counted as passes.
- `final_regressions`: navigation, ordinary wildlife, full save/recovery and terrain-startup checks.
- `packed`: native copied-save PCK checks, recovery of a saved pending search, actual new ducks, screenshots and separate release startup.
- `package_audit.json`: exact runtime ZIP inventory and hashes against the release directory.

Input is a copy of the original settlement, SHA256
`f223eee6dfe52fefe6add9a763362640f02c439fb2f33687f550661fb9cc148b`.
Profiles and runtime saves stay under `tmp/`, not in this directory.

Use `RunArrivals.ps1` with a fresh label and the copied save. Baseline runs use
the three `.profile.txt` versions of WildlifeManager, EdgeArrivalPlanner and
DuckPopulation, with the original director/navigation. Preserve final files
before any swap and restore their exact bytes in `finally`; never overlap
measurements with other native tests or editor Play. The temporary profile
wrappers are not production optimizations.

`CollectArrivalEvidence.py` copies reports/logs and freezes final hashes after
validation. The measurements are 40-second controlled event tests, not a
natural arrival-frequency study or an hours-long soak.
