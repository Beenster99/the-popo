"""Shared helpers for the scripted Blender art pipeline.

Run any builder with Blender 4.2+:
    blender -b --factory-startup -P tools/blender/<builder>.py
or with the pip `bpy` module:
    python tools/blender/<builder>.py

Godot import hints used in object names (see Godot docs, "Node type
customization using name suffixes"):
    -col          mesh plus a trimesh static collider
    -colonly      collider only, no visible mesh (trimesh)
    -convcolonly  collider only, convex
"""
import os
import bpy
import bmesh

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, roughness=0.8):
    """Flat base-colour material. Godot replaces it with the cel shader by
    material name prefix, so we only need the colour here."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return m


def box(name, size, location=(0, 0, 0), mat=None, bevel=0.0):
    """Axis-aligned box with its origin at the given location (Blender Z up)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, affect="EDGES")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.location = location
    bpy.context.scene.collection.objects.link(ob)
    if mat:
        me.materials.append(mat)
    return ob


def export_glb(path, objects=None):
    path = os.path.join(REPO, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if objects is not None:
        bpy.ops.object.select_all(action="DESELECT")
        for o in objects:
            o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=objects is not None,
        export_apply=True,
        export_yup=True,
        export_animations=True,
    )
    print("exported", path)
