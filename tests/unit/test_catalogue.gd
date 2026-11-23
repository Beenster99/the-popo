extends Node
## Wave 5, Phase 5.1: the catalogue: street furniture by district, more
## for the rooms, nothing stuck in a wall.
var t


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_city_blocks_have_street_furniture() -> void:
	City.next_seed = 4242
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	s.dispatch.enabled = false
	await _frames(20)
	var pw: PropWorld = s.props
	var by_style := {}
	for k in s.gen.blocks.size():
		var blk: Dictionary = s.gen.blocks[k]
		if not by_style.has(blk.style):
			by_style[blk.style] = k
	var before := pw.props.size()
	for st in by_style:
		pw.furnish_block(by_style[st])
	var kinds := {}
	var new_ids: Array = []
	for p in pw.props.values():
		kinds[p.kind] = int(kinds.get(p.kind, 0)) + 1
		new_ids.append(p.id)
	print("    %d props over %d blocks: %s" % [pw.props.size() - before, by_style.size(), kinds])
	for k in ["hydrant", "wheelie_bin", "post_box", "phone_box", "tyres"]:
		t.check(kinds.has(k), "%s out on the streets" % k)
	var rooms := 0
	for k in ["tv", "fridge", "armchair", "plant", "bookcase", "washer", "water_cooler", "vending"]:
		if kinds.has(k):
			rooms += 1
	t.check(rooms >= 4, "new things in the rooms: %d kinds" % rooms)
	var start := {}
	for p in pw.props.values():
		start[p.id] = (p.body as RigidBody3D).global_position
		(p.body as RigidBody3D).sleeping = false
	await _frames(90)
	var moved := []
	for p in pw.props.values():
		if p.broken:
			moved.append("%s broke" % p.kind)
			continue
		var d := (p.body as RigidBody3D).global_position.distance_to(start[p.id])
		if d > 0.4:
			moved.append("%s %.2f m" % [p.kind, d])
	t.check(moved.size() <= int(pw.props.size() * 0.01) + 1, "everything stands where it was put (%d of %d moved): %s" % [moved.size(), pw.props.size(), moved.slice(0, 12)])
	s.queue_free()
	await _frames(2)
