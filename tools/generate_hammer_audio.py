"""Original stone-hammer knocks, with no external samples. Python + numpy.

Seeded dry, weighty masonry impacts contrast with the pick's bright steel ring.
Only regenerates this hammer bank and its local listening sampler.
"""
import json
import numpy as np
from generate_chopping_audio import ROOT, RATE, filtered_noise, write


def impact(seed):
    rng = np.random.default_rng(seed)
    duration = .23
    t = np.arange(round(duration * RATE)) / RATE
    sound = filtered_noise(rng, len(t), 6500) * np.exp(-t / .0025) * .7
    sound += filtered_noise(rng, len(t), 1500) * np.exp(-t / .018) * .5
    for frequency, strength, decay in [(235, .8, .022), (493, .5, .017),
                                      (1079, .24, .012), (1837, .1, .009)]:
        sound += np.sin(2 * np.pi * frequency * rng.uniform(.93, 1.07) * t) * np.exp(-t / decay) * strength
    # A tiny gritty settling tail, without the pick's long scrape or steel ping.
    sound += filtered_noise(rng, len(t), 3100) * (1 - np.exp(-t / .008)) * np.exp(-t / .027) * .09
    sound -= sound.mean()
    sound *= np.minimum(t / .0004, 1) * np.minimum((duration - t) / .012, 1)
    sound *= .7 / max(np.max(np.abs(sound)), .001)
    return sound


if __name__ == '__main__':
    samples, report = [], []
    for index in range(6):
        sound = impact(28700 + index)
        name = f'hammer_stone_{index + 1:02}.wav'
        write(ROOT / 'assets/audio/work' / name, sound)
        samples.extend([sound, np.zeros(round(.65 * RATE))])
        report.append({'file': name, 'peak': round(float(abs(sound).max()), 4),
                       'rms': round(float(np.sqrt(np.mean(sound ** 2))), 4)})
    write(ROOT / 'tmp/construction_hammer_20261017/hammer_sampler.wav', np.concatenate(samples))
    print(json.dumps(report))
