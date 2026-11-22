class_name RoofFader
extends Node
## Fades the roof and upper floors of a building while the watched officer is
## inside it, so the isometric camera can see in. Faded pieces keep casting
## their shadows (through a shadow-only copy), so interiors stay shaded.

## Node3D whose position decides (usually the local player's officer).
var watch: Node3D
## [{bounds: AABB, meshes: Array[MeshInstance3D]}]
var buildings: Array = []
var fade_speed := 4.0
var _state := {}    # MeshInstance3D -> current fade
var _shadow := {}   # MeshInstance3D -> shadow-only copy


## Registers every piece of a DestructionWorld that lies inside bounds.
func add_building_from_world(world: DestructionWorld, bounds: AABB) -> void:
	var meshes: Array = []
	for p in world.pieces.values():
		if bounds.intersects(p.aabb):
			for mi in p.node.find_children("*", "MeshInstance3D", false, false):
				mi.set_meta("bottom_y", (p.aabb as AABB).position.y)
				meshes.append(mi)
	buildings.append({"bounds": bounds, "meshes": meshes})


func add_building(bounds: AABB, meshes: Array) -> void:
	for mi in meshes:
		if not mi.has_meta("bottom_y"):
			mi.set_meta("bottom_y", mi.get_aabb().position.y + mi.global_position.y)
	buildings.append({"bounds": bounds, "meshes": meshes})


func _process(delta: float) -> void:
	if watch == null or not is_instance_valid(watch):
		return
	var p := watch.global_position
	for b in buildings:
		var inside: bool = (b.bounds as AABB).grow(-0.1).has_point(p + Vector3(0, 0.5, 0))
		for m in b.meshes:
			# Pieces that broke or fell are gone; skip them (no typed loop
			# variable, which would choke on a freed mesh).
			if not is_instance_valid(m):
				continue
			var mi := m as MeshInstance3D
			# Hide everything that starts above the officer's head.
			var target := 0.0 if inside and float(mi.get_meta("bottom_y")) > p.y + 2.0 else 1.0
			var cur: float = _state.get(mi, 1.0)
			if is_equal_approx(cur, target):
				continue
			cur = move_toward(cur, target, delta * fade_speed)
			_state[mi] = cur
			mi.set_instance_shader_parameter("fade", cur)
			_set_shadow_copy(mi, cur < 0.999)


func _set_shadow_copy(mi: MeshInstance3D, on: bool) -> void:
	if on and not _shadow.has(mi):
		var s := MeshInstance3D.new()
		s.mesh = mi.mesh
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mi.add_child(s)
		_shadow[mi] = s
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif not on and _shadow.has(mi):
		_shadow[mi].queue_free()
		_shadow.erase(mi)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func faded_count() -> int:
	var n := 0
	for v in _state.values():
		if v < 0.5:
			n += 1
	return n
