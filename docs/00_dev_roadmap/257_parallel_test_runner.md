# 257 — Parallel, isolated test runner

**Date:** 2026-10-22 · **Status:** done · **Player impact:** none (tooling only)

## What changed

`tools/run_job_reliability.ps1` now runs any set of headless tests, not just the job gate.
The selection lives in `tools/test_suite.json`.

- **Selection.**
  - No arguments runs the 46-test job gate (`gate` in the JSON).
  - `-Tests` takes names or wildcards (`-Tests Hauling*,LadderTest`).
  - `-Area` takes a group from `areas` (`-Area hauling,navigation`).
  - `-All` runs every `*Test.gd` in `scripts/tests` (163 today).
  - `-List` prints the selection without running it.
- **Isolation.** Each test gets a throwaway `APPDATA`/`LOCALAPPDATA`, so the player profile
  (saves, `audio.cfg`, `ui_layout.json`) is never read or written.
  - Tests whose guard checks the profile path (`profile_roots`) get their profile under
    that folder, so `StorageFilterTest`, `ZoneWindowTest` and the world-layout tests run
    without a manual setup step.
- **Parallel.** `-Parallel` (default 8) tests run at once.
  - Tests that write to the same `tmp/` folder (`shared_output`) never overlap.
  - Long tests (raised `timeouts`) start first.
- **Multi-phase tests.** `phases` lists the argument sets that run one after another in
  the same profile. `StartupSaveTest` runs `--prepare`, then a plain resume.
- **Quiet output.** Prints one summary line, plus each failure with up to 8 error lines and
  5 `FAIL` lines. `-ShowPasses` lists passes too.
- **Cleanup.** On full success the run's logs, profiles and any new `tmp/` folders are
  deleted, unless `-KeepOutput` is given. On failure everything is kept and the log path is
  printed.
  - The run also reports any tracked file whose `git status` changed during it.
- `-Godot` now defaults to the Steam install of Godot 4.7.

## Timings (2026-10-22, 16 logical cores)

| Run | Workers | Result | Wall time |
|---|---|---|---|
| Job gate | 1 | 46/46 | 403 s |
| Job gate | 4 | 46/46 | 106 s |
| Job gate | 8 | 46/46 | 66 s |
| All tests | 8 | 157/163 | 467 s |

## Known failures outside the gate

These six fail the same way when run alone with `-Parallel 1`, so they were broken before
this change and parallel running isn't the cause:

| Test | Failure |
|---|---|
| `BoulderPilotTest` | Out-of-bounds index into a `PackedInt32Array` (exits 0 but logs script errors) |
| `CaveGenerationTest` | Prints `CaveGenerationTest: FAIL` |
| `FurniturePlaceTest` | `'storage'` key missing on a Dictionary, then timeout |
| `DwarfInspectorTest` | `'base:furniture:wooden_table'` key missing, then timeout |
| `EnvironmentDetailsTest` | `store_string` on a null file (its `tmp/` output folder no longer exists), then timeout |
| `ToolPromotionTest` | `free` called on null, then timeout |

Under the standing test rule, each is either repaired, if other tests are built on it, or
deleted.

## Headless coverage

Every test runs headless. Screenshot captures only run with `--capture`. About ten tests
(sky, audio, the loading screen) skip their render or audio checks without a display, so run
those windowed when that area changes.
