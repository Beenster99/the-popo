"""Car interiors, seen through the glass (beenster 2026-11-24: "make
interiors for the cars with people in them for when we shoot through the
windows"). Shared by build_vehicles.py and build_police_car.py.

Everything is named interior_* and sits in Godot axes (x right, y up,
z forward); the driver sits on the right (x = -0.40), UK style. Door cards
are parented to their door so they come off with it.
"""
import math

import bpy

SEAT = (0.16, 0.15, 0.15)
SEAT_HI = (0.30, 0.29, 0.28)
TRIM = (0.24, 0.24, 0.26)
DASH = (0.09, 0.09, 0.10)
CARPET = (0.07, 0.07, 0.08)
DIAL = (0.85, 0.86, 0.80)
SCREEN = (0.20, 0.42, 0.62)
CHROME = (0.65, 0.66, 0.68)
BELT = (0.05, 0.05, 0.06)


def seat(H, x, y, z, width=0.50, headrests=(0.0,), back_h=0.62):
    """A seat: cushion with side bolsters, a two-part back leaning back,
    and headrests on posts (x offsets from the seat centre)."""
    m = H.mat("seat", SEAT)
    hi = H.mat("seat_hi", SEAT_HI)
    out = [H.gbox("interior_seat", (width, 0.11, 0.50), (x, y, z), m, 0.03)]
    for s in (-1, 1):
        out.append(H.gbox("interior_bolster", (0.06, 0.07, 0.46), (x + s * (width / 2 - 0.03), y + 0.07, z), m, 0.02))
    out.append(H.gbox("interior_seatback", (width, back_h * 0.5, 0.11), (x, y + 0.06 + back_h * 0.25, z - 0.25), m, 0.03))
    out.append(H.gbox("interior_seatback", (width - 0.02, back_h * 0.5, 0.10), (x, y + 0.06 + back_h * 0.73, z - 0.30), m, 0.03))
    out.append(H.gbox("interior_seat_panel", (width - 0.14, back_h * 0.7, 0.01), (x, y + 0.06 + back_h * 0.5, z - 0.205), hi))
    top = y + 0.06 + back_h
    for hx in headrests:
        out.append(H.gbox("interior_headrest", (0.26, 0.17, 0.09), (x + hx, top + 0.13, z - 0.32), m, 0.03))
        for px in (-0.07, 0.07):
            out.append(H.gbox("interior_headrest_post", (0.012, 0.06, 0.012), (x + hx + px, top + 0.03, z - 0.32), H.mat("chrome", CHROME)))
    return out


def belt(H, x, y, z, side):
    """A seatbelt from the pillar over the shoulder down to the hip."""
    a = (x + side * 0.22, y + 0.66, z - 0.30)
    b = (x - side * 0.18, y + 0.10, z - 0.05)
    w = 0.025
    pts = [(a[0], a[1], a[2] + 0.02), (a[0] - side * w * 2, a[1] - w, a[2] + 0.02), (b[0] - side * w * 2, b[1] - w, b[2] + 0.02), (b[0], b[1], b[2] + 0.02)]
    return H.quad("interior_belt", pts if side < 0 else list(reversed(pts)), H.mat("belt", BELT), 0.006)


def steering(H, x, y, z, tilt=62):
    m = H.mat("dash", DASH)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.18, minor_radius=0.022, major_segments=24, minor_segments=8)
    wh = bpy.context.object
    wh.name = "interior_wheel"
    wh.location = H.g2b((x, y, z))
    wh.rotation_euler = (math.radians(tilt), 0, 0)
    wh.data.materials.append(m)
    out = [wh]
    # Hub and three spokes, in the wheel's own plane.
    hub = H.cyl("interior_wheel_hub", 0.055, 0.05, (0, 0, 0), "z", m, 14)
    hub.parent = wh
    hub.location = (0, 0, 0)
    hub.rotation_euler = (0, 0, 0)
    for ang in (0, 120, 240):
        a = math.radians(ang + 90)
        bpy.ops.mesh.primitive_cube_add(size=1.0)
        sp = bpy.context.object
        sp.name = "interior_wheel_spoke"
        sp.scale = (0.03, 0.15, 0.015)
        sp.parent = wh
        sp.location = (math.cos(a) * 0.09, math.sin(a) * 0.09, 0)
        sp.rotation_euler = (0, 0, a - math.pi / 2)
        sp.data.materials.append(m)
    # Column back into the dash.
    col = H.cyl("interior_column", 0.03, 0.34, (x, y - 0.08, z + 0.16), "z", m, 10)
    col.rotation_euler = (math.radians(90 - (90 - tilt)), 0, 0)
    out.append(col)
    return out


def fit_out(H, out, W, rows, seat_y, floor_y, dash, wheel, roof_y=None, screen_z=None, doors=None, shelf=None, console=True,
            bench_headrests=(-0.45, 0.0, 0.45), bench_back_h=0.56, roof_box=None):
    """rows: [(z, "pair"|"bench")], front row first.
    dash: (y, z, depth) of the dash's centre; wheel: (y, z) for the driver.
    roof_y / screen_z: where the mirror and visors hang. doors: {"l": obj, "r": obj}
    front doors to hang door cards on. shelf: (y, z) of a parcel shelf."""
    trim = H.mat("trim", TRIM)
    dm = H.mat("dash", DASH)
    inner = W / 2 - 0.08
    # Seats and belts.
    for i, (z, kind) in enumerate(rows):
        if kind == "pair":
            for x in (-0.40, 0.40):
                out += seat(H, x, seat_y, z)
                out.append(belt(H, x, seat_y, z, -1 if x < 0 else 1))
        else:
            bw = min(1.40, W - 0.30)
            out += seat(H, 0.0, seat_y, z, bw, headrests=bench_headrests, back_h=bench_back_h)
    # Floor.
    zs = [r[0] for r in rows]
    z0, z1 = min(zs) - 0.40, dash[1] + 0.05
    out.append(H.gbox("interior_floor", (W - 0.22, 0.03, z1 - z0), (0, floor_y, (z0 + z1) / 2), H.mat("carpet", CARPET)))
    # Dash: main moulding, a top pad, the binnacle over the dials, the
    # centre stack with a screen and vents.
    dy, dz, dd = dash
    out.append(H.gbox("interior_dash", (W - 0.22, 0.22, dd), (0, dy, dz), dm, 0.04))
    out.append(H.gbox("interior_dash_top", (W - 0.30, 0.04, dd * 0.8), (0, dy + 0.12, dz + 0.02), trim, 0.02))
    out.append(H.gbox("interior_binnacle", (0.40, 0.09, 0.16), (-0.40, dy + 0.15, dz - dd / 2 + 0.06), dm, 0.03))
    for dx in (-0.09, 0.09):
        d = H.cyl("interior_dial", 0.055, 0.01, (-0.40 + dx, dy + 0.10, dz - dd / 2 - 0.005), "z", H.mat("dial", DIAL), 16)
        out.append(d)
    out.append(H.gbox("interior_stack", (0.30, 0.30, 0.10), (0, dy - 0.10, dz - dd / 2 - 0.02), trim, 0.02))
    out.append(H.gbox("interior_screen", (0.22, 0.13, 0.012), (0, dy - 0.03, dz - dd / 2 - 0.075), H.mat("screen", SCREEN)))
    for vx in (-0.62, -0.08, 0.08, 0.62):
        if abs(vx) < inner:
            out.append(H.gbox("interior_vent", (0.12, 0.05, 0.012), (vx, dy + 0.04, dz - dd / 2 - 0.006), H.mat("black", (0.03, 0.03, 0.035))))
    out.append(H.gbox("interior_glovebox", (0.42, 0.12, 0.012), (0.40, dy - 0.03, dz - dd / 2 - 0.006), trim))
    out += steering(H, -0.40, wheel[0], wheel[1])
    # Centre console with the gear lever and handbrake.
    if console and rows and rows[0][1] == "pair":
        fz = rows[0][0]
        out.append(H.gbox("interior_console", (0.20, 0.20, 0.75), (0, seat_y - 0.02, fz + 0.12), trim, 0.03))
        out.append(H.gbox("interior_gear", (0.02, 0.12, 0.02), (0, seat_y + 0.12, fz + 0.30), H.mat("chrome", CHROME)))
        out.append(H.gbox("interior_gear_knob", (0.045, 0.045, 0.045), (0, seat_y + 0.19, fz + 0.30), dm, 0.015))
        out.append(H.gbox("interior_handbrake", (0.04, 0.05, 0.22), (0, seat_y + 0.10, fz - 0.02), dm, 0.015))
    # Mirror and sun visors under the roof at the top of the windscreen.
    if roof_y is not None and screen_z is not None:
        out.append(H.gbox("interior_mirror", (0.22, 0.06, 0.025), (0, roof_y - 0.12, screen_z - 0.10), dm, 0.01))
        out.append(H.gbox("interior_mirror_stem", (0.02, 0.07, 0.02), (0, roof_y - 0.06, screen_z - 0.10), dm))
        for vx in (-0.40, 0.40):
            out.append(H.gbox("interior_visor", (0.40, 0.025, 0.16), (vx, roof_y - 0.05, screen_z - 0.16), trim, 0.01))
        if roof_box:
            # (rear z, half width) of the roof: the headliner stays under it
            # instead of poking out over the rear window.
            back, hw = roof_box
            out.append(H.gbox("interior_headliner", (hw * 2 - 0.08, 0.02, screen_z - back - 0.06), (0, roof_y - 0.02, (screen_z + back) / 2), H.mat("seat_hi", SEAT_HI)))
        else:
            out.append(H.gbox("interior_headliner", (W - 0.36, 0.02, max(0.2, screen_z - min(zs) + 0.2)), (0, roof_y - 0.02, (screen_z + min(zs) - 0.4) / 2), H.mat("seat_hi", SEAT_HI)))
    # Door cards (inner door panels) with an armrest and a pull handle.
    for sn, d in (doors or {}).items():
        if d is None:
            continue
        s = 1 if sn == "r" else -1
        x = s * (W / 2 - 0.05)
        fz = rows[0][0]
        card = H.gbox("interior_doorcard", (0.03, 0.40, 0.78), (x, seat_y + 0.22, fz + 0.12), trim, 0.01)
        arm = H.gbox("interior_armrest", (0.07, 0.04, 0.34), (x - s * 0.04, seat_y + 0.26, fz + 0.05), dm, 0.01)
        H.attach(card, d)
        H.attach(arm, d)
    if shelf is not None:
        out.append(H.gbox("interior_shelf", (W - 0.30, 0.025, 0.45), (0, shelf[0], shelf[1]), H.mat("carpet", CARPET)))
    return out
