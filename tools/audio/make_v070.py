"""v0.9.0: lift and grapple sounds made from scratch (no third-party audio).

  lift_ding     the lift arriving: a soft two-note chime (1)
  grapple_fire  the grapple launcher: a hard pneumatic thump and the line
                whipping out (2 variants)
  grapple_hit   the hook biting a roof edge: a heavy metal clank (3)
  rope_slide    sliding down the rope: friction hiss through a descender (2)

    python3 tools/audio/make_v070.py        (needs ffmpeg and numpy)
"""
import csv, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_wave2 as w2

SR = w2.SR
SRC = "Made by tools/audio/make_v070.py"
rng = np.random.default_rng(7070)


def env_exp(n, tau):
    return np.exp(-np.arange(n) / SR / tau)


def lift_ding():
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k, (f, at) in enumerate([(1318.5, 0.0), (1046.5, 0.38)]):
        s = int(at * SR)
        tt = t[: n - s]
        tone = (np.sin(2 * np.pi * f * tt) + 0.35 * np.sin(2 * np.pi * f * 2.76 * tt) * np.exp(-tt / 0.15)
                + 0.2 * np.sin(2 * np.pi * f * 5.4 * tt) * np.exp(-tt / 0.05))
        out[s:] += tone * np.exp(-tt / 0.55) * np.clip(tt / 0.004, 0, 1)
    return out * 0.5


def grapple_fire(i):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * (70 + 15 * i) * t * (1 + 2.0 * np.exp(-t / 0.02))) * env_exp(n, 0.06)
    crack = w2.fft_filter(rng.normal(0, 1, n), 500, 7000) * env_exp(n, 0.012) * 1.6
    # The line whipping out: band noise sweeping down as it pays out.
    whip = np.zeros(n)
    for k in range(6):
        lo = 2400 - k * 320
        seg = w2.fft_filter(rng.normal(0, 1, n), lo, lo + 900)
        win = np.exp(-((t - (0.06 + k * 0.07)) / 0.05) ** 2)
        whip += seg * win * 0.5
    return np.tanh((thump * 1.4 + crack + whip) * 1.6)


def grapple_hit(i):
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f, a, tau in [(380 + 40 * i, 1.0, 0.12), (930 + 70 * i, 0.6, 0.08), (2210 + 130 * i, 0.4, 0.05), (3460, 0.25, 0.03)]:
        out += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * np.exp(-t / tau)
    hit = w2.fft_filter(rng.normal(0, 1, n), 800, 9000) * env_exp(n, 0.008) * 1.5
    grit = w2.fft_filter(rng.normal(0, 1, n), 200, 2000) * env_exp(n, 0.05) * 0.5   # concrete scrape
    return np.tanh((out + hit + grit) * 1.8)


def rope_slide(i):
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    hiss = w2.fft_filter(rng.normal(0, 1, n), 900 + 200 * i, 5200)
    flutter = 0.7 + 0.3 * np.sin(2 * np.pi * (9 + 2 * i) * t)
    env = np.clip(t / 0.08, 0, 1) * np.clip((t[-1] - t) / 0.25, 0, 1)
    squeak = np.sin(2 * np.pi * (1700 + 60 * np.sin(2 * np.pi * 3 * t)) * t) * 0.08
    return (hiss * flutter + squeak) * env


def main():
    w2.write("lift_ding_1.wav", lift_ding(), "lift arriving: two-note chime", -6.0, SRC)
    for i in range(2):
        w2.write(f"grapple_fire_{i + 1}.wav", grapple_fire(i), "grapple launcher: pneumatic thump, line whipping out", -1.0, SRC)
    for i in range(3):
        w2.write(f"grapple_hit_{i + 1}.wav", grapple_hit(i), "grapple hook biting a roof edge: metal clank", -1.0, SRC)
    for i in range(2):
        w2.write(f"rope_slide_{i + 1}.wav", rope_slide(i), "sliding down a rope through a descender", -6.0, SRC)
    with open(w2.MANIFEST, newline="") as f:
        rows = list(csv.reader(f))
    names = {r[0] for r in w2.ROWS}
    rows = [r for r in rows if r and r[0] not in names] + w2.ROWS
    with open(w2.MANIFEST, "w", newline="") as f:
        csv.writer(f, lineterminator="\n").writerows(rows)
    print("made", len(w2.ROWS), "sounds")


if __name__ == "__main__":
    main()
