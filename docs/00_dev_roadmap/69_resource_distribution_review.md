# 69 — Resource distribution review

Completed 2026-10-08 after [68 — Caves and discovery](68_caves_and_discovery.md).
The user chose to defer additional manual cave checks and move to resource
distribution, abundance and vein shape. This pass measures the current world
with caves and corrects a confirmed gem-selection defect. Larger vein-shape and
economy choices remain open.

## Implemented correction

Diamond and emerald both used a 0.90 threshold on the shared gem noise field.
Because diamond is selected first, emerald could never generate in its configured
Y5–12 overlap with diamond. Emerald could still appear at Y13–16.

`data/terrain/block_resources.json` now gives diamond **0.91**. Emerald retains
0.90, so it owns `(0.90, 0.91]` at Y5–12 while diamond owns `>0.91`. This preserves
the intended rarest-first order and makes diamond the rarer deep gem. It is an
intentional diamond-density reduction, not merely a visibility fix.

Other thresholds, depths, resource order, ore/gem noise, mining durability and
drop rates are unchanged. At Y5–12, affected diamond blocks become emerald. At
Y4, where emerald is outside its band, affected blocks become foundation rock.
Geography, cave geometry and measured metal deposits are unchanged.

## Measurements and limits

Eight seeds: **7, 1234, 65535, 20261007, 3381051336, 4294967295, 314159265,
2147483647**. Three complementary measurements avoid confusing samples with
whole-world counts:

1. **World resource sample:** x/z 4,12,…,1020, every Y4 through the solid terrain
   height, including cave air. This gives **3,662,272 cells across eight worlds**,
   about one column in 64. Counts below are sample counts, not estimated totals.
2. **Exact deep-gem census:** every eligible column and Y4–22, covering the entire
   configured depth range of diamond, emerald, sapphire and ruby. The protected
   eight-column map perimeter cannot contain resources and is excluded. Noise
   filters candidate positions, then actual generated block IDs determine counts.
3. **Spatial samples:** one contiguous **64³** box per seed, starting at Y12 under
   the first qualifying Y115 macro-cell center. Six-neighbor components measure
   connected deposits. Components touching the box boundary are explicitly marked
   clipped and are lower bounds on the full deposit size.

Sparse sampling alone missed all emeralds in seven of the original eight seed
samples and misses diamonds in some corrected samples. The exact census finds
all four deep gem types in every tested world. A zero sparse count must not be
reported as proof that a resource is absent from a seed.

## Deep gems: full-resolution results

The old column below uses the same world and original diamond threshold 0.90 as
a counterfactual during the exhaustive scan; all other generation rules match.
The corrected column queries actual generated blocks.

| Seed | Diamond before → after | Emerald before → after | Emerald at Y5–12 after |
|---|---:|---:|---:|
| 7 | 241 → 97 | 49 → 177 | 128 |
| 1234 | 281 → 132 | 50 → 186 | 136 |
| 65535 | 254 → 118 | 50 → 173 | 123 |
| 20261007 | 223 → 76 | 42 → 170 | 128 |
| 3381051336 | 247 → 98 | 45 → 176 | 131 |
| 4294967295 | 194 → 76 | 35 → 143 | 108 |
| 314159265 | 207 → 82 | 70 → 167 | 97 |
| 2147483647 | 198 → 80 | 48 → 156 | 108 |
| **Total** | **1,845 → 759** | **389 → 1,348** | **959** |

Sapphire remains **2,989** blocks and ruby **4,993** across these worlds. The
1,086 removed diamond assignments comprise 959 new emeralds and 127 ordinary
foundation-rock blocks at Y4. These counts establish observed presence and the
effect of this correction; they are not an all-seed resource guarantee or a
final judgment about gem value and mining effort.

## Ore abundance and cave impact

The world sample contains **392,898 ore blocks** (10.73% of sampled cells,
including rock, soil and cave air in the denominator). Per-resource totals:

| Resource | Sample count after caves |
|---|---:|
| Coal | 220,202 |
| Iron | 98,764 |
| Copper | 39,485 |
| Tin | 14,597 |
| Silver | 12,956 |
| Gold | 6,894 |

The diamond change leaves every sampled metal count and metal component box
unchanged. Cave air occupies **0.0859%** of the sampled underground cells. The
64 actual cave systems contain **201,971 air blocks** in total.

The first four seeds can be compared directly to doc 67's historical pre-cave
samples: identical geography fingerprints, sample coordinates and metal rules.

| Seed | Sampled ore before caves | Sampled ore with caves | Reduction |
|---|---:|---:|---:|
| 7 | 38,954 | 38,857 | 0.249% |
| 1234 | 61,414 | 61,364 | 0.081% |
| 65535 | 49,116 | 49,007 | 0.222% |
| 20261007 | 48,142 | 48,069 | 0.152% |

This supports keeping the current ore abundance through the cave integration;
it does not justify increasing ore globally to compensate for cave carving.
Local effects are larger where a chamber intersects a deposit.

An exact scan of cave boundaries finds **23,174 metal blocks** and **345 gem
blocks**, the latter all jade/amethyst, across the eight worlds. This audit
includes floor, walls, ceiling and changes in ceiling height; the explorer's
simpler floor/exterior-wall count does not include every ceiling face. Counts are
unique blocks per system, not rendered faces. Deep diamonds/emeralds lie below
these caves' minimum floor Y16, so ordinary downward mining remains necessary.

## Vein shape: the main outstanding decision

The shared ore field creates broad, connected deposits. In the seed-1234 64³
box, the largest connected coal body contains **35,217 blocks** and iron
**34,309 blocks**. Both touch the box boundary, so their complete deposits may
be larger. Tin often forms thinner, fragmented regions around higher-priority
metals because all metals compete for intervals of the same noise field.

This is consistent with the existing 0.02-frequency design, not a new cave bug.
It may make finding one deposit satisfy a colony for a very long time. It also
helps explain why ore drops were previously reduced for testing. Whether that
is desirable depends on excavation effort and the eventual crafting economy.

Recommended next design pass:

- Compare a few **smaller, distinct deposits** against the current large bodies,
  using the same seeds and explicit counts/shape captures before choosing one.
- Keep coal relatively broad if fuel should be plentiful; use more contained
  metal deposits if exploration and following veins should remain valuable.
- Evaluate shared-field nested bands versus independent per-resource shapes.
  Merely increasing one frequency shrinks features but retains nested selection.
- Decide horizontal resource bias separately from depth. Lowlands currently
  provide a short route to deep gems; moving all value under mountains would
  change that deliberate choice.
- Evaluate item yield when smelting/tool demand is playable. Current **10% ore
  drop chances** and **5% rock/soil drops** were explicitly lowered for testing;
  they are not the intended final economy balance and were preserved here.

No frequency, horizontal-bias or drop-rate change is made by this review.

**Follow-up completed:** [70 — Ore vein prototypes](70_ore_vein_prototypes.md)
compares the current field, a finer shared field and separate metal fields with
broader coal. It includes measured sections and abundance checks on the same
eight seeds. The accepted separate-field direction is subsequently integrated
in [71 — Independent ore fields](71_independent_ore_fields.md).

## Verification and reproducibility

`scripts/tests/WorldResourceBalanceTest.gd` now covers:

- Every configured metal, gem and soil window has a reachable shared-channel
  interval at every configured depth. The baseline records emerald's eight
  shadowed Y levels; the corrected run has none.
- Strict threshold comparisons and inclusive min/max depth boundaries.
- Actual generated resources remain below the surface and outside protected
  natural cliffs/perimeter. Rebuilding seeded noise preserves sampled identities.
- Streamed chunks contain the same resource blocks and normal slice strata keep
  them concealed, including every rare gem found by the full census.
- Exact cave-carving losses, unique boundary resources and dense ore components.
- Before/after comparisons preserve all eight geography fingerprints, cave
  summaries, metal-component boxes and sampled resource counts other than
  diamond/emerald.

Both runs pass with no script errors. The baseline was captured before editing
the diamond threshold; `--baseline` records the code currently installed and
does not restore historical configuration. The optional deep census explicitly
reconstructs the old diamond threshold for the comparison table above.

Reports in `tmp/world_layout_review/`:
[before](../../tmp/world_layout_review/resource_balance_before.json),
[after](../../tmp/world_layout_review/resource_balance_after.json), and
[comparison](../../tmp/world_layout_review/resource_balance_comparison.json).
Logs: `resource_balance_before.log`, `resource_balance_after.log`.
The older doc 67 reports are preserved.

```powershell
$env:APPDATA = 'P:\Deepdraft\tmp\world_layout_review\appdata_balance'
$env:LOCALAPPDATA = 'P:\Deepdraft\tmp\world_layout_review\localappdata_balance'
$resourceRun = Start-Process -FilePath 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' -WindowStyle Hidden -Wait -PassThru -ArgumentList '--headless --path P:\Deepdraft --log-file P:\Deepdraft\tmp\world_layout_review\resource_balance_after.log --script res://scripts/tests/WorldResourceBalanceTest.gd -- --deep-census'
if ($resourceRun.ExitCode -ne 0) { throw 'Resource checks failed; inspect the log.' }
Select-String -Path tmp/world_layout_review/resource_balance_after.log -Pattern 'SCRIPT ERROR|ERROR:|\bFAIL\b'
```

Restart play mode to generate the corrected gem distribution. No new global
class, autoload, UI, save schema or migration was introduced.
