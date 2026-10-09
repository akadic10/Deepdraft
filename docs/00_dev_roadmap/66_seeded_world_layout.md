# 66 — Seeded world layout

Status: **live integration completed**, 2026-10-07.
The user accepted the macro gallery and its larger lowland share. They confirmed
there are no existing saves in this early development stage and explicitly
removed legacy-save compatibility from the plan. The seeded layout now replaces
the fixed compass geography in normal generation. No old generator or migration
path is retained; current save/load behavior is tested against the new terrain.

## Accepted direction

Remove the fixed northwest mountains, southwest lake, southeast foothills and
central valley. Let the seed determine ridge position, orientation, length,
bends, secondary hills, foothill approaches and lake placement.

Every seed must reach **Y115 with substantial mountains**. The summit minimum
is **one intact 32×32 plateau**, corrected from the initial 64×64 proposal.
Larger summits are allowed. Keep one guaranteed lowland lake and an optional
mountain tarn; water bodies have separate footprints, floors and waterlines so
future lakes need not share one global elevation.

After playtesting, the user removed the generated starting area. Players choose
their own site and clear trees themselves. There is no reserved plateau, flat
starting-space guarantee, vegetation exclusion, or camera preference for a site.

## Approved macro contract

The existing 1024×128×1024 world, 32×32 macro cells and shelf tops remain:
Y19, 27, 35, 43, 55, 67, 79, 91, 103 and 115.

| Requirement | Active setting |
|---|---|
| Summit | At least one complete 32×32 cell at Y115 |
| Mountain mass | At least 128 dry, cardinally connected cells at Y55+ in a component containing the summit: 12.5% of map |
| Mountain shelves | At least four dry cells on each of Y55/67/79/91/103; Y115 follows the summit minimum |
| Height transitions | Adjacent cells, including diagonals, differ by at most one shelf rank, before water carving |
| Lowland | At least 205 cells' worth of connected dry Y19 columns after edge detail; all lowland components reach a map edge |
| Main lake | One connected footprint, 12–32 macro cells, floor Y11, waterline Y18; coastal or inland |
| Tarn | Optional one-cell basin, floor Y47, waterline Y54, with a complete Y55/Y67 surround |
| Containment | Every landward neighbor outside a water body is above that body's waterline |
| Failure handling | At most eight candidate attempts, then a seed-selected, validated fallback; never publish invalid terrain |

Area thresholds retain the accepted prototype balance. Water carving is the
explicit exception to the dry shelf step rule. Flag placement is the player's
choice. Trees follow the ordinary flora rules everywhere. The initial camera
uses its configured position; navigation is tested on naturally occurring shelves.
This change does not add ramps or guarantee walking between every height tier.

## Implementation

- `data/world_gen/macro_layout_v1.json` owns tunable values and the active
  algorithm/profile identifier (promoted from the reviewed preview profile).
- `WorldGenerator.load_macro_layout_profile()` is the sole profile reader.
  Normal generation loads and validates it on the main thread before starting
  its worker. The offline gallery uses the same loader and layout component.
- `scripts/components/WorldLayout.gd` consumes that profile and a seed. Separate
  RNG streams control terrain, the main lake and tarns.
  A ridge and secondary elevation sources form a maximum distance envelope:
  raising surrounding shelves preserves the summit instead of subsequently
  lowering it away. Broader ledges are terrain features regardless of tarns.
  Interior lowland holes are promoted and water footprints are selected from
  the resulting terrain. No pass reshapes terrain for an initial settlement.
- `scripts/components/WorldLayoutValidator.gd` independently inspects finished
  arrays. It checks heights, connected areas, shelf transitions and water geometry
  without calling construction helpers or repairing output.
- The fallback is a finite family of **32** layouts. Seed modulo 32 selects the
  variant, while the returned world seed remains the original seed. All 32 are
  forced through validation in the test. This provides complete fallback-family
  coverage for the supplied profile; a modified profile is still validated and
  can fail explicitly if its requirements are incompatible.

No new autoload, global `class_name`, scene or project setting was added.

`WorldGenerator` expands accepted macro heights into column maps in parallel,
builds per-body waterlines and compatibility footprint sets, then applies edge
detail. Every natural cliff boundary receives seeded ledges, including summits,
foothill edges, lowland transitions and shores. Summit interiors are immutable.
Detail grows outward by at most three
columns, so the intact 32×32 Y115 summit is never eroded. Corners are constrained
to prevent a protrusion from creating an excessive dry shelf step.
`WorldLayoutValidator.inspect_columns()` checks all 1,048,576 finished columns
before `_maps_ready` is published: unchanged protected interiors, no erosion,
bounded edge strips, exact shelf/lowland areas, domain/waterline agreement and dry
shelf steps. Macro acceptance reserves a conservative area allowance for detail.
Lowland and water cells retain at least a 26×26 core with wide connections to
their neighbors, preserving connectivity through the detail pass.

Shore ledges grow into the original water footprint, with varying dry lips and
submerged steps. Every remaining wet column retains its body's flat waterline;
columns filled to that line become solid shore. Lake/tarn membership and bank
masks are rebuilt from the finished columns before rendering or flora placement.
This replaces the first integration's broad exclusions, which caused the smooth
cliffs and square-edged water shown in the user's playtest screenshots.

Visible water queries, streamed chunk bounds, overview tile ranges and block
generation use `waterline_map`, including the elevated tarn. The old compass
functions, shelf-lowering passes and associated terrain noise were removed.
Material strata, resource rules and slice concealment remain the existing ones.

The starting-area removal also deletes the profile settings, layout metadata,
validation requirements, terrain protection, flora exclusion and suggested-site
diagnostics. Camera initialization and `SaveManager` use their original flows;
the temporary camera signal/loading-state helper is removed. Saved cameras still
restore through the existing save-owner flow; the save schema is unchanged.

## Verification and artifacts

`scripts/tests/WorldLayoutTest.gd` passed on Godot 4.7.2. The batch uses 16 fixed
gallery seeds followed by a reproducible spread across the unsigned 32-bit seed
range. These are measured results for the current profile:

| Measurement | Result across 1,000 seeds |
|---|---|
| Valid maps | 1,000 / 1,000 |
| Connected summit mountain region | 128–266 cells; mean 183.347 (12.5–26.0%; mean 17.9%) |
| Y115 summit cells | 1–13 per map |
| Smallest connected dry lowland | 212 cells (minimum required: 205) |
| Summit center by NW / NE / SW / SE quadrant | 269 / 243 / 274 / 214 |
| Main lake coastal / inland | 474 / 526 |
| Optional tarns | 705 |
| Accepted first / second attempt | 978 / 22 |
| Fallbacks needed by the batch | 0 |

The 22 rejected first attempts were 21 undersized mountain components and one
insufficient connected lowland. Each succeeded on its second attempt. The
separate forced-fallback test covers every fallback variant. Sixteen seeds are
also regenerated in-process. Full regenerated column maps are compared during
save/load. The earlier pre-removal batch also matched 1,000 hashes across processes.
Corruption checks verify rejection of a missing summit, excessive shelf jumps,
inconsistent lake floor, disconnected water, and inadequate
mountain/lowland area. An unsupported grid configuration is rejected.

The full test batch runs in roughly 10 seconds locally; that is **macro layout
testing only**, not an estimate of full game generation time. Test-only startup
warnings about a missing scene for SkyController and randomized weather at seed
zero do not participate in the geography RNG or map generation.

Review artifacts live in `tmp/world_layout_review/`:

- [Review page](../../tmp/world_layout_review/index.html): each seed has a top
  view and an exaggerated relief diagram.
- [16-seed overview](../../tmp/world_layout_review/seed_gallery.png).
- [Previous-geography comparison](../../tmp/world_layout_review/baseline_comparison.png).
- `gallery.json`, `baseline.json` and `report.json`: actual map data and checks.

The archived `baseline.json` captures the pre-integration generation phases for seeds
1234, 20261007 and 3381051336. Its diagrams sample macro-cell centers; its height
histogram counts all 1,048,576 final columns, including edge detail. These three
live seeds had 19,653 / 12,576 / 10,396 Y115 columns and retain the fixed northwest
mountain and southern lake composition. This is a geography comparison, not a
material or rendering comparison. Its one-time capture helper was retired when
the old generator was removed; reproducing that baseline requires the old code.

Visual inspection confirms differing ridge positions, orientations, secondary
hills and lake locations. The new macro contours remain regular, with broad
flat lowlands, and generally contain less mountain area than these three live
baselines (25.7–29.0%). Judge that proportion and terrace shape at this checkpoint.
Those were the macro-only observations. The live checks below additionally
cover edge detail, actual blocks, natural flora and rendered game scenes.

### Live integration verification

- `WorldGenerationTest.gd`: **8 ordinary seeds plus all 32 fallback variants**
  passed final column validation. Minimum-summit seeds retained all 1,024 Y115
  columns. Corrupting one summit column was rejected by the final validator.
- Gameplay checks: flag placement on natural ground, dry 3-block navigation
  clearance, a path across a natural shelf to a mining face, and real mining/
  rematerialization without deleting neighbors. Every dry macro-cell center is
  checked against the generic flora footprint rule to catch artificial exclusions.
- Block checks: bedrock Y0–3, surface/getter agreement, air above dry ground, all
  six authored mountain rock types, and concealed overview strata.
- Water checks: actual floor and water stacks, visible waterline, air above it,
  and complete lowland/tarn water in streamed chunks. The cliff follow-up checks
  every original natural cliff/shore segment for a nonuniform cross-section,
  confirms each water body has dry lip variation and submerged ledges, and
  compares actual streamed wet/dry shore blocks with the final terrain.
- `SaveManagerRoundTripTest.gd`: **passed**, including normal save, autosave,
  backup recovery, scene-owner state and a SHA-256 comparison of the complete
  height/domain/water maps after regeneration. The fixture locates an existing
  flat lowland strip for its objects without reshaping the generated world.
- `WorldLayoutLivePreview.gd`: normal game scene captured for **1234 and 65535**;
  initial camera retained its configured position, the test selected ordinary
  natural ground for the flag, and five starter dwarves spawned. Initial
  captures use normal camera/fog; inspection captures disable distance fog in the
  review process only. Wide mountains use extended zoom; new close-ups inspect
  lowland cliffs, the main lake shore and the tarn.

Live captures: [seed 1234](../../tmp/world_layout_review/live_1234_mountain.png),
[seed 65535](../../tmp/world_layout_review/live_65535_mountain.png), and
[normal initial view](../../tmp/world_layout_review/live_1234_initial_view.png).
Starting-area removal: [seed 1234 natural terrain](../../tmp/world_layout_review/live_1234_natural_terrain.png)
and [seed 65535 natural terrain](../../tmp/world_layout_review/live_65535_natural_terrain.png)
show the former clearing locations with naturally generated trees.
Those former footprints contain 35 and 31 trees respectively. The starting-area
removal passed the 1,000-layout batch, all 40 full-world checks, save/load and both
native scene previews; the normal initial camera position and arbitrary natural
flag placement were also checked.
Cliff follow-up: [lowland cliff](../../tmp/world_layout_review/live_1234_lowland_cliff.png),
[lake shore](../../tmp/world_layout_review/live_1234_lowland_lake.png), and
[mountain tarn](../../tmp/world_layout_review/live_1234_mountain_tarn.png).
`live_report.json`, `live_fallback_report.json`, render logs and the save test log
are stored beside them. At initial integration, seed 1234's map precompute was about **1.8 seconds**;
its complete overview rendered in about **7.5 seconds** on this machine. The
old baseline's corresponding terrain phases took about 7.3 seconds, but these
captures were not a controlled performance benchmark.

The cliff/shore follow-up reran the 1,000-layout batch, all 40 finished-world
checks, save/load and both rendered seeds successfully. Macro layouts and batch
statistics stayed unchanged at that step; the detail changes only boundary columns.
The later starting-area removal changes the former raised terrace and can affect
lowland lake selection. It retains all height, mountain, rough-edge and water
requirements; the gallery and statistics above reflect that removal.

## Reproduce

Use an isolated profile; the test deliberately refuses the normal APPDATA path.
Run from the project root in PowerShell:

```powershell
$env:APPDATA = Join-Path $PWD 'tmp/world_layout_review/appdata'
$env:LOCALAPPDATA = Join-Path $PWD 'tmp/world_layout_review/localappdata'
New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA | Out-Null
$godotPath = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
$layoutRun = Start-Process -FilePath $godotPath -WindowStyle Hidden -Wait -PassThru -ArgumentList '--headless --path P:\Deepdraft --log-file P:\Deepdraft\tmp\world_layout_review\test.log --script res://scripts/tests/WorldLayoutTest.gd'
if ($layoutRun.ExitCode -ne 0) { throw 'WorldLayoutTest failed; read test.log' }
$liveRun = Start-Process -FilePath $godotPath -WindowStyle Hidden -Wait -PassThru -ArgumentList '--headless --path P:\Deepdraft --log-file P:\Deepdraft\tmp\world_layout_review\live.log --script res://scripts/tests/WorldGenerationTest.gd'
if ($liveRun.ExitCode -ne 0) { throw 'Live checks failed; read live.log' }
# Append -- --fallbacks to WorldGenerationTest.gd to exercise all 32 fallbacks.
# Save/load: --script res://scripts/tests/SaveManagerRoundTripTest.gd
# Render (omit --headless): --script res://tools/WorldLayoutLivePreview.gd -- --seed=1234
# Use a Python environment with Pillow installed:
python tools/render_world_layout_gallery.py
```

## Deferred work

Future lowland features, additional water-body types, automatic ramps, and
resource availability/balance tuning remain separate design work. The user
accepted the larger open lowlands for now. Legacy-save compatibility was
explicitly removed from this milestone because there are no existing saves.

The subsequent [diagnostics and tin follow-up](67_world_generation_diagnostics.md)
corrects surface-metric accuracy and copper/tin precedence independently of
geography. [68 — Caves and discovery](68_caves_and_discovery.md) subsequently
implemented dry connected caves; [69 — Resource distribution review](69_resource_distribution_review.md)
records the resource audit with caves included.
