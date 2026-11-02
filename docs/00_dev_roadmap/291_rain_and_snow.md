# 291 — Rain and snow across the whole view

2026-11-01. Built, with storm lightning added the same day; the owner's look in Play is next.

From the owner: "can we review the rain and other weather animations for my game, it appears
the rain only falls in the center section. are there better rain and snow animations to
consider?" Shown a review with three ways to draw weather, the owner took the recommended
one, a drop field drawn by the graphics card: "Yes, build it". Offered a lightning flash timed
to the thunder next, the owner answered "Add lightning" (see "Lightning" below).

The rules now live in doc 24, "Rain and Snow" and "Lightning". This doc records what was wrong,
what changed and how it was checked.

## What was wrong

- **Rain only near the centre.** Every drop was placed within `radius` (24) blocks of the
  ground at screen centre: a 48 × 48 square. On the owner's 32:9 screen the default camera
  shows about 105 × 190–380 blocks, so rain covered about 8% of the view, and about 2% zoomed
  all the way out.
- **Thin and jumpy.** 117 streaks in rain, 180 in a storm. Every 0.75 s, and every 4 blocks
  of camera travel, all drops jumped to new random spots; one fall took 0.8 s, so no drop
  finished falling. The mesh was rebuilt in GDScript 30 times a second.
- **Hard to see.** Streaks were about one pixel wide, in a fixed unshaded colour as bright at
  midnight as at noon.
- **Water.** Streaks over the river ran down to the riverbed; nothing splashed.
- **Switching.** Rain started and stopped at once while the sky faded.
- **Snow** had no falling animation at all; snow days were only fog and cloud.

## What changed for the player

- Rain and storms fall over the whole view at every zoom, on any screen shape. A storm is
  heavier, faster and slants more.
- Snow falls as small spinning square flakes that flutter down, rest on the ground for a
  moment and fade.
- Rain ends in a small splash on the ground and a ripple ring on water, on the water surface.
- A change of weather fades the old one out over 4 s, then the new one in over 4 s.
- Drops dim at night instead of glowing.
- With the slice on just above the ground, as the owner plays, the space under the cut stays
  full of rain. Rain still never falls into a room whose roof the slice hides.

## How it is built

- `scripts/shaders/weather_precipitation.gdshader` (new): one quad per drop, placed and
  animated in the vertex shader from its world tile, number and fall cycle.
- `scripts/components/WeatherPrecipitation.gd` (rewritten): picks the tiles in view on two
  zoom levels, keeps the landing map (top solid block plus water per column), fades the
  weather and sets the uniforms. One `MultiMesh` of 192 × 256 instances; only the drops
  shown are drawn.
- `data/weather/rain.json`, `storm.json`: new `precipitation` keys; the old `radius`,
  `streaks`, `width` and `length` are gone. `snow.json`: a new snow `precipitation` block.
- `scripts/tests/WeatherPrecipitationTest.gd` (new, `sky` area) replaces the rain-geometry
  checks in `EnvironmentDetailsTest`, which poked the old mesh.

## How it was checked

- `WeatherPrecipitationTest`: rain reaches every screen point at zoom 20 to 180, pitch 30° to
  80°, yaw 0° to 45°, on 16:9 and 32:9; a pan keeps the same world tiles; drops per screen
  area stay within 1% across zoom, a level change included; drops land on a built roof, in a
  dug pit, on 0.6 and 3.25 blocks of water and back on the ground when it dries; a roof the
  slice hides still holds drops above the cut; pause freezes the fall; clear weather fades the
  storm out; snow follows a storm only after the storm has faded.
- The `sky` area, `EnvironmentDetailsTest`, `AmbientAudioTest` and `SkyDialTest` pass. Gate
  55/55; the lint finds nothing new.
- Captures over a copy of the owner's quicksave (slice on at level 47), in an isolated profile
  at 3200 × 900: rain by day at default, close and far zoom, a storm at night, snow at the
  three zooms. Each held the 60 fps cap. Pictures are in `tmp/weather_capture_20261101/`.

## Gotchas found while building

- **The projection is flipped in y** on this renderer: `PROJECTION_MATRIX[1][1]` was negative,
  which shrank every drop to its smallest size. Screen-size maths uses its absolute value.
- **The slice sits just above the ground in play.** The owner's save had the slice on at 47,
  three blocks over the grass. Anything drawn above the ground must be checked under a low cut.
- **A `--script` capture must call `SkyController.rebind_to_current_scene()`** after the world
  loads, or the sky and light never change (night looked like day).

## Lightning

- **What the player sees.** In a storm each thunder now comes with a lightning strike: one to
  three blue-white flickers light the sky, the clouds, the distant fog and open ground, and the
  thunder follows 0.5–2.5 s later. Nearer strikes are brighter and rumble sooner. Rooms under a
  roof stay dark, even when the slice hides the roof.
- **Built in** `SkyController.flash_lightning()`, `lightning_level()` and a shadowless
  `Lightning` light made on the first strike. `AmbientAudio._strike()` runs when a thunder call
  comes due, and `_tick_thunder()` plays the thunder after the lead. The thunder cadence is
  unchanged (35–85 s), as are its sounds, bus, volume, voice limit and pause behaviour.
- **Data:** `lightning` in `data/sky/sky_settings.json` (colour, light energy, sky and cloud
  boost, pitch, flickers, gaps, fade); `flash_lead` on the thunder call in
  `data/audio/environment.json`.
- **Checked:** new `StormLightningTest` (sky area), which covers:
  - the flash lighting the light, fog and clouds;
  - its fade and its exact return to the storm's colours;
  - one light kept across rebinds;
  - no thunder before the flash or during the lead, and the thunder after it.

  A capture of a night storm over the owner's save shows the calm night, the flash's peak and
  the scene a quarter second later, with the house interior unchanged throughout
  (`tmp/lightning_capture_20261101/`).

## Thunder sounds

From the owner: "does the lightning and thunder have in game sound files, if not, can you
review claude.md and import some".

- **What was there.** Thunder already had three real recordings:
  - CC0 "Thunder 04/06/07" by Emulius (Freesound), prepared on 2026-10-28 under the sound
    workflow;
  - all three are distant thunder, rolling in over 1.2–2.2 s, with no crack.
- **What was missing.** The lightning had no sound of its own. In life a lightning strike's
  sound is its thunder, and a near strike starts with a sharp crack.
- **Added** three recorded close cracks, `thunder_near_01`–`03`. They play for the nearest 30%
  of strikes (`near_share`), 0.5–1.1 s after the flash. Farther strikes keep the distant
  rumbles. The cracks reach full volume within 0.06–0.38 s.
- **Sources:** all three are CC0, checked on each Freesound page on 2026-11-01:
  - cognito perceptu, "thunder sharp dry crack 2" (721072);
  - TRP, "200817 Thunder, pretty close crack 4pm" (567945);
  - cognito perceptu, "thunder crack.wav" (347853).

  The original lossless uploads need a Freesound login, so the public HQ MP3 previews were used,
  as for the existing thunder.
- **Preparation** followed the 2026-10-28 conversion exactly: one microphone, the same Kaiser
  resampler to 22.05 kHz, peak 0.8 masters.
  - Records: `tools/audio_sources/rain_thunder/source.json` and `LICENSE.txt` now hold eight
    sources.
  - Rebuild: `tools/generate_rain_thunder_audio.py` and the details generator rebuild all eight
    files without a download. The five existing files came out byte-identical.
  - Godot imported the new files headlessly (`tools/voxel_assets/Import.ps1`).
- **Listening review:** `tmp/thunder_near_20261101/review.html` has:
  - the new cracks and the old rumbles, at file and in-game level;
  - a 30-second storm mix and the source previews;
  - credits and measurements.

  The sounds were chosen from the uploaders' descriptions and checked by waveform measurement
  and tests; nobody has listened yet, so the owner's listening decides.
- **Checked:** `StormLightningTest` now also checks that the three cracks load, that a near strike
  plays a crack and a far strike a rumble, and that both are the same thunder call.

## Not in this milestone

- Snow cover on open ground (doc 24, "Planned weather effects") and wet-looking ground in rain.
- Cloud shadows drifting over the ground, so cloudy days read from the RTS angle; the sky is
  almost never on screen at the default pitch.
- Wind is fixed toward −X; nothing sways trees or grass in a storm.

## To tune in Play

All in `data/weather/*.json`, `precipitation`: `intensity` (how many drops), `opacity`,
`width_px` and `length_px` (rain), `size_px` (snow), `slant`, `speed`, `color`. Lightning:
`light_energy` and `sky_boost` in `data/sky/sky_settings.json` for its brightness, and the
thunder call's `interval` in `data/audio/environment.json` for how often it strikes.
