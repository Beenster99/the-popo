"""Phase 1.7: make the fight sounds hit harder (beenster: "the gun sounds and
breakage sounds are very weak").

The recordings are peak-normalised but very peaky, so their loudness is low
(the loudest 50 ms sits 15-25 dB under full scale). This drives each one
into a soft clipper (tanh) until its loudest 50 ms reaches a target, then
puts the peak back at -1 dBFS. Transients stay sharp, the body gets fat.

Run once from the repo root:  python3 tools/audio/punch.py
It is idempotent-ish: files already at their target are left alone."""
import glob, os, wave
import numpy as np

SFX = "assets/audio/sfx"
# stem prefix -> target loudness of the loudest 50 ms, dBFS
TARGETS = {
    "gun_near": -6.0, "gun_dry": -6.0, "gun_far": -9.0, "gun_mech": -10.0,
    "break_": -8.0, "impact_": -8.0, "glass_break": -8.0, "glass_big": -8.0,
    "rubble": -10.0, "explosion_1": -5.0, "body_hit": -7.0, "bullet_crack": -7.0,
}


def loud50(x, rate):
    win = max(1, int(rate * 0.05))
    sq = np.convolve(x.astype(np.float64) ** 2, np.ones(win) / win, mode="valid")
    return 10 * np.log10(sq.max() + 1e-12)


def process(path, target):
    with wave.open(path) as w:
        ch, sw, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if sw != 2:
        return None
    x = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0
    mono = x.reshape(-1, ch).mean(axis=1) if ch > 1 else x
    before = loud50(mono, rate)
    if before >= target - 0.5:
        return before, before
    peak_out = 10 ** (-1.0 / 20)
    lo, hi = 1.0, 60.0
    y = x
    for _ in range(30):
        g = (lo + hi) / 2
        y = np.tanh(x * g)
        y *= peak_out / max(np.abs(y).max(), 1e-9)
        m = y.reshape(-1, ch).mean(axis=1) if ch > 1 else y
        if loud50(m, rate) < target:
            lo = g
        else:
            hi = g
    out = (np.clip(y, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(out.tobytes())
    m = y.reshape(-1, ch).mean(axis=1) if ch > 1 else y
    return before, loud50(m, rate)


for f in sorted(glob.glob(os.path.join(SFX, "*.wav"))):
    name = os.path.basename(f)
    for k, tgt in TARGETS.items():
        if name.startswith(k):
            r = process(f, tgt)
            if r:
                print(f"{name:28s} {r[0]:6.1f} -> {r[1]:6.1f} dB")
            break
