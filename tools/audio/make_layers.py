"""Phase 1.6: sounds made from scratch for the project (no third-party audio):
layers that make gunshots punch, and small physical sounds there are no good
free recordings of.

  gun_thump       the low-end punch under a close shot (pitch-dropping sine + sub)
  gun_shotgun_body  the deeper boom under a shotgun blast
  bullet_crack    a supersonic bullet passing close to your head (N-wave + hiss)
  bullet_whizz    a bullet going past further off (swept band noise)
  ricochet        the whine of a bullet glancing off metal or concrete
  casing_<surface>  a pistol case bouncing on concrete, wood or metal
  mag_drop_<surface>  an empty magazine hitting the floor
  ear_ring        the ring in your ears after a very close shot
  whoosh          a fist or boot swinging through the air
  tyre_skid       tyres squealing (loops)
  room_tone       the hush of an indoor room (loops)
  fire_loop       a fire roaring and crackling (loops; Phase 1.5)
  fire_whoomph    flames catching
  gas_hiss        a fire extinguisher bursting

    python3 tools/audio/make_layers.py        (needs ffmpeg and numpy)

Writes 16-bit mono 44.1 kHz WAV to assets/audio/sfx/ and lists them in the
manifest as the project's own.
"""
import csv, os, subprocess
import numpy as np

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "assets", "audio", "sfx")
MANIFEST = os.path.join(ROOT, "assets", "audio", "manifest.csv")
rng = np.random.default_rng(1606)


def t_(sec):
    return np.arange(int(sec * SR)) / SR


def write(name, x, note, peak_db=-1.0):
    m = np.abs(x).max()
    if m > 0:
        x = x * (10 ** (peak_db / 20) / m)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "pcm_s16le", os.path.join(OUT, name)], input=data, check=True)
    ROWS.append([f"sfx/{name}", "Made by tools/audio/make_layers.py", "Project's own (no third-party audio)", note])


def onepole_lp(x, hz):
    a = np.exp(-2 * np.pi * hz / SR)
    y = np.empty_like(x)
    s = 0.0
    for i, v in enumerate(x):
        s = (1 - a) * v + a * s
        y[i] = s
    return y


def bandpass(x, lo, hi):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(X, len(x))


def swept_band(n, f0, f1, width):
    """Noise whose pass band slides from f0 to f1 (STFT-ish, 20 ms blocks)."""
    out = np.zeros(n)
    blk = int(0.02 * SR)
    noise = rng.standard_normal(n + blk)
    for s in range(0, n, blk // 2):
        k = s / max(1, n - 1)
        fc = f0 * (f1 / f0) ** k
        seg = bandpass(noise[s:s + blk], fc - width / 2, fc + width / 2) * np.hanning(blk)
        e = min(n, s + blk)
        out[s:e] += seg[: e - s]
    return out


def env_exp(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def thump(i):
    t = t_(0.45)
    f = 48 + 9 * i + 140 * np.exp(-t / 0.018)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * env_exp(len(t), 0.09)
    sub = np.sin(2 * np.pi * (34 + 4 * i) * t) * env_exp(len(t), 0.16) * 0.6
    click = rng.standard_normal(len(t)) * env_exp(len(t), 0.0015) * 0.5
    x = body + sub + onepole_lp(click, 3000)
    att = np.minimum(1, t / 0.0015)
    return np.tanh(1.6 * x * att)


def shotgun_body(i):
    t = t_(0.8)
    f = 38 + 6 * i + 110 * np.exp(-t / 0.03)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(len(t), 0.16)
    rumble = onepole_lp(rng.standard_normal(len(t)), 220) * env_exp(len(t), 0.25) * 4
    return np.tanh(1.4 * (body + rumble) * np.minimum(1, t / 0.002))


def crack(i):
    n = int(0.07 * SR)
    x = np.zeros(n)
    w = int(0.0011 * SR)                     # the N-wave: up, down, back
    x[:w] = np.linspace(0, 1, w)
    x[w:3 * w] = np.linspace(1, -1, 2 * w)
    x[3 * w:4 * w] = np.linspace(-1, 0, w)
    hiss = bandpass(rng.standard_normal(n), 2500, 12000) * env_exp(n, 0.006 + 0.002 * i) * 0.35
    snap = bandpass(rng.standard_normal(n), 800, 6000) * env_exp(n, 0.004) * 0.6
    return x + hiss + snap


def whizz(i):
    n = int((0.22 + 0.04 * i) * SR)
    x = swept_band(n, 3800 - 300 * i, 900, 900)
    k = np.linspace(0, 1, n)
    return x * np.sin(np.pi * k) ** 1.5 * (1 - 0.6 * k)


def ricochet(i):
    dur = 0.55 + 0.12 * i
    t = t_(dur)
    f0, f1 = 3400 - 250 * i, 1100 + 120 * i
    f = f0 * (f1 / f0) ** (t / dur) * (1 + 0.012 * np.sin(2 * np.pi * 31 * t))
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(len(t), dur * 0.45)
    hit = bandpass(rng.standard_normal(len(t)), 1500, 9000) * env_exp(len(t), 0.006)
    return tone * 0.8 + hit


def modal_ping(n, freqs, decays, amp):
    t = np.arange(n) / SR
    y = np.zeros(n)
    for f, d in zip(freqs, decays):
        y += np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / d)
    return y * amp


def bounces(times, amps, make, length):
    n = int(length * SR)
    x = np.zeros(n)
    for tm, a in zip(times, amps):
        s = int(tm * SR)
        p = make(n - s) * a
        x[s:] += p
    return x


def casing(surface, i):
    base = np.array([4100, 6900, 10800]) * (1 + 0.04 * (i - 1))
    if surface == "concrete":
        dec, hard = [0.05, 0.03, 0.018], 1.0
        times = [0.0, 0.11, 0.19, 0.245, 0.28]
    elif surface == "metal":
        dec, hard = [0.12, 0.08, 0.05], 1.0
        times = [0.0, 0.12, 0.21, 0.27]
    else:  # wood: dull, short, a knock under it
        dec, hard = [0.018, 0.012, 0.008], 0.6
        times = [0.0, 0.09, 0.15]
    amps = [1.0, 0.55, 0.32, 0.2, 0.12][: len(times)]
    def make(n):
        y = modal_ping(n, base * rng.uniform(0.98, 1.02, 3), dec, 1.0)
        tick = bandpass(rng.standard_normal(n), 3000, 14000) * env_exp(n, 0.0012) * 0.8
        knock = np.sin(2 * np.pi * 420 * np.arange(n) / SR) * env_exp(n, 0.01) * (0.6 if surface == "wood" else 0.0)
        return (y * hard + tick + knock)
    return bounces(times, amps, make, times[-1] + 0.3)


def mag_drop(surface, i):
    times = [0.0, 0.09 + 0.01 * i, 0.16]
    amps = [1.0, 0.45, 0.2]
    def make(n):
        t = np.arange(n) / SR
        if surface == "wood":
            thud = np.sin(2 * np.pi * 180 * t) * np.exp(-t / 0.02)
            clat = bandpass(rng.standard_normal(n), 600, 4000) * np.exp(-t / 0.006) * 0.6
        elif surface == "metal":
            thud = modal_ping(n, [1300, 2900, 4700], [0.08, 0.05, 0.03], 0.6)
            clat = bandpass(rng.standard_normal(n), 2000, 9000) * np.exp(-t / 0.004)
        else:
            thud = np.sin(2 * np.pi * 260 * t) * np.exp(-t / 0.012) * 0.7
            clat = bandpass(rng.standard_normal(n), 1500, 9000) * np.exp(-t / 0.005)
            clat += modal_ping(n, [2200, 3700], [0.02, 0.012], 0.4)
        return thud + clat
    return bounces(times, amps, make, 0.5)


def explosion_body(i):
    t = t_(2.6)
    rumble = onepole_lp(rng.standard_normal(len(t)), 160 + 40 * i) * 6
    roar = bandpass(rng.standard_normal(len(t)), 200, 2500) * 0.5
    e = np.minimum(1, t / 0.004) * (np.exp(-t / 0.5) * 0.7 + np.exp(-t / 0.06) * 0.6)
    f = 32 + 130 * np.exp(-t / 0.05)
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.35) * 1.4
    return np.tanh((rumble + roar * np.exp(-t / 0.25) + boom) * e * 1.5)


def ear_ring():
    t = t_(3.2)
    tone = np.sin(2 * np.pi * 4100 * t) + 0.35 * np.sin(2 * np.pi * 4127 * t)
    e = np.minimum(1, t / 0.05) * np.exp(-t / 1.1)
    return tone * e


def whoosh(i):
    n = int((0.2 + 0.03 * i) * SR)
    x = swept_band(n, 350 + 60 * i, 1600, 700)
    k = np.linspace(0, 1, n)
    return x * np.sin(np.pi * k) ** 2


def tyre_skid():
    dur = 3.0
    t = t_(dur)
    f = 760 * (1 + 0.03 * np.sin(2 * np.pi * 7 * t) + 0.02 * onepole_lp(rng.standard_normal(len(t)), 30) * 6)
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.25 * np.sin(3 * ph)
    am = 0.75 + 0.25 * onepole_lp(rng.standard_normal(len(t)), 40) * 8
    hiss = bandpass(rng.standard_normal(len(t)), 1500, 7000) * 0.08
    x = np.tanh(tone * am * 0.8) + hiss
    n = int(0.3 * SR)
    w = np.linspace(0, 1, n)
    x[:n] = x[:n] * w + x[-n:] * (1 - w)
    return x[:-n]


def room_tone():
    dur = 8.0
    n = int(dur * SR)
    brown = np.cumsum(rng.standard_normal(n))
    brown = brown - onepole_lp(brown, 5)          # keep it from wandering
    x = onepole_lp(brown, 350) * 0.02
    t = np.arange(n) / SR
    x += (np.sin(2 * np.pi * 100 * t) * 0.25 + np.sin(2 * np.pi * 50 * t) * 0.15) * np.abs(x).mean() * 2
    m = int(0.5 * SR)
    w = np.linspace(0, 1, m)
    x[:m] = x[:m] * w + x[-m:] * (1 - w)
    return x[:-m]


def crackles(n, rate, lo, hi, amp):
    x = np.zeros(n)
    k = int(rate * n / SR)
    for at in rng.integers(0, n - int(0.03 * SR), k):
        m = int(rng.uniform(0.002, 0.012) * SR)
        burst = bandpass(rng.standard_normal(m * 4), lo, hi)[:m] * np.exp(-np.arange(m) / (m * 0.25))
        x[at:at + m] += burst * amp * rng.uniform(0.2, 1.0) ** 2
    return x


def fire_loop():
    dur = 6.0
    n = int(dur * SR)
    roar = bandpass(rng.standard_normal(n), 60, 900)
    am = 0.7 + 0.3 * onepole_lp(rng.standard_normal(n), 3) * 25
    x = roar * np.clip(am, 0.2, 1.4) * 0.5
    x += crackles(n, 28, 1500, 7000, 3.0) + crackles(n, 6, 300, 2500, 4.0)
    m = int(0.5 * SR)
    w = np.linspace(0, 1, m)
    x[:m] = x[:m] * w + x[-m:] * (1 - w)
    return x[:-m]


def fire_whoomph(i):
    n = int((1.0 + 0.2 * i) * SR)
    k = np.linspace(0, 1, n)
    x = swept_band(n, 150, 900 + 300 * i, 600)
    x += bandpass(rng.standard_normal(n), 40, 220) * 0.8
    env = np.minimum(k / 0.12, 1.0) * np.exp(-np.maximum(k - 0.12, 0) * 4.5)
    return x * env + crackles(n, 20, 1500, 6000, 1.5) * env


def gas_hiss():
    n = int(1.6 * SR)
    k = np.arange(n) / SR
    x = bandpass(rng.standard_normal(n), 1800, 9000) * np.exp(-k / 0.6) * np.minimum(k / 0.01, 1.0)
    pop = bandpass(rng.standard_normal(n), 80, 1200) * np.exp(-k / 0.05) * 2.0
    return x + pop


ROWS = []


def main():
    for i in (1, 2, 3):
        write(f"gun_thump_{i}.wav", thump(i), "low-end punch under a close shot")
        write(f"gun_shotgun_body_{i}.wav", shotgun_body(i), "shotgun boom layer")
        write(f"bullet_crack_{i}.wav", crack(i), "supersonic crack of a near miss")
        write(f"bullet_whizz_{i}.wav", whizz(i), "bullet whizzing past")
        write(f"whoosh_{i}.wav", whoosh(i), "swing through the air")
    for i in (1, 2, 3, 4):
        write(f"ricochet_{i}.wav", ricochet(i), "ricochet whine")
    for s in ("concrete", "wood", "metal"):
        for i in (1, 2, 3):
            write(f"casing_{s}_{i}.wav", casing(s, i), f"pistol case bouncing on {s}", -4.0)
        for i in (1, 2):
            write(f"mag_drop_{s}_{i}.wav", mag_drop(s, i), f"empty magazine dropping on {s}")
    for i in (1, 2):
        write(f"explosion_body_{i}.wav", explosion_body(i), "explosion rumble layer")
    write("ear_ring_1.wav", ear_ring(), "ear ring after a very close shot", -6.0)
    write("tyre_skid_1.wav", tyre_skid(), "tyres squealing, loops", -3.0)
    write("room_tone_1.wav", room_tone(), "indoor room hush, loops", -6.0)
    write("fire_loop_1.wav", fire_loop(), "fire roaring and crackling, loops", -3.0)
    for i in (1, 2):
        write(f"fire_whoomph_{i}.wav", fire_whoomph(i), "flames catching")
    write("gas_hiss_1.wav", gas_hiss(), "fire extinguisher bursting")
    rows = list(csv.reader(open(MANIFEST)))
    have = {r[0]: i for i, r in enumerate(rows)}
    for r in ROWS:
        if r[0] in have:
            rows[have[r[0]]] = r
        else:
            rows.append(r)
    with open(MANIFEST, "w", newline="") as fh:
        csv.writer(fh, lineterminator="\n").writerows(rows)
    print("made", len(ROWS), "sounds")


if __name__ == "__main__":
    main()
