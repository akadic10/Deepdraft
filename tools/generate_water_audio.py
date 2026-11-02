"""Prepare recorded shoreline, river, waterfall, cave drips and duck splash foley.

CC0 masters and edit profiles are in tools/audio_sources/water/.
Shoreline remains stereo; spatial moving water, drips and splashes are mono. Requires numpy; works offline.
"""
import json
import wave
import numpy as np
from generate_environment_audio import ROOT, RATE, write

SOURCE = ROOT/'tools/audio_sources/water'


def sound(kind):
    profile = json.loads((SOURCE/'source.json').read_text(encoding='utf-8'))['banks'][kind]
    channels = profile['channels']
    rate = profile['rate']
    assert rate in (22050, 48000) and channels in (1, 2)
    with wave.open(str(SOURCE/profile['master']), 'rb') as source:
        assert (source.getnchannels(), source.getsampwidth(), source.getframerate()) == (channels, 2, rate)
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype='<i2').reshape(-1, channels).astype(float)/32768
    start, end = profile['region_seconds']
    result = samples[round(start*rate):round(end*rate)].copy()
    assert len(result) == round(end*rate)-round(start*rate)
    result -= result.mean(axis=0)
    padding = round(rate*.5)
    padded = np.pad(result, ((padding, padding), (0, 0)), mode='reflect')
    frequencies = np.fft.rfftfreq(len(padded), 1/rate)
    high_pass = 1/np.sqrt(1+(profile['high_pass_hz']/np.maximum(frequencies, 1e-6))**4)
    low_pass = 1/np.sqrt(1+(frequencies/profile['low_pass_hz'])**8)
    result = np.fft.irfft(np.fft.rfft(padded, axis=0)*(high_pass*low_pass)[:, None],
                         n=len(padded), axis=0)[padding:-padding]
    if 'soft_peak_rms' in profile:
        # Tame rare close-mic brook transients without lowering the whole bed.
        threshold = profile['soft_peak_rms']*np.sqrt(np.mean(result**2))
        result = threshold*np.tanh(result/threshold)
    if profile['loop']:
        overlap = round(profile['crossfade_seconds']*rate)
        length = round(profile['loop_seconds']*rate)
        assert len(result) == length+overlap and length > overlap
        angle = np.linspace(0, np.pi/2, overlap)[:, None]
        loop = result[overlap:].copy()
        # Wrapping reaches adjacent source samples without a fade to silence.
        loop[-overlap:] = result[-overlap:]*np.cos(angle)+result[:overlap]*np.sin(angle)
        result = loop
    else:
        fade_in, fade_out = [round(seconds*rate) for seconds in profile['fades_seconds']]
        result[:fade_in] *= np.linspace(0, 1, fade_in)[:, None]
        result[-fade_out:] *= np.linspace(1, 0, fade_out)[:, None]
    result -= result.mean(axis=0)
    result *= min(profile['target_rms']/max(float(np.sqrt(np.mean(result**2))), 1e-8),
                  profile['peak_ceiling']/max(float(abs(result).max()), 1e-8))
    assert np.isfinite(result).all() and abs(result).max() < 1
    return result[:, 0] if channels == 1 else result


def write_sound(kind):
    profile = json.loads((SOURCE/'source.json').read_text(encoding='utf-8'))['banks'][kind]
    samples = sound(kind)
    if kind.startswith('duck_splash'):
        from generate_chopping_audio import write as write_wildlife
        write_wildlife(ROOT/profile['output'], samples)
    elif kind in ['river', 'waterfall']:
        path = ROOT/profile['output']
        path.parent.mkdir(parents=True, exist_ok=True)
        with wave.open(str(path), 'wb') as output:
            output.setparams((1, 2, RATE, len(samples), 'NONE', 'not compressed'))
            output.writeframes(np.round(samples*32767).astype('<i2').tobytes())
    else:
        write(kind, samples, profile['loop'])
    return samples


if __name__ == '__main__':
    profiles = json.loads((SOURCE/'source.json').read_text(encoding='utf-8'))['banks']
    for kind, profile in profiles.items():
        samples = write_sound(kind)
        print(kind, 'seconds', round(len(samples)/profile['rate'], 3), 'peak', round(float(abs(samples).max()), 3))
