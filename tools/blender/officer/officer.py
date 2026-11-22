"""Build a stylised cel-shaded police officer, rig it, scene helpers."""
import bpy, bmesh, math
from mathutils import Vector, Matrix, Quaternion, Euler

D = bpy.data
C = bpy.context


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ---------------------------------------------------------------- materials
def toon_mat(name, color, shadow=0.45, outline=False):
    m = D.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    if outline:
        # inverted hull: black on back faces, transparent on front faces
        geo = nt.nodes.new('ShaderNodeNewGeometry')
        em = nt.nodes.new('ShaderNodeEmission')
        em.inputs[0].default_value = (0.02, 0.02, 0.03, 1)
        tr = nt.nodes.new('ShaderNodeBsdfTransparent')
        mix = nt.nodes.new('ShaderNodeMixShader')
        nt.links.new(geo.outputs['Backfacing'], mix.inputs[0])
        nt.links.new(em.outputs[0], mix.inputs[1])
        nt.links.new(tr.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs[0])
        m.use_backface_culling = True
        m.use_backface_culling_shadow = True
        m.shadow_method = 'NONE' if hasattr(m, 'shadow_method') else None
        return m
    dif = nt.nodes.new('ShaderNodeBsdfDiffuse')
    s2r = nt.nodes.new('ShaderNodeShaderToRGB')
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.interpolation = 'CONSTANT'
    e = ramp.color_ramp.elements
    c = Vector(color[:3])
    e[0].position = 0.0
    e[0].color = (*(c * shadow), 1)
    e[1].position = 0.18
    e[1].color = (*c, 1)
    hi = e.new(0.75)
    hi.color = (*[min(1, x * 1.18 + 0.04) for x in c], 1)
    em = nt.nodes.new('ShaderNodeEmission')
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], em.inputs[0])
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


MATS = {}


def mats():
    MATS['outline'] = toon_mat('outline', (0, 0, 0), outline=True)
    MATS['shirt'] = toon_mat('shirt', (0.42, 0.58, 0.82))
    MATS['vest'] = toon_mat('vest', (0.07, 0.08, 0.10), shadow=0.6)
    MATS['trousers'] = toon_mat('trousers', (0.07, 0.10, 0.22), shadow=0.55)
    MATS['boots'] = toon_mat('boots', (0.04, 0.04, 0.04), shadow=0.7)
    MATS['skin'] = toon_mat('skin', (0.93, 0.68, 0.52), shadow=0.62)
    MATS['cap'] = toon_mat('cap', (0.06, 0.08, 0.18), shadow=0.6)
    MATS['band'] = toon_mat('band', (0.95, 0.95, 0.95), shadow=0.7)
    MATS['metal'] = toon_mat('metal', (0.75, 0.75, 0.70), shadow=0.5)
    MATS['gun'] = toon_mat('gun', (0.12, 0.12, 0.13), shadow=0.6)
    MATS['eye'] = toon_mat('eye', (0.03, 0.03, 0.03), shadow=1)
    MATS['hivis'] = toon_mat('hivis', (0.85, 0.95, 0.15), shadow=0.6)
    MATS['ground'] = toon_mat('ground', (0.55, 0.56, 0.58), shadow=0.55)
    MATS['ground2'] = toon_mat('ground2', (0.47, 0.48, 0.50), shadow=0.55)
    MATS['concrete'] = toon_mat('concrete', (0.72, 0.68, 0.62), shadow=0.6)
    MATS['brick'] = toon_mat('brick', (0.62, 0.30, 0.22), shadow=0.6)
    MATS['cone'] = toon_mat('cone', (0.95, 0.40, 0.08), shadow=0.6)
    MATS['flash'] = toon_mat('flash', (1.0, 0.85, 0.3), shadow=1.0)


# ---------------------------------------------------------------- mesh parts
def finish(obj, mat, outline=0.012, smooth=True, subsurf=0):
    obj.data.materials.append(MATS[mat])
    obj.data.materials.append(MATS['outline'])
    if smooth:
        for p in obj.data.polygons:
            p.use_smooth = True
    if subsurf:
        m = obj.modifiers.new('sub', 'SUBSURF')
        m.levels = subsurf
        m.render_levels = subsurf
    if outline:
        s = obj.modifiers.new('outline', 'SOLIDIFY')
        s.thickness = outline
        s.offset = 1
        s.use_flip_normals = True
        s.material_offset = 1
        s.use_rim = False
    return obj


def ellipsoid(name, loc, scale, mat, rot=(0, 0, 0), outline=0.012, seg=20):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=1, location=loc, rotation=rot)
    o = C.active_object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, mat, outline)


def rbox(name, loc, size, mat, bevel=0.03, rot=(0, 0, 0), outline=0.012, subsurf=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = C.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        b = o.modifiers.new('bevel', 'BEVEL')
        b.width = bevel
        b.segments = 3
    finish(o, mat, outline, subsurf=subsurf)
    return o


def taper(name, p0, p1, r0, r1, mat, outline=0.012, squash=1.0, verts=16):
    """Tapered rounded limb from p0 to p1 (radii r0 at p0, r1 at p1)."""
    p0, p1 = Vector(p0), Vector(p1)
    L = (p1 - p0).length
    bm = bmesh.new()
    rings = 7
    for i in range(rings + 1):
        t = i / rings
        r = r0 + (r1 - r0) * t
        # round the ends
        z = t * L
        if i == 0:
            r *= 0.55
            z += r0 * 0.05
        elif i == rings:
            r *= 0.55
            z -= r1 * 0.05
        elif i == 1 or i == rings - 1:
            r *= 0.92
        for j in range(verts):
            a = 2 * math.pi * j / verts
            bm.verts.new((math.cos(a) * r, math.sin(a) * r * squash, z))
    bm.verts.ensure_lookup_table()
    for i in range(rings):
        for j in range(verts):
            a = i * verts + j
            b = i * verts + (j + 1) % verts
            bm.faces.new((bm.verts[a], bm.verts[b], bm.verts[b + verts], bm.verts[a + verts]))
    bm.faces.new([bm.verts[(j)] for j in reversed(range(verts))])
    bm.faces.new([bm.verts[rings * verts + j] for j in range(verts)])
    me = D.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = D.objects.new(name, me)
    C.collection.objects.link(o)
    d = (p1 - p0).normalized()
    q = Vector((0, 0, 1)).rotation_difference(d)
    o.matrix_world = Matrix.Translation(p0) @ q.to_matrix().to_4x4()
    finish(o, mat, outline, subsurf=1)
    return o


def cyl(name, loc, r, depth, mat, rot=(0, 0, 0), outline=0.01, verts=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = C.active_object
    o.name = name
    return finish(o, mat, outline, smooth=False)


# ---------------------------------------------------------------- rig
J = {  # joint positions (character faces -Y, left = +X)
    'root': (0, 0, 0),
    'hips': (0, 0, 0.98), 'spine': (0, 0.0, 1.12), 'chest': (0, 0.0, 1.30), 'neck': (0, 0.0, 1.53),
    'head': (0, -0.0, 1.62), 'head_end': (0, -0.0, 1.88),
}
for s, x in (('L', 1), ('R', -1)):
    J['shoulder.' + s] = (0.20 * x, 0.0, 1.47)
    J['elbow.' + s] = (0.24 * x, 0.02, 1.20)
    J['wrist.' + s] = (0.26 * x, 0.0, 0.95)
    J['hand_end.' + s] = (0.265 * x, 0.0, 0.86)
    J['hip.' + s] = (0.10 * x, 0.0, 0.93)
    J['knee.' + s] = (0.10 * x, -0.015, 0.52)
    J['ankle.' + s] = (0.10 * x, 0.02, 0.10)
    J['toe.' + s] = (0.10 * x, -0.15, 0.03)


def build_rig():
    arm = D.armatures.new('rig')
    rig = D.objects.new('rig', arm)
    C.collection.objects.link(rig)
    C.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.edit_bones

    def bone(name, h, t, parent=None, connect=False, roll=0):
        b = eb.new(name)
        b.head = Vector(J[h]) if isinstance(h, str) else Vector(h)
        b.tail = Vector(J[t]) if isinstance(t, str) else Vector(t)
        b.roll = roll
        if parent:
            b.parent = eb[parent]
            b.use_connect = connect
        return b

    bone('root', (0, 0, 0), (0, 0.4, 0))
    bone('hips', 'hips', 'spine', 'root')
    bone('spine', 'spine', 'chest', 'hips', True)
    bone('chest', 'chest', 'neck', 'spine', True)
    bone('neck', 'neck', 'head', 'chest', True)
    bone('head', 'head', 'head_end', 'neck', True)
    for s in 'LR':
        bone('upper_arm.' + s, 'shoulder.' + s, 'elbow.' + s, 'chest')
        bone('forearm.' + s, 'elbow.' + s, 'wrist.' + s, 'upper_arm.' + s, True)
        bone('hand.' + s, 'wrist.' + s, 'hand_end.' + s, 'forearm.' + s, True)
        bone('thigh.' + s, 'hip.' + s, 'knee.' + s, 'hips')
        bone('shin.' + s, 'knee.' + s, 'ankle.' + s, 'thigh.' + s, True)
        bone('foot.' + s, 'ankle.' + s, 'toe.' + s, 'shin.' + s, True)
        # IK controls
        a = Vector(J['ankle.' + s])
        bone('foot_ik.' + s, a, Vector(J['toe.' + s]), 'root')
        k = Vector(J['knee.' + s])
        bone('knee_pole.' + s, k + Vector((0, -0.7, 0)), k + Vector((0, -0.8, 0)), 'hips')
        w = Vector(J['wrist.' + s])
        bone('hand_ik.' + s, w, Vector(J['hand_end.' + s]), 'root')
        e = Vector(J['elbow.' + s])
        x = 1 if s == 'L' else -1
        bone('elbow_pole.' + s, e + Vector((0.35 * x, 0.6, -0.3)), e + Vector((0.35 * x, 0.7, -0.3)), 'chest')
    bpy.ops.object.mode_set(mode='POSE')
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    for s in 'LR':
        pb = rig.pose.bones['shin.' + s]
        ik = pb.constraints.new('IK')
        ik.name = 'IK'
        ik.target = rig
        ik.subtarget = 'foot_ik.' + s
        ik.pole_target = rig
        ik.pole_subtarget = 'knee_pole.' + s
        ik.chain_count = 2
        ik.pole_angle = math.radians(-90)
        cr = rig.pose.bones['foot.' + s].constraints.new('COPY_ROTATION')
        cr.name = 'IKrot'
        cr.target = rig
        cr.subtarget = 'foot_ik.' + s
        pb = rig.pose.bones['forearm.' + s]
        ik = pb.constraints.new('IK')
        ik.name = 'IK'
        ik.target = rig
        ik.subtarget = 'hand_ik.' + s
        ik.pole_target = rig
        ik.pole_subtarget = 'elbow_pole.' + s
        ik.chain_count = 2
        ik.pole_angle = math.radians(90)
        ik.influence = 0
        cr = rig.pose.bones['hand.' + s].constraints.new('COPY_ROTATION')
        cr.name = 'IKrot'
        cr.target = rig
        cr.subtarget = 'hand_ik.' + s
        cr.influence = 0
    bpy.ops.object.mode_set(mode='OBJECT')
    return rig


def attach(obj, rig, bone):
    """Rigid-parent obj to bone keeping its world transform."""
    mw = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = 'BONE'
    obj.parent_bone = bone
    C.view_layer.update()
    pb = rig.pose.bones[bone]
    bone_mw = rig.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.bone.length, 0))
    obj.matrix_parent_inverse = bone_mw.inverted()
    obj.matrix_world = mw


def build_body(rig):
    P = lambda k: Vector(J[k])
    parts = []

    def add(o, b):
        attach(o, rig, b)
        parts.append(o)

    # torso
    add(rbox('pelvis', (0, 0.0, 0.97), (0.34, 0.22, 0.20), 'trousers', bevel=0.07), 'hips')
    add(rbox('belt', (0, 0.0, 1.02), (0.36, 0.24, 0.07), 'boots', bevel=0.03), 'hips')
    add(rbox('buckle', (0, -0.122, 1.02), (0.06, 0.01, 0.045), 'metal', bevel=0.005, outline=0.004), 'hips')
    add(rbox('holster', (-0.20, 0.0, 0.95), (0.06, 0.10, 0.16), 'boots', bevel=0.02), 'hips')
    add(rbox('pouch', (0.19, -0.04, 1.0), (0.05, 0.08, 0.08), 'boots', bevel=0.015), 'hips')
    add(rbox('abdomen', (0, 0.0, 1.16), (0.32, 0.20, 0.20), 'shirt', bevel=0.07), 'spine')
    add(rbox('chest', (0, 0.0, 1.36), (0.42, 0.25, 0.30), 'shirt', bevel=0.09), 'chest')
    add(rbox('vest', (0, 0.0, 1.30), (0.45, 0.285, 0.36), 'vest', bevel=0.06), 'chest')
    add(rbox('vest_band', (0, -0.006, 1.37), (0.452, 0.285, 0.05), 'hivis', bevel=0.02, outline=0.004), 'chest')
    add(rbox('badge', (0.09, -0.146, 1.44), (0.05, 0.01, 0.06), 'metal', bevel=0.01, outline=0.004), 'chest')
    add(rbox('radio', (-0.11, -0.15, 1.42), (0.05, 0.03, 0.09), 'boots', bevel=0.01, outline=0.005), 'chest')
    add(taper('neck', P('neck') + Vector((0, 0, -0.06)), P('head') + Vector((0, 0, 0.06)), 0.078, 0.07, 'skin'), 'neck')
    # head
    hc = P('head') + Vector((0, -0.01, 0.12))
    add(ellipsoid('head', hc, (0.115, 0.125, 0.14), 'skin'), 'head')
    add(ellipsoid('nose', hc + Vector((0, -0.125, -0.01)), (0.02, 0.025, 0.03), 'skin', outline=0.004), 'head')
    for x in (-1, 1):
        add(ellipsoid('eye', hc + Vector((0.045 * x, -0.112, 0.02)), (0.014, 0.01, 0.02), 'eye', outline=0), 'head')
        add(ellipsoid('ear', hc + Vector((0.115 * x, 0.0, 0.0)), (0.02, 0.03, 0.04), 'skin', outline=0.004), 'head')
        add(rbox('brow', hc + Vector((0.045 * x, -0.118, 0.055)), (0.04, 0.012, 0.012), 'boots', bevel=0.004, outline=0), 'head')
    # cap
    add(cyl('cap', hc + Vector((0, 0.0, 0.10)), 0.13, 0.09, 'cap', outline=0.01), 'head')
    add(cyl('capband', hc + Vector((0, 0.0, 0.075)), 0.132, 0.035, 'band', outline=0.0), 'head')
    add(rbox('brim', hc + Vector((0, -0.12, 0.06)), (0.2, 0.12, 0.015), 'boots', bevel=0.01, rot=(math.radians(-12), 0, 0), outline=0.006), 'head')
    add(cyl('capbadge', hc + Vector((0, -0.132, 0.085)), 0.018, 0.01, 'metal', rot=(math.radians(90), 0, 0), outline=0.003), 'head')
    for s, x in (('L', 1), ('R', -1)):
        add(ellipsoid('shoulder.' + s, P('shoulder.' + s) + Vector((0.02 * x, 0, 0)), (0.08, 0.08, 0.075), 'shirt'), 'chest')
        add(taper('upperarm.' + s, P('shoulder.' + s), P('elbow.' + s), 0.072, 0.058, 'shirt'), 'upper_arm.' + s)
        add(ellipsoid('elbow.' + s, P('elbow.' + s), (0.056, 0.056, 0.056), 'shirt', outline=0.006), 'upper_arm.' + s)
        add(taper('forearm.' + s, P('elbow.' + s), P('wrist.' + s), 0.056, 0.045, 'skin'), 'forearm.' + s)
        # hand: mitten + thumb
        w = P('wrist.' + s)
        add(rbox('hand.' + s, w + Vector((0, 0, -0.06)), (0.045, 0.085, 0.11), 'boots', bevel=0.02, subsurf=1, outline=0.008), 'hand.' + s)
        add(ellipsoid('thumb.' + s, w + Vector((0, -0.05, -0.04)), (0.018, 0.02, 0.035), 'boots', outline=0.005), 'hand.' + s)
        add(taper('thigh.' + s, P('hip.' + s) + Vector((0, 0, 0.04)), P('knee.' + s), 0.095, 0.068, 'trousers'), 'thigh.' + s)
        add(ellipsoid('knee.' + s, P('knee.' + s), (0.066, 0.068, 0.066), 'trousers', outline=0.006), 'thigh.' + s)
        add(taper('shin.' + s, P('knee.' + s), P('ankle.' + s) + Vector((0, 0, 0.06)), 0.066, 0.05, 'trousers'), 'shin.' + s)
        a = P('ankle.' + s)
        add(rbox('boot.' + s, a + Vector((0, -0.045, -0.045)), (0.11, 0.27, 0.11), 'boots', bevel=0.035, subsurf=1, outline=0.01), 'foot.' + s)
        add(rbox('bootcuff.' + s, a + Vector((0, 0.0, 0.04)), (0.11, 0.12, 0.08), 'boots', bevel=0.025, outline=0.008), 'shin.' + s)
    # pistol in right hand: barrel along hand bone axis (down in rest pose)
    w = P('wrist.R')
    g = []
    g.append(rbox('gun_slide', w + Vector((0, -0.055, -0.10)), (0.03, 0.05, 0.19), 'gun', bevel=0.006, outline=0.006))
    g.append(rbox('gun_grip', w + Vector((0, -0.0, -0.07)), (0.028, 0.09, 0.04), 'gun', bevel=0.006, outline=0.006))
    for o in g:
        add(o, 'hand.R')
    flash = ellipsoid('muzzle_flash', w + Vector((0, -0.055, -0.24)), (0.05, 0.05, 0.09), 'flash', outline=0)
    add(flash, 'hand.R')
    flash.hide_render = True
    return parts


# ---------------------------------------------------------------- posing helpers
class Animator:
    def __init__(self, rig):
        self.rig = rig
        self.prevq = {}

    def _rest(self, b):
        return self.rig.data.bones[b].matrix_local.to_3x3()

    def rot(self, b, f, x=0, y=0, z=0, order='XYZ'):
        """Key rotation of bone b at frame f. Angles in degrees about the
        character's axes (X = left/right pitch, Y = front/back roll, Z = up yaw),
        expressed in the parent's frame as if the parent were at rest."""
        R = self._rest(b)
        q_arm = Euler((math.radians(x), math.radians(y), math.radians(z)), order).to_quaternion()
        Rq = R.to_quaternion()
        q = Rq.inverted() @ q_arm @ Rq
        if b in self.prevq and self.prevq[b].dot(q) < 0:
            q.negate()
        self.prevq[b] = q.copy()
        pb = self.rig.pose.bones[b]
        pb.rotation_quaternion = q
        pb.keyframe_insert('rotation_quaternion', frame=f)

    def loc(self, b, f, x=0, y=0, z=0):
        """Key offset of bone b from its rest position, in character axes."""
        R = self._rest(b)
        v = R.inverted() @ Vector((x, y, z))
        pb = self.rig.pose.bones[b]
        pb.location = v
        pb.keyframe_insert('location', frame=f)

    def pos(self, b, f, x, y, z):
        """Key absolute position (root space) of a root-child control bone."""
        h = self.rig.data.bones[b].head_local
        self.loc(b, f, x - h.x, y - h.y, z - h.z)

    def ik(self, limb, f, v):
        """limb: 'arm.L' etc. v: 0..1 IK influence."""
        kind, s = limb.split('.')
        pb = self.rig.pose.bones[('forearm.' if kind == 'arm' else 'shin.') + s]
        pb.constraints['IK'].influence = v
        pb.constraints['IK'].keyframe_insert('influence', frame=f)
        hb = self.rig.pose.bones[('hand.' if kind == 'arm' else 'foot.') + s]
        hb.constraints['IKrot'].influence = v
        hb.constraints['IKrot'].keyframe_insert('influence', frame=f)


def set_interp(rig, kind='BEZIER', easing=None):
    for fc in rig.animation_data.action.fcurves:
        for k in fc.keyframe_points:
            k.interpolation = kind
            k.handle_left_type = 'AUTO_CLAMPED'
            k.handle_right_type = 'AUTO_CLAMPED'


def interp_range(rig, bones, f0, f1, kind='LINEAR', prop=None):
    for fc in rig.animation_data.action.fcurves:
        if not any('"%s"' % b in fc.data_path for b in bones):
            continue
        if prop and prop not in fc.data_path:
            continue
        for k in fc.keyframe_points:
            if f0 <= k.co.x < f1:
                k.interpolation = kind


# ---------------------------------------------------------------- scene
def setup_scene(frames, res=(720, 720), ortho=4.2, cam_target=(0, 0, 0.8), yaw=45, pitch=35, ground=True):
    s = C.scene
    s.render.engine = 'BLENDER_EEVEE_NEXT'
    s.eevee.taa_render_samples = 16
    s.render.resolution_x, s.render.resolution_y = res
    s.render.fps = 30
    s.frame_start, s.frame_end = frames
    s.view_settings.view_transform = 'Standard'
    s.render.film_transparent = False
    w = D.worlds.new('w')
    w.use_nodes = True
    w.node_tree.nodes['Background'].inputs[0].default_value = (0.62, 0.70, 0.78, 1)
    w.node_tree.nodes['Background'].inputs[1].default_value = 1.0
    s.world = w
    # sun
    sd = D.lights.new('sun', 'SUN')
    sd.energy = 4.0
    sd.angle = math.radians(2)
    sun = D.objects.new('sun', sd)
    C.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-30))
    # camera (orthographic, isometric-style)
    cd = D.cameras.new('cam')
    cd.type = 'ORTHO'
    cd.ortho_scale = ortho
    cam = D.objects.new('cam', cd)
    C.collection.objects.link(cam)
    s.camera = cam
    place_camera(cam, cam_target, yaw, pitch)
    return cam


def place_camera(cam, target, yaw, pitch, dist=20):
    t = Vector(target)
    y, p = math.radians(yaw), math.radians(pitch)
    # camera looks from direction (yaw around Z measured from -Y axis)
    d = Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p)))
    cam.location = t + d * dist
    cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()


def ground_tiles(size=14, tile=1.0, offset=(0, 0)):
    """Paving-slab ground made of slightly-separated tiles so motion reads."""
    bm = bmesh.new()
    n = int(size / tile)
    for i in range(-n // 2, n // 2):
        for j in range(-n // 2, n // 2):
            x0, y0 = i * tile + 0.01, j * tile + 0.01
            x1, y1 = x0 + tile - 0.02, y0 + tile - 0.02
            vs = [bm.verts.new((x, y, 0)) for x, y in ((x0, y0), (x1, y0), (x1, y1), (x0, y1))]
            f = bm.faces.new(vs)
            f.material_index = (i + j) % 2
    me = D.meshes.new('ground')
    bm.to_mesh(me)
    bm.free()
    o = D.objects.new('ground', me)
    C.collection.objects.link(o)
    me.materials.append(MATS['ground'])
    me.materials.append(MATS['ground2'])
    o.location = (offset[0], offset[1], 0)
    # dark grout under tiles
    bpy.ops.mesh.primitive_plane_add(size=size, location=(offset[0], offset[1], -0.005))
    g = C.active_object
    g.data.materials.append(toon_mat('grout', (0.3, 0.3, 0.32)))
    return o


def build_officer():
    mats()
    rig = build_rig()
    build_body(rig)
    return rig
