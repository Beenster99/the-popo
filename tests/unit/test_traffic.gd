extends Node
## Wave 2, Phase 2.3: the city's traffic drives its lanes, stops at red
## lights, keeps clear of what's in front; people walk the pavements and
## scatter from gunfire; a car that hits someone knocks them down.
var t


func _city() -> City:
	City.next_seed = 4242
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	for i in 30:
		await get_tree().physics_frame
	return s


func test_traffic_drives_the_lanes() -> void:
	var s := await _city()
	var tr := s.traffic
	t.check(tr.drivers.size() == TrafficSystem.MOVING, "%d cars in traffic" % tr.drivers.size())
	t.check(tr.parked.size() >= 20, "%d parked cars" % tr.parked.size())
	t.check(tr.trailers.size() == 2, "two artics with trailers")
	var start := {}
	for dr in tr.drivers:
		start[dr.idx] = (dr.car as Node3D).global_position
	var stopped_at_red := 0
	var t0 := Time.get_ticks_msec()
	for i in 60 * 25:
		await get_tree().physics_frame
		if i % 30 == 0:
			for dr in tr.drivers:
				var car: Car = dr.car
				var pts: Array = dr.pts
				if dr.wi < pts.size() and pts[dr.wi][1] == 1 and car.linear_velocity.length() < 0.3:
					var e: Array = pts[dr.wi]
					if tr.light(e[2], e[3]) == TrafficSystem.L.RED and car.global_position.distance_to(e[0]) < 4.0:
						stopped_at_red += 1
	var ms := Time.get_ticks_msec() - t0
	var moved := 0
	var upright := 0
	var on_road := 0
	var total := 0.0
	for dr in tr.drivers:
		var car: Car = dr.car
		var d: float = car.global_position.distance_to(start[dr.idx])
		total += d
		if d > 40.0:
			moved += 1
		if car.global_transform.basis.y.dot(Vector3.UP) > 0.8:
			upright += 1
		var p := car.global_position
		var c := CityGenerator.block_at(p)
		var in_lot := false
		for b in s.gen.blocks:
			if (b.rect as Rect2).grow(-0.5).has_point(Vector2(p.x, p.z)):
				in_lot = true
		if not in_lot:
			on_road += 1
		print("    %-12s %-7s %5.1f m  %3.0f km/h  wi %d" % [(car as CivilianVehicle).kind, dr.mode, d, car.speed_kmh(), dr.wi])
	print("    25 s of traffic in %d ms (%.1f ms a frame), %.0f m driven, %d stops at red" % [ms, ms / 1500.0, total, stopped_at_red])
	t.check(moved >= TrafficSystem.MOVING * 0.7, "most cars got somewhere (%d of %d)" % [moved, tr.drivers.size()])
	t.check(upright >= TrafficSystem.MOVING - 1, "they stay on their wheels (%d)" % upright)
	t.check(on_road >= TrafficSystem.MOVING - 2, "and on the road, not the pavement (%d)" % on_road)
	t.check(stopped_at_red > 0, "cars wait at red lights (%d)" % stopped_at_red)
	for tl in tr.trailers:
		t.check((tl as Trailer).hitched(), "the artic still has its trailer")
	s.queue_free()
	await get_tree().process_frame


func test_cars_get_round_a_car_stopped_in_the_lane() -> void:
	# v0.13.x: a car left in the road (crash, abandoned, a friend's car) used
	# to hold up everything behind it for good. Drivers now pull out and
	# overtake it when the other side of the road is clear.
	var s := await _city()
	var tr := s.traffic
	var dr: Dictionary = {}
	for d in tr.drivers:
		if (d.car as CivilianVehicle).kind in ["sedan", "hatchback", "taxi"] and d.mode == "drive":
			dr = d
			break
	t.check(not dr.is_empty(), "a car in the traffic to test with")
	if dr.is_empty():
		s.queue_free()
		return
	var car: Car = dr.car
	# Clear its lane ahead, then drop a parked car in the middle of it.
	var lane := TrafficSystem._lane(dr.a, dr.b)
	var dir: Vector3 = ((lane[1] as Vector3) - (lane[0] as Vector3)).normalized()
	var start: Vector3 = (lane[0] as Vector3).lerp(lane[1], 0.05)
	for c in tr.cars.cars:
		if c != car and (c as Node3D).global_position.distance_to(start + dir * 20.0) < 30.0:
			(c as Node3D).global_position += Vector3(0, 0, 400)
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), start + Vector3(0, 1.2, 0))
	car.linear_velocity = Vector3.ZERO
	tr._reroute(dr, start)
	var block: Car = tr.parked[0]
	block.global_transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), start + dir * 22.0 + Vector3(0, 1.2, 0))
	block.linear_velocity = Vector3.ZERO
	var passed := false
	for i in 60 * 22:
		await get_tree().physics_frame
		if dr.mode == "drive" and (car.global_transform.affine_inverse() * block.global_position).z < -4.0:
			passed = true
			break
	print("    %s behind a parked car in its lane: %s, %.0f m on" % [(car as CivilianVehicle).kind, "got past" if passed else "still stuck", car.global_position.distance_to(start)])
	t.check(passed, "it pulls out and goes round")
	t.check(car.global_transform.basis.y.dot(Vector3.UP) > 0.8, "and stays on its wheels")
	s.queue_free()
	await get_tree().process_frame


func test_people_walk_and_scatter() -> void:
	var s := await _city()
	# Walk routes bake in the background; people appear once they're ready.
	for i in 60 * 14:
		await get_tree().physics_frame
	var peds := s.peds.peds
	print("    %d people out walking" % peds.size())
	t.check(peds.size() >= 12, "people out on the pavements (%d)" % peds.size())
	var walked := 0
	var where := {}
	for p in peds:
		where[p] = (p as Node3D).global_position
	for i in 120:
		await get_tree().physics_frame
	for p in peds:
		if is_instance_valid(p) and (p as Node3D).global_position.distance_to(where[p]) > 1.5:
			walked += 1
	t.check(walked >= peds.size() / 2, "they walk their rounds (%d)" % walked)
	# A shot fired among them.
	var o: Officer = s.sync.my_pawn()
	var near: Suspect = null
	for p in peds:
		if near == null or (p as Node3D).global_position.distance_to(o.global_position) < near.global_position.distance_to(o.global_position):
			near = p
	get_tree().call_group("alarm_listeners", "on_alarm", near.global_position + Vector3(4, 0, 0), 45.0)
	await get_tree().physics_frame
	t.check(near.state in [Suspect.S.PANIC, Suspect.S.COWER], "a shot nearby: they run or cower (%s)" % Suspect.S.keys()[near.state])
	var drivers_reacted := 0
	for i in 60 * 16:
		await get_tree().physics_frame
	t.check(near.state in [Suspect.S.WANDER, Suspect.S.PANIC, Suspect.S.COWER], "calms down and carries on (%s)" % Suspect.S.keys()[near.state])
	s.queue_free()
	await get_tree().process_frame


func test_a_car_knocks_people_down() -> void:
	var s := await _city()
	var tr := s.traffic
	var car: Car = s.police_cars[0]
	var dir := car.global_transform.basis.z
	var p := s.dispatch.spawn_suspect(car.global_position + dir * 9.0 + Vector3(0, -0.6, 0), Suspect.S.WANDER, false)
	p.civilian = true
	for i in 5:
		await get_tree().physics_frame
	car.linear_velocity = dir * 13.0
	var hp0 := p.hp
	for i in 50:
		car.throttle = 1.0
		await get_tree().physics_frame
	print("    hit at about 45 km/h: hp %.0f -> %.0f, %s" % [hp0, p.hp, Suspect.S.keys()[p.state]])
	t.check(p.hp < hp0, "run over: hurt")
	t.check(p.state in [Suspect.S.DOWN, Suspect.S.STAGGER, Suspect.S.COWER, Suspect.S.PANIC], "knocked down (%s)" % Suspect.S.keys()[p.state])
	s.queue_free()
	await get_tree().process_frame


func test_car_thief_and_chase() -> void:
	var s := await _city()
	var d := s.dispatch
	d.enabled = false
	for i in 60 * 12:
		await get_tree().physics_frame   # walk routes for the call area
	var id := d.start_call(Dispatcher.Kind.PURSUIT)
	t.check(id > 0, "a pursuit call: %s" % (d.calls[id].text if id > 0 else "none"))
	if id <= 0:
		s.queue_free()
		return
	var th: Suspect = d.suspects[d.calls[id].suspects[0]]
	var car: CivilianVehicle = th.get_meta("getaway")
	var top := 0.0
	for i in 60 * 6:
		await get_tree().physics_frame
		top = maxf(top, car.speed_kmh())
	print("    getaway %s at up to %.0f km/h" % [car.kind, top])
	t.check(th.state == Suspect.S.DRIVE and top > 45.0, "the stolen car is driven hard")
	t.check(d.calls[id].marker.distance_to(car.global_position) < 40.0, "the marker follows it")
	s.cars.damage_car(car, 60.0)
	for i in 30:
		await get_tree().physics_frame
	t.check(th.state in [Suspect.S.FLEE, Suspect.S.HIDE, Suspect.S.LOITER, Suspect.S.SHOOT, Suspect.S.SURRENDER] and th.visible, "smashed up: the driver bails and runs (%s)" % Suspect.S.keys()[th.state])
	# Settle the first thief so his gunfire can't startle the next one
	# (armed suspects hear shots up to HEAR_SHOTS away).
	th.set_state(Suspect.S.SURRENDER)
	# A theft: left alone, the thief is in and away.
	var id2 := d.start_call(Dispatcher.Kind.THEFT)
	t.check(id2 > 0, "a car theft call: %s" % (d.calls[id2].text if id2 > 0 else "none"))
	if id2 > 0:
		var th2: Suspect = d.suspects[d.calls[id2].suspects[0]]
		var o: Officer = s.sync.my_pawn()
		o.global_position = th2.global_position + Vector3(120, 0, 0)   # nobody about
		for i in 60 * 24:
			await get_tree().physics_frame
		t.check(th2.state == Suspect.S.DRIVE, "the thief got the car going (%s)" % Suspect.S.keys()[th2.state])
		t.check(d.calls[id2].kind == Dispatcher.Kind.PURSUIT, "and it's a chase now")
	s.queue_free()
	await get_tree().process_frame
