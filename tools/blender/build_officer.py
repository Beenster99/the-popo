"""Phase 0.6: export the officer from the animation demo, with every clip, for
Godot. Output: assets/models/characters/officer.glb

- The body is the demo's rigid parts on bones (tools/blender/officer/officer.py).
- Clips: the five demo moves (clips.py) plus the extra movement-course clips
  (extra_clips.py). Mocap clips exported from beenster's PC use the same rig
  and conventions, so they drop in beside these.
- Every clip is baked to plain FK keys (IK and constraints evaluated, then
  removed), because Godot does not run Blender constraints.
- Root motion: for moves that travel (roll, mantle, climb, slide) the hips'
  horizontal travel is moved onto the 'root' bone, so Godot can extract it
  as root motion. Loops stay in place.
- Outline shells and toon node materials are dropped: Godot draws its own
  cel shading and outlines.
"""
import os, sys, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "officer"))
import bpy
from mathutils import Matrix, Vector, Quaternion
import common
import officer as O
import clips as K
import extra_clips as X

ROOT_MOTION = {"roll", "mantle", "climb", "slide"}
LOOPS = {"run", "idle", "walk", "crouch_idle", "crouch_walk", "prone_idle", "crawl", "fall",
         "cover_idle", "aim_hold", "ready_hold"}

O.reset()
rig = O.build_officer()
O.ground_tiles(size=4)
base_objects = set(bpy.data.objects)
A_ = None

clip_fns = {name: cfg["fn"] for name, cfg in K.CLIPS.items()}
clip_fns.update(X.EXTRA)

# Bones that matter in the game (deform chain). IK targets and poles are
# controls; they are evaluated into the deform bones by the bake and dropped.
DEFORM = [b.name for b in rig.data.bones if not any(k in b.name for k in ("_ik.", "_pole."))]
ORDER = []
def _walk(b):
    ORDER.append(b.name)
    for c in b.children:
        if c.name in DEFORM:
            _walk(c)
_walk(rig.data.bones["root"])


def reset_pose():
    for pb in rig.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)


def key_default_ik(f=1):
    for s in "LR":
        for limb, v in (("leg", 1.0), ("arm", 0.0)):
            pb = rig.pose.bones[("shin." if limb == "leg" else "forearm.") + s]
            pb.constraints["IK"].influence = v
            pb.constraints["IK"].keyframe_insert("influence", frame=f)
            hb = rig.pose.bones[("foot." if limb == "leg" else "hand.") + s]
            hb.constraints["IKrot"].influence = v
            hb.constraints["IKrot"].keyframe_insert("influence", frame=f)


# 1. Key every clip, then sample the evaluated armature-space pose per frame.
samples = {}
for name, fn in clip_fns.items():
    rig.animation_data_create()
    rig.animation_data.action = bpy.data.actions.new(name + "_src")
    reset_pose()
    key_default_ik()
    A = O.Animator(rig)
    f0, f1 = fn(rig, A)
    O.set_interp(rig) if name not in ("run",) else None
    frames = []
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        frames.append({b: rig.pose.bones[b].matrix.copy() for b in DEFORM})
    samples[name] = frames
    # Remove props the clip added (walls, crates) but keep the officer.
    for o in list(bpy.data.objects):
        if o not in base_objects:
            bpy.data.objects.remove(o, do_unlink=True)
    print("sampled", name, len(frames), "frames")

# 2. Drop constraints and control bones' influence; build baked actions.
for pb in rig.pose.bones:
    for c in list(pb.constraints):
        pb.constraints.remove(c)
rig.animation_data.action = None
for a in list(bpy.data.actions):
    if a.name.endswith("_src"):
        bpy.data.actions.remove(a)

rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
parent = {b.name: (b.parent.name if b.parent else None) for b in rig.data.bones}

for name, frames in samples.items():
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data.action = act
    start_hips = frames[0]["hips"].to_translation()
    prevq = {}
    for i, M in enumerate(frames):
        M = dict(M)
        if name in ROOT_MOTION:
            h = M["hips"].to_translation()
            d = Vector((h.x - start_hips.x, h.y - start_hips.y, 0.0))
            M["root"] = Matrix.Translation(d)
        f = i + 1
        for b in ORDER:
            pb = rig.pose.bones[b]
            p = parent[b]
            if p is None:
                L = rest[b].inverted() @ M[b]
            else:
                L = (rest[p].inverted() @ rest[b]).inverted() @ M[p].inverted() @ M[b]
            loc, rot, _ = L.decompose()
            if b in prevq and prevq[b].dot(rot) < 0:
                rot.negate()
            prevq[b] = rot.copy()
            pb.location = loc
            pb.rotation_quaternion = rot
            pb.keyframe_insert("location", frame=f)
            pb.keyframe_insert("rotation_quaternion", frame=f)
    for fc in act.fcurves:
        for k in fc.keyframe_points:
            k.interpolation = "LINEAR"
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, act)
    track.mute = True
    rig.animation_data.action = None
    print("baked", name, "loop" if name in LOOPS else "", "root motion" if name in ROOT_MOTION else "")

# 3. Clean up for export: control bones out, outline shells and toon materials out.
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
for eb in list(rig.data.edit_bones):
    if eb.name not in DEFORM:
        rig.data.edit_bones.remove(eb)
bpy.ops.object.mode_set(mode="OBJECT")
for o in list(bpy.data.objects):
    if o.name.startswith(("ground", "Plane", "muzzle_flash")):
        bpy.data.objects.remove(o, do_unlink=True)
        continue
    if o.type != "MESH":
        continue
    for m in list(o.modifiers):
        if m.type == "SOLIDIFY":
            o.modifiers.remove(m)
    o.data.materials.pop(index=len(o.data.materials) - 1) if len(o.data.materials) > 1 and o.data.materials[-1].name.startswith("outline") else None
# Clips hide the gun in the viewport; hidden objects export with stale
# transforms, so show everything again (Godot decides when the gun shows).
for o in bpy.data.objects:
    o.hide_viewport = False
    o.hide_render = False
    o.hide_set(False)
bpy.context.view_layer.update()
# Replace each toon material with a plain one carrying its base colour.
for m in bpy.data.materials:
    if not m.use_nodes:
        continue
    ramp = next((n for n in m.node_tree.nodes if n.type == "VALTORGB"), None)
    if ramp is None:
        continue
    col = ramp.color_ramp.elements[1].color[:]
    m.node_tree.nodes.clear()
    out = m.node_tree.nodes.new("ShaderNodeOutputMaterial")
    bsdf = m.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = col
    m.node_tree.links.new(bsdf.outputs[0], out.inputs[0])

path = os.path.join(common.REPO, "assets/models/characters/officer.glb")
os.makedirs(os.path.dirname(path), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=path, export_format="GLB", export_yup=True, export_apply=True,
    export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
    export_frame_range=False, export_anim_single_armature=True,
)
print("exported", path)
