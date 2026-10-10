# 91 — Rabbit audio

2026-10-09. The player approved soft selection and grazing sounds after the
rabbit pilot. No sleep, hopping, alarm or predator sounds were added.

## Behavior

- Explicit selection, including DEV: Next rabbit, plays one short breath/tooth
  tick. Three variants avoid immediate repeats. A 0.75-second real-time cooldown
  applies across rabbits, with one selection voice at a time. Selection works
  while paused; inspector refreshes never make sound.
- Grazing plays a leafy nibble phrase at 8% and 52% of the six-second animation.
  Three variants, a 0.2-second shared cooldown and two simultaneous grazing
  voices keep wildlife quiet. Stalled frames coalesce crossings into one cue.
- Grazing fades by fourteen blocks from camera focus and is disabled above
  zoom distance 56. Selection uses a wider twenty-four-block range. Both follow
  camera zoom and native stereo placement, with lower levels than work impacts.
- Active grazing playback pauses with WorldClock, resumes only while valid,
  and stops when fleeing, hidden, removed or out of audible range. Game speed
  changes animation/cue timing without changing sample pitch.
- No offscreen/restore backlog, audio save state, animal RNG use or simulation
  changes. Sleeping remains silent except for an explicit selection cue.

## Files and ownership

`tools/generate_rabbit_audio.py` reproducibly creates six original mono 48 kHz
WAVs in `assets/audio/wildlife/`. These are synthesized foley, not wildlife
recordings; there are no external sample licenses or dependencies beyond the
project's existing Python/numpy audio-generation workflow. Generated sampler:
`tmp/rabbit_audio_review/rabbit_sampler.wav` (selection first, then grazing).

WorkFeedback owns the banks and per-kind sound profiles in
`data/audio/work_feedback.json`. It extends the existing Work bus and eight-voice
pool rather than introducing another audio service. Profiles control volume,
range, zoom, cooldown, voice caps and pause policy; legacy work defaults remain.
Weak source references follow moving animals and retire invalid source playback.

WildlifeManager owns the rabbit definition's `feedback` section and observes
crossings in existing meal progress. ObjectExplorerController's optional
`on_explorer_selected` provider callback runs only on explicit selection. No
new autoload, global class, settings UI or scene node is required.

## Verification

All Godot runs use isolated APPDATA/LOCALAPPDATA under `tmp/rabbit_audio_review`.

- Native Godot importer loads all six WAVs and scripts with no parse errors.
- `RabbitAudioTest.gd`: paused selection, real cooldown, variation, no refresh
  spam or RNG mutation, two meal cues, pause/resume, restore silence, interruption,
  sleeping/slice/distance/zoom exclusion, no missed-cue backlog, speed-independent
  pitch, voice caps and scene-exit cleanup.
- `RabbitAudioPlaybackTest.gd`: records actual game Work-bus PCM (no microphone).
  Running/paused selection is audible; grazing is audible nearby; far/overview
  and paused-tail captures are silent; stereo follows the source; peaks retain
  headroom. Output is in `tmp/rabbit_audio_review/native_pcm/`.
- `WorkFeedbackTest.gd`, `MiningFeedbackTest.gd` and `RabbitWildlifeTest.gd` pass:
  existing work timing, pool limits, pause/speed, wildlife behavior and saved
  state remain intact.
- `ObjectExplorerTest.gd` and `SaveManagerRoundTripTest.gd` pass, including
  ordinary object selection, full scene restoration, autosaves and recovery
  from a deliberately corrupted primary save.

To hear it in play, restart the play session and choose **Menu → Development →
DEV: Next rabbit**, then click it while paused or running. Stay close and zoomed
in when it grazes. The existing Work mute/volume route also controls these sounds.
