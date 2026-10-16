# 195 — Normal speed rendering profile · 2026-10-15

**Follow-up:** [196 — Shared atmosphere performance](196_shared_atmosphere_performance.md)
implements and validates the shared-data recommendation below.

The 30-dwarf evening settlement is primarily limited by CPU work. The best next
rendering change is to share scene-wide fog and sky data instead of broadcasting
each changing value to roughly 1,300 materials. Dwarf lighting checks are a smaller
recurring cost. Terrain's own update callback is inexpensive once excavation
settles; the earlier broad renderer timing included water and lighting children.

This investigation adds diagnostic tools and retained measurements. Production
gameplay and rendering behavior remain as shipped in [194](194_gradual_season_transition.md).
Construction and repeated eligibility checks stay deferred for the drop-box and
timed-building design discussion in [193](193_arrival_preparation_performance.md).

## Normal speed scenario

Five native runs load independent copies of the same developed five-dwarf save
and expand it through normal spawning to 30 dwarves. The existing workload adds
64 mining blocks, 48 construction blocks and 240 loose supplies. The scene has
79 wildlife, 2,925 trees and 20 installed furniture objects. It is an expanded
developed settlement, not a colony grown organically to 30 dwarves.

The calendar starts on summer day 3 around 21:13 and retains normal x1 speed:
**60 real seconds per game hour**. Each run samples 30 seconds stationary,
30 seconds panning and 30 seconds panning again, with eight seconds of warmup
before each phase. The clock reaches approximately 23:08. Needs, movement,
work, water, wildlife and lighting run normally. Autosave and arrival scheduling
are disabled to isolate recurring cost; no seasonal boundary is forced.

Two runs use production sources without method timers or process markers. Two
use temporary method timers plus the established subsystem markers. A fifth
production-source run reduces resolution from 2560×1440 to 1280×720. All use
Godot 4.7.2 Steam, D3D12 Forward+, Ryzen 7 9800X3D / Radeon RX 9070 XT, VSync off,
no FPS cap, the saved clear weather and the normal slice at 127. Native runs
are sequential. The camera orbits the colony at zoom 48.

## Whole-frame measurements

Ranges below are the two 1440p controls, without the detailed timers.

| Phase | Mean frame ms | P95 frame ms | Maximum frame ms | Mean GPU ms |
|---|---:|---:|---:|---:|
| Stationary, initial active work | 25.89–27.81 | 46.16–46.89 | 81.60–87.55 | 2.86–3.00 |
| First camera pan | 20.08–21.36 | 36.70–38.10 | 88.01–97.70 | 2.93–3.01 |
| Later camera pan | 16.44–17.20 | 31.39–32.67 | 48.02–52.01 | 2.77–2.88 |

The first pan averages approximately 47–50 FPS and the later pan 58–61 FPS, but
P95 remains well above the 16.67 ms budget for consistently paced 60 FPS. Neither
control has a frame above 100 ms. The world advances between phases: mining and
much of the hauling subside, while the sky changes from evening toward night.
These rows do not show that panning is cheaper than a stationary camera.

At 720p, mean frame times are **27.48 / 21.13 / 17.04 ms**, while GPU times fall
to **1.67 / 1.88 / 1.83 ms**. Removing 75% of the pixels does not materially lower
whole-frame time beyond the variation between the 1440p controls. Main-viewport
GPU timestamps support a CPU diagnosis for this scene; they may lag and do not
measure every viewport or establish performance on other hardware.

Each normal run records four pipeline specializations on frames between 17 and
41 ms. Those are not its largest hitches. The fog intervention records one on a
frozen frame; excluding that frame changes the frozen mean by only 0.01 ms.

## Where the rendering CPU time goes

The following means come from the two detailed runs. They are attribution
measurements, not an optimization comparison. Added timing and normal live-job
variation mean they should not replace the production-source controls.

| Work | Initial active work, ms/frame | First pan, ms/frame | Later pan, ms/frame |
|---|---:|---:|---:|
| Renderer callback itself | 0.91–0.99 | 0.21–0.22 | 0.20 |
| Underground lighting, inclusive | 3.81–4.01 | 1.75–1.81 | 1.26–1.31 |
| ↳ Fog/sky material broadcasts | 1.37–1.49 | 1.13–1.18 | 0.66–0.69 |
| ↳ Dwarf mesh lighting synchronization | 0.60–0.61 | 0.61–0.62 | 0.59–0.61 |
| ↳ Light-field solver loop | 1.84–1.90 | ~0.001 | ~0.001 |
| Water presentation, sibling process bracket | 3.89–3.93 | 3.48–3.64 | 3.07–3.12 |

Indented lighting rows are inside the inclusive lighting total. The broad
`DebugWorld/Renderer` bracket includes water, lighting and other children; it
averages 8.99–9.31 ms during the busy phase, while its own callback uses less
than 1 ms. Do not add nested timings.

### Fog and sky broadcasts

`UndergroundLighting._sync_fog()` checks approximately every 50 ms and distributes
each changed fog, sun, moon or sky value to every cached material. The cache
contains **1,318–1,326 materials** in these runs. The first detailed run records
about **96,000–133,000 material-parameter writes per second**, depending on the
phase. Individual calls take up to **5.67–6.74 ms** across the two detailed runs.
This is atmospheric fog presentation, separate from gameplay fog of war.

The cost also correlates with deferred render setup. In the first detailed pan,
frames with fog writes average **4.01 ms** of render setup, compared with
**0.21 ms** on other frames. Main-viewport GPU time remains around 2.8–2.9 ms in
both groups. The targeted intervention below tests this connection directly.

### Controlled fog intervention

A sixth native run lets the normal workload settle for 60 seconds, then alternates
live broadcasts with a diagnostic that skips only `_sync_fog()`. Three ABBA groups
balance both halves of the camera orbit and time drift. Each block discards one
second after switching and samples the next three seconds, giving 18 sampled
seconds per condition. Clock, actors, light-field updates, water, wildlife and the
main sky continue normally. World-material atmosphere values are deliberately
stale during frozen blocks; this is not an acceptable shipping behavior.

| Metric | Live broadcasts | Frozen broadcasts |
|---|---:|---:|
| Mean whole-frame time | 18.60 ms | 15.98 ms |
| P95 whole-frame time | 33.83 ms | 29.39 ms |
| Maximum whole-frame time | 55.79 ms | 60.66 ms |
| Mean render setup | 1.15 ms | 0.18 ms |
| Mean direct fog callback | 0.82 ms | 0 ms |
| Mean main-viewport GPU time | 2.95 ms | 3.06 ms |

Mean frame time falls **14.1%**, P95 falls **13.1%**, and render setup falls **84%**.
All three ABBA groups have lower mean frame time with broadcasts frozen. The
frozen samples perform zero material fog writes; live samples perform 1.92 million.
This supports a causal CPU cost from the broadcasts, including deferred render
setup. It does not promise a 14% shipping gain: the replacement still needs to
update shared data, the world keeps evolving, and these are short evening samples.
The higher frozen maximum also shows that unrelated hitches remain.

### Actor checks and excavation

Lighting revisits roughly **407–420 dwarf mesh entries** for 30 actors each
frame, validating weak references, ancestry and viewport ownership. Body-center
samples account for about **0.15–0.21 ms** within the **0.6 ms** synchronization
total. Changed shader-instance values are already rare; neither detailed run
writes any during the final pan. A later improvement could organize these
bindings by actor and invalidate them on attachment/removal, preserving body
sampling and released-item behavior.

The light-field solver consumes its existing budget while mining changes terrain,
then becomes effectively idle. It is not a permanent 2.5 ms charge. Its observed
loop maximum is 2.67 ms, and light texture uploads stay below 0.26 ms across both
detailed runs. The former large buffer-disposal stall does not recur.

Excavation also rebuilds the cavity shell. Those calls reach **9.6 ms** and
contribute to renderer-callback peaks of **12–14 ms** during active mining.
This is a separate event-cost opportunity after shared atmosphere updates.
Terrain callback maxima stay below 0.84 ms in both sampled pan phases after
the mining finishes.

## Remaining work and next implementation

The next rendering implementation should deliver changing atmosphere values
through **shared scene-owned data**, retaining per-material tint/roughness and
per-instance actor/door properties. Preserve live day/night/weather changes,
sealed-room darkness, entrance transitions, water, newly attached tools/items,
portrait/preview isolation and scene teardown/reload. The optimization must
keep the appearance current; freezing fog is only a diagnostic intervention.

Validate it with the same production-source controls and focused native lighting
checks. Measure both the direct broadcast callback and render setup, rather
than claiming success from callback time alone. This is the proposed next task;
no rendering optimization is implemented by this profile.

Water presentation and wildlife remain larger aggregate steady costs than actor
lighting alone. The largest first detailed-run frame is 107.50 ms, including
55.75 ms in `TaskManager`; ordinary water-simulation updates also reach about
16 ms. A lighting change will not remove those costs. Scheduling stays parked
for the intended construction redesign. A normal-speed 30–60 minute soak with
autosaves and arrivals enabled remains a separate follow-up.

## Evidence and handoff

[Raw evidence and reproduction notes](concepts/steady_rendering_20261015/README.md)
retain controls, detailed runs, per-frame samples, source snapshots and input
hashes. Each native run uses isolated APPDATA/LOCALAPPDATA and a copied save.
Temporary instrumentation is restored byte for byte; the audit checks all
337 production GDScripts against their starting hashes.

All six native runs exit 0 with their completion markers and no script/engine
errors. Existing pre-world sky/weather warnings are retained in the logs. The
normal runs contain 15 sampled phases; the intervention contains 12 balanced
blocks. Scheduler lifecycle checks pass. All 30 dwarves and 79 wildlife remain.
Both the player save and copied input retain SHA-256
`f223eee6dfe52fefe6add9a763362640f02c439fb2f33687f550661fb9cc148b`.
The measurements do not validate long-session memory behavior or every lighting
scene; functional lighting regression and native visual checks belong to the
subsequent optimization, since no production source changes remain here.

There is no new global class, autoload, save schema or release build in this
profiling pass. The Windows release from 194 remains the current build. Findings
in 177 remain parked, and no population cap or fog-of-war system is introduced.
