"""Original quiet duck calls and small water splashes; deterministic synthesis."""
import numpy as np
from generate_chopping_audio import ROOT, RATE, filtered_noise, write
from generate_rabbit_audio import pulse


def sound(seed, splash=False):
    rng = np.random.default_rng(seed)
    duration = .48 if splash else .75
    t = np.arange(round(duration * RATE)) / RATE
    noise = filtered_noise(rng, len(t), 2800)
    result = np.zeros_like(t)
    if splash:
        result = noise * pulse(t, .01, .43)
        for onset in [.045, .13, .24]:
            result += np.sin(2*np.pi*(700*t-350*t*t)) * pulse(t, onset, .075) * .15
    else:
        # Breath-driven, descending nasal pulses, softened before playback.
        for onset, length in [(.025, .24), (.36, .18)]:
            local = np.maximum(0, t-onset)
            base = rng.uniform(250, 295)
            phase = 2*np.pi*(base*local-95*local*local)
            tone = np.sin(phase)+.42*np.sin(3*phase)+.22*np.sin(5*phase)
            result += (tone*.24 + noise*.24) * pulse(t, onset, length)
    result -= result.mean()
    result *= np.minimum(t/.012, 1)*np.minimum((duration-t)/.03, 1)
    result *= .32/max(float(abs(result).max()), .001)
    return result


if __name__ == '__main__':
    sampler = []
    for family in ['quack', 'splash']:
        for i in range(3):
            pcm = sound(84050+i, family == 'splash')
            write(ROOT/'assets/audio/wildlife'/f'duck_{family}_{i+1:02}.wav', pcm)
            sampler.extend([pcm, np.zeros(RATE//2)])
            assert np.isfinite(pcm).all() and abs(pcm).max() < .4
    write(ROOT/'tmp/duck_review/duck_sampler.wav', np.concatenate(sampler))
    print('Duck audio: 6 original mono PCM clips; peak <= 0.32')
