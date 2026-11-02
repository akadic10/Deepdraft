"""Prepare recorded campfire/hearth and torch ambience from local CC0 masters.

Torch uses a quieter wood-fire passage as foley. Source credits and edit profiles
are in tools/audio_sources/fire/. Requires numpy; rebuilding works offline.
"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'tools/audio_sources/fire'
RATE = 22050


def sound(kind):
    profile = json.loads((SOURCE/'source.json').read_text(encoding='utf-8'))['banks'][kind]
    with wave.open(str(SOURCE/profile['master']), 'rb') as source:
        assert (source.getnchannels(), source.getsampwidth(), source.getframerate()) == (1, 2, RATE)
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype='<i2').astype(float)/32768
    start, end = profile['region_seconds']
    result = samples[round(start*RATE):round(end*RATE)].copy()
    assert len(result) == round(end*RATE)-round(start*RATE)
    result -= result.mean()
    padding = round(RATE*.5)
    padded = np.pad(result, padding, mode='reflect')
    frequencies = np.fft.rfftfreq(len(padded), 1/RATE)
    high_pass = 1/np.sqrt(1+(profile['high_pass_hz']/np.maximum(frequencies, 1e-6))**4)
    low_pass = 1/np.sqrt(1+(frequencies/profile['low_pass_hz'])**8)
    result = np.fft.irfft(np.fft.rfft(padded)*high_pass*low_pass, n=len(padded))[padding:-padding]
    if 'soft_peak_rms' in profile:
        # Control close-mic wood pops so they do not force the flame bed too quiet.
        threshold = profile['soft_peak_rms']*np.sqrt(np.mean(result**2))
        result = threshold*np.tanh(result/threshold)
    overlap = round(profile['crossfade_seconds']*RATE)
    length = round(profile['loop_seconds']*RATE)
    assert len(result) == length+overlap and length > overlap
    angle = np.linspace(0, np.pi/2, overlap)
    loop = result[overlap:].copy()
    # The wrap returns to adjacent source samples without a fade to silence.
    loop[-overlap:] = result[-overlap:]*np.cos(angle)+result[:overlap]*np.sin(angle)
    loop -= loop.mean()
    loop *= min(profile['target_rms']/max(float(np.sqrt(np.mean(loop**2))), 1e-8),
                profile['peak_ceiling']/max(float(abs(loop).max()), 1e-8))
    assert np.isfinite(loop).all() and abs(loop).max() < 1
    return loop


def write_sound(kind):
    samples = sound(kind)
    rms = np.sqrt(np.mean(samples**2))
    seam = abs(samples[0]-samples[-1])
    difference = np.sqrt(np.mean(np.diff(samples)**2))
    assert .04 < rms < .25 and seam < difference*5
    path = ROOT/f'assets/audio/ambience/{kind}.wav'
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), 'wb') as writer:
        writer.setparams((1, 2, RATE, len(samples), 'NONE', 'not compressed'))
        writer.writeframes(np.round(samples*32767).astype('<i2').tobytes())
    print(f'{kind}: {len(samples)/RATE:g}s mono; RMS={rms:.4f}; peak={max(abs(samples)):.4f}; seam={seam:.4f}')


if __name__ == '__main__':
    for kind in ('campfire', 'torch'): write_sound(kind)
