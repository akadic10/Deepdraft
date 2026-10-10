# 92 — Deer wildlife

2026-10-09. The player approved deer after the rabbit and quiet-audio pilots.
Deer add a larger grazer with loose groups, distinct walking/grazing/rest poses,
faster flight from dwarves, soft selection/eating sounds and persistent herds.

## Scope and ownership

Up to eighteen deer start in six groups of three on connected lowland grass.
Groups wander locally and tend to remain together; nearby dwarves interrupt
eating or rest and make them run. Appetite and fatigue remain gentle, with no
starvation or deaths. They graze abstract ground vegetation. Berry depletion,
farm theft, hunting, wolves, breeding, domestication and sex/age variants remain
separate work. Full tuning is in `data/entities/animals/deer.json` and
[45 — Wildlife](../40_economy_colony/45_wildlife.md).

WildlifeManager remains the sole definition/population/inspection/save owner.
RabbitAgent and DeerAgent now inherit GrazerAgent's common needs and terrain
behavior. Rabbit art/poses and save fields are preserved. Deer adds loose herd
steering, peer destination avoidance and `herd_id`. AnimalNavigation checks the
entire 2×2 footprint and four-cell clearance; two-cell cardinal strides cover
all swept columns. Dwarf navigation is unchanged.

The optional deer array and initialization flag extend the existing `wildlife`
save section. A rabbit-only snapshot adds seeded deer once, preserving rabbits;
an explicitly saved empty deer population does not replenish. Partial strides,
needs, poses, deterministic RNG state and herd identity survive restoration.

## Art and audio

`tools/generate_deer.py` creates six original voxel GLBs under
`assets/animals/deer/`: body, neck, head, ears, antlers and one leg repeated four
times. Eight voxels per block are baked into the meshes; root scale is one.
The grounded standing model fits the 2×2×4 navigation envelope. Separate neck
and head pivots reach toward the grass; resting lowers the torso and folds legs.
The initial antlered form has brown fur, a cream throat/rump and dark hooves.

`tools/generate_deer_audio.py` creates six original synthesized foley WAVs under
`assets/audio/wildlife/`, with three quiet breath cues and three leafy chews.
These are generated sounds, not wildlife recordings. WorkFeedback's existing
Work bus, eight-voice pool, pause rules and cosmetic RNG own all playback. Sound
profiles live in its JSON; meal cue fractions live in the animal definition.
No new autoload, global class or main-scene node is required for deer.

## Verification

Godot runs use isolated APPDATA/LOCALAPPDATA under `tmp/deer_review`.

- `DeerWildlifeTest.gd`: imported bounds, mesh picking, inspector/herd count,
  paused selection, gentle feeding/sleep, interruption/faster flight, whole
  footprint obstacles/support, terrace/headroom/cliff checks, loose cohesion,
  peer spacing, gait articulation and mixed-species deterministic restoration.
- `DeerPopulationTest.gd`: seeds 0, 42, 1234 and 20261009 each produce six
  complete groups, with repeatable identities, supported nonoverlapping
  footprints, distinct layouts and separate home areas.
- `RabbitWildlifeTest.gd` and `RabbitAudioTest.gd`: existing rabbit behavior,
  pause, saved state, cue timing and sound/source lifecycle still pass.
- `RabbitAudioPlaybackTest.gd -- --deer`: native Work-bus PCM confirms audible
  running/paused selection and nearby eating, silent far/zoomed-out/paused tails,
  stereo placement and quiet headroom. No microphone input is used.
- `SaveManagerRoundTripTest.gd`: full mixed population, deer needs and herd IDs,
  regular saves, autosaves and corrupted-primary backup recovery pass.
- `tools/RabbitLivePreview.gd -- --deer`: seed 1234 has 48 rabbits and 18 deer,
  six repeatable connected groups, different candidate layouts under a changed
  seed, one-time rabbit-save migration, real screen picking, public DEV action,
  inspector Follow/Stop, and native standing/grazing/rest/scale captures.

Review images and the generated sound sampler are in `tmp/deer_review/`.
Native PCM recordings are in `tmp/deer_review/native_pcm/`.

## Playtest

Restart play, then choose **Menu → Development → DEV: Next deer**. Use Follow
to watch a group wander, click for its soft selection cue, and stay close while
it grazes. Move a dwarf nearby to trigger escape. The inspector shows activity,
appetite, rest and herd size. Existing Work audio volume/mute controls apply.
