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


## Inside a building the floor is cut away to the camera: near walls, floors
## above and anything in the way fade out; far walls and interior walls stay.
func test_inside_view_shows_the_whole_floor() -> void:
	var w := DestructionWorld.new()
	add_child(w)
	var fader := RoofFader.new()
	add_child(fader)
	var g := CityBlock.build(w, 4242, fader)
	var cam := Camera3D.new()
	add_child(cam)
	var b: Dictionary = g.buildings.filter(func(x): return x.enterable)[0]
	var bb: AABB = b.bounds
	var spot := Node3D.new()
	add_child(spot)
	spot.global_position = Vector3(bb.get_center().x, bb.position.y + 0.2, bb.get_center().z)
	cam.global_position = spot.global_position + Vector3(10, 12, 10)
	cam.look_at(spot.global_position)
	cam.current = true
	fader.watch = spot
	for i in 40:
		await get_tree().process_frame
	# Every solid piece that stands taller than 1 m above this floor must
	# not hide any of it, apart from interior walls, stairs and columns
	# (walls on this floor go see-through instead).
	var view := -cam.global_basis.z
	var foot := Rect2(bb.position.x, bb.position.z, bb.size.x, bb.size.z).grow(-0.6)
	var blocking := 0
	var hidden := 0
	var ghosted := 0
	for m in fader._all:
		if not is_instance_valid(m):
			continue
		var mi := m as MeshInstance3D
		if not mi.visible:
			hidden += 1
			continue
		var f: float = fader._state.get(mi, 1.0)
		if f <= RoofFader.GHOST + 0.01:
			ghosted += 1
			continue   # walls on this floor stay as see-through ghosts
		var kind: String = mi.get_meta("kind")
		if kind.begins_with("int_") or kind == "stairs" or kind.begins_with("column") or kind.begins_with("slab"):
			continue
		if fader._in_the_way(mi, spot.global_position.y, foot, view, false):
			blocking += 1
	t.check(hidden > 10, "pieces cut away: %d" % hidden)
	t.check(ghosted > 3, "camera-side walls see-through, not gone: %d" % ghosted)
	t.check(blocking == 0, "nothing left hiding the floor (%d pieces in the way)" % blocking)


## Phase 1.7: furniture on the floor above goes with that floor, and comes
## back when you go up.
func test_upstairs_furniture_goes_with_the_floor() -> void:
	var w := DestructionWorld.new()
	add_child(w)
	var fader := RoofFader.new()
	add_child(fader)
	var g := CityBlock.build(w, 4242, fader)
	var props := PropWorld.new()
	props.world = w
	add_child(props)
	props.furnish(g)
	var cam := Camera3D.new()
	add_child(cam)
	var b: Dictionary = g.buildings.filter(func(x): return x.enterable and x.storeys > 1)[0]
	var bb: AABB = b.bounds
	var ground_y := bb.position.y
	var up := props.props.values().filter(func(p): return bb.has_point((p.body as Node3D).global_position) and (p.body as Node3D).global_position.y > ground_y + 2.5)
	var down := props.props.values().filter(func(p): return bb.has_point((p.body as Node3D).global_position) and (p.body as Node3D).global_position.y < ground_y + 1.5)
	t.check(up.size() > 0 and down.size() > 0, "furniture on both floors: %d up, %d down" % [up.size(), down.size()])
	var spot := Node3D.new()
	add_child(spot)
	spot.global_position = Vector3(bb.get_center().x, ground_y + 0.2, bb.get_center().z)
	cam.global_position = spot.global_position + Vector3(10, 12, 10)
	cam.look_at(spot.global_position)
	cam.current = true
	fader.watch = spot
	for i in 5:
		await get_tree().process_frame
	t.check(up.all(func(p): return fader._cut.has(p.body)), "downstairs, the upstairs furniture is cut away with its floor")
	t.check(not down.any(func(p): return fader._cut.has(p.body)), "and this floor's stays")
	spot.global_position.y = ground_y + BlockGenerator.STOREY + 0.2
	for i in 5:
		await get_tree().process_frame
	t.check(not up.any(func(p): return fader._cut.has(p.body)), "upstairs, it's back")
	spot.global_position = bb.get_center() + Vector3(bb.size.x, -bb.size.y * 0.5 + 0.2, 0)
	for i in 5:
		await get_tree().process_frame
	t.check(fader.cut_count() == 0, "and outside nothing is cut")


## Phase 1.7: every lit thing on the block wears the cel shader (markers and
## effects are unshaded on purpose), so nothing looks out of place.
func test_everything_on_the_block_is_cel_shaded() -> void:
	Block.next_seed = 4242
	var scene: Node = load("res://prototypes/p08_block/block.tscn").instantiate()
	add_child(scene)
	for i in 90:
		await get_tree().physics_frame
	(scene.dispatch as Dispatcher).start_call(0)
	(scene.dispatch as Dispatcher).start_call(1)
	for i in 30:
		await get_tree().physics_frame
	var odd := []
	var n := 0
	for gi in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := gi as MeshInstance3D
		if mi.mesh == null or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var mats := []
		if mi.material_override:
			mats.append(mi.material_override)
		else:
			for i in mi.mesh.get_surface_count():
				mats.append(mi.get_surface_override_material(i) if mi.get_surface_override_material(i) else mi.mesh.surface_get_material(i))
		for m in mats:
			n += 1
			if m is ShaderMaterial and (m as ShaderMaterial).shader == Cel.CEL:
				continue
			if m is BaseMaterial3D and (m as BaseMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				continue
			odd.append("%s (%s)" % [scene.get_path_to(mi), m])
	t.check(n > 1000, "looked at %d surfaces" % n)
	t.check(odd.is_empty(), "all cel shaded: %s" % [odd.slice(0, 6)])
	scene.queue_free()
	await get_tree().physics_frame
	BlockState.delete_save()
