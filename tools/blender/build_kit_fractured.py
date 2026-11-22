"""Building kit pieces, each with a pre-fractured twin (Phase 0.3, grown to
the Wave 1 kit of about 30 pieces in Phase 1.1; grid in docs/wave1/grid.md).

Every piece is built from convex boxes. Each box is split into Voronoi cells
by cutting a copy of it with the bisector plane between its seed and every
other seed, which leaves convex cells (good for Jolt convex hulls). The cut
faces get an "inner" material so broken edges show raw concrete or brick.

Output: assets/models/kit/kit_fractured.glb with, per piece:
    <piece>            the intact mesh, origin at the piece centre
    <piece>__c<NNN>    each chunk, origin at its own centroid
Godot reads chunk positions from the glb, so the layout here is the truth.
Blender is Z up; the exporter converts to Godot's Y up.
"""
import os, sys, random
sys.path.insert(0, os.path.dirname(__file__))
import bpy, bmesh
from mathutils import Vector
import common as c

c.reset()
random.seed(1983)

MAT = {
    # Linear colour values (Blender), so they look darker here than on screen.
    "wall": (c.material("kit_wall", (0.42, 0.13, 0.08)), c.material("kit_wall_inner", (0.5, 0.42, 0.34))),
    "slab": (c.material("kit_slab", (0.33, 0.33, 0.35)), c.material("kit_slab_inner", (0.22, 0.22, 0.23))),
    "column": (c.material("kit_column", (0.3, 0.3, 0.34)), c.material("kit_column_inner", (0.2, 0.2, 0.22))),
    # Wave 1 kit materials. Godot recolours walls per building, keyed on the
    # material name, so the shapes stay shared.
    "plaster": (c.material("kit_plaster", (0.62, 0.58, 0.5)), c.material("kit_plaster_inner", (0.45, 0.42, 0.38))),
    "roof": (c.material("kit_roof", (0.12, 0.12, 0.13)), c.material("kit_roof_inner", (0.22, 0.22, 0.23))),
    "pave": (c.material("kit_pave", (0.42, 0.41, 0.38)), c.material("kit_pave_inner", (0.3, 0.29, 0.27))),
    "road": (c.material("kit_road", (0.06, 0.065, 0.07)), c.material("kit_road_inner", (0.14, 0.14, 0.14))),
    "paint": (c.material("kit_paint", (0.82, 0.8, 0.7)), c.material("kit_paint_inner", (0.14, 0.14, 0.14))),
    "metal": (c.material("kit_metal", (0.05, 0.06, 0.07)), c.material("kit_metal_inner", (0.3, 0.3, 0.32))),
    "glass": (c.material("kit_glass", (0.45, 0.65, 0.75)), c.material("kit_glass_inner", (0.6, 0.8, 0.85))),
    "wood": (c.material("kit_wood", (0.25, 0.12, 0.05)), c.material("kit_wood_inner", (0.45, 0.3, 0.16))),
    "brick": (c.material("kit_brick", (0.3, 0.1, 0.06)), c.material("kit_brick_inner", (0.5, 0.42, 0.34))),
}

# Piece definitions: list of convex boxes (size, centre) in piece space, metres.
# Blender axes: X along the wall, Y thickness, Z up.
PIECES = {
    "wall": ("wall", [((4.0, 0.25, 3.0), (0, 0, 1.5))], 18),
    "wall_window": ("wall", [
        ((1.2, 0.25, 3.0), (-1.4, 0, 1.5)),
        ((1.2, 0.25, 3.0), (1.4, 0, 1.5)),
        ((1.6, 0.25, 0.9), (0, 0, 0.45)),
        ((1.6, 0.25, 0.7), (0, 0, 2.65)),
    ], 6),
    "wall_door": ("wall", [
        ((1.3, 0.25, 3.0), (-1.35, 0, 1.5)),
        ((1.3, 0.25, 3.0), (1.35, 0, 1.5)),
        ((1.4, 0.25, 0.6), (0, 0, 2.7)),
    ], 6),
    "slab": ("slab", [((4.0, 4.0, 0.25), (0, 0, -0.125))], 16),
    "column": ("column", [((0.4, 0.4, 3.0), (0, 0, 1.5))], 5),
}
# Wave 1 pieces, added after the Wave 0 ones so those keep their fractures.
# A box may name its own material kind as a third item.
_STEP_RISE, _STEP_RUN, _STEPS = 3.25 / 17, 0.22, 17
PIECES.update({
    # Exterior walls (4 m and 2 m modules).
    "wall_half": ("wall", [((2.0, 0.25, 3.0), (0, 0, 1.5))], 18),
    "wall_half_window": ("wall", [
        ((0.5, 0.25, 3.0), (-0.75, 0, 1.5)),
        ((0.5, 0.25, 3.0), (0.75, 0, 1.5)),
        ((1.0, 0.25, 0.9), (0, 0, 0.45)),
        ((1.0, 0.25, 0.7), (0, 0, 2.65)),
    ], 6),
    "wall_shopfront": ("wall", [
        ((0.4, 0.25, 3.0), (-1.8, 0, 1.5)),
        ((0.4, 0.25, 3.0), (1.8, 0, 1.5)),
        ((3.2, 0.25, 0.5), (0, 0, 0.25)),
        ((3.2, 0.25, 0.7), (0, 0, 2.65)),
    ], 6),
    "wall_shopdoor": ("wall", [
        ((0.4, 0.25, 3.0), (-1.8, 0, 1.5)),
        ((1.4, 0.25, 0.6), (-0.9, 0, 2.7)),
        ((0.3, 0.25, 3.0), (-0.05, 0, 1.5)),
        ((1.5, 0.25, 0.5), (0.85, 0, 0.25)),
        ((1.5, 0.25, 0.7), (0.85, 0, 2.65)),
        ((0.4, 0.25, 3.0), (1.8, 0, 1.5)),
    ], 6),
    "wall_garage": ("wall", [
        ((0.4, 0.25, 3.0), (-1.8, 0, 1.5)),
        ((0.4, 0.25, 3.0), (1.8, 0, 1.5)),
        ((3.2, 0.25, 0.4), (0, 0, 2.8)),
    ], 6),
    "parapet": ("wall", [((4.0, 0.25, 1.0), (0, 0, 0.5))], 18),
    "parapet_half": ("wall", [((2.0, 0.25, 1.0), (0, 0, 0.5))], 18),
    # Interior partitions: thinner, plaster.
    "int_wall": ("plaster", [((4.0, 0.12, 3.0), (0, 0, 1.5))], 14),
    "int_wall_door": ("plaster", [
        ((1.5, 0.12, 3.0), (-1.25, 0, 1.5)),
        ((1.5, 0.12, 3.0), (1.25, 0, 1.5)),
        ((1.0, 0.12, 0.8), (0, 0, 2.6)),
    ], 6),
    "int_wall_half": ("plaster", [((2.0, 0.12, 3.0), (0, 0, 1.5))], 14),
    # Floors, stairwell and stairs (17 steps of 0.19 m climb one storey).
    "slab_half": ("slab", [((4.0, 2.0, 0.25), (0, 0, -0.125))], 16),
    "slab_stairwell": ("slab", [
        ((2.7, 4.0, 0.25), (0.65, 0, -0.125)),
        ((1.3, 0.25, 0.25), (-1.35, 1.875, -0.125)),
    ], 16),
    "stairs": ("slab", [((1.2, _STEP_RUN, _STEP_RISE * (i + 1)), (0, -1.875 + _STEP_RUN * (i + 0.5), _STEP_RISE * (i + 1) / 2))
                        for i in range(_STEPS)], 1),
    "roof": ("roof", [((4.0, 4.0, 0.25), (0, 0, -0.125))], 16),
    "roof_half": ("roof", [((4.0, 2.0, 0.25), (0, 0, -0.125))], 16),
    "column_thin": ("column", [((0.25, 0.25, 3.0), (0, 0, 1.5))], 4),
    # Glass and doors that sit in the wall openings.
    "glass_window": ("glass", [((1.6, 0.03, 1.4), (0, 0, 1.6))], 8),
    "glass_half_window": ("glass", [((1.0, 0.03, 1.4), (0, 0, 1.6))], 6),
    "glass_shopfront": ("glass", [((3.2, 0.03, 1.8), (0, 0, 1.4))], 14),
    "glass_shopdoor": ("glass", [((1.5, 0.03, 1.8), (0.85, 0, 1.4))], 8),
    "door_closed": ("wood", [((1.4, 0.06, 2.4), (0, 0, 1.2))], 4),
    "garage_door": ("metal", [((3.2, 0.06, 2.6), (0, 0, 1.3))], 8),
    # Street: pavement with a kerb, plain road, road with a centre dash, zebra crossing.
    "pavement": ("pave", [((4.0, 4.0, 0.15), (0, 0, 0.075))], 6),
    "road": ("road", [((4.0, 4.0, 0.05), (0, 0, -0.025))], 4),
    "road_line": ("road", [((4.0, 4.0, 0.05), (0, 0, -0.025)), ((2.0, 0.15, 0.01), (0, 0, 0.005), "paint")], 4),
    "road_crossing": ("road", [((4.0, 4.0, 0.05), (0, 0, -0.025))] +
                      [((0.5, 3.6, 0.01), (-1.5 + i * 1.0, 0, 0.005), "paint") for i in range(4)], 4),
    # Street furniture.
    "low_wall": ("brick", [((4.0, 0.3, 1.0), (0, 0, 0.5))], 8),
    "bollard": ("metal", [((0.2, 0.2, 0.9), (0, 0, 0.45))], 2),
    "lamp_post": ("metal", [((0.15, 0.15, 4.5), (0, 0, 2.25)), ((0.9, 0.3, 0.12), (0.35, 0, 4.5))], 3),
})
# Pieces whose boxes always split into exactly cells_per_box cells.
FIXED_CELLS = {"column", "column_thin", "stairs", "bollard", "lamp_post"}


def cell_meshes(size, centre, n_cells):
    """Return a list of bmesh cells for one convex box."""
    sx, sy, sz = size
    cx, cy, cz = centre
    seeds = [Vector((cx + random.uniform(-sx / 2, sx / 2) * 0.95,
                     cy + random.uniform(-sy / 2, sy / 2) * 0.95,
                     cz + random.uniform(-sz / 2, sz / 2) * 0.95)) for _ in range(n_cells)]
    cells = []
    for i, si in enumerate(seeds):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        for v in bm.verts:
            v.co = Vector((v.co.x * sx + cx, v.co.y * sy + cy, v.co.z * sz + cz))
        for f in bm.faces:
            f.material_index = 0
        for j, sj in enumerate(seeds):
            if i == j:
                continue
            n = (sj - si).normalized()
            mid = (si + sj) / 2
            res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                                         plane_co=mid, plane_no=n, clear_outer=True, dist=1e-5)
            cut_edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
            if cut_edges:
                new = bmesh.ops.holes_fill(bm, edges=cut_edges, sides=0)
                for f in new["faces"]:
                    f.material_index = 1
            if len(bm.verts) < 4:
                break
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-4)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        if len(bm.faces) >= 4:
            vol = bm.calc_volume()
            if vol > 1e-4:
                cells.append(bm)
                continue
        bm.free()
    return cells


def link_bm(name, bm, mats, location):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    ob.location = location
    bpy.context.scene.collection.objects.link(ob)
    return ob


exported = []
offset_x = 0.0
for pname, (kind, boxes, cells_per_box) in PIECES.items():
    boxes = [b if len(b) == 3 else (b[0], b[1], kind) for b in boxes]
    kinds = []
    for b in boxes:
        if b[2] not in kinds:
            kinds.append(b[2])
    mats = []
    for k_ in kinds:
        mats += list(MAT[k_])
    base = Vector((offset_x, 0, 0))  # spread pieces out in the file; Godot re-centres
    # Intact piece: union of its boxes in one mesh.
    bm = bmesh.new()
    for size, centre, bk in boxes:
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        for v in tmp.verts:
            v.co = Vector((v.co.x * size[0] + centre[0], v.co.y * size[1] + centre[1], v.co.z * size[2] + centre[2]))
        for f in tmp.faces:
            f.material_index = kinds.index(bk) * 2
        me = bpy.data.meshes.new("tmp")
        tmp.to_mesh(me)
        tmp.free()
        for k_ in kinds:
            me.materials.append(MAT[k_][0])
            me.materials.append(MAT[k_][1])
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    exported.append(link_bm(pname, bm, mats, base))
    k = 0
    for size, centre, bk in boxes:
        n = max(2, int(cells_per_box * (size[0] * size[2] if kind != "slab" else size[0] * size[1]) / (16.0 if kind == "slab" else 12.0 if kind == "wall" else 1.2)))
        if pname in FIXED_CELLS or kind not in ("wall", "slab", "column"):
            n = cells_per_box if pname in FIXED_CELLS else max(1, min(cells_per_box, n))
        for cell in cell_meshes(size, centre, n):
            off = kinds.index(bk) * 2
            for f in cell.faces:
                f.material_index += off
            centroid = sum((v.co for v in cell.verts), Vector()) / len(cell.verts)
            for v in cell.verts:
                v.co -= centroid
            exported.append(link_bm("%s__c%03d" % (pname, k), cell, mats, base + centroid))
            k += 1
    print(pname, "chunks:", k)
    offset_x += 6.0

c.export_glb("assets/models/kit/kit_fractured.glb")
