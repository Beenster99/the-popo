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
        if hasattr(m, 'shadow_method'):
            m.shadow_method = 'NONE'
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
    MATS['cap'] = toon_mat('cap', (0.05, 0.06, 0.13), shadow=0.6)
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
# ------------------------------------------------- skinned (bending) parts
def _skin(o, rig, groups, mat_names, outline):
    """Armature-deformed mesh: groups is {bone: [(vert index, weight)]}."""
    for b, vw in groups.items():
        vg = o.vertex_groups.new(name=b)
        for i, w in vw:
            if w > 0.0:
                vg.add([i], w, 'REPLACE')
    o.parent = rig
    m = o.modifiers.new('armature', 'ARMATURE')
    m.object = rig
    for n in mat_names:
        o.data.materials.append(MATS[n])
    o.data.materials.append(MATS['outline'])
    for poly in o.data.polygons:
        poly.use_smooth = True
    if outline:
        so = o.modifiers.new('outline', 'SOLIDIFY')
        so.thickness = outline
        so.offset = 1
        so.use_flip_normals = True
        so.material_offset = len(mat_names)
        so.use_rim = False
    return o


def _smooth01(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def skinned_limb(name, rig, pts, radii, bones, mats_per_seg, blend=0.1, outline=0.012, verts=16, rings=6):
    """One continuous tube through the joint points pts (radius radii[i] at
    each), bent by bones[i] along segment i, with weights blended across each
    joint so elbows and knees bend smoothly instead of needing a ball."""
    pts = [Vector(p) for p in pts]
    n = len(pts) - 1
    seg_len = [(pts[i + 1] - pts[i]).length for i in range(n)]
    dirs = [(pts[i + 1] - pts[i]).normalized() for i in range(n)]
    rings_all = []   # (centre, axis, radius, segment, distance along it)
    for i in range(n):
        for k in range(0 if i == 0 else 1, rings + 1):
            t = k / rings
            r = (radii[i] + (radii[i + 1] - radii[i]) * t) * (1.0 + 0.08 * math.sin(math.pi * t))
            if k == rings and i < n - 1:
                axis = (dirs[i] + dirs[i + 1]).normalized()
            elif k == 0 and i > 0:
                axis = (dirs[i - 1] + dirs[i]).normalized()
            else:
                axis = dirs[i]
            rings_all.append((pts[i].lerp(pts[i + 1], t), axis, r, i, t * seg_len[i]))
    # rounded ends
    c, ax, r, i, d = rings_all[0]
    head = [(c - ax * r * 0.8, ax, r * 0.45, i, d), (c - ax * r * 0.45, ax, r * 0.8, i, d)]
    c, ax, r, i, d = rings_all[-1]
    tail = [(c + ax * r * 0.45, ax, r * 0.8, i, d), (c + ax * r * 0.8, ax, r * 0.45, i, d)]
    rings_all = head + rings_all + tail
    bm = bmesh.new()
    weights = {}
    ring_verts = []
    vi = 0
    for c, axis, r, i, along in rings_all:
        ref = Vector((0, -1, 0))
        side = ref - axis * ref.dot(axis)
        if side.length < 1e-3:
            side = Vector((1, 0, 0)) - axis * axis.x
        side.normalize()
        up = axis.cross(side)
        w_next = 0.5 * _smooth01(1.0 - (seg_len[i] - along) / blend) if i < n - 1 else 0.0
        w_prev = 0.5 * _smooth01(1.0 - along / blend) if i > 0 else 0.0
        ws = {bones[i]: 1.0 - w_next - w_prev}
        if w_next > 0:
            ws[bones[i + 1]] = ws.get(bones[i + 1], 0) + w_next
        if w_prev > 0:
            ws[bones[i - 1]] = ws.get(bones[i - 1], 0) + w_prev
        vs = []
        for j in range(verts):
            a = 2 * math.pi * j / verts
            vs.append(bm.verts.new(c + side * math.cos(a) * r + up * math.sin(a) * r))
            for b, w in ws.items():
                weights.setdefault(b, []).append((vi, w))
            vi += 1
        ring_verts.append((vs, i))
    uniq = []
    for m_ in mats_per_seg:
        if m_ not in uniq:
            uniq.append(m_)
    for k in range(len(ring_verts) - 1):
        a, ia = ring_verts[k]
        b, ib = ring_verts[k + 1]
        mi = uniq.index(mats_per_seg[ib])
        for j in range(verts):
            f = bm.faces.new((a[j], b[j], b[(j + 1) % verts], a[(j + 1) % verts]))
            f.material_index = mi
    f0 = bm.faces.new(ring_verts[0][0])
    f0.material_index = uniq.index(mats_per_seg[0])
    f1 = bm.faces.new(list(reversed(ring_verts[-1][0])))
    f1.material_index = uniq.index(mats_per_seg[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = D.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = D.objects.new(name, me)
    C.collection.objects.link(o)
    return _skin(o, rig, weights, uniq, outline)


def skinned_loft(name, rig, sections, bone_at, mat_at, outline=0.012, verts=24, power=3.0):
    """A body shell lofted through rounded-rectangle sections (z, half width,
    half depth, y offset), skinned by bone_at(z) -> {bone: weight}."""
    bm = bmesh.new()
    weights = {}
    rings = []
    vi = 0
    for z, w, d, yo in sections:
        vs = []
        for j in range(verts):
            a = 2 * math.pi * j / verts
            ca, sa = math.cos(a), math.sin(a)
            # superellipse: squarer than an ellipse, rounder than a box
            x = w * math.copysign(abs(ca) ** (2 / power), ca)
            y = d * math.copysign(abs(sa) ** (2 / power), sa)
            vs.append(bm.verts.new((x, y + yo, z)))
            for b, wt in bone_at(z).items():
                weights.setdefault(b, []).append((vi, wt))
            vi += 1
        rings.append((vs, z))
    uniq = []
    def mi(z):
        m_ = mat_at(z)
        if m_ not in uniq:
            uniq.append(m_)
        return uniq.index(m_)
    for k in range(len(rings) - 1):
        a, za = rings[k]
        b, zb = rings[k + 1]
        m = mi(0.5 * (za + zb))
        for j in range(verts):
            f = bm.faces.new((a[j], a[(j + 1) % verts], b[(j + 1) % verts], b[j]))
            f.material_index = m
    fb = bm.faces.new(list(reversed(rings[0][0])))
    fb.material_index = mi(rings[0][1])
    ft = bm.faces.new(rings[-1][0])
    ft.material_index = mi(rings[-1][1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = D.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = D.objects.new(name, me)
    C.collection.objects.link(o)
    return _skin(o, rig, weights, uniq, outline)


def torso_bones(z):
    """hips below the belt, spine at the waist, chest above, blended."""
    if z <= 1.05:
        return {'hips': 1.0}
    if z <= 1.13:
        t = _smooth01((z - 1.05) / 0.08)
        return {'hips': 1 - t, 'spine': t}
    if z <= 1.24:
        return {'spine': 1.0}
    if z <= 1.32:
        t = _smooth01((z - 1.24) / 0.08)
        return {'spine': 1 - t, 'chest': t}
    return {'chest': 1.0}


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
    add(rbox('pelvis', (0, 0.0, 0.965), (0.31, 0.21, 0.19), 'trousers', bevel=0.07), 'hips')
    add(rbox('belt', (0, 0.0, 1.02), (0.33, 0.235, 0.065), 'boots', bevel=0.03), 'hips')
    add(rbox('buckle', (0, -0.12, 1.02), (0.06, 0.01, 0.045), 'metal', bevel=0.005, outline=0.004), 'hips')
    add(rbox('holster', (-0.185, 0.0, 0.95), (0.06, 0.10, 0.16), 'boots', bevel=0.02), 'hips')
    add(rbox('pouch', (0.175, -0.04, 1.0), (0.05, 0.08, 0.08), 'boots', bevel=0.015), 'hips')
    # Torso: one smooth shell (shirt), skinned to hips, spine and chest, and
    # (named 'chest' as before, which keeps the game's bone names chest_2 etc.)
    # narrow under the arms so they hang clear of it.
    shirt = [(1.00, 0.150, 0.105, 0.0), (1.06, 0.150, 0.108, 0.0), (1.14, 0.143, 0.110, 0.0),
             (1.24, 0.145, 0.118, 0.0), (1.33, 0.150, 0.125, 0.0), (1.41, 0.160, 0.120, 0.0),
             (1.47, 0.150, 0.105, 0.005), (1.515, 0.110, 0.085, 0.01), (1.535, 0.07, 0.06, 0.01)]
    parts.append(skinned_loft('chest', rig, shirt, torso_bones, lambda z: 'shirt'))
    # Vest over it, a little bigger, same shape.
    vest = [(1.08, 0.158, 0.120, 0.0), (1.14, 0.155, 0.124, 0.0), (1.24, 0.157, 0.132, 0.0),
            (1.33, 0.162, 0.140, 0.0), (1.40, 0.160, 0.134, 0.0), (1.455, 0.140, 0.118, 0.005),
            (1.48, 0.110, 0.10, 0.008)]
    parts.append(skinned_loft('vest', rig, vest, torso_bones, lambda z: 'hivis' if 1.345 < z < 1.385 else 'vest', power=3.4))
    vest_front = -0.142
    add(rbox('badge', (0.075, vest_front - 0.004, 1.43), (0.045, 0.01, 0.055), 'metal', bevel=0.01, outline=0.004), 'chest')
    add(rbox('radio', (-0.09, vest_front - 0.01, 1.415), (0.045, 0.03, 0.085), 'boots', bevel=0.01, outline=0.005), 'chest')
    add(taper('neck', P('neck') + Vector((0, 0, -0.06)), P('head') + Vector((0, 0, 0.06)), 0.078, 0.07, 'skin'), 'neck')
    # head
    hc = P('head') + Vector((0, -0.01, 0.12))
    add(ellipsoid('head', hc, (0.115, 0.125, 0.14), 'skin'), 'head')
    add(ellipsoid('nose', hc + Vector((0, -0.125, -0.01)), (0.02, 0.025, 0.03), 'skin', outline=0.004), 'head')
    for x in (-1, 1):
        add(ellipsoid('eye', hc + Vector((0.045 * x, -0.112, 0.02)), (0.014, 0.01, 0.02), 'eye', outline=0), 'head')
        add(ellipsoid('ear', hc + Vector((0.115 * x, 0.0, 0.0)), (0.02, 0.03, 0.04), 'skin', outline=0.004), 'head')
        add(rbox('brow', hc + Vector((0.045 * x, -0.118, 0.055)), (0.04, 0.012, 0.012), 'boots', bevel=0.004, outline=0), 'head')
    # Baseball cap: navy crown, curved peak, yellow lettering on the front.
    crown = ellipsoid('cap', hc + Vector((0, 0.008, 0.06)), (0.127, 0.135, 0.11), 'cap', outline=0.01)
    # keep the dome: cut the ellipsoid just below its middle (local coords)
    bmc = bmesh.new()
    bmc.from_mesh(crown.data)
    bmesh.ops.bisect_plane(bmc, geom=bmc.verts[:] + bmc.edges[:] + bmc.faces[:], plane_co=(0, 0, -0.01), plane_no=(0, 0, 1), clear_inner=True)
    bmc.to_mesh(crown.data)
    bmc.free()
    add(crown, 'head')
    peak = ellipsoid('cap_peak', hc + Vector((0, -0.145, 0.062)), (0.105, 0.085, 0.011), 'cap', rot=(math.radians(-14), 0, 0), outline=0.006)
    add(peak, 'head')
    add(ellipsoid('cap_button', hc + Vector((0, 0.008, 0.168)), (0.016, 0.016, 0.009), 'cap', outline=0.003), 'head')
    bpy.ops.object.text_add(location=hc + Vector((0, -0.118, 0.112)), rotation=(math.radians(66), 0, 0))
    txt = C.active_object
    txt.data.body = 'POPO'
    txt.data.size = 0.042
    txt.data.extrude = 0.003
    txt.data.align_x = 'CENTER'
    txt.data.align_y = 'CENTER'
    txt.data.font = D.fonts.load(_bold_font()) if _bold_font() else txt.data.font
    bpy.ops.object.convert(target='MESH')
    txt = C.active_object
    txt.name = 'cap_letters'
    add(finish(txt, 'hivis', outline=0, smooth=False), 'head')
    for s, x in (('L', 1), ('R', -1)):
        # Arm: one tube from inside the shoulder to the wrist (short sleeve,
        # bare forearm), skinned so the elbow bends smoothly.
        sh = P('shoulder.' + s)
        parts.append(skinned_limb('arm.' + s, rig,
            [sh + Vector((-0.06 * x, 0.0, 0.025)), sh + Vector((0.005 * x, 0, -0.01)), P('elbow.' + s), P('wrist.' + s) + Vector((0, 0, 0.015))],
            [0.068, 0.072, 0.054, 0.042], ['chest', 'upper_arm.' + s, 'forearm.' + s], ['shirt', 'shirt', 'skin'], blend=0.07))
        # hand: mitten + thumb
        w = P('wrist.' + s)
        add(rbox('hand.' + s, w + Vector((0, 0, -0.06)), (0.045, 0.085, 0.11), 'boots', bevel=0.02, subsurf=1, outline=0.008), 'hand.' + s)
        add(ellipsoid('thumb.' + s, w + Vector((0, -0.05, -0.04)), (0.018, 0.02, 0.035), 'boots', outline=0.005), 'hand.' + s)
        # Leg: one tube hip to ankle, skinned so the knee bends smoothly.
        parts.append(skinned_limb('leg.' + s, rig,
            [P('hip.' + s) + Vector((0, 0, 0.07)), P('knee.' + s), P('ankle.' + s) + Vector((0, 0, 0.07))],
            [0.092, 0.064, 0.050], ['thigh.' + s, 'shin.' + s], ['trousers', 'trousers'], blend=0.09))
        a = P('ankle.' + s)
        add(rbox('boot.' + s, a + Vector((0, -0.045, -0.045)), (0.11, 0.27, 0.11), 'boots', bevel=0.035, subsurf=1, outline=0.01), 'foot.' + s)
        add(rbox('bootcuff.' + s, a + Vector((0, 0.0, 0.04)), (0.11, 0.12, 0.08), 'boots', bevel=0.025, outline=0.008), 'shin.' + s)
    # A fresh magazine in the left fist, shown only mid-reload (the game
    # switches it on and off).
    wl = P('wrist.L')
    add(rbox('spare_mag', wl + Vector((0, -0.035, -0.10)), (0.024, 0.034, 0.10), 'gun', bevel=0.005, outline=0.005), 'hand.L')
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
    for fc in fcurves(rig.animation_data.action):
        for k in fc.keyframe_points:
            k.interpolation = kind
            k.handle_left_type = 'AUTO_CLAMPED'
            k.handle_right_type = 'AUTO_CLAMPED'


def interp_range(rig, bones, f0, f1, kind='LINEAR', prop=None):
    for fc in fcurves(rig.animation_data.action):
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


def _bold_font():
    import os
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"):
        if os.path.exists(f):
            return f
    return None


def build_officer():
    mats()
    rig = build_rig()
    build_body(rig)
    return rig


def fcurves(action):
    """An action's F-curves on Blender 4 (action.fcurves) and 5 (layered
    actions: the curves live in the channel bags of its keyframe strips)."""
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    out = []
    for layer in action.layers:
        for strip in layer.strips:
            for bag in getattr(strip, "channelbags", []):
                out.extend(bag.fcurves)
    return out
