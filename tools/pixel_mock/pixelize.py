"""Turn a low-res game render into pixel art: palette + optional Bayer dither,
then nearest-neighbour upscale to the target size."""
import sys
import numpy as np
from PIL import Image

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 - 0.5

# A gritty 32-colour city palette: asphalt greys, brick, sodium orange,
# police blues, blood reds, foliage, skin.
GRITTY = """
0d0e12 1a1c24 2a2d38 3d414f 4a4f5e 565b6b 666d7c 737a89 848c9b 959cab a8b0bc bcc2cc d0d6dc e4e7ea 141a2e 0e1220
2b1d1a 4a2f28 6e4536 925f45 b8835f d8ae86 f0d6b4
1b2a4a 23407a 3566b3 5d93d6 9cc4ee
5a1010 8c1a1a c02a20 e0503a
f0a030 f5d060
1f3a24 335a32 5a8040 8db05a
3a3048 6a5a78 e8c4a0 c89878 a0d8f0 ffffff
"""


def palette(name, img, n):
    if name == "gritty":
        cols = [tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for h in GRITTY.split()]
        return np.array(cols, dtype=np.float32)
    q = img.convert("RGB").quantize(colors=n, method=Image.Quantize.FASTOCTREE, kmeans=3)
    p = np.array(q.getpalette()[: n * 3], dtype=np.float32).reshape(-1, 3)
    # Keep a few key colours the auto palette can lose: skin, hi-vis, blood, flash.
    keys = np.array([[232, 196, 160], [200, 152, 120], [230, 240, 40], [170, 20, 20], [255, 230, 150]], dtype=np.float32)
    return np.concatenate([p, keys])


def apply(src, dst, low_w, low_h, pal, n, dither, out_w, out_h):
    img = Image.open(src).convert("RGB")
    if img.size != (low_w, low_h):
        img = img.resize((low_w, low_h), Image.Resampling.BOX)
    from PIL import ImageEnhance
    img = ImageEnhance.Color(img).enhance(1.35)
    img = ImageEnhance.Contrast(img).enhance(1.15)
    a = np.asarray(img, dtype=np.float32)
    p = palette(pal, img, n)
    if dither > 0:
        h, w = a.shape[:2]
        t = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]
        a = a + t[..., None] * dither
    d = ((a[:, :, None, :] - p[None, None, :, :]) ** 2).sum(-1)
    idx = d.argmin(-1)
    o = p[idx].clip(0, 255).astype(np.uint8)
    Image.fromarray(o).resize((out_w, out_h), Image.Resampling.NEAREST).save(dst)


if __name__ == "__main__":
    src, dst, lw, lh, pal, n, dither = sys.argv[1:8]
    apply(src, dst, int(lw), int(lh), pal, int(n), float(dither), 1280, 720)
