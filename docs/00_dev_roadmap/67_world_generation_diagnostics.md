# 67 — World generation diagnostics and tin reachability

Implemented 2026-10-07 after the seeded-layout, rough-cliff/shore and starting-area
removal work in [66](66_seeded_world_layout.md). This follow-up corrects surface
measurements and copper/tin precedence. Cave generation was kept separate in this
pass and subsequently implemented in [68 — Caves and discovery](68_caves_and_discovery.md).

## Changes

- Surface coverage counts the actual generated block at the higher of the solid
  surface and waterline for all 1,048,576 columns. Counts and percentages include
  water and are broken down by domain. This is top-view coverage of the initial
  generated world, not exposed cliff area, underground volume or player edits.
- The debug panel/log use current layout and finished-terrain measurements:
  summit columns, connected mountain cells, detailed columns, dry shores,
  attempts and fallback status. Obsolete fixed-compass, reserved-settlement and
  unused smoothing counters are removed. The panel labels metrics as pending
  while their background census is still running.
- Tin's JSON threshold changes from **0.66 to 0.64**. Copper previously won every
  shared-channel match at Y55–88 because both used 0.66. Tin now has the noise
  interval `(0.64, 0.66]` there. Depths, order, other thresholds, durability,
  drops, gems and soil rules stay unchanged.

## Verification

`WorldResourceDiagnosticsTest.gd` records the pre-fix baseline and corrected
results for seeds **7, 1234, 65535 and 20261007**. It independently classifies
publicly queried top blocks through BlockRegistry kinds, compares every global
and domain count/percentage, and samples all solid depths from Y4 on an 8-block
horizontal grid (x/z 4, 12, …, 1020). That is **1,835,136 sampled blocks** across
the four seeds, not a full ore-volume census.

| Seed | Tin at Y55–88 before | Tin at Y55–88 after | Copper at Y55–88, unchanged |
|---|---:|---:|---:|
| 7 | 0 | 1,037 | 2,183 |
| 1234 | 0 | 2,078 | 4,378 |
| 65535 | 0 | 1,681 | 3,807 |
| 20261007 | 0 | 1,384 | 3,315 |

Across the complete sample, tin increases from **1,381 to 7,891** blocks; coal
decreases from **116,652 to 110,322** (about 5.4%). Above coal's window, tin also
replaces some ordinary rock. Gold, silver, iron and copper counts at every depth
are unchanged. Height/water map fingerprints and actual top-surface counts are
identical before and after. This is a reachability correction; it does not settle
ore abundance, vein shape or economy balance across all seeds.

The old surface diagnostic was materially wrong. For seed 1234 it reported
42.47% grass, 28.78% dirt and 26.72% rock; the actual generated top columns are
**75.47% grass, 0.89% dirt and 21.61% rock**, with 2.03% water. No surface block
was changed to obtain those numbers.

Additional passing checks:

- Every metal retains a reachable noise interval at every configured depth;
  exact threshold and inclusive depth boundaries are checked.
- Sampled copper/tin blocks survive rebuilding seeded noise and match stored
  streamed chunks; slice strata still conceal them. Sampled ores remain below
  the surface and outside the protected perimeter.
- `WorldGenerationTest.gd`: all **8 seeds** pass finished-layout, Y115 summit,
  rough cliff/shore, water streaming, natural flag placement, navigation,
  mining/materialization, flora exclusion and authored-strata checks.
- Native seed-1234 debug-panel capture inspected for populated, readable
  measurements. The capture waits for metrics as well as the rendered overview;
  it moves the debug panel below the normal HUD solely for review framing.
- No script errors in the test/render logs; `git diff --check` passes.

Reports and capture:
[before](../../tmp/world_layout_review/resource_diagnostics_before.json),
[after](../../tmp/world_layout_review/resource_diagnostics_after.json),
[debug panel](../../tmp/world_layout_review/live_1234_diagnostics.png).
Logs are `diagnostics_before.log`, `diagnostics_after.log`,
`diagnostics_regression.log` and `diagnostics_render.log` in the same directory.

## Reproduce current checks

Run from `P:\Deepdraft` with an isolated profile:

```powershell
$env:APPDATA = 'P:\Deepdraft\tmp\world_layout_review\appdata'
$env:LOCALAPPDATA = 'P:\Deepdraft\tmp\world_layout_review\localappdata'
New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA | Out-Null
$godotPath = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
$diagnosticsRun = Start-Process -FilePath $godotPath -WindowStyle Hidden -Wait -PassThru -ArgumentList '--headless --path P:\Deepdraft --log-file P:\Deepdraft\tmp\world_layout_review\diagnostics_after.log --script res://scripts/tests/WorldResourceDiagnosticsTest.gd'
if ($diagnosticsRun.ExitCode -ne 0) { throw 'Diagnostics checks failed; read the log.' }
Select-String -Path tmp/world_layout_review/diagnostics_after.log -Pattern 'SCRIPT ERROR|ERROR:|FAIL'
# Gameplay regression: --script res://scripts/tests/WorldGenerationTest.gd
# Native capture (omit --headless): --script res://tools/WorldLayoutLivePreview.gd -- --seed=1234 --diagnostics
```

The test's `--baseline` mode only records the behavior of the code currently
installed. The saved before-report came from the pre-fix implementation; running
that flag now does not recreate it.

## Follow-up

The unreachable cave fallback was replaced by the dry connected cave systems in
[68](68_caves_and_discovery.md), including surface/water separation and discovery
through mining. The resource measurements above record the pre-cave world and
are retained as historical evidence, not a new census of remaining cave-world ore.
The equal diamond/emerald thresholds were subsequently corrected in the
[resource review](69_resource_distribution_review.md); this historical follow-up
changed only tin. Future lowland content, additional water bodies and full
resource balance remain outside this correction.
