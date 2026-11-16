"""Prepare the recorded farming cues from local CC0 masters.

A field plays farm_hoe each time the copper hoe bites the ground, farm_sow as a tile is sown by
hand and farm_pull as a ripe tile is pulled.
Sources, credits and edit profiles are in audio_sources/farming/. Requires numpy; no network or
audio decoder is needed. All thirteen outputs use the work bank's mono 48 kHz PCM16 format.
"""
import json
from generate_chopping_audio import ROOT, write
from generate_recorded_work_audio import sound as prepare_sound

SOURCE = ROOT/'tools/audio_sources/farming'


def sound(kind):
    return prepare_sound(kind, SOURCE)


if __name__ == '__main__':
    for kind, profile in json.loads((SOURCE/'source.json').read_text(encoding='utf-8'))['clips'].items():
        write(ROOT/profile['output'], sound(kind))
        print(kind)
