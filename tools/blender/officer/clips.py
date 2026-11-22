"""Hand-keyed clips. Conventions (character faces -Y, left = +X):
 up bones (hips/spine/chest/neck/head): +X lean forward, +Z turn left, +Y lean left
 down bones (thigh/upper_arm): +X swing back, -X swing forward
 shin: +X bends knee; forearm: -X bends elbow
 foot_ik/hand_ik: +X tip down/back. hand pointing forward = X -90
"""
import math, bpy
from mathutils import Vector
import officer as O

D = bpy.data


def gun_visible(rig, show):
    for o in D.objects:
        if o.name.startswith('gun_'):
            o.hide_render = not show
            o.hide_viewport = not show


def flash_keys(frames, dur=2):
    fl = D.objects['muzzle_flash']
    fl.hide_render = True
    fl.keyframe_insert('hide_render', frame=1)
    for f in frames:
        fl.hide_render = False
        fl.keyframe_insert('hide_render', frame=f)
        fl.hide_render = True
        fl.keyframe_insert('hide_render', frame=f + dur)
    for fc in fl.animation_data.action.fcurves:
        for k in fc.keyframe_points:
            k.interpolation = 'CONSTANT'


def add_box(name, loc, size, mat, bevel=0.02):
    return O.rbox(name, loc, size, mat, bevel=bevel, outline=0.015)


# ------------------------------------------------------------------ RUN
def run(rig, A):
    gun_visible(rig, False)
    N = 20           # frames per cycle (2 steps)
    v = 0.11         # metres per frame (3.3 m/s)
    half = N // 2
    # foot path for one leg, phase t in [0, N): (t, y, z, pitch)
    path = [(0, -0.28, 0.10, -8), (3, 0.05, 0.10, 0), (6, 0.38, 0.14, 38), (8, 0.47, 0.33, 70),
            (10, 0.32, 0.55, 80), (13, -0.12, 0.50, 25), (16, -0.40, 0.30, -5), (18, -0.37, 0.16, -12),
            (20, -0.28, 0.10, -8)]
    for s, x, ph in (('L', 0.085, 0), ('R', -0.085, half)):
        keys = {}
        for t, y, z, p in path:
            f = (t + ph) % N
            keys[f] = (y, z, p)
        if 0 in keys:
            keys[N] = keys[0]
        if N in keys and 0 not in keys:
            keys[0] = keys[N]
        for f in sorted(keys):
            y, z, p = keys[f]
            A.pos('foot_ik.' + s, f + 1, x, y + 0.0, z)
            A.rot('foot_ik.' + s, f + 1, p, 0, 0)
    # hips: bob twice per cycle, yaw/roll once
    for t in range(0, N + 1, 1):
        ph = 2 * math.pi * t / N
        # vertical: lowest ~2 frames after contact, highest in flight (t~8)
        bob = -0.075 + 0.03 * math.cos(2 * ph - 1.6 * math.pi)
        if t % 2 == 0:
            A.loc('hips', t + 1, 0.018 * math.cos(ph - 0.9), 0.0, bob)
            A.rot('hips', t + 1, 6, -4 * math.sin(ph - 0.3), -9 * math.cos(ph))
            A.rot('spine', t + 1, 8 + 1.5 * math.cos(2 * ph), 2 * math.sin(ph), 8 * math.cos(ph))
            A.rot('chest', t + 1, 5, 1 * math.sin(ph), 9 * math.cos(ph - 0.25))
            A.rot('neck', t + 1, -6, 0, -4 * math.cos(ph))
            A.rot('head', t + 1, -6 - 2 * math.cos(2 * ph + 0.6), 0, -4 * math.cos(ph))
            # arms opposite legs. at t0 left leg forward -> left arm back
            a = math.cos(ph - 0.35)
            A.rot('upper_arm.L', t + 1, 42 * a - 5, -12, 0)
            A.rot('upper_arm.R', t + 1, -42 * a - 5, 12, 0)
            A.rot('forearm.L', t + 1, -88 + 20 * a, 0, 0)
            A.rot('forearm.R', t + 1, -88 - 20 * a, 0, 0)
            A.rot('hand.L', t + 1, -10, 0, 0)
            A.rot('hand.R', t + 1, -10, 0, 0)
    act = rig.animation_data.action
    for fc in act.fcurves:
        fc.modifiers.new('CYCLES')
    # contact phases linear on Y
    for s, ph in (('L', 0), ('R', half)):
        for fc in act.fcurves:
            if '"foot_ik.%s"' % s in fc.data_path and 'location' in fc.data_path:
                for k in fc.keyframe_points:
                    t = (k.co.x - 1 - ph) % N
                    if t < 6 - 1e-6 or (t == 0):
                        k.interpolation = 'LINEAR'
    # moving ground (treadmill) so the run reads
    g = D.objects['ground']
    g.location.y = -9
    g.keyframe_insert('location', index=1, frame=1)
    g.location.y = -9 + v * 200
    g.keyframe_insert('location', index=1, frame=201)
    for fc in g.animation_data.action.fcurves:
        for k in fc.keyframe_points:
            k.interpolation = 'LINEAR'
    return (1, 60)


# ------------------------------------------------------------------ AIM
def aim_pose(A, f, scan=0.0, recoil=0.0, breathe=0.0):
    """Two-handed isosceles aim. scan: degrees yaw (left +)."""
    A.loc('hips', f, 0, 0.02, -0.05)
    A.rot('hips', f, 4, 0, scan * 0.3)
    A.rot('spine', f, 6, 0, scan * 0.3)
    A.rot('chest', f, 4 + breathe - recoil * 3, 0, scan * 0.4)
    A.rot('neck', f, 6, 0, 0)
    A.rot('head', f, 2 + recoil * 2, -4, 0)
    ang = math.radians(scan)
    def rotp(x, y):
        return x * math.cos(ang) - y * math.sin(ang), x * math.sin(ang) + y * math.cos(ang)
    rx, ry = rotp(-0.03, -0.47 + recoil * 0.06)
    lx, ly = rotp(0.01, -0.44 + recoil * 0.06)
    z = 1.39 + recoil * 0.035 + breathe * 0.004
    A.pos('hand_ik.R', f, rx, ry, z)
    A.rot('hand_ik.R', f, -90 - recoil * 18, 0, scan + 4)
    A.pos('hand_ik.L', f, lx, ly, z - 0.035)
    A.rot('hand_ik.L', f, -88 - recoil * 18, 0, scan - 25)


def low_ready(A, f, breathe=0.0):
    A.loc('hips', f, 0, 0.0, -0.03)
    A.rot('hips', f, 2, 0, 0)
    A.rot('spine', f, 4, 0, 0)
    A.rot('chest', f, 3 + breathe, 0, 0)
    A.rot('neck', f, 2, 0, 0)
    A.rot('head', f, 4 + breathe * 0.5, 0, 0)
    A.pos('hand_ik.R', f, -0.04, -0.30, 1.08 + breathe * 0.004)
    A.rot('hand_ik.R', f, -42, 0, 6)
    A.pos('hand_ik.L', f, 0.0, -0.27, 1.05 + breathe * 0.004)
    A.rot('hand_ik.L', f, -40, 0, -28)


def stance_feet(A, f):
    A.pos('foot_ik.L', f, 0.15, -0.10, 0.10)
    A.rot('foot_ik.L', f, 0, 0, 8)
    A.pos('foot_ik.R', f, -0.16, 0.12, 0.10)
    A.rot('foot_ik.R', f, 0, 0, -14)


def aim(rig, A):
    gun_visible(rig, True)
    for s in 'LR':
        A.ik('arm.' + s, 1, 1)
    stance_feet(A, 1)
    for f, b in ((1, 0), (10, 1), (20, 0)):
        low_ready(A, f, breathe=b)
    # snap up to aim with a small overshoot and settle
    aim_pose(A, 27, recoil=-0.35)
    aim_pose(A, 31, recoil=0.12)
    aim_pose(A, 35)
    aim_pose(A, 45, breathe=0.8)
    # scan left then right
    aim_pose(A, 56, scan=22)
    aim_pose(A, 62, scan=24, breathe=0.5)
    aim_pose(A, 74, scan=-6)
    aim_pose(A, 78, scan=0)
    # double tap
    for f0 in (84, 92):
        aim_pose(A, f0, 0)
        aim_pose(A, f0 + 1, recoil=1.0)
        aim_pose(A, f0 + 4, recoil=0.25)
        aim_pose(A, f0 + 7, recoil=0.0)
    aim_pose(A, 108, breathe=0.6)
    low_ready(A, 118)
    low_ready(A, 126, breathe=1)
    low_ready(A, 135)
    stance_feet(A, 135)
    flash_keys([85, 93])
    return (1, 135)


# ------------------------------------------------------------------ ROLL
def roll(rig, A):
    gun_visible(rig, False)
    # hips: (frame, loc y, loc z, pitch)
    hp = [(1, 0, 0, 0), (7, -0.12, -0.33, 32), (11, -0.38, -0.42, 70), (14, -0.60, -0.38, 115),
          (17, -0.86, -0.46, 170), (20, -1.08, -0.60, 228), (23, -1.30, -0.62, 290),
          (26, -1.50, -0.52, 360 + 32), (30, -1.56, -0.44, 360 + 36), (36, -1.55, -0.25, 360 + 18),
          (44, -1.52, -0.02, 360 + 2), (55, -1.52, 0, 360)]
    for f, y, z, p in hp:
        A.loc('hips', f, 0, y, z)
        A.rot('hips', f, p, 0, 0)
    # spine curl
    curl = {1: 0, 7: 0.6, 11: 1, 14: 1, 23: 1, 26: 0.8, 30: 0.6, 36: 0.3, 44: 0.05, 55: 0}
    for f, c in curl.items():
        A.rot('spine', f, 22 * c, 0, 0)
        A.rot('chest', f, 20 * c, 0, 0)
        A.rot('neck', f, 30 * c - (8 if f in (26, 30) else 0), 0, 0)
        A.rot('head', f, 25 * c - (14 if f in (26, 30, 36) else 0), 0, 0)
    # arms: reach to ground, then tuck, then out for balance
    arms = [(1, 0, 0, 0), (7, -55, -20, -10), (11, -95, -15, 0), (14, -150, -60, 0), (20, -100, -110, 0),
            (26, -70, -80, -10), (30, -60, -70, -15), (36, -30, -60, -10), (44, 0, -20, 0), (55, 0, -8, 0)]
    for f, u, fo, h in arms:
        A.rot('upper_arm.L', f, u, -8, 0)
        A.rot('upper_arm.R', f, u, 8, 0)
        A.rot('forearm.L', f, fo, 0, 0)
        A.rot('forearm.R', f, fo, 0, 0)
        A.rot('hand.L', f, h, 0, 0)
        A.rot('hand.R', f, h, 0, 0)
    # legs: IK planted at start, FK tuck mid-roll, IK planted on landing
    for s, x in (('L', 0.1), ('R', -0.1)):
        A.pos('foot_ik.' + s, 1, x, 0.02, 0.10)
        A.rot('foot_ik.' + s, 1, 0, 0, 0)
        A.pos('foot_ik.' + s, 11, x, 0.02, 0.10)
        A.rot('foot_ik.' + s, 11, 30, 0, 0)  # heels up, pushing off
        A.pos('foot_ik.' + s, 13, x, -0.05, 0.16)
        A.rot('foot_ik.' + s, 13, 55, 0, 0)
        A.ik('leg.' + s, 11, 1)
        A.ik('leg.' + s, 13, 0)
        A.ik('leg.' + s, 23, 0)
        A.ik('leg.' + s, 25, 1)
        lx = x * 1.4
        A.pos('foot_ik.' + s, 25, lx, -1.48, 0.12)
        A.rot('foot_ik.' + s, 25, -5, 0, 0)
        A.pos('foot_ik.' + s, 26, lx, -1.50, 0.10)
        A.rot('foot_ik.' + s, 26, 0, 0, 0)
        A.pos('foot_ik.' + s, 55, lx, -1.50, 0.10)
        A.rot('foot_ik.' + s, 55, 0, 0, 0)
        # FK tuck
        for f, th, sh, ft in ((1, 0, 0, 0), (11, -20, 50, 30), (13, -95, 135, 40), (17, -120, 145, 30),
                              (20, -125, 145, 20), (23, -110, 140, 10), (26, -95, 125, 0), (55, 0, 0, 0)):
            A.rot('thigh.' + s, f, th, 0, 0)
            A.rot('shin.' + s, f, sh, 0, 0)
            A.rot('foot.' + s, f, ft, 0, 0)
    return (1, 55)


# ------------------------------------------------------------------ MANTLE
def mantle(rig, A):
    gun_visible(rig, False)
    add_box('wall', (0, -0.75, 0.5), (2.4, 0.4, 1.0), 'brick', bevel=0.02)
    add_box('coping', (0, -0.75, 1.0), (2.5, 0.48, 0.06), 'concrete', bevel=0.01)
    # hips (frame, y, z, pitch)
    hp = [(1, 0, 0, 0), (5, -0.05, -0.12, 14), (8, -0.20, -0.16, 30), (11, -0.36, 0.20, 40),
          (14, -0.52, 0.50, 42), (17, -0.70, 0.70, 30), (20, -0.86, 0.80, 18), (23, -1.10, 0.62, 12),
          (26, -1.38, 0.15, 18), (28, -1.50, -0.28, 32), (31, -1.53, -0.38, 30), (40, -1.54, -0.06, 8),
          (52, -1.52, 0, 0)]
    for f, y, z, p in hp:
        A.loc('hips', f, 0, y, z)
        A.rot('hips', f, p, 0, 0)
    sp = {1: (0, 0), 5: (6, 6), 8: (12, 10), 11: (16, 12), 14: (16, 12), 17: (10, 8), 20: (4, 4),
          23: (0, -4), 26: (4, 4), 28: (14, 10), 31: (14, 10), 40: (4, 3), 52: (0, 0)}
    for f, (a, b) in sp.items():
        A.rot('spine', f, a, 0, 0)
        A.rot('chest', f, b, 0, 0)
        A.rot('neck', f, -0.5 * (a + b) - 4 if f < 40 else 0, 0, 0)
        A.rot('head', f, -0.3 * (a + b) if f < 40 else 0, 0, 0)
    # arms: FK swing forward, IK plant on coping, release, balance
    for s, x in (('L', 1), ('R', -1)):
        A.ik('arm.' + s, 4, 0)
        A.ik('arm.' + s, 8, 1)
        A.ik('arm.' + s, 16, 1)
        A.ik('arm.' + s, 20, 0)
        A.pos('hand_ik.' + s, 4, 0.30 * x, -0.45, 1.15)
        A.rot('hand_ik.' + s, 4, -80, 0, 0)
        for f in (8, 16):
            A.pos('hand_ik.' + s, f, 0.24 * x, -0.66, 1.10)
            A.rot('hand_ik.' + s, f, -95, 0, -20 * x)
        A.pos('hand_ik.' + s, 20, 0.30 * x, -0.80, 1.20)
        A.rot('hand_ik.' + s, 20, -95, 0, -20 * x)
        for f, u, ab, fo in ((1, 0, 0, 0), (4, -55, 0, -40), (20, -40, 25, -30), (24, -60, 45, -20),
                             (28, -40, 50, -30), (31, -30, 40, -40), (40, -5, 10, -15), (52, 0, 0, -6)):
            A.rot('upper_arm.' + s, f, u, -ab * x, 0)
            A.rot('forearm.' + s, f, fo, 0, 0)
    # feet: (frame, y, z, pitch) per foot
    feetL = [(1, 0.02, 0.10, 0), (3, -0.10, 0.20, -10), (5, -0.30, 0.10, 0), (9, -0.30, 0.10, 20),
             (11, -0.30, 0.14, 45), (13, -0.42, 0.45, 50), (15, -0.55, 0.85, 20), (17, -0.76, 1.13, 0),
             (20, -0.84, 1.13, 10), (21, -0.86, 1.15, 35), (23, -1.10, 0.85, 20), (25, -1.45, 0.25, -10),
             (26, -1.55, 0.10, 0), (52, -1.55, 0.10, 0)]
    feetR = [(1, 0.02, 0.10, 0), (8, 0.02, 0.10, 20), (10, -0.05, 0.25, 50), (12, -0.35, 0.80, 20),
             (14, -0.62, 1.13, 0), (19, -0.64, 1.13, 15), (21, -0.80, 1.16, 40), (23, -1.05, 0.90, 25),
             (25, -1.38, 0.30, -5), (26, -1.45, 0.10, 0), (52, -1.45, 0.10, 0)]
    for s, x, keys in (('L', 0.12, feetL), ('R', -0.12, feetR)):
        for f, y, z, p in keys:
            A.pos('foot_ik.' + s, f, x, y, z)
            A.rot('foot_ik.' + s, f, p, 0, 0)
    return (1, 52)


# ------------------------------------------------------------------ COVER PEEK
def cover(rig, A, f, lean=0.0, kneel=False, breathe=0.0, recoil=0.0, scan=0.0):
    """Corner cover; wall edge on the character's right. lean 0..1 peeks out to the right."""
    kz = -0.45 if kneel else -0.07
    A.loc('hips', f, -0.18 * lean, 0.0, kz)
    A.rot('hips', f, 4, -6 * lean, 0)
    A.rot('spine', f, 6, -15 * lean, -4 * lean)
    A.rot('chest', f, 6 + breathe - 2 * recoil, -15 * lean, -4 * lean)
    A.rot('neck', f, 6, 6 * lean, 0)
    A.rot('head', f, 2, 4 * lean, -6 * (1 - lean) + scan * 0.3)
    # gun: compressed high ready close to the chest (in cover) -> extended aim (peeking)
    sh_drop = 0.40 if kneel else 0.0
    cx = -0.02 + (-0.60) * lean
    cz = 1.26 + 0.12 * lean - sh_drop * (1.0 if not kneel else 0.98) + recoil * 0.03 + breathe * 0.003
    cy = -0.22 - 0.22 * lean + recoil * 0.05
    pitch = -60 - 30 * lean - recoil * 18
    A.pos('hand_ik.R', f, cx - 0.02, cy, cz)
    A.rot('hand_ik.R', f, pitch, 0, 4 + scan)
    A.pos('hand_ik.L', f, cx + 0.02, cy + 0.03, cz - 0.035)
    A.rot('hand_ik.L', f, pitch + 2, 0, -25 + scan)


def cover_feet(A, f, kneel=False, lean=0.0):
    if not kneel:
        A.pos('foot_ik.L', f, 0.16, -0.02, 0.10)
        A.rot('foot_ik.L', f, 0, 0, 10)
        A.pos('foot_ik.R', f, -0.16 - 0.22 * lean, 0.04, 0.10)
        A.rot('foot_ik.R', f, 0, 0, -12)
    else:
        A.pos('foot_ik.L', f, 0.17, -0.26, 0.10)
        A.rot('foot_ik.L', f, 0, 0, 6)
        A.pos('foot_ik.R', f, -0.14 - 0.10 * lean, 0.44, 0.17)
        A.rot('foot_ik.R', f, 62, 0, -6)


def peek(rig, A):
    gun_visible(rig, True)
    add_box('wall', (1.02, -0.52, 1.1), (2.6, 0.32, 2.2), 'brick', bevel=0.02)
    add_box('crate', (-1.4, -2.6, 0.4), (0.8, 0.8, 0.8), 'concrete', bevel=0.03)
    for s in 'LR':
        A.ik('arm.' + s, 1, 1)
    cover_feet(A, 1)
    cover(A=A, rig=rig, f=1)
    cover(rig, A, 12, breathe=1)
    cover(rig, A, 22)
    cover_feet(A, 22)
    # standing peek
    cover(rig, A, 27, lean=0.75)
    cover(rig, A, 30, lean=1.04)
    cover(rig, A, 33, lean=1.0)
    cover_feet(A, 27, lean=1)
    cover(rig, A, 42, lean=1.0, scan=6)
    for f0 in (46, 52):
        cover(rig, A, f0, lean=1.0)
        cover(rig, A, f0 + 1, lean=1.0, recoil=1)
        cover(rig, A, f0 + 4, lean=1.0, recoil=0.25)
    cover(rig, A, 62, lean=1.0, breathe=0.5)
    cover(rig, A, 65, lean=0.95)
    cover(rig, A, 70, lean=-0.04)
    cover(rig, A, 74, lean=0.0)
    cover_feet(A, 64, lean=1)
    cover_feet(A, 70)
    cover(rig, A, 80, breathe=0.8)
    # drop to a kneel: right knee down
    cover_feet(A, 82)
    A.pos('foot_ik.R', 86, -0.15, 0.25, 0.30)
    A.rot('foot_ik.R', 86, 40, 0, -6)
    cover_feet(A, 90, kneel=True)
    A.pos('foot_ik.L', 84, 0.17, -0.14, 0.22)
    A.rot('foot_ik.L', 84, -5, 0, 8)
    cover(rig, A, 84, breathe=0.5)
    cover(rig, A, 91, kneel=True)
    cover(rig, A, 94, kneel=True)
    cover(rig, A, 104, kneel=True, breathe=1)
    # low peek
    cover(rig, A, 109, kneel=True, lean=0.8)
    cover(rig, A, 112, kneel=True, lean=1.03)
    cover(rig, A, 115, kneel=True, lean=1.0)
    cover_feet(A, 104, kneel=True)
    cover_feet(A, 110, kneel=True, lean=1)
    cover(rig, A, 120, kneel=True, lean=1.0, scan=-5)
    cover(rig, A, 122, kneel=True, lean=1.0)
    cover(rig, A, 123, kneel=True, lean=1.0, recoil=1)
    cover(rig, A, 126, kneel=True, lean=1.0, recoil=0.2)
    cover(rig, A, 134, kneel=True, lean=1.0)
    cover(rig, A, 139, kneel=True, lean=-0.03)
    cover(rig, A, 142, kneel=True)
    cover_feet(A, 136, kneel=True, lean=1)
    cover_feet(A, 140, kneel=True)
    cover(rig, A, 155, kneel=True, breathe=1)
    cover_feet(A, 155, kneel=True)
    flash_keys([47, 53, 123])
    return (1, 155)


CLIPS = {
    'run': dict(fn=run, target=(0, -0.3, 0.8), ortho=3.6, yaw=45, ground_off=(0, 0)),
    'aim': dict(fn=aim, target=(0, -0.2, 0.95), ortho=3.0, yaw=45),
    'roll': dict(fn=roll, target=(0, -0.85, 0.6), ortho=3.8, yaw=60),
    'mantle': dict(fn=mantle, target=(0, -0.8, 0.85), ortho=3.8, yaw=60),
    'peek': dict(fn=peek, target=(-0.2, -0.6, 0.9), ortho=3.4, yaw=215),
}
