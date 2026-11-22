extends Node
## Phase 1.5: the mess a fight makes. Furniture and loose things that break
## like what they are, barrels and gas bottles that blow up, fire that
## spreads and burns out, extinguishers that put it out, cars that smoke,
## burn and go up, and the camera feeling it.
var t
var world: DestructionWorld
var props: PropWorld
var fire: FireSystem
var cars: CarSync


func _scene() -> void:
	Sfx.history.clear()
	ProtoWorld.ground(self, 200.0)
	world = DestructionWorld.new()
	add_child(world)
	world.finalize()
	cars = CarSync.new()
	cars.use_seats = true
	cars.destruction = world
	add_child(cars)
	props = PropWorld.new()
	props.world = world
	props.cars = cars
	add_child(props)
	fire = FireSystem.new()
	fire.world = world
	fire.props = props
	fire.cars = cars
	add_child(fire)
	var gs := GameSounds.new()
	gs.world = world
	gs.cars = cars
	add_child(gs)
	await get_tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _officer(pos: Vector3) -> Officer:
	var o := Officer.new()
	o.peer_id = 1
	o.position = pos
	add_child(o)
	return o


func _stems() -> Array:
	return Sfx.history.map(func(s): return s.stem)


func _at(kind: String, p: Vector3) -> int:
	return props.add_prop(kind, Transform3D(Basis(), p))


func test_the_block_is_furnished_and_nothing_is_stuck_in_a_wall() -> void:
	ProtoWorld.ground(self, 400.0)
	world = DestructionWorld.new()
	add_child(world)
	var gen := CityBlock.build(world, 4242)
	props = PropWorld.new()
	props.world = world
	add_child(props)
	props.furnish(gen)
	var kinds := {}
	for p in props.props.values():
		kinds[p.kind] = int(kinds.get(p.kind, 0)) + 1
	print("    props: %s" % [kinds])
	t.check(props.props.size() >= 25, "plenty of things about: %d" % props.props.size())
	var enterable := gen.buildings.filter(func(b): return b.enterable).size()
	t.check(int(kinds.get("extinguisher", 0)) == enterable, "an extinguisher in each building you can go in")
	t.check(kinds.has("chair") and kinds.has("table") and kinds.has("shelf"), "furniture indoors")
	t.check(kinds.has("barrel") or kinds.has("gas"), "something that goes bang")
	var start := {}
	for p in props.props.values():
		start[p.id] = (p.body as RigidBody3D).global_position
	# Wake everything and let it settle: anything placed inside a wall is
	# pushed out hard, anything in the air falls.
	for p in props.props.values():
		(p.body as RigidBody3D).sleeping = false
	await _frames(90)
	var moved := []
	for p in props.props.values():
		if p.broken:
			moved.append("%s broke" % p.kind)
			continue
		var d := (p.body as RigidBody3D).global_position.distance_to(start[p.id])
		if d > 0.35:
			moved.append("%s %.2f m" % [p.kind, d])
	t.check(moved.size() <= 1, "everything stands where it was put: %s" % [moved])


func test_shooting_furniture_breaks_it() -> void:
	await _scene()
	var chair := _at("chair", Vector3(0, 0, 5))
	var crate := _at("crate", Vector3(3, 0, 5))
	await _frames(2)
	var rb := props.body(chair)
	world.bullet_hit(rb, rb.global_position, Vector3.BACK, Vector3.FORWARD)
	t.check(not props.props[chair].broken, "one round chips it")
	world.bullet_hit(rb, rb.global_position, Vector3.BACK, Vector3.FORWARD)
	t.check(props.props[chair].broken, "two and the chair goes")
	t.check(_stems().has("break_wood"), "splintering: %s" % [_stems()])
	await _frames(2)
	t.check(not is_instance_valid(rb) or rb.is_queued_for_deletion(), "it's gone")
	# A kick does it too.
	props.damage_prop(crate, Melee.PIECE_DAMAGE[Officer.Strike.KICK] * 0.6, Vector3(3, 0.3, 5))
	props.damage_prop(crate, Melee.PIECE_DAMAGE[Officer.Strike.KICK] * 0.6, Vector3(3, 0.3, 5))
	t.check(props.props[crate].broken, "two kicks smash a crate")


func test_thrown_things_break_on_what_they_hit() -> void:
	await _scene()
	ProtoWorld.block(self, Vector3(6, 3, 0.4), Vector3(0, 1.5, -4), Color.GRAY, "Wall")
	var bottle := _at("bottle", Vector3(0, 1.0, 0))
	var chair := _at("chair", Vector3(2, 0.5, 0))
	await _frames(1)
	props.body(bottle).linear_velocity = Vector3(0, 1, -11)
	props.body(chair).linear_velocity = Vector3(-1, 2, -12)
	await _frames(60)
	t.check(props.props[bottle].broken, "a bottle smashes on the wall")
	t.check(_stems().has("glass_break"), "with a smash")
	t.check(props.props[chair].broken, "and so does a chair thrown hard")


func test_a_barrel_blows_up_and_starts_a_fire() -> void:
	await _scene()
	var o := _officer(Vector3(2.5, 0.05, 0))
	var barrel := _at("barrel", Vector3(0, 0, 0))
	var crate := _at("crate", Vector3(-1.6, 0, 0))
	var far_chair := _at("chair", Vector3(-12, 0, 0))
	await _frames(3)
	var hp0 := o.hp
	for i in 3:
		var rb := props.body(barrel)
		if rb:
			world.bullet_hit(rb, rb.global_position, Vector3.RIGHT, Vector3.LEFT)
	t.check(props.props[barrel].broken, "three rounds in a red barrel")
	await _frames(3)
	t.check(_stems().has("explosion"), "it goes off: %s" % [_stems()])
	t.check(o.hp < hp0 - 20.0, "and hurts an officer stood next to it: %.0f -> %.0f" % [hp0, o.hp])
	t.check(props.props[crate].broken, "the crate beside it is blown apart")
	t.check(not props.props[far_chair].broken, "a chair 12 m off is fine")
	t.check(fire.fires.size() >= 1, "and it leaves a fire")
	t.check(fire.burning_at(Vector3(0, 0, 0)), "where it was")


func test_fire_spreads_hurts_and_burns_out() -> void:
	await _scene()
	var chair := _at("chair", Vector3(1.2, 0, 0))
	var table := _at("table", Vector3(2.6, 0, 0))
	var bin := _at("bin", Vector3(0, 0, 1.6))
	var o := _officer(Vector3(0, 0.05, 0))
	await _frames(2)
	var id := fire.ignite(Vector3(0, 0, 0), 1.0, 6.0)
	t.check(id >= 0 and _stems().has("fire_whoomph"), "flames catch with a whoomph")
	var hp0 := o.hp
	await _frames(int(3.0 * 60))
	t.check(o.hp < hp0, "standing in it burns: %.0f -> %.0f" % [hp0, o.hp])
	t.check(props.props[chair].burning or props.props[chair].broken, "the chair next to it catches")
	t.check(not props.props[bin].burning, "a metal bin doesn't")
	# The chair burns away and the fire moves on to the table.
	for i in int(12.0 * 60):
		await get_tree().physics_frame
		if props.props[chair].broken:
			break
	t.check(props.props[chair].broken, "the chair burns away")
	for i in int(12.0 * 60):
		await get_tree().physics_frame
		if props.props[table].burning or props.props[table].broken:
			break
	t.check(props.props[table].burning or props.props[table].broken, "and the table next to it catches")
	# Everything burns out in the end.
	for i in int(60.0 * 60):
		await get_tree().physics_frame
		if fire.fires.is_empty():
			break
	t.check(fire.fires.is_empty(), "and it all burns out: %d fires left" % fire.fires.size())


func test_an_extinguisher_puts_fires_out() -> void:
	await _scene()
	var ext := _at("extinguisher", Vector3(0, 0, 0))
	fire.ignite(Vector3(2.0, 0, 0), 1.0, 60.0)
	fire.ignite(Vector3(-1.5, 0, 2.0), 1.0, 60.0)
	fire.ignite(Vector3(12, 0, 0), 1.0, 60.0)
	await _frames(2)
	var rb := props.body(ext)
	world.bullet_hit(rb, rb.global_position, Vector3.UP, Vector3.DOWN)
	t.check(props.props[ext].broken, "one round bursts it")
	t.check(_stems().has("gas_hiss"), "with a hiss")
	t.check(fire.fires.size() == 1, "the two fires round it go out, the far one doesn't: %d left" % fire.fires.size())


func test_cars_smoke_burn_and_go_up() -> void:
	await _scene()
	var c := Car.new()
	c.position = Vector3(0, 1.0, 0)
	add_child(c)
	cars.add_car(c)
	var o := _officer(Vector3(3.5, 0.05, 0))
	await _frames(30)
	var idx := cars.cars.find(c)
	# Shots into the tank, low at the back.
	var tank := c.global_transform * Vector3(0, -0.2, -1.8)
	var n := 0
	while cars.fire_state.get(idx, 0) < CarSync.Fire.SMOKING and n < 40:
		cars.bullet_hit(c, tank, Vector3.FORWARD)
		n += 1
	t.check(cars.fire_state.get(idx, 0) == CarSync.Fire.SMOKING, "shot up, it smokes (after %d rounds)" % n)
	while cars.fire_state.get(idx, 0) < CarSync.Fire.BURNING and n < 80:
		cars.bullet_hit(c, tank, Vector3.FORWARD)
		n += 1
	t.check(cars.fire_state.get(idx, 0) == CarSync.Fire.BURNING, "then catches fire (%d rounds)" % n)
	t.check(n >= 6 and n <= 14, "about ten rounds in the tank: %d" % n)
	t.check(fire.fires.values().any(func(f): return f.car == idx), "flames on it")
	var hp0 := o.hp
	Sfx.history.clear()
	await _frames(int((CarSync.BURN_TIME + 0.5) * 60))
	t.check(cars.fire_state.get(idx, 0) == CarSync.Fire.WRECKED and c.wrecked, "a few seconds later it goes up")
	t.check(_stems().has("explosion"), "with a bang")
	t.check(o.hp < hp0, "and hurts whoever stayed close")
	cars._apply_input(c, {"throttle": 1.0, "steer": 0.5, "handbrake": false})
	t.check(c.throttle == 0.0, "a wreck doesn't drive")


func test_a_bullet_in_the_body_is_not_the_tank() -> void:
	await _scene()
	var c := Car.new()
	c.position = Vector3(0, 1.0, 0)
	add_child(c)
	cars.add_car(c)
	await _frames(10)
	for i in 10:
		cars.bullet_hit(c, c.global_transform * Vector3(0.9, 0.3, 0.5), Vector3.LEFT)
	t.check(cars.fire_state.get(0, 0) == CarSync.Fire.OK, "ten rounds in the door just dent it")


func test_the_camera_feels_it() -> void:
	await _scene()
	var cam := IsoCamera.new()
	add_child(cam)
	var o := _officer(Vector3(0, 0.05, 0))
	cam.target = o
	await _frames(2)
	Blast.go(get_tree(), world, cars, Vector3(4, 0.5, 0), 3.0, 100.0, 8.0)
	t.check(cam.trauma > 0.5, "a blast close by shakes it: %.2f" % cam.trauma)
	for i in 60:
		await get_tree().process_frame
	t.check(cam.trauma < 0.2, "and it settles")
	Feel.hit_marker(get_tree())
	t.check(Time.get_ticks_msec() - Feel.last_hit_ms < 100, "a landed hit marks the reticle")
