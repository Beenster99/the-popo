"""Phase 0.3: building kit pieces, each with a pre-fractured twin.

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
    "wall": (c.material("kit_wall", (0.78, 0.72, 0.62)), c.material("kit_wall_inner", (0.62, 0.38, 0.3))),
    "slab": (c.material("kit_slab", (0.62, 0.62, 0.64)), c.material("kit_slab_inner", (0.45, 0.45, 0.47))),
    "column": (c.material("kit_column", (0.55, 0.55, 0.6)), c.material("kit_column_inner", (0.42, 0.42, 0.45))),
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
    outer, inner = MAT[kind]
    base = Vector((offset_x, 0, 0))  # spread pieces out in the file; Godot re-centres
    # Intact piece: union of its boxes in one mesh.
    bm = bmesh.new()
    for size, centre in boxes:
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        for v in tmp.verts:
            v.co = Vector((v.co.x * size[0] + centre[0], v.co.y * size[1] + centre[1], v.co.z * size[2] + centre[2]))
        me = bpy.data.meshes.new("tmp")
        tmp.to_mesh(me)
        tmp.free()
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    exported.append(link_bm(pname, bm, [outer, inner], base))
    k = 0
    for size, centre in boxes:
        n = max(2, int(cells_per_box * (size[0] * size[2] if kind != "slab" else size[0] * size[1]) / (16.0 if kind == "slab" else 12.0 if kind == "wall" else 1.2)))
        if kind == "column":
            n = cells_per_box
        for cell in cell_meshes(size, centre, n):
            centroid = sum((v.co for v in cell.verts), Vector()) / len(cell.verts)
            for v in cell.verts:
                v.co -= centroid
            exported.append(link_bm("%s__c%03d" % (pname, k), cell, [outer, inner], base + centroid))
            k += 1
    print(pname, "chunks:", k)
    offset_x += 6.0

c.export_glb("assets/models/kit/kit_fractured.glb")
