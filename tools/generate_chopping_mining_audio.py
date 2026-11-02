"""Prepare recorded axe, stone-pick and soil-mining cues from local CC0 masters.

Sources and edit profiles are in audio_sources/chopping_mining/. Requires numpy.
All eighteen outputs use the work bank's mono 48 kHz PCM16 format.
"""
import json
from generate_chopping_audio import ROOT, write
from generate_recorded_work_audio import sound as prepare_sound

SOURCE = ROOT/'tools/audio_sources/chopping_mining'


def sound(kind):
    return prepare_sound(kind, SOURCE)


if __name__ == '__main__':
    for kind, profile in json.loads((SOURCE/'source.json').read_text(encoding='utf-8'))['clips'].items():
        write(ROOT/profile['output'], sound(kind))
        print(kind)
