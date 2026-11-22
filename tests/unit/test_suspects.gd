extends Node
## Phase 1.4: suspects run and hide, give up, get cuffed, go in the car and
## are booked at the custody bay; the dispatcher's calls, the speeding car
## and the calls (no crime meter since v0.2.11).
var t
var cars: CarSync
var dispatch: Dispatcher
var nav: BlockNav
var gen: BlockGenerator


## A generated block with its navigation mesh and a dispatcher (no calls
## coming in by themselves).
func _block() -> void:
	ProtoWorld.ground(self, 400.0)
	var w := DestructionWorld.new()
	add_child(w)
	gen = CityBlock.build(w, 4242)
	cars = CarSync.new()
	cars.use_seats = true
	cars.destruction = w
	add_child(cars)
	nav = BlockNav.new()
	add_child(nav)
	await get_tree().physics_frame
	nav.bake_from(self)
	dispatch = Dispatcher.new()
	dispatch.enabled = false
	add_child(dispatch)
	dispatch.setup(gen, w, cars, nav, null)
	for i in 120:
		await get_tree().physics_frame
		if nav.ready_to_use and not dispatch.hide_spots.is_empty():
			break


func _officer(pos: Vector3, id := 1) -> Officer:
	var o := Officer.new()
	o.peer_id = id
	o.holstered = false
	o.position = pos
	add_child(o)
	return o


func _run(o: Officer, cmd: Dictionary, frames: int) -> void:
	for i in frames:
		o.sim_step(cmd, 1.0 / 60.0)
		await get_tree().physics_frame


func _cmd(buttons := 0, move := Vector2.ZERO, aim := Vector3.ZERO) -> Dictionary:
	return {"move": move, "buttons": buttons, "aim_yaw": 0.0, "aim_point": aim}


func test_nav_mesh_reaches_inside_and_upstairs() -> void:
	await _block()
	t.check(nav.ready_to_use, "navigation mesh baked and in use")
	var b: Dictionary = gen.buildings.filter(func(x): return x.enterable and x.storeys > 1)[0]
	var inside: Vector3 = b.origin + b.u * 6.0 + b.v * 5.0 + Vector3(0, 0.1, 0)
	var start := Vector3(24, 0.2, -6)
	t.check(nav.reaches(start, nav.closest(inside)), "a path from the road into a building")
	var up := nav.closest(inside + Vector3(0, BlockGenerator.STOREY, 0))
	t.check(up.y > 3.0, "the upper floor is walkable: y=%.2f" % up.y)
	t.check(nav.reaches(start, up), "and up the stairs")
	var upstairs := dispatch.hide_spots.filter(func(p): return p.y > 3.0)
	t.check(dispatch.hide_spots.size() > 8 and upstairs.size() > 0, "hide spots: %d (%d upstairs)" % [dispatch.hide_spots.size(), upstairs.size()])


func test_suspect_runs_and_hides() -> void:
	await _block()
	var p := nav.closest(Vector3(24, BlockGenerator.BASE_Y + 0.05, 1.5))
	var s := dispatch.spawn_suspect(p, Suspect.S.LOITER, false)
	var o := _officer(p + Vector3(6, 0, -3))
	await get_tree().physics_frame
	await get_tree().physics_frame
	t.check(s.state == Suspect.S.FLEE, "sees the officer and runs: %s" % Suspect.S.keys()[s.state])
	for i in 1500:
		await get_tree().physics_frame
		if s.state == Suspect.S.HIDE:
			break
	t.check(s.state == Suspect.S.HIDE, "got somewhere and hides: %s (at %s, goal %s)" % [Suspect.S.keys()[s.state], s.global_position, s._goal])
	print("    hid at %s, %.1f m from the officer" % [s.global_position, s.global_position.distance_to(o.global_position)])
	t.check(s.global_position.distance_to(o.global_position) > 10.0, "well away from the officer")


func test_aiming_makes_them_give_up_then_cuff() -> void:
	await _block()
	var p := nav.closest(Vector3(24, BlockGenerator.BASE_Y + 0.05, 1.5))
	var s := dispatch.spawn_suspect(p, Suspect.S.HIDE, false)
	s._check_t = 100.0   # no coin toss to bolt: this test is about the aim
	var o := _officer(p + Vector3(0, 0, -6))
	var chest := s.global_position + Vector3(0, 1.2, 0)
	await _run(o, _cmd(PlayerInput.AIM, Vector2.ZERO, chest), 150)
	t.check(s.state == Suspect.S.SURRENDER, "an officer's gun on them: gives up (%s, pressure %.2f)" % [Suspect.S.keys()[s.state], s.pressure])
	t.check(not s.armed, "nothing in their hands")
	# Walk up and hold interact.
	o.global_position = s.global_position + Vector3(0, 0, -1.0)
	await _run(o, _cmd(), 2)
	t.check(o.cuff_target() == s, "the officer can cuff them")
	await _run(o, _cmd(PlayerInput.INTERACT), 80)
	t.check(s.state == Suspect.S.CUFFED and s.escort == o, "cuffed, and following this officer")
	# They follow.
	await _run(o, _cmd(0, Vector2(1, 0)), 90)
	t.check(s.global_position.distance_to(o.global_position) < 2.5, "kept up with the officer: %.2f m" % s.global_position.distance_to(o.global_position))


func test_punch_knocks_the_fight_out() -> void:
	await _block()
	var p := nav.closest(Vector3(24, BlockGenerator.BASE_Y + 0.05, 1.5))
	var s := dispatch.spawn_suspect(p, Suspect.S.FLEE, false)
	s.struck(Vector3.FORWARD, Melee.OFFICER_DAMAGE[Officer.Strike.PUNCH], 2.5)
	t.check(s.state == Suspect.S.STAGGER, "staggered by a punch: %s" % Suspect.S.keys()[s.state])
	for i in 90:
		await get_tree().physics_frame
	t.check(s.state == Suspect.S.SURRENDER, "then gives up: %s" % Suspect.S.keys()[s.state])
	# A real punch from an officer lands on a suspect.
	var o := _officer(p + Vector3(0, 0, -0.9))
	for i in 3:
		await get_tree().physics_frame
	var hp := s.hp
	Melee.resolve(o, null, o.global_position + Vector3(0, 1.3, 0), Vector3(0, 0, 1), Officer.Strike.PUNCH)
	t.check(s.hp < hp, "the punch connects: %.0f -> %.0f hp" % [hp, s.hp])
	# Shot down instead: dealt with all the same (no conduct penalty).
	var s2 := dispatch.spawn_suspect(p + Vector3(3, 0, 0), Suspect.S.FLEE, true)
	for i in 3:
		s2.take_damage(Gunfire.BULLET_DAMAGE, Vector3.FORWARD)
	t.check(s2.state == Suspect.S.DOWN and s2.is_done(), "three hits put a suspect down")


func test_prisoner_goes_in_the_car_and_is_booked() -> void:
	await _block()
	var bay := dispatch.bay_position()
	var pc := PoliceCar.new()
	pc.position = Vector3(bay.x, 1.0, bay.z - 20.0)
	add_child(pc)
	cars.add_car(pc)
	var o := _officer(pc.door_point(2) * Vector3(1, 0, 1) + Vector3(0, BlockGenerator.BASE_Y, 0))
	var s := dispatch.spawn_suspect(o.global_position + Vector3(0, 0, -1.2), Suspect.S.SURRENDER, false)
	s.cuff(o)
	for i in 30:
		await get_tree().physics_frame
	await _run(o, _cmd(), 2)
	t.check(o.prisoner() == s, "walking a prisoner")
	await _run(o, _cmd(PlayerInput.INTERACT), 1)
	await _run(o, _cmd(), 2)
	t.check(s.state == Suspect.S.IN_CAR and s.car == pc and s.seat in [2, 3], "in the back of the car (seat %d)" % s.seat)
	t.check(pc.occupants().get(s.seat) == s, "the seat is taken")
	t.check(o.state != Officer.S.VEHICLE, "the officer stayed outside")
	# Drive (place) the car on the bay and stop.
	pc.global_position = Vector3(bay.x, 1.0, bay.z)
	pc.linear_velocity = Vector3.ZERO
	for i in 120:
		await get_tree().physics_frame
		if s.state == Suspect.S.BOOKED:
			break
	t.check(s.state == Suspect.S.BOOKED, "booked into custody at the bay: %s" % Suspect.S.keys()[s.state])
	t.check(not pc.occupants().has(s.seat), "the seat is free again")


func test_calls() -> void:
	await _block()
	var id := dispatch.start_call(Dispatcher.Kind.ROBBERY)
	t.check(id > 0 and dispatch.calls[id].suspects.size() == 2, "a robbery call with two suspects")
	var s1: Suspect = dispatch.suspects[dispatch.calls[id].suspects[0]]
	t.check(s1.state == Suspect.S.ROB, "robbers start inside, at it")
	var inside := false
	for b in gen.buildings:
		if (b.bounds as AABB).has_point(s1.global_position + Vector3(0, 0.5, 0)):
			inside = true
	t.check(inside, "the robbery is inside a building")
	for i in 60:
		await get_tree().physics_frame
	for sid in dispatch.calls[id].suspects:
		(dispatch.suspects[sid] as Suspect).take_damage(500.0, Vector3.FORWARD)
	for i in 3:
		await get_tree().physics_frame
	t.check(dispatch.calls[id].state == Dispatcher.CallState.CLOSED, "call closed when both suspects are dealt with")
	var aid := dispatch.start_call(Dispatcher.Kind.ARMED)
	var a: Suspect = dispatch.suspects[dispatch.calls[aid].suspects[0]]
	t.check(a.armed and a.state == Suspect.S.LOITER, "an armed suspect out on the street")


func test_speeding_car_laps_and_pulls_over() -> void:
	ProtoWorld.ground(self, 400.0)
	cars = CarSync.new()
	cars.use_seats = true
	add_child(cars)
	var car := Car.new()
	car.position = Vector3(20, 1.0, -6)
	car.rotation_degrees.y = 90.0     # facing +x, the lap's direction on the north road
	add_child(car)
	cars.add_car(car)
	dispatch = Dispatcher.new()
	dispatch.enabled = false
	add_child(dispatch)
	dispatch.setup(null, null, cars, null, car)
	var id := dispatch.start_call(Dispatcher.Kind.TRAFFIC)
	t.check(id > 0, "traffic stop call")
	var start := car.global_position
	for i in 300:
		await get_tree().physics_frame
	var moved := car.global_position - start
	print("    car went from %s to %s" % [start, car.global_position])
	t.check(moved.x > 20.0 or moved.z > 5.0, "drives on along the lap")
	t.check(absf(car.global_position.z + 6.0) < 4.0 or absf(car.global_position.x - 54.0) < 4.0, "stays on the road")
	# A police car close behind with its lights on.
	var pc := PoliceCar.new()
	var back := -car.global_transform.basis.z
	add_child(pc)
	pc.global_position = car.global_position + back * 8.0 + Vector3(0, 0.1, 0)
	cars.add_car(pc)
	pc.lights = true
	for i in 360:
		pc.global_position = car.global_position + (-car.global_transform.basis.z) * 8.0
		await get_tree().physics_frame
		if dispatch._traffic.phase == "pulled" and car.linear_velocity.length() < 0.5:
			break
	t.check(dispatch._traffic.phase == "pulled", "pulls over for the lights")
	t.check(car.linear_velocity.length() < 1.0, "and stops: %.2f m/s" % car.linear_velocity.length())
	# Walk up to it: it goes wrong.
	var o := _officer(car.global_position + car.global_transform.basis.x * 2.5)
	o.global_position.y = 0.05
	for i in 90:
		await get_tree().physics_frame
	var s: Suspect = dispatch.suspects[dispatch.calls[id].suspects[0]]
	t.check(dispatch._traffic.phase == "bailed" and s.state in [Suspect.S.FLEE, Suspect.S.SHOOT], "the driver bails: %s" % Suspect.S.keys()[s.state])


func test_suspect_state_round_trip() -> void:
	var s := Suspect.new()
	s.net_id = 12
	s.look = 77
	s.armed = true
	s.state = Suspect.S.FLEE
	s.escort_peer = 1234567890
	add_child(s)
	s.global_position = Vector3(3, 1, 4)
	var b := StreamPeerBuffer.new()
	s.encode(b)
	b.seek(0)
	var d := Suspect.decode(b)
	t.check(d.id == 12 and d.look == 77 and d.armed and d.state == Suspect.S.FLEE, "id, look, armed, state")
	t.check((d.pos as Vector3).distance_to(Vector3(3, 1, 4)) < 0.01, "position")
	var c := Suspect.new()
	add_child(c)
	c.apply_net(d)
	t.check(c.state == Suspect.S.FLEE and c.armed, "applied on a client")
