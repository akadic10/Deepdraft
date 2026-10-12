# 122 — Bedroom privacy, warmth and mining progression

Implemented 2026-10-11, following the saved-colony review and approval.

## Privacy

Owners may relax in their personal bedrooms. Visitors may enter for work, then
walk out before idling; assignment changes also displace idle visitors normally.
Unassigned single bedrooms accept sleepers but are not leisure destinations.
Barracks remain shared. Chair selection, wandering, ground sleep and bed routes
respect these rules. A filtered bed search can take a public detour, and path
shortcuts cannot cut through another colonist's bedroom. Ordinary task navigation
and doors remain unrestricted.

`DwarfPrivacy` checks RoomManager's derived classification. Exit searches expand
at most 64 floor cells per tick, up to 4096 per attempt, following real adjacent
segments. A blocked exit retries on terrain changes or after two seconds; no
teleporting or forced sleeping in a private room. Rest and work can interrupt it.
An unsealed room, or one missing its qualifying bed/light, follows ordinary room
rules. Privacy does not add a permanent navigation obstacle.

## Warmth and sleep

RoomManager owns `data/world_gen/temperature.json`. Ordinary rock starts at 10°C,
with seasonal/daily exposure damped by original overburden and enclosure. Low
absolute map Y no longer means freezing. This replaces the cold gradient in
the earlier doc 34. Explicit cold-biome baselines remain future work.

The rudimentary hearth is a Rudimentary → Camp furnishings recipe:
**two matching logs + four rough stones**, 18 seconds at a crude workbench.
Every ingredient is physically delivered before work. The packed result uses
normal haul/install/uninstall; its stone appearance does not inherit wood tint.
It contributes 2400 heat units and shares the quiet campfire crackle. Fuel upkeep
and ignition remain unimplemented, consistent with existing installed fires.

Heat adds `units / max(room volume, 128)` degrees. The small-room minimum models
surrounding thermal mass. Sources: log torch 75, wall torch 100, campfire 900,
rudimentary hearth 2400, brazier 3200. Braziers still have no starter recipe. Torches
retain their lighting strength and primarily provide light.

Both room inspectors show actual comfort: Cold below 8°C, Chilly below 16°C,
Comfortable from 16–26°C, Hot above 26°C. Room light count remains independent
of heat. Removing sources and rebuilding a save recomputes contributions once.

One game hour actually asleep in uncomfortable conditions creates a thought:
Cold −20, Chilly −5, Hot −15 happiness for 24 game hours. Only the strongest
thermal penalty applies at once. It can appear while sleeping and refreshes
with continued exposure. Walking/settling earns none. Personal bedroom sleep
still gives +10 after at least three qualifying hours and completed rest, so
4°C sleep outweighs that bonus. Mood exposure and memory timers persist and
follow pause/speed. No work-temperature penalties, illness or hypothermia yet.

The copied player save's two rooms changed from **3.5/4.2°C to 11.3/11.7°C**.
One hearth brings their calculated temperatures to **18.7/21.1°C**. Audtha
physically leaves the unassigned bedroom instead of settling there. The original
player save was not edited.

## Mining progression

BlockRegistry's `block_resources.json` now supplies `min_burial` as well as Y
limits, field scale, thresholds and loot. `NaturalRockCover` precomputes square
minimum surface maps for configured radii; WorldGenerator checks a complete
original rock shell, including diagonal cliff faces and roof cover. Terrain edits
never change this geological condition. Natural cave interiors do not redefine
the exterior. Read-only maps are published before generation queries, take eight
MiB total, and avoid a neighborhood scan per generated block.

| Resource | Minimum original cover | Maximum Y |
|---|---:|---:|
| Coal, copper | 2 | 120 |
| Tin | 10 | 100 |
| Iron | 14 | 100 |
| Jade / amethyst | 20 | 85 / 75 |
| Silver | 24 | 65 |
| Gold | 28 | 32 |
| Ruby, sapphire | 32 | 24 |
| Emerald / diamond | 40 | 16 / 12 |

All resources remain above bedrock (Y4+). Coal/copper use a higher noise cutoff
in the outer ten-block shell for sparse entrance seams. Deeper independent metal
fields retain useful deposits; increased field frequency reduces their extent.
The shared gem field frequency rises from 0.06 to 0.11, with higher common-gem
cutoffs. Gems remain finished valuables; no cutting profession is added.
Ore blocks now yield at most one unit, at 40% chance, replacing two-unit 10%
metal drops. Gem drop chances and rough stone/soil drops are unchanged.

The original 1,064-block player excavation would now expose one copper and four
tin blocks, with no iron or gems (previously 50 iron, five copper, five jade and
three amethyst). Across eight seeds the outer-shell sample is about 1.3% resource
blocks; local luck still matters—a sampled starter tunnel intersected 46 copper
blocks. This is a progression curve, not a guarantee of evenly spaced deposits.

Geography, rivers, caves, bedrock protection, concealed strata and mining rules
are unchanged. Existing inventory is preserved. Generated, unmined resources
use the current definitions on reload; use fresh worlds to judge the whole curve.

## Verification

- BedroomPrivacyTest: assignments, physical visitor exits, unassigned sleep,
  sleep detours, task access and no sleep credited during exit.
- BedroomComfortTest: actual hearth crafting/conservation, installed heat,
  removal, exposure threshold, cold vs personal bonus, hot sleep and expiry.
- Existing ownership, ground rest, idle, navigation, crafting-browser and save
  round-trip regressions; invalid saves include negative/wrong-type thermal timers.
- ResourceProgressionTest: eight fresh layouts with rivers/caves, 898,961 solid
  sample cells, contiguous starter excavations, all four rare deep gems found in
  every seed, original saved excavation, cover filter vs brute force, immutable
  geology after mining and concealed strata. Sparse samples are not world totals.
- Native crafting menu captures at 960/1280/1920 widths show one grouped stone
  count. Saved-colony checks and JSON evidence live in
  `tmp/colony_balance_review_20261011`; the reusable excavation mask is a test fixture.

The OreFieldIntegrationTest entry point now runs ResourceProgressionTest. The
historical abundance-preservation target from milestone 71 is superseded; its
recorded comparison data remains available.
