extends Node
var t


func _officer(pos := Vector3.ZERO) -> Officer:
	ProtoWorld.ground(self, 80.0)
	var o := Officer.new()
	o.position = pos
	add_child(o)
	return o


func _run(o: Officer, cmd: Dictionary, frames: int) -> void:
	for i in frames:
		o.sim_step(cmd, 1.0 / 60.0)
		await get_tree().physics_frame


func _cmd(move := Vector2.ZERO, buttons := 0) -> Dictionary:
	return {"move": move, "buttons": buttons, "aim_yaw": 0.0}


func test_clips_merge_mocap_and_hand_keys() -> void:
	var o := _officer()
	await get_tree().process_frame
	var lib := o.rig.anim_player.get_animation_library("")
	for n in ["idle", "walk", "run", "roll", "mantle", "climb", "slide", "crouch_walk", "crawl", "peek", "aim_hold", "punch", "kick"]:
		t.check(lib.has_animation(n), "clip " + n)
	print("    mocap clips: ", OfficerClips.mocap_clips)
	t.check(OfficerClips.mocap_clips.size() == 5, "five mocap clips merged")
	var roll_end := OfficerClips.root_offset("roll", OfficerClips.clip_length("roll"))
	print("    roll travel %s, mantle travel %s" % [roll_end, OfficerClips.root_offset("mantle", 99.0)])
	t.check(roll_end.z > 1.0, "roll travels forward (+Z): %s" % roll_end)


func test_runs_and_sprints() -> void:
	var o := _officer()
	await _run(o, _cmd(Vector2(0, 1)), 60)
	t.near(Vector2(o.velocity.x, o.velocity.z).length(), Officer.RUN, 0.2, "run speed")
	await _run(o, _cmd(Vector2(0, 1), PlayerInput.SPRINT), 30)
	t.near(Vector2(o.velocity.x, o.velocity.z).length(), Officer.SPRINT, 0.2, "sprint speed")


func test_vaults_a_low_wall() -> void:
	var o := _officer()
	ProtoWorld.block(self, Vector3(3, 1.0, 0.3), Vector3(0, 0.5, 1.2), Color.GRAY)
	await _run(o, _cmd(Vector2(0, 1)), 10)
	await _run(o, _cmd(Vector2(0, 1), PlayerInput.JUMP), 1)
	t.check(o.state == Officer.S.VAULT, "vault started, state %s" % Officer.S.keys()[o.state])
	await _run(o, _cmd(Vector2(0, 1)), 150)
	t.check(o.global_position.z > 1.5, "landed past the wall, z=%f" % o.global_position.z)
	t.check(o.global_position.y < 0.3, "on the ground, y=%f" % o.global_position.y)


func test_climbs_a_two_metre_ledge() -> void:
	var o := _officer()
	ProtoWorld.block(self, Vector3(3, 2.0, 3), Vector3(0, 1.0, 2.2), Color.GRAY)
	await _run(o, _cmd(Vector2(0, 1)), 8)
	await _run(o, _cmd(Vector2(0, 1), PlayerInput.JUMP), 1)
	t.check(o.state == Officer.S.CLIMB, "climb started, state %s" % Officer.S.keys()[o.state])
	await _run(o, _cmd(), 160)
	t.check(o.global_position.y > 1.9, "on top, y=%f" % o.global_position.y)
	t.check(o.state == Officer.S.MOVE, "standing again")


func test_roll_slide_prone_and_cover() -> void:
	var o := _officer()
	await _run(o, _cmd(Vector2(0, 1)), 30)
	var z0 := o.global_position.z
	await _run(o, _cmd(Vector2(0, 1), PlayerInput.DIVE), 1)
	t.check(o.state == Officer.S.ROLL, "rolling")
	await _run(o, _cmd(Vector2(0, 1)), 140)
	t.check(o.state != Officer.S.ROLL and o.global_position.z - z0 > 2.0, "rolled forward %f m" % (o.global_position.z - z0))
	await _run(o, _cmd(Vector2(0, 1), PlayerInput.SPRINT), 40)
	await _run(o, _cmd(Vector2(0, 1), PlayerInput.SPRINT | PlayerInput.DIVE), 1)
	t.check(o.state == Officer.S.SLIDE, "sliding")
	await _run(o, _cmd(), 70)
	t.check(o.state == Officer.S.CROUCH, "slide ends crouched")
	await _run(o, _cmd(Vector2.ZERO, PlayerInput.PRONE), 1)
	t.check(o.state == Officer.S.PRONE, "prone")
	await _run(o, _cmd(), 2)
	await _run(o, _cmd(Vector2.ZERO, PlayerInput.PRONE), 1)
	ProtoWorld.block(self, Vector3(4, 2, 0.3), o.global_position + Vector3(0, 1, 0.9), Color.GRAY)
	await _run(o, _cmd(), 2)
	await _run(o, _cmd(Vector2.ZERO, PlayerInput.COVER), 1)
	t.check(o.state == Officer.S.COVER, "in cover, state %s" % Officer.S.keys()[o.state])


func test_state_round_trips_for_the_network() -> void:
	var o := _officer()
	await _run(o, _cmd(Vector2(1, 0)), 20)
	var b := StreamPeerBuffer.new()
	o.encode_state(b)
	b.seek(0)
	var s := o.decode_state(b)
	t.check(s.pos.distance_to(o.global_position) < 0.001 and s.state == o.state, "decode matches")


func test_fires_from_the_barrel_at_the_aim_point() -> void:
	var o := _officer()
	var shots: Array = []
	o.fired.connect(func(origin, dir, _alt): shots.append([origin, dir]))
	var target := Vector3(1.0, 0.4, 6.0)  # low and a little to the side
	var cmd := {"move": Vector2.ZERO, "buttons": PlayerInput.AIM, "aim_yaw": atan2(target.x, target.z), "aim_point": target}
	await _run(o, cmd, 40)
	cmd.buttons = PlayerInput.AIM | PlayerInput.FIRE
	await _run(o, cmd, 2)
	t.check(shots.size() >= 1, "fired")
	if shots.is_empty():
		return
	var origin: Vector3 = shots[0][0]
	var dir: Vector3 = shots[0][1]
	var hand := o.rig.skeleton.global_transform * o.rig.skeleton.get_bone_global_pose(o.rig.skeleton.find_bone("hand.R")).origin
	print("    muzzle %s, hand %s, dir %s" % [origin, hand, dir])
	t.check(origin.distance_to(hand) < 0.35, "shot starts at the gun in the hand")
	t.check(origin.y > 0.9 and origin.y < 1.7, "muzzle at arm height: %f" % origin.y)
	t.check(dir.dot((target - origin).normalized()) > 0.99, "shot heads for the aim point")


func test_feet_step_round_instead_of_twisting() -> void:
	var o := _officer()
	var cmd := {"move": Vector2.ZERO, "buttons": PlayerInput.AIM, "aim_yaw": 0.3, "aim_point": Vector3(sin(0.3), 1.3, cos(0.3)) * 5.0}
	await _run(o, cmd, 20)
	t.check(not o.turning and absf(o.rotation.y) < 0.05, "small aim change: upper body only")
	cmd.aim_yaw = 2.0
	await _run(o, cmd, 3)
	t.check(o.turning, "big aim change: turning on the spot")
	t.check(o.rig._lower_state(o) == "walk", "legs step while turning")
	await _run(o, cmd, 40)
	t.check(absf(angle_difference(o.rotation.y, 2.0)) < 0.15, "ends facing the aim: %f" % o.rotation.y)
	t.check(not o.turning, "stops turning")


## The model must not hang in the air or drop when a climb ends.
func test_climb_ends_without_a_drop() -> void:
	var o := _officer()
	ProtoWorld.block(self, Vector3(3, 2.0, 3), Vector3(0, 1.0, 2.2), Color.GRAY)
	await _run(o, _cmd(Vector2(0, 1)), 8)
	await _run(o, _cmd(Vector2(0, 1), PlayerInput.JUMP), 1)
	var sk := o.rig.skeleton
	var head := sk.find_bone("head_2")
	var worst_above := -9.0
	var worst_step := 0.0
	var prev := -1.0
	var ended := -1
	for i in 200:
		await _run(o, _cmd(), 1)
		await get_tree().process_frame
		var y := (sk.global_transform * sk.get_bone_global_pose(head)).origin.y
		if prev >= 0.0:
			worst_step = maxf(worst_step, absf(y - prev))
		prev = y
		if ended < 0 and o.state != Officer.S.CLIMB:
			ended = i
		if ended >= 0:
			worst_above = maxf(worst_above, y - o.global_position.y)
	print("    head above feet after the climb: worst %.2f m, worst frame step %.2f m" % [worst_above, worst_step])
	t.check(worst_above < 2.0, "head never far above the officer after climbing: %.2f" % worst_above)
	t.check(worst_step < 0.25, "no jump in head height between frames: %.2f" % worst_step)


## The pistol itself points at the reticle (low, high and to the side), and
## aiming works lying down too.
func test_gun_points_at_the_reticle() -> void:
	var o := _officer()
	await get_tree().process_frame
	for target in [Vector3(1.5, 0.0, 4.0), Vector3(-2.0, 2.5, 5.0), Vector3(0.0, 1.2, 8.0)]:
		var cmd := {"move": Vector2.ZERO, "buttons": PlayerInput.AIM, "aim_yaw": atan2(target.x, target.z), "aim_point": target}
		for i in 50:
			o.sim_step(cmd, 1.0 / 60.0)
			await get_tree().process_frame
		# The rendered gun (it follows the hand after the procedural layers).
		var sl := o.rig.model.find_child("gun_slide", true, false) as Node3D
		var dir := -sl.global_basis.y.normalized()
		var want: Vector3 = (target - o.muzzle_position()).normalized()
		var err := rad_to_deg(dir.angle_to(want))
		print("    target %s: barrel off by %.1f deg" % [target, err])
		t.check(err < 4.0, "barrel points at %s (%.1f deg off)" % [target, err])
	# Prone: aiming is allowed and the body turns to the aim.
	await _run(o, _cmd(Vector2.ZERO, PlayerInput.PRONE), 1)
	var tgt := Vector3(3.0, 0.0, 0.5)
	var pc := {"move": Vector2.ZERO, "buttons": PlayerInput.AIM, "aim_yaw": atan2(tgt.x, tgt.z), "aim_point": tgt}
	for i in 90:
		o.sim_step(pc, 1.0 / 60.0)
		await get_tree().process_frame
	t.check(o.state == Officer.S.PRONE and o.is_aiming(), "aiming while prone")
	t.check(absf(angle_difference(o.rotation.y, pc.aim_yaw)) < 0.15, "prone body turns to the aim")


## Crouched (still and moving), each knee stays on its own side.
func test_crouch_knees_do_not_cross() -> void:
	var o := _officer()
	await get_tree().process_frame
	o._set_state(Officer.S.CROUCH)
	var sk := o.rig.skeleton
	for mv in [Vector2.ZERO, Vector2(0, 1)]:
		for i in 40:
			o.sim_step(_cmd(mv), 1.0 / 60.0)
			await get_tree().process_frame
		var kl := sk.get_bone_global_pose(sk.find_bone("shin.L")).origin.x
		var kr := sk.get_bone_global_pose(sk.find_bone("shin.R")).origin.x
		t.check(kl > 0.05 and kr < -0.05, "knees apart while crouched (%s): L %.2f R %.2f" % [mv, kl, kr])


## Cover: tucks the whole body in behind the end of a wall, stays hidden
## while moving toward the end, and leans out only while aiming.
func test_cover_hides_and_peeks_on_aim() -> void:
	var o := _officer(Vector3(0.1, 0, 0))
	# A tall wall ahead (facing +Z) whose right end (-X) is 0.1 m from the officer.
	ProtoWorld.block(self, Vector3(3, 2.2, 0.3), Vector3(1.5, 1.1, 1.0), Color.GRAY)
	await _run(o, _cmd(), 5)
	await _run(o, _cmd(Vector2.ZERO, PlayerInput.COVER), 1)
	await _run(o, _cmd(), 5)
	t.check(o.state == Officer.S.COVER, "in cover, state %s" % Officer.S.keys()[o.state])
	t.check(o.global_position.x > 0.3, "shuffled in behind the wall's end: x=%.2f" % o.global_position.x)
	await _run(o, _cmd(Vector2(-1, 0)), 60)
	t.check(o.global_position.x > 0.3, "stays hidden at the end of the wall: x=%.2f" % o.global_position.x)
	var hidden_x := o.global_position.x
	var aim := {"move": Vector2.ZERO, "buttons": PlayerInput.AIM, "aim_yaw": 0.0, "aim_point": Vector3(-1, 1.2, 8)}
	await _run(o, aim, 40)
	t.check(o.global_position.x < hidden_x - 0.4, "leans out past the end while aiming: x=%.2f" % o.global_position.x)
	await _run(o, _cmd(), 40)
	t.check(absf(o.global_position.x - hidden_x) < 0.1, "back in cover when the aim is let go: x=%.2f" % o.global_position.x)
	# A low wall: crouch behind it, stand to aim over.
	var p := _officer(Vector3(10, 0, 0))
	ProtoWorld.block(self, Vector3(3, 1.0, 0.3), Vector3(10, 0.5, 1.0), Color.GRAY)
	await _run(p, _cmd(), 5)
	await _run(p, _cmd(Vector2.ZERO, PlayerInput.COVER), 1)
	await _run(p, _cmd(), 3)
	t.check(p.state == Officer.S.COVER and p._cover_low, "low cover")
	t.check(p.rig._lower_state(p) == "crouch_idle", "crouched behind low cover")
	await _run(p, aim, 3)
	t.check(p.rig._lower_state(p) == "idle" and p.rig._upper_state(p) == "aim_hold", "stands and aims over it")
