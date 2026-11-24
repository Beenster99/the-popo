"""Repair crew sounds (the project's own, synthesised, no third-party audio):

  works_drill   cordless drill biting into concrete: motor whine, hammer rattle
  works_grind   angle grinder on steel: high screech with grit
  works_weld    arc welding: frying crackle and buzz
  works_beep    reversing beeper (one loop)
  works_hyd     crane hydraulics: pump whine and diesel under it
  works_chain   slings and hook chain rattling as a load lands

    python tools/audio/make_works.py      (needs numpy and scipy)
"""
import csv
import os

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SFX = os.path.join(ROOT, "assets", "audio", "sfx")
MANIFEST = os.path.join(ROOT, "assets", "audio", "manifest.csv")
rng = np.random.default_rng(7)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def bp(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], btype="band")
    return lfilter(b, a, x)


def lp(x, hi, order=2):
    b, a = butter(order, hi / (SR / 2), btype="low")
    return lfilter(b, a, x)


def env(n, a=0.02, r=0.1):
    e = np.ones(n)
    na, nr = int(a * SR), int(r * SR)
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] = np.linspace(1, 0, nr)
    return e


def saw(f, tt):
    ph = np.cumsum(f / SR) if np.ndim(f) else f * tt
    return 2.0 * (ph % 1.0) - 1.0


def drill(seed):
    tt = t(1.4 + 0.2 * seed)
    f = 520 + 60 * np.minimum(1, tt * 6) + 15 * np.sin(2 * np.pi * 3 * tt)
    motor = 0.5 * saw(f, tt) + 0.3 * np.sin(2 * np.pi * np.cumsum(f * 2) / SR)
    hammer = (np.sin(2 * np.pi * 38 * tt) > 0.6).astype(float)
    grit = bp(rng.standard_normal(len(tt)), 1500, 6000) * (0.5 + 0.5 * hammer)
    thud = lp(rng.standard_normal(len(tt)), 300) * hammer * 3
    x = bp(motor, 300, 5000) * 0.6 + grit * 0.5 + thud * 0.4
    return x * env(len(tt), 0.05, 0.15)


def grind(seed):
    tt = t(2.0)
    f = 2900 + 400 * seed + 120 * np.sin(2 * np.pi * 0.7 * tt)
    scream = np.sin(2 * np.pi * np.cumsum(np.full(len(tt), f)) / SR)
    scream += 0.5 * np.sin(2 * np.pi * np.cumsum(np.full(len(tt), f * 2.01)) / SR)
    grit = bp(rng.standard_normal(len(tt)), 2500, 12000)
    am = 0.7 + 0.3 * lp(rng.standard_normal(len(tt)), 8) * 8
    motor = bp(saw(180, tt), 150, 2000)
    x = (scream * 0.35 + grit * 0.9) * np.clip(am, 0.2, 1.3) + motor * 0.2
    return x * env(len(tt), 0.08, 0.2)


def weld(seed):
    tt = t(2.2)
    n = len(tt)
    crackle = np.zeros(n)
    for i in rng.integers(0, n - 400, 2600):
        k = rng.uniform(0.2, 1.0)
        crackle[i:i + 60] += k * rng.standard_normal(60) * np.exp(-np.arange(60) / 12)
    hum = 0.25 * np.sign(np.sin(2 * np.pi * 100 * tt)) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.5 * tt + seed))
    fry = bp(rng.standard_normal(n), 3000, 9000) * 0.35
    x = bp(crackle, 800, 10000) * 1.2 + lp(hum, 1200) * 0.4 + fry
    return x * env(n, 0.05, 0.2)


def beep(_seed):
    tt = t(1.0)
    on = tt < 0.45
    x = np.sin(2 * np.pi * 1180 * tt) + 0.3 * np.sin(2 * np.pi * 2360 * tt)
    x = x * on * np.minimum(1, tt * 300) * np.minimum(1, np.maximum(0, (0.45 - tt) * 300))
    return x * 0.8


def hyd(seed):
    tt = t(2.5)
    f = 140 + 30 * np.minimum(1, tt * 2)
    pump = bp(saw(f, tt), 100, 3000) * 0.5
    whine = np.sin(2 * np.pi * np.cumsum(np.full(len(tt), 880 + 40 * seed)) / SR) * 0.12
    diesel = lp(saw(36 + 4 * seed, tt) + 0.6 * rng.standard_normal(len(tt)), 400) * 0.9
    x = pump + whine + diesel
    return x * env(len(tt), 0.3, 0.4)


def chain(seed):
    tt = t(1.3)
    n = len(tt)
    x = np.zeros(n)
    for i in sorted(rng.integers(0, int(n * 0.7), 14 + seed * 3)):
        m = int(SR * 0.08)
        tone = sum(np.sin(2 * np.pi * f * np.arange(m) / SR) for f in rng.uniform(2200, 5200, 3))
        seg = tone * np.exp(-np.arange(m) / (SR * 0.015)) * rng.uniform(0.3, 1.0)
        x[i:i + m] += seg[: n - i]
    thump = lp(rng.standard_normal(n), 180) * np.exp(-tt * 9) * 6
    return x * 0.5 + thump


SOUNDS = [
    ("works_drill", drill, 2, "cordless hammer drill into concrete"),
    ("works_grind", grind, 2, "angle grinder on steel"),
    ("works_weld", weld, 2, "arc welding crackle"),
    ("works_beep", beep, 1, "reversing beeper"),
    ("works_hyd", hyd, 2, "crane hydraulics over diesel"),
    ("works_chain", chain, 2, "sling chains rattle, load lands"),
]

if __name__ == "__main__":
    rows = list(csv.reader(open(MANIFEST)))
    rows = [r for r in rows if r and not r[0].startswith("sfx/works_")]
    for stem, fn, count, note in SOUNDS:
        for v in range(1, count + 1):
            x = fn(v - 1)
            x = x * 0.85 / max(1e-6, np.abs(x).max())
            path = os.path.join(SFX, "%s_%d.wav" % (stem, v))
            wavfile.write(path, SR, (x * 32767).astype(np.int16))
            rows.append(["sfx/%s_%d.wav" % (stem, v), "Made by tools/audio/make_works.py", "Project's own (no third-party audio)", note])
            print("wrote", path)
    with open(MANIFEST, "w", newline="") as f:
        csv.writer(f).writerows(rows)
