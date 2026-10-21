# 249 — Solo games and partner search

The player reported Sollin waiting for a game partner after loading, despite
nearby available dwarves, and requested a smaller happiness reward for solo play.

## Copied-save reproduction

The original quicksave was copied into isolated test storage and loaded through
the normal startup path. In the unchanged code Sollin reached table 40's east
stool and waited until the 30-second timeout, then retried. Guntris, Ildgra and
Brynvin were eligible; the west stool was free, its placement valid and its
approaches walkable. They were outside its 24-block recruitment radius. Other
probes found reachable paths but rejected their 29–31-block length.

The earlier cooldown fix in 203 was still working: these companions had no
recreation memory or retry delay. This was a distance limit, not a stale saved
game or a missing stool.

An occupied table now searches up to 48 routed blocks for a partner, including
the route around the table and room. Initial solo discovery remains local at
24 blocks. Search retains one candidate/route slice per scene frame, 400 nodes,
500 microseconds and the existing three-second attempt limit. Needs, cargo,
explicit movement, privacy, cooldown and working-dwarf eligibility still apply.

The same copied save now recruits Guntris for Sollin. One initial travel attempt
was cancelled safely and retried; both were seated together by the 50-second
sample and both had earned the shared memory by the 70-second sample. No
participant was repositioned or made eligible by the test. Evidence includes
all five dwarves' eligibility, needs, cells, stool claims and route results.

## Solo and shared play

- One installed stool is enough for solo play. The dwarf begins playing after
  sitting down instead of waiting without benefit. A completed 20-second solo
  game earns **+4 happiness for 12 game hours**.
- A second dwarf can join on the opposite stool. When both are seated, a fresh
  20-second shared game begins. Completing it gives **+8 to each**, also for
  12 game hours. Travelling and prior solo time do not count as shared play.
- A solo player takes both animation turns. The inspector distinguishes solo
  play, shared play and travel; placement, recipe and item descriptions explain
  the one-stool and two-stool options and the different rewards.
- An already recruited traveller gets bounded arrival time. If it never arrives,
  the seated dwarf can finish for the solo reward; the traveller earns nothing
  and returns to work with the short retry delay.
- Successful games retain the six-game-hour cooldown. Interrupted games release
  claims and workers with the existing half-hour retry. Food, sleep, movement,
  professions, blocked access, removed furniture and scene teardown remain safe.

Solo and social memories have separate timers, but only the stronger contributes.
Solo play cannot downgrade or prolong a live social memory. Repetition refreshes
the relevant thought without stacking. The optional solo timer saves only while
positive; old `recreation_memory_hours` keeps its original social meaning.

## Validation

- Native copied-save reproduction before and after, with the original save's
  positions, needs, furniture and normal simulation.
- `RecreationSoloTest`: one stool, solo reward/animation, a companion beyond both
  old radii, late joining with a full shared duration, an unarrived companion's
  timeout, mood precedence/expiry, legacy and current JSON restoration, cooldown,
  explicit interruption, seat release and worker availability. Headless and
  native runs pass; the fixture is included in the default reliability gate.
- `RudimentaryRecreationTest`: crafting and physical installation, all rotations,
  contacts, two-player play, existing-memory eligibility, pause/speed, third-player
  exclusion, needs/work interruptions, partial-game no-reward and scene teardown.
- `DwarfDiningTest`, `DwarfIdleBehaviorTest`, `DwarfFoodTest` and `JobLifecycleTest`
  pass, retaining dining/idle handoff, nutrition, priorities and work ownership.
- `SaveManagerRoundTripTest` passes with both earned memory timers present,
  full owner restoration, autosave/backup recovery and malformed solo timer
  rejection. Legacy fields retain their meaning and schema version remains 2.

Evidence and task-start code/save hashes are in `tmp/recreation_fix_20261019/`.
The copied-save observations are `before_run/report.json` and
`fixed_run/report.json`. Minimal fixtures retain their existing sky/weather
startup warnings; accepted runs contain no script errors. All four original
player save files are unchanged. Restart Play and load the existing save.
No export or commit was created.
