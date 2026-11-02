"""Prepare tree creaks from three CC0 field recordings, reproducibly and offline.

Source masters, licensing and edit profiles are in tools/audio_sources/wood_creaks/.
Outputs retain the environmental bank's mono 22.05 kHz PCM format. Requires numpy.
"""
import json
import wave
import numpy as np
from generate_environment_audio import ROOT, RATE, write

SOURCE = ROOT/'tools/audio_sources/wood_creaks'


def sound(index):
    profile = json.loads((SOURCE/'source.json').read_text(encoding='utf-8'))['clips'][index]
    with wave.open(str(SOURCE/profile['master']), 'rb') as source:
        assert (source.getnchannels(), source.getsampwidth(), source.getframerate()) == (1, 2, RATE)
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype='<i2').astype(float)/32768
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
    samples *= min(profile['target_rms']/np.sqrt(np.mean(samples**2)),
                   profile['peak_ceiling']/abs(samples).max())
    assert np.isfinite(samples).all() and abs(samples).max() < .28
    return samples


if __name__ == '__main__':
    for index in range(3):
        write(f'creak_{index+1:02}', sound(index))
