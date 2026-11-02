"""Prepare wolf cues from CC0 recordings, reproducibly and without a network.

Howls are actual wolves. Selection and eating use recorded dog foley; see
tools/audio_sources/wolf/source.json for species, licensing and edit regions.
The source masters are mono PCM at the existing output rates. Requires numpy.
"""
import json
import wave
import numpy as np
from generate_chopping_audio import ROOT, RATE, write

SOURCE = ROOT/'tools/audio_sources/wolf'


def sound(kind, index):
    profile = json.loads((SOURCE/'source.json').read_text(encoding='utf-8'))['banks'][kind]
    rate = profile['rate']
    with wave.open(str(SOURCE/profile['master']), 'rb') as source:
        assert (source.getnchannels(), source.getsampwidth(), source.getframerate()) == (1, 2, rate)
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype='<i2').astype(float)/32768
    start, end = profile['regions_seconds'][index]
    result = samples[round(start*rate):round(end*rate)].copy()
    assert len(result) == round(end*rate)-round(start*rate)
    result -= result.mean()
    padding = round(rate*.15)
    padded = np.pad(result, padding, mode='reflect')
    frequencies = np.fft.rfftfreq(len(padded), 1/rate)
    high_pass = 1/np.sqrt(1+(profile['high_pass_hz']/np.maximum(frequencies, 1e-6))**4)
    low_pass = 1/np.sqrt(1+(frequencies/profile['low_pass_hz'])**8)
    result = np.fft.irfft(np.fft.rfft(padded)*high_pass*low_pass, n=len(padded))[padding:-padding]
    result -= result.mean()
    fade_in, fade_out = [round(seconds*rate) for seconds in profile['fades_seconds']]
    result[:fade_in] *= np.linspace(0, 1, fade_in)
    result[-fade_out:] *= np.linspace(1, 0, fade_out)
    rms = np.sqrt(np.mean(result**2))
    result *= min(profile['target_rms']/max(float(rms), 1e-8),
                  profile['peak_ceiling']/max(float(abs(result).max()), 1e-8))
    assert np.isfinite(result).all() and abs(result).max() < 1
    return result


def write_howl(index):
    # Use the same environmental WAV writer from either generator entry point.
    from generate_environment_audio import write as environment_write
    environment_write(f'wolf_howl_{index+1:02}', sound('howl', index))


if __name__ == '__main__':
    sampler = []
    for kind in ['select', 'eat']:
        for i in range(3):
            pcm = sound(kind, i)
            path = ROOT/'assets/audio/wildlife'/f'wolf_{kind}_{i+1:02}.wav'
            write(path, pcm)
            sampler.extend([pcm, np.zeros(round(.5*RATE))])
            print(path.name, 'seconds', round(len(pcm)/RATE, 2), 'peak', round(float(abs(pcm).max()), 3))
    for i in range(3): write_howl(i)
    write(ROOT/'tmp/wolf_review/wolf_sampler.wav', np.concatenate(sampler))
    print('Wolf audio: 3 recorded canine selection cues, 3 recorded canine eating cues, 3 real wolf howl excerpts.')
