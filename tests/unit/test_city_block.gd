extends Node
var t


func test_same_seed_same_block() -> void:
	var a := BlockGenerator.generate(1234)
	var b := BlockGenerator.generate(1234)
	var c := BlockGenerator.generate(1235)
	print("    %d pieces, %d buildings; fingerprints %d %d %d" % [a.pieces.size(), a.buildings.size(), a.fingerprint(), b.fingerprint(), c.fingerprint()])
	t.check(a.fingerprint() == b.fingerprint(), "same seed, same block")
	t.check(a.fingerprint() != c.fingerprint(), "another seed, another block")


func test_blocks_follow_the_brief() -> void:
	for s in 40:
		var g := BlockGenerator.generate(s * 7919 + 3)
		var n: int = g.buildings.size()
		var enter: int = g.buildings.filter(func(b): return b.enterable).size()
		t.check(n >= 4 and n <= 6, "seed %d: 4 to 6 buildings (%d)" % [s, n])
		t.check(enter == 2, "seed %d: two enterable (%d)" % [s, enter])
		# No two buildings overlap.
		for i in n:
			for j in range(i + 1, n):
				var ai: AABB = g.buildings[i].bounds.grow(-0.4)
				var bj: AABB = g.buildings[j].bounds.grow(-0.4)
				t.check(not ai.intersects(bj), "seed %d: buildings %d and %d apart" % [s, i, j])
		# Every piece is a kit piece.
		for p in g.pieces:
			if not KitLibrary.kinds().has(p.kind):
				t.check(false, "unknown piece " + p.kind)
				return


func test_built_block_stands_up() -> void:
	var w := DestructionWorld.new()
	add_child(w)
	var t0 := Time.get_ticks_msec()
	var g := CityBlock.build(w, 99)
	var ms := Time.get_ticks_msec() - t0
	var stable := w.compute_stable()
	var loose: Array = w.pieces.values().filter(func(p): return not stable.has(p.id)).map(func(p): return "%s@%s" % [p.kind, (p.aabb as AABB).position.snapped(Vector3.ONE * 0.01)])
	print("    built %d pieces in %d ms; unsupported: %s" % [w.pieces.size(), ms, loose.slice(0, 8)])
	t.check(loose.is_empty(), "every piece is held up (%d loose)" % loose.size())
	t.check(w.pieces.size() == g.pieces.size(), "one piece per plan entry")
	w.free()


## An officer can walk up the stairs of an enterable building to the floor above.
func test_officer_walks_upstairs() -> void:
	var w := DestructionWorld.new()
	add_child(w)
	var g := CityBlock.build(w, 99)
	var b: Dictionary = g.buildings.filter(func(x): return x.enterable and x.storeys >= 2)[0]
	# Bottom of the stairs: back-right tile, right-hand side, front end of the tile.
	var start: Vector3 = b.origin + b.u * ((b.w - 0.5) * 4.0 + 1.35) + b.v * ((b.d - 1) * 4.0 + 0.2) + Vector3(0, 0.1, 0)
	var o := Officer.new()
	add_child(o)
	o.global_position = start - b.v * 0.6
	var dir: Vector3 = b.v
	var mv := Vector2(dir.x, dir.z)
	for i in 240:
		o.sim_step({"move": mv, "buttons": 0, "aim_yaw": atan2(dir.x, dir.z)}, 1.0 / 60.0)
		await get_tree().physics_frame
	var floor_y: float = b.origin.y + BlockGenerator.STOREY
	print("    officer at y=%.2f (upper floor at %.2f)" % [o.global_position.y, floor_y])
	t.check(o.global_position.y > floor_y - 0.1, "reached the upper floor")
	o.free()
	w.free()
