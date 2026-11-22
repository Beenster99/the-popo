extends Node
var t


func test_quantised_transforms_round_trip() -> void:
	for i in 50:
		var pos := Vector3(randf_range(-300, 300), randf_range(-5, 60), randf_range(-300, 300))
		var q := Quaternion(Vector3(randf(), randf(), randf()).normalized(), randf_range(-PI, PI))
		var b := StreamPeerBuffer.new()
		DestructionWorld._put_qpos(b, pos)
		DestructionWorld._put_qquat(b, q)
		t.check(b.get_position() == 13, "13 bytes")
		b.seek(0)
		var p2 := DestructionWorld._get_qpos(b)
		var q2 := DestructionWorld._get_qquat(b)
		t.check(p2.distance_to(pos) < 0.02, "pos error %f" % p2.distance_to(pos))
		t.check(absf(q2.dot(q)) > 0.9999, "rot error %f" % absf(q2.dot(q)))


func test_snapshot_respects_body_budget() -> void:
	ProtoWorld.ground(self, 200.0)
	var w := DestructionWorld.new()
	add_child(w)
	BuildingLayout.wall_row(w, Vector3(-20, 0, 0), 10)
	w.finalize()
	for p in w.pieces.values():
		w.damage_piece(p.id, 9999.0, p.aabb.get_center() + Vector3(0, 0, 1), 5.0)
	await get_tree().physics_frame
	var b := StreamPeerBuffer.new()
	w._write_snapshot(b)
	b.seek(0)
	t.check(b.get_u16() <= DestructionWorld.MAX_BODIES_PER_SNAPSHOT, "budget respected")
	t.check(w.awake_total > DestructionWorld.MAX_BODIES_PER_SNAPSHOT, "test has more awake bodies than the budget: %d" % w.awake_total)
