"""Phase 0.1 pipeline check: one city prop built by script, exported to glTF,
and shown in Godot with collision. A street dumpster: body, lid, wheels, and a
convex collider. Output: assets/models/props/dumpster.glb"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import common as c

c.reset()
green = c.material("prop_green", (0.12, 0.38, 0.2))
dark = c.material("prop_dark", (0.08, 0.08, 0.09))
metal = c.material("prop_metal", (0.55, 0.56, 0.58), 0.4)

parts = [
    c.box("body", (1.8, 1.1, 1.0), (0, 0, 0.65), green, bevel=0.03),
    c.box("lid", (1.86, 1.16, 0.08), (0, 0.02, 1.2), dark, bevel=0.02),
    c.box("rim", (1.84, 0.06, 0.12), (0, -0.58, 1.08), metal),
]
for x in (-0.75, 0.75):
    for y in (-0.42, 0.42):
        parts.append(c.box("wheel", (0.14, 0.06, 0.14), (x, y, 0.07), dark))
# Convex collider only, no visible mesh. Godot turns this into a shape on a StaticBody3D.
parts.append(c.box("dumpster-convcolonly", (1.86, 1.16, 1.26), (0, 0, 0.63)))
c.export_glb("assets/models/props/dumpster.glb")
