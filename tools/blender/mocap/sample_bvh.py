"""Samples every frame of a BVH into world-space bone matrices (Blender Z up,
metres) for cycle.py. Usage: python sample_bvh.py <take.bvh> <out.npz>"""
import bpy, sys, numpy as np
src, out = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_anim.bvh(filepath=src, global_scale=0.01, rotate_mode='QUATERNION', update_scene_fps=True, update_scene_duration=True)
arm=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
sc=bpy.context.scene
names=[b.name for b in arm.data.bones]
rest=np.array([np.array(arm.matrix_world@b.matrix_local) for b in arm.data.bones])
F=[]
for f in range(sc.frame_start, sc.frame_end+1):
    sc.frame_set(f)
    F.append([np.array(arm.matrix_world@arm.pose.bones[n].matrix) for n in names])
np.savez(out, names=np.array(names), rest=rest, frames=np.array(F), fps=sc.render.fps)
print("saved", len(F))
