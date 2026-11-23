extends Node
## Shouted orders: the order fits whoever you're facing, some do as they're
## told and some don't, prisoners stay put or follow on command, and a
## prisoner left alone can do a runner in cuffs and be caught again.
var t
var cars: CarSync
var dispatch: Dispatcher
var nav: BlockNav
var gen: BlockGenerator


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


func _cmd(buttons := 0, move := Vector2.ZERO, yaw := 0.0) -> Dictionary:
	return {"move": move, "buttons": buttons, "aim_yaw": yaw, "aim_point": Vector3.ZERO}


func _last_kind() -> int:
	return Voices.LINES[Voices.history.back().line][2] if not Voices.history.is_empty() else -1


func test_voice_lines_exist() -> void:
	var missing := []
	for i in Voices.LINES.size():
		for v in range(1, Voices.VOICES + 1):
			if Voices.stream(i, v) == null:
				missing.append("%s_%d" % [Voices.LINES[i][0], v])
	t.check(missing.is_empty(), "every line has its three recordings (missing: %s)" % [missing])


func test_the_order_fits_the_target() -> void:
	await _block()
	var p := nav.closest(Vector3(24, BlockGenerator.BASE_Y + 0.05, 1.5))
	var o := _officer(p + Vector3(0, 0, -8))
	await get_tree().physics_frame
	# Nobody about.
	o.shout()
	t.check(_last_kind() == Voices.Kind.GENERIC, "nobody about: \"%s\"" % Voices.LINES[Voices.history.back().line][1])
	# Someone armed in front (aim_yaw 0 faces +z, where they stand).
	var a := dispatch.spawn_suspect(p, Suspect.S.HIDE, true)
	a.fighter = true
	a._check_t = 100.0
	await get_tree().physics_frame
	t.check(o._bark_target() == a, "the shout is aimed at the suspect in front")
	o.shout_t = 0.0
	o.shout()
	t.check(_last_kind() == Voices.Kind.ARMED, "armed: \"%s\"" % Voices.LINES[Voices.history.back().line][1])
	a.set_state(Suspect.S.BOOKED)
	await get_tree().physics_frame
	var u := dispatch.spawn_suspect(p, Suspect.S.HIDE, false)
	u._check_t = 100.0
	await get_tree().physics_frame
	o.shout_t = 0.0
	o.shout()
	t.check(_last_kind() == Voices.Kind.HANDS, "unarmed: \"%s\"" % Voices.LINES[Voices.history.back().line][1])
	# Behind you and far away: not the one you're shouting at.
	o.aim_yaw = PI
	t.check(o._bark_target() == null, "not facing them past 6 m: no target")


func test_some_obey_some_dont() -> void:
	await _block()
	var p := nav.closest(Vector3(24, BlockGenerator.BASE_Y + 0.05, 1.5))
	var o := _officer(p + Vector3(0, 0, -6))
	await get_tree().physics_frame
	var counts := {}
	for kind in ["unarmed", "armed", "fighter"]:
		var gave := 0
		for i in 24:
			var s := dispatch.spawn_suspect(p + Vector3((i % 6) * 0.8 - 2.0, 0, (i / 6) * 0.8), Suspect.S.HIDE, kind != "unarmed")
			s.fighter = kind == "fighter"
			s._rng.seed = 1000 + i * 31
			s.on_shout(o.global_position, Officer.SHOUT_RANGE, s)
			if s.state == Suspect.S.SURRENDER:
				gave += 1
				if kind != "unarmed" and s.armed:
					t.check(false, "gave up but still holding a gun")
			s.set_state(Suspect.S.BOOKED)
		counts[kind] = gave
		await get_tree().physics_frame
	print("    gave up on the first order out of 24: %s" % [counts])
	t.check(counts.unarmed > 10 and counts.unarmed < 24, "most unarmed do as they're told, not all")
	t.check(counts.armed > 2 and counts.armed < counts.unarmed, "fewer armed ones")
	t.check(counts.fighter >= 1 and counts.fighter <= counts.armed, "hardened fighters rarely")
	# Keep shouting: an unarmed one who ignored you gives up on the second.
	var s2 := dispatch.spawn_suspect(p, Suspect.S.HIDE, false)
	s2._check_t = 100.0
	for i in 2:
		s2.on_shout(o.global_position, Officer.SHOUT_RANGE, s2)
	t.check(s2.state == Suspect.S.SURRENDER, "second order: hands on head (%s)" % Suspect.S.keys()[s2.state])
	for i in 30:
		await get_tree().physics_frame
	t.check(s2.rig.procedural.head_hands > 0.5, "hands going onto the head (%.2f)" % s2.rig.procedural.head_hands)


func test_prisoner_stays_and_follows() -> void:
	await _block()
	var p := nav.closest(Vector3(24, BlockGenerator.BASE_Y + 0.05, 1.5))
	var o := _officer(p + Vector3(0, 0, -1.2))
	var s := dispatch.spawn_suspect(p, Suspect.S.SURRENDER, false)
	s.cuff(o)
	s._runner = false
	await _run(o, _cmd(), 10)
	# Nobody else about: a tap is an order for the prisoner.
	await _run(o, _cmd(PlayerInput.SHOUT), 1)
	await _run(o, _cmd(), 2)
	t.check(s.stay and s.state == Suspect.S.CUFFED, "\"Stay right there!\": stays put")
	t.check(_last_kind() == Voices.Kind.STAY, "said: \"%s\"" % Voices.LINES[Voices.history.back().line][1])
	var at := s.global_position
	await _run(o, _cmd(0, Vector2(1, 0)), 90)
	t.check(s.global_position.distance_to(at) < 0.5, "didn't follow (moved %.2f m)" % s.global_position.distance_to(at))
	# Back over: "With me!"
	o.global_position = s.global_position + Vector3(0, 0, -2.0)
	await _run(o, _cmd(), 3)
	o.shout_t = 0.0
	await _run(o, _cmd(PlayerInput.SHOUT), 1)
	await _run(o, _cmd(), 2)
	t.check(not s.stay and s.escort == o, "\"With me!\": walking with the officer again")
	await _run(o, _cmd(0, Vector2(1, 0)), 90)
	t.check(s.global_position.distance_to(o.global_position) < 2.5, "kept up: %.2f m" % s.global_position.distance_to(o.global_position))
	# Holding the button gives the prisoner order even with a crook in front.
	var c := dispatch.spawn_suspect(o.global_position + Vector3(0, 0, 4), Suspect.S.HIDE, false)
	c._check_t = 100.0
	o.shout_t = 0.0
	await _run(o, _cmd(PlayerInput.SHOUT), 40)
	await _run(o, _cmd(), 1)
	t.check(s.stay, "held: the prisoner is told to stay")


func test_left_alone_runs_and_is_caught() -> void:
	await _block()
	var p := nav.closest(Vector3(24, BlockGenerator.BASE_Y + 0.05, 1.5))
	var o := _officer(p + Vector3(0, 0, -1.2))
	var s := dispatch.spawn_suspect(p, Suspect.S.SURRENDER, false)
	s.cuff(o)
	s.order_stay()
	s._runner = true
	s._run_after = 1.0
	o.global_position = p + Vector3(60, 0, 0)
	for i in 240:
		await get_tree().physics_frame
		if s.state == Suspect.S.CUFF_RUN:
			break
	t.check(s.state == Suspect.S.CUFF_RUN, "left alone: does a runner in cuffs (%s)" % Suspect.S.keys()[s.state])
	for i in 60:
		await get_tree().physics_frame
	t.check(s.global_position.distance_to(p) > 1.5, "and gets moving: %.1f m" % s.global_position.distance_to(p))
	# Caught up with: the officer can grab them.
	o.global_position = s.global_position + Vector3(0, 0, -1.0)
	o.velocity = Vector3.ZERO
	t.check(o.cuff_target() == s, "close enough to grab the runner")
	# A shove stops them dead.
	s.struck(Vector3.FORWARD, Melee.OFFICER_DAMAGE[Officer.Strike.PUNCH], 2.0)
	t.check(s.state == Suspect.S.CUFFED and s.stay, "knocked down: back on their knees, still cuffed")
	# Grab them: they walk with the officer again.
	s.cuff(o)
	t.check(s.state == Suspect.S.CUFFED and not s.stay and s.escort == o, "grabbed: walking with the officer")
