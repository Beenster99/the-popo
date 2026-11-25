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


## v0.26 (beenster: "leans out to the right of a corner, but not the left"):
## aiming from the left end of a wall, the camera swaps to the left shoulder
## so the centre dot looks past the corner, not at the wall; at the right end
## it stays on the right shoulder.
func test_peek_left_swaps_shoulder() -> void:
	ProtoWorld.ground(self, 60.0)
	for side: float in [-1.0, 1.0]:
		# side -1: the wall's left end (+X, looking +Z); side 1: its right end (-X).
		var end_x := 12.0 * side
		var wall := ProtoWorld.block(self, Vector3(3, 2.2, 0.3), Vector3(end_x + 1.5 * side, 1.1, 1.0), Color.GRAY)
		var o := Officer.new()
		o.holstered = false
		o.position = Vector3(end_x + 0.1 * side, 0.05, 0)
		add_child(o)
		var cam := IsoCamera.new()
		add_child(cam)
		cam.target = o
		cam.tp_pitch = 0.0
		await _frames(5)
		o.sim_step({"move": Vector2.ZERO, "buttons": PlayerInput.COVER, "aim_yaw": 0.0, "aim_point": Vector3.ZERO}, 1.0 / 60.0)
		await _frames(5)
		t.check(o.state == Officer.S.COVER, "in cover (side %d)" % side)
		var cmd := {}
		for i in 60:
			cmd = PlayerInput.sample(cam, o)
			cmd.buttons = PlayerInput.AIM
			cmd.move = Vector2.ZERO
			o.sim_step(cmd, 1.0 / 60.0)
			await get_tree().physics_frame
		var cam_x := cam.camera.global_position.x - o.global_position.x
		var p: Vector3 = cmd.aim_point
		print("    side %d: camera %.2f m to the side, centre dot on %s" % [side, cam_x, p])
		t.check(signf(cam_x) == -side, "camera over the %s shoulder: %.2f" % ["left" if side < 0 else "right", cam_x])
		t.check(p.z > 1.3, "the centre dot looks past the corner, not at the wall (side %d): %s" % [side, p])
		cam.queue_free()
		o.queue_free()
		wall.queue_free()
