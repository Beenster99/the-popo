extends Node
## Wave 4, Phase 4.1: repair crews clear the rubble and build it back.
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


func test_crews_clear_rubble_and_rebuild() -> void:
	var s := await _city()
	var w := s.world
	var r := s.repairs
	var b0: Dictionary = {}
	for b in s.gen.buildings:
		if b.type != "station":
			b0 = b
			break
	var at: Vector3 = (b0.origin as Vector3) + Vector3(1.0, 1.0, 0.0)
	w.explode(at, 3.5, 400.0, 6.0)
	for i in 240:
		await get_tree().physics_frame
	var lost: Array = w.pieces.values().filter(func(p): return p.state != "intact").map(func(p): return p.id)
	var rubble: int = w.bodies.size()
	t.check(lost.size() > 3, "a hole blown in a building: %d pieces down, %d bits of rubble" % [lost.size(), rubble])
	# Skip the wait for the council.
	for id in r._broken:
		r._broken[id] = RepairCrews.WAIT
	r._tick = 0.0
	for i in 5:
		await get_tree().physics_frame
	t.check(r.sites.size() >= 1, "a repair site opened (%d)" % r.sites.size())
	var site: Dictionary = r.sites.values()[0] if not r.sites.is_empty() else {}
	var crew: Array = site.get("crew", [])
	t.check(crew.size() >= RepairCrews.CREW.x, "a crew turned up: %d workers" % crew.size())
	t.check(crew.all(func(c): return (c as Suspect).look >= SuspectLook.WORKER and (c as Suspect).part == "worker"), "in hi-vis")
	t.check(r._cones.size() == r.sites.size(), "cones out round the site")
	# Let them work, quickly.
	var cleared_at := -1
	for i in 60 * 120:
		for st in r.sites.values():
			st.t = minf(st.t, 0.0)
		if cleared_at < 0 and site.get("stage", "") == "build":
			cleared_at = i
			t.check(w.rubble_near(site.at, RepairCrews.SITE_REACH).is_empty(), "rubble carted away before building starts")
		if r.sites.is_empty():
			break
		await get_tree().physics_frame
	var still: Array = lost.filter(func(id): return w.pieces[id].state != "intact")
	print("    cleared at frame %d; %d of %d pieces still down; sites %d" % [cleared_at, still.size(), lost.size(), r.sites.size()])
	t.check(cleared_at >= 0, "the clean-up finished")
	t.check(still.is_empty(), "everything that came down is built back (%d left)" % still.size())
	t.check(r.sites.is_empty() and r._cones.is_empty(), "the crew packed up and the cones are gone")
	var nodes_ok: bool = lost.all(func(id): return is_instance_valid(w.pieces[id].node) and w.pieces[id].node.is_inside_tree())
	t.check(nodes_ok, "restored pieces are back in the world")
	# And they stand: nothing falls again over a few seconds.
	for i in 180:
		await get_tree().physics_frame
	var again: int = lost.filter(func(id): return w.pieces[id].state != "intact").size()
	t.check(again == 0, "the rebuilt wall stays up (%d fell again)" % again)
	s.queue_free()
	await get_tree().process_frame


func test_hurt_crew_stops_work() -> void:
	var s := await _city()
	var r := s.repairs
	var w := s.world
	var b0: Dictionary = s.gen.buildings[3]
	w.explode((b0.origin as Vector3) + Vector3(1.0, 1.0, 0.0), 3.5, 400.0, 6.0)
	for i in 120:
		await get_tree().physics_frame
	for id in r._broken:
		r._broken[id] = RepairCrews.WAIT
	r._tick = 0.0
	for i in 5:
		await get_tree().physics_frame
	var site: Dictionary = r.sites.values()[0]
	var w0: Suspect = site.crew[0]
	w0.set_state(Suspect.S.COWER)
	w0._calm_t = 5.0
	var n0: int = r.carted
	for i in 60:
		site.t = 0.0
		await get_tree().physics_frame
	t.check(site.paused, "a frightened worker: the job stops")
	t.check(r.carted == n0, "nothing carted off while they're hiding")
	for c in site.crew:
		(c as Suspect).set_state(Suspect.S.DOWN)
	site.crew_t = 0.0
	for i in 3:
		await get_tree().physics_frame
	var fresh: int = (site.crew as Array).filter(func(c): return is_instance_valid(c) and (c as Suspect).state == Suspect.S.WANDER).size()
	t.check(fresh >= RepairCrews.CREW.x, "crew all down: a fresh crew sent (%d)" % fresh)
	s.queue_free()
	await get_tree().process_frame


func test_crews_clean_up_blood() -> void:
	# beenster (2026-11-24): blood stays until it is cleaned.
	Settings.values["gore"] = 3
	var s := await _city()
	var r := s.repairs
	var at: Vector3 = s.gen.pavement_near((s.gen.buildings[3].origin as Vector3))
	for k in 6:
		Gore.splat(s, at + Vector3(k * 0.5, 0.0, 0.0), Vector3.UP, 0.8, false, Gore.TEX_SPECKLE)
	var blood := get_tree().get_nodes_in_group("blood").size()
	t.check(blood >= 6, "blood on the pavement: %d" % blood)
	for i in 60:
		await get_tree().physics_frame
	t.check(get_tree().get_nodes_in_group("blood").size() == blood, "and it stays there")
	for d in get_tree().get_nodes_in_group("blood"):
		d.set_meta("t", Time.get_ticks_msec() - int(RepairCrews.BLOOD_WAIT * 1000.0) - 1)
	r._tick = 0.0
	for i in 5:
		await get_tree().physics_frame
	t.check(r.sites.size() >= 1, "a crew is sent for it")
	for i in 60 * 60:
		if r.sites.is_empty():
			break
		await get_tree().physics_frame
	t.check(get_tree().get_nodes_in_group("blood").filter(func(d): return not d.is_queued_for_deletion()).is_empty(), "the crew scrubbed it all away")
	t.check(r.scrubbed >= 1, "a mark at a time (%d scrubbed)" % r.scrubbed)
	t.check(r.sites.is_empty(), "and packed up")
	s.queue_free()
	await get_tree().process_frame
