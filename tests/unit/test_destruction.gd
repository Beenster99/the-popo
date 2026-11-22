extends Node
var t


func _world() -> DestructionWorld:
	ProtoWorld.ground(self, 60.0)
	var w := DestructionWorld.new()
	add_child(w)
	return w


func test_kit_has_every_piece_with_chunks() -> void:
	for k in ["wall", "wall_window", "wall_door", "slab", "column"]:
		var p := KitLibrary.get_piece(k)
		t.check(p.chunks.size() >= 5, "%s has %d chunks" % [k, p.chunks.size()])
		var vol := 0.0
		for c in p.chunks:
			vol += c.volume
		t.check(vol > 0.3, "%s chunk volume %f" % [k, vol])


func test_shop_starts_fully_supported() -> void:
	var w := _world()
	BuildingLayout.shop(w, Vector3.ZERO)
	w.finalize()
	var stable := w.compute_stable()
	t.check(stable.size() == w.pieces.size(), "%d of %d stable" % [stable.size(), w.pieces.size()])


func test_losing_a_side_wall_drops_the_floor_above() -> void:
	var w := _world()
	BuildingLayout.shop(w, Vector3.ZERO)
	w.finalize()
	# Piece 1 is the ground-floor west wall; piece 8 is the first-floor slab over the west bay.
	t.check(w.pieces[1].kind == "wall" and w.pieces[8].kind == "slab", "layout ids")
	w.damage_piece(1, 9999.0, Vector3(-1, 1.5, 2), 3.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	t.check(w.pieces[1].state == "gone", "wall shattered")
	t.check(w.pieces[8].state != "intact", "slab above released, state=%s" % w.pieces[8].state)
	t.check(w.pieces[9].state == "intact", "east bay slab still held by the middle and east walls")
	# Let it fall: the slab should hit the ground floor and come down.
	var slab_body: RigidBody3D = w.bodies.get(8 * 64 + DestructionWorld.RELEASED_BIT)
	t.check(slab_body != null, "slab is a falling rigid body")
	for i in 180:
		await get_tree().physics_frame
		if i % 15 == 0 and is_instance_valid(slab_body) and OS.has_environment("POPO_DEBUG"):
			print(i, " ", slab_body.global_position, " v=", slab_body.linear_velocity, " contacts=", slab_body.get_contact_count(), " sleep=", slab_body.sleeping, " with=", slab_body.get_colliding_bodies().map(func(b): return b.name))
	t.check(w.pieces[8].state == "gone", "slab shattered on impact, state=%s" % w.pieces[8].state)


func test_explosion_breaks_nearby_pieces() -> void:
	var w := _world()
	BuildingLayout.wall_row(w, Vector3.ZERO, 3)
	w.finalize()
	w.explode(Vector3(0, 1, 1), 3.0, 500.0, 8.0)
	await get_tree().physics_frame
	t.check(w.pieces[1].state == "gone", "near wall gone")
	t.check(w.pieces[3].state == "intact", "far wall intact")
	t.check(w.bodies.size() > 3, "big chunks registered: %d" % w.bodies.size())
