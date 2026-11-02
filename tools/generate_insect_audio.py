"""Prepare recorded cricket/cicada loops and cricket chirps, offline.

CC0 masters and edit profiles live in tools/audio_sources/insects/.
Loops retain stereo and their original lengths; chirps remain mono. Requires numpy.
"""
import json
import wave
import numpy as np
from generate_environment_audio import ROOT, RATE, write

SOURCE = ROOT/'tools/audio_sources/insects'


def sound(kind, index=0):
    profile = json.loads((SOURCE/'source.json').read_text(encoding='utf-8'))['banks'][kind]
    channels = profile['channels']
    assert profile['rate'] == RATE
    with wave.open(str(SOURCE/profile['master']), 'rb') as source:
        assert (source.getnchannels(), source.getsampwidth(), source.getframerate()) == (channels, 2, RATE)
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype='<i2').reshape(-1, channels).astype(float)/32768
    start, end = profile['regions_seconds'][index]
    result = samples[round(start*RATE):round(end*RATE)].copy()
    assert len(result) == round(end*RATE)-round(start*RATE)
    result -= result.mean(axis=0)
    padding = round(RATE*.15)
    padded = np.pad(result, ((padding, padding), (0, 0)), mode='reflect')
    frequencies = np.fft.rfftfreq(len(padded), 1/RATE)
    high_pass = 1/np.sqrt(1+(profile['high_pass_hz']/np.maximum(frequencies, 1e-6))**4)
    low_pass = 1/np.sqrt(1+(frequencies/profile['low_pass_hz'])**8)
    result = np.fft.irfft(np.fft.rfft(padded, axis=0)*(high_pass*low_pass)[:, None],
                         n=len(padded), axis=0)[padding:-padding]
    if profile['loop']:
        overlap = round(profile['crossfade_seconds']*RATE)
        length = round(profile['loop_seconds']*RATE)
        assert len(result) == length+overlap and length > overlap
        # Blend the tail into the discarded head. On wrapping, the last and first
        # samples are adjacent samples from that head, with no fade to silence.
        angle = np.linspace(0, np.pi/2, overlap)[:, None]
        loop = result[overlap:].copy()
        loop[-overlap:] = result[-overlap:]*np.cos(angle)+result[:overlap]*np.sin(angle)
        result = loop
    else:
        fade_in, fade_out = [round(seconds*RATE) for seconds in profile['fades_seconds']]
        result[:fade_in] *= np.linspace(0, 1, fade_in)[:, None]
        result[-fade_out:] *= np.linspace(1, 0, fade_out)[:, None]
    result -= result.mean(axis=0)
    rms = np.sqrt(np.mean(result**2))
    result *= min(profile['target_rms']/max(float(rms), 1e-8),
                  profile['peak_ceiling']/max(float(abs(result).max()), 1e-8))
    assert np.isfinite(result).all() and abs(result).max() < 1
    return result[:, 0] if channels == 1 else result


if __name__ == '__main__':
    for kind in ['crickets', 'day_insects']:
        samples = sound(kind)
        write(kind, samples, True)
        print(kind, 'seconds', len(samples)/RATE, 'peak', round(float(abs(samples).max()), 3))
    for index in range(3):
        samples = sound('chirp', index)
        write(f'chirp_{index+1:02}', samples)
        print('chirp', index+1, 'seconds', round(len(samples)/RATE, 2),
              'peak', round(float(abs(samples).max()), 3))
