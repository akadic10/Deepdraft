# 71 — Independent ore fields

Implemented 2026-10-08 after the user accepted the separate-field direction in
[70 — Ore vein prototypes](70_ore_vein_prototypes.md).

## Live behavior

Gold, silver, iron, copper and tin use separate seeded fields to produce smaller,
more distinct deposits. Coal retains its broad field. First-match priority still
resolves actual overlaps: gems, then gold → silver → iron → copper → tin → coal,
then cave-floor soil and procedural cave soil. The metal thresholds no longer
represent adjoining intervals of one shared field.

`data/terrain/block_resources.json` owns each ore's `noise_field` settings and
cutoff. BlockRegistry loads them; WorldGenerator copies them before starting its
worker, builds one simplex-smooth field per ore and samples only the fields whose
depth windows include the queried block. Fields use two octaves and fixed offsets
added to `world_seed`. There is no runtime calibration or unseeded ore randomness.

| Resource | Depth | Frequency | Seed offset | Cutoff, rounded |
|---|---|---:|---:|---:|
| Gold | Y8–36 | 0.065 | 101 | 0.83855328 |
| Silver | Y16–52 | 0.065 | 211 | 0.80578738 |
| Iron | Y20–72 | 0.055 | 307 | 0.70352161 |
| Copper | Y45–88 | 0.060 | 401 | 0.70632493 |
| Tin | Y55–95 | 0.070 | 503 | 0.73587915 |
| Coal | Y12–90 | 0.020 | 1 | 0.66518578 |

The existing bedrock, surface, exposed-cliff and map-perimeter protections remain.
Geography, lakes, rough ledges, cave geometry and gem settings are unchanged.
Mining hardness, durability, loot counts and temporary drop chances are unchanged.
Soil still loses to ore where they overlap, so particular soil blocks may move
between soil and ore despite unchanged soil settings.

## Calibration and independent checks

`tools/CalibrateOreFields.gd` fits global cutoffs offline using the original eight
study seeds and their eligible sample positions. This replaces the four-seed
prototype fit, particularly to improve gold/tin stability. Each resource matches
its original aggregate sample count on those eight seeds after earlier resources
have claimed their positions. No per-seed or per-crop fitting occurs.

Calibration seeds: **7, 1234, 65535, 20261007, 3381051336, 4294967295, 314159265,
2147483647**. The eight additional check seeds are **0, 42, 8675309, 20261008,
305419896, 987654321, 2718281828, 4000000000**; none was used to adjust cutoffs.

The comparison samples x/z 4,12,…,1020 and every Y4 through the solid column top,
including cave air. It measures **7,577,216 cells** across sixteen worlds;
**3,914,944** belong to the independent check seeds. These are sample counts, not
whole-world estimates. The old field is reconstructed only inside the test, on
the same eligible positions, using frozen pre-change metadata. It exactly
reproduces the earlier audit's ore counts on all eight original seeds.

| Resource | Old count, check seeds | New count, check seeds | Change |
|---|---:|---:|---:|
| Gold | 7,224 | 7,669 | +6.16% |
| Silver | 12,779 | 15,095 | +18.12% |
| Iron | 107,134 | 113,164 | +5.63% |
| Copper | 46,133 | 45,061 | −2.32% |
| Tin | 16,599 | 16,695 | +0.58% |
| Coal | 246,549 | 243,207 | −1.36% |
| **Total** | **436,418** | **440,891** | **+1.02%** |

Across all sixteen seeds the total is **829,316 → 833,789 (+0.54%)**. Every ore
appears in every tested seed sample. Silver's independent-check increase is a
remaining balance consideration; the check seeds were not repeatedly fitted to
force agreement. These measurements do not guarantee identical abundance for
every possible seed.

### Distribution within the existing depth bands changes

Depth limits are unchanged, but removing shared-field competition changes where
ore falls inside them. On the check seeds, coal at Y12–19 decreases from 99,192 to
63,420 sampled blocks (−36%); coal at Y55–72 increases from 9,718 to 28,836
(about 3×), and at Y73–90 from 4,671 to 15,363 (about 3.3×). Copper at Y73–88
decreases from 16,830 to 8,730 (−48%), while its lower portions increase.

Thus close total counts must not be described as unchanged access at every
elevation. The full by-Y counts and band summaries are recorded for later mining
and smelting playtests. No horizontal mountain bias or new depth restriction was
added to compensate. Gold/tin now vary less in aggregate on the independent
check set than in the initial four-seed prototype, but neither their individual
seed counts nor their density at every depth is guaranteed.

## Deposit size and cave access

The same eight **64³** crop boxes used in docs 69/70 were measured again from the
integrated generator. Median of the largest connected same-ore component in
each crop:

| Resource | Previous shared field | Live independent fields |
|---|---:|---:|
| Gold | 43.5 | 113.5 |
| Silver | 1,017.5 | 214.5 |
| Iron | 14,651.5 | 3,251.5 |
| Copper | 10,641.5 | 2,179.5 |
| Tin | 1,926 | 472 |
| Coal | 26,159 | 32,173 |

These are **not median vein sizes**. Components touching a crop edge are clipped
lower bounds; some gold crops originally contained no gold. There is no claim
that every resource is smaller or that noise enforces a size cap. Coal remains
broad and can connect into larger bodies. The seed-1234 crop's largest iron body
is now at least **4,299 blocks**, down from at least **34,309**.

All **128 tested cave systems** still expose some ore along their solid boundary.
They expose ordinary generated deposits; no bonus ore is injected. Natural cave
volume on the original eight seeds remains exactly **201,971 air blocks**.

## Verification

- **OreFieldIntegrationTest:** PASS across sixteen seeds. Checks actual generated
  blocks, strict cutoffs, inclusive depth bounds, independent fields and overlap
  priority, streaming, noise rebuild determinism, protected surfaces, unchanged
  gem samples and geography, and concealed strata. Records old/new abundance by
  depth, cave boundary ores and the original eight dense component boxes.
- **CaveGenerationTest:** PASS across eight seeds. Checks cave connectivity and
  walkability, hidden slicing/picking, DEV preview isolation, mining discovery,
  cave entry navigation and discovery rebuilt from saved mining edits.
- **SaveManagerRoundTripTest:** PASS (`SAVE_MANAGER_ROUND_TRIP_OK`) with the real
  scene and threaded generator, terrain fingerprint, nonempty colony state,
  manual/autosave slots and backup recovery.
- **WorldResourceBalanceTest --windows-only:** PASS after final field validation
  and test refinements. Shared-channel shadowing tests now apply only to gems and
  soil; metal checks exercise the live independent selector.
- **WorldResourceDiagnosticsTest:** PASS across four seeds. Full surface censuses
  and geography fingerprints exactly match the previous audit; copper/tin both
  remain present in their overlapping depth ranges.
- **Original prototype recheck:** PASS. Its tool now freezes the old shared-field
  cutoffs, keeping doc 70 reproducible after live integration. Python component
  analysis again matches the historical baseline's counts, sizes and geography.
- Logs contain no `SCRIPT ERROR`, `ERROR:` or `FAIL`. Headless scene-less tools
  can emit the existing SkyController/WeatherManager initialization warnings;
  ore generation itself always uses the explicit test seed.

Evidence: [integration report](../../tmp/ore_field_integration/integration.json),
[summary](../../tmp/ore_field_integration/summary.json),
[calibration](../../tmp/ore_field_integration/calibration.json),
[integration log](../../tmp/ore_field_integration/integration.log),
[cave log](../../tmp/ore_field_integration/caves.log),
[save/load log](../../tmp/ore_field_integration/save.log).

The additional runs use isolated APPDATA/LOCALAPPDATA below the review folders.
Historical resource audit reports are preserved; regular resource diagnostics
now write `*_current.json` (or `*_baseline_current.json`) instead of replacing
doc 67/69's historical before/after files.

```powershell
$env:APPDATA = 'P:\Deepdraft\tmp\ore_field_integration\appdata_test'
$env:LOCALAPPDATA = 'P:\Deepdraft\tmp\ore_field_integration\localappdata_test'
$oreRun = Start-Process -FilePath 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' -WindowStyle Hidden -Wait -PassThru -ArgumentList '--headless --path P:\Deepdraft --log-file P:\Deepdraft\tmp\ore_field_integration\integration.log --script res://scripts/tests/OreFieldIntegrationTest.gd'
if ($oreRun.ExitCode -ne 0) { throw 'Ore integration failed; inspect the log.' }
Select-String -Path tmp/ore_field_integration/integration.log -Pattern 'SCRIPT ERROR|ERROR:|\bFAIL\b'
```

## Playtest and remaining decisions

Restart play mode to generate the new deposits. No new global class, autoload or
scene wiring requires a project reload. Use **Menu → Development → DEV: Cave
explorer → Focus + slice → Preview interior with DEV lighting** to see the new
exposed patches easily. Closing the explorer restores normal discovery and
concealment. Mining into a cave remains the ordinary discovery path.

The user confirmed no existing saves during this early-development work; no
legacy production generator or migration path is retained. Deterministic
save/load is tested within the new generator.

Next design choices remain separate: horizontal resource bias, final silver and
depth-density tuning during mining playtests, and item yields once the smelting/
tool economy can establish demand. The existing 10% ore and 5% rock/soil drops
are still temporary testing values. Deferred cave flora, hazards and other
rewards remain in [68](68_caves_and_discovery.md).

**Subsequent decision:** the user agreed to keep resource placement depth-based
for now and requested [72 — Surface details plan](72_surface_details_plan.md).
Horizontal bias is deferred; no further resource rules changed in that planning pass.
