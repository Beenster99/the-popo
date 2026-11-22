"""Synthesises the police siren loops (wail and yelp) as 16-bit mono WAVs.
Made from scratch here, so there is no licence to track.

    python3 tools/audio/make_sirens.py
"""
import math
import os
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "sfx")


def tone(freq_at, seconds):
    out = []
    phase = 0.0
    n = int(RATE * seconds)
    for i in range(n):
        t = i / RATE
        f = freq_at(t)
        phase += 2 * math.pi * f / RATE
        # A horn-like buzz: odd harmonics, then soft clipping.
        s = math.sin(phase) + 0.35 * math.sin(3 * phase) + 0.18 * math.sin(5 * phase) + 0.08 * math.sin(7 * phase)
        s = math.tanh(1.6 * s) * 0.55
        out.append(s)
    return out


def save(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32000)) for s in samples))
    print("wrote", path)


# Wail: a slow rise and fall, 4 s round, so the loop meets itself.
save("siren_wail_1.wav", tone(lambda t: 650 + 650 * (0.5 - 0.5 * math.cos(2 * math.pi * t / 4.0)), 4.0))
# Yelp: fast rising sweeps, 0.32 s each (25 of them make 8 s).
save("siren_yelp_1.wav", tone(lambda t: 700 + 800 * ((t / 0.32) % 1.0) ** 0.7, 0.32 * 25))
