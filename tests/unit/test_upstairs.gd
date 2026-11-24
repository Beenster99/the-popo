extends Node
## v0.24.0: crooks upstairs and on the roofs. The stairs leave headroom under
## the flight above, so the walking routes climb every floor; gangs can be
## up on a roof, armed men at an upstairs window, and runners head up.
var t


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_stairs_are_treads_with_headroom() -> void:
	var p := KitLibrary.get_piece("stairs")
	var thick := 0.0
	for ch in p.solid:
		thick = maxf(thick, (ch.mesh as Mesh).get_aabb().size.y)
	t.check(thick <= KitLibrary.STAIR_THICK + 0.01, "each step is a tread, not a block to the floor (%.2f m)" % thick)
	var a: AABB = p.aabb
	t.check(a.size.y > 3.0 and a.position.y < 0.1, "the flight still climbs a storey (%s)" % a)
	# Under the top step there is room to stand on the flight below.
	var top := 0.0
	var under := INF
	for v in (p.mesh as Mesh).get_faces():
		if v.z > a.end.z - KitLibrary.STAIR_RUN * 0.5:
			top = maxf(top, v.y)
			under = minf(under, v.y)
	t.check(top - under <= KitLibrary.STAIR_THICK + 0.01, "the top step's underside is up high (%.2f to %.2f)" % [under, top])


func test_crooks_upstairs_and_on_roofs() -> void:
	BlockState.save_path = City.SAVE_PATH
	BlockState.delete_save()
	City.next_seed = 4242
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	await _frames(30)
	var d := s.dispatch
	var nav := s.nav as CityNav
	var tower: Dictionary = s.gen.buildings.filter(func(x): return x.get("lift", false))[0]
	var bi: int = s.gen.buildings.find(tower)
	var k := -1
	for bk in s.gen.blocks.size():
		var blk: Dictionary = s.gen.blocks[bk]
		if bi >= blk.buildings_from and bi < blk.buildings_to:
			k = bk
	nav.set_focus(tower.door)
	for i in 2400:
		await get_tree().physics_frame
		if nav.ready_to_use and nav.block_ready(k):
			break
	t.check(nav.block_ready(k), "the tower's block has its walking routes")
	# Every floor of the tower from the street.
	var door := nav.closest(tower.door)
	var floors := 0
	for f in tower.storeys:
		var p := Rooftops.to_world(tower, 2.0, f * BlockGenerator.STOREY + 0.05, 2.0)
		if nav.closest(p).distance_to(p) < 0.8 and nav.reaches(door, nav.closest(p)):
			floors += 1
	t.check(floors == tower.storeys, "up the stairs to every floor of the tower (%d of %d)" % [floors, tower.storeys])
	d._use_area(k)
	var high := d.hide_spots.filter(func(p): return (p as Vector3).y > BlockGenerator.STOREY * 2.5)
	t.check(high.size() > 10, "hiding places high up (%d)" % high.size())
	t.check(d.roof_spots.size() > 0, "and on the roofs (%d)" % d.roof_spots.size())
	# A gang on a roof.
	var id: int = d.start_call(Dispatcher.Kind.GANG, {"block": k, "roof": true})
	t.check(id >= 0, "a gang call starts")
	if id >= 0:
		var c: Dictionary = d.calls[id]
		var ys: Array = c.suspects.map(func(n): return (d.suspects[n] as Suspect).global_position.y)
		t.check(ys.all(func(y): return y > BlockGenerator.STOREY * 1.5), "the gang is up on a roof (%s): %s" % [ys, c.text])
		t.check(String(c.text).contains("roof"), "dispatch says so")
	id = d.start_call(Dispatcher.Kind.ARMED, {"block": k, "upstairs": true})
	if id >= 0:
		var c: Dictionary = d.calls[id]
		var a: Suspect = d.suspects[c.suspects[0]]
		t.check(a.global_position.y > BlockGenerator.STOREY * 0.8, "the armed man is upstairs (y %.1f): %s" % [a.global_position.y, c.text])
		t.check(String(c.text).contains("floor"), "and dispatch names the floor")
	# Someone keen to climb, chased from the street, picks somewhere higher.
	var o: Officer = s.sync.my_pawn()
	o.global_position = door + Vector3(0, 0.1, 0)
	var r := d.spawn_suspect(door + (tower.v as Vector3) * 3.0, Suspect.S.LOITER, false, -1)
	await _frames(2)
	r.climb = 1.0
	var up := 0
	for i in 6:
		var spot := r._pick_hide({"o": o})
		if spot.y > r.global_position.y + 2.0:
			up += 1
	t.check(up >= 4, "a climber runs for the upper floors (%d of 6 picks)" % up)
	s.queue_free()
	await _frames(2)
