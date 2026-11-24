extends Node
## v0.14.0: the mini map, the job markers and the Max money cheat.

var t


func _city() -> City:
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	s.dispatch.missions.enabled = false
	s.dispatch.stories.enabled = false
	for i in 30:
		await get_tree().physics_frame
	return s


func test_route_stays_on_roads() -> void:
	CityGenerator.pick_sizes(4242)
	var half := CityGenerator.ROAD_W * 0.5
	var on_road := func(p: Vector2) -> bool:
		for r in CityGenerator.roads():
			if (r.rect as Rect2).grow(0.01).has_point(p):
				return true
		return false
	var a := CityGenerator.junction(1, 2) + Vector3(0, 0, 20.0)   # on a road along Z
	var b := CityGenerator.junction(4, 5) + Vector3(15.0, 0, half + 3.0)
	var pts := MiniMap.route(a, b)
	t.check(pts.size() == 5 and pts[0] == Vector2(a.x, a.z) and pts[-1] == Vector2(b.x, b.z), "starts at you and ends at the job")
	for i in range(1, 4):
		t.check(on_road.call(pts[i]), "corner %d is on a road: %s" % [i, pts[i]])
	CityGenerator.even_sizes()


func test_minimap_and_markers_draw() -> void:
	var s := await _city()
	var mm := s.get_node_or_null("MiniMap") as MiniMap
	t.check(mm != null, "the city has a mini map")
	var id := s.dispatch.start_call(Dispatcher.Kind.BURGLARY)
	t.check(id >= 0, "a job to show")
	for m in [1, 2, 0, 1]:
		Settings.set_value("minimap", m, false)
		for i in 3:
			await get_tree().process_frame
	t.check(mm.screen_rect().size.x > 100.0, "the small map is on screen")
	Settings.values["minimap"] = 1
	s.queue_free()
	await get_tree().process_frame


func test_max_money() -> void:
	var s := await _city()
	s.dispatch.set_pay(Dispatcher.MAX_PAY)
	t.check(s.dispatch.pay == 9999999, "pay at the top: £%d" % s.dispatch.pay)
	var a := s.armoury
	t.check(a._buy(2), "and it buys things")
	s.queue_free()
	await get_tree().process_frame
	Armoury.owned = 1
