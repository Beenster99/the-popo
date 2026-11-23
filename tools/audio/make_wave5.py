"""Wave 5, Phase 5.2: radio and music made from scratch (no third-party audio).

  radio_key     a radio keying up: click, squelch burst of static (3 variants)
  radio_unkey   the squelch tail when the talker lets go (2 variants)
  radio_voice   a far-off talker on another channel: speech-like syllables
                through a radio's narrow band, too garbled to make out (6)
  music/menu.ogg    the title theme: D minor, slow and moody (loops)
  music/patrol.ogg  under a quiet patrol: A minor pad and pluck (loops)
  music/action.ogg  gunfights and chases: E minor, driving drums and bass (loops)

    python3 tools/audio/make_wave5.py        (needs ffmpeg and numpy)
"""
import os, subprocess, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_wave2 as w2

SR = w2.SR
SRC = "Made by tools/audio/make_wave5.py"
MUSIC = os.path.join(w2.ROOT, "assets", "audio", "music")
rng = np.random.default_rng(5205)


# --- radio --------------------------------------------------------------------------

def radio_band(x):
    x = w2.fft_filter(x, 350, 3200)
    return np.tanh(x * 2.5) / np.tanh(2.5)


def radio_key(i):
    n = int(0.28 * SR)
    t = np.arange(n) / SR
    click = np.zeros(n)
    click[:60] = np.hanning(60) * (1 if i % 2 else -1)
    burst = rng.normal(0, 1, n) * np.exp(-t / 0.05) * 0.6
    tone = np.sin(2 * np.pi * (1100 + 150 * i) * t) * np.exp(-t / 0.03) * 0.25
    return radio_band(click * 1.5 + burst + tone)


def radio_unkey(i):
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    env = np.clip(t / 0.01, 0, 1) * np.exp(-t / (0.09 + 0.03 * i))
    return radio_band(rng.normal(0, 1, n) * env * 0.8)


def radio_voice(i):
    """Syllables: a buzzy glottal source through moving formants."""
    sec = rng.uniform(1.8, 3.4)
    n = int(sec * SR)
    t = np.arange(n) / SR
    f0 = 105 + 25 * (i % 3) + 12 * np.sin(2 * np.pi * 0.7 * t + i)
    phase = np.cumsum(f0) / SR
    src = 2 * (phase % 1.0) - 1.0      # saw: the voice's buzz
    out = np.zeros(n)
    # Syllable envelope: bursts of 90-220 ms with small gaps, the odd pause.
    env = np.zeros(n)
    p = int(0.05 * SR)
    while p < n - 2000:
        m = int(rng.uniform(0.09, 0.22) * SR)
        m = min(m, n - p)
        env[p:p + m] = np.hanning(m) ** 0.6 * rng.uniform(0.6, 1.0)
        p += m + int(rng.uniform(0.01, 0.06) * SR)
        if rng.random() < 0.12:
            p += int(0.25 * SR)
    # Formants that jump between vowels each syllable-ish.
    vowels = [(700, 1200), (400, 2000), (300, 900), (600, 1700), (500, 1400)]
    seg = int(0.12 * SR)
    for a in range(0, n, seg):
        b = min(n, a + seg)
        f1, f2 = vowels[rng.integers(0, len(vowels))]
        chunk = src[a:b]
        out[a:b] = w2.fft_filter(chunk, f1 * 0.7, f1 * 1.3) * 1.0 + w2.fft_filter(chunk, f2 * 0.8, f2 * 1.2) * 0.6
    out *= env
    out += rng.normal(0, 1, n) * env * 0.08          # breath
    out += rng.normal(0, 1, n) * 0.03                # the channel's hiss
    return radio_band(out)


# --- music --------------------------------------------------------------------------

NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def hz(name, octave):
    return 440.0 * 2 ** ((NOTE[name] + 12 * (octave + 1) - 69) / 12)


def chord(root, minor, octave):
    r = NOTE[root] + 12 * (octave + 1)
    third = 3 if minor else 4
    return [440.0 * 2 ** ((m - 69) / 12) for m in (r, r + third, r + 7)]


def saw(f, n, detune=0.0):
    ph = np.cumsum(np.full(n, f * (1 + detune))) / SR + rng.random()
    return 2 * (ph % 1.0) - 1.0


def adsr(n, a, r):
    e = np.ones(n)
    na, nr = min(n, int(a * SR)), min(n, int(r * SR))
    e[:na] = np.linspace(0, 1, na)
    if nr:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def reverb(x, sec=2.2, mix=0.3):
    n = int(sec * SR)
    ir = rng.normal(0, 1, n) * np.exp(-np.arange(n) / (sec * SR / 6.0))
    ir = w2.lowpass(ir, 5000)
    ir /= np.sqrt((ir ** 2).sum())
    L = len(x) + n
    wet = np.fft.irfft(np.fft.rfft(x, L) * np.fft.rfft(ir, L), L)
    # Fold the tail back to the start so the loop's reverb carries over.
    wet[:n] += wet[len(x):]
    return x * (1 - mix) + wet[:len(x)] * mix * 3.0


def kick(n, punch=1.0):
    t = np.arange(n) / SR
    f = 45 + 110 * np.exp(-t / 0.03)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.22) * punch


def snare(n):
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.05)
    noise = w2.fft_filter(rng.normal(0, 1, n), 1500, 9000) * np.exp(-t / 0.12)
    return body * 0.6 + noise * 0.7


def hat(n, open_=False):
    t = np.arange(n) / SR
    return w2.fft_filter(rng.normal(0, 1, n), 6000, 16000) * np.exp(-t / (0.12 if open_ else 0.025))


def place(buf, x, at):
    a = int(at)
    b = min(len(buf), a + len(x))
    if a < len(buf):
        buf[a:b] += x[:b - a]


def track(bpm, bars, prog, style):
    beat = 60.0 / bpm
    bar = 4 * beat
    n = int(bars * bar * SR)
    pad = np.zeros(n)
    bass = np.zeros(n)
    drums = np.zeros(n)
    lead = np.zeros(n)
    nb = int(bar * SR)
    for k in range(bars):
        root, minor = prog[k % len(prog)]
        a = k * nb
        # Pad: detuned saws on the chord, darkened, slow swell.
        tones = chord(root, minor, 3 if style != "action" else 4)
        p = sum(saw(f, nb, d) for f in tones for d in (-0.004, 0.004)) / 6.0
        p = w2.lowpass(p, 900 if style != "action" else 1500) * adsr(nb, 0.6 if style != "action" else 0.05, 0.3)
        pad[a:a + nb] += p * (0.55 if style != "action" else 0.3)
        # Bass.
        f = hz(root, 1 if style == "action" else 2)
        if style == "action":
            for e in range(8):   # driving eighths with a push on the last
                m = int(beat / 2 * SR)
                s = np.tanh(3 * (saw(f, m) * 0.7 + np.sin(2 * np.pi * f * np.arange(m) / SR))) * adsr(m, 0.003, 0.05)
                place(bass, w2.lowpass(s, 700) * (1.0 if e % 2 == 0 else 0.75), a + e * m)
        else:
            for e in range(2):
                m = int(2 * beat * SR)
                s = np.sin(2 * np.pi * f * np.arange(m) / SR) + 0.3 * w2.lowpass(saw(f, m), 400)
                place(bass, s * adsr(m, 0.02, 0.4) * 0.8, a + e * m)
        # Drums.
        for b in range(4):
            at = a + int(b * beat * SR)
            if style == "action":
                place(drums, kick(int(0.4 * SR), 1.1), at)
                if b in (1, 3):
                    place(drums, snare(int(0.3 * SR)), at)
                if b == 2 and k % 2 == 1:
                    place(drums, kick(int(0.4 * SR), 0.8), at + int(beat * 0.5 * SR))
                for h in range(4):
                    place(drums, hat(int(0.06 * SR)) * (0.35 if h % 2 else 0.2), at + int(h * beat / 4 * SR))
            elif style == "menu":
                if b in (0, 2) and k >= 2:
                    place(drums, kick(int(0.4 * SR), 0.7), at)
                if b in (1, 3) and k >= 4:
                    place(drums, snare(int(0.3 * SR)) * 0.5, at)
                if k >= 2:
                    for h in range(2):
                        place(drums, hat(int(0.05 * SR)) * 0.12, at + int(h * beat / 2 * SR))
            else:   # patrol: just a soft pulse
                place(drums, hat(int(0.05 * SR)) * 0.08, at + int(beat / 2 * SR))
                if b == 0:
                    place(drums, kick(int(0.4 * SR), 0.35), at)
        # A plucked arpeggio up the chord (stabs for action).
        tones = chord(root, minor, 4 if style != "action" else 5)
        steps = 8 if style != "action" else 4
        for e in range(steps):
            if style == "menu" and k < 4:
                break
            m = int(bar / steps * SR)
            f = tones[[0, 1, 2, 1, 0, 2, 1, 2][e % 8]] * (2 if (style == "patrol" and e == 7) else 1)
            tt = np.arange(m) / SR
            s = (saw(f, m) * 0.4 + np.sin(2 * np.pi * f * tt)) * np.exp(-tt / (0.18 if style != "action" else 0.07))
            place(lead, w2.lowpass(s, 2500) * (0.28 if style != "action" else 0.2), a + e * m)
    mix = pad + bass * (0.9 if style == "action" else 0.7) + drums * 0.9 + lead
    mix = reverb(mix, 2.6 if style != "action" else 1.4, 0.35 if style != "action" else 0.18)
    # Gentle stereo: delay the lead and pad a hair on one side.
    left = mix
    right = np.roll(mix, int(0.011 * SR)) * 0.96 + np.roll(lead, int(0.02 * SR)) * 0.15
    st = np.stack([left, right], axis=1)
    st = st / np.percentile(np.abs(st), 99.9)
    st = np.tanh(st * 0.9) / np.tanh(0.9)
    return st / np.abs(st).max() * 10 ** (-1.5 / 20)


def write_ogg(name, st, note):
    os.makedirs(MUSIC, exist_ok=True)
    data = (np.clip(st, -1, 1) * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", os.path.join(MUSIC, name)], input=data, check=True)
    w2.ROWS.append([f"music/{name}", SRC, "Project's own (no third-party audio)", note])


def main():
    for i in range(3):
        w2.write(f"radio_key_{i + 1}.wav", radio_key(i), "radio keying up: click and squelch", -3.0, SRC)
    for i in range(2):
        w2.write(f"radio_unkey_{i + 1}.wav", radio_unkey(i), "radio squelch tail as the talker lets go", -6.0, SRC)
    for i in range(6):
        w2.write(f"radio_voice_{i + 1}.wav", radio_voice(i), "far-off talker on the radio, garbled", -3.0, SRC)
    write_ogg("menu.ogg", track(84, 16, [("D", True), ("A#", False), ("F", False), ("C", False)], "menu"),
              "title theme, D minor (loops)")
    write_ogg("patrol.ogg", track(90, 16, [("A", True), ("F", False), ("C", False), ("G", False)], "patrol"),
              "quiet patrol bed, A minor (loops)")
    write_ogg("action.ogg", track(128, 16, [("E", True), ("E", True), ("C", False), ("D", False)], "action"),
              "gunfights and chases, E minor (loops)")
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
