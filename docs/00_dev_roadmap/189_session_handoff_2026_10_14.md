# 189 — Performance session handoff · 2026-10-14

Resume point for **October 15**. Camera panning and slicing now feel much
smoother to the player. Today's performance passes are implemented and packaged.
The next investigation is **lighting hitches**, followed by the agreed
long-session/event review within the intended maximum of **30 dwarves**.

## Where we stopped

| Area | Completed work |
|---|---|
| Baseline | [178](178_performance_baseline_and_camera_stutter.md): reproducible native camera measurements and subsystem timing. |
| Water rendering | [179](179_water_mesh_rebuild_performance.md): asynchronous mesh preparation and budgeted uploads. [182](182_moisture_rendering_performance.md) and [183](183_water_current_performance.md): smaller moisture updates and incremental current presentation. |
| Water simulation | [181](181_water_simulation_performance.md) and [184](184_water_flow_loop_performance.md): reuse unchanged queries and reduce flow-loop work, with differential solver checks. |
| Wildlife | [180](180_wildlife_navigation_performance.md) and [186](186_duck_query_performance.md): cheaper navigation queries with normal offscreen simulation retained. |
| Rooms | [185](185_room_rebuild_performance.md): room detection and metadata spread across frames; immediate door-lighting boundaries preserved. |
| Colony work | [187](187_colony_scaling_performance.md): scaling yard and cheaper construction obstacle scans. [188](188_job_scheduling_performance.md): shared hauling preparation and resumable construction planning. |

The latest 30-dwarf comparison builds **10–12 blocks** and stores **12–38 items**,
versus **one block and zero items** before. Controlled hauling-query CPU falls
88%. The final 20-dwarf run also progresses in mining, building and hauling.
However, later 30-dwarf mean frame times are **11–21% higher**; the worlds now
perform different amounts of work. Treat 188 as a job-progress improvement,
with remaining waits and frame costs, rather than an FPS improvement.

All **34 latest regression fixtures**, native packaged-save checks and release
startup pass. The player has praised earlier camera/slice improvements; player
feedback on the final scheduling build is still pending. Detailed results,
source hashes, frozen originals and frame traces are in
[188's evidence directory](concepts/jobs30_20261014/README.md).

## Tomorrow's work order

### 1. Diagnose and reduce the lighting hitch

In the final repeated 30-dwarf run, a **274.50 ms frame contains 249.68 ms in
the underground/actor-lighting group**. This is the strongest concrete next
target. Another 218.76 ms wall-frame outlier contains only 11.30 ms of measured
scene CPU; investigate it separately instead of attributing all stalls to lighting.

Start with `scripts/components/UndergroundLighting.gd`, particularly `_process`
and `_sync_actors`, and the renderer timing boundaries in
`tools/performance/CameraBenchmark.gd`. Reproduce the hitch with the current
30-dwarf yard and a copied settlement, then time the internal lighting stages
to identify the expensive operation and its trigger. Determine whether it is
an initial refresh, edit/event response or recurring actor cost before choosing
a fix. Lighting's ordinary first-pan average was 3.56 ms, so both the spike
and steady cost merit separate measurements.

The exact starting trace is
`concepts/jobs30_20261014/jobs30_after_repeat_active_pan_frames.json.gz`.
Its lighting timer is nested inside the renderer timer; do not add them together.

After a confirmed fix, repeat matched native pans and check P95/P99, maximum
frame time and lighting CPU. Preserve lighting appearance, immediate slice
concealment and door boundaries. Relevant fixtures include
`UndergroundLightingTest`, `RoomLightingTest`, `DoorLightingTest`,
`BedroomLightingTest`, `DwarfLimbLightingTest` and `RoomRebuildSchedulingTest`.
Use native daylight/underground/torch views and a packaged copied-save check
before refreshing the release.

### 2. Review long sessions and event spikes

This is the outstanding third opportunity from the earlier performance plan.
Use a fresh copy of the latest settlement and representative 20/30-dwarf
workloads. The existing yard is useful for repeatability but is not a mature
colony with accumulated rooms, goods, crafting and long routes.

Run a sustained baseline, then correlate stalls with autosave, arrivals,
day/season transitions, repeated mining/building edits, room/lighting refreshes
and inventory growth. Track frame-time distributions, frames over 33/50/100 ms,
memory/node growth, completed work and time spent waiting for assignments.
Separate initial setup spikes from recurring play-session hitches. Prioritize
one measured cause at a time and retain comparable before/after evidence.

### 3. Revisit remaining steady CPU cost and job waits

If lighting/event work leaves a meaningful CPU limit, profile dwarf updates
internally; they averaged 3.45 ms in the latest 30-dwarf first pan. Inspect
support, movement, needs and idle work before changing update frequency.

Construction handoff/validation can still push TaskManager to 5.3–7.5 ms,
and inventory changes still restart some planning. A later measured phase
took 12.37 seconds to dispatch its next hauling job, while prior trips could
remain active. Track actual completions and dispatch latency alongside FPS:
workers doing nothing must not make an optimization look successful.

## Decisions and boundaries to retain

- The intended maximum is **30 dwarves**. Use **5/20/30** for routine reviews;
  the earlier 50/100 results are optional stress evidence. No runtime population
  cap has been implemented.
- Fog of war was offered as an idea, not an instruction to implement it.
  No fog-of-war system or reduced offscreen simulation is part of these changes.
- Keep [177's project-review findings](177_project_review_deferred_2026_10_14.md)
  parked. Performance remains the focus.
- Preserve three-block dwarf navigation clearance, terrain identity, discovery
  concealment, item conservation and safe job interruption. Keep the approved
  visual quality and normal simulation behavior.
- Preserve the existing uncommitted work. The working tree contains the full
  performance series and an existing `project.godot` edit; no commit or push
  was requested during this session.

## Current build and measurement setup

Latest tested executable:

`build/windows/releases/20261014-215739-733-56349389/Deepdraft/Deepdraft.exe`

Share ZIP: `build/windows/Deepdraft-Windows-Playtest.zip` (76.9 MiB).

ZIP SHA256:
`4bbf447f53724619a9e6fa1952fb77e159b585de74ddb78df8656fd3f96eba28`.

Restart Play or launch this release to load the changes. Existing saves need
no migration. Export with `tools/windows_playtest/Export.ps1`; keep its unique
release directories so a running game's PCK is never replaced.

Measurements used Godot 4.7.2, D3D12 Forward+, 2560×1440, uncapped/VSync off,
on a Ryzen 7 9800X3D and Radeon RX 9070 XT. The player reports stutter in both
the editor and exported game. Existing FPS comparisons used the standalone
editor executable; exported checks establish functionality, not equivalent FPS.

Run benchmarks sequentially without tests or exports alongside them. Use
isolated APPDATA/LOCALAPPDATA, fresh output labels and copied saves. Keep the
player's editor and original saves intact. Existing benchmark runners disable
saving; an autosave experiment needs a separate isolated profile with saving
intentionally enabled.

```powershell
& tools/performance/RunScaling.ps1 -Population 30 -Label lighting_before_30 -Seconds 20
& tools/performance/RunScaling.ps1 -Population 20 -Label lighting_before_20 -Seconds 20
```

Use new labels if those already exist. Temporary diagnostic counters from 188
are stored as text evidence and are not installed in production. Their timings
must not be used as baseline FPS. Durable evidence belongs in
`docs/00_dev_roadmap/concepts/`; temporary profiles/build outputs belong in `tmp/`.

This closeout changes documentation only. Runtime code, tests and the tested
Windows package remain at the completed 188 state.
