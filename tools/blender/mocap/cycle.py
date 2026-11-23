"""Finds the cleanest gait cycle in a sampled 100STYLE take and makes it a
straight, in-place loop.

Input: the .npz from sample_bvh.py (world matrices of every bone, every frame,
Blender Z up, metres). The actor walks round a small capture volume, so the
take is mostly curves: every frame is turned so the body faces -Y (the
officer's forward) along a smoothed heading, and the smoothed travel is
taken off, leaving the body walking on the spot. The best cycle is picked by
least turning, steadiest speed and the smallest seam between its ends.
"""
import math
import numpy as np


def _smooth(x, sigma):
    r = int(sigma * 3)
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    pad = np.pad(x, [(r, r)] + [(0, 0)] * (x.ndim - 1), mode="edge")
    if x.ndim == 1:
        return np.convolve(pad, k, mode="valid")
    return np.stack([np.convolve(pad[:, i], k, mode="valid") for i in range(x.shape[1])], 1)


def _rotz(a):
    c, s = math.cos(a), math.sin(a)
    m = np.eye(4)
    m[0, 0], m[0, 1], m[1, 0], m[1, 1] = c, -s, s, c
    return m


def straighten(d, fps):
    names = list(d["names"])
    F = d["frames"]                       # (n, bones, 4, 4)
    ix = names.index
    hips = F[:, ix("Hips"), :3, 3]
    lr = F[:, ix("LeftHip"), :3, 3] - F[:, ix("RightHip"), :3, 3]
    # Facing = (left - right) x up, as a heading angle, unwrapped then smoothed.
    face = np.stack([lr[:, 1], -lr[:, 0]], 1)
    yaw = np.unwrap(np.arctan2(face[:, 1], face[:, 0]))
    yaw_s = _smooth(yaw, fps * 0.25)
    path = _smooth(hips[:, :2], fps * 0.45)
    out = np.empty_like(F)
    vel = np.gradient(path, axis=0) * fps
    local_v = np.empty((len(F), 2))
    for t in range(len(F)):
        phi = -math.pi / 2 - yaw_s[t]      # facing -> -Y
        R = _rotz(phi)
        T = np.eye(4)
        T[:2, 3] = -path[t]
        out[t] = R @ T @ F[t]
        local_v[t] = R[:2, :2] @ vel[t]
    turn = np.abs(np.gradient(yaw_s)) * fps   # rad/s
    return out, local_v, turn


def pick_cycle(d, fps, want="forward", min_s=0.8, max_s=1.6):
    names = list(d["names"])
    S, v, turn = straighten(d, fps)
    ix = names.index
    # Gait phase from the left ankle's swing relative to the hips (along the
    # direction of travel): peaks are where the left foot is furthest ahead.
    ax = 1 if want in ("forward", "back") else 0
    sign = {"forward": -1.0, "back": 1.0, "left": 1.0, "right": -1.0}[want]
    rel = (S[:, ix("LeftAnkle"), ax, 3] - S[:, ix("Hips"), ax, 3]) * sign
    rel = _smooth(rel, 2.0)
    peaks = [t for t in range(2, len(rel) - 2) if rel[t] == rel[t - 2:t + 3].max() and rel[t] > 0.05]
    speed_dir = v[:, ax] * sign
    best = None
    for a, b in zip(peaks, peaks[1:]):
        dur = (b - a) / fps
        if not (min_s <= dur <= max_s):
            continue
        sp = speed_dir[a:b]
        if sp.mean() < 0.4:
            continue
        # Moving the right way and not crabbing sideways.
        side = np.abs(v[a:b, 1 - ax]).mean()
        seam = 0.0
        for bi in range(len(names)):
            ra, rb = S[a, bi, :3, :3], S[b, bi, :3, :3]
            c = np.clip((np.trace(ra.T @ rb) - 1) / 2, -1, 1)
            seam += math.acos(c)
        seam += abs(S[a, 0, 2, 3] - S[b, 0, 2, 3]) * 10
        cost = turn[a:b].mean() * 3.0 + sp.std() * 2.0 + side * 2.0 + seam * 0.5
        if best is None or cost < best[0]:
            best = (cost, a, b, float(sp.mean()), float(turn[a:b].mean()), seam)
    return S, best
