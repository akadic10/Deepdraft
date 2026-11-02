"""Rebuild the promotion cue from the checked-in CC0 glockenspiel recording.

Requires NumPy. See tools/audio_sources/promotion for provenance and edit settings.
"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tools/audio_sources/promotion'
RATE = 44100


def sound(profile):
    with wave.open(str(SOURCE / profile['master']), 'rb') as wav:
        assert (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) == (1, 2, RATE)
        samples = np.frombuffer(wav.readframes(wav.getnframes()), dtype='<i2').astype(float) / 32768
    start_seconds, end_seconds = profile['region_seconds']
    start = round(start_seconds * RATE)
    end = start + round((end_seconds - start_seconds) * RATE)
    assert 0 <= start < end <= len(samples)
    samples = samples[start:end].copy()
    samples -= np.mean(samples)
    padding = round(RATE * .1)
    padded = np.pad(samples, padding, mode='reflect')
    frequencies = np.fft.rfftfreq(len(padded), 1 / RATE)
    high_pass = 1 / np.sqrt(1 + (profile['high_pass_hz'] / np.maximum(frequencies, 1e-6)) ** 4)
    low_pass = 1 / np.sqrt(1 + (frequencies / profile['low_pass_hz']) ** 8)
    samples = np.fft.irfft(np.fft.rfft(padded) * high_pass * low_pass, n=len(padded))[padding:-padding]
    samples -= np.mean(samples)
    attack = round(profile['fade_in_seconds'] * RATE)
    release = round(profile['fade_out_seconds'] * RATE)
    samples[:attack] *= np.sin(np.linspace(0, np.pi / 2, attack)) ** 2
    samples[-release:] *= np.cos(np.linspace(0, np.pi / 2, release)) ** 2
    rms = np.sqrt(np.mean(samples * samples))
    peak = np.max(np.abs(samples))
    assert rms > 0 and peak > 0
    samples *= min(profile['target_rms'] / rms, profile['peak_ceiling'] / peak)
    assert np.all(np.isfinite(samples)) and np.max(np.abs(samples)) <= .52
    return samples


if __name__ == '__main__':
    profile = json.loads((SOURCE / 'source.json').read_text())['clip']
    samples = sound(profile)
    output = ROOT / profile['output']
    output.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(output), 'wb') as wav:
        wav.setparams((1, 2, RATE, len(samples), 'NONE', 'not compressed'))
        wav.writeframes(np.round(samples * 32767).astype('<i2').tobytes())
    print(f'Generated {output}: {len(samples) / RATE:.2f}s, RMS {np.sqrt(np.mean(samples * samples)):.4f}, peak {np.max(np.abs(samples)):.4f}')
