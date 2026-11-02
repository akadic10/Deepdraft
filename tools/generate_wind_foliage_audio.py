"""Prepare five recorded wind and foliage ambience loops, offline.

CC0 masters, source credits and edit profiles are in tools/audio_sources/wind_foliage/.
Retains stereo, the original loop lengths and average levels. Requires numpy.
"""
import json
import wave
import numpy as np
from generate_environment_audio import ROOT, RATE, write

SOURCE = ROOT/'tools/audio_sources/wind_foliage'


def sound(kind):
    profile = json.loads((SOURCE/'source.json').read_text(encoding='utf-8'))['banks'][kind]
    assert profile['rate'] == RATE and profile['channels'] == 2
    with wave.open(str(SOURCE/profile['master']), 'rb') as source:
        assert (source.getnchannels(), source.getsampwidth(), source.getframerate()) == (2, 2, RATE)
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype='<i2').reshape(-1, 2).astype(float)/32768
    start, end = profile['region_seconds']
    result = samples[round(start*RATE):round(end*RATE)].copy()
    assert len(result) == round(end*RATE)-round(start*RATE)
    result -= result.mean(axis=0)
    # Reflect padding keeps the filter from connecting unrelated clip endpoints.
    padding = round(RATE*.5)
    padded = np.pad(result, ((padding, padding), (0, 0)), mode='reflect')
    frequencies = np.fft.rfftfreq(len(padded), 1/RATE)
    high_pass = 1/np.sqrt(1+(profile['high_pass_hz']/np.maximum(frequencies, 1e-6))**4)
    low_pass = 1/np.sqrt(1+(frequencies/profile['low_pass_hz'])**8)
    result = np.fft.irfft(np.fft.rfft(padded, axis=0)*(high_pass*low_pass)[:, None],
                         n=len(padded), axis=0)[padding:-padding]
    overlap = round(profile['crossfade_seconds']*RATE)
    length = round(profile['loop_seconds']*RATE)
    assert len(result) == length+overlap and length > overlap
    angle = np.linspace(0, np.pi/2, overlap)[:, None]
    loop = result[overlap:].copy()
    # The join wraps to adjacent samples in the original recording, not silence.
    loop[-overlap:] = result[-overlap:]*np.cos(angle)+result[:overlap]*np.sin(angle)
    loop -= loop.mean(axis=0)
    loop *= min(profile['target_rms']/max(float(np.sqrt(np.mean(loop**2))), 1e-8),
                profile['peak_ceiling']/max(float(abs(loop).max()), 1e-8))
    assert np.isfinite(loop).all() and abs(loop).max() < 1
    return loop


if __name__ == '__main__':
    for kind in ['wind', 'foliage', 'shelter', 'dry_leaves', 'winter_wind']:
        samples = sound(kind)
        write(kind, samples, True)
        print(kind, 'seconds', len(samples)/RATE, 'peak', round(float(abs(samples).max()), 3))
