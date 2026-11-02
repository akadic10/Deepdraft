"""Prepare rabbit cues from a CC0 recording, reproducibly and without a network.

Selection uses short real rabbit nibble fragments; grazing uses longer chewing
phrases. See tools/audio_sources/rabbit/source.json for licensing and edit regions.
The source master is mono PCM at the existing 48 kHz rate. Requires numpy.
"""
import json
import wave
import numpy as np
from generate_chopping_audio import ROOT, RATE, write

SOURCE = ROOT/'tools/audio_sources/rabbit'


def rabbit_sound(kind, index):
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
    samples, report = [], []
    for family in ['select', 'graze']:
        for index in range(3):
            sound = rabbit_sound(family, index)
            name = f'rabbit_{family}_{index + 1:02}.wav'
            write(ROOT / 'assets/audio/wildlife' / name, sound)
            samples.extend([sound, np.zeros(round(.5 * RATE))])
            report.append({'file': name, 'seconds': len(sound) / RATE,
                           'peak': round(float(abs(sound).max()), 4),
                           'rms': round(float(np.sqrt(np.mean(sound ** 2))), 4)})
        samples.append(np.zeros(round(.5 * RATE)))
    write(ROOT / 'tmp/rabbit_audio_review/rabbit_sampler.wav', np.concatenate(samples))
    print(json.dumps(report, indent=2))
