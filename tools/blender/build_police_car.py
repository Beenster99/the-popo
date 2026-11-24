"""Police car for Phase 1.3: assets/models/vehicles/police_car.glb.

Every part is its own object so the game can dent, shatter or knock it off:
  body                 lower shell, finely divided so it dents
  roof, pillar_*       the cabin frame
  win_front, win_rear, win_fl, win_fr, win_rl, win_rr   glass (shatters)
  door_fl, door_fr, door_rl, door_rr, bonnet, boot      panels (dent, come off)
  bumper_f, bumper_r, push_bar, mirror_l, mirror_r       come off
  lightbar, lens_red, lens_blue                          roof lights
  interior_*           seats, dash, wheel (seen through the glass)
  wheel                one wheel, instanced four times by the game

Written in Godot's axes (x right, y up, z forward) and turned into Blender's
(x, -z, y) here, so numbers match car.gd: the body box is 1.86 x 0.9 x 4.3,
centred on the car's origin.

    python tools/blender/build_police_car.py
"""
import math
import os
import sys

import bpy  # noqa: I001 (bpy first: it makes bmesh importable)
import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import common as C  # noqa: E402

WHITE = (0.93, 0.93, 0.91)
NAVY = (0.06, 0.12, 0.30)
HIVIS = (0.95, 0.85, 0.10)
BLACK = (0.06, 0.06, 0.07)
GREY = (0.20, 0.20, 0.22)
GLASS = (0.12, 0.17, 0.22)
SEAT = (0.10, 0.10, 0.12)
RED = (0.95, 0.10, 0.12)
BLUE = (0.10, 0.30, 1.00)
LAMP = (1.00, 0.96, 0.80)
TAIL = (0.70, 0.05, 0.05)
CHROME = (0.65, 0.66, 0.68)

MATS = {}


def mat(name, col):
    if name not in MATS:
        MATS[name] = C.material(name, col)
    return MATS[name]


def g2b(p):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return (p[0], -p[2], p[1])


def attach(child, parent):
    """Parent without moving: children are placed in car space."""
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
    """Box given in Godot axes."""
    return C.box(name, (size[0], size[2], size[1]), g2b(centre), m, bevel=bevel)


def quad(name, pts, m, thick=0.02):
    """A thin panel through four Godot-space corners (in order), given a
    little thickness along its normal so it has a back and casts shadow."""
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


# --- the lower body: lofted cross-sections, finely divided ---------------

L = 4.3
W = 1.84
BOTTOM = -0.42
BELT = 0.30


def top_at(z):
    """Height of the body's top line (bonnet, deck) along its length."""
    if z > 0.75:      # bonnet slopes down to the nose
        k = (z - 0.75) / (L / 2 - 0.75)
        return BELT - 0.10 * k * k
    if z < -1.15:     # boot deck, slight drop at the tail
        k = (-1.15 - z) / (L / 2 - 1.15)
        return BELT - 0.04 * k
    return BELT


def section(z):
    """Points round the body at station z, Godot x/y, going round once."""
    t = top_at(z)
    hw = W / 2
    # The nose and tail round off in plan.
    end = max(0.0, abs(z) - (L / 2 - 0.35)) / 0.35
    hw *= 1.0 - 0.10 * end * end
    pts = [
        (-hw + 0.05, BOTTOM), (hw - 0.05, BOTTOM),        # floor
        (hw, BOTTOM + 0.12), (hw, t - 0.10),              # right side
        (hw - 0.06, t), (-hw + 0.06, t),                  # top
        (-hw, t - 0.10), (-hw, BOTTOM + 0.12),            # left side
    ]
    return pts


def build_body():
    bm = bmesh.new()
    nz = 28
    rings = []
    for i in range(nz + 1):
        z = -L / 2 + L * i / nz
        sec = section(z)
        # Split each side of the section so the sides dent smoothly too.
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
    # End caps.
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = obj_from_bm("body", bm, [mat("white", WHITE)])
    # Navy skirt and hi-vis band painted by face height.
    me = ob.data
    me.materials.append(mat("navy", NAVY))
    me.materials.append(mat("hivis", HIVIS))
    for p in me.polygons:
        c = p.center  # Blender coords: z is up
        if c.z < -0.20 and abs(p.normal.z) < 0.7:
            p.material_index = 1
        elif -0.06 < c.z < 0.08 and abs(p.normal.z) < 0.7:
            p.material_index = 2
    return ob


# --- cabin -----------------------------------------------------------------

CAB_B = BELT            # base height
CAB_T = 1.00            # roof height
B_FRONT, B_REAR = 0.80, -1.10      # base of windscreen / rear window
T_FRONT, T_REAR = 0.15, -0.72      # top of windscreen / rear window
B_HW, T_HW = 0.86, 0.70            # half widths at base and roof
B_PILLAR = -0.22                   # B-pillar


def cab(x_sign, y, z):
    """A point on the cabin side at height y between base and roof."""
    k = (y - CAB_B) / (CAB_T - CAB_B)
    hw = B_HW + (T_HW - B_HW) * k
    return (x_sign * hw, y, z)


def build_cabin():
    out = []
    glass = mat("glass", GLASS)
    white = mat("white", WHITE)
    black = mat("black", BLACK)
    i = 0.02
    out.append(quad("win_front", [(-B_HW + 0.05, CAB_B + i, B_FRONT), (B_HW - 0.05, CAB_B + i, B_FRONT),
                                  (T_HW - 0.05, CAB_T - i, T_FRONT), (-T_HW + 0.05, CAB_T - i, T_FRONT)], glass))
    out.append(quad("win_rear", [(B_HW - 0.05, CAB_B + i, B_REAR), (-B_HW + 0.05, CAB_B + i, B_REAR),
                                 (-T_HW + 0.05, CAB_T - i, T_REAR), (T_HW - 0.05, CAB_T - i, T_REAR)], glass))

    def side(name, s, z0, z1, zt0, zt1):
        a = cab(s, CAB_B + i, z0)
        b = cab(s, CAB_B + i, z1)
        c = cab(s, CAB_T - i, zt1)
        d = cab(s, CAB_T - i, zt0)
        pts = [a, b, c, d] if s > 0 else [b, a, d, c]
        out.append(quad(name, pts, glass))

    # Side windows: the front pair runs from the windscreen to the B-pillar.
    side("win_fr", 1, B_FRONT - 0.10, B_PILLAR + 0.05, T_FRONT - 0.02, B_PILLAR + 0.05)
    side("win_fl", -1, B_FRONT - 0.10, B_PILLAR + 0.05, T_FRONT - 0.02, B_PILLAR + 0.05)
    side("win_rr", 1, B_PILLAR - 0.05, B_REAR + 0.12, B_PILLAR - 0.05, T_REAR + 0.02)
    side("win_rl", -1, B_PILLAR - 0.05, B_REAR + 0.12, B_PILLAR - 0.05, T_REAR + 0.02)
    # Roof and pillars in body white.
    out.append(gbox("roof", (T_HW * 2 + 0.06, 0.05, T_FRONT - T_REAR + 0.08), (0, CAB_T + 0.02, (T_FRONT + T_REAR) / 2), white, 0.015))
    for s in (-1, 1):
        nm = "l" if s < 0 else "r"
        for tag, zb, zt in (("a", B_FRONT - 0.04, T_FRONT), ("b", B_PILLAR, B_PILLAR), ("c", B_REAR + 0.04, T_REAR)):
            pb = cab(s, CAB_B, zb)
            pt = cab(s, CAB_T, zt)
            bm = bmesh.new()
            mid = [(pb[0] + pt[0]) / 2, (pb[1] + pt[1]) / 2, (pb[2] + pt[2]) / 2]
            length = math.dist(pb, pt)
            bmesh.ops.create_cube(bm, size=1.0)
            for v in bm.verts:
                v.co.x *= 0.07
                v.co.y *= 0.09
                v.co.z *= length + 0.02
            ob = obj_from_bm("pillar_%s%s" % (tag, nm), bm, [black if tag == "b" else white])
            ob.location = g2b(mid)
            d = Vector(g2b(pt)) - Vector(g2b(pb))
            # Tilt the pillar from upright to follow the cabin.
            ob.rotation_mode = "QUATERNION"
            ob.rotation_quaternion = d.normalized().to_track_quat("Z", "Y")
            out.append(ob)
    return out


# --- panels -----------------------------------------------------------------

def side_panel(name, s, z0, z1, m_top, text=None):
    """A door skin standing just proud of the body side."""
    x = s * (W / 2 + 0.012)
    bm = bmesh.new()
    rows = [(-0.30, mat("navy", NAVY)), (-0.20, mat("white", WHITE))]
    verts = []
    ys = [-0.30, -0.20, -0.06, 0.08, BELT - 0.08]
    zs = [z0 + (z1 - z0) * k / 4 for k in range(5)]
    grid = [[bm.verts.new(g2b((x, y, z))) for z in zs] for y in ys]
    faces = []
    for r in range(len(ys) - 1):
        for c in range(len(zs) - 1):
            q = (grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c])
            f = bm.faces.new(q if s > 0 else tuple(reversed(q)))
            f.material_index = 1 if r == 0 else (2 if r == 2 else 0)
            faces.append(f)
    r = bmesh.ops.extrude_face_region(bm, geom=faces)
    for v in [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.x -= s * 0.025
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = obj_from_bm(name, bm, [mat("white", WHITE), mat("navy", NAVY), mat("hivis", HIVIS)])
    # Door handle.
    h = gbox(name + "_handle", (0.02, 0.03, 0.14), (x + s * 0.012, 0.16, z0 - 0.18 if z0 > z1 else z0 + 0.18), mat("black", BLACK))
    attach(h, ob)
    if text:
        t = word(name + "_word", text, (x + s * 0.016, 0.012, (z0 + z1) / 2), s, 0.11, mat("navy", NAVY))
        attach(t, ob)
    return ob


def word(name, text, centre, s, size, m):
    bpy.ops.object.text_add()
    t = bpy.context.object
    t.name = name
    t.data.body = text
    t.data.size = size
    t.data.extrude = 0.004
    t.data.align_x = "CENTER"
    t.data.align_y = "CENTER"
    bpy.ops.object.convert(target="MESH")
    t = bpy.context.object
    t.data.materials.clear()
    t.data.materials.append(m)
    # Text is made flat on Blender's XY plane; stand it on the car side.
    # Facing out from the side (normal +x on the right, -x on the left) so the
    # word reads left to right from outside (it was mirrored before v0.15.0).
    t.rotation_euler = (math.pi / 2, 0, math.pi / 2 if s > 0 else -math.pi / 2)
    t.location = g2b(centre)
    return t


def top_panel(name, z0, z1, m):
    bm = bmesh.new()
    nx, nzs = 6, 6
    grid = []
    for i in range(nzs + 1):
        z = z0 + (z1 - z0) * i / nzs
        y = top_at(z) + 0.012
        row = []
        for j in range(nx + 1):
            x = -W / 2 + 0.08 + (W - 0.16) * j / nx
            row.append(bm.verts.new(g2b((x, y, z))))
        grid.append(row)
    faces = []
    for i in range(nzs):
        for j in range(nx):
            q = (grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j])
            faces.append(bm.faces.new(q if z1 > z0 else tuple(reversed(q))))
    r = bmesh.ops.extrude_face_region(bm, geom=faces)
    for v in [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.z -= 0.025
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return obj_from_bm(name, bm, [m])


def build_panels():
    out = []
    for s, sn in ((1, "r"), (-1, "l")):
        out.append(side_panel("door_f" + sn, s, B_FRONT - 0.12, B_PILLAR + 0.01, None, "POLICE"))
        out.append(side_panel("door_r" + sn, s, B_PILLAR - 0.01, B_REAR + 0.05, None))
    out.append(top_panel("bonnet", B_FRONT + 0.05, L / 2 - 0.12, mat("white", WHITE)))
    out.append(top_panel("boot", B_REAR - 0.05, -L / 2 + 0.10, mat("white", WHITE)))
    # Chevron of hi-vis on the boot and a word on the bonnet.
    stripe = gbox("boot_stripe", (W - 0.3, 0.004, 0.10), (0, top_at(-1.6) + 0.04, -1.6), mat("hivis", HIVIS))
    attach(stripe, out[-1])
    bw = word("bonnet_word", "POLICE", (0, top_at(1.5) + 0.04, 1.5), 1, 0.16, mat("navy", NAVY))
    bw.rotation_euler = (0, 0, math.pi)
    attach(bw, out[-2])
    out.append(gbox("bumper_f", (W + 0.04, 0.24, 0.20), (0, -0.24, L / 2 + 0.04), mat("grey", GREY), 0.03))
    out.append(gbox("bumper_r", (W + 0.04, 0.24, 0.20), (0, -0.24, -L / 2 - 0.04), mat("grey", GREY), 0.03))
    # Push bar: two uprights and a crossbar in front of the grille.
    pb = gbox("push_bar", (1.0, 0.05, 0.05), (0, 0.06, L / 2 + 0.16), mat("black", BLACK))
    for x in (-0.35, 0.35):
        u = gbox("push_bar_up", (0.05, 0.50, 0.05), (x, -0.12, L / 2 + 0.16), mat("black", BLACK))
        attach(u, pb)
    out.append(pb)
    for s, sn in ((1, "r"), (-1, "l")):
        m = gbox("mirror_" + sn, (0.10, 0.10, 0.16), (s * (B_HW + 0.10), BELT + 0.12, B_FRONT - 0.15), mat("black", BLACK), 0.02)
        out.append(m)
    return out


def build_details():
    out = []
    # Lamps and grille (fixed to the body).
    for s in (-1, 1):
        out.append(gbox("headlamp", (0.36, 0.11, 0.04), (s * 0.58, 0.10, L / 2 - 0.01), mat("lamp", LAMP)))
        out.append(gbox("taillamp", (0.34, 0.13, 0.04), (s * 0.62, 0.12, -L / 2 + 0.01), mat("tail", TAIL)))
    out.append(gbox("grille", (0.62, 0.14, 0.03), (0, 0.06, L / 2 + 0.005), mat("black", BLACK)))
    out.append(gbox("plate_f", (0.44, 0.10, 0.02), (0, -0.18, L / 2 + 0.15), mat("lamp", LAMP)))
    out.append(gbox("plate_r", (0.44, 0.10, 0.02), (0, 0.0, -L / 2 - 0.01), mat("lamp", LAMP)))
    # Roof lights.
    zl = (T_FRONT + T_REAR) / 2 + 0.05
    out.append(gbox("lightbar", (1.10, 0.06, 0.24), (0, CAB_T + 0.075, zl), mat("black", BLACK), 0.01))
    out.append(gbox("lens_red", (0.48, 0.09, 0.22), (-0.27, CAB_T + 0.15, zl), mat("red", RED), 0.02))
    out.append(gbox("lens_blue", (0.48, 0.09, 0.22), (0.27, CAB_T + 0.15, zl), mat("blue", BLUE), 0.02))
    # Interior: seats, dash, steering wheel, a cage between front and rear.
    seat = mat("seat", SEAT)
    for x in (-0.40, 0.40):
        out.append(gbox("interior_seat", (0.50, 0.12, 0.50), (x, -0.12, 0.05), seat, 0.03))
        out.append(gbox("interior_seatback", (0.50, 0.62, 0.12), (x, 0.20, -0.22), seat, 0.03))
    out.append(gbox("interior_bench", (1.40, 0.12, 0.50), (0, -0.12, -0.80), seat, 0.03))
    out.append(gbox("interior_benchback", (1.40, 0.55, 0.12), (0, 0.18, -1.05), seat, 0.03))
    out.append(gbox("interior_dash", (1.60, 0.20, 0.30), (0, 0.24, 0.72), mat("black", BLACK)))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.17, minor_radius=0.02, major_segments=20, minor_segments=6)
    wh = bpy.context.object
    wh.name = "interior_wheel"
    wh.location = g2b((-0.40, 0.32, 0.50))
    wh.rotation_euler = (math.radians(65), 0, 0)
    wh.data.materials.append(mat("black", BLACK))
    out.append(wh)
    out.append(gbox("interior_cage", (1.60, 0.55, 0.02), (0, 0.45, -0.42), mat("grey", GREY)))
    return out


def build_wheel():
    """One wheel round Godot's x axis, centred on the origin."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=18, radius=0.36, depth=0.24)
    tyre = bpy.context.object
    tyre.name = "wheel"
    tyre.rotation_euler = (0, math.pi / 2, 0)
    tyre.data.materials.append(mat("tyre", BLACK))
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.22, depth=0.26)
    rim = bpy.context.object
    rim.name = "wheel_rim"
    rim.rotation_euler = (0, math.pi / 2, 0)
    rim.data.materials.append(mat("chrome", CHROME))
    attach(rim, tyre)
    return tyre


def main():
    C.reset()
    root = bpy.data.objects.new("police_car", None)
    bpy.context.scene.collection.objects.link(root)
    parts = [build_body()] + build_cabin() + build_panels() + build_details() + [build_wheel()]
    for p in parts:
        if p.parent is None:
            p.parent = root
    C.export_glb("assets/models/vehicles/police_car.glb")


main()
