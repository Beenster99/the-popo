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
