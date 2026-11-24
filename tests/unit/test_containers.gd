extends Node
## v0.16.0: shipping containers on the docks and in the yards stay on the
## ground. Two used to be placed inside each other; the physics shoved them
## apart hard enough to push one down through the ground.
var t


func test_containers_stay_on_the_ground() -> void:
	City.next_seed = 4242
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	for i in 10:
		await get_tree().physics_frame
	for k in s.gen.blocks.size():
		if s.gen.blocks[k].style in ["docks", "industrial"]:
			s.props.furnish_block(k)
	var boxes: Array = []
	for id in s.props.props:
		if s.props.props[id].kind == "container":
			boxes.append(s.props.props[id].body)
	t.check(boxes.size() >= 6, "containers in the yards (%d)" % boxes.size())
	var y0 := {}
	for b in boxes:
		y0[b] = (b as Node3D).global_position.y
		(b as RigidBody3D).sleeping = false
	for i in 60 * 6:
		await get_tree().physics_frame
	var moved := 0
	var sunk := 0
	for b in boxes:
		var y: float = (b as Node3D).global_position.y
		if absf(y - y0[b]) > 0.1:
			moved += 1
		if y < 1.0:   # a container's centre sits 1.46 m up
			sunk += 1
	t.check(moved == 0, "none of them shoved about at the start (%d moved)" % moved)
	t.check(sunk == 0, "none through the ground (%d)" % sunk)
	s.queue_free()
	await get_tree().process_frame
