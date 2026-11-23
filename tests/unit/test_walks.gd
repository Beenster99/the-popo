extends Node
## The mocap walk mode: 100STYLE walk loops merged into the officer's clips,
## the tactical walk with the gun out, the controller's L3 tap, and slower
## backing off / sidestepping while aiming.
var t


func test_walk_clips_loaded() -> void:
	var m: Node = OfficerRig.MODEL.instantiate()
	var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	var lib := OfficerClips.library(ap, sk)
	for n in ["walk", "walk_ready", "walk_back", "walk_left", "walk_right"]:
		t.check(lib.has_animation(n), n + " loaded")
		t.check(n in OfficerClips.mocap_clips, n + " is mocap")
		if lib.has_animation(n):
			var a := lib.get_animation(n)
			t.check(a.length > 0.8 and a.length < 1.6, "%s is one gait cycle (%.2f s)" % [n, a.length])
			t.check(a.get_track_count() >= 17, n + " drives the body")
	t.check(lib.has_animation("hk_walk"), "hand-keyed walk kept")
	m.free()


func test_rig_picks_tactical_walk() -> void:
	ProtoWorld.ground(self, 40.0)
	var o := Officer.new()
	add_child(o)
	await get_tree().process_frame
	var r: OfficerRig = o.rig
	t.check(r != null and r._tac_ok, "tactical walks in the tree")
	o.velocity = Vector3(0, 0, 1.2)
	o.holstered = true
	t.check(r._lower_state(o) == "walk", "holstered: relaxed walk")
	o.holstered = false
	t.check(r._lower_state(o) == "walk_ready", "gun out: tactical walk")
	o.velocity = Vector3(0, 0, 3.5)
	t.check(r._lower_state(o) == "run", "running pace still runs")


func test_tactical_direction() -> void:
	var n := Node3D.new()
	add_child(n)
	# Facing +Z (rotation 0): +Z is forward, +X is the officer's left.
	t.check(OfficerRig.tac_dir(n, Vector3(0, 0, 1)).is_equal_approx(Vector2(0, 1)), "forward")
	t.check(OfficerRig.tac_dir(n, Vector3(0, 0, -1)).is_equal_approx(Vector2(0, -1)), "back")
	t.check(OfficerRig.tac_dir(n, Vector3(1, 0, 0)).is_equal_approx(Vector2(-1, 0)), "left")
	t.check(OfficerRig.tac_dir(n, Vector3(-1, 0, 0)).is_equal_approx(Vector2(1, 0)), "right")
	t.check(is_equal_approx(OfficerRig.tac_clip_speed(Vector2(0, 1)), OfficerRig.TAC_FWD_SPEED), "forward clip speed")
	t.check(is_equal_approx(OfficerRig.tac_clip_speed(Vector2(0, -1)), OfficerRig.TAC_BACK_SPEED), "back clip speed")
	n.free()


func test_pad_l3_tap_toggles_walk() -> void:
	var P := PlayerInput
	t.check(not P.pad_walk_tap(true, 5.0), "nothing on the press")
	t.check(P.pad_walk_tap(false, 5.1), "quick tap switches walk mode")
	P.pad_walk_tap(true, 6.0)
	t.check(not P.pad_walk_tap(true, 6.5), "held: still nothing")
	t.check(not P.pad_walk_tap(false, 6.6), "a long hold is sprint, not a toggle")
	t.check(not P.pad_walk_tap(false, 7.0), "nothing when it is not pressed")


func test_aiming_backs_off_slower() -> void:
	var o := Officer.new()
	add_child(o)
	o.rotation.y = 0.0
	t.check(is_equal_approx(o.strafe_scale(Vector3(0, 0, 1)), 1.0), "forward full pace")
	t.check(is_equal_approx(o.strafe_scale(Vector3(1, 0, 0)), Officer.STRAFE_SIDE), "sidestep slower")
	t.check(is_equal_approx(o.strafe_scale(Vector3(0, 0, -1)), Officer.STRAFE_BACK), "backing off slowest")
	o.free()
