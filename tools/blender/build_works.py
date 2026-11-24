"""Repair crews (beenster, 2026-11-24): the council's works vehicles and kit,
one glb each in assets/models/works/:

  works_lorry   rigid 8-wheel flatbed: flat-fronted cab with a beacon bar and
                rear chevrons, headboard, side guards, and a load the game
                takes off a piece at a time (load_slab_0..5, load_beam_0..3)
  crane_truck   all-terrain mobile crane: low carrier with a cab out front,
                outriggers that slide out (outrigger_fl/fr/rl/rr, with jacks),
                and the superstructure on a turntable (slew), its boom pivot
                (boom) and telescopic sections (boom_1..boom_4, boom_head)
  works_kit     hook block, drill, angle grinder, welding torch and visor,
                shovel, broom, bucket, trestles, generator, barrier, sign

Godot axes (x right, y up, z forward), ground at y = 0; turned into
Blender's in g2b. Pivots are empties so the game can turn them.

    python tools/blender/build_works.py [works_lorry|crane_truck|works_kit ...]
"""
import math
import os
import sys

import bpy  # noqa: I001

sys.path.insert(0, os.path.dirname(__file__))
import common as C  # noqa: E402
import build_vehicles as V  # noqa: E402

YELLOW = (0.96, 0.72, 0.04)
WHITE = (0.92, 0.92, 0.9)
ORANGE = (0.98, 0.42, 0.04)
RED = (0.75, 0.08, 0.06)
OXIDE = (0.48, 0.16, 0.09)
CONCRETE = (0.62, 0.61, 0.58)
TIMBER = (0.58, 0.42, 0.24)
STEEL = (0.5, 0.52, 0.55)
DARK = (0.1, 0.1, 0.11)
BLACK = (0.05, 0.05, 0.06)
GLASS = (0.12, 0.17, 0.22)
AMBER = (1.0, 0.6, 0.05)
LAMP = (1.0, 0.96, 0.8)
TAIL = (0.7, 0.05, 0.05)
BLUE = (0.1, 0.25, 0.7)
GREEN = (0.15, 0.45, 0.2)

mat = V.mat
gbox = V.gbox
quad = V.quad
cyl = V.cyl
attach = V.attach
g2b = V.g2b


def empty(name, at, parent=None):
    e = bpy.data.objects.new(name, None)
    e.location = g2b(at)
    bpy.context.scene.collection.objects.link(e)
    if parent is not None:
        attach(e, parent)
    return e


def under(parent, objs):
    for o in objs:
        attach(o, parent)
    return objs


def wheel_at(name, r, width, at):
    t = cyl(name, r, width, at, "x", mat("tyre", BLACK), 20)
    rim = cyl(name + "_rim", r * 0.58, width + 0.02, at, "x", mat("rim", STEEL), 12)
    attach(rim, t)
    hub = cyl(name + "_hub", r * 0.22, width + 0.06, at, "x", mat("dark", DARK), 8)
    attach(hub, t)
    return t


def chevrons(out, name, W, y0, y1, z, face=-1):
    """Red and yellow rear chevron board (stripes as slanted bars)."""
    out.append(gbox(name, (W - 0.1, y1 - y0, 0.03), (0, (y0 + y1) / 2, z), mat("chev_y", YELLOW)))
    n = 6
    for i in range(n):
        x0 = -W / 2 + 0.15 + i * (W - 0.3) / n
        bar = gbox(name + "_red", (0.14, (y1 - y0) * 1.1, 0.02), (x0 + 0.1, (y0 + y1) / 2, z + face * 0.02), mat("chev_r", RED))
        bar.rotation_euler[1] = math.radians(35 if x0 < 0 else -35)
        out.append(bar)


def flat_cab(out, W, z0, z1, floor, roof, colour):
    """Flat-fronted (cab over engine) truck cab, glass and doors."""
    paint = mat("cab_" + colour[0], colour[1])
    zc = (z0 + z1) / 2
    out.append(gbox("cab_shell", (W, roof - floor, z1 - z0), (0, (floor + roof) / 2, zc), paint, 0.05))
    out.append(gbox("cab_roof", (W - 0.1, 0.25, z1 - z0 - 0.2), (0, roof + 0.1, zc - 0.05), paint, 0.06))
    g = mat("glass", GLASS)
    wy0, wy1 = floor + 1.15, roof - 0.18
    out.append(quad("win_front", [(-W / 2 + 0.12, wy0, z1 + 0.01), (W / 2 - 0.12, wy0, z1 + 0.01),
                                  (W / 2 - 0.14, wy1, z1 - 0.04), (-W / 2 + 0.14, wy1, z1 - 0.04)], g))
    for s in (-1, 1):
        x = s * (W / 2 + 0.01)
        pts = [(x, wy0, z1 - 0.15), (x, wy0, z1 - 1.05), (x, wy1, z1 - 1.05), (x, wy1, z1 - 0.2)]
        out.append(quad("win_side", pts if s > 0 else [pts[1], pts[0], pts[3], pts[2]], g))
        # Door seam and handle, step below.
        out.append(gbox("door_seam", (0.02, wy0 - floor - 0.1, 0.03), (x + s * 0.01, (floor + wy0) / 2, z1 - 1.1), mat("dark", DARK)))
        out.append(gbox("door_handle", (0.03, 0.04, 0.2), (x + s * 0.02, wy0 - 0.2, z1 - 0.95), mat("dark", DARK)))
        out.append(gbox("cab_step", (0.25, 0.06, 0.5), (s * (W / 2 - 0.12), floor - 0.35, z1 - 0.6), mat("rim", STEEL)))
        out.append(gbox("mirror_arm", (0.35, 0.04, 0.04), (s * (W / 2 + 0.17), wy1 - 0.1, z1 - 0.15), mat("black", BLACK)))
        out.append(gbox("mirror", (0.08, 0.5, 0.22), (s * (W / 2 + 0.35), wy1 - 0.35, z1 - 0.15), mat("black", BLACK), 0.02))
        out.append(gbox("headlamp", (0.34, 0.16, 0.05), (s * (W / 2 - 0.35), floor + 0.25, z1 + 0.02), mat("lamp", LAMP)))
        out.append(gbox("indicator", (0.12, 0.1, 0.05), (s * (W / 2 - 0.1), floor + 0.25, z1 + 0.02), mat("amber", AMBER)))
    out.append(gbox("grille", (W * 0.62, 0.55, 0.04), (0, floor + 0.65, z1 + 0.02), mat("black", BLACK)))
    out.append(gbox("cab_band", (W + 0.02, 0.16, z1 - z0 + 0.02), (0, floor + 0.95, zc), mat("hivis", ORANGE)))
    out.append(gbox("bumper_f", (W + 0.04, 0.38, 0.28), (0, floor - 0.12, z1 + 0.08), mat("grey", (0.25, 0.25, 0.27)), 0.04))
    # Amber beacon bar.
    out.append(gbox("beacon_bar", (W * 0.7, 0.1, 0.25), (0, roof + 0.28, z1 - 0.3), mat("black", BLACK)))
    for s in (-1, 1):
        out.append(cyl("beacon", 0.1, 0.16, (s * W * 0.28, roof + 0.4, z1 - 0.3), "y", mat("beacon", AMBER), 12))


def works_lorry():
    L, W = 10.0, 2.5
    out = []
    zf = L / 2
    # Chassis rails, fuel tank, side guards, mudguards.
    for s in (-1, 1):
        out.append(gbox("rail", (0.2, 0.32, L - 0.4), (s * 0.45, 0.9, -0.1), mat("dark", DARK)))
    flat_cab(out, W, zf - 2.0, zf, 1.0, 3.25, ("white", WHITE))
    out.append(gbox("fuel_tank", (0.55, 0.55, 1.3), (W / 2 - 0.35, 0.85, zf - 3.1), mat("rim", STEEL), 0.08))
    out.append(gbox("toolbox", (0.55, 0.55, 0.9), (-W / 2 + 0.35, 0.85, zf - 3.0), mat("black", BLACK), 0.03))
    deck_z0, deck_z1 = -L / 2, zf - 2.25
    deck_y = 1.35
    out.append(gbox("deck", (W, 0.14, deck_z1 - deck_z0), (0, deck_y - 0.07, (deck_z0 + deck_z1) / 2), mat("deck", TIMBER)))
    out.append(gbox("deck_edge", (W + 0.04, 0.22, deck_z1 - deck_z0), (0, deck_y - 0.2, (deck_z0 + deck_z1) / 2), mat("dark", DARK)))
    for i in range(11):
        z = deck_z0 + 0.3 + i * (deck_z1 - deck_z0 - 0.6) / 10
        for s in (-1, 1):
            out.append(gbox("stake_pocket", (0.06, 0.18, 0.12), (s * (W / 2 + 0.03), deck_y - 0.18, z), mat("rim", STEEL)))
    # Headboard: steel frame and mesh behind the cab.
    hz = deck_z1 - 0.08
    out.append(gbox("headboard", (W - 0.1, 1.5, 0.08), (0, deck_y + 0.75, hz), mat("rim", STEEL)))
    for x in range(-4, 5):
        out.append(gbox("headboard_bar", (0.05, 1.5, 0.12), (x * 0.28, deck_y + 0.75, hz), mat("dark", DARK)))
    out.append(gbox("headboard_top", (W, 0.1, 0.16), (0, deck_y + 1.52, hz), mat("dark", DARK)))
    # Side guards and mudguards.
    for s in (-1, 1):
        out.append(gbox("side_guard", (0.04, 0.12, 2.6), (s * (W / 2 - 0.05), 0.72, -0.2), mat("hivis", ORANGE)))
        out.append(gbox("side_guard", (0.04, 0.12, 2.6), (s * (W / 2 - 0.05), 0.42, -0.2), mat("hivis", ORANGE)))
        for z in (-2.6, -4.0):
            out.append(gbox("mudguard", (0.6, 0.05, 1.3), (s * (W / 2 - 0.3), 1.12, z), mat("black", BLACK)))
        out.append(gbox("taillamp", (0.3, 0.18, 0.05), (s * (W / 2 - 0.3), 0.95, -L / 2 - 0.05), mat("tail", TAIL)))
    chevrons(out, "chevron", W, 0.55, 1.05, -L / 2 - 0.08)
    out.append(gbox("under_bar", (W - 0.2, 0.15, 0.15), (0, 0.5, -L / 2 + 0.05), mat("dark", DARK)))
    # Wheels: twin steer at the front, tandem drive at the back.
    for z in (zf - 0.95, zf - 2.55, -2.6, -4.0):
        for s in (-1, 1):
            out.append(wheel_at("wheel", 0.52, 0.34 if z > 0 else 0.55, (s * (W / 2 - 0.25), 0.52, z)))
    # The load: two stacks of precast slabs on bearers, steel beams behind.
    for k in range(6):
        y = deck_y + 0.08 + k * 0.26
        z0 = 0.0 if k < 3 else 0.0
        out.append(gbox("load_slab_%d" % k, (2.25, 0.2, 2.9), (0, y + 0.1, deck_z1 - 1.75 - (k % 2) * 0.02), mat("concrete", CONCRETE), 0.02))
        out.append(gbox("bearer", (2.3, 0.06, 0.1), (0, y + 0.23, deck_z1 - 0.7), mat("deck", TIMBER)))
        out.append(gbox("bearer", (2.3, 0.06, 0.1), (0, y + 0.23, deck_z1 - 2.8), mat("deck", TIMBER)))
    out.append(gbox("bearer", (2.3, 0.08, 0.1), (0, deck_y + 0.04, deck_z1 - 0.7), mat("deck", TIMBER)))
    out.append(gbox("bearer", (2.3, 0.08, 0.1), (0, deck_y + 0.04, deck_z1 - 2.8), mat("deck", TIMBER)))
    # Straps over the slabs.
    for z in (deck_z1 - 1.0, deck_z1 - 2.5):
        out.append(gbox("strap", (W + 0.02, 0.02, 0.06), (0, deck_y + 1.7, z), mat("hivis", ORANGE)))
        for s in (-1, 1):
            out.append(gbox("strap", (0.02, 1.7, 0.06), (s * (W / 2 + 0.01), deck_y + 0.85, z), mat("hivis", ORANGE)))
    # Steel I-beams, 4.2 m long, along the deck.
    bz = deck_z0 + 2.3
    for s in (-0.66, 0.66):
        out.append(gbox("bearer", (0.1, 0.1, 0.1), (s, deck_y + 0.05, bz), mat("deck", TIMBER)))
    for k in range(4):
        x = -0.75 + (k % 2) * 1.5
        y = deck_y + 0.1 + (k // 2) * 0.42
        beam = empty("load_beam_%d" % k, (x, y, bz))
        parts = [gbox("flange", (0.32, 0.04, 4.2), (x, y + 0.02, bz), mat("oxide", OXIDE)),
                 gbox("flange", (0.32, 0.04, 4.2), (x, y + 0.36, bz), mat("oxide", OXIDE)),
                 gbox("web", (0.04, 0.32, 4.2), (x, y + 0.19, bz), mat("oxide", OXIDE))]
        under(beam, parts)
        out.append(beam)
    # A pallet of blocks and a tub of bags at the very back.
    out.append(gbox("pallet", (1.1, 0.14, 1.0), (-0.6, deck_y + 0.07, deck_z0 + 0.6), mat("deck", TIMBER)))
    out.append(gbox("blocks", (1.0, 0.7, 0.9), (-0.6, deck_y + 0.5, deck_z0 + 0.6), mat("blocks", (0.72, 0.7, 0.66)), 0.02))
    out.append(gbox("bags", (0.9, 0.5, 0.8), (0.6, deck_y + 0.25, deck_z0 + 0.6), mat("bags", (0.85, 0.82, 0.72)), 0.06))
    return out


def crane_truck():
    L, W = 11.0, 2.55
    out = []
    zf = L / 2
    cy = 0.62   # wheel radius / axle height
    # Carrier: deep yellow chassis, cab low on the left out front.
    out.append(gbox("carrier", (W, 0.9, L - 0.6), (0, 1.2, -0.3), mat("yellow", YELLOW), 0.05))
    out.append(gbox("carrier_deck", (W - 0.2, 0.08, L - 2.2), (0, 1.69, -1.1), mat("dark", DARK)))
    for s in (-1, 1):
        out.append(gbox("carrier_skirt", (0.04, 0.3, L - 1.0), (s * (W / 2 + 0.01), 0.85, -0.3), mat("black", BLACK)))
    cz0, cz1 = zf - 1.7, zf
    cx0, cx1 = -W / 2, -0.15
    xc = (cx0 + cx1) / 2
    paint = mat("yellow", YELLOW)
    out.append(gbox("cab_shell", (cx1 - cx0, 1.4, cz1 - cz0), (xc, 2.15, (cz0 + cz1) / 2), paint, 0.05))
    g = mat("glass", GLASS)
    out.append(quad("win_front", [(cx0 + 0.08, 2.05, cz1 + 0.01), (cx1 - 0.08, 2.05, cz1 + 0.01), (cx1 - 0.1, 2.8, cz1 - 0.1), (cx0 + 0.1, 2.8, cz1 - 0.1)], g))
    pts = [(cx0 - 0.01, 2.0, cz1 - 0.2), (cx0 - 0.01, 2.0, cz0 + 0.2), (cx0 - 0.01, 2.75, cz0 + 0.2), (cx0 - 0.01, 2.75, cz1 - 0.25)]
    out.append(quad("win_side", [pts[1], pts[0], pts[3], pts[2]], g))
    out.append(gbox("cab_roof", (cx1 - cx0 + 0.04, 0.08, cz1 - cz0 + 0.04), (xc, 2.88, (cz0 + cz1) / 2), mat("white", WHITE)))
    out.append(gbox("beacon_bar", (0.9, 0.1, 0.22), (xc, 2.98, cz1 - 0.4), mat("black", BLACK)))
    for s in (-1, 1):
        out.append(cyl("beacon", 0.09, 0.15, (xc + s * 0.35, 3.1, cz1 - 0.4), "y", mat("beacon", AMBER), 12))
    out.append(gbox("mirror", (0.08, 0.45, 0.2), (cx0 - 0.35, 2.4, cz1 - 0.1), mat("black", BLACK), 0.02))
    out.append(gbox("mirror_arm", (0.33, 0.04, 0.04), (cx0 - 0.18, 2.6, cz1 - 0.1), mat("black", BLACK)))
    # Engine cover beside the cab, boom rest on top of it.
    out.append(gbox("engine_hood", (W + cx1 - 0.05 - W / 2 + 0.05 + W / 2 - 0.05 - (cx1 + 0.05) + 0.05 if False else W / 2 - 0.25, 0.7, 1.6), (W / 4 + 0.05, 1.95, zf - 0.9), paint, 0.05))
    out.append(gbox("boom_rest", (0.9, 0.9, 0.2), (0.35, 2.55, zf - 1.0), mat("dark", DARK)))
    out.append(gbox("bumper_f", (W + 0.04, 0.45, 0.3), (0, 0.95, zf + 0.05), mat("black", BLACK), 0.04))
    for s in (-1, 1):
        out.append(gbox("headlamp", (0.3, 0.14, 0.04), (s * (W / 2 - 0.3), 1.35, zf - 0.02 + 0.06), mat("lamp", LAMP)))
        out.append(gbox("taillamp", (0.3, 0.16, 0.05), (s * (W / 2 - 0.3), 1.25, -L / 2 - 0.02), mat("tail", TAIL)))
        out.append(gbox("hivis_band", (0.02, 0.12, L - 1.2), (s * (W / 2 + 0.02), 1.45, -0.3), mat("chev_r", RED)))
    chevrons(out, "chevron", W, 0.85, 1.55, -L / 2 - 0.12)
    out.append(gbox("cab_step", (0.4, 0.06, 0.5), (cx0 + 0.25, 1.0, cz1 - 0.6), mat("rim", STEEL)))
    # Four axles of big tyres.
    for z in (zf - 1.1, zf - 2.8, -1.8, -3.5):
        for s in (-1, 1):
            out.append(wheel_at("wheel", cy, 0.5, (s * (W / 2 - 0.3), cy, z)))
            out.append(gbox("wheel_arch", (0.55, 0.06, 1.5), (s * (W / 2 - 0.27), 1.66, z), mat("black", BLACK)))
    # Outriggers: boxes across the frame, beams slide out to the sides, a
    # jack and pad on the end of each. The game moves outrigger_* along x.
    for zn, z in (("f", zf - 3.7), ("r", -L / 2 + 0.6)):
        out.append(gbox("outrigger_box", (W - 0.05, 0.45, 0.55), (0, 1.05, z), mat("dark", DARK)))
        for s, sn in ((-1, "l"), (1, "r")):
            beam = empty("outrigger_%s%s" % (zn, sn), (s * (W / 2 - 0.2), 1.05, z))
            parts = [gbox("outrigger_beam", (2.4, 0.38, 0.45), (s * (W / 2 - 1.2), 1.05, z), mat("yellow", YELLOW), 0.02),
                     gbox("outrigger_stripe", (2.4, 0.06, 0.47), (s * (W / 2 - 1.2), 1.15, z), mat("chev_r", RED)),
                     gbox("jack", (0.32, 1.0, 0.32), (s * (W / 2 + 0.05), 0.65, z), mat("rim", STEEL)),
                     cyl("jack_pad", 0.38, 0.1, (s * (W / 2 + 0.05), 0.08, z), "y", mat("black", BLACK), 16)]
            under(beam, parts)
            out.append(beam)
    # Superstructure on the turntable at the back. Local axes: the boom
    # points along +z when the slew is at rest (over the cab).
    sx, sy, sz = 0.0, 1.73, -3.0
    slew = empty("slew", (sx, sy, sz))
    sp = []
    sp.append(cyl("turntable", 1.05, 0.35, (sx, sy + 0.17, sz), "y", mat("dark", DARK), 24))
    sp.append(gbox("upper_frame", (2.3, 0.75, 3.8), (sx, sy + 0.72, sz - 0.4), mat("yellow", YELLOW), 0.04))
    sp.append(gbox("counterweight", (2.5, 1.15, 1.0), (sx, sy + 0.9, sz - 2.6), mat("cweight", (0.2, 0.2, 0.22)), 0.06))
    sp.append(gbox("counterweight_stripe", (2.52, 0.14, 1.02), (sx, sy + 1.25, sz - 2.6), mat("chev_r", RED)))
    sp.append(gbox("engine_box", (1.0, 0.8, 1.6), (sx + 0.55, sy + 1.45, sz - 1.4), mat("yellow", YELLOW), 0.05))
    sp.append(gbox("winch", (0.9, 0.7, 0.7), (sx - 0.2, sy + 1.4, sz - 1.9), mat("dark", DARK), 0.04))
    sp.append(cyl("winch_drum", 0.3, 0.8, (sx - 0.2, sy + 1.55, sz - 1.9), "x", mat("rim", STEEL), 14))
    # Operator's cab, to the left of the boom.
    ox, oz = sx - 0.95, sz + 0.6
    sp.append(gbox("op_cab", (0.85, 1.55, 1.7), (ox, sy + 1.85, oz), mat("yellow", YELLOW), 0.05))
    sp.append(quad("op_win_front", [(ox - 0.38, sy + 1.6, oz + 0.86), (ox + 0.38, sy + 1.6, oz + 0.86), (ox + 0.38, sy + 2.5, oz + 0.8), (ox - 0.38, sy + 2.5, oz + 0.8)], g))
    sp.append(quad("op_win_side", [(ox - 0.44, sy + 1.6, oz - 0.6), (ox - 0.44, sy + 1.6, oz + 0.7), (ox - 0.44, sy + 2.5, oz + 0.7), (ox - 0.44, sy + 2.5, oz - 0.6)][::-1], g))
    sp.append(gbox("op_roof", (0.9, 0.06, 1.75), (ox, sy + 2.65, oz), mat("white", WHITE)))
    sp.append(gbox("ram_mount", (0.7, 0.5, 0.5), (sx, sy + 1.2, sz + 1.0), mat("dark", DARK)))
    under(slew, sp)
    out.append(slew)
    # Boom pivot high on the back of the superstructure.
    by, bz = sy + 1.6, sz - 1.6
    boom = empty("boom", (sx, by, bz), slew)
    sections = [("boom_1", 1.0, 1.05, 10.5), ("boom_2", 0.84, 0.88, 10.0), ("boom_3", 0.7, 0.74, 10.0), ("boom_4", 0.56, 0.6, 10.0)]
    parent = boom
    base_z = bz
    for i, (name, w, h, ln) in enumerate(sections):
        start = base_z if i == 0 else base_z + 0.5
        sec = empty(name, (sx, by, start), parent)
        parts = [gbox(name + "_box", (w, h, ln), (sx, by, start + ln / 2), mat("yellow", YELLOW), 0.04)]
        parts.append(gbox(name + "_top", (w * 0.7, 0.03, ln - 0.3), (sx, by + h / 2 + 0.01, start + ln / 2), mat("dark", DARK)))
        if i == 0:
            parts.append(gbox("boom_stripe", (w + 0.02, 0.14, ln - 1.0), (sx, by - 0.1, start + ln / 2), mat("chev_r", RED)))
            parts.append(gbox("ram_lug", (0.5, 0.35, 0.6), (sx, by - h / 2 - 0.15, start + 3.6), mat("dark", DARK)))
            parts.append(cyl("boom_foot", 0.32, w + 0.2, (sx, by, start + 0.3), "x", mat("dark", DARK), 14))
        under(sec, parts)
        parent = sec
        base_z = start
    head = empty("boom_head", (sx, by, base_z + 10.0), parent)
    hp = [gbox("head_plates", (0.62, 0.9, 0.8), (sx, by - 0.1, base_z + 10.2), mat("yellow", YELLOW), 0.04),
          cyl("sheave", 0.38, 0.25, (sx, by - 0.2, base_z + 10.5), "x", mat("dark", DARK), 16),
          gbox("tip_light", (0.12, 0.12, 0.12), (sx, by + 0.4, base_z + 10.4), mat("tail", TAIL))]
    under(head, hp)
    return out


def works_kit():
    """Loose kit, each a root the game instances by name."""
    out = []

    def item(name, parts):
        r = empty(name, (0, 0, 0))
        under(r, parts)
        out.append(r)

    # Hook block: origin at the top where the cable comes in.
    item("hook_block", [
        gbox("hb_body", (0.55, 0.75, 0.35), (0, -0.45, 0), mat("yellow", YELLOW), 0.05),
        gbox("hb_stripe", (0.57, 0.12, 0.37), (0, -0.35, 0), mat("black", BLACK)),
        cyl("hb_sheave", 0.2, 0.38, (0, -0.2, 0), "z", mat("dark", DARK), 14),
        gbox("hb_shank", (0.1, 0.3, 0.1), (0, -0.95, 0), mat("rim", STEEL)),
        gbox("hb_hook_a", (0.1, 0.1, 0.32), (0, -1.12, 0.1), mat("rim", STEEL)),
        gbox("hb_hook_b", (0.1, 0.22, 0.1), (0, -1.02, 0.24), mat("rim", STEEL)),
        gbox("hb_latch", (0.04, 0.16, 0.04), (0, -1.0, 0.05), mat("amber", AMBER)),
    ])
    # Cordless drill: origin at the grip, nose along +z.
    item("drill", [
        gbox("dr_body", (0.07, 0.09, 0.22), (0, 0.1, 0.04), mat("drill", (0.95, 0.75, 0.1)), 0.02),
        gbox("dr_grip", (0.05, 0.14, 0.06), (0, 0.0, 0.0), mat("black", BLACK), 0.015),
        gbox("dr_batt", (0.08, 0.06, 0.12), (0, -0.09, 0.01), mat("black", BLACK), 0.01),
        cyl("dr_chuck", 0.022, 0.06, (0, 0.1, 0.18), "z", mat("dark", DARK), 10),
        cyl("dr_bit", 0.006, 0.14, (0, 0.1, 0.28), "z", mat("rim", STEEL), 6),
    ])
    # Angle grinder: held two-handed, disc out to the front.
    item("grinder", [
        cyl("gr_body", 0.04, 0.32, (0, 0, -0.02), "z", mat("grinder", BLUE), 12),
        cyl("gr_disc", 0.11, 0.008, (0, -0.06, 0.16), "y", mat("dark", DARK), 18),
        gbox("gr_guard", (0.13, 0.03, 0.12), (0, -0.02, 0.12), mat("rim", STEEL)),
        cyl("gr_handle", 0.015, 0.16, (0.09, 0, 0.1), "x", mat("black", BLACK), 8),
    ])
    item("weld_torch", [
        cyl("wt_handle", 0.02, 0.18, (0, 0, 0), "z", mat("black", BLACK), 8),
        cyl("wt_neck", 0.01, 0.14, (0, -0.03, 0.14), "z", mat("rim", STEEL), 6),
        gbox("wt_cable", (0.02, 0.02, 0.3), (0, 0, -0.24), mat("black", BLACK)),
    ])
    item("weld_visor", [
        gbox("wv_shell", (0.24, 0.26, 0.08), (0, 0, 0), mat("black", BLACK), 0.04),
        gbox("wv_glass", (0.12, 0.05, 0.02), (0, 0.02, 0.045), mat("weld_glass", (0.08, 0.3, 0.12))),
    ])
    item("shovel", [
        cyl("sh_shaft", 0.017, 1.1, (0, 0, 0), "z", mat("deck", TIMBER), 8),
        gbox("sh_grip", (0.14, 0.03, 0.03), (0, 0, -0.56), mat("black", BLACK)),
        gbox("sh_blade", (0.24, 0.02, 0.3), (0, -0.02, 0.68), mat("rim", STEEL)),
    ])
    item("broom", [
        cyl("br_shaft", 0.016, 1.3, (0, 0, 0), "z", mat("deck", TIMBER), 8),
        gbox("br_head", (0.45, 0.06, 0.07), (0, -0.02, 0.66), mat("black", BLACK)),
        gbox("br_bristle", (0.43, 0.08, 0.06), (0, -0.08, 0.66), mat("bristle", (0.75, 0.6, 0.2))),
    ])
    item("bucket", [
        cyl("bk_body", 0.16, 0.3, (0, 0.15, 0), "y", mat("bucket", (0.85, 0.1, 0.1)), 12),
        cyl("bk_water", 0.145, 0.02, (0, 0.27, 0), "y", mat("water", (0.45, 0.4, 0.35)), 12),
    ])
    trestle = []
    for x in (-0.7, 0.7):
        for zz in (-0.25, 0.25):
            leg = gbox("tr_leg", (0.05, 0.85, 0.05), (x, 0.42, zz * 0.6), mat("rim", STEEL))
            leg.rotation_euler[1] = math.radians(14 if zz > 0 else -14)
            trestle.append(leg)
        trestle.append(gbox("tr_bar", (0.06, 0.06, 0.4), (x, 0.84, 0), mat("rim", STEEL)))
    trestle.append(gbox("tr_beam", (2.2, 0.28, 0.22), (0, 1.0, 0), mat("oxide", OXIDE)))
    item("trestle_beam", trestle)
    item("generator", [
        gbox("gen_body", (0.9, 0.55, 0.55), (0, 0.4, 0), mat("yellow", YELLOW), 0.05),
        gbox("gen_frame", (1.0, 0.05, 0.62), (0, 0.1, 0), mat("dark", DARK)),
        gbox("gen_panel", (0.3, 0.25, 0.02), (0.2, 0.42, 0.29), mat("dark", DARK)),
        cyl("gen_exhaust", 0.04, 0.2, (-0.35, 0.75, 0), "y", mat("rim", STEEL), 8),
    ])
    # Chapter-8 style barrier: red and white plank on two black feet.
    bar = [gbox("ba_plank", (1.9, 0.15, 0.03), (0, 0.85, 0), mat("white", WHITE))]
    for i in range(5):
        bar.append(gbox("ba_red", (0.2, 0.15, 0.035), (-0.76 + i * 0.38, 0.85, 0), mat("chev_r", RED)))
    for x in (-0.85, 0.85):
        bar.append(gbox("ba_post", (0.05, 0.85, 0.05), (x, 0.43, 0), mat("dark", DARK)))
        bar.append(gbox("ba_foot", (0.18, 0.08, 0.6), (x, 0.04, 0), mat("black", BLACK)))
    bar.append(cyl("ba_lamp", 0.06, 0.1, (0, 1.0, 0), "y", mat("beacon", AMBER), 10))
    item("barrier", bar)
    # Road works sign: red-rimmed triangle on a stand (the game writes the
    # plate below it).
    sign = []
    tri = [(0, 2.05, 0.0), (-0.42, 1.32, 0.0), (0.42, 1.32, 0.0)]
    sign.append(quad("sg_rim", [tri[0], tri[2], tri[1], tri[0]][:3], mat("chev_r", RED), 0.02))
    inner = [(0, 1.9, 0.015), (-0.3, 1.4, 0.015), (0.3, 1.4, 0.015)]
    sign.append(quad("sg_face", [inner[0], inner[2], inner[1]], mat("white", WHITE), 0.0))
    # Worker and spoil heap, a few bars.
    sign.append(gbox("sg_man", (0.05, 0.2, 0.01), (0.0, 1.55, 0.025), mat("black", BLACK)))
    sign.append(gbox("sg_spade", (0.2, 0.03, 0.01), (0.06, 1.6, 0.025), mat("black", BLACK)))
    sign.append(gbox("sg_heap", (0.18, 0.06, 0.01), (0.14, 1.45, 0.025), mat("black", BLACK)))
    sign.append(gbox("sg_plate", (0.95, 0.32, 0.02), (0, 1.1, 0), mat("white", WHITE)))
    sign.append(gbox("sg_post", (0.05, 1.3, 0.05), (0, 0.65, -0.03), mat("dark", DARK)))
    for x in (-0.3, 0.3):
        sign.append(gbox("sg_foot", (0.06, 0.06, 0.7), (x, 0.03, 0), mat("black", BLACK)))
    item("sign", sign)
    return out


BUILDS = {"works_lorry": works_lorry, "crane_truck": crane_truck, "works_kit": works_kit}


def build(name):
    C.reset()
    V.MATS.clear()
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    for p in BUILDS[name]():
        if p.parent is None:
            p.parent = root
    C.export_glb("assets/models/works/%s.glb" % name)


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if a in BUILDS] or list(BUILDS)
    for n in names:
        build(n)
