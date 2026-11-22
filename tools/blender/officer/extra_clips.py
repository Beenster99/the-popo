"""Extra hand-keyed clips for the Phase 0.6 movement course, using the same
rig, Animator and conventions as clips.py (character faces -Y, left = +X).

These are placeholders in the hand-keyed style until the mocap base takes
over (see docs/wave0/README.md). Each function keys one action and returns
its (first, last) frame. Loops end on the same pose they start on.
"""
import math
import clips as K


def _arms_relaxed(A, f, swing=0.0):
    A.rot('upper_arm.L', f, swing - 4, -8, 0)
    A.rot('upper_arm.R', f, -swing - 4, 8, 0)
    A.rot('forearm.L', f, -18, 0, 0)
    A.rot('forearm.R', f, -18, 0, 0)


def _feet(A, f, spread=0.11, l=(0, 0.10, 0), r=(0, 0.10, 0), pl=0, pr=0):
    A.pos('foot_ik.L', f, spread + l[0], l[1] if len(l) > 2 else 0, l[2] if len(l) > 2 else 0.10)
    A.rot('foot_ik.L', f, pl, 0, 4)
    A.pos('foot_ik.R', f, -spread + r[0], r[1] if len(r) > 2 else 0, r[2] if len(r) > 2 else 0.10)
    A.rot('foot_ik.R', f, pr, 0, -4)


def idle(rig, A):
    K.gun_visible(rig, False)
    for f, b in ((1, 0.0), (31, 1.0), (61, 0.0)):
        A.loc('hips', f, 0.01 * b, 0, -0.02 - 0.005 * b)
        A.rot('hips', f, 1, 0, 0)
        A.rot('spine', f, 2, 0, 0)
        A.rot('chest', f, 1 + 2.0 * b, 0, 0)
        A.rot('neck', f, 0, 0, 0)
        A.rot('head', f, 1 * b, 0, 3 * b)
        _arms_relaxed(A, f, 1.5 * b)
        _feet(A, f, l=(0, 0.02, 0.10), r=(0, -0.03, 0.10))
    return (1, 61)


def walk(rig, A):
    """In-place walk cycle, 1.4 m/s, 32 frames (two steps)."""
    K.gun_visible(rig, False)
    N = 32
    half = N // 2
    path = [(0, -0.30, 0.10, -4), (10, 0.02, 0.10, 0), (16, 0.28, 0.12, 18), (20, 0.30, 0.18, 22),
            (24, 0.12, 0.17, 10), (28, -0.15, 0.12, -6), (32, -0.30, 0.10, -4)]
    # one leg on the ground from 0 to 16 (moves back linearly), swing 16..32
    path = [(0, 0.30, 0.10, 0), (16, -0.30, 0.10, -6), (20, -0.20, 0.17, -14), (24, 0.05, 0.19, 10),
            (28, 0.27, 0.13, 14), (32, 0.30, 0.10, 0)]
    for s, x, ph in (('L', 0.09, 0), ('R', -0.09, half)):
        keys = {}
        for t, y, z, p in path:
            keys[(t + ph) % N] = (y, z, p)
        keys[N] = keys[0]
        for f in sorted(keys):
            y, z, p = keys[f]
            A.pos('foot_ik.' + s, f + 1, x, y, z)
            A.rot('foot_ik.' + s, f + 1, p, 0, 0)
    for t in range(0, N + 1, 2):
        ph = 2 * math.pi * t / N
        A.loc('hips', t + 1, 0.02 * math.cos(ph), 0.0, -0.035 + 0.015 * math.cos(2 * ph))
        A.rot('hips', t + 1, 2, -2 * math.sin(ph), -5 * math.cos(ph))
        A.rot('spine', t + 1, 3, 0, 4 * math.cos(ph))
        A.rot('chest', t + 1, 1, 0, 4 * math.cos(ph))
        A.rot('head', t + 1, 0, 0, -3 * math.cos(ph))
        a = math.cos(ph)
        A.rot('upper_arm.L', t + 1, -20 * a - 3, -8, 0)
        A.rot('upper_arm.R', t + 1, 20 * a - 3, 8, 0)
        A.rot('forearm.L', t + 1, -25 + 10 * a, 0, 0)
        A.rot('forearm.R', t + 1, -25 - 10 * a, 0, 0)
    return (1, N + 1)


def crouch_idle(rig, A):
    K.gun_visible(rig, True)
    for s in 'LR':
        A.ik('arm.' + s, 1, 1)
    for f, b in ((1, 0), (31, 1), (61, 0)):
        A.loc('hips', f, 0, 0.06, -0.42)
        A.rot('hips', f, 18, 0, 0)
        A.rot('spine', f, 10, 0, 0)
        A.rot('chest', f, 6 + b * 1.5, 0, 0)
        A.rot('neck', f, -12, 0, 0)
        A.rot('head', f, -10, 0, 0)
        # Feet apart and flat, left a little ahead: a balanced low crouch.
        # (Narrow feet with the right one tucked behind on its toes read as
        # crossed legs from the iso camera.)
        A.pos('foot_ik.L', f, 0.20, -0.12, 0.10)
        A.rot('foot_ik.L', f, 0, 0, 10)
        A.pos('foot_ik.R', f, -0.20, 0.10, 0.10)
        A.rot('foot_ik.R', f, 8, 0, -12)
        # Knees point out over the feet, not in toward each other.
        A.loc('knee_pole.L', f, 0.15, 0, 0)
        A.loc('knee_pole.R', f, -0.15, 0, 0)
        K.low_ready(A, f, breathe=b)
        A.loc('hips', f, 0, 0.06, -0.42)
        A.rot('hips', f, 18, 0, 0)
        A.pos('hand_ik.R', f, -0.04, -0.34, 0.74 + b * 0.004)
        A.pos('hand_ik.L', f, 0.0, -0.31, 0.71 + b * 0.004)
    return (1, 61)


def crouch_walk(rig, A):
    K.gun_visible(rig, True)
    for s in 'LR':
        A.ik('arm.' + s, 1, 1)
    N = 36
    half = N // 2
    path = [(0, 0.26, 0.10, 0), (18, -0.26, 0.10, -6), (23, -0.14, 0.16, -10), (28, 0.10, 0.17, 6),
            (32, 0.24, 0.12, 8), (36, 0.26, 0.10, 0)]
    for s, x, ph in (('L', 0.15, 0), ('R', -0.15, half)):
        keys = {}
        for t, y, z, p in path:
            keys[(t + ph) % N] = (y, z, p)
        keys[N] = keys[0]
        for f in sorted(keys):
            y, z, p = keys[f]
            A.pos('foot_ik.' + s, f + 1, x, y, z)
            A.rot('foot_ik.' + s, f + 1, p, 0, 0)
    for t in range(0, N + 1, 3):
        ph = 2 * math.pi * t / N
        A.loc('hips', t + 1, 0.025 * math.cos(ph), 0.04, -0.40 + 0.015 * math.cos(2 * ph))
        A.rot('hips', t + 1, 20, 0, -6 * math.cos(ph))
        A.loc('knee_pole.L', t + 1, 0.12, 0, 0)
        A.loc('knee_pole.R', t + 1, -0.12, 0, 0)
        A.rot('spine', t + 1, 10, 0, 3 * math.cos(ph))
        A.rot('chest', t + 1, 8, 0, 3 * math.cos(ph))
        A.rot('neck', t + 1, -14, 0, 0)
        A.rot('head', t + 1, -12, 0, 0)
        A.pos('hand_ik.R', t + 1, -0.05, -0.36, 0.80 + 0.01 * math.cos(2 * ph))
        A.rot('hand_ik.R', t + 1, -55, 0, 6)
        A.pos('hand_ik.L', t + 1, -0.01, -0.33, 0.77 + 0.01 * math.cos(2 * ph))
        A.rot('hand_ik.L', t + 1, -52, 0, -28)
    return (1, N + 1)


def _prone_arms(A, f, sway=0.0):
    """Elbows on the ground ahead of the shoulders, forearms forward, both
    hands together on the pistol, barrel level and pointing ahead."""
    A.rot('upper_arm.L', f, -138 + sway, -22, 0)
    A.rot('upper_arm.R', f, -138 - sway, 22, 0)
    A.rot('forearm.L', f, -32, 0, -30)
    A.rot('forearm.R', f, -28, 0, 30)
    A.rot('hand.L', f, 30, 0, -10)
    A.rot('hand.R', f, 28, 0, 10)


def prone_idle(rig, A):
    K.gun_visible(rig, True)
    for s in 'LR':
        A.ik('leg.' + s, 1, 0)
    for f, b in ((1, 0), (31, 1), (61, 0)):
        A.loc('hips', f, 0, 0.0, -0.82)
        A.rot('hips', f, 90, 0, 0)
        A.rot('spine', f, -4, 0, 0)
        A.rot('chest', f, -10 - b, 0, 0)
        A.rot('neck', f, -35, 0, 0)
        A.rot('head', f, -30, 0, 0)
        _prone_arms(A, f)
        A.rot('thigh.L', f, 0, -8, 0)
        A.rot('thigh.R', f, 0, 8, 0)
        A.rot('shin.L', f, 4, 0, 0)
        A.rot('shin.R', f, 4, 0, 0)
        A.rot('foot.L', f, 60, 0, 0)
        A.rot('foot.R', f, 60, 0, 0)
    return (1, 61)


def crawl(rig, A):
    K.gun_visible(rig, True)
    for s in 'LR':
        A.ik('leg.' + s, 1, 0)
    N = 40
    for t in range(0, N + 1, 4):
        ph = 2 * math.pi * t / N
        s = math.sin(ph)
        A.loc('hips', t + 1, 0.03 * s, 0.0, -0.82)
        A.rot('hips', t + 1, 90, 0, 6 * s)
        A.rot('spine', t + 1, -4, 0, -5 * s)
        A.rot('chest', t + 1, -10, 0, -5 * s)
        A.rot('neck', t + 1, -35, 0, 0)
        A.rot('head', t + 1, -30, 0, 3 * s)
        A.rot('upper_arm.L', t + 1, -150 + 25 * s, -25, 0)
        A.rot('upper_arm.R', t + 1, -150 - 25 * s, 25, 0)
        A.rot('forearm.L', t + 1, -70 - 15 * s, 0, 0)
        A.rot('forearm.R', t + 1, -60 + 15 * s, 0, 0)
        A.rot('thigh.L', t + 1, -35 * max(0.0, -s), -15, 0)
        A.rot('thigh.R', t + 1, -35 * max(0.0, s), 15, 0)
        A.rot('shin.L', t + 1, 4 + 60 * max(0.0, -s), 0, 0)
        A.rot('shin.R', t + 1, 4 + 60 * max(0.0, s), 0, 0)
        A.rot('foot.L', t + 1, 60, 0, 0)
        A.rot('foot.R', t + 1, 60, 0, 0)
    return (1, N + 1)


def slide(rig, A):
    """Baseball slide: drop, lean back, one leg out, recover to crouch. The
    controller supplies the travel; the clip stays near the origin."""
    K.gun_visible(rig, False)
    for s in 'LR':
        A.ik('leg.' + s, 1, 0)
    keys = [(1, 0.0, -0.05, 8), (5, 0.0, -0.45, -10), (9, 0.0, -0.66, -28), (24, 0.0, -0.66, -30),
            (30, 0.0, -0.50, 0), (36, 0.0, -0.40, 14)]
    for f, y, z, p in keys:
        A.loc('hips', f, 0, y, z)
        A.rot('hips', f, p, 0, 0)
        A.rot('spine', f, 0.4 * p + 4, 0, 0)
        A.rot('chest', f, 0.3 * p + 4, 0, 0)
        A.rot('head', f, -0.6 * p, 0, 0)
    for f, lead, bend, arm in ((1, 0, 0, 0), (5, -40, 30, -30), (9, -75, 10, -60), (24, -78, 8, -62),
                               (30, -40, 90, -20), (36, -10, 110, 0)):
        A.rot('thigh.L', f, lead, 0, 0)
        A.rot('shin.L', f, bend, 0, 0)
        A.rot('thigh.R', f, lead * 0.4 - 20 if f > 1 else 0, 0, 0)
        A.rot('shin.R', f, 110 if f > 1 else 0, 0, 0)
        A.rot('upper_arm.L', f, arm, -30 if f > 1 else -8, 0)
        A.rot('upper_arm.R', f, arm * 0.3 + 20 if f > 1 else 0, 50 if f > 1 else 8, 0)
        A.rot('forearm.L', f, -30, 0, 0)
        A.rot('forearm.R', f, -20, 0, 0)
    return (1, 36)


def jump(rig, A):
    K.gun_visible(rig, False)
    for s in 'LR':
        A.ik('leg.' + s, 1, 0)
    for f, z, p, tuck, arm in ((1, -0.04, 4, 0, 0), (5, -0.22, 18, 40, 30), (9, 0.05, -4, 0, -120),
                               (14, 0.08, 0, 30, -140), (20, 0.06, 6, 20, -80)):
        A.loc('hips', f, 0, 0, z)
        A.rot('hips', f, p, 0, 0)
        A.rot('spine', f, p * 0.5, 0, 0)
        for s in 'LR':
            A.rot('thigh.' + s, f, -tuck, 0, 0)
            A.rot('shin.' + s, f, tuck * 1.6, 0, 0)
            A.rot('foot.' + s, f, tuck * 0.5, 0, 0)
        A.rot('upper_arm.L', f, arm, -14, 0)
        A.rot('upper_arm.R', f, arm, 14, 0)
        A.rot('forearm.L', f, -20, 0, 0)
        A.rot('forearm.R', f, -20, 0, 0)
    return (1, 20)


def fall(rig, A):
    K.gun_visible(rig, False)
    for s in 'LR':
        A.ik('leg.' + s, 1, 0)
    for f, w in ((1, 0), (11, 1), (21, 0)):
        A.loc('hips', f, 0, 0, 0.02)
        A.rot('hips', f, 4, 0, 0)
        A.rot('thigh.L', f, -30 - 6 * w, 0, 0)
        A.rot('shin.L', f, 45 + 6 * w, 0, 0)
        A.rot('thigh.R', f, -10 + 6 * w, 0, 0)
        A.rot('shin.R', f, 25, 0, 0)
        A.rot('upper_arm.L', f, -70 - 15 * w, -45, 0)
        A.rot('upper_arm.R', f, -70 + 15 * w, 45, 0)
        A.rot('forearm.L', f, -25, 0, 0)
        A.rot('forearm.R', f, -25, 0, 0)
    return (1, 21)


def punch(rig, A):
    """Right straight from a guard. Upper body clip (legs hold a stance)."""
    K.gun_visible(rig, False)
    for s in 'LR':
        A.ik('arm.' + s, 1, 1)
    for f, ext, twist in ((1, 0, 0), (5, -0.08, -8), (8, 1, 28), (11, 1, 30), (18, 0, 0)):
        A.loc('hips', f, 0, 0, -0.06)
        A.rot('hips', f, 4, 0, twist * 0.3)
        A.rot('spine', f, 6, 0, twist * 0.4)
        A.rot('chest', f, 4, 0, twist * 0.5)
        A.pos('hand_ik.L', f, 0.10, -0.24, 1.42)
        A.rot('hand_ik.L', f, -80, 0, -30)
        A.pos('hand_ik.R', f, -0.12 + 0.10 * ext, -0.22 - 0.38 * ext, 1.42 + 0.02 * ext)
        A.rot('hand_ik.R', f, -80 - 10 * ext, 0, 20)
        K.stance_feet(A, f)
    return (1, 18)


def kick(rig, A):
    """Front push kick (door kick)."""
    K.gun_visible(rig, False)
    A.ik('leg.R', 1, 0)
    for f, chamber, ext, lean in ((1, 0, 0, 0), (6, 1, 0, -6), (10, 0.6, 1, -14), (14, 0.6, 1, -14), (22, 0, 0, 0)):
        A.loc('hips', f, 0, 0.04 * ext, -0.04)
        A.rot('hips', f, lean, 0, 0)
        A.rot('spine', f, lean * 0.5, 0, 0)
        A.rot('thigh.R', f, -95 * chamber - 10 * ext, 0, 0)
        A.rot('shin.R', f, 110 * chamber * (1 - ext) + 5, 0, 0)
        A.rot('foot.R', f, -20 * ext, 0, 0)
        A.rot('upper_arm.L', f, -30 - 20 * chamber, -20, 0)
        A.rot('upper_arm.R', f, 20 * chamber, 30, 0)
        A.rot('forearm.L', f, -80, 0, 0)
        A.rot('forearm.R', f, -60, 0, 0)
        A.pos('foot_ik.L', f, 0.12, 0.05, 0.10)
        A.rot('foot_ik.L', f, 0, 0, 6)
    return (1, 22)


def cover_idle(rig, A):
    K.gun_visible(rig, True)
    for s in 'LR':
        A.ik('arm.' + s, 1, 1)
    for f, b in ((1, 0), (31, 1), (61, 0)):
        K.cover_feet(A, f)
        K.cover(rig, A, f, breathe=b)
    return (1, 61)


def aim_hold(rig, A):
    """Upper-body aim loop, layered over any lower-body move in Godot."""
    K.gun_visible(rig, True)
    for s in 'LR':
        A.ik('arm.' + s, 1, 1)
    for f, b in ((1, 0.0), (21, 1.0), (41, 0.0)):
        K.aim_pose(A, f, breathe=b)
        K.stance_feet(A, f)
    return (1, 41)


def ready_hold(rig, A):
    """Upper-body low ready loop."""
    K.gun_visible(rig, True)
    for s in 'LR':
        A.ik('arm.' + s, 1, 1)
    for f, b in ((1, 0.0), (31, 1.0), (61, 0.0)):
        K.low_ready(A, f, breathe=b)
        K.stance_feet(A, f)
    return (1, 61)


def climb(rig, A):
    """Pull up onto a 2 m ledge: hang reach, pull, knee up, stand. The
    controller moves the body; travel here is up and forward on the root."""
    K.gun_visible(rig, False)
    for s in 'LR':
        A.ik('leg.' + s, 1, 0)
    for s in 'LR':
        A.ik('arm.' + s, 1, 1)
    hp = [(1, 0.0, 0.0, 0), (6, -0.05, 0.25, 10), (12, -0.15, 0.85, 15), (18, -0.35, 1.45, 35),
          (24, -0.55, 1.85, 30), (30, -0.65, 2.0, 5), (36, -0.65, 2.0, 0)]
    for f, y, z, p in hp:
        A.loc('hips', f, 0, y, z)
        A.rot('hips', f, p, 0, 0)
        A.rot('spine', f, p * 0.5, 0, 0)
    for s, x in (('L', 0.2), ('R', -0.2)):
        A.pos('hand_ik.' + s, 1, x, -0.4, 2.05)
        A.rot('hand_ik.' + s, 1, -170, 0, 0)
        A.pos('hand_ik.' + s, 18, x, -0.45, 2.02)
        A.pos('hand_ik.' + s, 26, x * 0.8, -0.5, 2.02)
        A.ik('arm.' + s, 30, 1)
        A.ik('arm.' + s, 36, 0)
        A.rot('thigh.' + s, 1, -10, 0, 0)
        A.rot('thigh.' + s, 18, -60 if s == 'R' else -20, 0, 0)
        A.rot('shin.' + s, 18, 90 if s == 'R' else 40, 0, 0)
        A.rot('thigh.' + s, 36, 0, 0, 0)
        A.rot('shin.' + s, 36, 0, 0, 0)
    return (1, 36)


EXTRA = {
    'idle': idle, 'walk': walk, 'crouch_idle': crouch_idle, 'crouch_walk': crouch_walk,
    'prone_idle': prone_idle, 'crawl': crawl, 'slide': slide, 'jump': jump, 'fall': fall,
    'punch': punch, 'kick': kick, 'cover_idle': cover_idle, 'aim_hold': aim_hold,
    'ready_hold': ready_hold, 'climb': climb,
}
