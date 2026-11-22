class_name BuildingLayout
extends RefCounted
## Test buildings assembled from kit pieces.

const STOREY := 3.25  # 3 m walls plus a 0.25 m slab
## Side-by-side pieces keep a few centimetres apart. Faces that touch exactly
## wedge a falling piece in place by friction, which real rubble would not.
const GAP := 0.03


## Two-bay, two-storey shop: 8 m x 4 m. Side walls and the middle wall carry
## the floors. The front (shop windows) and back are facades that only hold
## up the facade above them. Knock out a side wall on the ground floor and
## the floor above it loses one end of its span and drops.
static func shop(world: DestructionWorld, origin: Vector3, storeys := 2) -> void:
	var r90 := Basis(Vector3.UP, PI / 2)
	for s in storeys:
		var y := s * STOREY
		var o := origin + Vector3(0, y, 0)
		world.add_piece("wall", Transform3D(r90, o + Vector3(0, 0, 2)))
		world.add_piece("wall", Transform3D(r90, o + Vector3(8, 0, 2)))
		world.add_piece("wall_door" if s == 0 else "wall", Transform3D(r90, o + Vector3(4, 0, 2)))
		# Facades stack directly on each other (3 m a storey) in front of the
		# slab edges, so each one rests on the facade below.
		var f := origin + Vector3(0, s * 3.0, 0)
		var front := "wall_door" if s == 0 else "wall_window"
		world.add_piece(front, Transform3D(Basis(), f + Vector3(2, 0, -0.125 - GAP)), false)
		world.add_piece("wall_window", Transform3D(Basis(), f + Vector3(6, 0, -0.125 - GAP)), false)
		world.add_piece("wall", Transform3D(Basis(), f + Vector3(2, 0, 4.125 + GAP)), false)
		world.add_piece("wall_window", Transform3D(Basis(), f + Vector3(6, 0, 4.125 + GAP)), false)
		world.add_piece("slab", Transform3D(Basis(), o + Vector3(2 - GAP * 0.5, STOREY, 2)))
		world.add_piece("slab", Transform3D(Basis(), o + Vector3(6 + GAP * 0.5, STOREY, 2)))


## A row of free-standing walls, for the stress test.
static func wall_row(world: DestructionWorld, origin: Vector3, count: int) -> Array:
	var ids: Array = []
	for i in count:
		ids.append(world.add_piece("wall", Transform3D(Basis(), origin + Vector3(i * 4.5, 0, 0))))
	return ids
