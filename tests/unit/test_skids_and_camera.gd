extends Node
## v0.12.0 driving and on-foot feel: skid marks, the car camera swinging back
## behind the car, walking as the default pace, the run's knees, footsteps.
var t


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _car() -> Car:
	ProtoWorld.ground(self, 400.0)
	var c := Car.new()
	c.position = Vector3(0, 1.0, -150)
	add_child(c)
	return c


func _marks() -> SkidMarks:
	var s := SkidMarks.for_tree(get_tree())
	await get_tree().process_frame
	return s


func test_tyre_slide() -> void:
	t.check(Car.tyre_slide(0.5, 0.3, 20.0, 0.0, false) < 0.05, "cruising: no slide")
	t.check(Car.tyre_slide(3.0, 1.0, 1.0, 0.0, false) == 0.0, "nearly stopped: no marks")
	t.check(Car.tyre_slide(0.9, 8.0, 10.0, 0.0, false) > 0.5, "sideways at speed: sliding")
	t.check(Car.tyre_slide(0.9, 0.0, 15.0, 1.0, false) >= 0.6, "stamp on the brakes: locked")
	t.check(Car.tyre_slide(0.9, 0.0, 10.0, 0.0, true) >= 0.8, "handbrake: rear locked")
	t.check(Car.tyre_slide(2.5, 0.5, 6.0, 0.0, false) > 0.9, "wheelspin past the grip: sliding")


func test_strips_follow_the_wheel() -> void:
	var s := await _marks()
	var n0 := s.laid
	for i in 20:
		s.wheel(12345, Vector3(i * 0.3, 0, 5), Vector3.UP, 1.0)
	t.check(s.laid - n0 == 19, "one strip per step once the tyre slides (%d)" % (s.laid - n0))
	s.wheel(12345, Vector3(50, 0, 5), Vector3.UP, 1.0)
	t.check(s.laid - n0 == 19, "a jump starts a new mark, no strip across it")
	s.wheel(12345, Vector3(50.5, 0, 5), Vector3.UP, 0.0)
	s.wheel(12345, Vector3(51.0, 0, 5), Vector3.UP, 1.0)
	t.check(s.laid - n0 == 19, "gripping again ends the mark")
	var xf := SkidMarks.strip_transform(Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3.UP)
	t.near(xf.origin.y, SkidMarks.LIFT, 0.001, "lies just above the road")
	t.near(xf.basis.z.length(), 1.04, 0.01, "as long as the step (plus a little overlap)")
	t.near(xf.basis.x.length(), SkidMarks.WIDTH, 0.001, "a tread wide")


func test_handbrake_turn_leaves_marks_cruising_does_not() -> void:
	var s := await _marks()
	var c := _car()
	await _frames(30)
	c.throttle = 1.0
	var n0 := s.laid
	await _frames(120)
	c.throttle = 0.4
	await _frames(60)
	var cruise := s.laid - n0
	c.steer = 1.0
	c.handbrake = true
	await _frames(60)
	var turn := s.laid - n0 - cruise
	print("    strips: %d cruising, %d in a handbrake turn" % [cruise, turn])
	t.check(turn > 20, "handbrake turn lays rubber")
	c.queue_free()
	await _frames(2)


func test_hard_braking_leaves_marks() -> void:
	var s := await _marks()
	var c := _car()
	await _frames(30)
	c.throttle = 1.0
	await _frames(150)
	c.throttle = 0.0
	c.brake = 1.0
	var v0 := c.linear_velocity.length()
	var n1 := s.laid
	await _frames(30)
	print("    strips braking hard from %.0f m/s: %d" % [v0, s.laid - n1])
	t.check(s.laid - n1 > 20, "a stamp on the brakes lays two black lines per side")
	c.queue_free()
	await _frames(2)


func test_car_camera_recentres_the_short_way() -> void:
	t.near(IsoCamera.recentred_yaw(170.0, -170.0, 10.0), 190.0, 0.5, "goes the short way round past 180")
	var y := 0.0
	for i in 120:
		y = IsoCamera.recentred_yaw(y, 90.0, 1.0 / 60.0)
	t.check(y > 80.0 and y <= 90.0, "most of the way round in two seconds (%.1f)" % y)
	var y2 := IsoCamera.recentred_yaw(0.0, 90.0, 1.0 / 60.0, 0.0)
	t.near(y2, 0.0, 0.001, "eases in from standing still")


func test_walking_is_the_default() -> void:
	t.check(PlayerInput.walk_on, "on foot the officer walks unless switched to run")


func test_run_knees_point_forward() -> void:
	var m: Node = OfficerRig.MODEL.instantiate()
	add_child(m)   # (bone global poses update only in the tree)
	var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	var lib := OfficerClips.library(ap, sk)
	t.check(lib.has_animation("run") and lib.has_animation("hk_run"), "the fixed run replaces the old one")
	t.check(_knees_out(lib.get_animation("hk_run"), sk, ap) > 0.1, "(the old run did splay them: the check works)")
	t.check(_knees_out(lib.get_animation("run"), sk, ap) < 0.05, "knees stay over the feet when running")
	m.queue_free()


## How far (m) a clip's knees get outside their hip-ankle lines.
func _knees_out(a: Animation, sk: Skeleton3D, ap: AnimationPlayer) -> float:
	var tracks := {}
	for i in a.get_track_count():
		var bone := String(a.track_get_path(i).get_concatenated_subnames())
		var bi := sk.find_bone(bone)
		if bi >= 0:
			tracks[i] = bi
	var worst := 0.0
	var k := 0.0
	while k < a.length:
		for i in tracks:
			if a.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(tracks[i], a.rotation_track_interpolate(i, k))
			elif a.track_get_type(i) == Animation.TYPE_POSITION_3D:
				sk.set_bone_pose_position(tracks[i], a.position_track_interpolate(i, k))
		var lat := (sk.get_bone_global_pose(sk.find_bone("thigh.L")).origin - sk.get_bone_global_pose(sk.find_bone("thigh.R")).origin).normalized()
		for side in [["L", 1.0], ["R", -1.0]]:
			var hip := sk.get_bone_global_pose(sk.find_bone("thigh." + side[0])).origin
			var knee := sk.get_bone_global_pose(sk.find_bone("shin." + side[0])).origin
			var ank := sk.get_bone_global_pose(sk.find_bone("foot." + side[0])).origin
			var axis := (ank - hip).normalized()
			var o := (knee - hip) - axis * (knee - hip).dot(axis)
			worst = maxf(worst, o.dot(lat * side[1]))
		k += 1.0 / 30.0
	print("    %d tracks posed; knee at most %.1f cm outside the hip-ankle line" % [tracks.size(), worst * 100.0])
	return worst


func test_footsteps_quieter_with_metal() -> void:
	t.check(GameSounds.STEP_RUN_DB <= -12.0 and GameSounds.STEP_WALK_DB <= -18.0, "footsteps sit well under the action")
	t.check(Sfx.variants("step_metal") == 4, "boot steps on metal (car roofs)")
