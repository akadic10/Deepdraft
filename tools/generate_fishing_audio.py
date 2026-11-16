"""Prepare the recorded fishing cues from local CC0 masters.

A catch plays, in order: fish_cast (the rod's swing), fish_plop (the float lands), fish_bite,
fish_land or fish_land_big (a Ranger's big fish) and fish_flop (the caught fish flapping).
Sources, credits and edit profiles are in audio_sources/fishing/. Requires numpy; no network or
audio decoder is needed. All seventeen outputs use the work bank's mono 48 kHz PCM16 format.
"""
import json
from generate_chopping_audio import ROOT, write
from generate_recorded_work_audio import sound as prepare_sound

SOURCE = ROOT/'tools/audio_sources/fishing'


def sound(kind):
    return prepare_sound(kind, SOURCE)


if __name__ == '__main__':
    for kind, profile in json.loads((SOURCE/'source.json').read_text(encoding='utf-8'))['clips'].items():
        write(ROOT/profile['output'], sound(kind))
        print(kind)
