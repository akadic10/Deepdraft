# 170 — Environment sound details and weather

Implemented 2026-10-13 following the player's request to add the remaining
sound list in one pass, including actual rain and storm weather.

## Listening and weather

- Faint warm-day insects and individual night chirps complement the existing
  cricket bed. Winter and snow suppress both insects and frogs.
- Autumn blends toward dry leaves; winter gains a subdued wind texture and
  occasional creaks from nearby visible trees. Felled trees stop contributing.
- Live water beside a solid bank supplies local shoreline laps. Warm nights
  add frogs there. Draining the bank or slicing away its water removes them.
- Drips require a discovered natural cave with actual water. Dry bedrooms,
  dry tunnels and undiscovered caves never produce fictional drip sources.
- Sparse nighttime howls come from actual nearby awake wolves. Hidden,
  sleeping, hunting, eating or fleeing wolves cannot emit them. Playback
  follows the live animal and stops when the source becomes invalid.
- Rain and Storm join clear/overcast/fog/snow. Spring, summer and autumn can
  schedule them; winter retains its snow palette. Ordinary rain has no thunder.
  Storms add occasional low, distant rumbles. Cloud/haze changes, visible rain
  and the sky dial all follow the same weather ID.
- Thin rain streaks occupy one bounded mesh (at most 180 streaks), clipped to
  physical roofs and the visible slice. Visually removing a roof cannot rain
  into its room. Rain is presentation only; water mass, flooding, soil moisture
  and crop simulation are unaffected.
- Outdoor rain recedes into quieter roof patter near a sheltered roof. Deep
  underground spaces remain quiet. All playback runs in real time: pause
  softens beds and stops calls; fast simulation does not change pitch.

The existing Ambience slider controls these environmental layers. Actual wolf
howls use Effects alongside the other animal sounds. Preferences are preserved.
No music or new simulated bird/frog/owl populations are added.

## Ownership

AmbientAudio owns `data/audio/environment.json`, ten loop players and a shared
three-voice call pool with at most one active phrase per family. Six new loop
assets and eighteen phrase variants are original seeded synthesis from
`tools/generate_environment_details.py`; the accepted first-pass assets remain
unchanged. All sounds fade in/out through the existing bus and lifetime logic.

EnvironmentSoundSources performs bounded, read-only neighborhood queries every
.75 seconds, using live WaterManager volumes, cave discovery, streamed trees
and the actual wildlife roster. Source handles are weak references; scene exit
and save loading discard all derived audio state. No gameplay RNG is consumed.

The camera listening ray now also stops at visible water, using its fractional
surface height. A solid-terrain-only ray could sink below a lake and classify a
shore view as enclosed. Draining the water restores terrain focus.

WeatherManager remains the sole schedule/definition/persistence owner and
creates a scene-owned WeatherPrecipitation component when required. New weather
uses the existing saved ID and exact RNG-state format; no migration is needed.

## Verification

- EnvironmentDetailsTest checks habitat discovery, drainage, source visibility,
  wolves sleeping/hiding, seasons, rain/roof/thunder separation, weather IDs,
  unchanged RNG, rain slicing, and actual native mixer output for all 12 new
  sound families. Native peaks remain below .14 at the review volumes.
- AudioListeningPointTest covers fractional water, drainage, sliced bedrooms,
  camera motion and detached views. AmbientAudioTest retains bus/mute/settings,
  pause/speed, bounded voices and scene replacement coverage.
- WaterAudioTest, FireAudioTest, WolfWildlifeTest, SkyDialTest, DioramaSkyTest,
  SkySceneLifecycleTest and full dock-driven SaveManagerRoundTripTest pass.
- WeatherPersistenceTest compares 112 future daily choices across 12 seeded
  save/load cases. Its PASS marker now works with the shared test runner.
- Native generated-world review covers shoreline night, autumn, winter, rain
  and storm. It checks source gains, precipitation, unchanged water mass and
  scene teardown. Recordings and screenshots are captured from the game.
  Local habitat scans measure about 2.0 ms every .75 seconds (maximum 2.35 ms
  in this capture); rain/storm draw 117/180 streaks. Water mass is unchanged.

Evidence: [concepts/170_environment_sound_details](concepts/170_environment_sound_details/).
Runtime logs and the isolated review profiles are in
`tmp/environment_details_20261013/`. Review code is
`tools/environment_audio/ReviewDetails.gd`.

Restart Play and load normally. Menu → Audio retains the player's volume
settings. Final balance and synthesized timbres remain subject to player
listening review on their usual speakers/headphones.
