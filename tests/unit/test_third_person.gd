extends Node
var t


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## The game's only view (v0.2.11): the camera goes behind the officer and
## the aim point is whatever the centre of the screen is on.
func test_third_person_view() -> void:
	ProtoWorld.ground(self, 40.0)
	var wall := ProtoWorld.block(self, Vector3(6, 4, 0.4), Vector3(0, 2, 8), Color.GRAY)
	var o := Officer.new()
	o.position = Vector3(0, 0.05, 0)
	add_child(o)
	var cam := IsoCamera.new()
	add_child(cam)
	cam.target = o
	await _frames(3)
	await _frames(20)
	t.check(cam.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "perspective in third person")
	var behind := cam.camera.global_position - o.global_position
	t.check(behind.z < -1.0 and behind.length() < 5.0, "behind the officer: %s" % behind)
	cam.tp_pitch = 0.0
	await _frames(3)
	var cmd := PlayerInput.sample(cam, o)
	var p: Vector3 = cmd.aim_point
	t.check(absf(p.z - 7.8) < 0.1 and p.y > 1.0, "aims at the wall ahead, at eye height: %s" % p)
	t.check(absf(angle_difference(cmd.aim_yaw, 0.0)) < 0.2, "and turns the officer that way")
	t.check(cam.view_relative(Vector2(0, -1)).z > 0.9, "forward is away from the camera")
	t.check(not InputMap.has_action("toggle_view"), "and there is no switching to isometric")
	wall.queue_free()
