"""Recorded stone-pick impacts and shovel-to-soil mining foley.

Six short stone strikes followed by six softer earth strikes in the sampler.
Run with Python + numpy; saved CC0 masters and profiles make WAVs reproducible.
"""
import json
import numpy as np
from generate_chopping_audio import ROOT, RATE, write
from generate_chopping_mining_audio import sound as recorded_sound


if __name__ == "__main__":
    samples, report = [], []
    for family in ["stone", "soil"]:
        for index in range(6):
            sound = recorded_sound(f'pick_{family}_{index + 1:02}')
            name = f"pick_{family}_{index + 1:02}.wav"
            write(ROOT / "assets/audio/work" / name, sound)
            samples.extend([sound, np.zeros(round(.35 * RATE))])
            report.append({"file": name, "peak": round(float(abs(sound).max()), 4)})
        samples.append(np.zeros(round(.6 * RATE)))
    write(ROOT / "tmp/mining_feedback_review/mining_sampler.wav", np.concatenate(samples))
    print(json.dumps(report))
