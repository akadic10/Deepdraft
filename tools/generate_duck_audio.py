"""Prepare recorded duck quacks and small recorded water splashes.

Quacks are distinct excerpts of gibarroule's CC0 field recording, not oscillators.
Quack provenance lives in tools/audio_sources/duck_quack/; splash foley in
tools/audio_sources/water/ (three separate lake-water splashes, not recorded ducks).
Requires only numpy; no network or audio decoder is needed to rebuild the bank.
"""
import wave
import numpy as np
from generate_chopping_audio import ROOT, RATE, write

SOURCE = ROOT/'tools/audio_sources/duck_quack/duck_quacks.wav'
QUACK_REGIONS = [(0.31, 0.72), (0.88, 1.25), (1.49, 1.87)]


def quack(index):
    with wave.open(str(SOURCE), 'rb') as source:
        assert (source.getnchannels(), source.getsampwidth(), source.getframerate()) == (1, 2, RATE)
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype='<i2').astype(float)/32768
    start, end = QUACK_REGIONS[index]
    result = samples[round(start*RATE):round(end*RATE)].copy()
    result -= result.mean()
    # Gentle, zero-phase band limiting removes rumble without altering pitch.
    padding = RATE//10
    padded = np.pad(result, padding, mode='reflect')
    frequencies = np.fft.rfftfreq(len(padded), 1/RATE)
    high_pass = 1/np.sqrt(1+(110/np.maximum(frequencies, 1e-6))**4)
    low_pass = 1/np.sqrt(1+(frequencies/9500)**8)
    result = np.fft.irfft(np.fft.rfft(padded)*high_pass*low_pass, n=len(padded))[padding:-padding]
    result -= result.mean()
    # The short fades sit outside the recorded call; no gating or time stretching.
    result[:round(.005*RATE)] *= np.linspace(0, 1, round(.005*RATE))
    result[-round(.025*RATE):] *= np.linspace(1, 0, round(.025*RATE))
    # Match the old bank's ~-26 dBFS RMS without exceeding its 0.32 peak ceiling.
    rms = np.sqrt(np.mean(result**2))
    result *= min(.048/max(float(rms), 1e-8), .32/max(float(abs(result).max()), 1e-8))
    return result


def splash(index):
    from generate_water_audio import sound
    return sound(f'duck_splash_{index+1:02}')


if __name__ == '__main__':
    sampler = []
    for family in ['quack', 'splash']:
        for i in range(3):
            pcm = quack(i) if family == 'quack' else splash(i)
            write(ROOT/'assets/audio/wildlife'/f'duck_{family}_{i+1:02}.wav', pcm)
            sampler.extend([pcm, np.zeros(RATE//2)])
            assert np.isfinite(pcm).all() and abs(pcm).max() < .4
    write(ROOT/'tmp/duck_review/duck_sampler.wav', np.concatenate(sampler))
    print('Duck audio: 3 recorded quacks + 3 recorded water splashes; mono 48 kHz PCM; peak <= 0.32')
