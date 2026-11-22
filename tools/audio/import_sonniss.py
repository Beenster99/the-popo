"""v0.2.11 sound pass (beenster: "It's not a louder gun I am after it's the
full sound pass"): rebuilds the game's sounds from real recordings in the
Sonniss GDC Game Audio Bundles (royalty-free, usable in games, no
attribution needed), replacing the sounds that were synthesised and
upgrading guns, glass, breakage and debris. Adds gore_hit and bone_snap.

The bundle files were fetched from the archive.org mirrors
(gameaudiogdc-part1through7, SonnissGameAudioGDCPart2/4, game-audio-gdc).
Put them, under their original file names, in one folder and run from the
repo root:

    python3 tools/audio/import_sonniss.py <folder>

Each new sound is cut, faded, mixed to mono, and matched to the loudness of
the sound it replaces (so the game's mix holds), then manifest.csv is
updated. Light pitch changes of a real recording are noted in the manifest.
"""
import csv, os, subprocess, sys, wave
import numpy as np

SFX = "assets/audio/sfx"
MANIFEST = "assets/audio/manifest.csv"
RATE = 44100
LICENCE = "Sonniss GDC Game Audio Bundle licence (royalty-free, games allowed, no attribution)"
MIRROR = "https://archive.org/details/gameaudiogdc-part1through7"

# Source files, short key -> (pack, file name)
SRC = {
    "luger": ("Super Thump - Weapons of World War II - Designed", "STDSGN_WoWW2_Wep_Pistol_Luger_Shot_X5.flac"),
    "glock": ("Pole Position Production - Glock 18c", "Glock_18_1m_left_off_axis_MKH416_clean_Six_shots_x_1.flac"),
    "glock_far": ("Pole Position Production - Glock 18c", "Glock_18_75m_behind_Ehrlund_R2_clean_Six_shots_x_1.flac"),
    "beretta": ("Pole Position Production - Beretta 93R 9mm", "Beretta_93R_9mm_1m_left_on_ground_DPA4062_clean_Triple_shots_x_1.flac"),
    "beretta_far": ("Pole Position Production - Beretta 93R 9mm", "Beretta_93R_9mm_25m_behind_DPA4062_R_clean_Triple_shots_x_1.flac"),
    "handgun": ("Olivier Girardot - Hand Guns Sound Effects Pack", "Hand Gun 6.flac"),
    "bimpact": ("Olivier Girardot - Hand Guns Sound Effects Pack", "Bullet Impact 16 - Light Version.flac"),
    "brock": ("Olivier Girardot - Hand Guns Sound Effects Pack", "Bullet rock Impact 4.flac"),
    "whip": ("Olivier Girardot - Hand Guns Sound Effects Pack", "Whip sound 21.flac"),
    "shell_conc": ("Stuart Duffield - Bullet SFX", "ShotgunShell_Land_Concrete_02.flac"),
    "shell_lino": ("Stuart Duffield - Bullet SFX", "ShotgunShell_Land_Lino_03.flac"),
    "casings_wood": ("SculpTunes - Cartridges & Casings Shell", "6 35 GFL - Casings Shell & Cartridges - Drop bounce and roll on Wooden Floor - Outdoor.flac"),
    "shotgun": ("TS Sound - 12 Gauge Shotgun", "Shotgun_Fire_Round Eject_01.flac"),
    "expl_urban": ("BluezoneCorp - Detonation - Explosion", "Bluezone_BC0277_explosion_urban_004_02.flac"),
    "expl_large": ("Bluezone - Tank - Explosion Sound Effects", "Bluezone_BC0271_explosion_outdoors_large_005.flac"),
    "rock_dust": ("Bluezone - Tank - Explosion Sound Effects", "Bluezone_BC0271_debris_falling_rock_dust_002.flac"),
    "pane": ("Soundopolis - Glass Smash Full", "Glass_Break_Pane_702T_Fienup_005.flac"),
    "beer": ("Soundopolis - Glass Smash Full", "Glass_Break_BeerBottle_702T_Fienup_002.flac"),
    "wine": ("Soundopolis - Glass Smash Full", "Glass_Break_WineBottle_702T_Fienup_004.flac"),
    "vase": ("Soundopolis - Glass Smash Full", "Glass_Break_Vase_D50_Fienup_003.flac"),
    "car_glass": ("Coll Anderson - Car Destruction", "EFX EXT Shattered Glass Impact 10 A.flac"),
    "jol_glass": ("Secret Source - 003 Jaws Of Life", "JOL_0707_GlassImpact_02_COMP.flac"),
    "brick": ("Mechanical Wave - Rock Brick and Dirt", "Debris Brick_RBD 02.flac"),
    "rock_drop": ("Mechanical Wave - Rock Brick and Dirt", "Drop Rock On Rock Debris_RBD 03.flac"),
    "rock_hit": ("Mechanical Wave - Rock Brick and Dirt", "Hit Rock Debris_RBD 02.flac"),
    "rock_smash": ("Mechanical Wave - Rock Brick and Dirt", "Smash Rock On Debris_RBD 04.flac"),
    "rock_med": ("Alexander Kopeikin - Rocks", "rock impact medium 26.flac"),
    "rock_tumble": ("Alexander Kopeikin - Rocks", "rock tumble down debris long 06.flac"),
    "soil": ("Alexander Kopeikin - Rocks", "soil and dirt debris heavy 13.flac"),
    "metal_bounce": ("Mechanical Wave - Undoing-Computer", "Bouncing Metal Rattle Scrap Debris_UC 06.flac"),
    "metal_crush": ("Mechanical Wave - Undoing-Computer", "Crush Rattle Metal Scrap Debris_UC 04.flac"),
    "metal_drop": ("Mechanical Wave - Undoing-Computer", "Drop Fall Metal Rattle Scrap Debris_UC 10.flac"),
    "metal_hard": ("Mechanical Wave - Undoing-Computer", "Hit Impact Hard Metal Scrap Debris_UC 01.flac"),
    "metal_small": ("Mechanical Wave - Undoing-Computer", "Hit Impact Metal Scrap Debris_UC 06.flac"),
    "rust": ("Alexander Kopeikin - Black Metal", "dry hard metal impact with rust debris 20.flac"),
    "wood_rattle1": ("Robert Cordova - Base", "Wood Rattle 10.flac"),
    "wood_rattle2": ("Robert Cordova - Base", "Wood Rattle 27.flac"),
    "gore_crunch": ("Timothy McHugh - Gorification [HD]", "gore - crunchy flesh impact and blood squirt - hard -  8.flac"),
    "gore_wet": ("Timothy McHugh - Gorification [HD]", "gore - flesh guts gore impact blood squirt wet - medium - 104.flac"),
    "gore_beat": ("Timothy McHugh - Gorification [HD]", "gore - wood beating flesh wet blood splat - medium - 11.flac"),
    "gore_punch": ("Coll Anderson - Gore", "EFX SD GORE Punch 02 B.M.flac"),
    "gore_snap": ("Coll Anderson - Gore", "EFX SD GORE Snap 05 C.M.flac"),
    "spurt": ("Soundopolis - Gore Toolkit HD", "Punch_Spurt Blood_Fienup_001.flac"),
    "bone18": ("Membrans - Bone Crackings Sound Pack 01", "Bone Cracking 18.flac"),
    "bone34": ("Membrans - Bone Crackings Sound Pack 01", "Bone Cracking 34.flac"),
    "leeks": ("Mattia Cellotto - Crunch Mode", "Leeks,Break,Bone,Crack,Body,Arm13.flac"),
    "swish": ("Mechanical Wave - Hits Whoosh", "Action Swish_HW 02.flac"),
    "fast_swish": ("Mechanical Wave - Hits Whoosh", "Fast Action Swish_HW 05.flac"),
    "rope": ("SoundBits - Just Whoosh 3", "Swoosh_Rope_Whip_075.flac"),
    "lighter": ("Soundopolis - Foley Plus_Full", "Lighter_Blue Flame_E_Light_Fienup_001.flac"),
    "steam": ("The Sound Pack Tree - Trains", "166000 - Steam Blasts.flac"),
    "drift": ("Chupapsound - Megane RS Sport car", "pass by mrs drift.flac"),
}

# stem -> (source, start s, length s, pitch, note). pitch 1 = as recorded.
# lowpass: Hz, for the low-end layers cut from a real shot.
CUTS = [
    ("gun_near_1", "luger", 0.0, 1.8, 1.0, "Luger, close, outdoor tail"),
    ("gun_near_2", "luger", 5.04, 1.8, 1.0, "Luger, close, outdoor tail"),
    ("gun_near_3", "luger", 9.91, 1.8, 1.0, "Luger, close, outdoor tail"),
    ("gun_near_4", "glock", 1.33, 2.3, 1.0, "Glock, 1 m, last shot of a string, outdoor tail"),
    ("gun_near_5", "beretta", 0.41, 2.5, 1.0, "Beretta 93R, 1 m, outdoor tail"),
    ("gun_dry_1", "glock", 0.11, 0.26, 1.0, "Glock, 1 m, tail cut for indoors"),
    ("gun_dry_2", "glock", 0.37, 0.26, 1.0, "Glock, 1 m, tail cut for indoors"),
    ("gun_dry_3", "glock", 0.77, 0.26, 1.0, "Glock, 1 m, tail cut for indoors"),
    ("gun_dry_4", "glock", 1.05, 0.26, 1.0, "Glock, 1 m, tail cut for indoors"),
    ("gun_dry_5", "handgun", 0.0, 0.26, 1.0, "handgun shot, tail cut for indoors"),
    ("gun_far_1", "glock_far", 1.26, 2.4, 1.0, "Glock, 75 m behind"),
    ("gun_far_2", "glock_far", 0.21, 0.27, 1.0, "Glock, 75 m behind, short"),
    ("gun_far_3", "beretta_far", 0.46, 2.5, 1.0, "Beretta 93R, 25 m behind"),
    ("gun_far_4", "beretta_far", 0.13, 0.34, 1.0, "Beretta 93R, 25 m behind, short"),
    ("gun_thump_1", "beretta", 0.41, 0.5, 1.0, "low end of a real Beretta shot (lowpass 220 Hz)", 220),
    ("gun_thump_2", "glock", 1.33, 0.5, 1.0, "low end of a real Glock shot (lowpass 220 Hz)", 220),
    ("gun_thump_3", "luger", 0.0, 0.5, 1.0, "low end of a real Luger shot (lowpass 220 Hz)", 220),
    ("gun_shotgun_body_1", "shotgun", 0.0, 1.6, 1.0, "12 gauge shot"),
    ("gun_shotgun_body_2", "shotgun", 0.0, 1.6, 0.95, "12 gauge shot, pitched down 5%"),
    ("gun_shotgun_body_3", "shotgun", 0.0, 1.6, 1.05, "12 gauge shot, pitched up 5%"),
    ("bullet_crack_1", "whip", 0.08, 0.42, 1.0, "supersonic whip of a near miss"),
    ("bullet_crack_2", "whip", 0.08, 0.42, 1.12, "supersonic whip, pitched up 12%"),
    ("bullet_crack_3", "whip", 0.08, 0.42, 0.9, "supersonic whip, pitched down 10%"),
    ("bullet_whizz_1", "rope", 0.0, 0.9, 1.4, "rope swoosh pitched up 40% for a bullet passing"),
    ("bullet_whizz_2", "fast_swish", 0.6, 0.45, 1.5, "fast swish pitched up 50% for a bullet passing"),
    ("bullet_whizz_3", "rope", 0.0, 0.9, 1.7, "rope swoosh pitched up 70% for a bullet passing"),
    ("impact_concrete_1", "brock", 0.0, 1.0, 1.0, "bullet into rock"),
    ("impact_concrete_2", "bimpact", 0.0, 0.4, 1.0, "bullet impact"),
    ("casing_concrete_1", "shell_conc", 0.0, 0.9, 1.35, "shell landing on concrete, pitched up for a pistol case"),
    ("casing_concrete_2", "shell_conc", 0.0, 0.9, 1.5, "shell landing on concrete, pitched up for a pistol case"),
    ("casing_concrete_3", "shell_conc", 0.0, 0.9, 1.25, "shell landing on concrete, pitched up for a pistol case"),
    ("casing_wood_1", "casings_wood", 0.02, 1.5, 1.0, "case bouncing and rolling on a wooden floor"),
    ("casing_wood_2", "casings_wood", 1.57, 1.5, 1.0, "case bouncing and rolling on a wooden floor"),
    ("casing_wood_3", "casings_wood", 3.39, 1.5, 1.0, "case bouncing and rolling on a wooden floor"),
    ("casing_metal_1", "metal_drop", 0.13, 0.6, 1.8, "small metal rattle, pitched up for a case on metal"),
    ("casing_metal_2", "metal_small", 0.0, 0.7, 1.9, "small metal hit, pitched up for a case on metal"),
    ("casing_metal_3", "casings_wood", 4.87, 1.5, 1.25, "case bounce, pitched up"),
    ("mag_drop_concrete_1", "metal_small", 0.27, 0.7, 1.0, "small metal object dropping"),
    ("mag_drop_concrete_2", "metal_drop", 0.41, 0.5, 1.0, "small metal object dropping"),
    ("mag_drop_metal_1", "metal_bounce", 0.06, 0.7, 1.0, "metal bouncing on metal"),
    ("mag_drop_metal_2", "metal_bounce", 0.76, 0.9, 1.0, "metal bouncing on metal"),
    ("mag_drop_wood_1", "wood_rattle1", 0.0, 0.6, 1.0, "wooden rattle"),
    ("mag_drop_wood_2", "wood_rattle2", 0.0, 0.8, 1.0, "wooden rattle"),
    ("whoosh_1", "swish", 0.17, 0.6, 1.0, "swing through the air"),
    ("whoosh_2", "fast_swish", 0.6, 0.45, 1.0, "swing through the air"),
    ("whoosh_3", "rope", 0.0, 1.0, 1.0, "swing through the air"),
    ("explosion_body_1", "expl_urban", 0.0, 4.0, 1.0, "urban explosion"),
    ("explosion_body_2", "expl_large", 0.0, 3.6, 1.0, "large outdoor explosion"),
    ("fire_whoomph_1", "lighter", 1.08, 1.2, 0.5, "lighter flame catching, pitched down an octave"),
    ("fire_whoomph_2", "steam", 0.0, 1.5, 0.6, "steam blast pitched down for flames catching"),
    ("gas_hiss_1", "steam", 2.62, 1.8, 1.0, "steam blast for a bursting extinguisher"),
    ("tyre_skid_1", "drift", 7.9, 4.0, 1.0, "car drifting, loops"),
    ("glass_break_1", "pane", 0.0, 2.3, 1.0, "window pane smashing"),
    ("glass_break_2", "wine", 0.18, 2.1, 1.0, "bottle smashing"),
    ("glass_break_3", "beer", 0.15, 2.5, 1.0, "bottle smashing"),
    ("glass_big_1", "vase", 0.0, 3.0, 1.0, "big glass smash"),
    ("glass_big_2", "car_glass", 0.5, 3.0, 1.0, "car glass shattering"),
    ("glass_big_3", "jol_glass", 0.0, 2.6, 1.0, "glass impact and shatter"),
    ("break_concrete_1", "rock_smash", 0.05, 2.6, 1.0, "rock smashing onto debris"),
    ("break_concrete_2", "rock_drop", 0.44, 2.6, 1.0, "rock dropping on rock debris"),
    ("break_concrete_3", "rock_med", 0.08, 3.2, 1.0, "rock impact"),
    ("break_concrete_4", "brick", 0.04, 1.2, 1.0, "brick debris"),
    ("rubble_1", "rock_tumble", 0.15, 2.6, 1.0, "rocks tumbling"),
    ("rubble_2", "rock_tumble", 2.7, 2.6, 1.0, "rocks tumbling"),
    ("rubble_3", "soil", 0.03, 2.2, 1.0, "soil and dirt falling"),
    ("rubble_4", "rock_dust", 0.09, 2.4, 1.0, "rock and dust falling"),
    ("rubble_5", "rock_hit", 0.11, 1.8, 1.0, "rock debris"),
    ("rubble_6", "rock_drop", 1.89, 1.2, 1.0, "rock debris"),
    ("break_metal_1", "metal_hard", 0.21, 1.8, 1.0, "hard metal scrap hit"),
    ("break_metal_2", "metal_hard", 3.97, 2.0, 1.0, "hard metal scrap hit"),
    ("break_metal_3", "metal_crush", 0.04, 1.7, 1.0, "metal crushing and rattling"),
    ("break_metal_4", "rust", 0.09, 2.5, 1.0, "metal impact with rust debris"),
    ("break_metal_5", "metal_bounce", 0.0, 2.3, 1.0, "metal scrap bouncing"),
    ("gore_hit_1", "gore_crunch", 0.06, 1.0, 1.0, "bullet into a body: crunch and blood squirt"),
    ("gore_hit_2", "gore_wet", 0.1, 1.0, 1.0, "bullet into a body: wet impact"),
    ("gore_hit_3", "spurt", 0.0, 0.6, 1.0, "bullet into a body: hit and spurt"),
    ("gore_hit_4", "gore_beat", 0.04, 1.0, 1.0, "bullet into a body: wet splat"),
    ("gore_hit_5", "gore_punch", 0.01, 0.6, 1.0, "bullet into a body: gore punch"),
    ("bone_snap_1", "bone18", 0.19, 0.3, 1.0, "bone cracking"),
    ("bone_snap_2", "bone34", 0.24, 0.5, 1.0, "bone cracking"),
    ("bone_snap_3", "leeks", 0.14, 1.0, 1.0, "bone breaking"),
    ("bone_snap_4", "gore_snap", 0.48, 1.2, 1.0, "gore snap"),
]
# New stems take the loudness of an existing one.
LOUDNESS_LIKE = {"gore_hit": "body_hit_1", "bone_snap": "body_hit_2"}


def decode(path):
    out = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(RATE),
                          "-f", "s16le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(out, np.int16).astype(np.float64) / 32768.0


def read_wav(path):
    with wave.open(path) as w:
        ch, rate = w.getnchannels(), w.getframerate()
        x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float64) / 32768.0
    return (x.reshape(-1, ch).mean(axis=1) if ch > 1 else x), rate


def loud50(x):
    win = int(RATE * 0.05)
    if len(x) < win:
        return 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-9)
    sq = np.convolve(x ** 2, np.ones(win) / win, mode="valid")
    return 10 * np.log10(sq.max() + 1e-12)


def _pole(x, a):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def lowpass(x, hz):
    # One-pole filter forwards then backwards, twice: gentle, no phase smear.
    a = np.exp(-2 * np.pi * hz / RATE)
    for _ in range(2):
        x = _pole(_pole(x, a)[::-1], a)[::-1]
    return x


def cut(x, start, length, pitch):
    s = int(start * RATE)
    n = int(length * RATE * pitch)
    seg = x[s:s + n]
    if pitch != 1.0:
        t = np.arange(0, len(seg) - 1, pitch)
        seg = np.interp(t, np.arange(len(seg)), seg)
    fi = min(int(0.002 * RATE), len(seg))
    fo = min(int(max(0.03, len(seg) / RATE * 0.3) * RATE), len(seg))
    seg = seg.copy()
    seg[:fi] *= np.linspace(0, 1, fi)
    seg[-fo:] *= np.linspace(1, 0, fo) ** 2
    return seg


def write(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def main(folder):
    cache = {}
    rows = list(csv.reader(open(MANIFEST, newline="")))
    head, body = rows[0], rows[1:]
    by_file = {r[0]: r for r in body}
    for c in CUTS:
        stem, key, start, length, pitch, note = c[:6]
        if key not in cache:
            cache[key] = decode(os.path.join(folder, SRC[key][1]))
        seg = cut(cache[key], start, length, pitch)
        if len(c) > 6:
            seg = lowpass(seg, c[6])
        out = os.path.join(SFX, stem + ".wav")
        ref = out if os.path.exists(out) else os.path.join(SFX, LOUDNESS_LIKE[stem.rsplit("_", 1)[0]] + ".wav")
        target = loud50(read_wav(ref)[0])
        seg *= 10 ** ((target - loud50(seg)) / 20)
        peak = np.abs(seg).max()
        if peak > 0.89:  # soft-clip only what goes over -1 dBFS
            seg = np.tanh(seg / 0.89 * 1.2) / np.tanh(1.2) * 0.89
        write(out, seg)
        pack, name = SRC[key]
        rel = "sfx/" + stem + ".wav"
        by_file[rel] = [rel, f"Sonniss GDC bundle / {pack} / {name} ({MIRROR})", LICENCE, note]
        print(f"{stem:22s} {len(seg) / RATE:4.2f}s  {target:6.1f} dB  <- {name}")
    with open(MANIFEST, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(head)
        order = [r[0] for r in body] + [k for k in by_file if k not in {r[0] for r in body}]
        for k in order:
            w.writerow(by_file[k])


if __name__ == "__main__":
    main(sys.argv[1])
