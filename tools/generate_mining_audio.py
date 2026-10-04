"""Original procedural pick impacts; no external recordings or samples.

Six short stone strikes followed by six softer earth strikes in the sampler.
Run with Python + numpy; seeded synthesis makes shipping WAVs reproducible.
"""
import json
import numpy as np
from generate_chopping_audio import ROOT, RATE, filtered_noise, write


def impact(seed, soil=False):
    rng = np.random.default_rng(seed)
    duration = .28 if soil else .34
    t = np.arange(round(duration * RATE)) / RATE
    if soil:
        sound = filtered_noise(rng, len(t), 850) * np.exp(-t / .024) * .7
        sound += np.sin(2 * np.pi * rng.uniform(110, 145) * t) * np.exp(-t / .018) * .5
        sound += filtered_noise(rng, len(t), 3000) * (1 - np.exp(-t / .003)) * np.exp(-t / .055) * .19
    else:
        # Brief, inharmonic steel resonances over a hard stone crack.
        sound = filtered_noise(rng, len(t), 9200) * np.exp(-t / .004) * .85
        sound += filtered_noise(rng, len(t), 2500) * np.exp(-t / .018) * .35
        for frequency, strength, decay in [(1370, .38, .031), (2680, .23, .022), (4190, .13, .014)]:
            sound += np.sin(2 * np.pi * frequency * rng.uniform(.94, 1.06) * t) * np.exp(-t / decay) * strength
    # Small granular ticks and a scraping tail make the contact less sterile.
    for delay in rng.uniform(.016, .12, 7):
        shifted = np.maximum(t - delay, 0)
        envelope = (t >= delay) * (1 - np.exp(-shifted / .0006)) * np.exp(-shifted / .008)
        sound += filtered_noise(rng, len(t), 2300 if soil else 5800) * envelope * rng.uniform(.025, .09)
    sound -= sound.mean()
    sound *= np.minimum(t / .0004, 1) * np.minimum((duration - t) / .02, 1)
    sound *= (.42 if soil else .70) / max(np.max(np.abs(sound)), .001)
    return sound


if __name__ == "__main__":
    samples, report = [], []
    for family in ["stone", "soil"]:
        for index in range(6):
            sound = impact(14500 + index, soil=family == "soil")
            name = f"pick_{family}_{index + 1:02}.wav"
            write(ROOT / "assets/audio/work" / name, sound)
            samples.extend([sound, np.zeros(round(.35 * RATE))])
            report.append({"file": name, "peak": round(float(abs(sound).max()), 4)})
        samples.append(np.zeros(round(.6 * RATE)))
    write(ROOT / "tmp/mining_feedback_review/mining_sampler.wav", np.concatenate(samples))
    print(json.dumps(report))
