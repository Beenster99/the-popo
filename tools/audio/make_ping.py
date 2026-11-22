"""Makes the ping chime (the project's own sound, no third-party audio): two
quick bell-like notes, rising, so a ping is heard over gunfire.

    python tools/audio/make_ping.py      (needs numpy and scipy)
"""
import csv, os
import numpy as np
from scipy.io import wavfile

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "assets", "audio", "sfx", "ping_1.wav")
MANIFEST = os.path.join(ROOT, "assets", "audio", "manifest.csv")

x = np.zeros(int(SR * 0.6))
for start, f in ((0.0, 1318.5), (0.09, 1760.0)):
    n = np.arange(int(SR * 0.5)) / SR
    note = sum(np.sin(2 * np.pi * f * k * n) * a for k, a in ((1, 1.0), (2.76, 0.25), (5.4, 0.08)))
    note *= np.exp(-n * 9.0) * np.minimum(1.0, n * 400)
    i = int(start * SR)
    x[i:i + len(note)] += note
x *= 0.8 / np.abs(x).max()
wavfile.write(OUT, SR, (x * 32767).astype(np.int16))
rows = list(csv.reader(open(MANIFEST)))
rows = [r for r in rows if r and r[0] != "sfx/ping_1.wav"]
rows.append(["sfx/ping_1.wav", "Made by tools/audio/make_ping.py", "Project's own (no third-party audio)", "ping chime"])
with open(MANIFEST, "w", newline="") as f:
    csv.writer(f).writerows(rows)
print("wrote", OUT)
