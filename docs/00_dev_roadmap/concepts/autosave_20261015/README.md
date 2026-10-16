# Autosave evidence · 2026-10-15

See [192 — Autosave performance](../../192_autosave_performance.md) for interpretation.

- `summary.json`: all nine native runs, requests, completion timing and work progress.
- `autosave_before_5`, `autosave_before_20`, `autosave_profile_before_30`: original synchronous coordinator with timed stages.
- `autosave_after_trial_30`: preliminary worker run; retained, not the final matrix.
- `autosave_after_5`, `autosave_after_20`, `autosave_after_30`: final source matrix.
- `autosave_before_repeat_30`, `autosave_after_repeat_30`: consecutive repeat investigating ordinary frame-time variability. Both clean; no samples discarded.
- Each run retains `run.json` (arguments, exit, input hash), logs, report, full autosave trace and numeric frame rows. Frame rows are flat groups of five: seconds, wall ms, process ms, draw ms, render setup CPU ms.
- `*.before.txt`: frozen former coordinator, validator and serializers; WaterFlow/SoilMoisture remain unchanged in production.
- `final_sources`, `source_hashes.json`: final implementation and prior lighting/dust source identity.
- `worker_regression_v2`: final full round-trip pass, including 190 malformed saves, 19 validator comparisons, exact preparation, nested isolation, busy guards and three transaction failure stages.
- `final_regressions`: seven additional relevant fixtures, all clean.
- `shutdown`: coordinator teardown joins an outstanding owned transaction; external comparison confirms the complete input snapshot was written before process exit.
- `packed`: native D3D12 copied-save checks, screenshots, manual/autosave completion and backup recovery, plus separate release EXE startup.
- `package_audit.json`: exact ZIP file list and hashes compared to the release directory.
- `initial_round_trip` is the earlier pass before worker-specific checks. `worker_regression` is a **failed intermediate compile attempt**, retained as diagnostic evidence; it is not a passing test. Moving registry capture into SaveManager and keeping the validator pure fixes it.

All user-data profiles are disposable copies under `tmp/autosave_20261015` or
`tmp/performance_20261014`. Original save SHA256:
`f223eee6dfe52fefe6add9a763362640f02c439fb2f33687f550661fb9cc148b`.
No player profile or runtime JSON save is copied into this evidence directory.

PowerShell wrappers document the exact commands. Run from `P:/Deepdraft`, one
Godot process at a time, with the Steam 4.7.2 executable. `Repeat30.ps1` restores
final source bytes in `finally`; it temporarily swaps five files to the frozen
baseline, so do not overlap it with tests, export or editor Play.
`ProfileSaveManager.gd` is baseline-only and preserves the old transaction order.
Do not apply it to the current async coordinator.

Collect with `py -3 tools/performance/CollectAutosaveEvidence.py` after runs.
These are short focused measurements, not an hours-long soak or a guarantee
that every frame is within 16.7 ms.
