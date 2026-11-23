class_name GrappleRope
extends Node3D
## v0.7.0: the grapple line and hook you can see, and their sounds, for one
## officer. Reads the officer's state each frame (the same on every machine).

var officer: Officer
var _line: MeshInstance3D
var _hook: MeshInstance3D
var _was := -1
var _hit_played := false
var _slide_t := 0.0
var _last_y := 0.0


func _ready() -> void:
	top_level = true
	var m := Cel.material(Color("2a2c30"), false)
	_line = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.012
	c.bottom_radius = 0.012
	c.height = 1.0
	c.radial_segments = 5
	c.rings = 1
	_line.mesh = c
	_line.material_override = m
	_line.visible = false
	add_child(_line)
	_hook = MeshInstance3D.new()
	var hm := Cel.material(Color("8a8d92"))
	var hb := BoxMesh.new()
	hb.size = Vector3(0.28, 0.08, 0.28)
	_hook.mesh = hb
	_hook.material_override = hm
	_hook.visible = false
	add_child(_hook)


func _process(delta: float) -> void:
	if officer == null or not is_instance_valid(officer):
		return
	var st := int(officer.state)
	if st != _was:
		if st == Officer.S.GRAPPLE:
			Sfx.play(officer, "grapple_fire", officer.global_position + Vector3(0, 1.3, 0), 2.0, 60.0)
			_hit_played = false
		elif st == Officer.S.ROPE:
			Sfx.play(officer, "grapple_hit", officer._cover_anchor, -6.0, 40.0)
		_was = st
	if st == Officer.S.GRAPPLE and not _hit_played and officer.state_t >= Officer.GRAPPLE_FLY:
		_hit_played = true
		Sfx.play(officer, "grapple_hit", officer._cover_anchor, 2.0, 70.0)
	if st == Officer.S.ROPE:
		var vy := (officer.global_position.y - _last_y) / maxf(delta, 0.001)
		_slide_t -= delta
		if vy < -1.5 and _slide_t <= 0.0:
			_slide_t = 1.3
			Sfx.play(officer, "rope_slide", officer.global_position + Vector3(0, 1.0, 0), -2.0, 35.0)
	_last_y = officer.global_position.y
	var pts: Array = officer.rope_line()
	_line.visible = pts.size() == 2
	_hook.visible = _line.visible
	if not _line.visible:
		return
	var a: Vector3 = pts[0]
	var b: Vector3 = pts[1]
	var len_ := a.distance_to(b)
	if len_ < 0.05:
		_line.visible = false
		return
	var dir := (b - a) / len_
	var side := dir.cross(Vector3.RIGHT if absf(dir.y) > 0.9 else Vector3.UP).normalized()
	var basis := Basis(side, dir, side.cross(dir)).orthonormalized()
	_line.global_transform = Transform3D(basis.scaled(Vector3(1, len_, 1)), (a + b) * 0.5)
	_hook.global_position = a
