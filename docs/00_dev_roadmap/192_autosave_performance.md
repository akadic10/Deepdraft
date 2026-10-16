# 192 — Autosave performance · 2026-10-15

Manual saves and autosaves now capture the colony on the main thread and finish
formatting, validation and file replacement on one worker. This removes the
long save freeze found in [191](191_event_hitch_review.md). Measured request time
falls from **0.77–1.41 seconds to 14.7–17.6 ms** in the final native comparisons.
The repeated 30-dwarf run's maximum frame falls from **1,415 to 80 ms**.

This is a save-hitch improvement. Ordinary CPU stalls remain, and the work still
takes roughly 1–2 seconds to finish in the background. The intended maximum
remains 30 dwarves. Findings in 177 remain parked.

## What was blocking the frame

The original 30-dwarf trace takes 766 ms for a fresh autosave and 1,334 ms for
its replacement. Snapshot construction costs 113–119 ms, mostly water
serialization (96–99 ms). JSON encoding costs 47–48 ms. Structural validation
costs 479 ms for two reads on a fresh save, then 967 ms for four reads during
backup rotation. File reads/writes themselves are a small part of the stall.
Reducing validation or dropping the backup would weaken the save contract.

The new path preserves the existing format and transaction ordering:

1. Capture every owner and registry catalog in one synchronous main-thread call.
2. Give the worker private data. Water, mining and items copy raw containers;
   the worker formats and sorts them. Other owners are deeply copied.
3. Encode, write/flush, validate the temporary file, validate and stage the
   preceding primary, rotate its backup, install and validate the new primary.
4. Dispose of large temporary trees on the worker. The main thread collects
   only an already completed task and emits the success/failure signal.

No active scene, node, registry, or mutable gameplay container is read by the
worker. This follows Godot's [thread safety guidance](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html).
Every submitted task is joined, including on shutdown, as required by the
[WorkerThreadPool contract](https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html).

Only one save runs at a time. A second save or a load is rejected while it is
busy. The player can retry after completion. `request_save()` and
`request_autosave()` now return acceptance; the corresponding `*_finished`
signal means the transaction completed. Manual Save shows “Saving…” immediately;
“Game saved.” and “Autosaved.” appear after validation. Existing immediate-load
test/tool callers now wait for completion.

The five-minute timer pauses while writing and resumes afterward. Manual saves
do not reset it. Saving remains observational: jobs, reservations, carried
items, clock and wildlife are not paused or changed to take a snapshot.
Loading still reads/validates synchronously before replacing the world.

## Native measurements

Same copied settlement as 191: 5 original dwarves, 79 wildlife, 2,716 mined
blocks, 86 built blocks and 20 furniture pieces. Additional dwarves use normal
spawning. Each run adds 64 mining blocks, 48 construction blocks and 240 loose
items on real terrain. Camera pans continuously at speed 1 under clear weather.

Runs last 24 seconds and **explicitly request saves at 6 and 14 seconds** to
measure a fresh file and backup rotation. These are not new natural five-minute
tests. The round-trip fixture separately crosses the real timer threshold.
Each native run uses an isolated profile, starts a new process, and runs alone.
The source save stays unchanged. Hardware/engine: Ryzen 7 9800X3D, Radeon RX
9070 XT, Godot 4.7.2 Steam, D3D12 Forward+, VSync disabled for measurement.

| Dwarves / pair | Save request ms, before → after | Maximum frame ms, before → after | Mean frame ms, before → after | P95 ms, before → after |
|---|---|---|---|---|
| 5 | 816.6 / 1413.8 → 14.8 / 14.7 | 1429.8 → 60.8 | 19.84 → 17.74 | 37.11 → 35.87 |
| 20 | 867.6 / 1400.7 → 15.8 / 15.1 | 1442.3 → 96.4 | 31.74 → 28.33 | 48.66 → 47.96 |
| 30, consecutive repeat | 813.3 / 1396.8 → 16.0 / 15.4 | 1414.7 → 79.8 | 33.16 → 30.14 | 52.37 → 52.73 |

The first 30-dwarf baseline was faster outside saves: mean 21.97 ms versus
30.96 ms in the first final run (max 1347.09 → 101.91 ms). The latter's 101.91 ms
frame occurs at 1.98 seconds, before either save. Both runs and the preliminary
trial remain in the evidence. A consecutive before/after repeat checks this
inconsistency: pre-save means are 27.25/27.62 ms, and the save freeze disappears.
The variation prevents a general steady-FPS claim; the short request duration
and removal of the second-long stalls are consistent across every after run.

Worker completion takes 1.16–2.16 seconds in the main final matrix. Joining and
collecting completion costs 0.009–0.081 ms. Background validation still consumes
CPU; the repeat's save-window mean is about 33–35 ms. Main-thread snapshot
capture remains about 15–18 ms and can still make an individual frame longer.
Copies and validation trees temporarily increase memory; one writer bounds
concurrency, but this is not a memory or hours-long soak proof. Shutdown can
wait for an outstanding save. Flush/validated backup behavior is preserved;
this change does not introduce a stronger OS power-loss guarantee.

Work continues while saving. Net mined/built/stored changes before → after:
5 dwarves **39/0/8 → 44/0/8**; 20 dwarves **47/2/16 → 51/1/16**;
30 repeat **47/1/12 → 50/1/16**. Scheduling and world progression diverge,
so these are progress checks, not exact throughput comparisons.

## Validation and delivery

Eight relevant fixtures pass on final production sources: SaveManagerRoundTrip,
CraftMaterial, DuckWildlife, WorldTerrainStartup, WeatherPersistence, WaterFlow,
WaterWorld and WaterStoneLifecycle. The round-trip includes **190 malformed
snapshots**, **19 comparisons with the former validator**, exact preparation
against existing serializers, nested capture isolation, overlapping-operation
rejection, and injected write/staged-backup/installed-primary failures.
Failed writes preserve a valid primary and backup. Manual/autosave rotation,
weather continuation and in-transit item restoration retain their behavior.

A separate shutdown fixture starts an owned file transaction and immediately
quits. The coordinator joins it during teardown; an external comparison confirms
the output equals the complete input snapshot. All final checks exit 0 with no
script/engine errors. Expected no-scene startup warnings and injected rejection
warnings are retained. One intermediate fixture compile failure was corrected
by removing registry access from the pure validator; its logs remain labeled
as a failed attempt, not a pass.

Native checks run against the exported PCK, with loose workspace scripts
unavailable. The copied five-dwarf settlement passes exact manual snapshot
comparison, two autosaves, byte-identical preceding-backup checks, deliberate
primary corruption and actual backup loading/repair. It restores all 5 dwarves
and 79 wildlife. Existing lighting/dust preparation, slice concealment, offscreen
wildlife movement, 245 construction comparisons and 5 hauling comparisons pass.
Wolf and duck screenshots were inspected. A separate release EXE starts and
builds its world without script/engine errors.

Windows release:
`build/windows/releases/20261015-173619-332-778e7c05/Deepdraft/Deepdraft.exe`.
Refreshed archive: `build/windows/Deepdraft-Windows-Playtest.zip` (76.9 MiB).
ZIP SHA256: `bd17237590276f0bec12a4eb1a5dfccb2d73515d43ca7e3052f274daa4b1a62d`.
Its four entries exactly match the release EXE, console EXE, PCK and README.
Export checks include every runtime JSON definition and exclude development
files. The original save and prior lighting/dust sources retain their hashes.
Restart editor Play or launch this release to use the change.

## Reproduce and continue

Use `tools/performance/RunAutosave.ps1` with a new label, a disposable copied
save, `-Population 5`, `20` or `30`, `-Seconds 24 -NoAblations -Weather
base:weather:clear`. The runner isolates user data and verifies the input hash.
`AutosaveBenchmark.gd` writes request/completion profiles, frame rows and
work progress. `ProfileSaveManager.gd` is **baseline-only**: use it with the
frozen before sources, never as a production coordinator. `Repeat30.ps1` in
the evidence demonstrates exact-byte restore in `finally`; never overlap it
with another test or an editor play session.

[Evidence](concepts/autosave_20261015/README.md) includes raw logs, numeric frame
rows, before/final sources and hashes, regression results and package checks.
`CollectAutosaveEvidence.py` refreshes these artifacts without copying player
profiles. `autosave_frames.json` contains flat rows of five numbers: seconds,
wall ms, process ms, draw ms, render setup CPU ms.

Next: profile **wildlife arrival route preparation**, which reached 348 ms
in WorldEventDirector during 191. Then revisit construction waits and the
modest frame-time drift across seasons. Keep 5/20/30-dwarf progress metrics
alongside frame times; do not use fog of war to conceal simulation stalls.
