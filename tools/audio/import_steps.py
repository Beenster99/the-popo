"""v0.12.0 footsteps (beenster: "the footfall sound effect is not great and
too loud"): replaces the sneaker-on-stone steps with boot steps from the
Sonniss GDC 2016 bundle (Levan Nadashvili's Soldier and Civilian Footsteps,
PMSFX STEPS Dirt & Gravel), and adds step_metal for car roofs and bonnets.

Fetch the source files (names as below) from
https://archive.org/details/gameaudiogdc-part1through7 into one folder, then
from the repo root:

    python3 tools/audio/import_steps.py <folder>

Each step is cut from just before its onset, high-passed (no boom), gently
low-passed (no hiss), faded, and matched to a fixed loudness that sits
under the game's guns and voices. Variants past the recordings are light
pitch and tone changes of them, so no two steps in a row sound the same.
"""
import csv, os, subprocess, sys, wave
import numpy as np

SFX = "assets/audio/sfx"
MANIFEST = "assets/audio/manifest.csv"
RATE = 44100
LICENCE = "Sonniss GDC Game Audio Bundle licence (royalty-free, games allowed, no attribution)"
MIRROR = "https://archive.org/details/gameaudiogdc-part1through7"
TARGET_RMS_DB = -22.0
LENGTH = 0.42  # s

SRC = {
    "conc_a": ("Levan Nadashvili - Soldier Footsteps", "FS Concrete Soldier Crouch N02.flac"),
    "conc_b": ("Levan Nadashvili - Soldier Footsteps", "FS Concrete Soldier Crouch N05.flac"),
    "ground_a": ("Levan Nadashvili - Civilian Footsteps", "FS Ground Civilian Walk N03.flac"),
    "ground_b": ("Levan Nadashvili - Civilian Footsteps", "FS Ground Civilian Walk N05.flac"),
    "wood_a": ("Levan Nadashvili - Civilian Footsteps", "FS Wood Civilian Crouch N03.flac"),
    "wood_b": ("Levan Nadashvili - Civilian Footsteps", "FS Wood Civilian Crouch N05.flac"),
    "metal_a": ("Levan Nadashvili - Soldier Footsteps", "FS Metal Soldier Walk N01.flac"),
    "metal_b": ("Levan Nadashvili - Soldier Footsteps", "FS Metal Soldier Walk N05.flac"),
    "gravel_a": ("PMSFX - STEPS Dirt & Gravel", "PM_SDNG_Single_Step_Footstep_19.flac"),
    "gravel_b": ("PMSFX - STEPS Dirt & Gravel", "PM_SDNG_Single_Step_Footstep_46.flac"),
}

# out stem -> list of (source key, pitch, tilt): tilt > 0 brighter, < 0 duller
OUT = {
    "step_concrete": [("conc_a", 1.0, 0.0), ("conc_b", 1.0, 0.0), ("ground_a", 1.0, 0.0),
                      ("ground_b", 1.0, 0.0), ("conc_a", 0.94, -0.3), ("conc_b", 1.05, 0.2)],
    "step_dirt": [("gravel_a", 1.0, 0.0), ("gravel_b", 1.0, 0.0), ("ground_a", 0.92, -0.5),
                  ("ground_b", 0.95, -0.5), ("gravel_a", 0.94, -0.2), ("gravel_b", 1.05, 0.0)],
    "step_wood": [("wood_a", 1.0, 0.0), ("wood_b", 1.0, 0.0), ("wood_a", 0.95, -0.2), ("wood_b", 1.04, 0.1)],
    "step_metal": [("metal_a", 1.0, 0.0), ("metal_b", 1.0, 0.0), ("metal_a", 0.95, -0.2), ("metal_b", 1.04, 0.0)],
}


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)


def onepole_lp(x, cutoff):
    a = np.exp(-2.0 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    s = 0.0
    for i, v in enumerate(x):
        s = (1 - a) * v + a * s
        y[i] = s
    return y


def shape(x, pitch, tilt):
    if pitch != 1.0:
        n = int(len(x) / pitch)
        x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)
    # Cut from 5 ms before the onset.
    pk = np.max(np.abs(x))
    on = max(int(np.argmax(np.abs(x) > pk * 0.08)) - int(0.005 * RATE), 0)
    x = x[on:on + int(LENGTH * RATE)]
    # High-pass at ~90 Hz (x minus its low band), low-pass at ~7 kHz.
    x = x - onepole_lp(x, 90.0)
    x = onepole_lp(x, 7000.0 if tilt >= 0 else 4500.0)
    if tilt > 0:
        x = x + tilt * (x - onepole_lp(x, 2500.0))
    elif tilt < 0:
        x = (1 + tilt) * x + (-tilt) * onepole_lp(x, 1500.0)
    n = len(x)
    env = np.ones(n)
    fi = int(0.002 * RATE)
    env[:fi] = np.linspace(0, 1, fi)
    fo = int(0.15 * RATE)
    env[n - fo:] = np.linspace(1, 0, fo) ** 2
    x = x * env
    # Loudness over the step itself (first 150 ms carry it).
    body = x[: int(0.15 * RATE)]
    rms = np.sqrt(np.mean(body ** 2))
    x = x * (10 ** (TARGET_RMS_DB / 20) / max(rms, 1e-9))
    pk = np.max(np.abs(x))
    if pk > 0.89:
        x = x * 0.89 / pk
    return x


def write(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def main(folder):
    cache = {k: load(os.path.join(folder, f)) for k, (_, f) in SRC.items()}
    rows = list(csv.reader(open(MANIFEST, newline="")))
    head, body = rows[0], rows[1:]
    stems = set(OUT)
    body = [r for r in body if not any(r[0].startswith("sfx/%s_" % s) for s in stems)]
    for stem, takes in OUT.items():
        for i, (key, pitch, tilt) in enumerate(takes, 1):
            out = "%s_%d.wav" % (stem, i)
            write(os.path.join(SFX, out), shape(cache[key], pitch, tilt))
            pack, fname = SRC[key]
            note = "footstep, boots" + ("" if pitch == 1.0 and tilt == 0.0 else ", pitch x%.2f tone %+.1f" % (pitch, tilt))
            body.append(["sfx/" + out, "Sonniss GDC bundle / %s / %s (%s)" % (pack, fname, MIRROR), LICENCE, note])
            print(out, key, pitch, tilt)
    # Drop any older variants past the new counts (wood had 4, still 4).
    for stem, takes in OUT.items():
        i = len(takes) + 1
        while os.path.exists(os.path.join(SFX, "%s_%d.wav" % (stem, i))):
            os.remove(os.path.join(SFX, "%s_%d.wav" % (stem, i)))
            imp = os.path.join(SFX, "%s_%d.wav.import" % (stem, i))
            if os.path.exists(imp):
                os.remove(imp)
            i += 1
    with open(MANIFEST, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(head)
        w.writerows(body)


if __name__ == "__main__":
    main(sys.argv[1])
