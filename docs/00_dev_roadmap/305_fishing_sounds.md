# 305 — Fishing sounds

**Status:** built 2026-11-12; **not listened to.** I cannot hear audio; the owner's listening
decides. Listen at `tmp/fishing_sounds_20261112/review.html`.

## What the owner asked

> can we review the ranger when he is fishing, I think we could add some sounds, please follow
> the sound guide in the claude.md file

## The review: what a catch sounded like

| Moment of a catch | What was heard |
|---|---|
| The rod is cast | Nothing (`00_todo.md` had it: "Fishing's cast has no sound") |
| The float lands | The ducks' lake splash at −18 dB |
| The wait, about 23 s of a 30 s catch | Nothing, by design: fishing is the calm job |
| A fish bites | The same lake splash at −13 dB |
| The fish comes out | The same lake splash at −10 dB |
| The fish hangs on the line | Nothing, and the fish hung still |

All three cues were one recording of a splash in a lake, substitute foley shared with ducks
landing. By measurement they sat at or under a footstep, so a catch was close to silent: my
reading of why fishing seemed to have no sound.

## What was built

| Cue | When (`DwarfFishingPose`) | Recording | Level |
|---|---|---|---|
| `fish_cast` ×3 | the rod starts forward | swings of a bamboo fishing rod | −15 dB |
| `fish_plop` ×3 | the float lands | pebbles falling into a pond | −9 dB |
| `fish_bite` ×3 | the bite | a fish jumping and splashing | −8 dB |
| `fish_land` ×3 | the fish is out | a fish splashing as it is released | −7 dB |
| `fish_land_big` ×2 | the same, for a Ranger's big fish | longer stretches of a fish jumping | −7 dB |
| `fish_flop` ×3 | two flaps on the line | single flops of a fish on land | −10 dB |

- Each variant is a separate recorded event. The wait stays quiet.
- The hanging fish swings its tail with each flop (`DwarfFishingPose`), so the sound has
  something to belong to. That is the one thing here that is seen, not heard.
- Playback is as before: the same bus and voice pool, each cue its own kind with a cooldown and
  a two-voice cap, paused with the game, silent when the Ranger is out of view or sliced away.

## Sources

Eight recordings from Freesound, all CC0 1.0, each licence read on its own page on 2026-11-12:

| Recording | Author | Used for |
|---|---|---|
| [Fishing Rod Swish Swoosh](https://freesound.org/people/Mrthenoronha/sounds/371313/) | Mrthenoronha | the cast |
| [Pebbles into a pond](https://freesound.org/people/HenKonen/sounds/682165/) | HenKonen | the float landing |
| [Fish Jumping Splash 1](https://freesound.org/people/paulprit/sounds/507092/) | paulprit | the bite |
| [Fish Jumping Splash 2](https://freesound.org/people/paulprit/sounds/507091/) | paulprit | a big fish's landing |
| [Fish Splashing Release 1](https://freesound.org/people/paulprit/sounds/507094/) | paulprit | the landing |
| [Fish Splashing Release 2](https://freesound.org/people/paulprit/sounds/507093/) | paulprit | the landing; one bite |
| [Hook and Release](https://freesound.org/people/paulprit/sounds/591348/) | paulprit | the landing |
| [Fish Flopping](https://freesound.org/people/RatBird/sounds/570208/) | RatBird | the flaps |

- **Substitutes, named as such.** The float landing is pebbles, not a float. The landing is a
  fish going back into the water, not one coming out. The cast is a rod swung without a line.
- **Not the lossless originals.** The originals need a Freesound login, so the public HQ MP3
  previews were used and are named as such, as for the game's other recorded sounds.
- **Reproducible.** `tools/audio_sources/fishing/` holds the eight masters, `LICENSE.txt` and
  `source.json` (pages, download URLs, hashes, the conversion, each cue's crop, filters, fades
  and level). `tools/generate_fishing_audio.py` rebuilds all 17 cues without a download.
- **Edited lightly.** Cropped to start on the event, DC removed, gentle high- and low-pass,
  edge fades, level. No change of speed or pitch, nothing synthetic, no denoising.

Four recordings were downloaded and passed over: a single cast of a modern rod (one event, where
three were wanted), a reel cast with a small splash (hiss all through it, and the rod has no
reel), koi splashing in a temple pond (a steady noise behind them) and a caught fish slapping on
snow (very short slaps among handling sounds). A cast described as a mashup of other sounds was
not considered, as its sources could not be traced.

## Decisions I took, for the owner's ear

1. **Which moments get a sound:** the five above, and none for the wait.
2. **The levels.** By the measure in doc 13 the swish and the plop sit just above a footstep, the
   landing about level with a duck's quack, a big fish's landing a little louder, all under an
   axe. The former cues were 8 to 9 dB lower.
3. **A big fish sounds bigger:** its own longer splash.
4. **The fish swings its tail** on the line, twice, with its flops.
5. **Two of the three landings are dull** (their recordings hold little above 5 kHz). If they
   sound muffled beside the third, the third's recording can supply all three.

## Checked, and not

- Waveforms and spectrograms of every recording and every cue. The short cues (swing, plop,
  bite, flap) start on their event within 23 ms, and the landings swell in over at most 48 ms.
  Every cue ends in silence. One stretch of the jumping fish holds short tones (a bird or a
  squeak, my reading of the spectrogram); the bite was cut to end before it.
- All 17 installed cues rebuild from the masters byte for byte; every download and master
  matches its hash in `source.json`; the 119 other sound files are unchanged.
- `FishingTest` hears a catch in order (swing, float, bite, landing, flap) and checks each bank's
  format and length; `RangerTest` hears a big fish land with its own splash. The gate, 55 of 55,
  and the fishing, audio, wildlife and dwarves areas.
- **Not checked: how any of it sounds.** No listening was possible here. Not seen either: the
  fish's tail swing in play.

## Left for later

In `00_todo.md`, "Fishing sounds left for later": the drying rack, a sound for the wait, and
lossless originals.
