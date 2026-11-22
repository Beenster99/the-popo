"""Makes the car horn (the project's own sound, no third-party audio): a
classic two-tone horn, 420 Hz and 500 Hz, rich in harmonics like a real
diaphragm horn. One second holds whole cycles of both tones, so the game
loops it seamlessly while the horn is held.

    python tools/audio/make_horn.py      (needs numpy and scipy)
"""
import csv, os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "assets", "audio", "sfx", "car_horn_1.wav")
MANIFEST = os.path.join(ROOT, "assets", "audio", "manifest.csv")

t = np.arange(SR) / SR
x = np.zeros_like(t)
for f in (420.0, 500.0):
    for h in range(1, 14):
        x += np.sin(2 * np.pi * f * h * t) / h ** 1.1 * (1.0 if h % 2 else 0.6)
x = np.tanh(x * 1.5)                       # the diaphragm's buzz
x = sosfilt(butter(2, [300, 4500], btype="band", fs=SR, output="sos"), np.tile(x, 3))[SR:2 * SR]
x *= 0.89 / np.abs(x).max()
wavfile.write(OUT, SR, (x * 32767).astype(np.int16))
rows = list(csv.reader(open(MANIFEST)))
rows = [r for r in rows if r and r[0] != "sfx/car_horn_1.wav"]
rows.append(["sfx/car_horn_1.wav", "Made by tools/audio/make_horn.py", "Project's own (no third-party audio)", "two-tone car horn, loops"])
with open(MANIFEST, "w", newline="") as f:
    csv.writer(f).writerows(rows)
print("wrote", OUT)
