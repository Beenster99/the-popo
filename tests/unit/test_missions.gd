extends Node
## Wave 3, Phase 3.1: dispatcher version 2. Jobs come from templates
## weighted by district and time of day; every new job starts with its
## people in place; victims and witnesses talk; chance encounters stay
## quiet until an officer finds them.
var t


func _city() -> City:
	City.next_seed = 4242
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	s.dispatch.enabled = false
	s.dispatch.missions.enabled = false
	for i in 60 * 12:
		await get_tree().physics_frame   # walking routes near the station
	return s


func test_jobs_follow_the_clock() -> void:
	var s := await _city()
	var m := s.dispatch.missions
	var night := {}
	var day := {}
	m.minute = 2 * 60.0
	for i in 400:
		var k := m.pick_kind()
		night[k] = night.get(k, 0) + 1
	m.minute = 15 * 60.0
	for i in 400:
		var k := m.pick_kind()
		day[k] = day.get(k, 0) + 1
	var K := Dispatcher.Kind
	print("    night: drunk %d, shoplifting %d;  afternoon: drunk %d, shoplifting %d" % [night.get(K.DRUNK, 0), night.get(K.SHOPLIFT, 0), day.get(K.DRUNK, 0), day.get(K.SHOPLIFT, 0)])
	t.check(night.get(K.DRUNK, 0) > night.get(K.SHOPLIFT, 0), "more drunks than shoplifters at 2 am")
	t.check(day.get(K.SHOPLIFT, 0) > day.get(K.DRUNK, 0), "more shoplifters than drunks in the afternoon")
	t.check(m.clock_text() == "15:00", "the clock reads %s" % m.clock_text())
	t.check(Missions.TEMPLATES.size() >= 10, "%d job templates" % Missions.TEMPLATES.size())
	s.queue_free()
	await get_tree().process_frame


func test_every_new_job_starts() -> void:
	var s := await _city()
	var d := s.dispatch
	var K := Dispatcher.Kind
	for k in [K.MUGGING, K.SHOPLIFT, K.FIGHT, K.DOMESTIC, K.DEAL, K.VANDAL, K.DRUNK]:
		var id := d.start_call(k)
		t.check(id > 0, "%s starts: %s" % [Dispatcher.KIND_NAMES[k], d.calls[id].text if id > 0 else "-"])
		if id > 0:
			t.check(not d.calls[id].suspects.is_empty(), "  with suspects")
	# The fight is a fight, and the vandal breaks things.
	var fight: Dictionary = d.calls.values().filter(func(c): return c.kind == K.FIGHT)[0]
	var a: Suspect = d.suspects[fight.suspects[0]]
	t.check(a.state == Suspect.S.BRAWL, "the two square up")
	var o: Officer = s.sync.my_pawn()
	o.global_position = Vector3(5, 0.2, 5)   # out of everyone's way
	var vandal: Dictionary = d.calls.values().filter(func(c): return c.kind == K.VANDAL)[0]
	var broken_ids: Array = []
	s.world.piece_broken.connect(func(id): broken_ids.append(id))
	for i in 60 * 10:
		await get_tree().physics_frame
	var vs: Suspect = d.suspects[vandal.suspects[0]]
	print("    vandal %s at %s, target %s" % [Suspect.S.keys()[vs.state], vs.global_position, vs.brawl_with])
	t.check(broken_ids.size() > 0, "the vandal smashes windows (%d pieces broken)" % broken_ids.size())
	t.check(a.hp < Suspect.MAX_HP or (d.suspects[fight.suspects[1]] as Suspect).hp < Suspect.MAX_HP, "the brawlers land punches")
	# The drunk doesn't run from an officer.
	var drunk: Dictionary = d.calls.values().filter(func(c): return c.kind == K.DRUNK)[0]
	var dr: Suspect = d.suspects[drunk.suspects[0]]
	o.global_position = dr.global_position + Vector3(3, 0, 0)
	for i in 60 * 3:
		await get_tree().physics_frame
	t.check(dr.state in [Suspect.S.LOITER, Suspect.S.STAGGER], "the drunk doesn't run (%s)" % Suspect.S.keys()[dr.state])
	s.queue_free()
	await get_tree().process_frame


func test_victims_talk_and_encounters_wait_to_be_found() -> void:
	var s := await _city()
	var d := s.dispatch
	var o: Officer = s.sync.my_pawn()
	var said: Array = []
	d.radio.connect(func(x): said.append(x))
	var id := d.start_call(Dispatcher.Kind.MUGGING)
	t.check(id > 0, "a mugging")
	var victim: Suspect = d.missions.people[id].victim
	t.check(victim.part == "victim" and victim.state == Suspect.S.COWER, "the victim is down and shaken")
	o.global_position = victim.global_position + Vector3(1.5, 0, 0)
	for i in 30:
		await get_tree().physics_frame
	var lines := said.filter(func(x): return String(x).begins_with("VICTIM"))
	print("    %s" % [lines])
	t.check(not lines.is_empty(), "the victim describes the mugger")
	# An encounter: quiet until found.
	o.global_position = s._spawn_point(0)
	for i in 10:
		await get_tree().physics_frame
	var eid := -1
	for tries in 10:
		eid = d.missions.start_encounter()
		if eid > 0:
			break
	t.check(eid > 0, "a chance encounter up the street")
	if eid > 0:
		var c: Dictionary = d.calls[eid]
		t.check(c.state == Dispatcher.CallState.HIDDEN and not d.active_calls().has(c), "nobody's been told: %s" % c.text)
		var sus: Suspect = d.suspects[c.suspects[0]]
		o.global_position = sus.global_position + Vector3(0, 0, 4)
		for i in 20:
			await get_tree().physics_frame
		t.check(c.state == Dispatcher.CallState.ACTIVE, "walk up to it and it's yours")
	s.queue_free()
	await get_tree().process_frame
