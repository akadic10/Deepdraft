# 90 — Rabbit wildlife

2026-10-09. The player approved the rabbit recommendation after a project review
and discussion of mild hunger, rest and later predator/prey interactions.

Follow-up: [91 — Rabbit audio](91_rabbit_audio.md) adds quiet selection and
grazing foley, including pause, distance, variation and repetition controls.

## Shipped

- Seeded population capped at 48 in grassy lowlands, with reproducible identities.
- Three-part voxel rabbit with hopping, grazing, ear motion and sleeping poses.
- Gentle appetite/fatigue, quiet naps, and escape from nearby dwarves.
- Small-animal support/clearance checks, live obstacle revalidation and support
  loss handling, independent of dwarf jobs and ladder navigation.
- Shared inspection with activity/appetite/rest, smooth selection outline,
  Locate/Follow, slice concealment and **DEV: Next rabbit**.
- Complete population and behavioral save state, including partial hops and RNG.

Definition, design and deferred food connections are in [45 — Wildlife](../40_economy_colony/45_wildlife.md).
No starvation, berry consumption, crop theft, breeding, taming, hunting or wolves
ship in this pilot. Ground vegetation is abstract forage and is never depleted.

## Verification

Runs use isolated APPDATA/LOCALAPPDATA beneath `tmp/rabbit_review`; the player's
running game/editor and user saves are left alone.

- Godot 4.7.2 native importer: all three GLBs and new scripts import successfully.
- `RabbitWildlifeTest.gd`: imported mesh picking, bounds, inspector, slicing,
  pause/speed, grazing without terrain changes, interrupted eating, sleep
  recovery, waking/fleeing, occupancy/water/cliffs, swept step clearance,
  support removal during movement, mid-hop JSON state, repeatable behavior
  after restore, stale selection and empty-population persistence.
- `SaveManagerRoundTripTest.gd`: full main-scene save, independent autosave,
  primary load and deliberately corrupted-primary backup recovery, with a
  nonempty rabbit population and nondefault appetite/rest/activity. Deep scene
  state comparisons pass.
- `ObjectExplorerTest.gd`: existing twelve tree stages, furniture actions,
  terrain/slice/tool guards, seasonal continuity and inspector rows still pass.
- `RabbitLivePreview.gd`: native main scene on seed 1234; 48 valid dry lowland
  locations, repeated-seed equality and changed-seed candidate differences.
  Public Development action, terrain-aware screen picking, shared inspector,
  camera Follow/Stop following and actual rendered poses pass.
- Native images reviewed at normal/close zoom and beside a dwarf:
  `tmp/rabbit_review/rabbit_world.png`, `rabbit_grazing.png`,
  `rabbit_sleeping.png`, `rabbit_scale.png`.

The layout comparison varies animal RNG over a fixed generated world; it does
not claim a multi-world terrain balance census. Population density and local
escape behavior should be tuned after ordinary player observation.

## Player check

1. Start a new play session, then Menu → Development → DEV: Next rabbit.
2. Click or follow it; pause/unpause and try 2× speed. Appetite takes several game
   hours to grow, so feeding is deliberately occasional.
3. Bring a dwarf nearby to see it flee. Observe a nap later in the day/night.
4. Save/load while watching a rabbit; identity, needs and behavior persist.
   Camera follow itself is the existing transient camera behavior.

No new autoload or `class_name` requires a project reload.
