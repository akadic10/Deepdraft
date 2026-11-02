"""Prepare quiet recorded dwarf snores from local CC0 sleeping-person recordings.

Source credits and reproducible edit profiles live in tools/audio_sources/snoring/.
Requires numpy; rebuilding works offline and retains natural speed and pitch.
"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'tools/audio_sources/snoring'
RATE = 24000


def sound(profile):
    with wave.open(str(SOURCE/profile['master']), 'rb') as reader:
        assert (reader.getnchannels(), reader.getsampwidth(), reader.getframerate()) == (1, 2, RATE)
        source = np.frombuffer(reader.readframes(reader.getnframes()), dtype='<i2').astype(float)/32768
    start, end = profile['region_seconds']
    samples = source[round(start*RATE):round(end*RATE)].copy()
    assert len(samples) == round(end*RATE)-round(start*RATE)
    samples -= samples.mean()
    padding = round(RATE*.1)
    padded = np.pad(samples, padding, mode='reflect')
    frequencies = np.fft.rfftfreq(len(padded), 1/RATE)
    high_pass = 1/np.sqrt(1+(profile['high_pass_hz']/np.maximum(frequencies, 1e-6))**4)
    low_pass = 1/np.sqrt(1+(frequencies/profile['low_pass_hz'])**8)
    samples = np.fft.irfft(np.fft.rfft(padded)*high_pass*low_pass, n=len(padded))[padding:-padding]
    samples -= samples.mean()
    attack = round(profile['fade_in_seconds']*RATE)
    release = round(profile['fade_out_seconds']*RATE)
    samples[:attack] *= np.sin(np.linspace(0, np.pi/2, attack))**2
    samples[-release:] *= np.cos(np.linspace(0, np.pi/2, release))**2
    samples = np.pad(samples, (round(profile['leading_silence_seconds']*RATE),
                               round(profile['trailing_silence_seconds']*RATE)))
    samples *= min(profile['target_rms']/np.sqrt(np.mean(samples**2)),
                   profile['peak_ceiling']/abs(samples).max())
    assert np.isfinite(samples).all() and abs(samples).max() < .382
    assert 2 < len(samples)/RATE < 3 and abs(samples[0]) < 1e-6 and abs(samples[-1]) < 1e-6
    return samples


def write_sound(profile):
    samples = sound(profile)
    path = ROOT/profile['output']
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), 'wb') as writer:
        writer.setparams((1, 2, RATE, len(samples), 'NONE', 'not compressed'))
        writer.writeframes(np.round(samples*32767).astype('<i2').tobytes())
    print(f'{path.name}: {len(samples)/RATE:.2f}s; RMS={np.sqrt(np.mean(samples**2)):.4f}; peak={abs(samples).max():.4f}')


if __name__ == '__main__':
    for profile in json.loads((SOURCE/'source.json').read_text(encoding='utf-8'))['clips']:
        write_sound(profile)
