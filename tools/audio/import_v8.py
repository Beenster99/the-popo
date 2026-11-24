"""v0.13.1 (beenster: "police cars should have beefy V8 sound"): the police
cars' engine from a real V8, a 2014 Camaro ZL1 (6.2 litre supercharged V8)
recorded by Pole Position Production in the Sonniss GDC 2020 bundle
(royalty-free, games allowed, no attribution), via the archive.org mirror
gameaudiogdc-part1through7.

    v8_idle   ticking over, from the exhaust mic (the lumpy V8 burble)
    v8_drive  held steady at about 1,250 rpm, the low end lifted; the game
              pitches it up with speed and gear, and crossfades from idle

Put the two source files, under their original names, in one folder and run
from the repo root (on a clean checkout: levels match car_engine_1):

    python3 tools/audio/import_v8.py <folder>
"""
import csv, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import import_pack1 as P

LICENCE = "Sonniss GDC Game Audio Bundle licence (royalty-free, games allowed, no attribution)"
MIRROR = "https://archive.org/details/gameaudiogdc-part1through7"
PACK = "Sonniss GDC 2020 / Pole Position - Camaro ZL1 2014 / "
IDLE = "Camaro_ZL1_t11_Onbrd_On_Idle_Blips_Off_Exhaust_Mix.flac"
DRIVE = "Camaro_ZL1_t7_Onbrd_Start_Idle_Blips_Steady_in_Neutral_Off_Engine_Intake_DPA4062.flac"
# stem, file, start, length, low-end lift (dB), extra trim (dB), note
CUTS = [
    ("v8_idle_1", IDLE, 69.0, 8.0, 3.0, 4.0, "V8 idling, exhaust (looped)"),
    ("v8_drive_1", DRIVE, 160.5, 10.0, 6.0, 5.0, "V8 held at about 1,250 rpm, low end lifted (looped)"),
]


def main():
    folder = sys.argv[1]
    ref = P.read(os.path.join(P.SFX, "car_engine_1.wav"))
    rows = []
    for stem, f, start, length, lift, trim, note in CUTS:
        x = P.decode(os.path.join(folder, f))
        seg = P.cut(x, start, length, 1.0, 0.01)
        seg = seg + P.lowpass(seg, 220.0) * (10 ** (lift / 20) - 1.0)
        seg = P.make_loop(seg, 0.5)
        seg *= 10 ** ((P.rms_db(ref) - P.rms_db(seg) + trim) / 20)
        pk = np.abs(seg).max()
        if pk > 0.97:
            seg *= 0.97 / pk
        P.write(os.path.join(P.SFX, stem + ".wav"), seg)
        rows.append(["sfx/%s.wav" % stem, "%s%s (%s)" % (PACK, f, MIRROR), LICENCE,
                     "%s (start %.1f s, %.1f s long)" % (note, start, length)])
        print(stem)
    with open(P.MANIFEST, newline="") as fh:
        old = list(csv.reader(fh))
    done = {r[0] for r in rows}
    out = [old[0]] + [r for r in old[1:] if r and r[0] not in done] + rows
    with open(P.MANIFEST, "w", newline="") as fh:
        csv.writer(fh, lineterminator="\n").writerows(out)


if __name__ == "__main__":
    main()
