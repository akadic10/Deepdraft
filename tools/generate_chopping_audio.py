"""Recorded axe impacts, tree-felling completion and the shared work PCM writer.

Run with Python + numpy. Outputs shipping WAVs and a spaced listening sampler.
"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RATE = 48000


def write(path, sound):
    path.parent.mkdir(parents=True, exist_ok=True)
    assert np.isfinite(sound).all() and np.max(np.abs(sound)) < 1
    with wave.open(str(path), "wb") as out:
        out.setparams((1, 2, RATE, len(sound), "NONE", "not compressed"))
        out.writeframes(np.round(sound * 32767).astype("<i2").tobytes())


if __name__ == "__main__":
    from generate_chopping_mining_audio import sound as recorded_impact
    from generate_recorded_work_audio import sound as recorded_detail
    directory = ROOT / "assets/audio/work"
    samples = []
    report = []
    for index in range(6):
        sound = recorded_impact(f'axe_chop_{index + 1:02}')
        name = f"axe_chop_{index + 1:02}.wav"
        write(directory / name, sound)
        samples.extend([sound, np.zeros(round(.48 * RATE))])
        report.append({"file": name, "peak": round(float(abs(sound).max()), 4),
                       "rms": round(float(np.sqrt(np.mean(sound ** 2))), 4)})
    finish = recorded_detail('tree_felled')
    write(directory / "tree_felled.wav", finish)
    samples.extend([np.zeros(round(.4 * RATE)), finish])
    write(ROOT / "tmp/chopping_feedback_review/chopping_sampler.wav", np.concatenate(samples))
    print(json.dumps(report))
