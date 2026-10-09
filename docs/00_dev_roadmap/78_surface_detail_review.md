# 78 — Combined surface-detail review

Status: **initial review complete, 2026-10-08; current density retained.**

Review of steps 9–10 in [72 — Surface details plan](72_surface_details_plan.md),
covering boulders, scree, shrubs, flowers and lakeside reeds together.

## Density and visual assessment

Keep the current density, art scales and placement settings. Twelve seeds have
2,109–2,341 clumps per 1024×1024 world. Their logical support footprints cover
0.35–0.40% of the map; blocking boulders cover 0.019–0.032%. The busiest 64×64
regions have 16–23 clumps and at most 1.66% support coverage. Coverage counts
support tiles, not pixels, leaf overhangs or tree canopy; regional footprints are
assigned to the region containing their origin.

Native views at normal zoom and closer inspection show open ground between
plants, scattered boulders and localized rubble. Flowers remain small accents.
Reeds leave broad gaps along banks, including a sparse four-clump seed. No
continuous reed border, rubble carpet or additional reserved clearing was found
in the reviewed scenes. Large tree canopies can obscure individual small plants;
exposed examples remain selectable and the area tools handle grouped clearing.
Winter stems are deliberately less conspicuous than summer foliage.

The review does not set new per-seed quotas. Suitable habitats, gaps and the
player's ability to clear their own location remain the placement criteria.

## Coverage and reproducibility

`SurfaceDetailLayoutTest --review` exercises the eight established seeds
0, 1, 2, 7, 42, 1234, 65535 and 20261007, plus four seeds chosen before tuning:
17, 91, 2026 and 8675309. All twelve pass forward/reverse ordering and fresh-owner
restore, support/ground/moisture/water checks, gaps and removal persistence.
Terrain, water and tree fingerprints stay unchanged. Established populations
match the exact pre-review counts; all categories are present in the four new
seeds without forcing them.

`tools/SurfaceDetailCensus.gd` reads actual accepted records. It records counts,
support areas, ground materials, elevation ranges, habitat labels and 64×64
regional density. It does not generate a second approximation of the layout.

`tools/SurfaceDetailReview.gd` captures native game scenes for seeds 7, 17, 1234
and 20261007. Targets are chosen deterministically from accepted records: a
dense region, cliff foot, mountain boulder, shore and central wide view. The
dense view is also captured in all four seasons. An identical scripted pan/zoom
path is measured in enabled and disabled runs. Slicing hides all above-plane
detail picking and restores visibility afterwards. Season, camera, inspection
and slice operations leave no saved plant edits. Seed 1234 also checks exposed
mesh picking and inspector presentation for all seven category keys, including
the three shrub species.

The existing worker/Orders/save tests from milestones 73–77 remain the integrated
gameplay evidence; this review adds multi-seed spatial and native presentation
coverage rather than changing the clearing or reward rules.

## Performance method

Each seed runs in two separate native processes: current details enabled, then
all definitions disabled in that process's temporary registry. Live JSON and
project settings are untouched. The baseline uses the enabled run's exact
camera targets. Trees, terrain, water, lighting, UI and the rest of the scene
remain enabled. Runs are sequential and use isolated APPDATA/LOCALAPPDATA.

Hardware/backend: AMD Radeon RX 9070 XT, Godot 4.7.2 Steam, D3D12 Forward+,
1600×1000. VSync is disabled and the FPS cap removed only in the review process.
Both modes use identical seasonal cache warmup, screenshots and settling waits.
Each steady/panning sample spans at least two seconds and 180/240 complete
rendered frames. Engine frame indices verify the sample count. Viewport GPU/CPU
timestamps distinguish rendering cost from loop timing; the coarse process-time
monitor is not used as a frame benchmark.

These are paused early-world samples on one GPU, not a populated colony stress
test or a lower-end hardware guarantee. Memory figures are whole-process deltas
after matching camera/cache sequences, not allocations attributed precisely to
individual clumps. Ready time means full overview and flora/detail queues have
settled; it is later than the first playable terrain.

## Measured results

The following paired results were recorded before the small queue-only
optimization below. Across 24 camera samples, the median GPU difference is
−0.010 to +0.073 ms; the small negative result is run variation, not a claimed
speedup. The current populations do not justify cutting density or replacing
the renderer with region batching. Detail layout/registration costs roughly
0.57–0.61 seconds during world loading. Ready-time variation includes overlapping
terrain/tree work, so these single-run differences are not isolated detail cost.

| Seed | Boulders | Scree | Shrubs | Flowers | Reeds | Support coverage | Max clumps / 64×64 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 0 | 81 | 205 | 1003 | 914 | 18 | 0.391% | 22 |
| 1 | 83 | 183 | 1084 | 835 | 9 | 0.373% | 17 |
| 2 | 64 | 227 | 1003 | 850 | 8 | 0.397% | 16 |
| 7 | 76 | 180 | 1100 | 974 | 11 | 0.382% | 17 |
| 42 | 62 | 208 | 1085 | 793 | 20 | 0.383% | 19 |
| 1234 | 58 | 192 | 1073 | 804 | 15 | 0.367% | 17 |
| 65535 | 77 | 140 | 1159 | 908 | 10 | 0.348% | 17 |
| 20261007 | 51 | 170 | 1121 | 933 | 4 | 0.362% | 21 |
| 17 | 85 | 194 | 1061 | 821 | 7 | 0.379% | 16 |
| 91 | 78 | 196 | 961 | 861 | 13 | 0.373% | 17 |
| 2026 | 80 | 206 | 1107 | 770 | 13 | 0.388% | 17 |
| 8675309 | 82 | 188 | 1079 | 954 | 14 | 0.388% | 23 |

| Seed | Layout, ms | Ready without / with, s | Extra nodes | Static / renderer memory delta, MiB |
|---|---:|---:|---:|---:|
| 7 | 573.7 | 7.99 / 8.24 | 7099 | 31.5 / 18.2 |
| 17 | 570.3 | 7.71 / 7.56 | 6589 | 29.5 / 18.2 |
| 1234 | 585.7 | 7.93 / 7.98 | 6484 | 29.1 / 18.2 |
| 20261007 | 611.6 | 8.38 / 8.45 | 6888 | 30.5 / 18.2 |

| Seed / view | GPU median without / with, ms | Draw calls without / with | Frame P95 without / with, ms |
|---|---:|---:|---:|
| 7 / dense | 0.337 / 0.342 | 100.0 / 125.0 | 0.984 / 0.983 |
| 7 / wide | 0.375 / 0.412 | 211.0 / 246.0 | 0.900 / 1.128 |
| 7 / pan_zoom | 0.321 / 0.343 | 93.3 / 110.8 | 0.933 / 1.012 |
| 17 / dense | 0.320 / 0.356 | 136.0 / 162.0 | 0.809 / 0.916 |
| 17 / wide | 0.407 / 0.480 | 294.0 / 345.0 | 0.922 / 1.187 |
| 17 / pan_zoom | 0.325 / 0.381 | 132.2 / 157.1 | 0.815 / 1.100 |
| 1234 / dense | 0.323 / 0.353 | 120.0 / 147.0 | 0.808 / 0.893 |
| 1234 / wide | 0.389 / 0.407 | 195.0 / 229.0 | 0.990 / 1.061 |
| 1234 / pan_zoom | 0.335 / 0.356 | 123.6 / 148.4 | 0.930 / 0.932 |
| 20261007 / dense | 0.325 / 0.351 | 94.0 / 116.0 | 0.874 / 0.969 |
| 20261007 / wide | 0.369 / 0.412 | 195.0 / 228.0 | 0.943 / 1.134 |
| 20261007 / pan_zoom | 0.341 / 0.331 | 96.5 / 113.4 | 0.946 / 0.833 |

## Targeted optimization and remaining limit

The seasonal callback searched the growing visual queue once per plant. Replacing
those repeated linear searches with a temporary membership dictionary preserves
the original queue prefix, candidate order and twelve-per-frame visual budget.
No placement, art, reward, task or save schema changed.

`SurfaceDetailSeasonReview.gd` isolates this work on the real seed-1234 layout:
2,142 total records, of which 1,892 are seasonal plants. Fifteen repetitions per
case check exact queued identities and pending-prefix order.

| Queue at season change | Before median / P95, ms | After median / P95, ms |
|---|---:|---:|
| Empty | 9.820 / 10.979 | 3.234 / 3.530 |
| Half pending | 9.918 / 11.058 | 3.262 / 3.515 |
| All plants already pending | 9.834 / 10.897 | 3.185 / 3.251 |

This removes about two-thirds of **enqueue work**, not two-thirds of a complete
season transition. Full-world seasonal rebuilding remains a separate limitation:
the pre-optimization paired runs recorded individual frames up to 178 ms without
surface details and 194 ms with them. The existence of spikes in the baseline
means reducing detail density would not remove the underlying full-scene work.
A broader tree/material/rebuild profile is the next performance investigation if
season transitions become a playtest priority. No general hitch-free claim is made.

FlowerPilotTest, ReedPilotTest and ShrubPilotTest pass after the optimization,
including active work through season changes, removals, harvest state and worker
release. The queue fixture passes empty, partly pending and fully pending cases.
SaveManagerRoundTripTest also passes manual save, autosave and corrupt-primary
backup recovery after the optimization, with complete owner snapshot equality.
The final native seed-1234 rerun (`optimized_report.json` and `optimized_…png`)
passes seasonal swaps, all category picking and slice checks. Its complete
census, camera targets and populations exactly match the earlier run, and no
viewing action creates a saved plant edit.

## Evidence and commands

All reports, logs and native PNGs are under `tmp/surface_review/`. The native
per-seed folders contain matching `details_…` and `baseline_…` views and reports.
`layout_report.json` records the census and layout assertions.
`tools/summarize_surface_review.py` verifies matching targets, frame counts,
successful checks and nonzero GPU timestamps, then writes `summary.json` and
`tables.md` for the report.

Run Godot with `--path P:\Deepdraft --script res://scripts/tests/SurfaceDetailLayoutTest.gd -- --review`
in headless mode for the twelve-seed checks. For native captures, run
`res://tools/SurfaceDetailReview.gd -- --seed=1234`, then the same command with
`--baseline`. Use an isolated APPDATA path below `tmp/surface_review` as required
by the tool, and run performance samples sequentially.

## Scope after this review

The five-category surface-detail implementation is complete. Future population
increases should repeat this comparison before changing density or introducing
region batching. Lower-end hardware and a working colony remain separate
performance coverage. Planting recovered cuttings, food processing, reed/fiber
crafting and the required seasonal wildflower/honey connection are future
gameplay milestones, not changes made by this review.

**Subsequent work, 2026-10-09:** planting recovered cuttings shipped in
[80](80_shrub_cutting_growth.md); [85](85_plant_habitats_spacing_flowers.md) adds
soil-only wild berries below Y44, 3×3 planting reservations and flower relocation.
Its eight-seed census reflects those later habitat/spacing changes. The numbers
above remain the historical pre-change review, not current population targets.
Food processing, reed uses, honey and the broader season-transition performance
work remain deferred. See [89 — Session handoff](89_session_handoff_2026_10_09.md).
