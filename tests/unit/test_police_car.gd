extends Node
## Phase 1.3: the police car, its seats, lights and siren, damage, the boot,
## and injuries.
var t
var cars: CarSync


func _setup() -> PoliceCar:
	ProtoWorld.ground(self, 400.0)
	cars = CarSync.new()
	cars.use_seats = true
	add_child(cars)
	var pc := PoliceCar.new()
	pc.position = Vector3(0, 1.0, 0)
	add_child(pc)
	cars.add_car(pc)
	return pc


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


func _cmd(buttons := 0, move := Vector2.ZERO) -> Dictionary:
	return {"move": move, "buttons": buttons, "aim_yaw": 0.0}


func test_model_parts_and_glass() -> void:
	var pc := _setup()
	await get_tree().physics_frame
	for n in ["door_fl", "door_fr", "door_rl", "door_rr", "bonnet", "boot", "bumper_f", "bumper_r", "mirror_l", "mirror_r"]:
		t.check(pc.has_part(n), "part " + n)
	t.check(pc.glass.size() == 6, "six windows: %d" % pc.glass.size())
	t.check(pc._deform.size() >= 6, "body and panels dent: %d" % pc._deform.size())
	for i in 90:
		await get_tree().physics_frame
	print("    police car ride height %.2f" % pc.global_position.y)
	t.check(pc.global_position.y > 0.4 and pc.global_position.y < 1.1, "sits on its wheels")
	# A hard side hit dents the door and takes the mirror; more knocks the door off.
	var before := pc.dent_amount()
	pc.apply_dent(Vector3(-0.95, 0.1, 0.4), Vector3.RIGHT, 0.2)
	t.check(pc.dent_amount() > before + 0.05, "dented: %.2f" % pc.dent_amount())
	t.check(not pc.has_part("mirror_l"), "mirror knocked off")
	pc.apply_dent(Vector3(-0.95, 0.1, 0.4), Vector3.RIGHT, 0.3)
	pc.apply_dent(Vector3(-0.95, 0.0, 0.3), Vector3.RIGHT, 0.3)
	t.check(not pc.has_part("door_fl"), "front left door off after a beating")
	t.check(pc.has_part("door_fr"), "the other side is fine")
	t.check(get_tree().get_nodes_in_group("car_debris").size() >= 2, "parts are loose bodies")
	# A bullet through the windscreen breaks it.
	var w := pc.window_at((pc.glass["win_front"].box as AABB).get_center())
	t.check(w == "win_front", "window found at its centre: %s" % w)
	pc.shatter(w)
	t.check(pc.window_broken("win_front") and not pc.glass["win_front"].node.visible, "windscreen shattered")


func test_lights_and_siren_cycle() -> void:
	var pc := _setup()
	await get_tree().process_frame
	var seen := []
	for i in 4:
		pc.cycle_lights()
		seen.append([pc.lights, pc.siren])
	t.check(seen == [[true, 0], [true, 1], [true, 2], [false, 0]], "off, lights, wail, yelp, off: %s" % [seen])
	pc.lights = true
	pc.siren = 1
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(pc._siren_player.playing, "siren sounds")
	var b := StreamPeerBuffer.new()
	pc.encode_state(b)
	b.seek(0)
	var s := cars._decode(0, b)
	t.check(s.lights == true and s.siren == 1, "lights and siren in the car state: %s" % [s])


func test_three_officers_get_in_swap_and_get_out() -> void:
	var pc := _setup()
	for i in 60:
		await get_tree().physics_frame
	var a := _officer(pc.door_point(0) * Vector3(1, 0, 1) + Vector3(0, 0.1, 0), 1)
	var b := _officer(pc.door_point(1) * Vector3(1, 0, 1) + Vector3(0, 0.1, 0), 2)
	var c := _officer(pc.door_point(0) * Vector3(1, 0, 1) + Vector3(0.2, 0.1, -0.3), 3)
	for i in 20:
		a.sim_step(_cmd(), 1.0 / 60.0)
		b.sim_step(_cmd(), 1.0 / 60.0)
		c.sim_step(_cmd(), 1.0 / 60.0)
		await get_tree().physics_frame
	await _run(a, _cmd(PlayerInput.INTERACT), 1)
	t.check(a.state == Officer.S.VEHICLE and a.seat == 0, "driver in: seat %d" % a.seat)
	await _run(b, _cmd(PlayerInput.INTERACT), 1)
	t.check(b.state == Officer.S.VEHICLE and b.seat == 1, "front passenger in: seat %d" % b.seat)
	await _run(c, _cmd(PlayerInput.INTERACT), 1)
	t.check(c.state == Officer.S.VEHICLE and c.seat >= 2, "third officer takes a back seat: %d" % c.seat)
	t.check(pc.occupants().size() == 3, "three in the car")
	t.check(cars.driver_of(0) == 1 and cars.car_for(1) == 0, "officer 1 drives car 0")
	# Driving: the officers ride along. (The test drives the car itself.)
	cars.set_physics_process(false)
	pc.handbrake = false
	pc.throttle = 1.0
	for i in 60:
		a.sim_step(_cmd(), 1.0 / 60.0)
		b.sim_step(_cmd(), 1.0 / 60.0)
		await get_tree().physics_frame
	pc.throttle = 0.0
	t.check(pc.linear_velocity.length() > 3.0, "car moving")
	t.check(a.global_position.distance_to(pc.seat_point(0)) < 0.2, "driver in the seat as it moves")
	# Passenger leans out to aim; the driver can't.
	b.sim_step({"move": Vector2.ZERO, "buttons": PlayerInput.AIM, "aim_yaw": PI * 0.5}, 1.0 / 60.0)
	t.check(b.is_aiming(), "passenger aims out of the window")
	a.sim_step({"move": Vector2.ZERO, "buttons": PlayerInput.AIM, "aim_yaw": 0.0}, 1.0 / 60.0)
	t.check(not a.is_aiming(), "driver keeps both hands on the wheel")
	# Swap: the back-seat officer moves up when the passenger gets out.
	pc.brake = 1.0
	for i in 120:
		await get_tree().physics_frame
	await _run(b, _cmd(PlayerInput.INTERACT), 1)
	t.check(b.state == Officer.S.MOVE and b.car == null, "passenger got out")
	t.check(b.global_position.distance_to(pc.global_position) > 1.0, "outside the car: %.2f m" % b.global_position.distance_to(pc.global_position))
	await _run(c, _cmd(PlayerInput.CROUCH), 1)
	t.check(c.seat != 0 and c.seat != 2 or c.seat == 1, "shuffled to a free seat: %d" % c.seat)
	await _run(a, _cmd(PlayerInput.INTERACT), 1)
	t.check(a.state == Officer.S.MOVE and cars.car_for(1) == -1, "driver out; nobody drives")


func test_boot_restocks_and_injuries_are_treated() -> void:
	var pc := _setup()
	for i in 60:
		await get_tree().physics_frame
	var o := _officer(pc.boot_point() * Vector3(1, 0, 1) + Vector3(0, 0.1, -0.3))
	await _run(o, _cmd(), 30)
	o.reserve = 3
	o.pouch = 0
	o.injuries = Officer.LEG | Officer.BLEED
	await _run(o, _cmd(PlayerInput.INTERACT), int(Officer.BOOT_TIME * 60) + 5)
	t.check(o.reserve == Officer.RESERVE_MAX and o.pouch == Officer.POUCH_MAX and o.injuries == 0,
		"boot: ammo %d, first aid %d, injuries %d" % [o.reserve, o.pouch, o.injuries])
	# Away from the car: wounds slow you, bleeding drains health, and you
	# treat yourself one wound at a time.
	await _run(o, _cmd(0, Vector2(0, -1)), 60)
	o.injuries = Officer.LEG | Officer.ARM | Officer.BLEED
	var hp0 := o.hp
	await _run(o, _cmd(0, Vector2(1, 0)), 60)
	var v := Vector2(o.velocity.x, o.velocity.z).length()
	t.check(v <= Officer.LIMP_SPEED + 0.05, "limping: %.2f m/s" % v)
	t.check(o.hp < hp0 - 0.8, "bleeding: %.1f -> %.1f" % [hp0, o.hp])
	t.check(o.rig._lower == "limp", "limp clip: %s" % o.rig._lower)
	await _run(o, _cmd(PlayerInput.INTERACT), int(Officer.TREAT_SELF * 60) + 3)
	t.check(not o.injuries & Officer.BLEED and o.pouch == Officer.POUCH_MAX - 1, "bandaged first: injuries %d pouch %d" % [o.injuries, o.pouch])
	await _run(o, _cmd(), 2)
	await _run(o, _cmd(PlayerInput.INTERACT), int(Officer.TREAT_SELF * 60) + 3)
	t.check(not o.injuries & Officer.LEG, "leg splinted")
	# A teammate treats faster.
	var m := _officer(o.global_position + Vector3(0.8, 0, 0), 2)
	await _run(m, _cmd(), 3)
	await _run(m, _cmd(PlayerInput.INTERACT), int(Officer.TREAT_MATE * 60) + 3)
	t.check(o.injuries == 0, "teammate treated the arm: %d" % o.injuries)


func test_wounds_by_where_you_are_hit() -> void:
	ProtoWorld.ground(self, 40.0)
	var o := _officer(Vector3.ZERO)
	await get_tree().physics_frame
	t.check(o.body_part_at(o.global_position + Vector3(0, 0.5, 0)) == "leg", "shin is a leg")
	t.check(o.body_part_at(o.global_position + Vector3(0, 1.3, 0)) == "torso", "chest is torso")
	var legs := 0
	for i in 20:
		o.injuries = 0
		o.hp = 100.0
		o.take_damage(10.0, Vector3.ZERO, "leg")
		if o.injuries & Officer.LEG:
			legs += 1
	t.check(legs >= 8, "leg hits usually leave a leg wound: %d of 20" % legs)


## Phase 1.7: beenster got in on the passenger side and WASD did nothing.
## Into an empty car, from any door, you take the wheel.
func test_getting_in_alone_puts_you_at_the_wheel() -> void:
	var pc := _setup()
	for i in 60:
		await get_tree().physics_frame
	var a := _officer(pc.door_point(1) * Vector3(1, 0, 1) + Vector3(0, 0.1, 0), 1)
	for i in 20:
		a.sim_step(_cmd(), 1.0 / 60.0)
		await get_tree().physics_frame
	await _run(a, _cmd(PlayerInput.INTERACT), 1)
	t.check(a.state == Officer.S.VEHICLE and a.seat == 0, "in by the passenger door, at the wheel: seat %d" % a.seat)
	t.check(cars.car_for(1) == 0, "and driving")
