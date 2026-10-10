"""Generate Deepdraft's original, short mallet/chime promotion cue (no samples)."""
from pathlib import Path
import math
import struct
import wave

RATE = 44100
DURATION = 1.25
NOTES = [(0.0, 392.0, 0.26), (0.16, 523.251, 0.29), (0.32, 659.255, 0.42)]
samples = []
for i in range(round(RATE * DURATION)):
    t = i / RATE
    value = 0.0
    for onset, frequency, decay in NOTES:
        age = t - onset
        if age < 0:
            continue
        attack = 1.0 - math.exp(-age / 0.0035)
        # A warm wood-like fundamental with a soft bell overtone, no hiss.
        for ratio, weight, length in [(1, 1.0, 1.0), (2, .22, .55), (3.99, .07, .25)]:
            value += attack * weight * math.exp(-age / (decay * length)) * math.sin(math.tau * frequency * ratio * age)
    fade = min(1.0, max(0.0, (DURATION - t) / .12))
    samples.append(value * fade)
scale = .52 / max(abs(v) for v in samples)
output = Path(__file__).resolve().parents[1] / "assets/audio/ui/promotion.wav"
output.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(output), "wb") as wav:
    wav.setnchannels(1)
    wav.setsampwidth(2)
    wav.setframerate(RATE)
    wav.writeframes(b"".join(struct.pack("<h", round(value * scale * 32767)) for value in samples))
print(f"Generated {output}: {DURATION}s, peak {max(abs(v * scale) for v in samples):.3f}")
