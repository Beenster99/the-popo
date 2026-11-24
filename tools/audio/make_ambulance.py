"""Synthesises the ambulance siren loops as 16-bit mono WAVs: a wail a
little higher and quicker than the police one, and the two-tone hi-lo.
Made from scratch here, so there is no licence to track.

    python3 tools/audio/make_ambulance.py
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
    for i in range(int(RATE * seconds)):
        t = i / RATE
        phase += 2 * math.pi * freq_at(t) / RATE
        s = math.sin(phase) + 0.3 * math.sin(3 * phase) + 0.15 * math.sin(5 * phase) + 0.06 * math.sin(7 * phase)
        out.append(math.tanh(1.5 * s) * 0.55)
    return out


def save(name, samples):
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32000)) for s in samples))
    print("wrote", path)


# Wail: 3.2 s round, 750 to 1500 Hz.
save("ambulance_wail_1.wav", tone(lambda t: 750 + 750 * (0.5 - 0.5 * math.cos(2 * math.pi * t / 3.2)), 6.4))


# Hi-lo: two notes, 0.6 s each, a quick glide between them.
def hilo(t):
    k = (t / 0.6) % 2.0
    hi, lo = 960.0, 760.0
    if k < 1.0:
        return lo + (hi - lo) * min(1.0, k / 0.04)
    return hi + (lo - hi) * min(1.0, (k - 1.0) / 0.04)


save("ambulance_hilo_1.wav", tone(hilo, 0.6 * 2 * 6))
