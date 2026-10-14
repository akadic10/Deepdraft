"""Original woodland ambience, synthesized without external recordings.

Periodic filtered noise makes seamless stereo air/rustle beds. Insect pulses
and breathy frequency-modulated bird phrases are seeded cosmetic audio only.
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


def noise(rng, n, low, high):
    f = np.fft.rfftfreq(n, 1 / RATE)
    spectrum = rng.normal(size=len(f)) + 1j * rng.normal(size=len(f))
    curve = (f / (f + low)) ** 2 / (1 + (f / high) ** 3)
    values = np.fft.irfft(spectrum * curve, n=n)
    return values / max(np.std(values), 1e-8)


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
    rng = np.random.default_rng(seed)
    n = RATE * seconds
    t = np.arange(n) / RATE
    channels = []
    for channel in range(2):
        # Integer periods retain continuity at the seam, with different motion
        # on each channel so wind does not sit in the centre of the speakers.
        swell = .66 + .20 * np.sin(2 * np.pi * t / seconds * 2 + channel * .8)
        swell += .11 * np.sin(2 * np.pi * t / seconds * 7 + 1.2 + channel)
        if kind == "wind":
            x = noise(rng, n, 85, 650) * swell * .095
        elif kind == "foliage":
            x = noise(rng, n, 550, 3400) * swell ** 2 * .09
            x *= .86 + .14 * np.sin(2 * np.pi * t / seconds * 43 + channel)
        elif kind == "shelter":
            x = noise(rng, n, 95, 360) * swell * .045
        else:
            x = np.zeros(n)
            # Several softly pulsed insects at separate pitches and rhythms.
            # Carrier and modulation cycles all wrap exactly over the loop.
            for voice in range(3):
                hz = round((3400 + voice * 470 + channel * 65) * seconds) / seconds
                pulse = np.maximum(0, np.sin(2 * np.pi * t * (round((17 + voice * 2.1) * seconds) / seconds))) ** 5
                phrase = np.maximum(0, np.sin(2 * np.pi * t / seconds * (13 + voice * 5) + voice + channel)) ** 2
                x += np.sin(2 * np.pi * hz * t + .5 * np.sin(2 * np.pi * t / seconds * 21)) * pulse * phrase * .12
            x += noise(rng, n, 2000, 5000) * .006
        channels.append(x)
    write(kind, np.stack(channels, axis=1), True)


def bird(index):
    rng = np.random.default_rng(5830 + index)
    result = np.zeros(RATE * 4)
    cursor = rng.uniform(.12, .3)
    for syllable in range(int(rng.integers(4, 8))):
        duration = rng.uniform(.065, .22)
        t = np.arange(int(duration * RATE)) / RATE
        u = t / duration
        base = rng.uniform(2100, 3700)
        sweep = rng.uniform(-1400, 1600)
        hz = base + sweep * u + rng.uniform(70, 210) * np.sin(2 * np.pi * rng.uniform(12, 27) * t)
        phase = 2 * np.pi * np.cumsum(hz) / RATE
        env = np.sin(np.pi * u) ** 1.5
        tone = np.sin(phase) + .08 * np.sin(phase * 2 + .3)
        breath = noise(rng, len(t), 1500, 5000)
        note = (tone * .28 + breath * .012) * env
        start = int(cursor * RATE)
        result[start:start + len(note)] += note
        cursor += duration + rng.uniform(.075, .22)
    write(f"bird_{index:02}", result[:int((cursor + .3) * RATE)])


def owl(index):
    rng = np.random.default_rng(6770 + index)
    result = np.zeros(RATE * 4)
    for start, duration, strength in [(0.25, .23, .7), (.75, .73, 1), (2.0, .44, .6)]:
        t = np.arange(int(RATE * duration)) / RATE
        u = t / duration
        hz = (410 + index * 35) - 65 * u + 9 * np.sin(2 * np.pi * 9 * t)
        phase = np.cumsum(hz) * 2 * np.pi / RATE
        note = (np.sin(phase) + .18 * np.sin(phase * 2)) * np.sin(np.pi * u) ** 1.1
        note += noise(rng, len(t), 220, 800) * .055 * np.sin(np.pi * u) ** 2
        offset = int(start * RATE)
        result[offset:offset + len(note)] += note * .22 * strength
    write(f"owl_{index:02}", result)


if __name__ == "__main__":
    for args in [("wind", 31, 1781), ("foliage", 29, 2462), ("crickets", 37, 3843), ("shelter", 23, 9271)]:
        bed(*args)
    for i in range(1, 7): bird(i)
    for i in range(1, 4): owl(i)
    print(json.dumps(REPORT, indent=2))
