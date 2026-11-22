class_name RoofFader
extends Node
## Cutaway view for the isometric camera. Anything over the watched officer's
## head or between them and the camera fades out, inside or out (walls on
## their floor turn see-through instead). While they are inside
## a building, everything that would hide any part of the floor they stand
## on goes: the floors and roof above fade out, and the walls on the camera
## side (theirs or a neighbour's) turn see-through, so the room outline and
## its doorways still show.
## Interior walls and the far walls stay, so rooms still read. It follows the
## camera, so it works at any rotation. Faded pieces keep casting their
## shadows (through a shadow-only copy), so interiors stay shaded.

## Node3D whose position decides (usually the local player's officer).
var watch: Node3D
## [{bounds: AABB, meshes: Array[MeshInstance3D]}]
var buildings: Array = []
var fade_speed := 5.0
## Walls and pieces whose top is this far above the floor count as in the way.
const BLOCK_HEIGHT := 1.0
## Faded meshes, and every piece mesh that may need fading.
var _state := {}    # MeshInstance3D -> current fade
var _shadow := {}   # MeshInstance3D -> shadow-only copy
var _all: Array = []          # every registered mesh (all buildings and street)
var _seen := {}               # MeshInstance3D -> true (no duplicates)
## How much of a see-through wall still shows (screen-door dither).
const GHOST := 0.3


## Registers every piece of a DestructionWorld that lies inside bounds as one
## building, and every piece of the world as something that can be in the way.
func add_building_from_world(world: DestructionWorld, bounds: AABB) -> void:
	var meshes: Array = []
	for p in world.pieces.values():
		var inside: bool = bounds.intersects(p.aabb)
		for mi in p.node.find_children("*", "MeshInstance3D", false, false):
			_register(mi, p.aabb, String(p.kind))
			if inside:
				meshes.append(mi)
	buildings.append({"bounds": bounds, "meshes": meshes})


func add_building(bounds: AABB, meshes: Array) -> void:
	for mi in meshes:
		var box: AABB = mi.global_transform * mi.get_aabb()
		_register(mi, box, "")
	buildings.append({"bounds": bounds, "meshes": meshes})


func _register(mi: MeshInstance3D, box: AABB, kind: String) -> void:
	if _seen.has(mi):
		return
	_seen[mi] = true
	mi.set_meta("bottom_y", box.position.y)
	mi.set_meta("box", box)
	mi.set_meta("kind", kind)
	_all.append(mi)


func _process(delta: float) -> void:
	if watch == null or not is_instance_valid(watch):
		return
	var p := watch.global_position
	var home: Dictionary = {}
	for b in buildings:
		if (b.bounds as AABB).grow(-0.1).has_point(p + Vector3(0, 0.5, 0)):
			home = b
			break
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	var view := -cam.global_basis.z if cam else Vector3(-0.5, -0.7, -0.5).normalized()
	var floor_y := p.y
	var foot := Rect2()
	if not home.is_empty():
		var bb: AABB = home.bounds
		foot = Rect2(bb.position.x, bb.position.z, bb.size.x, bb.size.z).grow(-0.35)
	var home_meshes: Dictionary = {}
	if not home.is_empty():
		for m in home.meshes:
			home_meshes[m] = true
	var cutaway: bool = Settings.values.get("cutaway", true)
	var eye := -view
	var probes := [p + Vector3(0, 0.3, 0), p + Vector3(0, 1.0, 0), p + Vector3(0, 1.75, 0)]
	for m in _all:
		# Pieces that broke or fell are gone; skip them (no typed loop
		# variable, which would choke on a freed mesh).
		if not is_instance_valid(m):
			continue
		var mi := m as MeshInstance3D
		var target := 1.0
		var kind: String = mi.get_meta("kind")
		var bottom: float = mi.get_meta("bottom_y")
		if cutaway and not home.is_empty():
			if home_meshes.has(mi) and bottom > floor_y + 2.0:
				target = 0.0   # the floors and roof above
			elif _in_the_way(mi, floor_y, foot, view, home_meshes.has(mi)):
				# Walls standing on this floor turn see-through, so the room
				# and its doorways still show; anything else in the way goes.
				target = GHOST if _on_floor(kind, bottom, floor_y) else 0.0
		if cutaway and target > GHOST and _hides(mi, p, probes, eye):
			target = GHOST if _on_floor(kind, bottom, floor_y) else 0.0
		_fade(mi, target, delta)
		# Hidden pieces are not aimed at (the reticle looks through them).
		var body := mi.get_parent()
		if body is CollisionObject3D:
			body.set_meta("see_through", target < GHOST)


## A wall, door, window or pillar standing on the officer's floor.
static func _on_floor(kind: String, bottom: float, floor_y: float) -> bool:
	return absf(bottom - floor_y) < 0.6 and _is_wall(kind)


static func _is_wall(kind: String) -> bool:
	for k in ["wall", "int_wall", "column", "glass", "door", "garage"]:
		if kind.begins_with(k):
			return true
	return false


## Is this piece over the officer's head, or between them and the camera?
func _hides(mi: MeshInstance3D, p: Vector3, probes: Array, eye: Vector3) -> bool:
	var box: AABB = mi.get_meta("box")
	if box.end.y < p.y + 0.4:
		return false   # the ground and floor underfoot
	var c := box.get_center()
	if absf(c.x - p.x) > 40.0 or absf(c.z - p.z) > 40.0:
		return false
	# Overhead: an upper floor, roof, awning or balcony right above them.
	if box.position.y > p.y + 1.95:
		var r := Rect2(box.position.x, box.position.z, box.size.x, box.size.z).grow(0.6)
		if r.has_point(Vector2(p.x, p.z)):
			return true
	var grown := box.grow(0.15)
	for q in probes:
		if grown.intersects_segment(q, q + eye * 45.0):
			return true
	return false


## Does this piece hide part of the floor (foot, at floor_y) from a camera
## looking along view? Its box is swept down the view onto the floor.
func _in_the_way(mi: MeshInstance3D, floor_y: float, foot: Rect2, view: Vector3, own: bool) -> bool:
	var box: AABB = mi.get_meta("box")
	if box.end.y < floor_y + BLOCK_HEIGHT:
		return false
	var kind: String = mi.get_meta("kind")
	if own and (kind.begins_with("int_") or kind == "stairs" or kind.begins_with("slab")):
		return false   # rooms and stairs inside stay
	if own and kind.begins_with("column") and foot.grow(-0.3).has_point(Vector2(box.get_center().x, box.get_center().z)):
		return false   # columns inside the room stay; corner pillars go with the walls
	if view.y > -0.05:
		return false
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var c := box.get_endpoint(i)
		var h := maxf(c.y - floor_y, 0.0)
		var t := h / -view.y
		var q := Vector2(c.x + view.x * t, c.z + view.z * t)
		lo = lo.min(q)
		hi = hi.max(q)
	# High points hide the floor behind them (away from the camera), so a
	# near wall sweeps over the room and a far wall sweeps away from it.
	return Rect2(lo, hi - lo).intersects(foot)


func _fade(mi: MeshInstance3D, target: float, delta: float) -> void:
	var cur: float = _state.get(mi, 1.0)
	if is_equal_approx(cur, target):
		_set_shadow_copy(mi, cur < 0.999)
		return
	cur = move_toward(cur, target, delta * fade_speed)
	_state[mi] = cur
	mi.set_instance_shader_parameter("fade", cur)
	# The dither never hides every pixel: fully faded pieces are switched off.
	mi.visible = cur > 0.001
	_set_shadow_copy(mi, cur < 0.999)


func _set_shadow_copy(mi: MeshInstance3D, on: bool) -> void:
	if on and not _shadow.has(mi):
		var s := MeshInstance3D.new()
		s.mesh = mi.mesh
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		# A sibling, not a child, so it still casts while the piece is hidden.
		mi.get_parent().add_child(s)
		s.transform = mi.transform
		_shadow[mi] = s
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif not on and _shadow.has(mi):
		if is_instance_valid(_shadow[mi]):
			_shadow[mi].queue_free()
		_shadow.erase(mi)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func faded_count() -> int:
	var n := 0
	for v in _state.values():
		if v < 0.5:
			n += 1
	return n
