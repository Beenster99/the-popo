extends Node
## Phase 1.7: the block's damage is kept. The host saves it and Continue
## brings the same wrecked block back; the same state is what a friend joining
## late is sent (the two-process check is tools/capture/late_join.gd).
var t


func _block(seed_value: int, resume: bool) -> Node:
	Block.next_seed = seed_value
	Block.resume = resume
	var scene: Node = load("res://prototypes/p08_block/block.tscn").instantiate()
	add_child(scene)
	for i in 120:
		await get_tree().physics_frame
		if scene.get("state") != null and i > 5:
			break
	(scene.dispatch as Dispatcher).enabled = false
	return scene


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _lost(w: DestructionWorld) -> Array:
	var out := w.pieces.values().filter(func(p): return p.state != "intact").map(func(p): return p.id)
	out.sort()
	return out


func _broken_props(pw: PropWorld) -> Array:
	var out := pw.props.values().filter(func(p): return p.broken).map(func(p): return p.id)
	out.sort()
	return out


func test_the_block_is_saved_and_continue_brings_it_back() -> void:
	BlockState.delete_save()
	var a: Node = await _block(777, false)
	t.check(a.seed_value == 777, "a new block from the seed asked for")
	var b0: Dictionary = (a.gen as BlockGenerator).buildings[0]
	(a.world as DestructionWorld).explode((b0.origin as Vector3) + Vector3(1.0, 1.0, 0.0), 3.5, 400.0, 6.0)
	var n := 0
	for p in (a.props as PropWorld).props.values():
		if p.kind in ["chair", "table", "crate"] and n < 5:
			(a.props as PropWorld).break_prop(p.id)
			n += 1
	var cs: CarSync = a.cars
	cs.cars[0].apply_dent(Vector3(0.9, 0.3, 0.5), Vector3.LEFT, 0.25)
	cs.damage_car(cs.cars[1], 500.0)
	await _frames(int((CarSync.BURN_TIME + 6.0) * 60))
	var lost := _lost(a.world)
	var broken := _broken_props(a.props)
	var bodies: Dictionary = (a.world as DestructionWorld).rest_report()
	var dents: int = cs.cars[0].dent_log.size()
	var parked: Vector3 = cs.cars[0].global_position
	t.check(lost.size() > 5, "a hole blown in a building: %d pieces gone" % lost.size())
	t.check(cs.cars[1].wrecked, "a car burnt out")
	t.check(a.state.save(), "the host saves")
	var peek := BlockState.peek()
	t.check(peek.get("seed", 0) == 777, "the save is that block: %s" % [peek])
	a.queue_free()
	await _frames(3)

	var c: Node = await _block(0, true)
	t.check(c.seed_value == 777, "Continue builds the saved block: %d" % c.seed_value)
	await _frames(30)
	var lost2 := _lost(c.world)
	t.check(lost2 == lost, "the same pieces are gone: %d vs %d" % [lost2.size(), lost.size()])
	var bodies2: Dictionary = (c.world as DestructionWorld).rest_report()
	t.check(bodies2.size() == bodies.size(), "the rubble is all there: %d vs %d" % [bodies2.size(), bodies.size()])
	var off := 0
	for nid in bodies:
		if bodies2.has(nid) and (bodies2[nid] as Vector3).distance_to(bodies[nid]) > 0.3:
			off += 1
	t.check(off <= bodies.size() / 10, "and lies where it was: %d of %d moved" % [off, bodies.size()])
	t.check(_broken_props(c.props) == broken, "the same props are smashed")
	var cs2: CarSync = c.cars
	t.check(cs2.cars[1].wrecked and cs2.fire_state.get(1, 0) == CarSync.Fire.WRECKED, "the wreck is still a wreck")
	t.check(cs2.cars[0].dent_log.size() == dents, "and the dented car is dented")
	t.check(cs2.cars[0].global_position.distance_to(parked) < 0.5, "where it was parked")
	c.queue_free()
	await _frames(3)

	# A new block replaces the save when it ends.
	var d: Node = await _block(888, false)
	d.queue_free()
	await _frames(3)
	t.check(BlockState.peek().get("seed", 0) == 888, "a new block replaces the save")
	BlockState.delete_save()
	t.check(not BlockState.has_save(), "and with no save there's nothing to continue")


func test_a_broken_save_is_ignored() -> void:
	DirAccess.make_dir_recursive_absolute(BlockState.save_path.get_base_dir())
	var f := FileAccess.open(BlockState.save_path, FileAccess.WRITE)
	f.store_string("not a save at all, just some words")
	f.close()
	t.check(not BlockState.has_save(), "a file that isn't a save is no save")
	var c: Node = await _block(0, true)
	t.check(c.seed_value != 0, "Continue with a bad save just starts a block")
	c.queue_free()
	await _frames(3)
	BlockState.delete_save()


func test_the_menu_offers_continue() -> void:
	# The menu offers the city's save (Wave 2).
	BlockState.save_path = City.SAVE_PATH
	BlockState.delete_save()
	var m: Node = load("res://game/ui/main_menu.tscn").instantiate()
	add_child(m)
	await _frames(2)
	t.check(not _has_button(m, "Continue"), "no save, no Continue")
	m.queue_free()
	var a: Node = await _block(555, false)
	BlockState.save_path = City.SAVE_PATH
	a.state.save()
	a.queue_free()
	await _frames(3)
	m = load("res://game/ui/main_menu.tscn").instantiate()
	add_child(m)
	await _frames(2)
	t.check(_has_button(m, "Continue"), "with a save, Continue")
	t.check(_has_button(m, "New City"), "and New City")
	Net.last_notice = "Lost the connection to the host."
	m.queue_free()
	m = load("res://game/ui/main_menu.tscn").instantiate()
	add_child(m)
	await _frames(2)
	t.check(_has_label(m, "Lost the connection"), "a client dropped by the host is told why")
	t.check(Net.last_notice == "", "once")
	m.queue_free()
	await _frames(2)
	BlockState.delete_save()


func _has_button(n: Node, text: String) -> bool:
	for c in n.find_children("*", "Button", true, false):
		if (c as Button).text.begins_with(text):
			return true
	return false


func _has_label(n: Node, text: String) -> bool:
	for c in n.find_children("*", "Label", true, false):
		if (c as Label).text.contains(text):
			return true
	return false
