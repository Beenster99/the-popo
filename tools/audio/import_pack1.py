"""v0.13.0: beenster's own Sound Pack 1 (made in ElevenLabs, 2026-11-24).

Cuts, trims, levels and drives the pack's takes into the game's stems,
replacing stand-ins (synthesised or borrowed sounds) and adding the new
families the gun pass uses:

    gun_9mm_near   9 mm handguns, close, with their outdoor tail
    gun_9mm_room   9 mm fired inside a room (beenster's "in room" takes)
    gun_heavy_near the heavy pistols (.45, .357): Desert Eagle takes
    gun_heavy_mid  the heavy pistols heard down a street (slapback and all)
    gun_heavy_room heavy pistol cut dry for the indoor reverb
    gun_shotgun_near / gun_shotgun_room   the sawn-off
    gun_smg        one round of the machine pistol, sliced from Uzi bursts
    collapse       a building coming down (12 s)
    tyre_chirp     a short tyre squeal when a skid starts
    car_idle       an engine ticking over (loops)
    shell_shotgun  a spent shotgun shell hitting the floor

Run from the repo root, with the pack unzipped in <folder>:

    python3 tools/audio/import_pack1.py <folder>

Run it on a clean checkout: it reads the loudness of the sounds it replaces
first, so a second run would match the new sounds instead of the old ones.

Every cut is faded, mixed to mono at 44.1 kHz and levelled: gunshots are
driven into a soft clipper so they sit hot (loud without the limiter
having to squash them), everything else is matched to the loudness of the
sound it replaces so the mix holds. manifest.csv is updated.
"""
import csv, glob, os, subprocess, sys, wave
import numpy as np

SFX = "assets/audio/sfx"
VOICE = "assets/audio/voice"
MANIFEST = "assets/audio/manifest.csv"
RATE = 44100
LICENCE = "Made by beenster for The Popo (ElevenLabs Sound Effects), Sound Pack 1"

# Short key -> file name pattern in the pack.
SRC = {
    "p9_1": "Single_9mm_pistol_sh_#1-*", "p9_2": "Single_9mm_pistol_sh_#2-*",
    "p9_3": "Single_9mm_pistol_sh_#3-*", "p9_4": "Single_9mm_pistol_sh_#4-*",
    "gf_1": "gun_fire_pistol_#1-*", "gf_2": "gun_fire_pistol_#2-*",
    "gf_3": "gun_fire_pistol_#3-*", "gf_4": "gun_fire_pistol_#4-*",
    "dt_1": "pistol_double_tap_fi_#1-*", "dt_2": "pistol_double_tap_fi_#2-*",
    "dt_3": "pistol_double_tap_fi_#3-*",
    "room_1": "in_room_pistol_gunsh_#1-*", "room_2": "in_room_pistol_gunsh_#2-*",
    "room_3": "in_room_pistol_gunsh_#3-*", "room_4": "in_room_pistol_gunsh_#4-*",
    "de_1": "desert_eagle_gunshot_#1-*", "de_2": "desert_eagle_gunshot_#2-*",
    "de_3": "desert_eagle_gunshot_#3-*", "de_4": "desert_eagle_gunshot_#4-*",
    "def_1": "desert_eagle_fired_a_#1-*", "def_2": "desert_eagle_fired_a_#2-*",
    "def_3": "desert_eagle_fired_a_#3-*", "def_4": "desert_eagle_fired_a_#4-*",
    "sg_1": "shotgun_shot_#1-*", "sg_2": "shotgun_shot_#2-*", "sg_3": "shotgun_shot_#3-*", "sg_4": "shotgun_shot_#4-*",
    "pump_1": "shotgun_pump_action__#1-*", "pump_2": "shotgun_pump_action__#2-*",
    "pump_3": "shotgun_pump_action__#3-*", "pump_4": "shotgun_pump_action__#4-*",
    "sshell_1": "shotgun_shells_hittiing floor#1-*", "sshell_2": "shotgun_shells_hittiing floor_#2-*",
    "sshell_3": "shotgun_shells_hittiing floor#3-*", "sshell_4": "shotgun_shells_hittiing floor#4-*",
    "pshell_1": "pistol_shells_hittin_#1-*", "pshell_2": "pistol_shells_hittin_#2-*",
    "pshell_3": "pistol_shells_hittin_#3-*", "pshell_4": "pistol_shells_hittin_#4-*",
    "uzi_1": "9mm_uzi_machine_gun__#1-1795529650439.wav", "uzi_2": "9mm_uzi_machine_gun__#1-1795529650439 (1).wav",
    "uzi_3": "9mm_uzi_machine_gun__#3-*", "uzi_4": "9mm_uzi_machine_gun__#4-*",
    "snipe_3": "sniper_shot_from_dis_#3-*", "snipe_4": "sniper_shot_from_dis_#4-*",
    "whizz_1": "bullet_whizz_#1-*", "whizz_2": "bullet_whizz_#2-*", "whizz_3": "bullet_whizz_#3-*", "whizz_4": "bullet_whizz_#4-*",
    "ric_1": "bullet_ricochet_off__#1-*", "ric_2": "bullet_ricochet_off__#2-*",
    "ric_3": "bullet_ricochet_off__#3-*", "ric_4": "bullet_ricochet_off__#4-*",
    "wood_1": "bullet_hitting_wood_#1-*", "wood_2": "bullet_hitting_wood_#2-*",
    "wood_3": "bullet_hitting_wood_#3-*", "wood_4": "bullet_hitting_wood_#4-*",
    "conc_3": "bullet_hitting_concr_#3-*", "conc_4": "bullet_hitting_concr_#4-*",
    "gren_1": "grenade_explosion_#1-*", "gren_2": "grenade_explosion_#2-*",
    "gren_3": "grenade_explosion_#3-*", "gren_4": "grenade_explosion_#4-*",
    "flash_1": "flashbang_crack_bang_#1-*", "flash_2": "flashbang_crack_bang_#2-*",
    "flash_3": "flashbang_crack_bang_#3-*", "flash_4": "flashbang_crack_bang_#4-*",
    "gas_1": "gas_grenade_canister_#1-*", "gas_2": "gas_grenade_canister_#2-*",
    "gas_3": "gas_grenade_canister_#3-*", "gas_4": "gas_grenade_canister_#4-*",
    "pane_1": "shattering_glass_pan_#1-*", "pane_2": "shattering_glass_pan_#2-*",
    "pane_3": "shattering_glass_pan_#3-*", "pane_4": "shattering_glass_pan_#4-*",
    "brick_1": "lots_of_bricks_and_r_#1-*", "brick_2": "lots_of_bricks_and_r_#2-*",
    "brick_3": "lots_of_bricks_and_r_#3-*", "brick_4": "lots_of_bricks_and_r_#4-*",
    "fall_1": "building_falling_dow_#1-*", "fall_2": "building_falling_dow_#2-*",
    "fall_3": "building_falling_dow_#3-*", "fall_4": "building_falling_dow_#4-*",
    "start_1": "car_startup_#1-*", "start_2": "car_startup_#2-*", "start_3": "car_startup_#3-*", "start_4": "car_startup_#4-*",
    "tick_1": "car_engine_ticking_o_#1-*",
    "skid_1": "car_skid_#1-*", "skid_2": "car_skid_#2-*", "skid_3": "car_skid_#3-*", "skid_4": "car_skid_#4-*",
    "beep_1": "police_radio_beep_#1-*", "beep_2": "police_radio_beep_#2-*",
    "beep_3": "police_radio_beep_#3-*", "beep_4": "police_radio_beep_#4-*",
    "sq_1": "police_radio_squelch_#1-1795530405863.wav", "sq_4": "police_radio_squelch_#4-1795530405864.mp3",
    "sqs_1": "police_radio_squelch_#1-1795530437161.wav", "sqs_4": "police_radio_squelch_#4-1795530437162.wav",
    "stand_1": "stand down 1.mp3", "stand_2": "stand down 2.mp3",
}

A = None   # start "at the first transient"
# (out stem, source, start s (A = auto), length s, pitch, note, options)
# options: hot (dB of drive into the soft clipper: the gun families),
# like (stem to match loudness to), hp (high-pass Hz), lp (low-pass Hz),
# loop (crossfade seconds: a seamless loop), fade_in (s).
GUN = {"hot": 7.0}
GUN_ROOM = {"hot": 6.0}
CUTS = [
    # 9 mm: close, with the outdoor tail.
    ("gun_9mm_near_1", "p9_1", A, 1.6, 1.0, "single 9 mm shot", GUN),
    ("gun_9mm_near_2", "p9_2", A, 1.4, 1.0, "single 9 mm shot", GUN),
    ("gun_9mm_near_3", "p9_3", A, 1.4, 1.0, "single 9 mm shot", GUN),
    ("gun_9mm_near_4", "gf_1", A, 1.4, 1.0, "pistol shot", GUN),
    ("gun_9mm_near_5", "gf_2", A, 2.0, 1.0, "pistol shot, long street tail", GUN),
    ("gun_9mm_near_6", "gf_3", A, 1.4, 1.0, "pistol shot", GUN),
    ("gun_9mm_near_7", "gf_4", A, 1.6, 1.0, "pistol shot", GUN),
    ("gun_9mm_near_8", "dt_1", 0.185, 1.4, 1.0, "second shot of a double tap", GUN),
    ("gun_9mm_near_9", "dt_2", 0.180, 1.4, 1.0, "second shot of a double tap", GUN),
    ("gun_9mm_near_10", "dt_3", 0.915, 1.3, 1.0, "last shot of a double tap", GUN),
    # 9 mm inside a room.
    ("gun_9mm_room_1", "room_1", A, 1.1, 1.0, "pistol shot in a room", GUN_ROOM),
    ("gun_9mm_room_2", "room_2", A, 0.9, 1.0, "pistol shot in a room", GUN_ROOM),
    ("gun_9mm_room_3", "room_3", A, 1.1, 1.0, "pistol shot in a room", GUN_ROOM),
    ("gun_9mm_room_4", "room_4", A, 0.8, 1.0, "pistol shot in a room", GUN_ROOM),
    # Heavy pistols.
    ("gun_heavy_near_1", "de_2", A, 2.0, 1.0, "Desert Eagle shot", GUN),
    ("gun_heavy_near_2", "de_3", A, 2.0, 1.0, "Desert Eagle shot", GUN),
    ("gun_heavy_near_3", "de_4", A, 2.0, 1.0, "Desert Eagle shot", GUN),
    ("gun_heavy_mid_1", "def_1", A, 2.0, 1.0, "Desert Eagle down a street", {"hot": 4.0}),
    ("gun_heavy_mid_2", "def_2", A, 1.9, 1.0, "Desert Eagle down a street", {"hot": 4.0}),
    ("gun_heavy_mid_3", "def_3", A, 2.0, 1.0, "Desert Eagle down a street", {"hot": 4.0}),
    ("gun_heavy_mid_4", "def_4", A, 2.0, 1.0, "Desert Eagle down a street", {"hot": 4.0}),
    ("gun_heavy_room_1", "de_2", A, 0.32, 1.0, "Desert Eagle, tail cut for the room reverb", GUN_ROOM),
    ("gun_heavy_room_2", "de_3", A, 0.32, 1.0, "Desert Eagle, tail cut for the room reverb", GUN_ROOM),
    ("gun_heavy_room_3", "de_4", A, 0.32, 1.0, "Desert Eagle, tail cut for the room reverb", GUN_ROOM),
    ("gun_heavy_room_4", "room_3", A, 1.1, 0.82, "pistol in a room, pitched down 18% for a heavy round", GUN_ROOM),
    # The sawn-off.
    ("gun_shotgun_near_1", "sg_1", A, 1.6, 1.0, "shotgun shot", GUN),
    ("gun_shotgun_near_2", "sg_2", A, 1.6, 1.0, "shotgun shot", GUN),
    ("gun_shotgun_near_3", "sg_3", A, 1.7, 1.0, "shotgun shot", GUN),
    ("gun_shotgun_near_4", "sg_4", A, 1.6, 1.0, "shotgun shot", GUN),
    ("gun_shotgun_room_1", "sg_1", A, 0.38, 1.0, "shotgun, tail cut for the room reverb", GUN_ROOM),
    ("gun_shotgun_room_2", "sg_2", A, 0.38, 1.0, "shotgun, tail cut for the room reverb", GUN_ROOM),
    ("gun_shotgun_room_3", "sg_3", A, 0.38, 1.0, "shotgun, tail cut for the room reverb", GUN_ROOM),
    ("gun_shotgun_room_4", "sg_4", A, 0.38, 1.0, "shotgun, tail cut for the room reverb", GUN_ROOM),
    ("shotgun_pump_1", "pump_1", A, 0.42, 1.0, "pump racked", {"like": "shotgun_pump_1"}),
    ("shotgun_pump_2", "pump_2", A, 0.42, 1.0, "pump racked", {"like": "shotgun_pump_1"}),
    ("shotgun_pump_3", "pump_3", A, 0.38, 1.0, "pump racked", {"like": "shotgun_pump_1"}),
    ("shotgun_pump_4", "pump_4", A, 0.42, 1.0, "pump racked", {"like": "shotgun_pump_1"}),
    ("shell_shotgun_1", "sshell_1", A, 1.2, 1.0, "shotgun shell hitting the floor", {"like": "casing_concrete_1"}),
    ("shell_shotgun_2", "sshell_2", A, 1.0, 1.0, "shotgun shell hitting the floor", {"like": "casing_concrete_1"}),
    ("shell_shotgun_3", "sshell_3", A, 1.2, 1.0, "shotgun shell hitting the floor", {"like": "casing_concrete_1"}),
    ("shell_shotgun_4", "sshell_4", A, 1.0, 1.0, "shotgun shell hitting the floor", {"like": "casing_concrete_1"}),
    ("casing_concrete_1", "pshell_1", A, 0.9, 1.0, "pistol case hitting the floor", {"like": "casing_concrete_1"}),
    ("casing_concrete_2", "pshell_2", A, 0.7, 1.0, "pistol case hitting the floor", {"like": "casing_concrete_1"}),
    ("casing_concrete_3", "pshell_3", A, 1.0, 1.0, "pistol case hitting the floor", {"like": "casing_concrete_1"}),
    ("casing_concrete_4", "pshell_4", A, 0.8, 1.0, "pistol case hitting the floor", {"like": "casing_concrete_1"}),
    # Machine pistol: single rounds sliced out of Uzi bursts (each ends
    # before the next round's attack; in sustained fire they overlap).
    ("gun_smg_1", "uzi_4", 0.24, 0.088, 1.0, "one round from a burst", GUN),
    ("gun_smg_2", "uzi_4", 0.512, 0.088, 1.0, "one round from a burst", GUN),
    ("gun_smg_3", "uzi_4", 0.885, 0.088, 1.0, "one round from a burst", GUN),
    ("gun_smg_4", "uzi_4", 1.355, 0.088, 1.0, "one round from a burst", GUN),
    ("gun_smg_5", "uzi_4", 1.735, 0.088, 1.0, "one round from a burst", GUN),
    ("gun_smg_6", "uzi_1", 0.305, 0.088, 1.0, "one round from a burst", GUN),
    ("gun_smg_7", "uzi_1", 0.40, 0.088, 1.0, "one round from a burst", GUN),
    ("gun_smg_8", "uzi_3", 0.275, 0.07, 1.0, "one round from a burst", GUN),
    # Far away.
    ("gun_far_5", "snipe_3", A, 1.0, 1.0, "shot from a distance", {"like": "gun_far_1"}),
    ("gun_far_6", "snipe_4", A, 1.0, 1.0, "shot from a distance", {"like": "gun_far_1"}),
    ("gun_far_7", "p9_4", A, 2.2, 1.0, "thin 9 mm shot used as a far one", {"like": "gun_far_1"}),
    ("gun_far_8", "de_1", A, 2.4, 1.0, "soft Desert Eagle take used as a far one", {"like": "gun_far_1"}),
    # Bullets.
    ("bullet_whizz_1", "whizz_1", A, 0.6, 1.0, "bullet whizzing past", {"like": "bullet_whizz_1"}),
    ("bullet_whizz_2", "whizz_2", A, 0.7, 1.0, "bullet whizzing past", {"like": "bullet_whizz_1"}),
    ("bullet_whizz_3", "whizz_3", A, 0.5, 1.0, "bullet whizzing past", {"like": "bullet_whizz_1"}),
    ("bullet_whizz_4", "whizz_4", A, 0.95, 1.0, "bullet whizzing past", {"like": "bullet_whizz_1"}),
    ("ricochet_1", "ric_1", A, 1.2, 1.0, "ricochet off concrete", {"like": "impact_concrete_1", "trim": -4.0}),
    ("ricochet_2", "ric_2", A, 1.2, 1.0, "ricochet off concrete", {"like": "impact_concrete_1", "trim": -4.0}),
    ("ricochet_3", "ric_3", A, 1.2, 1.0, "ricochet off concrete", {"like": "impact_concrete_1", "trim": -4.0}),
    ("ricochet_4", "ric_4", A, 1.2, 1.0, "ricochet off concrete", {"like": "impact_concrete_1", "trim": -4.0}),
    ("impact_wood_1", "wood_1", A, 0.9, 1.0, "bullet into wood", {"like": "impact_concrete_1"}),
    ("impact_wood_2", "wood_2", A, 0.9, 1.0, "bullet into wood", {"like": "impact_concrete_1"}),
    ("impact_wood_3", "wood_3", A, 0.8, 1.0, "bullet into wood", {"like": "impact_concrete_1"}),
    ("impact_wood_4", "wood_4", A, 0.8, 1.0, "bullet into wood", {"like": "impact_concrete_1"}),
    ("impact_concrete_3", "conc_3", A, 0.9, 1.0, "bullet into concrete", {"like": "impact_concrete_1"}),
    ("impact_concrete_4", "conc_4", A, 1.0, 1.0, "bullet into concrete", {"like": "impact_concrete_1"}),
    # Grenades and blasts.
    ("explosion_1", "gren_1", A, 2.4, 1.0, "grenade explosion", {"hot": 5.0}),
    ("explosion_2", "gren_2", A, 2.1, 1.0, "grenade explosion", {"hot": 5.0}),
    ("explosion_3", "gren_3", A, 2.1, 1.0, "grenade explosion", {"hot": 5.0}),
    ("explosion_4", "gren_4", A, 2.2, 1.0, "grenade explosion", {"hot": 5.0}),
    ("frag_crack_1", "gren_2", A, 0.9, 1.08, "front of a grenade blast, high-passed: the casing cracking", {"hot": 5.0, "hp": 400}),
    ("frag_crack_2", "gren_3", A, 0.9, 1.08, "front of a grenade blast, high-passed: the casing cracking", {"hot": 5.0, "hp": 400}),
    ("flashbang_1", "flash_1", A, 2.3, 1.0, "flashbang", {"hot": 6.0}),
    ("flashbang_2", "flash_2", A, 2.3, 1.0, "flashbang", {"hot": 6.0}),
    ("flashbang_3", "flash_3", A, 2.3, 1.0, "flashbang", {"hot": 6.0}),
    ("flashbang_4", "flash_4", A, 2.5, 1.0, "flashbang", {"hot": 6.0}),
    ("smoke_pop_1", "gas_1", A, 0.75, 1.0, "gas canister popping", {"like": "smoke_pop_1", "trim": 3.0}),
    ("smoke_pop_2", "gas_3", A, 0.75, 1.0, "gas canister popping", {"like": "smoke_pop_1", "trim": 3.0}),
    ("smoke_hiss_1", "gas_1", 0.75, 3.7, 1.0, "gas canister pouring out (looped)", {"like": "smoke_hiss_1", "loop": 0.6, "rms": True, "hp": 120}),
    ("nade_bounce_1", "gas_2", 1.015, 0.16, 1.0, "canister bouncing", {"like": "nade_bounce_1", "trim": 6.0}),
    ("nade_bounce_2", "gas_2", 2.005, 0.16, 1.0, "canister bouncing", {"like": "nade_bounce_1", "trim": 6.0}),
    ("nade_bounce_3", "gas_4", 0.175, 0.16, 1.0, "canister bouncing", {"like": "nade_bounce_1", "trim": 6.0}),
    ("nade_bounce_4", "gas_4", 1.765, 0.16, 1.0, "canister bouncing", {"like": "nade_bounce_1", "trim": 6.0}),
    ("nade_bounce_5", "gas_4", 3.155, 0.16, 1.0, "canister bouncing", {"like": "nade_bounce_1", "trim": 6.0}),
    # Glass and rubble.
    ("glass_break_1", "pane_1", A, 1.9, 1.0, "window pane shattering", {"like": "glass_break_1"}),
    ("glass_break_2", "pane_2", A, 1.6, 1.0, "window pane shattering", {"like": "glass_break_1"}),
    ("glass_break_3", "pane_3", A, 1.7, 1.0, "window pane shattering", {"like": "glass_break_1"}),
    ("glass_break_4", "pane_4", A, 2.1, 1.0, "window pane shattering", {"like": "glass_break_1"}),
    ("glass_big_4", "pane_1", A, 2.2, 0.85, "window pane shattering, pitched down for a shop front", {"like": "glass_big_1"}),
    ("glass_big_5", "pane_4", A, 2.4, 0.85, "window pane shattering, pitched down for a shop front", {"like": "glass_big_1"}),
    ("rubble_7", "brick_1", A, 2.0, 1.0, "bricks and rubble falling", {"like": "rubble_1"}),
    ("rubble_8", "brick_2", A, 1.9, 1.0, "bricks and rubble falling", {"like": "rubble_1"}),
    ("rubble_9", "brick_3", A, 2.2, 1.0, "bricks and rubble falling", {"like": "rubble_1"}),
    ("rubble_10", "brick_4", A, 1.9, 1.0, "bricks and rubble falling", {"like": "rubble_1"}),
    ("collapse_1", "fall_1", A, 10.5, 1.0, "building falling down", {"like": "explosion_body_1", "trim": -2.0}),
    ("collapse_2", "fall_2", A, 11.0, 1.0, "building falling down", {"like": "explosion_body_1", "trim": -2.0}),
    ("collapse_3", "fall_3", A, 10.5, 1.0, "building falling down", {"like": "explosion_body_1", "trim": -2.0}),
    ("collapse_4", "fall_4", A, 10.5, 1.0, "building falling down", {"like": "explosion_body_1", "trim": -2.0}),
    # Cars.
    ("car_start_1", "start_1", 0.0, 2.5, 1.0, "car starting", {"like": "car_start_1"}),
    ("car_start_2", "start_2", 0.0, 2.5, 1.0, "car starting", {"like": "car_start_1"}),
    ("car_start_3", "start_3", 0.0, 2.5, 1.0, "car starting", {"like": "car_start_1"}),
    ("car_start_4", "start_4", 0.0, 2.5, 1.0, "car starting", {"like": "car_start_1"}),
    ("car_idle_1", "tick_1", 0.0, 2.0, 1.0, "engine ticking over (looped)", {"like": "car_engine_1", "loop": 0.35, "rms": True}),
    ("tyre_chirp_1", "skid_1", A, 1.0, 1.0, "tyre squeal", {"like": "tyre_skid_1"}),
    ("tyre_chirp_2", "skid_2", A, 1.0, 1.0, "tyre squeal", {"like": "tyre_skid_1"}),
    ("tyre_chirp_3", "skid_3", A, 1.0, 1.0, "tyre squeal", {"like": "tyre_skid_1"}),
    ("tyre_chirp_4", "skid_4", A, 0.98, 1.0, "tyre squeal", {"like": "tyre_skid_1"}),
    # The radio on your shoulder: key-up click and squelch, and the static
    # and click as the talker lets go. (The pack's longer squelches have
    # garbled talk in them, which beenster asked to keep off the radio.)
    ("radio_key_1", "sq_1", 0.10, 0.32, 1.0, "radio keying up", {"like": "radio_key_1"}),
    ("radio_key_2", "sq_4", 0.03, 0.32, 1.0, "radio keying up", {"like": "radio_key_1"}),
    ("radio_key_3", "sqs_1", 0.0, 0.3, 1.0, "radio keying up", {"like": "radio_key_1"}),
    ("radio_unkey_1", "beep_1", 0.58, 0.42, 1.0, "static and the click as the talker lets go", {"like": "radio_unkey_1", "fade_in": 0.08, "keep_end": True}),
    ("radio_unkey_2", "beep_2", 0.58, 0.42, 1.0, "static and the click as the talker lets go", {"like": "radio_unkey_1", "fade_in": 0.08, "keep_end": True}),
    ("radio_unkey_3", "beep_3", 0.58, 0.42, 1.0, "static and the click as the talker lets go", {"like": "radio_unkey_1", "fade_in": 0.08, "keep_end": True}),
    ("radio_unkey_4", "beep_4", 0.58, 0.42, 1.0, "static and the click as the talker lets go", {"like": "radio_unkey_1", "fade_in": 0.08, "keep_end": True}),
]
# Officer voice lines (ogg, in assets/audio/voice).
VOICE_CUTS = [
    ("stand_down_1", "stand_1", "drop_weapon_1"),
    ("stand_down_2", "stand_2", "drop_weapon_2"),
]


def decode(path):
    out = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(RATE),
                          "-f", "f32le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(out, np.float32).astype(np.float64)


def loud50(x):
    win = int(RATE * 0.05)
    if len(x) < win:
        return 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-9)
    sq = np.convolve(x ** 2, np.ones(win) / win, mode="valid")
    return 10 * np.log10(sq.max() + 1e-12)


def rms_db(x):
    return 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)


def onset(x):
    """The first moment within 30 dB of the loudest 5 ms, less 4 ms."""
    n = int(RATE * 0.005)
    k = len(x) // n
    e = 20 * np.log10(np.sqrt((x[:k * n].reshape(k, n) ** 2).mean(1)) + 1e-9)
    i = int(np.argmax(e > e.max() - 30))
    return max(0.0, i * 0.005 - 0.004)


def _pole(x, a):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def lowpass(x, hz):
    a = np.exp(-2 * np.pi * hz / RATE)
    for _ in range(2):
        x = _pole(_pole(x, a)[::-1], a)[::-1]
    return x


def highpass(x, hz):
    return x - lowpass(x, hz)


def cut(x, start, length, pitch, fade_in=0.002, keep_end=False):
    s = int(start * RATE)
    n = int(length * RATE * pitch)
    seg = x[s:s + n].copy()
    if pitch != 1.0:
        t = np.arange(0, len(seg) - 1, pitch)
        seg = np.interp(t, np.arange(len(seg)), seg)
    fi = min(int(fade_in * RATE), len(seg))
    seg[:fi] *= np.linspace(0, 1, fi)
    fo = int((0.004 if keep_end else max(0.012, min(0.35, len(seg) / RATE * 0.3))) * RATE)
    fo = min(fo, len(seg))
    seg[-fo:] *= np.linspace(1, 0, fo) ** 2
    return seg


def make_loop(seg, xf):
    """Crossfades the end into the start so the sound loops seamlessly."""
    n = int(xf * RATE)
    body = seg[n:].copy()
    head = seg[:n]
    t = np.linspace(0, 1, n)
    body[-n:] = body[-n:] * np.sqrt(1 - t) + head * np.sqrt(t)
    return body


def drive(seg, db):
    """Peak-normalise, push db into a soft clipper, normalise to -0.3 dBFS:
    hotter and denser, the transient rounded rather than chopped."""
    seg = seg / (np.abs(seg).max() + 1e-9)
    g = 10 ** (db / 20)
    seg = np.tanh(seg * g) / np.tanh(g)
    return seg * 10 ** (-0.3 / 20)


def write(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def read(path):
    with wave.open(path) as w:
        ch = w.getnchannels()
        x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float64) / 32768.0
    return x.reshape(-1, ch).mean(axis=1) if ch > 1 else x


def find(folder, pat):
    hits = glob.glob(os.path.join(glob.escape(folder), pat.replace("[", "[[]")))
    if len(hits) != 1:
        raise SystemExit("expected one file for %r, found %r" % (pat, hits))
    return hits[0]


def main():
    folder = sys.argv[1]
    # Reference loudness from the sounds being replaced, read before any are written.
    refs = {}
    for c in CUTS:
        like = c[6].get("like")
        if like and like not in refs:
            refs[like] = read(os.path.join(SFX, like + ".wav"))
    srcs = {}
    rows = []
    for stem, key, start, length, pitch, note, opt in CUTS:
        if key not in srcs:
            srcs[key] = decode(find(folder, SRC[key]))
        x = srcs[key]
        st = onset(x) if start is None else start
        seg = cut(x, st, length, pitch, opt.get("fade_in", 0.002), opt.get("keep_end", False))
        if "hp" in opt:
            seg = highpass(seg, opt["hp"])
        if "loop" in opt:
            seg = make_loop(seg, opt["loop"])
        if "hot" in opt:
            seg = drive(seg, opt["hot"])
        else:
            ref = refs[opt["like"]]
            if opt.get("rms"):
                gain = rms_db(ref) - rms_db(seg)
            else:
                gain = loud50(ref) - loud50(seg)
            seg = seg * 10 ** ((gain + opt.get("trim", 0.0)) / 20)
            pk = np.abs(seg).max()
            if pk > 0.97:
                seg *= 0.97 / pk
        write(os.path.join(SFX, stem + ".wav"), seg)
        how = "start %.3f s, %.2f s long" % (st, length)
        if pitch != 1.0:
            how += ", pitch x%.2f" % pitch
        rows.append(["sfx/%s.wav" % stem, "Sound Pack 1 / " + os.path.basename(find(folder, SRC[key])),
                     LICENCE, "%s (%s)" % (note, how)])
        print(stem, how)
    # Voice lines: matched to an existing officer line, written as ogg.
    for stem, key, like in VOICE_CUTS:
        x = decode(find(folder, SRC[key]))
        st = max(0.0, onset(x) - 0.02)
        seg = cut(x, st, len(x) / RATE - st, 1.0, 0.01)
        ref = decode(os.path.join(VOICE, like + ".ogg"))
        seg *= 10 ** ((rms_db(ref[np.abs(ref) > 0.01]) - rms_db(seg[np.abs(seg) > 0.01])) / 20)
        pk = np.abs(seg).max()
        if pk > 0.97:
            seg *= 0.97 / pk
        tmp = os.path.join(VOICE, stem + ".tmp.wav")
        write(tmp, seg)
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", "6",
                        os.path.join(VOICE, stem + ".ogg")], check=True)
        os.remove(tmp)
        rows.append(["voice/%s.ogg" % stem, "Sound Pack 1 / " + SRC[key], LICENCE,
                     '"Stand down, put the gun on the floor and we can all walk out of here happy."'])
        print(stem)
    # manifest: replace rows for the same files, keep the rest.
    with open(MANIFEST, newline="") as f:
        old = list(csv.reader(f))
    done = {r[0] for r in rows}
    out = [old[0]] + [r for r in old[1:] if r and r[0] not in done] + rows
    with open(MANIFEST, "w", newline="") as f:
        csv.writer(f, lineterminator="\n").writerows(out)


if __name__ == "__main__":
    main()
