"""Wave 2, sound track S3: sounds made from scratch for the city (no
third-party audio, except where it reworks the project's own gun recordings).

  gun_sub         a deep sub-bass boom under a close shot, felt more than heard
  gun_crack_near  the sharp supersonic snap and muzzle blast at the front of a
                  close shot, so it cuts through like a real one
  gun_tail_city   a shot rolling round the streets: the distant recordings
                  (gun_far_*) bounced off walls along a street, 2.5 s long,
                  darker and quieter with each echo (for shots further off)
  amb_docks       water slapping the quay, rigging, a ship's horn far off (loops)
  amb_industrial  a factory hum, a fan, metal clanking now and then (loops)
  amb_park        wind in the trees and birds (loops)

    python3 tools/audio/make_wave2.py        (needs ffmpeg and numpy)
"""
import csv, os, subprocess
import numpy as np

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "assets", "audio", "sfx")
MANIFEST = os.path.join(ROOT, "assets", "audio", "manifest.csv")
rng = np.random.default_rng(2303)
ROWS = []


def t_(sec):
    return np.arange(int(sec * SR)) / SR


def env_exp(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def write(name, x, note, peak_db=-1.0, source="Made by tools/audio/make_wave2.py"):
    m = np.abs(x).max()
    if m > 0:
        x = x * (10 ** (peak_db / 20) / m)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "pcm_s16le", os.path.join(OUT, name)], input=data, check=True)
    ROWS.append([f"sfx/{name}", source, "Project's own (no third-party audio)", note])


def read(name):
    raw = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", os.path.join(OUT, name), "-f", "s16le", "-ac", "1",
                          "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, "<i2").astype(np.float64) / 32768.0


def fft_filter(x, lo, hi):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(X, len(x))


def lowpass(x, hz):
    """Gentle (6 dB/oct-ish) low-pass in the frequency domain."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X /= np.sqrt(1 + (f / hz) ** 2)
    return np.fft.irfft(X, len(x))


def seamless(x, fade=1.0):
    """Cross-fades the end into the start so it loops without a click."""
    n = int(fade * SR)
    head, tail = x[:n].copy(), x[-n:]
    k = np.linspace(0, 1, n)
    x = x[:-n].copy()
    x[:n] = head * k + tail * (1 - k)
    return x


# --- guns ---------------------------------------------------------------------------

def gun_sub(i):
    t = t_(0.6)
    f = 31 + 4 * i + 60 * np.exp(-t / 0.035)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(len(t), 0.13 + 0.02 * i)
    att = np.minimum(1, t / 0.003)
    return np.tanh(2.2 * body * att)


def gun_crack_near(i):
    n = int(0.16 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    snap = fft_filter(noise, 1800, 14000) * env_exp(n, 0.0028 + 0.0007 * i)
    blast = fft_filter(rng.standard_normal(n), 120, 2500) * env_exp(n, 0.012 + 0.003 * i) * 1.3
    # The muzzle pressure wave: a single fat asymmetric pulse.
    pulse = np.exp(-((t - 0.0012) / 0.0007) ** 2) * 2.2 - np.exp(-((t - 0.0035) / 0.0016) ** 2) * 0.9
    x = snap + blast + pulse
    return np.tanh(1.8 * x)


def gun_tail_city(i, fars):
    """One distant shot, then its echoes off the buildings down the street:
    a dozen reflections over 2.5 s, each later one quieter and darker."""
    src = fars[i % len(fars)]
    m = min(len(src), int(0.9 * SR))
    src = src[:m] * np.hanning(m * 2)[m:]
    n = int(2.8 * SR)
    out = np.zeros(n)
    delays = np.sort(rng.uniform(0.09, 2.2, 14))
    for k, d in enumerate(delays):
        g = 0.75 * np.exp(-d / 0.7) * rng.uniform(0.6, 1.0)
        refl = lowpass(np.concatenate([src, np.zeros(int(0.05 * SR))]), 3500 * np.exp(-d / 0.9) + 400)
        s = int(d * SR)
        e = min(n, s + len(refl))
        out[s:e] += refl[: e - s] * g
    # A low rumble under it: the street's own boom.
    rum = lowpass(rng.standard_normal(n), 160) * env_exp(n, 0.6) * np.minimum(1, np.arange(n) / (0.12 * SR))
    out += rum * 0.6 * np.abs(out).max() / max(1e-6, np.abs(rum).max())
    fade = np.ones(n)
    fade[-int(0.4 * SR):] = np.linspace(1, 0, int(0.4 * SR))
    return out * fade


# --- district ambience (30 s loops) ---------------------------------------------------

def amb_docks():
    n = int(31 * SR)
    t = np.arange(n) / SR
    # Water slapping the quay: band noise swelling on slow random waves.
    swell = np.zeros(n)
    for k in range(int(31 / 1.7)):
        c = rng.uniform(0, 31)
        w = rng.uniform(0.25, 0.7)
        swell += np.exp(-((t - c) / w) ** 2) * rng.uniform(0.5, 1.0)
    water = fft_filter(rng.standard_normal(n), 180, 1400) * (0.25 + swell)
    water += fft_filter(rng.standard_normal(n), 40, 250) * 0.6
    # Rigging and hull creaks: short resonant ticks.
    creak = np.zeros(n)
    for k in range(9):
        s = int(rng.uniform(0, 29.5) * SR)
        m = int(0.5 * SR)
        f0 = rng.uniform(300, 700)
        tt = np.arange(m) / SR
        creak[s:s + m] += np.sin(2 * np.pi * (f0 + 40 * np.sin(2 * np.pi * 7 * tt)) * tt) * np.hanning(m) * 0.08
    # A ship's horn far off, once.
    horn = np.zeros(n)
    s = int(12.0 * SR)
    m = int(3.2 * SR)
    tt = np.arange(m) / SR
    h = sum(np.sin(2 * np.pi * 92 * k * tt) / k for k in range(1, 7))
    h *= np.minimum(1, tt / 0.3) * np.minimum(1, (3.2 - tt) / 0.6)
    horn[s:s + m] = lowpass(h, 600) * 0.35
    return seamless(water + creak + horn)


def amb_industrial():
    n = int(31 * SR)
    t = np.arange(n) / SR
    hum = (np.sin(2 * np.pi * 50 * t) + 0.5 * np.sin(2 * np.pi * 100 * t) + 0.25 * np.sin(2 * np.pi * 150 * t))
    hum *= 0.12 * (1 + 0.15 * np.sin(2 * np.pi * 0.21 * t))
    fan = fft_filter(rng.standard_normal(n), 200, 900) * 0.25 * (1 + 0.3 * np.sin(2 * np.pi * 11 * t))
    clank = np.zeros(n)
    for k in range(10):
        s = int(rng.uniform(0, 29.5) * SR)
        m = int(0.6 * SR)
        tt = np.arange(m) / SR
        ring = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt / rng.uniform(0.05, 0.25))
                   for f in rng.uniform(400, 3200, 4))
        hit = fft_filter(rng.standard_normal(m), 300, 6000) * np.exp(-tt / 0.01)
        clank[s:s + m] += (ring * 0.25 + hit * 0.5) * rng.uniform(0.2, 0.6)
    return seamless(hum + fan + lowpass(clank, 2500))


def amb_park():
    n = int(31 * SR)
    t = np.arange(n) / SR
    gust = 0.4 + 0.6 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.07 * t + 1.0)) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.19 * t))
    wind = fft_filter(rng.standard_normal(n), 250, 3000) * gust * 0.35
    birds = np.zeros(n)
    for k in range(26):
        s = int(rng.uniform(0, 30) * SR)
        f0 = rng.uniform(2600, 4800)
        notes = rng.integers(2, 6)
        for j in range(notes):
            m = int(rng.uniform(0.05, 0.12) * SR)
            tt = np.arange(m) / SR
            sweep = f0 * (1 + rng.uniform(-0.25, 0.35) * tt / tt[-1])
            chirp = np.sin(2 * np.pi * np.cumsum(sweep) / SR) * np.hanning(m)
            a = s + j * int(0.14 * SR)
            if a + m < n:
                birds[a:a + m] += chirp * rng.uniform(0.05, 0.18)
    return seamless(wind + birds)


def main():
    for i in range(3):
        write(f"gun_sub_{i + 1}.wav", gun_sub(i), "sub-bass boom under a close shot")
        write(f"gun_crack_near_{i + 1}.wav", gun_crack_near(i), "supersonic snap and muzzle blast at the front of a close shot")
    fars = [read(f"gun_far_{k}.wav") for k in range(1, 5)]
    for i in range(3):
        write(f"gun_tail_city_{i + 1}.wav", gun_tail_city(i, fars),
              "a shot echoing down the streets (reworked from the project's gun_far recordings)", -3.0,
              "Made by tools/audio/make_wave2.py from gun_far_1..4 (Sonniss GDC bundle)")
    write("amb_docks_1.wav", amb_docks(), "docks: water on the quay, creaks, a far ship's horn (loops)", -6.0)
    write("amb_industrial_1.wav", amb_industrial(), "industrial: hum, fan, metal clanks (loops)", -6.0)
    write("amb_park_1.wav", amb_park(), "park: wind in the trees, birds (loops)", -6.0)
    with open(MANIFEST, newline="") as f:
        rows = list(csv.reader(f))
    names = {r[0] for r in ROWS}
    rows = [r for r in rows if r and r[0] not in names] + ROWS
    with open(MANIFEST, "w", newline="") as f:
        csv.writer(f, lineterminator="\n").writerows(rows)
    print("made", len(ROWS), "sounds")


if __name__ == "__main__":
    main()
