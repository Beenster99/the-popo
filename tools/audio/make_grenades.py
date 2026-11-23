"""Grenades (2026-11-23): sounds made from scratch (no third-party audio).

  nade_pin      the pin pulled and the spoon flying off (2 variants)
  nade_bounce   a metal can or a frag clinking off the floor (4)
  flashbang     a flashbang: a huge, sharp crack with a pressure thump and
                a metallic ring (2). Meant to be the loudest thing in the game.
  frag_crack    the supersonic crack of a frag's casing, layered over the
                explosion (2)
  smoke_pop     the canister catching: a dull pop and a spit of gas (1)
  smoke_hiss    a smoke or CS can pouring out, a seamless loop (1)
  cough         someone choking on CS gas (6)

    python3 tools/audio/make_grenades.py        (needs ffmpeg and numpy)
"""
import csv, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_wave2 as w2

SR = w2.SR
SRC = "Made by tools/audio/make_grenades.py"
rng = np.random.default_rng(1123)


def t_(sec):
    return np.arange(int(sec * SR)) / SR


def ring(t, freqs, tau, amp=1.0):
    out = np.zeros_like(t)
    for k, f in enumerate(freqs):
        out += np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / (tau / (1 + 0.4 * k))) / (1 + k)
    return out * amp


def nade_pin(i):
    t = t_(0.7)
    n = len(t)
    out = np.zeros(n)
    # Pin: a scrape and a tink.
    s = int(0.02 * SR)
    m = int(0.09 * SR)
    out[s:m] += w2.fft_filter(rng.normal(0, 1, m - s), 2500, 9000) * np.hanning(m - s) * 0.35
    tt = t[m:] - t[m]
    out[m:] += ring(tt, [3900 + 300 * i, 6100, 8700], 0.05, 0.6)
    # Spoon: flicks off with a springy ping a moment later.
    k = int((0.32 + 0.05 * i) * SR)
    tt = t[k:] - t[k]
    out[k:] += ring(tt, [2300 + 200 * i, 3450, 5200], 0.08, 0.8)
    out[k:k + 200] += rng.normal(0, 1, 200) * np.hanning(200) * 0.6
    return out


def nade_bounce(i):
    t = t_(0.35)
    base = [1500, 1800, 1250, 2100][i]
    x = ring(t, [base, base * 2.43, base * 3.9], 0.04 + 0.01 * i)
    x[:120] += rng.normal(0, 1, 120) * np.hanning(120) * 1.2
    thud = np.sin(2 * np.pi * 160 * t) * np.exp(-t / 0.02) * 0.6
    return x + thud


def flashbang(i):
    t = t_(2.6)
    n = len(t)
    # The crack: an instant, brutally loud broadband spike.
    crack = rng.normal(0, 1, n) * np.exp(-t / (0.008 + 0.002 * i))
    crack = np.tanh(crack * 4) * 1.0
    # Pressure thump under it.
    f = 45 + 80 * np.exp(-t / 0.03)
    thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.18) * 1.3
    # Body: noise that rolls off, then the city slapping it back.
    body = w2.lowpass(rng.normal(0, 1, n), 1800) * np.exp(-t / 0.35) * 0.8
    tail = np.zeros(n)
    for d, g in [(0.09, 0.45), (0.21, 0.3), (0.38, 0.2), (0.6, 0.12)]:
        k = int(d * SR)
        tail[k:] += w2.lowpass(crack[: n - k], 2500) * g
    # The casing rings out (it's a steel can that's just been blown open).
    metal = ring(t, [2650 + 120 * i, 4100, 6900], 0.25, 0.18)
    x = crack * 1.4 + thump + body + tail + metal
    return np.tanh(x * 1.6)


def frag_crack(i):
    t = t_(1.4)
    n = len(t)
    crack = np.tanh(rng.normal(0, 1, n) * np.exp(-t / 0.006) * 5)
    f = 38 + 70 * np.exp(-t / 0.05)
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.35) * 1.4
    # Fragments whirring off in every direction.
    whirr = w2.fft_filter(rng.normal(0, 1, n), 1500 + 400 * i, 7000) * np.exp(-t / 0.12) * 0.5
    x = crack * 1.3 + sub + whirr
    return np.tanh(x * 1.4)


def smoke_pop():
    t = t_(0.9)
    n = len(t)
    pop = np.sin(2 * np.pi * (90 + 160 * np.exp(-t / 0.02)) * t) * np.exp(-t / 0.06)
    spit = w2.fft_filter(rng.normal(0, 1, n), 800, 8000) * np.clip(t / 0.03, 0, 1) * np.exp(-t / 0.4) * 0.6
    return pop + spit


def smoke_hiss():
    t = t_(7.0)
    n = len(t)
    hiss = w2.fft_filter(rng.normal(0, 1, n), 1200, 12000) * 0.6
    # Sputtering: the burning compound spits.
    flutter = 0.75 + 0.25 * np.sin(2 * np.pi * 7.3 * t) * np.sin(2 * np.pi * 1.1 * t)
    crackle = np.zeros(n)
    for k in rng.integers(0, n - 300, 160):
        crackle[k:k + 300] += rng.normal(0, 1, 300) * np.hanning(300) * rng.uniform(0.3, 1.0)
    crackle = w2.fft_filter(crackle, 1500, 9000) * 0.35
    rumble = w2.lowpass(rng.normal(0, 1, n), 300) * 0.5
    return w2.seamless(hiss * flutter + crackle + rumble, 0.6)


def cough(i):
    """One to three hacking coughs: a glottal burst through a vowel-ish formant."""
    reps = [1, 2, 3, 2, 1, 3][i]
    total = np.zeros(int(1.4 * SR))
    pos = 0
    f0 = [140, 120, 180, 210, 105, 160][i]
    for r in range(reps):
        dur = rng.uniform(0.22, 0.34)
        t = t_(dur)
        n = len(t)
        env = np.clip(t / 0.008, 0, 1) * np.exp(-t / (0.07 + 0.02 * r))
        noise = rng.normal(0, 1, n)
        buzz = np.sign(np.sin(2 * np.pi * f0 * (1 - 0.3 * t / dur) * t)) * 0.4
        src = noise + buzz * np.exp(-t / 0.05)
        x = w2.fft_filter(src, 300, 3200) + 0.6 * w2.fft_filter(src, 500, 1100)
        x = np.tanh(x * env * 2.0)
        end = min(pos + n, len(total))
        total[pos:end] += x[: end - pos]
        pos += int(n * rng.uniform(0.75, 1.0)) + int(rng.uniform(0.03, 0.09) * SR)
    # A gasp in after.
    g = t_(0.3)
    gasp = w2.fft_filter(rng.normal(0, 1, len(g)), 900, 4000) * np.sin(np.pi * g / 0.3) * 0.25
    end = min(pos + len(g), len(total))
    total[pos:end] += gasp[: end - pos]
    return total[: min(len(total), end + 100)]


def main():
    for i in range(2):
        w2.write(f"nade_pin_{i + 1}.wav", nade_pin(i), "grenade pin pulled, spoon flies off", -6.0, SRC)
    for i in range(4):
        w2.write(f"nade_bounce_{i + 1}.wav", nade_bounce(i), "grenade clinks off the floor", -4.0, SRC)
    for i in range(2):
        w2.write(f"flashbang_{i + 1}.wav", flashbang(i), "flashbang: huge crack, thump, ringing can", -0.3, SRC)
    for i in range(2):
        w2.write(f"frag_crack_{i + 1}.wav", frag_crack(i), "frag grenade casing crack and shrapnel", -0.3, SRC)
    w2.write("smoke_pop_1.wav", smoke_pop(), "smoke or CS canister catching", -2.0, SRC)
    w2.write("smoke_hiss_1.wav", smoke_hiss(), "smoke canister pouring out (loops)", -3.0, SRC)
    for i in range(6):
        w2.write(f"cough_{i + 1}.wav", cough(i), "choking on CS gas", -3.0, SRC)
    with open(w2.MANIFEST, newline="") as f:
        rows = list(csv.reader(f))
    names = {r[0] for r in w2.ROWS}
    rows = [r for r in rows if r and r[0] not in names] + w2.ROWS
    with open(w2.MANIFEST, "w", newline="") as f:
        csv.writer(f, lineterminator="\n").writerows(rows)
    print("made", len(w2.ROWS), "sounds")


if __name__ == "__main__":
    main()
