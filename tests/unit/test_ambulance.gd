extends Node
## An ambulance comes for the dead: drives to the body, paramedics load it
## on the stretcher, and it drives away.
var t


func _city() -> City:
	City.next_seed = 4242
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	s.dispatch.enabled = false
	s.dispatch.missions.enabled = false
	s.dispatch.stories.enabled = false
	for i in 20:
		await get_tree().physics_frame
	return s


func test_ambulance_model_and_lights() -> void:
	var v := CivilianVehicle.make("ambulance", 0)
	add_child(v)
	await get_tree().physics_frame
	var model := v.get_node_or_null("Model")
	t.check(model != null, "the ambulance model loads")
	t.check(model.find_child("lens_red", true, false) != null and model.find_child("lens_blue", true, false) != null, "it has its blue lights")
	t.check(v.siren_stems[0] == "ambulance_wail", "its own siren")
	t.check(Sfx.stream("ambulance_wail", 1) != null and Sfx.stream("ambulance_hilo", 1) != null, "siren sounds load")
	v.lights = true
	v.siren = 2
	for i in 10:
		await get_tree().process_frame
	t.check(v._siren_player.playing, "the two-tone plays")
	var st := AmbulanceService._make_stretcher()
	add_child(st)
	t.check(AmbulanceService._bag(st) != null, "the stretcher has a body bag")
	v.queue_free()
	st.queue_free()
	await get_tree().process_frame


func test_ambulance_collects_a_body() -> void:
	var s := await _city()
	var amb := s.ambulances
	t.check(amb.ambos.size() == AmbulanceService.COUNT, "%d ambulances built" % amb.ambos.size())
	# Someone killed in the street, away from the station.
	var at: Vector3 = s.gen.pavement_near(CityGenerator.junction(3, 2) + Vector3(14, 0, 4))
	if s.nav and s.nav.ready_to_use:
		at = s.nav.closest(at)
	var body := s.dispatch.spawn_suspect(at, Suspect.S.WANDER, false)
	body.civilian = true
	for i in 10:
		await get_tree().physics_frame
	body.take_damage(999.0, Vector3(1, 0, 0))
	t.check(body.state == Suspect.S.DOWN, "they're dead")
	for i in 5:
		await get_tree().physics_frame
	amb._down[body] = AmbulanceService.WAIT
	await get_tree().physics_frame
	var a: Dictionary = amb.ambos.filter(func(x): return x.state != "idle")[0] if amb.ambos.any(func(x): return x.state != "idle") else {}
	t.check(not a.is_empty(), "an ambulance is sent")
	if a.is_empty():
		s.queue_free()
		return
	var car: CivilianVehicle = a.car
	t.check(car.lights and car.siren > 0, "blue lights and siren on")
	var d0: float = car.global_position.distance_to(at)
	var seen := {}
	var arrived_at := -1
	var gone_at := -1
	var last := ""
	for i in 60 * 260:
		if a.state != last:
			last = a.state
			print("    %.1f s: %s, car %.1f m from the kerb spot, spot %.1f m from the body, %.1f m/s" % [i / 60.0, last, car.global_position.distance_to(a.goal), (a.goal as Vector3).distance_to(at), car.linear_velocity.length()])
		seen[a.state] = true
		if OS.has_environment("AMB_DEBUG") and i % 300 == 0:
			print("      t %d: %s lane %s->%s want %s, %.1f m, %.1f m/s, wi %d/%d" % [i / 60, a.state, a.dr.a, a.dr.b, a.lane, car.global_position.distance_to(a.goal), car.linear_velocity.length(), a.dr.wi, a.dr.pts.size()])
		if a.state == "work" and arrived_at < 0:
			arrived_at = i
			print("    pulled up %.1f m from the body after %.1f s (started %.0f m off)" % [car.global_position.distance_to(at), i / 60.0, d0])
		if gone_at < 0 and not is_instance_valid(body):
			gone_at = i
		if a.state in ["leave", "idle"] and gone_at >= 0:
			break
		await get_tree().physics_frame
	print("    states: %s, collected %d" % [seen.keys(), amb.collected])
	t.check(arrived_at >= 0, "it arrived and the paramedics got out")
	t.check(seen.has("work") and amb.collected == 1, "the body was collected")
	t.check(gone_at >= 0, "the body is gone from the street")
	t.check(a.state in ["leave", "idle"], "it drove away (%s)" % a.state)
	t.check((a.medics as Array).is_empty(), "the paramedics got back in")
	s.queue_free()
	await get_tree().process_frame


func test_scared_paramedics_stop_and_a_fresh_pair_comes() -> void:
	var s := await _city()
	var amb := s.ambulances
	var a: Dictionary = amb.ambos[0]
	var car: CivilianVehicle = a.car
	# Put the ambulance at work by a body right next to it.
	var at := car.global_position - car.global_transform.basis.z * 8.0
	at.y = BlockGenerator.BASE_Y
	if s.nav and s.nav.ready_to_use:
		at = s.nav.closest(at)
	var body := s.dispatch.spawn_suspect(at, Suspect.S.DOWN, false)
	a.bodies = [body]
	a.goal = car.global_position
	a.state = "work"
	a.stage = "out"
	for i in 5:
		await get_tree().physics_frame
	t.check((a.medics as Array).size() == 2, "two paramedics out of the back")
	t.check((a.medics as Array).all(func(m): return (m as Suspect).look >= SuspectLook.PARAMEDIC), "in paramedic green")
	var m0: Suspect = a.medics[0]
	m0.set_state(Suspect.S.COWER)
	m0._calm_t = 30.0
	var stage: String = a.stage
	for i in 120:
		await get_tree().physics_frame
	t.check(a.stage == stage and amb.collected == 0, "one hiding: the job waits")
	for m in a.medics:
		(m as Suspect).set_state(Suspect.S.DOWN)
	a.crew_t = 0.01
	for i in 5:
		await get_tree().physics_frame
	var fresh: int = (a.medics as Array).filter(func(m): return is_instance_valid(m) and (m as Suspect).state == Suspect.S.WANDER).size()
	t.check(fresh == 2, "both down: a fresh pair gets out (%d)" % fresh)
	s.queue_free()
	await get_tree().process_frame
