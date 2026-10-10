"""Original soft rabbit foley, not field recordings. No external samples.

Three breath/tooth-tick selection cues and three leafy nibble phrases. Seeded
noise gives reproducible mono 48 kHz PCM with no pitched squeaks or sharp attacks.
The listening sampler has selection first, then grazing, with silent gaps.
"""
import json
import numpy as np
from generate_chopping_audio import ROOT, RATE, filtered_noise, write


def pulse(t, onset, length):
    phase = np.clip((t - onset) / length, 0, 1)
    return np.sin(np.pi * phase) ** 2


def rabbit_sound(seed, grazing):
    rng = np.random.default_rng(seed)
    duration = .76 if grazing else .43
    t = np.arange(round(duration * RATE)) / RATE
    # Breath and leaf textures have rounded envelopes and irregular microdetail.
    low = filtered_noise(rng, len(t), 850)
    mid = filtered_noise(rng, len(t), 2600)
    high = filtered_noise(rng, len(t), 5100)
    sound = np.zeros_like(t)
    times = [.055, .285, .525] if grazing else [.025, .19]
    for onset in times:
        onset += rng.uniform(-.01, .012)
        length = rng.uniform(.095, .16) if grazing else rng.uniform(.085, .13)
        envelope = pulse(t, onset, length)
        texture = .60 * mid + .35 * low + .05 * high
        if grazing:
            texture *= .8 + .2 * np.sin(2 * np.pi * rng.uniform(32, 49) * t)
        sound += texture * envelope * rng.uniform(.65, 1)
        # A tiny dry tooth/leaf tick rather than a hard chopping impact.
        for offset in [.018, .04]:
            sound += mid * pulse(t, onset + offset, rng.uniform(.007, .013)) * .24
    sound -= sound.mean()
    sound *= np.minimum(t / .012, 1) * np.minimum((duration - t) / .02, 1)
    sound *= (.32 if grazing else .38) / max(float(np.max(np.abs(sound))), .001)
    return sound


if __name__ == '__main__':
    samples, report = [], []
    for family in ['select', 'graze']:
        for index in range(3):
            sound = rabbit_sound(32100 + index, family == 'graze')
            name = f'rabbit_{family}_{index + 1:02}.wav'
            write(ROOT / 'assets/audio/wildlife' / name, sound)
            samples.extend([sound, np.zeros(round(.5 * RATE))])
            report.append({'file': name, 'seconds': len(sound) / RATE,
                           'peak': round(float(abs(sound).max()), 4),
                           'rms': round(float(np.sqrt(np.mean(sound ** 2))), 4)})
        samples.append(np.zeros(round(.5 * RATE)))
    write(ROOT / 'tmp/rabbit_audio_review/rabbit_sampler.wav', np.concatenate(samples))
    print(json.dumps(report, indent=2))
