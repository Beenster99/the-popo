class_name PropWorld
extends Node
## Phase 1.5: loose things in the fight, from the same seed on every
## machine: chairs, tables and shelves indoors, bins, crates, benches,
## bottles, red barrels and gas bottles outside, and a fire extinguisher by
## each enterable building's door.
##
## The host simulates them and sends where the moving ones are; clients
## hold theirs still and follow. Shooting, kicking, blasts, fire and a hard
## knock break them: wood splinters, glass shatters, a barrel or a gas
## bottle blows up and starts a fire, and an extinguisher bursts into a
## cloud that puts out fires round it. The light ones can be thrown (by
## enemies, for now).

const MSG_SNAP := 90     # host -> all: where the moving props are
const MSG_BREAK := 91    # host -> all: a prop broke (id, where, which way)
const SNAP_EVERY := 0.05
const SLEEP_REFRESH := 1.5     # s: every prop is resent at least this often
const MAX_PER_SNAP := 80
const POS_SCALE := 64.0
const BULLET_DAMAGE := 14.0
const KNOCK_DV := 5.0          # m/s change of speed before a knock hurts
const LAYER := 16

## kind: {size (collision box, or [radius, height] for a cylinder), mass,
## hp, surface, throw, flammable, explosive, puffs (extinguisher), parts}
## parts: [size, offset, colour] boxes; size.x < 0 marks a cylinder
## (radius -size.x, height size.y).
const KINDS := {
	"chair": {"size": Vector3(0.46, 0.92, 0.46), "mass": 6.0, "hp": 25.0, "surface": "wood", "throw": true, "flammable": true,
		"parts": [[Vector3(0.46, 0.05, 0.46), Vector3(0, -0.02, 0), "8a5a34"],
			[Vector3(0.04, 0.44, 0.04), Vector3(-0.19, -0.25, -0.19), "6e4528"], [Vector3(0.04, 0.44, 0.04), Vector3(0.19, -0.25, -0.19), "6e4528"],
			[Vector3(0.04, 0.44, 0.04), Vector3(-0.19, -0.25, 0.19), "6e4528"], [Vector3(0.04, 0.44, 0.04), Vector3(0.19, -0.25, 0.19), "6e4528"],
			[Vector3(0.46, 0.42, 0.04), Vector3(0, 0.24, -0.21), "8a5a34"]]},
	"table": {"size": Vector3(1.2, 0.76, 0.8), "mass": 20.0, "hp": 60.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.2, 0.06, 0.8), Vector3(0, 0.35, 0), "9b6a3c"],
			[Vector3(0.06, 0.7, 0.06), Vector3(-0.54, -0.03, -0.34), "6e4528"], [Vector3(0.06, 0.7, 0.06), Vector3(0.54, -0.03, -0.34), "6e4528"],
			[Vector3(0.06, 0.7, 0.06), Vector3(-0.54, -0.03, 0.34), "6e4528"], [Vector3(0.06, 0.7, 0.06), Vector3(0.54, -0.03, 0.34), "6e4528"]]},
	"shelf": {"size": Vector3(1.2, 1.8, 0.4), "mass": 30.0, "hp": 70.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(0.04, 1.8, 0.4), Vector3(-0.58, 0, 0), "7b5232"], [Vector3(0.04, 1.8, 0.4), Vector3(0.58, 0, 0), "7b5232"],
			[Vector3(1.2, 1.8, 0.02), Vector3(0, 0, -0.19), "5f3f26"],
			[Vector3(1.16, 0.04, 0.38), Vector3(0, -0.85, 0), "8a5a34"], [Vector3(1.16, 0.04, 0.38), Vector3(0, -0.3, 0), "8a5a34"],
			[Vector3(1.16, 0.04, 0.38), Vector3(0, 0.25, 0), "8a5a34"], [Vector3(1.16, 0.04, 0.38), Vector3(0, 0.88, 0), "8a5a34"],
			[Vector3(0.3, 0.26, 0.26), Vector3(-0.3, -0.15, 0.02), "c9b48a"], [Vector3(0.22, 0.2, 0.22), Vector3(0.25, 0.37, 0.02), "a33b2e"]]},
	"crate": {"size": Vector3(0.6, 0.6, 0.6), "mass": 9.0, "hp": 30.0, "surface": "wood", "throw": true, "flammable": true,
		"parts": [[Vector3(0.6, 0.6, 0.6), Vector3.ZERO, "a87a46"], [Vector3(0.62, 0.08, 0.62), Vector3(0, 0.2, 0), "7d5630"],
			[Vector3(0.62, 0.08, 0.62), Vector3(0, -0.2, 0), "7d5630"]]},
	"bench": {"size": Vector3(1.6, 0.5, 0.45), "mass": 24.0, "hp": 55.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.6, 0.06, 0.45), Vector3(0, 0.2, 0), "8a5a34"], [Vector3(0.08, 0.44, 0.4), Vector3(-0.7, -0.03, 0), "3a3d42"],
			[Vector3(0.08, 0.44, 0.4), Vector3(0.7, -0.03, 0), "3a3d42"]]},
	"bin": {"size": Vector3(0.5, 0.85, 0.5), "mass": 7.0, "hp": 90.0, "surface": "metal", "throw": true, "flammable": false,
		"parts": [[Vector3(0.5, 0.78, 0.5), Vector3(0, -0.035, 0), "2f5d3a"], [Vector3(0.54, 0.07, 0.54), Vector3(0, 0.39, 0), "264a2f"]]},
	"bottle": {"size": Vector3(0.08, 0.28, 0.08), "mass": 0.6, "hp": 1.0, "surface": "glass", "throw": true, "flammable": false,
		"parts": [[Vector3(0.08, 0.2, 0.08), Vector3(0, -0.04, 0), "3c7a45"], [Vector3(0.035, 0.08, 0.035), Vector3(0, 0.1, 0), "3c7a45"]]},
	"barrel": {"size": Vector3(-0.3, 0.9, 0), "mass": 35.0, "hp": 35.0, "surface": "metal", "throw": false, "explosive": true,
		"parts": [[Vector3(-0.3, 0.9, 0), Vector3.ZERO, "b3261e"], [Vector3(-0.31, 0.05, 0), Vector3(0, 0.22, 0), "e0c23a"],
			[Vector3(-0.31, 0.05, 0), Vector3(0, -0.22, 0), "e0c23a"]]},
	"gas": {"size": Vector3(-0.15, 0.72, 0), "mass": 14.0, "hp": 20.0, "surface": "metal", "throw": true, "explosive": true,
		"parts": [[Vector3(-0.15, 0.62, 0), Vector3(0, -0.05, 0), "d86a1e"], [Vector3(-0.07, 0.1, 0), Vector3(0, 0.31, 0), "8a8d92"]]},
	# Wave 2 (Phase 2.2): furniture for flats, offices, shops, warehouses
	# and the station, and shipping containers on the docks.
	"bed": {"size": Vector3(1.4, 0.55, 2.0), "mass": 45.0, "hp": 80.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.4, 0.25, 2.0), Vector3(0, -0.15, 0), "5f3f26"], [Vector3(1.34, 0.18, 1.94), Vector3(0, 0.06, 0), "d9d4c8"],
			[Vector3(0.5, 0.12, 0.35), Vector3(-0.35, 0.2, -0.75), "eeeeee"], [Vector3(0.5, 0.12, 0.35), Vector3(0.35, 0.2, -0.75), "eeeeee"],
			[Vector3(1.4, 0.7, 0.08), Vector3(0, 0.1, -0.98), "5f3f26"]]},
	"sofa": {"size": Vector3(1.9, 0.8, 0.85), "mass": 40.0, "hp": 70.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.9, 0.4, 0.85), Vector3(0, -0.2, 0), "5a6b7d"], [Vector3(1.9, 0.45, 0.2), Vector3(0, 0.17, -0.32), "4c5b6b"],
			[Vector3(0.2, 0.3, 0.85), Vector3(-0.85, 0.05, 0), "4c5b6b"], [Vector3(0.2, 0.3, 0.85), Vector3(0.85, 0.05, 0), "4c5b6b"]]},
	"desk": {"size": Vector3(1.4, 0.75, 0.7), "mass": 28.0, "hp": 60.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.4, 0.05, 0.7), Vector3(0, 0.35, 0), "c9b48a"], [Vector3(0.05, 0.7, 0.66), Vector3(-0.66, -0.03, 0), "6b6f72"],
			[Vector3(0.05, 0.7, 0.66), Vector3(0.66, -0.03, 0), "6b6f72"], [Vector3(0.5, 0.32, 0.04), Vector3(0.1, 0.55, -0.15), "202226"],
			[Vector3(0.45, 0.02, 0.15), Vector3(0.1, 0.39, 0.1), "303236"]]},
	"counter": {"size": Vector3(2.0, 1.0, 0.6), "mass": 60.0, "hp": 90.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(2.0, 0.95, 0.6), Vector3(0, -0.025, 0), "7b5232"], [Vector3(2.04, 0.05, 0.64), Vector3(0, 0.475, 0), "d8cba8"]]},
	"cabinet": {"size": Vector3(0.5, 1.3, 0.6), "mass": 35.0, "hp": 90.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(0.5, 1.3, 0.6), Vector3.ZERO, "8a8d92"], [Vector3(0.3, 0.03, 0.02), Vector3(0, 0.4, 0.31), "303236"],
			[Vector3(0.3, 0.03, 0.02), Vector3(0, 0.0, 0.31), "303236"], [Vector3(0.3, 0.03, 0.02), Vector3(0, -0.4, 0.31), "303236"]]},
	"pallet": {"size": Vector3(1.2, 0.15, 1.0), "mass": 18.0, "hp": 30.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.2, 0.03, 1.0), Vector3(0, 0.06, 0), "b08a5a"], [Vector3(1.2, 0.09, 0.12), Vector3(0, -0.02, -0.4), "8a6a44"],
			[Vector3(1.2, 0.09, 0.12), Vector3(0, -0.02, 0), "8a6a44"], [Vector3(1.2, 0.09, 0.12), Vector3(0, -0.02, 0.4), "8a6a44"]]},
	"container": {"size": Vector3(2.44, 2.6, 6.06), "mass": 3800.0, "hp": 3000.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(2.44, 2.6, 6.06), Vector3.ZERO, "b3402a"], [Vector3(2.48, 0.12, 6.1), Vector3(0, 1.25, 0), "8a2f20"],
			[Vector3(2.48, 0.12, 6.1), Vector3(0, -1.25, 0), "8a2f20"], [Vector3(2.3, 2.4, 0.06), Vector3(0, 0, 3.03), "7a2a1c"]]},
	# Wave 5 (Phase 5.1): more of the city. Street furniture...
	"post_box": {"size": Vector3(-0.28, 1.5, 0), "mass": 160.0, "hp": 400.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(-0.28, 1.36, 0), Vector3(0, -0.07, 0), "c41f1f"], [Vector3(-0.31, 0.14, 0), Vector3(0, 0.68, 0), "a51818"],
			[Vector3(0.3, 0.04, 0.06), Vector3(0, 0.35, 0.26), "1a1a1a"], [Vector3(-0.3, 0.06, 0), Vector3(0, -0.72, 0), "2a2a2a"]]},
	"phone_box": {"size": Vector3(1.0, 2.5, 1.0), "mass": 600.0, "hp": 500.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(1.0, 2.3, 1.0), Vector3(0, -0.1, 0), "c41f1f"], [Vector3(1.06, 0.2, 1.06), Vector3(0, 1.15, 0), "a51818"],
			[Vector3(0.7, 1.4, 0.02), Vector3(0, 0.15, 0.5), "b9d6e2"], [Vector3(0.02, 1.4, 0.7), Vector3(0.5, 0.15, 0), "b9d6e2"],
			[Vector3(0.02, 1.4, 0.7), Vector3(-0.5, 0.15, 0), "b9d6e2"], [Vector3(0.8, 0.12, 0.02), Vector3(0, 1.0, 0.51), "f2efe6"]]},
	"hydrant": {"size": Vector3(-0.16, 0.75, 0), "mass": 120.0, "hp": 500.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(-0.13, 0.6, 0), Vector3(0, -0.05, 0), "d9b52a"], [Vector3(-0.16, 0.1, 0), Vector3(0, 0.3, 0), "b8961f"],
			[Vector3(0.36, 0.09, 0.09), Vector3(0, 0.08, 0), "b8961f"]]},
	"cone": {"size": Vector3(-0.17, 0.7, 0), "mass": 2.0, "hp": 30.0, "surface": "wood", "throw": true, "flammable": false,
		"parts": [[Vector3(0.4, 0.04, 0.4), Vector3(0, -0.33, 0), "1f1f22"], [Vector3(-0.12, 0.5, 0), Vector3(0, -0.06, 0), "ff6a13"],
			[Vector3(-0.07, 0.12, 0), Vector3(0, 0.08, 0), "f2efe6"], [Vector3(-0.05, 0.12, 0), Vector3(0, 0.26, 0), "ff6a13"]]},
	"planter": {"size": Vector3(1.4, 0.7, 0.7), "mass": 400.0, "hp": 300.0, "surface": "concrete", "throw": false, "flammable": false,
		"parts": [[Vector3(1.4, 0.6, 0.7), Vector3(0, -0.05, 0), "9a968c"], [Vector3(1.3, 0.12, 0.6), Vector3(0, 0.28, 0), "3e2c1e"],
			[Vector3(0.5, 0.45, 0.5), Vector3(-0.35, 0.5, 0), "3f7a3a"], [Vector3(0.45, 0.38, 0.45), Vector3(0.35, 0.46, 0), "4e8a44"]]},
	"vending": {"size": Vector3(0.9, 1.85, 0.75), "mass": 260.0, "hp": 160.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(0.9, 1.85, 0.75), Vector3.ZERO, "b3261e"], [Vector3(0.55, 1.2, 0.02), Vector3(-0.1, 0.2, 0.38), "cfe6ee"],
			[Vector3(0.18, 0.5, 0.02), Vector3(0.3, 0.3, 0.38), "202226"], [Vector3(0.7, 0.12, 0.02), Vector3(0, -0.65, 0.38), "1a1a1a"]]},
	"wheelie_bin": {"size": Vector3(0.6, 1.07, 0.72), "mass": 14.0, "hp": 80.0, "surface": "metal", "throw": false, "flammable": true,
		"parts": [[Vector3(0.58, 0.98, 0.7), Vector3(0, -0.04, 0), "2d3a2e"], [Vector3(0.62, 0.06, 0.76), Vector3(0, 0.48, 0.02), "232d24"],
			[Vector3(-0.1, 0.06, 0), Vector3(-0.25, -0.48, -0.3), "151515"], [Vector3(-0.1, 0.06, 0), Vector3(0.25, -0.48, -0.3), "151515"]]},
	"bike_rack": {"size": Vector3(2.0, 0.8, 0.5), "mass": 40.0, "hp": 200.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(0.05, 0.8, 0.5), Vector3(-0.9, 0, 0), "8a8d92"], [Vector3(0.05, 0.8, 0.5), Vector3(-0.3, 0, 0), "8a8d92"],
			[Vector3(0.05, 0.8, 0.5), Vector3(0.3, 0, 0), "8a8d92"], [Vector3(0.05, 0.8, 0.5), Vector3(0.9, 0, 0), "8a8d92"],
			[Vector3(2.0, 0.05, 0.05), Vector3(0, -0.38, 0), "6b6f72"]]},
	"trolley": {"size": Vector3(0.6, 1.0, 0.95), "mass": 16.0, "hp": 120.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(0.56, 0.45, 0.85), Vector3(0, 0.1, 0), "b8bcc2"], [Vector3(0.6, 0.04, 0.04), Vector3(0, 0.45, -0.47), "c41f1f"],
			[Vector3(0.5, 0.04, 0.8), Vector3(0, -0.32, 0), "8a8d92"], [Vector3(-0.06, 0.06, 0), Vector3(0, -0.47, 0.35), "151515"],
			[Vector3(-0.06, 0.06, 0), Vector3(0, -0.47, -0.35), "151515"]]},
	"tyres": {"size": Vector3(-0.38, 0.9, 0), "mass": 45.0, "hp": 400.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(-0.38, 0.28, 0), Vector3(0, -0.31, 0), "1a1a1c"], [Vector3(-0.38, 0.28, 0), Vector3(0, -0.01, 0), "222224"],
			[Vector3(-0.38, 0.28, 0), Vector3(0, 0.29, 0), "1a1a1c"], [Vector3(-0.16, 0.92, 0), Vector3(0, 0, 0), "3a3a3c"]]},
	# ...and for the rooms.
	"tv": {"size": Vector3(0.9, 0.55, 0.12), "mass": 10.0, "hp": 6.0, "surface": "glass", "throw": true, "flammable": false,
		"parts": [[Vector3(0.9, 0.52, 0.08), Vector3(0, 0.015, 0), "141416"], [Vector3(0.84, 0.46, 0.01), Vector3(0, 0.015, 0.045), "2a3440"],
			[Vector3(0.3, 0.03, 0.12), Vector3(0, -0.26, 0), "141416"]]},
	"fridge": {"size": Vector3(0.6, 1.8, 0.65), "mass": 70.0, "hp": 150.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(0.6, 1.8, 0.65), Vector3.ZERO, "e8e6e0"], [Vector3(0.58, 0.01, 0.02), Vector3(0, 0.3, 0.33), "b9b7b0"],
			[Vector3(0.03, 0.4, 0.04), Vector3(0.24, 0.6, 0.35), "8a8d92"], [Vector3(0.03, 0.3, 0.04), Vector3(0.24, 0.0, 0.35), "8a8d92"]]},
	"washer": {"size": Vector3(0.6, 0.85, 0.6), "mass": 65.0, "hp": 140.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(0.6, 0.85, 0.6), Vector3.ZERO, "eeeeea"], [Vector3(-0.2, 0.02, 0), Vector3(0, -0.05, 0.3), "9ab4c0"],
			[Vector3(0.5, 0.1, 0.02), Vector3(0, 0.34, 0.3), "c9c7c0"]]},
	"armchair": {"size": Vector3(0.9, 0.85, 0.85), "mass": 25.0, "hp": 50.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(0.9, 0.4, 0.85), Vector3(0, -0.22, 0), "7a4a3c"], [Vector3(0.9, 0.5, 0.18), Vector3(0, 0.17, -0.33), "6a3e32"],
			[Vector3(0.16, 0.3, 0.85), Vector3(-0.37, 0.02, 0), "6a3e32"], [Vector3(0.16, 0.3, 0.85), Vector3(0.37, 0.02, 0), "6a3e32"]]},
	"plant": {"size": Vector3(-0.22, 1.1, 0), "mass": 8.0, "hp": 15.0, "surface": "wood", "throw": true, "flammable": true,
		"parts": [[Vector3(-0.18, 0.35, 0), Vector3(0, -0.375, 0), "a0522d"], [Vector3(0.45, 0.6, 0.45), Vector3(0, 0.15, 0), "3f7a3a"],
			[Vector3(0.3, 0.3, 0.3), Vector3(0.05, 0.45, 0.05), "4e8a44"]]},
	"bookcase": {"size": Vector3(0.9, 1.9, 0.35), "mass": 40.0, "hp": 70.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(0.9, 1.9, 0.02), Vector3(0, 0, -0.165), "5f3f26"], [Vector3(0.03, 1.9, 0.35), Vector3(-0.435, 0, 0), "7b5232"],
			[Vector3(0.03, 1.9, 0.35), Vector3(0.435, 0, 0), "7b5232"], [Vector3(0.86, 0.03, 0.33), Vector3(0, -0.5, 0), "7b5232"],
			[Vector3(0.86, 0.03, 0.33), Vector3(0, 0.15, 0), "7b5232"], [Vector3(0.86, 0.03, 0.33), Vector3(0, 0.8, 0), "7b5232"],
			[Vector3(0.7, 0.26, 0.22), Vector3(0, -0.36, 0.02), "8a2f20"], [Vector3(0.6, 0.24, 0.22), Vector3(-0.08, 0.29, 0.02), "2f5d8a"],
			[Vector3(0.5, 0.26, 0.22), Vector3(0.1, 0.94, 0.02), "3f6b3a"]]},
	"water_cooler": {"size": Vector3(-0.17, 1.3, 0), "mass": 22.0, "hp": 20.0, "surface": "glass", "throw": false, "flammable": false,
		"parts": [[Vector3(0.34, 0.9, 0.34), Vector3(0, -0.2, 0), "e8e6e0"], [Vector3(-0.15, 0.38, 0), Vector3(0, 0.45, 0), "9fd0e8"]]},
	# v0.10.0: up on the roofs (reached by the stairs, the lifts' towers, or
	# a grapple): cover and clutter for rooftop fights.
	"ac_unit": {"size": Vector3(1.3, 1.0, 0.9), "mass": 260.0, "hp": 260.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(1.3, 1.0, 0.9), Vector3.ZERO, "c9ccd0"], [Vector3(-0.32, 0.04, 0), Vector3(-0.28, 0.0, 0.45), "2a2c30"],
			[Vector3(0.5, 0.75, 0.02), Vector3(0.35, 0.0, 0.46), "8a8d92"], [Vector3(1.34, 0.05, 0.94), Vector3(0, 0.5, 0), "a9acb0"],
			[Vector3(0.12, 0.12, 0.6), Vector3(0.5, -0.4, -0.7), "6b6f72"]]},
	"roof_vent": {"size": Vector3(-0.3, 1.2, 0), "mass": 40.0, "hp": 160.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(-0.22, 0.95, 0), Vector3(0, -0.12, 0), "9aa0a6"], [Vector3(-0.32, 0.12, 0), Vector3(0, 0.42, 0), "7d8388"],
			[Vector3(-0.36, 0.05, 0), Vector3(0, 0.56, 0), "6b6f72"], [Vector3(-0.3, 0.06, 0), Vector3(0, -0.57, 0), "5e6266"]]},
	"water_tank": {"size": Vector3(-1.1, 3.0, 0), "mass": 2400.0, "hp": 900.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(-1.1, 2.0, 0), Vector3(0, 0.45, 0), "7a5a3c"], [Vector3(-1.15, 0.08, 0), Vector3(0, 0.3, 0), "3a3d42"],
			[Vector3(-1.15, 0.08, 0), Vector3(0, 1.1, 0), "3a3d42"], [Vector3(-0.9, 0.35, 0), Vector3(0, 1.62, 0), "5e4630"],
			[Vector3(0.12, 1.0, 0.12), Vector3(-0.7, -1.0, -0.7), "3a3d42"], [Vector3(0.12, 1.0, 0.12), Vector3(0.7, -1.0, -0.7), "3a3d42"],
			[Vector3(0.12, 1.0, 0.12), Vector3(-0.7, -1.0, 0.7), "3a3d42"], [Vector3(0.12, 1.0, 0.12), Vector3(0.7, -1.0, 0.7), "3a3d42"],
			[Vector3(0.06, 2.6, 0.4), Vector3(1.15, -0.2, 0), "5e6266"]]},
	"sat_dish": {"size": Vector3(0.9, 1.3, 0.6), "mass": 25.0, "hp": 40.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(0.6, 0.06, 0.6), Vector3(0, -0.62, 0), "5e6266"], [Vector3(0.06, 0.9, 0.06), Vector3(0, -0.15, 0), "8a8d92"],
			[Vector3(-0.42, 0.06, 0), Vector3(0, 0.35, 0.05), "e8e6e0"], [Vector3(0.03, 0.03, 0.45), Vector3(0, 0.35, 0.25), "6b6f72"]]},
	"aerial": {"size": Vector3(0.3, 2.6, 0.3), "mass": 12.0, "hp": 30.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(0.04, 2.6, 0.04), Vector3.ZERO, "6b6f72"], [Vector3(1.0, 0.03, 0.03), Vector3(0, 0.9, 0), "8a8d92"],
			[Vector3(0.8, 0.03, 0.03), Vector3(0, 1.1, 0), "8a8d92"], [Vector3(0.6, 0.03, 0.03), Vector3(0, 1.3, 0), "8a8d92"],
			[Vector3(0.3, 0.05, 0.3), Vector3(0, -1.27, 0), "3a3d42"]]},
	"roof_box": {"size": Vector3(1.6, 0.7, 0.8), "mass": 180.0, "hp": 300.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(1.6, 0.7, 0.8), Vector3.ZERO, "6d7a5a"], [Vector3(1.4, 0.05, 0.02), Vector3(0, 0.15, 0.41), "2a2c30"],
			[Vector3(1.4, 0.05, 0.02), Vector3(0, -0.05, 0.41), "2a2c30"], [Vector3(0.2, 0.2, 0.2), Vector3(0.5, 0.45, 0), "8a8d92"]]},
	"extinguisher": {"size": Vector3(-0.1, 0.55, 0), "mass": 9.0, "hp": 12.0, "surface": "metal", "throw": true, "puffs": true,
		"parts": [[Vector3(-0.1, 0.48, 0), Vector3(0, -0.035, 0), "c41f1f"], [Vector3(0.06, 0.08, 0.14), Vector3(0, 0.25, 0.03), "202226"]]},
	# v0.25 (beenster, 2026-11-24: "add another 50 furniture models"): homes,
	# kitchens and bathrooms, offices, shops, workshops and the park.
	"coffee_table": {"size": Vector3(1.1, 0.45, 0.6), "mass": 15.0, "hp": 40.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.1, 0.04, 0.6), Vector3(0, 0.2, 0), "6e4528"], [Vector3(1, 0.02, 0.5), Vector3(0, -0.1, 0), "6e4528"]]},
	"tv_stand": {"size": Vector3(1.4, 0.5, 0.45), "mass": 25.0, "hp": 60.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.4, 0.46, 0.45), Vector3(0, 0, 0), "2a2a30"]]},
	"floor_lamp": {"size": Vector3(0.4, 1.7, 0.4), "mass": 5.0, "hp": 10.0, "surface": "metal", "throw": true, "flammable": false,
		"parts": [[Vector3(0.03, 1.4, 0.03), Vector3(0, -0.1, 0), "8a8d92"], [Vector3(0.36, 0.3, 0.36), Vector3(0, 0.7, 0), "efe4c4"]]},
	"side_table": {"size": Vector3(0.45, 0.55, 0.45), "mass": 5.0, "hp": 20.0, "surface": "wood", "throw": true, "flammable": true,
		"parts": [[Vector3(0.44, 0.03, 0.44), Vector3(0, 0.26, 0), "8a5a34"], [Vector3(0.05, 0.5, 0.05), Vector3(0, 0, 0), "6e4528"]]},
	"sideboard": {"size": Vector3(1.64, 0.85, 0.48), "mass": 40.0, "hp": 80.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.6, 0.8, 0.45), Vector3(0, 0, 0), "6e4528"]]},
	"piano": {"size": Vector3(1.5, 1.3, 0.7), "mass": 220.0, "hp": 200.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.5, 1.25, 0.4), Vector3(0, 0, -0.1), "1a1214"], [Vector3(1.5, 0.05, 0.28), Vector3(0, 0.07, 0.2), "f4f2ec"]]},
	"aquarium": {"size": Vector3(1, 1.25, 0.45), "mass": 90.0, "hp": 25.0, "surface": "glass", "throw": false, "flammable": false,
		"parts": [[Vector3(1, 0.75, 0.45), Vector3(0, -0.25, 0), "2a2a30"], [Vector3(0.96, 0.42, 0.4), Vector3(0, 0.33, 0), "6ab0d0"]]},
	"bean_bag": {"size": Vector3(0.9, 0.6, 0.9), "mass": 4.0, "hp": 30.0, "surface": "wood", "throw": true, "flammable": true,
		"parts": [[Vector3(0.8, 0.5, 0.8), Vector3(0, 0, 0), "c96a3a"]]},
	"recliner": {"size": Vector3(0.9, 1, 1.1), "mass": 35.0, "hp": 60.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(0.85, 0.6, 0.85), Vector3(0, -0.2, 0), "5a3a2e"]]},
	"dining_table": {"size": Vector3(1.8, 0.76, 0.95), "mass": 40.0, "hp": 80.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.8, 0.05, 0.95), Vector3(0, 0.35, 0), "6e4528"], [Vector3(0.1, 0.7, 0.1), Vector3(-0.65, 0, 0), "4a3020"]]},
	"wardrobe": {"size": Vector3(1.24, 2, 0.62), "mass": 70.0, "hp": 110.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.2, 1.95, 0.58), Vector3(0, 0, 0), "8a5a34"]]},
	"dresser": {"size": Vector3(1.04, 0.9, 0.5), "mass": 40.0, "hp": 80.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1, 0.85, 0.48), Vector3(0, 0, 0), "9b6a3c"]]},
	"nightstand": {"size": Vector3(0.47, 1, 0.42), "mass": 10.0, "hp": 35.0, "surface": "wood", "throw": true, "flammable": true,
		"parts": [[Vector3(0.45, 0.5, 0.4), Vector3(0, -0.2, 0), "9b6a3c"]]},
	"bunk_bed": {"size": Vector3(1.02, 1.7, 2), "mass": 70.0, "hp": 120.0, "surface": "metal", "throw": false, "flammable": true,
		"parts": [[Vector3(1, 0.12, 2), Vector3(0, -0.6, 0), "3a6a8a"], [Vector3(1, 0.12, 2), Vector3(0, 0.3, 0), "3a6a8a"]]},
	"single_bed": {"size": Vector3(0.95, 0.5, 2.02), "mass": 35.0, "hp": 80.0, "surface": "metal", "throw": false, "flammable": true,
		"parts": [[Vector3(0.95, 0.2, 2), Vector3(0, -0.05, 0), "8a8d92"], [Vector3(0.9, 0.16, 1.95), Vector3(0, 0.13, 0), "e8e4da"]]},
	"cot": {"size": Vector3(0.68, 0.95, 1.26), "mass": 15.0, "hp": 40.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(0.66, 0.5, 1.24), Vector3(0, 0, 0), "e8e6e0"]]},
	"laundry_basket": {"size": Vector3(0.48, 0.56, 0.48), "mass": 2.0, "hp": 15.0, "surface": "wood", "throw": true, "flammable": true,
		"parts": [[Vector3(0.44, 0.48, 0.44), Vector3(0, 0, 0), "e8e6e0"]]},
	"stove": {"size": Vector3(0.6, 0.9, 0.64), "mass": 60.0, "hp": 150.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(0.6, 0.86, 0.6), Vector3(0, -0.02, 0), "e8e6e0"]]},
	"microwave": {"size": Vector3(0.5, 0.3, 0.38), "mass": 15.0, "hp": 20.0, "surface": "metal", "throw": true, "flammable": false,
		"parts": [[Vector3(0.5, 0.3, 0.36), Vector3(0, 0, 0), "e8e6e0"]]},
	"bar_stool": {"size": Vector3(0.4, 0.75, 0.4), "mass": 6.0, "hp": 30.0, "surface": "metal", "throw": true, "flammable": false,
		"parts": [[Vector3(0.36, 0.06, 0.36), Vector3(0, 0.35, 0), "c41f1f"], [Vector3(0.06, 0.66, 0.06), Vector3(0, 0, 0), "b8bcc2"]]},
	"kitchen_island": {"size": Vector3(1.86, 0.92, 0.96), "mass": 120.0, "hp": 160.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.8, 0.86, 0.9), Vector3(0, -0.03, 0), "e8e6e0"], [Vector3(1.86, 0.05, 0.96), Vector3(0, 0.43, 0), "3a3d42"]]},
	"pedal_bin": {"size": Vector3(0.32, 0.62, 0.4), "mass": 4.0, "hp": 40.0, "surface": "metal", "throw": true, "flammable": false,
		"parts": [[Vector3(0.3, 0.6, 0.3), Vector3(0, 0, 0), "b8bcc2"]]},
	"toilet": {"size": Vector3(0.42, 0.8, 0.7), "mass": 30.0, "hp": 40.0, "surface": "glass", "throw": false, "flammable": false,
		"parts": [[Vector3(0.38, 0.4, 0.5), Vector3(0, -0.2, 0.05), "f4f4f0"], [Vector3(0.36, 0.4, 0.17), Vector3(0, 0.2, -0.2), "f4f4f0"]]},
	"bath": {"size": Vector3(1.7, 0.6, 0.75), "mass": 70.0, "hp": 150.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(1.7, 0.56, 0.75), Vector3(0, 0, 0), "f4f4f0"]]},
	"basin": {"size": Vector3(0.56, 1, 0.42), "mass": 25.0, "hp": 30.0, "surface": "glass", "throw": false, "flammable": false,
		"parts": [[Vector3(0.56, 0.16, 0.42), Vector3(0, 0.3, 0), "f4f4f0"], [Vector3(0.18, 0.68, 0.18), Vector3(0, -0.1, 0), "f4f4f0"]]},
	"shower": {"size": Vector3(0.92, 2.1, 0.92), "mass": 60.0, "hp": 40.0, "surface": "glass", "throw": false, "flammable": false,
		"parts": [[Vector3(0.9, 0.08, 0.9), Vector3(0, -1, 0), "f4f4f0"], [Vector3(0.86, 1.9, 0.02), Vector3(0, 0, 0.44), "b9d6e2"]]},
	"office_chair": {"size": Vector3(0.62, 1.05, 0.62), "mass": 12.0, "hp": 40.0, "surface": "metal", "throw": true, "flammable": false,
		"parts": [[Vector3(0.48, 0.08, 0.46), Vector3(0, -0.06, 0), "2a2a30"], [Vector3(0.44, 0.48, 0.06), Vector3(0, 0.26, -0.22), "2a2a30"]]},
	"printer": {"size": Vector3(0.45, 0.36, 0.5), "mass": 9.0, "hp": 20.0, "surface": "metal", "throw": true, "flammable": false,
		"parts": [[Vector3(0.45, 0.24, 0.38), Vector3(0, -0.03, 0), "d9d6cf"]]},
	"photocopier": {"size": Vector3(0.95, 1.2, 0.75), "mass": 110.0, "hp": 120.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(0.85, 0.95, 0.65), Vector3(0, -0.1, 0), "d9d6cf"]]},
	"whiteboard": {"size": Vector3(1.5, 1.8, 0.62), "mass": 18.0, "hp": 40.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(1.5, 0.95, 0.03), Vector3(0, 0.35, 0), "fafaf6"]]},
	"server_rack": {"size": Vector3(0.6, 2, 0.95), "mass": 180.0, "hp": 250.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(0.6, 2, 0.9), Vector3(0, 0, 0), "1a1a1c"]]},
	"safe": {"size": Vector3(0.6, 0.8, 0.68), "mass": 300.0, "hp": 900.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(0.6, 0.8, 0.6), Vector3(0, 0, 0), "3a3d42"]]},
	"coat_stand": {"size": Vector3(0.5, 1.8, 0.5), "mass": 6.0, "hp": 25.0, "surface": "wood", "throw": true, "flammable": true,
		"parts": [[Vector3(0.05, 1.75, 0.05), Vector3(0, 0, 0), "4a3020"], [Vector3(0.36, 0.8, 0.14), Vector3(0.12, 0.35, 0), "3b5677"]]},
	"partition": {"size": Vector3(1.62, 1.5, 0.4), "mass": 20.0, "hp": 50.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.6, 1.42, 0.06), Vector3(0, 0, 0), "5e6f7f"]]},
	"till": {"size": Vector3(1.04, 1.1, 0.64), "mass": 70.0, "hp": 120.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1, 0.9, 0.6), Vector3(0, -0.1, 0), "2f5d8a"], [Vector3(0.36, 0.08, 0.3), Vector3(0.25, 0.43, -0.05), "202226"]]},
	"drinks_fridge": {"size": Vector3(0.7, 1.95, 0.68), "mass": 110.0, "hp": 120.0, "surface": "glass", "throw": false, "flammable": false,
		"parts": [[Vector3(0.7, 1.95, 0.65), Vector3(0, 0, 0), "c41f1f"]]},
	"magazine_rack": {"size": Vector3(0.9, 1.4, 0.42), "mass": 20.0, "hp": 40.0, "surface": "metal", "throw": false, "flammable": true,
		"parts": [[Vector3(0.9, 1.4, 0.04), Vector3(0, 0, -0.18), "8a8d92"], [Vector3(0.8, 0.26, 0.05), Vector3(0, 0.2, 0), "c41f1f"]]},
	"clothes_rail": {"size": Vector3(1.5, 1.6, 0.5), "mass": 15.0, "hp": 40.0, "surface": "metal", "throw": false, "flammable": true,
		"parts": [[Vector3(1.4, 0.75, 0.42), Vector3(0, 0.3, 0), "3b5677"], [Vector3(0.04, 1.55, 0.04), Vector3(-0.7, 0, 0), "b8bcc2"]]},
	"display_table": {"size": Vector3(1.4, 0.9, 0.8), "mass": 30.0, "hp": 70.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.4, 0.06, 0.8), Vector3(0, 0.37, 0), "e8e6e0"], [Vector3(1.3, 0.7, 0.7), Vector3(0, -0.03, 0), "d9d6cf"]]},
	"cash_machine": {"size": Vector3(0.8, 1.7, 0.72), "mass": 350.0, "hp": 600.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(0.8, 1.7, 0.6), Vector3(0, 0, -0.05), "3a3d42"]]},
	"chest_freezer": {"size": Vector3(1.3, 0.86, 0.7), "mass": 70.0, "hp": 120.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(1.3, 0.82, 0.65), Vector3(0, 0, 0), "e8e6e0"]]},
	"workbench": {"size": Vector3(1.8, 1.6, 0.76), "mass": 70.0, "hp": 140.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.8, 0.06, 0.75), Vector3(0, 0.07, 0), "a87a46"], [Vector3(0.07, 0.84, 0.07), Vector3(-0.84, -0.38, 0), "3a3d42"]]},
	"tool_chest": {"size": Vector3(0.8, 1.1, 0.52), "mass": 90.0, "hp": 200.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(0.7, 1, 0.5), Vector3(0, 0, 0), "c41f1f"]]},
	"steel_shelving": {"size": Vector3(1.8, 2, 0.6), "mass": 60.0, "hp": 160.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(1.8, 0.03, 0.6), Vector3(0, -0.4, 0), "8a8d92"], [Vector3(0.45, 0.35, 0.45), Vector3(0, -0.2, 0), "c9b48a"]]},
	"boxes": {"size": Vector3(0.8, 0.9, 0.6), "mass": 12.0, "hp": 20.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(0.5, 0.4, 0.4), Vector3(-0.15, -0.25, 0), "c9a87a"], [Vector3(0.4, 0.3, 0.35), Vector3(0.05, 0.1, 0), "c9a87a"]]},
	"ladder": {"size": Vector3(0.5, 2, 0.1), "mass": 8.0, "hp": 60.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(0.04, 2, 0.08), Vector3(-0.22, 0, 0), "b8bcc2"], [Vector3(0.44, 0.03, 0.03), Vector3(0, 0, 0), "c9ccd0"]]},
	"sack_truck": {"size": Vector3(0.6, 1.2, 0.4), "mass": 12.0, "hp": 80.0, "surface": "metal", "throw": true, "flammable": false,
		"parts": [[Vector3(0.04, 1.15, 0.04), Vector3(-0.18, 0, 0), "c41f1f"], [Vector3(0.4, 0.02, 0.22), Vector3(0, -0.58, 0.06), "8a8d92"]]},
	"waiting_seats": {"size": Vector3(1.8, 0.88, 0.6), "mass": 45.0, "hp": 120.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(1.8, 0.05, 0.45), Vector3(0, 0, 0), "2f5d8a"], [Vector3(1.8, 0.42, 0.05), Vector3(0, 0.24, -0.22), "2f5d8a"]]},
	"picnic_table": {"size": Vector3(1.8, 0.76, 1.7), "mass": 60.0, "hp": 120.0, "surface": "wood", "throw": false, "flammable": true,
		"parts": [[Vector3(1.8, 0.04, 0.45), Vector3(0, 0.36, 0), "8a5a34"], [Vector3(1.8, 0.04, 0.25), Vector3(0, 0.06, 0.6), "8a5a34"]]},
	"bbq": {"size": Vector3(0.62, 0.95, 0.62), "mass": 12.0, "hp": 60.0, "surface": "metal", "throw": false, "flammable": false,
		"parts": [[Vector3(0.6, 0.3, 0.6), Vector3(0, 0.27, 0), "1a1a1c"], [Vector3(0.03, 0.6, 0.03), Vector3(0.18, -0.15, 0), "1a1a1c"]]},
}

static var current: PropWorld

signal broke(id: int, kind: String, at: Vector3)

var world: DestructionWorld
var cars: CarSync
## id -> {id, kind, body, hp, broken, burning}
var props := {}
var _snap_t := 0.0
var _sent := {}            # id -> time last sent
var _clock := 0.0
var _targets := {}         # client: id -> Transform3D
var _prev_v := {}          # host: id -> last linear velocity
var _next_id := 0


func _ready() -> void:
	current = self
	Net.register(MSG_SNAP, _on_snap)
	Net.register(MSG_BREAK, _on_break)


func _exit_tree() -> void:
	if current == self:
		current = null
	for m in [MSG_SNAP, MSG_BREAK]:
		Net.unregister(m)


## The props as they are now (Phase 1.7): what has broken, and where every
## standing one is. Sent to a friend who joins late, and what the host saves.
func write_state(b: StreamPeerBuffer) -> void:
	if city:
		# Wave 2: which city blocks are furnished, so the reader makes the
		# same props first.
		b.put_u16(furnished.size())
		for k in furnished:
			b.put_u16(k)
	b.put_u16(props.size())
	for p in props.values():
		b.put_u16(p.id)
		b.put_u8(1 if p.broken else 0)
		if not p.broken:
			DestructionWorld._put_xform(b, (p.body as RigidBody3D).global_transform)


## Puts the props where a written state says, quietly: the breaking happened
## a while ago, so no sound and no splinters.
func read_state(b: StreamPeerBuffer) -> void:
	if city:
		for i in b.get_u16():
			furnish_block(b.get_u16())
	for i in b.get_u16():
		var id := b.get_u16()
		var gone := b.get_u8() == 1
		var xf := Transform3D() if gone else DestructionWorld._get_xform(b)
		var p: Dictionary = props.get(id, {})
		if p.is_empty() or p.broken:
			continue
		var rb: RigidBody3D = p.body
		if gone:
			p.broken = true
			_targets.erase(id)
			rb.queue_free()
		else:
			rb.global_transform = xf
			_targets.erase(id)


# --- placing -------------------------------------------------------------------------

## Furnishes a generated block from its seed (the same on every machine).
func furnish(gen: BlockGenerator) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(gen.seed_value * 31 + 5)
	var M := BlockGenerator.M
	for b in gen.buildings:
		var basis: Basis = b.basis
		if b.enterable:
			var door_local: Vector3 = (b.door as Vector3) - (b.origin as Vector3)
			var door_x: float = door_local.dot(b.u)
			# The extinguisher on the floor just inside the door, by the wall.
			add_prop("extinguisher", _local(b, minf(door_x + 1.3, b.w * M - 0.5), 0.0, 0.45, basis, 0.0))
			for s in b.storeys:
				var y: float = s * BlockGenerator.STOREY
				for i in b.w:
					for j in b.d:
						if s < b.storeys - 1 and i == b.w - 1 and j == b.d - 1:
							continue    # the stairs
						if s > 0 and i == b.w - 1 and j == b.d - 1:
							continue    # the stairwell
						var cx: float = (i + 0.5) * M
						var cz: float = (j + 0.5) * M
						if s == 0 and j == 0 and absf(cx - door_x) < M * 0.6:
							continue    # keep the way in clear
						_furnish_cell(b, rng, cx, y, cz, basis, b.type == "shop" and s == 0 and j == 0)
		else:
			# Something left out in front now and then.
			if rng.randf() < 0.5:
				add_prop("bin", _local(b, rng.randf_range(0.8, b.w * M - 0.8), 0.0, -0.9, basis, rng.randf() * TAU))
	# Out in the yards and alleys, and along the pavement.
	var e := BlockGenerator.N * M
	for k in 8:
		var p := Vector3(rng.randf_range(6.0, e - 6.0), BlockGenerator.BASE_Y, rng.randf_range(6.0, e - 6.0))
		if _inside_any(gen, p):
			continue
		var roll := rng.randf()
		if roll < 0.3:
			for n in rng.randi_range(1, 3):
				add_prop("crate", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p + Vector3(n * 0.7, 0, 0)))
		elif roll < 0.5:
			add_prop("barrel", Transform3D(Basis(), p))
		elif roll < 0.65:
			add_prop("gas", Transform3D(Basis(), p))
		elif roll < 0.85:
			add_prop("bin", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
		else:
			for n in 3:
				add_prop("bottle", Transform3D(Basis(), p + Vector3(n * 0.15, 0, rng.randf() * 0.2)))
	for k in 4:
		var along := rng.randf_range(8.0, e - 8.0)
		var spots := [Vector3(along, BlockGenerator.BASE_Y, 2.0), Vector3(along, BlockGenerator.BASE_Y, e - 2.0)]
		var p: Vector3 = spots[k % 2]
		if not _inside_any(gen, p):
			add_prop("bench", Transform3D(Basis(), p))


# --- Wave 2: the city, a block at a time -----------------------------------------------

## Prop ids per city block (ids are u16 on the wire): block k uses
## k * BLOCK_IDS + 1 up to (k + 1) * BLOCK_IDS - 1.
const BLOCK_IDS := 1800
## Container colours on the docks.
const CONTAINER_COLOURS := ["b3402a", "2f5d8a", "3f6b3a", "c9a23a", "6f7378", "8a4a2c"]
var city: CityGenerator
var furnished := {}       # block index -> true


## Furnishes one city block (every machine, from the city seed). The host
## decides when (an officer coming near), so ids line up everywhere.
func furnish_block(k: int) -> void:
	if city == null or furnished.has(k) or k < 0 or k >= city.blocks.size():
		return
	furnished[k] = true
	var blk: Dictionary = city.blocks[k]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(city.seed_value * 31 + 5 + k * 977)
	_next_id = k * BLOCK_IDS + 1
	var limit: int = (k + 1) * BLOCK_IDS - 60
	for bi in range(blk.buildings_from, blk.buildings_to):
		if _next_id >= limit:
			break
		_furnish_rooms(city.buildings[bi], rng, limit)
	for bi in range(blk.buildings_from, blk.buildings_to):
		if _next_id >= limit:
			break
		_furnish_roof(city.buildings[bi], rng)
	_furnish_outdoors(blk, rng, (k + 1) * BLOCK_IDS - 1)


## v0.10.0: plant on the roofs: air conditioning, vents, aerials, a water
## tank on the tall ones. Kept off the stair hut and a metre in from the edge.
func _furnish_roof(b: Dictionary, rng: RandomNumberGenerator) -> void:
	if int(b.storeys) < 2 or b.type == "house":
		return
	var M := BlockGenerator.M
	var basis: Basis = b.basis
	var y: float = b.storeys * BlockGenerator.STOREY
	var tank := int(b.storeys) >= 4
	for i in int(b.w):
		for j in int(b.d):
			if b.get("roof_access", false) and i == b.w - 1 and j == b.d - 1:
				continue    # the stair hut
			if rng.randf() < 0.4:
				continue
			var cx := (i + 0.5) * M + rng.randf_range(-0.6, 0.6)
			var cz := (j + 0.5) * M + rng.randf_range(-0.6, 0.6)
			var yaw := float(rng.randi_range(0, 3)) * PI * 0.5
			var roll := rng.randf()
			if tank and roll < 0.25:
				tank = false
				add_prop("water_tank", _local(b, (i + 0.5) * M, y, (j + 0.5) * M, basis, 0.0))
			elif roll < 0.55:
				add_prop("ac_unit", _local(b, cx, y, cz, basis, yaw))
				if rng.randf() < 0.4:
					add_prop("ac_unit", _local(b, cx, y, cz + (1.1 if cz < M * 1.5 else -1.1), basis, yaw))
			elif roll < 0.75:
				add_prop("roof_vent", _local(b, cx, y, cz, basis, 0.0))
				if rng.randf() < 0.5:
					add_prop("roof_vent", _local(b, cx + 0.9, y, cz + 0.4, basis, 0.0))
			elif roll < 0.85:
				add_prop("roof_box", _local(b, cx, y, cz, basis, yaw))
			elif roll < 0.93:
				add_prop("sat_dish", _local(b, cx, y, cz, basis, rng.randf() * TAU))
			else:
				add_prop("aerial", _local(b, cx, y, cz, basis, 0.0))


func _furnish_rooms(b: Dictionary, rng: RandomNumberGenerator, limit: int) -> void:
	var M := BlockGenerator.M
	var basis: Basis = b.basis
	var door_local: Vector3 = (b.door as Vector3) - (b.origin as Vector3)
	var door_x: float = door_local.dot(b.u)
	add_prop("extinguisher", _local(b, minf(door_x + 1.3, b.w * M - 0.5), 0.0, 0.45, basis, 0.0))
	var stair := Rect2((b.w - 1) * M, (b.d - 1) * M, M, M).grow(0.3)
	var shaft := CityStyles.shaft_rect(b).grow(0.3)
	for r in b.get("rooms", []):
		if _next_id >= limit:
			return
		var y: float = r.floor * BlockGenerator.STOREY
		var rect: Rect2 = r.rect
		# One spot per module of the room.
		for i in int(rect.size.x / M):
			for j in int(rect.size.y / M):
				var cx: float = rect.position.x + (i + 0.5) * M
				var cz: float = rect.position.y + (j + 0.5) * M
				if stair.has_point(Vector2(cx, cz)) or shaft.has_point(Vector2(cx, cz)):
					continue
				if r.floor == 0 and cz < M and absf(cx - door_x) < M * 0.6:
					continue    # keep the way in clear
				if rng.randf() < 0.3:
					continue
				_furnish_module(b, rng, String(r.kind), cx, y, cz, basis)


func _furnish_module(b: Dictionary, rng: RandomNumberGenerator, kind: String, cx: float, y: float, cz: float, basis: Basis) -> void:
	var roll := rng.randf()
	# v0.25: more to furnish rooms with (fifty new pieces), picked per room.
	var at := func(dx: float, dz: float, yaw := 0.0, up := 0.0) -> Transform3D:
		return _local(b, cx + dx, y + up, cz + dz, basis, yaw)
	match kind:
		"living":
			if roll < 0.3:
				add_prop("sofa", at.call(0.0, 1.2, PI))
				var r2 := rng.randf()
				if r2 < 0.4:
					add_prop("coffee_table", at.call(0.0, 0.1))
				elif r2 < 0.75:
					add_prop("tv_stand", at.call(0.0, -1.5))
					add_prop("tv", at.call(0.0, -1.5, 0.0, 0.5))
				else:
					add_prop("table", at.call(0.0, -0.2))
				if rng.randf() < 0.4:
					add_prop("floor_lamp", at.call(1.3, 1.4))
			elif roll < 0.45:
				add_prop("armchair", at.call(-0.6, 0.0, rng.randf_range(-0.5, 0.5)))
				add_prop("side_table", at.call(0.2, 0.3))
				add_prop("plant", at.call(1.4, 1.4))
			elif roll < 0.55:
				add_prop("recliner", at.call(0.0, 0.3, PI + rng.randf_range(-0.4, 0.4)))
				add_prop("bean_bag" if rng.randf() < 0.5 else "floor_lamp", at.call(1.2, 1.2))
			elif roll < 0.65:
				add_prop("bookcase", at.call(0.0, 1.6, PI))
				if rng.randf() < 0.5:
					add_prop("sideboard", at.call(0.0, -1.6))
			elif roll < 0.72:
				add_prop("piano", at.call(0.0, 1.5, PI))
				add_prop("chair", at.call(0.0, 0.6, PI))
			elif roll < 0.78:
				add_prop("aquarium", at.call(0.0, 1.6, PI))
			elif roll < 0.88:
				add_prop("dining_table", at.call(0.0, 0.0))
				for n in 4:
					var sx := -0.5 if n % 2 == 0 else 0.5
					var sz := -0.75 if n < 2 else 0.75
					add_prop("chair", at.call(sx, sz, 0.0 if sz > 0.0 else PI))
			else:
				_furnish_cell(b, rng, cx, y, cz, basis, false)
		"bedroom":
			var bed := "bed" if roll < 0.5 else ("single_bed" if roll < 0.8 else "bunk_bed")
			add_prop(bed, at.call(0.0, 0.6, PI if rng.randf() < 0.5 else 0.0))
			var r2 := rng.randf()
			add_prop("nightstand", at.call(-1.1, 1.3))
			if r2 < 0.4:
				add_prop("wardrobe", at.call(1.4, -1.5))
			elif r2 < 0.7:
				add_prop("dresser", at.call(1.3, -1.6))
			elif r2 < 0.85:
				add_prop("cabinet", at.call(1.5, -1.4))
			if rng.randf() < 0.3:
				add_prop("laundry_basket", at.call(-1.4, -1.4))
			elif rng.randf() < 0.12:
				add_prop("cot", at.call(-1.2, -1.0))
		"kitchen":
			add_prop("counter", at.call(0.0, 1.6, PI))
			if rng.randf() < 0.6:
				add_prop("microwave", at.call(-0.5, 1.6, PI, 1.0))
			if roll < 0.35:
				add_prop("fridge", at.call(1.4, -1.2))
			elif roll < 0.55:
				add_prop("washer", at.call(-1.4, -1.3))
			elif roll < 0.8:
				add_prop("stove", at.call(1.4, -1.3))
			else:
				add_prop("kitchen_island", at.call(0.0, -0.4))
				for n in 2:
					add_prop("bar_stool", at.call(-0.4 + n * 0.8, -1.2))
			for n in rng.randi_range(0, 3):
				add_prop("bottle", at.call(0.1 + n * 0.25, 1.6, 0.0, 1.01))
			if rng.randf() < 0.5:
				add_prop("pedal_bin", at.call(-1.5, 1.6))
			elif rng.randf() < 0.5:
				add_prop("gas", at.call(1.4, 1.5))
		"bathroom":
			add_prop("toilet", at.call(-1.2, 1.4, PI))
			add_prop("basin", at.call(0.0, 1.65, PI))
			add_prop("bath" if roll < 0.55 else "shower", at.call(0.0, -1.2) if roll < 0.55 else at.call(1.3, -1.3))
			if rng.randf() < 0.4:
				add_prop("cabinet", at.call(1.5, 1.6, PI))
		"shopfloor":
			if roll < 0.35:
				add_prop("shelf", at.call(0.0, 0.4, PI))
				for n in rng.randi_range(1, 3):
					add_prop("bottle", at.call(-0.5 + n * 0.25, 0.4, 0.0, 1.81))
			elif roll < 0.5:
				add_prop("drinks_fridge", at.call(0.0, 1.5, PI))
			elif roll < 0.62:
				add_prop("clothes_rail", at.call(0.0, 0.0, rng.randf_range(-0.2, 0.2)))
			elif roll < 0.72:
				add_prop("display_table", at.call(0.0, 0.0))
			elif roll < 0.8:
				add_prop("magazine_rack", at.call(0.0, 1.6, PI))
			elif roll < 0.86:
				add_prop("chest_freezer", at.call(0.0, 0.5))
			elif roll < 0.93:
				add_prop("till", at.call(0.0, -1.0))
			else:
				add_prop("cash_machine", at.call(0.0, 1.5, PI))
		"stock", "hall":
			if roll < 0.35:
				add_prop("pallet", at.call(0.0, 0.0, rng.randf_range(-0.2, 0.2)))
				for n in rng.randi_range(1, 4):
					add_prop("crate", at.call(-0.3 + (n % 2) * 0.6, 0.0, 0.0, 0.15 + (n / 2) * 0.6))
			elif roll < 0.5:
				add_prop("shelf" if rng.randf() < 0.4 else "steel_shelving", at.call(0.0, 1.4, PI))
			elif roll < 0.6:
				add_prop("workbench", at.call(0.0, 1.4, PI))
				if rng.randf() < 0.6:
					add_prop("tool_chest", at.call(1.4, 1.5, PI))
			elif roll < 0.68:
				add_prop("boxes", at.call(0.0, 0.0, rng.randf() * TAU))
			elif roll < 0.74:
				add_prop("ladder", at.call(0.0, 1.75, PI))
				add_prop("sack_truck", at.call(1.0, 1.0, rng.randf() * TAU))
			elif roll < 0.82:
				add_prop("barrel", at.call(0.0, 0.0))
			elif roll < 0.9:
				add_prop("tyres", at.call(0.0, 0.0))
			else:
				add_prop("gas", at.call(0.8, 0.8))
		"office":
			add_prop("desk", at.call(0.0, 0.0, PI if roll < 0.5 else 0.0))
			add_prop("office_chair" if rng.randf() < 0.7 else "chair", at.call(0.0, 0.7 if roll >= 0.5 else -0.7, PI if roll >= 0.5 else 0.0))
			var extra := rng.randf()
			if extra < 0.2:
				add_prop("cabinet", at.call(1.6, 1.5, PI))
			elif extra < 0.3:
				add_prop("plant", at.call(1.6, 1.5))
			elif extra < 0.36:
				add_prop("water_cooler", at.call(1.6, 1.5))
			elif extra < 0.44:
				add_prop("photocopier", at.call(1.4, 1.4, PI))
			elif extra < 0.52:
				add_prop("partition", at.call(0.0, 1.2))
			elif extra < 0.58:
				add_prop("server_rack", at.call(1.5, 1.4, PI))
			elif extra < 0.64:
				add_prop("safe", at.call(1.5, 1.5, PI))
			elif extra < 0.7:
				add_prop("coat_stand", at.call(1.6, 1.6))
			if rng.randf() < 0.3:
				add_prop("printer", at.call(-0.5, 0.0, 0.0, 0.76))
		"meeting":
			add_prop("table" if roll < 0.6 else "dining_table", at.call(0.0, 0.0))
			for n in 4:
				var a := n * TAU / 4.0 + 0.4
				add_prop("chair" if roll < 0.6 else "office_chair", at.call(cos(a) * 0.95 * (1.2 if roll >= 0.6 else 1.0), sin(a) * 0.95, -a - PI * 0.5))
			if rng.randf() < 0.5:
				add_prop("whiteboard", at.call(0.0, 1.6, PI))
		"lobby":
			if roll < 0.3:
				add_prop("counter", at.call(0.0, 0.0))
			elif roll < 0.45:
				add_prop("vending", at.call(0.0, 1.4, PI))
			elif roll < 0.6:
				add_prop("waiting_seats", at.call(0.0, 1.4, PI))
			elif roll < 0.7:
				add_prop("plant", at.call(0.0, 0.0))
			elif roll < 0.78:
				add_prop("cash_machine", at.call(0.0, 1.5, PI))
			elif roll < 0.86:
				add_prop("coat_stand", at.call(0.0, 0.0))
			else:
				add_prop("chair", at.call(0.0, 0.0, rng.randf() * TAU))
		"cell":
			add_prop("bench", at.call(0.0, 1.4, PI))
		_:
			_furnish_cell(b, rng, cx, y, cz, basis, false)


## Out on the lot: yards and alleys, the pavement, parks, the docks.
func _furnish_outdoors(blk: Dictionary, rng: RandomNumberGenerator, limit: int) -> void:
	var r: Rect2 = blk.rect
	var o: Vector3 = blk.offset
	var y := BlockGenerator.BASE_Y
	var inside := func(p: Vector3) -> bool:
		for bi in range(blk.buildings_from, blk.buildings_to):
			if (city.buildings[bi].bounds as AABB).grow(1.0).has_point(p + Vector3(0, 0.5, 0)):
				return true
		return false
	var ex := r.size.x
	var ez := r.size.y
	# Bins and benches along the kerb.
	for k in 6:
		if _next_id >= limit:
			return
		var ax := rng.randf_range(6.0, ex - 6.0)
		var az := rng.randf_range(6.0, ez - 6.0)
		var spots := [Vector3(ax, 0, 1.6), Vector3(ax, 0, ez - 1.6), Vector3(1.6, 0, az), Vector3(ex - 1.6, 0, az)]
		var p: Vector3 = o + spots[k % 4] + Vector3(0, y, 0)
		if not inside.call(p):
			add_prop("bin" if k % 2 == 0 else "bench", Transform3D(Basis(Vector3.UP, 0.0 if k % 4 < 2 else PI / 2), p))
	_street_furniture(blk, rng, limit, inside)
	match blk.style:
		"park":
			for k in 8:
				var p := o + Vector3(rng.randf_range(8.0, ex - 8.0), y - 0.05, rng.randf_range(8.0, ez - 8.0))
				add_prop("bench", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
			# v0.25: picnic tables and a barbecue.
			for k in 3:
				var p := o + Vector3(rng.randf_range(8.0, ex - 8.0), y - 0.05, rng.randf_range(8.0, ez - 8.0))
				add_prop("picnic_table", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
				if k == 0:
					add_prop("bbq", Transform3D(Basis(), p + Vector3(1.6, 0, 0)))
		"docks", "industrial":
			# Container stacks in the yards (good, hard cover), pallets and
			# barrels.
			var tries := 30
			var placed := 0
			var stacks: Array = []   # footprints already used (v0.16.0: they were placed inside each other)
			while tries > 0 and placed < (8 if blk.style == "docks" else 3) and _next_id < limit - 4:
				tries -= 1
				var p := o + Vector3(rng.randf_range(6.0, ex - 6.0), y, rng.randf_range(6.0, ez - 6.0))
				var yaw := 0.0 if rng.randf() < 0.5 else PI / 2
				var foot := AABB(p - Vector3(3.5, 0, 3.5), Vector3(7, 3, 7))
				var clash := false
				for bi in range(blk.buildings_from, blk.buildings_to):
					if (city.buildings[bi].bounds as AABB).grow(1.5).intersects(foot):
						clash = true
				# Two containers spawned inside each other were shoved apart by
				# the physics hard enough to push one down through the ground.
				for f in stacks:
					if (f as AABB).intersects(foot):
						clash = true
				if clash:
					continue
				stacks.append(foot)
				var id := add_prop("container", Transform3D(Basis(Vector3.UP, yaw), p))
				_paint_container(id, rng)
				if rng.randf() < 0.5:
					var id2 := add_prop("container", Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 2.62, 0)))
					_paint_container(id2, rng)
				placed += 1
			for k in 6:
				var p := o + Vector3(rng.randf_range(6.0, ex - 6.0), y, rng.randf_range(6.0, ez - 6.0))
				if inside.call(p):
					continue
				add_prop("barrel" if rng.randf() < 0.4 else "pallet", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
		_:
			for k in 6:
				if _next_id >= limit:
					return
				var p := o + Vector3(rng.randf_range(6.0, ex - 6.0), y, rng.randf_range(6.0, ez - 6.0))
				if inside.call(p):
					continue
				var roll := rng.randf()
				if roll < 0.35:
					for n in rng.randi_range(1, 3):
						add_prop("crate", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p + Vector3(n * 0.7, 0, 0)))
				elif roll < 0.5:
					add_prop("barrel", Transform3D(Basis(), p))
				elif roll < 0.6:
					add_prop("gas", Transform3D(Basis(), p))
				else:
					add_prop("bin", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))


## Wave 5: what stands on the pavement depends on the district: phone
## boxes, post boxes, vending machines, planters and bike racks downtown;
## wheelie bins and post boxes on residential streets; tyres and cones in
## the industrial yards and the docks; a hydrant on every block.
func _street_furniture(blk: Dictionary, rng: RandomNumberGenerator, limit: int, inside: Callable) -> void:
	var o: Vector3 = blk.offset
	var ex: float = (blk.rect as Rect2).size.x
	var ez: float = (blk.rect as Rect2).size.y
	var y := BlockGenerator.BASE_Y
	var pool: Array
	match String(blk.style):
		"downtown", "station", "carpark":
			pool = ["phone_box", "post_box", "vending", "planter", "planter", "bike_rack", "wheelie_bin"]
		"residential":
			pool = ["wheelie_bin", "wheelie_bin", "wheelie_bin", "post_box", "planter"]
		"park":
			pool = ["planter", "bike_rack", "post_box"]
		_:
			pool = ["tyres", "cone", "cone", "wheelie_bin"]
	var n := rng.randi_range(4, 7)
	for k in n + 1:
		if _next_id >= limit - 4:
			return
		var ax := rng.randf_range(5.0, ex - 5.0)
		var az := rng.randf_range(5.0, ez - 5.0)
		var side := rng.randi_range(0, 3)
		var spots := [Vector3(ax, 0, 1.2), Vector3(ax, 0, ez - 1.2), Vector3(1.2, 0, az), Vector3(ex - 1.2, 0, az)]
		var yaws := [0.0, PI, PI / 2, -PI / 2]    # facing the road
		var p: Vector3 = o + spots[side] + Vector3(0, y, 0)
		if inside.call(p):
			continue
		var kind: String = "hydrant" if k == n else pool[rng.randi_range(0, pool.size() - 1)]
		var at := p
		add_prop(kind, Transform3D(Basis(Vector3.UP, yaws[side] + PI), at))
		if kind == "cone" and rng.randf() < 0.6:
			for c in rng.randi_range(1, 3):
				var off := Basis(Vector3.UP, yaws[side]) * Vector3(0.9 * (c + 1), 0, 0)
				add_prop("cone", Transform3D(Basis(), at + off))


func _paint_container(id: int, rng: RandomNumberGenerator) -> void:
	var rb := body(id)
	if rb == null:
		return
	var col := Color(CONTAINER_COLOURS[rng.randi_range(0, CONTAINER_COLOURS.size() - 1)])
	var mi := rb.find_children("*", "MeshInstance3D", false, false)[0] as MeshInstance3D
	var firsts: Array = _kind_first.get("container", [])
	for i in mi.mesh.get_surface_count():
		var first: bool = i < firsts.size() and firsts[i]
		mi.set_surface_override_material(i, Cel.material(col.darkened(0.0 if first else 0.25), true, 0.02))


func _furnish_cell(b: Dictionary, rng: RandomNumberGenerator, cx: float, y: float, cz: float, basis: Basis, shop_front: bool) -> void:
	var roll := rng.randf()
	if shop_front:
		add_prop("shelf", _local(b, cx, y, cz + 1.2, basis, PI))
		for n in rng.randi_range(1, 3):
			add_prop("bottle", _local(b, cx - 0.5 + n * 0.25, y + 1.81, cz + 1.2, basis, 0.0))
		return
	if roll < 0.45:
		add_prop("table", _local(b, cx, y, cz, basis, rng.randf_range(-0.3, 0.3)))
		for n in rng.randi_range(1, 3):
			var a := n * TAU / 3.0 + rng.randf() * 0.4
			add_prop("chair", _local(b, cx + cos(a) * 0.95, y, cz + sin(a) * 0.95, basis, -a - PI * 0.5))
		if rng.randf() < 0.5:
			add_prop("bottle", _local(b, cx + 0.2, y + 0.76, cz, basis, 0.0))
	elif roll < 0.7:
		add_prop("shelf", _local(b, cx, y, cz + 1.5, basis, PI))
	elif roll < 0.9:
		add_prop("crate", _local(b, cx + 0.8, y, cz + 0.8, basis, rng.randf() * TAU))
		add_prop("crate", _local(b, cx + 0.8, y + 0.6, cz + 0.8, basis, rng.randf() * TAU))
	elif roll < 0.97:
		add_prop("chair", _local(b, cx, y, cz, basis, rng.randf() * TAU))
	else:
		add_prop("gas", _local(b, cx + 1.2, y, cz + 1.2, basis, 0.0))


## A floor-standing transform from building-local coordinates (bottom at y).
func _local(b: Dictionary, x: float, y: float, z: float, basis: Basis, yaw: float) -> Transform3D:
	var p: Vector3 = (b.origin as Vector3) + (b.u as Vector3) * x + Vector3.UP * y + (b.v as Vector3) * z
	return Transform3D(basis * Basis(Vector3.UP, yaw), p)


func _inside_any(gen: BlockGenerator, p: Vector3) -> bool:
	for b in gen.buildings:
		if (b.bounds as AABB).grow(1.0).has_point(p + Vector3(0, 0.5, 0)):
			return true
	return false


static func height_of(kind: String) -> float:
	var s: Vector3 = KINDS[kind].size
	return s.y


## Adds a prop standing on the floor at xf (its bottom at xf.origin). Same
## order on every machine gives the same ids.
func add_prop(kind: String, xf: Transform3D) -> int:
	var d: Dictionary = KINDS[kind]
	var id := _next_id
	_next_id += 1
	var rb := RigidBody3D.new()
	rb.name = "Prop%d_%s" % [id, kind]
	rb.mass = d.mass
	rb.collision_layer = LAYER
	rb.collision_mask = 1 | 2 | 4 | 16
	rb.set_meta("prop_id", id)
	rb.set_meta("surface", d.surface)
	rb.add_to_group("props")
	rb.add_to_group(RoofFader.CUTAWAY_GROUP)   # goes with the floor it's on
	rb.add_to_group("destruction_body")    # blasts push them
	if d.get("throw", false):
		rb.add_to_group("throwable")
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.1
	rb.physics_material_override = pm
	var size: Vector3 = d.size
	var cs := CollisionShape3D.new()
	if size.x < 0.0:
		var cyl := CylinderShape3D.new()
		cyl.radius = -size.x
		cyl.height = size.y
		cs.shape = cyl
	else:
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
	rb.add_child(cs)
	# v0.8.1: one mesh per prop (its parts merged, one surface per colour)
	# instead of a mesh per part: a city has thousands of props.
	var pm_mi := MeshInstance3D.new()
	pm_mi.mesh = _kind_mesh(kind)
	pm_mi.visibility_range_end = OUTDOOR_RANGE if kind in OUTDOOR_KINDS else INDOOR_RANGE
	pm_mi.visibility_range_end_margin = 4.0
	pm_mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	if (size.x < 0.0 and -size.x < 0.25) or (size.x >= 0.0 and size.length() < 0.6):
		pm_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb.add_child(pm_mi)
	rb.transform = Transform3D(xf.basis, xf.origin + xf.basis.y * (size.y * 0.5 + 0.01))
	rb.can_sleep = true
	rb.sleeping = true
	if not Net.is_host():
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.freeze = true
	add_child(rb)
	props[id] = {"id": id, "kind": kind, "body": rb, "hp": float(d.hp), "broken": false, "burning": false}
	# Wave 2: only awake props are looked at each frame (a city has thousands).
	rb.sleeping_state_changed.connect(func():
		if is_instance_valid(rb) and not rb.sleeping:
			_awake[id] = true)
	return id


## v0.8.1: props past these distances (m) stop drawing.
const INDOOR_RANGE := 55.0
const OUTDOOR_RANGE := 110.0
const OUTDOOR_KINDS := ["picnic_table", "bbq", "bench", "bin", "barrel", "gas", "crate", "pallet", "container", "post_box", "phone_box",
	"hydrant", "cone", "planter", "vending", "wheelie_bin", "bike_rack", "trolley", "tyres", "extinguisher"]
static var _kind_meshes := {}
## kind -> per surface: whether it holds the kind's first part.
static var _kind_first := {}


## v0.25: the props' Blender models (tools/blender/build_furniture.py), one
## mesh per kind, centred on the kind's collision box.
const MODELS_PATH := "res://assets/models/props/furniture.glb"
static var _models := {}


static func model_of(kind: String) -> Mesh:
	if _models.is_empty():
		_models[""] = null
		var ps := load(MODELS_PATH) as PackedScene
		if ps:
			var root := ps.instantiate()
			for mi in root.find_children("*", "MeshInstance3D", true, false):
				_models[String(mi.name)] = (mi as MeshInstance3D).mesh
			root.free()
	return _models.get(kind)


## Every part of a kind merged into one mesh, a surface per colour (the
## Blender model's, cel shaded, when there is one).
static func _kind_mesh(kind: String) -> ArrayMesh:
	if _kind_meshes.has(kind):
		return _kind_meshes[kind]
	var model := model_of(kind)
	if model:
		var out := ArrayMesh.new()
		var fs: Array = []
		for i in model.get_surface_count():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, model.surface_get_arrays(i))
			var src := model.surface_get_material(i)
			var col := (src as BaseMaterial3D).albedo_color if src is BaseMaterial3D else Color(0.7, 0.7, 0.7)
			out.surface_set_material(i, Cel.material(col, true, 0.012))
			fs.append(src != null and src.resource_name.begins_with("paint_"))
		_kind_first[kind] = fs
		out = _one_surface(kind, out)
		_kind_meshes[kind] = out
		return out
	var by_colour := {}    # colour -> SurfaceTool
	var order: Array = []
	var first_col := ""
	var parts: Array = KINDS[kind].parts
	for pi in parts.size():
		var part: Array = parts[pi]
		var size: Vector3 = part[0]
		var src: PrimitiveMesh
		if size.x < 0.0:
			var cm := CylinderMesh.new()
			cm.top_radius = -size.x
			cm.bottom_radius = -size.x
			cm.height = size.y
			cm.radial_segments = 12
			src = cm
		else:
			var bm := BoxMesh.new()
			bm.size = size
			src = bm
		var col := String(part[2])
		if pi == 0:
			first_col = col
		if not by_colour.has(col):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			by_colour[col] = st
			order.append(col)
		(by_colour[col] as SurfaceTool).append_from(src, 0, Transform3D(Basis(), part[1]))
	var am := ArrayMesh.new()
	var firsts: Array = []
	for col in order:
		var st: SurfaceTool = by_colour[col]
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, Cel.material(Color(col), true, 0.012))
		firsts.append(col == first_col)
	_kind_first[kind] = firsts
	am = _one_surface(kind, am)
	_kind_meshes[kind] = am
	return am


## v0.25.1: a prop's colours become vertex colours on one surface, so each
## prop is a single draw (plus its outline) instead of one per colour. The
## v0.25 furniture averaged five colours a piece, which put the benchmark's
## draw calls up by half. Containers keep theirs: they are repainted per
## surface.
static func _one_surface(kind: String, src: ArrayMesh) -> ArrayMesh:
	if kind == "container" or src.get_surface_count() < 2:
		return src
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in src.get_surface_count():
		var a := src.surface_get_arrays(i)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n = a[Mesh.ARRAY_NORMAL]
		var uv = a[Mesh.ARRAY_TEX_UV]
		var ix = a[Mesh.ARRAY_INDEX]
		var mat := src.surface_get_material(i) as ShaderMaterial
		var c: Color = mat.get_shader_parameter("albedo") if mat else Color(0.7, 0.7, 0.7)
		var base := verts.size()
		verts.append_array(v)
		for k in v.size():
			norms.append(n[k] if n is PackedVector3Array and k < n.size() else Vector3.UP)
			uvs.append(uv[k] if uv is PackedVector2Array and k < uv.size() else Vector2.ZERO)
			cols.append(c)
		if ix is PackedInt32Array and ix.size() > 0:
			for k in ix:
				idx.append(base + k)
		else:
			for k in v.size():
				idx.append(base + k)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	out.surface_set_material(0, Cel.material(Color.WHITE, true, 0.012, null, 1.0, false, true))
	return out


static func _part_mesh(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if size.x < 0.0:
		var cm := CylinderMesh.new()
		cm.top_radius = -size.x
		cm.bottom_radius = -size.x
		cm.height = size.y
		cm.radial_segments = 12
		mi.mesh = cm
	else:
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
	mi.material_override = Cel.material(color, true, 0.012)
	mi.position = at
	return mi


func body(id: int) -> RigidBody3D:
	var p: Dictionary = props.get(id, {})
	return p.body if not p.is_empty() and not p.broken else null


func prop_of(collider: Object) -> Dictionary:
	if collider is Node and (collider as Node).has_meta("prop_id"):
		return props.get(int((collider as Node).get_meta("prop_id")), {})
	return {}


func intact() -> Array:
	return props.values().filter(func(p): return not p.broken)


# --- host: damage ----------------------------------------------------------------------

## Host: a bullet hit this collider (true if it was a prop).
func bullet_hit(collider: Object, point: Vector3, dir: Vector3, damage := BULLET_DAMAGE) -> bool:
	var p := prop_of(collider)
	if p.is_empty() or p.broken:
		return false
	var rb: RigidBody3D = p.body
	rb.apply_impulse(dir * 35.0, point - rb.global_position)
	damage_prop(p.id, damage, point, dir)
	return true


## Host: hurts a prop; at 0 it breaks.
func damage_prop(id: int, amount: float, at: Vector3, dir := Vector3.ZERO) -> void:
	if not Net.is_host():
		return
	var p: Dictionary = props.get(id, {})
	if p.is_empty() or p.broken:
		return
	p.hp -= amount
	if p.hp <= 0.0:
		break_prop(id, at, dir)


## Host: a blast at `at`: props near it are hurt (and pushed by the world's
## own blast push).
func blast(at: Vector3, radius: float, damage: float) -> void:
	for p in intact():
		var rb: RigidBody3D = p.body
		var d := rb.global_position.distance_to(at)
		if d < radius:
			damage_prop(p.id, damage * (1.0 - d / radius) + 1.0, rb.global_position, (rb.global_position - at).normalized())


## Host: breaks it for everyone.
func break_prop(id: int, at := Vector3.INF, dir := Vector3.ZERO) -> void:
	var p: Dictionary = props.get(id, {})
	if p.is_empty() or p.broken or not Net.is_host():
		return
	var rb: RigidBody3D = p.body
	var where := rb.global_position
	var b := StreamPeerBuffer.new()
	b.put_u16(id)
	for v in [where, dir]:
		b.put_float(v.x)
		b.put_float(v.y)
		b.put_float(v.z)
	if Net.is_online():
		Net.broadcast(MSG_BREAK, b.data_array)
	var d: Dictionary = KINDS[p.kind]
	_apply_break(id, where, dir)
	# What it does as it goes.
	if d.get("explosive", false):
		var big: bool = p.kind == "barrel"
		Blast.go(get_tree(), world, cars, where + Vector3(0, 0.3, 0), 4.0 if big else 3.0, 140.0 if big else 100.0, 9.0 if big else 7.0)
		if FireSystem.current:
			FireSystem.current.ignite(where, 1.8 if big else 1.2, 16.0 if big else 10.0)
	elif d.get("puffs", false):
		if FireSystem.current:
			FireSystem.current.extinguish(where, FireSystem.PUFF_RADIUS)
	elif p.burning and FireSystem.current:
		# What was burning leaves embers.
		FireSystem.current.ignite(where, 0.8, 6.0)


func _on_break(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var id := b.get_u16()
	var at := Vector3(b.get_float(), b.get_float(), b.get_float())
	var dir := Vector3(b.get_float(), b.get_float(), b.get_float())
	_apply_break(id, at, dir)


## Everyone: the prop goes, its pieces fly, and it sounds like what broke.
func _apply_break(id: int, at: Vector3, dir: Vector3) -> void:
	var p: Dictionary = props.get(id, {})
	if p.is_empty() or p.broken:
		return
	p.broken = true
	var rb: RigidBody3D = p.body
	var xf := rb.global_transform
	var lv := rb.linear_velocity
	var d: Dictionary = KINDS[p.kind]
	broke.emit(id, p.kind, at)
	var parent := get_parent() if get_parent() else self
	match d.surface:
		"glass":
			Sfx.glass_break(parent, at)
		"wood":
			Sfx.play(parent, "break_wood", at, 3.0 if d.mass < 15.0 else 6.0, 70.0, 0.08)
			if d.mass >= 15.0:
				Sfx.play(parent, "gun_thump", at, -4.0, 40.0, 0.15)
		"concrete":
			Sfx.play(parent, "break_concrete", at, 4.0, 70.0, 0.08)
		_:
			if not d.get("explosive", false):
				Sfx.play(parent, "break_metal", at, 3.0, 70.0, 0.08)
	if d.get("puffs", false):
		Sfx.play(parent, "gas_hiss", at, 2.0, 40.0, 0.06)
		Feel.cloud(parent, at, FireSystem.PUFF_RADIUS)
	_fragments(p.kind, xf, lv, dir)
	rb.queue_free()
	_targets.erase(id)


## Splinters, shards or bent bits: cosmetic, local, gone in a few seconds.
func _fragments(kind: String, xf: Transform3D, lv: Vector3, dir: Vector3) -> void:
	var d: Dictionary = KINDS[kind]
	if DisplayServer.get_name() == "headless" and not has_meta("fragments_in_headless"):
		return
	var parent := get_parent() if get_parent() else self
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(xf.origin)
	var parts: Array = d.parts
	var n := 3 if d.surface == "glass" else mini(parts.size() + 2, 8)
	for i in n:
		var part: Array = parts[i % parts.size()]
		var s: Vector3 = part[0]
		if s.x < 0.0:
			s = Vector3(-s.x * 1.4, s.y * 0.5, -s.x * 1.4)
		var piece := s * rng.randf_range(0.35, 0.7)
		if d.surface == "glass":
			piece = Vector3(0.04, 0.06, 0.01)
		var f := RigidBody3D.new()
		f.collision_layer = 0
		f.collision_mask = 1
		f.mass = maxf(0.2, d.mass / n)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = piece.max(Vector3.ONE * 0.02)
		cs.shape = box
		f.add_child(cs)
		f.add_child(_part_mesh(box.size, Vector3.ZERO, Color(part[2]).darkened(0.1 if d.surface == "wood" else 0.0)))
		parent.add_child(f)
		f.global_transform = Transform3D(xf.basis * Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * PI),
			xf * (part[1] as Vector3))
		f.linear_velocity = lv + dir * rng.randf_range(1.0, 4.0) + Vector3(rng.randf_range(-2, 2), rng.randf_range(1, 4), rng.randf_range(-2, 2))
		f.angular_velocity = Vector3(rng.randf_range(-9, 9), rng.randf_range(-9, 9), rng.randf_range(-9, 9))
		get_tree().create_timer(rng.randf_range(6.0, 10.0)).timeout.connect(f.queue_free)


# --- host: knocks and sync --------------------------------------------------------------

var _awake := {}    # host: prop id -> true while its body is awake


func _physics_process(delta: float) -> void:
	_clock += delta
	if not Net.is_host():
		_follow(delta)
		return
	# Hard knocks hurt: a chair thrown at a wall, a bottle dropped.
	for id in _awake.keys():
		var p: Dictionary = props.get(id, {})
		if p.is_empty() or p.broken or not is_instance_valid(p.body):
			_awake.erase(id)
			continue
		var rb: RigidBody3D = p.body
		if rb.sleeping or rb.freeze:
			_prev_v.erase(p.id)
			_awake.erase(id)
			continue
		var v := rb.linear_velocity
		var pv: Vector3 = _prev_v.get(p.id, v)
		_prev_v[p.id] = v
		var dv := (v - pv).length()
		var limit := 2.5 if p.kind == "bottle" else KNOCK_DV
		if dv > limit:
			damage_prop(p.id, (dv - limit) * (30.0 if p.kind == "bottle" else 9.0), rb.global_position, pv.normalized())
	_snap_t -= delta
	if _snap_t <= 0.0 and Net.is_online():
		_snap_t = SNAP_EVERY
		_send_snap()


func _send_snap() -> void:
	var b := StreamPeerBuffer.new()
	var n := 0
	b.put_u8(0)
	var due := []
	for p in props.values():
		if p.broken:
			continue
		var rb: RigidBody3D = p.body
		var last: float = _sent.get(p.id, -100.0)
		if not rb.sleeping or _clock - last > SLEEP_REFRESH:
			due.append(p)
	due.sort_custom(func(x, y): return float(_sent.get(x.id, -100.0)) < float(_sent.get(y.id, -100.0)))
	for p in due:
		if n >= MAX_PER_SNAP:
			break
		var rb: RigidBody3D = p.body
		b.put_u16(p.id)
		var o := rb.global_position
		b.put_16(clampi(roundi(o.x * POS_SCALE), -32768, 32767))
		b.put_16(clampi(roundi(o.y * POS_SCALE), -32768, 32767))
		b.put_16(clampi(roundi(o.z * POS_SCALE), -32768, 32767))
		var q := rb.global_transform.basis.get_rotation_quaternion().normalized()
		for c in [q.x, q.y, q.z, q.w]:
			b.put_16(int(c * 32767.0))
		_sent[p.id] = _clock
		n += 1
	if n == 0:
		return
	var data := b.data_array
	data[0] = n
	Net.broadcast(MSG_SNAP, data, Net.UNRELIABLE)


func _on_snap(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var n := b.get_u8()
	for i in n:
		var id := b.get_u16()
		var o := Vector3(b.get_16(), b.get_16(), b.get_16()) / POS_SCALE
		var q := Quaternion(b.get_16() / 32767.0, b.get_16() / 32767.0, b.get_16() / 32767.0, b.get_16() / 32767.0).normalized()
		if props.has(id) and not props[id].broken:
			_targets[id] = Transform3D(Basis(q), o)


func _follow(delta: float) -> void:
	var k := 1.0 - exp(-18.0 * delta)
	for id in _targets.keys():
		var rb := body(id)
		if rb == null:
			_targets.erase(id)
			continue
		var t: Transform3D = _targets[id]
		var cur := rb.global_transform
		if cur.origin.distance_to(t.origin) > 3.0:
			rb.global_transform = t
		else:
			rb.global_transform = Transform3D(Basis(cur.basis.get_rotation_quaternion().slerp(t.basis.get_rotation_quaternion(), k)), cur.origin.lerp(t.origin, k))
		if rb.global_transform.origin.distance_to(t.origin) < 0.002:
			_targets.erase(id)
