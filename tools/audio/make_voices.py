#!/usr/bin/env python3
"""Placeholder shouted voice lines for The Popo (officer orders and suspect
replies), made with Piper text-to-speech and pushed hard with ffmpeg so they
sound shouted. beenster's ElevenLabs takes replace them: drop a file with
the same name into assets/audio/voice/ (see the list in
/mnt/project-files/sound/elevenlabs-sound-list.md).

Needs: pip install piper-tts, the voice models (.onnx + .onnx.json) from
https://huggingface.co/rhasspy/piper-voices in VOICE_DIR, and ffmpeg.

The line ids and stems must match game/audio/voices.gd LINES.
"""
import os
import subprocess
import sys
import tempfile

VOICE_DIR = os.environ.get("PIPER_VOICES", "/tmp/claude-0/voices")
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "voice")

# (stem, text, who) in the order of Voices.LINES.
LINES = [
    ("drop_weapon", "Police! Drop the weapon!", "cop"),
    ("drop_it", "Drop it! Drop it now!", "cop"),
    ("gun_down", "Put the gun down! Now!", "cop"),
    ("hands_head", "Hands on your head!", "cop"),
    ("get_down", "Get down on the ground!", "cop"),
    ("knees", "On your knees! Hands where I can see them!", "cop"),
    ("hold_it", "Hold it right there!", "cop"),
    ("stop_police", "Stop! Police!", "cop"),
    ("dont_move", "Don't move!", "cop"),
    ("desist", "Desist! Desist now!", "cop"),
    ("popo", "This is the Popo!", "cop"),
    ("nobody_move", "Police! Nobody move!", "cop"),
    ("stay", "Stay right there!", "cop"),
    ("sit_tight", "Sit down. Don't you move.", "cop"),
    ("with_me", "With me. Move it!", "cop"),
    ("walk", "Up you get. Walk with me.", "cop"),
    ("ok_ok", "Okay, okay! Don't shoot!", "crook"),
    ("give_up", "Alright, I give up!", "crook"),
    ("easy", "Easy! Easy! I'm doing it!", "crook"),
    ("pig", "Get lost, pig!", "crook"),
    ("never", "You'll never take me alive!", "crook"),
    ("make_me", "Make me!", "crook"),
    ("lawyer", "I want my lawyer!", "crook"),
    ("brutality", "This is police brutality!", "crook"),
    ("stopping", "Alright! Alright! I'm stopping!", "crook"),
    # (stand_down is beenster's own take, Sound Pack 1.)
    ("warn_police", "Police! Leg it!", "crook"),
    ("warn_feds", "Feds! Feds are here!", "crook"),
    ("warn_bill", "Old Bill! Move, move!", "crook"),
]

# Three officer voices (one per player) and three for crooks: model, pitch.
VOICES = {
    "cop": [("en_GB-alan-medium", 1.04), ("en_GB-northern_english_male-medium", 1.03), ("en_US-ryan-high", 1.02)],
    "crook": [("en_US-joe-medium", 0.97), ("en_GB-northern_english_male-medium", 0.9), ("en_GB-alan-medium", 0.88)],
}

SHOUT = ("highpass=f=170,equalizer=f=2400:t=q:w=1.2:g=7,equalizer=f=250:t=q:w=1:g=-3,"
         "acompressor=threshold=-24dB:ratio=8:attack=3:release=60:makeup=10,"
         "asoftclip=type=tanh:threshold=0.8,aecho=0.85:0.5:35|70:0.18|0.08,"
         "volume=7dB,alimiter=limit=0.93:level=disabled,afade=t=out:st={fade}:d=0.08")


def run(cmd, **kw):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **kw)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    with tempfile.TemporaryDirectory() as tmp:
        for stem, text, who in LINES:
            if only and stem not in only:
                continue
            for i, (model, pitch) in enumerate(VOICES[who], 1):
                raw = os.path.join(tmp, "raw.wav")
                run([sys.executable, "-m", "piper", "-m", os.path.join(VOICE_DIR, model + ".onnx"), "-f", raw,
                     "--length-scale", "0.82" if who == "cop" else "0.9", "--noise-scale", "0.8"],
                    input=text.encode())
                rate = int(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "stream=sample_rate",
                                                    "-of", "csv=p=0", raw]).strip())
                dur = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                                     "-of", "csv=p=0", raw]).strip()) / pitch
                af = "asetrate=%d,aresample=44100,%s" % (int(rate * pitch), SHOUT.format(fade=max(0.0, dur - 0.05)))
                out = os.path.join(OUT, "%s_%d.ogg" % (stem, i))
                run(["ffmpeg", "-y", "-i", raw, "-af", af, "-ac", "1", "-c:a", "libvorbis", "-q:a", "5", out])
                print(out)


if __name__ == "__main__":
    main()
