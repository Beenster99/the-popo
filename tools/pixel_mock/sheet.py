import sys, os
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixelize
D = os.path.dirname(os.path.abspath(__file__))
OUT = "/mnt/project-files/screens/pixel-art/"
os.makedirs(OUT, exist_ok=True)
try:
    F = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
except Exception:
    F = ImageFont.load_default()
NAMES = {"street": "Street, day", "shootout": "Shootout", "night": "Street, night", "inside": "Office interior"}
for shot in sys.argv[1:]:
    rows = [("Current look", Image.open(f"{D}/full/{shot}.png").convert("RGB").resize((960, 540), Image.Resampling.LANCZOS))]
    pixelize.apply(f"{D}/low/{shot}.png", f"{OUT}{shot}_pixel_clean.png", 480, 270, "adaptive", 40, 6, 1920, 1080)
    rows.append(("Pixel A: clean, 480x270, 40 colours", Image.open(f"{OUT}{shot}_pixel_clean.png").resize((960, 540), Image.Resampling.NEAREST)))
    if os.path.exists(f"{D}/tiny/{shot}.png"):
        pixelize.apply(f"{D}/tiny/{shot}.png", f"{OUT}{shot}_pixel_retro.png", 320, 180, "gritty", 0, 12, 1920, 1080)
        rows.append(("Pixel B: retro, 320x180, fixed palette + dither", Image.open(f"{OUT}{shot}_pixel_retro.png").resize((960, 540), Image.Resampling.NEAREST)))
    H = 40
    sheet = Image.new("RGB", (960, len(rows) * (540 + H)), (18, 18, 22))
    d = ImageDraw.Draw(sheet)
    for i, (label, im) in enumerate(rows):
        y = i * (540 + H)
        d.text((12, y + 8), f"{NAMES[shot]}: {label}", fill=(235, 235, 235), font=F)
        sheet.paste(im, (0, y + H))
    sheet.save(f"{OUT}compare_{shot}.png")
    print("sheet", shot, len(rows))
