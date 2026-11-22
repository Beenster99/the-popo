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
	# Breaks pick their chunk pattern with randi(): fix the seed so the same
	# rubble falls every run (some patterns wedge the slab or knock the
	# neighbouring slab, which made this test pass or fail at random).
	seed(1234)
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
	# Let it fall: the slab comes down, and usually shatters on the way.
	var slab_body: RigidBody3D = w.bodies.get(8 * 64 + DestructionWorld.RELEASED_BIT)
	t.check(slab_body != null or w.pieces[8].state == "gone", "slab is a falling rigid body (or already broke up)")
	var start_y: float = slab_body.global_position.y if slab_body != null else 0.0
	var lowest := 99.0
	for i in 180:
		await get_tree().physics_frame
		if is_instance_valid(slab_body):
			lowest = minf(lowest, slab_body.global_position.y)
	# It can come to rest wedged on the rubble of the wall below, so only ask that it dropped.
	t.check(w.pieces[8].state == "gone" or lowest < start_y - 0.5, "slab came down (state %s, from %.2f to %.2f)" % [w.pieces[8].state, start_y, lowest])


func test_explosion_breaks_nearby_pieces() -> void:
	var w := _world()
	BuildingLayout.wall_row(w, Vector3.ZERO, 3)
	w.finalize()
	w.explode(Vector3(0, 1, 1), 3.0, 500.0, 8.0)
	await get_tree().physics_frame
	t.check(w.pieces[1].state == "gone", "near wall gone")
	t.check(w.pieces[3].state == "intact", "far wall intact")
	t.check(w.bodies.size() > 3, "big chunks registered: %d" % w.bodies.size())


func test_falling_slab_scraping_its_neighbour_does_no_damage() -> void:
	var w := _world()
	BuildingLayout.shop(w, Vector3.ZERO)
	w.finalize()
	w.damage_piece(1, 9999.0, Vector3(-1, 1.5, 2), 3.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var slab: RigidBody3D = w.bodies.get(8 * 64 + DestructionWorld.RELEASED_BIT)
	t.check(slab != null, "west slab released (state %s)" % w.pieces[8].state)
	if slab == null:
		return
	# A slow scrape past the east slab as the west one tips away from it.
	slab.linear_velocity = Vector3(0, -1.5, 0)
	slab.angular_velocity = Vector3(0, 0, 1.0)
	w._on_released_hit(w.pieces[9].node, slab, 8)
	t.check(w.pieces[9].state == "intact", "east slab survived the scrape")
	# A hard hit on something it was not attached to still does damage.
	var hp_before: float = w.pieces[3].hp
	slab.set_meta("torn_from", [])
	w._on_released_hit(w.pieces[3].node, slab, 8)
	t.check(w.pieces[3].hp < hp_before or w.pieces[3].state != "intact", "unattached piece takes damage")
