"""Original quiet dwarf snores: breath noise, soft low flutter, fading exhale.

Deterministic mono PCM masters; no third-party recordings or runtime synthesis.
Godot imports these like the existing work and wildlife sounds.
"""
from pathlib import Path
import math
import random
import struct
import wave

DEST = Path(__file__).resolve().parents[1] / 'assets/audio/dwarves'
DEST.mkdir(parents=True, exist_ok=True)
RATE = 24000
for variant in range(3):
    rng = random.Random(7319 + variant)
    length = 2.15 + variant * .17
    low = 0.0
    phase = 0.0
    values = []
    for i in range(round(length * RATE)):
        t = i / RATE
        # Inhale rises slowly with irregular soft-palate flutter, then a small
        # airy exhale. Envelopes reach zero at both ends, with no loop seam.
        inhale = math.sin(math.pi * min(1, t / 1.45)) ** 1.6 if t < 1.45 else 0
        exhale_t = (t - 1.48) / (length - 1.48)
        exhale = math.sin(math.pi * exhale_t) ** 1.7 if 0 < exhale_t < 1 else 0
        noise = rng.uniform(-1, 1)
        low += .12 * (noise - low)
        pitch = 67 + variant * 8 + 8 * math.sin(t * 2.4) + 3 * math.sin(t * 13)
        phase += math.tau * pitch / RATE
        flutter = .65 + .35 * math.sin(t * (43 + variant * 3) + math.sin(t * 7))
        voice = math.sin(phase) * .55 + math.sin(phase * 2) * .22 + math.sin(phase * 3) * .08
        signal = inhale * flutter * (low * .65 + voice * .22) + exhale * low * .5
        values.append(signal)
    peak = max(abs(v) for v in values)
    pcm = b''.join(struct.pack('<h', round(v / peak * 12500)) for v in values)
    output = DEST / f'snore_{variant+1:02}.wav'
    with wave.open(str(output), 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(pcm)
    print(f'{output.name}: {length:.2f}s, peak -8.4 dBFS')
