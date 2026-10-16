# 196 — Shared atmosphere performance · 2026-10-15

Fog, sky and directional-scattering data now live in one texture per lighting
owner. Materials bind that texture once. Updating the atmosphere no longer
rewrites each changing uniform on roughly 1,300 materials.

This implements the next rendering opportunity identified in
[195](195_normal_speed_rendering_profile.md), preserving the existing appearance
and live day/night/weather changes. Construction and eligibility work remain
deferred for the drop-box and timed-building discussion in
[193](193_arrival_preparation_performance.md).

## Implementation

`UndergroundLighting` retains its existing environment selection, camera override,
light discovery, comparison cache and maximum 20 Hz update cadence. If any value
changes, `SceneAtmosphereData` packs the complete cached state into a 20×1 RGBA
float image and updates the existing `ImageTexture`: **one 320-byte upload**.
Unchanged data does not upload. Newly created materials bind the same resource
and immediately see its current contents.

The shader reads the packet and evaluates the same atmosphere equations. Colours
previously marked `source_color` are converted from sRGB to linear when packed;
numeric fields are raw, and sunlight already converted by the owner is not
converted again. The matrix uses the same three basis columns. Full float
precision retains the original numeric range, including HDR colours.

The texture belongs to the scene's lighting owner. It is neither a project-wide
shader global nor an autoload. Separate viewport owners have independent data;
scene reload recreates the packet from the current environment. No save fields,
render settings, world simulation, roof/door gates, actor exposure or water
animation rules change. The helper has no `class_name` registration.

## Native measurements

The same copied settlement and normal-speed workload from 195 are used: 30
dwarves, 79 wildlife, 2,925 trees, 64 mining targets, 48 construction targets and
240 loose supplies. Each run samples 30 seconds stationary, then two 30-second
camera pans, with eight seconds of warmup per phase. Calendar speed is x1,
60 seconds per game hour, from approximately 21:13 to 23:08 on summer day 3.
Autosave and arrival scheduling are disabled for these recurring-cost samples.

Native runs are sequential at 2560×1440, Godot 4.7.2 Steam / D3D12 Forward+,
Ryzen 7 9800X3D and Radeon RX 9070 XT, VSync disabled. Two production-source
controls measure the new path; one temporary instrumented run separates CPU
costs. The old implementation is also repeated after those runs to check against
machine/session drift. Instrumentation and the old-path repeat restore exact
source bytes before regression testing or packaging.

Ranges below are the two uninstrumented controls for each implementation. The
before runs are retained in 195; all rows use live atmosphere and full simulation.

| Phase | Before mean ms | Shared mean ms | Before P95 ms | Shared P95 ms |
|---|---:|---:|---:|---:|
| Stationary, initial active work | 25.89–27.81 | 19.28–21.04 | 46.16–46.89 | 36.30–39.39 |
| First camera pan | 20.08–21.36 | 16.16–16.40 | 36.70–38.10 | 29.91–30.95 |
| Later camera pan | 16.44–17.20 | 13.04–14.16 | 31.39–32.67 | 26.19–27.47 |

Using the mean of the two controls, whole-frame time falls **25%, 21% and 19%**
respectively. First-pan throughput rises from about 47–50 to 61–62 FPS; the later
pan reaches 71–77 FPS. P95 remains above the 16.67 ms budget, so this is not a
claim of consistently paced 60 FPS. Maximum frames fall from 82–88 / 88–98 /
48–52 ms to 67–76 / 67–74 / 43–46 ms across the three phases. Neither new control
has a frame above 100 ms.

Mean render-setup CPU falls from 1.55–1.80 / 1.41–1.63 / 0.90–1.03 ms to
0.20 / 0.18 / 0.15 ms. First-pan setup is about **88% cheaper**. GPU means remain
around 2.7–3.0 ms: first-pan GPU averages 2.97 ms before and 2.94 ms after; the
later pan is 2.83 versus 2.91 ms. No material GPU regression is apparent in these
runs, but this measurement is specific to the tested renderer and hardware.

Repeating the old implementation afterwards gives mean frames of **28.73 /
20.20 / 17.97 ms**, P95 of 49.31 / 36.23 / 34.78 ms, and render setup of 1.91 /
1.52 / 1.09 ms. The first pan closely matches the earlier baseline; the old
stationary/later phases are slightly slower. This supports the improvement
without assuming the machine's timing is perfectly repeatable.

Each new run still records four pipeline specializations, as in 195. Sharing
atmosphere data does not eliminate every source of rendering work or frame spikes.

The detailed run reduces direct fog-update CPU from 1.37–1.49 / 1.13–1.18 /
0.66–0.69 ms per frame to **0.022 / 0.016 / 0.012 ms**. Its maximum is 0.167 ms,
versus the prior 6.738 ms. These are per-frame means including frames without an
update. The new path performs approximately 16.1 / 16.7 / 12.6 small texture
updates per second; changed-value material broadcasts are eliminated. Live
atmosphere still advances at the original cadence rather than being frozen.

Mining finishes in every run. Construction and hauling continue, with small
variations in progress: new controls build two or three blocks and store 31–34
items during the initial sample, then store another 15–17 during the first pan.
The old controls build two or three and store 31–33, then another 19–20. These
are timing-driven simulations, not identical execution traces. The world also
advances between phases; later-pan timings do not establish that camera motion
is cheaper than standing still.

## Appearance and correctness

`AtmosphereSharingTest` renders the frozen prior shader and new shader through
the same camera and geometry. Eight comparisons cover noon, evening, midnight,
procedural sky with HDR/height fog, both sky hemispheres, nonidentity sky rotation,
four directional lights, exponential/depth modes, camera overrides and fog
disable/re-enable. Every case includes full, partial and zero sky access.
All eight image pairs are pixel-identical on the target native renderer.

The same fixture checks stable texture identity across updates, material cache
reuse, late-created materials, independent viewport owners and fresh owner
recreation. Existing native lighting fixtures cover real terrain, dark rooms,
doors, torches, entrance transitions, slice concealment, dwarves and portraits.

All ten final fixtures pass: the new 33-check `AtmosphereSharingTest`, plus
`UndergroundLightingTest`, `TunnelEntranceTest`, `RoomLightingTest`,
`DoorLightingTest`, `DwarfLimbLightingTest`, `TerrainAppearanceTest`,
`WeatherPersistenceTest`, `SkySceneLifecycleTest` and `SaveManagerRoundTripTest`.
The room fixture measures 0.019 luminance with the door closed and no internal
light, and 0.243 with the internal brazier. Dwarf checks pass all 32 paired colour
samples across skin tones and daylight/torchlight.

The first dwarf fixture run passed its colour assertions but reported a shader
cache directory error: the runner inserted an empty segment in its profile path.
Normalizing that path gives a clean rerun. Both attempt logs are retained. No
production lighting change was needed for that harness issue.

The native exported-PCK check passes **3,494 assertions** on the copied original
five-dwarf settlement. All 869 restored materials share the correct scene packet;
noon/evening/midnight stay live without changing its RID. A real asynchronous
save/reload creates a fresh texture with byte-identical midnight data and retains
all five dwarves and 79 animals. Day/night captures were inspected. The actual
release executable also completes all 1,024 overview tiles with zero terrain
validation mismatches and exits cleanly.

## Playtest build

- Executable: `build/windows/releases/20261015-194526-942-648e8027/Deepdraft/Deepdraft.exe`
- ZIP: `build/windows/Deepdraft-Windows-Playtest.zip` — 80,657,629 bytes (76.9 MiB).
- ZIP SHA256: `3a3835d59b2785f1ee155c028d6455fee9df0d81443cac7d27bce47d392bff0f`.

The four ZIP entries match the release files byte-for-byte. The export includes
runtime JSON definitions and excludes development tools, tests and evidence.
Restart Play or launch this executable. No project reload is required for a new
global class or autoload because this change adds neither.

## Evidence and next work

Evidence is retained under
[`concepts/shared_atmosphere_20261015`](concepts/shared_atmosphere_20261015/).
It includes raw compressed frame rows, reports, source snapshots, image pairs,
test logs and hashes. The player's original save is checked against the input
copy; benchmarks and packaged save/load use isolated storage.
The audit checks all 342 existing script/shader files: only the intended lighting
owner and shader differ. The new helper/test and diagnostic tools are recorded
separately. Prior uncommitted work and historical fixture captures are preserved.

**Water deferred — user direction, 2026-10-15:** the player is unhappy with the
current water appearance and wants to revisit it in another session. Park the
proposed water-focused 20–30-minute profile and further water changes. Discuss
the desired appearance alongside performance when resuming; preserving the
current look is not an accepted objective for that future work. No water change
is made by this deferral.

The retained trace identifies water presentation at 2.8–3.8 ms/frame, including
mesh work, and simulation at another 1.4–2.3 ms with peaks near 17 ms. These are
investigation leads for the later session, not a diagnosed cause of the visual
concern or approval to optimize it now.

A longer general normal-speed 30-dwarf session through autosaves, arrivals and
seasonal transitions remains a follow-up. Short phase measurements do not
establish hours-long stability. Remaining work should follow measured frame
spikes rather than introduce fog of war or change the colony-size direction.
Construction/eligibility and the project review findings in 177 remain parked.
