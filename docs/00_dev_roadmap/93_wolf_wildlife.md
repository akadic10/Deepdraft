# 93 — Wolf wildlife

2026-10-09. The player approved the next animal after deer, continuing the
recommended rabbit → deer → wolf sequence. Wolves introduce occasional predation
while keeping wildlife needs gentle and prey populations visible over time.

## Implemented behavior

Four seeded wolves occupy sparse lowland habitats near original prey areas.
Hungry wolves pursue one unclaimed rabbit or deer, with a twelve-second limit,
bounded local routing, safe terrain contact and a one-hour retry delay. Nearby
prey flee. Wolves back away from dwarves; colony combat is not part of this pass.

A successful capture removes one prey animal and starts a brief eating pose.
One meal is credited immediately: 36 hours of satisfaction for a rabbit, 72 for
a deer, with greater appetite relief from deer. This prevents another kill if
feeding is interrupted. Capture is non-graphic and produces no dropped resources.

Because breeding/replenishment is not implemented, JSON reserve floors protect
32 rabbits and 12 deer. Wolves stop taking that species at its floor and never
take starvation damage. This is deliberate pilot balance; coordinated packs,
dens, breeding, domestication and player hunting remain separate work.

Full settings and save behavior: [45 — Wildlife](../40_economy_colony/45_wildlife.md).

## Ownership and assets

WildlifeManager loads `data/entities/animals/wolf.json`, owns seeded identity,
target claims, capture/meal commits, inspector data and persistence. WolfAgent
inherits the common terrestrial movement/rest machinery and overrides feeding
decisions. AnimalNavigation adds bounded approach routing and exact short contact
checks for terrain, placed occupancy and support. Dwarf NavGrid is unchanged.

The optional `wolves` array and `wolf_initialized` flag preserve target IDs,
pursuit progress, retry/satisfaction hours, needs and cosmetic pose phase. Prey
is represented only by the surviving animal records. Loading never repeats a
capture or refills the wolf; older wildlife saves add wolves once.

`tools/generate_wolf.py` creates body, head, tapered ears, tail and leg GLBs in
`assets/animals/wolf/`. The leg is instanced four times. Grey stone-range coat,
cream muzzle/belly and dark paws use the existing muted art palette. Eight
voxels/block and baked .125 scale keep root scale one and ground at Y0. Standing
bounds fit 2×2×2; gait, eating and folded rest animate without a skeleton.

`tools/generate_wolf_audio.py` creates six original synthesized foley WAVs.
These are soft breath/chuff and eating sounds, not wildlife recordings. Playback
reuses WorkFeedback's Work bus, eight-voice pool, source cleanup, pause and zoom
rules. Audio does not consume animal RNG or create saved timers. No new autoload,
global class or main-scene node was added.

## Verification

All Godot runs use isolated APPDATA/LOCALAPPDATA under `tmp/wolf_review`.

- `WolfWildlifeTest.gd`: imported/picked model, shared inspection, paused sound,
  slice concealment, content wolves refusing hunts, saved partial pursuit with
  deterministic continuation, actual chase/escape/capture, single-use meals,
  stale selection removal, eating audio, protected prey floor, larger deer meal,
  dwarf interruption, timeout/retry, exclusive target claims, sleep/recovery,
  wall/pit/corner contact rejection and bounded obstacle detours.
- `DeerPopulationTest.gd`: seeds 0, 42, 1234 and 20261009 each produce four
  repeatable, widely spaced wolves on supported lowland habitat alongside six
  complete deer groups.
- `RabbitWildlifeTest.gd`, `DeerWildlifeTest.gd` and `RabbitAudioTest.gd`: prior
  grazing, rest, terrain, animation, save and audio behavior remains intact.
- `RabbitAudioPlaybackTest.gd -- --wolf`: actual Work-bus PCM confirms nearby
  selection/eating, paused selection, distance/overview silence, stereo placement,
  paused eating tails and quiet headroom. No microphone input is used.
- `SaveManagerRoundTripTest.gd`: full three-species snapshots, meal cooldown and
  an in-flight hunt target survive regular saves, autosaves and recovery from a
  deliberately corrupted primary save.
- `tools/RabbitLivePreview.gd -- --wolf`: native world import/render, four wolves,
  one-time older-save migration preserving prey, public DEV locator, real screen
  picking, shared inspector, Follow/Stop, and standing/eating/rest/scale captures.

Review captures, sound sampler and native PCM are under `tmp/wolf_review/`.

## Playtest

Restart play and choose **Menu → Development → DEV: Next wolf**. Follow it to
watch wandering or an occasional hunt; the inspector explains its current
activity and meal satisfaction. Keep the camera close for quiet selection and
eating cues. Approach with a dwarf to interrupt and make it retreat. Existing
Work mute/volume controls apply.
