"""Woodland ambience prepared from recorded wildlife, wind and foliage.

Wind, foliage, sheltered air, crickets, birds and owls use credited CC0 recordings.
The details generator shares this writer for its recorded contextual sounds.
Run with the bundled Python (numpy); production loads the resulting WAVs.
"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio/ambience/environment"
RATE = 22050
REPORT = []


def write(name, samples, loop=False):
    samples -= np.mean(samples, axis=0)
    samples *= min(1, .68 / max(np.max(np.abs(samples)), 1e-8))
    if not loop:
        fade = min(220, len(samples) // 4)
        samples[:fade] *= np.linspace(0, 1, fade)
        samples[-fade:] *= np.linspace(1, 0, fade)
    pcm = (samples * 32767).astype("<i2")
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / (name + ".wav")), "wb") as writer:
        writer.setparams((1 if samples.ndim == 1 else 2, 2, RATE, len(samples), "NONE", "not compressed"))
        writer.writeframes(pcm.tobytes())
    rms = float(np.sqrt(np.mean(samples ** 2)))
    peak = float(np.max(np.abs(samples)))
    seam = float(np.max(np.abs(samples[0] - samples[-1])))
    difference = float(np.sqrt(np.mean(np.diff(samples, axis=0) ** 2)))
    assert .004 < rms < .25 and peak < .7, (name, rms, peak)
    if loop:
        assert seam < difference * 6, (name, seam, difference)
    REPORT.append(dict(name=name, seconds=len(samples) / RATE, rms=rms, peak=peak, seam=seam, loop=loop))


def bed(kind, seconds, seed):
    if kind == "crickets":
        from generate_insect_audio import sound
        write(kind, sound(kind), True)
        return
    if kind in ["wind", "foliage", "shelter"]:
        from generate_wind_foliage_audio import sound
        write(kind, sound(kind), True)
        return
    raise ValueError(f"Unknown environmental bed: {kind}")


def bird(index):
    from generate_bird_audio import sound
    write(f"bird_{index:02}", sound('bird', index-1))


def owl(index):
    from generate_bird_audio import sound
    write(f"owl_{index:02}", sound('owl', index-1))


if __name__ == "__main__":
    for args in [("wind", 31, 1781), ("foliage", 29, 2462), ("crickets", 37, 3843), ("shelter", 23, 9271)]:
        bed(*args)
    for i in range(1, 7): bird(i)
    for i in range(1, 4): owl(i)
    print(json.dumps(REPORT, indent=2))
