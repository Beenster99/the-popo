#!/usr/bin/env python3
"""Spoken police radio for The Popo (2026-11-23, beenster: "the chatter is
undiscernible"): dispatch reads each job out in a clear voice, and now and
then another unit says something you can make out. Made with Piper
text-to-speech and squeezed through a radio band-pass with ffmpeg.

Lines live in assets/audio/radio/lines.json (shared with
game/audio/police_radio.gd). Needs: pip install piper-tts, the voice models
(.onnx + .onnx.json) from https://huggingface.co/rhasspy/piper-voices in
PIPER_VOICES, and ffmpeg. An ElevenLabs take with the same file name
(assets/audio/radio/<stem>.ogg) can replace any line.
"""
import json
import os
import subprocess
import sys
import tempfile

VOICE_DIR = os.environ.get("PIPER_VOICES", "/tmp/claude-0/voices")
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "audio", "radio")
DISPATCHER = ("en_GB-jenny_dioco-medium", 1.0, "0.95")
UNITS = [("en_GB-alan-medium", 0.98, "0.9"), ("en_US-ryan-high", 0.96, "0.92")]
RADIO = ("highpass=f=320,lowpass=f=3400,equalizer=f=1800:t=q:w=1:g=5,"
         "acompressor=threshold=-26dB:ratio=6:attack=2:release=80:makeup=8,"
         "asoftclip=type=tanh:threshold=0.85,volume=2dB,alimiter=limit=0.9:level=disabled")


def run(cmd, **kw):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **kw)


def say(text, voice, out):
    model, pitch, length = voice
    with tempfile.TemporaryDirectory() as tmp:
        raw = os.path.join(tmp, "raw.wav")
        run([sys.executable, "-m", "piper", "-m", os.path.join(VOICE_DIR, model + ".onnx"), "-f", raw,
             "--length-scale", length], input=text.encode())
        rate = int(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "stream=sample_rate",
                                            "-of", "csv=p=0", raw]).strip())
        af = "asetrate=%d,aresample=44100,%s" % (int(rate * pitch), RADIO)
        run(["ffmpeg", "-y", "-i", raw, "-af", af, "-ac", "1", "-c:a", "libvorbis", "-q:a", "4", out])


def main():
    lines = json.load(open(os.path.join(OUT, "lines.json")))
    only = set(sys.argv[1:])
    for stem, _match, text in lines["dispatch"]:
        if not only or stem in only:
            say(text, DISPATCHER, os.path.join(OUT, stem + ".ogg"))
            print(stem)
    for i, (stem, text) in enumerate(lines["chatter"]):
        if not only or stem in only:
            say(text, UNITS[i % len(UNITS)], os.path.join(OUT, stem + ".ogg"))
            print(stem)


if __name__ == "__main__":
    main()
