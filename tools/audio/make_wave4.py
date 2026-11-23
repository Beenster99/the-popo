"""Wave 4, Phase 4.3: weather sounds made from scratch (no third-party audio).

  amb_rain   steady rain on the streets: a hiss of drops, patter on hard
             surfaces and the odd heavy drip off a gutter (loops)
  thunder    a crack of lightning close by rolling away into a long, low
             rumble off the buildings (3 variants)

    python3 tools/audio/make_wave4.py        (needs ffmpeg and numpy)
"""
import os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_wave2 as w2

SR = w2.SR
rng = np.random.default_rng(4303)


def amb_rain(sec=12.0):
    n = int(sec * SR)
    hiss = w2.fft_filter(rng.normal(0, 1, n), 1500, 11000) * 0.35
    body = w2.lowpass(rng.normal(0, 1, n), 700) * 0.5
    patter = np.zeros(n)
    for _ in range(int(sec * 900)):
        a = rng.integers(0, n - 400)
        m = rng.integers(60, 300)
        patter[a:a + m] += rng.normal(0, 1, m) * np.exp(-np.arange(m) / (m / 5)) * rng.uniform(0.05, 0.35)
    patter = w2.fft_filter(patter, 900, 9000)
    drips = np.zeros(n)
    for _ in range(int(sec * 1.5)):
        a = rng.integers(0, n - 3000)
        f = rng.uniform(500, 1100)
        m = 2400
        tt = np.arange(m) / SR
        drips[a:a + m] += np.sin(2 * np.pi * f * tt * (1 + 2.5 * tt)) * np.exp(-tt / 0.02) * 0.4
    return w2.seamless(hiss + body + patter + drips)


def thunder(i):
    sec = 7.5
    n = int(sec * SR)
    tt = np.arange(n) / SR
    crack_n = int(0.35 * SR)
    crack = w2.fft_filter(rng.normal(0, 1, crack_n), 400, 9000) * np.exp(-np.arange(crack_n) / (0.06 * SR))
    rumble = w2.lowpass(rng.normal(0, 1, n), 90 + 30 * i) * 4.0
    # Uneven swells as it rolls off different streets.
    swell = np.zeros(n)
    for k in range(6):
        c = rng.uniform(0.3, 5.0)
        wdt = rng.uniform(0.4, 1.4)
        swell += np.exp(-((tt - c) / wdt) ** 2) * rng.uniform(0.4, 1.0)
    rumble *= (0.4 + swell) * np.exp(-tt / 3.2)
    out = rumble
    delay = int(rng.uniform(0.0, 0.25) * SR)
    out[delay:delay + crack_n] += crack * (1.6 - 0.4 * i)
    fade = np.ones(n)
    fade[-int(0.8 * SR):] = np.linspace(1, 0, int(0.8 * SR))
    return out * fade


def main():
    w2.write("amb_rain_1.wav", amb_rain(), "rain on the streets: hiss, patter, drips (loops)", -6.0, "Made by tools/audio/make_wave4.py")
    for i in range(3):
        w2.write(f"thunder_{i + 1}.wav", thunder(i), "thunder: a close crack rolling into a long rumble", -1.0, "Made by tools/audio/make_wave4.py")
    import csv
    with open(w2.MANIFEST, newline="") as f:
        rows = list(csv.reader(f))
    names = {r[0] for r in w2.ROWS}
    rows = [r for r in rows if r and r[0] not in names] + w2.ROWS
    with open(w2.MANIFEST, "w", newline="") as f:
        csv.writer(f, lineterminator="\n").writerows(rows)
    print("made", len(w2.ROWS), "sounds")


if __name__ == "__main__":
    main()
