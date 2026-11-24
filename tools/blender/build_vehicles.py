"""Wave 2, Phase 2.4: every civilian vehicle, one glb each in
assets/models/vehicles/:

  sedan, hatchback        family cars
  van_panel               panel van (no side windows behind the cab)
  van_box                 delivery van with a tall box body (luton)
  minibus                 windows all along
  trash_truck             cab, compactor body, rear bin lifter (bin_lifter)
  hgv_tractor             articulated tractor unit with a fifth wheel
  trailer_box, trailer_tanker, trailer_flatbed   the trailers it pulls
  motorbike

Same part names as the police car so the game treats them the same way:
body (dents), door_fl/fr/rl/rr, bonnet, boot (dent, come off), bumper_f/r,
mirror_l/r, win_front, win_rear, win_fl/fr/rl/rr (shatter), wheel (one,
instanced by the game). The body colour uses material "paint", which the
game recolours per vehicle. Godot axes (x right, y up, z forward), turned
into Blender's here; each vehicle is centred on its body box like car.gd.

    python tools/blender/build_vehicles.py [name ...]
"""
import math
import os
import sys

import bpy  # noqa: I001
import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import common as C  # noqa: E402
import interiors as I  # noqa: E402

PAINT = (0.85, 0.85, 0.83)
BLACK = (0.06, 0.06, 0.07)
GREY = (0.22, 0.22, 0.24)
DARK = (0.12, 0.12, 0.13)
GLASS = (0.12, 0.17, 0.22)
SEAT = (0.14, 0.13, 0.13)
LAMP = (1.00, 0.96, 0.80)
TAIL = (0.70, 0.05, 0.05)
CHROME = (0.65, 0.66, 0.68)
ORANGE = (0.95, 0.45, 0.05)
STEEL = (0.55, 0.57, 0.6)
TANK = (0.78, 0.8, 0.82)
WOOD = (0.55, 0.38, 0.22)

MATS = {}


def mat(name, col):
    if name not in MATS:
        MATS[name] = C.material(name, col)
    return MATS[name]


def g2b(p):
    return (p[0], -p[2], p[1])


def attach(child, parent):
    bpy.context.view_layer.update()
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


def obj_from_bm(name, bm, mats):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def gbox(name, size, centre, m, bevel=0.0):
    return C.box(name, (size[0], size[2], size[1]), g2b(centre), m, bevel=bevel)


def quad(name, pts, m, thick=0.02):
    bm = bmesh.new()
    vs = [bm.verts.new(g2b(p)) for p in pts]
    f = bm.faces.new(vs)
    bm.normal_update()
    if thick > 0:
        r = bmesh.ops.extrude_face_region(bm, geom=[f])
        n = f.normal.copy()
        for v in [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]:
            v.co -= n * thick
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return obj_from_bm(name, bm, [m])


def cyl(name, r, depth, centre, axis, m, verts=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth)
    o = bpy.context.object
    o.name = name
    o.location = g2b(centre)
    if axis == "x":
        o.rotation_euler = (0, math.pi / 2, 0)
    elif axis == "z":   # Godot z = Blender -y
        o.rotation_euler = (math.pi / 2, 0, 0)
    o.data.materials.append(m)
    return o


# --- a lofted lower body ------------------------------------------------------------

def lofted_body(name, L, W, bottom, top_fn, m_main, nz=24, z0=None, z1=None):
    """A body shell lofted along z from z0 to z1 (default the whole length),
    its top line from top_fn(z), finely divided so it dents."""
    z0 = -L / 2 if z0 is None else z0
    z1 = L / 2 if z1 is None else z1
    bm = bmesh.new()
    rings = []
    for i in range(nz + 1):
        z = z0 + (z1 - z0) * i / nz
        t = top_fn(z)
        hw = W / 2
        end = max(0.0, abs(z) - (L / 2 - 0.3)) / 0.3
        hw *= 1.0 - 0.08 * end * end
        sec = [(-hw + 0.05, bottom), (hw - 0.05, bottom), (hw, bottom + 0.12), (hw, t - 0.08),
               (hw - 0.05, t), (-hw + 0.05, t), (-hw, t - 0.08), (-hw, bottom + 0.12)]
        fine = []
        for a, b in zip(sec, sec[1:] + sec[:1]):
            for s in range(3):
                k = s / 3.0
                fine.append((a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k))
        rings.append([bm.verts.new(g2b((x, y, z))) for x, y in fine])
    n = len(rings[0])
    for i in range(nz):
        a, b = rings[i], rings[i + 1]
        for j in range(n):
            bm.faces.new((a[j], a[(j + 1) % n], b[(j + 1) % n], b[j]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = obj_from_bm(name, bm, [m_main, mat("dark", DARK)])
    for p in ob.data.polygons:
        if p.center.z < bottom + 0.14 and abs(p.normal.z) < 0.7:
            p.material_index = 1
    return ob


def cabin(spec, out, side_windows="all"):
    """Glasshouse: windscreen, rear window, side windows, roof, pillars."""
    W = spec["W"]
    b = spec["belt"]
    t = spec["roof"]
    bf, tf = spec["cab_front"]
    br, tr = spec["cab_rear"]
    bhw, thw = W / 2 - 0.06, W / 2 - 0.18
    bp = spec.get("b_pillar", (bf + br) / 2)
    paint = mat("paint", PAINT)
    glass = mat("glass", GLASS)
    i = 0.02

    def cab(s, y, z):
        k = (y - b) / (t - b)
        return (s * (bhw + (thw - bhw) * k), y, z)

    out.append(quad("win_front", [(-bhw + 0.05, b + i, bf), (bhw - 0.05, b + i, bf), (thw - 0.05, t - i, tf), (-thw + 0.05, t - i, tf)], glass))
    if spec.get("rear_window", True):
        out.append(quad("win_rear", [(bhw - 0.05, b + i, br), (-bhw + 0.05, b + i, br), (-thw + 0.05, t - i, tr), (thw - 0.05, t - i, tr)], glass))
    else:
        out.append(quad("rear_panel", [(bhw, b, br), (-bhw, b, br), (-thw, t, tr), (thw, t, tr)], paint, 0.03))

    def side(name, s, z0, z1, zt0, zt1, m=glass):
        a = cab(s, b + i, z0)
        bb = cab(s, b + i, z1)
        c = cab(s, t - i, zt1)
        d = cab(s, t - i, zt0)
        out.append(quad(name, [a, bb, c, d] if s > 0 else [bb, a, d, c], m))

    for s, sn in ((1, "r"), (-1, "l")):
        side("win_f" + sn, s, bf - 0.10, bp + 0.05, tf - 0.02, bp + 0.05)
        if side_windows == "all":
            side("win_r" + sn, s, bp - 0.05, br + 0.12, bp - 0.05, tr + 0.02)
        else:
            side("panel_r" + sn, s, bp - 0.05, br, bp - 0.05, tr, paint)
    out.append(gbox("roof", (thw * 2 + 0.06, 0.05, tf - tr + 0.08), (0, t + 0.02, (tf + tr) / 2), paint, 0.015))
    for s, sn in ((-1, "l"), (1, "r")):
        for tag, zb, zt in (("a", bf - 0.04, tf), ("b", bp, bp), ("c", br + 0.04, tr)):
            pb = cab(s, b, zb)
            pt = cab(s, t, zt)
            bm = bmesh.new()
            mid = [(pb[k] + pt[k]) / 2 for k in range(3)]
            length = math.dist(pb, pt)
            bmesh.ops.create_cube(bm, size=1.0)
            for v in bm.verts:
                v.co.x *= 0.07
                v.co.y *= 0.09
                v.co.z *= length + 0.02
            ob = obj_from_bm("pillar_%s%s" % (tag, sn), bm, [mat("black", BLACK) if tag == "b" else paint])
            ob.location = g2b(mid)
            d = Vector(g2b(pt)) - Vector(g2b(pb))
            ob.rotation_mode = "QUATERNION"
            ob.rotation_quaternion = d.normalized().to_track_quat("Z", "Y")
            out.append(ob)


def door(name, s, W, z0, z1, y0, y1):
    """A door skin just proud of the side, paint over a dark sill."""
    x = s * (W / 2 + 0.012)
    bm = bmesh.new()
    ys = [y0 + (y1 - y0) * k / 3 for k in range(4)]
    zs = [z0 + (z1 - z0) * k / 4 for k in range(5)]
    grid = [[bm.verts.new(g2b((x, y, z))) for z in zs] for y in ys]
    faces = []
    for r in range(len(ys) - 1):
        for c in range(len(zs) - 1):
            q = (grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c])
            faces.append(bm.faces.new(q if s > 0 else tuple(reversed(q))))
    r = bmesh.ops.extrude_face_region(bm, geom=faces)
    for v in [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.x -= s * 0.025
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = obj_from_bm(name, bm, [mat("paint", PAINT)])
    h = gbox(name + "_handle", (0.02, 0.03, 0.14), (x + s * 0.012, y1 - 0.12, z0 + (0.18 if z1 > z0 else -0.18)), mat("black", BLACK))
    attach(h, ob)
    return ob


def lamps(out, L, W, y_front, y_rear, z_front=None, z_rear=None):
    zf = L / 2 if z_front is None else z_front
    zr = -L / 2 if z_rear is None else z_rear
    for s in (-1, 1):
        out.append(gbox("headlamp", (0.34, 0.12, 0.04), (s * (W / 2 - 0.3), y_front, zf - 0.005), mat("lamp", LAMP)))
        out.append(gbox("taillamp", (0.26, 0.16, 0.04), (s * (W / 2 - 0.2), y_rear, zr + 0.005), mat("tail", TAIL)))
    out.append(gbox("grille", (W * 0.35, 0.14, 0.03), (0, y_front - 0.02, zf), mat("black", BLACK)))


def seats(out, rows, y=-0.12):
    seat = mat("seat", SEAT)
    for z, pair in rows:
        if pair:
            for x in (-0.40, 0.40):
                out.append(gbox("interior_seat", (0.50, 0.12, 0.50), (x, y, z), seat, 0.03))
                out.append(gbox("interior_seatback", (0.50, 0.6, 0.12), (x, y + 0.32, z - 0.27), seat, 0.03))
        else:
            out.append(gbox("interior_bench", (1.40, 0.12, 0.50), (0, y, z), seat, 0.03))
            out.append(gbox("interior_benchback", (1.40, 0.55, 0.12), (0, y + 0.3, z - 0.25), seat, 0.03))


def _doors(out):
    found = {}
    for o in out:
        for sn in ("l", "r"):
            if o.name == "door_f" + sn:
                found[sn] = o
    return found


def wheel(r, width=0.24):
    t = cyl("wheel", r, width, (0, 0, 0), "x", mat("tyre", BLACK), 18)
    rim = cyl("wheel_rim", r * 0.6, width + 0.02, (0, 0, 0), "x", mat("chrome", CHROME), 12)
    attach(rim, t)
    return t


def mirrors(out, W, y, z):
    for s, sn in ((1, "r"), (-1, "l")):
        out.append(gbox("mirror_" + sn, (0.10, 0.12, 0.16), (s * (W / 2 + 0.08), y, z), mat("black", BLACK), 0.02))


def bumpers(out, L, W, y):
    out.append(gbox("bumper_f", (W + 0.04, 0.24, 0.2), (0, y, L / 2 + 0.04), mat("grey", GREY), 0.03))
    out.append(gbox("bumper_r", (W + 0.04, 0.24, 0.2), (0, y, -L / 2 - 0.04), mat("grey", GREY), 0.03))


def top_panel(name, W, top_fn, z0, z1):
    bm = bmesh.new()
    nx, nzs = 6, 6
    grid = []
    for i in range(nzs + 1):
        z = z0 + (z1 - z0) * i / nzs
        y = top_fn(z) + 0.012
        grid.append([bm.verts.new(g2b((-W / 2 + 0.08 + (W - 0.16) * j / nx, y, z))) for j in range(nx + 1)])
    faces = []
    for i in range(nzs):
        for j in range(nx):
            q = (grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j])
            faces.append(bm.faces.new(q if z1 > z0 else tuple(reversed(q))))
    r = bmesh.ops.extrude_face_region(bm, geom=faces)
    for v in [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.z -= 0.025
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return obj_from_bm(name, bm, [mat("paint", PAINT)])


# --- the vehicles ----------------------------------------------------------------------

def car(spec):
    """Saloon or hatchback."""
    L, W = spec["L"], spec["W"]
    belt = spec["belt"]
    bf = spec["cab_front"][0]
    br = spec["cab_rear"][0]

    def top(z):
        if z > bf - 0.05:
            k = (z - bf) / max(0.01, (L / 2 - bf))
            return belt - 0.10 * k * k
        if z < br:
            k = (br - z) / max(0.01, (br + L / 2))
            return belt - 0.04 * k
        return belt

    out = [lofted_body("body", L, W, -0.42, top, mat("paint", PAINT))]
    cabin(spec, out)
    bp = spec.get("b_pillar", (bf + br) / 2)
    for s, sn in ((1, "r"), (-1, "l")):
        out.append(door("door_f" + sn, s, W, bf - 0.12, bp + 0.01, -0.32, belt - 0.06))
        if spec.get("rear_doors", True):
            out.append(door("door_r" + sn, s, W, bp - 0.01, br + 0.05, -0.32, belt - 0.06))
    out.append(top_panel("bonnet", W, top, bf + 0.05, L / 2 - 0.12))
    if br - (-L / 2) > 0.4:
        out.append(top_panel("boot", W, top, br - 0.05, -L / 2 + 0.10))
    bumpers(out, L, W, -0.24)
    mirrors(out, W, belt + 0.12, bf - 0.15)
    lamps(out, L, W, 0.10, 0.12)
    I.fit_out(sys.modules[__name__], out, W, [(0.05, "pair"), (-0.80, "bench")], -0.12, -0.27,
              (0.22, bf - 0.13, 0.34), (0.30, 0.50), roof_y=spec["roof"], screen_z=spec["cab_front"][1],
              doors=_doors(out), shelf=(belt + 0.03, br + 0.20) if br - (-L / 2) > 0.4 else None)
    return out


def van(spec, kind):
    """Panel van, minibus, or luton (box) van. Tall single-volume cabin."""
    L, W = spec["L"], spec["W"]
    belt = spec["belt"]
    bf = spec["cab_front"][0]
    nose = L / 2

    def top(z):
        if z > bf:
            k = (z - bf) / max(0.01, nose - bf)
            return belt - 0.12 * k
        return belt

    out = [lofted_body("body", L, W, -0.45, top, mat("paint", PAINT))]
    if kind == "box":
        # Short cab, then a tall box body behind it.
        cspec = dict(spec)
        cspec["cab_rear"] = (spec["box_front"], spec["box_front"])
        cspec["rear_window"] = False
        cabin(cspec, out, side_windows="front")
        bz0 = spec["box_front"] - 0.05
        bz1 = -L / 2
        bh = spec["box_top"]
        box = gbox("cargo_box", (W + 0.1, bh - belt + 0.1, bz0 - bz1), (0, (bh + belt) / 2 - 0.05, (bz0 + bz1) / 2), mat("paint", PAINT), 0.02)
        out.append(box)
        out.append(gbox("cargo_luton", (W + 0.1, 0.6, 0.9), (0, bh - 0.35, bz0 + 0.45), mat("paint", PAINT), 0.04))
        out.append(gbox("shutter", (W - 0.2, bh - belt - 0.1, 0.03), (0, (bh + belt) / 2 - 0.05, bz1 - 0.02), mat("grey", GREY)))
    else:
        cabin(spec, out, side_windows="all" if kind == "minibus" else "front")
    bp = spec.get("b_pillar", bf - 1.0)
    for s, sn in ((1, "r"), (-1, "l")):
        out.append(door("door_f" + sn, s, W, bf - 0.12, bp + 0.01, -0.35, belt - 0.06))
        if kind == "minibus" or (kind == "panel" and s > 0):
            out.append(door("door_r" + sn, s, W, bp - 0.05, bp - 1.25, -0.35, belt + 0.8))
    out.append(top_panel("bonnet", W, top, bf + 0.05, nose - 0.1))
    if kind != "box":
        out.append(gbox("boot", (W - 0.1, spec["roof"] - (-0.3), 0.05), (0, (spec["roof"] - 0.3) / 2, -L / 2 - 0.03), mat("paint", PAINT)))
    bumpers(out, L, W, -0.26)
    mirrors(out, W, belt + 0.25, bf - 0.15)
    lamps(out, L, W, 0.12, 0.2)
    rows = [(bf - 0.85, "pair")]
    if kind == "minibus":
        rows += [(bf - 1.8, "bench"), (bf - 2.6, "bench"), (bf - 3.4, "bench")]
    I.fit_out(sys.modules[__name__], out, W, rows, -0.12, -0.28, (belt - 0.04, bf - 0.18, 0.40), (belt + 0.04, bf - 0.47),
              roof_y=spec["roof"], screen_z=spec["cab_front"][1], doors=_doors(out))
    return out


def trash_truck(spec):
    L, W = spec["L"], spec["W"]
    out = []
    cab_z0, cab_z1 = L / 2 - 1.9, L / 2
    chassis = gbox("body", (W - 0.3, 0.4, L - 0.2), (0, -0.55, 0), mat("dark", DARK))
    out.append(chassis)
    # Cab: tall, flat-fronted.
    out.append(gbox("cab_shell", (W, 1.0, cab_z1 - cab_z0), (0, -0.05, (cab_z0 + cab_z1) / 2), mat("paint", PAINT), 0.03))
    out.append(gbox("roof", (W, 0.08, cab_z1 - cab_z0 - 0.2), (0, 1.55, (cab_z0 + cab_z1) / 2 - 0.1), mat("paint", PAINT), 0.02))
    out.append(quad("win_front", [(-W / 2 + 0.1, 0.5, cab_z1), (W / 2 - 0.1, 0.5, cab_z1), (W / 2 - 0.12, 1.5, cab_z1 - 0.08), (-W / 2 + 0.12, 1.5, cab_z1 - 0.08)], mat("glass", GLASS)))
    for s, sn in ((1, "r"), (-1, "l")):
        x = s * (W / 2)
        out.append(quad("win_f" + sn, [(x, 0.5, cab_z1 - 0.15), (x, 0.5, cab_z0 + 0.4), (x, 1.45, cab_z0 + 0.4), (x, 1.45, cab_z1 - 0.2)] if s > 0 else
                        [(x, 0.5, cab_z0 + 0.4), (x, 0.5, cab_z1 - 0.15), (x, 1.45, cab_z1 - 0.2), (x, 1.45, cab_z0 + 0.4)], mat("glass", GLASS)))
        out.append(door("door_f" + sn, s, W, cab_z1 - 0.15, cab_z0 + 0.35, -0.5, 0.45))
        for y, ln in ((1.52, 0.04),):
            pass
    for x in (-W / 2 + 0.25, W / 2 - 0.25):
        out.append(gbox("cab_pillar", (0.08, 1.05, 0.08), (x, 1.0, cab_z1 - 0.05), mat("paint", PAINT)))
    # Compactor body: tall box, high-vis band.
    bz1 = cab_z0 - 0.15
    bz0 = -L / 2 + 0.9
    out.append(gbox("compactor", (W, 2.6, bz1 - bz0), (0, 0.75, (bz0 + bz1) / 2), mat("paint", PAINT), 0.05))
    out.append(gbox("band", (W + 0.02, 0.18, bz1 - bz0), (0, 0.2, (bz0 + bz1) / 2), mat("orange", ORANGE)))
    # Rear hopper and the bin lifter (a part the game moves up and down).
    out.append(gbox("hopper", (W, 2.2, 0.9), (0, 0.45, -L / 2 + 0.45), mat("grey", GREY), 0.04))
    lift = gbox("bin_lifter", (1.4, 0.5, 0.25), (0, -0.25, -L / 2 - 0.15), mat("steel", STEEL), 0.02)
    out.append(lift)
    mirrors(out, W, 1.0, cab_z1 - 0.3)
    out.append(gbox("bumper_f", (W + 0.04, 0.3, 0.2), (0, -0.55, L / 2 + 0.08), mat("grey", GREY), 0.03))
    lamps(out, L, W, -0.2, 0.0, cab_z1 + 0.01, -L / 2 - 0.02)
    I.fit_out(sys.modules[__name__], out, W, [(cab_z0 + 0.8, "pair")], 0.0, -0.16, (0.40, cab_z1 - 0.28, 0.36), (0.55, cab_z1 - 0.62),
              roof_y=1.52, screen_z=cab_z1 - 0.08, doors=_doors(out))
    return out


def hgv_tractor(spec):
    L, W = spec["L"], spec["W"]
    out = []
    cab_z0, cab_z1 = L / 2 - 2.2, L / 2
    out.append(gbox("body", (W - 0.5, 0.45, L - 0.3), (0, -0.55, -0.1), mat("dark", DARK)))
    out.append(gbox("cab_shell", (W, 1.3, cab_z1 - cab_z0), (0, 0.1, (cab_z0 + cab_z1) / 2), mat("paint", PAINT), 0.04))
    out.append(gbox("roof", (W, 0.7, cab_z1 - cab_z0 - 0.15), (0, 1.75, (cab_z0 + cab_z1) / 2 - 0.08), mat("paint", PAINT), 0.08))
    out.append(quad("win_front", [(-W / 2 + 0.1, 0.8, cab_z1), (W / 2 - 0.1, 0.8, cab_z1), (W / 2 - 0.12, 1.4, cab_z1 - 0.06), (-W / 2 + 0.12, 1.4, cab_z1 - 0.06)], mat("glass", GLASS)))
    for s, sn in ((1, "r"), (-1, "l")):
        x = s * (W / 2)
        pts = [(x, 0.8, cab_z1 - 0.15), (x, 0.8, cab_z1 - 1.1), (x, 1.38, cab_z1 - 1.1), (x, 1.38, cab_z1 - 0.18)]
        out.append(quad("win_f" + sn, pts if s > 0 else [pts[1], pts[0], pts[3], pts[2]], mat("glass", GLASS)))
        out.append(door("door_f" + sn, s, W, cab_z1 - 0.15, cab_z1 - 1.15, -0.4, 0.75))
        out.append(gbox("fuel_tank", (0.5, 0.55, 1.2), (s * (W / 2 - 0.3), -0.45, cab_z0 - 0.8), mat("chrome", CHROME), 0.08))
        out.append(gbox("stack", (0.14, 1.6, 0.14), (s * (W / 2 - 0.15), 1.4, cab_z0 - 0.08), mat("chrome", CHROME)))
    out.append(gbox("fifth_wheel", (1.0, 0.12, 1.0), (0, -0.25, -L / 2 + 1.0), mat("black", BLACK)))
    out.append(gbox("grille", (W * 0.6, 0.6, 0.04), (0, 0.1, cab_z1 + 0.01), mat("chrome", CHROME)))
    out.append(gbox("bumper_f", (W + 0.04, 0.35, 0.25), (0, -0.5, L / 2 + 0.1), mat("grey", GREY), 0.04))
    mirrors(out, W, 1.1, cab_z1 - 0.35)
    for s in (-1, 1):
        out.append(gbox("headlamp", (0.36, 0.14, 0.04), (s * (W / 2 - 0.35), -0.35, cab_z1 + 0.06), mat("lamp", LAMP)))
    I.fit_out(sys.modules[__name__], out, W, [(cab_z0 + 1.0, "pair")], 0.25, 0.08, (0.68, cab_z1 - 0.28, 0.36), (0.82, cab_z1 - 0.62),
              roof_y=1.40, screen_z=cab_z1 - 0.06, doors=_doors(out))
    return out


def trailer(spec, kind):
    L, W = spec["L"], spec["W"]
    out = [gbox("body", (W - 0.2, 0.35, L), (0, -0.45, 0), mat("dark", DARK))]
    if kind == "box":
        out.append(gbox("cargo_box", (W, 2.7, L - 0.1), (0, 1.1, 0), mat("paint", PAINT), 0.04))
        out.append(gbox("doors", (W - 0.1, 2.5, 0.04), (0, 1.05, -L / 2 - 0.02), mat("grey", GREY)))
    elif kind == "tanker":
        t = cyl("tank", 1.15, L - 1.0, (0, 1.0, 0.2), "z", mat("tank", TANK), 24)
        out.append(t)
        out.append(gbox("walkway", (0.6, 0.05, L - 2.0), (0, 2.18, 0.2), mat("grey", GREY)))
        for z in (-L / 2 + 1.0, L / 2 - 0.6):
            out.append(gbox("cap", (2.0, 0.2, 0.2), (0, 0.0, z), mat("dark", DARK)))
    else:
        out.append(gbox("deck", (W, 0.12, L), (0, -0.2, 0), mat("wood", WOOD)))
        for z in range(-5, 6, 2):
            out.append(gbox("load", (W - 0.3, 0.9, 1.2), (0, 0.35, z * 1.0), mat("paint", PAINT), 0.05))
    out.append(gbox("kingpin_plate", (1.0, 0.1, 1.2), (0, -0.62, L / 2 - 1.0), mat("black", BLACK)))
    for s in (-1, 1):
        out.append(gbox("landing_leg", (0.12, 0.9, 0.12), (s * 0.8, -0.95, L / 2 - 2.5), mat("grey", GREY)))
        out.append(gbox("taillamp", (0.3, 0.15, 0.04), (s * (W / 2 - 0.25), -0.35, -L / 2 - 0.01), mat("tail", TAIL)))
    out.append(gbox("bumper_r", (W - 0.2, 0.2, 0.15), (0, -0.75, -L / 2 + 0.05), mat("grey", GREY)))
    return out


def motorbike(spec):
    out = []
    out.append(gbox("body", (0.32, 0.4, 1.0), (0, 0.05, 0.0), mat("paint", PAINT), 0.08))
    out.append(gbox("tank", (0.36, 0.22, 0.5), (0, 0.32, 0.2), mat("paint", PAINT), 0.08))
    out.append(gbox("seat", (0.3, 0.1, 0.6), (0, 0.32, -0.3), mat("black", BLACK), 0.04))
    out.append(gbox("engine", (0.36, 0.3, 0.4), (0, -0.2, 0.05), mat("chrome", CHROME), 0.04))
    out.append(gbox("fork", (0.08, 0.7, 0.08), (0, 0.0, 0.72), mat("chrome", CHROME)))
    out.append(gbox("handlebar", (0.7, 0.04, 0.04), (0, 0.42, 0.62), mat("black", BLACK)))
    out.append(gbox("headlamp", (0.16, 0.12, 0.06), (0, 0.3, 0.78), mat("lamp", LAMP)))
    out.append(gbox("taillamp", (0.12, 0.06, 0.04), (0, 0.2, -0.62), mat("tail", TAIL)))
    out.append(gbox("exhaust", (0.08, 0.08, 0.6), (0.2, -0.25, -0.3), mat("chrome", CHROME)))
    return out


SPECS = {
    "sedan": {"L": 4.5, "W": 1.82, "belt": 0.28, "roof": 0.97, "cab_front": (0.85, 0.2), "cab_rear": (-1.2, -0.75), "b_pillar": -0.25, "wheel": 0.34},
    "hatchback": {"L": 3.9, "W": 1.74, "belt": 0.3, "roof": 1.0, "cab_front": (0.75, 0.15), "cab_rear": (-1.75, -1.5), "b_pillar": -0.3, "wheel": 0.32},
    "van_panel": {"L": 5.2, "W": 2.0, "belt": 0.4, "roof": 1.6, "cab_front": (1.6, 1.05), "cab_rear": (-2.55, -2.55), "b_pillar": 0.35, "wheel": 0.36, "rear_window": False},
    "van_box": {"L": 6.0, "W": 2.05, "belt": 0.4, "roof": 1.5, "cab_front": (2.0, 1.45), "cab_rear": (0.6, 0.6), "b_pillar": 0.65, "box_front": 0.6, "box_top": 2.4, "wheel": 0.38},
    "minibus": {"L": 5.6, "W": 2.0, "belt": 0.45, "roof": 1.65, "cab_front": (1.9, 1.3), "cab_rear": (-2.7, -2.7), "b_pillar": 0.75, "wheel": 0.36},
    "trash_truck": {"L": 8.2, "W": 2.45, "wheel": 0.52},
    "hgv_tractor": {"L": 5.9, "W": 2.48, "wheel": 0.52},
    "trailer_box": {"L": 12.0, "W": 2.5, "wheel": 0.48},
    "trailer_tanker": {"L": 11.0, "W": 2.5, "wheel": 0.48},
    "trailer_flatbed": {"L": 12.0, "W": 2.5, "wheel": 0.48},
    "motorbike": {"L": 2.1, "W": 0.75, "wheel": 0.32},
}


def build(name):
    C.reset()
    MATS.clear()
    spec = SPECS[name]
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    if name in ("sedan", "hatchback"):
        parts = car(spec)
    elif name == "van_panel":
        parts = van(spec, "panel")
    elif name == "van_box":
        parts = van(spec, "box")
    elif name == "minibus":
        parts = van(spec, "minibus")
    elif name == "trash_truck":
        parts = trash_truck(spec)
    elif name == "hgv_tractor":
        parts = hgv_tractor(spec)
    elif name.startswith("trailer_"):
        parts = trailer(spec, name.split("_")[1])
    else:
        parts = motorbike(spec)
    parts.append(wheel(spec["wheel"], 0.12 if name == "motorbike" else (0.32 if spec["wheel"] > 0.45 else 0.24)))
    for p in parts:
        if p.parent is None:
            p.parent = root
    C.export_glb("assets/models/vehicles/%s.glb" % name)


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if a in SPECS] or list(SPECS)
    for n in names:
        build(n)
