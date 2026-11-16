"""Prepare the basic smelter's recorded sounds from local CC0 masters.

A copper bar's batch plays, in order: smelt_toss as each lump lands in the pot (smelt_log for a log
pushed into the fire hole instead), smelt_blow for each breath through the hollow stick, the smelter
loop while the coals glow and the copper melts, and smelt_bar when the cast bar is taken off.
Sources, credits and edit profiles are in audio_sources/smelter/. Requires numpy; no network or
audio decoder is needed. The twelve cues use the work bank's mono 48 kHz PCM16 format; the loop is
made as the campfire's is (generate_fire_audio.py), mono 22.05 kHz.
"""
import json
from generate_chopping_audio import ROOT, write
from generate_fire_audio import write_sound as write_fire
from generate_recorded_work_audio import sound as prepare_sound

SOURCE = ROOT/'tools/audio_sources/smelter'


def sound(kind):
    return prepare_sound(kind, SOURCE)


if __name__ == '__main__':
    profiles = json.loads((SOURCE/'source.json').read_text(encoding='utf-8'))
    for kind, profile in profiles['clips'].items():
        write(ROOT/profile['output'], sound(kind))
        print(kind)
    for kind in profiles['banks']: write_fire(kind, SOURCE)
