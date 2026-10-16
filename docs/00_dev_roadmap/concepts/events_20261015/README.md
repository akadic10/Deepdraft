# Event hitch evidence · 2026-10-15

See [report 191](../../191_event_hitch_review.md) for conclusions, limitations
and the next work order. Runs are sequential, native Windows/D3D12, with
isolated user profiles and the original player save left untouched.

- `events_pipeline_trace_30_*` / `events_pipeline_after_30_*`: eight-second
  camera phases with full frame lifecycle instrumentation. The first mining
  impact has a surface pipeline compilation before the change and none after.
  Phase-boundary report serialization is retained in the trace but excluded
  from gameplay statistics.
- `events_before_30_*` / `events_after_30_*`: standard 20-second camera phases,
  using the same benchmark and synthetic 30-dwarf work yard. `render_setup_ms`
  includes preparation omitted by viewport-only render CPU timing.
- `events_long_5_*`, `events_long_20_*`, `events_long_30_*`: copied developed
  settlement, real terrain jobs, continuous camera pan and controlled events.
  Durations are 330/210/330 seconds. The 20-dwarf run does not reach the normal
  300-second autosave. `long_session_summary.json` summarizes full numeric
  frame streams; `session.json.gz` contains windows, event times and progress.
- `*_frames.json.gz` and `*_lifecycle.json.gz`: raw frame evidence, compressed
  without changing its JSON content. Long-session numeric columns are seconds,
  wall ms, process ms, after-process ms, draw ms, after-draw ms, render setup ms.
- `WorkDustBurst.gd.before.txt` / `WorkFeedback.gd.before.txt`: frozen previous
  production source; corresponding `.after.txt` files are the shipped fix.
- `regressions_*`, `native_tests_*`, `packed_*`: fixture and packaged-build
  results. `audit.json` records final source, save and ZIP hashes.
- PowerShell `.txt` files preserve the exact experiment/package wrappers.
  `export_summary.txt` identifies the versioned Windows release.

The copied save is private scratch data and is not included here. Its SHA-256
is `f223eee6dfe52fefe6add9a763362640f02c439fb2f33687f550661fb9cc148b`.
Godot's startup warnings about the initially absent current scene and weather
seed are retained. They precede the loaded/seeded experiment and are not script
errors. The outer 20-dwarf wrapper initially treated an unset PowerShell
`LASTEXITCODE` as failure; the actual run has exit 0, its pass marker, and no
engine errors. It was verified without rerunning or selecting another sample.
The standard before-change camera run completes sampling but reports two
`DwarfAgent._begin_item_pickup` global-transform errors during `_exit_tree`.
This is the known shutdown issue from report 190. Its recorded frames remain
useful, but that run is not counted as a clean validation pass. The paired
wrapper correctly stops and restores the final sources; the after-change run
is then launched separately with the same arguments.

Reproduce a settlement run with `tools/performance/RunLongSession.ps1`, a new
label, `-Population 5`, `20` or `30`, `-SavePath` pointing at a copy of this save,
`-Seconds 330 -NoAblations -Weather base:weather:clear`. Use
`AnalyzeEvents.py` and `CollectEvents.py` for these recorded labels. The
diagnostic uses `EventSpikeBenchmark.gd`; the matched pair uses
`RunScaling.ps1`. Keep performance runs, tests and exports sequential.
