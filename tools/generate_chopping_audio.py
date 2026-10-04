"""Original procedural wood impacts. Reproducible mono PCM; no external samples.

Run with Python + numpy. Outputs shipping WAVs and a spaced listening sampler.
"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RATE = 48000


def filtered_noise(rng, count, cutoff):
    noise = rng.normal(0, 1, count)
    spectrum = np.fft.rfft(noise)
    frequencies = np.fft.rfftfreq(count, 1 / RATE)
    spectrum *= 1 / np.sqrt(1 + (frequencies / cutoff) ** 6)
    output = np.fft.irfft(spectrum, n=count)
    return output / max(np.std(output), .001)


def impact(seed, finish=False):
    rng = np.random.default_rng(seed)
    duration = .68 if finish else .29
    t = np.arange(round(duration * RATE)) / RATE
    attack = 1 - np.exp(-t / .0007)
    wood = np.zeros_like(t)
    # Short, inharmonic resonances avoid a pitched bell or synthetic beep.
    for frequency, strength, decay in [(168, .9, .036), (327, .65, .025),
                                      (541, .35, .018), (913, .15, .013)]:
        frequency *= rng.uniform(.9, 1.12) * (.83 if finish else 1)
        wood += strength * np.sin(2 * np.pi * frequency * t) * np.exp(-t / decay)
    snap = filtered_noise(rng, len(t), 5800) * np.exp(-t / .006) * .72
    body = filtered_noise(rng, len(t), 1450) * np.exp(-t / .034) * .33
    splinters = np.zeros_like(t)
    for delay in rng.uniform(.015, .09 if not finish else .24, 8 if finish else 4):
        shifted = np.maximum(t - delay, 0)
        envelope = (t >= delay) * (1 - np.exp(-shifted / .001)) * np.exp(-shifted / .008)
        splinters += filtered_noise(rng, len(t), 3600) * envelope * rng.uniform(.04, .12)
    sound = (wood + snap + body + splinters) * attack
    if finish:
        # A soft debris/rustle tail, not a long falling-tree crash.
        sound += filtered_noise(rng, len(t), 2100) * .22 * (1 - np.exp(-t / .035)) * np.exp(-t / .14)
    sound -= sound.mean()
    sound *= np.minimum(t / .0005, 1) * np.minimum((duration - t) / .015, 1)
    sound *= .70 / max(np.max(np.abs(sound)), .001)
    return sound


def write(path, sound):
    path.parent.mkdir(parents=True, exist_ok=True)
    assert np.isfinite(sound).all() and np.max(np.abs(sound)) < 1
    with wave.open(str(path), "wb") as out:
        out.setparams((1, 2, RATE, len(sound), "NONE", "not compressed"))
        out.writeframes(np.round(sound * 32767).astype("<i2").tobytes())


if __name__ == "__main__":
    directory = ROOT / "assets/audio/work"
    samples = []
    report = []
    for index in range(6):
        sound = impact(8700 + index)
        name = f"axe_chop_{index + 1:02}.wav"
        write(directory / name, sound)
        samples.extend([sound, np.zeros(round(.48 * RATE))])
        report.append({"file": name, "peak": round(float(abs(sound).max()), 4),
                       "rms": round(float(np.sqrt(np.mean(sound ** 2))), 4)})
    finish = impact(9801, finish=True)
    write(directory / "tree_felled.wav", finish)
    samples.extend([np.zeros(round(.4 * RATE)), finish])
    write(ROOT / "tmp/chopping_feedback_review/chopping_sampler.wav", np.concatenate(samples))
    print(json.dumps(report))
