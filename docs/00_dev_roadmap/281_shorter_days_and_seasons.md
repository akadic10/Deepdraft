# 281 — Shorter days and seasons

2026-10-29. Implemented; the owner's look in Play is pending.

From the owner: a 24-minute day with 28-day seasons felt long. After a comparison with
other colony sims (below), the owner chose **12-minute days and 21-day seasons**.

## The comparison

| Game | One day at 1× | Days per season | Season at 1× | Year at 1× | Top speed |
|---|---|---|---|---|---|
| Timberborn | 7 min 40 s | 13–17 normal + 5–9 drought | ~2.3–3.3 h per cycle | — | 7× |
| Oxygen Not Included | 10 min | no seasons | — | — | 3× |
| Stonehearth | ~13 min (one player's measurement) | 21 | ~4.6 h | ~18 h | 3× |
| RimWorld | 16 min 40 s | 15 | 4 h 10 min | 16 h 40 min | 6× |
| Going Medieval | ~17 min | 12 | ~3.4 h | ~13.6 h | 4× (7× while all sleep) |
| Clanfolk | 30 min | 10 | 5 h | 20 h | — |
| Dwarf Fortress | ~12 s at 100 FPS | 84 | ~17 min | ~67 min | frame-rate bound |
| Farthest Frontier | — | — | ~7 min | ~29 min (player-timed) | 3× |
| Stardew Valley (farming sim) | ~14 min | 28 | ~6.7 h | ~27 h | — |
| Deepdraft before | 24 min | 28 | 11 h 12 min | 44 h 48 min | 2× |
| **Deepdraft now** | **12 min** | **21** | **4 h 12 min** | **16 h 48 min** | **2×** |

Sources: the RimWorld, Dwarf Fortress, Oxygen Not Included, Timberborn and Clanfolk wikis;
Going Medieval's FAQ and settings files; the Stonehearth forum and modding guide; Crate's
Farthest Frontier forum; Stardew Valley developer notes quoted on Steam. The numbers are at
normal speed and come partly from players, so treat them as approximate.

## What changed

- **Calendar** (`data/calendar/calendar.json`): 30 real seconds per game hour (was 60),
  21 days per season (was 28), summer solstice on day 21 (was 28). WorldClock's fallbacks
  match. At 1× a day is 12 minutes, a season 4 h 12 min and a year 16 h 48 min; at 2×,
  the fastest the player can pick, 6 minutes, 2 h 6 min and 8 h 24 min. A new game
  (summer, day 1, 08:00) reaches its first winter after 8 h 20 min at 1× (4 h 10 min at 2×).
- **Dwarf tiredness drains per game hour** (`SLEEP_DRAIN_PER_HOUR` 0.042 in
  `DwarfAgent`, was 0.0007 per simulation second). The old rate only matched while a
  game hour was 60 seconds; at 30 seconds dwarves would have stayed up about 36 game
  hours and slept every day and a half instead of nightly.
- **Room temperature follows the calendar.** The seasonal swing uses the new
  `WorldClock.solstice_cosine()`, which daylight also uses. RoomManager had hard-coded a
  28-day season and a 112-day year, which with 21-day seasons would have jumped by about
  a tenth of the swing at every season change.
- **Timings counted in days are scaled to ¾** so they keep their place in the season:
  - shrub cuttings: blueberry and strawberry 3 → 2.25 growth days, elderberry 4 → 3;
  - berry regrowth: 2 → 1.5 days;
  - wildlife arrivals: rabbits 2–4 → 1.5–3 days, deer and ducks 4–7 → 3–5.25,
    wolves 7–12 → 5.25–9;
  - not live yet, scaled for when they arrive: tree stages (pine 3/6 → 2.25/4.5, juniper
    4/8 → 3/6, apple 5/10 → 3.75/7.5, oak 8/16 → 6/12) and crops (hops 4/7 → 3/5.25,
    grape vine and plump helmet 6 → 4.5, pig tail 8 → 6).
- **Left alone on purpose:** needs and moods counted in hours (hunger, sleep length,
  mood memories, recreation cooldown, wildlife needs), the 10-day food goal, the 10 days
  the event log and journal keep, hunting pressure's 0.5-per-day fade, the 6-hour arrival
  window, and the planned invader frequencies. Work, walking and eating stay in real
  seconds.

## What it means in play

- Days pass twice as fast. A dwarf is awake about 9 real minutes a day at 1× (18 before),
  so each day gets half the work done; a season gives each dwarf 3 h 9 min awake (8 h 24
  min before).
- Meals and sleep are still three and one a day. Berries regrow and animals arrive a third
  more often per day than before, because their day counts shrank while meals did not.
- Nights are shorter in real time: a winter night is 8 minutes at 1× (16 before), a nap
  3 minutes (6 before).
- Development saves from before the change load, but their days clamp to 21 and stored
  calendar times (plant ages, arrival due dates, log dates) were counted in 112-day years.
  Start a new game to judge the pace.

## Tests

`DwarfRestTest` checks that one game hour drains the per-game-hour rate. `HearthRoomTest`
checks that the seasonal temperature turns smoothly from autumn into winter. Tests that
assumed 28-day seasons, 60-second hours, 3-day cuttings, 2-day regrowth or 2-day rabbit
intervals now read the calendar or the data: `ArrivalEventTest`, `DwarfFoodTest`,
`EventsPanelTest`, `SeasonalRefreshTest`, `ShrubCuttingTest`, `ShrubRegrowthTest`,
`SkyDialTest`. A 100-second step is now over three game hours, enough for the test dwarf
to get hungry and drop its job, so `MinerProfessionTest` and `MiningFeedbackTest` start
their long steps fed and rested (`_work_for` in `MiningAnimationTest`).

The full run of 195 tests passes except `FireAudioTest` and `AudioListeningPointTest`,
which fail on the unfinished fire work (`FurnitureFires.burning()` is handed a
Dictionary), not on this change. The job gate passes 55/55; the lint finds nothing new.

The cutting placement note now prints the exact growth days ("2.25") instead of rounding
to one decimal.

## Not done

- A 3× speed was discussed but not added; the player still has ×1 and ×2.
