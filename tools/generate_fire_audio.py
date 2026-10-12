"""Original, seamless fire ambience. Private seeded synthesis; no source samples.

Periodic colored noise supplies the low flame bed; wrapped, damped noise bursts
provide small wood crackles. Torch is lighter and smoother than the campfire.
"""
from pathlib import Path
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RATE, SECONDS = 22050, 12


def synth(kind):
    rng = np.random.default_rng(7719 if kind == "campfire" else 8211)
    count = RATE * SECONDS
    frequencies = np.fft.rfftfreq(count, 1 / RATE)
    # Avoid an overpowering wind/hiss bed; rolling fire stays warm and close.
    spectrum = rng.normal(size=len(frequencies)) + 1j*rng.normal(size=len(frequencies))
    curve = (frequencies / (frequencies + 110)) / (1 + (frequencies / 1100)**2)
    bed = np.fft.irfft(spectrum * curve, n=count)
    bed /= np.std(bed)
    t = np.arange(count) / RATE
    envelope = .78 + .12*np.sin(2*np.pi*t/SECONDS*3) + .1*np.sin(2*np.pi*t/SECONDS*7+.8)
    samples = bed * envelope * (.13 if kind == "campfire" else .105)
    for _ in range(95 if kind == "campfire" else 42):
        length = int(RATE * rng.uniform(.009, .095))
        noise = rng.normal(size=length)
        noise = np.convolve(noise, [.2,.6,.2], mode="same")
        shape = np.exp(-np.arange(length)/(length*.19))
        shape *= np.minimum(1, np.arange(length)/max(4,length*.018))
        burst = noise * shape * rng.uniform(.14,.42)
        start = int(rng.integers(count))
        samples[(start + np.arange(length)) % count] += burst
    samples -= np.mean(samples)
    samples *= min(1, .68/np.max(np.abs(samples)))
    pcm = (samples * 32767).astype("<i2")
    path = ROOT / f"assets/audio/ambience/{kind}.wav"
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as writer:
        writer.setparams((1, 2, RATE, count, "NONE", "not compressed"))
        writer.writeframes(pcm.tobytes())
    rms = np.sqrt(np.mean(samples**2))
    seam = abs(samples[0]-samples[-1])
    difference = np.sqrt(np.mean(np.diff(samples)**2))
    assert .04 < rms < .25 and seam < difference*5
    print(f"{kind}: {SECONDS}s mono; RMS={rms:.4f}; peak={max(abs(samples)):.4f}; seam={seam:.4f}")


if __name__ == "__main__":
    for name in ("campfire", "torch"): synth(name)
