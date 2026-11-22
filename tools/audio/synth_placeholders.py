"""Phase 0.7: synthesised placeholder sounds, made from scratch (no third
party audio), so the sound engine work can be tested before real recordings
come in from the free libraries (Sonniss GDC bundles, Freesound, Kenney).

Writes 16-bit mono WAVs to assets/audio/sfx/ and lists each one in
assets/audio/manifest.csv with its source and licence.

    python tools/audio/synth_placeholders.py      (needs numpy and scipy)
"""
import csv, os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "sfx")
MANIFEST = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "manifest.csv")


def t(sec):
    return np.arange(int(SR * sec)) / SR


def env(sec, attack=0.001, decay=0.1):
    x = t(sec)
    a = np.clip(x / attack, 0, 1)
    return a * np.exp(-x / decay)


def band(x, lo=None, hi=None, order=4):
    if lo and hi:
        sos = butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    elif lo:
        sos = butter(order, lo, btype="high", fs=SR, output="sos")
    else:
        sos = butter(order, hi, btype="low", fs=SR, output="sos")
    return sosfilt(sos, x)


def modes(sec, freqs, decays, amps, rng, detune=0.01):
    x = t(sec)
    out = np.zeros_like(x)
    for f, d, a in zip(freqs, decays, amps):
        f *= 1 + rng.uniform(-detune, detune)
        out += a * np.sin(2 * np.pi * f * x + rng.uniform(0, 6.28)) * np.exp(-x / d)
    return out


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def save(name, x, rows, note):
    path = os.path.join(OUT, name + ".wav")
    wavfile.write(path, SR, (norm(x) * 32767).astype(np.int16))
    rows.append([f"sfx/{name}.wav", "Synthesised by tools/audio/synth_placeholders.py", "Project's own (no third-party audio)", note])


def gun_mech(rng):
    """Slide and hammer: two tight clicks and a metal ring."""
    out = np.zeros(int(SR * 0.12))
    for at, amp in ((0.0, 1.0), (0.018 + rng.uniform(0, 0.004), 0.6)):
        click = band(rng.standard_normal(int(SR * 0.006)), 2500, 9000) * env(0.006, 0.0002, 0.0015)
        i = int(at * SR)
        out[i:i + click.size] += click * amp
    ring = modes(0.12, [2350, 3720, 5130, 7400], [0.03, 0.02, 0.015, 0.01], [0.3, 0.25, 0.2, 0.1], rng)
    return out + ring * 0.5


def gun_crack(rng):
    """The supersonic crack: a very short broadband N-wave."""
    n = int(SR * 0.05)
    x = np.zeros(n)
    w = int(SR * 0.0012)
    x[:w] = np.linspace(1, -1, w)
    noise = band(rng.standard_normal(n), 1500, 14000) * env(0.05, 0.0001, 0.006)
    return x * 0.8 + noise


def gun_body(rng):
    """The low punch of the shot: a falling thump and saturated low noise."""
    sec = 0.35
    x = t(sec)
    f = 140 * np.exp(-x / 0.05) + 42
    thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(sec, 0.0005, 0.09)
    rumble = band(rng.standard_normal(x.size), None, 900) * env(sec, 0.0005, 0.06)
    return np.tanh(2.5 * (thump + rumble * 1.5))


def gun_tail_outdoor(rng):
    """Outdoor tail: slapback off distant buildings, long dark decay."""
    sec = 1.6
    x = t(sec)
    tail = band(rng.standard_normal(x.size), 120, 2200) * np.exp(-x / 0.45) * np.clip((x - 0.04) / 0.08, 0, 1)
    out = tail * 0.5
    for d, a in ((0.11, 0.5), (0.23, 0.3), (0.41, 0.2)):
        i = int(d * SR)
        burst = band(rng.standard_normal(int(SR * 0.08)), 200, 1800) * env(0.08, 0.002, 0.03)
        out[i:i + burst.size] += burst * a
    return out


def impact_wood(rng):
    knock = modes(0.25, [190, 410, 760, 1250], [0.05, 0.035, 0.02, 0.012], [1.0, 0.6, 0.35, 0.2], rng, 0.05)
    hit = band(rng.standard_normal(int(SR * 0.25)), 300, 2500) * env(0.25, 0.0005, 0.015)
    return knock + hit * 0.7


def impact_glass(rng):
    sec = 0.9
    out = modes(sec, [3100, 4870, 6650, 8900], [0.25, 0.18, 0.12, 0.08], [0.6, 0.5, 0.4, 0.25], rng, 0.03)
    crash = band(rng.standard_normal(int(SR * sec)), 2500, 15000) * env(sec, 0.0005, 0.06)
    out += crash
    # Tinkles of falling shards.
    for _ in range(14):
        i = int(rng.uniform(0.05, 0.8) * SR)
        p = modes(0.08, [rng.uniform(4000, 11000)], [0.02], [rng.uniform(0.1, 0.35)], rng)
        out[i:i + p.size] += p[: max(0, min(p.size, out.size - i))]
    return out


def impact_concrete(rng):
    sec = 0.3
    hit = band(rng.standard_normal(int(SR * sec)), 150, 4000) * env(sec, 0.0003, 0.025)
    grit = np.zeros(int(SR * sec))
    for _ in range(40):
        i = int(rng.uniform(0.005, 0.2) * SR)
        grit[i] += rng.uniform(-1, 1) * np.exp(-i / SR / 0.06)
    grit = band(grit, 2000, 9000)
    thud = modes(sec, [95, 160], [0.04, 0.03], [0.6, 0.3], rng, 0.05)
    return hit + grit * 2.5 + thud


def impact_metal(rng):
    sec = 0.8
    ring = modes(sec, [820, 1370, 2610, 3940], [0.25, 0.18, 0.12, 0.08], [0.8, 0.6, 0.4, 0.25], rng, 0.04)
    hit = band(rng.standard_normal(int(SR * sec)), 1500, 9000) * env(sec, 0.0003, 0.01)
    return ring + hit


def main():
    os.makedirs(OUT, exist_ok=True)
    rows = []
    gens = {
        "gun_mech": (gun_mech, 3, "Pistol layer 1: mechanism"),
        "gun_crack": (gun_crack, 3, "Pistol layer 2: crack"),
        "gun_body": (gun_body, 3, "Pistol layer 3: body"),
        "gun_tail_outdoor": (gun_tail_outdoor, 2, "Pistol layer 4: outdoor tail (indoors the reverb bus does the tail)"),
        "impact_wood": (impact_wood, 3, "Bullet impact on wood"),
        "impact_glass": (impact_glass, 3, "Bullet impact on glass"),
        "impact_concrete": (impact_concrete, 3, "Bullet impact on concrete and brick"),
        "impact_metal": (impact_metal, 3, "Bullet impact on metal"),
    }
    for name, (fn, variants, note) in gens.items():
        for v in range(variants):
            rng = np.random.default_rng(hash((name, v)) % (2 ** 32))
            save(f"{name}_{v + 1}", fn(rng), rows, note)
    with open(MANIFEST, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["file", "source", "licence", "notes"])
        w.writerows(rows)
    print(f"wrote {len(rows)} files")


if __name__ == "__main__":
    main()
