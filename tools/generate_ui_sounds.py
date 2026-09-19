#!/usr/bin/env python3
"""Generate the original, deterministic PCM samples bundled with k4."""

import math
from pathlib import Path
import struct
import wave


ROOT = Path(__file__).resolve().parent.parent
RATE = 48000


def render(name, duration, frequency, decay):
    count = round(RATE * duration)
    samples = []
    for i in range(count):
        t = i / RATE
        attack = min(1.0, t / 0.0015)
        release = min(1.0, (count - 1 - i) / (RATE * 0.004))
        envelope = attack * release * math.exp(-t / decay)
        tone = math.sin(math.tau * frequency * t)
        tone += 0.25 * math.sin(math.tau * frequency * 1.8 * t)
        samples.append(round(32767 * 0.55 * envelope * tone))
    with wave.open(str(ROOT / "assets/sounds" / name), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(struct.pack(f"<{count}h", *samples))


if __name__ == "__main__":
    render("click.wav", 0.040, 850, 0.007)
    render("tick.wav", 0.022, 1400, 0.004)
