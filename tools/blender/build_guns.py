"""Pistols for the armoury inspection bench: assets/models/guns/pistols.glb.

One root per pistol, pistol_0 .. pistol_5 (the order of Armoury.PISTOLS).
Every part a bench upgrade changes is its own object, so the game shows or
hides it by name (each name starts "p<n>_", e.g. p2_mag_ext):

  mag_std, mag_ext       standard / extended magazine (revolver: cylinder)
  barrel_std, barrel_match   factory / match barrel (match: bronze, a little longer)
  comp, comp_m           compensator for the factory / match barrel muzzle
  loader                 speed loader: flared magwell, or a revolver speed loader
  torch                  under-barrel tactical torch
  everything else        the gun itself, always shown

Blender axes: X along the barrel (muzzle at +X), Z up, Y to the gun's left.
Exported Y up, so X stays the barrel axis in Godot. Sizes are real (metres);
the grip's top is near the origin.

    python tools/blender/build_guns.py
"""
import math
import os
import sys

import bpy  # noqa: I001 (bpy first: it makes bmesh importable)
import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import common as C  # noqa: E402

MATS = {}


def mat(name, col):
    if name not in MATS:
        MATS[name] = C.material("gun_" + name, col)
    return MATS[name]


BLUED = (0.07, 0.075, 0.085)
POLY = (0.045, 0.045, 0.05)
STEEL = (0.42, 0.43, 0.45)
BRIGHT = (0.70, 0.71, 0.73)
DARK = (0.015, 0.015, 0.02)
TAN = (0.45, 0.36, 0.22)
OD = (0.22, 0.25, 0.16)
WOOD = (0.36, 0.17, 0.07)
BRONZE = (0.78, 0.52, 0.16)
LENS = (1.0, 0.95, 0.70)
RED = (0.95, 0.12, 0.10)
GREEN = (0.20, 0.95, 0.30)
BRASS = (0.85, 0.65, 0.25)


def link(ob, parent):
    bpy.context.scene.collection.objects.link(ob)
    if parent is not None:
        bpy.context.view_layer.update()
        ob.parent = parent
        ob.matrix_parent_inverse = parent.matrix_world.inverted()
    return ob


def bevel(ob, w, segs=2):
    if w > 0:
        m = ob.modifiers.new("bevel", "BEVEL")
        m.width = w
        m.segments = segs
        m.limit_method = "ANGLE"
    return ob


def box(name, size, centre, m, parent, bev=0.0015, rot=None):
    """Box of size (x, y, z) at centre; rot = (axis, degrees) about centre."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat(*m))
    ob = bpy.data.objects.new(name, me)
    ob.location = centre
    if rot:
        ob.rotation_euler = Matrix.Rotation(math.radians(rot[1]), 3, rot[0]).to_euler()
    link(ob, parent)
    return bevel(ob, bev)


def wedge(name, x0, x1, z0, z1_back, z1_front, w, m, parent, y=0.0):
    """A box whose top slopes from back (x0) to front (x1)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    pts = [(x0, z0), (x1, z0), (x1, z1_front), (x0, z1_back)]
    vs = [bm.verts.new((px, y - w / 2, pz)) for px, pz in pts] + [bm.verts.new((px, y + w / 2, pz)) for px, pz in pts]
    bm.faces.new(vs[0:4][::-1])
    bm.faces.new(vs[4:8])
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((vs[i], vs[j], vs[4 + j], vs[4 + i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat(*m))
    ob = bpy.data.objects.new(name, me)
    link(ob, parent)
    return bevel(ob, 0.0015)


def cyl(name, r, length, centre, m, parent, axis="X", segs=24, bev=0.001, r2=None):
    """Cylinder (or cone with r2) along an axis, centred at centre."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r if r2 is None else r2, depth=length)
    if axis == "X":
        bmesh.ops.rotate(bm, verts=bm.verts[:], matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    elif axis == "Y":
        bmesh.ops.rotate(bm, verts=bm.verts[:], matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(mat(*m))
    ob = bpy.data.objects.new(name, me)
    ob.location = centre
    link(ob, parent)
    return bevel(ob, bev, 1)


def empty(name, parent=None, loc=(0, 0, 0)):
    ob = bpy.data.objects.new(name, None)
    ob.location = loc
    link(ob, parent)
    return ob


# ---------------------------------------------------------------- semi-autos
def semi(n, root, L, sh, w, gh, slide_c, frame_c, grip_c, *, hammer=False, rail=True,
         mag_long=0.0, cuts=False, front_sight=("bright", BRIGHT), rear_adj=False, angle=16.0):
    """A semi-automatic pistol. L slide length, sh slide height, w width,
    gh grip height, mag_long how far the standard magazine sticks out."""
    p = "p%d_" % n
    back = -0.045
    front = back + L
    # Slide, with a lower front where it narrows over the barrel.
    box(p + "slide", (L, w, sh), (back + L / 2, 0, 0.028 + sh / 2), slide_c, root, bev=0.0025)
    for i in range(6):   # rear serrations
        box(p + "serr%d" % i, (0.0018, w + 0.001, sh * 0.7), (back + 0.008 + i * 0.0045, 0, 0.028 + sh * 0.5), ("dark", DARK), root, bev=0)
    if cuts:   # lightening cuts along the top of a match slide
        for i in range(3):
            box(p + "cut%d" % i, (0.018, w * 0.55, 0.004), (back + L * 0.45 + i * 0.024, 0, 0.028 + sh), ("dark", DARK), root, bev=0.0008)
    # Ejection port, with the barrel hood showing through it.
    port_x = back + L * 0.42
    box(p + "port", (0.03, w * 0.5, 0.004), (port_x, -w * 0.18, 0.028 + sh), ("dark", DARK), root, bev=0)
    # Barrels: the factory hood is plain steel; the match one is bronze and
    # stands a little proud of the muzzle.
    std = empty(p + "barrel_std", root)
    box(p + "hood_s", (0.026, w * 0.42, 0.003), (port_x, -w * 0.18, 0.028 + sh + 0.0005), ("steel", STEEL), std, bev=0.0005)
    cyl(p + "muzzle_s", 0.0068, 0.004, (front + 0.001, 0, 0.028 + sh * 0.45), ("steel", STEEL), std)
    cyl(p + "bore_s", 0.0045, 0.0045, (front + 0.0015, 0, 0.028 + sh * 0.45), ("dark", DARK), std, bev=0)
    mat_b = empty(p + "barrel_match", root)
    box(p + "hood_m", (0.026, w * 0.42, 0.003), (port_x, -w * 0.18, 0.028 + sh + 0.0006), ("bronze", BRONZE), mat_b, bev=0.0005)
    cyl(p + "muzzle_m", 0.0075, 0.016, (front + 0.006, 0, 0.028 + sh * 0.45), ("bronze", BRONZE), mat_b)
    cyl(p + "bore_m", 0.0045, 0.0045, (front + 0.0125, 0, 0.028 + sh * 0.45), ("dark", DARK), mat_b, bev=0)
    # Sights.
    box(p + "fsight", (0.004, 0.0035, 0.006), (front - 0.008, 0, 0.028 + sh + 0.003), front_sight, root, bev=0.0006)
    if rear_adj:
        box(p + "rsight", (0.008, w * 0.95, 0.007), (back + 0.01, 0, 0.028 + sh + 0.0035), ("steel", STEEL), root, bev=0.0008)
        cyl(p + "rsight_knob", 0.0016, w * 1.2, (back + 0.01, 0, 0.028 + sh + 0.004), ("bright", BRIGHT), root, axis="Y", segs=10)
    else:
        box(p + "rsight", (0.006, w * 0.8, 0.005), (back + 0.01, 0, 0.028 + sh + 0.0025), ("blued", BLUED), root, bev=0.0008)
    for dy in (-0.0018, 0.0018):
        box(p + "dot%d" % (dy > 0), (0.0012, 0.0012, 0.0012), (back + 0.0065, dy, 0.028 + sh + 0.004), front_sight, root, bev=0)
    # Frame (dust cover runs forward under the slide).
    fl = L * 0.86
    box(p + "frame", (fl, w * 0.94, 0.02), (back + fl / 2 + 0.004, 0, 0.018), frame_c, root, bev=0.002)
    if rail:
        for i in range(4):
            box(p + "rail%d" % i, (0.005, w * 0.96, 0.004), (back + fl - 0.03 + i * 0.008, 0, 0.0065), frame_c, root, bev=0.0005)
    # Trigger guard: front post and bottom bar, square-fronted.
    tg_front = 0.045
    box(p + "tg_bot", (0.06, w * 0.55, 0.005), (0.016, 0, -0.026), frame_c, root, bev=0.0015)
    box(p + "tg_front", (0.006, w * 0.55, 0.034), (tg_front, 0, -0.011), frame_c, root, bev=0.0015)
    box(p + "trigger", (0.005, 0.006, 0.02), (0.01, 0, -0.007), ("blued", BLUED) if not hammer else ("steel", STEEL), root, bev=0.001, rot=("Y", -12))
    # Slide release and takedown.
    box(p + "release", (0.022, 0.003, 0.0035), (0.0, w * 0.5 + 0.0008, 0.026), ("blued", BLUED), root, bev=0.0006)
    if hammer:
        box(p + "hammer", (0.012, 0.007, 0.012), (back - 0.003, 0, 0.044), ("steel", STEEL), root, bev=0.002, rot=("Y", -25))
        box(p + "beaver", (0.018, w * 0.9, 0.006), (back - 0.006, 0, 0.022), frame_c, root, bev=0.002)
    # Grip: tilted back by "angle"; magazine parts hang off its bottom.
    grip = empty(p + "gripframe", root, (-0.022, 0, 0.012))
    grip.rotation_euler = (0, math.radians(angle), 0)
    box(p + "grip", (0.046, w * 1.02, gh + 0.014), (0, 0, -gh / 2 + 0.007), frame_c, grip, bev=0.003)
    for side in (-1, 1):
        box(p + "panel%d" % (side > 0), (0.036, 0.003, gh * 0.78), (0, side * (w * 0.51 + 0.0012), -gh * 0.48), grip_c, grip, bev=0.0012)
        for i in range(5):   # stippling rows
            box(p + "stip%d%d" % (side > 0, i), (0.03, 0.0008, 0.002), (0, side * (w * 0.51 + 0.0028), -gh * 0.22 - i * gh * 0.11), ("dark", DARK), grip, bev=0)
    box(p + "backstrap", (0.006, w * 0.9, gh * 0.9), (-0.025, 0, -gh * 0.48), frame_c, grip, bev=0.002)
    # Magazines.
    ms = empty(p + "mag_std", grip)
    box(p + "base_s", (0.044, w * 1.0, 0.007 + mag_long), (0.001, 0, -gh - (0.007 + mag_long) / 2 + 0.003), ("blued", BLUED), ms, bev=0.002)
    me_ = empty(p + "mag_ext", grip)
    ext = 0.032 + mag_long * 1.3
    box(p + "body_e", (0.036, w * 0.82, ext), (0.002, 0, -gh - ext / 2 + 0.002), ("blued", BLUED), me_, bev=0.002)
    box(p + "base_e", (0.046, w * 1.05, 0.008), (0.001, 0, -gh - ext - 0.002), ("bright", BRIGHT), me_, bev=0.002)
    for i in range(3):
        box(p + "ridge%d" % i, (0.0365, w * 0.84, 0.0025), (0.002, 0, -gh - 0.008 - i * ext * 0.28), ("dark", DARK), me_, bev=0)
    # Speed loader: a flared magwell funnel around the bottom of the grip.
    ld = empty(p + "loader", grip)
    box(p + "well", (0.052, w * 1.3, 0.012), (0.0, 0, -gh + 0.004), ("bright", BRIGHT), ld, bev=0.003)
    box(p + "well_lip", (0.056, w * 1.38, 0.004), (0.0, 0, -gh - 0.002), ("bright", BRIGHT), ld, bev=0.0015)
    # Compensator, for each barrel's muzzle.
    mz = 0.028 + sh * 0.45
    for tag, x0 in (("comp", front), ("comp_m", front + 0.007)):
        c = empty(p + tag, root)
        box(p + tag + "_body", (0.034, w * 1.0, sh * 0.95), (x0 + 0.017, 0, 0.028 + sh * 0.48), slide_c, c, bev=0.002)
        for i in range(3):
            box(p + tag + "_port%d" % i, (0.004, w * 0.5, 0.004), (x0 + 0.008 + i * 0.008, 0, 0.028 + sh * 0.95), ("dark", DARK), c, bev=0)
        cyl(p + tag + "_bore", 0.0048, 0.002, (x0 + 0.0345, 0, mz), ("dark", DARK), c, bev=0)
    # Tactical torch on the rail.
    t = empty(p + "torch", root)
    tx = back + fl - 0.02
    box(p + "torch_mount", (0.026, w * 1.05, 0.008), (tx, 0, 0.004), ("poly", POLY), t, bev=0.0015)
    cyl(p + "torch_body", 0.0135, 0.058, (tx + 0.008, 0, -0.012), ("poly", POLY), t)
    cyl(p + "torch_head", 0.0165, 0.016, (tx + 0.04, 0, -0.012), ("poly", POLY), t)
    cyl(p + "torch_lens", 0.0135, 0.002, (tx + 0.0485, 0, -0.012), ("lens", LENS), t, bev=0)
    box(p + "torch_switch", (0.01, 0.004, 0.006), (tx - 0.018, w * 0.5, -0.006), ("dark", DARK), t, bev=0.001)


# ---------------------------------------------------------------- revolver
def revolver(n, root):
    p = "p%d_" % n
    frame_c = ("steel", STEEL)
    box(p + "frame", (0.075, 0.03, 0.04), (0.01, 0, 0.028), frame_c, root, bev=0.003)
    box(p + "topstrap", (0.06, 0.02, 0.008), (0.012, 0, 0.051), frame_c, root, bev=0.002)
    box(p + "hammer", (0.014, 0.008, 0.02), (-0.03, 0, 0.05), ("bright", BRIGHT), root, bev=0.002, rot=("Y", -30))
    box(p + "rsight", (0.008, 0.012, 0.004), (-0.012, 0, 0.056), ("blued", BLUED), root, bev=0.0008)
    box(p + "tg_bot", (0.05, 0.012, 0.005), (0.012, 0, -0.018), frame_c, root, bev=0.0015)
    box(p + "tg_front", (0.006, 0.012, 0.03), (0.035, 0, -0.005), frame_c, root, bev=0.0015)
    box(p + "trigger", (0.005, 0.006, 0.022), (0.008, 0, -0.002), ("bright", BRIGHT), root, bev=0.001, rot=("Y", -12))
    box(p + "latch", (0.01, 0.004, 0.006), (-0.012, 0.016, 0.034), ("bright", BRIGHT), root, bev=0.001)
    # Cylinders: a 6-shot, or a fatter 9-shot with extended magazines.
    for tag, r, shots in (("mag_std", 0.019, 6), ("mag_ext", 0.0225, 9)):
        e = empty(p + tag, root)
        cyl(p + tag + "_cyl", r, 0.04, (0.018, 0, 0.03), ("steel", STEEL), e, segs=36, bev=0.002)
        for i in range(shots):   # flutes and chamber mouths
            a = 2 * math.pi * i / shots
            y, z = math.sin(a) * r * 0.97, math.cos(a) * r * 0.97
            box(p + tag + "_flute%d" % i, (0.024, 0.004, 0.004), (0.018, y, 0.03 + z), ("dark", DARK), e, bev=0.0008,
                rot=("X", -math.degrees(a)))
            yc, zc = math.sin(a + math.pi / shots) * r * 0.55, math.cos(a + math.pi / shots) * r * 0.55
            cyl(p + tag + "_ch%d" % i, 0.0045, 0.001, (0.0385, yc, 0.03 + zc), ("brass", BRASS), e, bev=0, segs=10)
    # Barrel with an underlug; the match barrel is heavier, bronze-lined and longer.
    for tag, L, col in (("barrel_std", 0.1, ("blued", BLUED)), ("barrel_match", 0.125, ("steel", STEEL))):
        e = empty(p + tag, root)
        cyl(p + tag + "_tube", 0.0085, L, (0.045 + L / 2, 0, 0.042), col, e, bev=0.0015)
        box(p + tag + "_rib", (L, 0.008, 0.006), (0.045 + L / 2, 0, 0.051), col, e, bev=0.0015)
        box(p + tag + "_lug", (L * (0.95 if tag == "barrel_match" else 0.6), 0.012, 0.014), (0.045 + L * (0.475 if tag == "barrel_match" else 0.3), 0, 0.03), col, e, bev=0.002)
        box(p + tag + "_fsight", (0.012, 0.004, 0.008), (0.045 + L - 0.008, 0, 0.057), ("red", RED) if tag == "barrel_match" else col, e, bev=0.001)
        cyl(p + tag + "_bore", 0.0048, 0.002, (0.045 + L + 0.0002, 0, 0.042), ("bronze", BRONZE) if tag == "barrel_match" else ("dark", DARK), e, bev=0)
    for tag, x0 in (("comp", 0.145), ("comp_m", 0.17)):
        c = empty(p + tag, root)
        cyl(p + tag + "_body", 0.011, 0.03, (x0 + 0.015, 0, 0.042), ("blued", BLUED), c, segs=8, bev=0.002)
        for i in range(3):
            box(p + tag + "_port%d" % i, (0.004, 0.008, 0.004), (x0 + 0.007 + i * 0.008, 0, 0.0525), ("dark", DARK), c, bev=0)
    # Wooden grip.
    grip = empty(p + "gripframe", root, (-0.028, 0, 0.012))
    grip.rotation_euler = (0, math.radians(22), 0)
    box(p + "grip", (0.038, 0.034, 0.085), (0, 0, -0.04), ("wood", WOOD), grip, bev=0.006)
    box(p + "gripcap", (0.034, 0.03, 0.006), (0, 0, -0.084), ("blued", BLUED), grip, bev=0.002)
    # Speed loader: lies on the bench beside the gun, loaded.
    ld = empty(p + "loader", root)
    cyl(p + "sl_body", 0.02, 0.014, (0.02, -0.075, -0.03), ("poly", POLY), ld, axis="Z", segs=32, bev=0.002)
    cyl(p + "sl_knob", 0.008, 0.012, (0.02, -0.075, -0.018), ("poly", POLY), ld, axis="Z", segs=16)
    for i in range(6):
        a = 2 * math.pi * i / 6
        cyl(p + "sl_rnd%d" % i, 0.0046, 0.03, (0.02 + math.cos(a) * 0.0105, -0.075 + math.sin(a) * 0.0105, -0.045), ("brass", BRASS), ld, axis="Z", segs=12)
    # Torch: a barrel clamp under the barrel.
    t = empty(p + "torch", root)
    box(p + "torch_mount", (0.022, 0.024, 0.014), (0.1, 0, 0.024), ("poly", POLY), t, bev=0.002)
    cyl(p + "torch_body", 0.0125, 0.05, (0.104, 0, 0.006), ("poly", POLY), t)
    cyl(p + "torch_head", 0.015, 0.014, (0.134, 0, 0.006), ("poly", POLY), t)
    cyl(p + "torch_lens", 0.0125, 0.002, (0.1415, 0, 0.006), ("lens", LENS), t, bev=0)


def build():
    C.reset()
    roots = []
    specs = [
        # n, L, sh, w, gh, slide, frame, grip panel, extras
        (0, 0.19, 0.03, 0.026, 0.085, ("blued", BLUED), ("poly", POLY), ("poly", POLY), {}),
        (1, 0.16, 0.028, 0.025, 0.07, ("blued", BLUED), ("tan", TAN), ("tan", TAN), {}),
        (2, 0.215, 0.032, 0.03, 0.09, ("bright", BRIGHT), ("steel", STEEL), ("wood", WOOD), {"hammer": True, "rail": False, "angle": 12.0}),
        (4, 0.225, 0.029, 0.026, 0.085, ("blued", BLUED), ("od", OD), ("od", OD),
         {"cuts": True, "front_sight": ("red", RED), "rear_adj": True}),
        (5, 0.17, 0.03, 0.027, 0.08, ("blued", BLUED), ("poly", POLY), ("poly", POLY),
         {"mag_long": 0.045, "front_sight": ("green", GREEN)}),
    ]
    for n, L, sh, w, gh, sc, fc, gc, kw in specs:
        r = empty("pistol_%d" % n)
        semi(n, r, L, sh, w, gh, sc, fc, gc, **kw)
        roots.append(r)
    r = empty("pistol_3")
    revolver(3, r)
    roots.append(r)
    # Space them out so the .blend is readable; the game re-centres each one.
    for r in roots:
        n = int(r.name.split("_")[1])
        r.location = (0, n * 0.4, 0)
    C.export_glb("assets/models/guns/pistols.glb")


if __name__ == "__main__":
    build()
