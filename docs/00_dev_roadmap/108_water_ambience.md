# 108 — Water ambience

Implemented 2026-10-10: nearby waterfalls have a fuller rush; moving river
reaches have a softer bubbling sound. Both are original procedural synthesis.

## Sound and placement

`WaterAudioSynth` creates nine-second mono loops from colored noise, slow
turbulence, fine spray and overlapping damped bubbles. Waterfalls have a deeper,
broader body; rivers have less hiss and more gentle liquid detail. Equal-power
wraps retain sound through the loop boundary. A private seeded RNG keeps this
independent of weather, world generation and simulation randomness. Banks are
generated on a background thread once per process and cached in memory.

`WaterSound` owns exactly two spatial players per world, using the existing
Work bus volume/mute controls. Every quarter-second it samples visible falling
faces and the sparse measured current field. Nearby contributions determine
the sound position; their loudness is bounded rather than added per voxel.
Positions and gains ease between targets over about 0.7 seconds. River sound
recedes beneath a close waterfall. Panning is stereo; camera focus and zoom
control attenuation consistently with work and wildlife audio.

Current tuning in `data/world_gen/water.json`: waterfall level −19 dB and range
65 blocks; river level −17 dB and range 30 blocks, before synthesis and flow
strength. The waterfall was reduced by 10 dB on 2026-10-11 after playtesting
found its continuous rush masked work, fire and dwarf sounds. Other sound levels
and attenuation ranges are unchanged. Overview zoom fades both layers. Still lakes have no continuous
current sound. Dry, undiscovered and sliced-away water cannot supply a voice.
Stopped currents decay with the presentation field; pause, zero speed, loading,
hidden water presentation or loss of the camera silences playback. Two-times
simulation speed does not raise pitch. Scene exit frees both players.

No changes to water physics, terrain, world layout, save format or sound assets.
Restart Play to load the new scripts; current-version saves remain usable.

## Verification

`WaterAudioTest.gd` checks bank headroom and loop continuity, near/remote sources,
still/dry/hidden/sliced water, pause/speed/loading, bounded voices, unchanged
water state, fade-in and scene cleanup. Its native run records only the game's
Master bus and checks audible falls and rivers, the waterfall's measured 10 dB
reduction against the previous mix, stereo,
distance/zoom attenuation, pause, stopped flow, volume and mute.

Native recordings and logs are under `tmp/water_review/audio/` and
`tmp/water_review/audio_native.log`. `WaterAudioWorldPreview.gd` exercises the
full generated world with actual currents and falls, plus a quiet lake, and
records `world_falls.wav`, `world_river.wav` and `world_lake.wav` there.

Initial mix verified on world seed 2795346874 with all 1,024 terrain tiles present. Recorded
RMS levels were 0.0198 at the falls, 0.00486 at the river and below 0.000001 at
the quiet lake. Source scans peaked at 3.9 ms, four times per real second.
`WaterSurfaceMeshTest` and `WaterSurfaceMotionTest` also pass; the editor import
reports no script errors.
