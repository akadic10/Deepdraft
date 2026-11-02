"""Recorded stone-on-stone foley for the construction hammer. Python + numpy.

Six separate CC0 contacts; sources and profiles are in audio_sources/hammer_tree/.
Only regenerates this hammer bank and its local listening sampler.
"""
import json
import numpy as np
from generate_chopping_audio import ROOT, RATE, write
from generate_recorded_work_audio import sound as recorded_sound


if __name__ == '__main__':
    samples, report = [], []
    for index in range(6):
        sound = recorded_sound(f'hammer_stone_{index + 1:02}')
        name = f'hammer_stone_{index + 1:02}.wav'
        write(ROOT / 'assets/audio/work' / name, sound)
        samples.extend([sound, np.zeros(round(.65 * RATE))])
        report.append({'file': name, 'peak': round(float(abs(sound).max()), 4),
                       'rms': round(float(np.sqrt(np.mean(sound ** 2))), 4)})
    write(ROOT / 'tmp/construction_hammer_20261017/hammer_sampler.wav', np.concatenate(samples))
    print(json.dumps(report))
