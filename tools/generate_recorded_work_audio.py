"""Prepare recorded work cues, reproducibly and offline.

The default bank is audio_sources/hammer_tree/; other banks supply their directory.
Requires numpy. Outputs retain the work bank's mono 48 kHz PCM16 format.
"""
import json
import wave
import numpy as np
from generate_chopping_audio import ROOT, RATE, write

SOURCE = ROOT/'tools/audio_sources/hammer_tree'


def sound(kind, source_directory=SOURCE):
    profile = json.loads((source_directory/'source.json').read_text(encoding='utf-8'))['clips'][kind]
    with wave.open(str(source_directory/profile['master']), 'rb') as source:
        assert (source.getnchannels(), source.getsampwidth(), source.getframerate()) == (1, 2, RATE)
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype='<i2').astype(float)/32768
    start, end = [round(t*RATE) for t in profile['region_seconds']]
    samples = samples[start:end].copy()
    assert len(samples) == end-start
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
    assert np.isfinite(samples).all() and abs(samples).max() <= .7
    return samples


if __name__ == '__main__':
    for kind, profile in json.loads((SOURCE/'source.json').read_text(encoding='utf-8'))['clips'].items():
        samples = sound(kind)
        write(ROOT/profile['output'], samples)
        print(f'{kind}: {len(samples)/RATE:.3f}s, RMS={np.sqrt(np.mean(samples**2)):.4f}, peak={abs(samples).max():.4f}')
