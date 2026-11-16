# 307 — The basic smelter's sounds

**Status:** built 2026-11-13; **not listened to.** I cannot hear audio; the owner's listening
decides. Listen at `tmp/smelter_sounds_20261113/review.html`.

## What the owner asked

> The basic smelter could use some audio as well when it is in action, use the audio guide from
> claude.md

## The review: what the smelter sounded like

| Moment of a copper bar's batch | What was heard |
|---|---|
| Each lump of ore, and the coal, is thrown into the pot | Nothing |
| A log is pushed into the fire hole (a batch over logs) | Nothing |
| The Blacksmith blows on the fire through its stick, three breaths | Nothing |
| The coals glow and the copper melts, four game hours | Nothing |
| The copper sets and the coals go out | Nothing |
| The bar is taken off the casting stone | Nothing |
| A tool is hammered on the casting stone | The builders' stone hammer |

The smelter had no sound of its own. `00_todo.md` had it as "Sounds for the charge".

## What was built

| Sound | When | Recording | Level |
|---|---|---|---|
| `smelt_toss` ×3 | a lump lands in the pot | rocks thrown onto a pile of rocks | −6 dB |
| `smelt_log` ×3 | a log goes into the fire hole | logs thrown onto other logs | −7 dB |
| `smelt_blow` ×3 | each breath, as the blow starts | breath through a pipe or a tube | −13 dB |
| the `smelter` fire, a 29 s loop | while the coals show | the fire of a wood-fired pottery kiln | −13 dB |
| `smelt_bar` ×3 | the bar is taken off and lands beside the smelter | an aluminium ingot dropped on concrete | −10 dB |

- **Heard as it is seen.** The lumps, logs and breaths play at the marks the pose is drawn by
  (`DwarfSmeltPose.cues`): about 1.5 s apart for the lumps and 1.9 s for the breaths.
- **The fire follows the coals.** It starts as the last lump goes in, burns through the blowing
  and the melt, and stops when the copper sets. An idle smelter is silent. Lumps and logs land
  in a cold smelter, so those two sounds hold no fire.
- **Each variant is a separate recorded event.**
- **Unchanged:** the copper setting is silent, and a tool hammered on the casting stone keeps the
  stone hammer's knock.
- **Playback is the game's own.** The cues use the work sounds' bus and voice pool, each its own
  kind with a cooldown and a two-voice cap. The fire uses the fires' pool of four voices, out to
  20 blocks, as a campfire does. Everything pauses with the game and is silent out of view or
  sliced away; work taken up again replays nothing.
- **Code:** `DwarfSmeltPose` (the marks), `DwarfWorkExecution` (plays them, and a batch's
  `collect_sound`), `WorkFeedback` (`play_smelting`, `play_collect`), `WorkshopBatch`,
  `InstalledFurnitureComponent.batch_showing`, `FurnitureFires.burning`, `FurnitureFireSound`
  (a loop for every fire kind in the settings). Data: `work_feedback.json`,
  `basic_smelter.json` (`fire_sound`), the copper bar's `collect_sound`.

## Sources

Nine recordings from Freesound, all CC0 1.0, each licence read on its own page on 2026-11-13:

| Recording | Author | Used for |
|---|---|---|
| [Foley_Rocks_Stones_Impacts_Mono](https://freesound.org/people/Nox_Sound/sounds/567701/) | Nox_Sound | the lumps |
| [Wood logs - woodshed](https://freesound.org/people/Vrymaa/sounds/734628/) | Vrymaa | the logs |
| [dhungro](https://freesound.org/people/pbimal/sounds/646756/) | pbimal | a breath |
| [Blow in Card Tube01](https://freesound.org/people/SuzieHanna/sounds/676737/) | SuzieHanna | a breath |
| [Breath in Card Tube02](https://freesound.org/people/SuzieHanna/sounds/676738/) | SuzieHanna | a breath |
| [dropping_aluminum_ingots2](https://freesound.org/people/wjoojoo/sounds/179720/) | wjoojoo | the bar |
| [dropping_aluminum_ingots3](https://freesound.org/people/wjoojoo/sounds/179721/) | wjoojoo | the bar |
| [dropping_aluminum_ingots5](https://freesound.org/people/wjoojoo/sounds/179723/) | wjoojoo | the bar |
| [Anagama Kiln Pottery Fire](https://freesound.org/people/nicotep/sounds/761354/) | nicotep | the fire |

- **Direct:** the lumps are "rocks being thrown at a pile of rocks", which is what the game shows.
- **Substitutes, named as such.**
  - The logs are thrown onto other logs, not pushed into a stone hole.
  - One breath is blown through the plastic pipe its uploader blows a charcoal fire with; two
    are blown through a cardboard tube. No fire burns in any of them.
  - The bar is an aluminium ingot on concrete, not copper on stone.
  - The fire is a pottery kiln's at about 1300 °C, not a smelting fire.
- **Not the lossless originals.** The originals need a Freesound login, so the public HQ MP3
  previews were used and are named as such, as for the game's other recorded sounds.
- **Reproducible.** `tools/audio_sources/smelter/` holds the nine masters, `LICENSE.txt` and
  `source.json` (pages, download URLs, hashes, the conversion, each cue's crop, filters, fades
  and level). `tools/generate_smelter_audio.py` rebuilds the twelve cues and the loop without a
  download. `tools/generate_fire_audio.py` now takes a source folder, so the smelter's loop is
  made as the campfire's is; the campfire and the torch still rebuild byte for byte.
- **Edited lightly.** Cropped to start on the event, DC removed, gentle high- and low-pass, edge
  fades, level. No change of speed or pitch, nothing synthetic, no denoising.
  - Each breath is 1.2 s of a longer one, faded out: the pose blows for about a second.
  - The bar is low-passed at 8 kHz, because aluminium rings brighter than copper.
  - The loop is 31 s of the kiln (from 41 s in), its loudest pops rounded off as the campfire's
    are, its last two seconds crossfaded into its first.

**Passed over,** and why:
- Two uploads were not what their titles said: a "rock drop" was stale bread falling into a
  plastic bowl, and "metal scraping on rock" was cereal poured into a glass bowl.
- "Fire Large Roar And Hiss With Crackles" looked ideal, a steady roar. Matched against itself
  it is one six-second stretch repeated for three minutes, so it is not a natural recording.
- Another fire roar had its lows and highs boosted by its uploader and is clipped.
- A "gentle tube blow" is a processed hum; a "breathing through long and narrow tube" has delay
  and modulation added.
- Bellows, of which there were several: a bellows is not what the dwarf holds.
- Stones dropped on the ground were deep thuds with no clack; a stone dropped in a dry well has
  a cavern's tail.
- Coal burning in a tile oven is the right fuel but 7 s long, too short to loop. A fireplace's
  rumble lies almost wholly under 250 Hz, which small speakers barely play. A clay stove and
  slow-burning charcoal are sparse ticks over near silence.

## Decisions I took, for the owner's ear

1. **Which moments get a sound:** the five above. None for the copper setting, and the tool
   hammering keeps its knock.
2. **The fire crackles; it does not roar.** The kiln is the nearest real fire found. If it reads
   as a second campfire, a recording of a steady roar is the thing to look for.
3. **The fire is as loud as a campfire.** Its loop is brighter, so −13 dB matches the campfire's
   −10 dB by the measure in doc 13.
4. **The cues' levels.** By that measure the lump and the log sit about level with a fish being
   landed, well under an axe; the breath between a rod's swish and that landing; the bar level
   with the landing.
5. **The bar is dulled a little** (the 8 kHz low-pass). It is still aluminium; if it sounds like
   a tin, a recording of copper or bronze on stone is the fix.
6. **The breaths differ:** one pipe, two tubes of another kind. If they sound like three
   different things, the cardboard tube alone can supply all three.
7. **The bar's sound comes at the end of the take-down,** as the bar lands beside the smelter.

## Checked, and not

- Waveforms and spectrograms of every recording and every cue. The lumps, logs and bar start on
  their event within 10 ms, the breaths within 33 ms. Every cue ends in silence. The loop's seam
  steps less than its neighbouring samples do, and its last second is 0.3 dB beside its first.
- All twelve cues and the loop rebuild from the masters byte for byte; every download and master
  matches its hash in `source.json`; the 136 other sound files are unchanged.
- `BasicSmelterTest` hears a coal charge in order (three lumps, then three breaths, none before
  the last lump is in), a log charge (two logs, two lumps, three breaths), nothing replayed after
  a charge is given up and taken up again, and the bar once on collection. `FireAudioTest` gives
  the smelter a voice only while its coals show, and checks the new loop's format, level and
  seam.
- **Not checked: how any of it sounds.** No listening was possible here. Not seen in play either.

## Left for later

In `00_todo.md`, "The smelter's sounds left for later": a roar under the crackle, stone on copper
for the tool hammering, the copper setting, lossless originals; and under "The Blacksmith left
for later", the fire answering the breath.
