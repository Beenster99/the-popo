"""Tiling detail textures for the building kit (v0.25, beenster 2026-11-24:
"All building materials should have textures to help represent what they
are").

Each is near-white so the game's colour (and each building's tint) still
sets the colour; the texture adds the pattern. Alpha 0 marks mortar or
grout, which the cel shader draws in a fixed light grey whatever the tint.
Deterministic: run it again and the PNGs come out the same.

    python3 tools/textures/make_kit_textures.py
"""
import os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "textures", "kit")
N = 512


def rng(seed):
    return np.random.default_rng(seed)


def value_noise(r, size, cells):
    """Tileable smooth noise, 0..1."""
    g = r.random((cells, cells))
    x = np.linspace(0, cells, size, endpoint=False)
    i = np.floor(x).astype(int)
    f = x - i
    f = f * f * (3 - 2 * f)
    i1 = (i + 1) % cells
    a = g[np.ix_(i, i)]
    b = g[np.ix_(i, i1)]
    c = g[np.ix_(i1, i)]
    d = g[np.ix_(i1, i1)]
    fx = f[None, :]
    fy = f[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(r, size, base=4, octaves=5):
    out = np.zeros((size, size))
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        out += value_noise(r, size, base * 2 ** o) * amp
        tot += amp
        amp *= 0.5
    return out / tot


def save(name, rgb, alpha=None):
    rgb = np.clip(rgb, 0, 1)
    if rgb.ndim == 2:
        rgb = np.stack([rgb] * 3, -1)
    if alpha is None:
        alpha = np.ones(rgb.shape[:2])
    img = np.concatenate([rgb, np.clip(alpha, 0, 1)[..., None]], -1)
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + ".png"), optimize=True)


def bond(size, cols, rows, mortar_px, stagger=0.5):
    """Running bond: brick id per pixel and a mortar mask (1 = mortar)."""
    y, x = np.mgrid[0:size, 0:size]
    rh = size / rows
    cw = size / cols
    row = (y // rh).astype(int)
    xo = (x + (row % 2) * stagger * cw) % size
    col = (xo // cw).astype(int)
    my = (y % rh) < mortar_px
    mx = (xo % cw) < mortar_px
    return row * 1000 + col, (my | mx)


def per_id(r, ids, lo, hi):
    u, inv = np.unique(ids, return_inverse=True)
    v = r.uniform(lo, hi, len(u))
    return v[inv].reshape(ids.shape)


def brick():
    r = rng(11)
    ids, mortar = bond(N, 4, 13, 7)
    base = per_id(r, ids, 0.72, 0.98)
    speck = fbm(r, N, 32, 3)
    rgb = np.stack([base, base * 0.97, base * 0.94], -1) * (0.85 + 0.25 * speck)[..., None]
    # Darker fired edges.
    y, x = np.mgrid[0:N, 0:N]
    edge = np.minimum((y % (N / 13)), (N / 13) - (y % (N / 13))) < 10
    rgb[edge & ~mortar] *= 0.92
    grout = 0.8 + 0.2 * fbm(r, N, 64, 2)
    rgb[mortar] = np.stack([grout] * 3, -1)[mortar]
    save("brick", rgb, 1.0 - mortar)


def stone():
    r = rng(12)
    ids, joint = bond(N, 4, 8, 4)
    base = per_id(r, ids, 0.84, 1.0)
    tool = fbm(r, N, 16, 5)
    rgb = base * (0.88 + 0.16 * tool)
    rgb = np.stack([rgb, rgb * 0.99, rgb * 0.96], -1)
    save("stone", rgb, 1.0 - joint)


def concrete():
    r = rng(13)
    n = fbm(r, N, 8, 6)
    rgb = 0.86 + 0.14 * n
    # Rain streaks down from the top.
    streak = value_noise(r, N, 64)[0:1, :].repeat(N, 0)
    rgb -= 0.06 * np.clip(streak - 0.55, 0, 1) * 3 * np.linspace(1, 0.3, N)[:, None]
    y, x = np.mgrid[0:N, 0:N]
    # Panel joints (the tile is 4 m: one every 2 m across, one every 1.5 m up).
    rgb[(x % (N // 2)) < 3] *= 0.7
    rgb[(y % (N * 3 // 8)) < 3] *= 0.75
    # Form-tie holes on a 0.5 m grid.
    s = N // 8
    hx = (x + s // 2) % s - s // 2
    hy = (y + s // 2) % s - s // 2
    rgb[(hx * hx + hy * hy) < 16] *= 0.6
    rgb += (r.random((N, N)) - 0.5) * 0.05
    save("concrete", rgb)


def plaster():
    r = rng(14)
    n = fbm(r, N, 6, 6)
    rgb = 0.93 + 0.07 * n
    trowel = fbm(r, N, 24, 3)
    rgb -= 0.03 * (trowel > 0.62)
    save("plaster", np.stack([rgb, rgb, rgb * 0.98], -1))


def floor_tiles():
    r = rng(15)
    y, x = np.mgrid[0:N, 0:N]
    s = N // 4   # 0.5 m tiles on a 2 m texture
    ids = (y // s) * 10 + (x // s)
    base = per_id(r, ids, 0.9, 1.0)
    rgb = base * (0.95 + 0.05 * fbm(r, N, 32, 3))
    grout = ((x % s) < 3) | ((y % s) < 3)
    rgb[grout] *= 0.8
    save("floor", rgb)


def roof():
    r = rng(16)
    g = fbm(r, N, 64, 3)
    rgb = 0.78 + 0.3 * g + (r.random((N, N)) - 0.5) * 0.25
    # Felt sheets with lapped seams every 1 m.
    y, x = np.mgrid[0:N, 0:N]
    rgb[(y % (N // 2)) < 4] *= 0.75
    save("roof", rgb)


def pavement():
    r = rng(17)
    y, x = np.mgrid[0:N, 0:N]
    s = N // 3   # three slabs across 2 m
    row = y // s
    xo = (x + (row % 2) * (s // 2)) % N
    ids = row * 10 + xo // s
    base = per_id(r, ids, 0.88, 1.0)
    rgb = base * (0.88 + 0.14 * fbm(r, N, 16, 5)) + (r.random((N, N)) - 0.5) * 0.06
    grout = ((xo % s) < 4) | ((y % s) < 4)
    # A cracked slab or two.
    crack = np.zeros((N, N), bool)
    for k in range(3):
        cx, cy = r.integers(0, N, 2)
        p = np.array([cx, cy], float)
        d = r.normal(size=2)
        d /= np.linalg.norm(d)
        for t in range(140):
            d += r.normal(size=2) * 0.25
            d /= np.linalg.norm(d)
            p = (p + d * 1.5) % N
            crack[int(p[1]), int(p[0])] = True
    rgb[crack] *= 0.6
    save("pavement", rgb, 1.0 - grout)


def asphalt():
    r = rng(18)
    rgb = 0.8 + 0.25 * fbm(r, N, 32, 4) + (r.random((N, N)) - 0.5) * 0.35
    stones = r.random((N, N)) > 0.985
    rgb[stones] += 0.35
    # Patch repairs.
    for k in range(3):
        x0, y0 = r.integers(0, N - 120, 2)
        w, h = r.integers(50, 120, 2)
        rgb[y0:y0 + h, x0:x0 + w] *= 0.92
    save("asphalt", rgb)


def wood():
    r = rng(19)
    y, x = np.mgrid[0:N, 0:N]
    planks = 6
    pw = N / planks
    pid = (x // pw).astype(int)
    base = per_id(r, pid, 0.82, 1.0)
    warp = fbm(r, N, 4, 3) * 40
    grain = np.sin((x + warp + pid * 37) * 0.35 + fbm(r, N, 8, 3) * 6) * 0.5 + 0.5
    rgb = base * (0.82 + 0.18 * grain)
    rgb[(x % pw) < 3] *= 0.65
    save("wood", np.stack([rgb, rgb * 0.97, rgb * 0.93], -1))


def metal():
    r = rng(20)
    y, x = np.mgrid[0:N, 0:N]
    p = N // 10   # slats 0.1 m apart (garage doors, shutters)
    t = (y % p) / p
    rib = 0.88 + 0.12 * np.cos(t * 2 * np.pi)
    brushed = value_noise(r, N, 256)[:, 0:1].repeat(N, 1) * 0.06
    rgb = rib + brushed - 0.04 + (r.random((N, N)) - 0.5) * 0.03
    scratch = fbm(r, N, 48, 2) > 0.74
    rgb[scratch] += 0.08
    save("metal", rgb)


def rubble():
    r = rng(21)
    n = fbm(r, N, 16, 5)
    rgb = 0.75 + 0.3 * n + (r.random((N, N)) - 0.5) * 0.3
    pores = r.random((N, N)) > 0.992
    rgb[pores] *= 0.4
    save("rubble", rgb)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for f in [brick, stone, concrete, plaster, floor_tiles, roof, pavement, asphalt, wood, metal, rubble]:
        f()
    print("textures in", os.path.abspath(OUT))
