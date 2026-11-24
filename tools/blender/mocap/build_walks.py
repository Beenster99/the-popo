"""Walk clips for the officer from the 100STYLE dataset (Ian Mason, CC BY 4.0,
https://ianxmason.github.io/100style/): real XSens motion capture.

  walk        Neutral_FW  relaxed walk, gun holstered
  walk_ready  Swat_FW     tactical walk: knees soft, weight low, the upper
                          body is the game's own low-ready / aim layer
  walk_back   Swat_BW     backing off, the same tactical stance
  walk_left / walk_right  Swat_SW sidestep (right is the left one mirrored)

v0.12.0, beenster: the run is "a bit knees out". The video-capture run from
officer_mocap.glb is copied in as "run" (it replaces that one in the game)
with each thigh turned about its hip-to-ankle line until the knee points
along the leg's swing instead of out to the side; the foot keeps its world
angle and the ankle does not move, so stride and timing stay the same.
(100STYLE's runs were tried first: clean knees, but they are slow jogs,
1.7 m/s against the game's 3-5 m/s, so the legs would have spun.)

Each take is sampled (sample_bvh.py), the cleanest gait cycle is cut out and
straightened into an in-place loop (cycle.py), then retargeted onto the
officer by world-space rotation deltas: every officer bone turns the way its
mocap bone turns from rest, after the two rest poses (T-pose vs arms down)
are lined up bone by bone. The hips keep their bob and sway, scaled to the
officer's legs, and the whole clip is set down so the lowest foot touches
the floor. Output: assets/models/characters/mocap/officer_walks.glb, same
rig as officer_mocap.glb so it merges the same way (OfficerClips).

Usage: python build_walks.py <dir with the sampled .npz takes>
"""
import os, sys, math, json
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
from mathutils import Matrix, Vector, Quaternion
import cycle

REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SRC_GLB = os.path.join(REPO, "assets/models/characters/mocap/officer_mocap.glb")
OUT = os.path.join(REPO, "assets/models/characters/mocap/officer_walks.glb")
TAKES = sys.argv[-1]
FPS_IN, FPS_OUT = 60, 30

CLIPS = [  # name, take, direction of travel, mirror, cycle length range (s)
    ("walk", "Neutral_FW", "forward", False, (0.8, 1.6)),
    ("walk_ready", "Swat_FW", "forward", False, (0.8, 1.6)),
    ("walk_back", "Swat_BW", "back", False, (0.8, 1.6)),
    ("walk_left", "Swat_SW", "left", False, (0.8, 1.6)),
    ("walk_right", "Swat_SW", "left", True, (0.8, 1.6)),
]
MAP = {
    "hips": "Hips", "spine": "Chest2", "chest": "Chest4", "neck": "Neck", "head": "Head",
    "upper_arm.L": "LeftShoulder", "forearm.L": "LeftElbow", "hand.L": "LeftWrist",
    "upper_arm.R": "RightShoulder", "forearm.R": "RightElbow", "hand.R": "RightWrist",
    "thigh.L": "LeftHip", "shin.L": "LeftKnee", "foot.L": "LeftAnkle",
    "thigh.R": "RightHip", "shin.R": "RightKnee", "foot.R": "RightAnkle",
}
ORDER = ["hips", "spine", "chest", "neck", "head", "upper_arm.L", "forearm.L", "hand.L",
         "upper_arm.R", "forearm.R", "hand.R", "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R"]


def mat3(a):
    return Matrix([list(r) for r in a[:3, :3]])


def mirror_take(S, names):
    """Mirrors a straightened take left to right (x -> -x), swapping sides."""
    M = np.diag([-1.0, 1, 1, 1])
    out = np.empty_like(S)
    swap = {}
    for i, n in enumerate(names):
        o = n.replace("Left", "#").replace("Right", "Left").replace("#", "Right")
        swap[i] = names.index(o)
    for i in range(len(names)):
        # Reflect the transform; a reflected rotation is fixed by flipping the
        # bone's own x axis (the bone axis y and its roll z stay right-handed).
        m = M @ S[:, swap[i]] @ M
        out[:, i] = m
    return out


def loop_cycle(S, a, b):
    """Frames a..b as a loop: the seam between b and a is spread evenly over
    the cycle (rotations per bone in world space, and the hips' position)."""
    n = b - a
    C = S[a:b + 1].copy()
    for bi in range(C.shape[1]):
        qa = mat3(C[0, bi]).to_quaternion()
        qb = mat3(C[n, bi]).to_quaternion()
        res = qa @ qb.inverted()
        for t in range(n + 1):
            s = t / n
            q = Quaternion().slerp(res, s) @ mat3(C[t, bi]).to_quaternion()
            C[t, bi, :3, :3] = np.array(q.to_matrix())
        dp = C[0, bi, :3, 3] - C[n, bi, :3, 3]
        for t in range(n + 1):
            C[t, bi, :3, 3] += dp * (t / n)
    return C


def resample(C, fps_in, fps_out):
    n = C.shape[0] - 1
    length = n / fps_in
    m = max(2, round(length * fps_out))
    out = np.empty((m + 1,) + C.shape[1:])
    for k in range(m + 1):
        f = k / m * n
        i = min(int(f), n - 1)
        u = f - i
        for bi in range(C.shape[1]):
            qa = mat3(C[i, bi]).to_quaternion()
            qb = mat3(C[i + 1, bi]).to_quaternion()
            if qa.dot(qb) < 0:
                qb.negate()
            out[k, bi] = np.eye(4)
            out[k, bi, :3, :3] = np.array(qa.slerp(qb, u).to_matrix())
            out[k, bi, :3, 3] = C[i, bi, :3, 3] * (1 - u) + C[i + 1, bi, :3, 3] * u
    return out, length


def min_arc(a, b):
    return Vector(a).normalized().rotation_difference(Vector(b).normalized())


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC_GLB)
rig = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
IMPORT_FPS = bpy.context.scene.render.fps   # the importer keys at this rate
for t in list(rig.animation_data.nla_tracks) if rig.animation_data else []:
    rig.animation_data.nla_tracks.remove(t)
run_src = bpy.data.actions.get("run")
run_src.name = "run_src"
run_src.use_fake_user = True
for a in list(bpy.data.actions):
    if a is not run_src:
        bpy.data.actions.remove(a)
if rig.animation_data is None:
    rig.animation_data_create()
for pb in rig.pose.bones:
    pb.rotation_mode = "QUATERNION"
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.scene.render.fps = FPS_OUT

T_rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
parent = {b.name: (b.parent.name if b.parent else None) for b in rig.data.bones}
report = {}

for clip, take, want, mirror, (min_s, max_s) in CLIPS:
    d = np.load(os.path.join(TAKES, take + ".npz"))
    names = list(d["names"])
    S, best = cycle.pick_cycle(d, FPS_IN, want, min_s, max_s)
    cost, c0, c1, speed, turn, seam = best
    if mirror:
        S = mirror_take(S, names)
    C = loop_cycle(S, c0, c1)
    C, length = resample(C, FPS_IN, FPS_OUT)
    src_rest = d["rest"]
    if mirror:
        src_rest = mirror_take(src_rest[None], names)[0]
    ix = names.index
    # Rest alignment per bone (source rest direction -> officer rest direction).
    corr = {}
    for tb, sb in MAP.items():
        sdir = src_rest[ix(sb)][:3, 1]
        tdir = T_rest[tb].to_3x3().col[1]
        corr[tb] = min_arc(sdir, tdir)
    # Leg length ratio: hips joint to ankle.
    s_leg = np.linalg.norm(src_rest[ix("LeftHip")][:3, 3] - src_rest[ix("LeftAnkle")][:3, 3])
    t_leg = (T_rest["thigh.L"].translation - T_rest["foot.L"].translation).length
    k = t_leg / s_leg
    frames = []
    for f in range(C.shape[0]):
        W = {}
        for tb, sb in MAP.items():
            Sw = mat3(C[f, ix(sb)]).to_quaternion()
            Sr = mat3(src_rest[ix(sb)]).to_quaternion()
            Tr = T_rest[tb].to_quaternion()
            W[tb] = Sw @ Sr.inverted() @ corr[tb].inverted() @ Tr
        hp = Vector(C[f, ix("Hips"), :3, 3]) * k
        frames.append((W, hp))
    # Eyes front: the actors carry their heads pitched down a little, which
    # reads as staring at the floor on the officer. Take each of neck and
    # head's average turn from the rest pose off (half on the neck, all on
    # the head, measured against the chest) and keep the bob around it.
    for b, part in (("neck", 0.5), ("head", 1.0)):
        acc = Vector((0.0, 0.0, 0.0, 0.0))
        ref = None
        for W, hp in frames:
            rel = (W["chest"] @ T_rest["chest"].to_quaternion().inverted()).inverted() @ W[b] @ T_rest[b].to_quaternion().inverted()
            if ref is None:
                ref = rel
            if rel.dot(ref) < 0:
                rel.negate()
            acc += Vector(rel)
        mean = Quaternion(acc.normalized())
        fix = Quaternion().slerp(mean, part).inverted()
        for W, hp in frames:
            cw = W["chest"] @ T_rest["chest"].to_quaternion().inverted()
            W[b] = cw @ fix @ cw.inverted() @ W[b]
    # Hips height: put the lowest ankle of the cycle where the rest ankle is.
    # Forward kinematics of the legs for that check.
    def ankle_z(W, hp, side):
        hip_off = T_rest["thigh." + side].translation - T_rest["hips"].translation
        hips_q = W["hips"] @ T_rest["hips"].to_quaternion().inverted()
        p = hp + hips_q @ hip_off
        thigh = (T_rest["shin." + side].translation - T_rest["thigh." + side].translation)
        q = W["thigh." + side] @ T_rest["thigh." + side].to_quaternion().inverted()
        p = p + q @ thigh
        shin = (T_rest["foot." + side].translation - T_rest["shin." + side].translation)
        q = W["shin." + side] @ T_rest["shin." + side].to_quaternion().inverted()
        return (p + q @ shin).z
    low = min(min(ankle_z(W, Vector((0, 0, hp.z)), s) for s in "LR") for W, hp in frames)
    lift = T_rest["foot.L"].translation.z - low
    act = bpy.data.actions.new(clip)
    act.use_fake_user = True
    rig.animation_data.action = act
    prevq = {}
    for i, (W, hp) in enumerate(frames):
        for b in ORDER:
            pb = rig.pose.bones[b]
            p = parent[b]
            Rb = T_rest[b].to_quaternion()
            if b == "hips":
                Wp = Quaternion()   # root stays at rest
                Rp = T_rest[p].to_quaternion()
            else:
                Wp = W[p]
                Rp = T_rest[p].to_quaternion()
            L = Rb.inverted() @ Rp @ Wp.inverted() @ W[b]
            if b in prevq and prevq[b].dot(L) < 0:
                L.negate()
            prevq[b] = L.copy()
            pb.rotation_quaternion = L
            pb.keyframe_insert("rotation_quaternion", frame=i)
            if b == "hips":
                want_head = Vector((hp.x, hp.y, hp.z + lift))
                pb.location = Rb.inverted() @ (want_head - T_rest["hips"].translation)
                pb.keyframe_insert("location", frame=i)
    rig.animation_data.action = None
    track = rig.animation_data.nla_tracks.new()
    track.name = clip
    track.strips.new(clip, 0, act)
    track.mute = True
    report[clip] = {"take": take, "frames": [int(c0), int(c1)], "length_s": round(float(length), 3),
                    "speed_mps": round(float(speed * k), 3), "turn_rad_s": round(float(turn), 3), "mirror": mirror}
    print("baked", clip, report[clip])


KNEE_OUT_MAX = 0.01   # m: how far a knee may sit outside its hip-ankle line


def fix_run_knees(src, fps_in):
    """The run with its knees brought in (see the top of the file)."""
    vl = bpy.context.view_layer
    rig.animation_data.action = src
    f0, f1 = src.frame_range
    length = (f1 - f0) / fps_in
    n = round(length * FPS_OUT)
    keyed = {fc.data_path.split('"')[1] for fc in src.fcurves if fc.data_path.startswith("pose.bones")} \
        if hasattr(src, "fcurves") else {pb.name for pb in rig.pose.bones}
    frames = []
    worst = [0.0, 0.0]
    for k in range(n + 1):
        sf = f0 + k / FPS_OUT * fps_in
        bpy.context.scene.frame_set(int(sf), subframe=sf - int(sf))
        frames.append({pb.name: (pb.matrix_basis.copy(), pb.location.copy()) for pb in rig.pose.bones})
    act = bpy.data.actions.new("run")
    act.use_fake_user = True
    rig.animation_data.action = act
    prevq = {}
    for k, pose in enumerate(frames):
        for name, (mb, _) in pose.items():
            rig.pose.bones[name].matrix_basis = mb
        vl.update()
        P = rig.pose.bones
        lat = (P["thigh.L"].head - P["thigh.R"].head).normalized()
        for side, sgn in (("L", 1.0), ("R", -1.0)):
            th, sh, ft = P["thigh." + side], P["shin." + side], P["foot." + side]
            hip, knee, ank = th.head.copy(), sh.head.copy(), ft.head.copy()
            foot_rot = ft.matrix.to_3x3().copy()
            axis = (ank - hip).normalized()
            o = (knee - hip) - axis * (knee - hip).dot(axis)
            u = (lat * sgn - axis * (lat * sgn).dot(axis)).normalized()   # outward
            v = axis.cross(u)
            a, b = o.dot(u), o.dot(v)
            worst[0] = max(worst[0], a)
            if a <= KNEE_OUT_MAX:
                continue
            r = math.hypot(a, b)
            a2 = KNEE_OUT_MAX
            b2 = math.copysign(math.sqrt(max(r * r - a2 * a2, 0.0)), b if abs(b) > 1e-4 else 1.0)
            ang = math.atan2(b2, a2) - math.atan2(b, a)
            R = Matrix.Translation(hip) @ Matrix.Rotation(ang, 4, axis) @ Matrix.Translation(-hip)
            th.matrix = R @ th.matrix
            vl.update()
            m = foot_rot.to_4x4()
            m.translation = ft.head
            ft.matrix = m
            vl.update()
            knee2 = sh.head
            o2 = (knee2 - hip) - axis * (knee2 - hip).dot(axis)
            worst[1] = max(worst[1], o2.dot(u))
        for name in keyed:
            pb = rig.pose.bones[name]
            q = pb.matrix_basis.to_quaternion()
            if name in prevq and prevq[name].dot(q) < 0:
                q.negate()
            prevq[name] = q.copy()
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=k)
            pb.location = pb.matrix_basis.translation
            pb.keyframe_insert("location", frame=k)
    rig.animation_data.action = None
    track = rig.animation_data.nla_tracks.new()
    track.name = "run"
    track.strips.new("run", 0, act)
    track.mute = True
    print("run knees: worst outward %.1f cm before, %.1f cm after" % (worst[0] * 100, worst[1] * 100))
    return {"take": "officer_mocap.glb run, knees brought in", "length_s": round(length, 3),
            "knee_out_cm_before": round(worst[0] * 100, 1), "knee_out_cm_after": round(worst[1] * 100, 1)}


for pb in rig.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
report["run"] = fix_run_knees(run_src, IMPORT_FPS)
for pb in rig.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
bpy.ops.export_scene.gltf(
    filepath=OUT, export_format="GLB", export_yup=True, export_apply=True,
    export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
    export_frame_range=False, export_anim_single_armature=True,
)
with open(os.path.join(HERE, "walks.json"), "w") as fp:
    json.dump(report, fp, indent=1)
print("exported", OUT)
