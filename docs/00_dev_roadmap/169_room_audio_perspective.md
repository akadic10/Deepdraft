# 169 — Room audio perspective

Fixed 2026-10-13 after the player could not hear wall torches or nearby snoring
in a sliced bedroom, with Effects at 100% and Ambience at 50%.

The saved camera's orbit pivot was at Y61.23 while the bedroom floor was Y44.
Cursor zoom and the camera's terrain-floor guard can lift that pivot away from
what the player sees. Using it as the listening point put torches outside their
vertical hearing range and displaced horizontal snore attenuation.

`Camera.get_work_audio_context()` now traces the centre-screen ray through live
terrain at the current slice. All sound owners share its result once per process
frame. Distance to the hit supplies zoom attenuation. A ray without terrain falls
back to the pivot; a detached rig or camera supplies no context. Actual camera
movement, sound assets, volume profiles, user preferences and saves are unchanged.

Validation:

- `AudioListeningPointTest` covers the elevated pivot, sliced bedroom floor,
  actual snore emission, audible torch gain, panning, zoom, hidden sources above
  Slice, full-world roof, mined floor, sky-ray fallback and detached rig.
- DwarfRestTest, FireAudioTest, WorkFeedbackTest, WaterAudioTest and
  AmbientAudioTest pass.
- Native playback loads a copy of the player's quicksave through the real dock
  menu in isolated APPDATA. The corrected focus is `(660.12, 44.05, 473.47)`.
  Aggregate fire gain rises from zero to .057. The central sleeper's spatial
  gain rises from .194 to .272; the adjacent sleeper rises from .012 to .088.
  Actual mixer recordings contain both effects; the room mix peaks below .05.
  Separate captures can include unrelated local effects, so PCM is supporting
  evidence alongside explicit fire gain and snore emission counts.
- The original quicksave and audio.cfg retain their SHA-256 hashes.
- Headless editor import exits successfully with no errors.

Evidence: [review report](concepts/169_room_audio_perspective/review.json),
[tests](concepts/169_room_audio_perspective/tests.json),
[room capture](concepts/169_room_audio_perspective/room.png), and
[room audio](concepts/169_room_audio_perspective/room_mix.wav).
`tools/environment_audio/ReviewRoom.gd` reproduces the isolated comparison;
runtime logs are in `tmp/room_audio_20261013/`.

Restart Play and load normally. Player listening review should confirm the final
balance on the usual speakers or headphones.
