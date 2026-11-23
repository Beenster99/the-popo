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
	s.dispatch.stories.enabled = false
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


func test_indoor_jobs() -> void:
	var s := await _city()
	var d := s.dispatch
	var K := Dispatcher.Kind
	var said: Array = []
	d.radio.connect(func(x): said.append(x))
	for k in [K.BURGLARY, K.RAID, K.HOSTAGE, K.SEARCH]:
		var id := d.start_call(k)
		t.check(id > 0, "%s: %s" % [Dispatcher.KIND_NAMES[k], d.calls[id].text if id > 0 else "-"])
		if id <= 0:
			continue
		var c: Dictionary = d.calls[id]
		var inside := 0
		for sid in c.suspects:
			var sus: Suspect = d.suspects[sid]
			if Sfx.zone_at(get_tree(), sus.global_position + Vector3(0, 1.0, 0)) != null:
				inside += 1
		t.check(inside == c.suspects.size(), "  everyone is inside (%d of %d)" % [inside, c.suspects.size()])
		if k == K.HOSTAGE:
			var hs: Array = d.missions.people[id].hostages
			t.check(hs.size() >= 2 and hs.all(func(h): return h.state == Suspect.S.SURRENDER), "  hostages held, kneeling")
			var o: Officer = s.sync.my_pawn()
			o.global_position = (hs[0] as Suspect).global_position + Vector3(0.8, 0, 0)
			await get_tree().physics_frame
			t.check(o.cuff_target() == null, "  an officer can't cuff a hostage")
			o.global_position = s._spawn_point(0)
		if k == K.RAID:
			# Clear the ground floor: dispatch says so.
			var floors: Dictionary = c.floors
			t.check(floors.size() >= 1, "  suspects spread over %d floor(s)" % floors.size())
			if floors.size() >= 2:
				for sid in floors[floors.keys()[0]]:
					(d.suspects[sid] as Suspect).set_state(Suspect.S.DOWN)
				for i in 3:
					await get_tree().physics_frame
				t.check(said.any(func(x): return String(x).contains("clear. Keep going")), "  a floor is called clear")
	# Hostages walk free once the takers are dealt with.
	var hc: Array = d.calls.values().filter(func(c): return c.kind == K.HOSTAGE)
	if not hc.is_empty():
		var hostages: Array = d.missions.people[hc[0].id].hostages
		for sid in hc[0].suspects:
			(d.suspects[sid] as Suspect).set_state(Suspect.S.BOOKED)
		for i in 10:
			await get_tree().physics_frame
		t.check(said.any(func(x): return String(x).contains("hostages out safe")), "hostages out safe")
		t.check((hostages[0] as Suspect).state == Suspect.S.WANDER, "and they walk away")
	s.queue_free()
	await get_tree().process_frame


func test_story_chains() -> void:
	var s := await _city()
	var d := s.dispatch
	var st := d.stories
	var said: Array = []
	d.radio.connect(func(x): said.append(x))
	t.check(Stories.CHAINS.size() >= 3, "%d story chains" % Stories.CHAINS.size())
	# The Vipers, part one: Dex Moran is dealing on the corner.
	var id := st.start_chain(0)
	t.check(id > 0, "the Vipers' first job: %s" % (d.calls[id].text if id > 0 else "-"))
	if id <= 0:
		s.queue_free()
		return
	var c: Dictionary = d.calls[id]
	var dex: Suspect = d.suspects[c.character]
	t.check(c.story == "vipers" and dex.get_meta("story_name") == "Dex Moran" and dex.look == 41, "Dex Moran, with his own face")
	# He gets away: the job comes round again and he's ready for us.
	c.state = Dispatcher.CallState.LOST
	for i in 3:
		await get_tree().physics_frame
	t.check(st.progress.vipers.escapes == 1 and st.progress.vipers.step == 0, "he got away: the story waits for him")
	var id2 := st.start_chain(0)
	t.check(id2 > 0, "and he turns up again")
	if id2 > 0:
		var dex2: Suspect = d.suspects[d.calls[id2].character]
		t.check(dex2.look == 41 and dex2.armed and dex2.fighter, "same face, armed this time")
		t.check(said.any(func(x): return String(x).begins_with("DEX MORAN:")), "and he lets us know he remembers")
		# Caught: the story moves on.
		dex2.set_state(Suspect.S.BOOKED)
		d.calls[id2].state = Dispatcher.CallState.CLOSED
		for i in 3:
			await get_tree().physics_frame
		t.check(st.progress.vipers.step == 1 and st.progress.vipers.escapes == 0, "booked: on to the next part (step %d)" % st.progress.vipers.step)
	s.queue_free()
	await get_tree().process_frame


func test_arrests_pay_and_big_busts() -> void:
	var s := await _city()
	var d := s.dispatch
	var K := Dispatcher.Kind
	var o: Officer = s.sync.my_pawn()
	# "Police! Get down!": a shoplifter gives up on the spot.
	var id := d.start_call(K.SHOPLIFT)
	t.check(id > 0, "a shoplifter")
	if id > 0:
		var sh: Suspect = d.suspects[d.calls[id].suspects[0]]
		o.global_position = sh.global_position + Vector3(0, 0, 3)
		await get_tree().physics_frame
		o.shout()
		await get_tree().physics_frame
		t.check(sh.state == Suspect.S.SURRENDER, "shout at a shoplifter: hands up (%s)" % Suspect.S.keys()[sh.state])
		# Pay: book them and close the job.
		var before := d.pay
		d.book(sh)
		for i in 3:
			await get_tree().physics_frame
		print("    pay %d -> %d" % [before, d.pay])
		t.check(d.pay == before + Dispatcher.PAY_SUSPECT + Dispatcher.PAY_JOB[K.SHOPLIFT], "paid for the arrest and the job (£%d)" % d.pay)
	# A drunk takes some talking down.
	var id2 := d.start_call(K.DRUNK)
	if id2 > 0:
		var dr: Suspect = d.suspects[d.calls[id2].suspects[0]]
		o.global_position = dr.global_position + Vector3(0, 0, 2.5)
		await get_tree().physics_frame
		o.shout()
		o.shout_t = 0.0
		o.shout()
		await get_tree().physics_frame
		t.check(dr.state == Suspect.S.SURRENDER, "the drunk is talked down (%s)" % Suspect.S.keys()[dr.state])
	o.global_position = s._spawn_point(0)
	# Gang war: two crews shoot it out.
	var gid := d.start_call(K.GANGWAR)
	t.check(gid > 0, "gang war: %s" % (d.calls[gid].text if gid > 0 else "-"))
	if gid > 0:
		var gang: Array = d.calls[gid].suspects.map(func(x): return d.suspects[x])
		t.check(gang.size() == 6 and gang.all(func(g): return g.state == Suspect.S.BRAWL and g.armed), "six armed, squared up")
		o.global_position = (gang[0] as Suspect).global_position + Vector3(150, 0, 0)
		for i in 60 * 8:
			await get_tree().physics_frame
		var hurt := gang.filter(func(g): return g.hp < Suspect.MAX_HP or g.is_done()).size()
		print("    after 8 s: %d of 6 hit" % hurt)
		t.check(hurt >= 1, "they're hitting each other (%d hurt)" % hurt)
	# Bank job: robbers inside with staff, a driver at the kerb.
	o.global_position = s._spawn_point(0)
	var bid := d.start_call(K.BANK)
	t.check(bid > 0, "bank job: %s" % (d.calls[bid].text if bid > 0 else "-"))
	if bid > 0:
		var e: Dictionary = d.missions.people[bid]
		t.check(e.hostages.size() == 2, "staff held")
		t.check(e.has("getaway"), "a getaway car waiting")
		if e.has("getaway"):
			var drv: Suspect = e.getaway.s
			var robber: Suspect = d.suspects[d.calls[bid].suspects[0]]
			robber.set_state(Suspect.S.SHOOT)
			for i in 10:
				await get_tree().physics_frame
			t.check(drv.state == Suspect.S.DRIVE, "shooting starts: the driver's away (%s)" % Suspect.S.keys()[drv.state])
	s.queue_free()
	await get_tree().process_frame
