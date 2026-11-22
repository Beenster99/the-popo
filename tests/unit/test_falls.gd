extends Node
## v0.2.11 (beenster: "Players collapse in a heap when dead, can't this be a
## bit more realistic?"): a body goes down with its momentum, stays in one
## piece and lies stretched out rather than folded into a pile.
var t


func _scene(at := Vector3(0, 0.05, 0)) -> Suspect:
	ProtoWorld.ground(self, 60.0)
	var s := Suspect.new()
	s.position = at
	add_child(s)
	for i in 10:
		await get_tree().physics_frame
	return s


func _pb(s: Suspect, b: String) -> Node3D:
	return s.rig.bone_body(b)


func _report(s: Suspect) -> Dictionary:
	var head := _pb(s, "head_2").global_position
	var hips := _pb(s, "hips").global_position
	var feet := (_pb(s, "foot.L").global_position + _pb(s, "foot.R").global_position) * 0.5
	var spread := 0.0
	for b in ["head_2", "hand.L", "hand.R", "foot.L", "foot.R"]:
		spread = maxf(spread, _pb(s, b).global_position.distance_to(hips))
	return {"head_feet": head.distance_to(feet), "spread": spread, "hips_y": hips.y}


func test_shot_down_lies_stretched_out() -> void:
	var lens := []
	for push in [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1)]:
		var s: Suspect = await _scene()
		s.hp = 1.0   # a pistol round finishes them
		s.take_damage(35.0, push)
		for i in 180:
			await get_tree().physics_frame
		var r := _report(s)
		lens.append(r)
		t.check(r["hips_y"] < 0.45, "on the floor: hips at %.2f" % r["hips_y"])
		t.check(r["head_feet"] > 1.15, "stretched out, not heaped: head to feet %.2f m" % r["head_feet"])
		t.check(r["spread"] < 1.3, "in one piece: furthest limb %.2f m from the hips" % r["spread"])
		s.queue_free()
		await get_tree().physics_frame
	print("  falls: ", lens)


func test_a_runner_falls_forward() -> void:
	var s: Suspect = await _scene()
	s.velocity = Vector3(0, 0, -6.0)
	var hips0 := _pb(s, "hips").global_position
	s.take_damage(500.0, Vector3.ZERO)
	for i in 120:
		await get_tree().physics_frame
	var moved := _pb(s, "hips").global_position - hips0
	t.check(moved.z < -0.8, "carried on the way they ran: %.2f m" % moved.z)
