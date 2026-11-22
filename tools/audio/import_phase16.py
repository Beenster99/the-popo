"""Phase 1.6: imports the everyday and destruction sounds from CC0 packs on
OpenGameArt (all public domain), next to the guns and impacts that
import_cc0.py brought in.

Download each pack and unpack it into one folder, keeping its name:
  footsteps-0/                01..06-footstep*.ogg      https://opengameart.org/content/footsteps-0
  Fantozzi-footsteps/         (7z)                      https://opengameart.org/content/fantozzis-footsteps-grasssand-stone
  RPGsounds_Kenney/           (zip, Kenney)             https://opengameart.org/content/50-rpg-sound-effects
  qubodupPunch/               (7z)                      https://opengameart.org/content/punch
  independent_nu_ljudbank-hits_and_punches/  (7z)       https://opengameart.org/content/37-hitspunches
  car_sound_effects_pack/     (zip)                     https://opengameart.org/content/car-sound-effects-pack-low-quality
  qubodup-crash.ogg                                     https://opengameart.org/content/crash-collision
  reload.wav                                            https://opengameart.org/content/handgun-reload-sound-effect
  shotguncock_0.wav                                     https://opengameart.org/content/gun-reload-sounds
  "gatve Varniu_2.ogg"                                  https://opengameart.org/content/high-traffic-road-sounds
  amb_outdoor1_loop.ogg                                 https://opengameart.org/content/amb-outside-1
  sfx_100_v2/                 (zip)                     https://opengameart.org/content/100-cc0-sfx-2
  100-CC0-wood-metal-SFX/     (zip)                     https://opengameart.org/content/100-cc0-metal-and-wood-sfx
  sfx_breaking_and_falling/   (zip)                     https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx
  100-CC0-SFX_0/              (zip)                     https://opengameart.org/content/100-cc0-sfx
  woodcrack/wood_impact/      (7z of 35 wooden cracks)  https://opengameart.org/content/35-wooden-crackshitsdestructions

    python3 tools/audio/import_phase16.py <source folder>      (needs ffmpeg and numpy)

One-shots are trimmed of silence and peak-normalised; the game sets their
levels. Loops (ambience, engine) are cut to length and crossfaded end into
start so they loop without a click. Everything becomes 16-bit mono 44.1 kHz
WAV in assets/audio/sfx/ and is added to assets/audio/manifest.csv.
"""
import csv, os, subprocess, sys
import numpy as np

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "assets", "audio", "sfx")
MANIFEST = os.path.join(ROOT, "assets", "audio", "manifest.csv")
OGA = "https://opengameart.org/content/"
CC0 = "CC0 1.0 (public domain)"
K = "RPGsounds_Kenney/OGG/"
V2 = "sfx_100_v2/"
WM = "100-CC0-wood-metal-SFX/"
BF = "sfx_breaking_and_falling/"
FZ = "Fantozzi-footsteps/Fantozzi-footsteps/ogg/"
HP = "independent_nu_ljudbank-hits_and_punches/hits/"

# stem: [(file, page, note, start, end)]  (start/end in seconds, None = all)
ONE_SHOTS = {
    "step_concrete": [(FZ + f"Fantozzi-Stone{s}{i}.ogg", "fantozzis-footsteps-grasssand-stone", "footstep, stone", None, None)
                      for s in "LR" for i in (1, 2, 3)],
    "step_wood": [(V2 + f"sfx100v2_footstep_wood_0{i}.ogg", "100-cc0-sfx-2", "footstep, wood", None, None) for i in (1, 2, 3, 4)],
    "step_dirt": [(FZ + f"Fantozzi-Sand{s}{i}.ogg", "fantozzis-footsteps-grasssand-stone", "footstep, sand/grass", None, None)
                  for s in "LR" for i in (1, 2, 3)],
    "gear": [(K + n, "50-rpg-sound-effects", "belt and kit rattle (Kenney)", None, None)
             for n in ("beltHandle1.ogg", "beltHandle2.ogg", "clothBelt.ogg", "clothBelt2.ogg")],
    "cloth": [(K + f"cloth{i}.ogg", "50-rpg-sound-effects", "cloth movement (Kenney)", None, None) for i in (1, 2, 3, 4)],
    "holster": [(K + n, "50-rpg-sound-effects", "leather holster (Kenney)", None, None)
                for n in ("handleSmallLeather.ogg", "handleSmallLeather2.ogg")],
    "dry_fire": [(K + "metalClick.ogg", "50-rpg-sound-effects", "trigger click on empty (Kenney)", None, None)],
    "gun_mech": [(K + "metalLatch.ogg", "50-rpg-sound-effects", "slide cycling (Kenney)", None, None)],
    "door_open": [(K + f"doorOpen_{i}.ogg", "50-rpg-sound-effects", "door opening (Kenney)", None, None) for i in (1, 2)],
    "door_close": [(K + f"doorClose_{i}.ogg", "50-rpg-sound-effects", "door closing (Kenney)", None, None) for i in (1, 2, 3, 4)],
    "punch": [(f"qubodupPunch/qubodupPunch/qubodupPunch0{i}.ogg", "punch", "punch", None, None) for i in (1, 2, 3, 4, 5)],
    "body_hit": [(HP + f"hit{i:02d}.mp3.flac", "37-hitspunches", "hit on a body", None, None) for i in (1, 4, 8, 12, 16, 20)],
    "mag_out": [("reload.wav", "handgun-reload-sound-effect", "magazine release", 0.06, 0.52)],
    "mag_in": [("reload.wav", "handgun-reload-sound-effect", "magazine seated", 0.56, 0.98)],
    "slide_rack": [("reload.wav", "handgun-reload-sound-effect", "slide racked", 0.99, None)],
    "shotgun_pump": [("shotguncock_0.wav", "gun-reload-sounds", "pump shotgun racked", None, None)],
    "break_wood": [(f"woodcrack/wood_impact/crack0{i}.mp3.flac", "35-wooden-crackshitsdestructions", "wood cracking", None, None) for i in (1, 2, 3)]
                  + [(BF + f"bfh1_wood_breaking_0{i}.ogg", "75-cc0-breaking-falling-hit-sfx", "wood breaking", None, None) for i in (1, 2, 3, 4)],
    "break_concrete": [(BF + f"bfh1_rock_breaking_0{i}.ogg", "75-cc0-breaking-falling-hit-sfx", "concrete breaking", None, None) for i in (1, 2, 3)]
                      + [(BF + "bfh1_breaking_01.ogg", "75-cc0-breaking-falling-hit-sfx", "breaking", None, None)],
    "rubble": [(BF + f"bfh1_rock_falling_0{i}.ogg", "75-cc0-breaking-falling-hit-sfx", "rubble falling", None, None) for i in (1, 2, 3, 4, 5, 6)],
    "break_metal": [(BF + f"bfh1_metal_falling_0{i}.ogg", "75-cc0-breaking-falling-hit-sfx", "metal falling", None, None) for i in (1, 2, 3, 4)]
                   + [(WM + "metal_slam_01.ogg", "100-cc0-metal-and-wood-sfx", "metal slam", None, None)],
    "glass_settle": [(BF + f"bfh1_glass_falling_0{i}.ogg", "75-cc0-breaking-falling-hit-sfx", "glass shards falling", None, None) for i in (1, 2, 3, 4)],
    "glass_big": [(BF + f"bfh1_glass_breaking_0{i}.ogg", "75-cc0-breaking-falling-hit-sfx", "big pane breaking", None, None) for i in (4, 5, 6)],
    "car_crash": [("qubodup-crash.ogg", "crash-collision", "car crash", None, None),
                  (BF + "bfh1_metal_hit_06.ogg", "75-cc0-breaking-falling-hit-sfx", "metal crunch", None, None),
                  (WM + "metal_sheet_01.ogg", "100-cc0-metal-and-wood-sfx", "sheet metal", None, None)],
    "car_door_open": [("car_sound_effects_pack/Car_Door_Open.ogg", "car-sound-effects-pack-low-quality", "car door opening", None, None)],
    "car_door_close": [("car_sound_effects_pack/Car_Door_Close.ogg", "car-sound-effects-pack-low-quality", "car door shutting", None, None)],
    "explosion": [("100-CC0-SFX_0/explosion.ogg", "100-cc0-sfx", "explosion", None, None)],
    "car_start": [("car_sound_effects_pack/Car_Engine_Start_Up.ogg", "car-sound-effects-pack-low-quality", "engine starting", None, None)],
}
# stem: (file, page, note, start, length)
LOOPS = {
    "car_engine": ("car_sound_effects_pack/Car_Engine_Loop.ogg", "car-sound-effects-pack-low-quality", "engine idle loop", 0.0, 2.9),
    "amb_street": ("gatve Varniu_2.ogg", "high-traffic-road-sounds", "busy street loop", 2.0, 40.0),
    "amb_air": ("amb_outdoor1_loop.ogg", "amb-outside-1", "outdoor air, birds", 0.0, 29.8),
    "amb_far_traffic": (V2 + "sfx100v2_loop_highway.ogg", "100-cc0-sfx-2", "distant highway", 0.0, 16.6),
}


def load(path):
    raw = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "s16le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0


def write(path, x):
    x = np.clip(x, -1.0, 1.0)
    data = (x * 32767.0).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "pcm_s16le", path], input=data, check=True)


def trim(x, floor_db=-50.0):
    a = np.abs(x)
    thr = a.max() * 10 ** (floor_db / 20.0)
    idx = np.where(a > thr)[0]
    if len(idx) == 0:
        return x
    s = max(0, idx[0] - int(0.003 * SR))
    e = min(len(x), idx[-1] + int(0.02 * SR))
    y = x[s:e].copy()
    f = min(len(y) // 4, int(0.01 * SR))
    if f > 0:
        y[-f:] *= np.linspace(1, 0, f)
    return y


def normalise(x, peak_db=-1.0):
    m = np.abs(x).max()
    return x if m <= 0 else x * (10 ** (peak_db / 20.0) / m)


def make_loop(x, fade=0.5):
    n = int(fade * SR)
    body = x[:-n].copy()
    tail = x[-n:]
    w = np.linspace(0, 1, n)
    body[:n] = body[:n] * w + tail * (1 - w)
    return body


def main(src):
    rows = list(csv.reader(open(MANIFEST)))
    have = {r[0]: i for i, r in enumerate(rows)}
    def add(name, file, page, note):
        row = [f"sfx/{name}", f"{file} ({OGA}{page})", CC0, note]
        if row[0] in have:
            rows[have[row[0]]] = row
        else:
            have[row[0]] = len(rows)
            rows.append(row)
    for stem, items in ONE_SHOTS.items():
        for i, (f, page, note, s, e) in enumerate(items, 1):
            x = load(os.path.join(src, f))
            if s is not None or e is not None:
                x = x[int((s or 0) * SR): int(e * SR) if e else None]
            x = normalise(trim(x))
            write(os.path.join(OUT, f"{stem}_{i}.wav"), x)
            add(f"{stem}_{i}.wav", f, page, note)
    for stem, (f, page, note, s, length) in LOOPS.items():
        x = load(os.path.join(src, f))
        x = x[int(s * SR): int((s + length) * SR)]
        x = normalise(make_loop(x), -3.0)
        write(os.path.join(OUT, f"{stem}_1.wav"), x)
        add(f"{stem}_1.wav", f, page, note + ", loops")
    with open(MANIFEST, "w", newline="") as fh:
        csv.writer(fh, lineterminator="\n").writerows(rows)
    print("imported", sum(len(v) for v in ONE_SHOTS.values()) + len(LOOPS), "sounds")


if __name__ == "__main__":
    main(sys.argv[1])
