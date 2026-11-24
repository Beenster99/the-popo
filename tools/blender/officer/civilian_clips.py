"""Upper-body clips for people going about their day (not police, not
crooks): no gun anywhere near their hands. Same rig and conventions as
extra_clips.py (character faces -Y, left = +X, Z up; hands by IK target).

Built into assets/models/characters/civilian_clips.glb by
    OFFICER_CLIPS=civilian python tools/blender/build_officer.py
and merged into the officer's clip library by OfficerClips in Godot. Each is
a loop layered over idle or walk by the upper-body split.
"""
import math
import clips as K


def _arms_ik(A):
    for s in 'LR':
        A.ik('arm.' + s, 1, 1)


def _arm_relaxed(A, f, s, swing=0.0):
    sg = 1 if s == 'L' else -1
    A.rot('upper_arm.' + s, f, sg * swing - 4, sg * -8, 0)
    A.rot('forearm.' + s, f, -18, 0, 0)


def phone_call(rig, A):
    """On the phone: right hand to the ear, left hand loose, head tilted in."""
    K.gun_visible(rig, False)
    A.ik('arm.R', 1, 1)
    A.ik('arm.L', 1, 0)
    for f, b in ((1, 0.0), (41, 1.0), (81, 0.0)):
        A.rot('spine', f, 1, 0, 0)
        A.rot('chest', f, 1 + b, 0, -3 * b)
        A.rot('neck', f, 2, 0, 0)
        A.rot('head', f, 3 + 2 * b, -8, 6 * b - 3)
        A.pos('hand_ik.R', f, -0.13, -0.05, 1.58 + 0.01 * b)
        A.rot('hand_ik.R', f, -160, 0, -70)
        _arm_relaxed(A, f, 'L', 2 * b)
    return (1, 81)


def texting(rig, A):
    """Head down over a phone held at chest height in both hands."""
    K.gun_visible(rig, False)
    _arms_ik(A)
    for f, b in ((1, 0.0), (21, 1.0), (41, 0.0), (61, 1.0), (81, 0.0)):
        A.rot('spine', f, 1, 0, 0)
        A.rot('chest', f, 1, 0, 0)
        A.rot('neck', f, 8, 0, 0)
        A.rot('head', f, 9, 0, 2 * b)
        A.pos('hand_ik.R', f, -0.05, -0.30, 1.15 + 0.005 * b)
        A.rot('hand_ik.R', f, -100, 0, 25)
        A.pos('hand_ik.L', f, 0.06, -0.29, 1.14)
        A.rot('hand_ik.L', f, -100, 0, -25)
    return (1, 81)


def pockets(rig, A):
    """Hands in the front trouser pockets, shoulders easy."""
    K.gun_visible(rig, False)
    _arms_ik(A)
    for f, b in ((1, 0.0), (41, 1.0), (81, 0.0)):
        A.rot('spine', f, -1, 0, 0)
        A.rot('chest', f, -2 + b, 0, 0)
        A.rot('head', f, 1, 0, 4 * b - 2)
        A.pos('hand_ik.L', f, 0.17, -0.07, 0.92)
        A.rot('hand_ik.L', f, 175, 0, 20)
        A.pos('hand_ik.R', f, -0.17, -0.07, 0.92)
        A.rot('hand_ik.R', f, 175, 0, -20)
    return (1, 81)


def arms_folded(rig, A):
    """Arms folded across the chest, weight back."""
    K.gun_visible(rig, False)
    _arms_ik(A)
    for f, b in ((1, 0.0), (41, 1.0), (81, 0.0)):
        A.rot('spine', f, -2, 0, 0)
        A.rot('chest', f, -2 + b, 0, 0)
        A.rot('head', f, -1, 0, 5 * b - 2)
        A.pos('hand_ik.L', f, -0.12, -0.17, 1.27)
        A.rot('hand_ik.L', f, -90, 0, 80)
        A.pos('hand_ik.R', f, 0.12, -0.15, 1.24)
        A.rot('hand_ik.R', f, -90, 0, -80)
    return (1, 81)


def hands_behind(rig, A):
    """Hands clasped loosely behind the back, an unhurried stroll."""
    K.gun_visible(rig, False)
    _arms_ik(A)
    for f, b in ((1, 0.0), (41, 1.0), (81, 0.0)):
        A.rot('spine', f, 3, 0, 0)
        A.rot('chest', f, -1, 0, 0)
        A.rot('head', f, 2, 0, 6 * b - 3)
        A.pos('hand_ik.L', f, 0.06, 0.16, 1.00)
        A.rot('hand_ik.L', f, 180, 0, 25)
        A.pos('hand_ik.R', f, -0.06, 0.16, 1.01)
        A.rot('hand_ik.R', f, 180, 0, -25)
    return (1, 81)


def work_dig(rig, A):
    """Shovelling: both hands on a shovel (Godot puts the shovel in the right
    hand), push in, lever, lift, throw to the side. 1.6 s a scoop."""
    K.gun_visible(rig, False)
    _arms_ik(A)
    keys = [  # frame, chest pitch, chest yaw, right hand (top grip), blade (on the ground)
        (1, 22, 0, (-0.10, -0.22, 1.02), (-0.02, -0.80, 0.12)),
        (13, 32, 0, (-0.10, -0.30, 0.95), (-0.02, -0.95, 0.02)),
        (25, 26, 0, (-0.12, -0.12, 0.88), (-0.02, -0.95, 0.15)),
        (37, 14, -12, (-0.16, -0.10, 1.05), (-0.10, -0.85, 0.45)),
        (43, 10, -28, (-0.25, -0.05, 1.10), (-0.55, -0.70, 0.55)),
        (49, 22, 0, (-0.10, -0.22, 1.02), (-0.02, -0.80, 0.12)),
    ]
    for f, cp, cy, r, blade in keys:
        # The left hand slides along the shaft, 42% of the way to the blade.
        l = tuple(r[i] + 0.42 * (blade[i] - r[i]) for i in range(3))
        A.rot('spine', f, cp * 0.5, 0, cy * 0.4)
        A.rot('chest', f, cp * 0.5, 0, cy * 0.6)
        A.rot('head', f, -cp * 0.3, 0, 0)
        A.pos('hand_ik.R', f, *r)
        A.rot('hand_ik.R', f, -90, 0, 30)
        A.pos('hand_ik.L', f, *l)
        A.rot('hand_ik.L', f, -90, 0, -30)
    return (1, 49)


def work_hammer(rig, A):
    """Bent over hammering at waist height (Godot puts the hammer in the
    right hand); left hand steadies the work. 0.8 s a blow."""
    K.gun_visible(rig, False)
    _arms_ik(A)
    keys = [(1, (-0.18, -0.42, 1.10), -60), (9, (-0.18, -0.38, 1.32), -10), (13, (-0.17, -0.44, 1.22), -40),
            (17, (-0.18, -0.46, 0.98), -85), (19, (-0.18, -0.45, 0.97), -90), (25, (-0.18, -0.42, 1.10), -60)]
    for f, r, wr in keys:
        A.rot('spine', f, 14, 0, 0)
        A.rot('chest', f, 14, 0, 0)
        A.rot('neck', f, 6, 0, 0)
        A.rot('head', f, 10, 0, 0)
        A.pos('hand_ik.R', f, *r)
        A.rot('hand_ik.R', f, wr, 0, 20)
        A.pos('hand_ik.L', f, 0.08, -0.46, 0.98)
        A.rot('hand_ik.L', f, -100, 0, -30)
    return (1, 25)


CIVILIAN = {
    'civ_phone': phone_call, 'civ_texting': texting, 'civ_pockets': pockets,
    'civ_arms_folded': arms_folded, 'civ_hands_behind': hands_behind,
    'work_dig': work_dig, 'work_hammer': work_hammer,
}
