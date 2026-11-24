"""The ambulance and its stretcher, for the crews that come for the dead.

  assets/models/vehicles/ambulance.glb   box-bodied ambulance on a van cab
  assets/models/vehicles/stretcher.glb   wheeled trolley stretcher

Ambulance: the van_box layout (cab at the front, tall box behind) with a
squarer box, a high-vis chequer band (green and yellow) down both sides and
across the back, a red stripe, twin rear doors with windows, a step, and
blue lights: a bar on the cab roof and a lamp at each corner of the box.
The lights are two meshes, lens_red (left side) and lens_blue (right
side), like the police car's, so the game flashes them the same way (both
blue here). Part names as in build_vehicles.py so dents, panels and
glass work.

Stretcher: a trolley frame on four castors, a mattress, and body_bag (a
zipped black bag with a body's shape), hidden until someone's loaded.

    python tools/blender/build_ambulance.py
"""
import os
import sys

import bpy  # noqa: I001
import bmesh

sys.path.insert(0, os.path.dirname(__file__))
import common as C  # noqa: E402
import build_vehicles as V  # noqa: E402

GREEN = (0.12, 0.55, 0.22)
YELLOW = (0.98, 0.85, 0.08)
RED = (0.75, 0.06, 0.06)
BLUE = (0.10, 0.25, 0.95)
BAG = (0.04, 0.04, 0.05)
MATTRESS = (0.85, 0.5, 0.08)
FRAME = (0.70, 0.72, 0.75)

SPEC = {"L": 6.4, "W": 2.12, "belt": 0.42, "roof": 1.55, "cab_front": (2.15, 1.6), "cab_rear": (0.75, 0.75),
        "b_pillar": 0.8, "box_front": 0.75, "box_top": 2.6, "wheel": 0.38}


def multi_box(name, parts, m, bevel=0.01):
    """One mesh made of several boxes (Godot coords: size, centre)."""
    bm = bmesh.new()
    for size, centre in parts:
        geom = bmesh.ops.create_cube(bm, size=1.0)
        c = V.g2b(centre)
        for v in geom["verts"]:
            v.co.x = v.co.x * size[0] + c[0]
            v.co.y = v.co.y * size[2] + c[1]
            v.co.z = v.co.z * size[1] + c[2]
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, affect="EDGES")
    return V.obj_from_bm(name, bm, [m])


def ambulance():
    L, W = SPEC["L"], SPEC["W"]
    out = V.van(SPEC, "box")
    # A squarer box than the delivery van: no luton, no roller shutter.
    for o in list(out):
        if o.name.startswith("cargo_luton") or o.name.startswith("shutter"):
            bpy.data.objects.remove(o, do_unlink=True)
            out.remove(o)
    belt, top = SPEC["belt"], SPEC["box_top"]
    bz0 = SPEC["box_front"] - 0.05
    bz1 = -L / 2
    zc = (bz0 + bz1) / 2
    zl = bz0 - bz1
    hw = W / 2 + 0.05
    # Chequer band down each side: two rows, alternating green and yellow.
    sq = 0.42
    n = int(zl / sq)
    greens, yellows = [], []
    for s in (-1, 1):
        x = s * (hw + 0.012)
        for row, y in enumerate((0.95, 0.95 + sq)):
            for i in range(n):
                z = bz0 - sq / 2 - i * sq - (zl - n * sq) / 2
                (greens if (i + row) % 2 == 0 else yellows).append(((0.02, sq, sq), (x, y, z)))
        # Red stripe above the chequer.
        out.append(V.gbox("stripe_red", (0.02, 0.12, zl - 0.1), (x, 0.95 + sq * 1.5 + 0.12, zc), V.mat("red", RED)))
    # Across the back, below the door windows.
    for row, y in enumerate((0.55,)):
        k = int((W + 0.1) / sq)
        for i in range(k):
            x = -W / 2 + sq / 2 + i * ((W + 0.1 - sq) / max(1, k - 1))
            (greens if (i + row) % 2 == 0 else yellows).append(((sq * 0.98, sq, 0.02), (x, y, bz1 - 0.035)))
    out.append(multi_box("chequer_green", greens, V.mat("green", GREEN), 0.0))
    out.append(multi_box("chequer_yellow", yellows, V.mat("yellow", YELLOW), 0.0))
    # Chequer on the cab doors too (one row), and on the bonnet front.
    cab = []
    cab_y = []
    for s in (-1, 1):
        x = s * (W / 2 + 0.03)
        for i in range(3):
            z = SPEC["cab_front"][0] - 0.25 - i * sq
            (cab if i % 2 == 0 else cab_y).append(((0.02, sq * 0.8, sq), (x, 0.05, z)))
    out.append(multi_box("cab_chequer_green", cab, V.mat("green", GREEN), 0.0))
    out.append(multi_box("cab_chequer_yellow", cab_y, V.mat("yellow", YELLOW), 0.0))
    # Twin rear doors with windows, a grab handle and a step.
    dw = (W - 0.2) / 2
    for s, sn in ((-1, "l"), (1, "r")):
        out.append(V.gbox("door_rear_" + sn, (dw - 0.02, top - belt - 0.15, 0.04), (s * dw / 2, (top + belt) / 2 - 0.05, bz1 - 0.02), V.mat("paint", V.PAINT), 0.01))
        out.append(V.gbox("win_rear_" + sn, (dw * 0.6, 0.5, 0.02), (s * dw / 2, top - 0.6, bz1 - 0.045), V.mat("glass", V.GLASS)))
        out.append(V.gbox("handle_rear_" + sn, (0.03, 0.4, 0.04), (s * 0.12, 1.1, bz1 - 0.06), V.mat("black", V.BLACK)))
    out.append(V.gbox("step", (W - 0.3, 0.06, 0.35), (0, -0.55, bz1 - 0.15), V.mat("grey", V.GREY)))
    # Blue lights: a bar on the cab roof, a lamp at each top corner of the
    # box, and grille lamps. Left side lens_red, right side lens_blue.
    roof = SPEC["roof"] + 0.02
    zf = SPEC["cab_front"][1] - 0.35
    out.append(V.gbox("lightbar", (1.3, 0.06, 0.26), (0, roof + 0.06, zf), V.mat("black", V.BLACK), 0.01))
    left, right = [], []
    for s, side in ((-1, left), (1, right)):
        side.append(((0.58, 0.1, 0.24), (s * 0.33, roof + 0.14, zf)))
        side.append(((0.16, 0.16, 0.12), (s * (hw - 0.12), top + 0.02, bz0 + 0.02)))
        side.append(((0.16, 0.16, 0.12), (s * (hw - 0.12), top + 0.02, bz1 - 0.02)))
        side.append(((0.1, 0.12, 0.2), (s * (hw + 0.02), top - 0.15, zc)))
        side.append(((0.12, 0.06, 0.03), (s * 0.35, 0.12, L / 2 + 0.01)))
    out.append(multi_box("lens_red", left, V.mat("blue_l", BLUE)))
    out.append(multi_box("lens_blue", right, V.mat("blue_r", BLUE)))
    # Roof vents and a bit of kit on top of the box.
    for z in (zc + 0.8, zc - 0.6):
        out.append(V.gbox("roof_vent", (0.5, 0.1, 0.5), (0, top + 0.05, z), V.mat("grey", V.GREY), 0.02))
    return out


def stretcher():
    out = []
    frame = V.mat("frame", FRAME)
    # Godot coords: x across, y up, z along. Wheels on the ground at y=0.
    out.append(V.gbox("deck", (0.6, 0.05, 1.95), (0, 0.78, 0), frame, 0.01))
    out.append(V.gbox("mattress", (0.56, 0.08, 1.9), (0, 0.845, 0), V.mat("mattress", MATTRESS), 0.03))
    for s in (-1, 1):
        out.append(V.gbox("rail", (0.03, 0.03, 1.9), (s * 0.31, 0.92, 0), frame))
        for z in (-0.95, 0.95):
            out.append(V.gbox("handle", (0.5, 0.025, 0.025), (0, 0.84, z * 1.06), frame))
        for z in (-0.7, 0.7):
            out.append(V.gbox("leg", (0.035, 0.7, 0.035), (s * 0.22, 0.4, z), frame))
            out.append(V.cyl("castor", 0.06, 0.04, (s * 0.22, 0.06, z), "x", V.mat("tyre", V.BLACK), 10))
    out.append(V.gbox("base", (0.5, 0.04, 1.5), (0, 0.12, 0), frame))
    # The bag: a long rounded shape, wider at the shoulders, a zip line.
    bm = bmesh.new()
    rings = []
    zs = [-0.88, -0.6, -0.2, 0.2, 0.45, 0.62, 0.8, 0.9]
    ws = [0.12, 0.17, 0.2, 0.23, 0.24, 0.16, 0.15, 0.1]
    hs = [0.08, 0.1, 0.13, 0.14, 0.14, 0.1, 0.12, 0.08]
    import math
    for z, w, h in zip(zs, ws, hs):
        ring = []
        for k in range(10):
            a = math.pi * 2 * k / 10
            ring.append(bm.verts.new(V.g2b((math.cos(a) * w, 0.9 + max(0.0, math.sin(a)) * h + min(0.0, math.sin(a)) * 0.02, z))))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for j in range(10):
            bm.faces.new((a[j], a[(j + 1) % 10], b[(j + 1) % 10], b[j]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bag = V.obj_from_bm("body_bag", bm, [V.mat("bag", BAG)])
    zip_line = V.gbox("body_bag_zip", (0.015, 0.015, 1.6), (0, 1.045, 0.0), V.mat("frame", FRAME))
    V.attach(zip_line, bag)
    out.append(bag)
    return out


def build(name):
    C.reset()
    V.MATS.clear()
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    if name == "ambulance":
        parts = ambulance()
        parts.append(V.wheel(SPEC["wheel"], 0.24))
    else:
        parts = stretcher()
    for p in parts:
        if p.parent is None:
            p.parent = root
    C.export_glb("assets/models/vehicles/%s.glb" % name)


if __name__ == "__main__":
    for n in [a for a in sys.argv[1:] if a in ("ambulance", "stretcher")] or ["ambulance", "stretcher"]:
        build(n)
