"""Imports the game's sound effects from CC0 (public domain) libraries.

Sources (download and unpack them into one folder first, keeping these names):
  firearm/   The Free Firearm Sound Library, "Prepared SFX Library" (CC0)
             https://opengameart.org/content/the-free-firearm-sound-library
  breaking/  75 CC0 breaking/falling/hit sfx (CC0)
             https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx
  wood/      35 wooden cracks/hits/destructions (CC0)
             https://opengameart.org/content/35-wooden-crackshitsdestructions
  raw/       clink1_0.wav, clink2.wav, clink3.wav (CC0)
             https://opengameart.org/content/metal-impact-sounds
             glass_breaking.wav (CC0) https://opengameart.org/content/glass-break

    python tools/audio/import_cc0.py <source folder>     (needs ffmpeg, numpy, scipy)

Each gun recording holds two or three shots; they are found by their onset
and cut into single shots. Everything becomes 16-bit mono 44.1 kHz WAV in
assets/audio/sfx/ and is listed in assets/audio/manifest.csv.
"""
import csv, os, subprocess, sys, tempfile
import numpy as np
from scipy.io import wavfile

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "assets", "audio", "sfx")
MANIFEST = os.path.join(ROOT, "assets", "audio", "manifest.csv")
FIREARM = "https://opengameart.org/content/the-free-firearm-sound-library"
BREAKING = "https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx"
WOOD = "https://opengameart.org/content/35-wooden-crackshitsdestructions"
METAL = "https://opengameart.org/content/metal-impact-sounds"
GLASS = "https://opengameart.org/content/glass-break"
FA = "firearm/Prepared SFX Library/"

# Gun recordings: (file, shot stems to write, source note)
GUNS = [
    (FA + "Walther PPQ/X_39P.wav", "gun_near", "Walther PPQ 9mm, near"),
    (FA + "1911/A_42P.wav", "gun_near", "1911 .45, near"),
    (FA + "Walther PPQ/X_31P.wav", "gun_far", "Walther PPQ 9mm, mid distance"),
    (FA + "1911/A_34P.wav", "gun_far", "1911 .45, mid distance"),
]
# Impacts: (stem, [(file, url)])
IMPACTS = {
    "impact_wood": [("breaking/bfh1_wood_hit_01.ogg", BREAKING), ("breaking/bfh1_wood_hit_02.ogg", BREAKING),
                    ("breaking/bfh1_wood_hit_03.ogg", BREAKING), ("wood/wood_impact/impactwood07.mp3.flac", WOOD)],
    "impact_glass": [("breaking/bfh1_glass_hit_01.ogg", BREAKING), ("breaking/bfh1_glass_hit_02.ogg", BREAKING),
                     ("breaking/bfh1_glass_breaking_02.ogg", BREAKING)],
    "impact_metal": [("breaking/bfh1_metal_hit_01.ogg", BREAKING), ("breaking/bfh1_metal_hit_05.ogg", BREAKING),
                     ("raw/clink1_0.wav", METAL), ("raw/clink2.wav", METAL), ("raw/clink3.wav", METAL)],
    "impact_concrete": [("breaking/bfh1_rock_hit_01.ogg", BREAKING), ("breaking/bfh1_hit_05.ogg", BREAKING),
                        ("breaking/bfh1_hit_09.ogg", BREAKING), ("breaking/bfh1_hit_10.ogg", BREAKING)],
    "glass_break": [("breaking/bfh1_glass_breaking_01.ogg", BREAKING), ("breaking/bfh1_glass_breaking_03.ogg", BREAKING),
                    ("raw/glass_breaking.wav", GLASS)],
}


def load(path):
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", path, "-ac", "1", "-ar", str(SR),
                        "-c:a", "pcm_s16le", tmp.name], check=True)
        _, x = wavfile.read(tmp.name)
    return x.astype(np.float32) / 32768.0


def envelope(x):
    w = int(SR * 0.01)
    return np.convolve(np.abs(x), np.ones(w) / w, "same")


def onsets(x):
    env = envelope(x)
    thr = env.max() * 0.3
    out, i = [], 0
    while i < len(env):
        if env[i] > thr:
            # back up to where the shot starts rising
            j = i
            while j > 0 and env[j] > env.max() * 0.02:
                j -= 1
            out.append(j)
            i += int(SR * 0.4)
        else:
            i += 1
    return out


def finish(x, length, fade, peak_db=-1.0):
    x = x[: int(SR * length)].copy()
    n = min(len(x), int(SR * fade))
    if n > 0:
        x[-n:] *= np.linspace(1.0, 0.0, n) ** 2
    pre = min(len(x), int(SR * 0.002))
    x[:pre] *= np.linspace(0.0, 1.0, pre)
    peak = np.abs(x).max()
    if peak > 0:
        x *= (10 ** (peak_db / 20)) / peak
    return (np.clip(x, -1, 1) * 32767).astype(np.int16)


def trim_start(x):
    env = envelope(x)
    idx = np.where(env > env.max() * 0.02)[0]
    return x[max(0, idx[0] - int(SR * 0.002)):] if len(idx) else x


def main(src):
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".wav") or f.endswith(".wav.import"):
            os.remove(os.path.join(OUT, f))
    rows = []
    counts = {}

    def write(stem, data, source, url, note):
        counts[stem] = counts.get(stem, 0) + 1
        name = "%s_%d.wav" % (stem, counts[stem])
        wavfile.write(os.path.join(OUT, name), SR, data)
        rows.append(["sfx/" + name, "%s (%s)" % (source, url), "CC0 1.0 (public domain)", note])

    for path, stem, note in GUNS:
        x = load(os.path.join(src, path))
        for k, o in enumerate(onsets(x)):
            shot = x[o:]
            if stem == "gun_near":
                write("gun_near", finish(shot, 1.5, 0.5), path, FIREARM, note + ", shot %d, outdoor tail" % (k + 1))
                write("gun_dry", finish(shot, 0.32, 0.12), path, FIREARM, note + ", shot %d, tail cut for indoors" % (k + 1))
            else:
                write("gun_far", finish(shot, 2.0, 0.8, -3.0), path, FIREARM, note + ", shot %d" % (k + 1))
    for stem, files in IMPACTS.items():
        for path, url in files:
            x = trim_start(load(os.path.join(src, path)))
            length = 1.2 if stem == "glass_break" else 0.6
            write(stem, finish(x, length, 0.15, -2.0), path, url, stem.replace("_", " "))
    with open(MANIFEST, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["file", "source", "licence", "notes"])
        w.writerows(rows)
    print("wrote", len(rows), "files:", ", ".join("%s x%d" % kv for kv in sorted(counts.items())))


if __name__ == "__main__":
    main(sys.argv[1])
