"""Prepare individual recorded boot steps from local CC0 masters (numpy only).

Stone/wood are direct recordings; grass and earth use recorded foley. Credits,
source hashes and edit regions live in tools/audio_sources/footsteps/.
"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'tools/audio_sources/footsteps'
RATE = 48000


def sounds(kind):
    profile = json.loads((SOURCE/'source.json').read_text(encoding='utf-8'))['banks'][kind]
    with wave.open(str(SOURCE/profile['master']), 'rb') as reader:
        assert (reader.getnchannels(), reader.getsampwidth(), reader.getframerate()) == (1, 2, RATE)
        source = np.frombuffer(reader.readframes(reader.getnframes()), dtype='<i2').astype(float)/32768
    result = []
    for start, end in profile['regions_seconds']:
        samples = source[round(start*RATE):round(end*RATE)].copy()
        samples -= samples.mean()
        pad = round(RATE*.05)
        padded = np.pad(samples, pad, mode='reflect')
        frequencies = np.fft.rfftfreq(len(padded), 1/RATE)
        high_pass = 1/np.sqrt(1+(profile['high_pass_hz']/np.maximum(frequencies, 1e-6))**4)
        low_pass = 1/np.sqrt(1+(frequencies/profile['low_pass_hz'])**8)
        samples = np.fft.irfft(np.fft.rfft(padded)*high_pass*low_pass, n=len(padded))[pad:-pad]
        samples -= samples.mean()
        attack = round(profile['fade_in_seconds']*RATE)
        release = round(profile['fade_out_seconds']*RATE)
        samples[:attack] *= np.sin(np.linspace(0, np.pi/2, attack))**2
        samples[-release:] *= np.cos(np.linspace(0, np.pi/2, release))**2
        samples *= min(profile['target_rms']/np.sqrt(np.mean(samples**2)),
                       profile['peak_ceiling']/abs(samples).max())
        assert np.isfinite(samples).all() and abs(samples).max() < 1
        assert abs(samples[0]) < 1e-6 and abs(samples[-1]) < 1e-6
        result.append(samples)
    return result


def write_bank(kind):
    folder = ROOT/'assets/audio/dwarves/footsteps'
    folder.mkdir(parents=True, exist_ok=True)
    for index, samples in enumerate(sounds(kind), 1):
        path = folder/f'{kind}_{index:02d}.wav'
        with wave.open(str(path), 'wb') as writer:
            writer.setparams((1, 2, RATE, len(samples), 'NONE', 'not compressed'))
            writer.writeframes(np.round(samples*32767).astype('<i2').tobytes())
        print(f'{path.name}: {len(samples)/RATE:.3f}s; RMS={np.sqrt(np.mean(samples**2)):.4f}; peak={abs(samples).max():.4f}')


if __name__ == '__main__':
    runtime = json.loads((ROOT/'data/audio/work_feedback.json').read_text(encoding='utf-8'))['audio']
    for bank in ('footstep_stone', 'footstep_wood', 'footstep_earth', 'footstep_grass'):
        kind = bank.removeprefix('footstep_')
        expected = [f'res://assets/audio/dwarves/footsteps/{kind}_{i:02d}.wav'
                    for i in range(1, len(sounds(kind))+1)]
        assert runtime[bank] == expected, f'Runtime bank does not match source profiles: {bank}'
        write_bank(kind)
