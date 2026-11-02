"""Prepare recorded blackbird and owl phrases, reproducibly and offline.

CC0 source masters, licensing and edit regions are in tools/audio_sources/birds_owls/.
Outputs retain the environmental bank's mono 22.05 kHz PCM format. Requires numpy.
"""
import json
import wave
import numpy as np
from generate_environment_audio import ROOT, RATE, write

SOURCE = ROOT/'tools/audio_sources/birds_owls'


def sound(kind, index):
    profile = json.loads((SOURCE/'source.json').read_text(encoding='utf-8'))['banks'][kind]
    assert profile['rate'] == RATE
    with wave.open(str(SOURCE/profile['master']), 'rb') as source:
        assert (source.getnchannels(), source.getsampwidth(), source.getframerate()) == (1, 2, RATE)
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype='<i2').astype(float)/32768
    start, end = profile['regions_seconds'][index]
    result = samples[round(start*RATE):round(end*RATE)].copy()
    assert len(result) == round(end*RATE)-round(start*RATE)
    result -= result.mean()
    padding = round(RATE*.15)
    padded = np.pad(result, padding, mode='reflect')
    frequencies = np.fft.rfftfreq(len(padded), 1/RATE)
    high_pass = 1/np.sqrt(1+(profile['high_pass_hz']/np.maximum(frequencies, 1e-6))**4)
    low_pass = 1/np.sqrt(1+(frequencies/profile['low_pass_hz'])**8)
    result = np.fft.irfft(np.fft.rfft(padded)*high_pass*low_pass, n=len(padded))[padding:-padding]
    result -= result.mean()
    fade_in, fade_out = [round(seconds*RATE) for seconds in profile['fades_seconds']]
    result[:fade_in] *= np.linspace(0, 1, fade_in)
    result[-fade_out:] *= np.linspace(1, 0, fade_out)
    rms = np.sqrt(np.mean(result**2))
    result *= min(profile['target_rms']/max(float(rms), 1e-8),
                  profile['peak_ceiling']/max(float(abs(result).max()), 1e-8))
    assert np.isfinite(result).all() and abs(result).max() < 1
    return result


if __name__ == '__main__':
    for kind, count in [('bird', 6), ('owl', 3)]:
        for index in range(count):
            samples = sound(kind, index)
            write(f'{kind}_{index+1:02}', samples)
            print(kind, index+1, 'seconds', round(len(samples)/RATE, 2),
                  'peak', round(float(abs(samples).max()), 3))
