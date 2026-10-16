# 191 — Event hitch review and work effect preparation · 2026-10-15

The remaining first-mining hitch from [190](190_lighting_buffer_disposal_performance.md)
is graphics pipeline preparation for the first dust effect. Work effects now
prepare their rendering resources during loading and reuse those resources.
The first traced mining effect falls from about **200 ms of rendering to
2.3 ms**, with no new surface pipeline compilation when mining starts.

Longer copied-settlement tests also expose substantial autosave and wildlife
arrival stalls. These are separate from the dust fix and establish the next
work order. This pass retains the intended maximum of 30 dwarves, normal
simulation, visual quality and the original player save. Findings in 177 remain
parked.

## Locating the missing frame time

The earlier 168.18 ms frame had only 11.05 ms of measured scene processing.
`FrameLifecycleProbe.gd` now brackets process callbacks, work after processing,
rendering, and the interval before the next frame; physics callbacks and
benchmark bookkeeping are recorded separately. It also records render setup
CPU and pipeline compilation counters.

The diagnostic repeat records a **223.075 ms** frame at the first mining
impact. Rendering takes **199.829 ms**, including **197.411 ms** in render
setup, and the surface compilation counter increases by one. The previous
frame has no compilation and only 2.315 ms of setup. Physics callbacks take
0.178 ms; camera driving and worker observation are negligible. The earlier
viewport-only render CPU measurement omitted this setup cost.

`WorkDustBurst` created a new box mesh and alpha-blended, vertex-colored
material for each burst. The first live MultiMesh instance introduced a
rendering combination not prepared during loading. Godot supports preparing
these pipelines by instancing the effect in advance, including a hidden
instance. See the official [pipeline compilation guide](https://docs.godotengine.org/en/4.5/tutorials/performance/pipeline_compilations.html)
and [render setup timer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-get-frame-setup-time-cpu).

The diagnostic includes pauses between benchmark phases while reports are
serialized. Those are tool overhead, outside the sampled gameplay phases;
they are not attributed to the game. Full trace rows retain them for auditing.

## Implementation and limits

`WorkDustBurst.create_render_mesh()` builds the live MultiMesh format around
one shared box mesh and one shared material. Particle transforms and instance
colors remain private to each burst. No shader settings, colors, counts,
lifetimes, random draws or animation equations change.

`WorkFeedback` creates one invisible instance when it binds to a scene, while
the world is loading. The instance emits no sound, burst signal, particle
animation, loot or gameplay work. It stays alive for that scene and is freed
with other transient feedback on scene exit. Headless simulation skips the
warmup instance.

This moves initial graphics preparation into loading; it does not eliminate
the driver's compilation work. It adds one hidden instance per active scene
and retains the shared mesh/material. It does not prewarm every future effect,
change graphics drivers or alter project rendering settings.

With the fix, the first traced mining impact takes **13.078 ms for the whole
frame**, **2.332 ms for rendering**, and **0.239 ms for setup**. Its surface
compilation delta is zero. The eight-second first-pan sample has no frames
over 100 ms, but still has smaller CPU stalls. Diagnostic overhead and world
progress prevent treating this as a general FPS claim.

## Standard camera comparison

The ordinary benchmark, without the lifecycle trace, repeats the synthetic
30-dwarf yard with 20-second paused, first-active and later-active pan samples.
Both versions keep the earlier lighting fix and use the same benchmark.

| Frame measure | Before | After |
|---|---:|---:|
| First pan mean | 21.37 ms | 20.08 ms |
| First pan P95 / P99 | 38.66 / 51.27 ms | 37.44 / 48.05 ms |
| First pan maximum | 215.05 ms | 59.64 ms |
| First pan render setup maximum | 199.12 ms | 4.52 ms |
| First pan frames above 100 ms | 1 | 0 |
| Later pan mean | 21.11 ms | 20.99 ms |
| Later pan P95 / P99 | 36.62 / 44.28 ms | 37.67 / 45.28 ms |
| Later pan maximum | 62.07 ms | 61.83 ms |

The benefit is removal of the first-use spike, not a broad throughput increase.
The yard ends with **174/177 mined, 15/14 built and 46/30 stored items**
before/after. All work types progress, but scheduling diverges, so the small
mean/tail differences are not treated as reliable speedups or regressions.

The baseline completes sampling and writes its report, then hits the known
`DwarfAgent._exit_tree` hauling/global-transform error from 190. Its preserved
measurements are usable, but it is **not a clean validation pass**. The runner
rejects it and restores the final sources. The after-change run is launched
separately, completes sampling and shutdown with exit 0 and no errors. This
pass does not change dwarf shutdown behavior or conceal the baseline log.

## Longer settlement experiment

The input is the unchanged, developed five-dwarf settlement used in 190:
20 furniture pieces, 86 built blocks, 2,716 mined blocks and 79 wildlife.
Separate isolated copies run with 5, 20 and 30 dwarves. Additional dwarves use
the existing spawning code. Each copy receives the same nearby real-terrain
work: 64 mining blocks, 48 construction blocks, 160 stone and 80 logs. No
artificial floor or simulation-rate reduction is used.

The camera pans continuously at normal simulation speed. The harness enables
the real SaveManager and records frame intervals, subsystem CPU, memory,
node/resource counts, assignments, completions, pending work and oldest task
age. Frame data is stored numerically and written after sampling; only bounded
spike details and 30-second summaries are kept. Retained telemetry still uses
memory, so reported engine memory is not a clean leak measurement.

The following controlled triggers make infrequent events observable without
waiting several game weeks:

- At 30 seconds, request an autosave into the isolated profile.
- At 60 seconds, put the clock just before midnight and let it cross naturally.
- At 90 seconds, make wildlife opportunities due with a passing chance roll.
  Provider eligibility, population caps, route rules and member spacing remain.
- At 150 seconds, put the calendar just before the next season boundary.
- Leave the normal 300-second autosave timer running. The longer runs include
  its replacement save and backup rotation.

These are event stress tests, not natural arrival frequency measurements or
an hours-long soak. The populations share initial data but perform different
work; compare event costs and job progress rather than claiming pure scaling
speedups. A pending construction order also remains in this terrain fixture;
local placement validity does not establish a reachable work route.

All three native runs exit successfully, with no script/engine errors, failed
autosaves or task lifecycle errors. They run sequentially on the same Ryzen 7
9800X3D / Radeon RX 9070 XT, Godot 4.7.2 D3D12 Forward+ configuration.

| Copied settlement | 5 dwarves | 20 dwarves | 30 dwarves |
|---|---:|---:|---:|
| Sample duration | 330 s | 210 s | 330 s |
| Frames | 25,027 | 12,291 | 17,279 |
| Mean frame | 13.19 ms | 17.09 ms | 19.10 ms |
| P95 / P99 | 27.03 / 35.21 ms | 33.44 / 43.71 ms | 35.54 / 45.24 ms |
| Explicit autosave window peak | 868.01 ms | 840.96 ms | 855.15 ms |
| Natural autosave window peak | 1,427.49 ms | Not reached | 1,540.67 ms |
| Arrival window peak | 378.28 ms | 191.13 ms | 170.00 ms |
| Day boundary window peak | 42.99 ms | 75.27 ms | 53.82 ms |
| Season transition window peak | 84.96 ms | 89.83 ms | 106.73 ms |
| Frames above 100 ms | 7 | 2 | 4 |
| Added mined / built blocks | 64 / 3 | 64 / 3 | 64 / 3 |
| Net stored items / removed loose items | +54 / 57 | +54 / 57 | +54 / 59 |
| Added wildlife | 4 | 4 | 4 |

Event peaks are complete frames in declared windows, not isolated function
timings. Explicit save calls consume **796–826 ms** on the calling thread.
The natural autosave has **1,403 ms** in SaveManager at five dwarves and
**1,525 ms** at thirty. All five saves report success. Wildlife opportunities
admit one rabbit, one deer and two ducks; route preparation reaches **348 ms**
in WorldEventDirector. Different attempts and evolving world state mean the
lower arrival peaks at larger populations are not a scaling improvement.

The construction order ends pending in every copy, with its oldest wait
**168–286 seconds**. Only three of the 48 requested blocks are built. Mining
finishes all 64 blocks; hauling completes 18–21 tasks, but most supplied loose
items remain. These observations require a route/eligibility inspection before
assigning a cause. TaskManager's worst recorded wake is **46–60 ms**.

Node counts stabilize after the seasonal rebuild and four arrivals; sampled
orphan nodes stay at zero. Resources rise from 832 to 940 and then plateau.
Engine static memory starts/ends at **450/453, 461/469 and 467/472 MiB** for
5/20/30 dwarves. The telemetry, shared rendering resources, seasonal assets and
ordinary allocations are included, so this does not establish a memory leak
or rule one out. Post-season 30-second means rise from **13.80 to 14.99 ms**
at five dwarves and **17.94 to 19.69 ms** at thirty before the final autosave
window. That modest drift remains a follow-up for a longer, controlled soak.

Raw windows, full frame streams, event timelines and progress are retained in
[the evidence directory](concepts/events_20261015/README.md).

## Validation

All **10 headless fixtures** pass with exit 0 and no script/engine errors:
`WorkDustReuseTest`, `WorkFeedbackTest`, `MiningFeedbackTest`,
`MiningAnimationTest`, `TreeFellingTest`, `ConstructionTest`,
`JobMixedWorldTest`, `HaulingSelectionTest`, `SaveManagerRoundTripTest`, and
`WorldTerrainStartupTest`. The first three also pass in native D3D12.

The new test compares the frozen prior particle implementation against the
final source across three effect profiles, four seeds and five animation
steps: **60 exact poses**, including particle data, every transform/color and
expiration. It verifies shared mesh/material identity, hidden preparation,
absence of emitted work effects, and cleanup. Existing fixtures exercise
contact timing, pause/speed, slice and camera culling, cancellation, completion,
restore and bounds. The mixed-job fixture completes 2,124 invariant checks.

The native packaged-save check passes with the final PCK, five saved dwarves
and all 79 wildlife. It verifies hidden work-effect preparation and matching
live resources, 14 exact lighting image layers after a fresh update, idle
lighting cleanup, 245 construction obstacle comparisons, five hauling quotes,
slice behavior and offscreen wildlife movement. The exported executable also
generates its complete terrain overview and exits successfully with no errors.

Windows playtest:

- [Deepdraft.exe](P:/Deepdraft/build/windows/releases/20261015-170106-918-1d28ea4f/Deepdraft/Deepdraft.exe)
- [Playtest ZIP](P:/Deepdraft/build/windows/Deepdraft-Windows-Playtest.zip) — 76.9 MiB
- ZIP SHA-256: `7c0362b931ecbb11f8bf6a0b9cb8d19b956da68e6b19a2c4c138a169904b23c4`

The archive contains only the four expected runtime files, all byte-identical
to the tested release. The original player save and the frozen input copy keep
SHA-256 `f223eee6dfe52fefe6add9a763362640f02c439fb2f33687f550661fb9cc148b`.
The previous lighting implementation is unchanged. All final production
sources match their recorded hashes. Restart Play or use the new executable
to test; no project reload is needed for new global classes or autoloads.

## Next priorities

1. **Autosave:** profile snapshot construction, serialization, validation and
   safe file replacement separately. Preserve the consistent snapshot, validated
   primary/backup behavior and completion/error reporting when moving work out
   of the frame. Natural autosave frames reach 1.43–1.54 seconds, including
   1.40–1.52 seconds in SaveManager.
   In the current code, `_commit_snapshot` validates the temporary file,
   `_rotate_primary_to_backup_if_valid` validates the old primary and staged
   backup, and `_replace_primary_with_temp` validates the installed primary.
   Time these reads/parses/validations separately from snapshot construction,
   JSON encoding and file I/O. Extra backup work is a plausible explanation
   for the slower replacement save, not yet a measured stage attribution.
2. **Arrival route preparation:** the first settlement test records up to
   348 ms in WorldEventDirector during arrival preparation. A bounded number
   of route attempts is not necessarily a small time budget. Measure provider
   and navigation stages before changing the scheduler or species behavior.
3. **Construction waiting and steady CPU:** investigate the pending order's
   access and worker needs, together with repeated scheduling probes. More idle
   workers must not count as a performance win. Extend the soak beyond these
   few-minute tests once the event stalls are addressed.

The season transition is a smaller, separate hitch. Revisit it after saving
and arrival preparation; fog of war would not address these measured causes.
