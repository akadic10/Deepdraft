# Normal speed rendering profile evidence

The runs use a copy of the developed player settlement, expanded from five to
30 dwarves with the existing nearby mining, building and hauling workload.
The input save SHA-256 is
`f223eee6dfe52fefe6add9a763362640f02c439fb2f33687f550661fb9cc148b`.
Player profiles and save contents are not copied into this evidence directory.

## Scenario

Each fresh process loads the same copied save and creates 64 mining blocks,
48 construction blocks and 240 loose supplies through the established benchmark.
All 79 wildlife, 2,925 trees and normal needs/movement remain active. The roster
contains exactly 30 dwarves. The calendar retains x1 speed and 60 real seconds
per game hour, starting on summer day 3 at approximately 21:13.

Each phase has eight seconds of unsampled warmup followed by 30 seconds of
sampling: stationary camera, camera pan, repeated camera pan. The camera follows
the same eight-second orbit around the settlement, with zoom 48 and slice 127.
The world continues between phases; jobs finish and the evening grows darker.
Phase differences cannot be attributed to camera movement alone.

Autosave and arrival scheduling are disabled for this steady-cost investigation.
There are no artificial time jumps, season triggers, scene freezes or rendering
ablations. Audio uses the existing Dummy driver. These short samples do not
replace the planned long-session test with events enabled.

## Run variants

- `steady_render_plain_a` and `steady_render_plain_b`: production scripts,
  2560×1440, without process markers or method wrappers.
- `steady_render_detail_a` and `steady_render_detail_b`: 2560×1440, process
  markers plus temporary timers around renderer, lighting and dwarf callbacks.
- `steady_render_small`: production scripts, 1280×720, no process markers or
  method wrappers. The game world and camera's world-space path are unchanged.

All runs use native D3D12 Forward+ with VSync disabled and no FPS cap. GPU and
render CPU timestamps come from the main viewport. GPU results may lag and do
not cover every viewport; whole-frame wall time is the primary pacing measure.
The lifecycle probe and row collection remain enabled in the plain controls.
No screenshots or benchmark JSON writes occur within a sampled phase. Per-phase summary
and JSON writes happen after sampling, followed by the next warmup.

Sibling process-marker intervals include descendants. In particular, the renderer
group includes water, underground lighting and other children. Method wrappers
isolate the renderer callback itself, but include synchronous callees. The fog,
actor and solver timers are nested inside lighting; body samples are nested
inside actor synchronization. These overlapping timers must not be summed.
Detail keys ending in `/calls` and the two write counters are counts, not ms.
Summary threshold fields on count statistics have no frame-time interpretation.

A sixth run, `fog_broadcast_probe`, uses the same normal-speed settlement and
60 seconds of live warmup. Twelve four-second blocks follow an ABBA pattern:
live, frozen, frozen, live, repeated three times. Each block settles for one
second and samples three seconds. This balances the camera's eight-second orbit
and reduces time-order bias. Only `_sync_fog()` is skipped in frozen blocks;
the resulting stale atmosphere is intentionally diagnostic. Actor sampling,
the light field, sky, simulation and calendar continue. Results live under
`fog_intervention/`, including all rows, per-block means, pooled comparison,
complete logs and guarded source restoration snapshots.

## Files

- `summary.json`: phase measurements, work deltas, lighting counts, pipeline
  compilation counts and the eight slowest frames per phase.
- `runs/*/report.json`: original per-phase summaries and machine/source metadata.
- `runs/*/*_frames.json.gz`: losslessly compressed original per-frame JSON.
  `summary.json` records the uncompressed SHA-256 and row count.
- `runs/*/run.json`, `run.out`, `run.err`: invocation, input integrity, exit status
  and complete engine logs. Existing pre-world sky/weather warnings remain visible.
- Instrumented runs retain exact before/instrumented source snapshots, installation
  hashes and restoration hashes alongside their results.
- `sources/`: frozen diagnostic tools as text; `production_sources.json` records
  every production GDScript hash before the investigation.
- `audit.json`: final production-source and player-save integrity checks.

## Reproduction

Use fresh labels and an explicitly copied save. Run native cases sequentially.

```powershell
& tools/performance/RunSteadyRendering.ps1 -Label steady_render_plain_new -SavePath <copied-save> -NoMarkers -NoAblations
& tools/performance/RunSteadyRendering.ps1 -Label steady_render_detail_new -SavePath <copied-save> -Detailed -NoAblations
& tools/performance/RunSteadyRendering.ps1 -Label steady_render_small_new -SavePath <copied-save> -NoMarkers -NoAblations -Small
& tools/performance/RunFogBroadcast.ps1 -Label fog_broadcast_probe_new -SavePath <copied-save> -NoAblations
```

The runner redirects APPDATA/LOCALAPPDATA only for its child process. Detailed
mode temporarily wraps methods in `WorldRenderer.gd`, `UndergroundLighting.gd`
and `DwarfAgent.gd`; do not start another play session while those diagnostics
are installed. Its `finally` block restores the exact original bytes, guarded
against overwriting concurrent edits. Backups remain in the run's instrumentation
directory. `InstrumentRendering.py restore <that-directory>` is the recovery
command if the runner itself is forcibly terminated.

`AnalyzeSteadyRendering.py` collects completed `steady_render_*` runs, validates
normal clock speed and raw row counts, and refuses a clean audit if any of the
337 production GDScripts differs from the investigation's starting snapshot.
